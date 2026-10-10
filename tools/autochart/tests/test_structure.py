"""Unit tests for stages/structure.py (D-08, SPEC requirement 7, RESEARCH Pattern 7). Stdlib only."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import structure  # noqa: E402

BAR = 768
BARS = [b * BAR for b in range(33)]  # 32 bars plus the end of the last bar


def _notes(per_bar: dict, default=0):
    out = []
    for b in range(32):
        k = per_bar.get(b, default)
        for j in range(k):
            out.append({"tick": BARS[b] + j * (BAR // max(k, 1)), "lanes": [0], "len": 0})
    return out


class NamesTest(unittest.TestCase):
    def test_basic_song(self):
        self.assertEqual(structure.name_sections([0, 1, 2, 1, 2, 3], [0.2, 0.5, 0.9, 0.5, 0.95, 0.1]),
                         ["Intro", "Verse 1", "Chorus 1", "Verse 2", "Chorus 2", "Outro"])

    def test_single_middle_label_and_loud_edges(self):
        names = structure.name_sections([0, 1, 2, 1, 4, 2, 1], [0.1, 0.5, 0.9, 0.5, 0.6, 0.9, 0.2])
        self.assertEqual(names, ["Intro", "Verse 1", "Chorus 1", "Verse 2", "Section 5", "Chorus 2", "Outro"])
        # loud first/last sections are named by the same rules, not Intro/Outro
        names = structure.name_sections([2, 1, 2, 1, 2], [0.9, 0.3, 0.9, 0.3, 0.9])
        self.assertEqual(names, ["Chorus 1", "Verse 1", "Chorus 2", "Verse 2", "Chorus 3"])
        self.assertEqual(structure.name_sections([], []), [])


class SoloTest(unittest.TestCase):
    def test_dense_instrumental_window(self):
        per = {b: 5 for b in range(12, 20)}
        hard = _notes(per, default=1)
        vocals = [b < 12 or b >= 20 for b in range(32)]
        self.assertEqual(structure.pick_solo(hard, hard, BARS, vocals), (BARS[12], BARS[20] - 48))

    def test_prefers_instrumental_then_falls_back(self):
        per = {b: 8 for b in range(2, 10)}
        per.update({b: 5 for b in range(20, 28)})
        hard = _notes(per, default=1)
        vocals = [2 <= b < 10 for b in range(32)]
        self.assertEqual(structure.pick_solo(hard, hard, BARS, vocals), (BARS[20], BARS[28] - 48))
        all_vocal = [True] * 32
        self.assertEqual(structure.pick_solo(hard, hard, BARS, all_vocal), (BARS[2], BARS[10] - 48))
        self.assertEqual(structure.pick_solo(hard, hard, BARS, None), (BARS[2], BARS[10] - 48))

    def test_none_when_too_sparse(self):
        hard = _notes({}, default=1)
        self.assertIsNone(structure.pick_solo(hard, hard, BARS, None))
        # enough on Hard but not on Expert -> None
        dense = _notes({b: 5 for b in range(12, 20)}, default=0)
        self.assertIsNone(structure.pick_solo(dense, dense[:10], BARS, None))

    def test_ties_earliest_and_deterministic(self):
        per = {b: 4 for b in range(4, 8)}
        per.update({b: 4 for b in range(20, 24)})
        hard = _notes(per)
        a = structure.pick_solo(hard, hard, BARS, None)
        self.assertEqual(a, (BARS[4], BARS[8] - 48))
        self.assertEqual(a, structure.pick_solo(hard, hard, BARS, None))


class PreviewTest(unittest.TestCase):
    def test_loudest_section(self):
        self.assertEqual(structure.pick_preview([0, 20000, 41000], [0.1, 0.4, 0.3]), 20000)
        self.assertEqual(structure.pick_preview([0, 20000, 41000], [0.1, 0.4, 0.4]), 20000)

    def test_skips_sections_in_the_first_10_s(self):
        # HRT: the loudest section starts at 2.8 s
        self.assertEqual(structure.pick_preview([2789, 22322, 44649], [0.9, 0.5, 0.6], 161877), 44649)
        self.assertEqual(structure.pick_preview([9999, 10000], [0.9, 0.1], 100000), 10000)

    def test_skips_sections_starting_less_than_30_s_before_the_end(self):
        # Space Synth Wave: the loudest section starts 2.4 s before the end
        starts = [162, 16157, 160142, 176143, 189642]
        rms = [0.1, 0.5, 0.4, 0.8, 0.9]
        self.assertEqual(structure.pick_preview(starts, rms, 192014), 160142)
        self.assertEqual(structure.pick_preview([20000, 70000], [0.1, 0.9], 100000), 70000)
        self.assertEqual(structure.pick_preview([20000, 70001], [0.1, 0.9], 100000), 20000)

    def test_fallback_is_30_percent_clamped_to_30_s_of_audio(self):
        self.assertEqual(structure.pick_preview([], [], 100000), 30000)
        self.assertEqual(structure.pick_preview([500, 95000], [0.5, 0.9], 100000), 30000)
        # 30% of 40 s = 12 s, but only 10 s may start before the 30 s tail
        self.assertEqual(structure.pick_preview([1000], [0.5], 40000), 10000)
        self.assertEqual(structure.pick_preview([1000], [0.5], 20000), 0)

    def test_without_song_length_only_the_intro_rule_applies(self):
        self.assertEqual(structure.pick_preview([2000, 50000], [0.9, 0.1]), 50000)
        self.assertEqual(structure.pick_preview([0, 20000, 41000], [0.1, 0.4, 0.3]), 20000)


if __name__ == "__main__":
    unittest.main()
