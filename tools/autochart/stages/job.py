"""Job helpers for the pack entry point `autochart.py job <job.json>` (Phase 2.2.2, RESEARCH Pattern 3).

  load_job          validate job.json (written by the game, untrusted on disk; T-02.2.2-18)
  work_dir_for      work dir keyed by the source SHA-256 (D-12: a second instrument reuses the stems)
  is_analyzed / mark_analyzed / touch   analyze_done.json cache marker, last_used.json for LRU prune
  unique_slug       _2.._99 suffix on a folder-name collision unless replace (D-06)
  install_atomic    move the finished song into songs_root/<slug>; the scanner never sees a half song
                    (SongScanner._discover does not skip dot folders; T-02.2.2-20)
  write_song_audio  source audio as song.<ext>; FLAC -> song.wav PCM_16 (D-01, Godot has no FLAC stream)
  Emitter           ASCII JSON event lines with monotonic overall progress (STAGE_WEIGHTS)

STANDARD LIBRARY ONLY at import time (soundfile is imported inside write_song_audio): the unit tests run
under plain `python -I -B`. Error codes are the keys of AutochartJob.ERROR_TEXT
(src/autocharter/job_protocol.gd).
"""
from __future__ import annotations

import errno
import json
import os
import re
import shutil
import time
from pathlib import Path

from stages.errors import AutochartError

VERSION = 1
PACK_MAX_S = 600.0
MAX_BYTES = 200 * 1024 * 1024
MAX_TEXT = 120
SUFFIXES = (".mp3", ".ogg", ".wav", ".flac")
COPY_SUFFIXES = (".mp3", ".ogg", ".wav")
MODES = ("auto", "single", "lanes")
STEMS = ("other", "drums", "bass", "vocals")
DEFAULT_GENRE = "Autochart"
MARKER = "analyze_done.json"
LAST_USED = "last_used.json"
SLUG_RE = re.compile(r"[a-z0-9_]{1,48}")
MAX_SUFFIX = 99

CODES = frozenset({
    "bad_job", "bad_type", "not_found", "too_big", "too_short", "too_long", "bad_rate", "decode",
    "no_beats", "no_notes", "exists", "disk", "memory", "selftest", "internal", "crash", "start", "vcredist",
})

STAGE_WEIGHTS = {
    "decode": 0.03, "separate": 0.60, "beats": 0.06, "onsets": 0.08, "pitch": 0.10,
    "rank": 0.03, "chart": 0.07, "install": 0.03,
}


class JobError(AutochartError):
    def __init__(self, code, message, stage="job"):
        if code not in CODES:
            raise ValueError(f"unknown job error code {code!r}")
        super().__init__(stage, message, code=code)


# ---------------------------------------------------------------- job.json validation

def _bad(msg: str) -> JobError:
    return JobError("bad_job", msg)


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _abs_path(job: dict, key: str) -> Path:
    v = job.get(key)
    if not isinstance(v, str) or not v or "\x00" in v:
        raise _bad(f"{key} must be a path string")
    p = Path(v)
    if not p.is_absolute():
        raise _bad(f"{key} must be an absolute path")
    return p.resolve()


def _text(job: dict, key: str, required: bool) -> str:
    v = job.get(key)
    if not isinstance(v, str):
        raise _bad(f"{key} must be a string")
    v = v.strip()
    if (required and not v) or len(v) > MAX_TEXT:
        raise _bad(f"{key} must be 1..{MAX_TEXT} characters" if required else f"{key} is too long")
    return v


