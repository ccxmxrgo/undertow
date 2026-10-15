"""UNDERTOW autochart CLI (Phase 2.1). Runs in venv A:

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py analyze \
      --id <id> --src <audio> [--from-stage decode|separate|beats|onsets|pitch] [--godot-wav <wav>] [--force]

analyze: decode -> separate -> beats -> onsets -> pitch. Every stage writes an inspectable JSON / WAV
intermediate under build/autochart/<id>/ (D-02). Progress: `[k/5] <stage> ...` / `[k/5] <stage> done (X.X s)`.
Errors: `AUTOCHART_ERROR <stage>: <message>` on stderr, exit 2. Last line on success: `ANALYZE_OK <id>`.

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py chart       --id <id> --out <song_dir> --stem <name> [--fill-stem <name> [--fill-mode bars|sections]] [--target-nps 3.5]       --name <s> --artist <s> --genre <s> [--delay-ms <int>] [--song-length-ms <int>]       [--godot-wav <wav>] [--stats-dir <dir>]

chart: analysis intermediates -> <song_dir>/notes.chart + song.ini + <stats-dir>/<id>.chart_stats.json.
beats.json -> tempo map; onsets_<stem>.json (audible and loud) -> Expert notes; Expert lanes (contour,
accent chords, sustains); Hard / Medium / Easy reduced from Expert (assign_lanes never runs on a reduced
track); sections.json; solo + preview; write. Deterministic: the same intermediates give a byte-identical
notes.chart (D-04). --delay-ms replaces the song.ini delay only: chart ticks stay the same and every note,
beat and section moves by the same amount in song time, which is how the measured gate median is fitted
(the decoded audio does not change). Last line on success: `CHART_OK <id> <sha256 of notes.chart>`.

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/autochart.py extract --src <audio.mp3|.ogg|.wav>       [--name <s>] [--artist <s>] [--genre <s>] [--mode single|lanes] [--stem other] [--target-nps 3.5]       [--songs-root <dir>] [--force]

extract (player flow, STEM-02/04/05; wrapper tools/autochart/extract_song.ps1): analyze + chart for
work id user_<slug>, then copies the source audio (byte-for-byte, song.<ext>), notes.chart and song.ini
into <songs-root>/<slug> (default: Godot user://songs of UNDERTOW). --mode lanes = INSTRUMENT LANES
(stages/instrument_lanes.py: bass, drums, other, vocals from left to right). Chart stats go to
build/autochart/<id>/, never tools/autochart/reports/. Never writes outside the Songs folder and never
replaces an existing song folder without --force. Last line on success: `EXTRACT_OK <song folder>`.

  <pack>/v1/rt/python.exe -I -X utf8 -u autochart.py job <job.json> [--ac-root <dir>]
  <pack>/v1/rt/python.exe -I -X utf8 -u autochart.py selftest [--models-root <dir>] [--log <file>]

job (Phase 2.2.2, the one process the game spawns, D-05): job.json (stages/job.py load_job) -> decode,
in-process htdemucs, beats, onsets, in-process Basic Pitch, stem rank, chart, atomic install into
songs_root/<slug>. stdout carries only ASCII JSON events (start, work, stage, progress, warn, rank, error,
done); stdout/stderr of the process go to <job folder>/log.txt. A second instrument for the same file reuses
the SHA-keyed work dir. Exit: 0 ok, 2 an error event was printed, 3 MemoryError, 4 stdin closed (game gone).
selftest: loads htdemucs, runs beat_this and Basic Pitch on generated audio with sockets blocked; prints
{"ev":"selftest","ok":true,...} or an error event (code selftest / vcredist).
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))  # python -I does not put the script directory on sys.path

os.environ.setdefault("HF_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("TORCH_HOME", str(ROOT / "build" / "autochart" / "cache"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

from stages.errors import AutochartError  # noqa: E402

BUILD = (ROOT / "build" / "autochart").resolve()
ID_RE = re.compile(r"^[a-z0-9_]{1,48}$")
STAGES = ["decode", "separate", "beats", "onsets", "pitch"]
DEFAULT_STEMS = ["other", "drums", "bass", "vocals"]


def work_dir(song_id: str) -> Path:
    if not ID_RE.match(song_id or ""):
        raise AutochartError("args", f"--id '{song_id}' must match ^[a-z0-9_]{{1,48}}$")
    work = (BUILD / song_id).resolve()
    if work.parent != BUILD:
        raise AutochartError("args", f"work dir {work} is outside {BUILD}")
    return work


def _run_stage(name: str, args, work: Path):
    if name == "decode":
        from stages import decode
        if not args.src:
            raise AutochartError("decode", "--src is required for the decode stage")
        info = decode.decode(Path(args.src).resolve(), work)
        msg = f"{info['length_s']:.3f} s, {info['channels']} ch"
        if args.godot_wav:
            lag = decode.godot_lag_check(work, Path(args.godot_wav).resolve())
            msg += f", Godot lag {lag:+.3f} ms"
        return msg
    if name == "separate":
        from stages import separate
        info = separate.separate(work, force=args.force)
        return f"{info['model']}, stem lag {info['lag_ms']:+.3f} ms"
    if name == "beats":
        from stages import beats
        info = beats.beats_stage(work)
        return (f"{info['bpm']:.2f} BPM, constant {info['constant_tempo']}, "
                f"phase {info['phase_shift_ms']:+.1f} ms, repairs {info['repairs']}")
    if name == "onsets":
        from stages import onsets
        info = onsets.onsets_stage(work, args.stems)
        return ", ".join(f"{s} {v['audible_loud']}/{v['count']}" for s, v in info.items())
    if name == "pitch":
        from stages import pitch_bp
        info = pitch_bp.pitch_stage(work, args.stems)
        return ", ".join(f"{s} pitched {v['pitched_share']:.2f}" for s, v in info.items())
    raise AutochartError("args", f"unknown stage {name}")


def cmd_analyze(args) -> int:
    work = work_dir(args.id)
    first = STAGES.index(args.from_stage)
    if first > 0 and not (work / "decode.json").is_file():
        raise AutochartError(args.from_stage, f"{work / 'decode.json'} is missing; start from decode")
    n = len(STAGES)
    for k, name in enumerate(STAGES[first:], start=first + 1):
        print(f"[{k}/{n}] {name} ...", flush=True)
        t0 = time.perf_counter()
        msg = _run_stage(name, args, work)
        print(f"[{k}/{n}] {name} done ({time.perf_counter() - t0:.1f} s) {msg}", flush=True)
    print(f"ANALYZE_OK {args.id}", flush=True)
    return 0


# ---------------------------------------------------------------- chart
KEEP_BANDS = {"hard": (0.90, 1.00), "medium": (0.65, 0.75), "easy": (0.45, 0.55)}
STEP_BANDS = {"repeat": (0.20, 0.30), "step1": (0.40, 0.60), "step2": (0.15, 0.30), "step3plus": (0.00, 0.05)}
BAND_TOL = 0.05
CHART_DIFFS = ("easy", "medium", "hard", "expert")
CHART_STEPS = 7


def _inside(p: Path, roots) -> bool:
    for r in roots:
        try:
            p.relative_to(r)
            return True
        except ValueError:
            pass
    return False


def _out_dir(out: str) -> Path:
    """T-02.1-14: the song folder must resolve inside the repo songs/ or build/ (never the roots)."""
    p = Path(out).resolve()
    roots = [(ROOT / "songs").resolve(), (ROOT / "build").resolve()]
    if not _inside(p, roots) or p in roots:
        raise AutochartError("args", f"--out {p} must be a folder inside {roots[0]} or {roots[1]}")
    return p


def _load_json(path: Path, stage: str):
    import json
    if not path.is_file():
        raise AutochartError(stage, f"{path} is missing; run analyze first")
    return json.loads(path.read_text(encoding="utf-8"))


def _r4(x: float) -> float:
    return round(float(x), 4)


def _track_stats(notes: list, expert: list) -> dict:
    from stages import lanes, quantize, reduce as red
    n = len(notes)
    times = sorted(float(x["t"]) for x in notes)
    span = times[-1] - times[0] if n >= 2 else 0.0
    chords = sum(1 for x in notes if len(set(x["lanes"])) >= 2)
    hist = lanes.lane_step_hist(notes)
    return {
        "notes": n,
        "gems": sum(len(set(x["lanes"])) for x in notes),
        "notes_per_s": _r4(n / span) if span > 0 else 0.0,
        "max_per_1s": quantize.notes_per_window_max(notes),
        "keep_share": _r4(red.keep_share(notes, expert)),
        "chord_count": chords,
        "chord_share": _r4(chords / n) if n else 0.0,
        "sustain_share": _r4(sum(1 for x in notes if int(x.get("len") or 0) > 0) / n) if n else 0.0,
        "lane_step_hist": dict(zip(STEP_BANDS.keys(), (_r4(v) for v in hist))),
    }


def band_flags(per: dict) -> list:
    """One flag per keep_share / lane-step share outside its Neversoft band +- BAND_TOL.
    Flags are reported, never fixed by padding notes (SPEC req 6: a reduction never moves a note)."""
    flags = []
    for d in CHART_DIFFS:
        s = per[d]
        checks = []
        if d in KEEP_BANDS:
            checks.append(("keep_share", s["keep_share"], KEEP_BANDS[d]))
        for m, band in STEP_BANDS.items():
            checks.append((m, s["lane_step_hist"][m], band))
        for metric, v, (lo, hi) in checks:
            if v < lo - BAND_TOL - 1e-9 or v > hi + BAND_TOL + 1e-9:
                flags.append({"difficulty": d, "metric": metric, "value": v, "band": [lo, hi],
                              "tolerance": BAND_TOL})
    return flags


def cmd_chart(args) -> int:
    work = work_dir(args.id)
    out_dir = _out_dir(args.out)
    stats_dir = Path(args.stats_dir).resolve()
    if not _inside(stats_dir, [ROOT.resolve()]):
        raise AutochartError("args", f"--stats-dir {stats_dir} must be inside the repo {ROOT}")
    return _chart_core(work, out_dir, stats_dir, args.stem, args.fill_stem, args.fill_mode, args.target_nps,
                       args.name, args.artist, args.genre, args.delay_ms, args.song_length_ms, args.godot_wav,
                       getattr(args, "mode", "single"), args.id)


def _chart_core(work: Path, out_dir: Path, stats_dir: Path, stem: str, fill_stem, fill_mode: str,
                target_nps: float, name: str, artist: str, genre: str, delay_ms, song_length_ms, godot_wav,
                mode: str, song_id: str) -> int:
    """The chart stage shared by `chart` (dev, paths checked by cmd_chart) and `job` (pack, paths from the
    validated job.json). Writes out_dir/notes.chart + song.ini and stats_dir/<song_id>.chart_stats.json."""
    import argparse as _ap

    from stages import lanes, quantize
    from stages.tempo_map import build_tempo_map

    args = _ap.Namespace(id=song_id, stem=stem, fill_stem=fill_stem, fill_mode=fill_mode, target_nps=target_nps,
                         name=name, artist=artist, genre=genre, delay_ms=delay_ms,
                         song_length_ms=song_length_ms, godot_wav=godot_wav, mode=mode)
    if args.fill_stem and args.fill_stem == args.stem:
        raise AutochartError("args", f"--fill-stem {args.fill_stem} must differ from --stem")
    if not 0.5 <= args.target_nps <= 8.0:
        raise AutochartError("args", f"--target-nps {args.target_nps} must be within 0.5..8")
    n = CHART_STEPS

    def step(k: int, msg: str) -> None:
        print(f"[{k}/{n}] {msg}", flush=True)

    # 1. tempo map (optional decoder cross-check first)
    if args.godot_wav:
        from stages import decode
        lag = decode.godot_lag_check(work, Path(args.godot_wav).resolve())
        if abs(lag) > 1.0:
            raise AutochartError("chart", f"Godot decode lag {lag:+.3f} ms > 1 ms")
        print(f"Godot decode lag {lag:+.3f} ms", flush=True)
    beats = _load_json(work / "beats.json", "chart")
    dec = _load_json(work / "decode.json", "chart")
    tm = build_tempo_map(beats["beats"], beats["downbeats"], bool(beats["constant_tempo"]))
    n_b = sum(1 for e in tm["events"] if e[1] == "B")
    step(1, f"tempo map: {n_b} B event(s), analysis delay {tm['delay_ms']} ms, {len(tm['bar_ticks'])} bar lines")

    # sections first: the "sections" fill mode switches stems at section starts
    from stages import sections as sec_stage
    secs = sec_stage.sections_stage(work, tm)

    mode = getattr(args, "mode", "single")
    easy_map = None
    if mode == "lanes":
        # INSTRUMENT LANES (STEM-04): lane = stem index, no contour; Easy drops the sparsest lane
        from stages import instrument_lanes as il
        obs = {}
        for s in il.LANE_ORDER:
            o = _load_json(work / f"onsets_{s}.json", "chart")
            obs[s] = [x for x in o["onsets"] if x.get("audible") and x.get("loud")]
        expert = il.instrument_expert(obs, tm, target_nps=args.target_nps)
        if len(expert) < 32:
            raise AutochartError("chart", f"only {len(expert)} Expert notes from the four stems")
        step(2, f"expert: {len(expert)} notes from " + ", ".join(f"{s} {len(obs[s])}" for s in il.LANE_ORDER)
             + f" onsets (target {args.target_nps} n/s)")
        easy_map = il.easy_lane_map(expert)
        step(3, "lanes: instrument lanes " + ", ".join(f"{i}={s}" for i, s in enumerate(il.LANE_ORDER))
             + f"; Easy lane map {easy_map}")
        return _chart_tail(args, work, out_dir, stats_dir, step, tm, beats, dec, secs, n_b, expert,
                           easy_map, mode)

    # 2. Expert notes from the stem's audible + loud onsets; silent bars / sparse sections are filled
    #    from --fill-stem (RESEARCH Pitfall 9: never lower the audibility filter instead)
    ons = _load_json(work / f"onsets_{args.stem}.json", "chart")
    recs = [o for o in ons["onsets"] if o.get("audible") and o.get("loud")]
    n_primary = len(recs)
    if args.fill_stem:
        from stages.fill import fill_silent
        fons = _load_json(work / f"onsets_{args.fill_stem}.json", "chart")
        frecs = [o for o in fons["onsets"] if o.get("audible") and o.get("loud")]
        recs = fill_silent(recs, frecs, tm, mode=args.fill_mode,
                           section_starts_tick=secs["starts_tick"], fill_src=args.fill_stem)
        print(f"  fill: {args.fill_stem} ({args.fill_mode}) adds "
              f"{sum(1 for o in recs if o.get('src') == args.fill_stem)} onsets, "
              f"{len(recs)} total (primary {n_primary})", flush=True)
    expert = quantize.build_expert(recs, tm, args.target_nps)
    if len(expert) < 32:
        raise AutochartError("chart", f"only {len(expert)} Expert notes from stem {args.stem}")
    step(2, f"expert: {len(expert)} notes from {len(recs)} {args.stem} onsets (target {args.target_nps} n/s)")

    # 3. Expert lanes (contour, accent chords, sustains); 4. reductions from Expert only
    #    (assign_lanes never runs on a reduced track: reduce derives chords from Expert, Easy re-contours)
    expert = lanes.assign_lanes(expert, "expert")
    step(3, f"lanes: direction match {lanes.direction_match(expert):.3f}")
    return _chart_tail(args, work, out_dir, stats_dir, step, tm, beats, dec, secs, n_b, expert,
                       easy_map, mode)


def _chart_tail(args, work, out_dir, stats_dir, step, tm, beats, dec, secs, n_b, expert,
                easy_map, mode) -> int:
    import hashlib
    import json

    from stages import lanes, quantize, reduce as red, structure
    from stages.write_chart import render_chart, render_ini
    from stages.tempo_map import tick_to_sec

    tracks = {"expert": expert}
    for d in ("hard", "medium", "easy"):
        tracks[d] = red.reduce(expert, d, tm, easy_lane_map=easy_map if d == "easy" else None)
    step(4, "reductions: " + ", ".join(f"{d} {len(tracks[d])}" for d in ("hard", "medium", "easy")))

    # 5. sections (computed above)
    step(5, f"sections: {', '.join(secs['names'])}")

    # 6. solo + preview
    vocal = dict(zip(secs["bar_ticks"], secs["vocal_active"]))
    vocal_active = [bool(vocal.get(t, False)) for t in tm["bar_ticks"]]
    solo = structure.pick_solo(tracks["hard"], tracks["expert"], tm["bar_ticks"], vocal_active)
    if solo is None:
        raise AutochartError("chart", "no 4-8 bar window with 16 notes")
    song_length = (args.song_length_ms if args.song_length_ms is not None
                   else int(round(float(dec["length_s"]) * 1000.0)))
    preview = structure.pick_preview(secs["starts_ms"], secs["energies"], song_length)
    if not 0 < preview < song_length:
        preview = max(1, min(song_length - 1, preview))
    step(6, f"solo ticks {solo[0]}..{solo[1]}, preview {preview} ms")

    # 7. write. Chart ticks never depend on --delay-ms; it only sets the song.ini delay.
    delay = args.delay_ms if args.delay_ms is not None else int(tm["delay_ms"])
    song = {"name": args.name, "artist": args.artist, "genre": args.genre}
    chart_text = render_chart(song, tm, list(zip(secs["starts_tick"], secs["names"])), tracks, solo)
    ini_text = render_ini({"name": args.name, "artist": args.artist, "genre": args.genre,
                           "delay": delay, "preview_start_time": preview,
                           "song_length": song_length, "diff_guitar": 3})
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / "notes.chart", "w", encoding="utf-8", newline="\n") as f:
        f.write(chart_text)
    with open(out_dir / "song.ini", "w", encoding="utf-8", newline="\n") as f:
        f.write(ini_text)
    sha = hashlib.sha256(chart_text.encode("utf-8")).hexdigest()

    # statistics in game time (the written delay)
    tm_out = dict(tm, delay_ms=delay)
    for d in CHART_DIFFS:
        for x in tracks[d]:
            x["t"] = tick_to_sec(tm_out, x["tick"])
    per = {d: _track_stats(tracks[d], expert) for d in CHART_DIFFS}
    flags = band_flags(per)
    stats = {
        "id": args.id, "stem": "bass,drums,other,vocals" if mode == "lanes" else args.stem,
        "fill_stem": args.fill_stem,
        "fill_mode": args.fill_mode if args.fill_stem else None,
        "fill_share": _r4(sum(1 for x in expert if x.get("src") == args.fill_stem) / len(expert))
        if args.fill_stem else 0.0,
        "target_nps": args.target_nps,
        "difficulties": per,
        "expert_on_grid_share": _r4(quantize.on_grid_share(expert)),
        "direction_match": _r4(lanes.direction_match(expert)),
        "bpm": beats.get("bpm"), "constant_tempo": bool(beats["constant_tempo"]), "b_events": n_b,
        "delay_ms": delay, "analysis_delay_ms": int(tm["delay_ms"]), "song_length_ms": song_length,
        "sections": [{"tick": t, "ms": m, "name": nm}
                     for t, m, nm in zip(secs["starts_tick"], secs["starts_ms"], secs["names"])],
        "solo_ticks": list(solo), "preview_ms": preview,
        "band_tolerance": BAND_TOL, "band_flags": flags,
        "chart_sha256": sha,
    }
    if mode == "lanes":
        stats["mode"] = "lanes"
        stats["easy_lane_map"] = {str(k): v for k, v in easy_map.items()}
    stats_dir.mkdir(parents=True, exist_ok=True)
    with open(stats_dir / f"{args.id}.chart_stats.json", "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(stats, indent=2) + "\n")
    for d in CHART_DIFFS:
        s = per[d]
        print(f"  {d:6s} {s['notes']:4d} notes {s['notes_per_s']:.2f} n/s, max {s['max_per_1s']}/s, "
              f"keep {s['keep_share']:.2f}, chords {s['chord_count']}, sustains {s['sustain_share']:.2f}, "
              f"steps {list(s['lane_step_hist'].values())}", flush=True)
    for fl in flags:
        print(f"  BAND FLAG {fl['difficulty']} {fl['metric']} {fl['value']:.3f} outside {fl['band']} "
              f"+- {fl['tolerance']}", flush=True)
    if not flags:
        print("  BAND FLAGS none", flush=True)
    step(7, f"wrote {out_dir / 'notes.chart'}, song.ini (delay {delay}, song_length {song_length}), "
            f"{stats_dir / (args.id + '.chart_stats.json')}")
    print(f"CHART_OK {args.id} {sha}", flush=True)
    return 0


# ---------------------------------------------------------------- extract (player flow, STEM-02/04/05)
PLAYABLE_SUFFIXES = (".mp3", ".ogg", ".wav")
EXTRACT_STEPS = 3


def slugify(name: str) -> str:
    """Song folder name: lowercase, every run outside [a-z0-9] -> "_", trimmed, <= 40 chars, else "song"."""
    s = re.sub(r"[^a-z0-9]+", "_", (name or "").lower()).strip("_")[:40].strip("_")
    return s or "song"


def default_songs_root() -> Path:
    """Godot user://songs for project "UNDERTOW" on Windows (SongLibrary DEFAULT_SONGS_DIR)."""
    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise AutochartError("extract", "APPDATA is not set; pass --songs-root <folder>")
    return Path(appdata) / "Godot" / "app_userdata" / "UNDERTOW" / "songs"


