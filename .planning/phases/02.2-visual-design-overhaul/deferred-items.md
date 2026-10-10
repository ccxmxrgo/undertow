# Phase 2.2 deferred items (out of scope for the plan that found them)

## Found in 02.2-01

- **polish scenario: two live-dive capture checks fail on this machine, before any 02.2 change.**
  "captured a pending note inside the Good window" and "lane press observed for the receptor shot"
  fail at the pre-phase commit 6b45995 too (reproduced in a clean worktree on 2026-10-10). They wait for
  a pending note within 0..30 ms of the hit line and a lane press younger than 30 ms. Earlier runs had a
  240 Hz screen; Godot now sees one 59.94 Hz screen (16.7 ms frames), which makes those narrow
  windows hard to catch. Not caused by the results fix. Fix candidates: widen the windows when
  refresh < 100 Hz, or capture with vsync off as `sc_perf` does. All the results / bleed-through
  checks in that scenario pass.

## Found in 02.2-07

- **Scenario a (calibration) measures about +49..52 ms where it expects +40 ms (+-5).** The
  failure is the same at the pre-plan-07 commit 566b88e (reproduced in a clean worktree on
  2026-10-10, 49.17 ms), so it is environmental. It is not menu music: `isolate_settings` turns menu
  music off and stops it. The audio device list now includes a Razer 2.4 GHz headset and Elgato virtual
  devices, so the default output path probably carries about 10 ms of extra latency that the
  harness's "heard click" model does not see. Scenarios c and d pass.
- **test_pause_overlay `test_pause_freezes_song_time_without_scene_tree_pause` flakes in the full
  suite.** It waits 1500 ms, which is exactly the 3-beat lead-in at 120 BPM, then asserts
  song_time > 0 (seen -0.0066). It passes when rerun alone. Fix candidate: wait 1800 ms, or wait
  until song_time > 0 with a timeout.
