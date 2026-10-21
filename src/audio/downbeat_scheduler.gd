class_name DownbeatScheduler
extends RefCounted
## Downbeat sonar ping scheduling (05-02, D-02). Pure: no nodes, no AudioServer, no Settings.
##
## Godot 4.7 has no scheduled AudioStreamPlayer start, so the ping sample carries `lead_sec` of
## leading silence and is started early with `play(from_position)`. The audible onset then lands
## on the bar when
##     head = song_t + output_latency + audio_offset + time_to_next_mix
##     r    = bar_time - head                (time until the bar reaches the speaker)
##     from_position = lead - r
## This is the same lead the pinned Conductor uses to start its own audio on resume
## (src/core/conductor.gd:163, `get_time_to_next_mix() + _latency_cache + audio_offset()`;
## read-only reference, that file is never edited).
##
## Bars come from BeatClock.beats_between (bar == true, time >= 0) in WINDOW_SEC look-ahead
## windows. At most one bar is handled per tick. A bar whose window was missed by more than
## LATE_SKIP_SEC is skipped instead of pinged late. Bar ordinals count bars from time 0, so
## every_n_bars stays stable across refills and resets.

const LATE_SKIP_SEC := 0.03
const WINDOW_SEC := 4.0  # look-ahead refill window
const _MAX_WINDOWS_PER_FILL := 64
const _DEDUPE_EPS := 1e-6

var every_n_bars: int = 1  # 1 = every bar (D-02 default); 2 = every other bar

var _tempo_map: Array
var _time_sigs: Array
var _lead: float
var _queue: Array[float] = []
var _ordinal := 0  # ordinal of _queue[0] among bars at time >= 0
var _scan_t := 0.0
var _last_queued := -INF
var _last_fired := -INF
var _fired := 0


func _init(tempo_map: Array, time_sigs: Array, lead_sec: float = 0.15) -> void:
	_tempo_map = tempo_map
	_time_sigs = time_sigs
	_lead = maxf(lead_sec, 0.0) if is_finite(lead_sec) else 0.15
	_restart_scan()


## Call every frame while playing (never while paused). Returns the from_position (0..lead) to
## start the ping at right now, or -1.0 when no ping starts this frame.
func tick(song_t: float, latency: float, offset: float, to_next_mix: float) -> float:
	var head := song_t + latency + offset + to_next_mix
	if not is_finite(head):
		return -1.0
	_fill()
	if _queue.is_empty():
		return -1.0
	var bar_t: float = _queue[0]
	var r := bar_t - head
	if r < -LATE_SKIP_SEC:
		_advance()
		return -1.0
	if r < _lead:
		var ordinal := _ordinal
		_advance()
		if ordinal % maxi(every_n_bars, 1) == 0:
			_fired += 1
			_last_fired = bar_t
			return clampf(_lead - r, 0.0, _lead)
		return -1.0
	return -1.0


## After pause, resume or seek: the next bar becomes the first bar not yet fired whose time is
## >= head - LATE_SKIP_SEC. Bars already fired are never pinged again.
func reset(song_t: float, latency: float = 0.0, offset: float = 0.0, to_next_mix: float = 0.0) -> void:
	_restart_scan()
	var head := song_t + latency + offset + to_next_mix
	if not is_finite(head):
		return
	var threshold := head - LATE_SKIP_SEC
	while true:
		_fill()
		if _queue.is_empty():
			return
		var b: float = _queue[0]
		if b >= threshold and b > _last_fired:
			return
		_advance()


## Time of the next bar to be considered, INF when none.
func next_bar_time() -> float:
	_fill()
	return INF if _queue.is_empty() else _queue[0]


func fired_count() -> int:
	return _fired


func _restart_scan() -> void:
	_queue.clear()
	_ordinal = 0
	_scan_t = 0.0
	_last_queued = -INF


func _advance() -> void:
	_queue.pop_front()
	_ordinal += 1


func _fill() -> void:
	if not _queue.is_empty():
		return
	for i in _MAX_WINDOWS_PER_FILL:
		var entries := BeatClock.beats_between(_scan_t, _scan_t + WINDOW_SEC, _tempo_map, _time_sigs)
		for e in entries:
			var t := float(e["time"])
			if e["bar"] and t >= 0.0 and t > _last_queued + _DEDUPE_EPS:
				_queue.append(t)
				_last_queued = t
		if entries.size() >= BeatClock.MAX_BEATS:
			_scan_t = maxf(float(entries.back()["time"]), _scan_t + _DEDUPE_EPS)
		else:
			_scan_t += WINDOW_SEC
		if not _queue.is_empty():
			return