def _extract_dest(root_arg: str | None, slug: str, force: bool) -> tuple[Path, Path]:
    """T-02.1-24 / T-02.1-25: dest is a direct child of the resolved Songs root; no overwrite without force."""
    root = Path(root_arg) if root_arg else default_songs_root()
    root.mkdir(parents=True, exist_ok=True)
    root_r = root.resolve()
    dest = (root_r / slug).resolve()
    if dest.parent != root_r or dest == root_r:
        raise AutochartError("extract", "refusing to write outside the Songs folder")
    if dest.exists() and not force:
        raise AutochartError("extract", f"{dest} already exists (use --force to replace)")
    return root_r, dest


def cmd_extract(args) -> int:
    import argparse as _ap
    import json
    import shutil

    from stages import decode as dec_stage

    src = Path(args.src).resolve()
    ext = src.suffix.lower()
    if not src.is_file():
        raise AutochartError("extract", f"{src} does not exist")
    if ext in (".flac", ".opus"):
        raise AutochartError("extract", f"Godot cannot play {ext}; convert to .ogg/.mp3/.wav")
    if ext not in PLAYABLE_SUFFIXES:
        raise AutochartError("extract", f"unsupported file type '{src.suffix}' (use .mp3, .ogg or .wav)")
    if not 0.5 <= args.target_nps <= 8.0:
        raise AutochartError("args", f"--target-nps {args.target_nps} must be within 0.5..8")
    name = args.name or src.stem
    slug = slugify(name)
    song_id = "user_" + slug
    work = work_dir(song_id)
    root, dest = _extract_dest(args.songs_root, slug, args.force)
    n = EXTRACT_STEPS

    # 1. analyze (decode, separate, beats, onsets, pitch). Stems from an earlier run are reused only
    #    when they came from the same source file.
    print(f"[1/{n}] analyze {src.name} -> {work}", flush=True)
    old = work / "decode.json"
    same_src = old.is_file() and json.loads(old.read_text(encoding="utf-8")).get(
        "source_sha256") == dec_stage._sha256(src)
    cmd_analyze(_ap.Namespace(id=song_id, src=str(src), from_stage="decode", godot_wav=None,
                              force=not same_src, stems=list(DEFAULT_STEMS)))

    # 2. chart into build/autochart/<id>/out (stats next to the intermediates, never reports/)
    out = work / "out"
    print(f"[2/{n}] chart ({args.mode}{' ' + args.stem if args.mode == 'single' else ''})", flush=True)
    cmd_chart(_ap.Namespace(id=song_id, out=str(out), stem=args.stem, fill_stem=None, fill_mode="bars",
                            target_nps=args.target_nps, name=name, artist=args.artist, genre=args.genre,
                            delay_ms=None, song_length_ms=None, godot_wav=None, stats_dir=str(work),
                            mode=args.mode))

    # 3. install: source audio byte-for-byte as song.<ext>, notes.chart, song.ini
    print(f"[3/{n}] install -> {dest}", flush=True)
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    shutil.copyfile(src, dest / f"song{ext}")
    shutil.copyfile(out / "notes.chart", dest / "notes.chart")
    shutil.copyfile(out / "song.ini", dest / "song.ini")
    print(f"Stems: {work / 'stems'}", flush=True)
    print(f"Song folder: {dest}", flush=True)
    print("In the game: Settings > LIBRARY > Rescan (or restart)", flush=True)
    print(f"EXTRACT_OK {dest}", flush=True)
    return 0


