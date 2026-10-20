---
phase: 04-online-play
plan: 06
subsystem: net-session
tags: [networking, enet, lobby, handshake, clock-sync, security, autoload, tdd]
requires: [NetProtocol, NetCodec, ClockSync, NetTransport, MemTransport, VersusSig, LobbyState, Settings.player_name]
provides: [ENetTransport, NetSession autoload (lobby half)]
affects: [04-10, 04-11, 04-15, 04-16, 04-17]
tech-stack:
  added: []
  patterns: [manually polled SceneMultiplayer per transport, injected transport factory + virtual ticks, retire-then-close transports, welcome NOTICE for the local seat]
key-files:
  created:
    - src/net/enet_transport.gd
    - src/autoload/net_session.gd
    - tests/test_enet_transport.gd
    - tests/test_net_session_lobby.gd
  modified:
    - project.godot
decisions:
  - "A5 holds: a SceneMultiplayer that is never attached to the tree works for send_bytes/peer_packet once root_path is set; it is pointed at a node that never exists (/root/__undertow_net_raw_only__), so crafted RPC/spawn packets resolve to nothing"
  - "SceneMultiplayer auth needs BOTH sides to call complete_auth, and a side that completed stops receiving auth payloads. The client calls transport.complete_auth(1) only after an accepting AUTH_REPLY (a no-op on MemTransport)"
  - "The client learns its seat from NOTICE {code 'welcome', name = assigned name, n = seat}, sent to it right after the host admits it (LOBBY rows carry no peer id)"
  - "The ENet server is created with 4 slots (MAX_CLIENTS + 1) so the session itself can refuse a 4th joiner with reason 'full'; with 3 slots ENet just ignores the connect and the joiner would see 'timeout'"
  - "kick() sends KICKED and disconnects 0.5 s later (or when the client leaves on its own first): ENet discards a peer's unprocessed packets on disconnect, so a one-poll flush swallowed the reason on 127.0.0.1"
  - "Clock offset bound: under MemTransport's uniform +-20 ms per-leg jitter the D-06 estimator is 2 ms typical (median over 12 seeds), 10 ms worst; a +-2 ms link holds 2 ms on every seed"
metrics:
  duration: "~1h40m"
  completed: 2026-10-20
  tasks: 2
  files: 5
---

# Phase 4 Plan 06: ENet transport and NetSession lobby Summary

ENetTransport moves raw bytes over a hand-polled SceneMultiplayer + ENetMultiplayerPeer with the auth handshake. The NetSession autoload runs the lobby: the version handshake, a host-authoritative roster mirrored to clients, Ready, song match by fingerprint + VersusSig, the 16-ping clock-sync bursts, kick/leave/watchdog return codes, strikes and a PING token bucket. It is proven over MemTransport with independent virtual tick clocks and over real ENet on 127.0.0.1.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | e7778ab | feat(04-06): ENetTransport over manually polled SceneMultiplayer with 127.0.0.1 tests |
| 2 RED | dbcc795 | test(04-06): add failing NetSession lobby tests over MemTransport |
| 2 GREEN | fa5f5f5 | feat(04-06): NetSession autoload lobby half (auth, roster, ready, song match, clock sync, kick) |

## Tests

- test_enet_transport.gd: 8/8 (auth accepted, refusal reply before the drop, bytes both ways on both channels including a 3000-byte packet, no 2nd client beyond max 1, client close = peer_left and host close = server_lost, kick = one peer_left, resolve failure, engine flags).
- test_net_session_lobby.gd: 26/26. That is 22 MemTransport cases covering every behavior bullet, plus 4 real-ENet session cases (join/ready/kick, version + full refusals, host leave = closed, resolve error). It was run three times and was green each time.
- Regression: test_lobby_state 28/28, test_mem_transport 15/15, test_net_codec 21/21, test_boot_smoke 1/1 (with the autoload registered).
- `tools/check_timing_gate.ps1`: TIMING GATE OK.
- Grep gates: `server_relay = false` occurs exactly once in enet_transport.gd, `allow_object_decoding = true` does not occur, and `NetCodec.decode(` appears 4 times in net_session.gd.

