# Phase 4: Online Play - Pattern Map

**Mapped:** 2026-10-20
**Files analyzed:** 33 new or modified files
**Analogs found:** 30 / 33. ENetTransport, ClockSync and ONLINE_SETUP.md have no close analog. Use the RESEARCH.md code examples for them.

Line numbers refer to the working tree at mapping time.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/net/net_protocol.gd` (new) | config / consts | none | `src/autocharter/job_protocol.gd` (consts VERSION, MAX_TEXT, ERROR_TEXT) | exact (role) |
| `src/net/net_codec.gd` (new) | utility (validator) | transform | `src/autocharter/job_protocol.gd` `validate()` / `parse_event()` | exact |
| `src/net/clock_sync.gd` (new) | utility (pure model) | transform | none in the codebase; shape like `src/versus/player_state.gd` (pure RefCounted) | no analog (RESEARCH Pattern 3) |
| `src/net/net_transport.gd` (new) | service seam (base) | event-driven | `src/versus/event_channel.gd` + `src/autocharter/process_adapter.gd` | exact (seam idiom) |
| `src/net/mem_transport.gd` (new) | test transport | event-driven, virtual time | `src/versus/loopback_channel.gd` (latency_s queue) | exact |
| `src/net/enet_transport.gd` (new) | service adapter | event-driven | `src/autocharter/process_adapter.gd` (thin engine wrapper) | partial |
| `src/net/lobby_state.gd` (new) | model | CRUD | `src/versus/match_setup.gd` + `player_state.gd` | role-match |
| `src/net/versus_sig.gd` (new) | utility | transform | `ChartImporter.fingerprint` (`src/core/chart_importer.gd:108`), read only | role-match |
| `src/versus/referee.gd` (new) | base class | request-response | `src/versus/event_channel.gd` (no-op base with doc header) | exact (idiom) |
| `src/versus/match_sim.gd` (mod: `extends Referee`) | service | — | itself | — |
| `src/versus/host_input_queue.gd` (new) | service | batch / ordered queue | `src/versus/loopback_channel.gd` + `MatchHarness.advance_to` | exact |
| `src/versus/remote_referee.gd` (new) | service (client proxy) | request-response, serialize | `src/versus/sub_rig.gd` (calls into the sim) | role-match |
| `src/versus/net_host_channel.gd` (new) | channel | pub-sub | `src/versus/loopback_channel.gd` | exact |
| `src/versus/net_client_channel.gd` (new) | channel | pub-sub | `src/versus/loopback_channel.gd` | exact |
| `src/versus/net_match_harness.gd` (new) | test harness | batch, sim time | `src/versus/match_harness.gd` | exact |
| `src/versus/game_event.gd` (mod: PLAYER_LEFT, DUEL_LIVE) | model / vocabulary | — | itself (lines 11-69) | — |
| `src/versus/sub_rig.gd` (mod: `sim: Referee`) | service | — | itself | — |
| `src/versus/bot_player.gd`, `training_drone.gd` (mod, maybe) | — | — | they type `sim: MatchSim` (bot_player.gd:26,45; training_drone.gd:13,30). Keep `MatchSim`, because bots and the drone are host or offline only. | — |
| `src/autoload/net_session.gd` (new autoload) | service / provider | event-driven | `src/autoload/settings.gd` (autoload shape) + `song_library.gd:69-80` (cmdline) | role-match |
| `src/autoload/settings.gd` (mod: player_name, net_last_address, net_last_port, net_flight_beats, --net-profile) | config | file-I/O | itself, `_load_versus` (lines 312-329) | exact |
| `project.godot` (mod: NetSession autoload, `config/version`) | config | — | lines 13-19 | exact |
| `src/ui/versus/versus_controller.gd` (mod: backend injection) | controller | event-driven | itself | — |
| `src/ui/gameplay.gd` (mod: online branch, scheduled begin, no pause) | controller | — | itself, `_begin_count_in` (lines 245-256) | — |
| `src/ui/pause_menu.gd` / Leave overlay, HOST LEFT dialog | component | — | `src/ui/confirm_dialog.gd` | exact |
| `src/ui/online/online_menu.gd` (new) | component (screen) | request-response | `src/ui/versus/match_setup_screen.gd` | exact |
| `src/ui/online/lobby_screen.gd` (new) | component (screen) | event-driven | `src/ui/versus/match_setup_screen.gd` | exact |
| `scenes/online_menu.tscn`, `scenes/lobby.tscn` (new) | scene | — | `scenes/match_setup.tscn` | exact |
| `src/ui/main_menu.gd` (mod: "Play Online" item) | component | — | itself, line 172 `_item("Versus Bots", ...)` and line 500-505 | exact |
| `src/ui/online/net_debug_rows.gd` (new) / `src/ui/debug_overlay.gd` (mod) | component | polling | `src/ui/debug_overlay.gd` lines 61-74 | exact |
| `tests/test_net_codec.gd`, `test_clock_sync.gd`, `test_mem_transport.gd`, `test_lobby_state.gd` | test | unit | `tests/test_job_protocol.gd`, `tests/test_event_channel.gd` | exact |
| `tests/test_net_match_harness.gd` | test | integration | `tests/test_match_sim_determinism.gd`, `tests/test_versus_controller_determinism.gd` | exact |
| `tests/test_net_session.gd`, `test_online_gameplay.gd`, `test_lobby_screen.gd` | test | integration / UI | `tests/test_match_setup_screen.gd`, `tests/test_autochart_runner.gd` (FakeAdapter) | role-match |
| `tools/net_smoke.ps1` (new) | tool | batch, multi-process | `tools/playtest/run_all.ps1` + `tools/run_tests.ps1` | exact |
| `docs/ONLINE_SETUP.md` (new) | docs | — | none (no `docs/` folder exists yet) | no analog |

## Pattern Assignments

### `src/net/net_protocol.gd` and `src/net/net_codec.gd` (validator choke point)

**Analog:** `src/autocharter/job_protocol.gd`

**Header plus const table** (lines 1-47): a `class_name X extends RefCounted` header that describes the trust model, then `const VERSION := 1`, whitelists as `const MODES: Array[String] = [...]`, size caps (`const MAX_TEXT := 120`) and an error-code to player-text table (`ERROR_TEXT`) with `error_text(code)` falling back to `"internal"` (lines 182-183). Copy all of this for `PROTO := 1`, `MAX_PACKET := 16384`, `MAX_BATCH := 128`, `MAX_STR := 32`, `MAX_WARHEADS := 16`, `DEFAULT_PORT := 47474`, message type consts, and a refusal-reason to text table (`version`, `full`, `in_match`, `kicked`, `host_left`).

**Validate pattern** (lines 77-117): key presence loop, then `is int` / `is String` / `is bool` type checks, then range and whitelist checks. Return early on the first failure.
```gdscript
static func validate(job: Dictionary) -> String:
	for key in ["version", "src", ...]:
		if not job.has(key):
			return "bad_job"
	if not (job["version"] is int) or int(job["version"]) != VERSION:
		return "bad_job"
	...
	if not _is_number(job["target_nps"]):
		return "bad_job"
	var nps := float(job["target_nps"])
	if nps < 0.5 or nps > 8.0:
		return "bad_job"
