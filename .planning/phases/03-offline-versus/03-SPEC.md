# Phase 3: Offline Versus — Specification (Killstreak Rewards)

**Created:** 2026-10-08
**Ambiguity score:** 0.18 (gate: ≤ 0.20)
**Requirements:** 8 locked

> **Scope of this spec.** It locks only the *reward system* (how attacks are earned, drawn and fired, and the reward pool). It changes TORP-01, TORP-02 and PAY-02. All other Phase 3 requirements (TORP-03..06, PAY-01, PAY-03..06, MATCH-01..06) stay as written in `REQUIREMENTS.md` and are **not** pre-answered here. discuss-phase should still discuss them normally.

## Goal

The single "full tube = one torpedo" attack becomes a Call of Duty-style killstreak system. An unbroken Perfect streak earns a randomly drawn reward from a pool of 6 disruptors and 3 buffs, about 3 times per song for a strong player.

## Background

Phase 1 has a combo counter and streak popups at 10/25/50/every 100 (`src/core/streak_milestones.gd`). Timing windows are Perfect ±35 ms and Good ±70 ms (`src/core/judge_config.gd`). Hull damage goes through `HullScore._damage` (`src/core/hull_score.gd`). No torpedo, tube, payload or targeting code exists yet.

The original design (PROJECT.md, REQUIREMENTS TORP/PAY) had one tube that fires one of five payloads. `research/FEATURES.md` listed random pickups as an anti-feature. **The user reversed that on 2026-10-08:** rewards are now random, with the shuffled bag below as the fairness guard. The aim is to make matches more dynamic ("you get 5 kills, you get the Predator missile") without making them chaotic.

Typical chart sizes (Clone Hero, 3–4 min song): Easy ~150–250 notes, Medium ~300–450, Hard ~500–700, Expert ~800–1,300. Fixed streak counts can't work across difficulties, so the threshold scales with the chart.

## Requirements

1. **Scaled reward threshold**: The reward meter (the torpedo tube) fills by 1 per consecutive Perfect hit. It earns a reward at `ceil(0.12 × chart_note_count)` Perfects.
   - Current: No tube. TORP-01 says "a Perfect streak fills the tube" without a size.
   - Target: Threshold = `ceil(reward_threshold_ratio × chart_note_count)`, with `reward_threshold_ratio = 0.12` as a tunable constant. A Miss empties the meter. A Good doesn't add to the meter (Overclock is the exception) but doesn't empty it either. A stray press (no note) doesn't change it. Using a reward does **not** empty the meter (CoD-style: the streak keeps going).
   - Acceptance: Unit test: a 1,000-note chart gives a threshold of 120 and a 400-note chart gives 48. 119 Perfects earn nothing and the 120th earns a reward. A Miss at any point resets progress to 0.

2. **One reward slot**: A player holds at most one reward at a time.
   - Current: n/a
   - Target: While a reward is held, the meter stops at full and stays there. When the reward is used, the meter starts filling again from 0 with the ongoing streak. A Miss while holding a reward keeps the reward and resets the meter.
   - Acceptance: Unit test: with a reward held, 50 more Perfects don't earn a second reward. After using it, a new reward needs a full new threshold of Perfects.

3. **Shuffled-bag draw**: Each player draws rewards from a personal shuffled bag of all 9 rewards.
   - Current: n/a
   - Target: When a player earns a reward, it is the next item in their bag. The bag holds each of the 9 rewards exactly once in shuffled order and refills (reshuffled) when empty. Each player's bag uses a seeded RNG (seed is set per match, so Phase 4 online play can reproduce draws).
   - Acceptance: Unit test: 9 draws from a fresh bag give each reward exactly once. With a fixed seed the sequence is the same every run. No reward appears twice within any 9 draws in a row taken from the start of a bag.

