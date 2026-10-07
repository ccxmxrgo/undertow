---
phase: 01-timing-core-calibration
plan: 08
subsystem: ui-overlays-clock
status: complete
gap_closure: true
tags: [godot, gdscript, layout, clock, jitter, gap-closure]
requires:
  - phase: 01-06
    provides: PauseMenu, FailScreen, ResultsScreen, ConfirmDialog, DriftHarness
  - phase: 01-03
    provides: ClockModel
provides:
  - UiLayout.fill_rect (explicit anchors 0..1, offsets 0)
  - Viewport-sized, dimmed, modal pause/fail/results/confirm overlays
  - Time-constant ClockModel smoothing (slew_tau_s, JudgeConfig.clock_slew_tau_s = 0.4 s)
  - DriftHarness.log_path (injectable CSV path)
  - tools/playtest/replay_clock.py (tau tuning on recorded capture)
affects: [01-09, 01-10]
key-files:
  created:
    - src/ui/ui_layout.gd
    - tests/test_overlay_layout.gd
    - tests/test_clock_jitter.gd
    - tools/playtest/replay_clock.py
  modified:
    - src/ui/pause_menu.gd
    - src/ui/fail_screen.gd
    - src/ui/results_screen.gd
    - src/ui/confirm_dialog.gd
    - src/core/clock_model.gd
    - src/core/judge_config.gd
    - src/ui/drift_harness.gd
    - tests/test_clock_model.gd
    - tests/test_clock_drift.gd
    - tests/test_gameplay_smoke.gd
key-decisions:
  - "clock_slew_tau_s = 0.4 s (see tuning table)"
  - "Overlay roots use explicit anchors/offsets via UiLayout.fill_rect, never set_anchors_preset"
requirements-completed: [TIME-01, TIME-02, HULL-01, HULL-02, HULL-04]
duration: ~1 h
completed: 2026-10-07
---

# Phase 01 Plan 08: Overlay layout, time-based clock slew, drift log isolation Summary

Closes playtest gaps 1, 3 and 4: overlays are now full-viewport and modal, ClockModel smoothing is a time constant (tau 0.4 s) with p99 under 2 ms at 30/60/144/240 fps, and the unit suite no longer overwrites the player's drift log.

## Tasks and commits

| Task | Commit | Result |
|------|--------|--------|
| 1 Overlay layout (gap 1) | 95c9cb7 | UiLayout.fill_rect, 7 layout tests |
| 2 Time-based clock slew (gap 4) | 03004d0 | exp(-dt/tau) filter, jitter tests, replay_clock.py |
| 3 Injectable drift log (gap 3) | c0c3d54 | `log_path`, test uses temp file |

## Task 1 root cause and RED

Confirmed the playtest suspect. Before the fix, PauseMenu measured size (0, 0), `anchors=(0,0,1,1) offsets=(0,0,-1920,-1080)` and its panel root size (0, 0), with no viewport-sized dim and the button column at (0,0) with center (160, 167) instead of (960, 540). `set_anchors_preset(PRESET_FULL_RECT)` with keep_offsets=false computed offsets against the 0x0 rect, so they stayed stale after the parent was laid out. `UiLayout.fill_rect` writes anchors and offsets explicitly. The ordering of setup() vs add_child was not a factor (both orders pass, covered by a test).

Also added `MOUSE_FILTER_STOP` on PauseMenu's `_panel_root` (root stays IGNORE for the countdown label). FailScreen, ResultsScreen and ConfirmDialog roots were already STOP and are now full size. The Settings overlay was already viewport-sized; a regression test guards it. The mouse-block test pushes a click at (5, 5) with a probe Button behind the overlay and asserts it is never pressed (pause, fail, results, confirm).

## Task 2 tau selection

`replay_clock.py --sweep` on the real 240 Hz capture (`build/playtest/drift_probe.csv`), p99 ms of song_time minus fitted audio clock:

| tau (s) | 30 fps | 60 fps | 144 fps | 240 fps |
|---------|--------|--------|---------|---------|
| 0.050 | 3.513 | 2.983 | 2.698 | 2.612 |
| 0.100 | 2.261 | 1.761 | 1.560 | 1.494 |
| 0.150 | 1.671 | 1.264 | 1.105 | 1.054 |
| 0.250 | 1.180 | 0.845 | 0.728 | 0.691 |
| 0.400 | 0.849 | 0.606 | 0.513 | 0.487 |
| 0.500 | 0.734 | 0.522 | 0.442 | 0.421 |
| legacy 0.15/frame | 1.340 | 1.722 | 2.983 | 3.848 |

The legacy row reproduces the playtest figure (3.85 ms at 240 Hz) and shows the frame-rate dependence. On real data 0.15 s would already pass, but the synthetic test (white chunk noise, std 3.2 ms, outliers +-12 ms, +-20% frame jitter) is stricter at 30 fps: p99 was 2.155 ms at tau 0.25, 2.003 at 0.30, and passed at 0.35. Chose **0.4 s** for margin. `replay_clock.py --tau 0.4` exits 0: p99 0.85/0.61/0.51/0.49 ms (max 1.52 ms at 30 fps). Steady bias for a 400 ppm mismatch is below 0.5 ms (test). The 13 ms handoff offset decays below 2 ms inside 1 s at all four rates without snap.

RED: before the model change test_clock_jitter failed with p99 2.44 / 2.39 / 3.14 / 3.65 ms at 30 / 60 / 144 / 240 fps.

## Task 3

`DriftHarness.log_path` defaults to `LOG_PATH` (const kept for playtest_driver.gd). `test_drift_harness_scene_boots_and_logs` sets it to `user://test_drift_log.csv` before add_child, asserts the header, deletes the temp file, and asserts the real log is unchanged. Verified: wrote a marker line to the real `user://drift_log.csv`, ran the full suite twice, marker still present; the player's original file was restored afterwards.

## Deviations from Plan

**1. [Rule 1 - spec inconsistency] Per-frame advance bound is dt + 2 ms, not dt + 1 ms.** With the specified +-12 ms outliers on top of 3.2 ms noise at 30 fps, one frame can move the filter by about 1.55 ms beyond dt even though p99 error stays under 2 ms. The test asserts 2 ms (still catches snaps, which would be 12+ ms). Files: tests/test_clock_jitter.gd. Commit 03004d0.

**2. tau 0.4 s rather than the smallest value passing the real capture (0.15 s)**, because the synthetic 30 fps white-noise case is the binding constraint (see above).

Otherwise the plan was executed as written. The `_init` second argument is renamed `p_tau_s`; `test_zero_tau_follows_target_immediately` was added to cover tau <= 0 (T-08-03).

## Verification

- Full suite: 159 test cases, 0 failures, 0 orphans, exit 0 (run twice).
- `grep -rn "clock_slew\b" src tests tools` returns nothing; no `set_anchors_preset` remains in the four overlay files.

## Known Stubs

None.

## Notes for follow-up

- Real-hardware confirmation (layout scenario, scenarios d/e/i, full drift run) is plan 01-10. With a 0.4 s time constant, watch the audio restart on pause resume in scenarios d and i.
- Untracked `.uid` files in tools/playtest/ and the modified .planning/config.json pre-date this plan and were left alone.

## Self-Check: PASSED

Files verified present: ui_layout.gd, test_overlay_layout.gd, test_clock_jitter.gd, replay_clock.py. Commits 95c9cb7, 03004d0, c0c3d54 exist.