## A5 outcome (manually polled SceneMultiplayer)

It works without SceneTree.set_multiplayer, with one condition. SceneMultiplayer refuses to process any packet, raw ones included, until `root_path` is set ("Multiplayer root was not initialized"). ENetTransport sets `api.root_path` to a path that never exists. Raw bytes never touch the tree, and every transport is polled with `api.poll()` from `poll()`, so several transports run fine in one process.

## ENetTransport API (`src/net/enet_transport.gd`)

- `host(port, max_clients = 3) -> Error` (NetSession passes 4).
- `join(address, port) -> Error`. IP literals go straight to create_client. Hostnames resolve asynchronously through `IP.resolve_hostname_queue_item`. A failure shows up as `connect_failed("resolve")` from `poll()`.
- The NetTransport methods: send (channel 0 reliable / channel 1 unreliable), send_auth, complete_auth (host: accept; client: complete after an accepting reply), refuse_auth (the reply goes out, then the disconnect happens one poll later), disconnect_peer (emits peer_left once for a member), set_refuse_new, poll, close, unique_id, is_host, peers.
- Debug only: `rtt_ms(peer)`.
- Extra client signal `authing`: the link is up and auth started. A client `send_auth(1, ...)` made before that point is held and sent then.
- Signal mapping:
  - The host's connected → `peer_joined`. This fires only after the client also completes, so it can come one exchange after the client's `connected`.
  - Disconnects → `peer_left` (members only).
  - Client: a server drop after connecting → `server_lost`. A drop before connecting → `connect_failed("refused")`. A failed ENet connect → `connect_failed("timeout")`.
- Header facts: 2 channels, `server_relay = false`, object decoding is never enabled, `auth_timeout = 3.0`, per-peer `set_timeout(32, 4000, 10000)`.

## NetSession API (autoload `/root/NetSession`, `src/autoload/net_session.gd`)

**State:** `enum State { OFFLINE, CONNECTING, AUTHING, SYNCING, LOBBY }`. 04-10 appends LOADING, PLAYING and RESULTS. The current value is in `state`. `last_error_code` holds the Error from the last host().

