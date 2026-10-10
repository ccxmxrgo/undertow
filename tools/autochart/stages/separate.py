"""Stage 2: htdemucs 4-stem separation of work/decoded.wav (never the MP3, Pitfall 1). Runs demucs as a
child of the venv A interpreter with an argument list (no shell, -I -B, timeout; T-02.1-11) and checks
that the stem sum lines up with decoded.wav within 1 ms. Runs in venv A.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

from stages import d3
from stages.decode import lag_segment
from stages.errors import AutochartError

STEMS = ("drums", "bass", "other", "vocals")
MODEL = "htdemucs"
TIMEOUT_S = 1800
LAG_MAX_MS = 1.0
ROOT = Path(__file__).resolve().parents[3]
CACHE = ROOT / "build" / "autochart" / "cache"


def _env() -> dict:
    env = dict(os.environ)
    env["HF_HOME"] = str(CACHE)
    env["TORCH_HOME"] = str(CACHE)
    env["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
    return env


def stem_lag_ms(work: Path) -> float:
    ref = d3.load_mono(work / "decoded.wav")
    tot = None
    for s in STEMS:
        x = d3.load_mono(work / "stems" / f"{s}.wav")
        tot = x if tot is None else tot[: len(x)] + x[: len(tot)]
    n = min(len(ref), len(tot))
    return float(d3.lag_ms(ref[:n], np.asarray(tot[:n]), d3.SR, seg=lag_segment(n / d3.SR)))


def separate(work: Path, force: bool = False) -> dict:
    stems_dir = work / "stems"
    wav = work / "decoded.wav"
    if not wav.is_file():
        raise AutochartError("separate", f"{wav} is missing; run the decode stage first")
    have = all((stems_dir / f"{s}.wav").is_file() for s in STEMS)
    seconds = None
    if have and not force:
        old = work / "separate.json"
        if old.is_file():
            seconds = json.loads(old.read_text(encoding="utf-8")).get("seconds")
    else:
        out = work / "sep"
        cmd = [sys.executable, "-I", "-B", "-m", "demucs", "-n", MODEL, "-d", "cpu",
               "-o", str(out), str(wav)]
        t0 = time.perf_counter()
        try:
            r = subprocess.run(cmd, env=_env(), timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired as e:
            raise AutochartError("separate", f"demucs took longer than {TIMEOUT_S} s") from e
        seconds = round(time.perf_counter() - t0, 1)
        if r.returncode != 0:
            raise AutochartError("separate", f"demucs failed with exit code {r.returncode}")
        src_dir = out / MODEL / wav.stem
        stems_dir.mkdir(parents=True, exist_ok=True)
        for s in STEMS:
            f = src_dir / f"{s}.wav"
            if not f.is_file():
                raise AutochartError("separate", f"demucs did not write {f}")
            shutil.move(str(f), str(stems_dir / f"{s}.wav"))
        shutil.rmtree(out, ignore_errors=True)
    lag = stem_lag_ms(work)
    if abs(lag) > LAG_MAX_MS:
        raise AutochartError("separate", f"stem sum is {lag:+.2f} ms off decoded.wav (limit 1 ms)")
    info = {"model": MODEL, "seconds": seconds, "lag_ms": round(lag, 3)}
    (work / "separate.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
    return info
