class_name StreakMilestones
extends RefCounted
## Pure milestone logic for the note-streak popups (D-08): 10, 25, 50, then every 100.

const FIXED: Array[int] = [10, 25, 50]


static func is_milestone(n: int) -> bool:
	if FIXED.has(n):
		return true
	return n >= 100 and n % 100 == 0


## Highest milestone in (old, new], or 0 when none or when new <= old (combo reset).
static func reached(old: int, new: int) -> int:
	if new <= old:
		return 0
	var best := 0
	for m in FIXED:
		if m > old and m <= new:
			best = m
	var h: int = (new / 100) * 100
	if h >= 100 and h > old:
		best = maxi(best, h)
	return best