# ---------------------------------------------------------------- job / selftest (pack entry points, Phase 2.2.2)
EXIT_OK, EXIT_ERROR, EXIT_MEMORY, EXIT_PARENT_GONE = 0, 2, 3, 4
BELOW_NORMAL_PRIORITY_CLASS = 0x4000
VERSION_DIR_RE = re.compile(r"^v\d+$")


def job_error_code(e: Exception) -> str:
    """Stable player-facing code (AutochartJob.ERROR_TEXT key) for a pipeline failure."""
    from stages import job as jobmod
    code = getattr(e, "code", "") or ""
    if code in jobmod.CODES:
        return code
    stage = getattr(e, "stage", "")
    msg = getattr(e, "message", str(e))
    if (stage == "beats" and "found only" in msg) or (stage == "sections" and "bar lines" in msg):
        return "no_beats"
    if (stage == "stem_rank" and "no stem produced" in msg) or (
            stage == "chart" and ("Expert notes" in msg or "bar window" in msg)):
        return "no_notes"
    return "internal"


def is_dll_error(e: BaseException) -> bool:
    """D-15: a native DLL that cannot load (missing VC++ runtime) -> error code vcredist."""
    if not isinstance(e, (ImportError, OSError)):
        return False
    if getattr(e, "winerror", None) in (126, 193):
        return True
    text = str(e)
    return "DLL load failed" in text or "WinError 126" in text or "WinError 193" in text


