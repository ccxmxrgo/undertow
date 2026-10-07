# Phase 1 Hardware Playtest (automated) - plan 01-07 task 3, re-run in plan 01-10

**Date:** 2026-10-07 (original run, plan 01-07); gap closure re-run 2026-10-07 (plan 01-10, after plans 01-08 and 01-09)
**Run by:** automated harness `tools/playtest/` (windowed, real WASAPI audio and real GL renderer, NOT headless)
**Verdict (01-10 re-run):** All six playtest gaps are closed on the same PC: Bug 1, Bug 3 and Findings 4-6 are CLOSED, and Bug 2 is CLOSED with documented limitation. Unit suite 179/179 and all 11 windowed scenarios pass (201/201 checks). The 5-minute drift run now meets the strict ±2 ms D-30 figure: p99 0.48 ms, max 1.14 ms, trend -0.012 ms/min. Still needed from a human: second-PC export, subjective feel, physical gamepad, a real Bluetooth device and by-eye drift (see "NOT VERIFIED").

**Original verdict (01-07):** NOT APPROVED as-is. All functional flows passed. Two real defects needed gap work: a layout bug on every in-run overlay, and Output device = "Default". Clock jitter missed the strict ±2 ms D-30 figure, with no drift. Second-PC run and subjective feel still needed a human.

## Environment

| Item | Value |
|------|-------|
| OS | Windows 10.0.26300 (Windows 11 Pro) |
| Engine | Godot 4.7.2-stable (official), debug, `gl_compatibility` / opengl3 |
| GPU / display | AMD Radeon RX 6600 XT, 240 Hz, vsync on (mean frame 4.17 ms) |
| Audio | WASAPI, 48 kHz, configured buffer 15 ms, `get_output_latency()` = 10.0 ms, mix chunk = 10.67 ms (512 frames) |
| Output device reported | `Default` (Windows endpoints present include Razer BlackShark V2 Pro 2.4, Realtek, AMD HDMI, Elgato virtual) |
| Joypads | none connected (pad scenario uses synthetic joypad events) |

## Method and limits

- `godot --path . res://tools/playtest/playtest.tscn -- <scenario>` adds a persistent driver under the root and drives the shipped scenes only through `Input.parse_input_event` (keys, joypad buttons, trigger axes). Menus are driven with arrow keys, Enter and Esc. Shortcuts: `grab_focus()` is called directly only to reach far-down Settings sliders and the wizard's Retry/Accept buttons. No game code was changed.
- Settings were isolated: `Settings.save_path` was redirected to `user://playtest_settings.cfg`, which is deleted after each run. The real `user://settings.cfg` did not exist before the run and is still absent; every scenario checks this.
- Bot timing: in gameplay, input dispatch is synchronous because LaneInput disables accumulated input. The bot spin-waits inside the frame until `Conductor.song_time_at(now)` reaches the target. Measured press error vs intended was mean 0.027 ms, max 0.062 ms (n=119). The calibration wizard leaves accumulated input on, so synthetic taps there flush one frame later (±1.3 ms bot jitter). This is a harness artifact: real OS input is flushed in the same pump.
- **What the bot cannot measure:** the acoustic path (speaker to ear) and the true input path (keyboard USB to message pump). These scenarios check the clock, judge, UI and flow on real hardware. They do not check how timing feels. That still needs a human or a loopback microphone.
- Re-run all: `powershell -NoProfile -File tools/playtest/run_all.ps1` (since 01-10 it backs up and restores the real `user://settings.cfg` and `user://drift_log.csv`) (add `-SkipDrift` to skip the 5-minute drift run). Offline clock analysis: `python tools/playtest/analyze_probe.py build/playtest/drift_probe.csv`.
- Evidence: `build/playtest/<scenario>.json` (every check with detail, metrics, env), PNG screenshots, `c_probe.csv` and `drift_probe.csv` (one row per frame). `build/` is gitignored.

## Gap closure re-run (plans 01-08, 01-09, 01-10)

