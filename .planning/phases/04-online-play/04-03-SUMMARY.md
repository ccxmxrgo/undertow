---
phase: 04-online-play
plan: 03
subsystem: net-models
tags: [settings, lobby, addresses, version, tdd]
requires: []
provides:
  - "application/config/version = 0.7.0 (D-21 handshake + Play Online version line)"
  - "Settings [net]: player_name, player_name_set, net_last_address, net_last_port, net_flight_beats"
  - "Settings.clean_player_name / clean_address / profile_path_from_args (static)"
  - "--net-profile=<n> per-process settings file (Pitfall 10)"
  - "LobbyState (class_name) roster model + start_gate + wire snapshot"
  - "NetAddress (class_name) classify / display_list / invite_address / host_port"
affects: [04-net-session, 04-online-menu, 04-lobby-screen, 04-settings-online-section]
tech-stack:
  added: []
  patterns: [pure RefCounted models, untrusted-input validation with defaults, revision counter for change-only sends]
key-files:
  created:
    - src/net/lobby_state.gd
    - src/net/net_address.gd
    - tests/test_settings_net.gd
    - tests/test_lobby_state.gd
    - tests/test_net_address.gd
  modified:
    - project.godot
    - src/autoload/settings.gd
decisions:
  - "A SONG status of 'checking' counts as not OK in the start gate and reports code 'missing' (first non-OK row 'changed' reports 'changed')"
  - "LobbyState does its own light name sanitising (trim, 12 chars, empty -> DIVER); callers should pass Settings.clean_player_name output"
  - "NetAddress classifies all routable IPv6 as 'other' (only 100.64.0.0/10 is Tailscale, per UI-SPEC 8.1)"
metrics:
  duration: "~25 min"
  completed: 2026-10-20
  tasks: 2
  files: 7
---

# Phase 4 Plan 03: Settings net keys, version, LobbyState and NetAddress Summary

Game version 0.7.0, validated [net] Settings keys with a `--net-profile=<n>` per-process settings file, a pure LobbyState roster model with the UI-SPEC 9.1 start gate and a validated wire snapshot, and a NetAddress classifier that lists Tailscale addresses first.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | c958117 | test(04-03): add failing tests for Settings net keys and --net-profile |
| 1 GREEN | 10190b0 | feat(04-03): game version 0.7.0, Settings [net] keys and --net-profile |
| 2 RED | e487c5c | test(04-03): add failing tests for LobbyState and NetAddress |
| 2 GREEN | bc498c2 | feat(04-03): LobbyState roster model with start gate and NetAddress classifier |

## Settings API (autoload `Settings`, section `[net]`)

- Vars: `player_name` ("DIVER"), `player_name_set` (false), `net_last_address` (""), `net_last_port` (47474), `net_flight_beats` (2).
- Consts: `DEFAULT_PLAYER_NAME`, `PLAYER_NAME_MAX` (12), `DEFAULT_NET_PORT`, `NET_PORT_MIN`/`NET_PORT_MAX`, `ADDRESS_MAX` (64), `FLIGHT_BEATS` ([2, 1]).
- `static clean_player_name(s) -> String`: upper-case, keep `[A-Z0-9 _-]`, collapse spaces, trim, cap 12; "" if nothing is left.
- `static clean_address(s) -> String`: trim; "" if longer than 64 or any char outside `a-zA-Z0-9.-:[]`.
- `static profile_path_from_args(args) -> String`: `--net-profile=<1-2 digits>` gives `user://settings_net<n>.cfg`, otherwise "".
- `_ready()` applies the profile path before `load_from(save_path)`. `_load_net(cfg)` runs after `_load_versus`. Bad values fall back to the defaults.
- No setters were added. UI plans assign the var, then call `save_to(save_path)` and emit `settings_changed`, or add a setter in their own plan.

## LobbyState API (`src/net/lobby_state.gd`)

