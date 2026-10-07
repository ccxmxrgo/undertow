# Technology Stack

**Project:** UNDERTOW (online 2-4 player rhythm versus game, Godot 4)
**Researched:** 2026-10-07

Confidence legend: HIGH = official docs/site fetched this session; MEDIUM = multiple sources or partial verification; LOW = training knowledge or single search result, validate before relying.

## Recommended Stack

### Core Framework
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|-----------|
| Godot Engine (standard, non-.NET build) | **4.7.2-stable** (2026-08-18). Fallback: 4.6.3 | Engine | Latest stable per godotengine.org archive (4.7 released 2026-06-18; 4.7.1 July; 4.7.2 Aug). Pin the exact version in the repo (README + CI) so all friends and the exporter match. | HIGH |
| GDScript | built in | All game code | Matches the project constraint. Hit judgment is a few comparisons per frame; there is no CPU hotspot that needs C#. The standard build avoids the .NET SDK and a larger export. Keep the chart parser and judgment code as pure, typed GDScript classes (`RefCounted`) so they are unit-testable. | HIGH |
| C# / .NET build | NOT used | n/a | Adds SDK install, bigger exports, and friends' machines need nothing extra but it buys nothing here. Only reconsider if profiling shows the chart parser is slow (it will not be). | MEDIUM |

### Audio timing (built-in, no library)
| API | Use | Notes |
|-----|-----|-------|
| `AudioStreamPlayer.get_playback_position()` | Base song time | Advances in mix-chunk steps, so it is stale between mixes. |
| `AudioServer.get_time_since_last_mix()` | Add to playback position | Smooths the chunking. |
| `AudioServer.get_output_latency()` | Subtract | Compensates for the mix-to-speaker delay. |
| Formula | `song_time = pos + time_since_last_mix - output_latency` | This is the official recipe (Godot docs "Sync the gameplay with audio and music"). Clamp so it never decreases between frames (discard smaller values) because of thread jitter. HIGH. |
| Input timestamp | Use `event.timestamp`-style capture if available; otherwise compute song time at the start of `_input()`, not in `_process()` | Judging in `_input` removes up to one frame (~16 ms) of error. Verify in Godot 4.7 that input events are delivered before the frame's render. MEDIUM, validate in a timing spike. |
| User calibration offset | Per-player audio offset plus visual offset, saved in `user://` | Needed regardless: `get_output_latency()` is not reliable on all Windows drivers (WASAPI shared mode, Bluetooth). Ship a tap-to-beat calibration screen. |
| Song playback | Stream OGG Vorbis/MP3/WAV via `AudioStreamOggVorbis.load_from_file()` / `AudioStreamMP3` | Clone Hero charts ship `song.ogg/.opus/.mp3/.wav` and stems. Runtime loading from `user://` or arbitrary paths works with these loaders. Opus is NOT natively loadable at runtime in Godot (verify; may need ffmpeg conversion or reject) — LOW. |
| Audio bus effects | `AudioEffectLowPassFilter` (underwater muffling), reverb, `AudioEffectSpectrumAnalyzer` (visual pulses) | All built in. |

Start song with a scheduled future start (see networking) and `play()` at that moment; set `AudioServer` output latency setting (`audio/driver/output_latency`, default 15 ms) lower only after testing on friends' machines.

