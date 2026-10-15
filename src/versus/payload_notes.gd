class_name PayloadNotes
extends RefCounted
## Seeded overlay-note generators for Ghost Notes (D-11) and Depth Charge (D-14). Pure statics;
## each call owns a private RandomNumberGenerator seeded from the payload seed, so the same
## payload gives the same notes on every machine. Notes are returned as plain dictionaries
## {time, lane, kind, payload_id} for VersusJudge.add_overlay; ChartData is never touched.
## Spacing rule (RESEARCH Pitfall 2): no overlay note within overlay_spacing_s of a base note in
## the same lane, inside a base sustain (head .. tail + release_forgive_window) in that lane, or
## within overlay_spacing_s of another overlay note (any lane). Grid walks are bounded by
## BeatClock.MAX_BEATS and output by MAX_NOTES (hostile charts, T-03-10).

const MAX_NOTES := 256
## Grid points closer than this to a base note count as "carrying" it (float noise in charts).
const ON_NOTE_S := 0.002
const EPS := 1e-6


## 8th-note grid times in [start, end), counted from the first tempo segment.
static func grid_points(chart: ChartData, start: float, end: float) -> Array[float]:
	var out: Array[float] = []
	for p in _grid(chart, start, end):
		out.append(p[0])
	return out


## [[time, half_beat_index], ...] for the 8th-note points in [start, end), at most MAX_BEATS.
static func _grid(chart: ChartData, start: float, end: float) -> Array:
	var out: Array = []
	if not is_finite(start) or not is_finite(end) or end <= start:
		return out
	var tm := chart.tempo_map
	var k := int(ceilf(BeatClock.beat_at(start, tm) * 2.0 - 1e-4))
	while out.size() < BeatClock.MAX_BEATS:
		var t := BeatClock.time_at_beat(k * 0.5, tm)
		if t >= end - EPS:
			break
		if t >= start - EPS:
			out.append([t, k])
		k += 1
	return out


## True when an overlay note at (t, lane) obeys the spacing rule against the chart and `taken`
## (overlay notes already placed: dictionaries with "time").
static func is_free(chart: ChartData, t: float, lane: int, taken: Array, cfg: VersusConfig, jcfg: JudgeConfig) -> bool:
	return _is_free(chart.notes, t, lane, taken, cfg, jcfg)


## About ghost_per_beat ghosts per beat on free 8th-note points, seeded lanes (D-11).
static func ghosts(chart: ChartData, start: float, end: float, cfg: VersusConfig, jcfg: JudgeConfig,
		seed: int, payload_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts := _grid(chart, start, end)
	if pts.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var near := _near(chart, start, end, cfg, jcfg)
	var tm := chart.tempo_map
	var span := BeatClock.beat_at(end, tm) - BeatClock.beat_at(start, tm)
	var limit := mini(int(ceilf(cfg.ghost_per_beat * span - 1e-4)), MAX_NOTES)
	# Group the 8th points by the quarter beat they fall in (integer grid index, no float noise).
	var beats: Dictionary = {}
	var order: Array[int] = []
	for p in pts:
		var b: int = floori(p[1] / 2.0)
		if not beats.has(b):
			beats[b] = []
			order.append(b)
		(beats[b] as Array).append(p[0])
	var acc := 0.0
	for b in order:
		acc += cfg.ghost_per_beat
		while acc >= 1.0 - EPS:
			acc -= 1.0
			if out.size() >= limit:
				break
			var cands: Array = []
			for t in beats[b]:
				for lane in range(4):
					cands.append([t, lane])
			_shuffle(cands, rng)
			for c in cands:
				if _is_free(near, c[0], c[1], out, cfg, jcfg):
					out.append(_note(c[0], c[1], VersusJudge.GHOST, payload_id))
					break
		if out.size() >= limit:
			break
	out.sort_custom(_before)
	return out


## Depth Charge notes (D-14): on 8th-note points of [start, end) that carry no base note in any
## lane. Count = max(depth_charge_min_notes, min(floor(density x base notes in window), free
## points)), never more than the free points, depth_cap(jcfg) or MAX_NOTES. Seeded lanes.
static func depth_charges(chart: ChartData, start: float, end: float, cfg: VersusConfig, jcfg: JudgeConfig,
		seed: int, payload_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts := grid_points(chart, start, end)
	if pts.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var near := _near(chart, start, end, cfg, jcfg)
	var base := 0
	for n in near:
		if n["time"] >= start - EPS and n["time"] < end - EPS:
			base += 1
	var open_pts: Array = []
	for t in pts:
		if _carries_note(near, t):
			continue
		for lane in range(4):
			if _is_free(near, t, lane, [], cfg, jcfg):
				open_pts.append(t)
				break
	var count := mini(int(floor(cfg.depth_charge_density * base + EPS)), open_pts.size())
	count = maxi(count, cfg.depth_charge_min_notes)
	count = mini(count, mini(open_pts.size(), mini(depth_cap(jcfg), MAX_NOTES)))
	_shuffle(open_pts, rng)
	for t in open_pts:
		if out.size() >= count:
			break
		var lanes: Array = [0, 1, 2, 3]
		_shuffle(lanes, rng)
		for lane in lanes:
			if _is_free(near, t, lane, out, cfg, jcfg):
				out.append(_note(t, lane, VersusJudge.DEPTH, payload_id))
				break
	out.sort_custom(_before)
	return out


## Most Depth Charge notes one payload may hold, so missing every one of them cannot take a
## full hull to zero (D-08, TORP-06): ceil(hull_start / miss_damage) - 1 (12 at defaults).
static func depth_cap(jcfg: JudgeConfig) -> int:
	if jcfg.miss_damage <= 0.0:
		return MAX_NOTES
	return clampi(int(ceil(jcfg.hull_start / jcfg.miss_damage - EPS)) - 1, 1, MAX_NOTES)


## Base notes that can affect a spacing check inside [start, end).
static func _near(chart: ChartData, start: float, end: float, cfg: VersusConfig, jcfg: JudgeConfig) -> Array:
	var sp := cfg.overlay_spacing_s
	var out: Array = []
	for n in chart.notes:
		var t: float = n["time"]
		if t > end + sp:
			break
		if t + float(n["duration"]) + jcfg.release_forgive_window + sp >= start:
			out.append(n)
	return out


static func _is_free(notes: Array, t: float, lane: int, taken: Array, cfg: VersusConfig, jcfg: JudgeConfig) -> bool:
	var sp := cfg.overlay_spacing_s
	for o in taken:
		if absf(float(o["time"]) - t) < sp - EPS:
			return false
	for n in notes:
		if n["lane"] != lane:
			continue
		var nt: float = n["time"]
		if absf(nt - t) < sp - EPS:
			return false
		var dur: float = n["duration"]
		if dur > 0.0 and t >= nt - EPS and t <= nt + dur + jcfg.release_forgive_window + EPS:
			return false
	return true


static func _carries_note(notes: Array, t: float) -> bool:
	for n in notes:
		if absf(float(n["time"]) - t) < ON_NOTE_S:
			return true
	return false


static func _note(t: float, lane: int, kind: int, payload_id: int) -> Dictionary:
	return {"time": t, "lane": lane, "kind": kind, "payload_id": payload_id}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["time"] == b["time"]:
		return a["lane"] < b["lane"]
	return a["time"] < b["time"]
