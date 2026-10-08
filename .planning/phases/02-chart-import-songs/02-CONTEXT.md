# Phase 2: Chart Import & Songs - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous). The user accepted all recommended answers in 4 areas.

<domain>
## Phase Boundary

Players can bring their own Clone Hero songs (`.chart` + `song.ini` + OGG/MP3/WAV), browse them in a song-select screen with audio preview, pick a difficulty and play them on the 4-lane Trench Descent board. Two bundled songs work out of the box. Each song has a stable fingerprint for later peer matching (Phase 4). Guitar-solo markers are kept for Phase 3 Solo Duels.

**Not in this phase:**
- `.mid` import (v2 CONT-01)
- The instrument extraction tool (Phase 2.1)
- Versus and torpedo use of solos (Phase 3)
- Online song matching (Phase 4)

</domain>

<decisions>
## Implementation Decisions

### 5 frets → 4 lanes (SONG-02)
- **D-01:** Green→lane 1, Red→lane 2, Yellow→lane 3, Blue→lane 4, **Orange→lane 4**, merged with Blue. When a Blue+Orange chord collapses it becomes one lane-4 note (dedupe, keeping the longest sustain). Document the rule in-game (README) and in code, and version it (mapping version is part of the song fingerprint, D-14).
- **D-02:** **Open notes → a lane 2+3 chord.**
- **D-03:** **All difficulties present in the chart** (Easy/Medium/Hard/Expert, `[EasySingle]`..`[ExpertSingle]`) are importable and selectable in song select. Only the guitar (`*Single`) tracks are used.
- **D-04:** **Sustains and chords are kept as charted** after the merge. HOPO/tap flags are ignored (plain notes), as already decided. Forced/tap markers are parsed but not used.

### Getting songs in (SONG-01, SONG-06)
- **D-05:** The game creates a **`Songs` folder** (under `user://songs`, with an **"Open songs folder"** button in the menu and song select that opens it in Explorer). Players drop Clone Hero song folders, or `.zip`s that are extracted on scan, into it.
- **D-06:** **Optional extra folders:** Settings can list extra library folders (e.g. an existing Clone Hero songs folder). They are scanned **in place**, never copied or modified.
- **D-07:** The library is **scanned on game start plus a "Rescan" button.** Results are cached (keyed by path + mtime + size) so later starts are fast. The scan never blocks the UI thread for long; show progress for big libraries.
- **D-08:** **Broken/unsupported songs are listed greyed out with a one-line reason**, for example:
  - "Opus audio not supported"
  - "No guitar chart"
  - "Unreadable .chart (line 214)"
  - "Audio file missing"

  They never crash, and the game never blocks.

### Song select (SONG-03)
- **D-09:** Layout is a **vertical song list plus a "sonar" detail panel** in the neon-abyss style (consistent with Phase 1.2: clean edges, lane neons, sonar-green/teal chrome). The panel shows title, artist, charter, length, BPM, available difficulty pips and the **best score for the selected difficulty**.
- **D-10:** **Audio preview** starts about 0.4 s after a song is highlighted, from `song.ini` `preview_start_time` or 30% into the song, with a fade in and out. It stops on navigate-away or dive.
- **D-11:** **Navigation:**
  - Up/Down arrows or keys 1–4 move through the list.
  - Left/Right changes difficulty.
  - Enter dives (the goggles intro then plays as now).
  - Esc goes back.
  - Full gamepad support: D-pad and A/B.
- **D-12:** **Sort by title, artist or best score. Typing filters the list** (search across title and artist).
- **D-13:** The main menu's "Start Dive" / "Practice Dive (No-Fail)" now open song select (practice carries through). The test/hand chart stays available in the list as "Calibration Track" (dev build only, or always; Claude's discretion).

### Bundled songs, fingerprint, records, solos (SONG-04, SONG-05, SONG-07)
- **D-14:** **Bundled songs:** **2 free CC0 or CC-BY tracks**, found by research. Charts are written for Easy/Medium/Hard/Expert as `.chart` files in the same format players import. Credits go in the README and an in-game Credits line. Licenses are not a selection blocker (friends-only, user decision 2026-10-08), but attribution is kept where the license asks for it.
- **D-15:** **Song fingerprint (SONG-05)** is a hash of the **normalized chart contents + difficulty + lane-mapping version + importer version + audio duration**. It matches across renamed files and re-saves. Cache it with the scan.
- **D-16:** **Records are per song + per difficulty**, keyed by fingerprint. Extend the existing ScoreStore (`user://scores.cfg`). Migrate or keep the existing test-chart record harmlessly.
- **D-17:** **Solo sections (SONG-07):**
  - Parse `.chart` `[Events]`/track `solo`/`soloend` events and store each solo's start time, end time and note count on ChartData.
  - Nothing is shown in gameplay yet; Phase 3 Solo Duel uses it (see `phases/03-offline-versus/03-SPEC.md` requirement 11).
  - Charts without markers have no solos.

### Claude's Discretion
- Exact song-select visuals within the Phase 1.2 look.
- Scan threading.
- Zip handling details.
- Cache format.
- Whether the Calibration Track is dev-only.

</decisions>

<code_context>
## Existing Code Insights

- `src/core/chart_data.gd` (format-agnostic notes, tempo_map, `id`) is the import target. `src/core/score_store.gd` handles records. The `TestCharts` hand chart is the current only content.
- Runtime audio loading for OGG/MP3/WAV from arbitrary paths, and the Opus limitation, are covered in `.planning/research/` and `01-RESEARCH.md`.
- Gameplay entry is `Gameplay.pending_chart` / `pending_autoplay` / `pending_practice` / `pending_intro`, plus `main_menu.gd`.
- The Phase 1.2 look (Trench, Arena, Palette lane colours) and the UI-SPEC conventions of 01.1/01.2 apply to song select.
- Windowed playtest harness: `tools/playtest/` (scenarios + screenshots). Export/zip: `tools/export.ps1`, `tools/dist.ps1` (zip must include bundled songs).

</code_context>

<specifics>
## Specific Ideas

- The user wants to play a specific song from YouTube. The game will NOT rip YouTube audio. Real songs come from Clone Hero charts players own or download themselves (Phase 2), or from the instrument extraction tool (Phase 2.1).
- Phase 3 already depends on solo markers (03-SPEC requirement 11).

</specifics>

<deferred>
## Deferred Ideas

- `.mid` chart import (v2 CONT-01; solo note 103 lands with it).
- Showing "SOLO" in gameplay (Phase 3 Solo Duel).
- The instrument extraction / own-audio-to-chart tool (Phase 2.1).

</deferred>

---

*Phase: 02-chart-import-songs. Context gathered: 2026-10-08 (smart discuss, all recommended answers accepted)*
