# Roadmap: UNDERTOW

## Overview

UNDERTOW is built as a series of vertical slices, each playable on its own. First a solo song that feels tight (audio-clock timing, judgment, calibration, hull). Then real content through Clone Hero chart import. Then the whole versus game offline against bots, so torpedoes, payloads and match rules are tuned before any netcode exists. Then online play layered onto the already-working game through an event-channel seam. Last, the sonar CRT look, audio feedback and Windows packaging.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Timing Core & Calibration** - A solo song on a 4-lane sonar highway that feels tight, with hull, calibration and rebindable input (completed 2026-10-07)
- [ ] **Phase 2: Chart Import & Songs** - Import Clone Hero charts, browse a song library, and ship bundled starter songs
- [ ] **Phase 3: Offline Versus** - Torpedoes, five payloads, Return to Sender, elimination, wreck ghosts and results against bot rivals
- [ ] **Phase 4: Online Play** - Host a lobby, start in sync, and have torpedoes land mid-song across 2-4 PCs
- [ ] **Phase 5: Polish & Packaging** - Sonar CRT look, underwater audio, juice, low-effects toggle and a Windows build

## Phase Details

### Phase 1: Timing Core & Calibration

**Goal**: A player can play a song solo on a sonar highway where hit timing feels tight and fair on their own machine.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: TIME-01, TIME-02, TIME-03, TIME-04, TIME-05, CAL-01, CAL-02, CAL-03, CAL-04, HULL-01, HULL-02, HULL-03, HULL-04
**Success Criteria** (what must be TRUE):

  1. Player plays a full-length song with notes staying locked to the music, with no visible drift over 5 minutes, at any frame rate
  2. Each press is graded Perfect, Good or Miss, with clear visual and audio feedback, and held notes and chords work
  3. Autoplay mode finishes any chart with all-Perfect results
  4. Player runs the calibration wizard, and the saved audio and visual offsets make their hits feel on-beat
  5. Player rebinds the lane, Fire and Target-cycle keys, plays with a gamepad, adjusts scroll speed and volume, and can pause and resume a solo song
  6. Misses crack the hull, the screen shows combo, score/depth and hull, and a hull at zero eliminates the player

**Plans**: TBD
**UI hint**: yes

### Phase 01.1: Playtest Feedback Polish (INSERTED)

**Goal:** Act on friend playtest v0.1 feedback so the solo game is easier to read, fairer to aim at, and more motivating to replay, then ship playtest v0.2.
**Mode:** mvp
**Requirements**: POL-01, POL-02, POL-03, POL-04, POL-05, POL-06, POL-07
**Success Criteria** (what must be TRUE):

  1. A new player can play one-handed with the default keys 1 2 3 4, and gamepad defaults are unchanged
  2. Each lane has its own neon color as well as its shape, and the highway sits inside a cyberpunk "goggles" visor frame
  3. Each lane has a hit-marker receptor on the hull line, and a note only brightens once it is inside the hit window (no more "highlighted before it's ready")
  4. The game opens borderless fullscreen, and F11 or a Settings switch toggles windowed mode, remembered between launches
  5. Each song's best depth and accuracy are saved and shown on the results screen and the menu, and streak milestones pop up during play
  6. Practice (No-Fail) is offered right on the main menu, and a v0.2 playtest zip is exported for friends

**UI hint**: yes
**Depends on:** Phase 1
**Plans:** 6/6 plans complete

Plans:

- [x] TBD (run /gsd:plan-phase 01.1 to break down) (completed 2026-10-08)

### Phase 01.2: Goggles Immersion (INSERTED)

