"""Basic Pitch parity spike (Phase 2.2.2 Wave 0, D-03 / D-14): can the runtime pack ship ONE interpreter?

  build/autochart/venvA/Scripts/python.exe -I -B tools/autochart/bp_parity.py \
      --ids synth_wave_april space_synth_wave \
      --py-b build/autochart/venvB/Scripts/python.exe --py-p build/autochart/venvP/Scripts/python.exe \
      --out build/autochart/parity --report tools/autochart/reports/pack_bp_parity.json

Runs tools/autochart/bp_worker.py on the 4 stems of each song under venv B (Python 3.10, librosa 0.11,
numpy 2.2: the 02.1 reference) and under venv P (Python 3.12, merged pack pins, librosa 1.0, numpy 2.5)
and compares:
  (a) exact equality of the note arrays [[start, end, midi, amp], ...];
  (b) if not equal: note counts, max |start| / |end| difference and the share of notes with another
      midi pitch (notes paired by index when the counts match, else each B note with the P note of
      nearest start);
  (c) downstream: pitch_bp.attach_pitch on build/autochart/<id>/onsets_<stem>.json with each note list,
      compared per audible+loud onset on (pitch, amp >= 0.3), because lanes depend only on the integer
      pitch and the 0.3 octave-fold amplitude threshold (stages/lanes.py).
Decision: "merged" when (a) holds for every stem, or when (c) is identical for every audible+loud onset
of every stem; otherwise "two". The decision is data: exit 0 for both, exit 1 only when a run fails.
Last line: PARITY_MERGED or PARITY_TWO.

STANDARD LIBRARY ONLY (+ stages.pitch_bp, itself stdlib). Child processes: argument lists, no shell,
-I -B, fixed interpreter paths given as arguments, timeout 600 s (T-02.2.2-04). Only CC0 songs (D-08).
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # python -I does not put the script directory on sys.path

from stages.pitch_bp import attach_pitch  # noqa: E402

ROOT = HERE.parents[1]
WORKER = HERE / "bp_worker.py"
STEMS = ("drums", "bass", "other", "vocals")
TIMEOUT_S = 600
AMP_FOLD = 0.3
RULE = ("merged if the Basic Pitch note arrays are identical for every stem, or if attach_pitch gives the "
        "same (pitch, amp >= 0.3) for every audible+loud onset of every stem; otherwise two")
VERSION_PROBE = (
    "import json, logging, sys\n"
    "logging.disable(logging.WARNING)\n"
    "from importlib.metadata import version\n"
    "import basic_pitch\n"
    "out = {'python': sys.version.split()[0], 'model_path': str(basic_pitch.ICASSP_2022_MODEL_PATH)}\n"
    "for n in ('basic-pitch', 'onnxruntime', 'librosa', 'numpy', 'scipy', 'resampy', 'scikit-learn'):\n"
    "    out[n] = version(n)\n"
    "print(json.dumps(out))\n"
)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S, shell=False)
    return r.returncode, r.stdout, r.stderr


def versions(py):
    code, out, err = run([py, "-I", "-B", "-c", VERSION_PROBE])
    if code != 0:
        raise RuntimeError(f"version probe failed for {py}: {err.strip()[-300:]}")
    v = json.loads(out.strip().splitlines()[-1])
    mp = v["model_path"].replace("\\", "/")  # keep the part below site-packages (no user paths in the report)
    v["model_path"] = mp[mp.find("basic_pitch/"):] if "basic_pitch/" in mp else mp
    return v


def bp_notes(py, stem_wav, out_json):
    code, out, err = run([py, "-I", "-B", str(WORKER), str(stem_wav), str(out_json)])
    if code != 0:
        raise RuntimeError(f"bp_worker failed ({py}, {stem_wav}): {(out + err).strip()[-300:]}")
    return json.loads(Path(out_json).read_text(encoding="utf-8"))["notes"]


def compare_notes(nb, np_):
    res = {"equal": nb == np_, "count_b": len(nb), "count_p": len(np_)}
    if res["equal"] or not nb or not np_:
        res.update({"max_start_diff_s": 0.0 if res["equal"] else None,
                    "max_end_diff_s": 0.0 if res["equal"] else None,
                    "pitch_diff_share": 0.0 if res["equal"] else None,
                    "max_amp_diff": 0.0 if res["equal"] else None, "pairing": "none"})
        return res
    if len(nb) == len(np_):
        pairs, pairing = list(zip(nb, np_)), "index"
    else:
        pairs, pairing = [], "nearest_start"
        j = 0
        for b in nb:  # both lists are sorted by start
            while j + 1 < len(np_) and abs(np_[j + 1][0] - b[0]) <= abs(np_[j][0] - b[0]):
                j += 1
            pairs.append((b, np_[j]))
    res["pairing"] = pairing
    res["max_start_diff_s"] = round(max(abs(b[0] - p[0]) for b, p in pairs), 6)
    res["max_end_diff_s"] = round(max(abs(b[1] - p[1]) for b, p in pairs), 6)
    res["max_amp_diff"] = round(max(abs(b[3] - p[3]) for b, p in pairs), 4)
    res["pitch_diff_share"] = round(sum(1 for b, p in pairs if b[2] != p[2]) / len(pairs), 4)
    return res


def lane_key(rec):
    amp = rec["amp"]
    return (rec["pitch"], None if amp is None else amp >= AMP_FOLD)


def compare_downstream(onsets, nb, np_):
    rb, rp = attach_pitch(onsets, nb), attach_pitch(onsets, np_)
    kept = [i for i, r in enumerate(onsets) if r.get("audible") and r.get("loud")]
    pitch_diff = sum(1 for i in kept if rb[i]["pitch"] != rp[i]["pitch"])
    fold_diff = sum(1 for i in kept if rb[i]["pitch"] == rp[i]["pitch"] and lane_key(rb[i]) != lane_key(rp[i]))
    key_diff = sum(1 for i in kept if lane_key(rb[i]) != lane_key(rp[i]))
    amps = [abs(rb[i]["amp"] - rp[i]["amp"]) for i in kept
            if rb[i]["amp"] is not None and rp[i]["amp"] is not None]
    return {"audible_loud": len(kept), "pitch_diff": pitch_diff, "amp_fold_diff": fold_diff,
            "lane_key_diff": key_diff, "lane_key_identical": key_diff == 0,
            "max_amp_diff": round(max(amps), 4) if amps else 0.0}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="+", required=True)
    ap.add_argument("--py-b", required=True)
    ap.add_argument("--py-p", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--report", required=True)
    a = ap.parse_args(argv)
    a.py_b, a.py_p = str(Path(a.py_b).resolve()), str(Path(a.py_p).resolve())
    for py in (a.py_b, a.py_p):
        if not Path(py).is_file() or Path(py).name.lower() != "python.exe":
            print(f"PARITY_FAIL interpreter {py} is not an existing python.exe")
            return 1
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    try:
        report = {"interpreters": {"b": versions(a.py_b), "p": versions(a.py_p)}, "rule": RULE, "per_stem": {}}
        for sid in a.ids:
            work = ROOT / "build" / "autochart" / sid
            for stem in STEMS:
                wav = work / "stems" / f"{stem}.wav"
                on_json = work / f"onsets_{stem}.json"
                if not wav.is_file() or not on_json.is_file():
                    raise RuntimeError(f"{wav} or {on_json} is missing; run autochart.py analyze --id {sid}")
                nb = bp_notes(a.py_b, wav, out / f"{sid}_{stem}_b.json")
                np_ = bp_notes(a.py_p, wav, out / f"{sid}_{stem}_p.json")
                onsets = json.loads(on_json.read_text(encoding="utf-8"))["onsets"]
                entry = {"notes": compare_notes(nb, np_), "downstream": compare_downstream(onsets, nb, np_)}
                report["per_stem"][f"{sid}/{stem}"] = entry
                n, d = entry["notes"], entry["downstream"]
                print(f"{sid}/{stem}: equal={n['equal']} notes {n['count_b']}/{n['count_p']} "
                      f"max_start={n['max_start_diff_s']} pitch_diff_share={n['pitch_diff_share']} "
                      f"| onsets {d['audible_loud']} lane_key_diff={d['lane_key_diff']}", flush=True)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as e:
        print(f"PARITY_FAIL {type(e).__name__}: {e}")
        return 1
    stems = report["per_stem"].values()
    all_equal = all(s["notes"]["equal"] for s in stems)
    all_lane = all(s["downstream"]["lane_key_identical"] for s in stems)
    report["all_notes_equal"] = all_equal
    report["all_lane_keys_identical"] = all_lane
    report["decision"] = "merged" if (all_equal or all_lane) else "two"
    rp = Path(a.report)
    rp.parent.mkdir(parents=True, exist_ok=True)
    rp.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"decision {report['decision']} (notes equal everywhere: {all_equal}, lane keys identical: {all_lane})")
    print("PARITY_MERGED" if report["decision"] == "merged" else "PARITY_TWO")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
