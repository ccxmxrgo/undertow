# Domain Pitfalls

**Domain:** Online competitive rhythm game (Godot 4, GDScript, Windows, 2-4 peer-hosted friends, Clone Hero chart import)
**Project:** UNDERTOW
**Researched:** 2026-10-07
**Overall confidence:** MEDIUM. Written from domain knowledge (Godot docs on audio sync, Clone Hero/Moonscraper chart conventions, GH3 battle mode community feedback). No live doc lookups were done in this pass. Items marked [VERIFY] should be checked against current Godot docs (Godot 4.4+ may have changed audio-latency behaviour) before the owning phase starts.

Phase labels used below (map to the real roadmap later):
- P1 Timing core and solo highway
- P2 Chart import and audio loading
- P3 Calibration, input, judgment
- P4 Networking foundation (transport, lobby, clock sync, synced start)
- P5 Torpedoes and payloads
- P6 Polish, visuals, export

---

## Critical Pitfalls

### 1. Driving note position from frame delta or `Time` instead of the audio clock
**What goes wrong:** Notes scroll via `position += speed * delta`, or from `Time.get_ticks_msec()` captured at `play()`. Over a 3-5 minute song, visuals drift from audio by tens of ms. Frame hitches (shader compile, window drag, GC-like spikes) permanently desync.
**Why it happens:** It is the obvious first implementation, and it looks fine for 10 seconds.
**Consequences:** Violates the project's core constraint ("audio clock is source of truth"). Calibration cannot fix drift, only a constant offset.
**Prevention:** Compute `song_time` every frame from the audio playback. Never accumulate delta. All note Y positions are a pure function of `song_time`.
**Warning signs:** Hit offset average changes between the start and end of the same song. Notes visibly "slide" against the click track.
**Phase:** P1.

### 2. Naive `AudioStreamPlayer.get_playback_position()` (mix-chunk granularity plus output latency)
**What goes wrong:** `get_playback_position()` only advances in mix-buffer steps, so the value is stair-stepped (jitter of several ms up to ~10-20 ms, depending on mix buffer). It also reports the position of the mixed data, not what the speakers are playing, so it leads the audible sound by the output latency.
**Prevention:** Use the documented pattern: `get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()`. Then smooth: keep a monotonic estimate by combining a local high-res clock (`Time.get_ticks_usec`) with periodic correction from the audio position, so `song_time` never jumps backwards and never steps. Clamp small corrections, hard-snap only for large errors. Guard against `get_time_since_last_mix()` anomalies at the first frames after `play()`, and when the player is paused or has finished. [VERIFY] whether Godot 4.4+ made `get_playback_position` more accurate; keep the smoothing regardless.
**Warning signs:** Notes jitter at the strike line. Debug graph of `song_time` per frame is stair-stepped or non-monotonic.
**Phase:** P1. Build a debug overlay graphing `song_time` delta per frame right away.

### 3. Windows audio output latency is large, variable, and sometimes lies (WASAPI, Bluetooth)
**What goes wrong:** Godot's default Windows driver is WASAPI shared mode, with project setting `audio/driver/output_latency` (default about 15 ms) plus the OS mixer and device buffering. `AudioServer.get_output_latency()` reflects only Godot's buffer, not the device or Bluetooth stack. Bluetooth headphones add 100-250+ ms (and it changes when the codec renegotiates, e.g. when a mic is activated). Different friends have wildly different latency.
**Consequences:** "Perfect" timing is felt as late/early. Without fairness-grade calibration, the versus mode is unfair by definition.
**Prevention:**
- Mandatory first-run calibration wizard (audio tap test plus visual test) storing separate audio offset and visual offset per player. Apply the offset in judgment and rendering only, never to network timestamps.
- Show a warning in the lobby when the output device name looks like Bluetooth/Hands-Free ("wireless", "Bluetooth", "AirPods"). Recommend wired headphones.
- Re-prompt calibration when the output device changes (`AudioServer.output_device` change detection).
- Expose lowering `audio/driver/output_latency` as a setting and test that crackle does not occur on low-end PCs.
**Warning signs:** One friend always hits "late" by a consistent amount. Calibration result varies >15 ms between runs (usually a sign of the jitter in pitfall 2 or a frame-bound input path).
**Phase:** P3 (calibration), with the measurement hooks laid in P1.

