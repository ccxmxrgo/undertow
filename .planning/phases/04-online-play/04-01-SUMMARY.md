---
phase: 04-online-play
plan: 01
subsystem: net-core
tags: [networking, validation, security, clock-sync, transport, tdd]
requires: [GameEvent.ALL_TYPES, ChartData.time_sigs/solos, InputJudge.Judgment, PlayerState.TargetMode]
provides: [NetProtocol, NetCodec, ClockSync, NetTransport, MemTransport, MemTransport.Hub, VersusSig]
affects: [04-05, 04-06, 04-09, 04-10, 04-13, 04-17]
tech-stack:
  added: []
  patterns: [single validation choke point, strict per-type schemas, virtual-time transport hub, min-RTT median clock offset]
key-files:
  created:
    - src/net/net_protocol.gd
    - src/net/net_codec.gd
    - src/net/clock_sync.gd
    - src/net/net_transport.gd
    - src/net/mem_transport.gd
    - src/net/versus_sig.gd
    - tests/test_net_codec.gd
    - tests/test_clock_sync.gd
    - tests/test_mem_transport.gd
    - tests/test_versus_sig.gd
  modified: []
decisions:
  - "Wire times stay float64: var_to_bytes keeps doubles exactly (A1 holds, 123.456789012 round-trips with ==)"
  - "Message schemas are strict: unknown top-level keys are rejected (any field added later must be added to NetCodec)"
  - "AUTH.name is only loosely checked (String <= 32, no control chars) so the host can answer AUTH_REPLY reason bad_name; the host must run NetCodec.clean_name"
  - "A full 128-event EVENTS batch can exceed MAX_PACKET (16 KiB); the host channel must cut batches by encoded size (~12 KiB) as well as by count"
  - "MemTransport.Hub holds endpoints weakly; callers must keep every endpoint they create"
  - "`const P := NetProtocol` is not a constant expression in Godot 4.7; use NetProtocol.X directly or `const P := preload(\"res://src/net/net_protocol.gd\")`"
metrics:
  duration: "~2h (including a usage-limit pause)"
  completed: 2026-10-20
  tasks: 3
  files: 10
---

# Phase 4 Plan 01: Net core Summary

Built the node-free online networking core. NetProtocol holds the vocabulary and the D-23 caps. NetCodec is the single decode/validate choke point: it checks size before decoding, uses plain `bytes_to_var` only, and applies strict per-type schemas, a generic GameEvent rule set and a RESULTS row whitelist. A 10,000-case fuzz never crashes it. ClockSync takes the median offset of the 5 lowest-RTT samples. NetTransport is the seam, MemTransport is a seeded virtual-time hub with latency, jitter, loss, drop, stall and auth, and VersusSig is a 16-hex SHA-256 over time_sigs and solos.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | b4690fd | test(04-01): add failing NetCodec validation and fuzz tests |
| 1 GREEN | 2490865 | feat(04-01): NetProtocol vocabulary and NetCodec validation choke point |
| 2 RED | 246f9f8 | test(04-01): add failing ClockSync and MemTransport tests |
| 2 GREEN | f86e536 | feat(04-01): ClockSync estimator, NetTransport seam and MemTransport hub |
| 3 RED | 873da4f | test(04-01): add failing VersusSig tests |
| 3 GREEN | 2154f91 | feat(04-01): VersusSig song signature over time_sigs and solos |

## Tests

- test_net_codec.gd: 21/21. Covers round trips of every type, every rejection class, the real MatchSim log including MATCH_END with INF and finite eliminated_at, a real VersusController.finish() RESULTS, and the 10k fuzz (about 11 s).
- test_clock_sync.gd: 8/8. Within 2 ms over 10 seeds with asymmetric return-leg jitter.
- test_mem_transport.gd: 15/15.
- test_versus_sig.gd: 6/6.
- test_event_channel.gd: 10/10 (unchanged).
- `grep -c _with_objects src/net/*.gd` is 0 for every file. TIMING GATE OK.

## API for later plans (copy these)

### ctx for NetCodec.decode / validate
`{from_host: bool, note_count: int (0 = no chart, so JUDGED is rejected), song_len: float (<= 0 means MAX_SONG_S 1200 is used), max_seat: int (default 3)}`. Times must be finite and in `[-10, song_len + 30]`. decode returns `{}` or a deep copy of the message. `NetCodec.validate_event(e, ctx) -> bool`. `NetCodec.clean_name(v) -> String` returns the upper-cased name, or "" when invalid.

### Message types (String consts on NetProtocol; value = lowercase name)
Every key is required, and keys not listed are rejected.

