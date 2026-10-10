class_name HitOffsetRecorder
extends RefCounted
## Records per-hit timing offsets for the results histogram (D-09). Read-only listener on
## InputJudge.judged: the judge is never modified. Perfect and Good store error_s
## (t_press - note_time, negative = early); a Miss is only counted (it has no offset).

var _judge: Object = null
var _offsets := PackedFloat32Array()
var _perfect := 0
var _good := 0
var _miss := 0


## Starts listening to judge.judged (any object with a matching signal). Re-attaching
## detaches from the previous judge first, so hits are never counted twice.
func attach(judge: Object) -> void:
	detach()
	if judge == null or not judge.has_signal("judged"):
		return
	_judge = judge
	judge.judged.connect(_on_judged)


func detach() -> void:
	if _judge != null and is_instance_valid(_judge) and _judge.judged.is_connected(_on_judged):
		_judge.judged.disconnect(_on_judged)
	_judge = null


func reset() -> void:
	_offsets = PackedFloat32Array()
	_perfect = 0
	_good = 0
	_miss = 0


## Perfect and Good offsets in seconds, in judgment order (a copy).
func offsets() -> PackedFloat32Array:
	return _offsets.duplicate()


func counts() -> Dictionary:
	return {"perfect": _perfect, "good": _good, "miss": _miss}


func _on_judged(_lane: int, _note_index: int, judgment: int, error_s: float) -> void:
	match judgment:
		InputJudge.Judgment.PERFECT:
			_perfect += 1
			if is_finite(error_s):
				_offsets.append(error_s)
		InputJudge.Judgment.GOOD:
			_good += 1
			if is_finite(error_s):
				_offsets.append(error_s)
		InputJudge.Judgment.MISS:
			_miss += 1