### 4. Input handled at frame granularity (`_process` polling, `Input.is_action_just_pressed`)
**What goes wrong:** Polling in `_process` quantizes hit time to the frame boundary (16.7 ms at 60 Hz, which is a third of a +-50 ms window). Godot also delivers queued input events at the start of the frame, so even `_input` timestamps measured with "now" are late by however long the frame took.
**Prevention:**
- Handle key presses in `_input()` (or `_unhandled_input` after confirming the UI is not eating them). Ignore `event.echo`.
- On press, compute the hit time as `current song_time` at event handling, and consider subtracting an estimate of frame-start-to-event latency. Godot InputEvents have no reliable hardware timestamp in 4.x [VERIFY], so record `Time.get_ticks_usec()` at handling and keep a measured per-frame offset.
- Uncapped or high FPS (disable vsync option, or 144 Hz) directly shrinks input quantization. Offer it in settings. Consider running the game at a fixed high render cap.
- `Input.use_accumulated_input` mainly affects mouse/drag event merging and is mostly irrelevant for keyboard presses. Set it to `false` anyway for the gameplay scene to avoid event coalescing surprises, but do not expect it to fix keyboard latency. [VERIFY] scope in current docs.
- Process input, then judge, in a single place that uses the same `song_time` estimate as rendering.
**Warning signs:** Hit-offset histogram in calibration shows clumps spaced at the frame time instead of a smooth distribution.
**Phase:** P3.

### 5. Local judgment polluted by network concerns (or the reverse)
**What goes wrong:** Attempting to "sync" hit judgment across peers, rollback-style, or stamping judgment with network time. Or applying latency compensation to timing windows.
**Prevention:** Keep the project's stated rule: each client judges only against its own audio clock. The network carries events only (torpedo fired, hull changed, eliminated, score). No peer ever judges another peer's hits. Make this a code-structure rule: the judgment module has zero dependency on the network module.
**Phase:** P1/P3 design, enforced through P4+.

### 6. Timing-window fairness not defined or not uniform
**What goes wrong:** Windows are decided ad hoc, vary by lane or by note type (sustain starts, chords), or are scaled by the local frame rate. Players with high-latency setups feel cheated. Also overstrum/free-press rules: spamming all 4 keys wins if misses are not punished.
**Prevention:**
- Define one global table (e.g. Perfect +-25ms, Great +-50ms, Good +-80ms, tune after playtests) shared by all players in a match and sent in the lobby so the host's version rules.
- Define explicitly: what happens when a key is pressed with no note nearby (hull damage? streak break only?), how chords are judged (each lane within window, order not required), sustain release tolerance, and simultaneous-note handling (closest unjudged note per lane wins).
- Same windows for every payload (Ink Cloud hides notes, but must not change windows).
- Keep hit offset logging per note so playtest disputes can be answered with data.
**Phase:** P3.

### 7. Keyboard ghosting/rollover makes 4-lane chords impossible on some keyboards
**What goes wrong:** Cheap keyboards drop the 3rd/4th simultaneous key depending on the matrix. D-F-J-K plus Space/Tab (fire/target) in one moment can fail, especially "Fire while holding a chord".
**Prevention:** Test with a keyboard-rollover tool early; offer a rebind UI; keep Fire and Target on keys that are electrically independent (modifier keys such as Shift/Ctrl/Alt always register). Do not place the Tab key as target-cycle without handling `ui_focus_next` (Tab is a built-in UI focus action in Godot). Gamepad option helps.
**Phase:** P3.

### 8. 5-fret Clone Hero charts mapped onto a 4-lane highway without a plan
**What goes wrong:** Clone Hero/GH charts have 5 frets (G R Y B O), forced/tap/open flags, and chord shapes up to 5 notes. UNDERTOW has 4 lanes. Naive modulo or dropping a lane produces unplayable or ugly patterns, and "Expert" charts become absurdly dense on 4 keys.
**Prevention:** Decide the mapping up-front and document it: for example, merge Orange into Blue (or fold open into a chord of some kind), reduce 4-5 note chords to 2-3, enforce a minimum same-lane gap, and prefer using Hard/Medium difficulty by default. Add a per-song "difficulty" picker and a quality heuristic (peak notes-per-second warning). Write unit tests with real sample charts.
**Phase:** P2 (decision gate before P5, because Depth Charge payload generation depends on it).