def load_job(path: Path, ac_root: Path | None) -> dict:
    """Validated job: Path objects for src / songs_root / work_root / models_root, typed scalars and the
    raw dict under "raw". ac_root None skips the work_root containment check (dev end-to-end runs)."""
    try:
        job = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise _bad(f"cannot read job file: {e}") from e
    if not isinstance(job, dict):
        raise _bad("job file is not a JSON object")
    v = job.get("version")
    if not _is_int(v) or v != VERSION:
        raise _bad(f"job version must be {VERSION}")

    src = _abs_path(job, "src")
    if src.suffix.lower() not in SUFFIXES:
        raise JobError("bad_type", f"unsupported file type '{src.suffix}' (allowed: .mp3 .ogg .wav .flac)")
    if not src.is_file():
        raise JobError("not_found", f"source file not found: {src}")
    size = src.stat().st_size
    if size > MAX_BYTES:
        raise JobError("too_big", f"file is {size / 1e6:.0f} MB, the limit is 200 MB")

    name = _text(job, "name", True)
    artist = _text(job, "artist", False) or "Unknown"
    genre = _text(job, "genre", False) if "genre" in job else DEFAULT_GENRE
    mode = job.get("mode")
    if mode not in MODES:
        raise _bad(f"mode must be one of {', '.join(MODES)}")
    stem = job.get("stem")
    if stem not in STEMS:
        raise _bad(f"stem must be one of {', '.join(STEMS)}")
    nps = job.get("target_nps")
    if not _is_num(nps) or not 0.5 <= float(nps) <= 8.0:
        raise _bad("target_nps must be a number within 0.5..8")
    threads = job.get("threads")
    if not _is_int(threads) or not 1 <= threads <= 64:
        raise _bad("threads must be an integer within 1..64")
    replace = job.get("replace")
    if not isinstance(replace, bool):
        raise _bad("replace must be true or false")

    songs_root = _abs_path(job, "songs_root")
    if not songs_root.is_dir():
        raise _bad(f"songs_root is not a folder: {songs_root}")
    work_root = _abs_path(job, "work_root")
    if not work_root.is_dir():
        raise _bad(f"work_root is not a folder: {work_root}")
    if ac_root is not None:
        try:
            work_root.relative_to(Path(ac_root).resolve())
        except ValueError as e:
            raise _bad("work_root is outside the autocharter folder") from e
    models_root = _abs_path(job, "models_root")
    if not (models_root / "hf").is_dir() or not (models_root / "torch").is_dir():
        raise _bad(f"models_root has no hf/ and torch/ folders: {models_root}")

    return {"src": src, "name": name, "artist": artist, "genre": genre, "mode": mode, "stem": stem,
            "target_nps": float(nps), "threads": threads, "replace": replace,
            "songs_root": songs_root, "work_root": work_root, "models_root": models_root, "raw": job}


# ---------------------------------------------------------------- work dir cache (D-12)

def work_dir_for(work_root: Path, src_sha: str) -> Path:
    if not isinstance(src_sha, str) or not re.fullmatch(r"[0-9a-f]{16,64}", src_sha):
        raise ValueError(f"not a hex SHA-256: {src_sha!r}")
    return Path(work_root) / ("w_" + src_sha[:16])


