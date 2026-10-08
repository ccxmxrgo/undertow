---
phase: 02-chart-import-songs
plan: 01
subsystem: chart-import
tags: [chart-parser, song-ini, importer, fingerprint, solos, gdscript, tdd]
requires: []
provides:
  - ChartParser.parse_bytes -> ParsedChart (tolerant, capped, line-numbered)
  - SongIni.parse / sanitize_text / get_int
  - ChartImporter (difficulties, build, fingerprint, MAPPING_VERSION/IMPORTER_VERSION)
  - ChartData additive fields (solos, meta, difficulty, artist)
affects: [02-02, 02-03, 02-04, 02-05, 02-06]
tech-stack:
  added: []
  patterns: [pure RefCounted static utilities, strict integer parsing, integer-only SHA-256 fingerprint]
key-files:
  created:
    - src/core/parsed_chart.gd
    - src/core/chart_parser.gd
    - src/core/song_ini.gd
    - src/core/chart_importer.gd
    - tests/test_chart_parser.gd
    - tests/test_chart_importer.gd
    - tests/test_chart_solos.gd
    - tests/test_song_fingerprint.gd
    - tests/fixtures/charts/ (12 fixtures)
  modified:
    - src/core/chart_data.gd
key-decisions:
  - "Parser caps are injectable through an optional limits dictionary so cap tests allocate nothing large."
  - "Fingerprint takes an optional versions override (tests only) instead of mutating constants."
  - "Tempo map times are clamped to >= 0 under negative delay (earlier segments collapsed)."
  - "[Song] Offset ignored; recorded as meta.ignored_offset when present."
requirements-completed: [SONG-01, SONG-02, SONG-05, SONG-06, SONG-07]
duration: ~45 min
completed: 2026-10-08
---

# Phase 2 Plan 01: Chart import core Summary

Pure, deterministic `.chart` import core: tolerant parser, song.ini reader, 5-fret to 4-lane importer with solos, and an integer-only SHA-256 song fingerprint (`u1.<24 hex>.<e|m|h|x>`).

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 Parser, SongIni, ChartData fields | 0e9ef90 | 15 tests |
| 2 ChartImporter mapping, tempo, delay, solos | b2df582 | 26 tests (importer 15, solos 11) |
| 3 Fingerprint and end-to-end tests | 061ed48 | 7 tests |

Full suite: 358 test cases, 0 failures (310 existing + 48 new). Timing-core gate (`git diff --stat 72e21ce -- conductor clock_model input_judge judge_config hull_score`) prints nothing.

## Deviations from Plan

- `ChartImporter.fingerprint` was implemented in the Task 2 commit (same file); its tests landed in the Task 3 commit. No behavior change.
- Fixtures `community_style.chart` was authored in Task 1 (used by parser tests) and reused in Task 3.
- Otherwise none: plan executed as written.

## Notes for downstream plans

- `ChartData.id` is left empty by `build`; callers set it to the fingerprint.
- Sustain tap threshold constant: `ChartImporter.SUSTAIN_TAP_DIVISOR = 4` (len*4 <= resolution is a tap). Judge sustain tick is 0.1 s, a 16th at 120 BPM is 0.125 s.
- Parser error strings: "Unreadable .chart (line N)", "Chart too large". Callers map an empty `difficulties()` to "No guitar chart".
- `tests/test_song_fingerprint.gd.uid` is not committed yet (generated on next editor import); harmless.

## Known Stubs

None.

## Threat Flags

None. T-01..T-04 mitigated (caps, strict ints, pre-validation before add_note, sanitize_text), covered by tests.

## Self-Check: PASSED
