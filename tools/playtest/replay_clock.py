"""Tune ClockModel.slew_tau_s offline against a recorded frame probe (240 Hz real capture).

Usage:
  python tools/playtest/replay_clock.py build/playtest/drift_probe.csv --tau 0.25
  python tools/playtest/replay_clock.py build/playtest/drift_probe.csv --sweep
  python tools/playtest/replay_clock.py build/playtest/drift_probe.csv --legacy   (per-frame 0.15)

Re-implements ClockModel.update (time-constant smoothing, snap, monotonic) for tuning only; the
GDScript tests are authoritative. For each of 30/60/144/240 fps the recorded frames nearest each
k/fps tick are replayed and song_time minus the least-squares-fitted smooth audio clock is
reported (p50/p99/max, ms), the metric of analyze_probe.py.
Exit code 1 if any rate has p99 > 2.0 ms (single --tau / --legacy runs).
"""
import argparse
import csv
import math
import sys

SNAP_S = 0.050
RATES = (30, 60, 144, 240)
LIMIT_MS = 2.0


def load(path):
    rows = []
    for r in csv.DictReader(open(path)):
        if r["paused"] == "1" or r["audio_valid"] != "1":
            continue
        rows.append((int(r["ticks_usec"]), float(r["audio_target"])))
    return rows


def fit(x, y):
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    b = sum((a - mx) * (c - my) for a, c in zip(x, y)) / sum((a - mx) ** 2 for a in x)
    return my - b * mx, b


def resample(rows, fps):
    t0 = rows[0][0]
    step = 1e6 / fps
    out, k, i = [], 0, 0
    while True:
        want = t0 + k * step
        if want > rows[-1][0]:
            break
        while i + 1 < len(rows) and abs(rows[i + 1][0] - want) <= abs(rows[i][0] - want):
            i += 1
        if not out or rows[i][0] != out[-1][0]:
            out.append(rows[i])
        k += 1
    return out


def run(frames, tau, legacy=False):
    t0 = frames[0][0]
    a, b = fit([(t - t0) / 1e6 for t, _ in frames], [g for _, g in frames])
    song = frames[0][1]
    prev = frames[0][0]
    errs = []
    for tk, tgt in frames[1:]:
        dt = (tk - prev) / 1e6
        pred = song + dt
        err = tgt - pred
        if abs(err) > SNAP_S:
            pred = tgt
        elif legacy:
            pred += err * 0.15
        else:
            alpha = 1.0 if tau <= 0 else 1.0 - math.exp(-dt / tau)
            pred += err * alpha
        song = max(song, pred)
        prev = tk
        x = (tk - t0) / 1e6
        if x > 2.0:
            errs.append((song - (a + b * x)) * 1000.0)
    ae = sorted(abs(e) for e in errs)
    n = len(ae)
    return ae[n // 2], ae[int(0.99 * n)], ae[-1]


def report(rows, tau, legacy):
    ok = True
    for fps in RATES:
        p50, p99, mx = run(resample(rows, fps), tau, legacy)
        print("  %3d fps  p50 %.3f  p99 %.3f  max %.3f ms" % (fps, p50, p99, mx))
        ok = ok and p99 <= LIMIT_MS
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("probe")
    ap.add_argument("--tau", type=float)
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--legacy", action="store_true")
    args = ap.parse_args()
    rows = [r for r in load(args.probe) if r[0] >= 0]
    if args.sweep:
        print("tau_s   " + "  ".join("p99@%d" % f for f in RATES))
        for tau in (0.05, 0.075, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5):
            p99s = [run(resample(rows, f), tau)[1] for f in RATES]
            print("%.3f   " % tau + "  ".join("%6.3f" % p for p in p99s))
        print("legacy 0.15/frame  " + "  ".join(
            "%6.3f" % run(resample(rows, f), 0, True)[1] for f in RATES))
        return 0
    if args.legacy:
        print("legacy per-frame slew 0.15:")
        report(rows, 0, True)
        return 0
    print("tau = %.3f s:" % args.tau)
    return 0 if report(rows, args.tau, False) else 1


if __name__ == "__main__":
    sys.exit(main())
