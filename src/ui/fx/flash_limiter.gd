class_name FlashLimiter
extends RefCounted
## Photosensitivity rate cap for juice flashes (03-UI-SPEC 11.6, T-05-12): at most 3 accepted
## flashes in any 1 s window and at least 1/3 s between accepted flashes. Same numbers as
## EdgeFlash's pulse cap. Times are event song seconds (never frame time), so a peer flooding
## LANDED / IMPLODED events cannot strobe the screen.

const MAX_PER_SEC := 3
const MIN_GAP_SEC := 1.0 / 3.0
const WINDOW_SEC := 1.0
const EPS := 1e-6

var _accepted: Array[float] = []


## True (and records t) when a flash at song time t keeps the cap; false otherwise.
func try_flash(t: float) -> bool:
	if not is_finite(t):
		return false
	var keep: Array[float] = []
	for a in _accepted:
		if a > t - WINDOW_SEC:
			keep.append(a)
	_accepted = keep
	if not _accepted.is_empty() and absf(t - _accepted[_accepted.size() - 1]) < MIN_GAP_SEC - EPS:
		return false
	if _accepted.size() >= MAX_PER_SEC:
		return false
	_accepted.append(t)
	return true


func reset() -> void:
	_accepted.clear()
