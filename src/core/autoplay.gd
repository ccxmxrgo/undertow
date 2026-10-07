class_name Autoplay
extends RefCounted
## Chart player (D-28): presses and releases at the exact note times, never the frame time,
## so a correct judge scores all-Perfect at any frame rate. Events fire in time order,
## releases before presses at equal times.

var _judge: InputJudge
var _events: Array[Dictionary] = []  # {time, kind (0 release, 1 press), lane}
var _next: int = 0


func _init(chart: ChartData, judge: InputJudge) -> void:
	_judge = judge
	for n in chart.notes:
		_events.append({"time": n["time"], "kind": 1, "lane": n["lane"]})
		if n["duration"] > 0.0:
			_events.append({"time": n["time"] + n["duration"], "kind": 0, "lane": n["lane"]})
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time"] == b["time"]:
			if a["kind"] == b["kind"]:
				return a["lane"] < b["lane"]
			return a["kind"] < b["kind"]
		return a["time"] < b["time"])


func update(song_time: float) -> void:
	while _next < _events.size() and _events[_next]["time"] <= song_time:
		var e: Dictionary = _events[_next]
		_next += 1
		if e["kind"] == 1:
			_judge.press(e["lane"], e["time"])
		else:
			_judge.release(e["lane"], e["time"])


func is_done() -> bool:
	return _next >= _events.size()
