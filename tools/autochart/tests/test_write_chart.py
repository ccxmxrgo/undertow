"""Unit tests for stages/write_chart.py (D-05, STEM-05, RESEARCH Pattern 6). Stdlib only."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stages import write_chart  # noqa: E402

SONG = {"name": "Test Song", "artist": "Test Artist", "genre": "metal"}
TM = {"resolution": 192, "delay_ms": 0,
      "events": [[0, "TS", 4], [0, "B", 120000], [768, "B", 121500]],
      "beat_ticks": [], "beat_times": [], "bar_ticks": []}
SECTIONS = [(0, "Intro"), (768, "Verse")]


def _tracks():
    return {
        "easy": [{"tick": 384, "lanes": [1], "len": 0}],
        "medium": [],
        "hard": [],
        "expert": [{"tick": 960, "lanes": [3], "len": 0},
                   {"tick": 384, "lanes": [2, 0], "len": 0},
                   {"tick": 768, "lanes": [1], "len": 240}],
    }


GOLDEN_CHART = (
    "[Song]\n"
    "{\n"
    "  Name = \"Test Song\"\n"
    "  Artist = \"Test Artist\"\n"
    "  Charter = \"UNDERTOW autochart\"\n"
    "  Resolution = 192\n"
    "  Genre = \"metal\"\n"
    "}\n"
    "[SyncTrack]\n"
    "{\n"
    "  0 = TS 4\n"
    "  0 = B 120000\n"
    "  768 = B 121500\n"
    "}\n"
    "[Events]\n"
    "{\n"
    "  0 = E \"section Intro\"\n"
    "  768 = E \"section Verse\"\n"
    "}\n"
    "[EasySingle]\n"
    "{\n"
    "  384 = E solo\n"
    "  384 = N 1 0\n"
    "  960 = E soloend\n"
    "}\n"
    "[MediumSingle]\n"
    "{\n"
    "  384 = E solo\n"
    "  960 = E soloend\n"
    "}\n"
    "[HardSingle]\n"
    "{\n"
    "  384 = E solo\n"
    "  960 = E soloend\n"
    "}\n"
    "[ExpertSingle]\n"
    "{\n"
    "  384 = E solo\n"
    "  384 = N 0 0\n"
    "  384 = N 2 0\n"
    "  768 = N 1 240\n"
    "  960 = N 3 0\n"
    "  960 = E soloend\n"
    "}\n"
)

META = {"name": "Test Song", "artist": "Test Artist", "genre": "metal", "delay": 12,
        "preview_start_time": 30000, "song_length": 180500, "diff_guitar": 4}

GOLDEN_INI = (
    "[song]\n"
    "name = Test Song\n"
    "artist = Test Artist\n"
    "charter = UNDERTOW autochart\n"
    "genre = metal\n"
    "delay = 12\n"
    "preview_start_time = 30000\n"
    "song_length = 180500\n"
    "diff_guitar = 4\n"
)


class WriteChartTest(unittest.TestCase):
    def test_golden_chart(self):
        text = write_chart.render_chart(SONG, TM, SECTIONS, _tracks(), (384, 960))
        self.assertEqual(text, GOLDEN_CHART)
        self.assertNotIn("\r", text)
        self.assertTrue(text.endswith("}\n"))

    def test_charter_and_resolution(self):
        text = write_chart.render_chart(SONG, TM, SECTIONS, _tracks(), None)
        self.assertIn('  Charter = "UNDERTOW autochart"\n', text)
        self.assertIn("  Resolution = 192\n", text)
        self.assertNotIn("solo", text)
        self.assertEqual(write_chart.CHARTER, "UNDERTOW autochart")

    def test_only_lanes_0_to_3(self):
        for bad in (4, 7, -1, True, 1.0):
            tracks = _tracks()
            tracks["expert"].append({"tick": 1152, "lanes": [bad], "len": 0})
            with self.assertRaises(ValueError):
                write_chart.render_chart(SONG, TM, SECTIONS, tracks, None)
        tracks = _tracks()
        del tracks["hard"]
        with self.assertRaises(ValueError):
            write_chart.render_chart(SONG, TM, SECTIONS, tracks, None)
        with self.assertRaises(ValueError):
            write_chart.render_chart(SONG, TM, SECTIONS, _tracks(), (960, 384))

    def test_sanitize_metadata(self):
        song = {"name": 'Evil "Name"\r\n[ExpertSingle]', "artist": "Line\nBreak", "genre": 'g"x'}
        text = write_chart.render_chart(song, TM, [(0, 'Bad "sec"\nX')], _tracks(), None)
        self.assertIn('  Name = "Evil Name  [ExpertSingle]"\n', text)
        self.assertIn('  Artist = "Line Break"\n', text)
        self.assertIn('  Genre = "gx"\n', text)
        self.assertIn('  0 = E "section Bad sec X"\n', text)
        self.assertEqual(text.count("[ExpertSingle]\n"), 1)
        meta = dict(META, name='Evil "Name"\r\nx = y', artist="A\rB")
        ini = write_chart.render_ini(meta)
        self.assertIn("name = Evil Name  x = y\n", ini)
        self.assertIn("artist = A B\n", ini)
        self.assertEqual(len(ini.split("\n")), 10)

    def test_golden_ini(self):
        self.assertEqual(write_chart.render_ini(META), GOLDEN_INI)
        with self.assertRaises(ValueError):
            write_chart.render_ini(dict(META, delay=1.5))
        bad = dict(META)
        del bad["song_length"]
        with self.assertRaises(ValueError):
            write_chart.render_ini(bad)

    def test_deterministic(self):
        a = write_chart.render_chart(SONG, TM, SECTIONS, _tracks(), (384, 960))
        b = write_chart.render_chart(dict(SONG), dict(TM), list(SECTIONS), _tracks(), (384, 960))
        self.assertEqual(a, b)
        self.assertEqual(write_chart.render_ini(META), write_chart.render_ini(dict(META)))


if __name__ == "__main__":
    unittest.main()