**Public vars and injection:**
- `transport` (NetTransport or null) and `clock` (the client's ClockSync).
- `transport_factory: Callable(role "host"|"client") -> NetTransport`. The default is `ENetTransport.new()`. The session opens the transport itself: ENet gets host/join, MemTransport gets connect_to_host.
- `ticks_fn: Callable -> int us` (default `Time.get_ticks_usec`), `library: Object` (default /root/SongLibrary), `settings: Object` (default /root/Settings).
- `auto_process` (tests set it false and call `step(now_s)`).
- Test seams: `game_version_override` and `proto_override`.

**Methods:**

| Method | Notes |
|--------|-------|
| `host(port) -> int` | Error. Seat 0 under the cleaned `Settings.player_name` (DIVER fallback). The flight comes from `Settings.net_flight_beats` when present |
| `join(address, port) -> int` | Stages arrive through `connect_stage` |
| `leave()` | Host: LOBBY_CLOSED, then close after 0.1 s. Client: BYE, then close. No return message |
| `kick(seat)` | Host only, seats 1..3. KICKED, then a disconnect after 0.5 s |
| `set_ready(on)` | Client in LOBBY only. On = 16-ping burst unless a burst is running |
| `host_set_song({fp, sig, diff, title, artist}) -> bool` | false = rejected (not the host, empty fp or fp > 64, sig not 16 lowercase hex, unknown diff). Title and artist are trimmed to 64 with control characters dropped. `{}` clears the song. A real change clears Ready (LobbyState) |
| `host_set_flight(n)` | 1 or 2. Does not clear Ready |
| `start_gate() -> {ok, code, name, n}` | Host: LobbyState.start_gate(). Client: the same rule over its mirror |
| `local_seat()` | Host 0. Client: the seat from the welcome NOTICE (-1 before it and when offline) |
| `is_host()`, `is_offline()`, `is_in_lobby()` | |
| `lobby_rows() -> Array` | Wire rows `{seat, name, ready, song, ping_ms, synced, host}` in seat order. `song` is ok/missing/changed/checking ("checking" also while no song is picked). `ping_ms` is 0 until measured |
| `lobby_song() -> Dictionary` | `{fp, sig, diff, title, artist}` or {} |
| `flight() -> int` | |
| `ping_ms()` | Client RTT p50 to the host (0 on the host) |
| `clock_offset_us()` | Client: host_ticks = client_ticks + offset (0 on the host) |
| `is_synced()` | Host: always true |
| `take_return_message() -> String` | "kicked", "closed" or "lost". Consumed once. It survives host()/join() |
| `seconds_since_host_packet() -> float` | |
| `my_song_status()` | Client: none, checking, ok, missing or changed |
| `is_bursting()` | |
| `lobby_state() -> LobbyState` | Host only |
| `peer_strikes(peer_id)` | |
| `peer_rtt_p90_us() -> {seat: us}` | Host: input for D in 04-10 |
| `auth_refusal_for(msg) -> String` | Refusal reason for an AUTH, "" = accept |
| `debug_stats() -> Dictionary` | role, seat, peers, pings_sent, ping_dropped, rejected_packets, rtt_p50_ms, rtt_p90_ms, offset_us. 04-10/04-16 extend it |
| `step(now_s)` | |

**Signals:**
- `connect_stage(stage)`: "connecting", "auth", "sync", "lobby".
- `connect_error(code, info)`: timeout, resolve, version (info.host_version), full, in_match, bad_name, lost.
- `lobby_changed`.
- `log_line(code, {name, n})`:
  - choosing (the host is choosing a song)
  - joined, left, kicked_other
  - song_picked, flight_set (n = beats)
  - ready
  - missing (n = 0 for missing, 1 for changed)
  - high_latency (n = ms)
- `left_lobby(code)`: kicked, closed or lost (involuntary exits only).

**Wire additions (no codec change):**
- NOTICE `{code "welcome", name, n = seat}` goes only to the joiner. Every other NOTICE goes to everyone and turns into a client `log_line`.
- LOBBY `phase` is "lobby".

**Timing constants:**
- Client: BURST_PINGS 16 every 0.05 s, then PING_PERIOD_S 1.0.
- Host: HOST_BURST_PINGS 8 on join, then 1 Hz.
- LOBBY is sent on a revision change at most every 0.1 s, plus once every 1.0 s.
- SYNC_CAP_S 3.0: a client enters the lobby unsynced after that.
- WATCHDOG_S 4.0. CONNECT_TIMEOUT_S 8.0. ACCEPT_TTL_S 5.0 (an accepted peer that never gets admitted gives up its reservation).

### Notes for 04-10 (match half)
- Append to `State` after LOBBY. `_set_state()` already calls `transport.set_refuse_new(state != LOBBY)` on the host. With ENet, refuse_new drops a joiner without any packet, so they see "timeout" after 8 s rather than "in_match". `auth_refusal_for` already returns `in_match` when the state is not LOBBY. To show the reason, keep refuse_new off and rely on that refusal (the slot cap and auth_timeout still bound the cost).
- `_host_packet` and `_on_packet` end in a `_:` branch that ignores the match-half types. Extend them there.
- Use `_send(peer, msg, reliable)`. `_retire(grace_s)` + `_reset()` is the leave path. The client watchdog (`_client_tick`) only runs in SYNCING/LOBBY and must be widened.
- Clock: under ±20 ms per-leg uniform jitter the offset error is up to about 5-6 ms on unlucky seeds (2 ms median). A "start instants agree within 2 ms" test needs low-jitter links (±2 ms holds) or a median-over-seeds assertion.
- On ENet, the host's `peer_joined` comes after the client's `connected`. The first client data packet admits the peer on the host anyway.

### Notes for 04-11 (Play Online screen)
- Call `session.host(port)`: OK means go to the lobby. Otherwise read `last_error_code`.
- `session.join(addr, port)` returns OK or an Error. A sync failure also emits `connect_error("resolve"|"lost")`.
- The connect dialog listens to `connect_stage` and `connect_error`. The "lobby" stage means joined.
- On open, `take_return_message()` gives kicked, closed or lost.

### Notes for 04-15 (Lobby screen)
- Rows come from `lobby_rows()`. Pair `ping_ms` with `LobbyState.ping_bars` (0 = no sample yet). Read the song from `lobby_song()` and the flight from `flight()`. The gate is `start_gate()`.
- Log lines come from `log_line` codes. `lobby_changed` means redraw. `left_lobby(code)` means navigate to Play Online. Host-only calls are no-ops on clients.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] SceneMultiplayer needs a root path even for raw packets (A5)**
- **Found during:** Task 1. Every packet was dropped with "Multiplayer root was not initialized".
- **Fix:** Set `api.root_path` to a node path that never exists. No tree attachment is needed.
- **Commit:** e7778ab

