"""Expert note builder (SPEC requirement 3, D-06, RESEARCH "Chosen Pipeline" step 4). Stdlib only.

Order:
  1. strength-rank to k = round(target_nps * (last.t - first.t)) notes (ties: earlier, then stronger);
  2. sort by time and merge notes closer than 1/16 at the local tempo (resolution / 4 ticks, measured
     with sec_to_tick), keeping the stronger note's time and fields;
  3. snap each note to the nearer (in seconds) of the 1/16 grid (multiples of res/4) and the 1/12
     grid (multiples of res/3), only when the move is <= snap_ms; otherwise the exact rounded tick;
  4. resolve collisions created by snapping (same tick or < 1/16 apart) keeping the stronger;
  5. sliding-window cap: while some window [t, t + 1 s) holds more than cap_per_s notes, drop the
     weakest note of the densest window.
The silence gate and the audibility filter run earlier (onsets stage), not here.

Note record: every onset key passed through, plus tick, t (= tick_to_sec(tm, tick)), t_onset,
snap ("16" | "12" | None), end_tick (from off_t, or None), lanes ([]), len (0).
"""
from __future__ import annotations

try:
    from stages.tempo_map import sec_to_tick, tick_to_sec
except ImportError:  # imported as a sibling module
    from tempo_map import sec_to_tick, tick_to_sec  # type: ignore

_EPS_TICK = 1e-6


def _stronger(a: dict, b: dict) -> dict:
    """The stronger of two notes; ties keep the earlier one (deterministic)."""
    sa, sb = float(a.get("strength") or 0.0), float(b.get("strength") or 0.0)
    if sa != sb:
        return a if sa > sb else b
    return a if a["t_onset"] <= b["t_onset"] else b


def _merge(notes: list[dict], key: str, min_gap: float) -> list[dict]:
    """notes sorted by `key` (ticks); merge neighbours closer than min_gap ticks into the stronger."""
    out: list[dict] = []
    for n in notes:
        if out and n[key] - out[-1][key] < min_gap - _EPS_TICK:
            out[-1] = _stronger(out[-1], n)
        else:
            out.append(n)
    return out


def _snap(tm: dict, t: float, snap_s: float) -> tuple[int, str | None]:
    res = int(tm["resolution"])
    f = sec_to_tick(tm, t)
    best = None
    for name, step in (("16", res / 4.0), ("12", res / 3.0)):
        cand = int(round(round(f / step) * step))
        dist = abs(tick_to_sec(tm, cand) - t)
        if best is None or dist < best[0]:
            best = (dist, cand, name)
    if best[0] <= snap_s + 1e-12:
        return best[1], best[2]
    return int(round(f)), None


def _window_counts(times: list[float], span: float = 1.0) -> tuple[int, int, int]:
    """(max count, start index, end index exclusive) of the densest window [t_i, t_i + span)."""
    best = (0, 0, 0)
    j = 0
    for i in range(len(times)):
        if j < i:
            j = i
        while j < len(times) and times[j] < times[i] + span - 1e-9:
            j += 1
        if j - i > best[0]:
            best = (j - i, i, j)
    return best


def _cap(notes: list[dict], cap: int) -> list[dict]:
    notes = list(notes)
    while notes:
        count, i, j = _window_counts([n["t"] for n in notes])
        if count <= cap:
            break
        # weakest in the window; ties drop the later note
        k = min(range(i, j), key=lambda x: (float(notes[x].get("strength") or 0.0), -notes[x]["t"]))
        del notes[k]
    return notes


def build_expert(onsets: list[dict], tm: dict, target_nps: float, cap_per_s: float = 8.0,
                 snap_ms: float = 15.0) -> list[dict]:
    if not onsets:
        return []
    res = int(tm["resolution"])
    recs = []
    for o in onsets:
        n = dict(o)
        n["t_onset"] = float(o["t"])
        recs.append(n)

    # 1. density target by strength rank
    by_time = sorted(recs, key=lambda n: (n["t_onset"], -float(n.get("strength") or 0.0)))
    span = by_time[-1]["t_onset"] - by_time[0]["t_onset"]
    k = max(1, int(round(float(target_nps) * span)))
    ranked = sorted(recs, key=lambda n: (-float(n.get("strength") or 0.0), n["t_onset"]))[:k]

    # 2. merge below 1/16 at the local tempo
    for n in ranked:
        n["_ft"] = sec_to_tick(tm, n["t_onset"])
    ranked.sort(key=lambda n: (n["_ft"], -float(n.get("strength") or 0.0)))
    merged = _merge(ranked, "_ft", res / 4.0)

    # 3. snap to 1/16 or 1/12 when the move is small enough
    snap_s = float(snap_ms) / 1000.0
    for n in merged:
        n["tick"], n["snap"] = _snap(tm, n["t_onset"], snap_s)
    # 4. collisions from snapping
    merged.sort(key=lambda n: (n["tick"], n["t_onset"]))
    merged = _merge(merged, "tick", res / 4.0)

    out = []
    for n in merged:
        n.pop("_ft", None)
        n["t"] = tick_to_sec(tm, n["tick"])
        off = n.get("off_t")
        n["end_tick"] = int(round(sec_to_tick(tm, float(off)))) if off is not None else None
        n["lanes"] = []
        n["len"] = 0
        out.append(n)

    # 5. sliding 1 s window cap
    return _cap(out, int(cap_per_s))


def notes_per_window_max(notes: list[dict], span: float = 1.0) -> int:
    """Most notes in any window [t, t + span) (span 1 s = the SPEC density cap window)."""
    times = sorted(float(n["t"]) for n in notes)
    return _window_counts(times, span)[0]


def on_grid_share(notes: list[dict]) -> float:
    """Share of notes that were snapped to the 1/16 or 1/12 grid."""
    if not notes:
        return 0.0
    return sum(1 for n in notes if n.get("snap") is not None) / len(notes)