Same PC, same session conditions as the original run (240 Hz, WASAPI 48 kHz, latency 10 ms, output = Windows default alias). Fixes under test: `UiLayout.fill_rect` on every overlay (01-08), time-constant `ClockModel` smoothing with `clock_slew_tau_s = 0.4` s (01-08), injectable drift log path (01-08), `AudioDeviceInfo` snapshot and signature, "System default" readout, recalibration note, "Previously saved" caption, 280-480 px wizard buttons (01-09).

**Harness changes (01-10), so that the assertions would have caught the original defects:**
- Scenario a compares the saved `output_device_name` and `output_device_signature` with `Settings.device_info.snapshot()` instead of `AudioServer.output_device`. It also asserts the "Output device: System default" readout, the recalibration note, the "Previously saved" caption on the re-run (within 5 ms of the new result) and the button widths.
- The layout scenario now asserts that PauseMenu, FailScreen, ResultsScreen and three ConfirmDialogs (restart, back to menu, Reset Controls) each have a global rect equal to the viewport, a dim ColorRect of alpha >= 0.7 covering the viewport, and that a synthetic click at (5, 5) does not reach a probe Button behind the overlay. Before 01-10 the layout scenario only recorded rects as evidence.
- The drift scenario's D-30 reference is now the smooth (fitted) audio clock, the same method as `analyze_probe.py`. The old check compared against the instantaneous audio target, which itself steps in 10.67 ms mix chunks (std 3.1 ms, max 17 ms), so it could never meet ±2 ms. That figure is still recorded as `probe.song_minus_audio_target_ms`. The ±2 ms threshold is unchanged, and checks were added for per-window p99, drift trend and ppm. Scenario c records the same jitter as a metric.
- `run_all.ps1` backs up the real `user://settings.cfg` and `user://drift_log.csv` before a run and restores them afterwards. Every scenario still asserts that the real settings.cfg is untouched.

### Before / After

| Gap | Measure | Before (01-07 run) | After (01-10 run) | Evidence |
|-----|---------|--------------------|-------------------|----------|
| Bug 1 | PauseMenu global rect | (0,0) size **0x0** | (0,0) size **1920x1080**, panel root 1920x1080 | `layout.json` |
| Bug 1 | FailScreen global rect | (0,0) size **0x0** | **1920x1080** | `layout.json`, `layout_04_implosion.png` |
| Bug 1 | ResultsScreen / ConfirmDialog global rect | 0x0 (seen in screenshots) | **1920x1080** each (restart, menu, Reset Controls confirm) | `layout.json`, `layout_02/03/05/06_*.png` |
| Bug 1 | Dim layer over viewport | missing (highway at full brightness) | alpha **0.70** (pause, fail, confirms), **0.85** (results) | `layout.json` |
| Bug 1 | Click at (5, 5) behind overlay | not blocked (0x0 STOP rect) | **blocked** on all 6 overlays | `layout.json` |
| Bug 2 | Wizard readout | "Output device: **Default**" | "Output device: **System default**" + "Switched headphones or speakers? Calibrate Sonar again." | `a.json`, `a_01_wizard_intro.png` |
| Bug 2 | Device-change detection | name compare "Default" == "Default" (never fires) | signature = sorted device list + mix rate + latency bucket + endpoint count (`...\|48000\|10\|8`); saved signature == live snapshot; plug/unplug, mix-rate and latency changes are detected (unit tests). A plain Windows default-output switch is **not** detectable (Godot 4.7.2 limitation, accepted) | `a.json`, `tests/test_audio_device_info.gd` |
| Bug 3 | Real `user://drift_log.csv` after `run_tests.ps1` | **overwritten** to the header line | marker line **survives** the full suite (179/179) | 01-10 Task 1 run |
| Finding 4 | Re-run wording | checklist said "near 0", wizard shows absolute | re-run shows **+41 MS** with caption "**Previously saved: +41 MS**" (new result 41.42 ms, residual vs applied +0.77 ms) | `a.json`, `a_06_wizard_rerun_previously_saved.png` |
| Finding 5 | song_time - smooth audio clock, scenario c (20 s, 240 Hz) | std 1.84 / p99 **3.85** / max 4.51 ms | std **0.19** / p99 **0.46** / max **0.95** ms | `c.json` (`jitter`), `c_probe.csv` |
| Finding 5 | song_time - smooth audio clock, drift run j (5 min, 240 Hz) | std 1.87 / p99 **3.84** / max **4.58** ms | std **0.20** / p99 **0.48** / max **1.14** ms | `drift.json`, `drift_probe.csv` (before: `drift_before.json`, `drift_probe_before.csv`) |
| Finding 5 | Per 60 s window p99 (drift run) | 3.86 / 3.76 / 3.84 / 3.84 / 3.88 ms | 0.52 / 0.48 / 0.50 / 0.45 / 0.43 ms (max 1.14 / 0.69 / 0.66 / 0.62 / 0.55 ms) | `analyze_probe.py` output |
| Finding 5 | Drift trend (`drift_log.csv`, t >= 1 s) | **+0.04 ms/min**, spread 9.92-16.99 ms | **-0.012 ms/min**, spread 8.23-9.68 ms | `drift_log_copy.csv` |
| Finding 5 | Audio clock vs system clock | 0.38 ppm | -0.32 ppm | `drift.json` |
| Finding 5 | Pause resume landing (scenario d / i) | +3.67 ms / +3.57 ms | **+0.86 ms** / **+4.14 ms** (one 4.17 ms frame); post-resume song - audio target max 6.5 ms (was 8.3) | `d.json`, `i.json` |
| Finding 6 | Wizard button widths | Begin/Skip/Accept/Retry **1760 px** (full VBox) | Begin 320, Skip 280, Accept 320, Retry 320, Save 320 px | `a.json` (`button_widths_*`) |

