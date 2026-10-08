---
phase: 02-chart-import-songs
plan: 02
subsystem: song-library
tags: [audio-loader, zip, scanner, cache, autoload, worker-thread, gdscript, tdd]
requires:
  - phase: 02-01
    provides: ChartParser, SongIni, ChartImporter, fingerprint
provides:
  - AudioLoader (detect, load_file, load_song_audio, classify_stems)
  - ZipExtractor (safe_rel, extract with caps)
  - SongEntry, SongCache
  - SongScanner (scan, scan_sync, import_folder, import_bare, read_id3)
  - SongLibrary autoload (entries, rescan, build_chart, load_audio, calibration_entry, songs_dir, open_songs_folder)
  - BundledSongs manifest (empty, plan 05 fills it)
affects: [02-03, 02-04, 02-05, 02-06]
tech-stack:
  added: []
  patterns: [worker-thread scan with Mutex queue drained in _process, path+mtime+size signature cache, central-directory pre-check of zip sizes, header-sniffed audio decoding]
key-files:
  created:
    - src/audio/audio_loader.gd
    - src/core/zip_extractor.gd
    - src/core/song_entry.gd
    - src/core/song_cache.gd
    - src/core/song_scanner.gd
    - src/content/bundled_songs.gd
    - src/autoload/song_library.gd
    - tests/helpers/song_fixture.gd
    - tests/test_audio_loader.gd
    - tests/test_song_errors.gd
    - tests/test_song_scanner.gd
    - tests/test_song_library.gd
  modified:
    - project.godot
key-decisions:
  - "ZIPReader has no size query, so ZipExtractor parses the end-of-central-directory record itself and validates every claimed size before any read_file; Zip64 archives are refused."
  - "SongLibrary skips the boot scan under headless display (and via auto_scan) so test runs never touch the developer's real songs folder; tests use their own instance with songs_root_override/cache_path."
  - "Each rescan clears entries and re-emits them via entries_added, calibration entry first; consumers clear on scan_started."
  - "A zip with no usable song inside is reported as ERR_ZIP (same row as a failed unpack)."
  - "Unknown audio header returns ERR_UNSUPPORTED_AUDIO, decode failure ERR_AUDIO_BAD; .mp3 files with an odd header are still sent to the decoder."
  - "A loose folder with several non-reserved audio files and no chart yields one Needs-a-chart entry per file."
requirements-completed: [SONG-01, SONG-05, SONG-06]
duration: ~70 min
completed: 2026-10-08
---

# Phase 2 Plan 02: Audio loading, song scanner and SongLibrary Summary

Drop-in songs now work end to end: a background scan of the Songs folder, extra folders and zips produces SongEntry rows (ok, needs a chart, or broken with an exact one-line reason), and `SongLibrary.build_chart` turns a row plus difficulty into a playable ChartData whose id is the stored fingerprint.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 AudioLoader, ZipExtractor, SongEntry, SongCache, fixtures | 31683e3 | 16 tests |
| 2 SongScanner | 51a7ff6 | 14 tests |
| 3 SongLibrary autoload, BundledSongs, project.godot | d994976 | 8 tests |

Full suite: 396 test cases, 0 failures (358 existing + 38 new). Timing-core gate (`git diff --stat 72e21ce -- conductor clock_model input_judge judge_config hull_score`) prints nothing.

## Contracts for downstream plans

- `SongLibrary` signals: `scan_started`, `entries_added(batch)`, `progress(done,total,label)`, `scan_finished(count, unplayable)` (count excludes the Calibration entry). On `scan_started` clear lists; the Calibration entry arrives again through `entries_added` first.
- `entries[0]` is always the Calibration entry (`source "test"`, id `test.hand_chart.v1`).
- `SongEntry.status`: "ok", "needs_chart" (error = "Needs a chart"), "broken". `fix_hint` is pre-filled from `SongEntry.hint_for`.
- Test hooks on a SongLibrary instance: `songs_root_override`, `cache_path`, `auto_scan`, `shell_opener` (Callable). Scanner statics: `zip_cache_root`, `max_depth`, `max_candidates`, counters `parse_count`/`decode_count`.
- Bundled songs: fill `BundledSongs.SONGS` with `{id, dir, audio}`; the library imports them through `SongScanner.import_folder` with an audio override and the same cache.
- `extra_folders` is a plain `Array[String]` (use `.assign`); plan 04 wires it from Settings. `last_song_id`/`last_difficulty` are in-memory only.
- `build_chart` refuses (null, `last_build_error`) when the recomputed fingerprint differs from the stored one ("Song changed since the last scan. Press Rescan.").

## Deviations from Plan

### Auto-fixed Issues

None needed beyond test-only corrections (stale cache in one test, typed-array assignment).

### Notes

- `ZipExtractor.extract` takes an optional `limits` dictionary (max_entries, max_total, max_entry) so cap tests do not allocate large data.
- Broken-mp3 and garbage-Ogg test cases make the engine print decode errors to the log; the tests pass and the scanner reports ERR_AUDIO_BAD.
- No bundled-song scan test yet (manifest is empty); plan 05 verifies the res:// path.

## Known Stubs

`BundledSongs.SONGS` is intentionally empty (plan 05 fills it).

## Threat Flags

None beyond the plan's threat model. T-02-06..T-02-11 mitigated and tested (zip-slip, entry and size caps, depth and count caps, no symlink following, poisoned cache discarded, read-only extra roots, shell_show_in_file_manager only on a just-created absolute directory).

## Self-Check: PASSED
