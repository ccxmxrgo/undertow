---
phase: 02-chart-import-songs
plan: 06
status: awaiting-checkpoint
subsystem: verification-and-release
tags: [playtest-harness, song-select, export, audio-alignment, release-zip, gdscript]
requires:
  - phase: 02-03
    provides: SongSelect screen and test seams, menu routing through Song Select
  - phase: 02-04
    provides: Settings LIBRARY, library persistence
  - phase: 02-05
    provides: two bundled songs, charts, initial delays
provides:
  - Windowed harness scenario "songs" (70 checks) and "align" (decoded + recorded bundled audio)
  - Phase 1 scenarios re-routed through Song Select (menu_focus / dive_from_song_select helpers)
  - run_all.ps1 with --no-boot-scan, SHA-256 + real Songs folder proof
  - SongLibrary --selftest-bundled (BUNDLED_OK n / BUNDLED_FAIL), --no-boot-scan, scan throttle hook
  - export include_filter *.json,*.cfg,*.chart,*.ini; v0.3 README and zip
  - Bundled delays measured on decoded audio (April 48 ms, Space 525 ms)
affects: [phase-02-verification, release-v0.3]
tech-stack:
  added: []
  patterns:
    - "offline decode through AudioStreamPlayback.mix_audio for sample-exact alignment checks"
    - "rescans update the on-screen list in place (replace / append, prune at scan end)"
    - "every WorkerThreadPool task is reaped (wait_for_task_completion)"
key-files:
  created:
    - tests/test_playtest_harness.gd
    - tools/charting/grid_offset.py
    - .planning/phases/02-chart-import-songs/02-HUMAN-UAT.md
    - .planning/phases/02-chart-import-songs/deferred-items.md
  modified:
    - tools/playtest/playtest_driver.gd
    - tools/playtest/run_all.ps1
    - src/autoload/song_library.gd
    - src/ui/song_select.gd
    - export_presets.cfg
    - tools/dist.ps1
    - tools/dist/README.txt
    - tools/charting/README.txt
    - songs/synth_wave_april/song.ini
    - songs/space_synth_wave/song.ini
    - tests/test_song_select.gd
    - tests/test_bundled_songs.gd
key-decisions:
  - "Space Synth Wave delay 525 ms (was 372): no attacks within 60 ms of the old chart downbeats; at 525 downbeat attacks are -2 ms (IQR -6/+2) and bar-downbeat strength 3x higher. April 48 ms (was 17): MP3 decoder padding +31 ms."
  - "Both bundled songs confirmed 120 BPM by whole-song repetition lags (31997 ms / 16 bars April; 47996 / 63994 ms Space); short Space lags near 2004 ms/bar are a free-running echo."
  - "Harness passes --no-boot-scan so SongLibrary never reads the real Songs folder; scenarios use user://playtest_library."
  - "Bundled cache signature includes chart/ini MD5 because exported res:// mtimes are 0."
requirements-completed: []
duration: ~2h40m
completed: 2026-10-09 (automated tasks; human checkpoint pending)
---

# Phase 2 Plan 06: Harness, export, alignment, v0.3 zip Summary

Windowed harness covers Song Select end to end (369/369 checks across 13 scenarios). The exported build passes a bundled-song self-test (BUNDLED_OK 8). Both bundled delays were re-measured against the game's own decoded audio and corrected. The v0.3 zip (44.46 MB) is built. The plan is now waiting at the human-verify checkpoint (Task 3), which is never auto-approved.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 Harness "songs", self-test hook, export filter, README, dist v0.3 | d941f42 | songs scenario plus Song Select routing for the old scenarios; --selftest-bundled; include_filter adds *.chart,*.ini; README with Songs folder, lane rule, Opus/.mid note and credits; dist v0.3 |
| 2a Windowed run: Song Select defects fixed | f93ccd3 | 4 defects fixed, each with a regression test (below) |
| 2b Delay tuning on decoded audio, signature fix | 14fd11d | align scenario, grid_offset.py, April 17->48, Space 372->525, MD5 in bundled signature |
| 2c UAT evidence | ceb835f | 02-HUMAN-UAT.md |
| 3 Human playtest | - | **awaiting user** (checkpoint) |

## Verification

