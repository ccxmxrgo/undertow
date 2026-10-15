---
phase: 03-offline-versus
plan: 03
subsystem: versus-rules
tags: [match-sim, event-channel, determinism, bounty, standings, targeting]
requires: ["03-01"]
provides:
  - "GameEvent schema (25 types, make(type, t, fields), ALL_TYPES)"
  - "EventChannel seam + LoopbackChannel (optional latency FIFO)"
  - "PlayerState per-seat rules state"
  - "MatchSim song-time referee: fire/flight/collision/shields/immunity/buffs/targeting/bounty/elimination/standings"
affects: [03-06, 03-07, 03-09, 03-10, 03-11, 03-12, 03-14]
tech-stack:
  added: []
  patterns: ["beat-boundary resolution with catch-up-before-input (Pattern 2, Pitfall 6)", "meter signals mirrored into channel events"]
key-files:
  created:
    - src/versus/game_event.gd
    - src/versus/event_channel.gd
    - src/versus/loopback_channel.gd
    - src/versus/player_state.gd
    - src/versus/match_sim.gd
    - tests/test_event_channel.gd
    - tests/test_match_sim_fire.gd
    - tests/test_buffs.gd
    - tests/test_match_sim_bounty.gd
    - tests/test_match_standings.gd
    - tests/test_match_sim_determinism.gd
  modified: []
decisions:
  - "Every time-stamped input calls _advance(t) first, so beats/expiries before the input are processed before it, whatever the frame rate. This makes the event log ordered by song time."
  - "Equal-time tie order: expiries (payload end, decoy, overclock; then seat) come before the beat boundary at that time. Within a beat: collisions, then launches in seat order, then arrivals in id order, then bounty, last standing, targets, status."
  - "report_status, cycle_target and set_target_mode take an optional trailing t (NAN = stamp with the last processed song time)"
  - "STATUS also re-emits when hull changes (still at most once per beat per seat), so periscope hull segments stay current"
  - "Nobody holds the bounty before someone has depth > 0; drones never hold or claim it; a shooter who has become a wreck gets no refund"
  - "A pending launch whose target died before the launch beat is refused with FIRE_REFUSED no_target (reward kept)"
  - "Drones are excluded from standings and LAST_STANDING; wrecks resolve_target to the deepest living sub (D-25 debris target)"
  - "On elimination meter.enabled = false (bag meter off; 03-06 runs a separate debris counter)"
metrics:
  duration: "~40 min"
  completed: 2026-10-15
---

# Phase 3 Plan 03: Event channel and MatchSim rules Summary

A pure, deterministic song-time referee (MatchSim) that turns time-stamped judgments, fire presses, status reports and failures into a fixed GameEvent vocabulary sent through an EventChannel. It covers beat-snapped launches, 1-beat telegraphed flights, shields and immunity, head-on collisions, same-beat races, Decoy/Overclock/Ballast, AUTO/LOCKED/ATTACKERS targeting, the leader bounty, elimination, D-23 standings and LAST_STANDING. The event log is byte-identical at 30, 144 and 1000 fps.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 49fafe2 | test(03-03): add failing tests for GameEvent, EventChannel and PlayerState |
| 1 GREEN | 19b75e0 | feat(03-03): GameEvent schema, EventChannel seam, LoopbackChannel and PlayerState |
| 2 RED | 99a248f | test(03-03): add failing tests for MatchSim firing, shields, collisions, buffs and targeting |
| 2 GREEN | c05507c | feat(03-03): MatchSim firing, flight, collisions, shields, immunity, buffs and targeting |
| 3 RED | 986ef9d | test(03-03): add failing tests for bounty, standings, last standing and determinism |
| 3 GREEN | 4cbb3cf | feat(03-03): MatchSim bounty, standings, last standing, STATUS and finish |

## Tests

