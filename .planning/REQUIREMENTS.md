# Requirements: UNDERTOW

**Defined:** 2026-10-07
**Core Value:** Hitting notes feels tight and fair on each player's own machine, while torpedoes reach rivals over the network fast enough that a friend's perfect streak is felt inside the same song.

## v1 Requirements

### Timing Core

- [x] **TIME-01**: Notes scroll in sync with the song, driven by the audio clock (no visible drift across a full 5-minute song)
- [x] **TIME-02**: Player's key/button presses are judged against song time, independent of frame rate
- [x] **TIME-03**: Each hit is graded into one of three tiers (Perfect / Good / Miss) using tunable timing windows
- [x] **TIME-04**: Player can play sustained (held) notes and chords
- [x] **TIME-05**: An autoplay mode plays any chart with all-Perfect results (correctness check)

### Calibration & Input

- [x] **CAL-01**: Player can run a calibration wizard that sets separate audio and visual offsets, saved per machine
- [x] **CAL-02**: Player can rebind the 4 lane keys, Fire and Target-cycle on keyboard
- [x] **CAL-03**: Player can play with a gamepad
- [x] **CAL-04**: Player can adjust scroll speed and music/SFX volume

### Hull & Scoring

- [x] **HULL-01**: Misses and wrong hits damage the player's hull. The hull reaching zero eliminates the player.
- [x] **HULL-02**: Player sees combo, score/depth and hull integrity during play
- [x] **HULL-03**: Player gets clear visual and audio feedback for each Perfect/Good/Miss
- [x] **HULL-04**: Player can pause and resume during a solo song

### Songs & Charts

- [x] **SONG-01**: Player can import Clone Hero `.chart` songs (with `song.ini` and OGG/MP3/WAV audio) from a folder
- [x] **SONG-02**: Imported 5-fret charts are mapped to 4 lanes by a documented, consistent rule (HOPO/tap become plain notes)
- [x] **SONG-03**: Player can browse the song library and pick a song and difficulty with an audio preview
- [x] **SONG-04**: Game ships with at least 2 bundled royalty-free/original songs with charts
- [x] **SONG-05**: Each song has a stable hash so peers can confirm they have the identical chart
- [x] **SONG-06**: Unsupported or broken songs show a readable error instead of crashing
- [x] **SONG-07**: The importer keeps guitar solo section markers (`.chart` `solo`/`soloend` events; `.mid` note 103 once CONT-01 lands) on the parsed chart, with each solo's start time, end time and note count. Charts without markers import normally with no solos. Needed by Phase 3 Solo Duel (see `phases/03-offline-versus/03-SPEC.md`).

### Instrument Extraction (research first)

- [ ] **STEM-01**: A research study compares stem-separation and stem-to-chart approaches on real songs and records the chosen approach
- [ ] **STEM-02**: Player can load an audio file they own and extract instrument stems (drums, bass, guitar/other, vocals)
- [ ] **STEM-03**: Player can generate a 4-lane chart from ONE chosen instrument stem
- [ ] **STEM-04**: Player can generate an "instrument lanes" chart where each lane follows a different instrument
- [ ] **STEM-05**: Extracted songs are saved to the library, synced to the original audio, and playable like any other song
- [ ] **STEM-06**: The user's three custom songs (HRT, Sea Shanty 2, Duran Duran INVISIBLE) are bundled with audio-driven charts (real tempo map, notes on audible events, lanes follow melody contour) that pass the measured sync gate (see `phases/02.1-instrument-extraction-tool/02.1-SPEC.md`)
- [ ] **STEM-07**: The two existing bundled songs are re-charted with the same audio-driven pipeline, replacing the plan-authored charts

### Goggles Immersion (user direction 2026-10-08)

- [x] **IMM-01**: Each dive starts with a skippable goggles-on sequence: a first-person lens mask closes in (no outside-view goggles drawing, user 2026-10-08), a CRT-style blink turns the world on, then the song starts (quick version on Retry)
- [x] **IMM-02**: The note board is a 3D trench descent toward a glowing depth, with straight cables and a flat hit line (curves were too hard to hit; user 2026-10-08), neon edges reacting to the music, in a distinct UNDERTOW look (not Guitar Hero)
- [x] **IMM-03**: The screen edges are free of frame chrome; the HUD is minimal and sits near or on the board
- [x] **IMM-04**: The world around the board is a neon abyss arena with bioluminescent life pulsing to the beat and reacting to good play
- [x] **IMM-05**: The 3D board keeps timing fair: notes hit the line exactly on the beat, autoplay stays all-Perfect, readable at all scroll speeds
- [x] **IMM-06**: Playtest v0.2 (Phase 1.1 polish + immersion) is exported and zipped for friends