```
For NetCodec, return `{}` for malformed input, the same way `parse_event` does (lines 168-179: `{}` for junk, non-objects, or a missing typed discriminator). Add `is_finite(float(v))` for every time value. `_is_number` (lines 186-187) can be reused as written.

**Decode entry** (analog `parse_event`, lines 168-179): check the packet size first, then `bytes_to_var` (never `_with_objects`), then `if v is Dictionary and v.get("type") is String`, then dispatch per type. Strings use the `safe_path_arg` charset loop style (lines 147-150: `unicode_at`, reject `< 32` or `127`) for player names.

**Tests:** `tests/test_job_protocol.gd`. It has one `test_validate_rejects_*` per field class (lines 110-157) and a hostile-input round trip (line 63). Add a fuzz loop over random Variants and truncated `var_to_bytes` output.

---

### `src/net/net_transport.gd` (seam base) and `src/net/mem_transport.gd`

**Analog for the base:** `src/versus/event_channel.gd` (whole file, 18 lines). A doc header names the seam and its Phase 4 swap. It declares a signal, a default `send` and a no-op `update(_t)` pump:
```gdscript
class_name EventChannel
extends RefCounted
## The seam between ... Phase 3 uses LoopbackChannel (same process); Phase 4 swaps in a network channel
signal received(e: Dictionary)
func send(e: Dictionary) -> void:
	received.emit(e)
