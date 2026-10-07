---
phase: 01-timing-core-calibration
plan: 02
subsystem: timing-core
tags: [godot, gdscript, audio-clock, input-judge, settings, export, walking-skeleton]
requires:
  - phase: 01-01
    provides: Godot project scaffold, tools/run_tests.ps1, FakeTime
provides:
  - ClockModel (disciplined monotonic clock, song_time_at tick mapping)
  - JudgeConfig (all windows, hull/score and clock tunables)
  - ChartData and tap-only InputJudge (per-lane queues, judged/stray signals)
  - AudioSynth click track, TestCharts.click_chart
  - Settings autoload (user://settings.cfg, validated)
  - Conductor node (pre-roll to audio-clock handoff, cached latency)
  - scenes/skeleton.tscn (LaneInput, Highway, clock spike readout) as main scene
  - Windows debug export (export_presets.cfg, tools/export.ps1)
affects: [01-03, 01-04, 01-05, 01-06, 01-07]
tech-stack:
  added: []
  patterns: [pure RefCounted logic with injected ticks, Conductor wraps ClockModel, _input judging via ticks-to-song-time, _draw highway as pure function of song_time]
key-files:
  created:
    - src/core/clock_model.gd
    - src/core/conductor.gd
    - src/core/judge_config.gd
    - src/core/chart_data.gd
    - src/core/input_judge.gd
    - src/audio/audio_synth.gd
    - src/content/test_charts.gd
    - src/autoload/settings.gd
    - src/input/lane_input.gd
    - src/ui/highway.gd
    - src/ui/note_shape.gd
    - src/ui/skeleton_root.gd
    - scenes/skeleton.tscn
    - export_presets.cfg
    - tools/export.ps1
    - tests/test_clock_model.gd
    - tests/test_input_judge.gd
    - tests/test_settings_roundtrip.gd
    - tests/test_boot_smoke.gd
  modified:
    - project.godot
    - .planning/phases/01-timing-core-calibration/SKELETON.md
key-decisions:
  - "Settings reads file text and uses ConfigFile.parse (not ConfigFile.load) so no loader call touches user files"
  - "Conductor process_priority -1000 so song_time is fresh for the root tick and redraw"
  - "Audio play() is scheduled at song_time -(time_to_next_mix + cached latency) - audio_offset so the audible start lands at song_time 0"
  - "Judge comparisons carry a 1e-9 epsilon so exact-boundary presses (1.035, 1.070) land in the inner bucket despite float error"
requirements-completed: []
duration: ~40min
completed: 2026-10-07
status: awaiting-checkpoint
---

# Phase 1 Plan 02: Walking Skeleton Summary

End-to-end timing slice: generated click track plays through a Conductor-disciplined audio clock, notes scroll down a 4-lane `_draw()` highway, D/F/J/K are judged PERFECT/GOOD/MISS in `_input` against `song_time_at(ticks)`, offsets persist through `user://settings.cfg`, and a Windows debug export builds and launches. Tasks 1-4 are complete and committed; Task 5 (human play test on the dev PC and a second PC) is PENDING.

## Status

**Tasks 1-4 complete. Task 5 (checkpoint:human-verify, D-31 second-PC gate) is pending and has NOT been performed.** The requirements TIME-01, TIME-02, TIME-03 are not marked complete until that checkpoint is approved, because real-audio sync and feel cannot be proven headless (README, research Pitfall 7).

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 (RED) | Failing tests for ClockModel and tap InputJudge | 3de5808 |
| 1 (GREEN) | ClockModel, JudgeConfig, ChartData, InputJudge | 510fd76 |
| 2 | AudioSynth, TestCharts, Settings autoload, Conductor, settings tests | c788e37 |
| 3 | Skeleton scene, LaneInput, Highway, NoteShape, boot smoke test, input map | 38946b3 |
| 4 | Export preset + script (482b024), SKELETON.md refresh (587d013) | 482b024, 587d013 |
| 5 | Human play test and second-PC export run | PENDING (checkpoint) |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 26 test cases, 0 failures (smoke, clock model, input judge, settings roundtrip, boot smoke).
- Judge boundaries covered: 1.035 PERFECT, 1.0351 GOOD, 1.070 GOOD, 0.930 GOOD, 0.900 MISS on the note, 0.899 stray, tick(1.0701) MISS.
- `powershell -NoProfile -File tools/export.ps1` exits 0; `build/undertow-debug.exe` (+ .pck, console wrapper) produced and launched headless for 180 frames with no errors (only a benign ObjectDB leak warning at exit).
- Greps: `get_output_latency` appears once in conductor.gd (inside `_refresh_latency_if_due`); no `+= delta`; no polling input calls in lane_input.gd; no loader calls in settings.gd; input_judge.gd contains no window literals.
- Input map verified by script: lane_1..lane_4 resolve to physical keys D, F, J, K.

## Deviations from Plan

**1. [Rule 1 - Bug] Corrupt-file test input was not actually corrupt**
- Found during: Task 2. `ConfigFile` tolerates arbitrary garbage (returns OK), so the first corrupt-file test never exercised the backup path.
- Fix: test now writes a genuinely unparsable file (`audio_offset=` with no value, unterminated array) and asserts the `.bak` rename and defaults.
- Files: tests/test_settings_roundtrip.gd. Commit: c788e37.

**2. [Rule 2 - Acceptance] Settings uses `ConfigFile.parse` on file text instead of `ConfigFile.load`**
- The plan acceptance greps for `load(` in settings.gd must be 0; reading text and parsing satisfies that and keeps the T-02-02 posture (no loader on user files). Commit: c788e37.

**3. [Rule 3 - Blocking] Global class cache refresh**
- New `class_name` scripts are invisible to the test runner until `godot --headless --import` regenerates the cache. Ran import before tests. No code change. (tools/run_tests.ps1 only imports when `.godot` is missing; later plans adding class_names should run `--import` first.)

**4. Minor additions beyond the file list:** `src/ui/note_shape.gd` (NoteShape helper required by the plan text) and `src/ui/skeleton_root.gd` (the "small root script"), plus `default_clear_color` black in project.godot and `.uid` files for new scripts.

## Known Stubs

None that block the plan goal. Intentional placeholders within scope: the Highway ignores `duration` (sustains are plan 03) and the F3 overlay is the always-on spike readout in the skeleton (plan 06 replaces it).

## Threat Flags

None. T-02-01 and T-02-02 mitigations are implemented and tested (clamp, type-check, corrupt-file backup, no loader on user:// files). T-02-03 is accepted (unsigned exe; README SmartScreen note still to be documented).

## Issues Encountered

- A multi-file bash heredoc failed to parse once; files were then written individually. No impact on the repo.
- `git` warns about LF/CRLF on every commit; harmless.

## Pending: Task 5 human checkpoint

See the checkpoint message returned with this plan. Results (dev PC feel, second PC launch, clock smoothness answer to research Open Question 1, any SNAP_S/SLEW tuning) are to be recorded here when the human replies.

## Self-Check: PASSED

All created files exist and commits 3de5808, 510fd76, c788e37, 38946b3, 482b024, 587d013 verified in git log.
