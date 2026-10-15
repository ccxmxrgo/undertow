"""Unit tests for stages/job.py (Phase 2.2.2 plan 04: job validation, work-dir cache keys, slug
collisions, atomic install, FLAC -> WAV, progress emitter). Stdlib only (the FLAC test needs soundfile
and numpy, and is skipped without them)."""
import errno
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

from stages import job  # noqa: E402
from stages.errors import AutochartError  # noqa: E402

GODOT_CODES = {"bad_job", "bad_type", "not_found", "too_big", "too_short", "too_long", "bad_rate",
               "decode", "no_beats", "no_notes", "exists", "disk", "memory", "selftest", "internal",
               "crash", "start", "vcredist"}


class _Tmp(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = Path(self._td.name).resolve()

    def tearDown(self):
        self._td.cleanup()


class CodesTest(unittest.TestCase):
    def test_codes_equal_godot_error_text_keys(self):
        self.assertEqual(set(job.CODES), GODOT_CODES)

    def test_job_error(self):
        e = job.JobError("too_big", "big")
        self.assertIsInstance(e, AutochartError)
        self.assertEqual((e.code, e.stage, e.message), ("too_big", "job", "big"))
        self.assertEqual(job.JobError("disk", "x", stage="install").stage, "install")

    def test_constants(self):
        self.assertEqual(job.PACK_MAX_S, 600.0)
        self.assertEqual(job.MAX_BYTES, 200 * 1024 * 1024)

    def test_import_is_stdlib_only(self):
        code = ("import sys; sys.path.insert(0, sys.argv[1]); import stages.job; "
                "print(any(m in sys.modules for m in ('numpy', 'soundfile', 'torch')))")
        r = subprocess.run([sys.executable, "-I", "-B", "-c", code, str(HERE)],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "False")


class LoadJobTest(_Tmp):
    def setUp(self):
        super().setUp()
        self.ac = self.tmp / "ac"
        self.songs = self.tmp / "songs"
        self.work = self.ac / "work"
        self.models = self.ac / "v1" / "models"
        for d in (self.songs, self.work, self.models / "hf", self.models / "torch"):
            d.mkdir(parents=True)
        self.src = self.tmp / "music" / "My Song.mp3"
        self.src.parent.mkdir()
        self.src.write_bytes(b"ID3fake")

    def _job(self, **over):
        j = {"version": 1, "src": str(self.src), "name": "My Song", "artist": "Me", "genre": "Autochart",
             "mode": "auto", "stem": "other", "target_nps": 3.5, "songs_root": str(self.songs),
             "work_root": str(self.work), "models_root": str(self.models), "threads": 4,
             "replace": False}
        j.update(over)
        for k, v in list(j.items()):
            if v is _DROP:
                del j[k]
        return j

    def _write(self, j, raw=None):
        p = self.tmp / "job.json"
        p.write_text(raw if raw is not None else json.dumps(j), encoding="utf-8")
        return p

    def _code(self, j=None, raw=None, ac=True):
        with self.assertRaises(job.JobError) as cm:
            job.load_job(self._write(j, raw), self.ac if ac else None)
        return cm.exception.code

    def test_valid(self):
        r = job.load_job(self._write(self._job()), self.ac)
        self.assertEqual(r["src"], self.src.resolve())
        self.assertIsInstance(r["songs_root"], Path)
        self.assertEqual(r["songs_root"], self.songs.resolve())
        self.assertEqual(r["work_root"], self.work.resolve())
        self.assertEqual(r["models_root"], self.models.resolve())
        self.assertEqual((r["name"], r["artist"], r["mode"], r["stem"]), ("My Song", "Me", "auto", "other"))
        self.assertEqual(r["threads"], 4)
        self.assertEqual(r["target_nps"], 3.5)
        self.assertIs(r["replace"], False)
        self.assertEqual(r["raw"]["src"], str(self.src))

    def test_missing_file_and_bad_json(self):
        with self.assertRaises(job.JobError) as cm:
            job.load_job(self.tmp / "nope.json", self.ac)
        self.assertEqual(cm.exception.code, "bad_job")
        self.assertEqual(self._code(raw="{not json"), "bad_job")
        self.assertEqual(self._code(raw="[1, 2]"), "bad_job")

    def test_version(self):
        self.assertEqual(self._code(self._job(version=2)), "bad_job")
        self.assertEqual(self._code(self._job(version=True)), "bad_job")
        self.assertEqual(self._code(self._job(version=_DROP)), "bad_job")

    def test_src_missing(self):
        self.assertEqual(self._code(self._job(src=str(self.tmp / "gone.mp3"))), "not_found")

    def test_bad_types(self):
        for ext in (".opus", ".m4a", ".aac"):
            f = self.tmp / f"x{ext}"
            f.write_bytes(b"x")
            self.assertEqual(self._code(self._job(src=str(f))), "bad_type", ext)

    def test_too_big(self):
        with mock.patch.object(job, "MAX_BYTES", 4):
            self.assertEqual(self._code(self._job()), "too_big")

    def test_name(self):
        self.assertEqual(self._code(self._job(name="   ")), "bad_job")
        self.assertEqual(self._code(self._job(name="x" * 121)), "bad_job")
        self.assertEqual(self._code(self._job(name=5)), "bad_job")
        self.assertEqual(self._code(self._job(artist="a" * 121)), "bad_job")

    def test_mode_stem_nps(self):
        self.assertEqual(self._code(self._job(mode="drums")), "bad_job")
        self.assertEqual(self._code(self._job(stem="guitar")), "bad_job")
        self.assertEqual(self._code(self._job(target_nps=0.4)), "bad_job")
        self.assertEqual(self._code(self._job(target_nps=8.5)), "bad_job")
        self.assertEqual(self._code(self._job(target_nps="3")), "bad_job")

    def test_roots(self):
        self.assertEqual(self._code(self._job(songs_root=str(self.tmp / "nosongs"))), "bad_job")
        self.assertEqual(self._code(self._job(work_root=str(self.tmp / "nowork"))), "bad_job")
        outside = self.tmp / "elsewhere"
        outside.mkdir()
        self.assertEqual(self._code(self._job(work_root=str(outside))), "bad_job")
        self.assertEqual(self._code(self._job(songs_root="relative/songs")), "bad_job")

    def test_ac_root_none_skips_containment(self):
        outside = self.tmp / "elsewhere"
        outside.mkdir()
        r = job.load_job(self._write(self._job(work_root=str(outside))), None)
        self.assertEqual(r["work_root"], outside.resolve())

    def test_models_layout(self):
        bare = self.tmp / "models_bare"
        (bare / "hf").mkdir(parents=True)
        self.assertEqual(self._code(self._job(models_root=str(bare))), "bad_job")

    def test_threads_and_replace(self):
        for t in (0, 65, 2.5, True, "4"):
            self.assertEqual(self._code(self._job(threads=t)), "bad_job", t)
        self.assertEqual(self._code(self._job(replace="yes")), "bad_job")


_DROP = object()


class WorkDirTest(_Tmp):
    def test_work_dir_for(self):
        self.assertEqual(job.work_dir_for(self.tmp, "abcdef0123456789ffff"), self.tmp / "w_abcdef0123456789")

    def test_work_dir_rejects_non_hex(self):
        with self.assertRaises(ValueError):
            job.work_dir_for(self.tmp, "../../etc/passwd_xx")

    def test_analyzed_marker(self):
        w = self.tmp / "w"
        w.mkdir()
        sha = "a" * 64
        self.assertFalse(job.is_analyzed(w, sha))
        job.mark_analyzed(w, sha)
        self.assertTrue(job.is_analyzed(w, sha))
        self.assertFalse(job.is_analyzed(w, "b" * 64))
        self.assertEqual([p.name for p in w.iterdir()], ["analyze_done.json"])

    def test_marker_written_via_replace(self):
        w = self.tmp / "w"
        w.mkdir()
        with mock.patch.object(job.os, "replace", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                job.mark_analyzed(w, "c" * 64)
        self.assertFalse((w / "analyze_done.json").exists())
        self.assertFalse(job.is_analyzed(w, "c" * 64))

    def test_corrupt_marker(self):
        w = self.tmp / "w"
        w.mkdir()
        (w / "analyze_done.json").write_text("{", encoding="utf-8")
        self.assertFalse(job.is_analyzed(w, "a" * 64))

    def test_touch(self):
        w = self.tmp / "w"
        w.mkdir()
        job.touch(w)
        doc = json.loads((w / "last_used.json").read_text(encoding="utf-8"))
        self.assertGreater(doc["t"], 0)


class SlugTest(_Tmp):
    def test_unique_slug(self):
        self.assertEqual(job.unique_slug(self.tmp, "song", False), "song")
        (self.tmp / "song").mkdir()
        self.assertEqual(job.unique_slug(self.tmp, "song", False), "song_2")
        (self.tmp / "song_2").mkdir()
        self.assertEqual(job.unique_slug(self.tmp, "song", False), "song_3")
        self.assertEqual(job.unique_slug(self.tmp, "song", True), "song")
        for i in range(3, 100):
            (self.tmp / f"song_{i}").mkdir()
        with self.assertRaises(job.JobError) as cm:
            job.unique_slug(self.tmp, "song", False)
        self.assertEqual(cm.exception.code, "exists")

    def test_bad_slug(self):
        for s in ("..", "a/b", "", "A", ".tmp_x"):
            with self.assertRaises(job.JobError):
                job.unique_slug(self.tmp, s, False)


class InstallTest(_Tmp):
    def setUp(self):
        super().setUp()
        self.songs = self.tmp / "songs"
        self.songs.mkdir()
        self.work = self.tmp / "work" / "w_0123"
        self.work.mkdir(parents=True)

    def _out(self, tag="new"):
        out = self.work / "out"
        out.mkdir()
        (out / "notes.chart").write_text(f"[Song]\n{tag}\n", encoding="utf-8")
        (out / "song.ini").write_text(f"[song]\nname = {tag}\n", encoding="utf-8")
        (out / "song.mp3").write_bytes(tag.encode() * 10)
        return out

    def _chart_folders(self):
        return sorted(p.name for p in self.songs.iterdir() if (p / "notes.chart").exists())

    def test_same_volume(self):
        out = self._out()
        dest = job.install_atomic(out, self.songs, "song", False)
        self.assertEqual(dest, self.songs.resolve() / "song")
        self.assertFalse(out.exists())
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ["notes.chart", "song.ini", "song.mp3"])
        self.assertEqual([p.name for p in self.songs.iterdir()], ["song"])

    def test_collision_without_replace_gets_suffix(self):
        (self.songs / "song").mkdir()
        dest = job.install_atomic(self._out(), self.songs, "song", False)
        self.assertEqual(dest.name, "song_2")

    def test_replace(self):
        old = self.songs / "song"
        old.mkdir()
        (old / "notes.chart").write_text("old", encoding="utf-8")
        (old / "song.ogg").write_bytes(b"old")
        (old / "album.png").write_bytes(b"old")
        dest = job.install_atomic(self._out(), self.songs, "song", True)
        self.assertEqual(dest.name, "song")
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ["notes.chart", "song.ini", "song.mp3"])
        self.assertIn("new", (dest / "notes.chart").read_text(encoding="utf-8"))
        self.assertEqual([p.name for p in self.songs.iterdir()], ["song"])
        self.assertEqual(sorted(p.name for p in self.work.iterdir()), [])

    def test_cross_volume_fallback(self):
        out = self._out()
        seen = []
        real_replace = os.replace

        def spy_replace(a, b):
            # The temp folder must never hold notes.chart before it carries its final name.
            for p in self.songs.iterdir():
                if p.name.startswith(".tmp_"):
                    seen.append(sorted(c.name for c in p.iterdir()))
            return real_replace(a, b)

        def exdev(a, b):
            raise OSError(errno.EXDEV, "cross-device link")

        with mock.patch.object(job, "_move_dir", side_effect=exdev), \
                mock.patch.object(job.os, "replace", side_effect=spy_replace):
            dest = job.install_atomic(out, self.songs, "song", False)
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ["notes.chart", "song.ini", "song.mp3"])
        self.assertEqual([p.name for p in self.songs.iterdir()], ["song"])
        self.assertFalse(out.exists())
        self.assertTrue(seen)
        for names in seen:
            self.assertNotIn("notes.chart", names)
        self.assertEqual(self._chart_folders(), ["song"])

    def test_cross_volume_replace(self):
        old = self.songs / "song"
        old.mkdir()
        (old / "notes.chart").write_text("old", encoding="utf-8")
        (old / "extra.txt").write_text("old", encoding="utf-8")

        def exdev(a, b):
            raise OSError(errno.EXDEV, "cross-device link")

        with mock.patch.object(job, "_move_dir", side_effect=exdev):
            dest = job.install_atomic(self._out(), self.songs, "song", True)
        self.assertEqual(sorted(p.name for p in dest.iterdir()), ["notes.chart", "song.ini", "song.mp3"])
        self.assertEqual([p.name for p in self.songs.iterdir()], ["song"])

    def test_cross_volume_failure_cleans_up(self):
        out = self._out()
        calls = {"n": 0}
        real_copy = job._copy_file

        def flaky(a, b):
            calls["n"] += 1
            if calls["n"] == 2:
                raise OSError(errno.ENOSPC, "disk full")
            return real_copy(a, b)

        def exdev(a, b):
            raise OSError(errno.EXDEV, "cross-device link")

        with mock.patch.object(job, "_move_dir", side_effect=exdev), \
                mock.patch.object(job, "_copy_file", side_effect=flaky):
            with self.assertRaises(job.JobError) as cm:
                job.install_atomic(out, self.songs, "song", False)
        self.assertEqual(cm.exception.code, "disk")
        self.assertEqual(list(self.songs.iterdir()), [])
        self.assertTrue((out / "notes.chart").exists())  # the work copy survives for a retry

    def test_missing_chart_refused(self):
        out = self._out()
        (out / "notes.chart").unlink()
        with self.assertRaises(job.JobError):
            job.install_atomic(out, self.songs, "song", False)
        self.assertEqual(list(self.songs.iterdir()), [])

    def test_traversal_refused(self):
        with self.assertRaises(job.JobError):
            job.install_atomic(self._out(), self.songs, "..", False)
        self.assertEqual(list(self.songs.iterdir()), [])


