# Phase 2: Chart Import & Songs - Research

**Researched:** 2026-10-08
**Domain:** Clone Hero `.chart` / `song.ini` import, Godot 4.7.2 runtime audio loading, background library scan, song-select UI, bundled CC0 content
**Confidence:** HIGH on format grammar and Godot APIs (probed on the real 4.7.2 binary); MEDIUM on bundled-audio export behaviour and beat offsets (need a Wave 0 spike)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Green->lane 1, Red->lane 2, Yellow->lane 3, Blue->lane 4, **Orange->lane 4**, merged with Blue. When a Blue+Orange chord collapses it becomes one lane-4 note (dedupe, keeping the longest sustain). Document the rule in-game (README) and in code, and version it (mapping version is part of the song fingerprint, D-14).
- **D-02:** **Open notes -> a lane 2+3 chord.**
- **D-03:** **All difficulties present in the chart** (Easy/Medium/Hard/Expert, `[EasySingle]`..`[ExpertSingle]`) are importable and selectable in song select. Only the guitar (`*Single`) tracks are used.
- **D-04:** **Sustains and chords are kept as charted** after the merge. HOPO/tap flags are ignored (plain notes). Forced/tap markers are parsed but not used.
- **D-05:** The game creates a **`Songs` folder** (under `user://songs`, with an **"Open songs folder"** button in the menu and song select that opens it in Explorer). Players drop Clone Hero song folders, or `.zip`s that are extracted on scan, into it.
- **D-06:** **Optional extra folders:** Settings can list extra library folders (e.g. an existing Clone Hero songs folder). They are scanned **in place**, never copied or modified.
- **D-07:** The library is **scanned on game start plus a "Rescan" button.** Results are cached (keyed by path + mtime + size) so later starts are fast. The scan never blocks the UI thread for long; show progress for big libraries.
- **D-08:** **Broken/unsupported songs are listed greyed out with a one-line reason** ("Opus audio not supported", "No guitar chart", "Unreadable .chart (line 214)", "Audio file missing"). They never crash, and the game never blocks.
- **D-09:** Layout is a **vertical song list plus a "sonar" detail panel** in the neon-abyss style (Phase 1.2). The panel shows title, artist, charter, length, BPM, available difficulty pips and the **best score for the selected difficulty**.
- **D-10:** **Audio preview** starts about 0.4 s after a song is highlighted, from `song.ini` `preview_start_time` or 30% into the song, with a fade in and out. It stops on navigate-away or dive.
- **D-11:** **Navigation:** Up/Down arrows or keys 1-4 move through the list. Left/Right changes difficulty. Enter dives (goggles intro then plays as now). Esc goes back. Full gamepad support: D-pad and A/B.
- **D-12:** **Sort by title, artist or best score. Typing filters the list** (search across title and artist).
- **D-13:** The main menu's "Start Dive" / "Practice Dive (No-Fail)" now open song select (practice carries through). The test/hand chart stays available in the list as "Calibration Track" (dev build only, or always; Claude's discretion).
- **D-14:** **Bundled songs:** **2 free CC0 or CC-BY tracks**, found by research. Charts are written for Easy/Medium/Hard/Expert as `.chart` files in the same format players import. Credits go in the README and an in-game Credits line. Licenses are not a selection blocker (friends-only), but attribution is kept where the license asks for it.
- **D-15:** **Song fingerprint (SONG-05)** is a hash of the **normalized chart contents + difficulty + lane-mapping version + importer version + audio duration**. It matches across renamed files and re-saves. Cache it with the scan.
- **D-16:** **Records are per song + per difficulty**, keyed by fingerprint. Extend the existing ScoreStore (`user://scores.cfg`). Migrate or keep the existing test-chart record harmlessly.
- **D-17:** **Solo sections (SONG-07):** Parse `.chart` `[Events]`/track `solo`/`soloend` events and store each solo's start time, end time and note count on ChartData. Nothing is shown in gameplay yet; Phase 3 Solo Duel uses it. Charts without markers have no solos.

### Claude's Discretion
- Exact song-select visuals within the Phase 1.2 look.
- Scan threading.
- Zip handling details.
- Cache format.
- Whether the Calibration Track is dev-only.

### Deferred Ideas (OUT OF SCOPE)
- `.mid` chart import (v2 CONT-01; solo note 103 lands with it).
- Showing "SOLO" in gameplay (Phase 3 Solo Duel).
- The instrument extraction / own-audio-to-chart tool (Phase 2.1).
- The game will NOT rip YouTube audio.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SONG-01 | Import `.chart` + `song.ini` + OGG/MP3/WAV from a folder | Sections 1, 2, 3, 4: grammar, audio loaders, zip extraction, scanner |
| SONG-02 | 5-fret to 4-lane documented rule | Section 1 mapping algorithm, `MAPPING_VERSION` |
| SONG-03 | Browse library, pick song/difficulty, with audio preview | Sections 5, 6: preview player, ItemList UI, key-conflict pitfall |
| SONG-04 | 2+ bundled royalty-free songs with charts | Section 8: two CC0 tracks measured, authoring method; Section 9 export |
| SONG-05 | Stable hash so peers confirm identical chart | Section 7 fingerprint recipe |
| SONG-06 | Broken songs show a readable error | Error taxonomy in Sections 1, 2, 3; hostile-input caps |
| SONG-07 | Keep solo markers with start/end/note count | Section 1 solo parsing, inclusive `soloend` |
</phase_requirements>

## Summary

The format side is small and well specified. `.chart` is an INI-like file: `[Section]` / `{` / `tick = TYPE args` / `}`. Everything needed (Resolution, `B` milli-BPM, `TS` exponent, `E` events, `N`/`S` track lines, `solo`/`soloend`) is documented by the TheNathannator GuitarGame_ChartFormats docs, which I read directly. A hand-written tolerant line parser (~250 lines, pure `RefCounted`, unit-testable) is the right tool. The riskiest parser trap in this codebase is that `ChartData.add_note` uses `assert` for time/lane validity, so hostile or negative-delay data must be filtered before it reaches `add_note`.

On the Godot side I probed the real 4.7.2 console binary headless. `AudioStreamOggVorbis`, `AudioStreamMP3`, and `AudioStreamWAV` all have static `load_from_file`. `AudioStreamSynchronized` exists, takes the longest sub-stream length from `get_length()`, and `AudioStreamPlayer.get_playback_position()` advances normally on it, so multi-stem Clone Hero songs can be handed to the existing `Conductor` as one `AudioStream` with no Conductor changes. Opus is not loadable: `load_from_file` returns null (with an engine error print) for a non-Vorbis file, so detect Opus by magic bytes (`OggS` page containing `OpusHead`) before attempting a load and show "Opus audio not supported". `ZIPReader`, `ZIPPacker`, `WorkerThreadPool`, `OS.shell_show_in_file_manager`, and `HashingContext` are all available.