### Playtest Polish (from friend feedback v0.1)

- [x] **POL-01**: Default lane keys are 1 2 3 4 so the game can be played with one hand
- [x] **POL-02**: Each lane has a distinct neon color (cyan, amber, magenta, lime) in addition to its shape, inside a cyberpunk "goggles" visor frame
- [x] **POL-03**: Each lane shows a hit-marker receptor on the hull line, and notes only brighten once they are inside the hit window
- [x] **POL-04**: Game opens borderless fullscreen, with an F11 / Settings toggle that is remembered
- [x] **POL-05**: Best score (depth and accuracy) is saved per song and shown on results and the menu
- [x] **POL-06**: Note streak is prominent, with milestone popups (e.g. 10/25/50/100)
- [x] **POL-07**: Practice (No-Fail) can be started directly from the main menu

### Torpedoes (Versus Core)

- [ ] **TORP-01**: A Perfect streak fills the player's torpedo tube meter, which is always visible
- [ ] **TORP-02**: Player can fire a full torpedo at a target. Launch and arrival snap to beats.
- [ ] **TORP-03**: Player can cycle targets. The default target is the current leader. An "Attackers" toggle targets whoever last hit you.
- [ ] **TORP-04**: The target sees a telegraph warning at least 1 beat before a payload lands
- [ ] **TORP-05**: Only one payload can be active on a player at a time, followed by a short immunity window
- [ ] **TORP-06**: No payload requires button-mashing to clear or can instantly eliminate a player

### Payloads

- [ ] **PAY-01**: Pressure Crack: the target's scroll speed spikes for a few bars
- [ ] **PAY-02**: Lane Flip: the target's lanes are mirrored for a few bars
- [ ] **PAY-03**: Ghost Notes: fake notes (visually distinguishable by shape, not only color) that damage the hull if hit
- [ ] **PAY-04**: Ink Cloud: the lower part of the target's highway is obscured for a few bars
- [ ] **PAY-05**: Depth Charge: a burst of extra notes derived from the song's rhythm, capped by local chart density
- [ ] **PAY-06**: Return to Sender: hitting all marked warhead notes of a payload perfectly reflects it to the sender

### Match Flow

- [ ] **MATCH-01**: Player can play a versus match offline against bot rivals (used for practice and testing)
- [ ] **MATCH-02**: The last sub with an intact hull wins. If several survive the song, the deepest score wins, with a defined tie-break.
- [ ] **MATCH-03**: Eliminated players continue as wreck ghosts that charge weak, capped debris attacks
- [ ] **MATCH-04**: Player sees periscope panels showing each rival's hull, tube and incoming/active payloads
- [ ] **MATCH-05**: Results screen shows winner, depth, accuracy, torpedoes landed and reflected
- [ ] **MATCH-06**: Solo Dive mode lets a player practice any song with chosen training payloads

### Online Play

- [ ] **NET-01**: A friend can host a lobby, and 1-3 others can join from their own PCs over the internet
- [ ] **NET-02**: The lobby shows each player's ready state and whether they have the selected song (hash match)
- [ ] **NET-03**: All players' songs start in sync (clock-synced, host-scheduled start)
- [ ] **NET-04**: Torpedo, hull, elimination and score events reach other players mid-song and land on the intended beat
- [ ] **NET-05**: A player disconnecting is treated as eliminated, and the match continues for the rest
- [ ] **NET-06**: A host leaving ends the match cleanly for everyone, with a message
- [ ] **NET-07**: There is a documented, working way for friends behind home routers to connect (e.g., Tailscale/ZeroTier, or Steam relay)

### Look & Sound

- [ ] **AV-01**: Highway renders as a sonar CRT screen (phosphor glow, scanlines, sweep afterglow) (visor portion delivered early in Phase 1.1, plan 01.1-06)
- [ ] **AV-02**: Background shows the trench with bioluminescent life pulsing on the beat
- [ ] **AV-03**: Sonar pings on downbeats, hull creaks and a muffled filter that grows with damage
- [ ] **AV-04**: Torpedo impacts, eliminations and launches have screen shake/flash/implosion feedback
- [ ] **AV-05**: A low-effects toggle keeps the game smooth on weaker PCs

### Distribution

- [ ] **DIST-01**: Game exports as a Windows build that friends can download and run without installing Godot

## v2 Requirements

### Content

- **CONT-01**: Import Clone Hero `.mid` charts
- **CONT-02**: Auto-generate charts from the full mix (rejected by the user: charts come from extracted instruments instead, see STEM-*)

### Modes