- Windowed harness, final run (`run_all.ps1 -SkipDrift`): a 39, b 15, c 10, d 25, e 13, f 8, g 17, h 18, i 14, layout 42, polish 34, immersion 64, songs 70. Total 369/369, 0 scenarios failed. Real settings.cfg and drift_log.csv SHA-256 unchanged, scores.cfg absent before and after, real Songs folder untouched.
- Headless suite: 484 cases, 0 failures. One earlier run hit the known flaky `test_pause_overlay` case; it fails the same way on an untouched HEAD checkout (see deferred-items.md).
- Exported `undertow-debug.console.exe -- --selftest-bundled`: `BUNDLED_OK 8`, exit 0. The console exe unzipped from the v0.3 zip gives the same result.
- Zip: build/dist/UNDERTOW-playtest-v0.3.zip, 46,623,567 bytes. Entries: README.txt, undertow-debug.exe, undertow-debug.pck (11.8 MB), undertow-debug.console.exe.
- Timing-core gate (`git diff --stat 72e21ce` on conductor, clock_model, input_judge, judge_config, hull_score): empty.
- No godot or undertow process left running.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rescan moved the selection off its screen row**
- Found during: Task 2 (songs scenario: row 6 -> 2, offset 9 -> 16)
- Fix: SongSelect keeps `_all` during a rescan. Entries are replaced or appended through an id->index map, and unseen entries are pruned on scan_finished. The row now stays put (6 -> 6, offset +3).
- Files: src/ui/song_select.gd, tests/test_song_select.gd (fails on the old code, passes on the new). Commit f93ccd3

**2. [Rule 1 - Bug] Crash on quit after an audio preview (0xC0000005)**
- Found during: Task 2 (songs scenario exit code; bisected to the preview phase)
- Fix: preview WorkerThreadPool task ids are tracked and reaped with wait_for_task_completion, every frame once finished and in `_exit_tree` at the latest.
- Files: src/ui/song_select.gd, tests/test_song_select.gd. Commit f93ccd3

**3. [Rule 1 - Bug] Song count mismatch ("36 songs" in the filter field vs "35 songs" in the footer)**
- Fix: `filter_count_text()` leaves out the Calibration Track, matching the footer. Commit f93ccd3

**4. [Rule 1 - Bug] Empty-state Songs path broken mid-folder-name ("UND" / "ERTOW")**
- Fix: `wrap_path()` breaks after "/". Commit f93ccd3

**5. [Rule 1 - Bug] Bundled delays were wrong by +31 ms (April) and about +153 ms (Space)**
- The plan expected at most a small MP3-padding correction. Space's 02-05 value (372) was a ±30 ms estimate on a soft, pad-driven track. Only the song.ini delay lines changed, as the plan allows. The test constant DELAYS in test_bundled_songs.gd was updated to match.
- Evidence: tools/charting/README.txt and 02-HUMAN-UAT.md. Commit 14fd11d

**6. [Rule 2 - Missing critical] Stale bundled cache after a same-size song.ini change**
- In an exported .pck the res:// mtime is 0, so a delay change of the same length (17->48, 372->525) would keep the old cache fingerprint. The song would then fail with "Song changed since the last scan" even after a rescan. The bundled signature now includes the chart and ini MD5. A regression test was added. Commit 14fd11d

**7. [Rule 3 - Blocking] Harness isolation from the real Songs folder**
- The autoload boot scan runs before the driver. Added the user argument `--no-boot-scan`, which run_all.ps1 passes. The driver binds `SongLibrary.settings_ref = Settings` (temp file) itself, because the flag leaves it unbound. Commits d941f42, 14fd11d

### Other notes
- Added `tests/test_playtest_harness.gd` (the driver compiles, run_all lists songs, hooks default to off, export filter). Not in the plan's file list.
- The empty-library screenshot uses a stub SongLibrary instance with no entries. The real game always lists the Calibration Track and the bundled songs, so it only shows "NO SONGS FOUND" if the bundled content fails to load.
- Committed untracked Godot .uid files (tests and tools/charting).
- The drift scenario was skipped (`-SkipDrift`, per orchestrator instruction).

## Known Stubs

None.

## Threat Flags

None. T-02-26 (temp library root, --no-boot-scan, SHA-256 and folder proof), T-02-28 (zip entries verified), T-02-30 (only the two CC0 tracks, credits in README) are mitigated. The selftest uses user://selftest_* paths and deletes them afterwards.

## Checkpoint (Task 3)

Pending. The orchestrator must send the phone push notification first and must not auto-approve. The checklist is in 02-HUMAN-UAT.md (items a-h). Phase 2 is NOT verified.

## Self-Check: PASSED
Files exist: tests/test_playtest_harness.gd, tools/charting/grid_offset.py, 02-HUMAN-UAT.md, deferred-items.md, build/dist/UNDERTOW-playtest-v0.3.zip. Commits d941f42, f93ccd3, 14fd11d and ceb835f are present in git log.