For bundled content I found and measured two CC0 tracks by Pro Sensory (Alex McCulloch) on OpenGameArt. Both are exact constant 120 BPM, which makes hand-authoring a precise tempo map trivial: "Synth Wave April 3, 2022" (MP3, 2:08, 64 bars) and "Space Synth Wave" (WAV, 3:12, 96 bars). Charts should be produced by a deterministic, seeded generator tool driven by a hand-written per-bar section plan (not by audio analysis), then committed as ordinary `.chart` files.

**Primary recommendation:** Build `ChartParser` (text to a tick-based intermediate), `ChartImporter` (intermediate to 4-lane `ChartData` + solos + fingerprint), `AudioLoader`, `SongScanner` (worker thread + JSON cache), and `SongLibrary` (autoload) as separate pure units with fixture-driven tests; song select is then a thin `ItemList` UI over `SongLibrary`.

## Architectural Responsibility Map

Single-process desktop game; tiers are code layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Parse `.chart`/`song.ini` text | `src/core` (pure RefCounted) | — | Deterministic, no engine nodes, unit testable |
| 5-fret to 4-lane mapping, tick to seconds, solos | `src/core` importer | — | Output is format-agnostic `ChartData` |
| Fingerprint hash | `src/core` importer | — | Must be identical on every peer; pure function |
| Audio file loading and stem assembly | `src/audio` loader | — | Wraps engine loaders, Opus detection |
| Folder walk, zip extraction, cache | worker thread task in `src/core` scanner | `SongLibrary` autoload owns results | Must not run on the UI thread |
| Song list, filter, sort, detail panel | `src/ui/song_select.gd` | — | View only, reads `SongLibrary` + `ScoreStore` |
| Preview playback | `src/ui/song_select.gd` own `AudioStreamPlayer` (Music bus) | — | Independent of `Conductor` |
| Records per fingerprint+difficulty | `ScoreStore` | — | Existing store, extend |
| Bundled songs | `res://songs/` + manifest constant | export preset | Same format as user songs |

## Standard Stack

### Core (all built in to Godot 4.7.2; no new addons)
| API | Purpose | Verified |
|-----|---------|----------|
| `FileAccess`, `DirAccess` | Read chart/ini bytes, walk folders, mtime/size | [VERIFIED: used in repo + probe] |
| `ConfigFile` (or own line parser) for `song.ini` | Metadata | [CITED: STACK.md]; see pitfall on tolerant ini |
| `AudioStreamOggVorbis.load_from_file(path)` | OGG | [VERIFIED: docs.godotengine.org + probe: null + error on non-Vorbis] |
| `AudioStreamMP3.load_from_file(path)` | MP3 | [VERIFIED: probe, 4 ms for 5 MB] |
| `AudioStreamWAV.load_from_file(path, options={})` | WAV | [VERIFIED: probe, `ClassDB.class_has_method` true; 34 MB in 165 ms]. Docs list 8-bit, 16-bit, IMA ADPCM, QOA; 24/32-bit WAV is not documented, treat load failure as "unsupported WAV" |
| `AudioStreamSynchronized` | Multi-stem songs as one stream | [VERIFIED: probe: `get_length()` = longest stem; playback position advances; MAX_STREAMS 32] |
| `ZIPReader` / `ZIPPacker` | Extract zips at runtime; build zips in tests | [CITED: docs.godotengine.org/en/latest/classes/class_zipreader.html] |
| `WorkerThreadPool.add_task(Callable)` | Background scan | [VERIFIED: ClassDB probe] |
| `HashingContext` (SHA-256) | Fingerprint | [CITED: STACK.md; built in] |
| `OS.shell_show_in_file_manager(path, open_folder)` | "Open songs folder" | [VERIFIED: ClassDB probe]. `OS.shell_open(path)` also exists as a fallback |
| gdUnit4 via `tools/run_tests.ps1` | Tests | [VERIFIED: repo] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Own `.chart` parser | Port JS `parsehero` | No Godot lib exists; format is simple; own parser gives line numbers and caps |
| `AudioStreamSynchronized` | N `AudioStreamPlayer`s | Drift risk between players; Sync is verified to work |
| Thread via `WorkerThreadPool` | `Thread` | Pool handles lifecycle; use one long task |
| JSON cache | ConfigFile / Resource | JSON is safe for untrusted data (no `ResourceLoader` code paths) and diff-friendly |

**Installation:** none. No external packages are installed in this phase (dev-time Python only uses stdlib; see Section 8).

## Package Legitimacy Audit

No external packages are recommended for the game. `slopcheck` was not run (nothing to check). For research only I used `pip install --target <scratch> numpy miniaudio` to analyse the audio; these are not dependencies of the project and nothing from them ships.

| Package | Registry | Disposition |
|---------|----------|-------------|
| (none recommended) | — | n/a |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 user:// songs  ----+                       +--> cache hit? (path+mtime+size sig) --yes--> SongEntry (from cache)
 extra lib folders -+--> SongScanner  ------+                                       |
 (.zip -> extract   |   (WorkerThreadPool,  +--> no: ChartParser.parse(bytes) --------+--> ChartImporter
  to user://cache)  |    one task, Mutex      |      song.ini parse                       (per difficulty:
                    |    queue, cancel flag)  |      AudioLoader.probe (Opus? length)      4-lane map, merge,
 res://songs/       |                         v                                           sustain secs, solos,
 (bundled, manifest)|                  SongEntry {id, path, meta, diffs[], error,         fingerprint)
                    |                  fingerprints{diff}, duration, signature}               |
                    v                         |                                              v
              progress counters --poll--> SongLibrary (autoload; entries, sort, filter) --> user://song_cache.json
                                              |
              SongSelect (ItemList + detail panel) --highlight 0.4s debounce--> PreviewPlayer (own AudioStreamPlayer, Music bus)
                                              |  Enter
                                              v
              SongLibrary.build_chart(entry, diff)  -> ChartData (+audio_stream via AudioLoader, solos, id=fingerprint)
                                              v
              Gameplay.pending_chart / pending_practice / pending_autoplay  -> existing Conductor flow
              ScoreStore.submit(fingerprint) after run
