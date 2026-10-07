class_name ChartData
extends RefCounted
## Format-agnostic, seconds-based chart (D-27).

var notes: Array[Dictionary] = []  # {lane:int 0-3, time:float, duration:float}
var tempo_map: Array[Dictionary] = []  # {time:float, bpm:float}
var audio_stream: AudioStream
var title: String = ""


func add_note(lane: int, time: float, duration: float = 0.0) -> void:
	assert(lane >= 0 and lane <= 3, "lane must be 0-3")
	assert(duration >= 0.0, "duration must be >= 0")
	assert(time >= 0.0 and is_finite(time), "time must be finite and >= 0")
	notes.append({"lane": lane, "time": time, "duration": duration})


func finalize() -> void:
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time"] == b["time"]:
			return a["lane"] < b["lane"]
		return a["time"] < b["time"])
	for n in notes:
		assert(n["lane"] >= 0 and n["lane"] <= 3 and n["duration"] >= 0.0, "invalid note")
