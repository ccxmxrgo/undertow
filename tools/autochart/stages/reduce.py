"""Hard / Medium / Easy as subsets of the Expert ticks (SPEC requirement 6, RESEARCH Pattern 5). Stdlib only.

Every reduced note is a copy of an Expert note with its exact tick, so a reduction never moves a
note off the music. Targets come from the SPEC Neversoft reference table.

Priority (most important first): metric class downbeat (tick in bar_ticks) < beat (tick % res == 0)
< eighth (tick % (res/2) == 0) < other; then strength descending; then phrase start (first note, or
a gap of >= 1 beat before it in Expert) first; then tick. "Drop the lowest priority" removes the
note with the largest key.

  * Hard: all Expert notes; while some window [t, t + 1 s) holds > 7 notes, drop the lowest-priority
    note of the densest (earliest on ties) window. Chords: 3+ lanes become 2 (base lane + nearest);
    Expert chords sorted by strength, the weaker half become single notes.
  * Medium: candidates on the 1/8 grid; drop lowest priority until keep share <= 0.75, then until
    <= 5 notes/s; gaps are >= 1/8 by construction. 2-note chords only on the strongest kept
    downbeats that were chords in Expert, at most floor(3% of kept notes).
  * Easy: candidates on the 1/8 grid (lane-3 notes removed first when easy_lane_map maps them to
    None); greedy accept in priority order with >= 1 beat to every accepted note; then drop lowest
    priority until keep share <= 0.55 and <= 4 notes/s. No chords. Lanes: lanes.contour_lanes on
    the kept notes with 3 lanes, or easy_lane_map[base_lane]. Sustain lengths kept from Expert.

If fewer candidates exist than the lower share band (a 16th-heavy song), all candidates are kept;
the share is reported later, never padded with off-grid notes.
"""
from __future__ import annotations

import bisect
import math

try:
    from stages import lanes
except ImportError:  # imported as a sibling module
    import lanes  # type: ignore

CAPS = {"hard": 7, "medium": 5, "easy": 4}
MAX_SHARE = {"medium": 0.75, "easy": 0.55}


def _base(n: dict) -> int:
    if n.get("base_lane") is not None:
        return int(n["base_lane"])
    return int(n["lanes"][0]) if n.get("lanes") else 0


def _copy(n: dict) -> dict:
    c = dict(n)
    c["lanes"] = list(n.get("lanes") or [_base(n)])
    return c


def _two(n: dict) -> list[int]:
    """Reduce a chord to <= 2 lanes: the base lane plus its nearest other lane."""
    b = _base(n)
    others = sorted((l for l in set(n.get("lanes") or []) if l != b), key=lambda l: (abs(l - b), l))
    return sorted([b, others[0]]) if others else [b]


