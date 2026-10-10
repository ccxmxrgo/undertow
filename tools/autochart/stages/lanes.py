"""Contour lanes, accent chords and sustains (SPEC requirement 4, RESEARCH "Chosen Pipeline" 5-6). Stdlib only.

Contour rule (Clone Hero convention, "going right feels like going up"):
  * pitch per note = the note's "pitch" (Basic Pitch skyline, MIDI), else the spectral centroid as
    round(12 * log2(centroid / 440) + 69), else unpitched;
  * same pitch -> same lane; a step of 1..4 semitones -> +-1 lane; a leap of >= 5 semitones -> +-2 lanes;
  * unpitched notes repeat the previous lane and do not become the new reference pitch.

Octave handling (SPEC req 5: "follows RESEARCH.md's compromise", RESEARCH Pitfall 6 and "Important
conflict to plan around"). Basic Pitch makes many exact-octave errors (126 of 437 intervals on Sea
Shanty 2; B2/B3/B4 bass bleed on INVISIBLE), while SPEC req 4 says "octave leap -> +-2 lanes". The
interpretation implemented in effective_interval():
  * an interval larger than an octave is reduced: d = sign(d) * (|d| mod 12), and a remainder of 0
    (two or more octaves) counts as an exact octave;
  * an exact octave FOLDS to 0 (same lane) when it alternates (the next pitch returns to the previous
    one), when the previous interval was also an exact octave, or when either note's amplitude is
    below 0.3 (low Basic Pitch confidence);
  * otherwise an isolated octave is a real leap and stays +-12, i.e. +-2 lanes (literal SPEC rule);
  * there is no full pitch-class fold: folding a fifth (7) to -5 would flip its direction and break
    "right = up".

VISIBLE SLIDE (orchestrator decision, replaces the plain clamp of the research script): a step whose
target lane would leave 0..n_lanes-1 is a clamped step; the lane stays on the edge and a counter for
that direction increments. When the counter is already >= 2 and the next step goes the same way, the
window slides: that note goes to lane 1 (rising) or lane n_lanes-2 (falling) and the counter resets.
A step in the opposite direction resets the counter; repeats and unpitched notes leave it alone.
Example, rising scale C4 D4 E4 F4 G4 A4 B4 C5 from lane 0 -> 0,1,2,3,3,3,1,2 (falling mirror from
lane 3 -> 3,2,1,0,0,0,2,1). So different pitches never sit on one lane for long.

Accent chords: on "expert" and "hard", notes with strength >= the 90th percentile (linear
interpolation, numpy's default) get a second, adjacent lane (lane + 1, or lane - 1 on the top lane).
Never 3+ lanes.

Sustains: a note whose detected ring (end_tick - tick) is longer than one beat becomes a sustain of
min(end_tick, next note tick) - tick - resolution/4 ticks (a 1/16 gap before the next note); a
length <= resolution/4 becomes a tap (the importer turns those into taps anyway).
"""
from __future__ import annotations

import math

AMP_FOLD = 0.3


def _pitch_of(n: dict) -> int | None:
    p = n.get("pitch")
    if p is not None:
        return int(round(float(p)))
    c = n.get("centroid")
    if c is not None and float(c) > 0.0:
        return int(round(12.0 * math.log2(float(c) / 440.0) + 69.0))
    return None


def _is_octave(d: int | None) -> bool:
    return d is not None and d != 0 and abs(d) % 12 == 0


def _sign(x: float) -> int:
    return (x > 0) - (x < 0)


def effective_interval(prev: int, cur: int, nxt: int | None, prev_interval: int | None,
                       amp_prev: float | None, amp_cur: float | None) -> int:
    """Interval prev -> cur in semitones after the octave compromise (see module docstring).

    prev_interval is the raw interval into `prev` (None if unknown); nxt is the next pitched note's
    pitch (None if none). Amplitudes of None mean "unknown" and never trigger a fold.
    """
    d = int(cur) - int(prev)
    if d == 0:
        return 0
    s = _sign(d)
    if abs(d) > 12:
        r = abs(d) % 12
        d = s * (r if r else 12)
    if abs(d) == 12:
        low = any(a is not None and float(a) < AMP_FOLD for a in (amp_prev, amp_cur))
        if (nxt is not None and int(nxt) == int(prev)) or _is_octave(prev_interval) or low:
            return 0
    return d


def _step(d: int) -> int:
    if d == 0:
        return 0
    return _sign(d) * (2 if abs(d) >= 5 else 1)


