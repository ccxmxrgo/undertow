---
phase: 03-offline-versus
plan: 07
subsystem: versus-bots
tags: [sub-rig, bots, match-harness, determinism, training-drone, reward-frequency]
requires: ["03-03", "03-04", "03-06"]
provides:
  - "SubRig: one seat's VersusJudge + VersusHull + PayloadStack wired to MatchSim"
  - "BotProfile tiers (Veteran 33 ms / 1.5%, Regular 42 / 3.5%, Rookie 55 / 7%) with D-19 penalties"
  - "BotPlayer: seeded Gaussian timing on the real chart + D-20 fire policy"
  - "MatchHarness: headless global-time-order match runner (run / instance API)"
  - "TrainingDrone: Solo Dive payload launcher (D-27)"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns: ["exact-time actors (next_time/step) run in global song-time order", "fixed judge-tick grid instead of frame-time ticks"]
key-files:
  created:
    - src/versus/sub_rig.gd
    - src/versus/bot_profile.gd
    - src/versus/bot_player.gd
    - src/versus/match_harness.gd
    - src/versus/training_drone.gd
    - tests/test_sub_rig.gd
    - tests/test_bot_player.gd
    - tests/test_bot_frequency.gd
    - tests/test_match_determinism.gd
    - tests/test_training_drone.gd
    - .planning/phases/03-offline-versus/03-HUMAN-UAT.md
  modified: []
decisions:
  - "MatchHarness never ticks at frame time. A TICK_S = 5 ms grid ticks every rig, and bots, the autoplay human and the drone are actors stepped in global song-time order (ties: grid, human, bots by seat, drone). fps only chunks the song, so logs are identical at 30/144/1000 fps."
  - "Bots sample each base note at note time - 1 s (an exact-time action) and overlay notes when their payload LANDs. A press outside [-early_miss_window, +good_window] is dropped (a miss, never a stray)."
  - "The bot fire plan is driven by METER/REWARD_EARNED events (handles queued duel prizes) and cleared by TORPEDO_LAUNCH/BUFF_APPLIED/COLLISION/IMPLODED. A late FIRE_REFUSED (race) retries next beat."
  - "Debris penalties for bots: SILT uses the ink sigma multiplier, GROAN the pressure multiplier."
  - "PlayerState.accuracy is reported as 0..1 (RunStats.accuracy / 100); max_streak = hull.max_combo."
  - "Spec req 8: reward_threshold_ratio stays 0.12 and Veteran stays 33 ms / 1.5% (best of 8 configs). The strict per-bot test fails on one bot; the user decision is recorded in 03-HUMAN-UAT.md (D-UAT-01)."
metrics:
  duration: "~2 h (including an interruption)"
  completed: 2026-10-15
  tasks: 3
  files: 11
---

# Phase 3 Plan 07: SubRig, bots, MatchHarness and TrainingDrone Summary

Rivals are now real. Each seat (human or bot) plays through the same SubRig, so the same judge, hull, payload stack and MatchSim calls apply to everyone. Seeded Veteran/Regular/Rookie bots play the real chart with Gaussian timing, D-19 payload penalties and the D-20 fire policy. A headless MatchHarness plays whole songs deterministically at any fps, and the Solo Dive TrainingDrone shows that every disruptor is playable under autoplay.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 86a32b9 | test(03-07): add failing tests for SubRig wiring and BotPlayer timing and fire policy |
| 1 GREEN | c9b40d5 | feat(03-07): SubRig seat wiring, BotProfile tiers and seeded BotPlayer |
| 2 RED | 15a4209 | test(03-07): add failing tests for reward frequency and determinism with bots |
| 2 GREEN | fce89ae | feat(03-07): MatchHarness global-order headless match runner (+ 03-HUMAN-UAT.md) |
| 3 RED | 8639a83 | test(03-07): add tests for TrainingDrone schedule and payloads-under-autoplay acceptance |
| 3 GREEN | a29ef98 | feat(03-07): TrainingDrone for Solo Dive and harness training seat |

## Tests

- test_sub_rig 12/12, test_bot_player 12/12, test_match_determinism 4/4, test_training_drone 7/7
- test_bot_frequency 1/2. **The strict spec req 8 test fails on one bot (HRT seat 3 = 5 rewards).** This is intentional: the test was not loosened, per the escalation rule. See below and 03-HUMAN-UAT.md.
- Veteran on 1,000 notes (seed 5): Perfect within 80-92%, Miss <= 4%, 0 strays.
- `tools/check_timing_gate.ps1`: **TIMING GATE OK** (no pinned file touched).
- Full suite not run (parallel-wave rule).

## Reward frequency (spec req 8)

Default config, `reward_threshold_ratio` **0.12** (unchanged), Veteran 33 ms / 1.5% (unchanged), 4 Veteran bots, fps 60, committed seeds:

| song | notes | threshold | rewards per bot |
|------|-------|-----------|-----------------|
| synth_wave_april | 416 | 50 | 3, 3, 3, 4 |
| space_synth_wave | 569 | 69 | 2, 3, 4, 2 |
| sea_shanty_2 | 471 | 57 | 3, 4, 2, 4 |
| hrt | 394 | 48 | 4, 3, 3, **5** |
| invisible | 440 | 53 | 4, 4, 2, 2 |

