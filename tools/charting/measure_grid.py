"""Beat-grid measurement helper for the bundled songs (stdlib only, no numpy).

Usage (from the repo root):  python -I tools/charting/measure_grid.py <file.wav> <bpm> [delay_ms ...]

Reads a 16-bit PCM WAV, builds a 10 ms onset-energy envelope, and prints:
  1. the beat phase (seconds, mod beat length) ranked by summed onset strength,
  2. for each candidate chart delay (ms): onset strength on the chart's bar downbeats and on
     beat 1 of its accent bars, plus the mean RMS of "accent bars" (bar index 3 of every 4)
     versus the other bars, so the plan's accent-every-4th-bar assumption can be checked.
chart time = tick time + delay, so the chart's bar 0 starts at audio time delay/1000 s.
The decoded April MP3 cannot be read here: record it from Godot to a WAV and pass that.
"""
import array
import sys
import wave

HOP = 441  # 10 ms at 44.1 kHz


def load(path):
    w = wave.open(path, "rb")
    if w.getsampwidth() != 2:
        raise SystemExit("only 16-bit PCM is supported")
    ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    a = array.array("h")
    a.frombytes(raw)
    return a[0::ch], rate


def envelope(mono, rate):
    hop = rate // 100
    env = []
    for i in range(0, len(mono) - hop, hop):
        seg = mono[i:i + hop:4]
        env.append(sum(abs(x) for x in seg) / max(len(seg), 1))
    return env


def onsets(env):
    out = [0.0]
    for i in range(1, len(env)):
        out.append(max(env[i] - env[i - 1], 0.0))
    return out


def strength_at(ons, t, width=2):
    i = int(round(t * 100))
    if i - width < 0 or i + width >= len(ons):
        return None
    return max(ons[i - width:i + width + 1])


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    path, bpm = sys.argv[1], float(sys.argv[2])
    delays = [int(x) for x in sys.argv[3:]] or [0]
    mono, rate = load(path)
    env = envelope(mono, rate)
    ons = onsets(env)
    dur = len(env) / 100.0
    beat = 60.0 / bpm
    bar = beat * 4
    print("duration %.3f s, beat %.4f s, bar %.4f s" % (dur, beat, bar))

    scores = []
    for p in range(int(beat * 100)):
        tot, cnt = 0.0, 0
        t = p / 100.0
        while t < dur - 0.1:
            s = strength_at(ons, t)
            if s is not None:
                tot += s
                cnt += 1
            t += beat
        scores.append((tot / max(cnt, 1), p / 100.0))
    scores.sort(reverse=True)
    print("beat phase candidates (mean onset strength, phase s mod beat):")
    for sc, ph in scores[:5]:
        print("  %.1f  %.2f" % (sc, ph))

    for d in delays:
        origin = d / 1000.0
        bars = int((dur - origin) / bar)
        down, mid, rms_acc, rms_oth = [], [], [], []
        for b in range(bars):
            t0 = origin + b * bar
            if t0 < 0.05:
                continue
            s = strength_at(ons, t0)
            m = strength_at(ons, t0 + 2 * beat)
            if s is not None:
                down.append(s)
            if m is not None:
                mid.append(m)
            i0, i1 = int(t0 * 100), int((t0 + bar) * 100)
            seg = env[i0:i1]
            if len(seg) < 10:
                continue
            r = sum(seg) / len(seg)
            (rms_acc if b % 4 == 3 else rms_oth).append(r)
        print("delay %d ms: bar-downbeat onset mean %.1f, beat-3 onset mean %.1f, "
              "accent-bar level %.1f vs other bars %.1f (ratio %.2f)" % (
                  d, sum(down) / max(len(down), 1), sum(mid) / max(len(mid), 1),
                  sum(rms_acc) / max(len(rms_acc), 1), sum(rms_oth) / max(len(rms_oth), 1),
                  (sum(rms_acc) / max(len(rms_acc), 1)) / max(sum(rms_oth) / max(len(rms_oth), 1), 1e-9)))


main()
