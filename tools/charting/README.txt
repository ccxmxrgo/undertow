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
  To be re-measured against the decoded MP3 in plan 06 (A3: encoder padding; compensate
  if > 5 ms). measure_grid.py cannot decode MP3; record the Godot output to a WAV and
  run the tool on that.