## Song-time pump for channels that hold events (latency simulation, network). No-op here.
func update(_t: float) -> void:
	pass
```
NetTransport follows the same shape: `signal packet(peer: int, bytes: PackedByteArray)`, `signal peer_joined(id)`, `signal peer_left(id)`, a base `send(peer, bytes, reliable, channel)` and `poll(now)`.

**Analog for the in-memory transport:** `src/versus/loopback_channel.gd` (whole file, 30 lines). A `latency_s` var holds items in `_queue: Array[Dictionary]`, and `update(t)` releases them in FIFO order while `due <= t + 1e-9`. There is also a `pending_count()` test hook. MemTransport extends this with a per-item due time (`t_send + latency + jitter`), a seeded `RandomNumberGenerator` (seed it like `hash([seed, "bot", s])` in match_harness.gd:173), loss on unreliable packets only, and `drop_peer(id)`.

**Test-seam idiom (subclass fake):** `tests/test_autochart_runner.gd:6-30` `class FakeAdapter extends ProcessAdapter`. It overrides `start` and `read_*` and records calls in public vars (`kill_count`, `started_args`). Use the same approach for a `FakeTransport extends NetTransport` in NetSession and UI tests.

**Tests:** copy `tests/test_event_channel.gd:52-71` (`test_loopback_latency_holds_until_due_then_fifo`), with step-wise `update()` calls and asserts on counts and order.

---

### `src/net/enet_transport.gd`

**Analog (partial):** `src/autocharter/process_adapter.gd`. It is a thin wrapper over an engine API so that callers can be tested with a fake (header lines 1-8). It keeps the engine handles referenced in private vars (`_pid`, `_stdio`), returns sentinel values instead of throwing (`start` returns -1, lines 20-29), and never blocks (`_drain`, lines 64-81). The header comment documents engine quirks, so do the same for the ENet facts (2 channels, `server_relay = false`, `allow_object_decoding` false, `auth_timeout`, `set_timeout(32, 4000, 10000)`).
**Core API:** use the RESEARCH "ENet transport wiring" code example (`SceneMultiplayer` + `ENetMultiplayerPeer`, `send_bytes`, `peer_packet`). Nothing in the codebase uses networking yet.

---

### `src/net/clock_sync.gd`

**No analog.** Use RESEARCH Pattern 3. Follow the house style of pure classes: `class_name X extends RefCounted`, a doc header, no nodes, no `Time` reads inside (pass `c0/h/c1` in, like `SubRig`, which "never reads Time" per sub_rig.gd:8). That keeps it unit-testable with synthetic samples.

---

### `src/net/lobby_state.gd`

**Analog:** `src/versus/player_state.gd` (pure data RefCounted, typed vars with `##` docs, `_init(p_seat, p_callsign...)` with the `p_` prefix, lines 11-63) and `MatchSetup` (`clamped()`, `SKILLS` whitelist, `MIN_/MAX_RIVALS`). Roster rows: `{seat, peer_id, name, ready, song_status, ping_ms}`. Expose `can_start()` the way `MatchSetupScreen._start_enabled()` does (match_setup_screen.gd:252-253).

---

### `src/versus/referee.gd` (new base) and `match_sim.gd` (`extends Referee`)

