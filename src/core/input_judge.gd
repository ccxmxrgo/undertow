class_name InputJudge
extends RefCounted
## Per-lane queue judge for taps (D-08..D-10). Sustain/release hooks arrive in plan 03
## via the same press(lane, t) signature. error_s = t - note.time (positive = late).

enum Judgment { PERFECT, GOOD, MISS }

signal judged(lane: int, note_index: int, judgment: int, error_s: float)
signal stray(lane: int)

const EPS := 1e-9

var _chart: ChartData
var _cfg: JudgeConfig
var _queues: Array = []  # per lane: Array[int] of chart note indices, sorted by time
var _heads: Array[int] = []


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
