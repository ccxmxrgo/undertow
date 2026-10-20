---
status: pending
phase: 03-offline-versus
source: [03-15-SUMMARY.md, 03-14-SUMMARY.md, 03-07-SUMMARY.md, 03-UI-SPEC.md "Notes for the checker"]
started: 2026-10-15T00:00:00Z
updated: 2026-10-15T21:50:00Z
---

# Phase 3 Human UAT

## Current Test

Decision D-UAT-01 (below) comes first, because it decides whether the one red test (tests/test_bot_frequency.gd) stays red. After that, test 12 (the final checkpoint) covers most of the other items in one sitting. Test 10 needs a second PC.

## Tests

| # | Test | How | Expected | Status |
|---|------|-----|----------|--------|
| 1 | Full versus match, fun and fairness | Main menu > Versus Bots > 3 rivals, VETERAN > Start Match on a bundled song at Expert. Play the whole song | The match feels fun and fair, torpedoes land mid-song, and the outcome feels earned | pending |
| 2 | Telegraph noticed in time (UI-SPEC open question 1) | During test 1, note which cue you notice first when a torpedo is aimed at you: the alert slot at y 120, the red edge flash, the ping, or the warhead rings | You react before arrival. Record which cue does the work | pending |
| 3 | Decoy on rival panels (UI-SPEC open question 2) | Watch the panels while bots hold or use Decoy Flare | Decide whether a rival's armed Decoy should be visible (currently hidden until it absorbs something) | pending |
| 4 | Crossed Wires input reading (UI-SPEC open question 3, Defaults Log 17) | Take a Crossed Wires (training: F3 > CROSSED WIRES in Solo Dive) | Decide: input follows screen position (D-10, implemented) or follows lane colour (spec alternative). Also judge the feel of the slide | pending |
| 5 | Rival held-reward icons (UI-SPEC open question 4) | Watch the panel discs during test 1 | Not distracting from the highway | pending |
| 6 | Ballast Patch 25% (spec: unconfirmed) | Use Ballast Patch at low hull in a few matches | 25% of the hull feels like the right amount | pending |
| 7 | Readability of every disruptor, scroll 1x and 3x, Full and Low | Solo Dive training "ALL", once at 1x and once at 3x, with Low effects off and on. Compare with the uat-shots gallery | Every disruptor is readable and survivable at every combination | pending |
| 8 | Bot tiers and reward frequency for medium players (Pitfall 11) | One match each at Rookie, Regular, Veteran. Count your own rewards on Expert | The tiers feel distinct. A medium-skill player still earns at least 1-2 rewards a song (strong bots average 3, see D-UAT-01) | pending |
| 9 | Slower hull repair (req 14, perfect_regen 0.25, a Miss takes ~32 Perfects) | Play a normal Start Dive and a versus match | Hull repair feels slower but fair, and sinking is not too easy | pending |
| 10 | Friend PC test of zip v0.6.0 | Send build/dist/UNDERTOW-playtest-v0.6.0.zip (sha256 9d4a31188b47b01993083ee8438fd80f60ad98ca7ac6a1e26e0430c8c7c093a2). The friend follows TESTER-CHECKLIST.txt section 4d VERSUS | The game runs, the versus checklist is filled in, and frame rate and keyboard rollover (Space + 3 lane keys) are reported | pending |
| 11 | Visual follow-ups and the p95 result from 03-15 | Review the "Visual follow-ups" and "Performance follow-up" sections below and decide fix or accept for each | Each item is marked fix (gap closure plan) or accept | pending |
| 12 | Final checkpoint of plan 03-15: human verification of the versus match (non-blocking) | 1. Run UNDERTOW from the editor or the v0.6.0 zip. Main menu > Versus Bots > 3 rivals, VETERAN > Start Match on a bundled song at Expert. 2. Play the whole song: fire rewards with Space, switch targets with H, try to reflect a torpedo (hit the red-ringed notes Perfect), and watch the killfeed and the left panels. 3. Let your hull break once (or play badly) and check that you keep playing as a wreck and can fire debris. 4. Check the results screen (places, landed/reflected, medals, seed) and Rematch / Change Match / Back to Menu. 5. Solo Dive: Song Select > F3 to pick a training torpedo > Start Solo Dive, and check that the drone fires it every 8 bars. 6. Answer the questions in this file | Reply "approved" or list the issues. Then update this file (and run /gsd:verify-work 3, or plan gap closure for the issues) | pending |

Also pending from 03-14: the error blip volume in gameplay (refused fire: SHIELDED / NO TARGET) and the in-place Rematch flow (QUICK intro). Check both during test 12.

## Visual follow-ups (from the 03-15 screenshot review, non-blocking)

Gallery: `.planning/phases/03-offline-versus/uat-shots/` (33 shots, 960x540).

