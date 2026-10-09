"""Fine beat-grid offset for the bundled songs (stdlib only, 1 ms resolution). Plan 02-06.

Usage (from the repo root):
  python -I tools/charting/grid_offset.py <file.wav> <bpm> <delay_ms> [start_s] [end_s]

Reads a 16-bit PCM WAV whose t = 0 is audio position 0 of the song (decoded or recorded from
Godot), builds a 1 ms energy envelope and a 3 ms rising-edge onset curve, then:
  1. finds the beat phase (ms, mod one beat) that maximises the mean onset strength on a grid of
     beats (parabolic refinement between the 1 ms bins),
  2. folds the envelope over one beat and reports the steepest rise of the folded profile
     (an independent estimate of the same attack),
  3. picks the bar phase (beat phase + 0..3 beats) with the strongest downbeats,
  4. prints the error of the chart grid: chart beat k is at delay_ms + k * beat, so
     error = measured beat phase - (delay_ms mod beat), wrapped to +-half a beat,
  5. attack starts (the 200 strongest note attacks: 10 ms after / 20 ms before energy ratio,
     250 ms apart) within +-60 ms of the chart's downbeats and beats: count, median, quartiles
     and the median error. This is the number used for the +-5 ms check (soft synth attacks make
     the onset-curve peak in 1.-3. land 10-15 ms after the audible start).
Positive error = the music hits AFTER the chart grid (increase delay by that much).
"""
import array
import sys
import wave


def load_mono(path):
    w = wave.open(path, "rb")
    if w.getsampwidth() != 2:
        raise SystemExit("only 16-bit PCM is supported")
    ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    a = array.array("h")
    a.frombytes(raw)
    if ch == 1:
        return list(a), rate
    return [(a[i] + a[i + 1]) * 0.5 for i in range(0, len(a) - 1, ch)], rate


def envelope_ms(mono, rate):
    hop = rate / 1000.0
    env = []
    i = 0
    n = len(mono)
    k = 0
    while True:
        a = int(round(k * hop))
        b = int(round((k + 1) * hop))
        if b > n:
            break
        seg = mono[a:b]
        env.append(sum(abs(x) for x in seg) / max(len(seg), 1))
        k += 1
    return env


def wrap(x, period):
    return (x + period / 2.0) % period - period / 2.0


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    path, bpm, delay = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    start_s = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    mono, rate = load_mono(path)
    env = envelope_ms(mono, rate)
    end_ms = int(float(sys.argv[5]) * 1000) if len(sys.argv) > 5 else len(env) - 5
    ons = [0.0] * len(env)
    for i in range(3, len(env)):
        ons[i] = max(env[i] - env[i - 3], 0.0)
    beat = 60000.0 / bpm
    nb = int(round(beat))
    t0 = int(start_s * 1000)

    def score(phase):
        tot, cnt = 0.0, 0
        t = t0 + ((phase - t0) % beat)
        while t < end_ms - 2:
            i = int(round(t))
            tot += max(ons[i - 1:i + 2])
            cnt += 1
            t += beat
        return tot / max(cnt, 1)

    scores = [score(p) for p in range(nb)]
    best = max(range(nb), key=lambda p: scores[p])
    l, c, r = scores[(best - 1) % nb], scores[best], scores[(best + 1) % nb]
    den = l - 2 * c + r
    refine = 0.5 * (l - r) / den if den != 0 else 0.0
    phase = (best + refine) % beat

    # folded envelope profile over one beat
    prof = [0.0] * nb
    cnt = [0] * nb
    for i in range(t0, end_ms):
        j = int(i % beat) % nb
        prof[j] += env[i]
        cnt[j] += 1
    prof = [prof[j] / max(cnt[j], 1) for j in range(nb)]
    rise = [prof[j] - prof[(j - 5) % nb] for j in range(nb)]
    fold = max(range(nb), key=lambda j: rise[j]) - 2.5  # centre of the 5 ms difference window

    # bar phase: strongest downbeats among the 4 beat offsets
    bar = beat * 4

    def bar_score(ph):
        tot, n = 0.0, 0
        t = t0 + ((ph - t0) % bar)
        while t < end_ms - 2:
            i = int(round(t))
            tot += max(ons[i - 2:i + 3])
            n += 1
            t += bar
        return tot / max(n, 1)

    bars = [(bar_score(phase + k * beat), (phase + k * beat) % bar) for k in range(4)]
    bars.sort(reverse=True)

    # attack starts
    cand = []
    for i in range(max(t0, 30), end_ms - 12):
        before = sum(env[i - 20:i]) / 20.0 + 1.0
        after = sum(env[i:i + 10]) / 10.0
        if after - before >= 300:
            cand.append((after / before, i))
    cand.sort(reverse=True)
    taken = []
    for _, i in cand:
        if all(abs(i - j) > 250 for j in taken):
            taken.append(i)
        if len(taken) >= 200:
            break

    def near(period, centre):
        vals = sorted(wrap(t - centre, period) for t in taken if abs(wrap(t - centre, period)) <= 60)
        if not vals:
            return "n=0"
        q = lambda f: vals[min(len(vals) - 1, int(len(vals) * f))]
        return "n=%d median %+.0f ms (quartiles %+.0f / %+.0f)" % (len(vals), q(0.5), q(0.25), q(0.75))

    exp_beat = delay % beat
    err = wrap(phase - exp_beat, beat)
    err_fold = wrap(fold - exp_beat, beat)
    bar_err = wrap(bars[0][1] - (delay % bar), bar)
    print("file %s  rate %d  analysed %.1f-%.1f s" % (path, rate, t0 / 1000.0, end_ms / 1000.0))
    print("beat phase (onset grid): %.1f ms   (top-3 bins: %s)" % (
        phase, ", ".join("%d:%.1f" % (p, scores[p]) for p in sorted(range(nb), key=lambda p: -scores[p])[:3])))
    print("beat phase (folded rise): %.1f ms" % fold)
    print("bar phase candidates (strength, ms mod bar): %s" % ", ".join("%.1f@%.1f" % b for b in bars))
    print("chart delay %.1f ms -> expected beat phase %.1f ms, bar phase %.1f ms" % (delay, exp_beat, delay % bar))
    print("ERROR beat grid: %+.1f ms (onset)  %+.1f ms (fold)   bar downbeat error: %+.1f ms" % (err, err_fold, bar_err))
    print("ATTACK starts vs chart downbeats: %s" % near(bar, delay % bar))
    print("ATTACK starts vs chart beats:     %s" % near(beat, delay % beat))


main()
