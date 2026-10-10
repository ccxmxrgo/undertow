"""Song structure: bar features -> section boundaries, labels, energies and vocal activity (D-08,
SPEC requirement 7, RESEARCH Pattern 7). Runs in venv A (numpy, scipy, librosa, soxr).

Ported from build/research/scripts/sections.py. Fixed parameters only, so the same intermediates give
the same sections.json:

  * features: the decoded mix, mono, resampled to 22.05 kHz (soxr HQ); chroma_cqt (12) and MFCC (13,
    divided by 50 like the research) at hop 512, averaged per bar (bar lines = tm["bar_ticks"] through
    tempo_map.tick_to_sec, the chart's own times);
  * boundaries: librosa.segment.agglomerative(F, k) with k = max(2, round(duration_s / 20)), so they
    sit on bar lines by construction;
  * labels: scipy hierarchical clustering of the per-segment mean features, average linkage, cosine
    distance, cut into k = max(2, round(n_segments / 2)) clusters (fcluster "maxclust"; chosen over a
    fixed 0.35 distance threshold because the threshold gave one label for the whole of Sea Shanty 2
    in testing, which names nothing); labels are renumbered in order of first appearance;
  * energies: mean RMS (hop 512) of the mix per segment;
  * vocal_active per bar: the vocals stem's 50 ms RMS is above -30 dB re its own 95th percentile for
    more than half of the bar's 50 ms frames;
  * names: structure.name_sections(labels, energies).

Output build/autochart/<id>/sections.json:
  {bar_ticks, starts_tick, starts_ms, labels, energies, names, vocal_active, k, params}
starts_ms are song times in ms (delay included), i.e. what song.ini preview_start_time uses.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from stages import d3, structure
from stages.errors import AutochartError
from stages.tempo_map import tick_to_sec

FEAT_SR = 22050
HOP = 512
SECTION_S = 20.0
VOCAL_DB = -30.0
VOCAL_RMS_S = 0.05


def _resample(x: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    if sr_in == sr_out:
        return x
    import soxr
    return soxr.resample(x, sr_in, sr_out, quality="HQ").astype(np.float32)


def _vocal_active(vocals: np.ndarray, sr: int, bar_times: list[float]) -> list[bool]:
    w = int(round(VOCAL_RMS_S * sr))
    n = len(vocals) // w
    if n == 0:
        return [False] * max(len(bar_times) - 1, 0)
    frames = vocals[: n * w].astype(np.float64).reshape(n, w)
    rms = np.sqrt(np.mean(frames * frames, axis=1))
    ref = float(np.percentile(rms, 95))
    if ref <= 0.0:
        return [False] * max(len(bar_times) - 1, 0)
    on = rms > ref * (10.0 ** (VOCAL_DB / 20.0))
    out = []
    for a, b in zip(bar_times, bar_times[1:]):
        i0 = int(a / VOCAL_RMS_S)
        i1 = max(i0 + 1, int(b / VOCAL_RMS_S))
        seg = on[i0:min(i1, n)]
        out.append(bool(len(seg) and np.count_nonzero(seg) * 2 > len(seg)))
    return out


def _renumber(raw) -> list[int]:
    seen: dict[int, int] = {}
    out = []
    for v in raw:
        v = int(v)
        if v not in seen:
            seen[v] = len(seen)
        out.append(seen[v])
    return out


def sections_stage(work: Path, tm: dict) -> dict:
    import librosa
    from scipy.cluster.hierarchy import fcluster, linkage

    work = Path(work)
    dec = work / "decoded.wav"
    if not dec.is_file():
        raise AutochartError("sections", f"{dec} is missing; run analyze first")
    mix44 = d3.load_mono(dec)
    duration = len(mix44) / d3.SR
    y = _resample(mix44, d3.SR, FEAT_SR)

    bar_ticks = [int(t) for t in tm["bar_ticks"]]
    bar_times = [tick_to_sec(tm, t) for t in bar_ticks]
    # bars that start inside the audio; the last bar line closes the last bar
    keep = [i for i, t in enumerate(bar_times) if t < duration]
    if len(keep) < 3:
        raise AutochartError("sections", f"only {len(keep)} bar lines inside the audio")
    bar_ticks = [bar_ticks[i] for i in keep]
    bar_times = [bar_times[i] for i in keep]
    edges = bar_times + [duration] if bar_times[-1] < duration - 1e-6 else bar_times
    n_bars = len(edges) - 1

    C = librosa.feature.chroma_cqt(y=y, sr=FEAT_SR, hop_length=HOP)
    M = librosa.feature.mfcc(y=y, sr=FEAT_SR, hop_length=HOP, n_mfcc=13)
    rms = librosa.feature.rms(y=y, hop_length=HOP)[0]
    n_fr = C.shape[1]
    fr = [min(int(f), n_fr - 1) for f in librosa.time_to_frames(np.array(edges), sr=FEAT_SR, hop_length=HOP)]
    idx = [slice(fr[i], max(fr[i] + 1, fr[i + 1])) for i in range(n_bars)]
    F = np.vstack([librosa.util.sync(C, idx, pad=False), librosa.util.sync(M, idx, pad=False) / 50.0])

    k = max(2, int(round(duration / SECTION_S)))
    k = min(k, n_bars)
    bounds = sorted({int(b) for b in librosa.segment.agglomerative(F, k)} | {0})
    seg_bars = list(zip(bounds, bounds[1:] + [n_bars]))

    means = np.array([F[:, a:b].mean(axis=1) for a, b in seg_bars])
    if len(seg_bars) >= 2:
        kl = max(2, int(round(len(seg_bars) / 2)))
        Z = linkage(means, method="average", metric="cosine")
        labels = _renumber(fcluster(Z, t=kl, criterion="maxclust"))
    else:
        labels = [0]

    energies = []
    for a, b in seg_bars:
        r0, r1 = fr[a], max(fr[a] + 1, fr[b])
        energies.append(round(float(np.mean(rms[r0:r1])), 6))
    names = structure.name_sections(labels, energies)

    vocals_p = work / "stems" / "vocals.wav"
    vocal_active = (_vocal_active(d3.load_mono(vocals_p), d3.SR, edges) if vocals_p.is_file()
                    else [False] * n_bars)

    starts_tick = [bar_ticks[a] for a, _ in seg_bars]
    starts_ms = [int(round(tick_to_sec(tm, t) * 1000.0)) for t in starts_tick]
    out = {
        "bar_ticks": bar_ticks,
        "starts_tick": starts_tick,
        "starts_ms": starts_ms,
        "labels": labels,
        "energies": energies,
        "names": names,
        "vocal_active": vocal_active,
        "k": k,
        "params": {"feat_sr": FEAT_SR, "hop": HOP, "section_s": SECTION_S, "label_clusters": "round(n/2)",
                   "linkage": "average/cosine", "vocal_db": VOCAL_DB},
    }
    (work / "sections.json").write_text(json.dumps(out, indent=1), encoding="utf-8", newline="\n")
    return out
