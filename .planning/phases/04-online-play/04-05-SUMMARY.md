---
phase: 04-online-play
plan: 05
subsystem: versus-net
tags: [referee, horizon-queue, event-channel, networking, tdd]
requires: [Referee, MatchSim.set_approach, GameEvent.PLAYER_LEFT, GameEvent.DUEL_LIVE, NetProtocol, NetCodec]
provides: [HostInputQueue, RemoteReferee, NetHostChannel, NetClientChannel]
affects: [04-09, 04-13]
tech-stack:
  added: []
  patterns: [horizon-ordered input release, per-peer seq batching with size cut, seq-ordered exactly-once client delivery]
key-files:
  created:
    - src/versus/host_input_queue.gd
    - src/versus/remote_referee.gd
    - src/versus/net_host_channel.gd
    - src/versus/net_client_channel.gd
    - tests/test_host_input_queue.gd
    - tests/test_remote_referee.gd
    - tests/test_net_channels.gd
  modified: []
decisions:
  - "HostInputQueue.released_t starts at NetProtocol.TIME_MIN_S (-10.0), not -INF, so a drop_seat before the first pump still stamps finite IMPLODED/PLAYER_LEFT times"
  - "Release order is (t, seat, seq, arrival); arrival is the final tiebreak so the sort is total"
  - "Host-local non-finite t (cycle_target/set_target_mode NaN defaults) is stamped with the last pump host_song_time"
  - "Local set_approach is immediate (raw + min(margin, 0.3)); network IN_APPROACH is released in order, then takes the same margin path"
  - "DUEL_LIVE is only emitted when at least one seat has a live % (empty pct dicts are skipped); the queue's duel_live clears when no duel runs"
  - "LANDED late probe keys on the event's `to` field (LANDED has no `seat`; `to` is the target)"
  - "NetClientChannel.send is a no-op: clients run no rules"
metrics:
  duration: "~40 min"
  completed: 2026-10-20
  tasks: 2
  files: 7
---

# Phase 4 Plan 05: Host queue, client proxy and net event channels Summary

One MatchSim can now be driven online. HostInputQueue feeds it every seat's time-stamped inputs in (t, seat, seq) order behind the D horizon. RemoteReferee serializes a client's own inputs into INPUTS batches. NetHostChannel fans events out with per-peer seq batches. NetClientChannel applies them in order, exactly once, after validating each one again. All four are RefCounted, need no transport, and get a send Callable or batches injected by the caller.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | 0bf9ac9 | test(04-05): add failing HostInputQueue tests |
| 1 GREEN | b61f75e | feat(04-05): HostInputQueue horizon-ordered host referee |
| 2 RED | 52b78af | test(04-05): add failing RemoteReferee and net channel tests |
| 2 GREEN | 01c9d6b | feat(04-05): RemoteReferee client proxy and host/client net event channels |

## Tests

- test_host_input_queue.gd: 10/10.
  - Order independence: 3 seats, 40 s. The host seat goes through the local methods and the other two through push_item with random delays below D, shuffled per frame. The result is byte-identical to the in-order run and to MatchSim fed directly in sorted order.
  - Also covered: release waiting for the horizon, the late clamp (non-decreasing event t), the future drop, bad items, the STATUS clamps, update as a no-op, drop_seat ordering (IMPLODED, then PLAYER_LEFT, then a no-op on the second drop), the margin cap, and DUEL_LIVE at most once per beat inside the duel window only.
- test_remote_referee.gd: 7/7. Covers every IN_* kind and its seq, the foreign-seat ignore, NaN, INF and below -10 stamping, 300 items chunked 128/128/44 with each chunk decoding as valid, and duel_live/duel_active from events.
- test_net_channels.gd: 7/7.
  - Host: local emit first, per-peer seq, late peers, and cuts at 128 events and at 12 KiB (every message encodes to 12 KiB or less and decodes).
  - Client: delivery order 1,3,3,2,1,5,4,5 produces all 15 events in order exactly once. Invalid events are skipped and counted, and the LANDED late probe works.
  - End to end: HostInputQueue to NetHostChannel to wire encode/decode to NetClientChannel gives a client received_log equal to the host broadcast_log, ending in PLAYER_LEFT.
- Guards: test_versus_controller_determinism 5/5, test_match_sim_determinism 2/2, test_match_determinism 4/4, test_referee 7/7, test_sub_rig 18/18, test_event_channel 10/10, test_solo_duel 14/14, test_net_codec 21/21 and test_versus_gameplay 12/12 all pass. TIMING GATE OK.

## API (for 04-09 net match harness / 04-13 session wiring)

