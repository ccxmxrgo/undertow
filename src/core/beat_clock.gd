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


## Upper bound on beats_between output, so a huge window cannot stall a frame.
const MAX_BEATS := 4096
const _EPS := 1e-6


## Quarter-note beat grid in [t0, t1] (D-18): ordered [{time: float, bar: bool}].
## Beats are counted from the first tempo segment and keep counting across tempo changes.
## A bar lasts num * 4 / den quarter beats; each time signature starts a new bar at its
## time. A bar start that falls between quarter beats (7/8) is returned as its own entry.
## Empty tempo map -> 120 bpm from 0; empty time_sigs -> 4/4 from the tempo start.
static func beats_between(t0: float, t1: float, tempo_map: Array, time_sigs: Array) -> Array:
	var out: Array = []
	if not is_finite(t0) or not is_finite(t1) or t1 < t0:
		return out
	var b0 := beat_at(t0, tempo_map)
	var b1 := beat_at(t1, tempo_map)
	var regions := maxi(time_sigs.size(), 1)
	for r in regions:
		var start_b := 0.0
		var bar_len := 4.0
		if not time_sigs.is_empty():
			var ts: Dictionary = time_sigs[r]
			start_b = _snap(beat_at(float(ts.get("time", 0.0)), tempo_map))
			var num := clampi(int(ts.get("num", 4)), 1, 32)
			var den := clampi(int(ts.get("den", 4)), 1, 32)
			bar_len = float(num) * 4.0 / float(den)
		var region_lo := -INF if r == 0 else start_b
		var region_hi := INF
		if r < regions - 1:
			region_hi = _snap(beat_at(float(time_sigs[r + 1].get("time", 0.0)), tempo_map))
		var lo := maxf(region_lo, b0)
		var hi := minf(region_hi, b1)
		if lo > hi + _EPS:
			continue
		var k := ceilf(lo - start_b - _EPS)
		var j := ceilf((lo - start_b - _EPS) / bar_len)
		while true:
			var pb := start_b + k
			var pj := start_b + j * bar_len
			var p := minf(pb, pj)
			if p > hi + _EPS or p >= region_hi - _EPS:
				break
			var is_bar := absf(pj - p) <= _EPS
			if absf(pb - p) <= _EPS:
				k += 1.0
			if is_bar:
				j += 1.0
			out.append({"time": time_at_beat(p, tempo_map), "bar": is_bar})
			if out.size() >= MAX_BEATS:
				return out
	return out


## Quarter beats elapsed since the first tempo segment at song time t (negative before it).
static func beat_at(t: float, tempo_map: Array) -> float:
	if tempo_map.is_empty():
		return t * 2.0
	var origin := float(tempo_map[0]["time"])
	if t <= origin:
		return (t - origin) * maxf(float(tempo_map[0]["bpm"]), 1.0) / 60.0
	var beats := 0.0
	var n := tempo_map.size()
	for i in n:
		var st := float(tempo_map[i]["time"])
		var bpm := maxf(float(tempo_map[i]["bpm"]), 1.0)
		var next_t := INF if i == n - 1 else float(tempo_map[i + 1]["time"])
		if t <= next_t:
			return beats + (t - st) * bpm / 60.0
		beats += (next_t - st) * bpm / 60.0
	return beats


## Inverse of beat_at.
static func time_at_beat(b: float, tempo_map: Array) -> float:
	if tempo_map.is_empty():
		return b * 0.5
	var origin := float(tempo_map[0]["time"])
	if b <= 0.0:
		return origin + b * 60.0 / maxf(float(tempo_map[0]["bpm"]), 1.0)
	var beats := 0.0
	var n := tempo_map.size()
	for i in n:
		var st := float(tempo_map[i]["time"])
		var bpm := maxf(float(tempo_map[i]["bpm"]), 1.0)
		var seg_beats := INF if i == n - 1 else (float(tempo_map[i + 1]["time"]) - st) * bpm / 60.0
		if b <= beats + seg_beats:
			return st + (b - beats) * 60.0 / bpm
		beats += seg_beats
	return origin


## Removes float noise from beat positions that came from tick-aligned times.
static func _snap(b: float) -> float:
	var r := roundf(b)
	return r if absf(b - r) < 1e-4 else b