- test_event_channel 10/10, test_match_sim_fire 33/33, test_buffs 9/9, test_match_sim_bounty 12/12, test_match_standings 11/11, test_match_sim_determinism 2/2 (77 total, 0 failures)
- `grep -n "Time\.\|Settings\.\|extends Node" src/versus/match_sim.gd` is empty
- `tools/check_timing_gate.ps1`: TIMING GATE OK (conductor, clock_model, input_judge, hull_score and judge_config were not touched)
- Full suite not run (parallel-wave rule; 03-14/03-15 run it at wave end)

## MatchSim public API

```
MatchSim.new(chart: ChartData, cfg: VersusConfig, jcfg: JudgeConfig,
             players: Array[PlayerState], channel: EventChannel, match_seed: int)
const FIRE_OK=0, FIRE_NOTHING=1, FIRE_SHIELDED=2, FIRE_NO_TARGET=3, FIRE_PENDING=4
var threshold: int; var event_log: Array[Dictionary]; var bounty_holder: int (-1 none)
var chart, cfg, jcfg, players, channel, match_seed

on_judged(seat, note_index, judgment, t)        # raw judgment; Overclock flag applied inside
on_extra_judged(seat, judgment, t)              # Depth Charge overlay (P credit 1, G only in OC, M resets)
on_stray(seat, t)                               # meter untouched (spec req 1)
report_status(seat, hull, depth, accuracy, max_streak, t := NAN)
request_fire(seat, t) -> int                    # buffs apply now; disruptors queue for next beat
inject_fire(seat, to, reward, t) -> int         # no meter; disruptor or debris id only
cycle_target(seat, t := NAN) -> int             # returns resolved target
set_target_mode(seat, mode, locked := -1, t := NAN)
resolve_target(seat) -> int
on_failed(seat, t)
update(t)
standings() -> Array[Dictionary]                # {seat, place, alive, depth, hull, accuracy, max_streak, eliminated_at}
winner() -> int                                 # -1 for shared first
finish(t)                                       # MATCH_END once

static launch_beat(t, tempo_map) -> int
static bar_beats_at(t, chart) -> float
static time_after_bars(t0, bars, chart) -> float
static payload_span(reward, arrive_t, approach_s, chart, cfg) -> Array[float]   # exact [start, end]
static payload_window(reward, arrive_t, approach_s, chart, cfg) -> Vector2     # float32 copy
static pick_warheads(chart, arrive_t, count) -> Array[int]
```

Hooks and internals for 03-06: `_on_judged_hook(seat, note_index, judgment, t)` (empty, called for every seat including wrecks and drones after the meter update). `_pending` entries are `{seat, to, reward, launch_beat, inject, reflected, debris}`. `_flights` holds TORPEDO_LAUNCH fields plus `arrive_beat`. `target.active` is the LANDED fields plus `warheads`. `_pending_bounty[id] = {shooter, holder}`, with `_claim_bounty(id, t)` and `_drop_bounty(id)`. `_can_collide(q)` already excludes reflected and debris. `_commit_launch` refuses a shielded target with "race", so reflected relaunches need their own FIZZLED branch. `_emit(type, t, fields)` appends to the log and sends.

## Event schema

Every event has `type` and `t` (song seconds).

