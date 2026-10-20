# Phase 4: Online Play - Research

**Researched:** 2026-10-20
**Domain:** Godot 4.7.2 high-level networking (ENet + SceneMultiplayer raw packets), host-authoritative referee over the existing `MatchSim`, clock sync and scheduled audio start, lobby, friend connectivity without servers
**Confidence:** HIGH for the codebase integration (read from source), HIGH for the Godot networking API (official 4.7 docs fetched this session), MEDIUM for the latency numbers (derived, not measured on real friends' links yet), MEDIUM for third-party VPN plan details (vendor pages change)

## Summary

Phase 3 already built the part that is usually hard. `MatchSim` is a pure, song-time-driven referee. It decides every rule from time-stamped inputs and announces each outcome as a `GameEvent` dictionary through the `EventChannel` seam. Views read only events. `SubRig` judges locally and only reports judgments to the referee. So Phase 4 does not need lockstep, rollback or state sync. Run **one `MatchSim` on the host**, feed it every seat's time-stamped inputs **in global song-time order behind a small fixed input horizon**, and broadcast the event log to the clients. Each client keeps its own audio clock, its own judge and its own hull exactly as today. The network never touches hit judgment. The pinned timing-core files are not needed for any of this. `Conductor.begin(stream, lead_in_s)` already starts `song_time` at `-lead_in_s` from the moment of the call, so a synced start is just "call `begin` with lead_in = time until the scheduled local instant".

Transport: Godot's built-in `ENetMultiplayerPeer` under `SceneMultiplayer`. Use **raw `send_bytes` / `peer_packet`** instead of `@rpc`, so the transport can be swapped for an in-memory simulated-latency transport in headless tests. Friends connect over **Tailscale** (free Personal plan, up to 6 users and unlimited devices, verified on tailscale.com/pricing today). The host invites friends into their tailnet or shares the host machine with them. Plain LAN and manual UDP port forwarding are documented fallbacks. ZeroTier (free plan, 10 devices) is the second option. Nothing needs a server, a paid plan, or an account created by Claude. Each friend creates their own free account in the VPN app.

The main design finding is a latency-budget problem in TORP-04 ("telegraph at least 1 beat before a payload lands"). Offline, the flight time is 1 beat and the alert appears at launch. Online, the target learns of a launch only after horizon D plus one-way latency L, typically 100-230 ms. So with a 1-beat flight the telegraph is always shorter than 1 beat. **Online matches should use `torpedo_travel_beats = 2`.** This is already a `VersusConfig` tunable that the host sends. Everything else fits inside the existing 1-beat ease-in of `PayloadStack`, so torpedoes still land on the intended beat. Rules stay exact at any latency. Lateness only ever affects presentation.

**Primary recommendation:** host-authoritative `MatchSim` with a fixed input horizon (D = 60-200 ms, measured at lobby time). Use ENet via `SceneMultiplayer.send_bytes` behind a `NetTransport` seam. Do NTP-style tick-offset sync and start each peer with `Conductor.begin(lead_in = until scheduled instant)`. Use 2-beat online torpedo flight. Document Tailscale as the friend path. Test with an in-memory latency/jitter transport plus 4 local Godot processes.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hit judgment, hull, combo, score | Each client (local `SubRig`: VersusJudge/VersusHull) | — | Core value: timing is local, against the local audio clock. Never networked. |
| Song clock | Each client (`Conductor`, pinned) | Host schedules the start instant only | Audio clock is the source of truth, and each peer keeps its own. |
| Rules (meter, bag, fire, shields, collisions, bounty, duels, elimination, standings, medals) | Host (`MatchSim`, the same object as offline) | — | Must be decided once and identically for everyone (03-SPEC "host-decidable"). |
| Input ordering and the late-input policy | Host (`HostInputQueue`) | — | Determinism needs one global song-time order. |
| Event fan-out | Host (`NetHostChannel` extends `EventChannel`) | Client (`NetClientChannel`) | Views keep reading only `EventChannel.received`. |
| Applying a payload to my board | Target client (`SubRig._on_event` / `PayloadStack.install`) | — | Only the target sees its highway. The host decides that it landed, and the target draws it. |
| Clock offset estimation | Client | Host answers pings | NTP-style. Uses the client's monotonic ticks only. |
| Lobby roster, ready flags, song match | Host (`LobbyState` in `NetSession`) | Clients display and request | Host is the authority for match flow. |
| Transport, handshake, size limits, rate limits | `NetSession` autoload plus `NetTransport` | — | One place for every security check. |
| Friend connectivity (NAT) | Outside the game (Tailscale/ZeroTier/LAN/port forward) | — | A zero-code, no-server path (NET-07). |

## User Constraints

No CONTEXT.md exists, because the user is asleep and asked for autonomous progress. The binding constraints come from the orchestrator brief, CLAUDE.md, PROJECT.md and REQUIREMENTS.md:

### Locked (from orchestrator brief / project docs)
- Godot **4.7.2-stable**, standard build, GDScript only. No C#, no GDExtension needed.
- **Timing gate:** `src/core/conductor.gd`, `clock_model.gd`, `input_judge.gd`, `hull_score.gd` stay byte-identical to **72e21ce**. `src/core/judge_config.gd` stays identical to **2c2e54c**. Verify with `powershell -NoProfile -File tools/check_timing_gate.ps1` (the script is the source of truth; STATE.md's "fbcf994" line is stale). Every plan runs the gate.
- Hit judgment stays local. Only events cross the network (PROJECT.md, ARCHITECTURE anti-pattern 2).
- 2-4 players, peer-hosted. **No paid servers, no server the user must operate, no account created by Claude.** Friends install a free app and create their own accounts if the chosen path needs one.
- Pausing online matches is out of scope (REQUIREMENTS "Out of Scope").
- Anti-cheat is out of scope. The host does basic sanity checks.
- Never rename or remove a `GameEvent` type or field (game_event.gd header). Additions are allowed.
- Security enforcement on, ASVS level 1, block on high (config.json).
- The research doc commit only, no source edits in this step.

### Claude's Discretion (resolved below as D-xx defaults)
Transport, authority model, clock sync, start scheduling, flight time online, horizon, disconnect policy, lobby flow, connectivity docs, test strategy.

### Deferred (out of scope for Phase 4)
- Steam networking / GodotSteam (a `MultiplayerPeer` swap later. The `NetTransport` seam keeps it cheap).
- Host migration (PROJECT/ARCHITECTURE: host leaving ends the match).
- Song file transfer between peers (friends copy songs themselves, and the lobby only checks the hash).
- Mixed difficulties in one match (`MatchSim` takes one chart. This needs per-seat charts, a large change).
- Bots filling empty online seats (possible later, since MatchSim supports it, but not needed for NET-01..07).
- Spectators, late join, reconnect into a running match.
- In-game chat, voice (friends use Discord).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NET-01 | Host a lobby; 1-3 others join from their own PCs over the internet | ENetMultiplayerPeer `create_server(port, 3, 2)` / `create_client(addr, port, 2)`, SceneMultiplayer auth handshake, Tailscale path (D-01, D-02, D-14, D-15) |
| NET-02 | Lobby shows ready state and song hash match | `chart.id` fingerprint `u{imp}.{24hex}.{diff}` (SONG-05) plus a versus signature over time sigs/solos, LobbyState roster (D-11, D-12) |
| NET-03 | Songs start in sync (clock-synced, host-scheduled) | NTP min-RTT offset estimator, `START{host_start_ticks}`, `Conductor.begin(stream, lead_in = local_start - now)` without editing the pinned Conductor (D-05, D-06, D-07) |
| NET-04 | Torpedo/hull/elimination/score events reach others mid-song and land on the intended beat | Host-authoritative MatchSim plus input horizon, event fan-out, 2-beat online flight, approach margin, latency budget table (D-03, D-04, D-08, D-09, D-10) |
| NET-05 | Disconnect = eliminated, match continues | `peer_disconnected` → `sim.on_failed(seat, horizon_t)` plus additive `PLAYER_LEFT` event (D-16) |
| NET-06 | Host leaving ends match cleanly with message | `MATCH_ABORT` before close, `server_disconnected`, app watchdog plus ENet timeout, HOST LEFT dialog (D-17) |
| NET-07 | Documented working way through home routers | Tailscale (primary), ZeroTier, LAN, UDP port forward, all free. A docs file plus in-game help (D-14, D-15) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Godot 4.x stable, GDScript preferred. Windows desktop first.
- Networking: 2-4 players online, peer-hosted, no paid dedicated servers.
- Timing accurate to the +-50 ms range, with the audio clock as the source of truth (not frame time).
- Use the high-level multiplayer API (STACK.md). Do **not** use `MultiplayerSynchronizer`/`MultiplayerSpawner` for the highway, and do **not** use network-synchronized hit judgment.
- GSD workflow: edits only through GSD commands. This research step changes no source.
- Tests: gdUnit4 6.2.1 via `tools/run_tests.ps1` (headless needs `--ignoreHeadlessMode`, already in the script). New `class_name` scripts need `godot --headless --import` before tests (01-02 lesson).

## Phase 3 Architecture Facts This Phase Builds On (read from source)

| Fact | Where | Consequence for Phase 4 |
|------|-------|-------------------------|
| `MatchSim` decides every rule from time-stamped inputs: `on_judged(seat, note_index, judgment, t)`, `on_extra_judged`, `on_stray`, `on_ghost_hit`, `report_status`, `request_fire`, `inject_fire`, `cycle_target`, `set_target_mode`, `on_failed`, `update(t)`, `finish(t)` | `src/versus/match_sim.gd` | These 11 calls are exactly the client→host input vocabulary. |
| Every input calls `_begin(t)`: `_advance(t)` then `_now = t`. `_advance` only moves forward, so **an input with t earlier than already-processed beats sets `_now` backwards**. | match_sim.gd:438 | The host must feed inputs in non-decreasing t and clamp late ones (`t_eff = max(t, processed_t)`). This is the reason for the input horizon (D-04). |
| Launch = next whole beat after the press, resolved per beat (collisions, then seat order), arrival `torpedo_travel_beats` later, arrivals in id order | `_queue_launch`, `_resolve_launches`, `_commit_launch` | A fire stamped at the true press time gets offline-identical launch semantics if it reaches the host before the horizon passes. |
| `LANDED` carries `arrive_t, active_start, end_t, seed = hash([match_seed, id])`. `payload_span` uses the **target's `approach_s`** (Ghost Notes/Depth Charge start at the first beat at or after `arrive_t + approach_s`). | `_arrive`, `payload_span` | The host needs each client's `approach_s` (scroll speed) as an input. The host can add a network margin to it (D-09). |
| Warheads = the first `warhead_count` base notes at or after `arrive_t`, marked on the target when `TORPEDO_LAUNCH` arrives. Reflect is decided from the target's judgments of those notes. | `pick_warheads`, `_warhead_judged` | The rules stay correct even if the marks show late. With a 2-beat flight the marks arrive well before the notes reach the strike line. |
| `PayloadStack` effects ease in over `[arrive_t, arrive_t + 1 beat]` as pure functions of song time. `install()` replaces by id. Crossed Wires switches the **input map at the end of the in-slide** (arrive + 1 beat). | `src/versus/payload_stack.gd` header, `input_map` | A `LANDED` received up to ~1 beat late still produces the same input semantics as offline and only a small visual jump into the ease. |
| `SubRig` judges locally and calls `sim.*` directly (`var sim: MatchSim`). It applies `TORPEDO_LAUNCH`/`LANDED`/`WARHEAD`/`PAYLOAD_END`/`BUFF_*` for its own seat from the channel. | `src/versus/sub_rig.gd` | The client needs a referee stand-in with the same input methods that serializes them. The host needs one that queues them (D-03). |
| `VersusController` builds the `LoopbackChannel` plus `MatchSim`, runs actors in global song-time order (`advance_to`, TICK_S = 5 ms grid), and uses synchronous return codes from `request_fire` for the error blip | `src/ui/versus/versus_controller.gd` | The online client must use the `FIRE_REFUSED` event for the blip (D-13). The controller needs a backend injection point (D-03). |
| `LoopbackChannel.latency_s` holds events until `update(t)` reaches `e.t + latency_s` | `src/versus/loopback_channel.gd` | Views are already proven against delayed events. This can be reused in tests. |
| The live telegraph test asserts that the alert is visible at `launch_t` and at least 1 beat before `arrive_t` | 03-14-SUMMARY, `tests/test_versus_gameplay.gd` | TORP-04 must be re-proved online with latency (D-08). |
| `chart.id` = `ChartImporter.fingerprint(...)` = `"u%d.%s.%s"` (importer version, 24 hex SHA-256 of mapping version, difficulty, length to 0.1 s, tempo map, notes). It does **not** include `time_sigs` or `solos`. | `src/core/chart_importer.gd:108`, `song_library.gd:221` | This is good as the lobby key (SONG-05). But MatchSim also reads `time_sigs` (bar lengths) and `solos` (duels), so add a versus signature (D-11). Only the host runs MatchSim, so a mismatch would only break client-side predictions and visuals. Still, check it. |
| `Conductor.begin(stream, lead_in_s)` starts `song_time = -lead_in_s` at `Time.get_ticks_usec()` of the call and schedules audio so stream position 0 is heard at song_time 0 (with output latency and calibration offset). Without valid audio, `ClockModel` runs on the system clock. | `src/core/conductor.gd` (pinned) | A synced start needs **no pinned-file edit**. Headless multi-process tests run on the tick clock. |
| `Time.get_ticks_usec()` counts from **this process's engine start** | Godot semantics | Raw ticks are never comparable across processes or PCs. They must always go through the estimated offset. |
| Gameplay calls `conductor.begin` only in `_begin_count_in()` with `IntroTimeline.lead_in_seconds(...)` (clamped 0.6-4.0 s), after an optional skippable goggles intro | `src/ui/gameplay.gd:246` | The online start path must replace the intro timing with the scheduled instant (D-07). |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ENetMultiplayerPeer` (built-in) | Godot 4.7.2 | UDP transport with reliable-ordered and unreliable channels | Built in. Works over any IP path (Tailscale/ZeroTier/LAN). Channel and transfer-mode control. `create_client` accepts an FQDN or IPv4/IPv6 address [CITED: docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html] |
| `SceneMultiplayer` (built-in) | Godot 4.7.2 | Peer lifecycle, auth handshake, raw packets | `send_bytes(bytes, id, mode, channel)` plus the `peer_packet(id, packet)` signal, `auth_callback`/`send_auth`/`complete_auth` with `auth_timeout` (default 3.0 s), `refuse_new_connections`, `server_relay` (default true), `allow_object_decoding` (default false) [CITED: docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html, page shows "Godot Engine 4.7 documentation"] |
| `ENetPacketPeer` (built-in) | Godot 4.7.2 | RTT statistics, timeouts | `get_statistic(PEER_ROUND_TRIP_TIME / _VARIANCE)`, `set_timeout(timeout, timeout_min, timeout_max)` ms, `ping_interval` default 500 ms [CITED: docs.godotengine.org/en/stable/classes/class_enetpacketpeer.html] |
| `var_to_bytes` / `bytes_to_var` (built-in) | Godot 4.7.2 | Message encoding | Never use the `_with_objects` variants. Plain Variants only. [ASSUMED: standard Godot 4 API, names unchanged in 4.7] |
| gdUnit4 | 6.2.1 (already vendored) | Tests | Existing project runner `tools/run_tests.ps1` [VERIFIED: codebase] |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| Tailscale (free Personal plan) | Friend connectivity through home routers and CGNAT | Primary NET-07 path. $0, non-commercial, up to 6 users, unlimited user devices [VERIFIED: tailscale.com/pricing, fetched 2026-10-20]. Device sharing is on all plans; shared machines accept incoming connections only [CITED: tailscale.com/kb/1084/sharing] |
| ZeroTier (free plan) | Alternative overlay | 10 devices, 1 network on the free plan [CITED: zerotier.com/pricing via search, MEDIUM] |
| Godot `UPNP` class (built-in) | Optional automatic port mapping on the host | Only as a "Try automatic port forward" helper. Many routers have UPnP off, and it fails under CGNAT [ASSUMED] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ENet | `WebSocketMultiplayerPeer` | TCP has head-of-line blocking (a clock-sync ping stuck behind a retransmit inflates RTT samples). Its only real benefit is browser builds, which are not a target. Reject. |
| ENet | `WebRTCMultiplayerPeer` | Gives real NAT punching, but it **requires a signaling server**, and TURN for symmetric NAT needs a hosted relay. That breaks the "no server to operate" constraint. Copy-paste SDP signaling is possible but awful UX. Reject for v1. |
| ENet | GodotSteam `SteamMultiplayerPeer` | Best UX (relay plus invites), but everyone needs Steam, it needs an AppID (480 only for testing), and an extra GDExtension. Deferred. The `NetTransport` seam makes it a later swap. |
| `send_bytes` raw packets | `@rpc` functions on an autoload | RPC needs node paths, a scene tree and identical node layouts. It cannot be driven by an in-memory transport in pure tests. Raw bytes plus our own codec keeps one validation choke point. Reject RPC for game traffic. |
| Host-authoritative referee | Replicated deterministic sim on every peer (lockstep-like) | Every peer would need the horizon delay on its own inputs anyway (same feel). Divergence then needs desync detection and resolution, there are 4x more places to break determinism, and results could disagree. Reject. |
| Host-authoritative referee | Rollback | Rollback of rhythm board effects means visible re-simulation of payloads. It is massive complexity for no gain, because the events are beat-quantized. Reject. |

**Installation:** none. Every networking component is built into Godot 4.7.2. No addons, no packages.

## Package Legitimacy Audit

No external packages are installed in this phase (engine built-ins only). slopcheck was not run because there is nothing to check.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed:** none. **Packages flagged:** none. Tailscale/ZeroTier are end-user apps that friends install themselves. The game does not depend on or bundle them.

## Recommended Decisions (orchestrator defaults)

| ID | Decision | Default | Rationale / Notes |
|----|----------|---------|-------------------|
| **D-01** | Transport | `ENetMultiplayerPeer` under `SceneMultiplayer`. **2 channels**: 0 = reliable-ordered (lobby, inputs, events), 1 = unreliable (clock pings, heartbeats). Server `create_server(port, 3, 2)`, client `create_client(addr, port, 2)`. | Built in, UDP, works over every free connectivity path. Pings on their own unreliable channel are never stuck behind a reliable retransmit. |
| **D-02** | Message layer | All game traffic uses `SceneMultiplayer.send_bytes` / `peer_packet` through a `NetTransport` interface (`ENetTransport` real, `MemTransport` in-memory with virtual-time latency/jitter/loss). No `@rpc`. One `NetCodec.decode()` choke point. | Testable headless without sockets, and one place for validation. A Steam swap later only touches `ENetTransport`. |
| **D-03** | Authority model | **Host-authoritative:** the host runs the only `MatchSim`. Clients run no rules. They send inputs and apply events. Introduce a small `Referee` base class (`RefCounted`) declaring the input methods SubRig/VersusController call. `MatchSim extends Referee` (one-line change, behaviour identical). Add `HostInputQueue extends Referee` (host: queue → MatchSim) and `RemoteReferee extends Referee` (client: serialize → host). `SubRig.sim` is typed `Referee`. `VersusController` gets a backend injection (offline Loopback+MatchSim, online host, online client). | Keeps the Phase 3 promise ("the Phase 4 host runs the same object") with no rules duplicated. Type-safe with GDScript static typing. |
| **D-04** | Input ordering | Host processes all inputs (including its own local seat's) through `HostInputQueue`, sorted by `(t, seat, seq)`, and releases them only when `t <= horizon = host_song_time - D`. Each frame the host calls `sim.update(horizon)` after draining. **Late input** (`t < last released t`): process at `t_eff = last released t`, count it in `late_inputs` (debug overlay). Never drop. | Restores the offline invariant "the referee never sees time run backwards". Fair: the host's own inputs wait the same D. Late inputs only degrade, they never desync (there is only one sim). |
| **D-05** | Horizon value D | Fixed per match at START: `D = clamp(max_peer(rtt_p90/2) + 33 ms + 20 ms, 60 ms, 200 ms)` from lobby RTT samples. Sent in START. It never changes mid-song. | 33 ms covers one frame of poll delay on each side at 60 fps, and 20 ms is margin. Changing D mid-song would reorder inputs. |
| **D-06** | Clock sync | NTP-style ping/pong on channel 1 (unreliable): client sends `{seq, c0}` with local `Time.get_ticks_usec()`, host replies `{seq, c0, h}`, client receives at `c1`. `rtt = c1 - c0`, `offset = h + rtt/2 - c1` (host = client + offset). Keep the last 32 samples. Estimate = **median offset of the 5 lowest-RTT samples**. Burst 16 pings at 50 ms on join and on Ready, then 1 Hz while in the lobby. During the match send a 2 Hz heartbeat `{song_time, ticks}` used **only** to measure skew (debug), never to correct audio. | Min-RTT filtering removes queueing and frame-poll asymmetry. Ticks are per-process, so the offset is mandatory even on one PC. ARCHITECTURE anti-pattern 6 forbids seeking audio. |
| **D-07** | Synced start | Host sends `LOAD{fingerprint, versus_sig, difficulty, seed, cfg, roster, D}`. Each client builds the chart via `SongLibrary.build_chart` and the Gameplay run (intro forced to `IntroTimeline.Mode.NONE` online) and replies `LOADED`. Host waits for all (timeout 15 s, then back to the lobby with a message) and sends `START{host_start_ticks = host_now + 3.0 s}`. Each peer computes `local_start = host_start_ticks - offset` and calls `conductor.begin(stream, (local_start - Time.get_ticks_usec()) / 1e6)` (the host uses offset 0). The countdown UI keys off song_time (negative) as it does today. | No edit to the pinned Conductor. 3 s covers worst RTT plus the scene build. Abort if the computed lead-in is < 0.5 s (the START arrived too late): the client reports `START_LATE` and the host aborts to the lobby. |
| **D-08** | Online torpedo flight | Host sets `cfg.torpedo_travel_beats = 2` for online matches (lobby option "Torpedo flight: 2 beats (default) / 1 beat (LAN)"). Offline stays 1. | TORP-04 needs at least 1 beat of telegraph on the target. The target sees TORPEDO_LAUNCH at `launch_t + D + L + frame` (~100-230 ms), so a 1-beat flight can never give a full beat online. A 2-beat flight gives at least 1 beat whenever `D + L + frame <= 1 beat` (300 ms at 200 BPM). See the latency budget. |
| **D-09** | Overlay lead (Ghost Notes / Depth Charge) | Host stores `PlayerState.approach_s = reported approach_s + net_margin(seat)`, with `net_margin = D + L_seat_p90 + 33 ms` (capped 0.3 s). MatchSim is unchanged. | `payload_span` then starts overlay notes later, so their spawn (top of highway) happens after the target received LANDED. No pop-in. Zero MatchSim changes. |
| **D-10** | Landing prediction | **None in v1.** Clients install payloads when LANDED arrives. All windows are in song time, the ease-in is 1 beat, and Crossed Wires' input switch is at arrive + 1 beat, so a 100-230 ms late arrival is mostly invisible and rule-exact. The debug overlay shows `landed_late_ms`. Add target-side prediction from TORPEDO_LAUNCH only if UAT shows a visible jump. | Prediction needs cancel paths (Decoy, in-flight collision with a 2-beat flight). It is not worth the risk before measuring. |
| **D-11** | Song match key | Lobby key = `chart.id` (SONG-05 fingerprint, already per difficulty and importer version) **plus** `versus_sig` = first 16 hex of SHA-256 over `time_sigs` and `solos` (computed at runtime in `src/net/`, no chart_importer edit). A client "has the song" iff some library entry has that fingerprint for the chosen difficulty and the built chart's versus_sig matches. Songs are never referenced by path over the network. | The fingerprint excludes time sigs and solos, which MatchSim uses. Comparing chart data instead of audio bytes is cheap (no 30 MB hashing). |
| **D-12** | Lobby flow | Host picks song and difficulty from the library (reuse the MatchSetupScreen song list). Each player toggles Ready. Rows show NAME, PING, SONG (OK / MISSING / CHANGED) and READY. **Start** is enabled when at least 2 players are present and every present player is Ready with the song OK. The host can kick. Seats: host = 0, clients 1..3 in join order. Max 4. `refuse_new_connections = true` from LOAD until back in the lobby. | Matches the NET-02 wording. A song change clears every Ready. |
| **D-13** | Client-side feedback that offline gets synchronously | Error blip on `FIRE_REFUSED{seat == me, reason shielded/no_target}`. The meter, reward and target readout already come from events. `duel_live` on clients: add an additive `DUEL_LIVE{solo, pct: {seat: pct}}` host event at most once per beat while a duel runs. The client's `RemoteReferee.duel_live(seat)` returns the last value. | Keeps views unchanged (they already bind to the channel). A GameEvent addition is allowed. |
| **D-14** | Primary friend connectivity (NET-07) | **Tailscale.** The host adds friends to their tailnet (free Personal plan, up to 6 users), or uses "Share" on the host machine. Friends join by the host's `100.x.y.z` address (or MagicDNS name). Fallbacks, in this order: **ZeroTier** (free, 10 devices), **same LAN**, **router UDP port-forward** of the game port to the host PC (does not work under CGNAT). Optional in-game "Try UPnP" button on the host screen. | All free. No server operated by the user. Accounts are created by each friend themselves, never by Claude. |
| **D-15** | Default port and address entry | Default UDP port **47474** (editable). The Join screen takes an address (IPv4/IPv6/hostname) and a port. The last used values are saved in Settings. The host screen shows the host's local IPv4 addresses and highlights any `100.64.0.0/10` (Tailscale CGNAT range) address as "Tailscale address - give this to friends". | One copyable string. 47474 is not a well-known port [ASSUMED: no common conflict]. |
| **D-16** | Disconnect mid-match (NET-05) | Host on `peer_disconnected(id)`: map id → seat, enqueue `on_failed(seat, t_eff)` at the current horizon time, then emit the additive event `PLAYER_LEFT{seat, reason: "disconnected"}`. Drop that seat's pending inputs. Results label the seat "LEFT". The match continues. If only the host remains alive, normal LAST_STANDING applies. A client whose own connection drops gets the same treatment as host-left (D-17). | Reuses the existing elimination path (IMPLODED → wreck → standings). No new rules. |
| **D-17** | Host leaves (NET-06) | Deliberate quit: host broadcasts `MATCH_ABORT{reason: "host_left"}` (reliable), flushes for 100 ms, then closes the peer. Clients: on `MATCH_ABORT`, `server_disconnected`, or an **app watchdog (no packet from the host for 4 s)** → stop the conductor, show a modal "HOST LEFT - the match ended" with the last known standings from STATUS events, and a single "Back to Menu" button. Also set the ENet timeout on the server peer to `set_timeout(32, 4000, 10000)`. | The watchdog bounds detection even when the host crashes or loses the network. ENet's default timeouts are much longer [ASSUMED: ENet defaults 32 / 5000 / 30000 ms]. |
| **D-18** | Online pause / restart | No pause and no restart online. Esc opens a non-pausing "Leave match?" overlay (Conductor keeps running, input stays live behind it, matching the Phase 3 wreck behaviour). Leaving = disconnect (host: D-17, client: D-16 on the host). | REQUIREMENTS out of scope: "Pausing during online matches". |
| **D-19** | End of song and results | Each client sends `DONE{t}` when its song ends. Host waits for all living connections' DONE or `host_end + D + 3 s`, then `sim.update(end_t)`, `sim.finish(end_t)` and broadcasts MATCH_END plus a `RESULTS{rows, medals, last_standing_seat}` message (built like `VersusController.finish`). Clients show VersusResultsScreen with `local_seat = my seat`. Buttons: host "Back to Lobby" (everyone returns to the lobby, same roster) and "Menu". Clients "Leave". | Medals and standings are computed once, on the host. Results show identically on every PC. |
| **D-20** | Display names | New Settings `player_name` (1-12 chars, `[A-Z0-9 _-]`, upper-cased, default "DIVER"). Asked once on the first Play Online. The host de-duplicates by appending `2`, `3`, and so on. Shown wherever offline shows callsigns ("YOU" for the local seat). | Phase 3 D-21 promised a name setting in Phase 4. |
| **D-21** | Version handshake | `SceneMultiplayer.auth_callback`: the client sends `{proto: 1, game: ProjectSettings application/config/version, name}` via `send_auth`. The host checks proto and game equality, lobby phase, and room (at most 3 clients), then `complete_auth` or `disconnect_peer` with a reason packet first. `auth_timeout = 3.0`. | Different builds can differ in rules or charts. Refusing early gives a clear message. |
| **D-22** | Topology | Star through the host. `server_relay = false`. Clients never address each other. | Smaller attack surface, simpler validation, and the host is the single authority. |
| **D-23** | Batching and sizes | Client sends at most one input batch per frame (an array of tuples) on channel 0. Host sends at most one event batch per frame per peer with a per-peer `seq`. Hard caps: packet <= 16 KiB (reject larger before decoding), batch <= 128 items, strings <= 32 chars, arrays inside events <= 16 (warheads) / 4 (rows). Keep typical packets < 1200 bytes (Tailscale MTU 1280). | Normal traffic is about 10-40 events/s total. Caps bound decoder cost from a hostile peer. |
| **D-24** | Testing | (1) Pure unit tests (codec, validation fuzz, clock estimator, horizon queue). (2) `NetMatchHarness`: host plus 1-3 client rigs through `MemTransport` in virtual song time with latency/jitter/loss. (3) In-process ENet on 127.0.0.1 with manually polled `SceneMultiplayer` instances. (4) `tools/net_smoke.ps1` launches 4 real Godot processes (1 host plus 3 clients, autoplay) and compares JSON reports. (5) Human UAT over Tailscale on 2+ real PCs. | Covers determinism, transport and real-process behaviour, then the real internet. |

## Architecture Patterns

### System Architecture Diagram

```
CLIENT PC (seat k)                                   HOST PC (seat 0 + referee)
-------------------                                  ------------------------------------------
keyboard/pad                                         keyboard/pad
   |                                                    |
LaneInput --(press t = song_time_at(ticks))-->       LaneInput --> SubRig(0) (local judge/hull)
SubRig(k): VersusJudge/VersusHull/PayloadStack           |  judgments, fire, target, status, failed
   | judgments(note,j,t), fire(t), target(t),            v
   | status(hull,depth,acc,t), failed(t), approach_s  HostInputQueue  <--- decode+validate <--+
   v                                                     | release when t <= host_song - D       |
RemoteReferee --encode batch--> NetTransport ==========> | sorted (t, seat, seq); late -> clamp  |
   ^                            (ENet ch0 reliable)      v                                       |
   |                                                  MatchSim.update(horizon)  (unchanged rules)|
   |                                                     | GameEvents (event_log)                |
   |                                                     v                                       |
NetClientChannel <--decode+validate-- NetTransport <== NetHostChannel: emit locally + broadcast  |
   | received(e) (in seq order, dedupe)                  | (host views + SubRig(0) get same e)   |
   v                                                     v                                       |
SubRig(k)._on_event (install payload, warhead marks,  Views (HUD, periscopes, killfeed, alert)   |
buffs), views (same classes as offline)                                                          |
                                                                                                 |
Clock: ping{c0} --ch1 unreliable--> host stamps h --> pong{c0,h}; offset = median(min-RTT 5)     |
Start: host START{host_start_ticks} -> local_start = host_start - offset -> Conductor.begin(lead)|
Lifecycle: auth handshake -> lobby (ready/song) -> LOAD/LOADED -> START -> match -> DONE ->      |
           RESULTS -> lobby;  peer_disconnected -> on_failed + PLAYER_LEFT;  host gone -> abort  |
```

### Recommended Project Structure

```
src/net/                         # pure where possible (RefCounted), testable headless
  net_protocol.gd                # message type consts, PROTO=1, limits (D-23), port default
  net_codec.gd                   # encode/decode envelope; validate_* per message; never _with_objects
  clock_sync.gd                  # sample buffer + min-RTT median estimator (pure)
  net_transport.gd               # base: send(peer, bytes, reliable, channel); signals packet/joined/left
  enet_transport.gd              # SceneMultiplayer + ENetMultiplayerPeer (send_bytes / peer_packet)
  mem_transport.gd               # in-memory hub, virtual clock, latency/jitter/loss, seeded RNG
  lobby_state.gd                 # roster model: seat, name, ready, song_status, ping (pure)
  versus_sig.gd                  # versus_sig(chart) over time_sigs + solos (D-11)
src/versus/
  referee.gd                     # NEW base: on_judged/on_extra_judged/on_stray/on_ghost_hit/report_status/
                                 #   request_fire/cycle_target/set_target_mode/on_failed/set_approach/duel_live
  match_sim.gd                   # 'extends Referee' (only change)
  host_input_queue.gd            # NEW: D-04 horizon ordering into MatchSim
  remote_referee.gd              # NEW: client side, serializes inputs
  net_host_channel.gd            # NEW extends EventChannel: local emit + broadcast w/ seq
  net_client_channel.gd          # NEW extends EventChannel: seq order, dedupe, validate
  net_match_harness.gd           # NEW headless host+clients over MemTransport (tests)
  game_event.gd                  # ADD: PLAYER_LEFT, DUEL_LIVE (additive only)
src/autoload/
  net_session.gd                 # NEW autoload: host/join, auth, lobby msgs, clock sync, LOAD/START, watchdog
src/ui/online/
  online_menu.gd                 # Host / Join / name
  lobby_screen.gd                # roster, ready, song pick (host), start, messages
  net_debug_rows.gd              # F3 overlay rows: RTT, offset, D, late inputs, skew, landed_late_ms
docs/ONLINE_SETUP.md             # NET-07 friend guide (Tailscale, ZeroTier, LAN, port forward, firewall)
tools/net_smoke.ps1              # 4-process localhost smoke (D-24)
```

### Pattern 1: Horizon-ordered host referee (D-04)
**What:** queue every seat's input. Release in `(t, seat, seq)` order once `t <= host_song_time - D`. Then advance the sim to the horizon.
**Example:**
```gdscript
# Source: derived from MatchSim._begin/_advance semantics (src/versus/match_sim.gd:438-461)
class_name HostInputQueue extends Referee
var sim: MatchSim
var D: float
var _q: Array[Dictionary] = []   # {t, seat, seq, kind, args}
var _released_t := -INF
var late_inputs := 0

func push(seat: int, kind: int, args: Array, t: float, seq: int) -> void:
	_q.append({"t": t, "seat": seat, "seq": seq, "kind": kind, "args": args})

func pump(host_song_time: float) -> void:
	var horizon := host_song_time - D
	_q.sort_custom(func(a, b): return [a.t, a.seat, a.seq] < [b.t, b.seat, b.seq])
	while not _q.is_empty() and _q[0].t <= horizon:
		var it: Dictionary = _q.pop_front()
		var t: float = it.t
		if t < _released_t:
			late_inputs += 1
			t = _released_t          # never feed MatchSim a time in its past
		_released_t = t
		_apply(it, t)                # e.g. sim.on_judged(seat, idx, j, t)
	sim.update(horizon)
	_released_t = maxf(_released_t, horizon)
```
(Late items arrive with `t` already below the horizon. They are released on the next pump and clamped. Array comparison in GDScript compares element-wise. Use a stable explicit comparator in the real code.)

### Pattern 2: Scheduled start without touching the Conductor (D-07)
```gdscript
# Source: Conductor.begin contract (src/core/conductor.gd: "Start from song_time = -lead_in_s")
func begin_at_host_ticks(conductor: Conductor, stream: AudioStream, host_start_ticks: int, offset_us: int) -> bool:
	var local_start := host_start_ticks - offset_us          # host = client + offset
	var lead := float(local_start - Time.get_ticks_usec()) / 1e6
	if lead < 0.5:
		return false                                          # START_LATE -> host aborts to lobby
	conductor.begin(stream, lead)                             # song_time hits 0 at local_start
	return true
```

### Pattern 3: Clock offset estimator (D-06)
```gdscript
# Source: NTP offset/delay formulas (RFC 5905 simplified, one host timestamp)
class_name ClockSync extends RefCounted
var _samples: Array = []  # [rtt_us, offset_us]
func add(c0: int, h: int, c1: int) -> void:
	var rtt := c1 - c0
	if rtt < 0 or rtt > 2_000_000: return
	_samples.append([rtt, h + rtt / 2 - c1])
	if _samples.size() > 32: _samples.pop_front()
func offset_us() -> int:
	var s := _samples.duplicate(); s.sort_custom(func(a, b): return a[0] < b[0])
	var best := s.slice(0, mini(5, s.size())).map(func(x): return x[1]); best.sort()
	return best[best.size() / 2] if not best.is_empty() else 0
```

### Pattern 4: Validate-then-trust envelope (D-02, D-23)
```gdscript
func _on_peer_packet(id: int, packet: PackedByteArray) -> void:
	if packet.size() > NetProtocol.MAX_PACKET: return _strike(id)
	var v = bytes_to_var(packet)            # never bytes_to_var_with_objects
	var msg := NetCodec.validate(v)         # {} when malformed: type whitelist, field types, finiteness, ranges
	if msg.is_empty(): return _strike(id)   # 3 strikes -> disconnect_peer(id)
	var seat := _seat_of(id)                # seat ALWAYS from sender id, never from the message
	...
```

### Anti-Patterns to Avoid
- **Feeding MatchSim inputs as they arrive:** `_begin(t)` sets `_now` backwards for any t earlier than processed beats. That gives non-deterministic, host-favoured results. Use the horizon queue.
- **Comparing raw `Time.get_ticks_usec()` across peers:** it is per-process. Always go through `ClockSync`.
- **Seeking audio to fix skew:** forbidden (ARCHITECTURE anti-pattern 6). Log skew only.
- **`@rpc` with Dictionary args straight into game code:** it bypasses the single validation point. With `allow_object_decoding` accidentally true, it is an RCE-class risk [CITED: SceneMultiplayer docs warn against untrusted object decoding].
- **Trusting `seat`/`from` fields from clients:** a client can only speak for the seat bound to its peer id.
- **Pausing the Conductor in online matches:** it desyncs the shared timeline (D-18).
- **Editing the pinned timing files** for start scheduling: unnecessary (Pattern 2) and it fails the gate.
- **Running bots or a second MatchSim on clients:** clients have no rules. Everything comes from host events.

## Latency Budget (NET-04, TORP-04)

Symbols: D = host input horizon, L = one-way latency (about RTT/2), F = one frame of poll delay (about 16.7 ms at 60 fps), beat = 60/BPM.

| Path | Delay | Effect |
|------|-------|--------|
| Shooter's fire reaches the referee | Processed at the exact press time t if L_shooter + F <= D | Same launch beat as offline (next whole beat after t). |
| Target sees TORPEDO_LAUNCH (telegraph starts) | `launch_t + D + L_target + F` | Telegraph = `travel_beats * beat - (D + L + F)` |
| Target receives LANDED | `arrive_t + D + L + F` | Inside the 1-beat ease-in. Crossed Wires' input switch is at arrive + 1 beat, so exact. Overlay notes are covered by D-09. |
| Own meter, reward and FIRE_QUEUED feedback | `t + D + L + F` (one round trip plus horizon) | ~100-250 ms UI lag on the meter only. Hits, combo and hull are instant and local. |
| Rival STATUS (periscope hull/depth) | ~`D + L` | Cosmetic. |

Worked numbers (D from D-05):

| Link | RTT | L | D | D+L+F | Telegraph, 1-beat flight @120 BPM (500 ms) | Telegraph, 2-beat @120 | 2-beat @180 BPM (333 ms) | 2-beat @200 BPM (300 ms) |
|------|-----|---|---|-------|-------------------------|-----------|------------|------------|
| LAN | 2 ms | 1 | 60 | 78 ms | 422 ms = 0.84 beat ✗ | 922 = 1.84 ✓ | 589 = 1.77 ✓ | 522 = 1.74 ✓ |
| Tailscale direct (same country) | 40 ms | 20 | 73 | 110 ms | 390 = 0.78 ✗ | 890 = 1.78 ✓ | 556 = 1.67 ✓ | 490 = 1.63 ✓ |
| Tailscale via DERP relay | 160 ms | 80 | 133 | 230 ms | 270 = 0.54 ✗ | 770 = 1.54 ✓ | 437 = 1.31 ✓ | 370 = 1.23 ✓ |
| Bad (cross-continent relay) | 300 ms | 150 | 200 (cap) | 367 ms | ✗ | 633 = 1.27 ✓ | 299 = 0.90 ✗ | 233 = 0.78 ✗ |

The conclusion behind D-08: a 1-beat flight is good lag cover for **rule correctness** (rules never depend on latency at all with the horizon design). It is not enough cover for the **TORP-04 telegraph**, even on LAN. A 2-beat flight keeps TORP-04 for every realistic friend link up to about 200 BPM. The lobby should show a yellow "high latency" note when `D + L_max + F > 250 ms` [derived; MEDIUM until measured in UAT].

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reliable ordered UDP, retransmit, fragmentation | Custom UDP protocol over `PacketPeerUDP` | ENet via `ENetMultiplayerPeer` | Ack/retransmit/congestion are subtle, and ENet is built in. |
| NAT traversal / relays | Hole punching, STUN/TURN, a relay server | Tailscale/ZeroTier/LAN/port-forward (D-14) | Needs servers, and CGNAT defeats DIY. VPN overlays solve it for free. |
| Connection handshake and version check | Ad-hoc first packet | `SceneMultiplayer.auth_callback` + `send_auth` + `complete_auth`, `auth_timeout` | Built-in state machine. `peer_connected` fires only after auth. |
| Game rules on the host | A network-specific referee | The existing `MatchSim` | It is already the deterministic referee (03-SPEC req 12, D-28). |
| Song identity | Hashing audio files | `chart.id` fingerprint (SONG-05) + versus_sig | Already computed and cached at scan time. |
| Latency simulation | Sleeping threads or OS tools (clumsy) | `MemTransport` (virtual time) + existing `LoopbackChannel.latency_s` | Deterministic and headless. |
| Serialization | Custom binary format | `var_to_bytes`/`bytes_to_var` + schema validation | Compact enough, and the decoder is engine-hardened when objects are off. |

**Key insight:** the risky parts (determinism, judgment, payload timing) are already solved offline. Phase 4 is plumbing plus ordering. Every custom networking "smart" idea (prediction, rollback, mesh) adds failure modes that the current architecture makes unnecessary.

## Runtime State Inventory

Not a rename/refactor phase. Persistent state this phase adds or touches:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Settings file gains `player_name`, `net_last_address`, `net_last_port`, `net_flight_beats` | Settings load validation (lengths, ranges), like the existing keys |
| Live service config | None. No server, no cloud config. Friends' Tailscale/ZeroTier networks are theirs. | Docs only |
| OS-registered state | **Windows Defender Firewall rule** for UNDERTOW.exe (and the Godot editor during dev) is created when the user clicks "Allow" on the first `create_server` | Document in ONLINE_SETUP.md ("allow on Private networks; if you clicked Cancel, re-enable in Windows Security > Firewall > Allow an app") [ASSUMED: standard Windows prompt behaviour] |
| Secrets/env vars | None. No keys or tokens (D-14 needs none in-game). | None |
| Build artifacts | Friend zip (`tools/dist.ps1`) must include `docs/ONLINE_SETUP.md` or an in-game help page. The version string used by the D-21 handshake must be bumped per build. | Update dist.ps1 and README in the docs plan |

## Common Pitfalls

### Pitfall 1: Referee time running backwards
**What goes wrong:** remote inputs are applied on arrival, and MatchSim's `_now` jumps back. Bounty, meter and warhead outcomes depend on arrival order. Host and client views disagree with offline expectations.
**Why it happens:** `_begin(t)` assumes non-decreasing input times (true offline because of `advance_to`).
**How to avoid:** D-04 horizon queue plus clamp. Test: same event log at 0 ms and at 80±40 ms jitter (< D).
**Warning signs:** `late_inputs > 0` on LAN, and event `t` values that decrease in `event_log`.

### Pitfall 2: Ticks treated as a shared clock
**What goes wrong:** the start time is off by seconds (the difference in process start times).
**How to avoid:** always `local = host - offset`. Test with two processes started 2 s apart. The offset must be about 2 s, and both song_time = 0 instants (logged in unix ms) must agree within ~20 ms.

### Pitfall 3: TORP-04 silently broken online
**What goes wrong:** the telegraph is shorter than 1 beat with a 1-beat flight.
**How to avoid:** D-08. Add a NetMatchHarness assertion: target's `first_visible_t` (receipt in target song time) is at least `arrive_t - 1 beat` with latency = D cap.

### Pitfall 4: Overlay notes popping in mid-highway
**What goes wrong:** Ghost/Depth Charge notes are added after their spawn time.
**How to avoid:** D-09 approach margin on the host's PlayerState. Test: every overlay note's `time - approach_s(local)` is >= the LANDED receipt time.

### Pitfall 5: Client feedback relying on synchronous return codes
**What goes wrong:** `VersusController.fire()` uses `sim.request_fire`'s return code for the error blip. A client cannot know it synchronously.
**How to avoid:** D-13. On the client, the blip is played from the `FIRE_REFUSED` event. The return value of `RemoteReferee.request_fire` is `FIRE_PENDING`-like and ignored.

### Pitfall 6: Hostile or garbage packets crash the game
**What goes wrong:** missing keys, wrong types (`int(e["seat"])` on a String), NaN/INF times, huge arrays, out-of-range note indices into `chart.notes[idx]`. SubRig indexes `chart.notes[idx]` directly.
**How to avoid:** `NetCodec.validate` per message type. Song times must be finite and within `[-10, song_len + 30]`, seats 0..3, note indices `0 <= i < chart.notes.size()`, judgment in enum, reward in `Reward.Id`, warheads <= 16. Fuzz test with random Variants and truncated byte arrays. **Clients also validate host events** (a buggy host must not crash clients).

### Pitfall 7: Head-of-line blocking skews clock sync
**What goes wrong:** pings on the reliable channel wait behind retransmits and inflate RTT samples.
**How to avoid:** D-01 channel 1 unreliable for pings, plus min-RTT filtering (D-06).

### Pitfall 8: The intro or a frame hitch makes a client start late
**What goes wrong:** the goggles intro is skippable and variable, and scene build hitches delay `begin`.
**How to avoid:** D-07 forces intro NONE online and calls `begin` with a lead computed from the schedule. Since lead is computed at call time, a hitch before the call is absorbed, as long as lead >= 0.5 s.

### Pitfall 9: Windows Firewall blocks the host silently
**What goes wrong:** the friend's join times out, and nothing in the game explains why.
**How to avoid:** the Join screen shows "No answer from host after 8 s. Check that the host allowed UNDERTOW through Windows Firewall and that you are both connected in Tailscale." Document it in ONLINE_SETUP.md.

### Pitfall 10: Multiple instances on one PC sharing `user://settings`
**What goes wrong:** smoke-test processes overwrite each other's Settings (name, calibration) and fight over files.
**How to avoid:** a command-line `-- --net-profile=<n>` that redirects the Settings/ScoreStore file names (the harness already isolates settings, per 01.1-05). Also a `--mute` flag for the smoke test. [ASSUMED: no built-in Godot CLI flag for the user dir; the project's own override is needed.]

### Pitfall 11: Overclock / Ballast applied late on the client
**What goes wrong:** BUFF_APPLIED reaches the client ~RTT+D after the press. The local hull's `overclock_until` window starts late (the host meter is exact). The Ballast heal lands ~0.2 s late.
**How to avoid:** accept in v1 (cosmetic or hull-only, about 1-2 notes). Note it in UAT. Optionally the client sets `hull.overclock_until` optimistically on its own press of a held Overclock. Do not do this in v1.

### Pitfall 12: Tailscale MTU 1280
**What goes wrong:** large packets fragment inside the tunnel.
**How to avoid:** D-23 keeps typical packets < 1200 bytes. Split RESULTS/LOAD if they ever grow. ENet fragments large reliable packets itself anyway [ASSUMED].

### Pitfall 13: Custom MultiplayerAPI branches in tests
**What goes wrong:** several peers in one test process share the default `multiplayer`.
**How to avoid:** in tests, create separate `SceneMultiplayer` objects, assign each its own `ENetMultiplayerPeer`, and call `poll()` manually each test step. `send_bytes` needs no node tree. (If tree-bound APIs are needed, `SceneTree.set_multiplayer(api, root_path)` supports per-branch APIs, and nested ones are not allowed [CITED: SceneTree docs].)

## Code Examples

### ENet transport wiring (D-01, D-02, D-21, D-22)
```gdscript
# Source: docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html, class_enetmultiplayerpeer.html (4.7)
var api := SceneMultiplayer.new()
var peer := ENetMultiplayerPeer.new()

func host(port: int) -> Error:
	var err := peer.create_server(port, 3, 2)          # max 3 clients, 2 channels
	if err != OK: return err
	api.server_relay = false                            # star topology, no client<->client relay
	api.auth_callback = _on_auth                        # (id, data) -> validate proto/game/name
	api.auth_timeout = 3.0
	api.multiplayer_peer = peer
	api.peer_packet.connect(_on_peer_packet)
	api.peer_disconnected.connect(_on_peer_left)
	return OK

func send(id: int, msg: Dictionary, reliable := true) -> void:
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	api.send_bytes(var_to_bytes(msg), id, mode, 0 if reliable else 1)
```

### Host disconnect → elimination (D-16)
```gdscript
func _on_peer_left(id: int) -> void:
	var seat := _seat_by_peer.get(id, -1)
	if seat == -1 or phase != Phase.PLAYING: return
	queue.drop_seat(seat)
	queue.push_now(seat, Kind.FAILED, [], queue.released_t())   # -> sim.on_failed(seat, t_eff)
	host_channel.send(GameEvent.make(GameEvent.PLAYER_LEFT, queue.released_t(), {"seat": seat, "reason": "disconnected"}))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ARCHITECTURE.md (2026-10-07): each peer owns its hull and torpedoes; peers send TORPEDO_LAUNCH with sender-computed t_arrive | Phase 3: a central `MatchSim` decides launches, collisions, shields, bounty, duels and reflections | Phase 3 (03-03 .. 03-15) | The host must run MatchSim on everyone's inputs. Peers no longer compute arrivals. Inputs, not outcomes, cross the wire. |
| ARCHITECTURE 2-beat flight | 03-SPEC 1-beat flight offline | 03-RESEARCH | Online returns to 2 beats for TORP-04 (D-08). This is a config value, not a rules change. |
| Tailscale free "3 users / 100 devices" (older third-party pages) | Free Personal: 6 users, unlimited user devices, non-commercial | Plan rework 2026-04 per third-party guide. Current numbers verified on tailscale.com/pricing today. | 4 friends fit in one free tailnet. |
| ZeroTier free 25/50 nodes (old forum posts) | Free: 10 devices, 1 network | 2025 per vendor page via search | 4 PCs fit. Fine as the second option. |

**Deprecated/outdated:** STATE.md says judge_config is pinned to `fbcf994`. `tools/check_timing_gate.ps1` pins `2c2e54c` (perfect_regen change, user-approved 2026-10-08). The gate script wins.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `bytes_to_var` (no objects) is safe on untrusted input apart from size, and `var_to_bytes` keeps float64 precision for song times | Standard Stack, Pattern 4 | Low. If precision is lost, encode times as int microseconds (recommended anyway for `t` on the wire). |
| A2 | ENet default peer timeouts are 32 / 5000 / 30000 ms | D-17 | Low. The watchdog makes detection independent of this. |
| A3 | Port 47474 has no common conflict | D-15 | Low. It is editable. |
| A4 | Windows shows a firewall prompt on first `create_server`, and the Tailscale adapter needs the app to be allowed | Runtime State, Pitfall 9 | Medium. Verify on the user's PC during UAT. Docs must cover it. |
| A5 | `SceneMultiplayer.send_bytes` works on a manually polled API not attached to a SceneTree (in-process multi-peer tests) | Pitfall 13, D-24 | Medium. Fallback: `SceneTree.set_multiplayer(api, "/root/PeerN")` per peer branch, or only the MemTransport tests plus the process smoke test. |
| A6 | The latency figures (DERP RTT 100-200 ms, direct 20-60 ms) for friends | Latency Budget | Medium. D is measured per match, so wrong figures only shift D. Recheck the 2-beat choice in UAT. |
| A7 | Custom per-branch MultiplayerAPIs are polled automatically by SceneTree when `multiplayer_poll` is true | Pitfall 13 | Low. Tests can call `poll()` explicitly. |
| A8 | Tailscale shared-machine recipients can reach the host by its 100.x address as well as its FQDN | D-14/D-15 | Low. Docs recommend inviting friends as tailnet users (simplest), with Share as the alternative using the FQDN, which ENet accepts. |
| A9 | ENet fragments reliable packets larger than the path MTU without problems over Tailscale | Pitfall 12 | Low. Packets are kept small anyway. |
| A10 | Third-party "plan reworked 2026-04" history for Tailscale | State of the Art | None for the decision. The current numbers came from tailscale.com directly. |

## Open Questions (RESOLVED)

1. **Is a 2-beat online flight acceptable to the user's sense of "torpedoes fast"?**
   - What we know: the math (Latency Budget) shows that 1 beat cannot meet TORP-04 online. Offline stays 1 beat.
   - Unclear: feel.
   - Recommendation: default 2 (D-08), with a lobby toggle for 1 beat on LAN. Ask in UAT.
   - RESOLVED: default per D-08 (2-beat online flight, 1-beat LAN option in the lobby; plans 04-03, 04-13, 04-15). Feel is UAT item 4 in 04-HUMAN-UAT.md.
2. **Should the client predict its own landing/launch FX?** (D-10)
   - Recommendation: measure `landed_late_ms` in UAT first. Add prediction only if a jump is visible.
   - RESOLVED: default per D-10 (no prediction in v1; landed-late is measured in the F3 rows, plan 04-16). Visibility is UAT item 5.
3. **Rematch from results:** "Back to Lobby" keeps the roster. Should the host be able to start immediately with the same song? Default: yes. Ready flags reset, and Start needs everyone Ready again.
   - RESOLVED: default per D-19 (Back to Lobby keeps the roster, song and difficulty; Ready is cleared; plans 04-10, 04-12, 04-14). Checked in UAT item 1.
4. **Dev PC lacks Tailscale** (Environment). The human UAT needs Tailscale installed by the user (or LAN with a second PC).
   - RESOLVED: human action, recorded as UAT item 1 (the user installs Tailscale; Claude creates no accounts). Automation uses the 4-process localhost smoke (plan 04-17).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.7.2 console exe | Tests, smoke, export | ✓ | `C:\Users\User\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` (GODOT_BIN) | — |
| gdUnit4 | Tests | ✓ | 6.2.1 (vendored) | — |
| PowerShell | `tools/*.ps1` | ✓ | Windows built-in | — |
| Tailscale client | Human UAT over the internet | ✗ (not installed on the dev PC) | — | LAN test with a second PC, or the 4-process localhost smoke for automation. The user installs Tailscale themselves for UAT. |
| ZeroTier | Alternative UAT path | ✗ | — | Tailscale/LAN |
| Second PC / friends | NET-01/07 real-world proof | Human | — | Localhost multi-process covers automation only |

**Missing dependencies with no fallback:** none for automated work. Real-internet verification is a human UAT item (`human_verify_mode: end-of-phase`).

## Validation Architecture

(`workflow.nyquist_validation` is false in config.json. Included because the orchestrator asked for it.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | gdUnit4 6.2.1 on Godot 4.7.2 headless |
| Config file | `addons/gdUnit4`, runner `tools/run_tests.ps1` |
| Quick run command | `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_net_*.gd` (run `godot --headless --path . --import` first after adding class_names) |
| Full suite command | `powershell -NoProfile -File tools/run_tests.ps1` |
| Gates | `powershell -NoProfile -File tools/check_timing_gate.ps1` → `TIMING GATE OK` (every plan) |
| Process smoke | `powershell -NoProfile -File tools/net_smoke.ps1` (new, 04-06) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NET-01 | Host + 3 clients connect, auth OK. Wrong proto/version refused with a reason. 5th peer refused. | integration (in-process ENet 127.0.0.1) | `run_tests.ps1 -Path res://tests/test_net_session.gd` | ❌ Wave 2 |
| NET-01 | Codec rejects malformed, oversize, NaN and out-of-range messages (fuzz 10k cases) | unit | `res://tests/test_net_codec.gd` | ❌ Wave 1 |
| NET-02 | Roster ready flags. Song status OK/MISSING/CHANGED from fingerprint + versus_sig. Start gating. | unit (LobbyState) + integration | `res://tests/test_lobby_state.gd` | ❌ Wave 2 |
| NET-03 | ClockSync: synthetic samples with asymmetric jitter give an offset within 2 ms. Two processes started apart agree on song_time 0 within 20 ms (unix-ms log). | unit + process smoke | `res://tests/test_clock_sync.gd`; `tools/net_smoke.ps1` | ❌ Wave 1 / Wave 4 |
| NET-04 | Host event log is identical for latency 0 / 50 ms / 80±40 ms jitter / 2% loss (reliable) when L < D. All clients receive every event in seq order. Late inputs are clamped and counted. | integration (NetMatchHarness on MemTransport) | `res://tests/test_net_match_harness.gd` | ❌ Wave 2 |
| NET-04 | Telegraph: with a 2-beat flight and D+L at the cap, the target's alert receipt is at least 1 beat before arrive_t. Overlay notes are never added after their spawn time (D-09). | integration | same file | ❌ Wave 2 |
| NET-04 | `MatchSim extends Referee` changes nothing: the existing Phase 3 suite is still green (determinism at 30/144/1000 fps) | regression | full suite | ✅ existing |
| NET-05 | Disconnect mid-song gives IMPLODED + PLAYER_LEFT for that seat. The match continues to MATCH_END with remaining seats. Results show LEFT. | integration (MemTransport drop) + in-process ENet | `test_net_match_harness.gd`, `test_net_session.gd` | ❌ Wave 2/3 |
| NET-06 | Host MATCH_ABORT gives the client the HOST LEFT dialog. Silent host loss triggers the watchdog after 4 s. | integration (MemTransport stall) + UI test | `res://tests/test_online_gameplay.gd` | ❌ Wave 3 |
| NET-07 | The documented path works through real routers | manual UAT (Tailscale, 2+ PCs) | 04-HUMAN-UAT.md checklist | ❌ Wave 4 |

### Sampling Rate
- **Per task commit:** the touched `test_net_*` files plus the timing gate.
- **Per wave merge:** full suite plus the timing gate.
- **Phase gate:** full suite green (except the known red `test_bot_frequency.gd` D-UAT-01 if still open), `net_smoke.ps1` PASS, then human UAT.

### Wave 0 Gaps
- [ ] `tests/test_net_codec.gd`, `tests/test_clock_sync.gd`, `tests/test_mem_transport.gd`: created in 04-01
- [ ] `tests/test_net_match_harness.gd` and `src/versus/net_match_harness.gd`: 04-02
- [ ] `tests/test_net_session.gd`, `tests/test_lobby_state.gd`: 04-03
- [ ] `tests/test_online_gameplay.gd`, `tests/test_lobby_screen.gd`: 04-04 / 04-05
- [ ] `tools/net_smoke.ps1` with `--net-profile`/`--mute`/`--net-autotest` CLI args: 04-06
- No framework install needed.

## Suggested Plan / Wave Breakdown

Granularity is coarse and parallelization is on. ROADMAP marks "UI hint: yes", so the orchestrator should run the UI-SPEC step for the online menu, lobby and HOST LEFT/Leave dialogs before planning 04-05.

| Wave | Plan | Contents | Depends | Files (main) |
|------|------|----------|---------|--------------|
| 1 | **04-01 Net core (pure)** | NetProtocol (types, limits, PROTO), NetCodec + per-message validation, ClockSync, NetTransport base + MemTransport (virtual time, latency/jitter/loss/drop-peer, seeded), versus_sig. Tests: codec fuzz, clock estimator, mem transport ordering. | — | `src/net/*` (new), tests |
| 2 | **04-02 Host referee + net channels** | `Referee` base, `MatchSim extends Referee`, `SubRig.sim: Referee`, HostInputQueue (D-04), RemoteReferee, NetHostChannel/NetClientChannel (seq, dedupe, validate), GameEvent additions PLAYER_LEFT/DUEL_LIVE, host-side approach margin (D-09), NetMatchHarness (host + clients over MemTransport with bots/autoplay as the "humans"). Tests per the map. | 04-01 | `src/versus/*` |
| 2 | **04-03 NetSession + ENet** | NetSession autoload: ENetTransport, host/join, auth handshake (D-21), LobbyState, ready/song messages, clock-sync loop, D computation, LOAD/LOADED/START, watchdog, kick, MATCH_ABORT. Settings keys (name, last address/port, flight). In-process 127.0.0.1 tests. | 04-01 | `src/autoload/net_session.gd`, `src/net/enet_transport.gd`, `src/net/lobby_state.gd`, settings.gd, project.godot (autoload) |
| 3 | **04-04 Online gameplay integration** | VersusController backend injection (offline / online-host / online-client), Gameplay online branch (scheduled `conductor.begin`, intro NONE, no pause, Leave overlay, FIRE_REFUSED blip), disconnect → elimination, host-left dialog, DONE barrier, RESULTS, back to lobby. | 04-02, 04-03 | `src/ui/versus/versus_controller.gd`, `src/ui/gameplay.gd`, `src/ui/pause_menu.gd`, results screen |
| 3 | **04-05 Online menu + lobby UI** | Main menu "Play Online", name prompt, Host/Join screen (addresses incl. Tailscale 100.x highlight, port, UPnP try), Lobby screen (roster NAME/PING/SONG/READY, host song + difficulty pick, flight option, start gating, kick, messages), error states (timeout, refused, version mismatch). Keep-out/effect-settings contract tests. | 04-03 (UI-SPEC first) | `src/ui/online/*`, `main_menu.gd` |
| 4 | **04-06 Smoke, debug, docs, build** | `tools/net_smoke.ps1` (4 processes, autoplay, JSON reports, compare host log hash, clients received counts, start skew, late inputs), F3 net rows, `docs/ONLINE_SETUP.md` (Tailscale invite/share, ZeroTier, LAN, port forward, firewall, troubleshooting), friend zip update, 04-HUMAN-UAT.md checklist (2-4 PCs over Tailscale: join, ready/hash, synced start by ear, torpedo telegraph ≥1 beat, disconnect, host leave). | 04-04, 04-05 | tools, docs, `src/ui/debug_overlay.gd` rows |

Every plan's verification: touched tests green, full suite (wave end), `tools/check_timing_gate.ps1` → `TIMING GATE OK`.

## Security Domain

ASVS L1, block on high (config.json). The trust model is friends only: peers are trusted for their own hull/score (REQUIREMENTS "Anti-cheat: out of scope; host does basic sanity checks"). Peers are **not** trusted to send well-formed data.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Single validation choke point (`NetCodec.validate`), star topology, `server_relay = false` |
| V2 Authentication | partial | No accounts. A version/protocol handshake via `auth_callback` with a 3 s `auth_timeout`. Joining needs network reachability (the VPN membership is the real access control). |
| V3 Session Management | partial | Seat bound to the ENet peer id at auth. `refuse_new_connections` during a match. Kick = `disconnect_peer`. |
| V4 Access Control | yes | A client may only submit inputs for its own seat (seat taken from sender id). Only the host may send lobby/START/RESULTS/events (clients drop these from non-host ids. With a star topology all client packets come from id 1). Only the host can start, pick the song and kick. |
| V5 Input Validation | **yes (core)** | Packet size cap before decode. `bytes_to_var` only (never `_with_objects`). `allow_object_decoding` stays false. Per-type schema: key whitelist, `typeof` checks, `is_finite` for floats, int ranges (seat 0..3, note index < notes.size(), judgment enum, `Reward.Id`), string length and charset (names), array caps. Rate limits: at most 240 input items/s per client, at most 20 pings/s. 3 strikes → disconnect. Clients validate host events the same way. |
| V6 Cryptography | no | No secrets. Transport encryption comes from the VPN path (Tailscale/ZeroTier are encrypted). Over plain port-forward, ENet traffic is unencrypted, which is acceptable for game events (documented). ENet DTLS is not used (no cert management). |
| V7 Error Handling/Logging | yes | Never crash on bad input. Log rejected packets (type and size only, not content) to the debug overlay counter. User-facing messages are generic. |
| V12 Files/Resources | yes | Nothing from peers is ever used as a path, resource, script or class name. Songs are referenced by fingerprint and resolved only against the local library. No file transfer. |
| V14 Configuration | yes | Same build version required (D-21). `VersusConfig` from the host passes through `validated()` on the host before use and is re-validated on clients. |

### Known Threat Patterns for Godot ENet peer-hosted games

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Object/script injection via Variant decoding | Elevation of privilege | `allow_object_decoding = false` (default), `bytes_to_var` only [CITED: SceneMultiplayer docs] |
| Oversized or deeply nested packet (memory/CPU DoS) | Denial of service | Size cap before decode (16 KiB), item caps after, rate limit, strikes |
| Spoofing another seat's inputs | Spoofing | Seat from `peer_packet` sender id only |
| Forged host messages from a client | Spoofing/Tampering | Clients accept control/event messages only from peer id 1, and `server_relay = false` |
| NaN/INF/huge times poisoning MatchSim time walk | Tampering/DoS | `is_finite` + range clamp. `HostInputQueue` clamps to `[released_t, host_song + 2 s]`. Beyond the future bound → drop. |
| Out-of-range note index → array crash in SubRig/MatchSim | DoS | Validate `0 <= idx < chart.notes.size()` |
| Name with control characters or a huge string | Tampering/UI | Charset whitelist, 12 chars |
| Lying about own hull/score | Tampering | Accepted (friends trust model). Cheap host sanity: hull clamped to [0, hull_start], accuracy [-1, 1], depth non-negative, and fire only works with a held reward (MatchSim already enforces). |
| Connection floods / join spam | DoS | `max_clients = 3`, auth timeout 3 s, `refuse_new_connections` in matches |
| Eavesdropping | Information disclosure | Low value data. Tailscale/ZeroTier encrypt. Documented for the port-forward fallback. |

## Sources

### Primary (HIGH confidence)
- Codebase (read this session): `src/versus/match_sim.gd`, `game_event.gd`, `event_channel.gd`, `loopback_channel.gd`, `sub_rig.gd`, `player_state.gd`, `versus_config.gd`, `match_harness.gd`, `payload_stack.gd`, `match_setup.gd`; `src/ui/versus/versus_controller.gd`; `src/ui/gameplay.gd`; `src/core/conductor.gd`, `clock_model.gd`, `chart_importer.gd`; `src/autoload/song_library.gd`; `tools/check_timing_gate.ps1`, `tools/run_tests.ps1`; `.planning/research/ARCHITECTURE.md`, `PITFALLS.md`; 03-RESEARCH, 03-14-SUMMARY, 03-REVIEW-FIX; REQUIREMENTS/ROADMAP/PROJECT/STATE.
- https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html (4.7): properties, send_bytes, auth, peer_packet
- https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html: create_server/create_client signatures, FQDN support
- https://docs.godotengine.org/en/stable/classes/class_enetpacketpeer.html: set_timeout, RTT statistics, ping_interval
- https://docs.godotengine.org/en/stable/classes/class_scenetree.html: multiplayer_poll, set_multiplayer per branch
- https://tailscale.com/pricing: free Personal plan 6 users, unlimited user devices, non-commercial
- https://tailscale.com/kb/1084/sharing: device sharing on all plans; recipients need their own tailnet; shared machines accept inbound only

### Secondary (MEDIUM confidence)
- ZeroTier pricing (via search results citing zerotier.com/pricing and docs.zerotier.com/pricing): free 10 devices, 1 network
- Third-party Tailscale plan history (ssdnodes.com guides): 2026-04 plan rework

### Tertiary (LOW confidence)
- Latency figures for DERP vs direct paths (general knowledge, to be measured in UAT)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. Built-in APIs verified on the 4.7 docs today. No third-party packages.
- Architecture: HIGH. Derived directly from the MatchSim/SubRig/VersusController source. The horizon design follows from `_begin`'s semantics.
- Latency budget: MEDIUM. The arithmetic is exact, the link numbers are assumed, and D adapts per match.
- Connectivity: MEDIUM-HIGH. Tailscale verified on the vendor site. ZeroTier via search.
- Pitfalls: MEDIUM-HIGH.

**Research date:** 2026-10-20
**Valid until:** 2026-11-20 (Godot API stable. Re-check VPN free-plan terms before writing ONLINE_SETUP.md.)