**Analog:** `event_channel.gd` (a base class with default no-op bodies).
**Method list to declare.** Copy the signatures exactly from MatchSim (match_sim.gd):
- `on_judged(seat: int, note_index: int, judgment: int, t: float) -> void` (207)
- `on_extra_judged(seat: int, judgment: int, t: float) -> void` (221)
- `on_stray(_seat: int, t: float) -> void` (238)
- `on_ghost_hit(seat: int, t: float) -> void` (245)
- `report_status(seat, hull: float, depth: float, accuracy: float, max_streak: int, t: float = NAN) -> void` (257)
- `request_fire(seat: int, t: float) -> int` (272), plus the `FIRE_*` consts at lines 28-32. Move them to Referee, or keep them on MatchSim and reference them as `MatchSim.FIRE_*`.
- `inject_fire(seat, to, reward, t) -> int` (293)
- `cycle_target(seat: int, t: float = NAN) -> int` (309)
- `set_target_mode(seat: int, mode: int, locked: int = -1, t: float = NAN) -> void` (341)
- `on_failed(seat: int, t: float) -> void` (369)
- `duel_live(seat: int) -> float` (410), `update(t: float) -> void` (432)

**Hazard: `SubRig._init` reads `sim.players`** (sub_rig.gd:54-58). It looks up its own `PlayerState` to sync `approach_s`. The Referee base must expose `var players: Array[PlayerState] = []` (MatchSim already declares it at line 56. Move that declaration to the base and delete it in MatchSim, otherwise GDScript reports a redeclared member). A client `RemoteReferee` needs a local players array (built from the roster), or SubRig must tolerate `_player == null`, which it already does at line 57.
**Hazard: `VersusController` binds `Callable(sim, "duel_live")`** (versus_controller.gd:215, 227). RemoteReferee must implement `duel_live` from the last `DUEL_LIVE` event (D-13).

---

### `src/versus/host_input_queue.gd`

**Analogs:** `loopback_channel.gd` (a held queue released by `update(t)`) plus the `advance_to` ordered-actor loop (`match_harness.gd:182-198`, with `guard` counter, `best_t` selection, `now = maxf(now, t)`).
Order by `(t, seat, seq)` with an explicit comparator, like the determinism test's sort with an appended script index as tiebreak (`test_match_sim_determinism.gd:65-69`: `out[k].append(k)` then `sort_custom`). Clamp late items to `_released_t` and count them in `late_inputs`. RESEARCH Pattern 1 is the reference body.

---

### `src/versus/remote_referee.gd` (client)

**Analog:** `sub_rig.gd:106-165`. These are the exact call sites and argument shapes that the proxy receives (`sim.on_judged(seat, idx, j, t)`, `sim.report_status(seat, hull.hull, hull.depth(), accuracy(), hull.max_combo, now)`, `sim.on_failed(seat, now)`). Each override appends `[kind, args, t, seq]` to a per-frame batch. `flush()` encodes one packet per frame (D-23). `request_fire` returns `MatchSim.FIRE_PENDING` (an ignored value, Pitfall 5).

---

### `src/versus/net_host_channel.gd` / `net_client_channel.gd`

**Analog:** `loopback_channel.gd`. Override `send(e)` and `update(t)`. Host: `received.emit(e)` locally (so host views and SubRig(0) behave as offline), then append `{seq, e}` to every peer's outgoing batch. Client: buffer by `seq`, emit in order, drop duplicates or `seq <= last`, and validate every event through NetCodec before emitting (Pitfall 6: clients validate host events too).
**Event shape source:** `game_event.gd:11-62` (field list per type). `MatchSim._emit` (match_sim.gd:1322-1326) is the only producer: `event_log.append(e); channel.send(e)`.

---

### `src/versus/game_event.gd` (additive)

Follow lines 11-62 exactly. Add a `##` field-doc line above each const (`## {seat, reason: "disconnected"} - ...`). Append the new names to `ALL_TYPES` (lines 64-69). **Test impact:** `tests/test_event_channel.gd:31` asserts `ALL_TYPES.size() == 25`, so update it to 27. Never rename an existing type (header lines 8-9).

