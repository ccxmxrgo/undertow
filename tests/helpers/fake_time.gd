class_name FakeTime
extends RefCounted
## Injectable ticks source (D-03). Production code receives ticks as arguments
## and never calls Time directly; tests drive this instead.

var ticks_usec: int = 0


func now() -> int:
	return ticks_usec


func advance_usec(n: int) -> void:
	ticks_usec += n


func advance_sec(s: float) -> void:
	ticks_usec += int(round(s * 1000000.0))
