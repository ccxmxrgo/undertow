---
phase: 05-polish-packaging
plan: 06
subsystem: ui/results, core/frame-watch
tags: [AV-05, D-06, low-effects, results, performance]
requires: [05-04]
provides: [FrameWatch, LowEffectsHint, results slow-frame hint]
affects: [src/ui/gameplay.gd, src/ui/results_screen.gd, src/ui/versus/versus_results_screen.gd]
tech-stack:
  added: []
  patterns: [pure RefCounted counter fed from _process, local-only results flag on a duplicated dict]
key-files:
  created: [src/core/frame_watch.gd, src/ui/low_effects_hint.gd, tests/test_frame_watch.gd, tests/test_low_effects_hint.gd]
  modified: [src/ui/gameplay.gd, src/ui/results_screen.gd, src/ui/versus/versus_results_screen.gd]
decisions:
  - "FrameWatch clamps refresh to 30..144 Hz (non-finite/<=0 -> 60): a steady 120 fps on a 240 Hz panel is not 'late'"
  - "After the press the hint button leaves the focus loop (FOCUS_NONE) and focus moves to the last existing button, so focus never sits on a disabled control"
  - "The hint button is not part of VersusResultsScreen.focus_buttons() / online_state().buttons, so existing online semantics and tests are unchanged"
  - "frame_watch is recreated at the top of Gameplay.start() (next to _began = false) so an early audio-error return cannot carry the previous run's counts"
metrics:
  duration: ~45 min
  completed: 2026-10-21
---

# Phase 5 Plan 06: Slow-frame hint with one-press Low effects Summary

A pure FrameWatch counts frames whose delta exceeds 1.5 x the display refresh interval (refresh clamped to 30..144 Hz) after the first 2 s of song time and never while paused. If more than 3% of at least 600 counted frames were late and Low effects is off, the solo, offline versus and online results screens offer "Turn on Low effects". The flag stays on this PC and is never sent over the network.

## What was built

- **src/core/frame_watch.gd** (`FrameWatch`): WARMUP_SEC 2.0, LATE_FACTOR 1.5, HINT_RATIO 0.03 (strictly greater), MIN_FRAMES 600, MIN_HZ 30, MAX_HZ 144. API: `sample(dt, song_t, paused)`, `counted_frames()`, `late_frames()`, `late_ratio()`, `late_threshold()`, `should_hint(low_effects_on)`, `reset()`. Non-finite or negative dt and non-finite song_t are ignored. It has no Node, Settings or DisplayServer access, and it only counts. It is never used as a clock.
- **src/ui/low_effects_hint.gd** (`LowEffectsHint`): the copy (TEXT, DONE_TEXT, BUTTON_TEXT, DONE_BUTTON_TEXT) and layout (BUTTON_RECT (1368,752,400,64), LINE_RIGHT 1768, LINE_BASELINE 872). It provides:
  - `wanted(data)`: true only for a real bool `true` while Low effects is off.
  - `enable_low_effects()`: sets the flag, then calls `Settings.save_to(Settings.save_path)`, then emits `settings_changed` once.
  - `set_line()`: re-aligns the line on the right.
  - `link_loop()` and `add_button()`: shared button and focus-loop wiring.
- **Gameplay:** `frame_watch` is created in `start()` from `DisplayServer.screen_get_refresh_rate()` (headless returns -1, which becomes 60 Hz). `_process(delta)` feeds it right after the `_launch_lost` return, before the online branch, so online dives are counted too. `_finish` sets `run_info.slow_frames`, and `_finish_versus` sets `data.slow_frames`. `_show_online_results` duplicates the data and sets its own value on the copy, so a value injected by the host is overwritten (T-05-16). `_host_results` still sends the original dict without the key. dive_audio is untouched.
- **ResultsScreen / VersusResultsScreen:** `low_effects_button` and `slow_hint_label` stay null unless the hint is wanted.
  - **Line:** Body font, TEXT_MID, right-aligned to x 1768 on baseline 872.
  - **Button:** "default" variant at the 4th slot, appended to the end of the closed wrap loop.
  - **Initial focus and Esc / B are unchanged:** Retry Dive / Rematch / Back to Lobby / Leave Lobby.
  - **On press:** Low effects turns on and is saved. The button reads "Low effects on" and is disabled. The line reads "Low effects is on. Change it in Settings > Display.". The loop closes over the original buttons again and focus moves to the last original button.

## Commits

| Hash | Message |
|------|---------|
| b1be816 | test(05-06): failing FrameWatch and LowEffectsHint tests |
| f3aabf6 | feat(05-06): FrameWatch late-frame counter and LowEffectsHint helper |
| d4978c0 | test(05-06): failing results-hint tests |
| 01eb949 | feat(05-06): slow-frame hint on results with one-press Low effects |

## Tests

- test_frame_watch: 8/8. test_low_effects_hint: 12/12, covering:
  - the helper
  - the solo, versus offline, and online host and client screens
  - the gameplay end-to-end slow run and smooth run
  - the online host path: `host_send_results` receives no `slow_frames` and the local screen shows the hint
  - a client that ignores a host-injected flag and leaves its input dict unmutated
- Regression suites, all green:

  | Suite | Tests |
  |-------|-------|
  | test_gameplay_smoke | 13 |
  | test_versus_results | 14 |
  | test_online_results | 14 |
  | test_gamepad_menus | 17 |
  | test_review_fixes | 15 |
  | test_overlay_layout | 32 |
  | test_effect_settings | 14 |
  | test_color_literals | 7 |
  | test_versus_gameplay | 12 |
  | test_online_gameplay | 18 |
  | test_dive_audio | 18 |
  | test_match_determinism | 4 |
  | test_match_sim_determinism | 2 |
  | test_versus_controller_determinism | 5 |
  | test_net_session_match | 29 |

- `git grep slow_frames src/net` is empty. tools/check_timing_gate.ps1 printed TIMING GATE OK.

## Deviations from Plan

- **[Rule 1 - Bug]** The plan created `frame_watch` next to dive_audio in `start()`. It is now created at the top of `start()` instead. Otherwise, a run that returns early with an audio error would keep the previous run's counts.
- **[Rule 2]** After the press, the disabled hint button is taken out of the focus loop (FOCUS_NONE) and the original loop is re-linked. Without this, Left/Right could land on the disabled control.
- The shared button and loop wiring lives in `LowEffectsHint.add_button` / `link_loop` / `set_line`, so both screens use one implementation. That file is in this plan's files_modified.

## Known Stubs

None.

## Self-Check: PASSED