4. **Firing**: Fire uses the held reward.
   - Current: TORP-02 fires "a full torpedo".
   - Target: The HUD shows the held reward's name and icon. Fire on a **disruptor** sends it to the current target (targeting per TORP-03). Fire on a **buff** applies it to the player. Launch and arrival snap to beats (TORP-02). The target gets a telegraph ≥1 beat ahead (TORP-04). One active disruptor per player plus an immunity window (TORP-05). Disruptors can be reflected by Return to Sender (PAY-06). Buffs can't be targeted, reflected or absorbed.
   - Acceptance: In a bot match, firing a held disruptor puts it on the current target's highway on a beat after a ≥1-beat telegraph. Firing a held buff applies it to the firer only.

5. **Disruptor pool (6)**: Every disruptor is readable and survivable without mashing (TORP-06). Bar lengths are tunable constants.

   | Disruptor | Effect | Counterplay | Duration |
   |---|---|---|---|
   | **Crossed Wires** (new; replaces Lane Flip) | Two lanes, picked at random, swap positions. Notes keep their lane color and shape, and the receptors visibly slide to their new spots over 1 beat. Input follows the new position. | Follow color/shape, not position | 4 bars |
   | **Ghost Notes** (PAY-03) | Fake notes with a hollow shape mixed in. Hitting one costs hull. | Spot the shape | 4 bars |
   | **Ink Cloud** (PAY-04) | The bottom 35% of the highway is blacked out | Read ahead | 4 bars |
   | **Pressure Crack** (PAY-01) | Scroll speed ×1.5, easing in over 1 beat | React faster | 4 bars |
   | **Sonar Jam** (new) | All notes are drawn in one neutral gray with no lane shape | Read the lane by position | 3 bars |
   | **Depth Charge** (PAY-05) | Extra notes on the song's rhythm, capped by local chart density | Skill check | 2 bars |

   - Current: Only payload names in REQUIREMENTS. No code.
   - Target: All 6 run on a target's highway through the same payload interface.
   - Acceptance: In Solo Dive training (MATCH-06), each of the 6 can be triggered and ends after its duration. Autoplay still finishes the chart all-Perfect under each one, except Ghost Notes, where autoplay skips the fakes. That shows each one stays playable.

6. **Buff pool (3)**:

   | Buff | Effect |
   |---|---|
   | **Decoy Flare** | Arms immediately. The next disruptor that would land on the player is absorbed instead (no telegraph-to-impact effect, no immunity window spent). It expires unused after 8 bars. A disruptor reflected back by Return to Sender counts as incoming, so the flare absorbs it. |
   | **Ballast Patch** | Instantly restores 25% of max hull, capped at max. It can't revive an eliminated player. |
   | **Overclock** | For 4 bars, Good judgments count as Perfect for the reward meter and for score. Misses still reset. |

   - Current: n/a
   - Target: All 3 implemented. Each has a visible HUD state while it's active or armed.
   - Acceptance: Unit tests: Ballast Patch at 90% hull ends at 100%, and at 50% ends at 75%. An armed Decoy Flare absorbs exactly one incoming disruptor and then disarms, or disarms after 8 bars. During Overclock a Good adds +1 to the meter, and after 4 bars it stops doing that.

7. **Lane Flip removed from the pool**: PAY-02 (full mirror) isn't in the reward pool. Crossed Wires takes its place.
   - Current: PAY-02 in REQUIREMENTS.
   - Target: PAY-02 is superseded by Crossed Wires. REQUIREMENTS.md should be updated to match at the next transition.
   - Acceptance: The reward pool has exactly the 9 rewards listed above.

8. **Reward frequency target**: A strong player earns about 3 rewards per song.
   - Current: n/a
   - Target: The 0.12 ratio is tuned so that a bot at "strong" skill earns 2–4 rewards per song across the bundled songs.
   - Acceptance: A strong-skill bot match on each bundled song logs 2–4 rewards earned per strong bot. If not, adjust `reward_threshold_ratio` and record the new value.

## Boundaries

**In scope:**
- Reward meter (tube) with chart-scaled threshold
- Per-player seeded shuffled bag of 9 rewards
- One-slot hold, Fire to use, HUD display of the held reward
- 6 disruptors and 3 buffs as specified
- Bots earn, draw and fire rewards using the same rules