### 9. `.chart` parsing edge cases
**What goes wrong (all of these occur in community charts):**
- `Resolution` is not 192 (common values 192, 480, 960). Converting ticks to seconds with a hard-coded 192 shifts everything.
- Tempo events `B` are in thousandths of a BPM (`B 120000` = 120 BPM). Tempo changes mid-song require a piecewise tick->time map (cumulative seconds per segment). Computing `tick / res * 60 / bpm` with the first BPM breaks every chart with tempo changes.
- Time signature `TS n d` stores `d` as a power-of-two exponent (`TS 4 3` = 4/8). Only matters for bar lines/beat visuals, but wrong guesses create misaligned beat flashes. A missing TS means 4/4.
- Sections may be out of order, have CRLF/LF or BOM (UTF-8 BOM and UTF-16 files exist), trailing whitespace, quoted strings with `=` inside, and duplicate keys.
- `Offset` in `[Song]` (seconds) and `delay` in `song.ini` (ms) differ, are often wrong, and different players interpret them differently. Apply both consistently and expose a per-song user offset.
- Note numbers: `N 0-4` = frets, `N 5` = forced HOPO toggle, `N 6` = tap, `N 7` = open (GHL/open variants exist, charts vary). Event lines with same tick ordering are arbitrary.
- HOPO auto-calculation uses a threshold (about 1/3 beat, e.g. 65 ticks at 192 resolution, scaled by resolution; and chords/same-note repeats are not HOPOs). If UNDERTOW does not use HOPO mechanics (keyboard), decide to ignore HOPO/tap entirely and treat them as regular notes. Do this deliberately.
- Sustains: `N 0 0` is a tap/no-sustain; very short sustains (below ~1/8 beat) should be treated as non-sustains. Sustains overlapping the next note on the same lane must be clipped.
- `[Events]` with `section`, `lyric`, `phrase_start`, and star power `S 2 len` entries. Ignore unknown keys instead of failing.
**Prevention:** Hand-written tolerant parser (do not use a strict grammar). Fixture set of 10+ real charts covering tempo changes, odd resolution, BOM, and missing sections. Unit test tick->time against known timestamps. Fail soft with a visible warning, not a crash.
**Phase:** P2.

### 10. `.mid` chart parsing edge cases
**What goes wrong:**
- Track names matter: `PART GUITAR`, `PART BASS`, `PART RHYTHM`, `PART KEYS`, `PART DRUMS`, older `T1 GEMS`, `PART GUITAR COOP`. Tempo/time-signature live in the first (sync) track, not the instrument track. Picking "the first track with notes" picks the wrong one.
- Note pitch ranges by difficulty: Easy 60-64, Medium 72-76, Hard 84-88, Expert 96-100 (five frets each). Pitch 116 = star power, 103/105/106 = solo/other markers, and other pitches (e.g. 120-127) are animation/BRE. They must not become notes.
- Open notes via SysEx (and `ENHANCED_OPENS` text events) and forced HOPO via pitches 65/66, 77/78, 89/90, 101/102. Tap via SysEx.
- MIDI quirks: running status, note-on with velocity 0 as note-off, Format 0 vs 1, variable-length quantity, PPQ other than 480, tempo meta events being the only source of tempo (missing tempo = 120 BPM default).
- Godot has no MIDI file parser in core. [VERIFY] There is `InputEventMIDI` for devices but not SMF file parsing. Plan to write a small SMF reader in GDScript (about 200 lines) or consider a library. Do not count on an off-the-shelf solution.
**Prevention:** Support `.chart` first (text, easier). Treat `.mid` as a second milestone gated by the fixtures. Keep a single internal `ChartModel` (notes with `time_ms`, `lane`, `duration_ms`, plus tempo map and beat grid) so the renderer never sees format specifics.
**Phase:** P2 (`.chart`), P2b/late for `.mid`.

