"""Stage 4: audible note onsets per stem. D3 attack starts on the stem (delta 0.05) -> audible = a D3 mix
attack (delta 0.03) within +-30 ms (RESEARCH Pattern 3) -> loud = the stem's 50 ms RMS from the onset is
above -35 dB re the 95th percentile of its 50 ms RMS (silence gate) -> spectral centroid of the 2048-sample
frame starting at the onset (librosa, used for unpitched lanes). Pitch / amp / off_t are filled by the
pitch stage. Runs in venv A.

Onset record: {"t", "strength", "pitch", "amp", "centroid", "off_t", "src", "audible", "loud"}.
Only records with audible and loud both true go to quantize.build_expert (plan 05).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from stages import d3
from stages.errors import AutochartError

SR = 44100
STEM_DELTA = 0.05
MIX_DELTA = 0.03
AUDIBLE_S = 0.03
RMS_S = 0.05
SILENCE_DB = -35.0
N_FFT = 2048


def _nearest_dist(sorted_ref: np.ndarray, t: np.ndarray) -> np.ndarray:
    if len(sorted_ref) == 0:
        return np.full(len(t), np.inf)
    j = np.searchsorted(sorted_ref, t)
    a = sorted_ref[np.clip(j - 1, 0, len(sorted_ref) - 1)]
    b = sorted_ref[np.clip(j, 0, len(sorted_ref) - 1)]
    return np.minimum(np.abs(a - t), np.abs(b - t))


def _centroids(x: np.ndarray, starts: np.ndarray, sr: int) -> np.ndarray:
    import librosa
    if len(starts) == 0:
        return np.array([])
    xp = np.concatenate([x, np.zeros(N_FFT, dtype=x.dtype)])
    frames = np.stack([xp[s:s + N_FFT] for s in starts], axis=1)
    S = np.abs(np.fft.rfft(frames * np.hanning(N_FFT + 1)[:N_FFT, None], axis=0))
    return librosa.feature.spectral_centroid(S=S, sr=sr, n_fft=N_FFT)[0]


def stem_onsets(stem_wav: Path, mix: np.ndarray, sr: int, src: str, mix_onsets=None) -> list:
    """Onset records for one stem. mix_onsets (D3 delta 0.03 on the mix) may be passed in to reuse it."""
    x = d3.load_mono(stem_wav, sr)
    if mix_onsets is None:
        mix_onsets, _ = d3.onsets_gate(mix, sr, delta=MIX_DELTA)
    mlo = np.sort(np.asarray(mix_onsets, dtype=np.float64))
    on, strength = d3.onsets_gate(x, sr, delta=STEM_DELTA)
    if len(on) == 0:
        return []
    audible = _nearest_dist(mlo, on) <= AUDIBLE_S + 1e-9
    h = int(RMS_S * sr)
    n = len(x) // h
    frame_rms = np.sqrt((x[: n * h].reshape(n, h).astype(np.float64) ** 2).mean(1)) + 1e-12
    ref = float(np.percentile(frame_rms, 95))
    starts = np.clip((on * sr).astype(int), 0, len(x) - 1)
    rms = np.array([np.sqrt(np.mean(x[s:s + h].astype(np.float64) ** 2)) + 1e-12 for s in starts])
    loud = 20 * np.log10(rms / ref) > SILENCE_DB
    cents = _centroids(x, starts, sr)
    out = []
    for i in range(len(on)):
        c = float(cents[i])
        out.append({"t": round(float(on[i]), 6), "strength": round(float(strength[i]), 5),
                    "pitch": None, "amp": None,
                    "centroid": round(c, 1) if np.isfinite(c) and c > 0 else None,
                    "off_t": None, "src": src, "audible": bool(audible[i]), "loud": bool(loud[i])})
    return out


def onsets_stage(work: Path, stems: list) -> dict:
    wav = work / "decoded.wav"
    if not wav.is_file():
        raise AutochartError("onsets", f"{wav} is missing; run the decode stage first")
    mix = d3.load_mono(wav)
    mlo, _ = d3.onsets_gate(mix, SR, delta=MIX_DELTA)
    summary = {}
    for s in stems:
        f = work / "stems" / f"{s}.wav"
        if not f.is_file():
            raise AutochartError("onsets", f"{f} is missing; run the separate stage first")
        recs = stem_onsets(f, mix, SR, s, mix_onsets=mlo)
        al = sum(1 for r in recs if r["audible"] and r["loud"])
        doc = {"stem": s, "count": len(recs), "audible_loud": al, "onsets": recs}
        (work / f"onsets_{s}.json").write_text(json.dumps(doc, indent=0), encoding="utf-8")
        summary[s] = {"count": len(recs), "audible_loud": al}
    return summary
