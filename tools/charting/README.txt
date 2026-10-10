Bundled song charts
===================
SOURCE OF TRUTH (D-04): the committed songs/<id>/notes.chart and song.ini are the source of truth
for every bundled song. Tests (tests/test_bundled_songs.gd, tests/test_autochart_songs.gd) check the
committed charts and their recorded gate reports and never re-run ML or any generator. Regenerating
with tools/autochart from the same build/autochart/<id>/ intermediates is byte-identical (verified in
plans 02.1-05..07). Since plan 02.1-07 all five bundled charts are audio-driven (charter
"UNDERTOW autochart"); see tools/autochart/README.txt.

LEGACY: author_chart.gd / section_plans.gd (plan 02-05)
------------------------------------------------------
Moved to tools/charting/legacy/ in plan 02.1-07. legacy/.gdignore keeps them out of the Godot project
(class_name SectionPlans no longer exists) and out of every export; they are kept for history only.
Replaced by tools/autochart in Phase 2.1 after Phase 2 UAT item c failed: the plan-authored notes
followed a hand-written per-bar plan and ignored the music.
author_chart.gd   Deterministic .chart generator. Input was the hand-written per-bar plan in
                  section_plans.gd; the audio was never analysed. It no longer runs from res://
                  (the folder is ignored); copy both files back out of legacy/ to run it again:
                    godot --headless --path . --script res://tools/charting/author_chart.gd -- all
                  No test regenerates or compares its output any more.

Still in use
------------
measure_grid.py   Beat-grid check, Python standard library only, always run isolated:
                    python -I tools/charting/measure_grid.py <file.wav> <bpm> [delay_ms ...]
grid_offset.py    1 ms beat-grid / attack-start error of a chart delay (stdlib, run isolated):
                    python -I tools/charting/grid_offset.py <file.wav> <bpm> <delay_ms> [start_s] [end_s]
                  The "ATTACK starts vs chart downbeats / beats" medians are the +-5 ms check.
Decoded audio     The game's own streams are written by the windowed harness scenario "align"
                  (not in run_all): godot --path . res://tools/playtest/playtest.tscn -- align --no-boot-scan
                  -> build/playtest/align_<id>_decoded.wav (whole song, AudioStreamPlayback.mix_audio,
                  sample exact, 48 kHz) and align_<id>_recorded.wav (first 24 s recorded live from a
                  temp bus with AudioEffectRecord, a cross-check of the playback path).

LEGACY charts (plan-authored, replaced in 02.1-07): 120 BPM, 4/4, Resolution 192, bar = 768 ticks = 2 s. Expert was authored from the plan
(8ths/16ths by intensity, stairs/zig/trill/pulse lane families, accent chords on every 4th
bar); Hard/Medium/Easy are derived from Expert by thinning. Each difficulty carries the same
solo bar span (April bars 40-48, Space bars 48-56), >= 16 notes in Hard and Expert.

LEGACY delay evidence for the plan-authored charts (song.ini delay; chart time = tick time + delay, so bar 0 starts at audio
time delay/1000 s)
-------------------------------------------------------------------------------------
Space Synth Wave (song.wav, 192.010 s, 120 BPM):
  measure_grid.py songs/space_synth_wave/song.wav 120 372 -128 0 500 -628
    delay  372: bar-downbeat onset mean 1509, beat-3 onset mean 1103
    delay -128: bar-downbeat onset mean  796, beat-3 onset mean 1070
    delay    0: 472 / 2876;  delay 500: 2793 / 1811
  Folding the onsets of the 4-bar group at the 372 ms grid: the strongest hit of the
  group (mean onset 2358) lands on beat 12 = the first beat of bar 4 (the accent bar),
  and the next strongest (1203, 1148) on beats 8 and 10 of bar 3. With -128 the same hits
  fall on beat 11 (off the bar line). 372 puts the loudest accent on a chart bar boundary
  and its downbeats stronger than beat 3, so delay = 372 was chosen over -128.
  Caveat: the plain onset-energy method has about +-30 ms resolution (dotted-eighth synth
  rhythm); plan 06 must confirm by ear / recorded audio and may adjust only song.ini delay.

Synth Wave April 3, 2022 (MP3): initial delay +17 ms from the research measurement.