- **V-1 Collision headline clipped.** The alert headline "BOTH TORPEDOES DESTROYED" is truncated to "BOTH TORPEDOES DESTR..." at Heading 40 / 528 px (`versus_alert_collision`, `versus_killfeed_4`). The fix is shorter copy (for example "BOTH DESTROYED") or a smaller size.
- **V-2 Periscope callsign truncation.** "BARRACUDA" shows as "BARRA..." on the panels. UI-SPEC 6.2 says 112 px fits 9 characters (every in-match shot).
- **V-3 FxLayer bursts and Feedback popups under Crossed Wires (03-08 open item, confirmed).** After the swap, the hit burst rings and particles appear at the original lane x, not at the swapped receptor (`versus_crossed_wires_x3_full`: the green burst is on the pink receptor and the pink one on the green).
- **V-4 Pressure Crack rail cue reads pale, not red.** `mix(SONAR, WARNING_RED, 0.6)` gives a whitish rail, so the "danger" cue is weak (`versus_pressure_crack_*`).
- **V-5 Ink Cloud lets a popup letter through.** A judgment popup wider than the band shows a stray "T" (from PERFECT) just outside the ink polygon's right edge (`versus_ink_cloud_*`, `versus_ink_sustain`).
- **V-6 Sonar Jam never fully greys the warhead gems.** The warheads are the first notes after arrival, so they are judged during the 1-beat colour fade. This is by design, so check whether it reads well (`versus_jam_warheads`).
- **V-7 Solo Dive training description crowds the "TRAINING TORPEDOES" header.** The description line sits a few px above the header (`solo_training_stepper`).
- **V-8 Killfeed killstreak burst.** When 3-4 lines arrive within a beat, the newest lines are still sliding in (alpha low) for about 0.3 s (`versus_killfeed_4`; `versus_panels_bounty_target` shows the settled 4 lines). This is cosmetic.
- No element was found on the note path. Text is unclipped except V-1 and V-2. Every disruptor reads in Low effects.

## Performance follow-up (UI-SPEC 12, U-12 gate 4.35 ms p95 uncapped)

Measured on the dev PC (AMD Radeon RX 9070 XT, 1920x1080, 180 Hz screen, vsync off) by playtest scenario `versus`. The setup was 3 Veteran bots plus Ink Cloud kept on the human, over the densest 30 s of space_synth_wave Expert (35.9 s, 105 notes):

| Capture | p50 ms | p95 ms |
|---|---|---|
| Solo dive baseline (scenario perf, sea_shanty_2, Full) | 2.66 | 2.95 |
| **Versus, 3 bots + Ink Cloud, Full** | **4.79** | **5.22 (over the gate)** |
| VersusHud hidden and not processing | 3.97 | 4.28 |
| Ink layers hidden | 4.91 | 5.34 |
| Reward socket, target readout and status chips hidden | 4.91 | 5.32 |
| Versus, Low effects | 3.60 | 4.08 |
| Gameplay._process (VersusController.pre_tick + judge.tick + VersusController.update) | 0.18 | 0.28 |

The controller with 3 bots costs only about 0.3 ms. About 1 ms is the VersusHud views (periscope panels, killfeed, alert, banners), and the remaining ~1.3 ms over solo comes from elsewhere in drawing. The fix is to profile and throttle the VersusHud redraws, for example panels only on STATUS events. 5.2 ms is still about 190 fps, so the question is whether the 4.35 ms (230 fps) gate holds for versus.

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

## Verifier additions (03-VERIFICATION.md, 2026-10-20)

Status: human_needed. No blocking gaps. On the final tree: TIMING GATE OK, and the full suite runs 1726 cases with 1 failure (the known red test_bot_frequency, hrt seat 3 = 5). These items are added to the list above; the sections above are unchanged.

| # | Test | How | Expected | Status |
|---|------|-----|----------|--------|
| 13 | Review-fix input feel (CR-01, WR-01, WR-02, WR-03) | During test 12, play real presses in versus (they now route through VersusController's time-ordered stepping). Take a Crossed Wires and press a held lane's second key. Reflect a payload and watch its end | Presses feel the same as Solo Dive. Crossed Wires never swallows a press. A reflected payload eases out on the beat. A bounty claim appears when a shot lands on the leader after a missed first warhead | pending |
| 14 | Borderline versus perf gate | Decide accept or fix: p95 is 4.18-4.45 ms against the 4.35 ms U-12 gate on the final tree (passed in 1 of 2 runs, noise about +-0.15 ms) | Accept, or plan a perf follow-up (shared glow texture, profile the Full-only effects) | pending |
| 15 | Unreliable ink-share playtest check | The versus playtest's "Ink Cloud visible on >= 45% of frames" check ranged from 34% to 73% between runs because the harness injects ink outside the controller's time ordering | Decide whether to fix the harness so perf captures are reproducible (tooling follow-up) | pending |

Notes:
- Zip hash for test 10: the current `build/dist/UNDERTOW-playtest-v0.6.0.zip` is 65,821,334 bytes, sha256 `8bb56f40a926de26aa653c438acc54d49922720d89434869f406ddd7cd75402e` (rebuilt after the review fixes). The `9d4a3118...` hash in test 10 is the first build.
- For the transition step: ROADMAP Phase 3 SC2 and REQUIREMENTS PAY-02 still name Lane Flip (superseded by Crossed Wires, SPEC req 7). ROADMAP still shows 03-14 and 03-15 unchecked.