### HostInputQueue extends Referee
- `HostInputQueue.new(sim: MatchSim, channel: EventChannel, d_s: float)`. It sets `players = sim.players`. Pass the same channel the MatchSim was built with (normally a NetHostChannel).
- `push_item(seat, item: Array)` takes a NetCodec-validated `[kind, t, seq, ...args]`. The seat comes from the session (peer id to seat). Items are ignored for unknown or dropped seats, bad arity or kind, or a non-finite t. Items with t > last pump time + FUTURE_INPUT_S (2 s) are dropped and add 1 to `rejected_future`. Before the first pump the reference time is 0.0.
- The Referee input methods (host's own seat, or any local seat) queue with an auto seq per seat. `request_fire`/`inject_fire` return FIRE_REMOTE and `cycle_target` returns -1.
- `pump(host_song_time)`: horizon = t - D. It releases the sorted items with t <= horizon (late ones clamped to `released_t`), then calls `sim.update(horizon)`, then emits any due DUEL_LIVE. Call it every host frame with the live song time.
- `update(t)` is a no-op on purpose. SubRig/VersusController may keep calling it.
- `drop_seat(seat, reason)` with reason "disconnected" or "left": IMPLODED at `released_t`, then PLAYER_LEFT `{seat, reason}`.
- `set_net_margin(seat, margin_s)` and `static margin_for(d_s, rtt_p90_s) -> min(d + rtt_p90/2 + 0.033, 0.3)`. `set_approach(seat, s)` applies s + min(margin, 0.3) straight away.
- `duel_live(seat)` returns the last DUEL_LIVE pct (-1.0 otherwise). `duel_active()` delegates to the sim.
- Fields: `sim`, `channel`, `d_s`, `released_t`, `late_inputs`, `rejected_future`, `extra_log`.
- `debug_stats() -> {late_inputs, rejected_future, pending, released_t}`.

### RemoteReferee extends Referee
- `RemoteReferee.new(seat: int, players: Array[PlayerState], send_fn: Callable)`. send_fn receives `{type: INPUTS, items}`, and the caller encodes and sends it reliably.
- `flush()` runs once per frame and sends chunks of at most 128 items. `set_now(t)` and `update(t)` record the song time. Call set_now before flush so NaN/INF times get stamped with the current time.
- `bind(channel)` takes the client's NetClientChannel and drives `duel_live` (from DUEL_LIVE) and `duel_active` (DUEL_START/DUEL_LIVE, reset by DUEL_RESULT/MATCH_END).
- Fields: `seat`, `ignored_foreign`, `pending_count()`.

### NetHostChannel extends EventChannel
- `add_peer(id)`, `remove_peer(id)`, `peers()`. `send(e)` emits locally, appends to `broadcast_log`, and fills every outbox.
- `take_batches() -> {peer_id: Array[{type: EVENTS, seq, events}]}`. seq starts at 1 per peer. Cuts are at 128 events and CUT_BYTES = 12288 encoded. Outboxes are cleared, and a peer with nothing pending maps to [].
- Merged log: because PLAYER_LEFT/DUEL_LIVE go through the same channel, `broadcast_log` already equals the sim.event_log and extra_log interleaved in emission order.

### NetClientChannel extends EventChannel
- `NetClientChannel.new(local_seat, now_fn: Callable -> float song time, ctx: NetCodec ctx {from_host: true, note_count, song_len, max_seat})`.
- `receive(msg)` takes a decoded EVENTS message. Duplicates are dropped, gaps are buffered (MAX_BUFFERED 256), and each event is checked with `NetCodec.validate_event`.
- Fields: `last_seq`, `rejected_events`, `landed_late_last_ms`, `landed_late_max_ms`, `received_log`.
- `debug_stats() -> {last_seq, rejected_events, landed_late_last_ms, landed_late_max_ms, received}`.

## Deviations from Plan

**1. [Rule 1 - Spec mismatch] The LANDED target field is `to`, not `seat`**
- **Found during:** Task 2
- **Issue:** The plan's behavior block says "LANDED events whose `seat` (the target)". GameEvent.LANDED is `{id, from, to, ...}` and has no `seat` key.
- **Fix:** The probe keys on `to`.

**2. [Rule 1 - Test] The DUEL_LIVE test pushed seat-1 items too early**
- **Issue:** Items 20 s ahead were pushed before the first pump, so they were correctly rejected as future items. The test now pushes them shortly before their time.

**3. [Rule 2] Extra defensive handling**
- push_item re-checks the kind, arity and finiteness of each item, even though NetCodec has already checked them.
- RemoteReferee forces STATUS floats to be finite and clamps finite t to at least -10.
- NetClientChannel ignores malformed messages and caps its out-of-order buffer.

## Known Stubs
None.

## Threat Flags
None. T-04-13..16 are mitigated as planned: the seat comes from the caller, the future drop and late clamp protect the time walk, STATUS values are clamped, and batch caps, duplicate drops and client revalidation guard the client.

## Self-Check: PASSED
All 7 files exist. Commits 0bf9ac9, b61f75e, 52b78af and 01c9d6b are on origin/main.