`clock_slew_tau_s` stays at **0.4 s**. The real-device p99 (0.48 ms) is well inside 2.0 ms, so no retuning was needed.

### Gap status

| Gap | Status | Evidence |
|-----|--------|----------|
| Bug 1 - overlays 0x0, top-left, no dim, not modal | **CLOSED** | `layout.json` (39/39 checks), `layout_01_pause_menu.png`, `layout_02_restart_confirm.png`, `layout_03_menu_confirm.png`, `layout_04_implosion.png`, `layout_05_results.png`, `layout_06_reset_controls_confirm.png` |
| Bug 2 - output device "Default" | **CLOSED with documented limitation** | `a.json` (readout "System default", signature saved == live snapshot, recalibration note shown). The readout is fixed and plug/unplug, mix-rate and latency-bucket changes are detected. A plain Windows default-output switch (for example speakers to headset, both already plugged in) is **not** detected, because Godot 4.7.2 exposes only the "Default" alias and no API resolves it to an endpoint. The recalibration note covers this case. The Bluetooth warning cannot fire automatically under the alias (advisory only). |
| Bug 3 - unit suite clobbers `user://drift_log.csv` | **CLOSED** | marker line survived `run_tests.ps1` (179/179, 0 orphans) |
| Finding 4 - re-run "near 0" vs absolute display | **CLOSED** | "Previously saved: +41 MS" next to the +41 MS result; checklist step 1 corrected below |
| Finding 5 - frame-rate dependent clock jitter | **CLOSED** | drift run p99 0.48 ms, max 1.14 ms (D-30 strict ±2 ms met on every frame), trend -0.012 ms/min |
| Finding 6 - wizard buttons full window width | **CLOSED** | widths 280-320 px, `a_01_wizard_intro.png` |

### Re-run results (01-10)

