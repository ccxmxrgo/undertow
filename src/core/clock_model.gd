class_name ClockModel
extends RefCounted
## Disciplined, monotonic song clock (D-05). Pure: no Time/AudioServer calls (D-03);
## callers inject ticks (usec). Never accumulates frame delta; extrapolates from the
## system tick difference and slews toward the audio-derived target.

var snap_s: float
var slew: float

var _anchor_ticks: int = 0
var _song_time: float = 0.0


func _init(p_snap_s: float = -1.0, p_slew: float = -1.0) -> void:
	var cfg := JudgeConfig.new()
	snap_s = p_snap_s if p_snap_s >= 0.0 else cfg.clock_snap_s
	slew = p_slew if p_slew >= 0.0 else cfg.clock_slew


func reset(now_ticks: int, song_time: float) -> void:
	_anchor_ticks = now_ticks
	_song_time = song_time


func update(now_ticks: int, audio_target: float, audio_valid: bool) -> float:
	var dt := (now_ticks - _anchor_ticks) / 1000000.0
	var predicted := _song_time + dt
	if audio_valid:
		var err := audio_target - predicted
		predicted = audio_target if absf(err) > snap_s else predicted + err * slew
	_song_time = maxf(_song_time, predicted)  # never backwards
	_anchor_ticks = now_ticks
	return _song_time


func song_time() -> float:
	return _song_time


## Map an input event's tick stamp to song time (D-06).
func song_time_at(ticks: int) -> float:
	return _song_time + (ticks - _anchor_ticks) / 1000000.0
