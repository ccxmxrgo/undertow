"""Stage 3: beats. beat_this (final0, CPU, no DBN) on the mix -> repair (drop IBI < 0.6 P, split IBI ~ k*P)
-> constant-tempo check (linear-fit residual p90 <= 2 ms) -> least-squares line (constant) or local linear
smoothing over +-8 beats -> phase correction to the D3 mix attack starts -> work/beats.json.

Ported from the measured research scripts (build/research/scripts/pipeline_eval.py repair_beats /
smooth_beats, grid_phase.py corrected); 02.1-RESEARCH.md "Chosen Pipeline" step 3, Pattern 4,
Pitfall 2 (beat_this sits on 20 ms frames, 7-12 ms late) and Pitfall 3 (a local correction makes a
constant song wobble, so constant songs get one global shift). Runs in venv A.

beats.json contract: {"beats", "downbeats", "beats_raw", "downbeats_raw", "constant_tempo", "bpm",
"phase_shift_ms", "repairs"} (+ "resid_p90_ms", "mix_onsets_used" for inspection).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

SR = 44100
PRE = 4  # beats extrapolated on each side of the grid for residuals


def run_beat_this(mono: np.ndarray, sr: int):
    from beat_this.inference import Audio2Beats
    a2b = Audio2Beats(checkpoint_path="final0", device="cpu", dbn=False)
    beats, downs = a2b(np.asarray(mono, dtype=np.float32), sr)
    return np.asarray(beats, dtype=np.float64), np.asarray(downs, dtype=np.float64)


def repair_beats(beats):
    """Drop spurious half beats (IBI < 0.6 P) and fill missed beats (IBI ~ k*P split into k equal parts).
    Returns (beats, repairs) with repairs = dropped + inserted."""
    b = np.asarray(beats, dtype=np.float64)
    if len(b) < 3:
        return b.copy(), 0
    p = float(np.median(np.diff(b)))
    out = [float(b[0])]
    repairs = 0
    for t in b[1:]:
        gap = t - out[-1]
        if gap < 0.6 * p:
            repairs += 1
            continue
        k = max(1, int(round(gap / p)))
        base = out[-1]
        for j in range(1, k):
            out.append(base + gap * j / k)
            repairs += 1
        out.append(float(t))
    return np.array(out), repairs


def fit_residual_p90_ms(beats) -> float:
    b = np.asarray(beats, dtype=np.float64)
    k = np.arange(len(b))
    c = np.polyfit(k, b, 1)
    return float(np.percentile(np.abs(b - (c[0] * k + c[1])), 90) * 1000.0)


def is_constant(beats, p90_ms: float = 2.0) -> bool:
    if len(beats) < 8:
        return False
    return fit_residual_p90_ms(beats) <= p90_ms


def line_fit(beats):
    b = np.asarray(beats, dtype=np.float64)
    k = np.arange(len(b))
    c = np.polyfit(k, b, 1)
    return c[0] * k + c[1]


def smooth_beats(beats, half: int = 8):
    """Local linear fit over +-half beats, evaluated at each beat."""
    b = np.asarray(beats, dtype=np.float64)
    n = len(b)
    out = np.empty(n)
    k = np.arange(n)
    for i in range(n):
        lo, hi = max(0, i - half), min(n, i + half + 1)
        if hi - lo < 2:
            out[i] = b[i]
            continue
        c = np.polyfit(k[lo:hi], b[lo:hi], 1)
        out[i] = c[0] * i + c[1]
    return out


def _residuals(beats, onsets, div: int = 4):
    """Residual of every onset to the nearest 1/div grid point of the piecewise-linear beat map, and its
    position in beat-index units. Onsets outside the (extended) map are dropped."""
    b = np.asarray(beats, dtype=np.float64)
    on = np.asarray(onsets, dtype=np.float64)
    p = float(np.median(np.diff(b)))
    ext = np.concatenate([b[0] - p * np.arange(PRE, 0, -1), b, b[-1] + p * np.arange(1, PRE + 1)])
    idx_axis = np.arange(len(ext), dtype=np.float64)
    keep = (on >= ext[0]) & (on <= ext[-1])
    on = on[keep]
    pos = np.interp(on, ext, idx_axis)
    c = np.round(pos * div) / div
    r = on - np.interp(c, idx_axis, ext)
    return r, pos - PRE


def phase_correct(beats, mix_onsets, constant: bool, win_s: float = 0.03, half: int = 8):
    """Move the beats onto the mix attacks: median residual of attacks within +-win_s of the 1/16 grid.
    constant: one global shift (the line stays a line). Otherwise a local median over +-half beats
    (>= 4 attacks, else no shift), then re-smoothed."""
    b = np.asarray(beats, dtype=np.float64)
    if len(b) < 3 or len(mix_onsets) == 0:
        return b.copy()
    r, pos = _residuals(b, mix_onsets)
    near = np.abs(r) < win_s
    r, pos = r[near], pos[near]
    if constant:
        if len(r) < 4:
            return b.copy()
        return b + float(np.median(r))
    shifts = np.zeros(len(b))
    order = np.argsort(pos)
    pos, r = pos[order], r[order]
    for i in range(len(b)):
        lo = np.searchsorted(pos, i - half, side="left")
        hi = np.searchsorted(pos, i + half, side="right")
        if hi - lo >= 4:
            shifts[i] = float(np.median(r[lo:hi]))
    return smooth_beats(b + shifts, half)


def snap_downbeats(downbeats, beats):
    """Each downbeat moved to the nearest refined beat (duplicates removed, sorted)."""
    b = np.asarray(beats, dtype=np.float64)
    d = np.asarray(downbeats, dtype=np.float64)
    if len(b) == 0 or len(d) == 0:
        return np.array([])
    j = np.clip(np.searchsorted(b, d), 1, len(b) - 1)
    left, right = b[j - 1], b[j]
    nearest = np.where(np.abs(d - left) <= np.abs(right - d), j - 1, j)
    return b[np.unique(nearest)]


def _r(a):
    return [round(float(v), 6) for v in a]


def beats_stage(work: Path) -> dict:
    from stages import d3
    from stages.errors import AutochartError
    wav = work / "decoded.wav"
    if not wav.is_file():
        raise AutochartError("beats", f"{wav} is missing; run the decode stage first")
    mono = d3.load_mono(wav)
    raw_b, raw_d = run_beat_this(mono, SR)
    if len(raw_b) < 16:
        raise AutochartError("beats", f"beat_this found only {len(raw_b)} beats")
    rep, repairs = repair_beats(raw_b)
    p90 = fit_residual_p90_ms(rep)
    constant = p90 <= 2.0
    base = line_fit(rep) if constant else smooth_beats(rep)
    mix_on, _ = d3.onsets_gate(mono, SR, delta=0.1)
    refined = phase_correct(base, mix_on, constant)
    shift_ms = float(np.median(refined - base) * 1000.0)
    downs = snap_downbeats(raw_d, refined)
    bpm = 60.0 / float(np.median(np.diff(refined)))
    info = {"beats": _r(refined), "downbeats": _r(downs), "beats_raw": _r(raw_b), "downbeats_raw": _r(raw_d),
            "constant_tempo": bool(constant), "bpm": round(bpm, 4), "phase_shift_ms": round(shift_ms, 3),
            "repairs": int(repairs), "resid_p90_ms": round(p90, 3), "mix_onsets_used": int(len(mix_on))}
    (work / "beats.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
    return info