Escalation sweep (3 seeds x 5 songs x 4 bots = 60 bot-songs per row; MatchSim with the 03-06 rules):

| ratio | Veteran sigma / lapse | outside [2, 4] | mean |
|---|---|---|---|
| **0.120** | **33 / 1.5%** | **4/60** | **3.07** |
| 0.115 | 33 / 1.5% | 13/60 | 3.27 |
| 0.125 | 33 / 1.5% | 6/60 | 2.90 |
| 0.130 | 33 / 1.5% | 10/60 | 2.72 |
| 0.120 | 31 / 1.5% | 6/60 | 3.22 |
| 0.120 | 35 / 1.5% | 10/60 | 2.93 |
| 0.125 | 30 / 1.2% | 8/60 | 3.53 |
| 0.120 | 33 / 1.0% | 10/60 | 3.50 |

The current values are already optimal: the mean is centred on 3 and 93% of bot-songs land in 2-4. The failures are per-bot variance of about ±1, which no ratio or strong profile removes. Neither versus_config.gd nor bot_profile.gd was retuned. The test seeds were not changed to make it pass. **Decision needed from the user: D-UAT-01 in 03-HUMAN-UAT.md**, with options (per-song mean criterion, rate criterion, a spread-narrowing mechanic, or accepting the red test).

## Public API (for 03-14)

```
SubRig.new(seat, chart, jcfg, cfg, sim, channel, no_fail)
  judge: VersusJudge, hull: VersusHull, stack: PayloadStack, now, approach_s (writes PlayerState)
  press(lane, t) / release(lane, t) / tick(t) / begin(t)   # begin before pressing the judge directly
  accuracy() -> 0..1 ; counters perfect/good/miss/depth_perfect/depth_other/ghost_hits
  signals judgment_reported(idx, j, t), overlay_added(payload_id, notes)
BotProfile.veteran()/regular()/rookie()/from_skill(s); effective_for(reward)
BotPlayer.new(rig, profile, sim, cfg, chart, seed)
  next_time() / step() (exact-time actions), update(t) (per-frame driver + rig.tick)
  effective_profile(t), press_log, fire_log
MatchHarness.new(chart, opts) ; advance_to(t) ; finish() ; result()
MatchHarness.run(chart, opts) -> {event_log, standings, meter_rewards, fired, landed, reflected,
  duration_s, threshold, note_count, stats}
  opts: human autoplay|none|bot, human_skill, bots [skill|BotProfile], seed, fps (10..2000), cfg, jcfg,
        training (-1 off / -2 all / disruptor id)
TrainingDrone.new(sim, chart, cfg, drone_seat, target_seat, mode)
  next_time()/step()/update(t), bars_until_next(t) -> int, current_reward(), fire_log
```

## Notes for 03-14

- **Live scene driving.** For in-game play, call `bot.update(song_t)` and `drone.update(song_t)` each frame, and the human's `rig.press/release/tick` from LaneInput with the audio-clock song time. Frame-chunked bot updates are fine in-game; exact cross-fps determinism is only guaranteed through MatchHarness's global order. If you need it live, reuse `MatchHarness.advance_to(t)` with a human actor.
- **Human rig.** Set `rig.approach_s` from the Highway's approach time before payloads land. Versus rigs use `no_fail = false`; training uses `true` (D-27). Never read Settings.no_fail.
- **03-06 integration (confirmed).** SubRig forwards RAW judgments for every seat, including wrecks (which fill the debris meter). Bots keep playing as wrecks and fire debris as soon as REWARD_EARNED source "debris" arrives, retrying each beat.
- **Untracked scratch file.** `tests/zz_sweep_0307_scratch.gd` (+ .uid) is a leftover I could not delete (the shell guard held `rm`). It now holds an empty suite. Please delete both files; they were never committed.
- test_bot_frequency takes about 28 s and will stay red until D-UAT-01 is decided.

## Deviations from Plan

1. **[Rule 1 - Determinism] Global-order actor stepping instead of frame-order `bots.update(t), autoplay.update(t), rig.tick(t), sim.update(t)`.** Frame-time ticks stamp expiry misses and sustain-tick score reports at the frame time, and processing seats one after another inside a frame reorders events across seats. Both make logs depend on fps. Actors with exact action times and a fixed 5 ms tick grid fix this. Commit fce89ae.
2. **[Rule 2] Late commit refusals.** A FIRE_OK whose launch is later refused ("race"/"no_target") or cancelled in a COLLISION is handled through events, so the bot or drone retries or moves on instead of stalling.
3. **Spec req 8 escalation ended at the "record a user decision" step.** No tuning was committed; versus_config.gd was not touched.
4. The SubRig signals `judgment_reported` and `overlay_added`, `SubRig.begin(t)`, and the `stats`/`note_count` result keys were added for drivers and tests.

## Known Stubs

None.

## Threat Flags

None. T-03-18 is covered by the loop being bounded by chart end + 2 s and a 30-minute hard cap, fps clamped to 10..2000, and guard counters. T-03-19 is covered by a private seeded RNG per bot (hash of match seed, "bot" and seat) and the 3-fps determinism test.

## Self-Check: PASSED
