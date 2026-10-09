Bundled song charts (plan 02-05)
================================
author_chart.gd   Deterministic .chart generator. Input is the hand-written per-bar plan in
                  section_plans.gd (the creative part); the audio is never analysed.
                  Run from the repo root:
                    godot --headless --path . --script res://tools/charting/author_chart.gd -- all
                  Add --stats to print notes and notes/s per difficulty instead of writing.
                  Same input gives byte-identical output (fixed seeds); tests regenerate and compare.
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

Charts: 120 BPM, 4/4, Resolution 192, bar = 768 ticks = 2 s. Expert is authored from the plan
(8ths/16ths by intensity, stairs/zig/trill/pulse lane families, accent chords on every 4th
bar); Hard/Medium/Easy are derived from Expert by thinning. Each difficulty carries the same
solo bar span (April bars 40-48, Space bars 48-56), >= 16 notes in Hard and Expert.

Delay evidence (song.ini delay; chart time = tick time + delay, so bar 0 starts at audio
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
