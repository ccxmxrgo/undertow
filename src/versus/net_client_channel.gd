class_name NetClientChannel
extends EventChannel
## A client's event channel (D-03, D-23, Pitfall 6). The session hands it already-decoded EVENTS
## messages through receive(msg). Batches are applied in seq order exactly once: seq <= last_seq
## is a duplicate and dropped, a gap is buffered until it fills. Every event is re-validated with
## NetCodec.validate_event (a buggy host must not crash a client); invalid ones are skipped and
## counted. Valid events go out through `received` and are appended to received_log.
##
## Latency probe (D-09): for LANDED events whose target (`to`) is the local seat, it records how
## late the event arrived against the local song time, in ms (0 when early).
##
## Clients run no rules: send(e) is a no-op and update(t) does nothing.

## Out-of-order batches buffered at most (T-04-16).
const MAX_BUFFERED := 256

var local_seat: int
var last_seq := 0
var rejected_events := 0
var landed_late_last_ms := 0.0
var landed_late_max_ms := 0.0
var received_log: Array[Dictionary] = []

var _now_fn: Callable
var _ctx: Dictionary
## seq -> events Array waiting for the gap to fill.
var _buffer := {}


func _init(p_local_seat: int, p_now_fn: Callable, p_ctx: Dictionary) -> void:
	local_seat = p_local_seat
	_now_fn = p_now_fn
	_ctx = p_ctx


func receive(msg: Dictionary) -> void:
	var sv: Variant = msg.get("seq")
	var ev: Variant = msg.get("events")
	if not (sv is int) or not (ev is Array):
		return
	var seq: int = sv
	if seq <= last_seq or _buffer.has(seq):
		return
	if seq > last_seq + 1:
		if _buffer.size() < MAX_BUFFERED:
			_buffer[seq] = ev
		return
	_apply(ev)
	last_seq = seq
	while _buffer.has(last_seq + 1):
		var next: Array = _buffer[last_seq + 1]
		_buffer.erase(last_seq + 1)
		_apply(next)
		last_seq += 1


func send(_e: Dictionary) -> void:
	pass


func update(_t: float) -> void:
	pass


func debug_stats() -> Dictionary:
	return {"last_seq": last_seq, "rejected_events": rejected_events,
		"landed_late_last_ms": landed_late_last_ms, "landed_late_max_ms": landed_late_max_ms,
		"received": received_log.size()}


func _apply(events: Array) -> void:
	for e in events:
		if not NetCodec.validate_event(e, _ctx):
			rejected_events += 1
			continue
		var d: Dictionary = e
		if d["type"] == GameEvent.LANDED and d.get("to") is int and int(d["to"]) == local_seat:
			_probe_landed(float(d["t"]))
		received_log.append(d)
		received.emit(d)


func _probe_landed(t: float) -> void:
	if not _now_fn.is_valid():
		return
	var now: Variant = _now_fn.call()
	if not (now is float or now is int) or not is_finite(float(now)):
		return
	var late := maxf(0.0, (float(now) - t) * 1000.0)
	landed_late_last_ms = late
	landed_late_max_ms = maxf(landed_late_max_ms, late)