```

### Recommended Project Structure
```
src/core/chart_parser.gd      # text -> ParsedChart (ticks); tolerant; line numbers; caps
src/core/chart_importer.gd    # ParsedChart + diff -> ChartData; MAPPING_VERSION, IMPORTER_VERSION; solos; fingerprint
src/core/song_ini.gd          # tolerant song.ini reader
src/core/song_entry.gd        # data class for the library
src/core/song_scanner.gd      # walk + zip extract + cache; runs on worker thread (no scene/tree access)
src/core/song_cache.gd        # JSON load/save with validation
src/audio/audio_loader.gd     # load_stream(path), probe(path) (Opus detect), stems assembly
src/autoload/song_library.gd  # owns scan lifecycle, signals, sort/filter
src/ui/song_select.gd (+ scene)
src/content/bundled_songs.gd  # manifest of res://songs/<id>/ folders
songs/<id>/{notes.chart,song.ini,song.mp3|wav}   # bundled (res://songs)
tools/charting/author_chart.gd  # deterministic generator for bundled charts
tests/fixtures/charts/*.chart  # fixture charts (text only; no audio committed)
```

### Pattern 1: Chart grammar (tolerant, line-numbered)

[CITED: github.com/TheNathannator/GuitarGame_ChartFormats docs/Chart-File-Formats/chart-format/Format-Overview.md and Tracks/5-Fret-Guitar.md]

Structure:
```
[Song]
{
  Name = "x"
  Resolution = 192
}
[SyncTrack]
{
  0 = TS 4
  0 = B 120000
  768 = TS 3 3
}
[Events]
{
  0 = E "section Intro"
  3840 = E "solo"
}
[ExpertSingle]
{
  768 = N 0 0
  768 = N 5 0
  960 = N 2 96
  960 = S 2 768
  1056 = E solo
  1248 = E soloend
}
```
Rules to implement:
- Entries are `<tick> = <TYPE> <args...>`; split on the first `=`; tick is a base-10 integer. Named entries in `[Song]` are `Key = value`; strings are quoted but there are no escapes, so strip only the first and last quote and tolerate stray quotes inside.
- Types: `A` anchor (microseconds, ignore), `B` tempo (value = BPM x 1000; `150325` = 150.325 BPM), `TS n [exp]` (denominator = 2^exp, default exp 2; exp min 0), `E` text event, `N fret length`, `S type length`.
- Missing tick-0 `B` means 120 BPM; missing tick-0 `TS` means 4/4; missing `Resolution` defaults to 192 (spec says required, but be lenient and warn).
- Notes: 0=G, 1=R, 2=Y, 3=B, 4=O, 5=forced flip (modifier, no gem), 6=tap modifier, 7=open. Sustain is in ticks; the spec says sustains are not cut off in `.chart`.
- Track names: `ExpertSingle`, `HardSingle`, `MediumSingle`, `EasySingle` (lead guitar). Ignore `Double*`, `Keyboard`, `*Drums`, `*GHL*`, unknown sections.
- Solo: local events `E solo` and `E soloend` (unquoted) inside the track section. **Notes at the same tick as `soloend` ARE included in the solo.** Also check global `[Events]` for `E "solo"`/`"soloend"` as a fallback (old charts), as D-17 states. Prefer the per-track pair for the selected difficulty; if the track has none, use the global pair.
- Events in a section "should" be in tick order but may not be: sort stably by tick after reading, keeping file order for same-tick events.
- Encoding: strip UTF-8 BOM (EF BB BF); some charts are UTF-16 (FF FE / FE FF BOM), decode with `PackedByteArray.get_string_from_utf16()`; split on `\n` and strip `\r`; skip blank lines and lines starting with `//`.
- File naming: prefer `notes.chart`; else any `*.chart` (prefer names ending `[Y]`/`[F]`/`(Y)` over `[N]`).

Error and tolerance policy (D-08, SONG-06):
- **Fatal (song listed greyed): "Unreadable .chart (line N)"** when the first non-blank, non-comment line is not a `[Section]` header (binary garbage), a `{` is missing after a header, or the file exceeds the size cap. N is the 1-based line of the first structural violation.
- **Fatal: "No guitar chart"** when none of the four `*Single` tracks has at least one gem after import.
- **Non-fatal (skip line, count warnings, keep first warning line for debug):** bad tick, unknown fret number, negative length, malformed `B`/`TS`, truncated final section (missing `}` at EOF).
- Hostile-input caps (security): file <= 64 MB, <= 1,000,000 lines, <= 300,000 notes per track, tick <= 2^31-1, Resolution clamped to 1..65535 (0 or negative -> default 192 plus warning), `B` value <= 0 ignored, BPM clamped 1..2000 after division. All numeric parses via a helper that rejects non-integers instead of `int()` silently returning 0 (avoid treating garbage as tick 0).

Tick to seconds:
```gdscript
# Source: derived from spec; seg.sec precomputed cumulatively as double
# segments sorted by tick; B at same tick: last wins. seg = {tick, bpm, sec}
func tick_to_sec(tick: int) -> float:
    var s := _seg_for(tick)                      # binary search, last seg with seg.tick <= tick
    return s.sec + float(tick - s.tick) / float(resolution) * 60.0 / s.bpm
# building: sec[i+1] = sec[i] + (tick[i+1]-tick[i]) / resolution * 60 / bpm[i]
```
Sustain seconds = `tick_to_sec(tick + len) - tick_to_sec(tick)` (tempo changes inside a sustain handled). Apply `song.ini delay` (ms, **higher = later notes**, may be negative [CITED: song-ini Standard-Tags]): `time += delay / 1000.0`. The `[Song] Offset` key is documented as "start time of the audio in seconds"; Clone Hero's use of it is [ASSUMED] to be none, so ignore `[Song] Offset` and only honour `song.ini delay` (log it in the entry for debugging). Notes whose final time is < 0 (negative delay) are dropped with a warning, because `ChartData.add_note` asserts `time >= 0`.

`ChartData.tempo_map` must be `{time, bpm}` seconds-based (the Arena/BeatClock consume it). Build it from the tempo segments with delay applied. Store time signatures separately if wanted later (`TS` does not affect seconds).

### Pattern 2: 5-fret to 4-lane mapping (SONG-02, D-01/D-02/D-04)

```gdscript
const MAPPING_VERSION := 1
const IMPORTER_VERSION := 1
# per tick-group of gems (colours 0..4 and open 7 at the same tick):
#   lanes = {}                                   # lane -> sustain ticks
#   G(0)->0  R(1)->1  Y(2)->2  B(3)->3  O(4)->3  Open(7)-> lanes 1 AND 2
#   on collision in a lane keep the longest sustain
```
- Open + colours at the same tick is invalid in real charts; union them (do not drop), keep longest sustain per lane.
- Forced (5) and tap (6) lines create no gem. Parse and ignore (D-04).
- Sustain threshold: Real `.chart` files contain tiny accidental sustains. Recommend `len_ticks * 4 <= resolution` (<= a 16th note) becomes duration 0. This is [ASSUMED] (Clone Hero's threshold is unverified); expose as a constant so it is easy to retune. Check `InputJudge`/`JudgeConfig` sustain tick interval and use at least that as the minimum hold.
- Chords are kept as independent lane notes (the judge treats chords as independent lanes, `input_judge.gd` header), so **a solo's "note count" = number of lane-notes whose time is within `[start, end]`** (consistent with what the judge will count in Phase 3).
- Output `ChartData.solos: Array[Dictionary]` as `{start: float, end: float, note_count: int}` (add the field; default empty). Solo start/end are seconds with delay applied; `end` = time of the `soloend` tick. A solo missing its `soloend` ends at the last note; an unmatched `soloend` is ignored; nested `solo` while open is ignored.
- Store the mapping/importer version in `ChartData` (e.g. `meta`) so Phase 4 can show a mismatch reason.

### Pattern 3: Audio loading with explicit detection

```gdscript
# AudioLoader.probe/load, by magic bytes first, extension second
static func detect(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return "missing"
    var head := f.get_buffer(64)
    var s := head.get_string_from_ascii()   # OggS .. OpusHead / \x01vorbis
    if head.size() >= 4 and head[0] == 0x4F and head[1] == 0x67 and head[2] == 0x67 and head[3] == 0x53:
        return "opus" if s.contains("OpusHead") else "ogg"
    if s.begins_with("RIFF") and s.substr(8, 4) == "WAVE": return "wav"
    if s.begins_with("ID3") or (head.size() > 1 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0): return "mp3"
    return "unknown"
```
- `.opus` extension or an Ogg container with `OpusHead` -> error "Opus audio not supported" (verified: engine returns null and logs an error for non-Vorbis input). Never call `load_from_file` on a file you detected as Opus (avoids console error noise).
- Stem assembly: reserved names (case-insensitive, extensions ogg/mp3/wav/opus) `song`, `guitar`, `rhythm`, `bass`, `keys`, `drums`, `drums_1..4`, `vocals`, `vocals_1..2`, `crowd` [CITED: Supported-Audio-Files.md]. `preview.*` is a preview-only file (use it for the preview if present, do not add to the mix). Fallback to `[Song] MusicStream` / `song.ini`-less single-audio-file folder (one audio file, any name) only if no reserved names exist. If exactly one stem, use the stream directly; if more, build `AudioStreamSynchronized` (`stream_count`, `set_sync_stream(i, s)`). Failing optional stems (`crowd`, `vocals*`) are skipped; failing core stems make the song unsupported.
- `AudioStreamMP3`: set `loop = false`. MP3 encoder delay/padding: Godot's decoder does not advertise gapless trimming; residual offset is usually tens of ms and is covered by `song.ini delay` and the player's calibration [ASSUMED, not measured against a reference]. Do not try to auto-correct.
- Duration for fingerprint and display: `stream.get_length()` (works for Sync: longest stem). Decode/parse cost measured: MP3 4 ms, 34 MB WAV 165 ms.
- `AudioStreamPlayer` must be in the tree before `play()`; creating and playing in the same frame of `_init` fails (probe error). Not an issue in scenes.

### Pattern 4: Background scan + cache

- One `WorkerThreadPool.add_task(_scan, false, "song scan")`. The task must touch only `RefCounted`/files, never nodes. Push finished `SongEntry` objects into an `Array` guarded by a `Mutex`; the autoload drains it in `_process` (batch per frame, e.g. <= 8 ms) and emits `entries_added` / `progress(done, total)` / `scan_finished`. Keep `_cancel: bool` (checked between songs) and wait for the task (`WorkerThreadPool.wait_for_task_completion`) in `_exit_tree` / before starting a rescan.
- Phase A (fast): enumerate candidate song folders (depth cap ~6, entries cap, no following loops) and zips so `total` is known; Phase B: process each. Progress = processed/total.
- Cache: `user://song_cache.json` = `{"v": 1, "importer": IMPORTER_VERSION, "mapping": MAPPING_VERSION, "entries": {<abs path>: {sig, ...entry}}}`. `sig` = chart size + mtime, song.ini size + mtime, and size + mtime of each audio file (all via `FileAccess.get_modified_time`/`get_length`; cheap). Hit when `sig` equal and cache `v`/importer/mapping versions equal; otherwise re-import. Include error entries in the cache (failed songs are cached with their reason). Validate everything loaded from JSON by type (it is a user-writable file); on any problem discard the cache and rescan. Save atomically (tmp then rename), same pattern as `ScoreStore.save`.
- Entry fields: id/path, title, artist, charter, length_sec, bpm (first tempo or "min-max"), `preview_start_ms`, `difficulties: [{name, note_count, fingerprint}]`, `has_solos`, `error: ""`, `warnings: int`.
- Detail panel BPM comes from the tempo map, not from `song.ini`.
- Zip extraction (on the worker thread): destination `user://song_cache/zips/<sha1(zip path + mtime + size)>/`; skip extraction if destination marker exists. Security per entry: normalise `\` to `/`, reject empty names, absolute paths, drive letters (`:`), any `..` segment, entries ending in `/` (create dirs only under the destination); extract only allow-listed extensions (`chart ini ogg mp3 wav opus mid`); caps: <= 4,000 entries, cumulative extracted bytes <= 2 GiB (note `ZIPReader.read_file` loads the entire file into memory, so also cap one entry at ~512 MiB); `make_dir_recursive` for parents because zip order is not guaranteed [CITED: ZIPReader docs]. Never modify or delete the user's zip. A zip with a top-level folder is handled because the walk is recursive.
- Song folder detection: a directory is a song if it has a `*.chart` (or `song.ini` + audio). A `.mid`-only folder is listed as "MIDI charts not supported yet" (D-08 style, not silently dropped).

### Pattern 5: Preview player (independent of the Conductor)

- `SongSelect` owns an `AudioStreamPlayer` on the `Music` bus (exists in `default_bus_layout.tres`). Debounce: restart a 0.4 s `Timer` on every highlight change; on timeout, load the stream **on a worker task** (WAV 165 ms or big OGG would hitch the frame), then on the main thread assign it and `play(from_sec)` where `from_sec = preview_start_time/1000` if set and `< length - 5 s`, else `0.3 * length`. Ignore a result if the highlight has moved on (compare a request id).
- Fade in/out with a `Tween` on `volume_db` (e.g. -40 to 0 over 0.4 s; stop after fade out 0.25 s). Stop and free on Esc, Enter (dive) and `_exit_tree`; the Conductor owns its own player so nothing is shared.
- Prefer `preview.*` file if present; otherwise the assembled mix (for stems use the same Sync stream). Cache the last 1-2 loaded streams to make up/down scrubbing cheap; cap memory.
- Respect `Settings.volume_music`.

### Pattern 6: Fingerprint (SONG-05, D-15)

Use integers only so every peer on every OS computes the same digest:
```gdscript
# per (song, difficulty)
var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256)
var sb := PackedStringArray()
sb.append("u:%d:m:%d" % [IMPORTER_VERSION, MAPPING_VERSION])
sb.append("d:%s" % diff_name)                          # "easy".."expert"
sb.append("len:%d" % int(round(duration_sec * 10.0)))   # 0.1 s buckets
for t in tempo_map: sb.append("b:%d:%d" % [int(round(t.time * 1000.0)), int(round(t.bpm * 1000.0))])
for n in notes (sorted time, lane): sb.append("n:%d:%d:%d" % [int(round(n.time*1000.0)), n.lane, int(round(n.duration*1000.0))])
ctx.update("\n".join(sb).to_utf8_buffer())
var id := "u%d.%s.%s" % [IMPORTER_VERSION, ctx.finish().hex_encode().substr(0, 24), diff_letter]
```
- Hash the **post-merge 4-lane notes** (sorted), so renamed/re-saved/re-ordered charts match, and the mapping version is inside the hash.
- Include `song.ini delay` implicitly (it is in the times). Do not hash metadata strings (title/artist) so retagging does not change identity.
- `ScoreStore.sanitize_id` allows `[a-z0-9_.:-]`, max 64: the id above (about 31 chars) is safe. Use `chart.id = fingerprint`.
- Audio is represented only by duration (D-15). Two different encodes of the same length will match; accepted by decision.

### Pattern 7: Records (D-16)

- `ScoreStore.MAX_SECTIONS := 256` **will truncate** a real library (4 difficulties x many songs). Raise it (e.g. 8192) and add a test; the existing test-chart id `test.hand_chart.v1` keeps working untouched (D-16 "keep harmlessly").
- Key = fingerprint (already includes difficulty). Song select shows `ScoreStore.best(fp)` for the highlighted difficulty. Load the store once per song-select entry, not per row.
- Sort by best score requires the best depth for each row (use the Expert or highest-played difficulty; define: max best depth across the song's difficulties).

### Anti-Patterns to Avoid
- **Calling `ChartData.add_note` with unvalidated numbers:** it asserts (debug builds crash). Validate in the importer.
- **Loading audio on the UI thread during scan:** do it in the worker; and never during scan for songs whose cache hit is valid.
- **Using `int(str)` for ticks:** `"abc".to_int()` is 0 and masks corrupt data. Use a strict integer check (`is_valid_int()`).
- **Giving `Settings` extra folders to `FileAccess` blindly:** normalise and require existing directories.
- **Using `ResourceLoader.load` on user paths:** can instantiate arbitrary resources (T-style rule already in `ScoreStore`). Only `load_from_file` for user files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OGG/MP3/WAV decoding | Decoder | `AudioStream*.load_from_file` | Engine-verified |
| Stem mixing | Sample mixer | `AudioStreamSynchronized` | Sample-accurate sync, verified length and position |
| Zip reading | Inflate | `ZIPReader` | Built in |
| Hashing | SHA | `HashingContext` | Built in |
| Opening Explorer | `OS.execute("explorer")` | `OS.shell_show_in_file_manager(globalized, true)` | Cross-platform, no shell injection |
| Atomic file save | direct write | tmp + `DirAccess.rename_absolute` (pattern in `ScoreStore.save`) | Crash safety |
| Big list rendering | 1000 `Button` nodes | `ItemList` (or `Tree`) | Virtualised drawing; handles 5k songs |

**Key insight:** Everything heavy is already in the engine. The real work is defensive parsing and careful threading, not new technology.

## Runtime State Inventory

Not a rename/refactor phase. One adjacent note: existing `user://scores.cfg` records (`chart:test.hand_chart.v1`) remain valid; no data migration needed (just raise the section cap). `user://songs` and `user://song_cache*` are new.

## Common Pitfalls

### Pitfall 1: Hostile or sloppy chart data trips an `assert` or loops
**What goes wrong:** Negative delay, `Resolution = 0`, `B 0`, huge ticks, NaN BPM yield negative/infinite times; `ChartData.add_note` asserts.
**How to avoid:** Validate everything in the importer; clamp as listed; unit test with hostile fixtures; run the parser in the scanner behind the caps so a bad song can only produce an error entry.
**Warning signs:** debug-build assertion in `chart_data.gd` during a scan.

### Pitfall 2: Digits 1-4 are both navigation (D-11) and search characters (D-12)
**What goes wrong:** Typing "1999" in the filter jumps the selection.
**How to avoid:** Letters/space/punctuation append to the filter immediately; digits 1-4 navigate **only while the filter text is empty**, otherwise they are typed. Backspace edits; Esc clears a non-empty filter first and goes back only when empty. Lane keys in game are rebindable (`BindingStore`), so do not reuse gameplay bindings on this screen.

### Pitfall 3: Scan thread touching the scene tree or autoload state
**How to avoid:** Worker only builds `SongEntry` and writes files; results cross via Mutex-guarded array drained in `_process`. Do not call `push_error`-heavy loops; do not `print` per file.

### Pitfall 4: `AudioStreamPlayer.play()` before being in the tree; preview loading hitch
See Pattern 3/5. Load previews on a worker, play on main.

### Pitfall 5: Bundled audio and export (res://)
**What goes wrong:** Godot imports `.mp3`/`.wav` under `res://`; the exported PCK holds the imported resource, not the raw file, so `AudioStreamMP3.load_from_file("res://...")` can fail in an exported build even though it works in the editor. Also `export_presets.cfg` `include_filter="*.json,*.cfg"` does not include `.chart`/`.ini` (non-resource files).
**How to avoid:** Add `*.chart,*.ini` to `include_filter`. For `res://` audio use `ResourceLoader.load(path) as AudioStream` (imported resource) inside `AudioLoader.load_stream`, and `load_from_file` only for `user://`/absolute paths. Verify with `tools/export.ps1` plus a smoke run of the exported exe (Wave 0 spike) [MEDIUM: standard Godot behaviour, not exercised here]. `DirAccess` listing of `res://` in an exported build shows `*.import`/remapped names, so **do not enumerate bundled songs by directory**; use an explicit manifest constant in `bundled_songs.gd` and read `notes.chart`/`song.ini` via `FileAccess` at known paths.
Size: the Space Synth Wave source WAV is 34 MB; the import default keeps PCM. Options: accept it, or set the WAV import to QOA/IMA-ADPCM in the `.import` (lossy, [ASSUMED] timing-safe); decide in planning. The April MP3 is only 5 MB.

### Pitfall 6: Extra library folder = Clone Hero's huge library
A real CH library is thousands of songs with many stems. The cache must make the second start fast; do not decode audio on cache hits; keep entries small; ItemList not Buttons; cap the displayed warnings.

### Pitfall 7: Zip slip / zip bombs
Per Pattern 4 caps and path checks. Test with a `ZIPPacker`-made zip containing `../evil.txt`, `C:/x.chart`, and a deep path.

### Pitfall 8: Tempo math drift
Compute cumulative seconds per segment once and add an in-segment remainder (do not accumulate per note). Use `float` doubles (GDScript floats are 64-bit).

### Pitfall 9: `ScoreStore.MAX_SECTIONS = 256`
See Pattern 7; silent record loss on large libraries.

### Pitfall 10: Same-tick events at the segment boundary
`B` and `TS` at the same tick, multiple `B` at one tick (last wins), notes before the first tempo (use default 120 at tick 0).

## Code Examples

### song.ini tolerant reading
```gdscript
# ConfigFile is strict (rejects lines without '=' outside sections, odd quoting). Prefer a tiny reader:
static func parse(text: String) -> Dictionary:
    var d := {}
    var in_song := false
    for raw in text.lstrip("\uFEFF").split("\n"):
        var line := raw.strip_edges()
        if line == "" or line.begins_with(";") or line.begins_with("#"): continue
        if line.begins_with("["):
            in_song = line.to_lower() == "[song]"; continue
        var eq := line.find("=")
        if not in_song or eq < 0: continue
        d[line.substr(0, eq).strip_edges().to_lower()] = line.substr(eq + 1).strip_edges()
    return d
```
Keys used [CITED: song-ini/Standard-Tags.md]: `name`, `artist`, `charter` (`frets` is a synonym to ignore), `song_length` (ms, metadata only: never trust, use audio length), `preview_start_time` (ms; -1 means unset), `delay` (ms; higher = later notes), `diff_guitar`. Strip rich-text tags like `<color=#00FF00>` from displayed strings (`<[^>]*>` regex) and cap length (e.g. 120 chars) before rendering in Labels.

### Open songs folder
```gdscript
var dir := ProjectSettings.globalize_path("user://songs")
DirAccess.make_dir_recursive_absolute(dir)
OS.shell_show_in_file_manager(dir, true)   # verified present in 4.7.2
```

### Zip entry guard
```gdscript
static func safe_rel(name: String) -> String:
    var n := name.replace("\\", "/")
    if n == "" or n.begins_with("/") or n.contains(":"): return ""
    for seg in n.split("/"):
        if seg == "..": return ""
    return n.simplify_path()
```

### Worker + drain skeleton
```gdscript
var _mutex := Mutex.new(); var _done: Array = []; var _task := -1; var _cancel := false
func rescan() -> void:
    _cancel_and_wait()
    _cancel = false
    _task = WorkerThreadPool.add_task(_scan_all, false, "undertow song scan")
func _process(_d: float) -> void:
    _mutex.lock(); var batch := _done.duplicate(); _done.clear(); _mutex.unlock()
    # add to entries, emit signals; when WorkerThreadPool.is_task_completed(_task) -> finished
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Convert audio externally / import only in editor | `AudioStreamOggVorbis/MP3/WAV.load_from_file` at runtime (WAV loader is newer; present in 4.7.2) | Players can drop files in |
| Multiple players per stem | `AudioStreamSynchronized` (4.3+) | One stream for the Conductor |
| `OS.shell_open` for folders | `OS.shell_show_in_file_manager` | Opens and selects properly |

**Deprecated/outdated:** Opus is the recommended format in new Clone Hero charts [CITED: Supported-Audio-Files.md] but Godot cannot decode it; that is the main compatibility gap (D-08 reason string; Phase 2.1 or a future converter can address it).

## Section 8: Bundled songs (SONG-04, D-14)

Both tracks are by **Pro Sensory (Alex McCulloch)** on OpenGameArt, license **CC0 1.0**; the uploader says "all my music is public domain" and asks (does not require) that his name is included in credits. [VERIFIED: opengameart.org pages fetched]. I downloaded each and measured with Godot (length) and a stdlib-style onset/autocorrelation analysis (numpy, scratch only). Results are measured, not claimed by the author.

| Track | Page | Direct download | Format | Length | BPM (measured) | Grid |
|-------|------|-----------------|--------|--------|----------------|------|
| **Synth Wave April 3, 2022** | https://opengameart.org/content/synth-wave-april-3-2022 | https://opengameart.org/sites/default/files/synth_wave_april_3_2022_3.mp3 | MP3, 5.1 MB | 128.05 s (Godot) | 120.0 constant | exactly 64 bars of 4/4; beat phase 0.017 s, stable across the whole file |
| **Space Synth Wave** ("Cool 80's Synth Wave.wav") | https://opengameart.org/content/space-synth-wave | https://opengameart.org/sites/default/files/Cool%2080%27s%20Synth%20Wave.wav | WAV 44.1 kHz 16-bit stereo, 33.9 MB | 192.01 s (Godot) | 120.0 constant | exactly 96 bars; beat phase 0.372 s (mod 0.5 s), stable |

Mood: both are synth-wave/electronic; tags "synth wave", "space", "electronic", "Battle" [CITED: OGA tags]. Fits the neon abyss. Energy is moderate-steady rather than aggressive, so charts should get their drama from density/section planning, not from the audio.

Alternate (not recommended as the pair): "Dark Night" (dark_night_0.mp3, https://opengameart.org/content/dark-night, CC0, MP3 134.8 s, ~120.07 BPM but beat phase drifts 0.10 to 0.03 s over the track, so a fixed-120 grid would drift). Skip unless a third track is wanted. OGA also has "Resistors" (Spring Spring; multi-license incl. CC-BY, single short tune) which is not suitable.

**Important caveats for the planner [verify in a listening spike]:**
- The measured beat phase is where onset energy peaks, which may be a beat or an off-beat and it is not guaranteed to be bar 1 beat 1. Put the tempo `B 120000` at tick 0 and an audio **delay** (ms) in `song.ini` equal to the measured phase (April: ~+17 ms; Space: ~+372 ms or -128 ms, whichever lands on a kick), then verify by running the chart under **Autoplay** with a click overlay / by ear, and adjust `delay` until kicks line up. Autoplay is the existing test harness for this.
- MP3 decoder start offset can add ~tens of ms to April; this is absorbed by the same `delay` tuning (tune against Godot's decoder, which is what ships).
- Credits: README + in-game Credits line: "Synth Wave April 3, 2022 / Space Synth Wave by Pro Sensory (Alex McCulloch), CC0, via OpenGameArt.org".

### How to author the charts (no auto-charting of audio)
Write a deterministic generator `tools/charting/author_chart.gd` (GDScript, run `--headless --script`; Python 3.14 stdlib is also installed if preferred, but GDScript keeps one language) that emits `.chart` text at `Resolution = 192`, `B 120000`, `TS 4`.
1. **Hand-written section plan** (committed data, the creative part): a table of bar ranges with label, intensity 0..4, and pattern family. Both tracks are 8-bar-phrase structured. Measured per-bar RMS shows: Space Synth Wave has a loud accent every 4th bar (bar 4 and 8 of each 8-bar phrase peak at 1.0, 8-bar blocks alternate 0.70/0.83 average); April has a 4-bar accent (bar 4 of every group is 1.0, odd bars 0.6-0.7). Use bar-level `[Events]` `section` names on 8-bar boundaries (Intro, Verse, Drive, Break, Drop, Outro) and use the accent bars as fills.
2. **Pattern library by difficulty** (templates on a 16th grid, seeded `RandomNumberGenerator` with a fixed seed so output is reproducible):
   - Easy: quarter notes on beats 1 and 3 (1 and 2 in high-intensity), one lane at a time, lane steps of at most 1, no chords, a few sustains on held pad bars.
   - Medium: quarters plus some 8ths, lane steps <= 2, occasional two-note chords on bar downbeats.
   - Hard: 8ths with 16th pickups at accents, chords on accent beats, sustains.
   - Expert: 8th/16th mix following intensity, stairs/trills/zigzags, chords on accents, extended sustains.
   - Derive lower difficulties from Expert by **thinning** (keep on-beat gems, drop off-beat gems, collapse chords to the lower lane) so all four feel like the same song, then apply the difficulty's constraints.
3. **Constraints that keep it musically sensible:** a gem on every kick-like downbeat of an accent bar; rest bars in Break sections; no same-lane sustain overlap (the judge closes overlapping holds); sustain end >= one 16th before the next gem in that lane; max 3 simultaneous lanes (and 4-note chords only on Expert accents); keep a density cap per difficulty (about 1.0 / 1.6 / 2.6 / 3.8 notes per second as a starting target; Space at 120 BPM is 2 beats per second).
4. **One solo per song** on a high-intensity 8 to 16-bar block, >= 16 notes, with `E solo` / `E soloend` in the Expert (and Hard) tracks. This gives Phase 3 a real fixture.
5. **Validate** by loading the output with the real importer in a test (note counts per difficulty, no overlap, solo count >= 16, sorted ticks, first note after the intro), and run Autoplay all-perfect on each.
6. Output the generated `.chart` files to `songs/<id>/notes.chart` plus a hand-written `song.ini` (name, artist, charter = "UNDERTOW", `delay`, `preview_start_time`, `song_length`, `diff_guitar`). Commit generated files; the generator is a dev tool (excluded from export by `tools/*`).

## Section 9: Export and distribution

- `export_presets.cfg` preset 0: `export_filter="all_resources"`, `include_filter="*.json,*.cfg"`. Change to `"*.json,*.cfg,*.chart,*.ini"`. `exclude_filter` already strips `addons/*,tests/*,reports/*,tools/*,build/*`; `tests/fixtures` is therefore excluded automatically; `tools/charting` too.
- Bundled audio: see Pitfall 5 (imported resource via `ResourceLoader`). The PCK carries it, so `tools/dist.ps1` needs no change except the zip gets larger (+~40 MB with the WAV; consider the QOA/ADPCM import option or MP3-only to keep the Discord upload small). User songs are never exported: they live in `user://songs` or the user's own folders.
- Update `tools/dist/README.txt` with: songs folder location, how to drop songs/zips, 5-to-4 lane rule, Opus not supported, credits.
- Windows `user://` is `%APPDATA%\Godot\app_userdata\<project name>` unless the project sets a custom user dir; the "Open songs folder" button removes the need for players to know this.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Clone Hero ignores `[Song] Offset` and honours only `song.ini delay` | Pattern 1 | Imported charts with an `Offset` would be shifted vs CH |
| A2 | Sustains of <= a 16th note should be treated as taps | Pattern 2 | Slightly different hold feel than CH on sloppy charts |
| A3 | MP3 encoder padding offset is small and absorbed by `delay` plus calibration | Pattern 3 | Systematic offset on MP3-only songs |
| A4 | Bundled res:// audio needs `ResourceLoader.load` (imported) in exported builds | Pitfall 5 | Bundled songs silent in the exported exe (caught by export smoke test) |
| A5 | QOA/ADPCM WAV import is timing-safe | Pitfall 5 | Only matters if chosen |
| A6 | Measured beat phases (0.017 s / 0.372 s) correspond to usable grid anchors | Section 8 | Needs a listening spike and `delay` tuning |
| A7 | Density targets per difficulty (1.0/1.6/2.6/3.8 notes/s) feel right | Section 8 | Retune after playtest |
| A8 | UTF-16 charts exist in the wild and `get_string_from_utf16` handles them | Pattern 1 | Some songs show "Unreadable" |

## Open Questions

1. **Is `res://` raw-file audio loadable in an exported build?** Known from Godot's import system that it usually is not; the Wave 0 spike (export + run) settles it. Recommendation: use the imported-resource path for `res://`.
2. **Calibration Track visibility (D-13 discretion).** Recommendation: always listed, sorted last, tagged "Calibration Track", since the first-launch wizard and tests use it. Hide in release only if friends find it confusing.
3. **Mixed-stem failure policy.** Recommendation as in Pattern 3 (core stem failure = unsupported; optional stem failure = skip).
4. **Partial-chart difficulties.** A difficulty track with notes fewer than ~5 is listed but greyed? Recommendation: hide difficulties with 0 gems, show all others.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.7.2 console (GODOT_BIN) | tests, probes, export | yes | 4.7.2.stable | — |
| gdUnit4 | tests | yes (addons/) | repo | — |
| Python 3 | optional chart generator, analysis | yes | 3.14 (stdlib; numpy absent) | write generator in GDScript |
| ffmpeg / ffprobe | audio conversion | no | — | not needed; bundled tracks are already MP3/WAV |
| Network | OGA downloads | yes | — | files already fetched in scratch during research |

Missing with no fallback: none.

## Validation Architecture

(`workflow.nyquist_validation` is false in `.planning/config.json`; included because the request asked for it.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | gdUnit4 (existing, 310 tests) |
| Config file | none beyond `addons/gdUnit4` |
| Quick run command | `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_chart_parser.gd` |
| Full suite command | `powershell -NoProfile -File tools/run_tests.ps1` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SONG-01 | Folder with chart+ini+wav imports; zip extracts; `delay` applied | integration | `run_tests.ps1 -Path res://tests/test_song_scanner.gd` | Wave 0 |
| SONG-01 | Tick to seconds across tempo changes, TS exponent, sustain across a tempo change | unit | `... test_chart_parser.gd` | Wave 0 |
| SONG-02 | G/R/Y/B/O/open mapping, Blue+Orange merge keeps longest, forced/tap ignored | unit | `... test_chart_importer.gd` | Wave 0 |
| SONG-03 | Filter/sort logic, digit-vs-filter rule, preview start selection and debounce (pure functions) | unit | `... test_song_library.gd` | Wave 0 |
| SONG-04 | Bundled songs import: 4 difficulties, note counts, density, solo >= 16, sorted, audio length matches | integration | `... test_bundled_songs.gd` | Wave 0 |
| SONG-05 | Same fingerprint after rename, whitespace/re-save, event reorder; differs on 1 note, difficulty, mapping version | unit | `... test_song_fingerprint.gd` | Wave 0 |
| SONG-06 | Opus header, missing audio, no guitar track, garbage file line number, hostile numbers, zip slip, zip bomb caps, bad cache JSON | unit | `... test_song_errors.gd` | Wave 0 |
| SONG-07 | track solo pair, global pair fallback, soloend-tick note inclusive, note_count, no markers = none, unmatched markers | unit | `... test_chart_solos.gd` | Wave 0 |
| D-16 | ScoreStore with > 256 songs retained; per-difficulty keys | unit | `... test_score_store.gd` | extend existing |
| Export | Bundled songs load from exported exe | manual/script | `tools/export.ps1` + smoke run | Wave 0 spike |

### Fixture strategy
- `tests/fixtures/charts/*.chart` (text, committed): `minimal.chart`, `tempo_change.chart` (B 120 -> 180 mid-sustain), `time_sig.chart`, `frets_all.chart` (0-4, 5, 6, 7, blue+orange chord, open chord), `solo_track.chart`, `solo_global.chart`, `solo_inclusive.chart`, `crlf_bom.chart`, `utf16.chart` (write bytes in test), `out_of_order.chart`, `garbage.chart` (line number assertion), `truncated.chart`, `hostile.chart` (Resolution 0, B 0, tick 99999999999, negative length, NaN-like text), `no_guitar.chart` (only drums).
- Audio is generated at test time, never committed: `AudioSynth` (existing) to `AudioStreamWAV.save_to_wav("user://...")`; Opus fixture = a byte array with `OggS` + `OpusHead`; zips built with `ZIPPacker` (including `../evil.txt`, `C:/x.chart`, and nested folder cases). Real OGG decode is covered by a manual check with a real Clone Hero song (no OGG encoder available here).
- Use temp dirs under `user://test_*` and clean in `after_test` (pattern from `test_score_store.gd`). Worker thread tests: wait on completion with a timeout (poll `is_task_completed`), never sleep blindly.
- Autoplay-all-perfect on both bundled songs at all four difficulties via existing `Autoplay` + `InputJudge` (headless), to prove the generated charts are playable and sustain overlap-free.

### Sampling Rate
- **Per task commit:** the single new test file for that unit.
- **Per wave merge:** full suite.
- **Phase gate:** full suite green plus a human playtest: (1) drop a real CH folder and a zip, (2) greyed Opus song with reason, (3) preview, (4) both bundled songs sound aligned with notes.

### Wave 0 Gaps
- [ ] Fixtures and the test files above.
- [ ] Spike: exported exe loads bundled `res://` audio (Pitfall 5).
- [ ] Spike: bundled song `delay` tuning with Autoplay (Section 8).
- [ ] Spike: multi-stem Sync song through the real `Conductor` (probe showed playback position advances; the Conductor path itself is untested).

## Security Domain

(`security_enforcement` is true, ASVS level 1.)

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3 Authentication/Session | no | n/a (offline) |
| V4 Access Control | no | n/a |
| V5 Input Validation | **yes** | Strict tolerant parser with size/line/note/tick caps; JSON cache validated by type; strip rich-text tags and cap lengths of displayed metadata |
| V6 Cryptography | partial | `HashingContext` SHA-256 for identity only (not security) |
| V12 Files/Resources | **yes** | Zip path-traversal guard, extension allow-list, size caps; `load_from_file` only, never `ResourceLoader`/`load()` on user-supplied paths; extra folders are read-only (never write into them) |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Zip slip (`../`, absolute, drive letters, backslashes) | Tampering | `safe_rel` guard, write only under hashed cache dir |
| Zip bomb / huge files | DoS | Entry-count, per-entry and cumulative byte caps; extract on worker; user can cancel/rescan |
| Malicious `.chart` (huge ticks, millions of lines, resolution 0) | DoS | Caps and clamps; assert-safe importer |
| Poisoned cache JSON | Tampering | Version check, type validation, discard on mismatch; never evaluate content |
| Rich-text/BBCode in titles | Spoofing/UI | Labels (not RichTextLabel with BBCode enabled); strip `<...>` and control chars; length cap |
| Symlink/junction loops in song folders | DoS | Depth cap and entries cap |
| Console-injection via `OS.shell_*` | Elevation | Use `shell_show_in_file_manager` with a globalized, existing directory only |

## Sources

### Primary (HIGH confidence)
- Godot 4.7.2 console binary probes (headless, run in this session): `AudioStreamMP3/WAV.load_from_file`, Ogg failure mode, `AudioStreamSynchronized` length and playback position, `ClassDB` presence of `shell_show_in_file_manager`, `WorkerThreadPool`; timings for MP3/WAV load and 34 MB `get_sha256`.
- https://docs.godotengine.org/en/latest/classes/class_audiostreamsynchronized.html , `..._audiostreammp3.html`, `..._audiostreamwav.html`, `..._audiostreamoggvorbis.html`, `..._zipreader.html`
- https://github.com/TheNathannator/GuitarGame_ChartFormats : docs/Chart-File-Formats/chart-format/Format-Overview.md, chart-format/Tracks/5-Fret-Guitar.md, song-ini/Standard-Tags.md, song-ini/Format-Overview.md, Supported-Audio-Files.md
- Repo: `src/core/chart_data.gd`, `score_store.gd`, `input_judge.gd`, `src/ui/main_menu.gd`, `gameplay.gd`, `export_presets.cfg`, `tools/dist.ps1`, `tools/run_tests.ps1`, `default_bus_layout.tres`, `03-SPEC.md` requirement 11

### Secondary (MEDIUM confidence)
- OpenGameArt pages for the three Pro Sensory tracks (license CC0 and file URLs) : https://opengameart.org/content/synth-wave-april-3-2022 , https://opengameart.org/content/space-synth-wave , https://opengameart.org/content/dark-night
- Own audio analysis (onset autocorrelation) for BPM/phase: measured, but beat anchors require a listening check.

### Tertiary (LOW confidence)
- Clone Hero behaviours not covered by the spec docs (Offset ignoring, sustain threshold, MP3 padding): tagged [ASSUMED].

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (built-ins, probed on 4.7.2)
- Architecture: HIGH (follows repo patterns)
- Chart grammar: HIGH (spec read directly)
- Bundled tracks: MEDIUM-HIGH (licenses and lengths verified; beat anchors need a spike)
- Export of bundled audio: MEDIUM (needs smoke test)
- Pitfalls: HIGH

**Research date:** 2026-10-08
**Valid until:** 2026-11-07 (stable engine and format)
