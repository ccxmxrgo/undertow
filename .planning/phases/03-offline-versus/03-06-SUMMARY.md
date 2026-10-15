---
phase: 03-offline-versus
plan: 06
subsystem: versus-rules
tags: [match-sim, return-to-sender, solo-duel, wreck-debris]
requires: ["03-03"]
provides:
  - "Return to Sender: WARHEAD / REFLECTED / FIZZLED, PAYLOAD_END reason reflected"
  - "Solo Duel: DUEL_ANNOUNCE / DUEL_START / DUEL_RESULT, duel_live(seat), duel_active()"
  - "Wreck debris meter and debris launches (METER debris true, REWARD_EARNED source debris)"
affects: [03-07, 03-09, 03-10, 03-11, 03-12, 03-14]
tech-stack:
  added: []
  patterns: ["Solo Duel milestones scheduled as a 4th expiry kind in the song-time walk"]
key-files:
  created:
    - tests/test_return_to_sender.gd
    - tests/test_solo_duel.gd
    - tests/test_wreck_debris.gd
  modified:
    - src/versus/match_sim.gd
decisions:
  - "Landed stat: +1 at LANDED for non-reflected, non-debris disruptors; -1 on the shooter when the target reflects. Reflected and debris landings never count."
  - "Warhead sets are registered at TORPEDO_LAUNCH (keyed Vector2i(target, note)), so a warhead judged early (before arrival) still counts; if all are Perfect before arrival, reflection fires at LANDED."
  - "Reflection: REFLECTED at the judgment time of the last warhead; the payload's end_t moves to the next whole beat (PAYLOAD_END reason reflected, immunity from there); the relaunch is queued for that same beat."
  - "Reflected pending launches never block the reflector's own Fire and survive the reflector's elimination; FIZZLED uses the original torpedo id."
  - "The reflect chance also dies (pending bounty claimed, no event) when the target is eliminated or the payload expires before the last warhead is judged."
  - "Solo Duel judgments are counted from the announcement, so a solo note judged early before DUEL_START counts. Final % = Perfects / recounted solo notes; live % = Perfects / judged."
  - "DUEL_RESULT pct = winner's % (-1.0 with no winner); best_pct = best % of any participant; tied only when qualifiers stay tied after the streak tie-break."
  - "Overlapping solos: a solo that starts at or before the end of an earlier kept solo is dropped. Cap 64 duels."
  - "Duel prize is not drawn when slot and queue are both full (bag kept intact)."
  - "Debris target is fixed at the press (the leader at that time), like normal fires; a race/shield at the launch beat refuses it and keeps the debris."
metrics:
  duration: "~60 min (including a usage-limit interruption)"
  completed: 2026-10-15
---

# Phase 3 Plan 06: Return to Sender, Solo Duel and wreck debris Summary

MatchSim now decides the last three rule systems from song-time-stamped judgments: all-Perfect warheads reflect a disruptor back at its sender (with fizzle, Decoy and bounty rules), solos with 16+ recounted notes run a Perfect % duel that awards the next bag item, and eliminated players fill a capped SILT/GROAN debris meter aimed at the living leader.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 585cbdb | test(03-06): add failing tests for Return to Sender |
| 1 GREEN | 0bf188e | feat(03-06): Return to Sender warheads, reflection and fizzle in MatchSim |
| 2 RED | 15e3a60 | test(03-06): add failing tests for Solo Duel |
| 2 GREEN | 3aa1c1c | feat(03-06): Solo Duel in MatchSim |
| 3 RED | e2b4510 | test(03-06): add failing tests for wreck debris |
| 3 GREEN | 0041fab | feat(03-06): wreck debris meter and debris launches in MatchSim |

## Tests

- test_return_to_sender 14/14, test_solo_duel 14/14, test_wreck_debris 10/10
- 03-03 suites still green: test_match_sim_fire 33/33, test_match_sim_bounty 12/12, test_buffs 9/9, test_match_standings 11/11, test_match_sim_determinism 2/2, test_event_channel 10/10
- `grep "Time\.\|Settings\.\|extends Node" src/versus/match_sim.gd` is empty
- `tools/check_timing_gate.ps1`: TIMING GATE OK
- Full suite not run (parallel-wave rule). While these suites ran, the console showed parse errors in src/ui/highway.gd and src/ui/feedback.gd (other wave-3 plans, half-finished at that moment). They did not affect these suites.

## New public API

```
duel_live(seat) -> float   # 0..100 live Perfect % in the running duel, -1.0 otherwise
duel_active() -> int       # chart.solos index of the running duel, -1 otherwise
const MAX_DUELS := 64
```
request_fire on a wreck now fires debris (FIRE_OK / FIRE_PENDING / FIRE_SHIELDED / FIRE_NO_TARGET, or FIRE_NOTHING with "nothing" when no debris is held).

## Notes for later plans

- **03-07 (controller):** Feed every base judgment for wrecks too (on_judged): wrecks fill the debris meter through it. A wreck's Fire key calls request_fire as usual. Warheads need raw judgments (Overclock upgrades must not be passed in).
- **03-09/03-10/03-11 (views):** METER with debris true is the wreck socket. It is emitted once at elimination (progress 0), on every fill/reset, and after each debris launch. `PlayerState.debris_used == cfg.debris_max_per_wreck` means NO DEBRIS LEFT. WARHEAD k/n drives the warhead ring. PAYLOAD_END reason "reflected" arrives one beat after REFLECTED (ease-out beat). DUEL_* `solo` is the chart.solos index.
- **03-12 (medals):** REFLECTED.id and FIZZLED.id are the original torpedo id (the LANDED id), so `reflected_ids` filtering works. A reflected relaunch gets a new id with TORPEDO_LAUNCH reflected true.
- **03-14 (wave end):** Run the full suite. match_sim.gd is the only shared file this plan touched. Results LANDED column = PlayerState.landed (excludes reflected and debris), REFLECTED column = PlayerState.reflected (counts fizzled reflections too).

## Deviations from Plan

**1. [Rule 2] Reflect-chance end cases.** The plan covered failed warheads and reflection only. Two more cases now end the reflect chance (open warheads dropped, a pending bounty claimed): the target is eliminated, or the payload expires before every warhead is judged. Without this, a pending bounty claim could stay stuck forever. Commit 0bf188e.

**2. [Rule 1] Early judgments.** A warhead or solo note can be judged up to good_window before its time, which can be before the torpedo lands or before DUEL_START. Warhead sets are registered at launch, and duel counting starts at the announcement, so these judgments are not lost. Commits 0bf188e, 3aa1c1c.

**3. [Rule 2] Reflected launches do not block the reflector.** `_has_pending` ignores reflected entries, and on_failed keeps them, so the reflector can still fire, and a reflection still resolves (or fizzles) if the reflector dies. Equal-seat launches sort reflected first, so the order is deterministic. Commit 0bf188e.

**4. Test fixture.** The bounty tests in test_return_to_sender use a 1000-note chart (threshold 120, refund 30), which matches the plan's refund 30.

## Known Stubs

None.

## Threat Flags

None. T-03-15 (64-duel cap, recount, malformed solos dropped), T-03-16 (reflected torpedoes carry no warheads, tested) and T-03-17 (debris cap, 1-bar payloads, shields) are all mitigated.

## Self-Check: PASSED
