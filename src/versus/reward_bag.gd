class_name RewardBag
extends RefCounted
## Seeded shuffle bag of the 9 rewards (03-SPEC req 3): every 9 draws give each Reward.ALL id once.
## Fisher-Yates with a private RandomNumberGenerator (never the global randi/randomize), so the
## same seed always gives the same sequence. Seed per seat = seed_for(match_seed, seat).

var _rng := RandomNumberGenerator.new()
var _bag: Array[int] = []


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func draw() -> int:
	if _bag.is_empty():
		_bag = Reward.ALL.duplicate()
		for i in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
	return _bag.pop_back()


## Items left in the current bag (a copy, for tests).
func remaining() -> Array[int]:
	return _bag.duplicate()


static func seed_for(match_seed: int, seat: int) -> int:
	return hash([match_seed, seat])
