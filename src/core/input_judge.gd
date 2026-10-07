class_name InputJudge
extends RefCounted
## Per-lane queue judge (D-08..D-11). Chords are independent lanes (D-09). Sustains start a
## hold on a non-miss head, emit sustain_tick at head + n * interval (frame-rate independent)
## and end quietly on early release (D-11). error_s = t - note.time (positive = late).

enum Judgment { PERFECT, GOOD, MISS }

signal judged(lane: int, note_index: int, judgment: int, error_s: float)
signal stray(lane: int)
signal sustain_tick(lane: int)
signal sustain_end(lane: int, completed: bool)

const EPS := 1e-9

var _chart: ChartData
var _cfg: JudgeConfig
var _queues: Array = []  # per lane: Array[int] of chart note indices, sorted by time
var _heads: Array[int] = []
var _holds: Array = [null, null, null, null]  # per lane: null or {head, tail, emitted, max_ticks}


func _init(chart: ChartData, cfg: JudgeConfig) -> void:
	_chart = chart
	_cfg = cfg
	for lane in range(4):
		_queues.append([] as Array[int])
		_heads.append(0)
	for i in range(chart.notes.size()):
		var q: Array[int] = _queues[chart.notes[i]["lane"]]
		q.append(i)


func press(lane: int, t: float) -> void:
	_expire(lane, t)
	var q: Array[int] = _queues[lane]
	if _heads[lane] >= q.size():
		stray.emit(lane)
		return
	var idx: int = q[_heads[lane]]
	var dt: float = t - float(_chart.notes[idx]["time"])
	var adt := absf(dt)
	if adt <= _cfg.perfect_window + EPS:
		_resolve(lane, idx, Judgment.PERFECT, dt)
	elif adt <= _cfg.good_window + EPS:
		_resolve(lane, idx, Judgment.GOOD, dt)
	elif dt < 0.0 and -dt <= _cfg.early_miss_window + EPS:
		_resolve(lane, idx, Judgment.MISS, dt)
	else:
		stray.emit(lane)


func tick(t: float) -> void:
	for lane in range(4):
		_expire(lane, t)
		_advance_hold(lane, t)


## Release of a lane key at song time t. Ignored when the lane has no active hold.
func release(lane: int, t: float) -> void:
	var h = _holds[lane]
	if h == null:
		return
	_emit_ticks(lane, h, minf(t, h["tail"]))
	if t >= h["tail"] - _cfg.release_forgive_window - EPS:
		_emit_ticks(lane, h, h["tail"])  # credit remaining ticks (D-11)
		_end_hold(lane, true)
	else:
		_end_hold(lane, false)


## Notes not yet judged (excludes notes whose head is judged but tail is still held).
func remaining_unjudged() -> int:
	var n := 0
	for lane in range(4):
		n += (_queues[lane] as Array).size() - _heads[lane]
	return n


func is_finished() -> bool:
	if remaining_unjudged() > 0:
		return false
	for lane in range(4):
		if _holds[lane] != null:
			return false
	return true


func _advance_hold(lane: int, t: float) -> void:
	var h = _holds[lane]
	if h == null:
		return
	_emit_ticks(lane, h, minf(t, h["tail"]))
	if t > h["tail"] + _cfg.good_window + EPS:
		_emit_ticks(lane, h, h["tail"])
		_end_hold(lane, true)


func _emit_ticks(lane: int, h: Dictionary, upto: float) -> void:
	var due := mini(int(floor((upto - h["head"]) / _cfg.sustain_tick_interval + EPS)), h["max_ticks"])
	while h["emitted"] < due:
		h["emitted"] += 1
		sustain_tick.emit(lane)


func _end_hold(lane: int, completed: bool) -> void:
	_holds[lane] = null
	sustain_end.emit(lane, completed)


func _expire(lane: int, t: float) -> void:
	var q: Array[int] = _queues[lane]
	while _heads[lane] < q.size():
		var idx: int = q[_heads[lane]]
		var dt: float = t - float(_chart.notes[idx]["time"])
		if dt > _cfg.good_window + EPS:
			_resolve(lane, idx, Judgment.MISS, dt)
		else:
			break


func _resolve(lane: int, idx: int, judgment: int, err: float) -> void:
	_heads[lane] += 1
	judged.emit(lane, idx, judgment, err)
	var note: Dictionary = _chart.notes[idx]
	var dur: float = note["duration"]
	if judgment != Judgment.MISS and dur > 0.0:
		var head: float = note["time"]
		_holds[lane] = {
			"head": head,
			"tail": head + dur,
			"emitted": 0,
			"max_ticks": int(floor(dur / _cfg.sustain_tick_interval + EPS)),
		}