| Const | Dir | Fields |
|-------|-----|--------|
| PING | both | seq:int>=0, c0:int |
| PONG | both | seq:int>=0, c0:int, h:int |
| AUTH | C->H | proto:int, game:String<=32, name:String<=32 (host must clean_name) |
| AUTH_REPLY | H->C | ok:bool, reason:"" or REASONS, host_version:String<=32 |
| READY | C->H | ready:bool, synced:bool |
| SONG_STATUS | C->H | status in SONG_STATES ["ok","missing","changed","checking"], synced:bool |
| LOADED / LOAD_FAIL / BYE | C->H | (none) |
| START_LATE | C->H | lead_ms:int (+-600000) |
| INPUTS | C->H | items: Array<=128 of items (below) |
| DONE | C->H | t: time |
| HEARTBEAT | C->H | song_t: time, ticks:int |
| LOBBY | H->C | roster: Array<=4 of {seat 0..max_seat (unique), name (name rule), ready:bool, song in SONG_STATES, ping_ms:int 0..99999, synced:bool, host:bool}; song: {} or {fp:String<=64, sig: 16 lowercase hex, diff in ["easy","medium","hard","expert"], title<=64, artist<=64}; flight:int 1..2; phase: token [a-z0-9_]{1,32} |
| NOTICE | H->C | code: token [a-z0-9_]{1,32}, name: "" or name rule, n:int |
| KICKED / MATCH_ABORT | H->C | reason in REASONS |
| LOAD | H->C | fp (non-empty, <=64), sig (16 hex), diff, seed:int, flight 1..2, roster: Array 1..4 of {seat (unique), name}, d_ms:int 0..1000, max_song_s: float 0..1200, autoplay:bool |
| START | H->C | host_start_ticks:int |
| ABORT_TO_LOBBY | H->C | reason in REASONS, name: "" or name rule |
| EVENTS | H->C | seq:int>=0, events: Array<=128 of GameEvent (validate_event). Cut batches by size too (<= ~12 KiB) |
| RESULTS | H->C | rows: Array<=4, medals: {int seat 0..3: Array<=8 of String<=32} (<=4 keys), last_standing_seat:int -1..3, local_seat: seat. Optional: title/artist String<=64, difficulty String<=16, seed:int, online:bool, is_host:bool, host_seat: seat, host_name: name rule |
| BACK_TO_LOBBY / LOBBY_CLOSED | H->C | (none) |

RESULTS row keys (<=16, `seat` required, unknown keys rejected): seat (0..max_seat), place int 1..4, alive bool, depth float>=0, hull float, accuracy float, max_streak int>=0, eliminated_at (finite or +INF), name (name rule), landed int>=0, reflected int>=0, left bool, left_t (finite float). Float fields accept int or float.

REASONS: version, full, in_match, kicked, host_left, proto, bad_name, load_timeout, start_late, load_fail, closed (consts R_*).

Name rule: 1-12 chars of `[A-Z0-9 _-]` after strip_edges plus to_upper.

### INPUTS item wire shape
`[kind:int, t:float (time range), seq:int>=0, ...args]`, with arity from `NetProtocol.IN_ARITY`:

| Kind | Value | Args |
|------|-------|------|
| IN_JUDGED | 0 | note_index:int 0..note_count-1, judgment (InputJudge.Judgment) |
| IN_EXTRA | 1 | judgment |
| IN_STRAY | 2 | - |
| IN_GHOST | 3 | - |
| IN_STATUS | 4 | hull, depth, accuracy (finite numbers), max_streak:int>=0 |
| IN_FIRE | 5 | - |
| IN_CYCLE | 6 | - |
| IN_TARGET_MODE | 7 | mode:int (PlayerState.TargetMode), locked:int -1..3 |
| IN_FAILED | 8 | - |
| IN_APPROACH | 9 | approach_s: finite, 0..10 |