---

### `src/versus/net_match_harness.gd`

**Analog:** `src/versus/match_harness.gd` (whole file).
- Opts Dictionary documented in the header (lines 13-16). Use `opts.get(..., default)` with `clampi`/`clampf` (lines 105-123).
- Inner actor classes with `next_time()` / `step()` (`_TickActor` lines 48-65, `_AutoActor` lines 68-102). Reuse `MatchHarness._AutoActor` directly, as `VersusController` does at line 134.
- `advance_to(t)` global ordering (lines 182-198), `finish()` once-guard (lines 202-207), `result()` summary dict (lines 210-243), `static func run(chart, opts)` fixed-step driver (lines 246-257).
For the net version, each client is a SubRig on a `RemoteReferee` + `NetClientChannel`. The host holds the `MatchSim` + `HostInputQueue` + `NetHostChannel`, and a `MemTransport` sits in between, stepped in the same loop.

**Tests:** `tests/test_match_sim_determinism.gd` (scripted `[t, kind, args]` inputs, byte-identical logs) and `tests/test_versus_controller_determinism.gd:27-48` (the fps loop from `MatchHarness.START_T`, then `finish(end_t)`, then `sim.event_log.duplicate(true)`). For NET-04, compare the host log at latency 0 against the log at jitter < D.

---

### `src/ui/versus/versus_controller.gd` (backend injection)

**Current construction to branch** (lines 97-148): `cfg = VersusConfig.new().validated()`, players and names, `channel = LoopbackChannel.new()`, `sim = MatchSim.new(...)`, human SubRig, bots, actors, `channel.received.connect(_on_event)`.
- Change `var channel: LoopbackChannel` (line 40) to `EventChannel`, and `var sim: MatchSim` (line 41) to `Referee`. Keep a separate `var match_sim: MatchSim` (null on clients) for `finish`, `standings` and `event_log` (lines 352-380).
- Keep the `static var test_autoplay_human` test-seam style (line 25). Add a backend selector the same way (`static var pending_backend` or a `setup` parameter), mirroring the `Gameplay.pending_*` statics (gameplay.gd:20-24).
- `fire()` (lines 331-339) uses the synchronous return code for the blip. The online client must instead count `error_blips` and play `_error_player` from `_on_event` on `FIRE_REFUSED` where `seat == HUMAN_SEAT` and the reason is `shielded`/`no_target` (D-13). Extend the `match` in `_on_event` (lines 390-400).
- HUMAN_SEAT is a const 0 (line 27). Online it must become `local_seat` (a var), because clients are seats 1..3. Every `bind(channel, HUMAN_SEAT, ...)` call (lines 191-232) must take that var.
- Offline behaviour must stay byte-identical: `tests/test_versus_controller_determinism.gd` is the regression guard.

### `src/ui/gameplay.gd` (online start)

**Hook:** `_begin_count_in` (lines 245-256) is "the only place Conductor.begin is called". Add a sibling `begin_at_host_ticks(...)` (RESEARCH Pattern 2) that sets the same flags (`lane_input.enabled`, `_began`, `highway.notes_enabled`, `arena.beat_live`) and passes the computed lead. Force `intro_mode = IntroTimeline.Mode.NONE` online through `pending_intro` (line 24, used at 222). Pause is gated at lines 341-347. Add `and not online` there.

---

### `src/ui/online/online_menu.gd` and `lobby_screen.gd` (+ `.tscn`)

