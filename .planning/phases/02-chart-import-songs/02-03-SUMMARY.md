---
phase: 02-chart-import-songs
plan: 03
subsystem: ui
tags: [song-select, menu, preview, gdscript, tdd]
requires:
  - phase: 02-02
    provides: SongLibrary autoload, SongEntry, build_chart, load_audio, open_songs_folder
provides:
  - SongListModel (pure filter/sort/order/nav/snap/preview/scroll rules)
  - SongSelect screen + scenes/song_select.tscn (SongList, DetailPanel, FilterField, SortChip, ScanStatus, FooterHints, CreditsLine)
  - Arena menu_mode (Conductor-free)
  - MainMenu routing Start/Practice/Autoplay through Song Select, Open Songs Folder item
affects: [02-04, 02-05, 02-06]
key-files:
  created:
    - src/core/song_list_model.gd
    - src/ui/song_select.gd
    - scenes/song_select.tscn
    - tests/test_song_list_model.gd
    - tests/test_song_select.gd
  modified:
    - src/ui/arena.gd
    - src/ui/main_menu.gd
    - tests/test_menu_flow.gd
    - tests/test_calibration_flow.gd
key-decisions:
  - "SongSelect.run_autoplay / run_practice static flags carry run mode from MainMenu; the menu no longer presets Gameplay.pending_chart"
  - "best_label kept as a hidden node for harness compatibility; best line now lives in Song Select"
  - "Open Songs Folder in menu has an open_folder Callable test seam; failure line shows the globalized user://songs path without creating folders"
requirements-completed: [SONG-03, SONG-06]
duration: n/a (split across two runs)
completed: 2026-10-09
---

# Phase 2 Plan 03: Song Select and menu wiring Summary

Pure-logic SongListModel, a code-drawn Song Select screen with debounced threaded audio preview, and a main menu that routes every dive through Song Select.

## Tasks

| Task | Commit | Notes |
|------|--------|-------|
| 1 SongListModel + tests | 8bceae9 | done by the previous run |
| 2 SongSelect screen, scene, Arena menu mode, tests | 2b808ea | done by the previous run |
| 3 Main menu wiring | dc65ef8 | this run: item order Start, Practice, Calibrate, Settings, Autoplay, Open Songs Folder, Quit; focus ring updated; launch()/launch_practice() set SongSelect run flags and navigate to song_select.tscn; 6 s red folder-failure message; hidden best_label |

## Verification

- Full suite: 446 test cases, 0 errors, 0 failures, 0 orphans (44 suites).
- Timing-core gate (`git diff --stat 72e21ce -- conductor/clock_model/input_judge/judge_config/hull_score`): empty.
- No windowed Godot run (layout checks deferred to plan 06).

## Deviations from Plan

- [Rule 1] tests/test_calibration_flow.gd also asserted old launch behaviour (pending_chart preset); updated to assert song-select navigation and run flags. Not in the plan's file list.
- The previous run noted a songs_dir() side effect in the menu failure message; the final code uses ProjectSettings.globalize_path("user://songs") directly, so no folders are created.

## Known Stubs

None.

## Self-Check: PASSED
Commits 8bceae9, 2b808ea, dc65ef8 present; files exist.
