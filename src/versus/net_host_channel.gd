class_name NetHostChannel
extends EventChannel
## The online host's event channel (D-03, D-23). send(e) first emits `received` locally, so the
## host's views and its own SubRig behave exactly as offline, then queues e for every peer and
## appends it to broadcast_log (the single source of truth for "what clients received").
##
## The session pulls take_batches() each frame: per peer, EVENTS messages {type, seq, events}
## with a per-peer seq starting at 1. Batches are cut at MAX_BATCH events and at CUT_BYTES of
## encoded size (a full 128-event batch of real events can exceed MAX_PACKET; T-04-16).
## update(t) is a no-op.

## Encoded size cap per EVENTS message (well under NetProtocol.MAX_PACKET).
const CUT_BYTES := 12 * 1024

## Every event sent, in emission order.
var broadcast_log: Array[Dictionary] = []

## peer id -> Array of pending events.
var _outbox := {}
## peer id -> last seq used.
var _seq := {}


func add_peer(id: int) -> void:
	if not _outbox.has(id):
		_outbox[id] = []
		_seq[id] = 0


func remove_peer(id: int) -> void:
	_outbox.erase(id)
	_seq.erase(id)


func peers() -> Array:
	return _outbox.keys()


func send(e: Dictionary) -> void:
	received.emit(e)
	broadcast_log.append(e)
	for id in _outbox:
		_outbox[id].append(e)


func update(_t: float) -> void:
	pass


## peer id -> Array of EVENTS messages (possibly empty). Outboxes are cleared.
func take_batches() -> Dictionary:
	var out := {}
	for id in _outbox:
		var evs: Array = _outbox[id]
		var msgs: Array = []
		if not evs.is_empty():
			var sizes: Array[int] = []
			for e in evs:
				sizes.append(var_to_bytes(e).size())
			var k := 0
			while k < evs.size():
				var seq: int = _seq[id] + 1
				var size := NetCodec.encode(
					{"type": NetProtocol.EVENTS, "seq": seq, "events": []}).size()
				var chunk: Array = []
				while k < evs.size() and chunk.size() < NetProtocol.MAX_BATCH:
					if not chunk.is_empty() and size + sizes[k] > CUT_BYTES:
						break
					chunk.append(evs[k])
					size += sizes[k]
					k += 1
				_seq[id] = seq
				msgs.append({"type": NetProtocol.EVENTS, "seq": seq, "events": chunk})
			_outbox[id] = []
		out[id] = msgs
	return out