### 11. Audio file format and loading problems at runtime
**What goes wrong:**
- Imported songs live outside `res://` (`user://` or a user folder), so Godot's import pipeline does not run on them. They must be loaded at runtime: `AudioStreamOggVorbis.load_from_file()` [VERIFY exact API for the Godot version], `AudioStreamMP3` with `.data = FileAccess.get_file_as_bytes(path)`, `AudioStreamWAV` for wav. Naively using `load("path.ogg")` fails in exported builds.
- Clone Hero songs use `.ogg`, `.mp3`, `.wav`, and often `.opus`. Godot does not decode Opus files natively as far as I know [VERIFY]. Plan on documenting a required conversion, or bundling a converter step (ffmpeg is a third-party dependency).
- MP3 decoders insert encoder delay/padding (tens of ms unless gapless metadata is honoured), so the same chart may be offset against MP3 vs OGG. OGG is the safest default for bundled tracks.
- Seeking: OGG streaming seek is fine but not sample-accurate; MP3 seeking can be coarse. Practice "restart from section" and lead-in start require seeking. Prefer starting playback from 0 with a silent lead-in (play at `-N s` song time via the clock) over `play(from_position)` for the sync start.
- Multi-stem songs (`guitar.ogg`, `rhythm.ogg`, `song.ogg`, `drums.ogg`): starting several `AudioStreamPlayer`s separately drifts or starts at different mix chunks. Use `AudioStreamSynchronized` (Godot 4.3+) [VERIFY], or pre-mix, and use one reference player for the clock.
- Loop points: bundled tracks that loop (menu music) can click at the loop point when decoded from MP3; use OGG loop offsets or WAV.
- Long songs decoded to memory (WAV) are large; stream from OGG.
**Prevention:** Build the song loader as a single module with a format matrix test. Have one known test song in each format with a click track so you can measure offset between formats.
**Phase:** P2.

### 12. NAT traversal ignored until the first remote playtest
**What goes wrong:** Godot's `ENetMultiplayerPeer` needs a reachable UDP port. Friends behind home routers (and CGNAT, which cannot be fixed by port forwarding) cannot connect. Port forwarding instructions for friends are a social failure mode. No hole punching in ENet.
**Prevention (opinionated):** Choose one transport on day one of P4 and build the lobby around it:
- Easiest for a friend group: Tailscale/ZeroTier (friends install one app, all connect by virtual IP; ENet over it just works; adds a small relay latency when direct connection fails). Zero code cost.
- Best UX if everyone has Steam: GodotSteam with Steam Networking Sockets (relay and NAT punching built in). Dev can use the Spacewar test AppID 480 but this restricts distribution. [VERIFY] licensing and GodotSteam version compatibility with the chosen Godot version.
- Self-managed: a tiny WebSocket/WebRTC signaling server plus STUN/TURN (WebRTC data channel in Godot). More moving parts; only if the above are rejected.
Abstract the transport behind a thin interface so it can be swapped. Keep the game on `MultiplayerPeer`.
Also: Windows Defender Firewall prompt on first host (explain in UI), host's IP/port display, and a connection test button.
**Warning signs:** "Works on LAN/localhost" is the only test that has passed.
**Phase:** P4. This is a decision gate, not an implementation detail. Needs its own research task.

### 13. Clock sync done once, naively, or conflated with audio clock
**What goes wrong:** A single ping measured at join (one sample, possibly an outlier) is used to align song starts; or the system clock difference between PCs is assumed zero; or song start is "host sends start, everyone starts on receipt" so the offset equals one-way latency per player.
**Prevention:**
- Run an NTP-style exchange (client t0, host t1/t2, client t3): repeated 10-20 times, take the sample with the minimum RTT, offset = ((t1 - t0) + (t2 - t3)) / 2. Keep refreshing during the lobby and mid-song with a low-rate, smoothed update (do not step the clock).
- Use a monotonic local clock (`Time.get_ticks_usec`), never wall clock (system time can jump with NTP adjustments).
- Host broadcasts "start at host_time T" with T at least ~2-3 s in the future (longer than worst-case RTT, plus load time). Each client converts T to local monotonic time and begins the audio so that `song_time == 0` lines up with T, including the audio output latency (start playing `output_latency` early or compensate when mapping).
- After start, the mapping from local monotonic clock to audio clock is established per client; do not keep re-syncing audio. Drift between audio device clocks and the system clock over a 4-5 min song is real (tens of ppm) but small; do not try to re-align the audio mid-song.
- Pre-load and decode everything before the countdown; confirm "ready" from each peer before the host schedules the start.
- Only events need cross-peer song-time agreement; the exact milliseconds of "who's ahead" do not matter for judgment. Define the tolerance explicitly (probably +-50-100 ms is fine for torpedo arrival).
**Warning signs:** Torpedoes land at visibly different beat positions for different observers. Players report "his sub started a second earlier".
**Phase:** P4.