def _pack_version_dir() -> Path | None:
    """<ac>/v<N> when this interpreter is the pack's <ac>/v<N>/rt/python.exe, else None (dev venvs)."""
    exe = Path(sys.executable).resolve()
    if exe.parent.name.lower() == "rt" and VERSION_DIR_RE.match(exe.parents[1].name):
        return exe.parents[1]
    return None


def _open_protocol(log_path: Path | None):
    """Protocol stream on a dup of the original stdout; fds 1 and 2 (and sys.stdout / sys.stderr) go to the
    log so tqdm, prints and native library warnings never reach the game's pipes (Pitfalls 1 and 2)."""
    proto = os.fdopen(os.dup(1), "w", encoding="ascii", buffering=1, newline="\n")
    target = None
    if log_path is not None:
        try:
            target = open(log_path, "a", encoding="utf-8", buffering=1)
        except OSError:
            target = None
    if target is None:
        log_path = None
        target = open(os.devnull, "w", encoding="utf-8")
    sys.stdout.flush()
    sys.stderr.flush()
    os.dup2(target.fileno(), 1)
    os.dup2(target.fileno(), 2)
    sys.stdout = sys.stderr = target
    import faulthandler
    faulthandler.enable(file=target)  # a native crash leaves its Python stack in the log
    return proto, target, log_path