| # | Scenario | Result |
|---|----------|--------|
| - | Unit suite `tools/run_tests.ps1` | PASS 179/179, 0 orphans; real `drift_log.csv` marker survived |
| a | First launch, wizard, readout, re-run | PASS 40/40. Run 1 measured +40.65 ms, run 2 +41.42 ms, residual +0.77 ms. |
| b | Keyboard bot, mixed offsets | PASS 14/14 (124/124 judgments match windows) |
| c | F3 overlay + clock smoothness | PASS 9/9. Jitter metric above. |
| d | Pause / countdown / resume / confirms | PASS 24/24. Countdown 1.801 s, resume +0.86 ms. |
| e | IMPLOSION, No-Fail | PASS 12/12 |
| f | Gamepad (synthetic) | PASS 7/7 |
| g | Settings rebind, scroll, volumes, reset | PASS 18/18 |
| h | Autoplay + F4 | PASS 15/15 |
| i | Settings overlay from pause | PASS 13/13, resume +4.14 ms |
| layout | Overlay size, dim, mouse block (asserted) | PASS 39/39 |
| j (drift) | 5 min real audio | PASS 10/10: p99 0.477, max 1.143 ms, monotonic, 0 snaps, trend -0.012 ms/min, -0.32 ppm |
| k | Exported build boots | PASS. Re-exported with `tools/export.ps1`. Stdout has only the engine and OpenGL banner lines. Boots into the first-launch wizard showing "Output device: System default" (`k_01_export_boot_desktop.png`, `k_export_stdout.txt`). **Found and fixed during the re-export:** the pck had grown to 29.6 MB because it packed 79 playtest evidence files from `build/playtest` (JSON including the device list, probe CSVs imported as translations, screenshots). `export_presets.cfg` now excludes `build/*`, and `build/.gdignore` stops imports. The re-exported pck is 181 KB with 0 `build/` files (commit 801f007). |

### NOT VERIFIED (requires a human; updated in 01-10)

| Item | Why |
|------|-----|
| Second-PC export run (step 11, D-31) | Needs another machine. The local export boot passes (re-exported in 01-10). |
| Subjective feel: hits sound and look on-beat after calibration; feedback (flash, text, tick, clunk) clear | Needs a human. The bot proves the clock-to-judge pipeline, not speaker-to-ear latency. |
| True acoustic calibration accuracy | The bot taps relative to the game's own clock model. Real latency needs human taps or a loopback mic. |
| Physical gamepad | No controller connected. Synthetic events only. |
| Real Bluetooth device warning | No Bluetooth device in use. Under the "Default" alias (the common case) the warning cannot fire automatically, so it is advisory only. It fires only when the configured device is a named endpoint whose name matches the markers. "headset" alone no longer counts; it needs "hands-free" or "bluetooth" (D-17 as refined in 01-09). "Razer BlackShark V2 Pro 2.4" must not trigger it. |
| Windows default-output switch | Documented limitation: not detectable in Godot 4.7.2. Human check: switch the output and confirm there is no crash, the readout says "System default", the recalibration note shows, and no automatic prompt appears. A prompt is expected only on plug/unplug or a mix-rate change. |
| "No visible drift between clicks and notes" by eye | Numerically there is none (-0.012 ms/min, p99 jitter 0.48 ms). Not judged visually. |

## Original run results (plan 01-07, before gap closure)

