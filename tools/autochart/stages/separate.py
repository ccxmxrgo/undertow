"""Stage 2: htdemucs 4-stem separation of work/decoded.wav (never the MP3, Pitfall 1). Dev mode
(runtime.SEP_MODE "subprocess"): demucs runs as a child of the venv A interpreter with an argument list
(no shell, -I -B, timeout; T-02.1-11). Pack mode ("inprocess", Phase 2.2.2 D-05): demucs.api.Separator
runs inside this process with the CLI defaults and a seeded RNG, so killing the one job process stops all
work. Both check that the stem sum lines up with decoded.wav within 1 ms.
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

from stages import d3, runtime
from stages.decode import lag_segment
from stages.errors import AutochartError

STEMS = ("drums", "bass", "other", "vocals")
MODEL = "htdemucs"
TIMEOUT_S = 1800
LAG_MAX_MS = 1.0


def _env() -> dict:
    """os.environ plus the model paths of the current runtime mode (dev: HF_HOME = TORCH_HOME =
    build/autochart/cache, read at call time from stages/runtime.py)."""
    env = dict(os.environ)
    env.update(runtime.model_env())
    return env


def stem_lag_ms(work: Path) -> float:
    ref = d3.load_mono(work / "decoded.wav")
    tot = None
    for s in STEMS:
        x = d3.load_mono(work / "stems" / f"{s}.wav")
        tot = x if tot is None else tot[: len(x)] + x[: len(tot)]
    n = min(len(ref), len(tot))
    return float(d3.lag_ms(ref[:n], np.asarray(tot[:n]), d3.SR, seg=lag_segment(n / d3.SR)))


def _sep_fraction(d: dict) -> float:
    """demucs callback dict -> 0..1 over all submodels of the bag (segment_offset / audio_length)."""
    try:
        models = max(1, int(d.get("models") or 1))
        length = max(1, int(d.get("audio_length") or 1))
        part = float(d.get("segment_offset") or 0) / length
        idx = int(d.get("model_idx_in_bag") or 0)
        return min(1.0, max(0.0, (idx + min(1.0, part)) / models))
    except (TypeError, ValueError):
        return 0.0


def separate_inprocess(work: Path, threads: int = 0, on_progress=None) -> float:
    """htdemucs in this process (RESEARCH Pattern 3 item 3): the same defaults as the demucs CLI
    (shifts 1, overlap 0.25, split, clip rescale, int16 WAV), fed decoded.wav (never the MP3). The RNG is
    seeded because apply_model draws a random shift (Pitfall 5). Writes work/stems/<stem>.wav and returns
    the seconds taken."""
    import random

    import torch
    from demucs.api import Separator, save_audio

    random.seed(0)
    torch.manual_seed(0)
    if threads and threads > 0:
        torch.set_num_threads(int(threads))

    def cb(d: dict) -> None:
        if on_progress is not None:
            on_progress(_sep_fraction(d))

    t0 = time.perf_counter()
    separator = Separator(model=MODEL, device="cpu", shifts=1, overlap=0.25, split=True, callback=cb)
    # separate_audio_file reads decoded.wav exactly like the CLI does (soundfile wrote it in the decode stage)
    _, res = separator.separate_audio_file(work / "decoded.wav")
    stems_dir = work / "stems"
    stems_dir.mkdir(parents=True, exist_ok=True)
    for s in STEMS:
        if s not in res:
            raise AutochartError("separate", f"htdemucs returned no {s} stem")
        tmp = stems_dir / f"{s}.part.wav"
        save_audio(res[s], str(tmp), samplerate=separator.samplerate, clip="rescale", bits_per_sample=16)
        os.replace(tmp, stems_dir / f"{s}.wav")
    if on_progress is not None:
        on_progress(1.0)
    return round(time.perf_counter() - t0, 1)


def separate(work: Path, force: bool = False, on_progress=None) -> dict:
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
    elif runtime.SEP_MODE == "inprocess":
        seconds = separate_inprocess(work, runtime.THREADS, on_progress)
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
    if runtime.SEP_MODE == "inprocess":
        info["mode"] = "inprocess"
    (work / "separate.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
    return info
