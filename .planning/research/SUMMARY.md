# Project Research Summary

**Project:** UNDERTOW
**Domain:** Competitive online rhythm game (Guitar Hero / Clone Hero lineage) with Tetris 99 / Puyo-style attacks, 2-4 friends, peer-hosted, Godot 4
**Researched:** 2026-10-07
**Confidence:** MEDIUM

## Executive Summary

UNDERTOW is a rhythm game where each player's machine runs its own simulation, with a thin layer of network events on top. Every client judges hits locally against its own audio clock. The network only carries a small number of events stamped with song time: torpedo launched, hull state, eliminated, final score.

Torpedoes never change another player's hull. They install beat-quantized "modifier overlays" (lane map, scroll speed, fog, injected notes) on the target's own highway, and the target only takes damage from its own misses. This rules out desync between clients and protects the Core Value: ping never affects timing feel. The torpedo's flight time (at least ~2 beats) is the latency budget. Snapping arrival to the beat hides network jitter and also works as the gameplay warning that an attack is coming.

**Recommended approach:**
- Godot 4.7.2, standard build, version pinned.
- Pure typed GDScript.
- The official audio-clock recipe: `playback_position + time_since_last_mix - output_latency`, clamped so it never goes backwards, with input timestamped in `_input()`.
- All versus gameplay goes behind an `EventChannel` interface with Loopback, Bot and Net implementations. Torpedoes, payloads, elimination and balance get built and tuned offline against bots that simulate latency, before any netcode exists.
- Content comes from a hand-written, tolerant `.chart` parser (`.mid` deferred). It produces a format-agnostic `ChartData`. HOPO and tap notes are flattened to plain notes, and 5-fret charts map to 4 lanes through a pluggable `LaneMapper`.
- Transport defaults to ENet over Tailscale/ZeroTier, which needs no code. GodotSteam is an optional upgrade, gated on a compatibility spike.

**Main risks and mitigations:**
1. **Audio clock and Windows latency.** Frame-quantized input and Windows output latency (WASAPI, Bluetooth) can make timing feel off. Mitigations: an early debug overlay, an autoplay-bot correctness test, and mandatory audio and visual calibration.
2. **NAT traversal.** It tends to get ignored until the first remote playtest. Mitigation: a transport decision gate before internet play.
3. **GH3-style unfair attacks and dogpiling the leader.** Mitigations: every attack has a warning, only one payload at a time, an immunity window after each one, no mash-to-clear, no instant kills, and payload strength bounded by how dense the chart is.
4. **Scope creep.** This is a solo hobby project. Mitigations: the vertical-slice order below, plus a playtest gate before each new payload.

## Key Findings

### Recommended Stack

Godot 4.7.2-stable (fallback 4.6.3), the standard non-.NET build, GDScript throughout. Time, judgment, chart parsing and rules logic go in `RefCounted` classes, so they can be unit-tested headless with a fake clock injected.

- **Godot 4.7.2 standard + GDScript.** C# buys nothing for this workload. Pin the same version for every friend.
- **Audio clock.** The `AudioServer` recipe plus per-player audio and visual offsets saved in `user://`. Never accumulate `delta`.
- **Networking.** Godot high-level multiplayer (`@rpc`, `MultiplayerPeer`) over `ENetMultiplayerPeer`, hidden behind `NetSession` and `EventChannel`.
- **Internet path.** Tailscale/ZeroTier + ENet is the default. GodotSteam 4.23.1 (Steam relay and invites) is an optional upgrade. `steam-multiplayer-peer` is only verified up to Godot 4.4 (confidence LOW-MEDIUM), so it needs a spike.
- **Charts.**
  - A custom GDScript `.chart` parser (about 200 lines).
  - `song.ini` read via `ConfigFile`.
  - `.mid` later, via `brainfoolong/gdscript-midi-parser` or a small hand-written reader.
- **Tests.** gdUnit4 6.x or GUT; pick one.
- **Visuals.** A `canvas_item` CRT shader. Rival "periscope" panels render in `SubViewport`s. The Compatibility renderer is probably the right choice for friends' PCs.
- **Audio formats.** Opus probably can't be loaded at runtime. Support OGG, MP3 and WAV, and fail cleanly on Opus.

### Expected Features