def _priority_keys(expert: list[dict], tm: dict) -> dict[int, tuple]:
    res = int(tm.get("resolution", 192))
    bars = set(tm.get("bar_ticks") or [])
    keys: dict[int, tuple] = {}
    prev = None
    for n in sorted(expert, key=lambda n: n["tick"]):
        t = n["tick"]
        if t in bars:
            cls = 0
        elif t % res == 0:
            cls = 1
        elif t % (res // 2) == 0:
            cls = 2
        else:
            cls = 3
        phrase = 0 if prev is None or t - prev >= res else 1
        keys[t] = (cls, -float(n.get("strength") or 0.0), phrase, t)
        prev = t
    return keys


def _densest(notes: list[dict]) -> tuple[int, int, int]:
    """(count, i, j) of the densest window [t_i, t_i + 1 s) over notes sorted by t; earliest on ties."""
    best = (0, 0, 0)
    j = 0
    for i, n in enumerate(notes):
        if j < i:
            j = i
        while j < len(notes) and notes[j]["t"] < n["t"] + 1.0 - 1e-9:
            j += 1
        if j - i > best[0]:
            best = (j - i, i, j)
    return best


def _cap_density(notes: list[dict], cap: int, keys: dict[int, tuple]) -> list[dict]:
    """Drop the lowest-priority note of the densest window until <= cap per 1 s (one drop per loop)."""
    notes = sorted(notes, key=lambda n: n["tick"])
    while notes:
        cnt, i, j = _densest(notes)
        if cnt <= cap:
            break
        worst = max(range(i, j), key=lambda k: keys[notes[k]["tick"]])
        del notes[worst]
    return notes


def _cap_share(notes: list[dict], max_keep: int, keys: dict[int, tuple]) -> list[dict]:
    if len(notes) <= max_keep:
        return notes
    best = sorted(notes, key=lambda n: keys[n["tick"]])[:max_keep]
    return sorted(best, key=lambda n: n["tick"])


def keep_share(reduced: list[dict], expert: list[dict]) -> float:
    """Share of distinct Expert ticks kept by a reduction."""
    ex = {n["tick"] for n in expert}
    return len({n["tick"] for n in reduced} & ex) / len(ex) if ex else 0.0


def reduce(expert: list[dict], difficulty: str, tm: dict,
           easy_lane_map: dict | None = None) -> list[dict]:
    """Reduced chart notes (copies, sorted by tick) for "hard", "medium" or "easy"."""
    diff = difficulty.lower()
    if diff not in CAPS:
        raise ValueError(f"unknown difficulty {difficulty!r}")
    res = int(tm.get("resolution", 192))
    keys = _priority_keys(expert, tm)
    total = len(keys)
    ex = sorted((_copy(n) for n in expert), key=lambda n: n["tick"])

    if diff == "hard":
        chords = sorted((n for n in ex if len(set(n["lanes"])) >= 2),
                        key=lambda n: (-float(n.get("strength") or 0.0), n["tick"]))
        strong = {n["tick"] for n in chords[: math.ceil(len(chords) / 2)]}
        for n in ex:
            n["lanes"] = _two(n) if n["tick"] in strong else [_base(n)]
        return _cap_density(ex, CAPS["hard"], keys)

    eighth = res // 2
    cands = [n for n in ex if n["tick"] % eighth == 0]
    max_keep = int(math.floor(MAX_SHARE[diff] * total + 1e-9))

    if diff == "medium":
        kept = _cap_share(cands, max_keep, keys)
        kept = _cap_density(kept, CAPS["medium"], keys)
        bars = set(tm.get("bar_ticks") or [])
        chordable = sorted((n for n in kept if n["tick"] in bars and len(set(n["lanes"])) >= 2),
                           key=lambda n: (-float(n.get("strength") or 0.0), n["tick"]))
        allow = {n["tick"] for n in chordable[: int(math.floor(0.03 * len(kept) + 1e-9))]}
        for n in kept:
            n["lanes"] = _two(n) if n["tick"] in allow else [_base(n)]
        return kept

    # easy
    if easy_lane_map is not None:
        cands = [n for n in cands if easy_lane_map.get(_base(n)) is not None]
    accepted: list[int] = []
    chosen: list[dict] = []
    for n in sorted(cands, key=lambda n: keys[n["tick"]]):
        t = n["tick"]
        k = bisect.bisect_left(accepted, t)
        if k > 0 and t - accepted[k - 1] < res:
            continue
        if k < len(accepted) and accepted[k] - t < res:
            continue
        accepted.insert(k, t)
        chosen.append(n)
    kept = _cap_share(sorted(chosen, key=lambda n: n["tick"]), max_keep, keys)
    kept = _cap_density(kept, CAPS["easy"], keys)
    if easy_lane_map is not None:
        for n in kept:
            n["base_lane"] = int(easy_lane_map[_base(n)])
            n["lanes"] = [n["base_lane"]]
    else:
        for n, lane in zip(kept, lanes.contour_lanes(kept, n_lanes=3, start_lane=1)):
            n["base_lane"] = lane
            n["lanes"] = [lane]
    return kept
