---
phase: 01-timing-core-calibration
reviewed: 2026-10-07T00:00:00Z
depth: standard
files_reviewed: 39
files_reviewed_list:
  - export_presets.cfg
  - project.godot
  - src/audio/audio_synth.gd
  - src/audio/sfx_pool.gd
  - src/autoload/settings.gd
  - src/content/test_charts.gd
  - src/core/audio_device_info.gd
  - src/core/autoplay.gd
  - src/core/calibration_math.gd
  - src/core/chart_data.gd
  - src/core/clock_model.gd
  - src/core/conductor.gd
  - src/core/device_heuristics.gd
  - src/core/hull_score.gd
  - src/core/input_judge.gd
  - src/core/judge_config.gd
  - src/input/binding_store.gd
  - src/input/lane_input.gd
  - src/ui/calibration_wizard.gd
  - src/ui/confirm_dialog.gd
  - src/ui/debug_overlay.gd
  - src/ui/drift_harness.gd
  - src/ui/fail_screen.gd
  - src/ui/feedback.gd
  - src/ui/gameplay.gd
  - src/ui/highway.gd
  - src/ui/hud.gd
  - src/ui/main_menu.gd
  - src/ui/note_shape.gd
  - src/ui/palette.gd
  - src/ui/pause_menu.gd
  - src/ui/rebind_cell.gd
  - src/ui/results_screen.gd
  - src/ui/settings_screen.gd
  - src/ui/skeleton_root.gd
  - src/ui/step_slider.gd
  - src/ui/ui_layout.gd
  - tools/export.ps1
  - tools/run_tests.ps1
findings:
  critical: 1
  warning: 9
  info: 4
  total: 14
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-10-07
**Depth:** standard
**Files Reviewed:** 39 (note_shape.gd was not opened; it only draws shapes)
**Status:** issues_found

## Summary

The timing core (ClockModel, Conductor, InputJudge, CalibrationMath) is mostly sound. The audio offset sign convention is consistent end to end. The `user://settings.cfg` parsing is type-checked and clamped throughout. One real timing bug exists in the pause/resume path when pausing during the lead-in. There are several robustness problems around modal focus, the clock's stall behaviour, and calibration domain mixing.

Focus question (Restart confirm dialog): initial focus is still grabbed after the 01-08 layout change. `ConfirmDialog.setup()` calls `safe_button.grab_focus()` when `is_inside_tree()`. `PauseMenu._show_dialog` adds the dialog to the tree before `setup`, so that branch runs. `PauseMenu` then calls `grab_focus()` again, and `_ready()` has a third call. `UiLayout.fill_rect` only sets anchors and offsets and cannot affect focus. `tests/test_pause_overlay.gd:90` asserts `safe_button.has_focus()`. So the missing highlight in the screenshot is not a lost grab. See WR-05 for what the code can and cannot explain. I could not run the game to confirm the visual cause.

## Critical Issues

### CR-01: Pausing during the lead-in resumes audio from a negative position and desyncs the clock

**File:** `src/core/conductor.gd:82-95` (also 168-170, 152)
**Issue:** `pause()` during PREROLL freezes `song_time` at a negative value, for example -0.6. `resume()` then sets `_start_pos = clock.paused_position()`, which is negative. `_process` fires `_start_audio()` at `resume_ticks - lead`, calling `_player.play(-0.6)`. Godot clamps or misbehaves on a negative `from_position`, so the stream most likely starts at 0. Song_time at that moment is still about -0.6, so the audio is roughly 0.6 s ahead of the clock. The `_audio_valid` test (`position > _start_pos`) is true immediately, because any position is greater than -0.6. The clock then hits the snap branch in `ClockModel.update` and song_time jumps forward by about 0.6 s. Notes skip and are judged as missed or mis-timed. The same hazard applies to a pause in the first moments before the audio has started. The player can reach this by pressing Esc during the 2-beat lead-in.
**Fix:** In `resume()`, if `_start_pos < 0`, do not start the audio by the countdown. Treat the remainder as pre-roll, schedule the audio so position 0 is heard at song_time 0, and clamp the seek position:
```gdscript
# resume(): after computing _start_pos
var seek_pos := maxf(_start_pos, 0.0)
# _play_at (song_time at which play() must fire) = seek_pos - delay - audio_offset
# when _start_pos < 0, start audio only once clock.song_time() >= _play_at (as in _start),
# and call _player.play(seek_pos), never a negative value.
```
Also change the `_audio_valid` guard to compare against `maxf(_start_pos, 0.0)`.

