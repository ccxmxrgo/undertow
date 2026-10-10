"""Unit tests for stages/fill.py (RESEARCH Pitfall 9, SPEC requirement 3 fill stem). Stdlib only."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import fill  # noqa: E402

# 120 BPM, 4/4, resolution 192: one bar = 768 ticks = 2.0 s; 12 bars
BAR_S = 2.0


def _tm(delay_ms=0, bars=12):
    return {"resolution": 192, "delay_ms": delay_ms,
            "events": [[0, "TS", 4], [0, "B", 120000]],
            "beat_ticks": [], "beat_times": [], "bar_ticks": [i * 768 for i in range(bars + 1)]}


def _on(t, src, strength=1.0):
    return {"t": t, "strength": strength, "pitch": None, "amp": None, "centroid": 300.0,
            "off_t": None, "src": src}


def _per_bar(bars, src, per=2, delay_s=0.0):
    out = []
    for b in bars:
        for k in range(per):
            out.append(_on(delay_s + b * BAR_S + 0.25 + k * BAR_S / per, src))
    return out


class FillBarsTest(unittest.TestCase):
    def test_silent_bars_take_fill_onsets(self):
        tm = _tm()
        primary = _per_bar(list(range(0, 4)) + list(range(6, 10)), "other")
        fill_ons = _per_bar(range(0, 12), "drums", per=3)
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars", fill_src="drums")
        got_fill = [n for n in out if n["src"] == "drums"]
        # bars 4-5 are silent inside the primary; bars 10-11 too (no primary at all there)
        bars = sorted({int(n["t"] // BAR_S) for n in got_fill})
        self.assertEqual(bars, [4, 5, 10, 11])
        self.assertEqual(len([n for n in out if n["src"] == "other"]), len(primary))
        self.assertEqual(len(got_fill), 4 * 3)

    def test_fill_only_bars_4_5_when_primary_covers_the_rest(self):
        tm = _tm(bars=10)
        primary = _per_bar(list(range(0, 4)) + list(range(6, 10)), "other")
        fill_ons = _per_bar(range(0, 10), "drums", per=3)
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars", fill_src="drums")
        bars = sorted({int(n["t"] // BAR_S) for n in out if n["src"] == "drums"})
        self.assertEqual(bars, [4, 5])

    def test_min_bars_run_length(self):
        tm = _tm(bars=10)
        primary = _per_bar([0, 1, 2, 4, 5, 8, 9], "other")  # gaps: bar 3 (1 bar), bars 6-7 (2 bars)
        fill_ons = _per_bar(range(0, 10), "drums")
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars", min_bars=2, fill_src="drums")
        bars = sorted({int(n["t"] // BAR_S) for n in out if n["src"] == "drums"})
        self.assertEqual(bars, [6, 7])

    def test_delay_respected(self):
        tm = _tm(delay_ms=500, bars=10)
        primary = _per_bar(list(range(0, 4)) + list(range(6, 10)), "other", delay_s=0.5)
        fill_ons = _per_bar(range(0, 10), "drums", delay_s=0.5)
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars", fill_src="drums")
        bars = sorted({int((n["t"] - 0.5) // BAR_S) for n in out if n["src"] == "drums"})
        self.assertEqual(bars, [4, 5])

    def test_fill_src_defaults_to_record_src(self):
        tm = _tm(bars=10)
        primary = _per_bar(list(range(0, 4)) + list(range(6, 10)), "other")
        fill_ons = _per_bar(range(0, 10), "bass")
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars")
        self.assertTrue(all(n["src"] in ("other", "bass") for n in out))
        self.assertTrue(any(n["src"] == "bass" for n in out))


class FillSectionsTest(unittest.TestCase):
    def test_sparse_section_switches_to_fill(self):
        tm = _tm()
        # sections start at bars 0, 4, 8; section 2 (bars 4-7) is sparse: 1 note vs 8 per section
        primary = _per_bar(range(0, 4), "other") + [_on(4 * BAR_S + 0.3, "other")] \
            + _per_bar(range(8, 12), "other")
        fill_ons = _per_bar(range(0, 12), "bass", per=3)
        out = fill.fill_silent(primary, fill_ons, tm, mode="sections",
                               section_starts_tick=[0, 4 * 768, 8 * 768], fill_src="bass")
        sec2 = [n for n in out if 4 * BAR_S <= n["t"] < 8 * BAR_S]
        self.assertTrue(sec2)
        self.assertTrue(all(n["src"] == "bass" for n in sec2))
        self.assertEqual(len(sec2), 4 * 3)
        others = [n for n in out if not 4 * BAR_S <= n["t"] < 8 * BAR_S]
        self.assertTrue(all(n["src"] == "other" for n in others))
        self.assertEqual(len(others), 16)

    def test_dense_sections_stay_primary(self):
        tm = _tm()
        primary = _per_bar(range(0, 12), "other")
        fill_ons = _per_bar(range(0, 12), "bass")
        out = fill.fill_silent(primary, fill_ons, tm, mode="sections",
                               section_starts_tick=[0, 4 * 768, 8 * 768], fill_src="bass")
        self.assertTrue(all(n["src"] == "other" for n in out))
        self.assertEqual(len(out), len(primary))

    def test_sections_mode_requires_starts(self):
        with self.assertRaises(ValueError):
            fill.fill_silent([_on(1.0, "other")], [_on(1.0, "bass")], _tm(), mode="sections")


class FillGeneralTest(unittest.TestCase):
    def test_empty_fill_returns_primary_sorted_and_inputs_untouched(self):
        tm = _tm()
        primary = [_on(5.0, "other"), _on(1.0, "other"), _on(3.0, "other")]
        snap_p = copy.deepcopy(primary)
        out = fill.fill_silent(primary, [], tm, mode="bars")
        self.assertEqual([n["t"] for n in out], [1.0, 3.0, 5.0])
        self.assertEqual(primary, snap_p)

    def test_output_sorted_and_inputs_not_mutated(self):
        tm = _tm(bars=10)
        primary = _per_bar(list(range(0, 4)) + list(range(6, 10)), "other")
        fill_ons = _per_bar(range(0, 10), "drums", per=3)
        snap_p, snap_f = copy.deepcopy(primary), copy.deepcopy(fill_ons)
        out = fill.fill_silent(primary, fill_ons, tm, mode="bars", fill_src="drums")
        self.assertEqual(primary, snap_p)
        self.assertEqual(fill_ons, snap_f)
        ts = [n["t"] for n in out]
        self.assertEqual(ts, sorted(ts))

    def test_bad_mode(self):
        with self.assertRaises(ValueError):
            fill.fill_silent([], [], _tm(), mode="nope")


if __name__ == "__main__":
    unittest.main()