- **MODE-01**: Wolfpack 2v2 with shared team hull and pooled torpedoes
- **MODE-02**: Alternate pitched modes (MIMIC social deduction, ECHO call-and-response, ONE ORGAN co-op)
- **MODE-03**: Optional handicap / catch-up system

### Online

- **ONL-01**: Steam invites / Steam relay via GodotSteam (if not chosen as v1 transport)
- **ONL-02**: Host migration

## Out of Scope

| Feature | Reason |
|---------|--------|
| Plastic guitar / real instrument controllers | Hardware-specific input work. Keyboard and gamepad are enough for friends. |
| Public matchmaking, ranked play, accounts | Game is for one friend group. Join by host address/invite is enough. |
| Anti-cheat | Friends only. The host does basic sanity checks. |
| Bundling copyrighted songs | Legal risk. Players import their own. |
| Strum key / HOPO mechanics | Flattened to plain notes for keyboard play. Keeps the 4-lane game readable. |
| Random power-up pickups | GH3 Battle Mode lesson: randomness decided matches. Torpedoes are earned by skill only. |
| Pausing during online matches | Can't pause a shared song fairly |
| Voice chat | Friends already use Discord |
| Chart editor | Imports cover content |
| Mobile / console builds | Friends play on PCs |
| Story / campaign | The game is about friends playing against each other |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TIME-01 | Phase 1 | Complete |
| TIME-02 | Phase 1 | Complete |
| TIME-03 | Phase 1 | Complete |
| TIME-04 | Phase 1 | Complete |
| TIME-05 | Phase 1 | Complete |
| CAL-01 | Phase 1 | Complete |
| HULL-01 | Phase 1 | Complete |
| CAL-02 | Phase 1 | Complete |
| HULL-02 | Phase 1 | Complete |
| CAL-03 | Phase 1 | Complete |
| HULL-03 | Phase 1 | Complete |
| CAL-04 | Phase 1 | Complete |
| HULL-04 | Phase 1 | Complete |
| SONG-01 | Phase 2 | Complete |
| TORP-01 | Phase 3 | Pending |
| PAY-01 | Phase 3 | Pending |
| MATCH-01 | Phase 3 | Pending |
| SONG-02 | Phase 2 | Complete |
| TORP-02 | Phase 3 | Pending |
| PAY-02 | Phase 3 | Pending |
| MATCH-02 | Phase 3 | Pending |
| SONG-03 | Phase 2 | Complete |
| TORP-03 | Phase 3 | Pending |
| PAY-03 | Phase 3 | Pending |
| MATCH-03 | Phase 3 | Pending |
| SONG-04 | Phase 2 | Complete |
| TORP-04 | Phase 3 | Pending |
| PAY-04 | Phase 3 | Pending |
| MATCH-04 | Phase 3 | Pending |
| SONG-05 | Phase 2 | Complete |
| TORP-05 | Phase 3 | Pending |
| PAY-05 | Phase 3 | Pending |
| MATCH-05 | Phase 3 | Pending |
| SONG-06 | Phase 2 | Complete |
| SONG-07 | Phase 2 | Complete |
| STEM-01 | Phase 2.1 | Pending |
| STEM-02 | Phase 2.1 | Pending |
| STEM-03 | Phase 2.1 | Pending |
| STEM-04 | Phase 2.1 | Pending |
| STEM-05 | Phase 2.1 | Pending |
| STEM-06 | Phase 2.1 | Pending |
| STEM-07 | Phase 2.1 | Pending |
| POL-01 | Phase 1.1 | Complete |
| POL-02 | Phase 1.1 | Complete |
| POL-03 | Phase 1.1 | Complete |
| POL-04 | Phase 1.1 | Complete |
| POL-05 | Phase 1.1 | Complete |
| POL-06 | Phase 1.1 | Complete |
| POL-07 | Phase 1.1 | Complete |
| TORP-06 | Phase 3 | Pending |
| PAY-06 | Phase 3 | Pending |
| MATCH-06 | Phase 3 | Pending |
| NET-01 | Phase 4 | Pending |
| NET-02 | Phase 4 | Pending |
| NET-03 | Phase 4 | Pending |
| NET-04 | Phase 4 | Pending |
| NET-05 | Phase 4 | Pending |
| NET-06 | Phase 4 | Pending |
| NET-07 | Phase 4 | Pending |
| AV-01 | Phase 5 | Pending |
| AV-02 | Phase 5 | Pending |
| AV-03 | Phase 5 | Pending |
| AV-04 | Phase 5 | Pending |
| AV-05 | Phase 5 | Pending |
| DIST-01 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 63 total
- Mapped to phases: 63
- Unmapped: 0

---
*Requirements defined: 2026-10-07*
*Last updated: 2026-10-08 added SONG-07 (solo markers for Phase 3 Solo Duel)*
