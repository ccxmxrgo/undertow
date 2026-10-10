"""Stem ranking for the autochart pipeline (Phase 2.1, STEM-07). Runs in venv A:

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/stem_rank.py build/autochart/<id>

Ported from build/research/scripts/stem_pick.py (RESEARCH "Per-song recommendation", A6). Uses only the
analyze intermediates in <work_dir> (beats.json, decoded.wav, onsets_<stem>.json, stems/<stem>.wav) and the
stage modules read-only. For each stem in other, drums, bass, vocals:

  audible + loud onsets -> quantize.build_expert(target_nps 3.0) on the beats.json tempo map, then
    on_grid    share of Expert notes snapped to the 1/16 or 1/12 grid (quantize.on_grid_share)
    mix        % of Expert notes within +-25 ms of a D3 (delta 0.1) onset of decoded.wav
    chance     the same with each note shifted by a random +-60..200 ms (random.Random(0), mean of 20)
    pitched    share of Expert notes with a Basic Pitch pitch
    nps        Expert notes per second over the decoded length
    energy     the stem's share of the summed energy of the four stems

Recommendation: the highest mix % among stems with pitched >= 0.3 and nps >= 1.5 (melodic stems first,
SPEC req 3 "lead melody"); if none qualifies, the highest mix % overall. Ties: the order above.
Writes <work_dir>/stem_rank.json and prints a table; last line `RANK_OK <stem>` (exit 0).
Errors: `AUTOCHART_ERROR stem_rank: <message>` on stderr, exit 2.
"""
from __future__ import annotations

import json
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # python -I does not put the script directory on sys.path

import numpy as np  # noqa: E402

from stages import d3, quantize  # noqa: E402
from stages.errors import AutochartError  # noqa: E402
from stages.tempo_map import build_tempo_map  # noqa: E402

STEMS = ["other", "drums", "bass", "vocals"]
TARGET_NPS = 3.0
WIN = 0.025
CHANCE_REPS = 20
CHANCE_LO, CHANCE_HI = 0.060, 0.200
MIN_PITCHED = 0.3
MIN_NPS = 1.5


def _pct_within(notes: np.ndarray, ons: np.ndarray) -> float:
    if len(notes) == 0 or len(ons) == 0:
        return 0.0
    j = np.searchsorted(ons, notes)
    a = ons[np.clip(j - 1, 0, len(ons) - 1)]
    b = ons[np.clip(j, 0, len(ons) - 1)]
    d = np.minimum(np.abs(a - notes), np.abs(b - notes))
    return float(100.0 * np.mean(d <= WIN + 1e-9))


def _chance(notes: np.ndarray, ons: np.ndarray) -> float:
    rng = random.Random(0)
    vals = []
    for _ in range(CHANCE_REPS):
        sh = np.array([rng.uniform(CHANCE_LO, CHANCE_HI) * (1 if rng.random() < 0.5 else -1) for _ in notes])
        vals.append(_pct_within(notes + sh, ons))
    return float(np.mean(vals))


def _load(path: Path):
    if not path.is_file():
        raise AutochartError("stem_rank", f"missing {path} (run autochart.py analyze first)")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def rank(work: Path) -> dict:
    beats = _load(work / "beats.json")
    tm = build_tempo_map(beats["beats"], beats["downbeats"], bool(beats["constant_tempo"]))
    mix = d3.load_mono(work / "decoded.wav")
    dur = len(mix) / d3.SR
    mon, _ = d3.onsets_gate(mix, delta=0.1)
    mon = np.sort(mon)

    energies = {}
    for st in STEMS:
        x = d3.load_mono(work / "stems" / f"{st}.wav")
        energies[st] = float(np.sum(x.astype(np.float64) ** 2))
    e_tot = sum(energies.values()) or 1.0

    rows = []
    for st in STEMS:
        ons = _load(work / f"onsets_{st}.json")
        recs = [o for o in ons["onsets"] if o.get("audible") and o.get("loud")]
        ex = quantize.build_expert(recs, tm, TARGET_NPS) if recs else []
        t = np.array(sorted(float(n["t"]) for n in ex), dtype=np.float64)
        rows.append({
            "stem": st,
            "audible_loud": len(recs),
            "expert_notes": len(ex),
            "notes_per_s": round(len(ex) / dur, 4) if dur > 0 else 0.0,
            "on_grid_share": round(quantize.on_grid_share(ex), 4),
            "mix_pct": round(_pct_within(t, mon), 2),
            "mix_chance_pct": round(_chance(t, mon), 2),
            "pitched_share": round(sum(1 for n in ex if n.get("pitch") is not None) / len(ex), 4) if ex else 0.0,
            "energy_share": round(energies[st] / e_tot, 4),
        })

    def qualifies(r):
        return r["pitched_share"] >= MIN_PITCHED and r["notes_per_s"] >= MIN_NPS

    pool = [r for r in rows if qualifies(r)]
    rule = "melodic (pitched >= 0.3, n/s >= 1.5): highest mix %"
    if not pool:
        pool = [r for r in rows if r["expert_notes"] > 0]
        rule = "no melodic stem qualifies: highest mix % overall"
    if not pool:
        raise AutochartError("stem_rank", "no stem produced Expert notes")
    best = max(pool, key=lambda r: (r["mix_pct"], -STEMS.index(r["stem"])))
    ordered = sorted(rows, key=lambda r: (-(qualifies(r)), -r["mix_pct"], STEMS.index(r["stem"])))
    return {"id": work.name, "target_nps": TARGET_NPS, "duration_s": round(dur, 3),
            "mix_onsets": int(len(mon)), "rule": rule, "recommended": best["stem"],
            "ranking": [r["stem"] for r in ordered], "stems": rows}


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    try:
        if len(argv) != 1:
            raise AutochartError("stem_rank", "usage: stem_rank.py <work_dir>")
        work = Path(argv[0]).resolve()
        if not work.is_dir():
            raise AutochartError("stem_rank", f"{work} is not a directory")
        res = rank(work)
    except AutochartError as e:
        print(f"AUTOCHART_ERROR {e}", file=sys.stderr)
        return 2
    print(f"stem ranking {res['id']} (Expert target {TARGET_NPS} n/s, {res['duration_s']:.1f} s, "
          f"{res['mix_onsets']} mix onsets)")
    print(f"  {'stem':7s} {'notes':>5s} {'n/s':>5s} {'on-grid':>7s} {'mix %':>6s} {'chance':>6s} "
          f"{'pitched':>7s} {'energy':>6s}")
    for r in res["stems"]:
        print(f"  {r['stem']:7s} {r['expert_notes']:5d} {r['notes_per_s']:5.2f} {100*r['on_grid_share']:6.1f}% "
              f"{r['mix_pct']:5.1f}% {r['mix_chance_pct']:5.1f}% {100*r['pitched_share']:6.1f}% "
              f"{100*r['energy_share']:5.1f}%")
    print(f"  rule: {res['rule']}; ranking {', '.join(res['ranking'])}")
    with open(work / "stem_rank.json", "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(res, indent=2) + "\n")
    print(f"RANK_OK {res['recommended']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
