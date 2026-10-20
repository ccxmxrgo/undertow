class_name ClockSync
extends RefCounted
## Host clock offset estimator (D-06, RESEARCH Pattern 3; RFC 5905 simplified, one host stamp).
##
## The client sends PING {seq, c0} with its own Time.get_ticks_usec(), the host replies PONG
## {seq, c0, h} with its ticks, and the client receives it at c1. Then rtt = c1 - c0 and
## offset = h + rtt/2 - c1, so host_ticks = client_ticks + offset. Queueing and frame-poll
## delay only ever add to one leg, so the estimate is the median offset of the BEST_N
## lowest-RTT samples. Ticks are passed in (never read here), as in the rest of the core.

const MAX_SAMPLES := 32
const BEST_N := 5
const MIN_SAMPLES := 5
const MAX_RTT_US := 2_000_000

var _samples: Array = []  # [rtt_us, offset_us], oldest first


## Adds one exchange. Negative or > 2 s round trips are ignored.
func add(c0: int, h: int, c1: int) -> void:
	var rtt := c1 - c0
	if rtt < 0 or rtt > MAX_RTT_US:
		return
	_samples.append([rtt, h + rtt / 2 - c1])
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


## host_ticks - client_ticks in microseconds; 0 with no samples.
func offset_us() -> int:
	if _samples.is_empty():
		return 0
	var s := _samples.duplicate()
	s.sort_custom(_by_rtt)
	var best: Array[int] = []
	for i in mini(BEST_N, s.size()):
		best.append(int(s[i][1]))
	best.sort()
	return best[best.size() / 2]


func rtt_p50_us() -> int:
	return _rtt_pct(0.5)


func rtt_p90_us() -> int:
	return _rtt_pct(0.9)


func sample_count() -> int:
	return _samples.size()


func is_synced() -> bool:
	return _samples.size() >= MIN_SAMPLES


func reset() -> void:
	_samples.clear()


## Nearest-rank percentile of the kept round trips (0 with no samples).
func _rtt_pct(p: float) -> int:
	if _samples.is_empty():
		return 0
	var r: Array[int] = []
	for x in _samples:
		r.append(int(x[0]))
	r.sort()
	var rank := clampi(ceili(p * r.size()) - 1, 0, r.size() - 1)
	return r[rank]


static func _by_rtt(a: Array, b: Array) -> bool:
	return a[0] < b[0]