- `LobbyState.new(host_name)` puts the host at seat 0 with peer id 1, ready, synced, and song_status "none" ("ok" once a song is set).
- Row: `{seat, peer_id, name, ready, song_status, ping_ms (-1 = no samples), synced, host}`. Read rows with `row(seat)` (a copy, or {}) and `rows()` (occupied rows in seat order).
- `add_peer(peer_id, name) -> seat|-1` gives the lowest free seat 1..3. It returns -1 when the lobby is full, the peer is already seated, or the id is <= 0 or 1. Names are de-duplicated as DIVER2, DIVER3 and stay within 12 chars.
- `remove_peer(peer_id) -> seat|-1` returns -1 for the host. Also `seat_of(peer_id)`, `peer_of(seat)` (0 when the seat is open), `present_count()` and `is_full()`.
- Row setters: `set_ready(seat, bool)` (ignored for the host), `set_song_status(seat, s)` (s is one of none/ok/missing/changed/checking), `set_ping(seat, ms)` and `set_synced(seat, bool)`.
- `set_song({fp, sig, diff, title, artist}) -> bool`: a change to fp, sig or diff clears every client's Ready and sets their status to "checking". A title/artist-only update does not reset Ready. `{}` clears the song.
- `set_flight(1|2) -> bool` does not clear Ready.
- `revision` goes up on every real change, so the session sends LOBBY only when something changed.
- `start_gate() -> {ok, code, name, n}` checks in this order:
  1. `need_players`
  2. `need_song`
  3. `syncing`
  4. `missing` or `changed`
  5. `not_ready`
  6. `ok`

  `name` is set when exactly one sub fails the rule, and `n` is the number that fail. A "checking" status counts as `missing`.
- `to_wire() -> {rev, flight, song, rows}` and `apply_wire(d) -> bool`. apply_wire treats the snapshot as untrusted: it checks types and ranges, requires host row 0, and changes nothing if any check fails.
- Static helpers: `ping_bars(ms)` (4/3/2/1 bars, 0 when there are no samples) and `is_high_latency(d_s, rtt_ms)` (`d + rtt/2000 + 0.0167 > 0.250`).

## NetAddress API (`src/net/net_address.gd`)

- `classify(ip)` returns "tailscale" (100.64.0.0/10), "lan" (10/8, 172.16/12, 192.168/16) or "other". It returns "" for loopback, 0/8, 169.254/16, multicast, ::1, ::, fe80::/10, ff00::/8 and unparsable strings. It strips `%scope` and brackets first.
- `display_list(addrs) -> Array[Dictionary]` returns up to 4 `{ip, kind}` entries ordered tailscale, then lan, then other. Order is stable within a kind and duplicates are dropped.
- `invite_address(addrs)` returns the first Tailscale address, else the first LAN address, else "".
- `host_port(ip, port)` returns "ip:port", with IPv6 in brackets.

## Verification

- test_settings_net: 18/18 passed
- test_settings: 25/25 passed
- test_settings_roundtrip: 17/17 passed
- test_library_settings: 12/12 passed
- test_lobby_state: 28/28 passed
- test_net_address: 8/8 passed
- `tools/check_timing_gate.ps1`: TIMING GATE OK

## TDD Gate Compliance

Both tasks have a `test(...)` RED commit followed by a `feat(...)` GREEN commit. RED was confirmed: the Settings suite failed at discovery because the helpers were missing, and the Lobby and Address suites referenced classes that did not exist yet. No refactor commit was needed.

## Deviations from Plan

None. The plan was executed as written. A few additions go beyond the listed behaviour but stay within the plan's files:
- LobbyState: `row()`, `rows()`, `present_count()`, `is_full()`, the "none" song status and validated `apply_wire`.
- NetAddress: `host_port()`.
- Settings: an `_whole()` helper so that a float such as 1.5 for flight is rejected.

## Known Stubs

None.

## Self-Check: PASSED

- All 5 created files and both modified files are present.
- Commits c958117, 10190b0, e487c5c and bc498c2 are on origin/main.
