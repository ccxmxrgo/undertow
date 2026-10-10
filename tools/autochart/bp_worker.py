"""Basic Pitch worker. Runs ONLY in venv B (Python 3.10, basic-pitch 0.4.0 on onnxruntime):

  build/autochart/venvB/Scripts/python.exe -I -B tools/autochart/bp_worker.py <stem.wav> <out.json>

Writes {"notes": [[start_s, end_s, midi, amp], ...]} sorted by start (pitch bends dropped) and exits 0,
or prints `BP_FAIL <msg>` and exits 1. Parameters as measured in the research (build/research/scripts/bp_run.py).
"""
import json
import logging
import sys


def main(argv):
    if len(argv) != 3:
        print("BP_FAIL usage: bp_worker.py <stem.wav> <out.json>")
        return 1
    stem_wav, out_json = argv[1], argv[2]
    try:
        logging.disable(logging.WARNING)
        from basic_pitch.inference import predict, Model
        from basic_pitch import ICASSP_2022_MODEL_PATH
        _, _, notes = predict(stem_wav, Model(ICASSP_2022_MODEL_PATH), onset_threshold=0.5,
                              frame_threshold=0.3, minimum_note_length=58, melodia_trick=True)
        ev = sorted([[round(float(a), 6), round(float(b), 6), int(p), round(float(v), 4)]
                     for a, b, p, v, _ in notes])
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump({"notes": ev}, f)
    except Exception as e:  # report any failure as one readable line
        print(f"BP_FAIL {type(e).__name__}: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
