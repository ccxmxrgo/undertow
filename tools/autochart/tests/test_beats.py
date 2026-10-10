"""Unit tests for stages/beats.py (RESEARCH "Chosen Pipeline" step 3, Pattern 4, Pitfalls 2-3).
numpy allowed; run with venv A:
  build/autochart/venvA/Scripts/python.exe -I -B -m unittest discover -s tools/autochart/tests -p "test_beats.py" -v
"""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import beats as B  # noqa: E402


def _grid(n=200, p=0.3, start=1.0):
    return start + p * np.arange(n)


def _drifting(n=200, start=0.5):
    out = [start]
    for i in range(n - 1):
        out.append(out[-1] + 0.69 + 0.02 * i / (n - 2))
    return np.array(out)


class RepairTest(unittest.TestCase):
    def test_missing_beats_reinserted(self):
        g = _grid()
        drop = [10, 40, 41, 120, 170]
        b = np.delete(g, drop)
        out, repairs = B.repair_beats(b)
        self.assertEqual(len(out), len(g))
        self.assertEqual(repairs, 5)
        np.testing.assert_allclose(out, g, atol=1e-9)

    def test_half_beats_dropped(self):
        g = _grid()
        extra = g[[5, 50, 90, 130, 180]] + 0.15
        b = np.sort(np.concatenate([g, extra]))
        out, repairs = B.repair_beats(b)
        self.assertEqual(repairs, 5)
        np.testing.assert_allclose(out, g, atol=1e-9)


class ConstantTest(unittest.TestCase):
    def test_jittered_grid_is_constant(self):
        jit = np.where(np.arange(200) % 2 == 0, 0.001, -0.001)
        self.assertTrue(B.is_constant(_grid() + jit))

    def test_drifting_tempo_is_not_constant(self):
        self.assertFalse(B.is_constant(_drifting()))


class PhaseTest(unittest.TestCase):
    def test_constant_global_shift_keeps_tempo(self):
        g = _grid()
        jit = np.where(np.arange(200) % 2 == 0, 0.001, -0.001)
        beats = g + jit
        onsets = g - 0.0065
        out = B.phase_correct(beats, onsets, constant=True)
        np.testing.assert_allclose(out - beats, -0.0065, atol=1e-4)
        self.assertTrue(B.is_constant(out))
        ibi = np.diff(out)
        self.assertLess(ibi.max() - ibi.min(), 0.0021)  # no wobble beyond the input jitter

    def test_local_shift_ignores_far_onsets(self):
        beats = _drifting()
        near = beats - 0.0065
        far = beats[::3] + 0.05  # 50 ms after a beat (> 30 ms window, nearer the beat than a 1/16)
        onsets = np.sort(np.concatenate([near, far]))
        out = B.phase_correct(beats, onsets, constant=False)
        want = B.smooth_beats(beats - 0.0065)
        np.testing.assert_allclose(out, want, atol=1e-4)

    def test_smooth_beats_keeps_a_line(self):
        g = _grid()
        np.testing.assert_allclose(B.smooth_beats(g), g, atol=1e-9)


class DownbeatTest(unittest.TestCase):
    def test_downbeats_snap_to_nearest_refined_beat(self):
        beats = _grid()
        downs = beats[::4][:20] + 0.012
        out = B.snap_downbeats(downs, beats)
        np.testing.assert_allclose(out, beats[::4][:20], atol=1e-12)

    def test_downbeats_deduplicated(self):
        beats = _grid()
        out = B.snap_downbeats(np.array([beats[4] - 0.01, beats[4] + 0.01, beats[8]]), beats)
        np.testing.assert_allclose(out, [beats[4], beats[8]], atol=1e-12)


if __name__ == "__main__":
    unittest.main()
