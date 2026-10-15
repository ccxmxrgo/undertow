class_name RewardMeter
extends RefCounted
## The reward meter (03-SPEC reqs 1 and 2, D-30, D-31, D-24).
## +1 per Perfect; a reward is drawn from the bag at threshold(base chart note count). Miss empties
## the meter; Good neither adds nor empties it (Overclock: Good adds 1). Strays never reach it.
## While a reward is held the meter stays full and draws nothing; use() empties it. One duel prize
## may wait in a queue. Bounty refunds are ignored while holding (overflow dropped, D-31).
## Never listens to HullScore.streak_changed: Good resets the streak but must not reset the meter.

signal progress_changed(value: int, threshold: int)
signal reward_earned(id: int, source: String)
signal slot_changed(id: int)
signal queue_changed(id: int)

## Instance threshold (named target because the static threshold() owns the name).
var target: int = 1
var progress: int = 0
var held: int = -1
var queued: int = -1
## False on wrecks and in modes without rewards: judgments are ignored.
var enabled: bool = true
var _bag: RewardBag


func _init(p_threshold: int, p_bag: RewardBag) -> void:
	target = maxi(1, p_threshold)
	_bag = p_bag


## ceil(ratio x note_count), at least 1. The epsilon guards float noise (0.07 x 100).
static func threshold(note_count: int, ratio: float) -> int:
	return maxi(1, ceili(ratio * note_count - 1e-9))


func on_judgment(judgment: int, overclock: bool = false) -> void:
	if not enabled:
		return
	match judgment:
		InputJudge.Judgment.PERFECT:
			_advance(1, "meter")
		InputJudge.Judgment.GOOD:
			if overclock:
				_advance(1, "meter")
		_:
			_set_progress(0)


## Depth Charge overlay Perfects count like base Perfects (D-14).
func credit(n: int) -> void:
	if enabled and n > 0:
		_advance(n, "meter")


## Returns the held id (or -1) and empties the meter; a queued prize drops into the slot at once.
func use() -> int:
	var id := held
	if id == -1:
		return -1
	_set_progress(0)
	if queued != -1:
		var next := queued
		_set_queued(-1)
		_set_held(next)
	else:
		_set_held(-1)
	return id


## Solo Duel prize (spec req 2/11). Empty slot -> held now; else one-item queue; else false.
func queue_prize(id: int) -> bool:
	if held == -1:
		_set_held(id)
		reward_earned.emit(id, "duel")
		return true
	if queued == -1:
		_set_queued(id)
		return true
	return false


## Bounty refund (03-SPEC req 10, D-31). Ignored while holding; reaching the threshold draws at
## once with source "bounty" and drops the extra. Returns true when a reward was earned.
func add_refund(amount: int) -> bool:
	if not enabled or held != -1 or amount <= 0:
		return false
	return _advance(amount, "bounty")


## Elimination (D-24): the held reward, queue and progress are lost.
func reset_lost() -> void:
	_set_queued(-1)
	_set_held(-1)
	_set_progress(0)


func _advance(n: int, source: String) -> bool:
	if held != -1:
		return false
	if progress + n < target:
		_set_progress(progress + n)
		return false
	_set_progress(target)
	_set_held(_bag.draw())
	reward_earned.emit(held, source)
	return true


func _set_progress(v: int) -> void:
	if v == progress:
		return
	progress = v
	progress_changed.emit(progress, target)


func _set_held(v: int) -> void:
	held = v
	slot_changed.emit(held)


func _set_queued(v: int) -> void:
	if v == queued:
		return
	queued = v
	queue_changed.emit(queued)