**Goal:** Putting on the goggles takes you somewhere else. Each dive opens with the goggles sliding on and a "TV turning on" blink, and drops you into a neon abyss arena where you play like a rockstar, on a curved 3D board that feels like UNDERTOW rather than Guitar Hero. Ship playtest v0.2 at the end.
**Mode:** mvp
**Requirements**: IMM-01, IMM-02, IMM-03, IMM-04, IMM-05, IMM-06
**Success Criteria** (what must be TRUE):

  1. Starting a dive plays the goggles-on sequence (goggles slide in, a CRT-style blink "turns on" the world, then the song starts). Any key skips it, and Retry uses a quick version.
  2. The board is a 3D road diving toward a glowing horizon, with curved neon edges that react to the music. Players describe it as its own look, not "Guitar Hero".
  3. The screen edges are clean: no frame lines or clutter around the screen. Any HUD floats near or on the board and stays minimal.
  4. The world around the board (neon abyss arena with a pulsing bioluminescent "crowd") reacts to the beat and to playing well.
  5. Timing stays fair: notes reach the hit line exactly on the beat in the new 3D view, autoplay is still all-Perfect, and 60+ fps holds on the dev PC.
  6. Playtest v0.2 is exported and zipped for friends with the Phase 1.1 polish plus the new feel.

**UI hint**: yes
**Depends on:** Phase 1.1
**Plans:** 9/9 plans complete

Plans:

- [x] TBD (run /gsd-plan-phase 1.2 to break down) (completed 2026-10-08)

### Phase 2: Chart Import & Songs

**Goal**: Players can bring their own Clone Hero songs, browse them, and play bundled songs out of the box.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SONG-01, SONG-02, SONG-03, SONG-04, SONG-05, SONG-06, SONG-07
**Success Criteria** (what must be TRUE):

  1. Player points the game at a Clone Hero song folder (`.chart`, `song.ini`, OGG/MP3/WAV) and plays it
  2. Imported 5-fret charts play on 4 lanes by a documented, consistent rule, with HOPO and tap notes as plain notes
  3. Player browses the library, picks a song and difficulty, and hears an audio preview
  4. A fresh install has at least 2 bundled royalty-free or original songs that are playable with no imports
  5. A broken or unsupported song shows a readable error instead of crashing, and each song has a stable hash for later peer matching
  6. A chart with guitar solo markers keeps each solo's start, end and note count after import, ready for Phase 3 Solo Duels

**Plans**: TBD
**UI hint**: yes

### Phase 02.1: Instrument Extraction Tool (INSERTED)

