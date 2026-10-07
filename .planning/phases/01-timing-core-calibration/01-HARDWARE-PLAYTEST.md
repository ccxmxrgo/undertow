# Phase 1 Hardware Playtest (automated) - plan 01-07 task 3

**Date:** 2026-10-07
**Run by:** automated harness `tools/playtest/` (windowed, real WASAPI audio and real GL renderer, NOT headless)
**Verdict:** NOT APPROVED as-is. All functional flows pass. Two real defects need gap work: a layout bug on every in-run overlay and Output device = "Default". Clock jitter misses the strict ±2 ms D-30 figure, with no drift. Second-PC run and subjective feel still need a human.

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
- Re-run all: `powershell -NoProfile -File tools/playtest/run_all.ps1` (add `-SkipDrift` to skip the 5-minute drift run). Offline clock analysis: `python tools/playtest/analyze_probe.py build/playtest/drift_probe.csv`.
- Evidence: `build/playtest/<scenario>.json` (every check with detail, metrics, env), PNG screenshots, `c_probe.csv` and `drift_probe.csv` (one row per frame). `build/` is gitignored.

## Results

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

### NOT VERIFIED (requires a human)

| Item | Why |
|------|-----|
| Second-PC export run (step 11, D-31) | Needs another machine. |
| Subjective feel: hits sound and look on-beat after calibration; feedback (flash, text, tick, clunk) clear | Needs a human. The bot proves the clock-to-judge pipeline, not speaker-to-ear latency. |
| True acoustic calibration accuracy | The bot taps relative to the game's own clock model. Real latency needs human taps or a loopback mic. |
| Physical gamepad | No controller connected. Synthetic events only. |
| Bluetooth output warning | No Bluetooth device in use. The name heuristic also cannot fire while the device reads "Default" (Bug 2). |
| "No visible drift between clicks and notes" by eye | Numerically there is none (0.04 ms/min). Not judged visually. |

## Drift detail (D-30 / TIME-01)

- **Drift: none.** The audio clock and QueryPerformanceCounter agree to 0.38 ppm. The game's own log trends +0.04 ms/min. TIME-01 ("no visible drift across a full 5-minute song") is met on this PC.
- **Jitter vs D-30's ±2 ms:** song_time differs from the fitted smooth audio clock by std 1.87, p99 3.84 and max 4.58 ms. This is constant across the 5 minutes, so it is jitter, not drift. Cause: Godot's position advances in 10.67 ms mix chunks, and `pos + time_since_last_mix` jitters about ±6 ms (p99) around the true line. `ClockModel` slews 15% of the error **per frame** (`src/core/clock_model.gd:92`, `clock_slew = 0.15`). At 240 fps the time constant is about 28 ms, so song_time follows much of that jitter. At 60 fps it would be about 4x smoother. The filter strength depends on frame rate. The ±2 ms D-30 assertion in the unit suite uses a fake clock and passes there. Against real audio it holds for p50 but not for p99/max. The max (4.6 ms) is far inside the 35 ms PERFECT window, so this is a tuning gap item, not a gameplay blocker.
- **Constant offset:** song_time runs about 13 ms ahead of the system-clock schedule once audio takes over. At t=0 (preroll) the offset is 4.4 ms, and from t=1 s on it is 10-17 ms. That is about one mix chunk, consistent with `get_playback_position()` reporting the end of the last mixed chunk. A constant offset is absorbed by calibration, but it causes a ~10 ms forward slew at every audio (re)start. It is invisible in the 1.2 s lead-in.

## Bugs found (not fixed in this pass)

**Bug 1 - every in-run overlay and every ConfirmDialog has zero size and renders in the top-left (HIGH, visible to every player).**
- Repro: Start Dive -> Esc (or let the hull hit 0, finish a song, or open Reset Controls in Settings).
- Expected (UI-SPEC): full-screen 70-85% dim with a centered panel; modal dialogs block the screen.
- Actual: PauseMenu, FailScreen, ResultsScreen and ConfirmDialog have global rect size (0,0). Their CenterContainer collapses to its minimum size at (0,0). IMPLOSION and DIVE COMPLETE titles overlap the HUD hull bar. The dim layer is missing, so the highway shows through at full brightness. The confirm dialog covers the pause buttons. Because `MOUSE_FILTER_STOP` covers a 0x0 rect, the "modal" dialogs do not block mouse clicks elsewhere. Evidence: `layout.json` (pause menu and fail screen 0x0 while `_run_root` is 1920x1080), `e_01_implosion.png`, `b_02_results.png`, `d_01_pause_menu.png`, `d_03_restart_confirm.png`, `g_06_reset_controls_confirm.png`.
- Suspect: `set_anchors_preset(Control.PRESET_FULL_RECT)` is called after the node is already in the tree with a 0x0 rect. Godot 4's default `keep_offsets=false` recomputes offsets to keep that zero rect. Lines: `src/ui/pause_menu.gd:39`, `src/ui/fail_screen.gd:20`, `src/ui/results_screen.gd:18`, `src/ui/confirm_dialog.gd:18`. `_run_root` works because its preset is set before `add_child` (`src/ui/gameplay.gd`). Likely fix: `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`. Add a test that asserts `size == viewport size`; the current tests check only text and focus, so they miss this.

