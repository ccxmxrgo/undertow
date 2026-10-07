---
phase: 01-timing-core-calibration
plan: 03
subsystem: timing-core
tags: [godot, gdscript, input-judge, hull-score, autoplay, clock-model, pause-resume, drift-simulation]
requires:
  - phase: 01-02
    provides: ClockModel, tap InputJudge, JudgeConfig, ChartData, Conductor, AudioSynth, TestCharts
provides:
  - InputJudge with chords, sustains, release forgiveness, frame-rate independent sustain ticks
  - HullScore (hull, combo, perfect streak, multiplier, score, depth, failed/no_fail)
  - Autoplay chart player (exact note times)
  - TestCharts.hand_chart and five_minute_click_chart, AudioSynth.make_song
  - ClockModel state machine (IDLE/PREROLL/PLAYING/PAUSED) and Conductor pause()/resume(beats)
affects: [01-04, 01-05, 01-06, 01-07]
tech-stack:
  added: []
  patterns: [signals from pure RefCounted logic, schedule-driven sim loops (autoplay.update then judge.tick), one shared audio start path]
key-files:
  created:
    - src/core/hull_score.gd
    - src/core/autoplay.gd
    - tests/test_sustain_chord.gd
    - tests/test_hull_score.gd
    - tests/test_autoplay.gd
    - tests/test_input_mapping.gd
    - tests/test_pause_resume.gd
    - tests/test_clock_drift.gd
  modified:
    - src/core/input_judge.gd
    - src/core/judge_config.gd
    - src/core/clock_model.gd
    - src/core/conductor.gd
    - src/audio/audio_synth.gd
    - src/content/test_charts.gd
key-decisions:
  - "Sustain ticks are scheduled at head + n*interval and emitted up to min(t, tail) on tick() or release(), so the count is identical at any frame rate"
  - "Score for a hit uses the multiplier before that hit raises the combo (hit 11 is the first at x2)"
  - "Hull floors at 0 always; failed fires once; under no_fail, no_fail_used is set when hull reaches 0"
  - "Added JudgeConfig.score_per_meter (100) so hull_score.gd holds no numeric literals for depth"
  - "Resume: song_time frozen during the countdown, ClockModel continues from the exact paused position; audio restarts via play(paused_position) launched early by mix delay + latency + audio_offset"
requirements-completed: [TIME-04, TIME-05, HULL-01, HULL-02, HULL-04]
duration: ~45min
completed: 2026-10-07
status: complete
---

# Phase 1 Plan 03: Full Judge, Hull/Score, Autoplay, Pause/Resume, Drift Simulation Summary

Complete headless logic layer: chords and sustains judged per D-09..D-11, hull/score rules, autoplay scoring all-Perfect on the hand chart and 5-minute click chart at 30/60/144 fps plus jitter, pause/resume clock logic, and a 5-minute drift simulation within 2 ms.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Full InputJudge: chords, sustains, release forgiveness, sustain ticks | 75598de |
| 2 | HullScore, Autoplay, hand/5-minute charts, make_song | c4bf55f |
| 3 | ClockModel state machine, Conductor pause/resume, drift test | f91023d |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 55 test cases, 0 failures.
- Autoplay: 0 Miss, 0 Good, 0 stray, hull 100, every judged error exactly 0, all sustains completed, on hand_chart and the 600-note 5-minute chart at 30/60/144 fps and a jittered-with-hitch schedule.
- Same physical press times give identical judgments at 30/60/144 fps and jittered 60 fps via `ClockModel.song_time_at` (TIME-02 logic).
- Drift sim (300 s, jittered 60 fps, 100 ms hitches, 0.4 ms/s drift, 1 ms audio-target noise): every note judged Perfect with error < 2 ms, clock never decreases.
- Greps: `get_tree().paused` count 0 in conductor.gd, `_player.stop()` present; hull_score.gd has no `8.0`/`100.0` literals; input_judge.gd uses `sustain_tick_interval`.

## Deviations from Plan

**1. [Rule 3 - Blocking] Class cache refresh**: ran `godot --headless --import` after adding class_name scripts (as noted in 01-02). No code change.

**2. [Rule 2 - Config] Added `JudgeConfig.score_per_meter`** so depth (D-14) has no literal in hull_score.gd; judge_config.gd was not in the plan file list. Commit c4bf55f.

**3. [Rule 1 - Bug in my test] test_hull_score max_perfect_streak expectation** corrected from 2 to 3 (initial streak of 3 is the max). No production change.

**4. Extra optional params**: `hand_chart(rate)` and `five_minute_click_chart(bpm, rate)` accept a sample rate so tests render 8 kHz audio quickly; defaults use the mixer rate.

## Known Stubs

None. Conductor.pause/resume are only verified through the pure ClockModel (headless); real audio restart via `play(paused_position)` is exercised in plan 06 and the plan 01-07 hardware gate.

## Threat Flags

None. T-03-01 (NaN/negative/lane validation) covered by existing ChartData asserts; T-03-02 accepted.

## Notes for downstream plans

- HullScore.connect_judge wires judged/stray/sustain_tick; the UI should also connect `sustain_end`.
- Conductor.tempo_map must be set from the chart before `resume()` so the countdown uses the right BPM (defaults to 120 if empty).
- TIME-01/02/03 real-audio evidence is still deferred to the plan 01-07 hardware gate; requirement ids TIME-01..03 are not marked complete here (simulation evidence only).

## Self-Check: PASSED

Created files and commits 75598de, c4bf55f, f91023d verified present.
