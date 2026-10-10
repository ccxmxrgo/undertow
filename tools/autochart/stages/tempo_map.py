"""Tempo map stage: refined beat times -> Clone Hero [SyncTrack] (SPEC requirement 2, RESEARCH Pattern 1).

Stdlib only (no numpy) so it runs and is unit-tested without the ML venvs (D-04).

Rules:
- Bar 1 = the first downbeat (snapped to its nearest beat). Beats before it are dropped.
- Lead-in: n = round(first_downbeat / IBI), IBI = median inter-beat interval.
  n = 0 -> the downbeat sits at tick 0 and delay_ms = round(first_downbeat * 1000).
  n >= 1 -> delay_ms = 0 and one lead-in B at tick 0 = round(60000 * n / first_downbeat).
- constant_tempo=True: one B at the downbeat = round(60000 / slope), slope = least-squares IBI.
  The downbeat time comes from the same line fit (one noisy beat does not shift the grid).
- Otherwise one B on every beat. Error diffusion on absolute time: each beat's integer milli-BPM is
  the one whose resulting chart time for the next beat is closest to the tracked beat, so rounding
  never accumulates (the error of any beat stays within half a milli-BPM step, a few microseconds).
  The last beat reuses the previous B.
- TS from downbeats: beats per bar between consecutive downbeats; default 4; a change needs at least
  2 consecutive bars that agree. A lead-in that is not a whole number of bars becomes a pickup bar
  (TS r at tick 0, then the song's TS where full bars start), so bar 1 lands on a bar line.
- tick_to_sec mirrors src/core/chart_importer.gd _segments/_tick_to_sec exactly (float64, BPM
  clamped to 1..2000, the last B at one tick wins, 120 BPM before the first B, delay added).

TempoMap dict: resolution, delay_ms, events ([tick, "TS", num] / [tick, "B", milli_bpm], sorted by
tick, TS before B at one tick), beat_ticks, beat_times (= tick_to_sec of each beat tick), bar_ticks
(bar lines as the game draws them from the TS events, starting at bar 1 = the first downbeat).
"""
from __future__ import annotations

from bisect import bisect_right
from functools import lru_cache

MIN_BPM = 1.0
MAX_BPM = 2000.0
DEFAULT_BPM = 120.0
MIN_MILLI = 1000
MAX_MILLI = 2000000


def _clamp_milli(mb: float) -> int:
    return int(min(max(int(round(mb)), MIN_MILLI), MAX_MILLI))


def _median(xs: list[float]) -> float:
    s = sorted(xs)
    m = len(s) // 2
    return s[m] if len(s) % 2 else 0.5 * (s[m - 1] + s[m])


def _beat_dur(mb: int) -> float:
    # one beat (res ticks) at mb, in the importer's operation order: float(res)/res * 60.0 / bpm
    bpm = min(max(float(mb) / 1000.0, MIN_BPM), MAX_BPM)
    return 1.0 * 60.0 / bpm


def _best_milli(target_dur: float) -> int:
    """Integer milli-BPM whose beat duration is closest to target_dur (clamped to importer limits)."""
    if target_dur <= 0.0:
        return MAX_MILLI
    c = _clamp_milli(60000.0 / target_dur)
    best = c
    best_err = abs(_beat_dur(c) - target_dur)
    for cand in (c - 1, c + 1):
        if MIN_MILLI <= cand <= MAX_MILLI:
            err = abs(_beat_dur(cand) - target_dur)
            if err < best_err:
                best, best_err = cand, err
    return best


def _nearest_index(beats: list[float], t: float) -> int:
    i = bisect_right(beats, t)
    if i == 0:
        return 0
    if i >= len(beats):
        return len(beats) - 1
    return i if (beats[i] - t) < (t - beats[i - 1]) else i - 1


def _ls_fit(beats: list[float]) -> tuple[float, float]:
    """Least-squares line t = a + slope * i over beat indices."""
    n = len(beats)
    mx = (n - 1) / 2.0
    my = sum(beats) / n
    sxx = sum((i - mx) ** 2 for i in range(n))
    sxy = sum((i - mx) * (t - my) for i, t in enumerate(beats))
    slope = sxy / sxx if sxx > 0 else 0.5
    return my - slope * mx, slope


def _bar_counts(rel_idx: list[int]) -> list[int]:
    return [b - a for a, b in zip(rel_idx, rel_idx[1:])]


def _ts_plan(counts: list[int]) -> tuple[int, list[tuple[int, int]]]:
    """(initial numerator, [(bar index, numerator)] changes). A change needs >= 2 agreeing bars."""
    initial = 4
    if len(counts) >= 2 and counts[0] == counts[1] and counts[0] > 0:
        initial = counts[0]
    cur = initial
    changes: list[tuple[int, int]] = []
    for k in range(1, len(counts) - 1):
        c = counts[k]
        if c > 0 and c != cur and counts[k + 1] == c:
            changes.append((k, c))
            cur = c
    return initial, changes


