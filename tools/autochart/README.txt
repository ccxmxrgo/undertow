UNDERTOW autochart (Phase 2.1, instrument extraction tool)
===========================================================

PURPOSE
-------
Audio-driven, Clone Hero-style charts. A human charter beat-maps the song, puts a note on every
audible onset of one instrument and moves lanes with the melody contour. This dev-side Python
tool does the same from the audio: tempo map from the real beats, notes from the onsets of one
separated stem, lanes from relative pitch. It never ships; friends only receive the charts.
Nothing in src/ depends on Python.

STEM-01 RESEARCH
----------------
Full study (measured tables per song, alternatives, pitfalls):
  .planning/phases/02.1-instrument-extraction-tool/02.1-RESEARCH.md
Chosen pipeline: soundfile decode -> htdemucs (4 stems, ~22 s CPU per song) -> beat_this beats and
downbeats + repair / smooth / phase-correct -> D3 attack-start onsets on the chosen stem + audibility
filter against the mix -> Basic Pitch (ONNX, venv B) for pitch only -> octave-folded contour lanes.
Key findings:
  - Decoder: demucs 4.1.0 reading an MP3 itself (sphn/symphonia) gives stems +25.01 ms (1103 samples)
    LATER than Godot's stream. soundfile (libsndfile/mpg123) matches Godot within 0.05 ms. Always
    decode with soundfile and feed demucs a WAV.
  - beat_this beats sit on a 20 ms frame grid and lag the attacks by 7-12 ms: phase-correct them.
  - Basic Pitch onsets are frame-quantised and early: use them for pitch only, never for timing.
  - Professional baseline (Neversoft GH3 "Before I Forget", same D3 metric): 54.5% of Expert notes
    within +-25 ms of a guitar-stem onset (chance 37.7%), 73.5% for the mix (chance 43.1%).

SETUP
-----
  powershell -NoProfile -File tools/autochart/setup_venv.ps1
Idempotent; prints AUTOCHART_ENV_OK. Installs uv 0.12.24 into build/autochart/boot (system Python
3.14 untouched), CPython 3.12.15 + 3.10.22 into build/autochart/pythons, and two venvs from the
committed exact pins:
  build/autochart/venvA  Python 3.12  requirements-a.txt  torch 2.11 cpu, demucs 4.1.0, beat-this 1.1.0,
                                                           librosa 1.0.0, soundfile 0.14.0
  build/autochart/venvB  Python 3.10  requirements-b.txt  basic-pitch 0.4.0, onnxruntime 1.23.2
                                                           (3.10 so basic-pitch picks ONNX, not tensorflow)
Disk: about 1.5 GB under build/autochart. The first pipeline run downloads htdemucs (~80 MB, HF hub)
and beat_this final0 (~77 MB, cloud.cp.jku.at) into build/autochart/cache, unless setup copied them
from build/research/cache.
Env vars for every run (the tools set them; honoured under python -I):
  HF_HOME=build/autochart/cache  TORCH_HOME=build/autochart/cache  HF_HUB_DISABLE_SYMLINKS_WARNING=1

RULES
-----
  - Always run Python as `python -I -B` (isolated: no cwd / PYTHONPATH on sys.path; -B because -I
    ignores PYTHONDONTWRITEBYTECODE, so no __pycache__ appears next to the scripts).
  - Untrusted audio never goes into tools/. Audio and intermediates live under build/ or songs/.
  - Scripts are never run from a data directory; pass data paths as arguments.
  - Only install from the committed requirements files (exact == pins).

SYNC GATE
---------
Sync is measured on the game's own decoded stream, never guessed (SPEC req 5, D-09, D-10).
1. Decode every bundled song through the game (windowed; 48 kHz decoded WAV + 24 s live recording):
     & $env:GODOT_BIN --path . res://tools/playtest/playtest.tscn -- align --no-boot-scan [--only=<id>,<id>]
     -> build/playtest/align_<id>_decoded.wav, align_<id>_recorded.wav
        (metrics <id>_decoded_s in build/playtest/align.json = real decoded length, use for song_length)
