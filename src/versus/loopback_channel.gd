class_name LoopbackChannel
extends EventChannel
## Phase 3 channel: events go straight back out to local listeners. With latency_s > 0 each
## event is held until update(t) reaches e.t + latency_s and is then delivered in send order
## (strict FIFO), so Phase-4-style latency can be tested headless without a network.

## Simulated one-way delay in seconds (0 = synchronous delivery).
var latency_s := 0.0
var _queue: Array[Dictionary] = []


func send(e: Dictionary) -> void:
	if latency_s <= 0.0:
		received.emit(e)
		return
	_queue.append(e)


func update(t: float) -> void:
	while not _queue.is_empty():
		var e: Dictionary = _queue[0]
		if float(e.get("t", 0.0)) + latency_s > t + 1e-9:
			break
		_queue.pop_front()
		received.emit(e)


## Events still held back (tests).
func pending_count() -> int:
	return _queue.size()