def _process_hygiene() -> None:
    """Environment before any torch / demucs / huggingface import, lower priority, and the stdin-EOF
    watchdog (the game died -> exit 4, no orphan keeps burning CPU; Pitfall 4)."""
    import stat
    import threading

    os.environ["TQDM_DISABLE"] = "1"
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
    if sys.platform == "win32":
        try:
            import ctypes
            k32 = ctypes.windll.kernel32
            k32.SetPriorityClass(k32.GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS)
        except (OSError, AttributeError):
            pass
    try:
        is_pipe = stat.S_ISFIFO(os.fstat(0).st_mode)
    except (OSError, ValueError):
        is_pipe = False
    if is_pipe:
        # The watchdog reads a private dup of the pipe; fd 0 / sys.stdin become NUL. On Windows a pending
        # synchronous ReadFile serialises every other call on that file object (fstat, isatty,
        # GetFileType), so a library touching stdin during import would hang behind the watchdog.
        watch_fd = os.dup(0)
        null = os.open(os.devnull, os.O_RDONLY)
        os.dup2(null, 0)
        os.close(null)
        sys.stdin = open(os.devnull, "r", encoding="utf-8")

        def _watch():
            try:
                while os.read(watch_fd, 4096):
                    pass
            except OSError:
                pass
            os._exit(EXIT_PARENT_GONE)
        threading.Thread(target=_watch, name="stdin-eof-watchdog", daemon=True).start()


