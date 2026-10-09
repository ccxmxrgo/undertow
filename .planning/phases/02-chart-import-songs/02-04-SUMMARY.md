---
phase: 02-chart-import-songs
plan: 04
subsystem: persistence
tags: [score-store, settings, library, gdscript, tdd]
requires:
  - phase: 02-02
    provides: SongLibrary autoload, SongEntry
provides:
  - ScoreStore.MAX_SECTIONS 8192 (per-fingerprint records at library scale)
  - Settings library_folders / last_song_id / last_difficulty in [library] (validated)
  - SongLibrary last_* and extra_folders backed by Settings (settings_ref)
  - Settings > LIBRARY section (add/remove folder, status, hints)
affects: [02-05, 02-06]
key-files:
  modified:
    - src/core/score_store.gd
    - src/autoload/settings.gd
    - src/autoload/song_library.gd
    - src/ui/settings_screen.gd
    - tests/test_score_store.gd
    - tests/test_settings_roundtrip.gd
  created:
    - tests/test_library_settings.gd
key-decisions:
  - "SongLibrary.settings_ref is bound to the Settings autoload in _ready only when auto_scan is true, so tests never write the real settings.cfg"
  - "folder_error text left as 'Folder not found: path'; Song Select (02-03) already renders the spec copy from it"
requirements-completed: [SONG-03, SONG-05]
duration: ~40min
completed: 2026-10-09
---

# Phase 2 Plan 04: Library persistence and Settings LIBRARY Summary

ScoreStore cap raised to 8192, Settings persists extra folders and last song/difficulty, and Settings has a LIBRARY section with validated Add/Remove Folder and a rescan on leaving when the list changed.

## Commits
- aad0218: ScoreStore cap, Settings [library] fields and validation
- f8f7a84: LIBRARY section, SongLibrary-Settings wiring, tests

## Details
- Settings [library]: folders capped at 8, strings <= 1024 chars, non-strings and duplicates dropped, last_difficulty whitelisted to easy/medium/hard/expert, last_song_id <= 1024. Old configs and garbage sections load defaults. `set_last_played()` saves only on change.
- SongLibrary: `last_song_id`/`last_difficulty` keep their names and types (setters now persist through `settings_ref`); `extra_folders` is refreshed from Settings at the start of every `rescan()`. Loading from Settings does not write back.
- Settings screen: order Controls, Gameplay, Display, Audio, Library, Calibration. `add_library_folder(path) -> String` returns "" or the exact spec errors (plus a Songs-folder rejection). Native directory dialog via DisplayServer with FileDialog fallback; `folder_picker` seam used by tests. Remove only forgets the path. Rescan on back only if the list differs from when the screen opened.
- Timing-core diff vs 72e21ce is empty. Full suite: 464 tests, 0 failures, 0 orphans.

## Deviations from Plan
- [Rule 1] Existing `test_section_cap` assumed the 256 cap (1000 sections, c255 present); rewritten to use `MAX_SECTIONS + 50` since the cap intentionally changed.
- folder_error string unchanged (see key-decisions); not a behavior gap.

## Known Stubs
None.

## Self-Check: PASSED
