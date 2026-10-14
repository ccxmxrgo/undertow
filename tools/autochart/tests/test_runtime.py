"""Unit tests for stages/runtime.py and the error code in stages/errors.py (Phase 2.2.2 plan 04). Stdlib only."""
import subprocess
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

from stages import runtime  # noqa: E402
from stages.errors import AutochartError  # noqa: E402

REPO = HERE.parents[1]


class RuntimeDefaultsTest(unittest.TestCase):
    def setUp(self):
        runtime.reset_dev()

    def tearDown(self):
        runtime.reset_dev()

    def test_dev_defaults_equal_old_constants(self):
        self.assertEqual(runtime.CACHE, REPO / "build" / "autochart" / "cache")
        self.assertEqual(runtime.VENV_B, REPO / "build" / "autochart" / "venvB" / "Scripts" / "python.exe")
        self.assertEqual(runtime.WORKER, REPO / "tools" / "autochart" / "bp_worker.py")
        self.assertEqual(runtime.SEP_MODE, "subprocess")
        self.assertEqual(runtime.BP_MODE, "subprocess")
        self.assertEqual(runtime.THREADS, 0)

    def test_model_env_dev(self):
        env = runtime.model_env()
        self.assertEqual(env["HF_HOME"], str(runtime.CACHE))
        self.assertEqual(env["TORCH_HOME"], str(runtime.CACHE))
        self.assertEqual(env["HF_HUB_DISABLE_SYMLINKS_WARNING"], "1")

    def test_configure_pack_inprocess(self):
        models = Path("C:/pack/models")
        worker = Path("C:/pack/app/bp_worker.py")
        runtime.configure_pack(models, "inprocess", None, worker, 4)
        env = runtime.model_env()
        self.assertEqual(env["HF_HOME"], str(models / "hf"))
        self.assertEqual(env["TORCH_HOME"], str(models / "torch"))
        self.assertEqual(runtime.BP_MODE, "inprocess")
        self.assertEqual(runtime.SEP_MODE, "inprocess")
        self.assertEqual(runtime.THREADS, 4)
        self.assertEqual(runtime.WORKER, worker)

    def test_configure_pack_worker(self):
        py = Path("C:/pack/rt310/python.exe")
        runtime.configure_pack(Path("C:/pack/models"), "worker", py, Path("C:/pack/app/bp_worker.py"), 2)
        self.assertEqual(runtime.BP_MODE, "worker")
        self.assertEqual(runtime.VENV_B, py)

    def test_configure_pack_unknown_mode(self):
        with self.assertRaises(ValueError):
            runtime.configure_pack(Path("C:/m"), "magic", None, Path("C:/w.py"), 1)

    def test_reset_dev_restores(self):
        runtime.configure_pack(Path("C:/m"), "inprocess", None, Path("C:/w.py"), 8)
        runtime.reset_dev()
        self.assertEqual(runtime.CACHE, REPO / "build" / "autochart" / "cache")
        self.assertEqual(runtime.BP_MODE, "subprocess")
        self.assertEqual(runtime.THREADS, 0)


class ErrorCodeTest(unittest.TestCase):
    def test_code_default_empty(self):
        e = AutochartError("decode", "x")
        self.assertEqual(e.code, "")
        self.assertEqual(e.stage, "decode")
        self.assertEqual(e.message, "x")

    def test_code_given(self):
        self.assertEqual(AutochartError("decode", "x", code="too_big").code, "too_big")


class ImportHygieneTest(unittest.TestCase):
    def test_runtime_and_errors_do_not_import_numpy(self):
        code = ("import sys; sys.path.insert(0, sys.argv[1]); import stages.runtime, stages.errors; "
                "print('numpy' in sys.modules)")
        r = subprocess.run([sys.executable, "-I", "-B", "-c", code, str(HERE)],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "False")


if __name__ == "__main__":
    unittest.main()
