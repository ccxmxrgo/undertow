"""Unit tests for stages/quantize.py (SPEC requirement 3, D-06). Stdlib only."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import quantize, tempo_map  # noqa: E402


def _tm(milli_bpm=120000, delay_ms=0):
    return {"resolution": 192, "delay_ms": delay_ms,
            "events": [[0, "TS", 4], [0, "B", milli_bpm]],
            "beat_ticks": [], "beat_times": [], "bar_ticks": []}


def _on(t, strength=1.0, **kw):
    d = {"t": t, "strength": strength, "pitch": None, "amp": None, "centroid": None,
         "off_t": None, "src": "other"}
    d.update(kw)
    return d


class QuantizeTest(unittest.TestCase):
    def test_density_target_keeps_strongest(self):
        ons = [_on(1.0 + i * 10.0 / 39.0, float((i * 7) % 40 + 1)) for i in range(40)]
        notes = quantize.build_expert(ons, _tm(), target_nps=2.0)
        self.assertEqual(len(notes), 20)
        strongest = sorted(ons, key=lambda o: -o["strength"])[:20]
        self.assertEqual(sorted(n["t_onset"] for n in notes), sorted(o["t"] for o in strongest))
        ticks = [n["tick"] for n in notes]
        self.assertEqual(ticks, sorted(ticks))

    def test_merge_below_sixteenth_keeps_stronger(self):
        ons = [_on(1.0, 1.0, src="a"), _on(1.03, 2.0, src="b")]
        notes = quantize.build_expert(ons, _tm(), target_nps=100.0)
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]["t_onset"], 1.03)
        self.assertEqual(notes[0]["src"], "b")

    def test_snap_rules(self):
        tm = _tm()
        n16 = quantize.build_expert([_on(1.125 + 0.008)], tm, target_nps=100.0)[0]
        self.assertEqual(n16["snap"], "16")
        self.assertEqual(n16["tick"], 432)
        self.assertAlmostEqual(n16["t"], 1.125, delta=1e-9)

        tm200 = _tm(200000)  # beat 0.3 s: 1/16 = 75 ms, 1/12 = 100 ms
        n12 = quantize.build_expert([_on(0.095)], tm200, target_nps=100.0)[0]
        self.assertEqual(n12["snap"], "12")
        self.assertEqual(n12["tick"], 64)

        free = quantize.build_expert([_on(2.025)], tm, target_nps=100.0)[0]
        self.assertIsNone(free["snap"])
        self.assertEqual(free["tick"], round(tempo_map.sec_to_tick(tm, 2.025)))
        self.assertAlmostEqual(free["t"], tempo_map.tick_to_sec(tm, free["tick"]), delta=1e-12)
        self.assertEqual(free["t_onset"], 2.025)

    def test_window_cap_drops_weakest(self):
        tm = _tm(240000)  # 1/16 = 62.5 ms
        ons = [_on(1.0 + i * 0.0625, float(i + 1)) for i in range(12)]
        notes = quantize.build_expert(ons, tm, target_nps=100.0)
        self.assertEqual(len(notes), 8)
        self.assertEqual(sorted(n["strength"] for n in notes), [float(i + 1) for i in range(4, 12)])
        self.assertLessEqual(quantize.notes_per_window_max(notes), 8)

    def test_fields_and_end_tick(self):
        on = _on(1.0, 3.0, pitch=64.0, amp=0.5, centroid=900.0, off_t=2.0, src="vocals")
        n = quantize.build_expert([on], _tm(), target_nps=100.0)[0]
        for k in ("tick", "t", "t_onset", "snap", "end_tick", "lanes", "len"):
            self.assertIn(k, n)
        self.assertEqual(n["end_tick"], 768)
        self.assertEqual(n["lanes"], [])
        self.assertEqual(n["len"], 0)
        self.assertEqual((n["pitch"], n["amp"], n["centroid"], n["strength"], n["src"]),
                         (64.0, 0.5, 900.0, 3.0, "vocals"))
        self.assertIsNone(quantize.build_expert([_on(1.0)], _tm(), 100.0)[0]["end_tick"])
        self.assertEqual(on["t"], 1.0)  # input not mutated
        self.assertNotIn("tick", on)

    def test_deterministic_and_reporting(self):
        ons = [_on(0.5 + 0.11 * i, 1.0 if i % 3 else 2.0) for i in range(60)]
        a = quantize.build_expert(ons, _tm(), target_nps=4.0)
        b = quantize.build_expert(list(reversed(ons)), _tm(), target_nps=4.0)
        self.assertEqual(a, b)
        self.assertLessEqual(quantize.notes_per_window_max(a), 8)
        share = quantize.on_grid_share(a)
        self.assertEqual(share, sum(1 for n in a if n["snap"] is not None) / len(a))
        self.assertEqual(quantize.on_grid_share([]), 0.0)
        self.assertEqual(quantize.build_expert([], _tm(), 4.0), [])
        for x, y in zip(a, a[1:]):
            self.assertGreaterEqual(y["tick"] - x["tick"], 48)


if __name__ == "__main__":
    unittest.main()
