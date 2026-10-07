# Architecture Patterns

**Domain:** Online 2-4 player competitive rhythm game (Godot 4, GDScript)
**Project:** UNDERTOW
**Researched:** 2026-10-07
**Overall confidence:** MEDIUM (patterns are well established; Godot API details below come from training knowledge and were not re-verified against current docs in this pass. Items marked VERIFY need a quick check against the Godot version you install.)

## Recommended Architecture

Guiding principle, taken from PROJECT.md: **gameplay is a deterministic, local simulation driven by one clock. The network only carries a small set of discrete, song-time-stamped events.** Nothing about hit judgment ever waits on the network.

```
                +-------------------- Autoloads (global services) --------------------+
                |  Settings   Calibration   SongLibrary   NetSession   EventBus         |
                +-----------------------------------------------------------------------+
                                 |                 |                |
   Lobby scene  <----------------+                 |                |
   Match scene                                      v                v
 +-------------------------------------------------------------------------------+
 | Match (scene root, owns one MatchState)                                       |
 |                                                                               |
 |  Conductor (audio clock) --song_time--> PlayerRig (local, 1x)                 |
 |                              |            |- ChartRunner (spawns/expires)     |
 |                              |            |- InputJudge  -> HitResult         |
 |                              |            |- HullScore                        |
 |                              |            |- TorpedoTube                      |
 |                              |            |- ModifierStack (incoming payloads)|
 |                              |            |- HighwayView (render only)        |
 |                              |                                                |
 |                              |--> RivalProxy (N-1) : hull, score, mini-view   |
 |                              |       fed ONLY by network events / bot sim     |
 |                              |                                                |
 |  EventChannel (interface) <--+-- NetEventChannel | LoopbackChannel | BotChannel|
 +-------------------------------------------------------------------------------+
```

Key structural decision: **the gameplay core never calls `rpc()` or touches `multiplayer`.** It emits and consumes `GameEvent` objects through an `EventChannel` interface. Three implementations (network, loopback/solo, bot) are what make offline testing possible.

### Component Boundaries

| Component | Responsibility | Talks To | Must NOT |
|-----------|---------------|----------|----------|
| **Conductor** (node, per match) | Single source of truth for `song_time` (seconds), beat/bar position, BPM map lookups, pause/start-at. Wraps the `AudioStreamPlayer`. | Audio server; read by everything | Use `delta` accumulation as the authority |
| **ChartData** (Resource, immutable) | Parsed chart: tempo map, time signature map, per-difficulty note list (time sec, lane, sustain length, flags), song metadata, audio path, content hash | Produced by importers; read by ChartRunner, SongLibrary | Contain runtime state |
| **ChartImporter** (RefCounted, pure functions) | `.chart` text parser, `.mid` parser, `song.ini` reader; converts ticks to seconds via tempo map; maps 5-fret to 4 lanes; outputs ChartData | File system; SongLibrary | Touch scene tree or audio playback |
| **SongLibrary** (autoload) | Scans bundled + user dirs, caches parsed ChartData (e.g. as `.res`/JSON), computes song hash, exposes list for lobby | ChartImporter, Lobby, Match | Parse on the gameplay path |
| **ChartRunner** | Walks the note list by song_time; produces "active notes" window for judging and view; marks notes hit/missed; injects modifier-generated notes (ghost, depth charge) | Conductor, InputJudge, ModifierStack | Render anything |
| **InputJudge** | Converts input events to judgments: timestamp each press with audio-clock time, find nearest unhit note in lane, grade by window, emit `HitResult` | Conductor, ChartRunner, Calibration | Know about networking or visuals |
| **HullScore** (RefCounted / Node) | Hull value, score, depth, streak, multiplier; applies damage rules; detects elimination | InputJudge results, ModifierStack (ghost hit cost), EventChannel | Be modified from outside except via `apply_*` methods |
| **TorpedoTube** | Charge meter from streak, ready state, fire request, target selection (cycle/leader), beat-quantized launch time computation | HullScore (streak), Conductor, EventChannel | Decide arrival on the target's machine |
| **ModifierStack** | Active payloads on the local highway with start/end song_time; exposes queries (`lane_map()`, `scroll_mult()`, `fog_amount()`, extra notes); handles Return-to-Sender warhead tracking | ChartRunner, HighwayView, EventChannel | Read network state directly |
| **PayloadDef** (Resource per payload) | Data: id, duration in beats, parameters, `apply(stack)`/hooks. Five payloads = five small resources/scripts | ModifierStack | Hold match state |
| **HighwayView** | Pure render of the sonar lanes: notes at `y = f(note_time - song_time, scroll_speed)`, CRT shader, fog, flips. Used at full size (local) and mini size (rivals) | Reads ChartRunner window + ModifierStack + visual latency offset | Mutate gameplay state |
| **RivalProxy** | Local mirror of a remote player: hull, score, streak, alive flag, last-known song_time, mini panel data | EventChannel (inbound events) | Simulate rival hits (it only shows reported state) |
| **EventChannel** (interface) | `send(event)` / signal `received(event)`; abstracts transport | Gameplay core on one side; transport on the other | Leak transport details upward |
| **NetEventChannel** | Implementation over Godot high-level multiplayer RPC; applies authority rules and arrival scheduling | NetSession | Be referenced by gameplay classes directly |
| **LoopbackChannel / BotChannel** | Solo: events go to self. Bots: simulated rivals emit scripted hull/score/torpedo events with configurable latency/jitter | Gameplay core | Ship in release lobby |
| **NetSession** (autoload) | Peer lifecycle: host/join, transport choice, peer list, clock sync, ready states, start scheduling, disconnects | Lobby, Match, NetEventChannel | Contain game rules |
| **MatchState / MatchCoordinator** | Match phase machine (Lobby -> Loading -> Countdown -> Playing -> Finished), roster, winner determination, results data. Host-authoritative on elimination/final result | NetSession, EventChannel, RivalProxy | Run per-note logic |
| **Calibration** (autoload) | Stores audio offset and visual offset; provides tap-test routine; exposes `input_offset` and `visual_offset` | Settings, InputJudge, HighwayView | |
| **Settings** (autoload) | Key/gamepad bindings (InputMap), volumes, scroll speed, persisted to `user://` | All | |
| **FX/Audio layer** | Sonar pings, hull creak, underwater low-pass bus effect driven by hull, shake, flashes. Subscribes to signals | Local signals only | Gate gameplay |

