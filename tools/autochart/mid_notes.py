"""Unique note times of one difficulty from a Clone Hero / Guitar Hero notes.mid (stdlib only).

  python -I -B tools/autochart/mid_notes.py <notes.mid> <out.json> [--track "PART GUITAR"] [--lo 96 --hi 100]

Parses a Standard MIDI File (header division, running status, meta / sysex events), builds the tempo
map from every FF 51 tempo meta event (default 120 BPM before the first), takes the note-on ticks of
pitches lo..hi (Expert gems 96-100) in the named track, converts them to seconds through the tempo
map and writes a JSON list of unique note times (a chord counts once). Used to feed reference charts
(the Neversoft "Before I Forget" calibration, SPEC req 5) into note_sync.py --notes-json.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path


def _vlq(data: bytes, i: int):
    v = 0
    while True:
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80:
            return v, i


def read_smf(path):
    data = Path(path).read_bytes()
    if data[:4] != b"MThd":
        raise ValueError("not a Standard MIDI File")
    hlen = struct.unpack(">I", data[4:8])[0]
    _fmt, ntrk, division = struct.unpack(">HHH", data[8:14])
    if division & 0x8000:
        raise ValueError("SMPTE time division is not supported")
    i = 8 + hlen
    tracks = []  # [{"name": str|None, "notes": [(tick, on, pitch)], "tempos": [(tick, us)]}]
    for _ in range(ntrk):
        if data[i:i + 4] != b"MTrk":
            raise ValueError("bad track chunk at %d" % i)
        tlen = struct.unpack(">I", data[i + 4:i + 8])[0]
        j, end = i + 8, i + 8 + tlen
        tick, status = 0, 0
        tr = {"name": None, "notes": [], "tempos": []}
        while j < end:
            delta, j = _vlq(data, j)
            tick += delta
            b = data[j]
            if b == 0xFF:
                mtype = data[j + 1]
                ln, k = _vlq(data, j + 2)
                body = data[k:k + ln]
                j = k + ln
                if mtype == 0x03 and tr["name"] is None:
                    tr["name"] = body.decode("latin-1")
                elif mtype == 0x51 and ln == 3:
                    tr["tempos"].append((tick, (body[0] << 16) | (body[1] << 8) | body[2]))
                elif mtype == 0x2F:
                    break
                continue
            if b in (0xF0, 0xF7):
                ln, k = _vlq(data, j + 1)
                j = k + ln
                continue
            if b & 0x80:
                status = b
                j += 1
            elif status == 0:
                raise ValueError("running status without a status byte")
            kind = status & 0xF0
            if kind in (0xC0, 0xD0):
                j += 1
                continue
            d1, d2 = data[j], data[j + 1]
            j += 2
            if kind == 0x90:
                tr["notes"].append((tick, d2 > 0, d1))
            elif kind == 0x80:
                tr["notes"].append((tick, False, d1))
        tracks.append(tr)
        i = end
    return division, tracks


def tempo_map(tracks):
    tempos = sorted(t for tr in tracks for t in tr["tempos"])
    return tempos


def tick_to_sec(tempos, res, tick):
    s, pt, pu = 0.0, 0, 500000
    for tt, uu in tempos:
        if tt > tick:
            break
        s += (tt - pt) / res * pu / 1e6
        pt, pu = tt, uu
    return s + (tick - pt) / res * pu / 1e6


def note_times(path, track="PART GUITAR", lo=96, hi=100):
    res, tracks = read_smf(path)
    tempos = tempo_map(tracks)
    sel = [tr for tr in tracks if tr["name"] == track]
    if not sel:
        raise ValueError("track %r not found (have %s)" % (track, [tr["name"] for tr in tracks]))
    ticks = sorted({t for t, on, p in sel[0]["notes"] if on and lo <= p <= hi})
    return res, len(tempos), [tick_to_sec(tempos, res, t) for t in ticks]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mid")
    ap.add_argument("out")
    ap.add_argument("--track", default="PART GUITAR")
    ap.add_argument("--lo", type=int, default=96)
    ap.add_argument("--hi", type=int, default=100)
    a = ap.parse_args(argv)
    res, ntempo, times = note_times(a.mid, a.track, a.lo, a.hi)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(times), encoding="utf-8")
    print("MID_NOTES resolution=%d tempo_events=%d track=%s pitches=%d-%d unique_note_times=%d"
          % (res, ntempo, a.track, a.lo, a.hi, len(times)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