**Analog:** `src/ui/versus/match_setup_screen.gd`. Visual specifics come from 04-UI-SPEC.md, which another agent is writing in parallel. Structural conventions to copy:
- Header comment that cites the UI-SPEC section, focus model and Esc behaviour (lines 1-14).
- Scene paths and copy as consts at the top (lines 16-43). Layout as `const ..._RECT := Rect2(...)` in 1920x1080 design pixels (lines 52-80).
- Injectable deps for tests: `var navigate: Callable = Callable()` and `var library: Node = null` (lines 106-108), resolved in `_ready` via `get_node_or_null("/root/SongLibrary")` (lines 174-187). Add `var session: Node = null` resolved from `/root/NetSession` the same way.
- `_ready` order: `UiLayout.fill_rect(self)`, `theme = Palette.load_theme()`, load model, `_build()`, `_refresh()`, `UiKit.register_fx(self)`, `_set_focus(...)` (lines 174-187).
- Row input in each row's `gui_input` with `ui_up/down/left/right/accept`, and `_unhandled_input` for `ui_cancel` that calls `_back()` (lines 733-759).
- Navigation via `_go(path)`: `navigate` if valid, else `ScreenTransition.change_scene` (lines 886-890).
- Double-press guard `_starting`, error line `_show_error(text)` (lines 840-884).
- Song pick for the host: reuse `open_song_pick()` (lines 828-837, `SongSelect.run_pick = true` + a `MatchSetup.pending` handoff) and `library.build_chart(entry, difficulty)` (line 844).
- Effects contract `apply_effect_settings()` / `effect_counts()` (lines 895-911) and test seams `debug_state()`, `focus_row_for_test`, `press_key_for_test` (lines 914-955).
- Scene file: copy `scenes/match_setup.tscn` (a single full-rect Control with the script attached).
- Main menu entry: add `_item("Play Online", <icon>, "default", func() -> void: launch_online())` next to line 172, with `launch_online()` modelled on `launch_versus` (lines 500-505).

**Tests:** `tests/test_match_setup_screen.gd` (drives `press_key_for_test` and asserts on `debug_state()`).

### HOST LEFT / Leave match dialogs

**Analog:** `src/ui/confirm_dialog.gd`. Call `setup(title, body, confirm_text, safe_text)`, connect the `confirmed` / `cancelled` signals and set `process_mode = PROCESS_MODE_ALWAYS` (lines 41-45). HOST LEFT is a single-button variant, so the planner either adds an optional "no safe button" mode or builds a sibling class.

---

### `src/autoload/net_session.gd` (+ `project.godot`)

**Autoload shape:** `settings.gd` (`extends Node`, no class_name, a header naming the autoload, `signal settings_changed`, consts, typed state vars, `_ready()`).
**Registration:** `project.godot` lines 13-19 (`NetSession="*res://src/autoload/net_session.gd"`). **Note:** `project.godot` has no `application/config/version`, so D-21's handshake value needs one added (or a `NetProtocol.GAME_VERSION` const). `tools/dist.ps1` should keep it in step.
**CLI args:** `song_library.gd:69-75` (`OS.get_cmdline_user_args()`, `user_args.has("--no-boot-scan")`). Use the same for `--net-profile=<n>`, `--mute`, `--net-autotest=...`. Playtest arg parsing with values: `playtest_driver.gd:3808` (`for a in OS.get_cmdline_user_args():`).
**Testability:** keep the protocol state machine in pure RefCounted parts (LobbyState, NetCodec, ClockSync) and inject the transport (`var transport: NetTransport`, with a FakeTransport/MemTransport in tests), following the `AutochartRunner.adapter` injection (`autochart_runner.gd:25`: `var adapter: ProcessAdapter = ProcessAdapter.new()`).

### `src/autoload/settings.gd` (new keys)

Copy `_load_versus` (lines 312-329) for a new `_load_net(cfg)`. Read with `cfg.get_value(section, key, default)`, check `typeof(...) == TYPE_STRING` or a number with `is_finite`, clamp or whitelist, and fall back to the default otherwise. Every new key goes in all four places: the var declaration (lines 51-56 style, with a `##` doc), `reset_defaults()` (lines 72-97), `save_to()` (`cfg.set_value("net", ...)` near lines 229-233) and `load_from()` (call `_load_net(cfg)` after `_load_versus`, line 286). For `--net-profile`, set `save_path` (line 58, "tests override this") in `_ready()` before `load_from(save_path)` (lines 68-69).
**Tests:** `tests/test_settings.gd`, `tests/test_settings_roundtrip.gd`.