### Data Flow

**1. Local gameplay loop (every frame, no network involved)**

```
AudioServer clock -> Conductor.song_time
song_time -> ChartRunner (advance window; mark passed notes as misses after window)
raw input (timestamp from event) -> InputJudge -> HitResult{lane, grade, delta_ms, note_id}
HitResult -> HullScore (streak, score, damage) -> TorpedoTube (charge)
HitResult -> FX (signals), ModifierStack (warhead hits, ghost hits)
HullScore state changes -> EventChannel.send(HULL_STATE / ELIMINATED)
```

**2. Outbound event (torpedo)**

```
Fire pressed at song_time t_press
TorpedoTube: t_launch = next_beat_boundary(t_press)           # quantized locally on the firing client
event = {type: TORPEDO, id, from, to, payload_id, t_launch, t_arrive = quantize(t_launch + flight_beats)}
EventChannel.send(event)     # reliable RPC to host (or all peers)
Local: show launch FX at t_launch; deduct tube charge immediately (optimistic)
```

**3. Inbound event (torpedo landing on me)**

```
NetEventChannel receives event (reliable RPC)
  -> validate (sender is real peer, id not seen, target==me or relay)
  -> convert t_arrive to local song_time (shared timeline, see clock sync)
  -> if t_arrive > now + min_lead: schedule payload start exactly at t_arrive (beat-aligned)
  -> else (late): clamp to next available beat boundary >= now + min_lead   # never retroactive
ModifierStack.add(payload, start=t_arrive_effective, end=start+duration_beats)
ChartRunner/HighwayView query ModifierStack each frame
```

**4. Rival display**

```
Periodic HULL_STATE {peer, hull, score, streak, song_time} (e.g. on change + 4 Hz heartbeat, unreliable ok for heartbeat; reliable for changes)
-> RivalProxy -> mini HighwayView panel (shows rival hull/streak/active payload, not their individual notes in v1)
```

Note on rival mini-highways: PROJECT.md mentions "periscope panels showing rivals' highways". Cheapest accurate approach: render the **rival's chart for the same song** (everyone has it) scrolled by the rival's last reported song_time plus active payload state, and show hit/miss pulses as events. Do not stream per-note judgments in v1. Decorative approximation is enough; flag as Phase-later polish.

## Song Clock / Conductor (the heart of the game)

**Pattern:** `song_time` derived from the audio playback position, smoothed with the frame clock between mixer updates, minus output latency, minus calibrated offset.

