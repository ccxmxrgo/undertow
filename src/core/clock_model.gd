class_name ClockModel
extends RefCounted
## Disciplined, monotonic song clock (D-05). Pure: no Time/AudioServer calls (D-03);
## callers inject ticks (usec). Never accumulates frame delta; extrapolates from the
## system tick difference and slews toward the audio-derived target.

enum State { IDLE, PREROLL, PLAYING, PAUSED }

var snap_s: float
var slew: float
var state: State = State.IDLE

var _anchor_ticks: int = 0
var _song_time: float = 0.0
var _pause_pos: float = 0.0
var _resume_at_ticks: int = -1  # PAUSED + countdown running when >= 0


func _init(p_snap_s: float = -1.0, p_slew: float = -1.0) -> void:
	var cfg := JudgeConfig.new()
	snap_s = p_snap_s if p_snap_s >= 0.0 else cfg.clock_snap_s
	slew = p_slew if p_slew >= 0.0 else cfg.clock_slew


func reset(now_ticks: int, song_time: float) -> void:
	_anchor_ticks = now_ticks
	_song_time = song_time
	_resume_at_ticks = -1
	state = State.PLAYING


## Start counting from start_pos - lead_in_s on the system clock; the first valid audio
## target hands over to discipline (D-07).
func begin_preroll(now_ticks: int, lead_in_s: float, start_pos: float) -> void:
	reset(now_ticks, start_pos - lead_in_s)
	state = State.PREROLL


## Freeze song_time at its current value. Cancels a running resume countdown.
func pause(now_ticks: int) -> void:
	if state == State.PLAYING or state == State.PREROLL:
		update(now_ticks, 0.0, false)
		state = State.PAUSED
		_pause_pos = _song_time
	_resume_at_ticks = -1
	_anchor_ticks = now_ticks


## Start a countdown; song_time stays frozen at the paused position until it elapses, then
## continues from exactly that position (no jump).
func resume(now_ticks: int, countdown_s: float) -> void:
	if state != State.PAUSED:
		return
	_anchor_ticks = now_ticks
	_resume_at_ticks = now_ticks + int(round(countdown_s * 1000000.0))


func is_paused() -> bool:
	return state == State.PAUSED


func is_counting_down() -> bool:
	return state == State.PAUSED and _resume_at_ticks >= 0


## Where audio must restart (song position) when the countdown ends.
func paused_position() -> float:
	return _pause_pos


## Tick at which the countdown ends (valid while is_counting_down()).
func resume_ticks() -> int:
	return _resume_at_ticks


func update(now_ticks: int, audio_target: float, audio_valid: bool) -> float:
	if state == State.IDLE:
		return _song_time
	if state == State.PAUSED:
		if _resume_at_ticks < 0 or now_ticks < _resume_at_ticks:
			_anchor_ticks = now_ticks
			return _song_time
		_anchor_ticks = _resume_at_ticks
		_resume_at_ticks = -1
		state = State.PLAYING
	if state == State.PREROLL and audio_valid:
		state = State.PLAYING
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
	if state == State.PAUSED:
		return _song_time
	return _song_time + (ticks - _anchor_ticks) / 1000000.0
