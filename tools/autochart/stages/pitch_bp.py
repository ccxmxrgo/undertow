"""Stage 5: pitch. Basic Pitch (ONNX, venv B, Python 3.10) on each stem through tools/autochart/bp_worker.py,
then every onset record gets the pitch of the Basic Pitch note that best explains it (RESEARCH "Chosen
Pipeline" step 5). Basic Pitch onsets are frame-quantised and early: they are used for pitch only, never
for timing (Pitfall 6 is handled later by the octave-folded contour in lanes.py).

STANDARD LIBRARY ONLY (json, subprocess, pathlib, sys): this module runs under venv A, but its unit tests
run under plain `python -I -B`. The worker is called with an argument list, -I -B, a fixed interpreter
path and a timeout (T-02.1-11).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from stages import runtime
from stages.errors import AutochartError

TIMEOUT_S = 600
EPS = 1e-9


def run_bp(stem_wav: Path, out_json: Path) -> None:
    # Interpreter and worker are read at call time (dev: build/autochart/venvB + tools/autochart/bp_worker.py).
    venv_b = runtime.VENV_B
    worker = runtime.WORKER
    if not venv_b.is_file():
        raise AutochartError("pitch", f"{venv_b} is missing; run tools/autochart/setup_venv.ps1")
    cmd = [str(venv_b), "-I", "-B", str(worker), str(stem_wav), str(out_json)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired as e:
        raise AutochartError("pitch", f"Basic Pitch took longer than {TIMEOUT_S} s on {stem_wav.name}") from e
    if r.returncode != 0 or not out_json.is_file():
        lines = [ln for ln in (r.stdout + "\n" + r.stderr).splitlines() if ln.strip()]
        fail = [ln for ln in lines if ln.startswith("BP_FAIL")]
        msg = (fail or lines[-1:] or [f"exit code {r.returncode}"])[0]
        raise AutochartError("pitch", f"Basic Pitch failed on {stem_wav.name}: {msg}")


def pitch_at(t, notes, win=0.05):
    """(pitch, amp, end) of the highest Basic Pitch note starting within +-win of t; otherwise of the highest
    note sounding at t + 30 ms; otherwise (None, None, None). notes: [[start, end, midi, amp], ...]."""
    best = None
    for n in notes:
        if abs(n[0] - t) <= win + EPS and (best is None or n[2] > best[2]):
            best = n
    if best is None:
        probe = t + 0.03
        for n in notes:
            if n[0] <= probe + EPS and n[1] >= probe - EPS and (best is None or n[2] > best[2]):
                best = n
    if best is None:
        return (None, None, None)
    return (best[2], best[3], best[1])


def attach_pitch(onsets, notes):
    """Copies of the onset records with pitch / amp / off_t filled (None where nothing matches); order kept."""
    out = []
    for rec in onsets:
        p, a, e = pitch_at(rec["t"], notes)
        r = dict(rec)
        r["pitch"] = p
        r["amp"] = round(a, 4) if a is not None else None
        r["off_t"] = round(e, 6) if e is not None else None
        out.append(r)
    return out


def pitch_stage(work: Path, stems) -> dict:
    summary = {}
    for s in stems:
        stem_wav = work / "stems" / f"{s}.wav"
        on_json = work / f"onsets_{s}.json"
        if not stem_wav.is_file() or not on_json.is_file():
            raise AutochartError("pitch", f"{stem_wav.name} or {on_json.name} is missing; run separate / onsets first")
        bp_json = work / f"bp_{s}.json"
        run_bp(stem_wav, bp_json)
        notes = json.loads(bp_json.read_text(encoding="utf-8"))["notes"]
        doc = json.loads(on_json.read_text(encoding="utf-8"))
        recs = attach_pitch(doc["onsets"], notes)
        kept = [r for r in recs if r.get("audible") and r.get("loud")]
        share = sum(1 for r in kept if r["pitch"] is not None) / len(kept) if kept else 0.0
        share_all = sum(1 for r in recs if r["pitch"] is not None) / len(recs) if recs else 0.0
        doc["onsets"] = recs
        doc["pitched_share"] = round(share, 4)          # over audible + loud records (the chart candidates)
        doc["pitched_share_all"] = round(share_all, 4)  # over every stem onset
        doc["bp_notes"] = len(notes)
        on_json.write_text(json.dumps(doc, indent=0), encoding="utf-8")
        summary[s] = {"pitched_share": doc["pitched_share"], "bp_notes": len(notes)}
    return summary


if __name__ == "__main__":
    sys.exit("pitch_bp is a library module; use autochart.py analyze")
