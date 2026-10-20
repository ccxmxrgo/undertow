---
phase: 04-online-play
plan: 10
subsystem: net-session
tags: [networking, synced-start, match-link, disconnect, watchdog, results, tdd]
requires: [NetSession lobby half (04-06), HostInputQueue, RemoteReferee, NetHostChannel, NetClientChannel (04-05), NetCodec, ClockSync, MemTransport]
provides: [NetSession match half: start_match, LOAD/LOADED/START, lead_in_for_start, pump_match, DONE/RESULTS, back to lobby, host loss handling, debug_stats]
affects: [04-14, 04-15, 04-16, 04-17]
tech-stack:
  added: []
  patterns: [host-scheduled start in tick units (local_start = host_start - offset), per-peer input token bucket, frame-pumped inbox for inputs and events, DONE barrier with a tick deadline]
key-files:
  created:
    - tests/test_net_session_match.gd
  modified:
    - src/autoload/net_session.gd
decisions:
  - "refuse_new stays off in every state. Joiners during LOADING/PLAYING/RESULTS are refused by auth with reason in_match, so they see the reason instead of an ENet timeout. The plan text said set_refuse_new(true), but its own in_match test (and the 04-06 handoff) requires this"
  - "HEARTBEAT is client -> host only (NetProtocol.FROM_CLIENT; the codec rejects it from the host). The host computes each client's skew from HEARTBEAT (client ticks mapped through the host's ping clock). A client's skew_ms is its song_time against its own scheduled start. Clients are kept alive by host PINGs, which run at 2 Hz in a match (MATCH_PING_PERIOD_S 0.5) so link-weak (1 s) does not flicker"
  - "D is rounded to whole ms (LOAD.d_ms), and the host uses the same rounded value, so every peer has an identical d_s"
  - "lead_in_for_start: the first call decides. Late (< 0.5 s) or an unsynced clock gives -1 and sends one START_LATE. Later calls return the raw lead (or -1 if the first call was late) and never send anything"
  - "After the host's report_done(end_t), pump_match caps queue.pump at end_t + D (04-09: MATCH_END must be the last event; finish() pumps the same value again, which is idempotent)"
  - "host_send_results flushes pending EVENTS first, so MATCH_END reaches clients before RESULTS on the reliable channel. Only NetCodec RESULTS keys are sent. local_seat is set per recipient and is_host is false. Clients reject RESULTS whose local_seat is not their own"
  - "Overflowing input batches are cut to the bucket, and each overflowing batch counts as one strike (3 = disconnect, then the seat is dropped)"
  - "A client leaving during LOADING is remembered and its seat is dropped at bind_host_match. START waits only for live peers"
metrics:
  duration: "~45 min"
  completed: 2026-10-20
  tasks: 2
  files: 2
---

# Phase 4 Plan 10: NetSession match flow Summary

NetSession now runs a whole online match lifecycle. The host schedules a synced start (LOAD, LOADED barrier, START at host_now + 3 s, local_start = host_start - offset). A per-frame match link feeds rate-limited INPUTS into the HostInputQueue and EVENTS into the NetClientChannel. A lost client is eliminated and the match continues. A lost host ends the match cleanly on every client (MATCH_ABORT, server_lost or a 4 s watchdog). Then come the DONE barrier, per-client RESULTS and the return to the lobby. It is proven over MemTransport with independent tick clocks.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1+2 RED | 3f30293 | test(04-10): add failing NetSession match-flow tests over MemTransport |
| 1+2 GREEN | 9a028a2 | feat(04-10): NetSession match half (synced start, match link, disconnects, DONE/RESULTS, back to lobby) |

Both tasks touch the same two files. Their tests were written together first (RED), then the implementation landed in one GREEN commit.

## Tests

test_net_session_match.gd: 22/22 in about 4 s.
- **Start sync:**
  - Gate refusal.
  - LOAD and pending_match fields on both roles, with D from the formula and margins.
  - 3 tick origins (0, +2.0 s, +5.3 s) on 30 ± 10 ms links agree within 2 ms. Measured: 0.5 and 1.0 ms. A mutation run to 0.1 µs failed as expected.
  - 6 seeds: median ≤ 2 ms, worst ≤ 10 ms.
- **Aborts:** load_timeout (name TWO, Ready cleared, gate back to not_ready), START_LATE from a late lead_in call, START_LATE from an unsynced clock (ClockSync reset before START), load_fail.
- **in_match:** joins are refused with in_match in both LOADING and PLAYING.
- **Match link:**
  - INPUTS land in the host queue under the sender's seat.
  - A 300-item flood is cut to about 240 with 1-2 strikes. A second flood reaches 3 strikes, which disconnects the client and gives PLAYER_LEFT.
  - 300 events reach 2 clients equal to broadcast_log.
  - HEARTBEAT count and skew are within bounds.