def _bp_mode(raw: dict, version_dir: Path | None):
    """("worker", python) with a dev "bp_python" key or a pack rt310/python.exe, else ("inprocess", None)."""
    from stages.job import JobError
    bp = raw.get("bp_python")
    if bp is not None:
        if not isinstance(bp, str) or not bp or not Path(bp).is_absolute() or not Path(bp).is_file():
            raise JobError("bad_job", "bp_python must be the absolute path of an existing interpreter")
        return "worker", Path(bp).resolve()
    if version_dir is not None:
        rt310 = version_dir / "rt310" / "python.exe"
        if rt310.is_file():
            return "worker", rt310
    return "inprocess", None


def _job_run(cfg: dict, emit, log_path: Path | None) -> int:
    import json
    import shutil

    from stages import decode, job as jobmod, runtime

    def progress(stage_name):
        last = [-1.0]

        def cb(frac):
            f = round(float(frac), 2)
            if f > last[0]:
                last[0] = f
                emit.progress(stage_name, f)
        return cb

    emit.emit(ev="start", pid=os.getpid())
    src = cfg["src"]
    sha = decode._sha256(src)
    work = jobmod.work_dir_for(cfg["work_root"], sha)
    work.mkdir(parents=True, exist_ok=True)
    emit.emit(ev="work", dir=str(work))
    reused = jobmod.is_analyzed(work, sha)
    rank_json = work / "stem_rank.json"
    stems = list(DEFAULT_STEMS)
    if not reused:
        if rank_json.exists():
            rank_json.unlink()
        emit.stage("decode")
        info = decode.decode(src, work)
        if float(info["length_s"]) > jobmod.PACK_MAX_S:
            raise jobmod.JobError("too_long", "Songs longer than 10 minutes are not supported", stage="decode")
        emit.progress("decode", 1.0)
        emit.stage("separate")
        from stages import separate
        separate.separate(work, force=False, on_progress=progress("separate"))
        emit.stage("beats")
        from stages import beats
        beats.beats_stage(work)
        emit.progress("beats", 1.0)
        emit.stage("onsets")
        from stages import onsets
        onsets.onsets_stage(work, stems)
        emit.progress("onsets", 1.0)
        emit.stage("pitch")
        from stages import pitch_bp
        for i, s in enumerate(stems):
            pitch_bp.pitch_stage(work, [s])
            emit.progress("pitch", (i + 1) / len(stems))
        jobmod.mark_analyzed(work, sha)
    else:
        emit.emit(ev="warn", msg="Reusing separated instruments")
        for name in ("decode", "separate", "beats", "onsets", "pitch"):
            emit.stage(name)
            emit.progress(name, 1.0)

    # rank: required for auto, best effort for single / lanes (the UI offers "Re-chart with ...")
    emit.stage("rank")
    mode = cfg["mode"]
    ranking, recommended = [], None
    res = None
    if rank_json.is_file():
        try:
            res = json.loads(rank_json.read_text(encoding="utf-8"))
        except ValueError:
            res = None
    if res is None:
        import stem_rank
        try:
            res = stem_rank.rank(work)
            rank_json.write_text(json.dumps(res, indent=2) + "\n", encoding="utf-8")
        except AutochartError:
            if mode == "auto":
                raise
            res = None
    if res is not None:
        ranking, recommended = list(res["ranking"]), res["recommended"]
        emit.emit(ev="rank", recommended=recommended, ranking=ranking)
    emit.progress("rank", 1.0)

    emit.stage("chart")
    if mode == "auto":
        stem = recommended
    else:
        stem = cfg["stem"]
    chart_mode = "lanes" if mode == "lanes" else "single"
    out = work / ("out_lanes" if mode == "lanes" else f"out_{stem}")
    if out.exists():
        shutil.rmtree(out)
    slug_base = slugify(cfg["name"])
    song_id = "user_" + slug_base
    _chart_core(work, out, work, stem, None, "bars", cfg["target_nps"], cfg["name"], cfg["artist"],
                cfg["genre"], None, None, None, chart_mode, song_id)
    stats = json.loads((work / f"{song_id}.chart_stats.json").read_text(encoding="utf-8"))
    expert_nps = float(stats["difficulties"]["expert"]["notes_per_s"])
    emit.progress("chart", 1.0)

    emit.stage("install")
    jobmod.write_song_audio(src, out)
    slug = jobmod.unique_slug(cfg["songs_root"], slug_base, cfg["replace"])
    folder = jobmod.install_atomic(out, cfg["songs_root"], slug, cfg["replace"])
    jobmod.touch(work)
    emit.progress("install", 1.0)
    emit.emit(ev="done", folder=str(folder), slug=folder.name, stem="lanes" if mode == "lanes" else stem,
              mode=mode, expert_nps=round(expert_nps, 4), reused=bool(reused), ranking=ranking,
              log=str(log_path) if log_path else "")
    return EXIT_OK


