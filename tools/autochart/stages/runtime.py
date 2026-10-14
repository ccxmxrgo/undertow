"""Runtime settings for the autochart pipeline (Phase 2.2.2, RESEARCH Pattern 3 item 1).

The dev commands (analyze / chart / extract) use the defaults below, which equal the constants that
separate.py and pitch_bp.py hard-coded before (D-02: dev behaviour unchanged). The pack's `job` /
`selftest` commands call configure_pack() once, before any stage runs; the stages read these globals
at call time (`runtime.CACHE`, never a copy taken at import).

STANDARD LIBRARY ONLY: imported by stdlib-only modules whose tests run under plain `python -I -B`.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

BP_MODES = ("subprocess", "inprocess", "worker")

_DEV_CACHE = ROOT / "build" / "autochart" / "cache"
_DEV_VENV_B = ROOT / "build" / "autochart" / "venvB" / "Scripts" / "python.exe"
_DEV_WORKER = ROOT / "tools" / "autochart" / "bp_worker.py"

CACHE: Path = _DEV_CACHE          # dev: HF_HOME == TORCH_HOME == CACHE
MODELS: Path | None = None        # pack: <models>/hf and <models>/torch
VENV_B: Path = _DEV_VENV_B        # interpreter for bp_worker.py (dev venvB, or the pack's rt310)
WORKER: Path = _DEV_WORKER
SEP_MODE: str = "subprocess"      # "inprocess" in the pack (no grandchild process)
BP_MODE: str = "subprocess"       # "inprocess" (merged pack) or "worker" (two-interpreter pack)
THREADS: int = 0                  # 0 = library default


def reset_dev() -> None:
    """Restore the dev defaults (tests)."""
    global CACHE, MODELS, VENV_B, WORKER, SEP_MODE, BP_MODE, THREADS
    CACHE = _DEV_CACHE
    MODELS = None
    VENV_B = _DEV_VENV_B
    WORKER = _DEV_WORKER
    SEP_MODE = "subprocess"
    BP_MODE = "subprocess"
    THREADS = 0


def configure_pack(models_root: Path, bp_mode: str, bp_python: Path | None, worker: Path,
                   threads: int) -> None:
    """Switch to pack mode: models from models_root/{hf,torch}, separation in-process, Basic Pitch
    in-process ("inprocess") or through bp_worker.py under bp_python ("worker")."""
    global MODELS, VENV_B, WORKER, SEP_MODE, BP_MODE, THREADS
    if bp_mode not in ("inprocess", "worker"):
        raise ValueError(f"unknown bp_mode {bp_mode!r} (inprocess or worker)")
    if bp_mode == "worker" and bp_python is None:
        raise ValueError("bp_mode 'worker' needs bp_python")
    if not isinstance(threads, int) or isinstance(threads, bool) or threads < 0:
        raise ValueError(f"threads must be an int >= 0, got {threads!r}")
    MODELS = Path(models_root)
    if bp_python is not None:
        VENV_B = Path(bp_python)
    WORKER = Path(worker)
    SEP_MODE = "inprocess"
    BP_MODE = bp_mode
    THREADS = threads


def model_env() -> dict:
    """Environment entries that point demucs (HF hub) and beat_this (torch hub) at the model files."""
    if MODELS is None:
        hf = torch = str(CACHE)
    else:
        hf = str(MODELS / "hf")
        torch = str(MODELS / "torch")
    return {"HF_HOME": hf, "TORCH_HOME": torch, "HF_HUB_DISABLE_SYMLINKS_WARNING": "1"}