- **Disconnects:**
  - A client drop gives IMPLODED + PLAYER_LEFT. The match continues, and the other client's log equals the host log.
  - Host leave() in a match gives MATCH_ABORT, so clients see host_left("host_left") and the return message "closed".
  - server_lost gives connection_lost and "lost".
  - A stall gives link_weak [true] after 1 s, then exactly one host_left("connection_lost") after 4 s.
- **Results:**
  - The DONE barrier holds with still_diving 2 → 1 → 0, and results_due fires exactly once.
  - Each client's RESULTS carries its own local_seat and is_host false.
  - The D + 3 s deadline holds.
  - Back to lobby clears Ready and keeps the song and flight; a second match can be gated.
  - Host leave() in RESULTS sends LOBBY_CLOSED, so clients get "closed".
- **debug_stats:** keys are present offline, on the host and on the client.

Regression: test_net_session_lobby 26/26, test_boot_smoke 1/1, test_online_controller 7/7, test_net_match_harness 7/7. `tools/check_timing_gate.ps1`: TIMING GATE OK. No pinned timing file was touched.

## Match API (src/autoload/net_session.gd)

**State:** `enum State { OFFLINE, CONNECTING, AUTHING, SYNCING, LOBBY, LOADING, PLAYING, RESULTS }`. START moves both roles from LOADING to PLAYING. host_send_results and a received RESULTS move them to RESULTS.

**Signals:**

| Signal | Who | When |
|--------|-----|------|
| `match_loading` | all | LOAD sent (host) / received (client). pending_match() is filled. Navigate to gameplay |
| `start_scheduled` | all | START sent / received. Call `lead_in_for_start()` once |
| `results_due(end_t)` | host | All live clients sent DONE and the host called report_done, or host_end + D + 3 s passed. Once |
| `results_received(data)` | client | RESULTS (type stripped, local_seat = own seat) |
| `returned_to_lobby` | all | BACK_TO_LOBBY |
| `match_aborted_to_lobby(code, name)` | all | load_timeout / load_fail / start_late. State LOBBY, Ready cleared |
| `host_left(kind)` | client | "host_left" (MATCH_ABORT) or "connection_lost" (server_lost / 4 s watchdog) in LOADING/PLAYING/RESULTS. The session is OFFLINE; take_return_message() is "closed" / "lost" |
| `link_weak_changed(weak)` | client | In a match, no host packet for > 1 s (true) / recovered (false) |

In LOBBY or RESULTS, a LOBBY_CLOSED still arrives as `left_lobby("closed")`. That is the host's leave() from RESULTS.

**Functions:**
- `start_match(opts := {}) -> String`: "" ok, "gate" (start_gate not ok), "not_host". opts: `seed` (int), `max_song_s` (float, 0 = full), `autoplay` (bool).
- `pending_match() -> Dictionary` ({} outside LOADING/PLAYING/RESULTS). Keys:
  - role, local_seat
  - names (PackedStringArray by seat; a gap seat is ""), seats (Array of roster seats)
  - fp, sig, diff, title, artist, seed, flight, d_s, max_song_s, autoplay
  - margins ({seat: rtt_p90_s} on the host, with seat 0 = 0.0; {} on clients)
- `report_loaded()`, `report_load_failed()`.
- `lead_in_for_start() -> float`: seconds to song_time 0, for `Conductor.begin(stream, lead)`. It returns -1 before START, when the clock was unsynced at START, or when the lead is < 0.5 s (START_LATE is sent once). The first call decides.
- `bind_host_match(queue: HostInputQueue, channel: NetHostChannel, note_count, song_len)`: adds every live client to the channel itself (04-14 does NOT need `host_channel.add_peer`). Seats that left during LOADING are dropped.
- `bind_client_match(remote: RemoteReferee, channel: NetClientChannel, note_count, song_len)`.
- `send_to_host(msg)`: use `Callable(NetSession, "send_to_host")` as `controller.net_send`.
- `pump_match(song_time)`: once per frame, after `controller.net_tick(t)`. NAN is fine before START.
- `still_diving() -> int`, `report_done(t)`, `host_send_results(data)` (pass the VersusController.finish dict as is), `host_back_to_lobby()`.
- `is_link_weak()`, `seconds_since_host_packet()`, `heartbeats_received()` (host).
- `leave()`: the host sends MATCH_ABORT in LOADING/PLAYING and LOBBY_CLOSED in LOBBY/RESULTS, then flushes for 0.1 s. A client sends BYE.

