---
phase: 04-online-play
plan: 13
subsystem: ui/versus
tags: [online, controller, NET-04, NET-05, D-03, D-13, D-19]
requires: ["04-05"]
provides:
  - "VersusController.setup_online(gp, chart, jcfg, spec): host and client backends"
  - "local_seat variable; match_sim (offline + host, null on clients)"
  - "online-only FIRE_REFUSED error blip; host finish() online keys + queue drain"
  - "net_tick(t), debug_net(), net_send Callable"
affects: ["04-14 (gameplay wiring: binds NetSession, calls net_tick + pump_match)"]
tech-stack:
  added: []
  patterns: ["backend injection behind Referee/EventChannel, views unchanged", "offline construction order preserved via shared private helpers"]
key-files:
  created: [tests/test_online_controller.gd]
  modified: [src/ui/versus/versus_controller.gd]
decisions:
  - "sim is typed Referee and channel EventChannel; existing tests reading vc.sim.event_log still compile (dynamic access) and pass unchanged"
  - "Online blip reasons are exactly [shielded, no_target] (REFUSAL_BLIP_REASONS); nothing/race stay silent, matching offline FIRE_SHIELDED/FIRE_NO_TARGET"
  - "The host's own fire also blips from FIRE_REFUSED (its queue returns FIRE_REMOTE), so every online PC uses the event path"
  - "Client finish() returns {} without touching anything (D-19)"
  - "Online names: players carry the real names (callsign); names[local_seat] is YOU"
metrics:
  duration: "~35 min"
  completed: 2026-10-20
  tasks: 2
  files: 2
---

# Phase 4 Plan 13: Online VersusController Summary

VersusController now runs as an offline match (unchanged), an online host (MatchSim behind a HostInputQueue, events through a NetHostChannel) or an online client (RemoteReferee proxy, NetClientChannel). The seat the PC drives is the `local_seat` variable. Online error blips come from FIRE_REFUSED. The host's finish() drains the queue and adds names, left flags and the online keys for the 04-12 results screen.

## setup_online(gp, chart, jcfg, spec)

| spec key | Type | Default | Use |
|----------|------|---------|-----|
| `role` | "host" / "client" | - | Picks the backend (`is_host`) |
| `local_seat` | int | 0 | Seat of the human rig and every view binding |
| `names` | PackedStringArray (or Array) by seat | [] | One PlayerState per entry (at most 4). The callsign is the real name; `names[local_seat]` is "YOU" |
| `seed` | int | 0 | MatchSim seed (host) |
| `flight` | int | 1 | `cfg.torpedo_travel_beats`, then `validated()` |
| `d_s` | float | 0 | Input delay D (HostInputQueue, finish drain) |
| `autoplay` | bool | false | Adds the autoplay human (`test_autoplay_human` works too) |
| `margins` | Dictionary {seat:int -> rtt_p90_s} | {} | Host only: `queue.set_net_margin(seat, HostInputQueue.margin_for(d_s, rtt))` |
| `song_len` | float | `ProgressTrack.song_length_of(chart)` | Client NetClientChannel ctx |

- **Host:** `host_channel` (NetHostChannel) is `channel`. `match_sim` = MatchSim(chart, cfg, jcfg, players, channel, seed). `queue` = HostInputQueue(match_sim, channel, d_s) is `sim`. The human rig is at local_seat on the queue.
- **Client:** `client_channel` = NetClientChannel(local_seat, `_song_now` -> `now`, {from_host, note_count, song_len, max_seat 3}) is `channel`. `remote` = RemoteReferee(local_seat, players, `_send_net`), bound to the channel, is `sim`. `match_sim` is null.
- **`net_send: Callable`** (client): `_send_net(msg)` forwards every INPUTS message from `remote.flush()` to it. An invalid Callable drops the message. It is read at flush time, so it can be set before or after setup_online.
- There are no bots, no drone and no training online. `versus` is true, so the periscope column and killfeed show the other seats.
- `human_rig.approach_s` comes from Settings as offline. The setter goes through the referee: immediate on the host queue, an IN_APPROACH item on a client.
- **Peers:** after setup_online, nothing has been broadcast yet (`broadcast_log` is empty, and the test asserts it). 04-14 can therefore `host_channel.add_peer(id)` for every client right after setup_online without missing events.

## Per frame (for 04-14)