## Warnings

### WR-01: Monotonic clamp turns "audio is behind" into a clock freeze instead of a slew

**File:** `src/core/clock_model.gd:92-99`
**Issue:** When `|audio_target - predicted| > snap_s` and the target is behind the prediction, `predicted = audio_target`. The line `_song_time = maxf(_song_time, predicted)` then discards that correction. Next frame `predicted = _song_time + dt` is again ahead of the target by more than the snap, so the same branch runs. The result is that `song_time` is frozen until the audio catches up, so notes visibly stop. Typical triggers are audio that started later than scheduled (Bluetooth, wrong `get_output_latency`) or a mix thread stall. A freeze of 50 ms or more also lands inside the judgment window.
**Fix:** When the error is negative and larger than the snap, advance at a reduced rate instead of holding. For example, cap the backward correction by running `dt * 0.5` that frame:
```gdscript
if absf(err) > snap_s:
    predicted = audio_target if err > 0.0 else _song_time + dt * 0.5
```

### WR-02: Visual calibration is measured against the old saved audio offset, not the accepted one

**File:** `src/ui/calibration_wizard.gd:265-286, 392-396` (conductor offset in `src/core/conductor.gd:57,155`)
**Issue:** `Conductor` always applies `Settings.audio_offset`. After "Accept Offset" the wizard stores the new value only in `pending_audio`. Settings is unchanged until Save. The visual step therefore plays the click with the previous audio offset, and the user aligns the flash to that. When the new audio offset is saved, gameplay's audio/visual alignment differs from what was calibrated by `pending_audio - Settings.audio_offset`. The audio step is handled correctly (`remove_applied_offset`); the visual step is not.
**Fix:** Let the Conductor take an explicit offset override, for example `conductor.offset_override: float = NAN`, and set it to `pending_audio` before `_start_loop()` in `_build_visual_step`. Alternatively, apply `pending_audio - Settings.audio_offset` to `vt` in `_draw_stage`.

### WR-03: A new hold can overwrite an active hold without emitting `sustain_end`

**File:** `src/core/input_judge.gd:122-134`
**Issue:** `_resolve` assigns `_holds[lane] = {...}` unconditionally. If a second sustain head in the same lane is judged while an earlier hold is still active, the first hold vanishes silently. `sustain_end` is never emitted. `Highway._holding[lane]` and the note state stay `S_HOLDING` forever. The first hold's remaining ticks are lost. The authored charts avoid overlap, but `ChartData.finalize()` does not validate it. Imported charts (the roadmap's next input) can contain a note starting before the previous tail in the same lane. Autoplay also hits this: its press is not preceded by a release when a note head is earlier than the previous tail.
**Fix:** In `_resolve`, if `_holds[lane] != null`, end it first:
```gdscript
if _holds[lane] != null:
    _emit_ticks(lane, _holds[lane], _holds[lane]["tail"])
    _end_hold(lane, true)
```
Alternatively, validate and trim overlaps in `ChartData.finalize()`.

### WR-04: One `_held` flag is shared by a lane's keyboard key and its trigger axis

**File:** `src/input/lane_input.gd:64-75`
**Issue:** By default lane_2 and lane_3 are mapped to both a key (F, J) and a trigger axis. `_handle_motion` releases the lane whenever `_held[lane]` is true and a motion event for that axis reports `strength <= 0.4`. While the player holds F, any idle-trigger motion event, such as jitter or a light touch, calls `_release(lane)`. This ends a sustain early for a key that is still held. It also lets a later trigger press re-trigger a lane the key already holds. Events from multiple joypads share the same state.
**Fix:** Track the source separately, for example `_held_key[lane]` and `_held_axis[lane]`. Only release when no source remains held. Emit press on the 0 to 1 transition of the union, and release on the 1 to 0 transition.