2. Gate one chart (venv A):
     build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/note_sync.py `
         songs/<id>/notes.chart songs/<id>/song.ini build/playtest/align_<id>_decoded.wav `
         --stem build/autochart/<id>/stems/<stem>.wav [--stem <second charted stem>.wav] `
         --beats build/autochart/<id>/beats.json --recorded build/playtest/align_<id>_recorded.wav `
         [--difficulty expert] [--json build/autochart/<id>/sync.json]
   Chart note / beat times come from the game's ChartImporter through a headless Godot dump
   (tools/autochart/dump_chart_times.gd, GODOT_BIN), delay included. Onsets: D3 attack-start detector
   (tools/autochart/stages/d3.py, delta 0.1). --stem is repeatable: a filled chart (e.g. other + drums)
   is gated against the union of the onsets of every charted stem.
   Prints n, median, IQR and % within +-25 ms vs stem and vs mix, each with "(chance X%)" (notes
   shifted by random +-60..200 ms, seed 0, mean of 20), tempo gate vs refined and raw beats, live lag,
   suggested_delay_ms, and a last line GATE PASS | GATE PASS_BASELINE | GATE FAIL <reasons>
   (exit 0 / 0 / 1). --json also stores chart_sha256 and ini_delay_ms so a report can be tied to the
   committed chart.
   Error sign: note - onset (negative = the note comes before the sound). RESEARCH tables use the
   opposite sign (onset - note). suggested_delay_ms = ini delay - round(median_mix).
   Reference charts: tools/autochart/mid_notes.py <notes.mid> <out.json> (stdlib) gives unique Expert
   note times for note_sync.py --notes-json (chart / ini become '-' placeholders); --extra-mix sums
   more audio into the mix (Neversoft song + guitar + rhythm).
   SPEC req 2 "tracker beats" = the refined (repaired, smoothed, phase-corrected) beat list in
   beats.json; the raw beat_this numbers are printed too (RESEARCH Pitfall 2).

Thresholds (Expert):
  metric                               SPEC fixed (PASS)   Neversoft baseline (PASS_BASELINE)   effective
  median note-to-onset, mix            within +-5 ms       within +-5.9 ms                      +-5.9 ms
  % within +-25 ms of a stem onset     >= 90%              >= 54.5%                             >= 54.5%
  % within +-25 ms of a mix onset      >= 80%              >= 73.5% with mix chance <= 45%      >= 73.5%
  tempo: chart beats vs refined beats  med <= 10, p90 <= 20 ms (both levels)                    same
  live recording vs decoded            |lag| <= 3 ms (both levels)                              same
  Stem / tempo / live checks apply only when --stem / --beats / --recorded are given. PASS_BASELINE
  songs are flagged in the phase UAT.

Baseline numbers (2026-10-09, reports/ has the full printouts):
  Neversoft "Before I Forget", 1091 Expert note times (reports/neversoft_baseline.txt):
    mix song+guitar+rhythm  74.0% (chance 43.2%), median -5.9 ms   [RESEARCH 73.5% / 43.1%]
    guitar stem             55.3% (chance 39.7%), median +2.0 ms   [RESEARCH 54.5% / 37.7%]
    song.mp3 alone as mix   70.6% (chance 28.8%)
    stems guitar + rhythm   83.0% (chance 66.0%)  (union >= guitar-only, as designed)
  Plan-authored charts, before re-chart (reports/baseline_plan_authored.txt, UAT item c FAILED):
    synth_wave_april  mix 78.5% (chance 9.9%), median -3.0 ms, live lag +1.33 ms  -> GATE PASS_BASELINE
    space_synth_wave  mix 55.3% (chance 30.0%), median -1.0 ms, live lag +1.33 ms -> GATE FAIL
  The old grid is in phase with the audio (only the notes ignore the music). Without a stem the mix
  metric cannot tell "on the beat" from "on the instrument", so new charts are always gated with
  --stem, and the ear check stays the final word.

