"""Unit tests for stages/pitch_bp.py pitch_at / attach_pitch (RESEARCH "Chosen Pipeline" step 5).
Stdlib only: runs under plain `python -I -B -m unittest discover -s tools/autochart/tests -p "test_pitch_pick.py"`."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import pitch_bp  # noqa: E402

# [start, end, midi, amp]
NOTES = [
    [1.00, 1.40, 60, 0.5],
    [1.03, 1.20, 67, 0.4],   # higher pitch starting within 50 ms of 1.0
    [2.00, 3.00, 55, 0.6],   # long note sounding through 2.5
    [2.40, 2.45, 50, 0.3],   # short, lower note that has ended before 2.5 + 30 ms
    [4.00, 4.10, 72, 0.7],
]


class PitchAtTest(unittest.TestCase):
    def test_highest_starting_within_window(self):
        self.assertEqual(pitch_bp.pitch_at(1.0, NOTES), (67, 0.4, 1.20))
        self.assertEqual(pitch_bp.pitch_at(0.96, NOTES), (60, 0.5, 1.40))  # 67 starts 70 ms later

    def test_fallback_sounding_at_plus_30ms(self):
        self.assertEqual(pitch_bp.pitch_at(2.5, NOTES), (55, 0.6, 3.00))

    def test_none_when_nothing(self):
        self.assertEqual(pitch_bp.pitch_at(3.5, NOTES), (None, None, None))
        self.assertEqual(pitch_bp.pitch_at(1.0, []), (None, None, None))

    def test_window_edge(self):
        self.assertEqual(pitch_bp.pitch_at(4.05, NOTES)[0], 72)   # exactly 50 ms
        self.assertEqual(pitch_bp.pitch_at(3.94, NOTES)[0], None)  # 60 ms early, nothing sounding


class AttachTest(unittest.TestCase):
    def test_fills_and_preserves_order(self):
        recs = [{"t": 4.0, "src": "other", "pitch": None, "amp": None, "off_t": None},
                {"t": 3.5, "src": "other", "pitch": None, "amp": None, "off_t": None},
                {"t": 1.0, "src": "other", "pitch": None, "amp": None, "off_t": None}]
        out = pitch_bp.attach_pitch(recs, NOTES)
        self.assertEqual([r["t"] for r in out], [4.0, 3.5, 1.0])
        self.assertEqual((out[0]["pitch"], out[0]["amp"], out[0]["off_t"]), (72, 0.7, 4.10))
        self.assertEqual((out[1]["pitch"], out[1]["amp"], out[1]["off_t"]), (None, None, None))
        self.assertEqual(out[2]["pitch"], 67)
        self.assertEqual(out[2]["src"], "other")

    def test_does_not_mutate_input(self):
        recs = [{"t": 1.0, "pitch": None, "amp": None, "off_t": None}]
        pitch_bp.attach_pitch(recs, NOTES)
        self.assertIsNone(recs[0]["pitch"])


if __name__ == "__main__":
    unittest.main()