### WR-05: Modal dialogs leave the screen behind them focusable; the Restart dialog's focus highlight is unexplained

**File:** `src/ui/confirm_dialog.gd:66-69`, `src/ui/pause_menu.gd:170-183`, `src/ui/settings_screen.gd:291-310`
**Issue:** (a) Only `confirm_button.focus_neighbor_right` and `safe_button.focus_neighbor_left` are set. Up and down are unset, so Godot picks the geometrically nearest focusable control in the whole viewport. The pause panel buttons (and the Settings rows or rebind cells) remain visible and focusable behind the dim. Pressing Up or Down on "Keep Playing" can move focus behind the dialog. A following Enter or Space activates a hidden control, for example "Back to Menu" or a rebind cell, while the dialog is still open. The mouse is blocked by `MOUSE_FILTER_STOP`, but the keyboard is not.
(b) On the focus-highlight question, the code path grabs focus on `safe_button` and `Style_focus` exists in the theme (`ui/undertow_theme.tres:84`, 4 px accent border). Nothing in the layout change removes it. Likely causes to verify at runtime:
  - The screenshot may have been taken before the next draw.
  - The focus was moved by (a), or the pointer-hover state was masking it.
  - The Godot 4.7 behaviour of hiding focus rings after a mouse-originated interaction. The Restart button was probably clicked, and I could not verify this.
**Fix:** Make the dialog a real modal. Set all four neighbors on both buttons (for example top and bottom point to themselves, and left and right point to each other, wrapping). Better, add `focus_mode = Control.FOCUS_NONE` to the covered content, or toggle `_panel_root.visible` and `process_mode` while the dialog is open. Call `grab_focus` once, deferred, from `ConfirmDialog` only:
```gdscript
safe_button.focus_neighbor_top = safe_button.get_path_to(safe_button)
safe_button.focus_neighbor_bottom = safe_button.get_path_to(safe_button)
safe_button.focus_neighbor_right = safe_button.get_path_to(confirm_button)
confirm_button.focus_neighbor_left = confirm_button.get_path_to(safe_button)
# ... same for confirm_button top/bottom, then:
safe_button.grab_focus.call_deferred()
```
Add a screenshot or test step that asserts `get_viewport().gui_get_focus_owner() == dialog.safe_button` after one frame.

### WR-06: Fail screen buttons are active while the panel is still invisible

**File:** `src/ui/fail_screen.gd:61-69`, `src/ui/gameplay.gd:183-192`
**Issue:** `play()` sets `modulate.a = 0`, grabs focus on Retry immediately, and fades in after the 0.4 s squash. For about 0.7 s the panel is transparent but fully interactive. Space is both the default `fire` key and `ui_accept`, and the player is still mashing when the hull breaks. A single press retriggers Retry and instantly restarts the dive with no fail screen. The restart also leaves a running tween that targets the freed `highway` and `feedback` nodes.
**Fix:** Keep the buttons disabled until the fade completes:
```gdscript
retry_button.disabled = true; menu_button.disabled = true
tw.tween_callback(func() -> void:
    retry_button.disabled = false; menu_button.disabled = false; retry_button.grab_focus())
```
Also kill the fail tween in `Gameplay._teardown`.

### WR-07: `export.ps1` can report success for a failed export

**File:** `tools/export.ps1:21-27`
**Issue:** Success is judged only by `Test-Path build/undertow-debug.exe`. A stale exe from a previous build satisfies it, so a failed export (missing templates, script error) still prints "Export OK" and exits 0. A friend can then be sent an out-of-date build.
**Fix:** Delete the artifact before exporting, and check the exit code as well:
```powershell
Remove-Item build/undertow-debug.exe, build/undertow-debug.pck -ErrorAction SilentlyContinue
& $godot --headless --path . --export-debug "Windows Desktop" build/undertow-debug.exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path build/undertow-debug.exe)) { ... exit 1 }
```

### WR-08: Settings are saved non-atomically and save failures are ignored

