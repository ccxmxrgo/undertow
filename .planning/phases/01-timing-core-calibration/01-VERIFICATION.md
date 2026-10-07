---
phase: 01-timing-core-calibration
verified: 2026-10-07T00:00:00Z
status: human_needed
score: 6/6 roadmap success criteria verified (automated + real-hardware bot evidence); 3 residual hardware checks deferred to human
overrides_applied: 0
gaps: []
human_verification:
  - test: "Run the exported build on a second PC"
    expected: "Boots to the first-launch wizard, plays a song, and calibration yields on-beat hits (D-31)"
    why_human: "Needs another machine"
  - test: "Play with a physical gamepad"
    expected: "LB/LT/RT/RB lanes and Start pause behave like the synthetic-pad run (7/7)"
    why_human: "Only a synthetic pad was tested"
  - test: "Calibrate with a real Bluetooth output, and switch the Windows default output"
    expected: "Bluetooth warning shows; default-output switch causes no crash, readout says 'System default', non-blocking recalibrate note shows"
    why_human: "Needs real devices (documented Godot 4.7.2 limitation on default-endpoint detection)"
---

# Phase 1: Timing Core & Calibration - Verification

**Goal:** A player can play a song solo on a sonar highway where hit timing feels tight and fair on their own machine.
**Status:** human_needed. No gaps. Only optional hardware checks remain.

Note: ROADMAP marks the phase `mode: mvp`, but the goal is not in "As a..., I want..., so that..." form, so I used standard goal-backward verification.

## Success criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Notes locked to music, no drift over 5 min, any frame rate | VERIFIED | `src/core/clock_model.gd` is time-based (`slew_tau_s`, no per-frame delta accumulation). It was fixed in 01-08. The 5-min real-audio drift run gave p99 0.48 ms, max 1.14 ms, trend -0.012 ms/min, 0 snaps. Unit sims at 30/60/144/240 fps. |
| 2 | Perfect/Good/Miss grading with feedback; holds and chords | VERIFIED | `input_judge.gd` judges in `_input` (`lane_input.gd`). The keyboard bot matched 124/124 judgments to the 35/70/100 ms windows. 6 chords judged per lane, 9 sustains gave 95 ticks. Feedback scenario passes. |
| 3 | Autoplay all-Perfect | VERIFIED | `autoplay.gd`. 124/124 PERFECT on hardware; F4 restart works; unit tests cover the 5-min chart at 30/60/144 fps. |
| 4 | Calibration wizard, saved offsets feel on-beat | VERIFIED (objective); feel confirmed by user | Simulated +40 ms player measured +40.65 / +41.42 ms, residual +0.77 ms. Offsets persist. The user approved the human gate and reported the game "feeling smooth". |
| 5 | Rebind, gamepad, scroll/volume, pause/resume | VERIFIED (gamepad synthetic only) | Settings scenario 18/18, gamepad 7/7, pause 24/24, overlay 13/13. |
| 6 | Hull cracks, HUD, zero hull eliminates | VERIFIED | `hull_score.gd`. IMPLOSION at hull 0 and No-Fail both pass on hardware. HUD matched score at all 60 samples. The Gap 1 overlay layout bug is fixed (rects now 1920x1080, asserted). |

## Requirements coverage

All 13 IDs are claimed by at least one PLAN and are marked Complete in REQUIREMENTS.md (traceability table maps all to Phase 1). There are no orphans.

| Req | Plans | Status |
|-----|-------|--------|
| TIME-01/02/03 | 02, 03, 06, 08, 10 | SATISFIED |
| TIME-04/05 | 03, 05, 06, 10 | SATISFIED |
| CAL-01 | 04, 07, 09, 10 | SATISFIED |
| CAL-02/03/04 | 01, 04, 07, 10 | SATISFIED |
| HULL-01/02/04 | 03, 06, 08, 10 | SATISFIED |
| HULL-03 | 05, 10 | SATISFIED |

## Checks run

- Unit tests: `tools/run_tests.ps1` exited 0. 188 test cases, 0 errors, 0 failures, 0 orphans, 25/25 suites. This is more than the 179 recorded in the playtest document, so tests were added after it.
- `OS.execute` in src/ and scenes/: none, as required by 01-09.
- Debt markers (TBD/FIXME/XXX) in scripts, scenes, src and tools: none found.
- Real-hardware evidence in `01-HARDWARE-PLAYTEST.md`: 201/201 checks after gap closure. The 01-07 gaps (overlay layout, "Default" device readout, clock jitter) are closed with before/after numbers.

## Residual items (not blockers)

- Second-PC export run, physical gamepad and real Bluetooth device are untested (see frontmatter).
- A plain Windows default-output switch cannot be detected in Godot 4.7.2. It is documented, and a non-blocking recalibrate note is shown.
- Acoustic latency (speaker to ear) cannot be measured by the bot. The user's subjective "smooth" confirmation covers it on their own machine.

_Verifier: Claude (gsd-verifier)_
