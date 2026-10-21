---
phase: 05-polish-packaging
plan: 01
subsystem: audio
tags: [audio, procedural, sfx, AV-03, AV-04]
requires: []
provides:
  - "AudioSynth.make_sonar_ping / make_creak / make_impact / make_launch / make_implosion"
  - "AudioSynth.sfx_bank() / clear_sfx_cache() once-per-process cache"
  - "AudioSynth.PING_LEAD_SEC, SONAR_PING_DB, CREAK_SEEDS"
affects: [05-04 DiveAudio, 05-05 TorpedoJuice]
tech-stack:
  added: []
  patterns: ["static var cache keyed by mix rate", "LCG-seeded deterministic synthesis", "_encode_peak normalise-and-encode helper"]
key-files:
  created: [tests/test_audio_synth_sfx.gd, tests/test_audio_synth_sfx.gd.uid]
  modified: [src/audio/audio_synth.gd]
decisions:
  - "Downbeat ping is a 700->520 Hz pong (measured ZCR ~600 Hz) so it never reads as the 1.1-1.7 kHz incoming-torpedo ping"
  - "sfx_bank() returns the cached Dictionary itself; callers treat it as read-only"
  - "Impact crack: plan's 'noise at 0.6' read as gain 0.6 on one-pole (coef 0.15) lowpassed noise"
metrics:
  duration: "~25 min"
  completed: 2026-10-21
  tasks: 2
  files: 3
---

# Phase 5 Plan 01: Procedural SFX bank Summary

AudioSynth now renders every Phase 5 sound in code: a downbeat sonar "pong" with 0.15 s of lead silence, four seeded stick-slip hull creaks, a torpedo impact, a launch thump and whoosh, and a near and distant implosion. All of them sit behind a once-per-process `sfx_bank()` cache that builds cold in about 143 ms at 44.1 kHz.

## Contract (05-04 / 05-05 code against this)

| Symbol | Value / shape |
|--------|---------------|
| `AudioSynth.PING_LEAD_SEC` | `0.15` (exact digital zeros, `round(0.15*rate)` samples) |
| `AudioSynth.SONAR_PING_DB` | `-20.0` |
| `AudioSynth.CREAK_SEEDS` | `[11, 23, 37, 51]` (`Array[int]`) |
| `make_sonar_ping(rate := 0)` | AudioStreamWAV |
| `make_creak(seed, rate := 0)` | AudioStreamWAV, same seed gives identical bytes |
| `make_impact(rate := 0)` | AudioStreamWAV |
| `make_launch(rate := 0)` | AudioStreamWAV |
| `make_implosion(distant := false, rate := 0)` | AudioStreamWAV |
| `sfx_bank() -> Dictionary` | keys `sonar_ping`, `creaks` (`Array[AudioStreamWAV]` x4 in CREAK_SEEDS order), `impact`, `launch`, `implosion`, `implosion_distant` |
| `clear_sfx_cache()` | tests only |

`rate <= 0` means `AudioServer.get_mix_rate()`. The bank uses the current mix rate and rebuilds only if that rate changes. All streams are 16-bit mono, non-looping.

## Levels and lengths (measured by tests at 44.1 kHz)

| Stream | Length | Peak |
|--------|--------|------|
| sonar_ping | 0.15 s lead + 0.75 s = 0.90 s | -20 dBFS (0.10) |
| creak x4 | 0.5 to 1.2 s (seeded) | 0.70 |
| impact | 0.60 s | -6 dBFS (0.50), more than 60% RMS below 200 Hz |
| launch | 0.45 s | -9 dBFS (0.355), whoosh peaks around 0.2 s |
| implosion | 1.40 s | -4 dBFS (0.63) |
| implosion_distant | 1.40 s | near x -14 dB (about 0.126), lowpassed at about 600 Hz |

Every stream starts and ends within 0.01 of zero and peaks at or below 0.9.

**Cold `sfx_bank()` build: 143.1 ms at 44100 Hz** (dev PC, headless). A cached call takes under 5 ms (asserted). The budget is 1500 ms (T-05-01).

## Notes for 05-04 (DiveAudio)

- Ping scheduling: to put the onset on downbeat time `T`, start the stream at `T - PING_LEAD_SEC`. If you are already late by `d < PING_LEAD_SEC`, call `play(d)` (seek into the lead). The lead is exact zeros, so seeking within it is click-free.
- Creaks: pick from `sfx_bank()["creaks"]` (4 variants). Pitch and volume variation, if wanted, belong on the player.
- Call `AudioSynth.sfx_bank()` in `_ready` or at gameplay load, never on the first downbeat.

## Notes for 05-05 (TorpedoJuice)

- Use `bank["impact"]` for a landing on your own board, `bank["launch"]` for the shooter, `bank["implosion"]` for your own hull and `bank["implosion_distant"]` for a rival's.
- These are distinct from `VersusSfx.make_ping` and `make_collision`, which are unchanged.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | 3dd7ed7 | test(05-01): failing tests for the sonar ping, creaks and SFX bank |
| 1 GREEN | 3cfb17f | feat(05-01): procedural downbeat sonar ping, seeded hull creaks and cached sfx_bank |
| 2 RED | 633a70a | test(05-01): failing tests for impact, launch and implosion |
| 2 GREEN | b4819a5 | feat(05-01): procedural Phase 5 SFX bank (ping, creaks, impact, launch, implosion) |

## Verification

- `tests/test_audio_synth_sfx.gd`: 13/13 passed.
- `tests/test_ui_sounds.gd`: 15/15 passed (unchanged).
- `tools/check_timing_gate.ps1`: TIMING GATE OK.
- `git diff` against the pre-plan `audio_synth.gd` shows additions only. No existing generator changed.

## TDD Gate Compliance

There is a RED `test(...)` commit before each GREEN `feat(...)` commit (3dd7ed7 then 3cfb17f; 633a70a then b4819a5). Each RED run failed with parse errors because the functions were missing.

## Deviations from Plan

- Task 1 GREEN got its own `feat` commit (3cfb17f). The plan names only the Task 2 feat commit, so this keeps the RED/GREEN gates per task.
- The test `.gd.uid` was generated only after the RED commit. It is committed with this SUMMARY.

Otherwise the plan was executed as written.

## Self-Check: PASSED

- src/audio/audio_synth.gd, tests/test_audio_synth_sfx.gd and tests/test_audio_synth_sfx.gd.uid exist.
- Commits 3dd7ed7, 3cfb17f, 633a70a and b4819a5 are on origin/main.
