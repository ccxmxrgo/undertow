"""Chart writer: deterministic Clone Hero .chart and song.ini text (D-05, STEM-05, RESEARCH Pattern 6).

Stdlib only. Output format copies songs/synth_wave_april/notes.chart: two-space indent, LF line
endings, trailing newline, Resolution 192, sections Easy, Medium, Hard, Expert. Lanes are written as
`N 0..3` (identity under ChartImporter._collect); 4 (Orange, merges into lane 3) and 7 (open, becomes
a chord) are rejected. Text is a pure function of the input: no timestamps, ints only, sorted events,
so the song hash (SONG-05) is stable. Write it to disk with newline="" (or as bytes) so Windows does
not turn LF into CRLF.

Trust boundary (T-02.1-05): name/artist/genre/section names lose `"` and control characters
(CR/LF and other C0 -> space), so metadata cannot break out of a quoted value or start a new line.
"""
from __future__ import annotations

CHARTER = "UNDERTOW autochart"
DIFFICULTIES = (("easy", "EasySingle"), ("medium", "MediumSingle"), ("hard", "HardSingle"),
                ("expert", "ExpertSingle"))
INI_INT_KEYS = ("delay", "preview_start_time", "song_length", "diff_guitar")


def sanitize(s) -> str:
    """Remove double quotes; CR, LF and other control characters become a space; trim the edges."""
    out = []
    for ch in str(s):
        if ch == '"':
            continue
        out.append(" " if (ord(ch) < 32 or ord(ch) == 127) else ch)
    return "".join(out).strip()


def _int(v, what: str, lo: int | None = None) -> int:
    if isinstance(v, bool) or not isinstance(v, int):
        raise ValueError(f"{what} must be an int, got {v!r}")
    if lo is not None and v < lo:
        raise ValueError(f"{what} must be >= {lo}, got {v}")
    return v


def _lane(v) -> int:
    v = _int(v, "lane")
    if not 0 <= v <= 3:
        raise ValueError(f"lane must be 0..3 (D-05), got {v}")
    return v


def _track_lines(notes: list[dict], solo: tuple[int, int] | None) -> list[str]:
    rows: list[tuple[int, int, int, str]] = []  # (tick, order, lane, text); solo < N < soloend
    seen: set[tuple[int, int]] = set()
    for n in notes:
        tick = _int(n["tick"], "tick", 0)
        length = _int(n.get("len", 0), "len", 0)
        lanes = n.get("lanes") or []
        if not lanes:
            raise ValueError(f"note at tick {tick} has no lanes")
        for lane in lanes:
            lane = _lane(lane)
            if (tick, lane) in seen:
                raise ValueError(f"duplicate note: tick {tick} lane {lane}")
            seen.add((tick, lane))
            rows.append((tick, 1, lane, f"  {tick} = N {lane} {length}"))
    if solo is not None:
        rows.append((solo[0], 0, 0, f"  {solo[0]} = E solo"))
        rows.append((solo[1], 2, 0, f"  {solo[1]} = E soloend"))
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    return [r[3] for r in rows]


def render_chart(song: dict, tm: dict, sections: list[tuple[int, str]],
                 tracks: dict[str, list[dict]], solo: tuple[int, int] | None) -> str:
    res = _int(tm["resolution"], "resolution", 1)
    if solo is not None:
        s0, s1 = _int(solo[0], "solo start", 0), _int(solo[1], "solo end", 0)
        if s1 <= s0:
            raise ValueError(f"solo end {s1} must be after solo start {s0}")
        solo = (s0, s1)
    for key, _ in DIFFICULTIES:
        if key not in tracks:
            raise ValueError(f"missing difficulty: {key}")

    lines = [
        "[Song]", "{",
        f'  Name = "{sanitize(song.get("name", ""))}"',
        f'  Artist = "{sanitize(song.get("artist", ""))}"',
        f'  Charter = "{CHARTER}"',
        f"  Resolution = {res}",
        f'  Genre = "{sanitize(song.get("genre", ""))}"',
        "}",
        "[SyncTrack]", "{",
    ]
    sync = []
    for e in tm["events"]:
        tick = _int(e[0], "event tick", 0)
        kind = e[1]
        if kind not in ("TS", "B"):
            raise ValueError(f"unknown SyncTrack event {kind!r}")
        val = _int(e[2], kind, 1)
        if kind == "B" and not 1000 <= val <= 2000000:
            raise ValueError(f"B {val} outside the importer's 1..2000 BPM")
        sync.append((tick, 0 if kind == "TS" else 1, f"  {tick} = {kind} {val}"))
    sync.sort(key=lambda r: (r[0], r[1]))  # stable: equal (tick, kind) keep input order
    lines += [r[2] for r in sync]
    lines += ["}", "[Events]", "{"]
    secs = sorted(((_int(t, "section tick", 0), sanitize(name)) for t, name in sections),
                  key=lambda s: s[0])
    lines += [f'  {t} = E "section {name}"' for t, name in secs]
    lines.append("}")
    for key, header in DIFFICULTIES:
        lines += [f"[{header}]", "{"]
        lines += _track_lines(tracks[key], solo)
        lines.append("}")
    return "\n".join(lines) + "\n"


def render_ini(meta: dict) -> str:
    for k in ("name", "artist", "genre") + INI_INT_KEYS:
        if k not in meta:
            raise ValueError(f"song.ini needs {k}")
    lines = [
        "[song]",
        f"name = {sanitize(meta['name'])}",
        f"artist = {sanitize(meta['artist'])}",
        f"charter = {CHARTER}",
        f"genre = {sanitize(meta['genre'])}",
    ]
    for k in INI_INT_KEYS:
        lines.append(f"{k} = {_int(meta[k], k)}")
    return "\n".join(lines) + "\n"
