---
phase: 03-offline-versus
plan: 01
subsystem: versus-core
tags: [timing-gate, hull, rewards, bag, match-setup, settings]
requires: []
provides:
  - "perfect_regen 0.25 (03-SPEC req 14) with judge_config.gd re-baselined to 2c2e54c"
  - "VersusConfig (all Phase 3 tunables, bars_for, validated)"
  - "Reward (ids, kinds, UI-SPEC 4.1 table, descriptions from config)"
  - "RewardBag (seeded Fisher-Yates, seed_for)"
  - "RewardMeter (threshold, hold/queue/refund/credit/reset_lost)"
  - "MatchSetup (launch record, callsigns, rematch, static pending) + Settings [versus]"
affects: [03-03, 03-05, 03-13, 03-14, all later Phase 3 plans]
tech-stack:
  added: []
  patterns: ["pure RefCounted rule classes with emit-on-set", "private RandomNumberGenerator per object"]
key-files:
  created:
    - src/versus/versus_config.gd
    - src/versus/reward.gd
    - src/versus/reward_bag.gd
    - src/versus/reward_meter.gd
    - src/versus/match_setup.gd
    - tests/test_reward_meter.gd
    - tests/test_reward_bag.gd
    - tests/test_match_setup.gd
  modified:
    - src/core/judge_config.gd
    - tests/test_hull_score.gd
    - tools/check_timing_gate.ps1
    - src/autoload/settings.gd
    - tests/test_settings_roundtrip.gd
decisions:
  - "RewardMeter's instance threshold is named `target` (GDScript forbids a var and the static func threshold() sharing a name); progress_changed still emits (value, threshold)"
  - "Reward descriptions also fill a {mult} token for Pressure Crack from pressure_crack_mult, so no number is hard-coded"
  - "_set_held always emits slot_changed (even when the id repeats) so a queued prize equal to the used one still notifies the HUD"
metrics:
  duration: "~35 min"
  completed: 2026-10-15
---

# Phase 3 Plan 01: Hull pin move and reward/match foundations Summary

perfect_regen moved 1.0 -> 0.25 in the exact D-29 three-commit shape (A 2c2e54c), plus the pure, headless-tested reward model (VersusConfig, Reward table, seeded RewardBag, RewardMeter) and the MatchSetup launch record with validated Settings [versus] persistence.

## Commits

| Step | Hash | Message |
|------|------|---------|
| A | 2c2e54c | feat(03-01): perfect_regen 1.0 -> 0.25 (03-SPEC req 14, user-approved 2026-10-08) |
| B | a191e06 | test(03-01): hull regen tests expect a quarter per Perfect (03-SPEC req 14) |
| C | f348127 | chore(03-01): timing gate re-baselines judge_config.gd to 2c2e54c |
| T2 RED | 709eb1a | test(03-01): add failing tests for reward meter, bag and table |
| T2 GREEN | 531a9b8 | feat(03-01): VersusConfig, Reward table, RewardBag and RewardMeter |
| T3 RED | 401a7c7 | test(03-01): add failing tests for MatchSetup and versus settings |
| T3 GREEN | 235a119 | feat(03-01): MatchSetup launch record and versus Settings persistence |

Commit A changed 1 file, 1 insertion, 1 deletion. After pushing, `git merge-base --is-ancestor 2c2e54c HEAD` exited 0 and `git log --oneline -1 2c2e54c` still shows the perfect_regen commit (the rebase did not rewrite A), so C did not need redoing.

## Gate proof (D-29, T-03-01)

1. After commit C:
```
TIMING GATE OK
exit 0
```
2. Scratch edit (one space appended to src/core/judge_config.gd):
```
vs 2c2e54c:
 src/core/judge_config.gd | 1 +
 1 file changed, 1 insertion(+)
 M src/core/judge_config.gd
TIMING GATE FAILED
exit 1
```
3. After `git checkout -- src/core/judge_config.gd`:
```
TIMING GATE OK
exit 0
```
4. `git diff fbcf994 2c2e54c -- src/core/judge_config.gd`:
```
@@ -13,7 +13,7 @@ extends Resource
 @export var hull_start: float = 100.0
 @export var miss_damage: float = 8.0
-@export var perfect_regen: float = 1.0
+@export var perfect_regen: float = 0.25
 @export var score_perfect: int = 100
```
Plan end: TIMING GATE OK again. conductor, clock_model, input_judge and hull_score were not touched; `$base = "72e21ce"` is unchanged.

## Tests

- test_hull_score 10/10 (92.0 -> 92.25; 31 Perfects -> 99.75; 32 -> 100.0)
- test_reward_meter 19/19, test_reward_bag 13/13, test_match_setup 11/11, test_settings_roundtrip 17/17
- Full suite: 1276 test cases, 0 errors, 0 failures (run after 03-02 had landed)
- `grep "randi()\|randomize()" src/versus` only matches calls on private RandomNumberGenerator instances (none global)

## Deviations from Plan

**1. [Rule 3 - Blocking] RewardMeter instance field renamed `threshold` -> `target`**
- **Found during:** Task 2 GREEN. GDScript refuses to parse a class with both `var threshold` and `static func threshold`.
- **Fix:** Kept `static func threshold(note_count, ratio)` (used by 03-03 and 03-13) and named the per-meter value `target`. The `progress_changed(value, threshold)` signal is unchanged.
- **Commit:** 531a9b8

**2. [Rule 2] Extra small API pieces:** `Reward.is_valid`, a `{mult}` description token, `MatchSetup.MIN_RIVALS/MAX_RIVALS` (Settings uses them for clamping), `RewardMeter.enabled` blocks judgments/credit/refund. `new_seed()` uses a hashed ticks+counter seed instead of `randomize()`, so the plan's grep check stays clean.

## Notes for later plans

- Use `meter.target` (not `meter.threshold`) for a live meter's threshold; `RewardMeter.threshold(n, ratio)` is the static calculator.
- `RewardMeter.on_judgment(j, overclock)` is fed per judgment; strays must not be forwarded. Depth Charge overlay Perfects go through `credit(n)`, bounty refunds through `add_refund(amount)` (source "bounty"), duel prizes through `queue_prize(id)` (source "duel").
- `MatchSetup.save_to_settings()` writes to `Settings.save_path`; tests must redirect it (see tests/test_match_setup.gd).
- Callsign shuffle seed is `hash(["callsigns", seed])`, independent of the bag seeds (`RewardBag.seed_for(match_seed, seat)`).

## Known Stubs

None.

## Self-Check: PASSED