def _emit_failure(emit, e: BaseException, stage: str, log_path) -> int:
    import errno
    import traceback

    traceback.print_exception(type(e), e, e.__traceback__)
    log = str(log_path) if log_path else ""
    if isinstance(e, MemoryError):
        emit.emit(ev="error", code="memory", stage=stage, msg="Not enough memory for a song this long", log=log)
        return EXIT_MEMORY
    if isinstance(e, AutochartError):
        emit.emit(ev="error", code=job_error_code(e), stage=e.stage, msg=e.message, log=log)
    elif is_dll_error(e):
        emit.emit(ev="error", code="vcredist", stage=stage, msg=f"{type(e).__name__}: {e}", log=log)
    elif isinstance(e, OSError) and (e.errno == errno.ENOSPC or getattr(e, "winerror", None) in (39, 112)):
        emit.emit(ev="error", code="disk", stage=stage, msg=f"{type(e).__name__}: {e}", log=log)
    else:
        emit.emit(ev="error", code="internal", stage=stage, msg=f"{type(e).__name__}: {e}", log=log)
    return EXIT_ERROR


def cmd_job(args) -> int:
    """Pack entry point (D-05): one process does decode -> separate -> beats -> onsets -> pitch -> rank ->
    chart -> install. stdout carries only protocol events; everything else goes to <job folder>/log.txt.
    Exit codes: 0 ok, 2 an error event was printed, 3 MemoryError, 4 the game closed stdin."""
    from stages import job as jobmod

    job_path = Path(args.job)
    folder = job_path.parent
    log_path = folder / "log.txt" if folder.is_dir() else None
    proto, _log, log_path = _open_protocol(log_path)
    emit = jobmod.Emitter(proto)
    _process_hygiene()
    try:
        ac_root = Path(args.ac_root).resolve() if args.ac_root else None
        version_dir = _pack_version_dir()
        if ac_root is None and version_dir is not None:
            ac_root = version_dir.parent
        cfg = jobmod.load_job(job_path, ac_root)
        # before any numba / librosa / torch import (load_job is stdlib only)
        numba_cache = (cfg["work_root"].parent / "cache" / "numba").resolve()
        numba_cache.mkdir(parents=True, exist_ok=True)
        os.environ["NUMBA_CACHE_DIR"] = str(numba_cache)
        from stages import runtime
        bp_mode, bp_python = _bp_mode(cfg["raw"], version_dir)
        runtime.configure_pack(cfg["models_root"], bp_mode, bp_python, HERE / "bp_worker.py", cfg["threads"])
        os.environ.update(runtime.model_env())
        print(f"autochart job {job_path} pid {os.getpid()} bp_mode {bp_mode} threads {cfg['threads']}",
              flush=True)
        return _job_run(cfg, emit, log_path)
    except BaseException as e:  # noqa: BLE001 - every failure becomes one error event
        if isinstance(e, SystemExit):
            raise
        return _emit_failure(emit, e, getattr(e, "stage", "job"), log_path)
    finally:
        sys.stdout.flush()


