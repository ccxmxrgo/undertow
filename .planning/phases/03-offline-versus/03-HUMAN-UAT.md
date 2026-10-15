# Phase 3 Human UAT

## Decisions needed

### D-UAT-01: Strong-bot reward frequency (03-SPEC req 8) cannot be met per bot (plan 03-07)

**Requirement:** in a 4-Veteran-bot match on each bundled song (Expert), each bot earns 2-4 meter rewards.

**Status:** `tests/test_bot_frequency.gd` keeps the strict per-bot [2, 4] assertion and **fails on one bot** (HRT seat 3 earns 5). As instructed, the test was not loosened and the defaults were not changed.

**Measured in-engine** (MatchHarness, 4 Veteran bots, fps 60, real MatchSim rules including payloads, warheads and duels; committed seeds 101/202/303/404/505):

| song | notes | threshold | rewards per bot |
|------|-------|-----------|-----------------|
| synth_wave_april | 416 | 50 | 3, 3, 3, 4 |
| space_synth_wave | 569 | 69 | 2, 3, 4, 2 |
| sea_shanty_2 | 471 | 57 | 3, 4, 2, 4 |
| hrt | 394 | 48 | 4, 3, 3, **5** |
| invisible | 440 | 53 | 4, 4, 2, 2 |

**Escalation tried** (3 seeds x 5 songs x 4 bots = 60 bot-songs each):

| reward_threshold_ratio | Veteran sigma / lapse | bots outside [2, 4] | mean rewards | committed seeds pass |
|---|---|---|---|---|
| **0.120 (current)** | **33 ms / 1.5% (current)** | **4 / 60** | **3.07** | no (one 5) |
| 0.115 | 33 ms / 1.5% | 13 / 60 | 3.27 | no |
| 0.125 | 33 ms / 1.5% | 6 / 60 | 2.90 | no |
| 0.130 | 33 ms / 1.5% | 10 / 60 | 2.72 | no |
| 0.120 | 31 ms / 1.5% | 6 / 60 | 3.22 | no |
| 0.120 | 35 ms / 1.5% | 10 / 60 | 2.93 | no |
| 0.125 | 30 ms / 1.2% | 8 / 60 | 3.53 | no |
| 0.120 | 33 ms / 1.0% | 10 / 60 | 3.50 | no |

The current values are already the best: the mean sits at 3 and about 93% of bot-songs land in 2-4. The misses are per-bot variance. A bot's reward count spreads by about ±1 around the mean, so no single ratio or strong profile puts all 20 bots on every song inside [2, 4]. Choosing seeds until the test passes would be cherry-picking, so that was not done.

**Options for the user:**
1. Accept the per-song average criterion. The mean per song for strong bots is in [2, 4]: 3.25, 2.75, 3.25, 3.75 and 3.0 here. The test would then assert the per-song mean in [2, 4] and each bot in [1, 5].
2. Accept a rate criterion. At least 90% of strong-bot songs land in [2, 4] over N seeds (93% measured).
3. Keep the strict per-bot rule and add a mechanic that narrows the spread, such as a soft cap or pity timer on the meter. This is a design change beyond spec req 1-2.
4. Keep everything as is and accept the red test as a known deviation.

Until the user decides, `reward_threshold_ratio` stays at 0.12 and Veteran stays at 33 ms / 1.5%.
