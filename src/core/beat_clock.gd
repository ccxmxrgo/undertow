class_name BeatClock
extends RefCounted
## Pure beat phase and pulse. Valid for negative (lead-in) time so the world beats during
## the 3-2-1 count-in (D-10).


## Fraction 0..1 through the current beat at song time t. Empty map -> 120 bpm.
static func phase(t: float, tempo_map: Array) -> float:
	if t < 0.0:
		var bpm0 := 120.0
		if not tempo_map.is_empty():
			bpm0 = float(tempo_map[0]["bpm"])
		var spb := 60.0 / maxf(bpm0, 1.0)
		return fposmod(t / spb, 1.0)
	if tempo_map.is_empty():
		return fposmod(t * 2.0, 1.0)
	var seg: Dictionary = tempo_map[0]
	for s in tempo_map:
		if float(s["time"]) <= t:
			seg = s
		else:
			break
	var bpm := maxf(float(seg["bpm"]), 1.0)
	return fposmod((t - float(seg["time"])) * bpm / 60.0, 1.0)


## Sharp-attack decay: 1.0 at phase 0, 0.0 at phase 1.
static func pulse(p: float) -> float:
	var q := clampf(1.0 - p, 0.0, 1.0)
	return q * q * q
