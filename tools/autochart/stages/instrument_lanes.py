"""INSTRUMENT LANES Expert builder (STEM-04, RESEARCH Pattern 8). Stdlib only.

In this mode each lane is one instrument instead of one pitch range. Default lane order, left to right:

    lane 0 = bass, lane 1 = drums, lane 2 = other, lane 3 = vocals

Rationale: the importer and the highway use "going right feels like going up" (lanes.py contour rule).
Bass is the lowest register, so it sits on the left; vocals are usually the highest line, so they sit
on the right. Drums cover the whole spectrum but carry the low-end pulse with the bass, so they sit
next to it, and "other" (guitars, synths, keys) sits between drums and vocals. No contour is applied:
the lane of a note is the index of its stem in lane_order.

Rules (the same snap / density / reduction rules as single-instrument charts, quantize.py):
  1. strength is normalised per stem by that stem's own 95th percentile (stems differ in loudness);
  2. per lane: quantize.build_expert without a density cut merges onsets closer than 1/16 (keeping the
     stronger) and snaps to the 1/16 or 1/12 grid when the move is <= 15 ms;
  3. notes of different stems on the same tick become one chord; 3+ stems on one tick keep the two
     strongest (never 3+ lanes). base_lane is the stronger lane;
  4. notes on different ticks closer than 1/16 (across lanes) merge into the stronger, exactly like
     quantize's collision rule, so the chart never has flams;
  5. strength rank to k = round(target_nps * span) notes (chords count once), then the sliding 1 s
     window cap (cap_per_s);
  6. sustains (SPEC req 4): end_tick - tick > 1 beat -> len = min(end_tick, next tick in the same
     lane) - tick - resolution/4, a length <= resolution/4 becomes a tap; else 0.

easy_lane_map(notes) drops the lane with the fewest gems and shifts the higher lanes down, so the
reduce.reduce(..., "easy", tm, easy_lane_map=...) track uses lanes 0..2 (Easy has 3 lanes).
Deterministic; inputs are never mutated.
"""
from __future__ import annotations

import bisect

try:
    from stages import quantize
    from stages.lanes import _percentile
    from stages.tempo_map import tick_to_sec
except ImportError:  # imported as a sibling module
    import quantize  # type: ignore
    from lanes import _percentile  # type: ignore
    from tempo_map import tick_to_sec  # type: ignore

LANE_ORDER = ("bass", "drums", "other", "vocals")
_NO_CUT = 1.0e9


def _strength(n: dict) -> float:
    return float(n.get("strength") or 0.0)


def _rank_key(n: dict) -> tuple:
    return (-_strength(n), n["t_onset"], n["base_lane"])


def _normalised(onsets: list[dict], stem: str) -> list[dict]:
    p95 = _percentile([_strength(o) for o in onsets], 95.0) if onsets else 1.0
    if not p95 or p95 <= 0.0:
        p95 = 1.0
    out = []
    for o in onsets:
        c = dict(o)
        c["raw_strength"] = _strength(o)
        c["strength"] = _strength(o) / p95
        c["src"] = stem
        out.append(c)
    return out


def instrument_expert(onsets_by_stem: dict, tm: dict, lane_order: tuple = LANE_ORDER,
                      target_nps: float = 3.5, cap_per_s: float = 8.0) -> list[dict]:
    """Expert notes (new dicts, sorted by tick) where the lane is the stem's index in lane_order."""
    res = int(tm["resolution"])
    sixteenth = res // 4

    # 1-2. per lane: normalise, merge below 1/16, snap (no density cut yet)
    per_lane: list[dict] = []
    for lane, stem in enumerate(lane_order):
        recs = _normalised(list(onsets_by_stem.get(stem) or []), stem)
        if not recs:
            continue
        for n in quantize.build_expert(recs, tm, _NO_CUT, cap_per_s=_NO_CUT):
            n["base_lane"] = lane
            n["lanes"] = [lane]
            per_lane.append(n)
    if not per_lane:
        return []

    # 3. same tick -> one chord of the (at most) two strongest lanes
    by_tick: dict[int, list[dict]] = {}
    for n in per_lane:
        by_tick.setdefault(n["tick"], []).append(n)
    grouped: list[dict] = []
    for tick in sorted(by_tick):
        group = sorted(by_tick[tick], key=_rank_key)[:2]
        head = dict(group[0])
        head["lanes"] = sorted({g["base_lane"] for g in group})
        grouped.append(head)

    # 4. distinct ticks closer than 1/16 (across lanes) merge into the stronger
    merged: list[dict] = []
    for n in grouped:
        if merged and n["tick"] - merged[-1]["tick"] < sixteenth:
            if _rank_key(n) < _rank_key(merged[-1]):
                merged[-1] = n
        else:
            merged.append(n)

    # 5. density: strength rank to the target, then the sliding 1 s cap
    span = max(n["t_onset"] for n in merged) - min(n["t_onset"] for n in merged)
    k = max(1, int(round(float(target_nps) * span)))
    kept = sorted(sorted(merged, key=_rank_key)[:k], key=lambda n: n["tick"])
    for n in kept:
        n["t"] = tick_to_sec(tm, n["tick"])
    kept = quantize._cap(kept, int(cap_per_s))

    # 6. sustains, bounded by the next note in the same lane
    next_in_lane: dict[int, list[int]] = {}
    for n in kept:
        for lane in n["lanes"]:
            next_in_lane.setdefault(lane, []).append(n["tick"])
    out = []
    for n in kept:
        ln = 0
        end = n.get("end_tick")
        if end is not None and int(end) - n["tick"] > res:
            stop = int(end)
            for lane in n["lanes"]:
                ticks = next_in_lane[lane]
                j = bisect.bisect_right(ticks, n["tick"])
                if j < len(ticks):
                    stop = min(stop, ticks[j])
            ln = stop - n["tick"] - sixteenth
            if ln <= sixteenth:
                ln = 0
        c = dict(n)
        c["len"] = ln
        out.append(c)
    return out


def easy_lane_map(notes: list[dict]) -> dict:
    """{lane: new lane or None}: the lane with the fewest gems is dropped (ties: the higher lane),
    higher lanes shift down by one, so Easy uses lanes 0..2."""
    counts = {lane: 0 for lane in range(4)}
    for n in notes:
        for lane in set(n.get("lanes") or []):
            if lane in counts:
                counts[lane] += 1
    drop = min(counts, key=lambda lane: (counts[lane], -lane))
    return {lane: (None if lane == drop else (lane if lane < drop else lane - 1)) for lane in range(4)}
