class_name IntroTimeline
extends RefCounted
## Pure goggles-on intro schedule (D-10..D-12, D-17 lens mask). No nodes, no Settings access: reduce_motion is a
## parameter. Times are seconds of PRE-COUNT wall clock; the count-in itself is the Conductor
## lead-in, so numerals derive from song_time.

enum Mode { FULL, QUICK, NONE }
enum Phase { ROOM_LENS, BLACK, CRT, ARENA, COUNT }

const FULL_LENS_END := 1.10
const FULL_BLACK_END := 1.25
const FULL_CRT_END := 1.65
const FULL_ARENA_END := 2.60
const QUICK_BLACK_END := 0.05
const QUICK_CRT_END := 0.40
const QUICK_ARENA_END := 0.60
const RM_LENS_END := 0.8
const RM_BLACK_END := 0.9
const RM_ARENA_END := 1.6
const DIVE_SEC := 0.6
const DIVE_SEC_QUICK := 0.4
const LEAD_IN_MIN_SEC := 0.6
const LEAD_IN_MAX_SEC := 4.0


static func seconds_per_beat(bpm: float) -> float:
	return 60.0 / maxf(bpm, 1.0)


## Conductor lead-in length: beats * spb, bounded so a very fast tempo cannot start the music
## inside the output-latency window and a very slow one cannot stall the count (WR-06).
static func lead_in_seconds(beats: int, bpm: float) -> float:
	return clampf(float(beats) * seconds_per_beat(bpm), LEAD_IN_MIN_SEC, LEAD_IN_MAX_SEC)


## Seconds per displayed count beat once the lead-in is bounded (lead / beats).
static func count_beat_seconds(beats: int, bpm: float) -> float:
	return lead_in_seconds(beats, bpm) / float(maxi(beats, 1))


static func ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


static func pre_count_seconds(mode: int, reduce_motion: bool = false) -> float:
	match mode:
		Mode.FULL:
			return RM_ARENA_END if reduce_motion else FULL_ARENA_END
		Mode.QUICK:
			return QUICK_ARENA_END
	return 0.0


static func lead_in_beats(mode: int, skipped: bool = false) -> int:
	if skipped:
		return 3
	return 1 if mode == Mode.QUICK else 3


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## {phase, progress}; progress 0..1 within the phase. Beyond the pre-count: COUNT.
static func phase_at(t: float, mode: int, reduce_motion: bool = false) -> Dictionary:
	if mode == Mode.NONE or t >= pre_count_seconds(mode, reduce_motion):
		return {"phase": Phase.COUNT, "progress": 1.0}
	if mode == Mode.QUICK:
		if t < QUICK_BLACK_END:
			return {"phase": Phase.BLACK, "progress": _seg(t, 0.0, QUICK_BLACK_END)}
		if t < QUICK_CRT_END:
			return {"phase": Phase.CRT, "progress": _seg(t, QUICK_BLACK_END, QUICK_CRT_END)}
		return {"phase": Phase.ARENA, "progress": _seg(t, QUICK_CRT_END, QUICK_ARENA_END)}
	if reduce_motion:
		if t < RM_LENS_END:
			return {"phase": Phase.ROOM_LENS, "progress": _seg(t, 0.0, RM_LENS_END)}
		if t < RM_BLACK_END:
			return {"phase": Phase.BLACK, "progress": _seg(t, RM_LENS_END, RM_BLACK_END)}
		return {"phase": Phase.ARENA, "progress": _seg(t, RM_BLACK_END, RM_ARENA_END)}
	if t < FULL_LENS_END:
		return {"phase": Phase.ROOM_LENS, "progress": _seg(t, 0.0, FULL_LENS_END)}
	if t < FULL_BLACK_END:
		return {"phase": Phase.BLACK, "progress": _seg(t, FULL_LENS_END, FULL_BLACK_END)}
	if t < FULL_CRT_END:
		return {"phase": Phase.CRT, "progress": _seg(t, FULL_BLACK_END, FULL_CRT_END)}
	return {"phase": Phase.ARENA, "progress": _seg(t, FULL_CRT_END, FULL_ARENA_END)}


## 3, 2, 1 during the lead-in; 0 otherwise.
static func count_number(song_time: float, spb: float, beats: int) -> int:
	if song_time >= 0.0 or spb <= 0.0:
		return 0
	if song_time < -float(beats) * spb:
		return 0
	return clampi(int(ceil(-song_time / spb - 1e-9)), 0, beats)


## Fraction through the current count beat (0 at the beat start, toward 1).
static func beat_fraction(song_time: float, spb: float) -> float:
	if song_time >= 0.0 or spb <= 0.0:
		return 0.0
	var rem := -song_time / spb
	return clampf(1.0 - (rem - floorf(rem - 1e-9)), 0.0, 1.0)


static func dive_progress(song_time: float, quick: bool = false) -> float:
	var d := DIVE_SEC_QUICK if quick else DIVE_SEC
	if song_time < 0.0 or song_time > d:
		return -1.0
	return song_time / d


const FULL_LENS_CLOSE_END := 0.6
const RM_LENS_FOCUS_AT := 0.4


## First-person lens mask closing in (0 = open/invisible, 1 = fully closed). No lens in QUICK/NONE.
static func lens_close(t: float, mode: int, reduce_motion: bool = false) -> float:
	if mode != Mode.FULL:
		return 0.0
	if reduce_motion:
		return ease_out(t / RM_LENS_FOCUS_AT)
	return ease_out(t / FULL_LENS_CLOSE_END)


## Room behind the lenses: 0 = blurred/dim, 1 = in focus.
static func lens_focus(t: float, mode: int, reduce_motion: bool = false) -> float:
	if mode != Mode.FULL:
		return 0.0
	if reduce_motion:
		return 1.0 if t >= RM_LENS_FOCUS_AT else 0.0
	return ease_out(_seg(t, FULL_LENS_CLOSE_END, FULL_LENS_END))


## Mask opening and dissolving over the arena phase (0 closed, 1 gone).
static func lens_open(t: float, mode: int, reduce_motion: bool = false) -> float:
	if mode != Mode.FULL:
		return 0.0
	if reduce_motion:
		return ease_out(_seg(t, RM_BLACK_END, RM_ARENA_END))
	return ease_out(_seg(t, FULL_CRT_END, FULL_ARENA_END))