class SongAudioTest(_Tmp):
    def test_mp3_copied_byte_for_byte(self):
        src = self.tmp / "In.MP3"
        data = bytes(range(256)) * 7
        src.write_bytes(data)
        out = self.tmp / "out"
        out.mkdir()
        self.assertEqual(job.write_song_audio(src, out), "song.mp3")
        self.assertEqual((out / "song.mp3").read_bytes(), data)

    def test_bad_suffix(self):
        src = self.tmp / "x.opus"
        src.write_bytes(b"x")
        with self.assertRaises(job.JobError) as cm:
            job.write_song_audio(src, self.tmp)
        self.assertEqual(cm.exception.code, "bad_type")

    def test_flac_to_pcm16_wav(self):
        try:
            import numpy as np
            import soundfile as sf
        except ImportError:
            self.skipTest("soundfile not installed")
        sr = 44100
        t = np.arange(sr // 2) / sr
        x = (0.5 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
        x = np.stack([x, -x], axis=1)
        src = self.tmp / "in.flac"
        sf.write(str(src), x, sr, subtype="PCM_24")
        out = self.tmp / "out"
        out.mkdir()
        self.assertEqual(job.write_song_audio(src, out), "song.wav")
        info = sf.info(str(out / "song.wav"))
        self.assertEqual(info.subtype, "PCM_16")
        self.assertEqual(info.samplerate, sr)
        self.assertEqual(info.channels, 2)
        self.assertEqual(info.frames, sf.info(str(src)).frames)


class EmitterTest(unittest.TestCase):
    def test_weights(self):
        self.assertEqual(list(job.STAGE_WEIGHTS), ["decode", "separate", "beats", "onsets", "pitch", "rank",
                                                   "chart", "install"])
        self.assertAlmostEqual(sum(job.STAGE_WEIGHTS.values()), 1.0, places=9)

    def test_ascii_line(self):
        buf = io.StringIO()
        job.Emitter(buf).emit(ev="start", name="Café")
        text = buf.getvalue()
        self.assertTrue(text.endswith("\n"))
        self.assertEqual(text.count("\n"), 1)
        text.encode("ascii")
        self.assertIn("\\u00e9", text)
        self.assertEqual(json.loads(text)["name"], "Café")

    def test_binary_stream(self):
        buf = io.BytesIO()
        job.Emitter(buf).emit(ev="warn", msg="ü")
        self.assertEqual(json.loads(buf.getvalue().decode("ascii"))["msg"], "ü")

    def test_progress_monotonic(self):
        buf = io.StringIO()
        em = job.Emitter(buf)
        for name in job.STAGE_WEIGHTS:
            em.stage(name)
            for f in (0.0, 0.5, 0.25, 1.0):  # 0.25 after 0.5 must not go backwards
                em.progress(name, f)
        evs = [json.loads(ln) for ln in buf.getvalue().splitlines()]
        stages = [e for e in evs if e["ev"] == "stage"]
        self.assertEqual([e["name"] for e in stages], list(job.STAGE_WEIGHTS))
        self.assertEqual([e["k"] for e in stages], list(range(1, 9)))
        self.assertTrue(all(e["n"] == 8 for e in stages))
        fr = [e["frac"] for e in evs if e["ev"] == "progress"]
        self.assertEqual(fr, sorted(fr))
        self.assertEqual(fr[-1], 1.0)
        self.assertTrue(all(0.0 <= f <= 1.0 for f in fr))

    def test_skipped_stage_jumps_forward(self):
        buf = io.StringIO()
        em = job.Emitter(buf)
        em.progress("chart", 0.0)  # cached analyze: straight to chart
        frac = json.loads(buf.getvalue().splitlines()[-1])["frac"]
        before = sum(w for k, w in job.STAGE_WEIGHTS.items() if k in ("decode", "separate", "beats", "onsets",
                                                                      "pitch", "rank"))
        self.assertAlmostEqual(frac, round(before, 4))

    def test_unknown_stage(self):
        with self.assertRaises(ValueError):
            job.Emitter(io.StringIO()).stage("nope")


if __name__ == "__main__":
    unittest.main()