**Goal:** Players can turn a song they own into a playable chart by extracting its instruments. Research comes first: study how to separate stems and how to turn a stem into notes, then build the tool.
**Mode:** mvp
**Requirements**: STEM-01, STEM-02, STEM-03, STEM-04, STEM-05, STEM-06, STEM-07
**Spec:** `phases/02.1-instrument-extraction-tool/02.1-SPEC.md` (locked 2026-10-09: Clone Hero-style audio-driven charts; first deliverable = the user's 3 custom songs bundled and synced)
**Research:** REQUIRED before planning (stem separation models, runtime/packaging on friends' PCs, onset/pitch-to-lane charting, quality on real songs)
**Success Criteria** (what must be TRUE):

  1. A written study compares extraction approaches on real songs and records a chosen approach, with its reasons and trade-offs
  2. Player gives the tool an audio file they own and gets separated instrument stems (e.g. drums, bass, guitar/other, vocals)
  3. Player can chart ONE chosen instrument across the 4 lanes, or use INSTRUMENT LANES mode where each lane is a different instrument
  4. Generated charts are synced to the original song and saved into the song library like any other song
  5. The tool runs on the player's own PC without a paid service, and reports progress and failures clearly
  6. The user's three custom songs (HRT, Sea Shanty 2, INVISIBLE) and the two existing bundled songs ship with audio-driven charts that pass the measured sync gate (median note-to-onset within ±5 ms, ≥90% of notes within ±25 ms)

**Depends on:** Phase 2
**Plans:** 1/9 plans executed

Plans:

- [x] 02.1-01-PLAN.md — Reproducible venvs, align-harness hang fix, sync gate (note_sync.py) + baseline numbers for the plan-authored charts (STEM-01 cited)
- [ ] 02.1-02-PLAN.md — TDD: tempo map (per-beat B), Expert builder (density/merge/snap/cap), .chart/.ini writer
- [ ] 02.1-03-PLAN.md — TDD: contour lanes, accent chords, sustains, Hard/Medium/Easy reductions, section/solo/preview picks
- [ ] 02.1-04-PLAN.md — Analysis CLI: decode, htdemucs stems, beats, audible onsets, Basic Pitch; run on the 3 songs
- [ ] 02.1-05-PLAN.md — First synced song: failing e2e test, `autochart.py chart`, Sea Shanty 2 bundled and gated
- [ ] 02.1-06-PLAN.md — HRT + INVISIBLE bundled and gated (stem fill), D-13 override (PROJECT.md + CLAUDE.md), headless BUNDLED_OK 20
- [ ] 02.1-07-PLAN.md — STEM-07: re-chart April + Space Synth Wave, retire author_chart.gd to legacy, tests on committed charts
- [ ] 02.1-08-PLAN.md — STEM-02/04/05: extract_song.ps1 player flow, INSTRUMENT LANES mode, same-hash proof (after 07)
- [ ] 02.1-09-PLAN.md — Final v0.4 rebuild, gate table, UAT sheet, end-of-phase human verification

### Phase 3: Offline Versus

**Goal**: Player can play a complete, fun, fair versus match against bot rivals, with the full torpedo and payload game working offline.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: TORP-01, TORP-02, TORP-03, TORP-04, TORP-05, TORP-06, PAY-01, PAY-02, PAY-03, PAY-04, PAY-05, PAY-06, MATCH-01, MATCH-02, MATCH-03, MATCH-04, MATCH-05, MATCH-06
**Success Criteria** (what must be TRUE):

  1. Player's Perfect streak fills a visible torpedo tube, and they can fire at a target (leader by default, cycling, or an Attackers toggle) with launch and arrival snapped to beats
  2. A bot-fired torpedo shows a telegraph at least 1 beat before it lands, and each of the five payloads (Pressure Crack, Lane Flip, Ghost Notes, Ink Cloud, Depth Charge) is readable and survivable without mashing
  3. Only one payload is active on a player at a time, followed by an immunity window, and hitting all warhead notes perfectly reflects a torpedo back at its sender
  4. Player sees periscope panels with each rival's hull, tube and incoming payloads, and the last intact hull wins, or the deepest score if several survive the song
  5. Eliminated players keep playing as wreck ghosts with capped debris attacks, and a results screen shows winner, depth, accuracy, and torpedoes landed and reflected
  6. In Solo Dive, player practices any song with chosen training payloads

**Plans**: TBD
**UI hint**: yes

### Phase 4: Online Play

**Goal**: 2-4 friends on separate PCs can play the same song at once and feel each other's torpedoes mid-song.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, NET-07
**Success Criteria** (what must be TRUE):

  1. A friend hosts a lobby and 1-3 others join from their own PCs over the internet, following a documented setup (Tailscale/ZeroTier or equivalent) that works behind home routers
  2. The lobby shows each player's ready state and whether they have the selected song (hash match)
  3. When the host starts, all players' songs begin in sync
  4. A torpedo, hull change, elimination or score update from one player reaches the others mid-song, and torpedoes land on the intended beat
  5. A player who disconnects counts as eliminated while the match continues, and if the host leaves, everyone sees a message and the match ends cleanly

**Plans**: TBD
**UI hint**: yes

### Phase 5: Polish & Packaging

**Goal**: The game looks and sounds like a deep-sea sonar scope, runs smoothly on weaker PCs, and friends can download and run it without Godot.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: AV-01, AV-02, AV-03, AV-04, AV-05, DIST-01
**Success Criteria** (what must be TRUE):

  1. The highway renders as a phosphor-green sonar CRT with scanlines and sweep afterglow, over a trench background where bioluminescent life pulses on the beat
  2. Sonar pings land on downbeats, and hull creaks and the muffled underwater filter get stronger as hull drops
  3. Torpedo impacts, launches and eliminations trigger screen shake, flash and implosion feedback
  4. Player turns on a low-effects toggle and the game stays smooth on a weaker PC
  5. A friend downloads the Windows build and runs it without installing Godot

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Timing Core & Calibration | 10/10 | Complete   | 2026-10-07 |
| 2. Chart Import & Songs | 5/6 | In Progress|  |
| 3. Offline Versus | 0/TBD | Not started | - |
| 4. Online Play | 0/TBD | Not started | - |
| 5. Polish & Packaging | 0/TBD | Not started | - |