Gameplay order is `pre_tick(t)`, `update(t)`, `controller.net_tick(t)`, then `NetSession.pump_match(t)`.
- `net_tick(t)`: on a client, `remote.set_now(t)`. On the host and offline it is a no-op.
- The controller never calls `queue.pump` or `remote.flush` during play. pump_match owns them: on the host it does `queue.push_item(seat, item)` for received INPUTS, then `queue.pump(t)`, then sends `host_channel.take_batches()`. On a client it does `remote.flush()` and passes received EVENTS to `client_channel.receive(msg)`.
- The only exception is `finish(t)` on the host, which calls `queue.pump(t + d_s)` before `match_sim.update(t)` and `match_sim.finish(t)`. After finish, pump_match still has to send the last batches (MATCH_END).

## fire / blip

- `fire(t)` online: `sim.request_fire(local_seat, t)` returns `FIRE_REMOTE` and makes no synchronous blip.
- `_on_event`: when online, a FIRE_REFUSED with `seat == local_seat` and reason in `REFUSAL_BLIP_REASONS = ["shielded", "no_target"]` calls `_error_blip()`. The host blips the same way for its own seat.
- Offline: the blip comes only from the FIRE_SHIELDED / FIRE_NO_TARGET return. The FIRE_REFUSED loopback event is ignored, so it never blips twice (tested).

## finish(t) data

Offline the data is unchanged. On the host, the same dictionary has these additions:
- Each row: `name` (the real callsign), plus `left: true` and `left_t` (the song time of the seat's first PLAYER_LEFT in `host_channel.broadcast_log`).
- `online: true`, `is_host`, `host_seat: 0`, `host_name` (seat 0's callsign), and `local_seat` set to the controller's local_seat.
- On a client, finish() returns `{}` and has no side effects.

## debug_net()

Offline it returns `{}`. Online it returns `{online, is_host, local_seat, d_s}` merged with:
- host: `late_inputs, rejected_future, pending, released_t`
- client: `last_seq, rejected_events, landed_late_last_ms, landed_late_max_ms, received`, plus `pending_inputs` and `ignored_foreign`

## Tasks

| Task | Commit | Notes |
|------|--------|-------|
| 1: backends, local_seat, online blip / finish | fa07638 | Offline guards green |
| 2: test_online_controller (7 cases) | 1feee00 | Host + client over MemTransport, 30 ms link, D 0.08 |

## Verification

- test_online_controller: 7/7. Covers: the client log equals the host broadcast log (40 s autoplay); the host MatchSim has seat 1 STATUS with accuracy > 0 and 0 late inputs; a client "nothing" refusal gives no blip, while a scripted "shielded" refusal gives exactly 1 client blip and 0 host blips; the host blips from its own refusal; offline gives exactly one blip from the return code; host finish has names and left/left_t; the finish drain picks up a STATUS stamped at end_t - 0.05 (hull 37.5, depth 123, streak 9); client finish returns {}; local_seat and human_rig.seat are 1.
- Offline guards were run unchanged: test_versus_controller_determinism 5/5 (30/144/1000 fps logs and harness equality), test_versus_gameplay 12/12, test_match_determinism 4/4, test_match_sim_determinism 2/2, test_training_drone 7/7 and test_versus_results 14/14.
- TIMING GATE OK.

## Deviations from Plan

None in behaviour. Two small additions:
- `test_host_blips_from_its_own_fire_refused` and `test_client_finish_returns_empty` cover the host's own refusal path and the D-19 client guard.
- The "event count > 100" sanity floor in the loop test was lowered to 50, because a two-seat perfect-autoplay match emits about 90 events in 40 s. The log-equality assertion itself is unchanged.

## Notes

- While this ran, `src/autoload/net_session.gd` (04-06, in progress in parallel) had a parse error that printed autoload errors at test start. My suites do not depend on it and pass. I did not touch it.
- An empty stray file `C:\Users\User\AppData\Local\Temp\claude\fin.txt` is left outside the repo; deleting it was blocked by the sandbox.

## Threat model

- T-04-39: the offline determinism suites were re-run unchanged after Task 1 (all green, byte-identical logs).
- T-04-40: the client's RemoteReferee is constructed for local_seat only, so foreign-seat calls are counted and dropped. In the test, the host binds the seat from the sender peer id (`push_item(1, ...)` only when `src == peer`).

## Self-Check: PASSED

- src/ui/versus/versus_controller.gd: FOUND (setup_online, local_seat, match_sim, FIRE_REFUSED)
- tests/test_online_controller.gd: FOUND
- fa07638, 1feee00: FOUND