def _write_json_atomic(path: Path, doc: dict) -> None:
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_text(json.dumps(doc), encoding="utf-8")
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def is_analyzed(work: Path, src_sha: str) -> bool:
    try:
        doc = json.loads((Path(work) / MARKER).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return isinstance(doc, dict) and doc.get("source_sha256") == src_sha


def mark_analyzed(work: Path, src_sha: str) -> None:
    """Written LAST, after every analyze intermediate exists; tmp + os.replace, never half-written."""
    _write_json_atomic(Path(work) / MARKER, {"source_sha256": src_sha, "t": time.time()})


def touch(work: Path) -> None:
    _write_json_atomic(Path(work) / LAST_USED, {"t": time.time()})


# ---------------------------------------------------------------- install (D-06)

def unique_slug(songs_root: Path, slug: str, replace: bool) -> str:
    if not isinstance(slug, str) or not SLUG_RE.fullmatch(slug):
        raise _bad(f"invalid song folder name {slug!r}")
    root = Path(songs_root)
    if replace or not (root / slug).exists():
        return slug
    for i in range(2, MAX_SUFFIX + 1):
        cand = f"{slug}_{i}"
        if not (root / cand).exists():
            return cand
    raise JobError("exists", f"{slug} and {slug}_2..{slug}_{MAX_SUFFIX} already exist", stage="install")


# Test hooks: _move_dir moves a folder between the work dir and songs_root (raises EXDEV across
# volumes); _copy_file copies one file in the cross-volume fallback.
_move_dir = os.replace
_copy_file = shutil.copyfile


def _is_exdev(e: OSError) -> bool:
    return e.errno == errno.EXDEV or getattr(e, "winerror", None) == 17  # ERROR_NOT_SAME_DEVICE


def _install_error(e: OSError, what: str) -> JobError:
    full = e.errno == errno.ENOSPC or getattr(e, "winerror", None) in (39, 112)  # HANDLE_DISK_FULL, DISK_FULL
    return JobError("disk" if full else "internal", f"{what}: {e}", stage="install")


def _drop_folder(p: Path) -> None:
    """Remove a song folder so it stops being a song first (notes.chart goes before the rest)."""
    if p.is_dir():
        chart = p / "notes.chart"
        if chart.exists():
            chart.unlink()
        shutil.rmtree(p)


def _install_copy(out_dir: Path, root: Path, dest: Path, replace: bool) -> None:
    """Cross-volume fallback: songs_root/.tmp_<slug> without notes.chart, rename to <slug>, then
    notes.chart.part -> notes.chart. On failure the temp / half folder is removed."""
    tmp = root / f".tmp_{dest.name}"
    created_dest = False
    try:
        if tmp.exists():
            shutil.rmtree(tmp)
        tmp.mkdir()
        for f in sorted(out_dir.iterdir()):
            if f.name == "notes.chart":
                continue
            if f.is_dir():
                shutil.copytree(f, tmp / f.name, copy_function=_copy_file)
            else:
                _copy_file(f, tmp / f.name)
        if dest.exists():
            if not replace:
                raise JobError("exists", f"{dest.name} already exists", stage="install")
            _drop_folder(dest)
        os.replace(tmp, dest)
        created_dest = True
        part = dest / "notes.chart.part"
        _copy_file(out_dir / "notes.chart", part)
        os.replace(part, dest / "notes.chart")
    except OSError as e:
        shutil.rmtree(tmp, ignore_errors=True)
        if created_dest:
            shutil.rmtree(dest, ignore_errors=True)
        raise _install_error(e, "cannot copy the song into the Songs folder") from e
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        if created_dest:
            shutil.rmtree(dest, ignore_errors=True)
        raise
    shutil.rmtree(out_dir, ignore_errors=True)


def install_atomic(out_dir: Path, songs_root: Path, slug: str, replace: bool) -> Path:
    """Move out_dir (notes.chart, song.ini, song.<ext>) to songs_root/<slug or slug_N>; returns the folder.
    Same volume: one os.replace of the complete folder. replace=True first moves the old folder into
    the work dir (out_dir.parent / old_<slug>), never into songs_root."""
    out_dir = Path(out_dir)
    root = Path(songs_root).resolve()
    if not (out_dir / "notes.chart").is_file():
        raise JobError("internal", f"{out_dir} has no notes.chart", stage="install")
    name = unique_slug(root, slug, replace)
    dest = (root / name).resolve()
    if dest.parent != root or dest == root:  # T-02.2.2-19
        raise _bad("refusing to write outside the Songs folder")

    old = None
    try:
        if dest.exists():
            if not replace:
                raise JobError("exists", f"{name} already exists", stage="install")
            old = out_dir.parent / f"old_{name}"
            if old.exists():
                shutil.rmtree(old)
            _move_dir(dest, old)
        try:
            _move_dir(out_dir, dest)
        except OSError:
            if old is not None:
                os.replace(old, dest)  # put the old song back before deciding what to do
                old = None
            raise
    except OSError as e:
        if not _is_exdev(e):
            raise _install_error(e, "cannot move the song into the Songs folder") from e
        _install_copy(out_dir, root, dest, replace)
        return dest
    if old is not None:
        shutil.rmtree(old, ignore_errors=True)
    return dest


def write_song_audio(src: Path, out_dir: Path) -> str:
    """mp3 / ogg / wav: copied byte-for-byte as song.<ext>. flac: decoded with soundfile and written as
    song.wav, 16-bit PCM at the source rate (RESEARCH Pattern 3 item 7: no OGG transcode)."""
    src = Path(src)
    ext = src.suffix.lower()
    if ext in COPY_SUFFIXES:
        name = f"song{ext}"
        shutil.copyfile(src, Path(out_dir) / name)
        return name
    if ext == ".flac":
        import soundfile as sf

        try:
            x, sr = sf.read(str(src), dtype="float32", always_2d=True)
        except Exception as e:  # libsndfile errors
            raise JobError("decode", f"cannot decode {src.name}: {e}", stage="install") from e
        name = "song.wav"
        sf.write(str(Path(out_dir) / name), x, sr, subtype="PCM_16")
        return name
    raise JobError("bad_type", f"unsupported file type '{src.suffix}'", stage="install")


# ---------------------------------------------------------------- event protocol

_ORDER = list(STAGE_WEIGHTS)
_BASE = {}
_acc = 0.0
for _k in _ORDER:
    _BASE[_k] = _acc
    _acc += STAGE_WEIGHTS[_k]
del _k, _acc


class Emitter:
    """One ASCII JSON object per line on the protocol stream (text or binary), flushed each time.
    progress() reports the overall fraction 0..1 and never goes backwards."""

    def __init__(self, stream):
        self._stream = stream
        self._last = 0.0

    def emit(self, **ev) -> None:
        line = json.dumps(ev, ensure_ascii=True, separators=(",", ":")) + "\n"
        try:
            self._stream.write(line)
        except TypeError:
            self._stream.write(line.encode("ascii"))
        self._stream.flush()

    @staticmethod
    def _check(name: str) -> None:
        if name not in STAGE_WEIGHTS:
            raise ValueError(f"unknown stage {name!r}")

    def stage(self, name: str) -> None:
        self._check(name)
        self.emit(ev="stage", k=_ORDER.index(name) + 1, n=len(_ORDER), name=name)

    def progress(self, name: str, frac_in_stage: float) -> None:
        self._check(name)
        f = min(1.0, max(0.0, float(frac_in_stage)))
        overall = round(min(1.0, _BASE[name] + STAGE_WEIGHTS[name] * f), 4)
        overall = max(overall, self._last)
        self._last = overall
        self.emit(ev="progress", frac=overall)
