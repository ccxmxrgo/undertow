"""Offline analysis of a frame-probe CSV written by the playtest driver (build/playtest/*_probe.csv)
and of the game's own user://drift_log.csv.

Usage: python tools/playtest/analyze_probe.py build/playtest/drift_probe.csv [path/to/drift_log.csv]

Reports, for frames where audio is valid and song_time is in [1, 299.5] s:
  * raw audio clock vs system clock rate (ppm) from a least-squares fit of the audio target
  * jitter of the raw audio target around that fit (Godot mix-chunk stepping)
  * song_time vs the fitted (smooth) audio clock: the D-30 "note times vs expected song_time" figure
  * song_time vs the instantaneous audio target
  * the same song_time error per 60 s window (drift trend)
"""
import csv
import statistics as S
import sys


def fit(x, y):
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    b = sum((a - mx) * (c - my) for a, c in zip(x, y)) / sum((a - mx) ** 2 for a in x)
    return my - b * mx, b


def st(v):
    av = sorted(abs(x) for x in v)
    return {"n": len(v), "mean": round(S.mean(v), 3), "std": round(S.pstdev(v), 3),
            "p99_abs": round(av[int(0.99 * len(av))], 3), "max_abs": round(av[-1], 3)}


def main(probe, drift_log=None):
    t0 = None
    X, ST, TG = [], [], []
    for r in csv.DictReader(open(probe)):
        s = float(r["song_time"])
        if r["paused"] == "1" or r["audio_valid"] != "1" or s < 1.0 or s > 299.5:
            continue
        tk = int(r["ticks_usec"])
        t0 = t0 if t0 is not None else tk
        X.append((tk - t0) / 1e6)
        ST.append(s)
        TG.append(float(r["audio_target"]))
    a, b = fit(X, TG)
    print("audio clock vs system clock: %.2f ppm" % ((b - 1) * 1e6))
    print("raw audio target jitter around fit (ms):", st([(y - (a + b * x)) * 1000 for x, y in zip(X, TG)]))
    print("song_time - smooth audio clock (ms):", st([(y - (a + b * x)) * 1000 for x, y in zip(X, ST)]))
    print("song_time - instantaneous audio target (ms):", st([(s - t) * 1000 for s, t in zip(ST, TG)]))
    for w in range(0, int(max(X)) + 1, 60):
        v = [(y - (a + b * x)) * 1000 for x, y in zip(X, ST) if w <= x < w + 60]
        if v:
            print("  window %3d-%3d s" % (w, w + 60), st(v))
    if drift_log:
        rows = list(csv.DictReader(open(drift_log)))
        xs = [float(r["elapsed_s"]) for r in rows if float(r["elapsed_s"]) >= 1.0]
        ds = [float(r["drift_ms"]) for r in rows if float(r["elapsed_s"]) >= 1.0]
        a2, b2 = fit(xs, ds)
        print("drift_log.csv rows %d, drift_ms (t>=1 s):" % len(rows), st(ds),
              "min %.2f max %.2f trend %.4f ms/min first %.2f last %.2f" % (min(ds), max(ds), b2 * 60, ds[0], ds[-1]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
