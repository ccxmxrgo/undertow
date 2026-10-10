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