**Table stakes:**
- Audio-clock scrolling and judgment with 3 timing tiers.
- Per-player audio and visual calibration.
- Hit feedback.
- Hull and elimination.
- Combo (for score) kept separate from the Perfect streak (for torpedo charge).
- Sustains and chords. HOPO and tap notes flattened; no strum key.
- `.chart` import with 5-to-4 lane mapping.
- Song select with library scan and cache.
- 1-2 bundled tracks.
- Rebinding and gamepad support.
- Scroll speed and volume settings.
- Pause in solo mode.
- Results screen.
- Lobby with song-hash check and synced start. A disconnect counts as elimination. No pausing online.
- Visible torpedo tube.
- Warning when a torpedo is incoming.
- Every payload survivable.
- Target cycling, with the leader as default.
- Rival panels.

**Differentiators:**
- Streaks become torpedoes, with no random pickups.
- Launch and arrival snapped to the beat.
- Five payloads.
- Return to Sender.
- Wreck ghosts, with their debris attacks capped.
- An Attackers targeting toggle.
- Training payloads in Solo Dive.

**Defer:**
- `.mid` import (late in v1 at best)
- 2v2 mode
- Auto-charting
- Handicaps
- Extra targeting modes
- Host migration
- Anti-cheat
- Matchmaking
- Chart editor
- Real instrument controllers
- Full CRT polish (but keep a minimal readable look from day one)

### Architecture Approach

Only global services are autoloads: Settings, Calibration, SongLibrary, NetSession. Everything that belongs to a single match lives in the Match scene: Conductor, ChartRunner, InputJudge, HullScore, TorpedoTube, ModifierStack, HighwayView.

Gameplay code never calls `rpc()`. It sends `GameEvent`s through `EventChannel`. The chart is immutable. Payloads are `PayloadDef` resources that install overlays on `ModifierStack`, and they work in three ways:
- **View-only:** Fog and Pressure Crack.
- **Input mapping:** Lane Flip is applied where inputs map to lanes.
- **Generated notes:** Ghost Notes and Depth Charge are injected from a seed, on the target's machine only.

**Major components:**
1. **Conductor:** the single source of song time, with tempo-map beat math.
2. **ChartImporter, ChartData, SongLibrary, LaneMapper:** a tolerant parser that converts ticks to seconds once at import, stores packed arrays, and caches by hash.
3. **InputJudge, HullScore, TorpedoTube:** local judgment through a shared `press(lane, song_time)` API (the autoplay bot uses the same API). The player's own machine is authoritative for its hull.
4. **ModifierStack + PayloadDef:** data-driven overlays, plus tracking of Return-to-Sender warhead notes.
5. **EventChannel (Loopback, Bot, Net) + RivalProxy:** the seam that makes everything testable offline.
6. **NetSession + MatchCoordinator:** the host referees the roster, start time, elimination order and winner. Each peer owns its own hull.

### Critical Pitfalls

1. **Frame-delta clocks, or calling `get_playback_position()` naively.** Use the audio clock with a monotonic clamp, add a debug graph, and run an autoplay test that must score all-perfect.
2. **Windows/Bluetooth latency and frame-quantized input.** Judge hits in `_input()`, ship a mandatory calibration wizard, warn when a Bluetooth device is in use, and test on a friend's PC early.
3. **NAT traversal discovered at the first remote playtest.** Hold a transport decision gate before internet play, and keep the transport behind abstractions.
4. **Torpedoes injected late, and GH3-style unfair attacks.** Snap arrival times to the beat with a minimum lead time, and push late arrivals to the next beat. Allow one payload at a time with an immunity window and a warning. No mash-to-clear, no instant kills, density caps, and Ghost Note cues that don't rely on color alone.
5. **Chart import edge cases.** Resolution other than 192, tempo stored as milli-BPM, time signatures stored as an exponent, BOM, offsets. Write down the 5-to-4 lane rule before starting payload work.
6. **Scope creep.** Build in vertical slices, playtest before each new payload, and keep a cut list: Return to Sender, then wreck debris, then `.mid`, then 4-player-first.

## Implications for Roadmap

**How researcher disagreements were resolved:**
- Match flow (elimination, winner, wreck ghosts, results) gets built offline against bots in Phase 3. Phase 4 only adds real-network concerns.
- Chart import gets its own phase, Phase 2.
- Transport: Tailscale/ZeroTier + ENet is committed for v1. GodotSteam is an optional swap.