**Bug 2 - Output device is always "Default", so the device-change prompt and the Bluetooth warning cannot fire (MEDIUM, CAL-03/CAL-04).**
- Repro: open the wizard on any PC that uses the Windows default output device (the common case).
- Expected: the readout names the real endpoint (e.g. "Speakers (Razer BlackShark V2 Pro 2.4)"). Switching Windows output to Bluetooth headphones shows the warning and, after calibration, the "Output device changed" prompt.
- Actual: `AudioServer.output_device` returns the alias `Default`. The readout shows "Output device: Default", `Settings.output_device_name` saves "Default", and `device_changed()` compares "Default" to "Default". So a switch of the Windows default device is never detected, and `DeviceHeuristics.is_bluetooth_name("Default")` is always false.
- Suspect: `src/ui/calibration_wizard.gd:127`, `src/autoload/settings.gd:57` and `:64`. Needs a way to resolve the real default endpoint name, or a different change signal (for example, a change in `get_output_latency()` or mix rate, or a platform query). Gap item. Root-cause verification of what Godot 4.7 can expose is still pending.

**Bug 3 - the unit suite overwrites the player's real `user://drift_log.csv` (LOW).**
- Repro: run the 5-minute drift harness, then `tools/run_tests.ps1`. The log is reduced to its header line. This happened during this playtest; the 5-minute numbers survive in `build/playtest/drift.json` because the harness had already analysed them.
- Suspect: `tests/test_gameplay_smoke.gd:84-91` instantiates `drift_harness.tscn`, which opens `DriftHarness.LOG_PATH` (`src/ui/drift_harness.gd:7,32`) for writing. Fix idea: an overridable log path (as `Settings.save_path` is) set to a temp file in the test. The harness now also copies the CSV to `build/playtest/drift_log_copy.csv`.

**Finding 4 - checklist and implementation disagree on the calibration re-run (doc, LOW).**
- Plan step 1 says a re-run "should be near 0". The 01-07 decision makes the wizard show the absolute offset, so a correct re-run shows about +40 MS again. The measured residual vs the applied offset is -0.03 ms, which is the actual "near 0" quantity. Either the checklist wording or the wizard copy (e.g. "change from current: +0 MS") should change so a human tester isn't misled.

**Finding 5 - clock jitter tuning is frame-rate dependent (LOW, tuning).** See "Drift detail". Per-frame slew makes song_time smoothing depend on fps: p99 3.8 ms, max 4.6 ms at 240 Hz. A time-based slew (e.g. `1 - exp(-dt/tau)`) would make it consistent and could bring p99 within ±2 ms.

**Finding 6 - calibration wizard buttons stretch the full window width (cosmetic).** `begin_button`, `skip_button`, Accept and Retry fill the 1760 px VBox, unlike the 320-480 px menu buttons (`src/ui/calibration_wizard.gd:99,174`; no `size_flags_horizontal` shrink). See `a_01_wizard_intro.png`.

**Inconclusive:** "2 ObjectDB instances were leaked at exit" appeared on some harness runs (b, c, e, h, i) and not on others. A `--verbose` re-run of c did not reproduce it. Most likely the harness quits while its coroutines are still awaiting timers. Not attributed to the game.

## Checklist mapping (plan 01-07 task 3)

| Step | Status |
|------|--------|
| 1 Wizard on first launch, taps, visual, readout, re-run | PASS (Bug 2 for device name, Finding 4 for the "near 0" wording) |
| 2 Play hand chart: chords, sustains, HUD, hull | PASS (pipeline). Feel NOT VERIFIED |
| 3 F3 graph smooth, hit errors listed | PASS |
| 4 5-minute drift harness | No drift: PASS. Strict ±2 ms jitter: FAIL (Finding 5) |
| 5 Pause / countdown / resume / confirms | PASS functionally; FAIL visually (Bug 1) |
| 6 IMPLOSION, No-Fail | PASS functionally; FAIL visually (Bug 1) |
| 7 Gamepad | PASS with synthetic events; physical pad NOT VERIFIED |
| 8 Settings rebind, scroll, volumes, reset | PASS (Reset dialog affected by Bug 1) |
| 9 Autoplay + F4 | PASS |
| 10 Settings overlay from pause | PASS |
| 11 Export runs on second PC | Local boot PASS; second PC NOT VERIFIED |