### Networking
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|-----------|
| Godot high-level multiplayer API (`MultiplayerAPI`, `@rpc`, `MultiplayerPeer`) | built in | Lobby, event RPCs, clock sync | Only a handful of small events (torpedo fired, hull damage, eliminated, score) cross the wire. RPC with reliable/unreliable channels is more than sufficient. Because judgment is local, no rollback/prediction is needed. Write a thin `NetTransport` abstraction so the peer type can be swapped. | HIGH |
| **GodotSteam GDExtension** | **4.23.1** (Steamworks SDK 1.65 line) | Invites, lobbies, NAT traversal and relay (Steam Datagram Relay) | Solves the real risk: friends behind home routers. Steam Networking Sockets with SDR needs no port forwarding and no paid server; Steam friends list gives invite-by-click. This is the recommended primary transport. | MEDIUM-HIGH (version from godotsteam.com changelog; compat with 4.7.x should be tested) |
| `steam-multiplayer-peer` (expressobits, GDExtension) | check latest on GitHub | Makes Steam Sockets look like a Godot `MultiplayerPeer` so `@rpc` works unchanged | Lets the same game code run over ENet (dev/LAN) and Steam. Asset library listings show support only up to Godot 4.4 — MUST verify it builds/works on 4.7, else fall back to a custom `SteamPeer` wrapper using GodotSteam's `Networking Messages`/sockets directly. Does not support channels or mesh. | LOW-MEDIUM |
| ENet (`ENetMultiplayerPeer`) | built in | Dev/LAN transport and fallback over VPN | Simple host/join by IP. Works with Tailscale/ZeroTier addresses. Needs UDP reachability. | HIGH |
| Steam App ID 480 (Spacewar) | n/a | Test Steam features without paying | Friends must run Steam, be logged in, and all use AppID 480 for development. Caveat: Spacewar is shared by many devs; lobby search must filter by a custom key. A real $100 Steamworks AppID is optional later. | MEDIUM |
| Tailscale or ZeroTier | free tiers | Documented no-code fallback | Gives a virtual LAN so ENet works with zero NAT work and zero engine dependencies. Use as plan B if the Steam peer addon breaks on 4.7. | HIGH (well-known) |
| WebRTC (`WebRTCMultiplayerPeer`, godot-webrtc-native GDExtension) | n/a | NOT recommended | Needs a signaling server plus STUN/TURN; TURN costs money or self-hosting; native build needs an extra extension on desktop. Only worthwhile for web exports, which are out of scope. | MEDIUM |
| Dedicated relay (self-hosted) | n/a | NOT recommended for v1 | Violates "no paid servers". | HIGH |

Clock sync: implement NTP-style ping/pong over the existing RPC channel (several samples, take lowest-RTT), host broadcasts `start_at_host_time`; clients convert to local monotonic time (`Time.get_ticks_usec()`) and start audio at that point. Song-time-stamp every event; schedule effects on the receiver at the next beat.

### Chart parsing (Clone Hero)
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|-----------|
| Custom GDScript `.chart` parser | n/a (write it) | Parse `[Song]`, `[SyncTrack]` (BPM `B`, `TS`), `[Events]`, `[ExpertSingle]` etc. | Format is a simple INI-like text file; ~200 lines in GDScript. No maintained Godot `.chart` library was found (only a JS `parsehero`/`herochartio`, plus a hobby Godot project that did not publish code). Writing it yourself is cheaper than adapting a JS lib. Convert ticks (resolution, default 192) to seconds via the tempo map. | MEDIUM (absence of library = search result only) |
| Custom `.mid` chart reader (built on a MIDI parser) | n/a | `PART GUITAR` track notes 96-100 (Expert) etc., tempo map from meta events | Clone Hero MIDI conventions: note pitch ranges per difficulty (Easy 60-64, Medium 72-76, Hard 84-88, Expert 96-100), 116 star power, 103/104/105 solo/tap/etc. Spec: Moonscraper / Clone Hero docs. | MEDIUM |
| `brainfoolong/gdscript-midi-parser` | check latest | Pure GDScript 4 MIDI file parser, zero dependencies | Preferred: no native binary to ship, easy to vendor and read. Needs verification on real CH `.mid` files (running status, SysEx). | MEDIUM |
| `G0retZ/godot-midi-mport`, `nlaha/godot-midi` | Godot 4.2+ | Alternate MIDI parsers | Backup choices. Importer addons are editor-time; UNDERTOW needs runtime import by players, so prefer a runtime parser. | LOW-MEDIUM |
| `song.ini` parsing | `ConfigFile` | Metadata (name, artist, delay, charter) | Godot's `ConfigFile` handles INI. Note the `delay` field and `[Song] Offset`. | MEDIUM |
| Song hash | `FileAccess.get_sha256()` / `HashingContext` over chart + audio | Lobby "who is missing the song" check | Built in. | HIGH |

