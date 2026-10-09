"""D3 "attack start" onset detector, shared by the sync gate (note_sync.py) and the chart pipeline.

Ported from the Phase 2.1 research (build/research/scripts/lib.py::onsets_gate and offsets.py::lag_ms);
see 02.1-RESEARCH.md "Pattern 2". Runs in venv A (numpy, scipy, soundfile, soxr, librosa).

D3: librosa onset_strength (n_fft 2048, hop 64 = 1.45 ms, lag 1, max_size 3) normalised by its 99th
percentile -> peak_pick (pre/post_max 30 ms, pre_avg 120 ms, post_avg 30 ms, wait 30 ms, delta) ->
each peak moved back to the attack start: where the 1 ms RMS envelope first reaches 50 % of the way
from the preceding minimum (searched within back_ms before the peak) to the local top.
"""
from __future__ import annotations

import numpy as np
import soundfile as sf

SR = 44100


def load_mono(path, sr: int = SR) -> np.ndarray:
    """Mono float32 at `sr` (44.1 kHz). Files at another rate (the windowed harness writes 48 kHz,
    RESEARCH Pitfall 8) are resampled with soxr (linear phase, delay compensated)."""
    x, file_sr = sf.read(str(path), dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if file_sr != sr:
        import soxr
        x = soxr.resample(x, file_sr, sr, quality="HQ").astype(np.float32)
    return np.ascontiguousarray(x)


def onsets_gate(x: np.ndarray, sr: int = SR, delta: float = 0.1, hop: int = 64, back_ms: int = 30):
    """D3 onsets. Returns (times_s, strength) as numpy arrays (strength = normalised flux at the peak)."""
    import librosa
    x = np.asarray(x, dtype=np.float32)
    env = librosa.onset.onset_strength(y=x, sr=sr, hop_length=hop, n_fft=2048, lag=1, max_size=3)
    env = env / (np.percentile(env, 99) + 1e-9)
    w = max(1, int(0.03 * sr / hop))
    pk = librosa.util.peak_pick(env, pre_max=w, post_max=w, pre_avg=w * 4, post_avg=w, delta=delta, wait=w)
    h = sr // 1000
    n = len(x) // h
    e = np.sqrt((x[: n * h].reshape(n, h) ** 2).mean(1))
    out = []
    for p in pk:
        t = int(p * hop / sr * 1000)
        lo = max(t - back_ms, 0)
        hi = min(t + 5, n - 1)
        if hi <= lo + 2:
            out.append(t / 1000.0)
            continue
        seg = e[lo:hi + 1]
        kmin = int(np.argmin(seg[: max(1, t - lo)])) if t > lo else 0
        top = seg[kmin:].max()
        lvl = seg[kmin] + 0.5 * (top - seg[kmin])
        k = kmin + int(np.argmax(seg[kmin:] >= lvl))
        out.append((lo + k) / 1000.0)
    return np.array(out, dtype=np.float64), np.asarray(env[pk], dtype=np.float64)


def lag_ms(ref: np.ndarray, x: np.ndarray, sr: int = SR, seg=(20.0, 50.0), maxlag: float = 0.2) -> float:
    """Cross-correlation lag of x against ref over ref[seg]. Positive = x is LATER than ref (ms),
    with parabolic sub-sample interpolation."""
    from scipy.signal import correlate
    a = ref[int(seg[0] * sr):int(seg[1] * sr)]
    m = int(maxlag * sr)
    b = x[max(int(seg[0] * sr) - m, 0):int(seg[1] * sr) + m]
    if int(seg[0] * sr) - m < 0:
        raise ValueError("seg[0] must be >= maxlag")
    if len(a) == 0 or len(b) < len(a):
        raise ValueError("signals too short for the lag segment")
    c = correlate(b, a, mode="valid", method="fft")
    k = float(np.argmax(c))
    ki = int(k)
    if 0 < ki < len(c) - 1:
        lft, cc, rgt = c[ki - 1], c[ki], c[ki + 1]
        den = lft - 2 * cc + rgt
        if den != 0:
            k = ki + 0.5 * (lft - rgt) / den
    return (k - m) / sr * 1000.0
