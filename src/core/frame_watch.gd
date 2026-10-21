class_name FrameWatch
extends RefCounted
## Late-frame counter for the slow-frame results hint (05-06, D-06, AV-05).
## Counts only; never a clock. The song clock and judgment stay on the audio clock (Conductor);
## nothing here feeds song_time, InputJudge or HullScore (CLAUDE.md: no _process delta as a clock).
##
## A frame is late when its delta exceeds LATE_FACTOR x the display refresh interval. Frames in
## the first WARMUP_SEC of song time (loading hitches, the count-in) and paused frames are not
## counted. should_hint() is true when at least MIN_FRAMES frames were counted, more than
## HINT_RATIO of them were late, and Low effects is still off.
##
## The refresh rate is passed in (no DisplayServer access here). It is clamped to
## MIN_HZ..MAX_HZ: a non-finite or <= 0 rate (headless returns -1) falls back to 60 Hz. The
## 144 Hz cap is deliberate: on a 240 Hz panel a steady 120 fps would otherwise count every frame
## as late, and that player does not need to cut effects.

const WARMUP_SEC := 2.0
const LATE_FACTOR := 1.5
const HINT_RATIO := 0.03
const MIN_FRAMES := 600
const MIN_HZ := 30.0
const MAX_HZ := 144.0
const FALLBACK_HZ := 60.0

var _late_dt: float = LATE_FACTOR / FALLBACK_HZ
var _counted: int = 0
var _late: int = 0


func _init(refresh_hz: float = FALLBACK_HZ) -> void:
	var hz := refresh_hz
	if not is_finite(hz) or hz <= 0.0:
		hz = FALLBACK_HZ
	_late_dt = LATE_FACTOR / clampf(hz, MIN_HZ, MAX_HZ)


## One rendered frame: its delta, the song time and whether the dive is paused.
func sample(dt: float, song_t: float, paused: bool) -> void:
	if paused or not is_finite(dt) or dt < 0.0 or not is_finite(song_t) or song_t < WARMUP_SEC:
		return
	_counted += 1
	if dt > _late_dt:
		_late += 1


## Seconds: a frame longer than this is late.
func late_threshold() -> float:
	return _late_dt


func counted_frames() -> int:
	return _counted


func late_frames() -> int:
	return _late


func late_ratio() -> float:
	return float(_late) / float(_counted) if _counted > 0 else 0.0


func should_hint(low_effects_on: bool) -> bool:
	return not low_effects_on and _counted >= MIN_FRAMES and late_ratio() > HINT_RATIO


func reset() -> void:
	_counted = 0
	_late = 0
