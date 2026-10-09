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

MODEL HASHES (SHA-256)
----------------------
htdemucs  build/autochart/cache/hub/models--adefossez--HTDemucs/snapshots/cbc8a9b1a87023b7fd74e7b3412e6321c0eab003/955717e8.safetensors
  d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd
beat_this final0  build/autochart/cache/hub/checkpoints/beat_this-final0.ckpt
  8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331
