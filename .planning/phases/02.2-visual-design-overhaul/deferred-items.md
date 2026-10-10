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

## Found in 02.2-14

- **Scenario b "bot hit intended offsets (max |actual - intended| < 2 ms)" fails with one outlier
  of 2.5..5 ms per run (p50 0.05 ms).** It fails the same way at the pre-plan-14 commit 27b88e9
  (reproduced in a clean worktree on 2026-10-10, max 3.2 ms), on both the primary (240 Hz) and the
  secondary (180 Hz) monitor, so it is environmental (bot spin-wait / OS scheduling), not the HUD.
  All judgment checks in b pass. Fix candidate: judge the bot on p99 instead of the single max, or
  allow one outlier.

## Found in 02.2-17

- **Scenario songs "nothing bright in the outer 32 px (max channel <= 0.35)" fails at a random
  edge point (midlist and/or reduce_motion shot).** It fails the same way at the pre-plan-17 commit
  050b19d (reproduced in a clean checkout on 2026-10-10 under xvfb: 0.420 at (524, 2)), so it comes
  from the Song Select backdrop decoration, not the detail panel. RESEARCH Pitfall 9 already lists
  `_check_outer_band` as a check to replace (clean-edge rule retired). Plan 19 moves Song Select to
  the `table` AbyssBackdrop; replace the check there with the keep-out style check.
  **Resolved in 02.2-19:** `_check_outer_band` was replaced by "no bright decoration over the list
  text" (row title vs row background >= 4.5:1; 12.6..12.7 under xvfb), and Song Select now uses the
  table AbyssBackdrop.
- **Scenario songs "bundled gameplay frame rate >= 60 fps"** reads about 18 fps under xvfb software
  GL (same at 050b19d). Environment only; re-check on the Windows PC.

## Found in 02.2-20

- **Scenario d "song_time continues from paused position (+-20 ms)" fails under xvfb + Dummy
  audio (22..121 ms).** It fails the same way at the pre-plan-20 commit 1cb3c77 (clean worktree on
  2026-10-10 under xvfb: 101.9 ms and 93.4 ms in two runs), so it comes from the cloud container
  (software GL at ~20 fps, Dummy audio driver), not the pause restyle. The timing core is unchanged
  (TIMING GATE OK). Re-check on the Windows PC with WASAPI.
- **Scenario immersion "lens mask edge is smooth" samples the 1.0 s frame**, which under xvfb
  (~20 fps) can land in the BLACK stage (1.10..1.25 s), so the check can pass on a black frame. Not
  a failure; on the PC the frame lands in the lens stage as intended.

## Found in 02.2-21

- **Scenario a: the calibration measurement depends on the wizard's frame cost.** Taps are stamped
  in `_input` when Godot processes the event (once per frame), and the harness injects its taps
  inside a frame, so the stamp lands after the rest of that frame is rendered. Under xvfb software
  GL the measured offset was 51.3 ms at the pre-plan commit edcba01, 74.3 ms with the table
  AbyssBackdrop behind the restyled wizard, 53.2 ms with no backdrop, and 58..60 ms in the final
  build (the backdrop is hidden while the audio test runs). The remaining ~7 ms is the richer stage
  (NotePainter gem, ping ring, glass panels) rasterised by llvmpipe. On a real GPU these costs are
  well under 1 ms. Re-run scenario a on the Windows PC and compare with the 02.2-07 figure
  (49..52 ms). Possible follow-up for a later phase: stamp taps with the OS event time instead of
  the processing time.
- **Scenario i "resumes from the same place (+-20 ms)" is flaky under xvfb + Dummy audio.** It
  passed once and failed once (88.3 ms) at the pre-plan commit edcba01 in a clean worktree, and
  failed at 109.8 ms after this plan. Same cause as the scenario d resume check from 02.2-20
  (Dummy audio driver). Re-check on the PC with WASAPI.

## Found in 02.2-22

- **Scenario visual "bio colonies brighter on the beat than off it" fails under xvfb with no
  on-beat sample ("on": n 0).** It fails the same way at the pre-plan commit 91f53e3 (clean worktree
  on 2026-10-10 under xvfb, two runs: on n 0 both times). The check needs `beat_pulse() > 0.8` both
  before and after a screenshot; at ~20 fps with a slow `get_image()` the frame drawn is always past
  the beat window. Environment only (software GL); re-check on the Windows PC.
- **polish "screen transition finishes within 400 ms" is measured from the Enter press**, so under
  xvfb (~20 fps) it includes about one frame of input delay and one frame of finish detection on top
  of the 300 ms wipe: 349 ms in the final run, 422 ms in one earlier run before the load
  compensation. The wipe itself (started -> finished) was 314 ms. On the PC (60-240 Hz) the
  frame terms are 4-17 ms; re-run polish there to confirm.

## Found in 02.2-23

- **Song Select list navigation is silent.** The list moves its selection while its root Control keeps
  focus, so `UiSounds` sees no focus change. A follow-up can call `UiSounds.play("move")` from
  song_select.gd when the selection changes (outside plan 23's files).
- **Mouse clicks on buttons do not blip.** Only ui_accept plays confirm. UI-SPEC 9 lists a confirm
  blip on "Pressed", which a mouse click would also need. Possible follow-up.
- **Blips are untested by ear.** The Dummy audio driver in the cloud is silent. On the Windows PC,
  check that the blips are soft next to the menu music, that they follow the SFX volume, and that
  none are heard during a dive or the calibration pings.
- **Scenario a gave one 68.87 ms run** among 58.46 / 59.97 ms runs (the known 58-60 ms cloud value).
  This is xvfb frame-cost noise; the run 1 path did not change in this plan.

## Found in 02.2-24

- **Scenario perf under xvfb cannot produce a gate result.** Under Mesa llvmpipe (software GL) the frame
  times are about 50 ms. Also, the capture window stays at 1600x900 because xvfb has no window manager,
  so the FULLSCREEN request does not resize it. Full p95 was 57.9 ms and Low p95 42.5 ms, logged in
  02.2-PERF.md as not representative. No cut step was applied. The "plan 24 (final)" row needs the
  Windows PC.
- **Scenario visual "judgment popup readable" depends on the song moment of the burst shot.** At
  0.35 s it samples a popup that is crowd-skipped to its fade when a newer judgment lands in a dense
  passage. Running the plan 24 readability steps inside the same dive moved the shot and made the
  check fail. Those steps now run on their own dive. Possible hardening: pick the popup by birth
  time and skip the sample when a newer popup was born within 0.35 s.
