---
phase: 02-chart-import-songs
plan: 05
subsystem: bundled-content
tags: [bundled-songs, chart-generator, cc0-audio, autoplay, gdscript]
requires: [02-01, 02-02]
provides:
  - Two bundled CC0 songs (Pro Sensory) with Easy/Medium/Hard/Expert charts and solos
  - Deterministic seeded chart generator driven by a hand-written section plan
  - BundledSongs.SONGS manifest filled; credits recorded in songs/CREDITS.txt
affects: [02-06]
tech-stack:
  added: []
  patterns: [seeded generator as dev tool, explicit res:// manifest, derive lower difficulties by thinning]
key-files:
  created:
    - songs/CREDITS.txt
    - songs/synth_wave_april/{song.mp3,song.mp3.import,song.ini,notes.chart}
    - songs/space_synth_wave/{song.wav,song.wav.import,song.ini,notes.chart}
    - tools/charting/{author_chart.gd,section_plans.gd,measure_grid.py,README.txt}
    - tests/test_bundled_songs.gd
  modified:
    - src/content/bundled_songs.gd
    - tests/test_song_library.gd
key-decisions:
  - "Space Synth Wave delay = 372 ms (strongest accent hit lands on the bar-4 boundary; -128 puts it off the bar line). April keeps +17 ms, to be re-measured in 02-06."
  - "WAV kept as repo source, imported as QOA (Godot 4.7 default compress/mode=2, ~6.8 MB sample vs 33.9 MB); no encoder installed."
  - "All four difficulties carry the same solo span (April bars 40-48, Space bars 48-56); Hard and Expert have >= 16 notes in it."
requirements-completed: [SONG-04, SONG-07]
completed: 2026-10-09
---

# Phase 2 Plan 05: Bundled songs and chart generator Summary

Two CC0 Pro Sensory tracks ship in the game with generated 4-difficulty charts (120 BPM, 64 and 96 bars), a solo each, a manifest, credits with SHA-256, and Autoplay/audio-length tests.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 Download and import the two approved tracks | ced844e | MP3 5122216 B, WAV 33871132 B, magic bytes verified, both pages CC0, SHA-256 in CREDITS.txt |
| 2 Generator, section plans, charts, song.ini, manifest | 0a83b09 | 9 tests; also measure_grid.py and README with delay evidence |
| 3 Autoplay, audio lengths, library listing | a0e0861 | 11 tests in test_bundled_songs.gd; full suite 475 cases, 0 failures |

## Results

- Density (notes/s, April / Space): Easy 0.92 / 0.98, Medium 1.85 / 1.87, Hard 2.51 / 2.69, Expert 3.43 / 3.49 (all inside the plan bands). Note counts April 113/229/310/423, Space 183/351/505/655.
- Generator output is byte-identical across runs and equal to the committed files (test normalises CRLF checkouts).
- Autoplay all-perfect (0 miss, 0 good, every note judged) for all 8 chart/difficulty pairs through `SongLibrary.build_chart` on the bundled `res://` entries; imported audio lengths within 0.15 s of 128.0 / 192.0 s (the test bound; MP3 128.05 s, QOA WAV 192.01 s as measured in research).
- Timing-core gate (`git diff --stat 72e21ce` on conductor, clock_model, input_judge, judge_config, hull_score): empty.
- Delay evidence for Space (measure_grid.py, stdlib only, run with `python -I`): delay 372 gives bar-downbeat onset 1509 vs beat-3 1103; -128 gives 796 vs 1070. The strongest hit of the 4-bar group (2358) falls on the first beat of bar 4 only on the 372 grid. Method resolution is about +-30 ms (dotted-eighth rhythm), so 02-06 must confirm by ear / recorded audio and may adjust only the song.ini delay lines.
- Download: only the two approved URLs were fetched (plus the two OpenGameArt pages for the licence check). Nothing installed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] test_song_library.gd assumed no bundled entries**
- **Found during:** Task 3 full-suite run
- **Issue:** Three tests hard-coded entry counts and `entries[1]` positions; the two bundled songs are now listed in every scan.
- **Fix:** counts use `1 + BundledSongs.SONGS.size()`, positional lookup replaced by `_user_song(lib)` helper.
- **Files modified:** tests/test_song_library.gd
- **Commit:** a0e0861

**2. [Scope] measure_grid.py and tools/charting/README.txt were committed with Task 2** (README documents both tools; the Task 3 commit holds only tests). No behavior change.

**3. WAV import mode:** Godot 4.7 already generated `compress/mode=2` (QOA) on first import, so no re-import step was needed.

## Notes for 02-06

- export_presets.cfg include_filter still needs `*.chart,*.ini` (02-06 task) for the bundled charts to enter the PCK.
- April delay (+17 ms) and Space delay (372 ms) are research/onset-based initial values; verify by ear and recorded decoded audio, update `tools/charting/README.txt`.
- Easy/Medium solo spans carry fewer than 16 notes guarantees are not asserted (only Hard/Expert, per plan).

## Known Stubs

None.

## Threat Flags

None. T-02-22 (two approved URLs, size, magic bytes, SHA-256, files never executed), T-02-23 (CC0 re-verified on both pages, credits stored), T-02-24 (stdlib-only Python, `-I`) mitigated.

## Self-Check: PASSED
Files and commits ced844e, 0a83b09, a0e0861 present.
