"""Tests for the Autocharter pack assembler tools/autochart/pack_build.py (Phase 2.2.2 plan 06, D-03/D-04/D-08/D-16).
Stdlib only, fake trees in temp dirs."""
import hashlib
import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import pack_build  # noqa: E402


def touch(root: Path, rel: str, data: bytes = b"x") -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return p


class PruneTest(unittest.TestCase):
    def test_prune_removes_dev_only_and_keeps_licences(self):
        with tempfile.TemporaryDirectory() as td:
            rt = Path(td) / "rt"
            sp = "Lib/site-packages/"
            removed = [
                "Lib/test/test_os.py", "Lib/idlelib/x.py", "Lib/tkinter/__init__.py", "Lib/turtledemo/a.py",
                "tcl/tcl8.6/init.tcl", "Scripts/demucs.exe",
                sp + "pip/__init__.py", sp + "pip-25.0.dist-info/RECORD",
                sp + "torch/include/ATen/a.h", sp + "torch/lib/x.lib", sp + "torch/x.lib",
                sp + "torch/testing/_internal/data/a.bin",
                sp + "pkg/tests/test_a.py", sp + "pkg/sub/test/test_b.py",
                sp + "pkg/__pycache__/a.cpython-312.pyc", "Lib/__pycache__/os.cpython-312.pyc",
            ]
            kept = [
                "python.exe", "Lib/os.py", sp + "torch/__init__.py", sp + "torch/lib/torch_cpu.dll",
                sp + "torch/testing/__init__.py",
                sp + "pkg/__init__.py", sp + "pkg/LICENSE.txt", sp + "pkg/NOTICE", sp + "pkg/COPYING",
                sp + "pkg-1.0.dist-info/licenses/LICENSE", sp + "pkg-1.0.dist-info/RECORD",
                sp + "pkg-1.0.dist-info/tests/keep.txt",
                sp + "pkg/tests/LICENSE",
            ]
            for r in removed + kept:
                touch(rt, r)
            pack_build.prune(rt)
            for r in removed:
                self.assertFalse((rt / r).exists(), r)
            for r in kept:
                self.assertTrue((rt / r).exists(), r)
            self.assertFalse((rt / "Lib/test").exists())
            self.assertFalse((rt / (sp + "pip")).exists())
            self.assertFalse((rt / (sp + "torch/include")).exists())


class AssignTest(unittest.TestCase):
    def test_assign_part(self):
        a = pack_build.assign_part
        sp = "rt/Lib/site-packages/"
        self.assertEqual(a(sp + "torch/x.py"), "rt-torch")
        self.assertEqual(a(sp + "torch-2.11.0+cpu.dist-info/RECORD"), "rt-torch")
        self.assertEqual(a(sp + "beat_this-1.1.0.dist-info/METADATA"), "rt-torch")
        self.assertEqual(a(sp + "lameenc.cp312-win_amd64.pyd"), "rt-torch")
        self.assertEqual(a(sp + "lameenc-1.8.4.dist-info/RECORD"), "rt-torch")
        self.assertEqual(a(sp + "huggingface_hub/x.py"), "rt-torch")
        self.assertEqual(a(sp + "numpy/x.py"), "rt-core")
        self.assertEqual(a(sp + "numpy-2.5.3.dist-info/RECORD"), "rt-core")
        self.assertEqual(a(sp + "numpy.libs/a.dll"), "rt-core")
        self.assertEqual(a(sp + "six.py"), "rt-core")
        self.assertEqual(a("rt/python.exe"), "rt-core")
        self.assertEqual(a("rt/Lib/os.py"), "rt-core")
        self.assertEqual(a("app/autochart.py"), "app")
        self.assertEqual(a("app/stages/job.py"), "app")
        self.assertEqual(a("NOTICES/THIRD_PARTY.txt"), "app")
        self.assertEqual(a("models/hf/hub/x"), "models")
        self.assertEqual(a("rt310/python.exe"), "rt310")
        with self.assertRaises(ValueError):
            a("other/x")

    def test_roots(self):
        self.assertEqual(pack_build.part_roots("app"), ["app", "NOTICES"])
        self.assertEqual(pack_build.part_roots("rt-core"), ["rt"])
        self.assertEqual(pack_build.part_roots("rt-core-b"), ["rt"])
        self.assertEqual(pack_build.part_roots("rt-torch"), ["rt"])
        self.assertEqual(pack_build.part_roots("models"), ["models"])
        self.assertEqual(pack_build.part_roots("rt310"), ["rt310"])


class LimitTest(unittest.TestCase):
    def test_max_part_entries_below_extractor_cap(self):
        src = (REPO / "src/autocharter/pack_extractor.gd").read_text(encoding="utf-8")
        m = re.search(r"const MAX_ENTRIES := (\d+)", src)
        self.assertIsNotNone(m)
        self.assertEqual(pack_build.MAX_PART_ENTRIES, 55000)
        self.assertLess(pack_build.MAX_PART_ENTRIES, int(m.group(1)))

    def test_split_uses_the_same_constant(self):
        n = pack_build.MAX_PART_ENTRIES + 1
        rels = ["rt/Lib/f%06d.py" % i for i in range(n)]
        groups = pack_build.split_groups({"rt-core": rels, "app": ["app/a.py"]})
        self.assertEqual(sorted(groups), ["app", "rt-core-a", "rt-core-b"])
        self.assertEqual(len(groups["rt-core-a"]) + len(groups["rt-core-b"]), n)
        self.assertTrue(all(len(v) <= pack_build.MAX_PART_ENTRIES for v in groups.values()))
        self.assertLess(max(groups["rt-core-a"]), min(groups["rt-core-b"]))
        self.assertEqual(pack_build.part_roots("rt-core-a"), ["rt"])
        # Under the cap nothing is renamed.
        self.assertEqual(sorted(pack_build.split_groups({"rt-core": rels[:10]})), ["rt-core"])


