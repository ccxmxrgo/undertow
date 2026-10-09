---
status: awaiting-human
phase: 02-chart-import-songs
source: [02-06-PLAN.md Task 2 (windowed verification) and Task 3 (human-verify checkpoint)]
started: 2026-10-09T00:40:00Z
updated: 2026-10-09T03:05:00Z
---

## Current Test

Automated verification is done (below). Waiting for the user's playtest of the v0.3 build
(checklist at the end). This checkpoint is never auto-approved; the phase is not verified yet.

## Automated evidence (02-06 Task 2)

### Windowed harness (real GPU / audio, 240 Hz, Windows 11)
`powershell -NoProfile -File tools/playtest/run_all.ps1 -SkipDrift`, final run after all fixes:

| Scenario | Checks |
|----------|--------|
| a | 39 / 39 |
| b | 15 / 15 |
| c | 10 / 10 |
| d | 25 / 25 |
| e | 13 / 13 |
| f | 8 / 8 |
| g | 17 / 17 |
| h | 18 / 18 |
| i | 14 / 14 |
| layout | 42 / 42 |
| polish | 34 / 34 |
| immersion | 64 / 64 |
| songs (new) | 70 / 70 |
| **total** | **369 / 369, 0 scenarios failed** |

Drift was skipped (`-SkipDrift`, as instructed; the timing core is unchanged since 72e21ce).
Headless suite: 484 test cases, 0 failures (one earlier run hit the known flaky
`test_pause_overlay` case, see deferred-items.md; it also fails on an untouched HEAD checkout).

Real user data: run_all.ps1 compared SHA-256 before / after: settings.cfg
8F53A789...B0B6 unchanged, drift_log.csv B7442FF8...F9B4 unchanged, scores.cfg absent before and
after, real Songs folder (`C:\Users\user\AppData\Roaming\Godot\app_userdata\UNDERTOW\songs`)
empty and untouched (same mtime). `--no-boot-scan` keeps SongLibrary off the real folder; the
harness used `user://playtest_library` and removed it. No godot / undertow process left.
Timing-core gate `git diff --stat 72e21ce -- conductor clock_model input_judge judge_config hull_score`: empty.

### Song Select screenshots reviewed (build/playtest/songs_NN_*.png)
- 01 library mid-list: exactly 9 rows, caret on the selected row, panel (title, artist, charter,
  length / BPM / notes, difficulty tiles, best depth, source, preview bars), footer path visible.
  Hint line ends at x 928 (filter hint 993, pad 950; limit 1040), path starts at x 1143 (>= 1056),
  credits start at x 1197 (>= 1184). Outer 32 px max channel 0.267 (<= 0.35).
- 02 preview playing: preview started 406 ms after the highlight change (gate 400 ms).
- 03 mid-scan: "Scanning 4 / 33", progress bar visible, Rescan shows "Scanning...".
- 04 broken Opus row: muted title, red "!" + "Opus audio not supported"; panel red block with the
  fix hint; Start "Unavailable"; Enter does nothing.
- 05 Needs-a-chart row: green outline "NEEDS A CHART" badge, hint line, no red anywhere; Enter does nothing.
- 06 long title: row "The Extraordinarily Long Title Of A Progressive...", panel wraps to 2 lines
  and ends with "..."; artist line truncated with "...". 07 CJK / Cyrillic title and artist render
  (system font fallback), 0 missing glyphs (shaped-glyph check), no tofu boxes.
- 08 filter no match: "NO MATCHES"; 09 filter "tide": 2 rows, "2 / 35", filter hint line.
- 10 Low effects / 11 Reduce motion: same rows; sweep off; outer band 0.247 / 0.263.
- 12 Settings > LIBRARY: Songs folder row, two extra folders: "1 song" and red "Folder not found",
  Remove Folder buttons, Add Folder.
- 13 bundled-only: both bundled songs + Calibration Track (TEST) + onboarding info row; footer path.
- 14 empty library: "NO SONGS FOUND", body, "Your Songs folder is:" and the full path (breaks after "/").
- 15 autoplay dive on an imported fixture from Song Select: chart id = fingerprint, P8 G0 M0.
- 16 gameplay on the bundled April (Autoplay, Expert): P41 G0 M0 at 22 s, 239.9 fps.
- Note (by spec, cosmetic): the row length text ("0:02") is right-aligned to x 904 and the Easy pip
  starts at x 904, so they touch. Spec-conformant; mention if it bothers you.

