class_name VersusJudge
extends InputJudge
## Overlay notes (Ghost Notes D-11/D-12, Depth Charge D-14) on top of the pinned base judge.
## Never edit input_judge.gd (pinned 72e21ce). Base chart notes are judged only by super, so
## with no overlay notes this class emits exactly the InputJudge event sequence (T-03-11).
## Overlay notes live in this object's own queue and are never added to ChartData.notes.
## PayloadNotes keeps overlay notes 0.25 s away from base notes in the same lane (Pitfall 2),
## so a press can match at most one of them and checking the overlay first is safe.

const GHOST := 1
const DEPTH := 2

## A Depth Charge note was judged (PERFECT/GOOD/MISS). error_s = t - note time.
signal extra_judged(kind: int, lane: int, judgment: int, error_s: float)
## A press landed within good_window of an open ghost note.
signal ghost_hit(lane: int, payload_id: int)

## Upper bound on stored overlay notes; older closed notes are dropped first (hostile input).
const MAX_OVERLAY := 4096

var _overlay: Array = [[], [], [], []]  # per lane: Array[Dictionary] sorted by time
var _ov_heads: Array[int] = [0, 0, 0, 0]  # per lane: first note that may still be open
var _all: Array[Dictionary] = []  # every overlay note, sorted by time then lane
var _uid: int = 0


func _init(chart: ChartData, cfg: JudgeConfig) -> void:
	super(chart, cfg)


## Adds overlay notes ({time, lane, kind, payload_id}); invalid entries are skipped. Each stored
## note gains state ("open") , judgment (-1) and a unique uid.
func add_overlay(notes: Array) -> void:
	var added := false
	for raw in notes:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var t = d.get("time")
		var lane = d.get("lane")
		var kind = d.get("kind")
		if not (t is float or t is int) or not (lane is int) or not (kind is int):
			continue
		if not is_finite(float(t)) or lane < 0 or lane > 3 or (kind != GHOST and kind != DEPTH):
			continue
		_uid += 1
		var n := {
			"time": float(t), "lane": lane, "kind": kind,
			"payload_id": int(d.get("payload_id", -1)),
			"state": "open", "judgment": -1, "uid": _uid,
		}
		(_overlay[lane] as Array).append(n)
		_all.append(n)
		added = true
	if not added:
		return
	for lane in range(4):
		(_overlay[lane] as Array).sort_custom(_before)
		_ov_heads[lane] = 0
		_advance_head(lane)
	_all.sort_custom(_before)
	_trim()


## Removes a payload's still-open notes at or after from_t (payload ended early by reflection).
func clear_payload(payload_id: int, from_t: float) -> void:
	var keep := func(n: Dictionary) -> bool:
		return not (n["payload_id"] == payload_id and n["state"] == "open" and n["time"] >= from_t)
	for lane in range(4):
		_overlay[lane] = (_overlay[lane] as Array).filter(keep)
		_ov_heads[lane] = 0
		_advance_head(lane)
	_all.assign(_all.filter(keep))


## Read-only view for Highway: every overlay note sorted by time, with its live state
## ("open" | "hit" | "passed" | "missed" | "judged") and judgment (-1 until judged).
func overlay_notes() -> Array[Dictionary]:
	return _all


func press(lane: int, t: float) -> void:
	if lane >= 0 and lane < 4 and _press_overlay(lane, t):
		return
	super.press(lane, t)


func tick(t: float) -> void:
	super.tick(t)
	for lane in range(4):
		_expire_overlay(lane, t)


func is_finished() -> bool:
	if not super.is_finished():
		return false
	for lane in range(4):
		for n in (_overlay[lane] as Array).slice(_ov_heads[lane]):
			if n["kind"] == DEPTH and n["state"] == "open":
				return false
	return true


func _press_overlay(lane: int, t: float) -> bool:
	_expire_overlay(lane, t)
	var q: Array = _overlay[lane]
	for i in range(_ov_heads[lane], q.size()):
		var n: Dictionary = q[i]
		if n["state"] != "open":
			continue
		var dt: float = t - float(n["time"])
		if dt < -(_cfg.early_miss_window + EPS):
			return false  # sorted: every later note is further away
		var adt := absf(dt)
		if n["kind"] == GHOST:
			if adt <= _cfg.good_window + EPS:
				n["state"] = "hit"
				_advance_head(lane)
				ghost_hit.emit(lane, n["payload_id"])
				return true
			continue
		var j := -1
		if adt <= _cfg.perfect_window + EPS:
			j = Judgment.PERFECT
		elif adt <= _cfg.good_window + EPS:
			j = Judgment.GOOD
		elif dt < 0.0:
			j = Judgment.MISS  # early miss (within early_miss_window, checked above)
		if j >= 0:
			_close(lane, n, "judged", j, dt)
			return true
	return false


func _expire_overlay(lane: int, t: float) -> void:
	var q: Array = _overlay[lane]
	for i in range(_ov_heads[lane], q.size()):
		var n: Dictionary = q[i]
		if n["state"] != "open":
			continue
		var dt: float = t - float(n["time"])
		if dt <= _cfg.good_window + EPS:
			break
		if n["kind"] == GHOST:
			n["state"] = "passed"
		else:
			_close(lane, n, "missed", Judgment.MISS, dt)
	_advance_head(lane)


func _close(lane: int, n: Dictionary, state: String, judgment: int, dt: float) -> void:
	n["state"] = state
	n["judgment"] = judgment
	_advance_head(lane)
	extra_judged.emit(DEPTH, lane, judgment, dt)


func _advance_head(lane: int) -> void:
	var q: Array = _overlay[lane]
	while _ov_heads[lane] < q.size() and q[_ov_heads[lane]]["state"] != "open":
		_ov_heads[lane] += 1


## Bounds memory on very long sessions: drop the oldest closed notes beyond MAX_OVERLAY.
func _trim() -> void:
	if _all.size() <= MAX_OVERLAY:
		return
	var drop: Dictionary = {}
	var excess := _all.size() - MAX_OVERLAY
	for n in _all:
		if excess <= 0:
			break
		if n["state"] != "open":
			drop[n["uid"]] = true
			excess -= 1
	if drop.is_empty():
		return
	var keep := func(n: Dictionary) -> bool: return not drop.has(n["uid"])
	_all.assign(_all.filter(keep))
	for lane in range(4):
		_overlay[lane] = (_overlay[lane] as Array).filter(keep)
		_ov_heads[lane] = 0
		_advance_head(lane)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["time"] == b["time"]:
		if a["lane"] == b["lane"]:
			return a["uid"] < b["uid"]
		return a["lane"] < b["lane"]
	return a["time"] < b["time"]