### 14. Torpedo arrival inserted into the already-visible part of the highway
**What goes wrong:** An attack arrives over the network, and its notes are injected at a song time that is already on screen or already passed for the target. Players see notes pop in, or ghost notes appear after the strike line. A late-arriving packet makes the attack either unplayable or silently skipped.
**Prevention:**
- Torpedoes carry `arrival_song_time` (beat-quantized) chosen by the sender with a lead of at least `scroll_time_on_screen + max_expected_latency` (look-ahead window of the target's highway). If the packet arrives later than that, quantize to the next beat/bar that is still in the future instead of dropping.
- The target decides locally where the payload attaches to its own chart (its own song_time), so the payload can never retroactively modify what has already been shown.
- Payload content must be deterministic from a shared seed plus the chart, so both sides can render the periscope panel identically (ghost note positions, depth-charge notes).
- Use reliable-ordered delivery for events (fire, hit, hull, eliminated) with sequence IDs; make handlers idempotent so duplicates do not double-damage.
- Host (or each owner) is the authority for its own hull/score; others only display. Eliminated/final-ranking decisions are arbitrated by the host to resolve simultaneous deaths and ties.
**Phase:** P4 design, P5 implementation.

### 15. Attack balancing repeats the GH3 battle mode mistakes
**What goes wrong (GH3 battle mode community lessons):** unreadable or unavoidable attacks (broken string needing frantic mashing, Lefty Flip with no cue), attacks that stack so a player is effectively dead (Death Drain), snowballing (the leader gets attacked and the leader's attackers earn more), RNG power-up allocation, and the sense of "I lost for reasons that weren't my skill". In 4-player FFA, dogpiling the leader is the Nash equilibrium; hostile targeting makes the lowest player quit.
**Prevention (stated design rule: "counterplay, not punishment"):**
- Every payload gets a clear telegraph: 1-2 beats of audio+visual warning on the target before it takes effect, plus a distinctive silhouette (colorblind-safe, not hue-only. Ghost Notes must differ by shape/animation as well as colour).
- Hard cap: only one active payload per target at a time (queue the rest), or a cap on total affected beats per bar. Mandatory immunity window (e.g. 1 bar) after a payload ends.
- Payload damage is bounded: Ghost Note cost small, Depth Charge density capped to a playable maximum for the chart's difficulty (min gap per lane, max notes per second), generated from the song's own rhythm and validated.
- Ink Cloud must leave enough visible highway for reaction and never fully hide the strike zone. Pressure Crack should ramp up/down and not change when the note hits (timing from `song_time`, only the spacing changes).
- Lane Flip: show the flip as a visual swap (animated), keep the flip to a bounded duration and exclude from chords near the swap.
- Anti-dogpile: default targeting should not always be "leader". Add a mild catch-up (leader costs more charge, or trailing players charge faster). Playtest with 3-4 actual people early.
- Wreck-ghost debris attacks must be weak enough that being dead is not a kingmaker role, and ideally cannot target the lowest remaining player.
- Return-to-Sender must be possible at skill (marked warhead notes forgiving of a missed one? choose deliberately) or it becomes a no-op.
**Warning signs:** Playtesters can't say what killed them. Games end in <60 s after the first torpedo. One payload dominates fire choices.
**Phase:** P5. Plan a dedicated balance/playtest iteration; do not ship all five payloads untuned.

---

## Moderate Pitfalls

### 16. Frame hitches from shader compilation, bloom/CRT post-processing, and asset loading mid-song
**What goes wrong:** The first torpedo effect compiles a shader mid-song, causing a visible stutter; the CRT/bloom/scanline pipeline is too heavy for a friend's integrated GPU; four periscope sub-viewports (rival highways) multiply the draw cost.
**Prevention:** Pre-warm all materials and particles during load (spawn each effect once off-screen). Budget the post-processing, provide a "low effects" toggle, render rival periscopes cheaply (simplified draw, lower update rate), and use the Compatibility/Forward+ renderer choice deliberately and test on the weakest friend's PC. Because timing is audio-clock-based, hitches do not break judgment but do hurt feel. Frame time spikes still hurt input quantization (pitfall 4).
**Phase:** P6, but profile from P1 with the CRT shader on.

### 17. Song hash identifies the wrong thing
**What goes wrong:** Hashing audio bytes breaks when friends have different encodes of the "same" song. Hashing only the filename/folder breaks with renamed folders. Different chart versions of one song produce different note counts and unfair matches.
**Prevention:** Hash the parsed normalized chart (notes + tempo map + chosen difficulty + mapping version) plus the audio duration, not raw file bytes alone. Include the app's chart-mapping version in the hash so parser changes invalidate. Show missing/mismatch with a reason. Optionally allow the host to push a small chart (not audio) to peers, since audio is copyrighted and chart data is the cheaper part. Careful: audio length mismatch implies offsets differ.
**Phase:** P2 for hash design, P4 for lobby.

### 18. Disconnects, joins, and pause semantics in a real-time song
**What goes wrong:** A player drops mid-song and the others hang waiting; the host leaves and the match dies; someone alt-tabs and audio continues but input is lost; there is no pause in multiplayer.
**Prevention:** Treat disconnect as elimination after a short grace window (keep the game running). Host migration is out of scope for v1, but make the host leaving end the match cleanly with a result screen. No pause in versus; pause only in Solo. Handle window focus loss by releasing held keys/sustains (otherwise stuck keys cause phantom holds).
**Phase:** P4.

### 19. Hidden dependence on tick rate / float precision
**What goes wrong:** Using `float` seconds from the audio clock for long songs is fine, but storing note times as floats from tick conversions accumulates error; comparing floats for equality in chord grouping fails.
**Prevention:** Store chart times in integer milliseconds (or microseconds) after conversion. Group chords with a tolerance (a few ms) or by tick.
**Phase:** P2.

### 20. Godot export gotchas
**What goes wrong:** Non-resource files (`.chart`, `.mid`, `.ini`, bundled data) are not exported unless included via the export filter (`*.chart, *.ini, *.mid`). `res://` is read-only in exported builds, so writes (calibration, settings, imported songs, caches) must go to `user://`. Export templates must match the editor version exactly. Missing audio device at startup (no output) can break the clock logic. Antivirus/SmartScreen flags unsigned exe for friends.
**Prevention:** Make a throwaway export in P1 and run it on a second PC; repeat after each phase. Keep a documented "friend install" zip.
**Phase:** P1 smoke test, P6 packaging.

### 21. Settings and calibration only tested on the dev's machine
**What goes wrong:** Tight timing "feels great" on the dev's wired headset and 144 Hz monitor, and bad for friends. Display refresh and display latency (TVs, game mode off) are separate from audio latency.
**Prevention:** Include visual latency offset in calibration, not only audio. Collect per-hit offset histograms. Have a friend run calibration early, remotely.
**Phase:** P3.

---

## Minor Pitfalls

### 22. Beat-quantized launch makes tight timing feel late
**What goes wrong:** Quantizing fire to the next beat adds up to a beat of delay (e.g. 500 ms at 120 BPM, worse at slow songs), so the "my streak is a torpedo" feedback feels laggy.
**Prevention:** Give immediate local feedback on press (launch animation/sound), then land at the quantized time. Use half-beats or 1/4-note quantization at slow tempos. Quantization subdivisions come from the tempo map, not a fixed beat length.

### 23. Beat-grid visuals/audio (pings on downbeats, creatures pulsing) tied to rendering, not the clock
**Prevention:** Trigger beat-based effects from `song_time` crossing beat times, including after tempo changes. Use the tempo map, not a fixed BPM.

### 24. Rebinding and gamepad quirks
**Prevention:** Use `InputMap` actions for lanes, store scancodes by physical keycode (layout independent; AZERTY users), debounce analog triggers on gamepads, and test XInput vs DirectInput controllers. Game logic must read actions not specific keys.

### 25. Sustain handling forgotten until late
**Prevention:** Decide in P1 whether sustains exist in v1. If not, collapse them to single notes in the importer (and say so). Sustains complicate judgment, Lane Flip, and network summaries.

---

## Scope Creep (project-level, most likely failure mode for a solo hobby project)

**What goes wrong:** The list in PROJECT.md (5 payloads + Return to Sender + wreck ghosts + CRT shaders + 2 chart formats + calibration + online lobby) is already a lot. Common additions: auto-charting, Wolfpack 2v2, editor, ranked, animated sub models, procedural creatures, workshop/online song sharing, rollback netcode, host migration.
**Prevention:**
- Ship the vertical slice in this order and play it with friends at each step: (1) solo highway with a bundled chart and perfect timing, (2) calibration, (3) 2-player online with torpedoes as a single payload (Ghost Notes), (4) remaining payloads one at a time, (5) imports, (6) polish.
- Cut candidates if schedule slips: Return to Sender, wreck-ghost debris attacks, `.mid` support, Ink Cloud/Pressure Crack variants, 4-player (ship 2-3 first).
- A new payload is not allowed until the previous one has survived a playtest.
- Keep an explicit "later" list (auto-charting, Wolfpack, editor) and do not touch it.
- Art/audio polish is a trap: use placeholder programmer art until P5 is fun.
**Phase:** All; reviewed at each phase transition.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| P1 Timing core | Delta-based scroll; stair-stepped `get_playback_position`; no smoothing | Audio-clock-derived `song_time`, debug graph, click-track test song |
| P1 Export | `.chart`/data files missing in export; templates mismatch | Early export smoke test on a second PC |
| P2 Chart import | Resolution, tempo map, TS exponent, offsets, BOM; 5-fret to 4-lane mapping | Tolerant parser, real fixtures, written mapping rule |
| P2 Audio loading | Runtime loading outside `res://`, Opus unsupported, MP3 padding, multi-stem sync | Loader module, format matrix test, `AudioStreamSynchronized` [VERIFY] |
| P2 `.mid` | Wrong track, SysEx opens, pitch ranges, no SMF parser in core | Defer after `.chart`; write small SMF reader; fixtures |
| P3 Calibration/Input | Frame-bound polling; Bluetooth latency; ghosting; Tab = ui_focus_next | `_input`-based handling, calibration wizard (audio+visual), rollover test |
| P3 Judgment | Undefined windows/overstrum/chord rules | One shared table sent by host, logged offsets |
| P4 Transport | No NAT traversal | Decision gate: Tailscale/ZeroTier vs GodotSteam; transport interface |
| P4 Clock sync | One-shot ping, wall clock, start-on-receipt | NTP-style min-RTT sampling, scheduled start 2-3 s ahead, ready handshake |
| P4 Lobby | Song hash mismatch; disconnect handling | Normalized-chart hash; disconnect = elimination |
| P5 Torpedoes | Notes injected into visible area; unreadable/stacking attacks; leader dogpile | Lead time + next-beat re-quantize, telegraphs, one-at-a-time cap, immunity, playtests |
| P5 Depth Charge | Generated patterns unplayable | Density cap, min lane gap, validation against difficulty |
| P6 Polish | Shader stutter, GPU cost of CRT + periscopes | Pre-warm, low-effects toggle, profile on weakest PC |
| All | Scope creep | Vertical-slice order, kill list, playtest gates |

## Research Flags

- P4 (transport and NAT) needs deeper, dedicated research and a decision before design: licensing/UX of GodotSteam vs Tailscale/ZeroTier, and the Godot version's `MultiplayerPeer` options.
- P2 `.mid` parsing needs targeted research (sample files, SMF reader options).
- P1/P3 audio clock: verify against current Godot 4.x docs ("Sync the gameplay with audio and music") and whether `get_playback_position`/latency behavior changed in the target version.
- P5 balance is a playtest problem, not a research problem.

## Sources and Confidence

| Claim area | Confidence | Basis |
|------------|------------|-------|
| Audio-clock formula (`playback_position + time_since_last_mix - output_latency`) | MEDIUM | Godot official "Sync the gameplay with audio and music" doc, from memory, not re-fetched |
| Bluetooth/WASAPI latency behavior | MEDIUM | Widely reported; exact Godot defaults [VERIFY] |
| Input quantization and `use_accumulated_input` scope | MEDIUM/LOW | Engine behavior from memory; scope of accumulated input [VERIFY] |
| `.chart` format details (resolution, tempo in milli-BPM, TS exponent, N 5/6/7, HOPO threshold) | MEDIUM | Community chart format docs (GuitarGame_ChartFormats), from memory |
| `.mid` pitch ranges and track names | MEDIUM | Community docs (Clone Hero / Moonscraper), from memory |
| Opus unsupported in Godot; `AudioStreamSynchronized` 4.3+ | LOW/MEDIUM | [VERIFY] |
| NAT options (ENet lacks hole punching; Tailscale/ZeroTier; GodotSteam) | MEDIUM | General knowledge |
| GH3 battle mode lessons | MEDIUM | Community feedback from memory, not sourced here |
| Clock sync (NTP-style min-RTT) | HIGH | Standard technique |

Reference URLs to check when the owning phase starts:
- https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
- https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- https://github.com/TheNathannator/GuitarGame_ChartFormats
- https://github.com/GodotSteam/GodotSteam