Known Godot behaviour (VERIFY exact method names for the installed 4.x version, but this pattern is the long-standing community recipe from Godot's own "Sync the gameplay with audio and music" docs page):

```gdscript
# Conductor.gd (sketch)
var _player: AudioStreamPlayer
var _start_offset := 0.0   # chart offset / lead-in

func song_time() -> float:
    var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix()
    t -= AudioServer.get_output_latency()
    return t - Calibration.audio_offset - _start_offset
```

Rules:
- `get_playback_position()` only updates per mixer chunk (~10-20 ms steps depending on buffer), so add `get_time_since_last_mix()` for sub-chunk resolution. Without this you get visible stutter and +/-10 ms judgment jitter.
- Even then results can be non-monotonic at chunk boundaries. Add a **monotonic clamp** (`song_time = max(song_time, last_song_time)`) and optionally a small smoothing filter that blends a free-running `Time.get_ticks_usec()` delta toward the audio-derived value. Pick one approach and test it; do not stack several.
- **Lead-in / negative time:** start the audio player at `play(0)` after a countdown, with song_time starting negative; or use `play(from_position)` carefully. Easiest: Conductor runs a "pre-roll" phase driven by the system clock until the audio actually begins, then hands over to audio-derived time. Handle the handoff without a jump (record the offset at handoff).
- **Input timestamps:** judge using the time the **event** occurred, not when `_process` ran. In Godot, `InputEvent` has no hardware timestamp on all platforms; the practical approach is to capture `Time.get_ticks_usec()` in `_input()` (which runs before the frame's `_process`) and convert via a stored mapping `(ticks_usec at sample) <-> song_time`. Keep a `Conductor.song_time_at_ticks(usec)` helper so input is converted at the moment it is received, not at frame end. This matters at 60 fps (16.7 ms frame granularity eats a third of a +/-50 ms window).
- Consider running input and judgment in `_input()` and rendering in `_process()`. Do not use `_physics_process` for anything timing related.
- Audio mix rate/buffer: expose output latency setting; lower buffer reduces latency but risks crackle. Calibration absorbs the remainder.
- Beat math lives in Conductor: `beat_at(song_time)`, `time_at_beat(beat)`, `next_beat_time(song_time)`, all tempo-map aware (charts have BPM changes; use a sorted tempo list with prefix-summed seconds and binary search).
- Pause/resume, restart, and seeking (practice mode) are Conductor concerns; the rest of the game only reads `song_time`.

**Two calibrations, both needed:** audio offset (tap-to-beat test; shifts judging) and visual offset (shifts only note drawing). Keep them as separate values.

**Confidence:** MEDIUM-HIGH on the pattern; VERIFY API names/behaviour on the chosen Godot version (some platform-specific latency reporting quirks exist, notably WASAPI default on Windows).

## Chart Data Model and Import Pipeline

### Runtime model (format-agnostic)

```gdscript
class_name ChartData extends Resource
@export var meta: Dictionary         # title, artist, charter, preview_time, song.ini fields
@export var audio_path: String       # relative to song dir (song.ogg / guitar.ogg / etc.)
@export var tempo_map: PackedFloat64Array  # parallel arrays: tick/beat, bpm, seconds_at
@export var time_sigs: Array
@export var tracks: Dictionary       # difficulty -> NoteTrack
@export var content_hash: String     # sha256 of chart file bytes + audio file bytes (or size+mtime fast path)

class NoteTrack:
    var times: PackedFloat64Array    # seconds, sorted
    var lanes: PackedByteArray       # 0..3
    var lengths: PackedFloat32Array  # sustain seconds (0 = tap)
    var flags: PackedByteArray       # HOPO/chord/etc., kept for future use
```

Use parallel packed arrays rather than thousands of per-note objects. Seconds are computed **once at import** using the tempo map, so runtime never deals with ticks.

### Import steps

1. **Discover** a song folder: `notes.chart` or `notes.mid`, `song.ini`, audio stems (`song.ogg`, `guitar.ogg`, `rhythm.ogg`, `drums.ogg`...). Clone Hero folder layout is the de-facto standard.
2. **Parse**
   - `.chart`: INI-like text with `[Song]`, `[SyncTrack]` (B = BPM*1000, TS), `[Events]`, and `[ExpertSingle]` style sections with `tick = N lane length` lines. Resolution is in `[Song]`. Simple to hand-write a parser in GDScript (line-based). **Prefer `.chart` first.**
   - `.mid`: Standard MIDI file with track names like `PART GUITAR`; difficulty encoded by note number ranges (60-64 easy, 72-76 medium, 84-88 hard, 96-100 expert). Godot has no built-in MIDI file reader for this; you must write a small SMF parser (header, varlen delta times, running status, meta events 0x51 tempo / 0x58 time sig / 0x03 track name). Moderate work, well-specified. Defer to a later phase than `.chart`.
3. **Convert**: ticks -> seconds through tempo map. Collapse chords into same-time notes. Map to 4 lanes (see below). Apply `song.ini` `delay` (ms) to audio offset.
4. **Lane mapping decision:** Clone Hero charts are 5-fret (+ open). UNDERTOW has 4 lanes. Options: drop one fret, fold green+orange, or per-song mapping. Make the mapping a pluggable `LaneMapper` strategy (default: fold frets 0-4 into 4 lanes with collision handling, open note -> chosen lane or dropped). Flag as a design decision; tune with real charts.
5. **Validate**: reject empty tracks, nonmonotonic tempo maps, missing audio; surface errors in the library UI, not as crashes.
6. **Cache** as a Godot `Resource` (`.res`) or JSON under `user://cache/` keyed by content hash.
7. **Audio loading:** load `.ogg` at runtime with `AudioStreamOggVorbis.load_from_file()` (Godot 4.x). `.mp3` via `AudioStreamMP3` from buffer. Some charts ship stems; v1 plays `song.ogg` or mixes `guitar` + backing stems only if trivial. VERIFY loader API on installed version. Plan for opus-in-ogg or unusual encodings to fail gracefully.
8. **Song hash for lobby:** hash the **converted-relevant bytes** (chart file + audio file) with SHA-256 via `HashingContext`, streamed in chunks (audio files are tens of MB). Compute once at scan time and cache by (path, size, mtime). Host broadcasts `{hash, difficulty, lane_map_version}`; each client replies has/missing. Include importer version in the match config so two clients with different importer versions don't diverge on note times.

**Determinism requirement:** every peer must derive the **identical note list** from the same files. Use only integer-tick math, a fixed algorithm, and (if needed) `double` seconds. Do not depend on locale, float formatting, or random seeds that differ. Depth Charge and Ghost Note generation must use a **seeded RNG** with the seed carried in the torpedo event.

## Judgment

- Judgment windows (tune later): Perfect +/-25, Great +/-40, Good +/-60 ms (hard cap ~+/-50-ish per PROJECT.md; make windows data-driven in one `JudgeConfig` resource).
- Per lane, keep an index of the earliest unresolved note. On press: look at candidate within window; consume it. On pass beyond the late window: mark Miss. This is O(1) amortised.
- Input without a note (ghost tapping) policy: no penalty in v1 (avoids punishing mashing frustration), but **hitting a Ghost Note costs hull** by design.
- Sustains: hold to end for bonus; keep in model, implement minimal in v1 or defer (see build order).
- Lane Flip: apply at the **input-to-lane mapping** step (`ModifierStack.lane_map`) and at the view; chart data is never mutated.
- Fog and Pressure Crack are **view-only** modifiers. **Pressure Crack changes scroll speed, not note times**. Judgment is unaffected; this is crucial so the fairness invariant holds.
- Ghost Notes and Depth Charge are **chart-layer injections**: `ChartRunner` merges generated notes (from a seeded generator referencing the real chart's rhythm in that time window) into the active window. Depth charge notes are real, judged notes; ghost notes are judged inversely (hit = damage, ignoring = fine).
- Return-to-Sender warhead notes: a tagged subset of notes with `torpedo_id`; the ModifierStack tracks if all were hit at Perfect; on success emits a `TORPEDO` event back to the original sender.

## Hull / Score State

- `HullScore` is the **only authority over the local player's own hull**. It emits `hull_changed`, `eliminated`.
- Each client announces its own hull/elimination. The **host acts as referee** for match end and winner: it accepts `ELIMINATED` events, tracks the roster, and broadcasts `MATCH_RESULT`.
- Torpedoes do not directly subtract hull. They install modifiers; hull damage arises only from the target's own misses/ghost hits. This eliminates a whole class of cross-client desync: **nobody can modify another player's hull**, and remote events are essentially "cosmetic or modifier-install."
- Tie-break at song end: depth (score) wins; host computes from last reported scores, with each peer sending a final authoritative `FINAL_SCORE` at song end.
- Wreck ghost: on elimination, HullScore state flips to `wreck`; ChartRunner continues; TorpedoTube uses a weaker charge table and `DEBRIS` payload variants (subset of existing payloads at reduced duration/intensity). Same code path, different data: do this via a `PlayerMode` resource, not branching all over.

## Torpedo / Payload System

Model payloads as **data + hooks on a modifier stack**, never as special cases in the highway.

```gdscript
class_name PayloadDef extends Resource
@export var id: StringName
@export var duration_beats: float
@export var intensity: float
# Hooks, all optional:
# lane_transform(lane:int) -> int
# scroll_multiplier(song_time) -> float
# fog(song_time) -> float
# inject_notes(window_start, window_end, chart, rng) -> Array
```

`ModifierStack.active_at(t)` returns payloads whose `[start, end)` contains `t`. Because start/end are in **song time** and quantized to beats, the same payload event produces the same effect window on the receiver no matter when the packet arrived (as long as it arrived before start).

Torpedo lifecycle states: `Charging -> Ready -> Launched(t_launch) -> InFlight -> Landed(t_arrive) -> Active(until) -> Expired`; plus `Reflected` branch for Return-to-Sender. Only `Launched` and `Landed/Reflected` cross the network.

Design for the arrival problem: a torpedo needs lead time. Make **flight time a deliberate game mechanic** (e.g., 2 beats minimum, ~1-2 s) which comfortably exceeds typical internet RTT/2 (30-150 ms). Beat-quantized arrival then hides jitter: events that arrive early wait for the next beat boundary; the lead is a buffer. This is the core feasibility trick: the flight time is the latency budget and also telegraphed gameplay ("incoming" warning on the target's sonar).

## Network Layer

### Transport recommendation

Use Godot's **high-level multiplayer API with `ENetMultiplayerPeer`** (UDP, reliable + unreliable channels, simple RPC), hosted by one player. Put it behind `NetSession` so a different transport can be swapped in.

NAT traversal is the open decision in PROJECT.md. Options ranked for this project:
1. **VPN overlay (Tailscale / ZeroTier / Radmin):** zero code, works with ENet as-is, friends install one app. Best for a fixed friend group; ship v1 with this as the documented path.
2. **Steam Networking via GodotSteam (`SteamMultiplayerPeer`):** relay + NAT punch + invite by friends list; slots into the same `MultiplayerPeer` interface. Requires a Steam app ID (Spacewar 480 for testing) and everyone on Steam. Strong later option; since it is a `MultiplayerPeer` subclass the architecture change is localized to NetSession.
3. **Direct port forwarding / UPnP** (`UPNP` class in Godot): flaky on home routers; offer as optional.
4. **Custom relay / WebRTC:** more code and hosting; avoid for v1.

Architecture implication: **write all networking against `MultiplayerPeer` abstractions and the `EventChannel` interface**, so the transport decision does not block the first phases. Confidence: MEDIUM (GodotSteam compatibility with latest Godot 4.x should be checked at adoption time).

### Lobby

- Host creates `ENetMultiplayerPeer.create_server(port, max_clients=3)`. Join by IP:port or a code that encodes it (v1: plain address; a short code is polish).
- `NetSession` keeps the roster (peer_id, display name, ready, has_song, calibration summary, ping).
- Host picks song + difficulty; broadcasts `{song_hash, difficulty, importer_version, seed}`; clients answer `has_song`. Start button is enabled when all present players are ready and have the song.
- Disconnect handling: roster change event; in a match a disconnected player is treated as eliminated (their RivalProxy becomes a wreck with no output).

### Clock sync and scheduled start

Goal: all clients begin the audio at (approximately) the same real moment so that "song time" is a **shared timeline** (needed so torpedo `t_arrive` means the same musical moment for everybody).

Note the subtlety: the actual requirement is not wall-clock equality but that **song_time T means the same position in the song on every machine, to within a tolerance (~50-100 ms is fine for torpedo arrival since arrival is beat-quantized)**. Hit judgment is never networked, so cross-machine skew does not affect fairness.

Procedure:
1. **Estimate offset to host clock** using ping-pong (NTP-style): client sends `t0` (local `Time.get_ticks_usec()`), host replies with `t_host`, client receives at `t1`. `rtt = t1 - t0`, `offset = t_host + rtt/2 - t1`. Repeat 8-16 times at ~100 ms spacing, discard outliers, take the sample with **lowest RTT** (or median of the lowest few). Keep a low-rate re-sync (every few seconds in lobby) so drift and route changes are tracked.
2. Host chooses `start_host_time = host_now + lead` (lead ~3 s, covering countdown and worst RTT) and broadcasts `START{start_host_time, config}` reliably.
3. Each client converts: `start_local = start_host_time - offset`, and starts its countdown/pre-roll so that **song_time = 0 at that local instant**. Because the Conductor's pre-roll runs from the system clock then hands off to audio-derived time, the audio's real start moment is aligned to `start_local` minus audio output latency (start audio early by the output latency so sound exits the speakers at the scheduled moment).
4. During the match, optionally run a gentle **drift check**: each client periodically reports its `song_time` against host-time stamps; if difference exceeds a threshold (e.g. 100 ms) you do **not** seek audio (audible and unfair); you instead adjust the **mapping used for incoming events** (a per-peer `timeline_skew` value). Simple and non-destructive.
5. Use a monotonic local clock (`Time.get_ticks_usec()`), never wall-clock/system time.

### Event replication

Event schema (small, fixed, versioned):

```
GameEvent { type: enum, seq: int, sender: peer_id, song_time: float, payload: Dictionary/packed }
types: HULL_STATE, TORPEDO_LAUNCH, TORPEDO_REFLECT, ELIMINATED, FINAL_SCORE, TARGET_CHANGED(optional), PING_FX(optional)
```

- **Reliable-ordered** channel for TORPEDO_*, ELIMINATED, FINAL_SCORE, match-phase messages (volume is tiny: a handful per minute).
- **Unreliable** channel for HULL_STATE heartbeat (4-10 Hz). Latest-wins.
- **Topology:** star through the host for authority (host validates and relays), or full mesh broadcast with host validating only match-level events. For 2-4 players the star is simplest and consistent: sender -> host -> target(s). Cost: one extra hop of latency, already covered by flight time. If using star, the host's own client is just another peer using the same channel in loopback.
- **Arrival rule (beat-quantized):** event carries `t_arrive` computed by the sender as a *song time on the shared timeline*. Receiver schedules at `max(t_arrive, now_song_time + min_lead)`, then quantizes up to the next beat boundary (tempo-map aware). All peers' tempo maps are identical, so the quantization result is identical unless the "now" differs, in which case the later boundary wins on the late receiver only; acceptable.
- **Ordering and dedupe:** `seq` per sender; receivers ignore duplicates. Torpedo `id = (sender, seq)`.
- **Seeded effects:** include `rng_seed` in TORPEDO_LAUNCH so Ghost/Depth Charge placement is deterministic on the *target's* machine (only the target needs to generate notes; others just show the payload icon).
- **Exploit surface:** judging is local, so a modified client can lie about hull or never take damage. For a friend group this is **accepted** (trust model: peers trusted for their own hull/score; host trusted for match flow). Host-side sanity checks are cheap and worthwhile: rate-limit torpedoes by charge rules (max one per N streak-notes of the chart), reject torpedo from eliminated non-wreck players, reject `t_arrive` far in the past or future, verify target is alive. Do not invest in anti-cheat beyond that.
- **Host authority summary:** host owns roster, song selection, start time, elimination ordering, winner. Peers own their own hull/score/streak and generate their own torpedoes. Targets own the application of incoming payloads (only they can see their own highway).
- **Host migration:** out of scope. If host drops, the match ends gracefully with last known standings.

## Scene / Autoload Organization

```
res://
  autoload/
    settings.gd          # InputMap + persisted prefs
    calibration.gd
    song_library.gd
    net_session.gd
    event_bus.gd         # optional: global signals for UI/FX (keep small)
  core/                  # no scene-tree dependencies where possible; testable headless
    conductor.gd
    chart/ chart_data.gd, chart_importer_chart.gd, chart_importer_midi.gd, lane_mapper.gd
    judge/ input_judge.gd, judge_config.gd
    state/ hull_score.gd, torpedo_tube.gd, modifier_stack.gd, payloads/*.tres|gd
    net/ game_event.gd, event_channel.gd, net_event_channel.gd, loopback_channel.gd, bot_channel.gd
  scenes/
    boot/ main_menu, settings, calibration
    lobby/ lobby.tscn
    match/ match.tscn, player_rig.tscn, highway_view.tscn, rival_panel.tscn, hud.tscn
    results/ results.tscn
  assets/ shaders/ (CRT, fog, sweep), audio/, bundled_songs/
  tests/ (GUT or gdUnit4)
```

Autoload discipline: keep autoloads to **services with global lifetime** (settings, calibration, library, network session). Per-match objects (Conductor, ChartRunner, HullScore, ModifierStack, channels) live in the Match scene and are created/freed per match, so restarts are clean and tests can instantiate them without autoloads.

Scene flow: `Boot -> MainMenu -> {SoloSetup | Lobby} -> Match -> Results -> MainMenu`. Match receives a `MatchConfig` resource (song, difficulty, seed, roster, mode, start_time, channel kind); nothing else is passed through globals.

Use signals for upward notifications (view, FX, HUD subscribe to HullScore, InputJudge, etc.) and direct method calls downward. Avoid a global event bus for gameplay-critical paths; reserve it for UI/FX convenience.

## Making It Testable Offline

This is the main payoff of the `EventChannel` abstraction.

1. **Solo Dive** uses `LoopbackChannel`: the player's own torpedoes can be redirected to self (training payloads menu to trigger any payload on demand), roster has one entry.
2. **Bot rivals** (`BotChannel` / `BotRival` nodes): produce `HULL_STATE` and `TORPEDO_LAUNCH` events on a schedule or by simulated accuracy (e.g. hit probability p, streak model), with **configurable latency and jitter injection** (delay queue) and packet loss for unreliable messages. This exercises beat-quantized arrival, late-arrival clamping, elimination flow, and the RivalProxy UI with zero network.
3. **Two-instances-on-localhost:** Godot can run multiple instances (Debug -> Run Multiple Instances); ENet to 127.0.0.1 tests the real transport, lobby, and scheduled start. Add a debug `NetworkConditioner` (artificial delay/jitter on send) to approximate internet play; also test through a real VPN early.
4. **Headless unit tests** (GUT or gdUnit4; VERIFY compatibility with chosen Godot version) for pure logic: tempo map conversion, `.chart` parsing against fixture files, MIDI parsing, judgment window edge cases, ModifierStack time windows, beat quantization, payload determinism with seeded RNG, event dedupe.
5. **Autoplay bot for the local player:** a `SimulatedInput` source that feeds scripted/perfect presses into InputJudge at chart times (with configurable offset/jitter). Lets you check that a perfect run yields all-perfect judgments (verifies clock correctness end to end) and soak-test long songs headless. Design InputJudge to take a `press(lane, song_time)` API so real input and synthetic input use the same path.
6. **Debug overlay:** shows song_time, audio-derived vs frame-derived drift, last N hit deltas (histogram), clock offset estimates, RTT, queued events. Cheap and invaluable for tuning feel.
7. **Calibration tool doubles as a test harness** (PROJECT.md mentions solo mode for calibration and chart import testing).

## Patterns to Follow

### Pattern 1: Single time authority
**What:** Everything gameplay-related reads `Conductor.song_time()`; nothing integrates `delta`.
**When:** Always.
**Why:** Prevents drift between audio and visuals; makes seeking/pausing/testing trivial.

### Pattern 2: Chart immutable, modifiers are overlays
**What:** Payloads never edit ChartData; they are overlays (lane map, speed, fog, injected notes).
**When:** Every payload.
**Example:**
```gdscript
func effective_lane(raw_lane: int, t: float) -> int:
    for p in active_at(t):
        if p.has_lane_transform:
            raw_lane = p.lane_transform(raw_lane)
    return raw_lane
```

### Pattern 3: Event channel interface with swappable backends
**What:** Gameplay depends on `EventChannel`; network, loopback, and bot implement it.
**When:** All cross-player information.

### Pattern 4: Seeded determinism for shared content
**What:** Any randomness affecting a note layout derives from a seed in the event.
**When:** Ghost notes, depth charges.

### Pattern 5: Optimistic local, authoritative match flow
**What:** Local effects (launch FX, tube drain) happen immediately; host only arbitrates match-level facts.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Frame-time song clock
**What:** `song_time += delta` in `_process`.
**Why bad:** Drifts against audio; breaks on hiccups; makes calibration meaningless.
**Instead:** Audio-derived time with latency compensation.

### Anti-Pattern 2: Networked judgment or lockstep
**What:** Sending inputs or waiting for peers to judge hits.
**Why bad:** Latency enters the feel; violates the Core Value.
**Instead:** Local judgment, event-only networking.

### Anti-Pattern 3: Torpedo directly mutating remote hull
**What:** Attacker applies damage to a target.
**Why bad:** Cross-client desync, unfair, requires reconciliation.
**Instead:** Payloads install modifiers; only the owner changes their hull.

### Anti-Pattern 4: RPCs sprinkled through gameplay scripts
**What:** `rpc()` calls in HullScore/TorpedoTube/etc.
**Why bad:** Untestable offline; transport swap becomes a rewrite.
**Instead:** EventChannel only.

### Anti-Pattern 5: Parsing charts in the match scene on load of every game
**What:** Parse `.mid`/`.chart` each launch.
**Why bad:** Hitches, inconsistent results on versions.
**Instead:** Parse and cache at library scan; hash for lobby matching.

### Anti-Pattern 6: Seeking audio to correct drift mid-song
**What:** Re-syncing by changing playback position.
**Why bad:** Audible glitch, shifts hit timing for the player.
**Instead:** Adjust the event-timeline mapping only.

### Anti-Pattern 7: Per-note Node objects for the highway
**What:** Instantiating a scene per note for dense charts (Depth Charge bursts).
**Why bad:** GC/allocation hitches in the hot path.
**Instead:** Pool nodes or draw with `MultiMeshInstance2D` / custom `_draw` over the active window only (typically < 100 visible notes).

## Scalability Considerations

(Scale here = players and chart density, not users.)

| Concern | 1 player (solo) | 4 players | Dense charts / edge |
|---------|-----------------|-----------|---------------------|
| Rendering | 1 full highway | 1 full + 3 mini highways; mini views cheap (reuse chart, no judging) | Pool/MultiMesh notes; cap visible notes |
| Network | none | tiny: <10 events/min reliable + ~40 small unreliable pkts/s total | unaffected |
| Chart parse | once per scan, cached | same | Large MIDI files: parse in a thread (`WorkerThreadPool`) |
| Clock | audio-derived | + offset per peer | Long songs: monitor drift logging |
| Host load | n/a | host also plays; relay work negligible | n/a |
| Sync tolerance | n/a | ~100 ms timeline skew acceptable due to beat quantization and flight lead | n/a |

## Suggested Build Order (dependencies drive this)

1. **Conductor + minimal highway + autoplay** (no input yet): load a hard-coded chart and an OGG; scroll notes against `song_time`; verify sync with a metronome click test. Depends on: nothing. Risk-retiring for the core feel. Debug overlay here.
2. **InputJudge + calibration + HullScore**: real input timestamps, windows, hull/streak, hit feedback, audio/visual offset tap-test. Depends on 1. *Gate:* a solo song feels tight.
3. **Chart import (.chart first) + SongLibrary + hash + bundled songs**: ChartData, tempo map, lane mapper, cache. Depends on 1 (model), enables real content. `.mid` import follows later (separate task, isolated by `ChartData` boundary).
4. **EventChannel abstraction + Loopback/Bot channels + RivalProxy/mini panels + TorpedoTube**: build the whole torpedo gameplay offline against bots. Depends on 2. *Gate:* a solo+bots match is fun and testable without sockets.
5. **ModifierStack + the five payloads + Return-to-Sender**: add one payload at a time (Pressure Crack and Fog are view-only and easiest; Lane Flip next; Ghost Notes and Depth Charge need chart injection and seeded RNG; Return-to-Sender last). Depends on 4.
6. **NetSession + lobby + ENet (localhost two-instance) + clock sync + scheduled start**: first real transport, using `NetEventChannel`. Depends on 4 (interface) so the swap is mechanical. Include `NetworkConditioner`. *Gate:* two local instances start in sync, torpedoes land beat-aligned.
7. **Internet play over chosen transport** (VPN docs first; GodotSteam later if wanted): real-world latency tuning of flight time, sync tolerance, drift handling. Depends on 6.
8. **Match flow completion**: elimination, wreck-ghost, winner determination, results screen, disconnect handling. Depends on 6 (host referee) and 4.
9. **Polish layer**: CRT shaders, bioluminescence, audio feedback (creaks, low-pass), juice. Largely independent; can start in parallel after 2 using signals only, but schedule after gameplay is proven.
10. **MIDI import, rebinding UI, gamepad polish, 2v2 prep**: independent, boundary-clean additions.

**Why this order:** it retires the biggest feel risk (audio-clock timing) first, then builds all versus gameplay offline behind an interface so networking becomes a transport swap rather than a redesign, and defers NAT/transport decisions until the game itself is worth playing.

**Parallelizable:** chart importer (3) can proceed alongside 2 once ChartData is defined; visual/CRT work (9) alongside 4-5.

## Phase Research Flags

- Conductor/latency details on Windows (WASAPI buffer, output latency reporting): needs a short spike with measurement before committing (phase 1).
- NAT traversal / transport (Tailscale vs GodotSteam): decision research before phase 7; not blocking earlier phases.
- MIDI chart quirks (open notes, tap/HOPO markers, SysEx, multiple tempo tracks): research when reached.
- 5-fret to 4-lane mapping: gameplay experiment with real charts, not research.
- Clock sync accuracy over real internet: measure in phase 6/7.

## Sources

- Godot docs, "Sync the gameplay with audio and music" (AudioServer.get_time_since_last_mix, get_output_latency pattern), training knowledge, not re-fetched this session: MEDIUM
- Godot docs, High-level multiplayer / ENetMultiplayerPeer / MultiplayerPeer abstraction: MEDIUM (training knowledge)
- Clone Hero `.chart` format and MIDI note-number conventions (community-documented, e.g. Moonscraper/GuitarGame_ChartFormats docs): MEDIUM (training knowledge)
- NTP-style offset estimation (lowest-RTT sample selection): standard technique, HIGH as a technique
- GodotSteam / SteamMultiplayerPeer, Tailscale/ZeroTier as VPN overlay: MEDIUM, verify version compatibility at adoption
- PROJECT.md (UNDERTOW) for requirements and constraints: HIGH
