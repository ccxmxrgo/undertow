class_name EventChannel
extends RefCounted
## The seam between the versus referee and everything that shows or carries its results
## (03-SPEC req 12, D-28). MatchSim only ever calls send(); views only ever connect to
## received. Phase 3 uses LoopbackChannel (same process); Phase 4 swaps in a network channel
## without touching MatchSim or the views. Events are GameEvent records (Dictionaries).

signal received(e: Dictionary)


## Delivers one event. The base channel delivers synchronously.
func send(e: Dictionary) -> void:
	received.emit(e)


## Song-time pump for channels that hold events (latency simulation, network). No-op here.
func update(_t: float) -> void:
	pass