| # | Scenario (checklist step) | Result | Key numbers / evidence |
|---|---------------------------|--------|------------------------|
| a | First launch -> wizard; audio taps; visual slider; readout (1) | PASS 28/28 | No settings -> menu routes to the wizard. Simulated player 40 ms behind the heard click: measured **+40.97 ms**. Re-run with +41 applied: wizard shows **+40.94 ms** (absolute), residual vs applied **-0.03 ms**. Slider: tap ±1 ms; 1 s hold = +51 ms (1 + 5 x 10 ms repeats). Readout: "Output latency: 10 ms / Buffer: 15 ms / Output device: Default". Bluetooth warning hidden. Save and Continue persists offset, done flag and device. Esc = Skip, offset unchanged. `a_01_wizard_intro.png`, `a_02_wizard_audio_result.png`, `a_03_wizard_visual.png`, `a_04_wizard_summary.png` |
| b | Start Dive hand chart, keyboard bot, mixed offsets (2) | PASS 14/14 | 124 notes, offsets cycled over 0, ±5..±60, ±90 ms and skip. **All 124 judgments match the 35/70/100 ms windows using the actual press error.** P79 G30 M15. Five +90 ms presses produced 5 strays. 6 chords judged per lane. 9 sustains gave 95 ticks. HUD hull/combo/depth/multiplier matched the score at all 60 one-second samples. Hull minimum 42%. Results show no flags. `b_01_midsong_hud_notes_feedback.png`, `b_02_results.png` |
| c | F3 overlay + clock smoothness, ~20 s real audio (3) | PASS 9/9 | Overlay hidden by default, F3 shows it, 20 hit errors listed. Over 4792 frames: **song_time monotonic (0 backwards steps)**. Per-frame `dsong - dsys`: mean 0.000, std 0.418, p99 1.33, max 1.77 ms. No snaps. song_time vs smooth audio clock: std 1.84, p99 3.85, max 4.51 ms. `c_01_f3_overlay.png`, `c_probe.csv` |
| d | Esc pause / countdown / resume / confirms (5) | PASS 24/24 (but see Bug 1) | song_time frozen exactly (0.000000 s change over 3 s, 723 frames). Audio stopped. Countdown 3-2-1 in **1.803 s** (expected 1.800 at 100 BPM). Resume lands **+3.67 ms** after the paused position (one 4 ms frame). Audio resumed in place (song - audio target max 8.3 ms, mean 0.14). Restart confirm (score > 0) focuses "Keep Playing". Back to Menu confirm focuses "Stay". Esc = safe. Leave Dive -> menu. `d_01_pause_menu.png`, `d_02_countdown.png`, `d_03_restart_confirm.png`, `d_04_menu_confirm.png` |
| e | Hull 0 -> IMPLOSION; No-Fail (6) | PASS 12/12 (but see Bug 1) | With no input, hull hits 0 at song_time 7.27 s after 13 misses. Audio stops, IMPLOSION shows, focus on Retry Dive. With No-Fail on, Retry keeps playing at hull 0 to the end, and results show **NO-FAIL USED**. `e_01_implosion.png`, `e_02_nofail_hull_zero_still_running.png`, `e_03_nofail_results.png` |
| f | Gamepad LB / LT / RT / RB, Start (7) | PASS 7/7 (synthetic pad) | 25 notes in 1-15 s played with buttons (duplicate downs) and analog trigger ramps (noise 0.45-0.52 while held). Presses and releases per lane were exactly [3,6,9,7] = expected. 25/25 PERFECT, 0 strays. Start pauses. **No physical pad connected**: this proves the event path and hysteresis, not a real controller's driver. `f_01_pad_start_pause.png` |
| g | Settings: rebind, duplicate, Tab, scroll, volumes, reset (8) | PASS 18/18 (but see Bug 1) | Lane 1 rebound to Q (InputMap + cfg = 81). F rejected: "! F is already used for Lane 2. Pick a different key." Tab rejected: "! Tab can't be used. It is reserved for menus." Esc cancels listening. Scroll clamps at 0.5x and reaches 3.0x by holding. Volumes 80/70/85% -> buses -1.94/-3.10/-1.41 dB and persisted. Reset Controls confirm (safe focus) restores D. `g_03_rebind_duplicate_rejected.png`, `g_04_rebind_tab_rejected.png`, `g_05_scroll_3x.png`, `g_06_reset_controls_confirm.png` |
| h | Autoplay Dive from menu; F4 mid-run (9) | PASS 15/15 | Autoplay: **124/124 PERFECT**, max error 0.0, AUTOPLAY badge, results show **AUTOPLAY USED**. F4 at 5 s on a normal run restarts it (song_time -1.19 s) with autoplay on and the badge; 11/11 PERFECT after. `h_01_autoplay_midsong.png`, `h_02_autoplay_results.png`, `h_03_f4_autoplay_restart.png` |
| i | Settings from pause as overlay (10) | PASS 13/13 | Overlay (CanvasLayer) shows over the paused run, Re-run Calibration disabled, song_time frozen. Esc returns to pause with focus on Settings. Resume lands +3.57 ms after the paused position. Score/combo 4150/23 intact. Run keeps scoring after (6700, 0 misses). `i_01_settings_overlay_over_pause.png` |
| j | Drift harness, full 5 min real audio (4) | **No drift: PASS. Strict ±2 ms jitter: FAIL** | 300 s, 72,478 frames, max frame 5.45 ms. **Audio clock vs system clock: 0.38 ppm (0.11 ms over 300 s).** `drift_log.csv` trend **+0.04 ms/min** (first 11.69 ms, last 11.61 ms; constant offset mean 13.19 ms, spread 9.92-16.99 ms). Monotonic, 0 snaps. song_time vs smooth audio clock: **std 1.87, p99 3.84, max 4.58 ms**, flat in all five 60 s windows (max 4.44-4.58). song_time vs instantaneous audio target: p99 7.57, max 15.43 ms (the target itself jitters std 3.19 / max 15.6 ms). See "Drift detail". `drift.json`, `drift_probe.csv`, `drift_01_drift_harness_done.png` |
| k | Exported build boots (11, local half) | PASS | `build/undertow-debug.console.exe` (export 18:12, newer than the last source commit, so not re-exported) ran 12 s. Stdout has only the engine and OpenGL banner lines, no errors or warnings. Still running after 7 s. Boots into the first-launch Calibrate Sonar wizard, which is correct with no settings.cfg. `k_01_export_boot_desktop.png`, `k_export_stdout.txt` |
| - | layout evidence (extra) | FAIL (Bug 1) | Viewport 1920x1080. Gameplay root and `_run_root` are 1920x1080. **PauseMenu and FailScreen global rect = (0,0) size (0,0).** `layout.json`, `layout_01_pause_layout.png` |
| - | Unit suite after harness added | PASS | `tools/run_tests.ps1`: 146/146, 0 orphans |