FINAL (plan 02-06, 2026-10-09), measured on the game's own decoded audio (align scenario):
  Synth Wave April 3, 2022: delay 17 -> 48
    grid_offset.py align_synth_wave_april_decoded.wav 120 <delay> 1 127
      delay 17: attack starts vs chart beats  n=158 median +31 ms (quartiles +28/+34),
                vs chart downbeats n=37 median +33 ms
      delay 48: attack starts vs chart beats  n=158 median  +0 ms (quartiles -3/+3),
                vs chart downbeats n=37 median  +2 ms (quartiles -1/+5)
    The +31 ms is the MP3 encoder/decoder padding (A3): Godot's MP3 decoder does not strip it.
    Tempo check: onset autocorrelation repeats at 7999 / 15999 / 31997 ms (4/8/16 bars) = 120 BPM.
    Live recording vs decoded: onset-grid beat phase 64.1 vs 62.9 ms (playback path adds ~1 ms).
  Space Synth Wave: delay 372 -> 525
    grid_offset.py align_space_synth_wave_decoded.wav 120 <delay> 1 191
      delay 372: NO attack starts within +-60 ms of the chart downbeats (n=0); the nearest beat
                 family is +27 ms (n=79, a 16th-note pickup layer)
      delay 525: attack starts vs chart downbeats n=28 median -2 ms (quartiles -6/+2),
                 vs chart beats n=50 median +0 ms (quartiles -5/+4)
    measure_grid.py (bar-downbeat onset mean / beat-3 / accent-bar ratio):
      372: 1464 / 1035 / 1.12    525: 4443 / 2715 / 1.17    540: 4476 / 2545 / 1.18
      (plateau 520-550; 140: 3294, 400: 2043, 1525: 2715 / 4428 = downbeat on beat 3)
    The 02-05 value 372 was a +-30 ms onset-energy estimate on a soft, pad-driven track; the
    1 ms analysis of the decoded stream puts the chart grid 153 ms early. 525 keeps the same bar
    index (the shift is less than a bar), so the accent bars still fall on bar 4 of each group.
    Tempo check: whole-song repetition at 47996 / 63994 ms (24 / 32 bars) = 120 BPM. (Short lags of
    8017 / 16035 / 32070 ms come from a free-running dotted-eighth echo, not the song tempo.)
    The last Space note (tick 73536) now lands 15 ms after the audio ends (192.025 vs 192.010 s);
    song time keeps running past the end of the stream, so it is judged normally.

AUDIO-DRIVEN RE-CHART (plan 02.1-07, 2026-10-10, STEM-07)
--------------------------------------------------------
Both songs keep their folders, audio files and ids; only notes.chart and song.ini were rewritten
(best scores reset because the chart hash changed, SPEC req 8). The old delays 48 / 525 were fitted
to the plan-authored grid and are not reused. Godot decode lag vs the soundfile decode is +0.148 ms
(April, MP3) and +0.158 ms (Space, WAV/QOA): the +31 ms MP3 padding seen in 02-06 does not affect the
new pipeline because the analysis decodes the same stream the game plays.

Stem choice, measured by tools/autochart/stem_rank.py (Expert target 3.0 n/s, mix = decoded.wav D3
delta 0.1, chance = random +-60..200 ms shifts; rule: highest mix % among stems with pitched >= 0.3
and >= 1.5 n/s):
  synth_wave_april   notes  n/s   on-grid  mix % (chance)  pitched  energy
    other            350    2.73  88.6%    92.0 (8.2)      63.1%    31.5%   <- recommended
    drums            350    2.73  80.3%    90.3 (6.9)      23.7%    33.5%
    bass             382    2.98  87.7%    86.9 (5.8)      91.9%    35.1%
    vocals           345    2.69  75.9%    88.7 (5.9)      52.5%     0.0%   (instrumental; leakage)
  space_synth_wave
    other            465    2.42  87.5%    97.2 (22.4)     89.0%    17.7%   <- recommended
    drums            537    2.80  88.4%    99.3 (14.5)      7.6%    79.7%
    bass             281    1.46  52.0%    66.5 (22.3)     60.9%     2.6%
    vocals           488    2.54  81.3%    93.7 (17.6)     41.4%     0.0%   (instrumental; leakage)

Sync gate (Expert, game's decoded stream, tools/autochart/note_sync.py --stem --beats --recorded):
  song              stem   target  Expert n/s  median mix  mix % (chance)  stem % (chance)  tempo med/p90  live lag  delay  verdict
  synth_wave_april  other  3.5     2.95        +0.3 ms     89.7 (9.8)      100.0 (33.1)     0.0 / 0.0 ms   +1.33 ms  58     PASS
  space_synth_wave  other  3.5     2.70        +0.0 ms     95.6 (22.0)     100.0 (27.5)     2.0 / 2.0 ms   +1.33 ms  164    PASS
  Before (plan-authored, reports/baseline_plan_authored.txt): April 78.5% PASS_BASELINE, Space 55.3% FAIL.
  Full numbers: tools/autochart/reports/<id>.sync.json and <id>.chart_stats.json.

GATE RESULTS (all 5 bundled songs; Expert, game's decoded stream; copy of the consolidated table,
tools/autochart/README.txt "GATE RESULTS" has the baseline rows, per-difficulty shares and notes)
  song              stem/fill        Expert n/s  median mix  mix % (chance)        stem % (chance)        tempo med/p90  delay  verdict
  sea_shanty_2      other            3.45        +0.1 ms     99.1% (chance 17.4%)  100.0% (chance 14.2%)  0.2 / 0.3 ms   72     PASS
  hrt               other+drums (b)  2.30        -0.4 ms     91.9% (chance 24.9%)  100.0% (chance 47.0%)  4.0 / 4.0 ms   -4     PASS
  invisible         other+bass (s)   2.12        +0.1 ms     80.5% (chance 24.1%)  100.0% (chance 64.2%)  1.0 / 1.0 ms   1      PASS
  synth_wave_april  other            2.95        +0.3 ms     89.7% (chance 9.8%)   100.0% (chance 33.1%)  0.0 / 0.0 ms   58     PASS
  space_synth_wave  other            2.70        +0.0 ms     95.6% (chance 22.0%)  100.0% (chance 27.5%)  2.0 / 2.0 ms   164    PASS
  Neversoft BIF     guitar (GH3)     4.08        -5.9 ms     74.0% (chance 43.2%)  55.3% (chance 39.7%)   -              -      PASS_BASELINE
  Live lag (recorded vs decoded) is +1.33 ms for every bundled song.
