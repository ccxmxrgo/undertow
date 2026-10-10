"""Fill silent stretches of the primary stem from a second stem (RESEARCH Pitfall 9, SPEC requirement 3).

When the charted stem goes quiet, lowering the audibility filter would chart bleed. Instead the notes of
that stretch come from a fill stem:

  * mode "bars": every run of >= min_bars consecutive bars with ZERO primary onsets takes the fill
    stem's onsets of those bars (HRT: other + drums fill);
  * mode "sections": a section whose primary density (onsets per second) is below 50% of the median
    primary section density takes ALL its notes from the fill stem; the primary notes in it are dropped
    (INVISIBLE: bass in the verses, switched at section boundaries).

Bar / section membership uses the chart tempo map (sec_to_tick, tm["bar_ticks"]), so the switch points
fall on bar lines. Inputs are not mutated; output records are copies sorted by time. Fill records get
src = fill_src (when given) so chart_stats can report the fill share. Stdlib only.
"""
from __future__ import annotations

from bisect import bisect_right

from stages.tempo_map import sec_to_tick, tick_to_sec

SECTION_SPARSE_RATIO = 0.5
MODES = ("bars", "sections")


def _copy(recs: list[dict], src: str = "") -> list[dict]:
    out = []
    for r in recs:
        n = dict(r)
        if src:
            n["src"] = src
        out.append(n)
    return out


def _index(starts: list[int], tick: float) -> int:
    """Index of the interval [starts[i], starts[i+1]) containing tick (clamped to the first / last)."""
    return min(max(bisect_right(starts, tick) - 1, 0), len(starts) - 1)


def _median(xs: list[float]) -> float:
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return 0.0
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def _sorted(recs: list[dict]) -> list[dict]:
    return sorted(recs, key=lambda n: (float(n["t"]), -float(n.get("strength") or 0.0)))


def fill_silent(primary: list[dict], fill: list[dict], tm: dict, mode: str = "bars",
                section_starts_tick: list[int] | None = None, min_bars: int = 1,
                fill_src: str = "") -> list[dict]:
    if mode not in MODES:
        raise ValueError(f"fill mode {mode!r} must be one of {MODES}")
    if mode == "sections" and not section_starts_tick:
        raise ValueError("fill mode 'sections' needs section_starts_tick")
    prim = _copy(primary)
    if not fill:
        return _sorted(prim)
    fil = _copy(fill, fill_src)

    if mode == "bars":
        bars = [int(t) for t in tm["bar_ticks"]]
        if not bars:
            return _sorted(prim)
        used = {_index(bars, sec_to_tick(tm, float(n["t"]))) for n in prim}
        silent = [i not in used for i in range(len(bars))]
        fill_bars: set[int] = set()
        i = 0
        while i < len(bars):
            if silent[i]:
                j = i
                while j < len(bars) and silent[j]:
                    j += 1
                if j - i >= max(1, int(min_bars)):
                    fill_bars.update(range(i, j))
                i = j
            else:
                i += 1
        add = [n for n in fil if _index(bars, sec_to_tick(tm, float(n["t"]))) in fill_bars]
        return _sorted(prim + add)

    # sections
    starts = sorted(int(t) for t in section_starts_tick)
    all_t = [float(n["t"]) for n in prim + fil]
    bar_ticks = [int(t) for t in tm.get("bar_ticks") or []]
    end_tick = max(bar_ticks[-1] if bar_ticks else 0, starts[-1] + 1,
                   int(max(sec_to_tick(tm, t) for t in all_t)) + 1)
    bounds = starts + [end_tick]
    dur = [max(1e-6, tick_to_sec(tm, bounds[k + 1]) - tick_to_sec(tm, bounds[k])) for k in range(len(starts))]
    counts = [0] * len(starts)
    for n in prim:
        counts[_index(starts, sec_to_tick(tm, float(n["t"])))] += 1
    dens = [c / d for c, d in zip(counts, dur)]
    med = _median(dens)
    sparse = {k for k, d in enumerate(dens) if d < SECTION_SPARSE_RATIO * med}
    keep = [n for n in prim if _index(starts, sec_to_tick(tm, float(n["t"]))) not in sparse]
    add = [n for n in fil if _index(starts, sec_to_tick(tm, float(n["t"]))) in sparse]
    return _sorted(keep + add)


def fill_share(notes: list[dict], fill_src: str) -> float:
    """Share of notes whose src is the fill stem."""
    if not notes or not fill_src:
        return 0.0
    return sum(1 for n in notes if n.get("src") == fill_src) / len(notes)