### Original run: NOT VERIFIED (as listed in 01-07)

| Item | Why |
|------|-----|
| Second-PC export run (step 11, D-31) | Needs another machine. |
| Subjective feel: hits sound and look on-beat after calibration; feedback (flash, text, tick, clunk) clear | Needs a human. The bot proves the clock-to-judge pipeline, not speaker-to-ear latency. |
| True acoustic calibration accuracy | The bot taps relative to the game's own clock model. Real latency needs human taps or a loopback mic. |
| Physical gamepad | No controller connected. Synthetic events only. |
| Bluetooth output warning | No Bluetooth device in use. The name heuristic also cannot fire while the device reads "Default" (Bug 2). |
| "No visible drift between clicks and notes" by eye | Numerically there is none (0.04 ms/min). Not judged visually. |

## Original run drift detail (D-30 / TIME-01, before 01-08)

- **Drift: none.** The audio clock and QueryPerformanceCounter agree to 0.38 ppm. The game's own log trends +0.04 ms/min. TIME-01 ("no visible drift across a full 5-minute song") is met on this PC.
- **Jitter vs D-30's ±2 ms:** song_time differs from the fitted smooth audio clock by std 1.87, p99 3.84 and max 4.58 ms. This is constant across the 5 minutes, so it is jitter, not drift. Cause: Godot's position advances in 10.67 ms mix chunks, and `pos + time_since_last_mix` jitters about ±6 ms (p99) around the true line. `ClockModel` slews 15% of the error **per frame** (`src/core/clock_model.gd:92`, `clock_slew = 0.15`). At 240 fps the time constant is about 28 ms, so song_time follows much of that jitter. At 60 fps it would be about 4x smoother. The filter strength depends on frame rate. The ±2 ms D-30 assertion in the unit suite uses a fake clock and passes there. Against real audio it holds for p50 but not for p99/max. The max (4.6 ms) is far inside the 35 ms PERFECT window, so this is a tuning gap item, not a gameplay blocker.
- **Constant offset:** song_time runs about 13 ms ahead of the system-clock schedule once audio takes over. At t=0 (preroll) the offset is 4.4 ms, and from t=1 s on it is 10-17 ms. That is about one mix chunk, consistent with `get_playback_position()` reporting the end of the last mixed chunk. A constant offset is absorbed by calibration, but it causes a ~10 ms forward slew at every audio (re)start. It is invisible in the 1.2 s lead-in.

