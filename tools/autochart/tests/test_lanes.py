"""Unit tests for stages/lanes.py (SPEC requirement 4, RESEARCH octave compromise). Stdlib only."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import lanes  # noqa: E402

# MIDI numbers
C4, D4, E4, F4, G4, A4, B4, C5 = 60, 62, 64, 65, 67, 69, 71, 72
A3 = 57


def _n(pitch=None, tick=0, strength=1.0, amp=None, centroid=None, end_tick=None):
    return {"tick": tick, "t": tick / 384.0, "t_onset": tick / 384.0, "strength": strength,
            "pitch": pitch, "amp": amp, "centroid": centroid, "end_tick": end_tick,
            "snap": "16", "src": "other", "lanes": [], "len": 0}


def _seq(pitches, **kw):
    return [_n(p, tick=i * 192, **kw) for i, p in enumerate(pitches)]


class ContourTest(unittest.TestCase):
    def test_rising_scale_visible_slide(self):
        notes = _seq([C4, D4, E4, F4, G4, A4, B4, C5])
        self.assertEqual(lanes.contour_lanes(notes, start_lane=0), [0, 1, 2, 3, 3, 3, 1, 2])
        notes = _seq([C4, D4, E4, F4, G4, A4, B4, C5, B4])
        self.assertEqual(lanes.contour_lanes(notes, start_lane=0)[-1], 1)

    def test_falling_scale_visible_slide(self):
        notes = _seq([C5, B4, A4, G4, F4, E4, D4, C4])
        self.assertEqual(lanes.contour_lanes(notes, start_lane=3), [3, 2, 1, 0, 0, 0, 2, 1])

    def test_single_clamp_then_back_does_not_slide(self):
        notes = _seq([C4, D4, E4, F4, G4, F4])
        self.assertEqual(lanes.contour_lanes(notes, start_lane=0), [0, 1, 2, 3, 3, 2])

    def test_repeated_pitch_same_lane(self):
        notes = _seq([E4, E4, E4, G4, G4])
        out = lanes.contour_lanes(notes)
        self.assertEqual(out[0], out[1])
        self.assertEqual(out[1], out[2])
        self.assertEqual(out[3], out[4])

    def test_isolated_octave_leap_is_plus_two(self):
        notes = _seq([A3, A4, B4, 73], amp=0.8)
        out = lanes.contour_lanes(notes, start_lane=0)
        self.assertEqual(out[1] - out[0], 2)

    def test_alternating_or_quiet_octave_folds(self):
        notes = _seq([A3, A4, A3, A4], amp=0.8)
        out = lanes.contour_lanes(notes)
        self.assertEqual(len(set(out)), 1)
        quiet = [_n(A3, 0, amp=0.8), _n(A4, 192, amp=0.2), _n(B4, 384, amp=0.8)]
        out = lanes.contour_lanes(quiet, start_lane=0)
        self.assertEqual(out[0], out[1])

    def test_compound_interval_reduces_without_fifth_flip(self):
        self.assertEqual(lanes.effective_interval(60, 79, None, None, 0.8, 0.8), 7)
        self.assertEqual(lanes.effective_interval(60, 67, None, None, 0.8, 0.8), 7)
        self.assertEqual(lanes.effective_interval(79, 60, None, None, 0.8, 0.8), -7)
        out = lanes.contour_lanes(_seq([60, 79], amp=0.8), start_lane=0)
        self.assertEqual(out, [0, 2])
        out = lanes.contour_lanes(_seq([60, 67], amp=0.8), start_lane=0)
        self.assertEqual(out, [0, 2])

    def test_centroid_fallback_and_unpitched(self):
        # 440 Hz -> 69, 493.88 Hz -> 71 (+2 semitones = +1 lane)
        notes = [_n(None, 0, centroid=440.0), _n(None, 192, centroid=493.88)]
        self.assertEqual(lanes.contour_lanes(notes, start_lane=1), [1, 2])
        notes = [_n(C4, 0), _n(None, 192), _n(None, 384)]
        self.assertEqual(lanes.contour_lanes(notes, start_lane=1), [1, 1, 1])


class AssignTest(unittest.TestCase):
    def _notes(self):
        strengths = [float((i * 7) % 20 + 1) for i in range(20)]  # 1..20 distinct
        pitches = [60 + (i * 5) % 12 for i in range(20)]
        return [_n(pitches[i], i * 192, strength=strengths[i]) for i in range(20)]

    def test_accent_chords_expert_only_top_decile(self):
        notes = self._notes()
        before = copy.deepcopy(notes)
        out = lanes.assign_lanes(notes, "expert")
        self.assertEqual(notes, before)  # input untouched
        chords = [n for n in out if len(n["lanes"]) == 2]
        self.assertEqual(sorted(n["strength"] for n in chords), [19.0, 20.0])
        for n in out:
            self.assertLessEqual(len(n["lanes"]), 2)
            self.assertIn(n["base_lane"], n["lanes"])
            if len(n["lanes"]) == 2:
                other = [l for l in n["lanes"] if l != n["base_lane"]][0]
                want = n["base_lane"] - 1 if n["base_lane"] == 3 else n["base_lane"] + 1
                self.assertEqual(other, want)
            for l in n["lanes"]:
                self.assertTrue(0 <= l <= 3)
        hard = lanes.assign_lanes(notes, "hard")
        self.assertEqual(sum(1 for n in hard if len(n["lanes"]) == 2), 2)
        for diff in ("medium", "easy"):
            self.assertTrue(all(len(n["lanes"]) == 1 for n in lanes.assign_lanes(notes, diff)))

    def test_sustains(self):
        notes = [_n(C4, 0, end_tick=600), _n(D4, 384, end_tick=500), _n(E4, 768, end_tick=1000),
                 _n(F4, 1152, end_tick=1384), _n(G4, 1500, end_tick=1600)]
        out = lanes.assign_lanes(notes, "medium")
        self.assertEqual(out[0]["len"], 384 - 48)      # cut at next note minus 1/16
        self.assertEqual(out[1]["len"], 0)             # rings <= 1 beat -> tap
        self.assertEqual(out[2]["len"], 1000 - 768 - 48)
        self.assertEqual(out[3]["len"], 1384 - 1152 - 48)
        self.assertEqual(out[4]["len"], 0)
        short = lanes.assign_lanes([_n(C4, 0, end_tick=400), _n(D4, 90)], "expert")
        self.assertEqual(short[0]["len"], 0)           # 90 - 48 = 42 <= 48 -> tap
        for i in range(len(out) - 1):
            self.assertLess(out[i]["len"], out[i + 1]["tick"] - out[i]["tick"])


class MetricsTest(unittest.TestCase):
    def test_direction_match_and_hist(self):
        pitches = [60 if i % 2 == 0 else 62 for i in range(21)]
        base = [1 if i % 2 == 0 else 2 for i in range(21)]
        notes = []
        for i in range(21):
            n = _n(pitches[i], i * 192)
            n["base_lane"] = base[i]
            n["lanes"] = [base[i]]
            notes.append(n)
        # three clamp losses: lane stays put while pitch moves (pairs 4->5, 10->11, 16->17)
        for i in (5, 11, 17):
            notes[i]["base_lane"] = notes[i - 1]["base_lane"]
            notes[i]["lanes"] = [notes[i]["base_lane"]]
            # keep the following pair a valid direction change
            notes[i + 1]["base_lane"] = notes[i]["base_lane"] - 1
            notes[i + 1]["lanes"] = [notes[i + 1]["base_lane"]]
        self.assertAlmostEqual(lanes.direction_match(notes), 17 / 20)
        hist = lanes.lane_step_hist(notes)
        self.assertEqual(len(hist), 4)
        self.assertAlmostEqual(sum(hist), 1.0)


if __name__ == "__main__":
    unittest.main()
