"""Section names, solo span and preview start (D-08, SPEC requirement 7, RESEARCH Pattern 7). Stdlib only.

All choices are deterministic; ties resolve to the earliest section / window.

name_sections: the first / last section is "Intro" / "Outro" when its energy is below the median
section energy; otherwise it is named like any other section. Among the remaining sections, the
repeated label (>= 2 occurrences) with the highest mean energy is the chorus, the most frequent other
repeated label is the verse ("Chorus 1", "Verse 2", ... numbered per name); everything else is
"Section N" with N the 1-based section index.

pick_solo: windows of min_bars..max_bars consecutive bars (a window needs the next bar start, which
also gives its end: next bar start - resolution / 4, the existing soloend convention). Eligible when
both Hard and Expert hold >= min_notes distinct ticks in [start, end]. Score = Hard notes per bar.
An instrumental window (vocal_active share < 0.5, or no vocal data) is preferred; otherwise the
densest eligible window; None when nothing is eligible. Ties: earliest start, then the longer window.

pick_preview: start (ms) of the loudest section by mean RMS among the candidates: a section that starts
in the first PREVIEW_MIN_START_MS (10 s, usually an intro) is skipped, and so is one that starts less
than PREVIEW_TAIL_MS (30 s) before the song end, so the preview always has >= 30 s of audio after it.
When no section qualifies: 30% of the song length, clamped to song_length - 30 s (and >= 0). Without a
song length only the intro rule applies (falls back to the loudest section overall).
"""
from __future__ import annotations

import bisect
import statistics
from fractions import Fraction


def name_sections(labels: list[int], energies: list[float]) -> list[str]:
    n = len(labels)
    if n == 0:
        return []
    med = statistics.median(energies)
    names: list[str | None] = [None] * n
    if energies[0] < med:
        names[0] = "Intro"
    if n > 1 and energies[-1] < med:
        names[-1] = "Outro"
    rest = [i for i in range(n) if names[i] is None]

    counts: dict[int, int] = {}
    first: dict[int, int] = {}
    esum: dict[int, float] = {}
    for i in rest:
        lab = labels[i]
        counts[lab] = counts.get(lab, 0) + 1
        first.setdefault(lab, i)
        esum[lab] = esum.get(lab, 0.0) + float(energies[i])
    repeated = [lab for lab, c in counts.items() if c >= 2]
    chorus = min(repeated, key=lambda l: (-esum[l] / counts[l], first[l])) if repeated else None
    others = [l for l in repeated if l != chorus]
    verse = min(others, key=lambda l: (-counts[l], first[l])) if others else None

    numbers = {"Chorus": 0, "Verse": 0}
    for i in rest:
        lab = labels[i]
        if lab == chorus:
            numbers["Chorus"] += 1
            names[i] = f"Chorus {numbers['Chorus']}"
        elif lab == verse:
            numbers["Verse"] += 1
            names[i] = f"Verse {numbers['Verse']}"
        else:
            names[i] = f"Section {i + 1}"
    return [str(x) for x in names]


def _count(ticks: list[int], lo: int, hi: int) -> int:
    return bisect.bisect_right(ticks, hi) - bisect.bisect_left(ticks, lo)


def pick_solo(hard: list[dict], expert: list[dict], bar_ticks: list[int],
              vocal_active: list[bool] | None, min_bars: int = 4, max_bars: int = 8,
              min_notes: int = 16, resolution: int = 192) -> tuple[int, int] | None:
    h = sorted({n["tick"] for n in hard})
    e = sorted({n["tick"] for n in expert})
    n_bars = len(bar_ticks) - 1
    best_inst = None
    best_any = None
    for start in range(max(n_bars, 0)):
        for k in range(min_bars, max_bars + 1):
            if start + k > n_bars:
                break
            lo = bar_ticks[start]
            hi = bar_ticks[start + k] - resolution // 4
            nh = _count(h, lo, hi)
            if nh < min_notes or _count(e, lo, hi) < min_notes:
                continue
            key = (-Fraction(nh, k), start, -k)
            cand = (key, (lo, hi))
            if best_any is None or key < best_any[0]:
                best_any = cand
            inst = True
            if vocal_active is not None:
                seg = vocal_active[start:start + k]
                inst = not seg or Fraction(sum(1 for v in seg if v), len(seg)) < Fraction(1, 2)
            if inst and (best_inst is None or key < best_inst[0]):
                best_inst = cand
    chosen = best_inst or best_any
    return chosen[1] if chosen else None


PREVIEW_MIN_START_MS = 10000
PREVIEW_TAIL_MS = 30000


def pick_preview(section_starts_ms: list[int], section_rms: list[float],
                 song_length_ms: int | None = None) -> int:
    idx = range(len(section_starts_ms))
    cands = [k for k in idx if int(section_starts_ms[k]) >= PREVIEW_MIN_START_MS
             and (song_length_ms is None
                  or int(section_starts_ms[k]) <= int(song_length_ms) - PREVIEW_TAIL_MS)]
    if cands:
        i = min(cands, key=lambda k: (-float(section_rms[k]), k))
        return int(section_starts_ms[i])
    if song_length_ms is None:
        if not section_starts_ms:
            return 0
        i = min(idx, key=lambda k: (-float(section_rms[k]), k))
        return int(section_starts_ms[i])
    length = int(song_length_ms)
    return max(0, min(int(round(0.3 * length)), length - PREVIEW_TAIL_MS))
