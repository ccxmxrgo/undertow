"""Check the runtime pack pin set (Phase 2.2.2, T-02.2.2-02). STANDARD LIBRARY ONLY.

  python -I -B tools/autochart/check_pack_reqs.py [--in <requirements-pack.in>] [--txt <requirements-pack.txt>]

Fails (exit 1) when:
  - a name==version is in the .in but not in the .txt, or the other way round;
  - a requirement in the .txt has no --hash=sha256: line;
  - tensorflow, tflite(-runtime) or coremltools appear in either file;
  - setuptools is not pinned to 80.10.2 (resampy 0.4.2 imports pkg_resources).
Prints PACK_REQS_OK and exits 0 otherwise.
"""
import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FORBIDDEN = ("tensorflow", "tflite", "coremltools")
SETUPTOOLS = "80.10.2"
PIN = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([^\s\\;]+)")


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_in(text):
    pins = {}
    for line in text.splitlines():
        s = line.split("#", 1)[0].strip()
        if not s:
            continue
        m = PIN.match(s)
        if not m:
            raise ValueError(f"not an exact pin: {line!r}")
        pins[norm(m.group(1))] = m.group(2)
    return pins


def parse_txt(text):
    """Returns ({name: version}, [names without a hash]). A requirement spans its continuation lines."""
    pins, unhashed = {}, []
    cur, hashed = None, False
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("--hash="):
            if cur is None:
                raise ValueError(f"hash line without a requirement: {line!r}")
            if s.startswith("--hash=sha256:"):
                hashed = True
            continue
        if s.startswith("-"):
            continue  # global options such as --index-url
        if cur is not None and not hashed:
            unhashed.append(cur)
        m = PIN.match(s)
        if not m:
            raise ValueError(f"not an exact pin: {line!r}")
        cur, hashed = norm(m.group(1)), False
        pins[cur] = m.group(2)
        hashed = "--hash=sha256:" in s
    if cur is not None and not hashed:
        unhashed.append(cur)
    return pins, unhashed


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default=str(HERE / "requirements-pack.in"))
    ap.add_argument("--txt", default=str(HERE / "requirements-pack.txt"))
    a = ap.parse_args(argv)
    errors = []
    try:
        pin_in = parse_in(Path(a.inp).read_text(encoding="utf-8"))
        pin_txt, unhashed = parse_txt(Path(a.txt).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"PACK_REQS_FAIL {e}")
        return 1
    for n in sorted(set(pin_in) | set(pin_txt)):
        vi, vt = pin_in.get(n), pin_txt.get(n)
        if vi != vt:
            errors.append(f"mismatch {n}: in={vi} txt={vt}")
    for n in unhashed:
        errors.append(f"no --hash=sha256 for {n}")
    for n in sorted(set(pin_in) | set(pin_txt)):
        if any(f in n for f in FORBIDDEN):
            errors.append(f"forbidden package {n}")
    for label, pins in (("in", pin_in), ("txt", pin_txt)):
        if pins.get("setuptools") != SETUPTOOLS:
            errors.append(f"setuptools in {label} is {pins.get('setuptools')}, must be {SETUPTOOLS}")
    for e in errors:
        print(e)
    if errors:
        print(f"PACK_REQS_FAIL {len(errors)} problem(s)")
        return 1
    print(f"{len(pin_txt)} pins, all hashed")
    print("PACK_REQS_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
