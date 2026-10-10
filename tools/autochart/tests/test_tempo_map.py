"""Unit tests for stages/tempo_map.py (SPEC requirement 2, RESEARCH Pattern 1). Stdlib only."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import tempo_map  # noqa: E402


def _bs(tm):
    return [e for e in tm["events"] if e[1] == "B"]


def _ts(tm):
    return [e for e in tm["events"] if e[1] == "TS"]


def _drifting_beats(start=0.5, count=200):
    beats = [start]
    for i in range(count - 1):
        ibi = 0.69 + 0.02 * i / (count - 2)
        zig = 0.001 if i % 2 == 0 else -0.001
        beats.append(beats[-1] + ibi + zig)
    return beats


class TempoMapTest(unittest.TestCase):
    def test_constant_tempo_lead_in(self):
        beats = [1.0 + 0.5 * i for i in range(64)]
        downbeats = beats[::4]
        tm = tempo_map.build_tempo_map(beats, downbeats, constant_tempo=True)
        self.assertEqual(tm["resolution"], 192)
        self.assertEqual(tm["delay_ms"], 0)
        self.assertIn(0, [e[0] for e in _bs(tm)])
        self.assertEqual(tm["beat_ticks"][0], 384)
        self.assertLessEqual(len(_bs(tm)), 2)
        self.assertEqual(len(tm["beat_ticks"]), len(beats))
        for k, t in zip(tm["beat_ticks"], beats):
            self.assertAlmostEqual(tempo_map.tick_to_sec(tm, k), t, delta=1e-6)
        self.assertEqual(tm["bar_ticks"][0], 384)
        self.assertEqual(tm["bar_ticks"][1], 384 + 4 * 192)

    def test_sea_shanty_no_lead_in_uses_delay(self):
        beats = [0.06 + 0.3 * i for i in range(40)]
        tm = tempo_map.build_tempo_map(beats, beats[::4], constant_tempo=False)
        self.assertEqual(tm["beat_ticks"][0], 0)
        self.assertEqual(tm["delay_ms"], 60)
        self.assertAlmostEqual(tempo_map.tick_to_sec(tm, 0), 0.06, delta=1e-9)
        for k, t in zip(tm["beat_ticks"], beats):
            self.assertAlmostEqual(tempo_map.tick_to_sec(tm, k), t, delta=5e-6)

    def test_invisible_three_beat_lead_in(self):
        beats = [1.44 + 0.52 * i for i in range(40)]
        tm = tempo_map.build_tempo_map(beats, beats[::4], constant_tempo=False)
        self.assertEqual(tm["delay_ms"], 0)
        b0 = [e for e in _bs(tm) if e[0] == 0]
        self.assertEqual(b0, [[0, "B", 125000]])
        self.assertEqual(tm["beat_ticks"][0], 576)
        self.assertAlmostEqual(tempo_map.tick_to_sec(tm, 576), 1.44, delta=1e-9)

    def test_drifting_beats_error_diffusion(self):
        beats = _drifting_beats()
        tm = tempo_map.build_tempo_map(beats, beats[::4], constant_tempo=False)
        bs = _bs(tm)
        db_tick = tm["beat_ticks"][0]
        per_beat = [e for e in bs if e[0] >= db_tick]
        self.assertEqual([e[0] for e in per_beat], tm["beat_ticks"])  # one B on every beat
        # Integer milli-BPM limits a single beat to half a milli-BPM step: 30000 / mb^2 s
        # (about 4.1 us at 86 BPM). Error diffusion keeps every beat inside that bound (no drift).
        bound = max(30000.0 / (e[2] ** 2) for e in per_beat) + 1e-9
        errs = [abs(tempo_map.tick_to_sec(tm, k) - t) for k, t in zip(tm["beat_ticks"], beats)]
        self.assertLessEqual(max(errs), bound)
        self.assertLess(max(errs), 0.000005)
        self.assertLessEqual(errs[-1], 0.000005)
        self.assertEqual(tm["beat_times"], [tempo_map.tick_to_sec(tm, k) for k in tm["beat_ticks"]])

    def test_time_signature_from_downbeats(self):
        beats = [0.5 + 0.5 * i for i in range(40)]
        # bars: 4 4 3 3 4 4 4 ... -> TS 3 at the first 3-bar, TS 4 when 4-beat bars resume
        idx = [0, 4, 8, 11, 14, 18, 22, 26, 30, 34]
        tm = tempo_map.build_tempo_map(beats, [beats[i] for i in idx], constant_tempo=False)
        base = tm["beat_ticks"][0]
        ts = _ts(tm)
        self.assertEqual(ts[0][0], 0)
        self.assertIn([base + 8 * 192, "TS", 3], ts)
        self.assertIn([base + 14 * 192, "TS", 4], ts)
        self.assertEqual(tm["bar_ticks"][:6], [base + i * 192 for i in (0, 4, 8, 11, 14, 18)])
        # TS sorts before B at the same tick
        for a, b in zip(tm["events"], tm["events"][1:]):
            self.assertLessEqual(a[0], b[0])
            if a[0] == b[0]:
                self.assertFalse(a[1] == "B" and b[1] == "TS")

        # a single odd bar changes nothing
        idx2 = [0, 4, 8, 11, 15, 19, 23, 27, 31, 35]
        tm2 = tempo_map.build_tempo_map(beats, [beats[i] for i in idx2], constant_tempo=False)
        base2 = tm2["beat_ticks"][0]
        self.assertEqual([e for e in _ts(tm2) if e[0] >= base2 and e[2] != 4], [])

    def test_bpm_range_and_round_trip(self):
        for beats, const in ((_drifting_beats(), False), ([0.06 + 0.3 * i for i in range(40)], True),
                             ([1.44 + 0.52 * i for i in range(40)], False),
                             ([2.0 + 0.02 * i for i in range(50)], False)):
            tm = tempo_map.build_tempo_map(beats, beats[::4], constant_tempo=const)
            for e in _bs(tm):
                self.assertIsInstance(e[2], int)
                self.assertGreaterEqual(e[2], 1000)
                self.assertLessEqual(e[2], 2000000)
            for k in list(range(0, 192 * 60, 37)) + tm["beat_ticks"]:
                self.assertAlmostEqual(tempo_map.sec_to_tick(tm, tempo_map.tick_to_sec(tm, k)), k, delta=1e-6)

    def test_deterministic(self):
        beats = _drifting_beats()
        a = tempo_map.build_tempo_map(beats, beats[::4], constant_tempo=False)
        b = tempo_map.build_tempo_map(list(beats), list(beats[::4]), constant_tempo=False)
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