class ZipTest(unittest.TestCase):
    def _tree(self, td):
        root = Path(td) / "stage"
        touch(root, "app/b.py", b"print('b')\n" * 50)
        touch(root, "app/stages/a.py", b"x = 1\n")
        touch(root, "NOTICES/THIRD_PARTY.txt", b"notices\n")
        return root

    def test_write_zip_is_deterministic(self):
        with tempfile.TemporaryDirectory() as td:
            root = self._tree(td)
            rels = ["app/stages/a.py", "NOTICES/THIRD_PARTY.txt", "app/b.py"]
            z1 = Path(td) / "1.zip"
            z2 = Path(td) / "2.zip"
            n1 = pack_build.write_zip(z1, root, rels)
            # touch mtimes so only content counts
            (root / "app/b.py").write_bytes((root / "app/b.py").read_bytes())
            n2 = pack_build.write_zip(z2, root, list(reversed(rels)))
            self.assertEqual(n1, 3)
            self.assertEqual(n2, 3)
            self.assertEqual(pack_build.sha256_file(z1), pack_build.sha256_file(z2))
            self.assertEqual(pack_build.sha256_file(z1), hashlib.sha256(z1.read_bytes()).hexdigest())
            with zipfile.ZipFile(z1) as zf:
                names = zf.namelist()
                self.assertEqual(names, sorted(names))
                self.assertTrue(all("\\" not in n for n in names))
                for info in zf.infolist():
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertEqual(info.compress_type, zipfile.ZIP_DEFLATED)
                self.assertEqual(zf.read("app/stages/a.py"), b"x = 1\n")

    def test_write_zip_refuses_audio_and_oversize(self):
        with tempfile.TemporaryDirectory() as td:
            root = self._tree(td)
            for ext in (".mp3", ".ogg", ".wav", ".flac", ".opus", ".m4a", ".WAV"):
                touch(root, "models/x" + ext)
                with self.assertRaises(ValueError):
                    pack_build.write_zip(Path(td) / "a.zip", root, ["app/b.py", "models/x" + ext])
            too_many = ["app/b.py"] * (pack_build.MAX_PART_ENTRIES + 1)
            with self.assertRaises(ValueError):
                pack_build.write_zip(Path(td) / "b.zip", root, too_many)


class SpecTest(unittest.TestCase):
    PARTS = [
        {"name": "undertow-ac-v1-app.zip", "size": 1234, "sha256": "a" * 64, "roots": ["app", "NOTICES"]},
        {"name": "undertow-ac-v1-rt-core.zip", "size": 160000000, "sha256": "0123456789abcdef" * 4, "roots": ["rt"]},
        {"name": "undertow-ac-v1-models.zip", "size": 153000000, "sha256": "f" * 64, "roots": ["models"]},
    ]

    def test_render_spec(self):
        txt = pack_build.render_spec(self.PARTS, 987654321)
        self.assertIn("## GENERATED by tools/autochart/pack_build.py", txt)
        self.assertIn("class_name PackSpec", txt)
        self.assertIn("const VERSION := 1\n", txt)
        self.assertIn('const TAG := "autocharter-pack-v1"', txt)
        self.assertIn('const BASE_URL := "https://github.com/ccxmxrgo/undertow/releases/download/autocharter-pack-v1/"',
                      txt)
        self.assertIn("const UNPACKED_BYTES := 987654321\n", txt)
        for fn in ("static func available() -> bool:", "static func download_bytes() -> int:",
                   "static func url(part: Dictionary) -> String:", "static func as_dict() -> Dictionary:"):
            self.assertIn(fn, txt)
        got = re.findall(r'\{"name": "([^"]+)", "size": (\d+), "sha256": "([0-9a-f]{64})"', txt)
        self.assertEqual(got, [(p["name"], str(p["size"]), p["sha256"]) for p in self.PARTS])
        self.assertIn('"roots": ["app", "NOTICES"]', txt)
        self.assertNotIn("\r", txt)

    def test_render_matches_committed_template(self):
        # The plan 03 contract: rendering with no parts reproduces the committed placeholder layout
        # apart from PARTS / UNPACKED_BYTES, so the functions are byte-for-byte the plan 03 ones.
        committed = (REPO / "src/autocharter/pack_spec.gd").read_text(encoding="utf-8")
        tail = committed[committed.index("static func available()"):]
        self.assertTrue(pack_build.render_spec([], 0).endswith(tail))

    def test_sha256sums_sorted(self):
        txt = pack_build.sha256sums_text(self.PARTS)
        lines = txt.splitlines()
        self.assertEqual(lines, sorted(lines, key=lambda s: s.split("  ")[1]))
        self.assertIn("a" * 64 + "  undertow-ac-v1-app.zip", lines)
        self.assertEqual(len(lines), 3)
        self.assertTrue(txt.endswith("\n"))


if __name__ == "__main__":
    unittest.main()