CHART (one song, end to end)
----------------------------
  1. analyze (once per song, writes build/autochart/<id>/):
       build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py analyze --id <id> --src songs/<id>/song.mp3
  2. chart (deterministic: the same intermediates give a byte-identical notes.chart, D-04):
       build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py chart --id <id> `
           --out songs/<id> --stem <stem> --target-nps 3.5 --name <s> --artist <s> --genre <s>
     -> songs/<id>/notes.chart, song.ini, tools/autochart/reports/<id>.chart_stats.json, sections.json
     Prints [k/7] progress, per-difficulty stats, BAND FLAG lines and CHART_OK <id> <sha256>.
     --fill-stem <stem> [--fill-mode bars|sections] (stages/fill.py, RESEARCH Pitfall 9): bars = every
     bar with no primary onset takes the fill stem's onsets; sections = a section whose primary density
     is below 50% of the median section density takes all its notes from the fill stem. The audibility
     filter is never lowered instead. chart_stats.json records fill_stem, fill_mode and fill_share
     (share of Expert notes from the fill stem). Gate a filled chart with one --stem per charted stem.
  3. bundle (BundledSongs.SONGS + songs/CREDITS.txt), then measure with the SYNC GATE above,
     writing --json tools/autochart/reports/<id>.sync.json. If suggested_delay_ms differs from the ini
     delay, re-run chart with --delay-ms <suggested> --song-length-ms <decoded_length_ms> and re-gate.
     --delay-ms changes only the song.ini delay; chart ticks stay the same, so the whole chart moves
     in song time by the change (the decoded audio does not change). Always pass the decoded length.
  tests/test_autochart_songs.gd re-checks the committed chart, the report (verdict, numbers,
  chart_sha256, ini delay) and the chart stats for every id in AUTOCHART_IDS.

GATE RESULTS (all 5 bundled songs; Expert, game's decoded stream, D3 delta 0.1)
-----------------------------------------------------------------------------
Generated from the committed reports tools/autochart/reports/<id>.sync.json and <id>.chart_stats.json
(2026-10-10, plans 02.1-05..08). "(chance X)" = the same notes shifted by random +-60..200 ms (seed 0,
mean of 20): a chart that ignored the music would score about the chance level. Error sign: note - onset.
Fill: (b) = bars mode, (s) = sections mode. Stem % is measured against the union of every charted stem.
  song              stem/fill        Expert n/s  max/1 s  median mix  mix % (chance)        stem % (chance)        tempo med/p90  live lag  delay  verdict
  sea_shanty_2      other            3.45        7        +0.1 ms     99.1% (chance 17.4%)  100.0% (chance 14.2%)  0.2 / 0.3 ms   +1.33 ms  72     PASS
  hrt               other+drums (b)  2.30        5        -0.4 ms     91.9% (chance 24.9%)  100.0% (chance 47.0%)  4.0 / 4.0 ms   +1.33 ms  -4     PASS
  invisible         other+bass (s)   2.12        6        +0.1 ms     80.5% (chance 24.1%)  100.0% (chance 64.2%)  1.0 / 1.0 ms   +1.33 ms  1      PASS
  synth_wave_april  other            2.95        6        +0.3 ms     89.7% (chance 9.8%)   100.0% (chance 33.1%)  0.0 / 0.0 ms   +1.33 ms  58     PASS
  space_synth_wave  other            2.70        7        +0.0 ms     95.6% (chance 22.0%)  100.0% (chance 27.5%)  2.0 / 2.0 ms   +1.33 ms  164    PASS
  ----------------  professional baseline, re-measured with the shipped metric (reports/neversoft_baseline.txt)
  Neversoft BIF     guitar (GH3)     4.08        -        -5.9 ms     74.0% (chance 43.2%)  55.3% (chance 39.7%)   -              -         -      PASS_BASELINE
                    (RESEARCH values for comparison: mix 73.5% (chance 43.1%), stem 54.5% (chance 37.7%),
                     median -2.0 / +5.9 ms in RESEARCH sign = +2.0 / -5.9 ms in the gate's sign;
                     Expert n/s = 1091 unique note times / 267.2 s; mix = song + guitar + rhythm)
  ----------------  before: plan-authored charts (fixed 120 BPM grid, audio never analysed;
                    reports/baseline_plan_authored.txt, Phase 2 UAT item c FAILED; mix only, no stem)
  synth_wave_april  (old)            -           -        -3.0 ms     78.5% (chance 9.9%)   -                      -              +1.33 ms  48     PASS_BASELINE
  space_synth_wave  (old)            -           -        -1.0 ms     55.3% (chance 30.0%)  -                      -              +1.33 ms  525    FAIL
Every bundled song passes the fixed SPEC thresholds (no PASS_BASELINE song). Tempo maps: sea_shanty_2
has a single B event at 200 BPM (constant tempo); hrt 224 B events (~86 BPM), invisible 360 (~114 BPM),
April and Space per-beat maps at ~120 BPM. Raw beat_this tempo gate for comparison (med/p90 ms):
sea_shanty_2 7.5/12.0, hrt 13.0/24.4, invisible 6.1/14.0, April 6.3/12.1, Space 6.2/16.6.

Interpretation of "tracker beats" (SPEC req 2, RESEARCH Pitfall 2): the tempo gate compares chart beats
with the REFINED beat list in build/autochart/<id>/beats.json (beat_this beats after repair, smoothing
and phase correction onto the attacks). Raw beat_this beats sit on a 20 ms frame grid and lag the
attacks by 7-12 ms, so they are printed for reference only (numbers above).

Per-difficulty shares (chart_stats.json): n/s, max notes in any 1 s, keep share (notes kept from
Expert), chord / sustain share, lane-step histogram (repeat, +-1, +-2, +-3 or more lanes).
  song              diff    n/s   max  keep   chord  sust   repeat step1  step2  step3+
  sea_shanty_2      easy    1.89  4    0.549  0.000  0.170  0.389  0.440  0.171  0.000
  sea_shanty_2      medium  2.56  5    0.743  0.028  0.145  0.296  0.429  0.259  0.016
  sea_shanty_2      hard    3.45  7    1.000  0.051  0.124  0.290  0.461  0.248  0.000
  sea_shanty_2      expert  3.45  7    1.000  0.101  0.124  0.290  0.461  0.248  0.000
  hrt               easy    0.89  2    0.386  0.000  0.007  0.268  0.370  0.362  0.000
  hrt               medium  1.33  3    0.578  0.019  0.005  0.271  0.324  0.338  0.068
  hrt               hard    2.30  5    1.000  0.050  0.019  0.226  0.382  0.393  0.000
  hrt               expert  2.30  5    1.000  0.100  0.019  0.226  0.382  0.393  0.000
  invisible         easy    0.67  2    0.315  0.000  0.008  0.344  0.328  0.328  0.000
  invisible         medium  0.85  3    0.398  0.006  0.006  0.260  0.405  0.240  0.095
  invisible         hard    2.12  6    1.000  0.050  0.010  0.288  0.366  0.346  0.000
  invisible         expert  2.12  6    1.000  0.100  0.010  0.288  0.366  0.346  0.000
  synth_wave_april  easy    1.36  3    0.460  0.000  0.063  0.341  0.439  0.220  0.000
  synth_wave_april  medium  2.13  5    0.717  0.029  0.059  0.304  0.367  0.296  0.033
  synth_wave_april  hard    2.95  6    1.000  0.050  0.066  0.260  0.419  0.321  0.000
  synth_wave_april  expert  2.95  6    1.000  0.101  0.066  0.260  0.419  0.321  0.000
  space_synth_wave  easy    1.03  3    0.381  0.000  0.035  0.321  0.393  0.286  0.000
  space_synth_wave  medium  1.55  5    0.575  0.003  0.034  0.301  0.307  0.341  0.051
  space_synth_wave  hard    2.70  7    1.000  0.050  0.044  0.302  0.293  0.405  0.000
  space_synth_wave  expert  2.70  7    1.000  0.101  0.044  0.302  0.293  0.405  0.000
Neversoft bands (UAT FLAGS below): keep hard 0.90-1.00, medium 0.65-0.75, easy 0.45-0.55; steps repeat
0.20-0.30, +-1 0.40-0.60, +-2 0.15-0.30, +-3+ 0.00-0.05 (each +- 0.05).

Direction match (share of Expert pitch moves where the lane moves the same way as the pitch; "going
right feels like going up"): sea_shanty_2 0.785, hrt 0.829, invisible 0.823, synth_wave_april 0.811,
space_synth_wave 0.812.

DETERMINISM (D-04): the committed songs/<id>/notes.chart is the source of truth. The ML stages
(htdemucs separation, beat_this, Basic Pitch) run once per song in `analyze` and write intermediates
under build/autochart/<id>/. Every stage after separation (`chart`: tempo map, onsets, quantize, lanes,
reductions, sections, render) is deterministic, so the same intermediates give a byte-identical
notes.chart (re-verified for all five songs in plan 08: same CHART_OK sha256, byte-identical song.ini
and chart_stats.json). Tests never re-run ML: tests/test_autochart_songs.gd checks the committed charts
(structure, density caps, contour rules) against the committed reports (verdict, numbers,
chart_sha256, ini delay), and the Python suite tests the post-separation stages on synthetic note lists.

Per-song notes:
  sea_shanty_2 (plan 05): 428 unique Expert times / 471 gems, IQR mix [-6.0, +7.7] ms, Godot decode
    lag +0.16 ms, decoded length 127850 ms.
  hrt (plan 06): 360 unique Expert times / 396 gems, IQR mix [-6.5, +9.0] ms, decoded length 161877 ms.
    The drums fill added nothing (fill_share 0.0): "other" has onsets in every bar. The tick-0 chord
    sits at -4 ms in song time (the game preroll plays it; the gate dump skips it, so the report
    counts 359 times). Attempt (a) passed; (b)-(d) were not needed.
  invisible (plan 06): 400 unique Expert times / 440 gems, IQR mix [-9.5, +11.3] ms, decoded length
    191635 ms, fill_share 0.005 (one sparse section switched to bass).
    Attempts (Expert, gated with every charted stem, delay fitted until stable):
     (a) other, target 3.0                       2.24 n/s  mix 79.0% (chance 23.5%)  median -0.3  PASS_BASELINE
     (b) other + bass sections, target 3.0       2.23 n/s  mix 79.4% (chance 24.0%)  median -0.0  PASS_BASELINE
     (c) other + bass sections, target 2.5       1.95 n/s  mix 82.4% (chance 22.0%)  median +0.2  PASS, but Expert
         average 1.95 n/s is below the SPEC 2..5 n/s range (test_density_caps_and_expert_average fails)
     (d) other + drums bars, target 3.0          2.24 n/s  mix 79.0% (chance 23.5%)  median -0.3  PASS_BASELINE
     shipped: (c) with target 2.8 (2.7 gave 2.06 n/s, 80.7%), the lowest target that passes both the
     fixed gate and the density range.
  synth_wave_april / space_synth_wave (plan 07): re-charted with stem "other" (picked by
    tools/autochart/stem_rank.py). Space needed 57 beat repairs (tempo gate still 2.0 / 2.0 ms).
    Best scores of the old charts no longer match (new fingerprints).

PLAYER FLOW (STEM-02/04/05)
---------------------------
One command turns an audio file you own into separated stems and a ready-to-play song folder in
your UNDERTOW Songs folder:

  powershell -NoProfile -File tools/autochart/extract_song.ps1 -Audio "C:\Music\song.mp3" -Name "My Song" -Artist "Me"
  powershell -NoProfile -File tools/autochart/extract_song.ps1 -Audio "C:\Music\song.mp3" -Name "My Song" -Mode lanes
  (same as: build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py extract --src <file> ...)

Why a command and not an in-game button: the separator stack (about 1.5 GB of venvs and models) is
not packaged for friends' PCs (CONTEXT "Deferred Ideas"), so a button would only work on the dev PC.
An in-game screen and friend packaging are deferred. The game needs no changes: the folder lands
where the library already scans.

Modes:
  -Mode single (default)  one instrument over the 4 lanes, lanes follow its melody contour
                          (-Stem other|drums|bass|vocals, default other). Same rules as the bundled songs.
  -Mode lanes             INSTRUMENT LANES: each lane is one instrument, left to right
                          lane 0 = bass, lane 1 = drums, lane 2 = other, lane 3 = vocals
                          (low on the left, high on the right, like "right = up"). Stems hitting on the
                          same tick become a 2-lane chord (the two strongest, strength normalised per
                          stem). Easy drops the instrument lane with the fewest notes and uses 3 lanes.
                          (stages/instrument_lanes.py)
Only .mp3, .ogg and .wav are accepted (Godot cannot play FLAC/Opus at runtime: convert first).

Where things go:
  - Stems (drums/bass/other/vocals WAVs): build/autochart/user_<slug>/stems (printed as "Stems: ...").
  - Song folder: <Songs folder>/<slug>/ with song.<ext> (your file, byte-for-byte), notes.chart,
    song.ini. Default Songs folder: %APPDATA%\Godot\app_userdata\UNDERTOW\songs (user://songs);
    -SongsRoot <folder> picks another one. The slug is the name lowercased, every run of other
    characters -> "_", at most 40 characters (so "..\..\x" becomes "x").
  - Chart stats: build/autochart/user_<slug>/user_<slug>.chart_stats.json (never tools/autochart/reports).
  - The tool never writes outside the Songs folder, and never replaces an existing song folder
    unless you pass -Force. Errors print AUTOCHART_ERROR <stage>: <message> and exit 2.
  - The song.ini delay comes from the tempo map: the soundfile decode matches Godot's MP3/WAV decode
    within 0.05 ms, so no align run is needed for player songs.
  - Re-running with the same name reuses the stems only when the source file is the same (SHA-256).
Then in the game: Settings > LIBRARY > Rescan (or restart). Last line on success: EXTRACT_OK <folder>.

Generated charts are written as 4-lane `N 0..3`; the importer maps gems 0..3 to lanes 0..3
(identity), no 5->4 folding is involved (SPEC req 9). A generated folder is an ordinary library song:
tests/test_generated_song_library.gd copies a bundled song into a Songs folder and checks status ok,
the same fingerprints and the identity mapping.

LANE RULE
---------
From tools/autochart/stages/lanes.py (module docstring):
Contour rule (Clone Hero convention, "going right feels like going up"):
  * pitch per note = the note's "pitch" (Basic Pitch skyline, MIDI), else the spectral centroid as
    round(12 * log2(centroid / 440) + 69), else unpitched;
  * same pitch -> same lane; a step of 1..4 semitones -> +-1 lane; a leap of >= 5 semitones -> +-2 lanes;
  * unpitched notes repeat the previous lane and do not become the new reference pitch.
Octave compromise (SPEC req 5 / RESEARCH Pitfall 6): Basic Pitch makes many exact-octave errors, while
SPEC req 4 says "octave leap -> +-2 lanes". So:
  * an interval larger than an octave is reduced: d = sign(d) * (|d| mod 12), and a remainder of 0
    (two or more octaves) counts as an exact octave;
  * an exact octave FOLDS to 0 (same lane) when it alternates (the next pitch returns to the previous
    one), when the previous interval was also an exact octave, or when either note's amplitude is
    below 0.3 (low Basic Pitch confidence);
  * otherwise an isolated octave is a real leap and stays +-12, i.e. +-2 lanes (literal SPEC rule);
  * there is no full pitch-class fold: folding a fifth (7) to -5 would flip its direction.
VISIBLE SLIDE: a step whose target lane would leave 0..3 is a clamped step; the lane stays on the edge
and a counter for that direction increments. After 2 clamped steps in the same direction, the next
step that way re-centres: lane 1 (rising) or lane 2 (falling), and the counter resets. A step in the
opposite direction resets the counter; repeats and unpitched notes leave it alone.
Example: rising scale C4 D4 E4 F4 G4 A4 B4 C5 from lane 0 -> 0,1,2,3,3,3,1,2 (falling mirror from
lane 3 -> 3,2,1,0,0,0,2,1).
Accent chords: Expert / Hard notes with strength >= the 90th percentile get an adjacent second lane.
Sustains: a ring longer than 1 beat becomes a sustain ending 1/16 before the next note.

UAT FLAGS
---------
Band flags from reports/<id>.chart_stats.json: a keep_share or lane-step share outside its Neversoft
band +- 0.05 (bands: keep hard 0.90-1.00, medium 0.65-0.75, easy 0.45-0.55; steps repeat 0.20-0.30,
+-1 0.40-0.60, +-2 0.15-0.30, +-3+ 0.00-0.05). Reported for the ear check, never fixed by padding notes.
  song          difficulty  metric  value  band
  sea_shanty_2  easy        repeat  0.389  0.20-0.30   (Easy re-contours on 3 lanes; the tune repeats notes)
  hrt           easy        keep    0.386  0.45-0.55
  hrt           easy        step2   0.362  0.15-0.30
  hrt           medium      keep    0.578  0.65-0.75
  hrt           medium      step1   0.324  0.40-0.60
  hrt           hard        step2   0.393  0.15-0.30
  hrt           expert      step2   0.393  0.15-0.30
  invisible     easy        keep    0.315  0.45-0.55
  invisible     easy        step1   0.328  0.40-0.60
  invisible     medium      keep    0.398  0.65-0.75
Other UAT notes for sea_shanty_2: kept at 200 BPM (RESEARCH open question 2: do the beat lines look too
dense?); section names are generic (Intro, Section 2, Chorus 1, Chorus 2, Section 5, Outro) and the
boundaries are not ear-checked; the vocals stem is near-silent, so its relative gate marks every bar
vocal-active and the solo falls back to the densest 4-8 bar window (bars 94-99).
hrt: GATE PASS, no PASS_BASELINE and no fallback used. The drums fill added nothing (fill_share 0.0),
so the chart is the "other" synth line only. The RESEARCH drums-only fallback (98.9% mix, centroid
lanes) stays available if the ear check says "other" is inaudible. Preview starts at 22322 ms
(Chorus 1; moved from 2789 ms by the plan-08 pick_preview fix); sections are generic and not ear-checked.
The tick-0 chord plays at -4 ms (inside the game's preroll).
invisible: GATE PASS at 80.5% mix (chance 24.1%), only 0.5 points over the 80% line, at target 2.8
(the plan's attempt (c) target 2.5 went below the 2 n/s Expert floor). Ear-check the verse density:
Medium keeps only 40% of Expert and Easy 32% (band flags above).
synth_wave_april (re-charted in plan 02.1-07, stem "other" picked by tools/autochart/stem_rank.py):
GATE PASS, mix 89.7% (chance 9.8%), stem 100.0% (chance 33.1%), median +0.3 ms, delay 58; no
PASS_BASELINE and no fallback. Band flags: none. Sections are generic (Intro, Chorus 1, Section 3,
Chorus 2, Chorus 3, Outro); the "Outro" starts 6 ms before the end of the audio. Not ear-checked.
space_synth_wave (re-charted in plan 02.1-07, stem "other" picked by stem_rank.py): GATE PASS, mix
95.6% (chance 22.0%), stem 100.0% (chance 27.5%), median +0.0 ms, delay 164; no PASS_BASELINE and no
fallback. beat_this needed 57 beat repairs (tempo gate still 2.0 / 2.0 ms). Band flags:
  space_synth_wave  easy        keep    0.381  0.45-0.55
  space_synth_wave  medium      keep    0.575  0.65-0.75
  space_synth_wave  medium      step1   0.307  0.40-0.60
  space_synth_wave  hard        step1   0.293  0.40-0.60
  space_synth_wave  hard        step2   0.405  0.15-0.30
  space_synth_wave  expert      step1   0.293  0.40-0.60
  space_synth_wave  expert      step2   0.405  0.15-0.30
Preview starts at 80440 ms (Chorus 2). Plan 07 shipped 189642 ms (2.4 s before the end); the plan-08
pick_preview fix skips intro (< 10 s) and tail (< 30 s before the end) sections. Check the Song Select
preview in UAT (invisible moved too: 169864 -> 49867 ms).

MODEL HASHES (SHA-256)
----------------------
htdemucs  build/autochart/cache/hub/models--adefossez--HTDemucs/snapshots/cbc8a9b1a87023b7fd74e7b3412e6321c0eab003/955717e8.safetensors
  d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd
beat_this final0  build/autochart/cache/hub/checkpoints/beat_this-final0.ckpt
  8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331