def build_tempo_map(beats: list[float], downbeats: list[float], constant_tempo: bool,
                    resolution: int = 192) -> dict:
    beats = sorted(float(b) for b in beats)
    if len(beats) < 2:
        raise ValueError("build_tempo_map needs at least 2 beats")
    res = int(resolution)
    ibi = _median([b - a for a, b in zip(beats, beats[1:])])
    if ibi <= 0:
        raise ValueError("beats must be increasing")

    downs = sorted(float(d) for d in downbeats)
    i0 = _nearest_index(beats, downs[0]) if downs else 0
    used = beats[i0:]

    if constant_tempo:
        a, slope = _ls_fit(beats)
        fd = a + slope * i0
    else:
        slope = ibi
        fd = used[0]

    n = int(round(fd / ibi)) if fd > 0 else 0
    events: list[list] = []
    delay_ms = 0
    if n <= 0:
        n = 0
        delay_ms = int(round(fd * 1000.0)) if fd > 0 else 0
        seg_sec = 0.0
    else:
        lead = _clamp_milli(60000.0 * n / fd)
        events.append([0, "B", lead])
        bpm = min(max(float(lead) / 1000.0, MIN_BPM), MAX_BPM)
        seg_sec = float(n * res) / float(res) * 60.0 / bpm
    delay = float(delay_ms) / 1000.0
    db_tick = n * res
    beat_ticks = [db_tick + res * i for i in range(len(used))]

    if constant_tempo:
        mb = _clamp_milli(60000.0 / slope) if slope > 0 else MAX_MILLI
        if not events or events[-1][2] != mb:
            events.append([db_tick, "B", mb])
    else:
        mbs: list[int] = []
        for i in range(len(used) - 1):
            target = used[i + 1] - (seg_sec + delay)
            mb = _best_milli(target)
            mbs.append(mb)
            events.append([beat_ticks[i], "B", mb])
            seg_sec += _beat_dur(mb)
        last = mbs[-1] if mbs else _clamp_milli(60000.0 / ibi)
        events.append([beat_ticks[-1], "B", last])

    # time signature
    rel = sorted({_nearest_index(beats, d) - i0 for d in downs if _nearest_index(beats, d) >= i0})
    if not rel or rel[0] != 0:
        rel = [0] + rel
    counts = _bar_counts(rel)
    num0, changes = _ts_plan(counts)
    ts_events: list[list] = []
    r = n % num0
    if n == 0 or r == 0:
        ts_events.append([0, "TS", num0])
    else:
        ts_events.append([0, "TS", r])
        ts_events.append([r * res, "TS", num0])
    for k, c in changes:
        ts_events.append([db_tick + rel[k] * res, "TS", c])

    all_events = ts_events + events
    all_events.sort(key=lambda e: (e[0], 0 if e[1] == "TS" else 1))

    # bar lines from bar 1 as drawn from the TS events
    end_tick = beat_ticks[-1]
    ts_after = [(e[0], e[2]) for e in ts_events if e[0] > db_tick]
    bar_ticks: list[int] = []
    cur, num, j = db_tick, num0, 0
    while cur <= end_tick:
        bar_ticks.append(cur)
        nxt = cur + num * res
        if j < len(ts_after) and ts_after[j][0] <= nxt:
            nxt = ts_after[j][0]
            num = ts_after[j][1]
            j += 1
        cur = nxt

    tm = {
        "resolution": res,
        "delay_ms": delay_ms,
        "events": all_events,
        "beat_ticks": beat_ticks,
        "beat_times": [],
        "bar_ticks": bar_ticks,
    }
    tm["beat_times"] = [tick_to_sec(tm, k) for k in beat_ticks]
    return tm


@lru_cache(maxsize=64)
def _segments(res: int, events: tuple) -> tuple:
    """Mirror of ChartImporter._segments: ((tick, bpm, sec), ...) sorted by tick."""
    raw: list[list] = []
    for tick, kind, val in events:
        if kind != "B":
            continue
        bpm = min(max(float(val) / 1000.0, MIN_BPM), MAX_BPM)
        if raw and raw[-1][0] == tick:
            raw[-1][1] = bpm
        else:
            raw.append([tick, bpm])
    if not raw or raw[0][0] > 0:
        raw.insert(0, [0, DEFAULT_BPM])
    r = float(max(res, 1))
    sec = 0.0
    out = []
    for i, (tick, bpm) in enumerate(raw):
        if i > 0:
            p = raw[i - 1]
            sec += float(tick - p[0]) / r * 60.0 / p[1]
        out.append((tick, bpm, sec))
    return tuple(out)


def _segs(tm: dict) -> tuple:
    # stable sort by tick only, so the last B at one tick still wins (importer reads file order)
    evs = tuple(sorted(((int(e[0]), e[1], e[2]) for e in tm["events"] if e[1] == "B"), key=lambda e: e[0]))
    return _segments(int(tm["resolution"]), evs)


def tick_to_sec(tm: dict, tick) -> float:
    """Chart tick -> song seconds exactly as ChartImporter computes it, delay_ms included."""
    segs = _segs(tm)
    res = float(int(tm["resolution"]))
    ticks = [s[0] for s in segs]
    lo = max(bisect_right(ticks, tick) - 1, 0)
    s = segs[lo]
    return s[2] + float(tick - s[0]) / res * 60.0 / s[1] + float(int(tm["delay_ms"])) / 1000.0


def sec_to_tick(tm: dict, t: float) -> float:
    """Exact inverse of tick_to_sec (fractional ticks; times before tick 0 extrapolate)."""
    segs = _segs(tm)
    res = float(int(tm["resolution"]))
    local = float(t) - float(int(tm["delay_ms"])) / 1000.0
    secs = [s[2] for s in segs]
    lo = max(bisect_right(secs, local) - 1, 0)
    s = segs[lo]
    return s[0] + (local - s[2]) * s[1] / 60.0 * res