## Original run bugs found (status after 01-10 in brackets)

**[CLOSED in 01-08, verified 01-10: all overlays 1920x1080, dimmed, modal; `layout.json`]** **Bug 1 - every in-run overlay and every ConfirmDialog has zero size and renders in the top-left (HIGH, visible to every player).**
- Repro: Start Dive -> Esc (or let the hull hit 0, finish a song, or open Reset Controls in Settings).
- Expected (UI-SPEC): full-screen 70-85% dim with a centered panel; modal dialogs block the screen.
- Actual: PauseMenu, FailScreen, ResultsScreen and ConfirmDialog have global rect size (0,0). Their CenterContainer collapses to its minimum size at (0,0). IMPLOSION and DIVE COMPLETE titles overlap the HUD hull bar. The dim layer is missing, so the highway shows through at full brightness. The confirm dialog covers the pause buttons. Because `MOUSE_FILTER_STOP` covers a 0x0 rect, the "modal" dialogs do not block mouse clicks elsewhere. Evidence: `layout.json` (pause menu and fail screen 0x0 while `_run_root` is 1920x1080), `e_01_implosion.png`, `b_02_results.png`, `d_01_pause_menu.png`, `d_03_restart_confirm.png`, `g_06_reset_controls_confirm.png`.
- Suspect: `set_anchors_preset(Control.PRESET_FULL_RECT)` is called after the node is already in the tree with a 0x0 rect. Godot 4's default `keep_offsets=false` recomputes offsets to keep that zero rect. Lines: `src/ui/pause_menu.gd:39`, `src/ui/fail_screen.gd:20`, `src/ui/results_screen.gd:18`, `src/ui/confirm_dialog.gd:18`. `_run_root` works because its preset is set before `add_child` (`src/ui/gameplay.gd`). Likely fix: `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`. Add a test that asserts `size == viewport size`; the current tests check only text and focus, so they miss this.

**[CLOSED with documented limitation in 01-09, verified 01-10: readout "System default", signature-based detection; plain default-output switch not detectable]** **Bug 2 - Output device is always "Default", so the device-change prompt and the Bluetooth warning cannot fire (MEDIUM, CAL-03/CAL-04).**
- Repro: open the wizard on any PC that uses the Windows default output device (the common case).
- Expected: the readout names the real endpoint (e.g. "Speakers (Razer BlackShark V2 Pro 2.4)"). Switching Windows output to Bluetooth headphones shows the warning and, after calibration, the "Output device changed" prompt.
- Actual: `AudioServer.output_device` returns the alias `Default`. The readout shows "Output device: Default", `Settings.output_device_name` saves "Default", and `device_changed()` compares "Default" to "Default". So a switch of the Windows default device is never detected, and `DeviceHeuristics.is_bluetooth_name("Default")` is always false.
- Suspect: `src/ui/calibration_wizard.gd:127`, `src/autoload/settings.gd:57` and `:64`. Needs a way to resolve the real default endpoint name, or a different change signal (for example, a change in `get_output_latency()` or mix rate, or a platform query). Gap item. Root-cause verification of what Godot 4.7 can expose is still pending.

**[CLOSED in 01-08, verified 01-10: marker survives the suite]** **Bug 3 - the unit suite overwrites the player's real `user://drift_log.csv` (LOW).**
- Repro: run the 5-minute drift harness, then `tools/run_tests.ps1`. The log is reduced to its header line. This happened during this playtest; the 5-minute numbers survive in `build/playtest/drift.json` because the harness had already analysed them.
- Suspect: `tests/test_gameplay_smoke.gd:84-91` instantiates `drift_harness.tscn`, which opens `DriftHarness.LOG_PATH` (`src/ui/drift_harness.gd:7,32`) for writing. Fix idea: an overridable log path (as `Settings.save_path` is) set to a temp file in the test. The harness now also copies the CSV to `build/playtest/drift_log_copy.csv`.

