class_name VersusAutoplay
extends RefCounted
## Autoplay for versus (D-28 of Phase 1): presses and releases base notes at the exact note
## times, never the frame time, and also presses Depth Charge overlay notes at their exact
## times. Ghost notes are never pressed (spec req 5 acceptance: autoplay skips the fakes).
## Call refresh(judge) after VersusJudge.add_overlay to queue newly landed overlay notes.

var _judge: InputJudge
var _events: Array[Dictionary] = []  # {time, kind (0 release, 1 press), lane}
var _next: int = 0
var _last_t: float = -INF
var _queued: Dictionary = {}  # overlay uid -> true


func _init(chart: ChartData, judge: InputJudge) -> void:
	_judge = judge
	for n in chart.notes:
		_events.append({"time": n["time"], "kind": 1, "lane": n["lane"]})
		if n["duration"] > 0.0:
			_events.append({"time": n["time"] + n["duration"], "kind": 0, "lane": n["lane"]})
	_events.sort_custom(_before)
	if judge is VersusJudge:
		refresh(judge)


## Queues open Depth Charge overlay notes not yet queued whose time is after the last update.
func refresh(judge: VersusJudge) -> void:
	for n in judge.overlay_notes():
		if n["kind"] != VersusJudge.DEPTH or n["state"] != "open" or _queued.has(n["uid"]):
			continue
		if float(n["time"]) <= _last_t:
			continue
		_queued[n["uid"]] = true
		var e := {"time": n["time"], "kind": 1, "lane": n["lane"]}
		var i := _events.bsearch_custom(e, _before, false)
		_events.insert(maxi(i, _next), e)


func update(song_time: float) -> void:
	_last_t = maxf(_last_t, song_time)
	while _next < _events.size() and _events[_next]["time"] <= song_time:
		var e: Dictionary = _events[_next]
		_next += 1
		if e["kind"] == 1:
			_judge.press(e["lane"], e["time"])
		else:
			_judge.release(e["lane"], e["time"])


func is_done() -> bool:
	return _next >= _events.size()


## Events not yet played.
func pending() -> int:
	return _events.size() - _next


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["time"] == b["time"]:
		if a["kind"] == b["kind"]:
			return a["lane"] < b["lane"]
		return a["kind"] < b["kind"]
	return a["time"] < b["time"]
