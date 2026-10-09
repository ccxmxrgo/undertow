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
(filled by plan 02.1-01 task 3)

MODEL HASHES (SHA-256)
----------------------
htdemucs  build/autochart/cache/hub/models--adefossez--HTDemucs/snapshots/cbc8a9b1a87023b7fd74e7b3412e6321c0eab003/955717e8.safetensors
  d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd
beat_this final0  build/autochart/cache/hub/checkpoints/beat_this-final0.ckpt
  8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331