def contour_lanes(notes: list[dict], n_lanes: int = 4, start_lane: int = 1) -> list[int]:
    """Lane per note (in the given order) by the contour rule with the VISIBLE SLIDE."""
    top = n_lanes - 1
    pitches = [_pitch_of(n) for n in notes]
    pitched_idx = [i for i, p in enumerate(pitches) if p is not None]
    next_pitched: dict[int, int | None] = {}
    for k, i in enumerate(pitched_idx):
        next_pitched[i] = pitches[pitched_idx[k + 1]] if k + 1 < len(pitched_idx) else None

    lane = max(0, min(top, int(start_lane)))
    up = down = 0
    out: list[int] = []
    prev_i: int | None = None
    prev_raw: int | None = None
    for i, n in enumerate(notes):
        p = pitches[i]
        if p is None or prev_i is None:
            out.append(lane)
            if p is not None:
                prev_i = i
            continue
        pp = pitches[prev_i]
        raw = p - pp
        d = effective_interval(pp, p, next_pitched[i], prev_raw,
                               notes[prev_i].get("amp"), n.get("amp"))
        s = _step(d)
        if s > 0:
            down = 0
            if lane + s > top:
                if up >= 2:
                    lane, up = min(1, top), 0
                else:
                    lane, up = top, up + 1
            else:
                lane += s
        elif s < 0:
            up = 0
            if lane + s < 0:
                if down >= 2:
                    lane, down = max(0, n_lanes - 2), 0
                else:
                    lane, down = 0, down + 1
            else:
                lane += s
        out.append(lane)
        prev_i, prev_raw = i, raw
    return out


def _percentile(values: list[float], q: float) -> float:
    """Linear-interpolation percentile (numpy default), q in 0..100."""
    s = sorted(values)
    if not s:
        return math.inf
    pos = (len(s) - 1) * q / 100.0
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def assign_lanes(notes: list[dict], difficulty: str, n_lanes: int = 4,
                 resolution: int = 192) -> list[dict]:
    """New note dicts (sorted by tick) with base_lane, lanes and len set. Input is not modified."""
    out = [dict(n) for n in sorted(notes, key=lambda n: n["tick"])]
    base = contour_lanes(out, n_lanes=n_lanes, start_lane=1)
    chords = difficulty.lower() in ("expert", "hard")
    thr = _percentile([float(n.get("strength") or 0.0) for n in out], 90.0) if chords else math.inf
    sixteenth = resolution // 4
    top = n_lanes - 1
    for i, n in enumerate(out):
        b = max(0, min(top, base[i]))
        n["base_lane"] = b
        lanes = [b]
        if chords and n_lanes > 1 and float(n.get("strength") or 0.0) >= thr:
            lanes = sorted([b, b - 1 if b == top else b + 1])
        n["lanes"] = lanes
        ln = 0
        end = n.get("end_tick")
        if end is not None and int(end) - n["tick"] > resolution:
            stop = int(end)
            if i + 1 < len(out):
                stop = min(stop, out[i + 1]["tick"])
            ln = stop - n["tick"] - sixteenth
            if ln <= sixteenth:
                ln = 0
        n["len"] = ln
    return out


def _lane(n: dict) -> int:
    if n.get("base_lane") is not None:
        return int(n["base_lane"])
    return int(n["lanes"][0])


def direction_match(notes: list[dict]) -> float:
    """Share of consecutive pitched pairs with different pitch whose lane moves the same way.

    Uses raw pitch (octave errors count as losses, like the research metric) and base_lane.
    Returns 1.0 when there is no direction change to judge.
    """
    hit = total = 0
    for a, b in zip(notes, notes[1:]):
        pa, pb = _pitch_of(a), _pitch_of(b)
        if pa is None or pb is None or pa == pb:
            continue
        total += 1
        if _sign(_lane(b) - _lane(a)) == _sign(pb - pa):
            hit += 1
    return hit / total if total else 1.0


def lane_step_hist(notes: list[dict]) -> list[float]:
    """Shares of |base_lane step| = 0, 1, 2, 3+ between consecutive notes (all zeros if < 2 notes)."""
    counts = [0, 0, 0, 0]
    for a, b in zip(notes, notes[1:]):
        counts[min(3, abs(_lane(b) - _lane(a)))] += 1
    total = sum(counts)
    return [c / total for c in counts] if total else [0.0, 0.0, 0.0, 0.0]
