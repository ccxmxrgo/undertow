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
  critical: 0
  warning: 0
  info: 6
  total: 6
status: clean
---

# Phase 01: Code Review Report (re-review after fixes)

**Reviewed:** 2026-10-07
**Depth:** standard
**Files Reviewed:** 39 (re-review focused on the fix diff plus the surrounding code it touches)
**Status:** clean (no Critical or Warning findings remain; Info items only)

## Summary

I traced each previous Critical and Warning finding through the fix diff and the current source. I found no new defects at Critical or Warning level. Nothing was run, as instructed, so the timing fixes are verified by reading only.

Verification of the earlier findings:

- **CR-01 fixed.** `resume()` clamps `_start_pos` to >= 0 and sets `_deferred_start` when the paused position was negative. It recomputes `_play_at` for the pre-roll. `_process` skips the countdown-lead `_start_audio()` while `_deferred_start` is set. When the countdown ends it sets `_preroll = true`, and the existing pre-roll branch then fires `play(0)` at `song_time >= _play_at`. `_audio_valid` compares against the clamped `_start_pos`. `pause()` and `stop()` clear the flag. The `lead_ticks` and `_play_at` sign conventions agree with each other. The case of pausing again during the deferred countdown re-enters `resume()` and recomputes everything.
- **WR-01 fixed.** For `err < -snap_s`, `predicted = _song_time + dt * 0.5`, so the monotonic clamp no longer freezes the clock. The error shrinks at 0.5 s/s, so it converges. The new test covers it.
- **WR-02 fixed.** `Conductor.audio_offset()` is used at all four sites (`_start`, `resume`, the lead calculation and the target calculation). The wizard sets `offset_override = pending_audio` only for the visual step and resets it to NAN in `show_step`, so the audio step still uses `Settings.audio_offset` and `remove_applied_offset` stays consistent. The wizard owns its own Conductor, so the override does not leak into gameplay.
- **WR-03 fixed.** `_resolve` closes the earlier hold, emitting its ticks up to `min(head, tail)` and `sustain_end`, before the new hold starts. `completed` is true only when the new head is at or past the old tail minus the forgive window.
- **WR-04 fixed.** Key and axis sources are tracked separately. `_set_source` calls `_press`, which is guarded by the union `_held`, and releases only when neither source is held. `_release_all` clears both sources.
- **WR-05 (a) fixed.** All four directions plus `focus_next` and `focus_previous` stay inside the dialog. Part (b), the missing Restart highlight, is still unexplained (see IN-05).
- **WR-06 fixed.** Buttons are disabled until the fade finishes, and Retry then takes focus. `_fail_tween` is killed in `_teardown` before the `_run_root == null` early return.
- **WR-07 fixed.** Stale artifacts are removed, and the check now also requires exit code 0. `Remove-Item -ErrorAction SilentlyContinue` is safe under `$ErrorActionPreference = "Stop"`.
- **WR-08 fixed.** The save goes to `path.tmp`, then `rename_absolute`. Failures call `push_warning` and the temp file is removed. See IN-04 for the residual window.
- **WR-09 fixed.** A grep finds no `PRESET_FULL_RECT` left in `src/`. The only remaining `set_anchors_preset` is `PRESET_CENTER` on a label in `gameplay.gd:221`, which is a different case. `fill_rect` is safe to call before `add_child`.

## Info

### IN-01: F4 autoplay restart is not gated on a debug build (carried forward)

**File:** `src/ui/gameplay.gd:163-165`
**Issue:** F3 (`DebugOverlay`) checks `OS.is_debug_build()`, but F4 restarts the run with autoplay in any build. The results screen flags "AUTOPLAY USED", so scores are not misrepresented. It still contradicts the "debug only" intent of D-28.
**Fix:** Add `and OS.is_debug_build()`, or document the behaviour as intentional.

### IN-02: Line continuations are flattened into tab runs (carried forward)

**File:** `src/core/conductor.gd:171,182`, `src/ui/gameplay.gd:159`, `src/ui/calibration_wizard.gd:389`
**Issue:** Expressions such as `... get_time_since_last_mix() 			- _latency_cache - audio_offset()` are single lines with embedded tab runs. They parse correctly but read like lost continuations. The timing formula at `conductor.gd:171` is easy to misread.
**Fix:** Reformat with a parenthesised multi-line expression.

### IN-03: Focus is grabbed through several redundant paths per dialog (carried forward)

**File:** `src/ui/confirm_dialog.gd:81-82`, `src/ui/pause_menu.gd:177`, `src/ui/settings_screen.gd:298`
**Issue:** `setup()`, `_ready()` and the callers each call `grab_focus`. This hides real focus-ordering bugs.
**Fix:** Keep a single deferred call inside `ConfirmDialog` and delete the caller copies.

### IN-04: Settings persistence has residual gaps (carried forward and extended)

**File:** `src/autoload/settings.gd:79-99,133-146` and the callers
**Issue:**
- On Windows, Godot's `rename_absolute` removes an existing target before renaming. The save is therefore not truly atomic. A crash between the remove and the rename leaves only `settings.cfg.tmp`, and `load_from` ignores it, so the player is reset to defaults.
- `set_scroll_speed` and `set_volume` still write the file on every slider step.
- Callers still ignore the returned error code. The central `push_warning` is the only signal, and the UI shows the change as applied.
- `ConfigFile.parse` still accepts `Object(...)` literals from a user-editable file. Safety rests on every consumed value being type-checked.
**Fix:** In `load_from`, fall back to `path + ".tmp"` when the main file is missing. Debounce saves to slider release or screen close. Optionally pre-scan the text for `Object(`.

### IN-05: Restart dialog's missing focus highlight is still unexplained (carried forward from WR-05b)

**File:** `src/ui/confirm_dialog.gd:66-85`
**Issue:** The fix makes the keyboard focus modal, but the earlier screenshot symptom (no visible highlight on "Keep Playing") is not explained by the code. One possibility is Godot hiding focus rings after a mouse-originated interaction. Another is that the screenshot was taken before the next draw. This needs a runtime check. The new test asserts `has_focus()` but not visibility of the style.
**Fix:** Verify in a real window with the keyboard. If the ring is hidden after a mouse click, consider a custom pressed or hover style, or an explicit focus style on the dialog buttons.

### IN-06: Fail screen still accepts a fresh Space or Enter press immediately after fade-in

**File:** `src/ui/fail_screen.gd:70-73`
**Issue:** The buttons are now inert while invisible, which fixes the original bug. Retry takes focus the instant the fade finishes (about 0.7 s after the hull breaks). A player still mashing Space, which is also `ui_accept`, can trigger Retry on the first press after that. This is a UX risk, not a correctness bug.
**Fix:** Optionally add a short grace period (for example 0.25 s) between enabling the buttons and `grab_focus`, or ignore `ui_accept` presses for that interval.

---

_Reviewed: 2026-10-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