def _selftest_run(models_root: Path, emit) -> int:
    import socket
    import tempfile

    t0 = time.perf_counter()
    ckpt = models_root / "torch" / "hub" / "checkpoints" / "beat_this-final0.ckpt"
    if not (models_root / "hf").is_dir() or not (models_root / "torch").is_dir() or not ckpt.is_file():
        raise AutochartError("selftest", f"models are missing under {models_root}", code="selftest")

    def _blocked(*_a, **_k):
        raise OSError("network disabled in selftest")
    socket.socket.connect = _blocked
    socket.socket.connect_ex = _blocked
    socket.create_connection = _blocked
    socket.getaddrinfo = _blocked

    from stages import runtime
    bp_mode, bp_python = _bp_mode({}, _pack_version_dir())
    runtime.configure_pack(models_root, bp_mode, bp_python, HERE / "bp_worker.py", 0)
    os.environ.update(runtime.model_env())

    import numpy as np
    import soundfile as sf
    from demucs.pretrained import get_model

    if get_model("htdemucs") is None:
        raise AutochartError("selftest", "htdemucs did not load", code="selftest")
    sr = 22050
    n = 10 * sr
    clicks = np.zeros(n, dtype=np.float32)
    for k in range(0, n, sr // 2):  # 120 BPM
        clicks[k:k + 200] = np.hanning(400)[200:].astype(np.float32)
    from beat_this.inference import Audio2Beats
    a2b = Audio2Beats(checkpoint_path=str(ckpt), device="cpu", dbn=False)
    beats, _downs = a2b(clicks, sr)
    if len(beats) < 10:
        raise AutochartError("selftest", f"beat_this found {len(beats)} beats in 10 s of 120 BPM clicks",
                             code="selftest")
    from stages import pitch_bp
    import json
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "sine.wav"
        t = np.arange(n, dtype=np.float64) / sr
        sf.write(str(wav), (0.5 * np.sin(2 * np.pi * 440.0 * t)).astype(np.float32), sr, subtype="PCM_16")
        out = Path(td) / "bp.json"
        pitch_bp.run_bp(wav, out)
        notes = json.loads(out.read_text(encoding="utf-8"))["notes"]
    if not any(abs(int(x[2]) - 69) <= 1 for x in notes):
        raise AutochartError("selftest", f"Basic Pitch found no A4 in a 440 Hz sine ({len(notes)} notes)",
                             code="selftest")
    print(f"selftest: htdemucs ok, {len(beats)} beats, {len(notes)} Basic Pitch notes, bp_mode {bp_mode}",
          flush=True)
    emit.emit(ev="selftest", ok=True, seconds=round(time.perf_counter() - t0, 1))
    return EXIT_OK


def cmd_selftest(args) -> int:
    """Offline model check run right after the pack is installed (RESEARCH Pattern 3 item 11): loads
    htdemucs, runs beat_this and Basic Pitch on generated audio with every socket call blocked."""
    from stages import job as jobmod

    version_dir = _pack_version_dir()
    if args.models_root:
        models_root = Path(args.models_root).resolve()
    elif version_dir is not None:
        models_root = version_dir / "models"
    else:
        models_root = (ROOT / "build" / "autochart" / "pack_models").resolve()
    if args.log:
        log_path = Path(args.log)
    else:
        log_path = models_root.parent / "selftest_log.txt" if models_root.parent.is_dir() else None
    proto, _log, log_path = _open_protocol(log_path)
    emit = jobmod.Emitter(proto)
    _process_hygiene()
    if version_dir is not None:
        numba_cache = version_dir.parent / "cache" / "numba"
        try:
            numba_cache.mkdir(parents=True, exist_ok=True)
            os.environ["NUMBA_CACHE_DIR"] = str(numba_cache)
        except OSError:
            pass
    try:
        return _selftest_run(models_root, emit)
    except BaseException as e:  # noqa: BLE001
        if isinstance(e, SystemExit):
            raise
        import traceback
        traceback.print_exception(type(e), e, e.__traceback__)
        log = str(log_path) if log_path else ""
        if isinstance(e, MemoryError):
            emit.emit(ev="error", code="memory", stage="selftest", msg="Not enough memory", log=log)
            return EXIT_MEMORY
        code = "vcredist" if is_dll_error(e) else "selftest"
        msg = e.message if isinstance(e, AutochartError) else f"{type(e).__name__}: {e}"
        emit.emit(ev="error", code=code, stage="selftest", msg=msg, log=log)
        return EXIT_ERROR
    finally:
        sys.stdout.flush()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="autochart", description="UNDERTOW audio-to-chart tool")
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("analyze", help="decode, separate, beats, onsets, pitch")
    a.add_argument("--id", required=True)
    a.add_argument("--src")
    a.add_argument("--from-stage", choices=STAGES, default="decode")
    a.add_argument("--godot-wav")
    a.add_argument("--force", action="store_true")
    a.add_argument("--stems", nargs="+", default=DEFAULT_STEMS,
                   choices=DEFAULT_STEMS, help="stems for the onsets / pitch stages")
    c = sub.add_parser("chart", help="intermediates -> notes.chart, song.ini, chart stats")
    c.add_argument("--id", required=True)
    c.add_argument("--out", required=True, help="song folder (inside the repo songs/ or build/)")
    c.add_argument("--stem", required=True, choices=DEFAULT_STEMS)
    c.add_argument("--fill-stem", choices=DEFAULT_STEMS)
    c.add_argument("--fill-mode", choices=("bars", "sections"), default="bars",
                   help="bars: fill bars with no primary onsets; sections: sparse sections take the fill stem")
    c.add_argument("--target-nps", type=float, default=3.5)
    c.add_argument("--name", required=True)
    c.add_argument("--artist", required=True)
    c.add_argument("--genre", required=True)
    c.add_argument("--delay-ms", type=int)
    c.add_argument("--song-length-ms", type=int)
    c.add_argument("--godot-wav")
    c.add_argument("--stats-dir", default=str(ROOT / "tools" / "autochart" / "reports"))
    x = sub.add_parser("extract", help="audio file -> stems + a song folder in the UNDERTOW Songs folder")
    x.add_argument("--src", required=True, help=".mp3, .ogg or .wav file you own")
    x.add_argument("--name", help="song name (default: the file name)")
    x.add_argument("--artist", default="Unknown")
    x.add_argument("--genre", default="Unknown")
    x.add_argument("--mode", choices=("single", "lanes"), default="single",
                   help="single: one instrument over 4 lanes; lanes: bass, drums, other, vocals left to right")
    x.add_argument("--stem", choices=DEFAULT_STEMS, default="other", help="instrument for --mode single")
    x.add_argument("--target-nps", type=float, default=3.5)
    x.add_argument("--songs-root", help="Songs folder (default %%APPDATA%%/Godot/app_userdata/UNDERTOW/songs)")
    x.add_argument("--force", action="store_true", help="replace an existing song folder")
    j = sub.add_parser("job", help="pack entry point: job.json -> song folder, JSON events on stdout")
    j.add_argument("job", help="job.json written by the game")
    j.add_argument("--ac-root", help="autocharter folder that must contain work_root (tests / dev runs)")
    t = sub.add_parser("selftest", help="pack check: load the models offline and run them on generated audio")
    t.add_argument("--models-root", help="folder with hf/ and torch/ (default: the pack's models folder)")
    t.add_argument("--log", help="log file (default: selftest_log.txt next to the models folder)")
    args = ap.parse_args(argv)
    if args.cmd == "job":
        return cmd_job(args)
    if args.cmd == "selftest":
        return cmd_selftest(args)
    try:
        if args.cmd == "analyze":
            return cmd_analyze(args)
        if args.cmd == "chart":
            return cmd_chart(args)
        if args.cmd == "extract":
            return cmd_extract(args)
    except AutochartError as e:
        print(f"AUTOCHART_ERROR {e.stage}: {e.message}", file=sys.stderr, flush=True)
        return 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
