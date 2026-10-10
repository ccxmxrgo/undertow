"""Unit tests for stages/instrument_lanes.py (STEM-04, RESEARCH Pattern 8). Stdlib only."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import instrument_lanes as il, reduce as red  # noqa: E402

RES = 192
SEC_PER_BEAT = 0.5  # 120 BPM
N_BARS = 16


def _tm():
    return {"resolution": RES, "delay_ms": 0,
            "events": [[0, "TS", 4], [0, "B", 120000]],
            "beat_ticks": [b * RES for b in range(N_BARS * 4 + 1)], "beat_times": [],
            "bar_ticks": [b * RES * 4 for b in range(N_BARS + 1)]}


def _on(t, strength=1.0, off_t=None, **kw):
    d = {"t": t, "strength": strength, "pitch": None, "amp": None, "centroid": None,
         "off_t": off_t, "audible": True, "loud": True}
    d.update(kw)
    return d


def _tick(t):
    return int(round(t / SEC_PER_BEAT * RES))


def _band(n=32, step=0.5, start=0.5, phase=0.0, strength=1.0):
    return [_on(start + phase + i * step, strength + (i % 3) * 0.1) for i in range(n)]


class InstrumentLanesTest(unittest.TestCase):
    def test_lane_is_stem_index(self):
        ons = {"bass": [_on(1.0)], "drums": [_on(2.0)], "other": [_on(3.0)], "vocals": [_on(4.0)]}
        notes = il.instrument_expert(ons, _tm(), target_nps=100.0)
        self.assertEqual([(n["tick"], n["lanes"], n["src"]) for n in notes],
                         [(_tick(1.0), [0], "bass"), (_tick(2.0), [1], "drums"),
                          (_tick(3.0), [2], "other"), (_tick(4.0), [3], "vocals")])
        self.assertEqual([n["base_lane"] for n in notes], [0, 1, 2, 3])
        custom = il.instrument_expert(ons, _tm(), lane_order=("vocals", "other", "drums", "bass"),
                                      target_nps=100.0)
        self.assertEqual([n["lanes"] for n in custom], [[3], [2], [1], [0]])
        for key in ("tick", "t", "t_onset", "snap", "strength", "src", "base_lane", "lanes", "len"):
            self.assertIn(key, notes[0])

    def test_three_stems_on_one_tick_become_a_two_lane_chord_of_the_strongest(self):
        # strengths are normalised per stem by its own 95th percentile: raw values differ by 100x
        ons = {"bass": [_on(1.0, 100.0)] + [_on(5.0 + i, 100.0) for i in range(4)],
               "drums": [_on(1.0, 0.5)] + [_on(5.25 + i, 1.0) for i in range(4)],
               "other": [_on(1.0, 0.9)] + [_on(5.5 + i, 1.0) for i in range(4)]}
        notes = il.instrument_expert(ons, _tm(), target_nps=100.0)
        first = [n for n in notes if n["tick"] == _tick(1.0)]
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0]["lanes"], [0, 2])  # bass 1.0 and other 0.9 beat drums 0.5
        self.assertEqual(first[0]["base_lane"], 0)
        self.assertTrue(all(len(n["lanes"]) <= 2 for n in notes))

    def test_same_lane_merge_below_sixteenth_and_snap(self):
        ons = {"bass": [_on(1.0, 1.0), _on(1.03, 2.0), _on(2.008, 1.0), _on(3.04, 1.0)]}
        notes = il.instrument_expert(ons, _tm(), target_nps=100.0)
        self.assertEqual(len(notes), 3)
        self.assertEqual(notes[0]["t_onset"], 1.03)  # stronger kept
        self.assertEqual(notes[1]["tick"], _tick(2.0))  # 8 ms -> snapped to the grid
        self.assertEqual(notes[1]["snap"], "16")
        self.assertIsNone(notes[2]["snap"])  # 40 ms from any grid line -> exact tick
        ticks = [n["tick"] for n in notes]
        self.assertTrue(all(b - a >= RES // 4 for a, b in zip(ticks, ticks[1:])))

    def test_cross_lane_flams_merge_into_the_stronger(self):
        ons = {"bass": [_on(1.0, 1.0), _on(9.0, 1.0)], "drums": [_on(1.04, 2.0), _on(9.5, 2.0)]}
        notes = il.instrument_expert(ons, _tm(), target_nps=100.0)
        near = [n for n in notes if n["t"] < 2.0]
        self.assertEqual(len(near), 1)
        self.assertEqual(near[0]["lanes"], [1])

    def test_density_target_and_window_cap(self):
        ons = {"bass": _band(64, 0.25), "drums": _band(64, 0.25, phase=0.125, strength=2.0),
               "other": _band(64, 0.25, phase=0.0625)}
        notes = il.instrument_expert(ons, _tm(), target_nps=3.0)
        span = 0.5 + 63 * 0.25 + 0.125 - 0.5
        self.assertLessEqual(len(notes), round(3.0 * span) + 1)
        times = sorted(n["t"] for n in notes)
        for i, t in enumerate(times):
            self.assertLessEqual(sum(1 for u in times[i:] if u < t + 1.0 - 1e-9), 8)
        dense = il.instrument_expert(ons, _tm(), target_nps=50.0, cap_per_s=8.0)
        times = sorted(n["t"] for n in dense)
        for i, t in enumerate(times):
            self.assertLessEqual(sum(1 for u in times[i:] if u < t + 1.0 - 1e-9), 8)

    def test_sustains_stop_before_the_next_note_in_the_same_lane(self):
        ons = {"bass": [_on(1.0, 1.0, off_t=4.0), _on(2.0, 1.0)],
               "drums": [_on(1.5, 1.0)],
               "other": [_on(5.0, 1.0, off_t=5.3)]}
        notes = {n["src"] + str(n["tick"]): n for n in il.instrument_expert(ons, _tm(), target_nps=100.0)}
        held = notes["bass" + str(_tick(1.0))]
        self.assertEqual(held["len"], _tick(2.0) - _tick(1.0) - RES // 4)  # drums at 1.5 s do not cut it
        self.assertEqual(notes["other" + str(_tick(5.0))]["len"], 0)  # ring < 1 beat

    def test_easy_lane_map_drops_the_sparsest_lane(self):
        notes = [{"tick": i * RES, "lanes": [lane], "base_lane": lane}
                 for i, lane in enumerate([0, 0, 1, 1, 1, 2, 3, 3, 3, 0])]
        self.assertEqual(il.easy_lane_map(notes), {0: 0, 1: 1, 2: None, 3: 2})
        tie = [{"tick": 0, "lanes": [0, 1]}, {"tick": RES, "lanes": [2, 3]}]
        self.assertEqual(il.easy_lane_map(tie), {0: 0, 1: 1, 2: 2, 3: None})

    def test_easy_reduction_uses_three_lanes_and_expert_ticks(self):
        ons = {"bass": _band(48, 0.5), "drums": _band(48, 0.5, phase=0.25, strength=2.0),
               "other": _band(24, 1.0, phase=0.125), "vocals": _band(6, 4.0, phase=0.375)}
        tm = _tm()
        expert = il.instrument_expert(ons, tm, target_nps=3.5)
        self.assertTrue(all(0 <= lane <= 3 for n in expert for lane in n["lanes"]))
        lane_map = il.easy_lane_map(expert)
        easy = red.reduce(expert, "easy", tm, easy_lane_map=lane_map)
        self.assertGreater(len(easy), 0)
        self.assertTrue(all(0 <= lane <= 2 for n in easy for lane in n["lanes"]))
        self.assertTrue({n["tick"] for n in easy} <= {n["tick"] for n in expert})
        for d in ("hard", "medium"):
            sub = red.reduce(expert, d, tm)
            self.assertTrue({n["tick"] for n in sub} <= {n["tick"] for n in expert})

    def test_deterministic_and_inputs_not_mutated(self):
        ons = {"bass": _band(40, 0.3), "drums": _band(40, 0.3, phase=0.1, strength=3.0),
               "vocals": _band(10, 1.1, phase=0.05)}
        before = copy.deepcopy(ons)
        a = il.instrument_expert(ons, _tm())
        b = il.instrument_expert(ons, _tm())
        self.assertEqual(a, b)
        self.assertEqual(ons, before)
        self.assertEqual(il.instrument_expert({}, _tm()), [])


if __name__ == "__main__":
    unittest.main()