Normalize everything to an internal `Chart` resource (lanes 0-3, time in seconds, note type, sustain length) so UI, bundled charts, and network never see a Clone Hero format. Map CH 5-fret to 4 lanes by a defined rule (drop orange or fold) — a design decision for the chart-import phase.

### Visuals and shaders
| Technology | Purpose | Why | Confidence |
|------------|---------|-----|-----------|
| Godot `canvas_item` shader on a full-screen `ColorRect` + `BackBufferCopy` / `hint_screen_texture` | CRT: scanlines, curvature, vignette, chromatic aberration | Standard approach; many open-source Godot 4 CRT shaders (e.g., on godotshaders.com) to adapt. Per-player "periscope" panels: render each rival highway in a `SubViewport` and apply the shader to the `SubViewportContainer` texture. | HIGH |
| `WorldEnvironment` glow (Forward+/Mobile; in Compatibility renderer glow is supported since 4.3) | Bloom | Built in. | MEDIUM |
| Phosphor afterglow | Previous-frame feedback via a persistent `SubViewport` with `render_target_clear_mode = never` blended with fade, or a trail shader | Cheap persistence effect. | MEDIUM |
| Renderer | **Compatibility or Mobile** for broad friend-PC support; Forward+ only if everyone has a modern GPU | A 2D game; Compatibility is the safest on integrated GPUs and has lowest latency risk. Decide in the visual phase after testing glow quality. | MEDIUM |

### Testing
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|-----------|
| **gdUnit4** | 6.x (v6.1.3 listed 2026-04-27; one source said 6.2.1, "based on Godot 4.5+, not backward compatible") | Unit tests, scene runner, CLI + JUnit XML | Active, has scene runner and input simulation useful for lane/judgment tests, headless CLI for CI. | MEDIUM (version details inconsistent between sources; check Asset Library/GitHub when installing) |
| GUT | 9.6.1 (Godot 4.6 line) | Alternative | Also fine and GDScript-only. Pick one, not both. gdUnit4 chosen for scene runner and better editor inspector. | MEDIUM |
| Deterministic sim tests | Plain GDScript with a fake `Clock` | Judgment, tempo map, hull/torpedo rules, clock sync math | Inject time as a parameter so tests do not need real audio. | HIGH |
| Network tests | Two headless Godot instances over ENet on localhost with artificial delay (OS tools such as `clumsy` on Windows) | Verify torpedo landing and start sync | Manual/semi-automated. | MEDIUM |