### Event rule (validate_event)
- type is in GameEvent.ALL_TYPES (read at runtime, so the 27 types incl. PLAYER_LEFT/DUEL_LIVE are covered), t is finite, and there are <= 24 String keys.
- Values are scalars (int, bool, String<=32 with no control chars, or float), Arrays<=16 of scalars or flat dicts, or flat dicts (<=8 keys, String or int keys, scalar values). Max depth is 3.
- Keys seat/from/to/target/sender/winner must be an int -1..3 at every level.
- Floats must be finite. The exception is eliminated_at/until_t/immune_until/*_until, which may also be +INF or -INF. NaN is never allowed.

### ClockSync
`add(c0, h, c1)`, `offset_us()` (host = client + offset), `rtt_p50_us()`, `rtt_p90_us()`, `sample_count()`, `is_synced()` (>= 5), `reset()`. Consts: MAX_SAMPLES 32, BEST_N 5, MAX_RTT_US 2 s.

### NetTransport / MemTransport
- Signals: packet(peer, bytes), peer_joined(peer), peer_left(peer), auth_request(peer, bytes), auth_reply(bytes), connected, connect_failed(code: "timeout"|"resolve"|"refused"), server_lost.
- Methods: send(peer, bytes, reliable=true) (host: peer 0 = broadcast to members), send_auth, complete_auth, refuse_auth(peer, reply), disconnect_peer, set_refuse_new, poll(now_s), close, unique_id, is_host, peers. HOST_ID = 1.
- `MemTransport.Hub.new(seed)` provides make_host() (id 1), make_client() (2, 3, 4...), set_link(id, latency_s, jitter_s=0, loss=0), advance(now_s), drop_peer(id), stall(id), unstall(id), pending_count(), `now`, `log` ([due, src, dst, size, kind]) and `dropped`. The client calls `connect_to_host()` and then `send_auth(1, bytes)`.
- Semantics:
  - Data to or from an unauthenticated peer is discarded.
  - Host-side `complete_auth` and `disconnect_peer` emit peer_joined/peer_left synchronously. Everything else is emitted inside advance().
  - The host refuses `hello` when refuse_new is set or 3 peers are present (the client gets connect_failed("refused")).
  - With no answer, connect_failed("timeout") fires after CONNECT_TIMEOUT_S.

### VersusSig
`VersusSig.of(chart) -> String` returns 16 lowercase hex chars. Dictionary keys are sorted, and numbers are formatted "%.6f", so 4 and 4.0 hash the same.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `const P := NetProtocol` does not parse**
- **Found during:** Task 1 GREEN
- **Issue:** Godot 4.7 reports "Assigned value for constant P isn't a constant expression" for a class-name alias const, in both the codec and the RED test.
- **Fix:** The codec uses `NetProtocol.X` directly, and the test uses `const P := preload("res://src/net/net_protocol.gd")`.
- **Commit:** 2490865

**2. [Rule 1 - Bug, test] A 128-event EVENTS batch of real MatchSim events exceeds MAX_PACKET**
- **Found during:** Task 1 GREEN. Each event passed on its own, but the full batch encoded above 16 KiB.
- **Fix:** The test cuts batches at 12 KiB as well as at 128 items, matching the 04-05 plan ("chunking at 128 items and 12 KiB"). This is recorded as a decision for 04-05.
- **Commit:** 2490865

**3. [Rule 1 - Test design] The ClockSync 2 ms synthetic with purely uniform 0-60 ms return jitter is outside what median-of-5 can achieve**
- **Issue:** The expected 3rd-lowest extra delay of 32 uniform samples is about 5.5 ms, which gives about 2.7 ms of error. The estimator itself is fixed by D-06.
- **Fix:** The 2 ms test (10 seeds) uses realistic queueing: 25% of packets get 0-2 ms extra and the rest get 0-60 ms. A separate test bounds the pure-uniform case at 8 ms and checks the bias direction.
- **Commit:** 246f9f8 / f86e536

**4. [Rule 1 - Test] Test-side fixes in test_mem_transport**
- Client endpoints in the loop tests were dropped because the hub refs are weak, so the tests now keep them.
- Arrivals that happened during the send loop were missed, so the test now uses one stepped loop.
- **Commit:** f86e536

**5. Fuzz cost.** The first fuzz variant took 67 s because of 200-element arrays nested 5 deep. Large arrays now appear only at the top level and nesting is capped at 3, which takes about 11 s. Byte-level damage cases (truncation and bit flips) run every 40th iteration, because each one makes the engine log a decode error.

## Notes / Known limitations
- `bytes_to_var` on broken bytes prints engine `ERROR:` lines (marshalls.cpp). These are non-fatal, and decode returns {}. 04-06 should expect log noise from hostile peers. Strikes still apply.
- MemTransport has no host-side auth timeout (ENet's 3 s auth_timeout); 04-06's session should own that timer if it needs it in MemTransport tests.

## Threat Flags
None. There is no new surface beyond the plan's threat model (T-04-01..05 mitigated in NetCodec).

## Self-Check: PASSED
All 10 files exist, and commits b4690fd, 2490865, 246f9f8, f86e536, 873da4f and 2154f91 are on origin/main.
