"""Tests for the pack entry points `autochart.py job <job.json>` and `autochart.py selftest` (Phase 2.2.2
plan 05). Every failing run must print only protocol lines (one ASCII JSON object each) on stdout and exit 2.
Stdlib only: the commands run as children of this interpreter (`-I -B`, argument lists, temp dirs) and fail
before any heavy import, so the suite stays fast under plain python too."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
AUTOCHART = HERE / "autochart.py"
sys.path.insert(0, str(HERE))

import autochart  # noqa: E402
from stages.errors import AutochartError  # noqa: E402
from stages.job import JobError  # noqa: E402


def run_cmd(*argv, timeout=120):
    t0 = time.perf_counter()
    r = subprocess.run([sys.executable, "-I", "-B", str(AUTOCHART), *argv], stdin=subprocess.DEVNULL,
                       capture_output=True, timeout=timeout)
    return r, time.perf_counter() - t0


def events(stdout: bytes) -> list:
    """Every non-empty stdout line parsed as JSON; fails the test on a non-JSON or non-ASCII line."""
    out = []
    for raw in stdout.splitlines():
        if not raw.strip():
            continue
        raw.decode("ascii")  # protocol lines are ASCII only
        ev = json.loads(raw)
        if not isinstance(ev, dict) or "ev" not in ev:
            raise AssertionError(f"not a protocol event: {raw!r}")
        out.append(ev)
    return out


class _Tmp(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = Path(self._td.name).resolve()

    def tearDown(self):
        self._td.cleanup()

    def write_job(self, **over) -> Path:
        src = self.tmp / "song.wav"
        src.write_bytes(b"RIFF0000WAVE")
        for d in ("songs", "ac/work", "models/hf", "models/torch"):
            (self.tmp / d).mkdir(parents=True, exist_ok=True)
        job = {"version": 1, "src": str(src), "name": "Test Song", "artist": "Me", "genre": "Autochart",
               "mode": "auto", "stem": "other", "target_nps": 3.5, "songs_root": str(self.tmp / "songs"),
               "work_root": str(self.tmp / "ac" / "work"), "models_root": str(self.tmp / "models"),
               "threads": 2, "replace": False}
        job.update(over)
        jobs = self.tmp / "ac" / "work" / "jobs" / "1"
        jobs.mkdir(parents=True, exist_ok=True)
        p = jobs / "job.json"
        p.write_text(json.dumps(job), encoding="utf-8")
        return p


class JobCommandTest(_Tmp):
    def assert_single_error(self, r, code):
        self.assertEqual(r.returncode, 2, r.stderr.decode("utf-8", "replace"))
        evs = events(r.stdout)
        self.assertEqual(len(evs), 1, evs)
        self.assertEqual(evs[0]["ev"], "error")
        self.assertEqual(evs[0]["code"], code, evs[0])
        self.assertIn("msg", evs[0])
        self.assertIn("stage", evs[0])
        self.assertIn("log", evs[0])
        return evs[0]

    def test_missing_job_file_is_bad_job(self):
        r, _ = run_cmd("job", str(self.tmp / "missing.json"))
        self.assert_single_error(r, "bad_job")

    def test_opus_source_is_bad_type(self):
        opus = self.tmp / "x.opus"
        opus.write_bytes(b"OggS")
        r, _ = run_cmd("job", str(self.write_job(src=str(opus))))
        self.assert_single_error(r, "bad_type")

    def test_work_root_outside_ac_root_is_bad_job(self):
        other = self.tmp / "elsewhere"
        other.mkdir()
        p = self.write_job(work_root=str(other))
        r, _ = run_cmd("job", str(p), "--ac-root", str(self.tmp / "ac"))
        ev = self.assert_single_error(r, "bad_job")
        self.assertIn("outside", ev["msg"])

    def test_error_names_the_log_and_library_output_stays_off_stdout(self):
        p = self.write_job(mode="nonsense")
        r, _ = run_cmd("job", str(p))
        ev = self.assert_single_error(r, "bad_job")
        self.assertEqual(Path(ev["log"]), p.parent / "log.txt")
        self.assertTrue((p.parent / "log.txt").is_file())

    def test_bad_bp_python_is_bad_job(self):
        p = self.write_job(bp_python=str(self.tmp / "nope" / "python.exe"))
        r, _ = run_cmd("job", str(p))
        self.assert_single_error(r, "bad_job")


class SubcommandsTest(unittest.TestCase):
    def test_help_lists_all_subcommands(self):
        r, _ = run_cmd("-h")
        self.assertEqual(r.returncode, 0)
        text = r.stdout.decode("utf-8", "replace")
        self.assertIn("{analyze,chart,extract,job,selftest}", text)


class SelftestCommandTest(_Tmp):
    def test_models_root_without_hf_fails_fast(self):
        (self.tmp / "models" / "torch").mkdir(parents=True)
        r, secs = run_cmd("selftest", "--models-root", str(self.tmp / "models"))
        self.assertEqual(r.returncode, 2, r.stderr.decode("utf-8", "replace"))
        evs = events(r.stdout)
        self.assertEqual([e["ev"] for e in evs], ["error"])
        self.assertEqual(evs[0]["code"], "selftest")
        self.assertLess(secs, 30.0)


class ErrorMappingTest(unittest.TestCase):
    def test_codes(self):
        m = autochart.job_error_code
        self.assertEqual(m(JobError("too_long", "x")), "too_long")
        self.assertEqual(m(AutochartError("decode", "x", code="bad_rate")), "bad_rate")
        self.assertEqual(m(AutochartError("beats", "beat_this found only 3 beats")), "no_beats")
        self.assertEqual(m(AutochartError("sections", "only 2 bar lines inside the audio")), "no_beats")
        self.assertEqual(m(AutochartError("stem_rank", "no stem produced Expert notes")), "no_notes")
        self.assertEqual(m(AutochartError("chart", "only 12 Expert notes from stem bass")), "no_notes")
        self.assertEqual(m(AutochartError("chart", "no 4-8 bar window with 16 notes")), "no_notes")
        self.assertEqual(m(AutochartError("separate", "demucs failed")), "internal")
        self.assertEqual(m(AutochartError("decode", "x", code="not_a_code")), "internal")

    def test_dll_errors(self):
        d = autochart.is_dll_error
        self.assertTrue(d(ImportError("DLL load failed while importing _C: The specified module could not be found.")))
        e = OSError("[WinError 126] The specified module could not be found")
        self.assertTrue(d(e))
        w = OSError(22, "bad")
        w.winerror = 193
        self.assertTrue(d(w))
        self.assertFalse(d(ImportError("No module named foo")))
        self.assertFalse(d(OSError(2, "No such file")))


if __name__ == "__main__":
    unittest.main()
