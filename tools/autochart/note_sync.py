"""Sync gate for one chart (Phase 2.1, SPEC requirement 5, D-09 / D-10). Runs in venv A:

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/note_sync.py \
      songs/<id>/notes.chart songs/<id>/song.ini build/playtest/align_<id>_decoded.wav \
      [--stem <stem.wav> ...] [--beats build/autochart/<id>/beats.json] \
      [--recorded build/playtest/align_<id>_recorded.wav] [--json <out.json>]

Chart note / beat times come from the game itself: dump_chart_times.gd run headless through GODOT_BIN
(ChartParser + ChartImporter.build, song.ini delay included), never from a re-implementation.

Per difficulty (default expert), for every unique note time (a chord counts once):
  error = note time - nearest D3 onset (delta 0.1) in ms; negative = the note comes before the sound.
  median / IQR over plausible matches (|error| <= 50 ms); % of notes within +-25 ms over all notes.
  Chance level = the same % after shifting every note by a random +-U(60, 200) ms
  (random.Random(0), mean of 20 repetitions). Every % is printed with its chance level.
  Mix  = decoded_wav (+ every --extra-mix summed in), resampled to 44.1 kHz.
  Stem = union of the D3 onsets of every --stem (a filled chart is gated against all charted stems).
  Tempo (--beats, keys beats / beats_raw): chart beat times vs nearest refined (and raw) tracker beat.
  Live (--recorded): cross-correlation lag of the live recording vs the decoded stream, first 20 s.
  suggested_delay_ms = ini delay - round(median_mix).

Verdict: PASS (SPEC fixed numbers), PASS_BASELINE (at least as tight as the Neversoft professional
baseline, SPEC req 5, flagged in UAT) or FAIL. Exit 0 for PASS / PASS_BASELINE, 1 for FAIL.
--notes-json <file>: a JSON list of note times in seconds (reference charts such as the Neversoft
.mid via mid_notes.py); the Godot dump is skipped, chart / ini become optional ('-' placeholders).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))  # python -I does not put the script directory on sys.path

os.environ.setdefault("HF_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("TORCH_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np  # noqa: E402

from stages import d3  # noqa: E402

TMP = ROOT / "build" / "autochart" / "tmp"
DUMP_SCRIPT = "res://tools/autochart/dump_chart_times.gd"
WIN = 0.025          # +-25 ms
MATCH = 0.050        # median / IQR over |error| <= 50 ms (plausible matches)
DELTA = 0.1          # D3 detector delta for the gate (RESEARCH Pitfall 5)
CHANCE_REPS = 20
CHANCE_LO, CHANCE_HI = 0.060, 0.200

FIXED = {"median_mix_abs_ms": 5.0, "stem_pct": 90.0, "mix_pct": 80.0,
         "tempo_median_ms": 10.0, "tempo_p90_ms": 20.0, "live_lag_abs_ms": 3.0}
BASELINE = {"median_mix_abs_ms": 5.9, "stem_pct": 54.5, "mix_pct": 73.5, "mix_chance_max_pct": 45.0,
            "tempo_median_ms": 10.0, "tempo_p90_ms": 20.0, "live_lag_abs_ms": 3.0}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def ini_delay(path: Path) -> int:
    """Same rules as SongIni.get_int(ini, "delay", 0): [song] section, strict int, else 0."""
    in_song = True
    for raw in path.read_text(encoding="utf-8", errors="replace").lstrip("﻿").split("\n"):
        line = raw.strip()
        if not line or line.startswith((";", "#")):
            continue
        if line.startswith("["):
            in_song = line.lower() == "[song]"
            continue
        if in_song and "=" in line:
            k, v = line.split("=", 1)
            if k.strip().lower() == "delay":
                v = v.strip()
                try:
                    return int(v) if 0 < len(v) <= 12 else 0
                except ValueError:
                    return 0
    return 0


def godot_dump(godot: str, chart: Path, ini: Path, difficulty: str) -> dict:
    TMP.mkdir(parents=True, exist_ok=True)
    out = TMP / f"dump_{chart.parent.name}_{difficulty}.json"
    if out.exists():
        out.unlink()
    cmd = [godot, "--headless", "--path", str(ROOT), "--script", DUMP_SCRIPT, "--",
           str(chart), str(ini), difficulty, str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180, encoding="utf-8", errors="replace")
    if "DUMP_OK" not in r.stdout or not out.exists():
        lines = [ln for ln in (r.stdout + r.stderr).splitlines() if "DUMP_" in ln or "ERROR" in ln]
        raise SystemExit(f"dump_chart_times.gd failed (exit {r.returncode}): {' | '.join(lines[-5:])}")
    return json.loads(out.read_text(encoding="utf-8"))


def errors(notes: np.ndarray, ons: np.ndarray) -> np.ndarray:
    """Signed error note - nearest onset (seconds)."""
    ons = np.sort(ons)
    j = np.searchsorted(ons, notes)
    a = ons[np.clip(j - 1, 0, len(ons) - 1)]
    b = ons[np.clip(j, 0, len(ons) - 1)]
    nearest = np.where(np.abs(a - notes) <= np.abs(b - notes), a, b)
    return notes - nearest


def pct_within(notes: np.ndarray, ons: np.ndarray) -> float:
    return float(100.0 * np.mean(np.abs(errors(notes, ons)) <= WIN + 1e-9))


def chance_pct(notes: np.ndarray, ons: np.ndarray) -> float:
    rng = random.Random(0)
    vals = []
    for _ in range(CHANCE_REPS):
        sh = np.array([rng.uniform(CHANCE_LO, CHANCE_HI) * (1 if rng.random() < 0.5 else -1) for _ in notes])
        vals.append(pct_within(notes + sh, ons))
    return float(np.mean(vals))


def metric(notes: np.ndarray, ons: np.ndarray) -> dict:
    if len(notes) == 0 or len(ons) == 0:
        return {"n": int(len(notes)), "onsets": int(len(ons)), "median_ms": None, "q25_ms": None,
                "q75_ms": None, "pct": 0.0, "chance_pct": 0.0}
    e = errors(notes, ons)
    m = e[np.abs(e) <= MATCH]
    med = float(1000 * np.median(m)) if len(m) else None
    return {"n": int(len(notes)), "onsets": int(len(ons)),
            "median_ms": med,
            "q25_ms": float(1000 * np.percentile(m, 25)) if len(m) else None,
            "q75_ms": float(1000 * np.percentile(m, 75)) if len(m) else None,
            "median_all_ms": float(1000 * np.median(e)),
            "pct": pct_within(notes, ons), "chance_pct": chance_pct(notes, ons)}


def beat_gate(chart_beats: np.ndarray, ref: np.ndarray) -> dict:
    ref = np.sort(np.asarray(ref, dtype=np.float64))
    if len(ref) < 2:
        return {"n": 0, "median_abs_ms": None, "p90_abs_ms": None}
    cb = chart_beats[(chart_beats >= ref[0] - 0.05) & (chart_beats <= ref[-1] + 0.05)]
    if len(cb) == 0:
        return {"n": 0, "median_abs_ms": None, "p90_abs_ms": None}
    e = np.abs(errors(cb, ref)) * 1000
    return {"n": int(len(cb)), "median_abs_ms": float(np.median(e)), "p90_abs_ms": float(np.percentile(e, 90))}


def fmt_ms(v) -> str:
    return "n/a" if v is None else f"{v:+.1f}"


def versions() -> dict:
    out = {"python": sys.version.split()[0], "numpy": np.__version__}
    for mod in ("librosa", "soundfile", "scipy", "soxr"):
        try:
            out[mod] = __import__(mod).__version__
        except Exception:  # pragma: no cover - informative only
            out[mod] = "?"
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="chart ini decoded_wav (with --notes-json: decoded_wav, or - - decoded_wav)")
    ap.add_argument("--stem", action="append", default=[], help="charted stem wav (repeatable; onsets are unioned)")
    ap.add_argument("--extra-mix", action="append", default=[], help="audio summed into the mix (repeatable)")
    ap.add_argument("--notes-json", help="JSON list of note times (s); skips the Godot dump")
    ap.add_argument("--difficulty", default="expert", choices=["easy", "medium", "hard", "expert"])
    ap.add_argument("--beats", help="beats.json with keys beats (refined) and beats_raw")
    ap.add_argument("--recorded", help="live recording wav (align_<id>_recorded.wav)")
    ap.add_argument("--json", help="write every number to this JSON file")
    ap.add_argument("--godot", default=os.environ.get("GODOT_BIN", ""), help="Godot binary (default env GODOT_BIN)")
    a = ap.parse_args(argv)

    if a.notes_json:
        if len(a.paths) == 1:
            chart_p = ini_p = None
            wav_p = Path(a.paths[0])
        elif len(a.paths) == 3:
            chart_p = None if a.paths[0] == "-" else Path(a.paths[0]).resolve()
            ini_p = None if a.paths[1] == "-" else Path(a.paths[1]).resolve()
            wav_p = Path(a.paths[2])
        else:
            ap.error("with --notes-json give decoded_wav or chart ini decoded_wav")
    else:
        if len(a.paths) != 3:
            ap.error("give chart ini decoded_wav")
        chart_p, ini_p, wav_p = (Path(p).resolve() for p in a.paths)
    wav_p = wav_p.resolve()

    # ---- note / beat times
    chart_beats = None
    if a.notes_json:
        raw = json.loads(Path(a.notes_json).read_text(encoding="utf-8"))
        times = np.array(raw["notes"] if isinstance(raw, dict) else raw, dtype=np.float64)
        if times.ndim > 1:
            times = times[:, 0]
        delay_ms = ini_delay(ini_p) if ini_p else 0
        note_count = int(len(times))
        source = f"notes-json {a.notes_json}"
    else:
        if not a.godot or not Path(a.godot).exists():
            ap.error("Godot not found: set GODOT_BIN or pass --godot")
        dump = godot_dump(a.godot, chart_p, ini_p, a.difficulty)
        times = np.array([n[0] for n in dump["notes"]], dtype=np.float64)
        chart_beats = np.array(dump["beats"], dtype=np.float64)
        delay_ms = int(dump["delay_ms"])
        note_count = int(len(times))
        source = "godot ChartImporter dump"
    notes = np.unique(np.round(times, 6))

    # ---- audio
    import soundfile as sf
    info = sf.info(str(wav_p))
    decoded_length_ms = int(round(info.frames / info.samplerate * 1000))
    mix = d3.load_mono(wav_p)
    for extra in a.extra_mix:
        y = d3.load_mono(extra)
        k = min(len(mix), len(y))
        mix = mix[:k] + y[:k]
    mix_on, _ = d3.onsets_gate(mix, delta=DELTA)
    m_mix = metric(notes, mix_on)

    m_stem = None
    stem_paths = [str(Path(s).resolve()) for s in a.stem]
    if a.stem:
        ons = [d3.onsets_gate(d3.load_mono(s), delta=DELTA)[0] for s in a.stem]
        m_stem = metric(notes, np.sort(np.concatenate(ons)))

    tempo = None
    if a.beats:
        if chart_beats is None:
            ap.error("--beats needs a chart (Godot dump), not --notes-json")
        bj = json.loads(Path(a.beats).read_text(encoding="utf-8"))
        tempo = {"refined": beat_gate(chart_beats, bj.get("beats", [])),
                 "raw": beat_gate(chart_beats, bj.get("beats_raw", []))}

    live_lag = None
    if a.recorded:
        rec = d3.load_mono(a.recorded)
        live_lag = float(d3.lag_ms(mix if not a.extra_mix else d3.load_mono(wav_p), rec,
                                   seg=(1.0, 20.0), maxlag=0.5))

    med_mix = m_mix["median_ms"]
    suggested = int(delay_ms - round(med_mix)) if med_mix is not None else delay_ms

    # ---- verdict
    def checks(th: dict, baseline: bool) -> list:
        bad = []
        if med_mix is None or abs(med_mix) > th["median_mix_abs_ms"]:
            bad.append(f"median_mix {fmt_ms(med_mix)} ms > +-{th['median_mix_abs_ms']}")
        if m_mix["pct"] < th["mix_pct"]:
            bad.append(f"mix {m_mix['pct']:.1f}% < {th['mix_pct']}%")
        if baseline and m_mix["chance_pct"] > th["mix_chance_max_pct"]:
            bad.append(f"mix chance {m_mix['chance_pct']:.1f}% > {th['mix_chance_max_pct']}%")
        if m_stem is not None and m_stem["pct"] < th["stem_pct"]:
            bad.append(f"stem {m_stem['pct']:.1f}% < {th['stem_pct']}%")
        if tempo is not None:
            r = tempo["refined"]
            if r["median_abs_ms"] is None or r["median_abs_ms"] > th["tempo_median_ms"] \
                    or r["p90_abs_ms"] > th["tempo_p90_ms"]:
                bad.append(f"tempo med/p90 {fmt_ms(r['median_abs_ms'])}/{fmt_ms(r['p90_abs_ms'])} ms")
        if live_lag is not None and abs(live_lag) > th["live_lag_abs_ms"]:
            bad.append(f"live lag {live_lag:+.2f} ms > +-{th['live_lag_abs_ms']}")
        return bad

    fixed_bad = checks(FIXED, False)
    base_bad = checks(BASELINE, True)
    if not fixed_bad:
        verdict = "PASS"
    elif not base_bad:
        verdict = "PASS_BASELINE"
    else:
        verdict = "FAIL"

    # ---- report
    def pct_line(label: str, m: dict) -> str:
        return f"{label} within +-25 ms: {m['pct']:.1f}% (chance {m['chance_pct']:.1f}%)"

    dur = max(len(mix) / d3.SR, 1e-9)
    lines = [
        f"NOTE SYNC {a.difficulty}: {chart_p if chart_p else '-'}",
        f"source: {source}",
        f"chart_sha256: {sha256(chart_p) if chart_p else '-'}",
        f"ini_delay_ms: {delay_ms}",
        f"mix: {wav_p}" + "".join(f" + {Path(e).name}" for e in a.extra_mix),
        f"decoded_length_ms: {decoded_length_ms}",
        f"notes: {note_count} (unique times {len(notes)})",
        f"mix onsets: {len(mix_on)} ({len(mix_on) / dur:.1f}/s), D3 delta {DELTA}",
        f"mix median error (note - onset): {fmt_ms(med_mix)} ms, IQR [{fmt_ms(m_mix['q25_ms'])}, {fmt_ms(m_mix['q75_ms'])}] ms",
        pct_line("mix", m_mix),
    ]
    if m_stem is not None:
        lines += [
            f"stems: {', '.join(Path(s).name for s in stem_paths)} (onsets unioned: {m_stem['onsets']})",
            f"stem median error (note - onset): {fmt_ms(m_stem['median_ms'])} ms, IQR [{fmt_ms(m_stem['q25_ms'])}, {fmt_ms(m_stem['q75_ms'])}] ms",
            pct_line("stem", m_stem),
        ]
    else:
        lines.append("stem: not given")
    if tempo is not None:
        for k in ("refined", "raw"):
            t = tempo[k]
            lines.append(f"tempo vs {k} beats: median |e| {fmt_ms(t['median_abs_ms'])} ms, p90 |e| {fmt_ms(t['p90_abs_ms'])} ms (n {t['n']})")
    else:
        lines.append("tempo: not given (--beats)")
    lines.append(f"live lag (recorded vs decoded, first 20 s): {live_lag:+.2f} ms" if live_lag is not None
                 else "live lag: not given (--recorded)")
    lines.append(f"suggested_delay_ms: {suggested}")
    if verdict == "PASS":
        lines.append("GATE PASS")
    elif verdict == "PASS_BASELINE":
        lines.append("fixed-threshold misses: " + "; ".join(fixed_bad))
        lines.append("GATE PASS_BASELINE")
    else:
        lines.append("fixed-threshold misses: " + "; ".join(fixed_bad))
        lines.append("GATE FAIL " + "; ".join(base_bad))
    print("\n".join(lines))

    if a.json:
        out = {
            "verdict": verdict, "difficulty": a.difficulty, "source": source,
            "chart": str(chart_p) if chart_p else None,
            "chart_sha256": sha256(chart_p) if chart_p else None,
            "notes_json": a.notes_json, "notes_json_sha256": sha256(Path(a.notes_json)) if a.notes_json else None,
            "ini_delay_ms": delay_ms, "decoded_wav": str(wav_p), "extra_mix": [str(Path(e).resolve()) for e in a.extra_mix],
            "decoded_length_ms": decoded_length_ms, "note_count": note_count, "unique_note_times": int(len(notes)),
            "mix_onsets": int(len(mix_on)),
            "median_mix_ms": med_mix, "iqr_mix_ms": [m_mix["q25_ms"], m_mix["q75_ms"]],
            "mix_pct": m_mix["pct"], "mix_chance_pct": m_mix["chance_pct"],
            "stems": stem_paths,
            "median_stem_ms": m_stem["median_ms"] if m_stem else None,
            "iqr_stem_ms": [m_stem["q25_ms"], m_stem["q75_ms"]] if m_stem else None,
            "stem_pct": m_stem["pct"] if m_stem else None,
            "stem_chance_pct": m_stem["chance_pct"] if m_stem else None,
            "tempo": tempo, "live_lag_ms": live_lag, "suggested_delay_ms": suggested,
            "fixed_misses": fixed_bad, "baseline_misses": base_bad,
            "thresholds": {"fixed": FIXED, "baseline": BASELINE},
            "detector": {"name": "D3", "delta": DELTA, "hop": 64, "back_ms": 30},
            "error_sign": "note - onset (negative = note before the sound)",
            "versions": versions(),
        }
        Path(a.json).parent.mkdir(parents=True, exist_ok=True)
        Path(a.json).write_text(json.dumps(out, indent=2), encoding="utf-8")
    return 0 if verdict in ("PASS", "PASS_BASELINE") else 1


if __name__ == "__main__":
    sys.exit(main())