### Export and infrastructure
| Technology | Purpose | Why | Confidence |
|------------|---------|-----|-----------|
| Godot export templates 4.7.2 (Windows Desktop, x86_64) | Build `.exe` + `.pck` | Install via Editor > Manage Export Templates. Use "embed PCK" for a single exe if desired. Include GodotSteam DLLs and `steam_appid.txt` (480) next to the exe for dev builds. | HIGH |
| Godot CLI `--headless --export-release` | Repeatable builds | Script it (PowerShell) for sending builds to friends. | HIGH |
| Install via `winget install GodotEngine.GodotEngine` or direct zip from godotengine.org | Setup (Godot not installed) | Verify winget package version matches the pinned 4.7.2; otherwise download the zip and add to PATH. | MEDIUM |
| Git + `.gitignore` for `.godot/`; Git LFS only if bundled audio gets big | Version control | | HIGH |
| Distribution | Zip over Discord / itch.io private (butler) / Steam playtest later | Friend-group scale. Windows SmartScreen will warn on unsigned exe; tell friends. | MEDIUM |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Language | GDScript | C# | Extra tooling, no perf need. |
| Transport | GodotSteam (SDR) + ENet fallback | WebRTC | Signaling/TURN infrastructure; web-only benefits. |
| Transport | GodotSteam | Self-hosted relay | Costs money and ops time. |
| NAT fallback | Tailscale/ZeroTier | UPnP / manual port forward | Unreliable across home routers. |
| Netcode model | Local judgment + event RPCs | Rollback / lockstep | Unnecessary since rhythm timing is local. |
| Chart parser | Write own | Port JS `parsehero` | Language mismatch; format is simple. |
| Tests | gdUnit4 | GUT | Either is OK; see above. |
| Audio sync | Built-in AudioServer formula + calibration | FMOD/Wwise GDExtension | Overkill, extra licensing. |
| Engine | 4.7.2 | 4.6.3 | Only if a required GDExtension (steam-multiplayer-peer, GodotSteam) fails on 4.7. |

## Installation

```powershell
# Engine (pin version)
winget install GodotEngine.GodotEngine
# or download Godot_v4.7.2-stable_win64.exe.zip from godotengine.org and add to PATH

# Addons (copy into res://addons/ via Asset Library or GitHub release)
# - GodotSteam GDExtension 4.23.1   (godotsteam.com / GitHub GodotSteam/GodotSteam)
# - steam-multiplayer-peer          (expressobits) -- verify Godot 4.7 support
# - gdUnit4 6.x                     (Asset Library or MikeSchulze/gdUnit4)
# - gdscript-midi-parser            (brainfoolong) -- vendor into addons/ or scripts/vendor/
```

## What NOT to use
- Godot 3.x, or alpha/beta/dev 4.x builds (instability, addon incompatibility).
- `AudioStreamPlayer.get_playback_position()` alone, or `_process(delta)` accumulation, as the song clock (drifts and steps).
- Network-synchronized hit judgment (latency would decide fairness).
- Godot's `MultiplayerSynchronizer`/`MultiplayerSpawner` for the highway (no per-frame state needs replication).
- The old GodotSteam "module" (custom engine build) or Godot 3 GodotSteam; use the GDExtension.

## Key Uncertainties to Resolve Early (spikes)
1. Does steam-multiplayer-peer work on Godot 4.7.2 with GodotSteam 4.23.1? (Else custom wrapper or Tailscale+ENet.)
2. Measured end-to-end audio/input latency on Windows 11 with default driver; is `get_output_latency()` trustworthy?
3. Runtime loading of OGG/MP3/Opus from arbitrary paths; Opus unsupported natively (verify).
4. Exact gdUnit4 version/compat with 4.7.2.

## Sources
- Godot download archive (versions/dates): https://godotengine.org/download/archive/ (HIGH)
- Godot docs, Sync the gameplay with audio and music: https://docs.godotengine.org/en/4.2/tutorials/audio/sync_with_audio.html (HIGH; formula)
- GodotSteam GDExtension changelog: https://godotsteam.com/changelog/gdextension (HIGH for 4.23.1; SDK 1.65 as of v4.21)
- GodotSteam repo: https://github.com/GodotSteam/GodotSteam
- Steam Multiplayer Peer (expressobits): https://github.com/expressobits/steam-multiplayer-peer (LOW-MEDIUM, from asset library listings)
- gdUnit4: https://github.com/MikeSchulze/gdUnit4 ; GUT: https://github.com/bitwes/Gut (MEDIUM; versions from search)
- MIDI parsers: https://github.com/brainfoolong/gdscript-midi-parser , https://github.com/G0retZ/godot-midi-mport , https://github.com/nlaha/godot-midi (LOW-MEDIUM)
- Chart libs in other languages (reference for the format): https://github.com/bumpmann/herochartio , https://npmjs.com/package/parsehero