**[CLOSED in 01-09/01-10: "Previously saved" caption, checklist step 1 corrected]** **Finding 4 - checklist and implementation disagree on the calibration re-run (doc, LOW).**
- Plan step 1 says a re-run "should be near 0". The 01-07 decision makes the wizard show the absolute offset, so a correct re-run shows about +40 MS again. The measured residual vs the applied offset is -0.03 ms, which is the actual "near 0" quantity. Either the checklist wording or the wizard copy (e.g. "change from current: +0 MS") should change so a human tester isn't misled.

**[CLOSED in 01-08, verified 01-10: drift-run p99 0.48 ms, max 1.14 ms]** **Finding 5 - clock jitter tuning is frame-rate dependent (LOW, tuning).** See "Drift detail". Per-frame slew makes song_time smoothing depend on fps: p99 3.8 ms, max 4.6 ms at 240 Hz. A time-based slew (e.g. `1 - exp(-dt/tau)`) would make it consistent and could bring p99 within ±2 ms.

**[CLOSED in 01-09, verified 01-10: 280-320 px]** **Finding 6 - calibration wizard buttons stretch the full window width (cosmetic).** `begin_button`, `skip_button`, Accept and Retry fill the 1760 px VBox, unlike the 320-480 px menu buttons (`src/ui/calibration_wizard.gd:99,174`; no `size_flags_horizontal` shrink). See `a_01_wizard_intro.png`.

**Inconclusive:** "2 ObjectDB instances were leaked at exit" appeared on some harness runs (b, c, e, h, i) and not on others. A `--verbose` re-run of c did not reproduce it. Most likely the harness quits while its coroutines are still awaiting timers. Not attributed to the game.

## Checklist mapping (plan 01-07 task 3, corrected in 01-10)

| Step | Status |
|------|--------|
| 1 Wizard on first launch, taps, visual, readout, re-run | PASS. Readout "Output device: System default" plus the recalibration note. A re-run shows the absolute offset again (+41 MS) with the caption "Previously saved: +41 MS". Both values should match within a few ms (measured residual +0.77 ms). |
| 2 Play hand chart: chords, sustains, HUD, hull | PASS (pipeline). Feel NOT VERIFIED |
| 3 F3 graph smooth, hit errors listed | PASS (jitter p99 0.46 ms) |
| 4 5-minute drift harness | PASS: no drift (-0.012 ms/min, -0.32 ppm) and strict ±2 ms jitter met (p99 0.48, max 1.14 ms). By eye NOT VERIFIED |
| 5 Pause / countdown / resume / confirms | PASS. Full-screen dimmed pause menu and confirm dialogs that block the mouse (Bug 1 CLOSED). Resume +0.86 ms. |
| 6 IMPLOSION, No-Fail | PASS. IMPLOSION is centered on a full-screen dim (Bug 1 CLOSED). |
| 7 Gamepad | PASS with synthetic events; physical pad NOT VERIFIED |
| 8 Settings rebind, scroll, volumes, reset | PASS (Reset Controls confirm is full-size and modal) |
| 9 Autoplay + F4 | PASS |
| 10 Settings overlay from pause | PASS |
| 11 Export runs on second PC | Local boot PASS (re-exported, pck 181 KB); second PC NOT VERIFIED |

## Human results

Pending: the plan 01-10 Task 3 checkpoint (human-verify) is awaiting the user's reply.

## Human results

2026-10-07: user approved (feel, gamepad, second PC, output switch). No issues reported.

2026-10-07 (after code-review fixes CR-01, WR-01..09): user playtested on the dev PC and reported it "feeling smooth".