### Phase 1: Timing Core, Judgment & Calibration (solo vertical slice)
Godot pin, Conductor with debug overlay, a hard-coded chart and click track, minimal highway, autoplay bot, InputJudge, a 3-tier `JudgeConfig`, HullScore, hit feedback, calibration wizard, rebinding (Tab conflicts with Godot's `ui_focus_next`), solo pause, and an export smoke test on a second PC.
**Gate:** a solo song feels tight on the dev PC and on a friend's PC.

### Phase 2: Chart Import & Content Pipeline
`.chart` parser, `song.ini`, tempo map, `ChartData`, sustains and chords, HOPO/tap flattening, `LaneMapper`, runtime audio loader, SongLibrary and cache, song hash, song select, bundled royalty-free tracks.
**Song hash** = normalized chart + difficulty + importer and mapping version + audio duration, with a fast path on raw file bytes.

### Phase 3: Offline Versus
EventChannel with Loopback and Bot channels (latency, jitter, loss), RivalProxy and periscope panels, TorpedoTube, targeting, ModifierStack and the five payloads (each one playtested before the next), warnings, cap and immunity, Return to Sender, elimination, winner and tie-break, wreck ghosts, results screen, Solo Dive training mode.
**Gate:** a solo + bots match is fun and every payload is readable.

### Phase 4: Online Play
Transport decision gate first. Then NetSession, lobby with hash check and Bluetooth warning, clock sync, host-scheduled start, NetEventChannel, arrival scheduling, drift handling, disconnects, a network conditioner, a localhost test, and a playtest with friends.
**Gate:** 4 friends on 4 PCs start in sync, and torpedoes land on the beat for everyone watching.

### Phase 5: Polish, Secondary Import & Packaging
CRT shaders, bioluminescence, audio feedback, juice, low-effects toggle, profiling, gamepad polish, `.mid` import, packaging.

### Research Flags
- **Phase 1:** Windows latency spike and input timestamping on 4.7.
- **Phase 2:** audio loading matrix and the 5-to-4 lane mapping.
- **Phase 4:** GodotSteam on 4.7, real-world Tailscale latency, clock-sync accuracy.
- **Phases 3 and 5:** standard patterns. Phase 3's open questions are about balance and playtesting, not research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Steam peer on 4.7, gdUnit4 version and Opus support not verified |
| Features | MEDIUM | Timing window values and GH3 attack list come from memory |
| Architecture | MEDIUM-HIGH | API names need checking against the installed Godot |
| Pitfalls | MEDIUM | Several items still marked [VERIFY] |

### Gaps to Address
- **Timing windows.** The research files disagree, so make them data-driven in `JudgeConfig` and tune them in Phase 1. The constraint is about ±50 ms.
- **Torpedo charge rule.** Perfect streak charges the tube; combo is only for score. Tune by playtest.
- **Godot 4.7 APIs.** Verify the audio and loader APIs during the Phase 1 and 2 spikes.
- **Steam peer support.** Unverified on 4.7, but not blocking because the Tailscale route is the fallback.
- **5-to-4 lane rule.** Must be decided before payload generation.
- **Sustains.** Keep them, with a forgiving release window.
- **Match rules.** Tie-break, ghost-attack caps, stacking and immunity values get settled in Phase 3.
- **Anti-dogpile.** Evaluate in Phase 3 playtests.
- **Rival periscope panels.** Decorative, driven by each rival's reported song time and payload state.
- **Test framework.** Pick one in Phase 1.

## Sources

**Primary (HIGH):**
- Godot download archive (4.7.2)
- Godot docs, "Sync the gameplay with audio and music"
- GodotSteam changelog (4.23.1)
- NTP-style clock sync (standard technique)

**Secondary (MEDIUM):**
- Clone Hero / Moonscraper chart format docs
- Godot multiplayer and ENet docs
- gdUnit4 and GUT repos
- Tailscale/ZeroTier
- Community discussion of GH3 Battle Mode and Tetris 99

**Tertiary (LOW):**
- `steam-multiplayer-peer` asset listings
- MIDI parser addons
- Opus and `AudioStreamSynchronized` claims
- Exact timing window numbers

---
*Research completed: 2026-10-07*
*Ready for roadmap: yes*