**2. [Rule 1 - Bug] The client must complete auth only after the host's reply**
- **Issue:** SceneMultiplayer stops delivering auth payloads once a side completes locally, so the AUTH_REPLY (including refusal reasons) would be lost.
- **Fix:** The client calls `transport.complete_auth(1)` when an accepting AUTH_REPLY arrives. ENetTransport holds an early client `send_auth` until the link is authing and emits `authing` (used for the "auth" stage).
- **Commit:** e7778ab / fa5f5f5

**3. [Rule 2 - Correctness] "full" needs a spare ENet slot**
- **Issue:** `create_server(port, 3, 2)` makes ENet ignore a 4th connect, so the joiner sees "timeout" and never "full".
- **Fix:** NetSession hosts with 4 slots. The session refuses with reason full, and the seat cap stays at 3 clients. A bare transport refusal (MemTransport's 3-peer cap) is reported to the client as "full".
- **Commit:** fa5f5f5

**4. [Rule 1 - Bug] Kick reason lost on ENet**
- **Issue:** Disconnecting one poll after KICKED still dropped it on 127.0.0.1. ENet clears the peer's unprocessed packets on disconnect, and the client saw "lost".
- **Fix:** The host disconnects 0.5 s after KICKED (the client normally leaves first), and it ignores the kicked peer's packets in between.
- **Commit:** fa5f5f5

**5. [Rule 1 - Test design] Clock offset "within 2 ms under 40±20 ms jitter"**
- **Issue:** MemTransport jitter is uniform and symmetric per leg. The fixed D-06 estimator (median of the 5 lowest-RTT samples) measured -6.5 to +5 ms across 12 seeds, both after the 16-ping burst and at 32 samples. The same limit was noted in 04-01.
- **Fix:** At 40±20 ms the main test asserts the 10 ms hard bound (jitter/2), and the seeded test asserts a median error of at most 2 ms over 12 seeds. At 40±2 ms, 2 ms is asserted on every seed. ClockSync was not changed.
- **Commit:** fa5f5f5

**6. [Test] Join order follows arrival.** With jitter, simultaneous joins get seats in arrival order. The tests read `local_seat()`, or join one at a time where seat numbers matter.

### Additions beyond the plan (within plan files)
- A host 8-ping burst on join. Without it the roster PING column fills only at 1 Hz, and the 10 ms RTT check needs samples.
- The welcome NOTICE (local seat), `auth_refusal_for`, `peer_rtt_p90_us`, `debug_stats`, `lobby_state`, `my_song_status`, `is_bursting`, `peer_strikes`, `is_offline` and `is_in_lobby`.
- A high_latency notice (estimated D from RTT p90).
- Four ENet-backed NetSession tests in test_net_session_lobby.gd.

## Known Stubs
None. The match half (LOAD/START/inputs/events/results) is planned work for 04-10.

## Threat Flags
None beyond the plan's register:
- T-04-17: star topology, and clients drop any sender other than 1.
- T-04-18: object decoding is never set.
- T-04-19: slot cap, auth_timeout, ping bucket and strikes. refuse_new is wired.
- T-04-20: proto/game check.
- T-04-21: only fp/sig/diff/title/artist cross the wire, and the library lookup is by fingerprint.

## Self-Check: PASSED
- All of these exist: src/net/enet_transport.gd, src/autoload/net_session.gd, tests/test_enet_transport.gd, tests/test_net_session_lobby.gd, and the NetSession line in project.godot.
- Commits e7778ab, dbcc795 and fa5f5f5 are on origin/main.