**Out of scope:**
- Comeback/deathstreak rewards (Last Gasp, Mimic, Emergency Blow, Leader Seeker, Scuttle Charge): deferred. The bag already guarantees a fair mix. Candidates for a later phase.
- Draw odds that depend on match position (Mario Kart-style rubber-banding): deferred, same reason.
- Pre-match loadouts / choosing rewards: the user chose random.
- Salvage phrases (Clone Hero star-power phrases as special reward notes): good idea, deferred. Needs Phase 2 import to keep star-power data.
- Finisher-tier rewards (Leviathan, Torpedo Spread, EMP): deferred. They would need TORP-05 exceptions.
- Wreck-ghost debris attacks (MATCH-03): unchanged by this spec. Ghosts don't draw from the reward bag.
- Network sync of draws: Phase 4. This spec only requires the seeded bag so draws can be replayed.

## Constraints

- Rhythm judgment stays local. Rewards are game events that go through the EventChannel seam (Loopback/Bot now, Net in Phase 4).
- All thresholds, durations and percentages are tunable constants (a config resource like `JudgeConfig`), not hard-coded.
- Ghost-note and Sonar Jam visuals must stay readable with the low-effects toggle on.
- Godot 4.7.2, GDScript, gdUnit4 tests (`tools/run_tests.ps1`).

## Acceptance Criteria

- [ ] Reward threshold = `ceil(0.12 × note_count)` (120 for 1,000 notes, 48 for 400)
- [ ] A Miss resets meter progress. A Good neither adds nor resets (except during Overclock). Using a reward doesn't reset the streak.
- [ ] At most one reward is held, and the meter stops at full while holding
- [ ] A fresh 9-draw bag gives each of the 9 rewards exactly once. A fixed seed gives the same sequence.
- [ ] Fire sends a disruptor to the current target (beat-snapped, ≥1-beat telegraph), or applies a buff to self
- [ ] All 6 disruptors trigger in Solo Dive training and end after their configured duration
- [ ] Decoy Flare absorbs exactly one disruptor or expires after 8 bars
- [ ] Ballast Patch restores 25% of max hull, capped at max
- [ ] Overclock counts Goods as Perfect for 4 bars
- [ ] Lane Flip isn't in the pool, and Crossed Wires is
- [ ] Strong bots earn 2–4 rewards per bundled song

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes |
|--------------------|-------|------|--------|-------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | CoD killstreak framing, 3/song |
| Boundary Clarity   | 0.85  | 0.70 | ✓      | Deferred items listed |
| Constraint Clarity | 0.75  | 0.65 | ✓      | Event seam, tunables |
| Acceptance Criteria| 0.75  | 0.70 | ✓      | Strong-bot frequency check depends on bot skill model from discuss-phase |
| **Ambiguity**      | 0.18  | ≤0.20| ✓      | |

Assumptions the user hasn't explicitly confirmed (proposed in brainstorming, not objected to): the 12% ratio, the one-slot hold, Lane Flip replaced by Crossed Wires, all bar durations, and Ballast Patch at 25%. Treat them as tunable defaults.

## Interview Log

| Round | Perspective     | Question summary | Decision locked |
|-------|-----------------|------------------|-----------------|
| 1     | Researcher      | What should power-ups/killstreaks add? | Escalation, self-buffs and comebacks wanted. CoD killstreak feel ("5 kills → Predator"). |
| 2     | Simplifier      | How are rewards earned/chosen? | Streak-earned. Special notes considered (deferred). |
| 3     | Researcher      | Streak counts of 10–75 too low? Notes per song? | Yes, too chaotic. Thresholds scale with chart note count. |
| 4     | Boundary Keeper | How many rewards per song? | ~3 per song for a strong player, "for now" |
| 5     | Simplifier      | Pool and selection | At least 6 disruptors + 3 buffs, **random** in-game. Shuffled bag chosen as the fairness guard. |

---

*Phase: 03-offline-versus*
*Spec created: 2026-10-08 (via superpowers brainstorming)*
*Next step: /gsd:discuss-phase 3 — implementation decisions (reward HUD, bot skill model, payload interface, plus the rest of Phase 3)*