**debug_stats() keys:**
- role, seat, state, peers
- pings_sent, ping_dropped, rejected_packets
- rtt_p50_ms, rtt_p90_ms (host: worst client)
- per_peer [{seat, name, p90_ms, skew_ms}] (host)
- offset_us, horizon_ms, late_inputs, skew_ms
- landed_late_last_ms, landed_late_max_ms
- event_seq, link_weak

All of them are numeric or empty defaults when offline.

## Notes for downstream plans

- **04-14 (gameplay wiring):**
  1. On `match_loading`: build the chart from `pending_match()` (fp/diff via SongLibrary), then `controller.setup_online(gp, chart, jcfg, {role, local_seat, names, seed, flight, d_s, autoplay, margins})`.
  2. Bind: on the host, `bind_host_match(controller.queue, controller.host_channel, chart.notes.size(), song_len)`; on a client, `bind_client_match(controller.remote, controller.client_channel, ...)`, and set `controller.net_send = Callable(NetSession, "send_to_host")`.
  3. Then call `report_loaded()`, or `report_load_failed()` on any failure.
  4. On `start_scheduled`: `var lead := NetSession.lead_in_for_start()`. If lead < 0, wait for `match_aborted_to_lobby`. Otherwise call `conductor.begin(stream, lead)` with the intro forced to NONE.
  5. Each frame: `pre_tick`, `update`, `net_tick`, then `NetSession.pump_match(t)`.
  6. At the song end: `report_done(end_t)`. The host waits for `results_due(end_t)`, calls `data = controller.finish(end_t)`, then `NetSession.host_send_results(data)`; pump_match keeps running in RESULTS. Clients wait for `results_received(data)`.
  7. Handle `host_left(kind)` (show "host left" / "connection lost" and go to Play Online) and `link_weak_changed` (HUD hint).
  8. `max_song_s` and `autoplay` in pending_match are the 04-17 autotest switches.
- **04-15 (lobby screen):**
  - Start calls `NetSession.start_match()`, and every peer navigates on `match_loading`.
  - After `match_aborted_to_lobby(code, name)` or `returned_to_lobby`, the lobby is live again with Ready cleared. Show the abort code and name in the log.
  - The results screen's "back to lobby" button (host) calls `host_back_to_lobby()`.
- **04-16 (F3 overlay):** use the `debug_stats()` keys above. horizon_ms is D. skew_ms is debug only.
- **04-17 (autotest / smoke):** pass `start_match({"seed": s, "max_song_s": n, "autoplay": true})`. The same values reach every peer through LOAD.

## Deviations from Plan

**1. [Rule 1 - Spec conflict] refuse_new is kept off during the match.** The plan said `set_refuse_new(true)` in start_match, but also requires joiners in LOADING/PLAYING to be refused with "in_match". MemTransport and ENet with refuse_new drop the joiner before auth, so the joiner would see "full"/"timeout". The 04-06 handoff recommended this. `_set_state` now always sets refuse_new false. Auth refuses with in_match, and a late `peer_joined` outside LOBBY is disconnected.

**2. [Rule 1 - Codec constraint] Host HEARTBEAT is not sent.** HEARTBEAT is client → host only in NetProtocol/NetCodec, so a host HEARTBEAT would be rejected. To stay within this plan's files, host-side skew comes from client HEARTBEATs, the client skew comes from its scheduled start, and the client keep-alive is the host's 2 Hz PING during a match.

**3. [Rule 2] Extra safety.** START_LATE is honoured only within 5 s of the scheduled start. RESULTS with a foreign local_seat are rejected on clients. The client EVENTS inbox is capped at 4096 messages. INPUTS outside PLAYING are ignored.

**4. [Additions]** `seats`, `title` and `artist` in pending_match. `is_link_weak()`, `link_weak_changed`, `heartbeats_received()`. A `state` key and a `link_weak` key in debug_stats.

## Known Stubs
None.

## Threat Flags
None beyond the plan's register:
- T-04-29: token bucket, strikes, disconnect at 3 (tested).
- T-04-30: the seat comes from `_lobby.seat_of(sender)` only.
- T-04-31: watchdog, server_lost and MATCH_ABORT are each tested.
- T-04-32: START_LATE leads to an abort, never an unsynced start.
- T-04-33: the host sets local_seat per recipient, and the client validates RESULTS through NetCodec plus a seat check.

## Self-Check: PASSED
- src/autoload/net_session.gd, tests/test_net_session_match.gd and tests/test_net_session_match.gd.uid exist.
- Commits 3f30293 and 9a028a2 are on origin/main.
