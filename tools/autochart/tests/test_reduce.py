"""Unit tests for stages/reduce.py (SPEC requirement 6, RESEARCH Pattern 5). Stdlib only."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import lanes, reduce  # noqa: E402

RES = 192
BAR = 4 * RES
N_BARS = 64
TICKS_PER_S = 384  # 120 BPM: one beat = 0.5 s = 192 ticks

# 8 notes per bar; offsets in ticks inside the bar
PATTERNS = {
    "A": [0, 96, 192, 288, 384, 480, 576, 672],          # straight 8ths
    "B": [0, 48, 96, 192, 384, 432, 480, 576],           # beats + 16ths
    "C": [0, 64, 128, 192, 384, 576, 640, 704],          # triplets
    "D": [0, 96, 192, 240, 288, 384, 576, 672],          # one 16th
    "E": [0, 48, 96, 144, 192, 240, 288, 336],           # 16th run: 8 in 1 s
}
CYCLE = "ABCDABCE"


def _tm():
    return {"resolution": RES, "bar_ticks": [b * BAR for b in range(N_BARS + 1)],
            "beat_ticks": [b * RES for b in range(N_BARS * 4 + 1)]}


def _expert():
    raw = []
    i = 0
    for bar in range(N_BARS):
        for off in PATTERNS[CYCLE[bar % len(CYCLE)]]:
            tick = bar * BAR + off
            strength = 0.2 + ((i * 37) % 101) / 101.0 * 0.8
            pitch = 60 + [0, 2, 4, 5, 7, 5, 4, 2, 0, -3, -5, 0][(i * 5) % 12]
            end = tick + 300 if i % 5 == 0 else None
            raw.append({"tick": tick, "t": tick / TICKS_PER_S, "t_onset": tick / TICKS_PER_S,
                        "strength": strength, "pitch": float(pitch), "amp": 0.8,
                        "centroid": None, "end_tick": end, "snap": "16", "src": "other",
                        "lanes": [], "len": 0})
            i += 1
    return lanes.assign_lanes(raw, "expert", resolution=RES)


def _max_per_s(notes):
    ts = sorted(n["t"] for n in notes)
    best = 0
    j = 0
    for i, t in enumerate(ts):
        while j < len(ts) and ts[j] < t + 1.0 - 1e-9:
            j += 1
        best = max(best, j - i)
    return best


class ReduceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tm = _tm()
        cls.expert = _expert()
        cls.ticks = {n["tick"] for n in cls.expert}
        cls.red = {d: reduce.reduce(cls.expert, d, cls.tm) for d in ("hard", "medium", "easy")}

    def test_subset_of_expert_ticks(self):
        for d, notes in self.red.items():
            self.assertTrue(notes, d)
            for n in notes:
                self.assertIn(n["tick"], self.ticks, d)
            self.assertEqual([n["tick"] for n in notes], sorted({n["tick"] for n in notes}), d)

    def test_hard(self):
        hard = self.red["hard"]
        self.assertLessEqual(_max_per_s(hard), 7)
        self.assertGreater(_max_per_s(self.expert), 7)  # the cap actually had work to do
        self.assertGreaterEqual(reduce.keep_share(hard, self.expert), 0.90)
        self.assertTrue(all(len(n["lanes"]) <= 2 for n in hard))
        ex_chords = sum(1 for n in self.expert if len(n["lanes"]) >= 2)
        hard_chords = sum(1 for n in hard if len(n["lanes"]) >= 2)
        self.assertGreater(ex_chords, 0)
        self.assertTrue(0.40 <= hard_chords / ex_chords <= 0.60, (hard_chords, ex_chords))

    def test_medium(self):
        med = self.red["medium"]
        self.assertTrue(all(n["tick"] % 96 == 0 for n in med))
        self.assertLessEqual(_max_per_s(med), 5)
        share = reduce.keep_share(med, self.expert)
        self.assertTrue(0.65 <= share <= 0.75, share)
        chords = [n for n in med if len(n["lanes"]) >= 2]
        self.assertLessEqual(len(chords), 0.03 * len(med))
        bars = set(self.tm["bar_ticks"])
        for n in chords:
            self.assertEqual(len(n["lanes"]), 2)
            self.assertIn(n["tick"], bars)

    def test_easy(self):
        easy = self.red["easy"]
        self.assertTrue(all(n["tick"] % 96 == 0 for n in easy))
        gaps = [b["tick"] - a["tick"] for a, b in zip(easy, easy[1:])]
        self.assertGreaterEqual(min(gaps), 192)
        self.assertLessEqual(_max_per_s(easy), 4)
        share = reduce.keep_share(easy, self.expert)
        self.assertTrue(0.45 <= share <= 0.55, share)
        for n in easy:
            self.assertEqual(len(n["lanes"]), 1)
            self.assertTrue(0 <= n["lanes"][0] <= 2)
        by_tick = {n["tick"]: n for n in self.expert}
        sustained = [n for n in easy if by_tick[n["tick"]]["len"] > 0]
        self.assertTrue(sustained)
        for n in sustained:
            self.assertGreater(n["len"], 0)

    def test_easy_lane_map(self):
        mapped = reduce.reduce(self.expert, "easy", self.tm,
                               easy_lane_map={0: 0, 1: 1, 2: 2, 3: None})
        by_tick = {n["tick"]: n for n in self.expert}
        self.assertTrue(mapped)
        for n in mapped:
            self.assertNotEqual(by_tick[n["tick"]]["base_lane"], 3)
            self.assertEqual(n["lanes"], [by_tick[n["tick"]]["base_lane"]])

    def test_deterministic_and_pure(self):
        before = copy.deepcopy(self.expert)
        for d in ("hard", "medium", "easy"):
            a = reduce.reduce(self.expert, d, self.tm)
            b = reduce.reduce(self.expert, d, self.tm)
            self.assertEqual(a, b)
        self.assertEqual(self.expert, before)

    def test_sparse_grid_keeps_all_candidates(self):
        # 16th-heavy input: only a few 1/8-grid notes exist; Medium keeps them all, nothing off-grid
        ex = [n for n in self.expert if n["tick"] % 96 != 0 or n["tick"] % BAR == 0]
        med = reduce.reduce(ex, "medium", self.tm)
        cands = [n for n in ex if n["tick"] % 96 == 0]
        self.assertEqual(len(med), len(cands))
        self.assertTrue(all(n["tick"] % 96 == 0 for n in med))


if __name__ == "__main__":
    unittest.main()