| Type | Fields | Emitted by 03-03 |
|------|--------|------------------|
| reward_earned | seat, reward, source meter/bounty/duel/debris | yes (mirrors RewardMeter.reward_earned) |
| reward_queued | seat, reward | yes (mirrors queue_changed != -1) |
| meter | seat, progress, threshold, held, queued, debris | yes (on every progress/slot/queue change; debris false) |
| fire_queued | seat, reward, to, launch_beat | yes |
| fire_refused | seat, reason shielded/no_target/race/nothing | yes |
| torpedo_launch | id, from, to, reward, launch_beat, launch_t, arrive_t, warheads, reflected, debris | yes |
| collision | a, b, ids [id_a, id_b], reward_a, reward_b (a = lower seat) | yes |
| absorbed | id, from, to, reward | yes |
| landed | id, from, to, reward, arrive_t, active_start, end_t, seed, reflected, debris | yes |
| payload_end | id, seat, reward, reason expired/reflected, immune_until | expired only |
| warhead | id, seat, note, k, n, ok | 03-06 |
| reflected | id, by, to, reward | 03-06 |
| fizzled | id, from, to, reward | 03-06 |
| buff_applied | seat, reward, until_t, amount | yes (Ballast amount = ratio x hull_start, until_t = t) |
| buff_ended | seat, reward, reason expired/used/lost | yes |
| target | seat, mode (PlayerState.TargetMode int), target | yes (on change; checked every beat, on cycle/set and on failure) |
| bounty_moved | from_seat, to_seat | yes |
| bounty_claimed | from, to, refund | yes (warhead-free torpedoes; else pending for 03-06) |
| status | seat, hull, depth, alive, place, accuracy | yes (beat boundaries; place 0 for drones) |
| duel_announce / duel_start / duel_result | see game_event.gd | 03-06 |
| imploded | seat | yes |
| last_standing | seat | yes |
| match_end | standings | yes |

## Notes for later plans

- **03-06:** RewardMeter signals are already mirrored into events. Calling `meter.queue_prize(id)` emits REWARD_EARNED source "duel" or REWARD_QUEUED by itself, so do not emit them again. LANDED currently does `landed += 1` on the shooter at landing. Adjust that per the 03-06 plan (reflected payloads must not count). `request_fire` returns FIRE_NOTHING for any wreck at its top, so insert the debris branch before that check. METER for debris must set `debris: true` itself.
- **03-07:** Pass the judgment time (note time + error_s) as `t` and pass `t` to report_status for deterministic stamps. `PlayerState.approach_s` decides the Ghost/Depth window start, so set it before payloads land. Hull changes are not applied by MatchSim; apply BUFF_APPLIED Ballast `amount` yourself. Call `on_failed(seat, t)` when the hull fails. A hull of 0 alone does not eliminate.
- **03-09/03-10/03-11:** TARGET `mode` is the PlayerState.TargetMode int. METER fires per Perfect. The first beat (beat 0) emits an initial TARGET and STATUS for every seat. FIRE_PENDING (a second press while a launch waits) emits no event.
- **03-12:** `event_log` contains COLLISION {a, b}, LANDED, ABSORBED, BOUNTY_CLAIMED and IMPLODED. PlayerState stats are landed, reflected, absorbed, bounties, collisions and duels_won.
- **03-14:** `finish(t)` emits MATCH_END. Drones are not in `standings()`. A LAST_STANDING event exists only when one non-drone sub remained at a beat boundary (no event in training).

## Deviations from Plan

**1. [Rule 1 - Determinism] Inputs catch the referee up to their own time.** Without this, a beat processed in a later update() would be logged after an input that happened after it, and logs would differ between frame rates. Every public input runs `_advance(t)` first. Commit c05507c.

**2. [Rule 2] Optional `t` on report_status / cycle_target / set_target_mode.** report_status had no time parameter, so BOUNTY_MOVED / TARGET would otherwise carry a frame-dependent stamp. The new parameter is optional and trailing, so the 03-07 call shape still works. Commits c05507c, 4cbb3cf.

**3. [Rule 2] STATUS includes hull changes.** The spec trigger was place/alive/depth bucket, but a Miss changes hull without depth, which would leave the periscope hull segments stale. It is still at most once per beat per seat. Commit 4cbb3cf.

**4. Small rule choices that the plan left open** (all documented in code): no bounty holder at depth 0; drones excluded from bounty, standings and LAST_STANDING; wrecks get no bounty refund; a target that died before the launch beat leads to no_target refusal; `payload_span` gives exact float times next to the Vector2 `payload_window`; `GameEvent.ALL_TYPES` lists every type.

## Known Stubs

- `_on_judged_hook` is intentionally empty. Plan 03-06 fills it (warheads, Solo Duel).
- WARHEAD / REFLECTED / FIZZLED / DUEL_* are defined but not emitted yet. Plan 03-06 emits them.

## Self-Check: PASSED