### Defects found by the windowed run and fixed (each with a regression test)
1. Rescan with a mid-list selection jumped the selection (screen row 6 -> 2) when new songs sorted
   above it: the list was cleared on scan start. Now entries are replaced in place, missing ones
   dropped at the end; row stays (6 -> 6, offset 9 -> 12 for 3 inserted rows).
2. Game crashed on quit (exit 0xC0000005) after any audio preview: preview WorkerThreadPool tasks
   were never waited for. Now reaped when finished and in `_exit_tree`.
3. Filter field said "36 songs" while the footer said "35 songs" (Calibration Track counted). Fixed.
4. Empty-state path wrapped inside a folder name ("UND" / "ERTOW"). Now breaks after "/".
5. (latent) Bundled song cache signature used mtime + size; in an exported .pck mtime is 0, so a
   future same-size delay change would leave a stale fingerprint ("Song changed since the last
   scan" forever). Signature now includes the chart / ini MD5.

### Audio / chart alignment (decoded audio, harness scenario "align")
The game's own streams were decoded offline (AudioStreamPlayback.mix_audio, whole song, 48 kHz)
and 24 s were recorded live from a temp bus (AudioEffectRecord). Recorded vs decoded beat phase
differs by ~1 ms, so the decoded audio is what plays. Measured with
`python -I tools/charting/grid_offset.py <wav> 120 <delay>` (attack starts vs chart beats / downbeats):

| Song | delay before | error before | delay after | error after |
|------|--------------|--------------|-------------|-------------|
| Synth Wave April 3, 2022 (MP3) | 17 ms | beats +31 ms (n=158, IQR +28/+34), downbeats +33 ms | **48 ms** | beats +0 ms (IQR -3/+3), downbeats +2 ms (IQR -1/+5) |
| Space Synth Wave (WAV/QOA) | 372 ms | no attacks within 60 ms of the chart downbeats; nearest beat layer +27 ms; bar-downbeat strength 1464 | **525 ms** | downbeats -2 ms (n=28, IQR -6/+2), beats +0 ms (IQR -5/+4); downbeat strength 4443 |

Both songs are 120 BPM (whole-song repetition at 31997 ms / 16 bars for April, 47996 / 63994 ms
for 24 / 32 bars of Space). April's +31 ms is the MP3 padding (A3). Only the song.ini delay lines
changed; charts unchanged. Details in tools/charting/README.txt.

### Exported build
`tools/export.ps1`, then `build/undertow-debug.console.exe -- --selftest-bundled`: **BUNDLED_OK 8**
(2 songs x 4 difficulties, audio > 1 s from the .pck), exit 0. The same line from the console exe
unzipped from the v0.3 zip. The self test uses throwaway user paths (removed after); real
settings / scores / song cache unchanged.

### v0.3 zip
`build/dist/UNDERTOW-playtest-v0.3.zip`, 46,623,567 bytes (44.46 MB). Entries: README.txt
(7.8 KB, contains the Songs folder section, the 5-to-4 lane rule, Opus / .mid note and the
Pro Sensory credits), undertow-debug.exe, undertow-debug.pck (11.8 MB, bundled songs inside),
undertow-debug.console.exe.

## Manual checklist for the user (Task 3)

Launch `build/undertow-debug.exe` (or unzip the v0.3 zip and run `undertow-debug.exe`).

| # | Test | Result |
|---|------|--------|
| a | Start Dive opens SELECT SONG: both bundled songs, the credits line and the Songs folder path are visible | pending |
| b | Highlight a song, wait about half a second: the preview fades in; move away: it stops | pending |
| c | Play one bundled song on 2 difficulties (Easy and Expert; Expert has a solo). Do the notes feel in time with the music? | pending |
| d | Open Songs Folder (menu or Song Select), drop a real Clone Hero song folder AND a .zip of one into the Songs folder, press Rescan Library: both appear and play | pending |
| e | An Opus-audio song shows greyed with "Opus audio not supported" (any Opus song you have) | pending |
| f | Drop a bare .mp3: it shows "NEEDS A CHART" and cannot be started | pending |
| g | Settings > Library > Add Folder: add your Clone Hero songs folder; its songs appear after leaving Settings | pending |
| h | Finish a (non-autoplay) dive: the record shows for that song and difficulty in SELECT SONG | pending |

Songs folder on this PC: `C:\Users\user\AppData\Roaming\Godot\app_userdata\UNDERTOW\songs`

Report any song that does not import (name + what SELECT SONG said), any timing problem
(song + difficulty), or anything confusing. Reply "approved" or describe the issues.