### `src/ui/online/net_debug_rows.gd` / `debug_overlay.gd`

**Analog:** `debug_overlay.gd:61-74`. A fixed-width label block built with a `%` format string in `_process`, only when `visible`. The overlay is gated by `OS.is_debug_build()` (line 56). Add rows such as `rtt / offset / D / late / skew / landed_late` in the same `name   %9.4f` column style. `PANEL_SIZE` (line 7) must grow, or the net rows go in a second label.

---

### `tools/net_smoke.ps1`

**Analog:** `tools/playtest/run_all.ps1` (whole file):
- GODOT_BIN resolution (lines 11-13, identical in `run_tests.ps1:6-11`).
- Back up and restore the protected user files with SHA-256 proof (lines 15-30, 48-55, 80-91). With `--net-profile` each process writes its own settings file, but keep the proof anyway.
- `Start-Process -NoNewWindow -PassThru -RedirectStandardOutput/-Error` with user args after `--` (lines 65-66), `WaitForExit($limit*1000)`, then `taskkill /T /F` on stall (lines 68-72).
- Summary lines in the `[PASS]/[FAIL]/[note]` grammar, read with `Select-String` (line 74), and `exit $failed`.
- The 4 processes must start concurrently (host first, then 3 clients), unlike the sequential loop in run_all.
Use `--headless` (as in run_tests.ps1:19) plus `--mute` so the smoke test needs no audio device.

### `docs/ONLINE_SETUP.md`

No analog (`docs/` does not exist). Content comes from RESEARCH D-14, D-15 and Pitfall 9. Update `tools/dist.ps1` to ship it.

## Shared Patterns

### Untrusted-input validation (ASVS V5)
**Sources:** `job_protocol.gd:77-117` (message schema), `settings.gd:347-354` `_num` (type, `is_finite`, clamp, default) and `settings.gd:312-329` (whitelists).
**Apply to:** NetCodec (both directions), LobbyState updates, NetSession auth, the Settings net keys, and VersusConfig received from the host (`VersusConfig.validated()`, versus_config.gd:112).

### Pure RefCounted plus a doc header
Every rules or model file starts with `class_name X` / `extends RefCounted` and a `##` header that cites the decision IDs (D-xx, Pitfall n), says what the class never does ("no nodes, no Time, no Settings", sub_rig.gd:8, match_harness.gd:10-11), and documents the determinism contract. Apply to all of `src/net/*` and the new `src/versus/*` files.

### Signal connections without leaks
Use method callables, not lambdas, for long-lived connections (sub_rig.gd:70-74, CR-02 reference-cycle leak). Apply to NetSession, the channels and RemoteReferee.

### Song time, never frame time
Every input and event is stamped with song time (game_event.gd:6-7, versus_controller.gd:15-16). Network ticks (`Time.get_ticks_usec`) are only used inside ClockSync and the start schedule.

### Gates
After every plan, run `powershell -NoProfile -File tools/check_timing_gate.ps1` and confirm `TIMING GATE OK`. Tests run with `tools/run_tests.ps1 -Path res://tests/test_net_*.gd`. Run `godot --headless --path . --import` after adding any new `class_name`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `src/net/enet_transport.gd` | adapter | event-driven | No networking code exists yet. Use RESEARCH "ENet transport wiring". |
| `src/net/clock_sync.gd` | utility | transform | No estimator exists. Use RESEARCH Pattern 3. |
| `docs/ONLINE_SETUP.md` | docs | — | No docs folder exists. Use RESEARCH D-14/D-15/Pitfall 9. |

## Metadata

**Analog search scope:** `src/versus`, `src/ui/versus`, `src/ui` (gameplay, debug_overlay, confirm_dialog, main_menu), `src/autocharter`, `src/autoload`, `tests`, `tools`, `tools/playtest`, `scenes`, `project.godot`
**Files scanned:** about 30
**Pattern extraction date:** 2026-10-20
