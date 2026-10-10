"""Stage 1: decode the source audio with soundfile (libsndfile / mpg123), the decoder that matches Godot's
AudioStreamMP3 within 0.05 ms (02.1-RESEARCH.md "Decoder offsets", Pitfall 1). demucs is later fed this
WAV, never the MP3 (its own MP3 reader lands +25.01 ms late). Runs in venv A.

Untrusted input guard (T-02.1-10): suffix whitelist, size <= 200 MB, sample rate 44.1 / 48 kHz only,
length 5 .. 1200 s. Every failure is an AutochartError("decode", ...).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

from stages import d3
from stages.errors import AutochartError

SR = 44100
SUFFIXES = {".mp3", ".ogg", ".wav", ".flac"}
MAX_BYTES = 200 * 1024 * 1024
MIN_S, MAX_S = 5.0, 1200.0
LAG_MAX_MS = 1.0


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def decode(src: Path, work: Path) -> dict:
    src = Path(src)
    if not src.is_file():
        raise AutochartError("decode", f"source file not found: {src}")
    if src.suffix.lower() not in SUFFIXES:
        raise AutochartError("decode", f"unsupported file type '{src.suffix}' (allowed: .mp3 .ogg .wav .flac)")
    size = src.stat().st_size
    if size > MAX_BYTES:
        raise AutochartError("decode", f"file is {size / 1e6:.0f} MB, the limit is 200 MB")
    try:
        x, sr = sf.read(str(src), dtype="float32", always_2d=True)
    except Exception as e:  # libsndfile raises LibsndfileError / RuntimeError on bad data
        raise AutochartError("decode", f"cannot decode {src.name}: {e}") from e
    if sr not in (44100, 48000):
        raise AutochartError("decode", f"sample rate {sr} Hz is not supported (44100 or 48000 only)")
    if sr == 48000:
        import soxr
        x = soxr.resample(x, 48000, SR, quality="HQ").astype(np.float32)
    length_s = x.shape[0] / SR
    if not (MIN_S <= length_s <= MAX_S):
        raise AutochartError("decode", f"length {length_s:.1f} s is outside {MIN_S:.0f}..{MAX_S:.0f} s")
    work.mkdir(parents=True, exist_ok=True)
    sf.write(str(work / "decoded.wav"), x, SR, subtype="FLOAT")
    info = {"sr": SR, "length_s": round(length_s, 6), "channels": int(x.shape[1]),
            "source_name": src.name, "source_sha256": _sha256(src)}
    (work / "decode.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
    return info


def lag_segment(length_s: float, maxlag: float = 0.2):
    """The cross-correlation window: 20..50 s like the research, or as much as a short song allows."""
    if length_s >= 50.0 + maxlag + 0.05:
        return (20.0, 50.0)
    return (maxlag, max(maxlag + 1.0, length_s - maxlag - 0.05))


def godot_lag_check(work: Path, godot_wav: Path) -> float:
    """Lag of Godot's own decode (harness align_<id>_decoded.wav, 48 kHz resampled) against decoded.wav.
    Positive = Godot later. Raises when |lag| > 1 ms (Pitfall 1 guard)."""
    ref = d3.load_mono(work / "decoded.wav")
    g = d3.load_mono(godot_wav)
    n = min(len(ref), len(g))
    lag = float(d3.lag_ms(ref[:n], g[:n], SR, seg=lag_segment(n / SR)))
    if abs(lag) > LAG_MAX_MS:
        raise AutochartError("decode", f"Godot decode is {lag:+.2f} ms off decoded.wav (limit 1 ms)")
    return lag