**File:** `src/autoload/settings.gd:121-136` and callers (`save_calibration`, `set_scroll_speed`, `set_volume`, `settings_screen.gd:213,259,305,337`)
**Issue:** `ConfigFile.save(path)` writes in place, so a crash or power loss mid-write leaves a truncated file. The next launch fails `parse`, backs the file up, and resets everything, including the calibration and `calibration_done`. The player is then forced back through the wizard. `save_to` returns an error code that no caller checks. After a failed save (full disk, read-only profile) the UI still shows the change as applied and it is lost on restart.
**Fix:** Write to `path + ".tmp"` and then `DirAccess.rename_absolute` over the target. Check the returned code and `push_warning` on failure.

### WR-09: SettingsScreen builds its layout with `set_anchors_preset(PRESET_FULL_RECT)`, the pattern 01-08 fixed elsewhere

**File:** `src/ui/settings_screen.gd:44,55,58`
**Issue:** `UiLayout.fill_rect` exists because `set_anchors_preset(FULL_RECT)` computes offsets from the node's current 0x0 rect before first layout, and it collapsed the overlays. `PauseMenu`, `ConfirmDialog`, `ResultsScreen` and `FailScreen` were converted. `SettingsScreen` is instantiated as an overlay inside a `CanvasLayer` by the pause menu and still uses the old call on itself, the background and the margin container. It is at risk of the same collapsed-overlay bug when opened over a paused run. The same pattern also remains in `calibration_wizard.gd:61,77,81`, `main_menu.gd:32,52,56` and `hud.gd:39`.
**Fix:** Use `UiLayout.fill_rect(self)`, `UiLayout.fill_rect(bg)` and `UiLayout.fill_rect(margin)`. Run the pause to Settings flow in a real window to confirm.

## Info

### IN-01: F4 autoplay restart is not gated on a debug build

**File:** `src/ui/gameplay.gd:159-161`
**Issue:** F3 (`DebugOverlay`) checks `OS.is_debug_build()`, but F4 (`debug_autoplay`) restarts the run with autoplay in any build. The results screen does flag "AUTOPLAY USED", so scores are not misrepresented, but it contradicts the "debug only" intent of D-28.
**Fix:** Add `and OS.is_debug_build()` to the check, or document that it is intentional.

### IN-02: Line continuations are flattened into tab runs

**File:** `src/core/conductor.gd:155,163`, `src/ui/gameplay.gd:155`, `src/ui/calibration_wizard.gd:386`
**Issue:** Expressions such as `... get_time_since_last_mix() 			- _latency_cache - ...` and `while _cd_emitted < _cd_beats 			and ...` are single lines with embedded tab runs. They parse correctly because tabs are whitespace, but they look like backslash continuations that lost their `\` and newline. They are hard to read and the timing formula in particular is easy to misread. The same tool artifact may exist elsewhere.
**Fix:** Reformat with real line breaks (parenthesised expression) or a `\` continuation.

### IN-03: Focus is grabbed through up to three redundant paths per dialog

**File:** `src/ui/confirm_dialog.gd:68-74`, `src/ui/pause_menu.gd:177`, `src/ui/settings_screen.gd:298`
**Issue:** `setup()`, `_ready()` and the callers all call `grab_focus`. This hides real focus-ordering bugs, because one of the calls will always win.
**Fix:** Keep a single deferred call inside `ConfirmDialog` (see WR-05) and delete the caller copies.

### IN-04: Settings are written on every slider step, and untrusted `Object()` values are instantiated by `ConfigFile.parse`

**File:** `src/autoload/settings.gd:79-99,145-147`
**Issue:** `set_scroll_speed` and `set_volume` write the whole file for every step. A held key repeats 10 times per second. This is not a correctness bug, but combined with WR-08 it widens the window for a corrupted file. Separately, the `_num`, `_bool` and string checks protect every consumed value. `ConfigFile.parse` itself still accepts `Object(...)` and other Variant literals from a user-editable file, and the code relies on never using them rather than rejecting them.
**Fix:** Debounce saves (save on slider release or on screen close; `back_pressed` already saves). Optionally pre-scan the text for `Object(` and treat it as a bad file.

---

_Reviewed: 2026-10-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
