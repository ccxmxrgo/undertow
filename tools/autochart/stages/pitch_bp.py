"""Stage 5: pitch. Basic Pitch (ONNX, venv B, Python 3.10) on each stem through tools/autochart/bp_worker.py,
then every onset record gets the pitch of the Basic Pitch note that best explains it (RESEARCH "Chosen
Pipeline" step 5). Basic Pitch onsets are frame-quantised and early: they are used for pitch only, never
for timing (Pitfall 6 is handled later by the octave-folded contour in lanes.py).

STANDARD LIBRARY ONLY at import time (json, subprocess, pathlib, sys; ctypes on demand): this module runs
under venv A, but its unit tests run under plain `python -I -B`. The worker is called with an argument
list, -I, a fixed interpreter path and a timeout (T-02.1-11).

runtime.BP_MODE (Phase 2.2.2): "subprocess" (dev) runs bp_worker.py under venv B; "inprocess" (merged
pack) runs Basic Pitch in this process with the bp_worker.py parameters (predict_inprocess); "worker"
(two-interpreter pack) runs bp_worker.py under the pack's second interpreter inside a Windows job object
with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, so killing the job process also kills the worker (Pitfall 4).
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


# Basic Pitch parameters as measured in the research (bp_worker.py uses the same values)
BP_PARAMS = {"onset_threshold": 0.5, "frame_threshold": 0.3, "minimum_note_length": 58, "melodia_trick": True}
_MODEL = None


def bp_notes(raw_notes) -> list:
    """Basic Pitch note events -> sorted [[start, end, midi, amp]], rounded exactly like bp_worker.py."""
    return sorted([[round(float(a), 6), round(float(b), 6), int(p), round(float(v), 4)]
                   for a, b, p, v, _ in raw_notes])


def predict_inprocess(stem_wav: Path) -> list:
    """Basic Pitch in this process (merged pack runtime) with the bp_worker.py parameters and rounding.
    The ONNX model is loaded once per process."""
    global _MODEL
    import logging

    logging.disable(logging.WARNING)
    from basic_pitch import ICASSP_2022_MODEL_PATH
    from basic_pitch.inference import Model, predict

    if _MODEL is None:
        _MODEL = Model(ICASSP_2022_MODEL_PATH)
    _, _, notes = predict(str(stem_wav), _MODEL, **BP_PARAMS)
    return bp_notes(notes)


# ---------------------------------------------------------------- Windows job object (worker mode)
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
_JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
# Kept open for the life of this process. When the process ends (normally or by TerminateProcess from the
# game), the kernel closes the handle and kills every process in the job, i.e. the Basic Pitch worker.
_JOB = None


def _kill_on_close_job():
    """The job object with KILL_ON_JOB_CLOSE (created once), or None off Windows or on failure."""
    global _JOB
    if _JOB is not None or sys.platform != "win32":
        return _JOB
    import ctypes
    from ctypes import wintypes

    class IO_COUNTERS(ctypes.Structure):
        _fields_ = [(n, ctypes.c_ulonglong) for n in (
            "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
            "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]

    class BASIC_LIMIT(ctypes.Structure):
        _fields_ = [("PerProcessUserTimeLimit", ctypes.c_longlong), ("PerJobUserTimeLimit", ctypes.c_longlong),
                    ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                    ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                    ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD),
                    ("SchedulingClass", wintypes.DWORD)]

    class EXTENDED_LIMIT(ctypes.Structure):
        _fields_ = [("BasicLimitInformation", BASIC_LIMIT), ("IoInfo", IO_COUNTERS),
                    ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                    ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateJobObjectW.restype = wintypes.HANDLE
    k32.CreateJobObjectW.argtypes = (ctypes.c_void_p, wintypes.LPCWSTR)
    k32.SetInformationJobObject.argtypes = (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD)
    k32.CloseHandle.argtypes = (wintypes.HANDLE,)
    job = k32.CreateJobObjectW(None, None)
    if not job:
        return None
    info = EXTENDED_LIMIT()
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not k32.SetInformationJobObject(job, _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                                       ctypes.byref(info), ctypes.sizeof(info)):
        k32.CloseHandle(job)
        return None
    _JOB = job
    return _JOB


def _assign_to_job(proc) -> bool:
    """Put a started child into the kill-on-close job object (Windows only)."""
    job = _kill_on_close_job()
    if job is None:
        return False
    import ctypes
    from ctypes import wintypes

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.AssignProcessToJobObject.argtypes = (wintypes.HANDLE, wintypes.HANDLE)
    return bool(k32.AssignProcessToJobObject(job, int(proc._handle)))


CREATE_SUSPENDED = 0x00000004


def _resume(proc) -> bool:
    """Resume a child created with CREATE_SUSPENDED (every thread of the process; Windows only)."""
    import ctypes
    from ctypes import wintypes

    ntdll = ctypes.WinDLL("ntdll")
    ntdll.NtResumeProcess.argtypes = (wintypes.HANDLE,)
    ntdll.NtResumeProcess.restype = ctypes.c_long
    return ntdll.NtResumeProcess(int(proc._handle)) == 0


def _run_worker(cmd: list, stem_wav: Path, in_job: bool):
    """(returncode, stdout + stderr) of the bp_worker.py child; a timeout raises AutochartError.
    IN-07: in a job object the worker starts suspended and only runs after it was assigned, so a kill of
    this process can never leave an unassigned (orphaned) worker behind."""
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, creationflags=CREATE_SUSPENDED if in_job else 0)
    if in_job and not (_assign_to_job(p) and _resume(p)):
        p.kill()
        p.communicate()
        raise AutochartError("pitch", "cannot put the Basic Pitch worker into a job object")
    try:
        out, err = p.communicate(timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired as e:
        p.kill()
        p.communicate()
        raise AutochartError("pitch", f"Basic Pitch took longer than {TIMEOUT_S} s on {stem_wav.name}") from e
    return p.returncode, (out or "") + "\n" + (err or "")


def run_bp(stem_wav: Path, out_json: Path) -> None:
    if runtime.BP_MODE == "inprocess":
        notes = predict_inprocess(stem_wav)
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump({"notes": notes}, f)
        return
    # Interpreter and worker are read at call time (dev: build/autochart/venvB + tools/autochart/bp_worker.py).
    venv_b = runtime.VENV_B
    worker = runtime.WORKER
    if not venv_b.is_file():
        raise AutochartError("pitch", f"{venv_b} is missing; run tools/autochart/setup_venv.ps1")
    if runtime.BP_MODE == "worker":
        # pack: no -B (pyc are cached in the player's own LOCALAPPDATA, RESEARCH Pattern 3 item 12)
        cmd = [str(venv_b), "-I", str(worker), str(stem_wav), str(out_json)]
        code, text = _run_worker(cmd, stem_wav, in_job=sys.platform == "win32")
    else:
        cmd = [str(venv_b), "-I", "-B", str(worker), str(stem_wav), str(out_json)]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired as e:
            raise AutochartError("pitch", f"Basic Pitch took longer than {TIMEOUT_S} s on {stem_wav.name}") from e
        code, text = r.returncode, r.stdout + "\n" + r.stderr
    if code != 0 or not out_json.is_file():
        lines = [ln for ln in text.splitlines() if ln.strip()]
        fail = [ln for ln in lines if ln.startswith("BP_FAIL")]
        msg = (fail or lines[-1:] or [f"exit code {code}"])[0]
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
