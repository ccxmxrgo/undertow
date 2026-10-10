"""UNDERTOW autochart CLI (Phase 2.1). Runs in venv A:

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py analyze \
      --id <id> --src <audio> [--from-stage decode|separate|beats|onsets|pitch] [--godot-wav <wav>] [--force]

analyze: decode -> separate -> beats -> onsets -> pitch. Every stage writes an inspectable JSON / WAV
intermediate under build/autochart/<id>/ (D-02). Progress: `[k/5] <stage> ...` / `[k/5] <stage> done (X.X s)`.
Errors: `AUTOCHART_ERROR <stage>: <message>` on stderr, exit 2. Last line on success: `ANALYZE_OK <id>`.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))  # python -I does not put the script directory on sys.path

os.environ.setdefault("HF_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("TORCH_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

from stages.errors import AutochartError  # noqa: E402

BUILD = (ROOT / "build" / "autochart").resolve()
ID_RE = re.compile(r"^[a-z0-9_]{1,48}$")
STAGES = ["decode", "separate", "beats", "onsets", "pitch"]
WIRED = 2  # stages wired so far (plan 02.1-04 tasks 1-3)
DEFAULT_STEMS = ["other", "drums", "bass", "vocals"]


def work_dir(song_id: str) -> Path:
    if not ID_RE.match(song_id or ""):
        raise AutochartError("args", f"--id '{song_id}' must match ^[a-z0-9_]{{1,48}}$")
    work = (BUILD / song_id).resolve()
    if work.parent != BUILD:
        raise AutochartError("args", f"work dir {work} is outside {BUILD}")
    return work


def _run_stage(name: str, args, work: Path):
    if name == "decode":
        from stages import decode
        if not args.src:
            raise AutochartError("decode", "--src is required for the decode stage")
        info = decode.decode(Path(args.src).resolve(), work)
        msg = f"{info['length_s']:.3f} s, {info['channels']} ch"
        if args.godot_wav:
            lag = decode.godot_lag_check(work, Path(args.godot_wav).resolve())
            msg += f", Godot lag {lag:+.3f} ms"
        return msg
    if name == "separate":
        from stages import separate
        info = separate.separate(work, force=args.force)
        return f"{info['model']}, stem lag {info['lag_ms']:+.3f} ms"
    if name == "beats":
        from stages import beats
        info = beats.beats_stage(work)
        return (f"{info['bpm']:.2f} BPM, constant {info['constant_tempo']}, "
                f"phase {info['phase_shift_ms']:+.1f} ms, repairs {info['repairs']}")
    if name == "onsets":
        from stages import onsets
        info = onsets.onsets_stage(work, args.stems)
        return ", ".join(f"{s} {v['audible_loud']}/{v['count']}" for s, v in info.items())
    if name == "pitch":
        from stages import pitch_bp
        info = pitch_bp.pitch_stage(work, args.stems)
        return ", ".join(f"{s} pitched {v['pitched_share']:.2f}" for s, v in info.items())
    raise AutochartError("args", f"unknown stage {name}")


def cmd_analyze(args) -> int:
    work = work_dir(args.id)
    first = STAGES.index(args.from_stage)
    if first > 0 and not (work / "decode.json").is_file():
        raise AutochartError(args.from_stage, f"{work / 'decode.json'} is missing; start from decode")
    n = len(STAGES)
    for k, name in enumerate(STAGES[first:WIRED], start=first + 1):
        print(f"[{k}/{n}] {name} ...", flush=True)
        t0 = time.perf_counter()
        msg = _run_stage(name, args, work)
        print(f"[{k}/{n}] {name} done ({time.perf_counter() - t0:.1f} s) {msg}", flush=True)
    print(f"ANALYZE_OK {args.id}", flush=True)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="autochart", description="UNDERTOW audio-to-chart tool")
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("analyze", help="decode, separate, beats, onsets, pitch")
    a.add_argument("--id", required=True)
    a.add_argument("--src")
    a.add_argument("--from-stage", choices=STAGES, default="decode")
    a.add_argument("--godot-wav")
    a.add_argument("--force", action="store_true")
    a.add_argument("--stems", nargs="+", default=DEFAULT_STEMS,
                   choices=DEFAULT_STEMS, help="stems for the onsets / pitch stages")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "analyze":
            return cmd_analyze(args)
    except AutochartError as e:
        print(f"AUTOCHART_ERROR {e.stage}: {e.message}", file=sys.stderr, flush=True)
        return 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
