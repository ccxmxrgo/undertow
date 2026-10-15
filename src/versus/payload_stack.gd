class_name PayloadStack
extends RefCounted
## View/input-facing modifier state for one player's highway. Reads payload records; decides
## no rules (D-28). Every query is a pure function of song time t and eases over exactly one
## beat in beat space (BeatClock), so effects are beat-locked and frame-rate independent
## (UI-SPEC 3.3). ChartData is never modified (RESEARCH Pattern 3).
##
## Payload record (MatchSim LANDED, plain Dictionary):
##   {id, reward (Reward.Id), from, to, arrive_t, active_start, end_t, seed, reflected, debris}
## Effects ease in over [arrive_t, arrive_t + 1 beat] and out over [end_t, end_t + 1 beat].

## Warhead mark states; same values as NotePainter.WARHEAD_* (UI-SPEC 7.1).
const OPEN := 0
const CONFIRMED := 1
const DEAD := 2

const EPS := 1e-6

var _chart: ChartData
var _cfg: VersusConfig
## Installed payloads: {id, reward, seed, b_arr, b_end, a, b} (beats from BeatClock.beat_at).
var _payloads: Array[Dictionary] = []
var _warheads: Dictionary = {}  # base note index -> {torpedo, state}
var _marks: Dictionary = {}  # torpedo id -> Array of note indices


func _init(chart: ChartData, cfg: VersusConfig) -> void:
	_chart = chart
	_cfg = cfg


## Adds (or replaces, by id) a payload record. Invalid records are ignored.
func install(p: Dictionary) -> void:
	var reward = p.get("reward")
	var arrive = p.get("arrive_t")
	var end = p.get("end_t")
	if not (reward is int) or not Reward.is_valid(reward):
		return
	if not (arrive is float or arrive is int) or not (end is float or end is int):
		return
	if not is_finite(float(arrive)) or not is_finite(float(end)):
		return
	var id := int(p.get("id", -1))
	var seed := int(p.get("seed", 0))
	var b_arr := _beat(float(arrive))
	var e := {
		"id": id, "reward": reward, "seed": seed,
		"b_arr": b_arr, "b_end": maxf(_beat(float(end)), b_arr), "a": -1, "b": -1,
	}
	if reward == Reward.Id.CROSSED_WIRES:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var a := rng.randi_range(0, 3)
		var b := rng.randi_range(0, 2)
		if b >= a:
			b += 1
		e["a"] = a
		e["b"] = b
	if id >= 0:
		_remove(id)
	_payloads.append(e)


## Ends a payload early (reflection, D-17): the 1-beat ease-out starts at the next whole beat
## after t. Never moves an end later.
func end_early(id: int, t: float) -> void:
	if not is_finite(t):
		return
	for e in _payloads:
		if e["id"] == id:
			var nb := floorf(_beat(t) + EPS) + 1.0
			e["b_end"] = maxf(minf(e["b_end"], nb), e["b_arr"])


## Ends a payload at the referee's end time t (PAYLOAD_END "reflected", WR-02): the 1-beat
## ease-out starts AT t (MatchSim already put t on the next whole beat after the reflection).
## Never moves an end later.
func end_at(id: int, t: float) -> void:
	if not is_finite(t):
		return
	for e in _payloads:
		if e["id"] == id:
			e["b_end"] = maxf(minf(e["b_end"], _beat(t)), e["b_arr"])


func clear() -> void:
	_payloads.clear()
	_warheads.clear()
	_marks.clear()


## Drops payloads whose ease-out finished before t.
func prune(t: float) -> void:
	var bt := _beat(t)
	_payloads.assign(_payloads.filter(func(e: Dictionary) -> bool: return bt < e["b_end"] + 1.0))


func payload_count() -> int:
	return _payloads.size()


## Scroll multiplier (Pressure Crack D-09, Groan D-25), smoothstep over 1 beat each way.
func scroll_mult(t: float) -> float:
	var m := 1.0
	var bt := _beat(t)
	for e in _payloads:
		var target := _scroll_target(e["reward"])
		if target > 1.0:
			m = maxf(m, 1.0 + (target - 1.0) * _k(e, bt))
	return m


## Effective scroll speed (D-09, Pitfall 8): base x mult, capped at max(base, cap), never
## slower than base.
static func effective_speed(base: float, mult: float, cap: float) -> float:
	return maxf(base, minf(base * mult, maxf(base, cap)))


## Outer-rail warning tint 0..1 (UI-SPEC 7.5): Pressure Crack k, Groan 0.5 k.
func rail_tint(t: float) -> float:
	var k := 0.0
	var bt := _beat(t)
	for e in _payloads:
		if e["reward"] == Reward.Id.PRESSURE_CRACK:
			k = maxf(k, _k(e, bt))
		elif e["reward"] == Reward.Id.GROAN:
			k = maxf(k, 0.5 * _k(e, bt))
	return k


## Trench.lane_f-space x where `lane` is drawn at t (Crossed Wires slide, cubic in-out, D-10).
func lane_pos(lane: int, t: float) -> float:
	var f := Trench.lane_f(lane)
	var e := _crossed_at(_beat(t))
	if e.is_empty():
		return f
	var c := _slide_c(e, _beat(t))
	if lane == e["a"]:
		return lerpf(f, Trench.lane_f(e["b"]), c)
	if lane == e["b"]:
		return lerpf(f, Trench.lane_f(e["a"]), c)
	return f


## Linear 0..1 progress of the Crossed Wires slide running at t (in or return); 0 otherwise.
func slide_k(t: float) -> float:
	var bt := _beat(t)
	var e := _crossed_at(bt)
	if e.is_empty():
		return 0.0
	if bt >= e["b_end"]:
		return clampf(bt - e["b_end"], 0.0, 1.0)
	if bt < e["b_arr"] + 1.0:
		return clampf(bt - e["b_arr"], 0.0, 1.0)
	return 0.0


## True while a Crossed Wires slide (in or return) is running at t (swap guides).
func sliding(t: float) -> bool:
	var bt := _beat(t)
	var e := _crossed_at(bt)
	if e.is_empty():
		return false
	return bt < e["b_arr"] + 1.0 or bt >= e["b_end"]


## Crossed lanes (a, b), or (-1, -1). With no t: the latest installed Crossed Wires payload;
## with t: only if it is active (arrival .. end of the return slide) at t.
func crossed_pair(t: float = NAN) -> Vector2i:
	var e: Dictionary = {}
	if is_nan(t):
		for p in _payloads:
			if p["reward"] == Reward.Id.CROSSED_WIRES:
				e = p
	else:
		e = _crossed_at(_beat(t))
	if e.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(e["a"], e["b"])


## Physical lane action index -> judged lane (D-10): input follows screen position and switches
## at the end of the in-slide, back at the end of the return slide.
func input_map(t: float) -> PackedInt32Array:
	var m := PackedInt32Array([0, 1, 2, 3])
	var bt := _beat(t)
	var e := _crossed_at(bt)
	if e.is_empty():
		return m
	if bt >= e["b_arr"] + 1.0 - EPS and bt < e["b_end"] + 1.0 - EPS:
		m[e["a"]] = e["b"]
		m[e["b"]] = e["a"]
	return m


## Sonar Jam colour fade 0..1 (D-15).
func jam_amount(t: float) -> float:
	return _amount(t, [Reward.Id.SONAR_JAM])


## Ink Cloud / Silt opacity 0..1 (D-13, D-25).
func ink_amount(t: float) -> float:
	return _amount(t, [Reward.Id.INK_CLOUD, Reward.Id.SILT])


## Top depth of the ink band: Ink Cloud ink_depth_top (0.35), Silt silt_depth_top (0.20).
## With t: the highest top among ink payloads visible at t; otherwise (or none visible) the
## latest installed ink payload; cfg.ink_depth_top when there is none.
func ink_top_depth(t: float = NAN) -> float:
	var top := -INF
	var latest := -1
	if not is_nan(t):
		var bt := _beat(t)
		for e in _payloads:
			if _is_ink(e["reward"]) and _k(e, bt) > 0.0:
				top = maxf(top, _ink_top(e["reward"]))
	if top > -INF:
		return top
	for e in _payloads:
		if _is_ink(e["reward"]):
			latest = e["reward"]
	return _ink_top(latest) if latest >= 0 else _cfg.ink_depth_top


## Reward id of the most recently arrived payload active at t (arrival .. end of ease-out), -1.
func active_reward(t: float) -> int:
	var bt := _beat(t)
	var best := -1
	var best_b := -INF
	for e in _payloads:
		if bt >= e["b_arr"] and bt < e["b_end"] + 1.0 and e["b_arr"] >= best_b:
			best = e["reward"]
			best_b = e["b_arr"]
	return best


# ---- warheads (UI-SPEC 7.1, D-16, D-17) ----

func mark_warheads(torpedo_id: int, indices: Array) -> void:
	var list: Array = []
	for i in indices:
		if i is int:
			_warheads[i] = {"torpedo": torpedo_id, "state": OPEN}
			list.append(i)
	_marks[torpedo_id] = list


## A warhead note judged Perfect.
func confirm(note_index: int) -> void:
	var w = _warheads.get(note_index)
	if w != null and w["state"] == OPEN:
		w["state"] = CONFIRMED


## The reflect chance is gone: remaining OPEN warheads of that torpedo become DEAD.
func kill(torpedo_id: int) -> void:
	for i in _marks.get(torpedo_id, []):
		var w = _warheads.get(i)
		if w != null and w["torpedo"] == torpedo_id and w["state"] == OPEN:
			w["state"] = DEAD


func clear_warheads(torpedo_id: int) -> void:
	for i in _marks.get(torpedo_id, []):
		var w = _warheads.get(i)
		if w != null and w["torpedo"] == torpedo_id:
			_warheads.erase(i)
	_marks.erase(torpedo_id)


## OPEN / CONFIRMED / DEAD, or -1 for a note that is not a warhead.
func warhead_state(note_index: int) -> int:
	var w = _warheads.get(note_index)
	return -1 if w == null else int(w["state"])


## (confirmed, total) for one torpedo's warheads; (0, 0) when unknown.
func warhead_progress(torpedo_id: int) -> Vector2i:
	var list: Array = _marks.get(torpedo_id, [])
	var k := 0
	var n := 0
	for i in list:
		var w = _warheads.get(i)
		if w != null and w["torpedo"] == torpedo_id:
			n += 1
			if w["state"] == CONFIRMED:
				k += 1
	return Vector2i(k, n)


# ---- internals ----

func _beat(t: float) -> float:
	return BeatClock.beat_at(t, _chart.tempo_map)


## Smoothstep ease factor 0..1 of one payload at beat bt.
func _k(e: Dictionary, bt: float) -> float:
	var b_arr: float = e["b_arr"]
	var b_end: float = e["b_end"]
	if bt < b_arr or bt >= b_end + 1.0:
		return 0.0
	var k_in := smoothstep(0.0, 1.0, bt - b_arr)
	var k_out := 1.0 - smoothstep(0.0, 1.0, bt - b_end)
	return minf(k_in, k_out)


## Cubic in-out slide amount 0..1 of a Crossed Wires payload at beat bt.
func _slide_c(e: Dictionary, bt: float) -> float:
	var c_in := _cubic(clampf(bt - e["b_arr"], 0.0, 1.0))
	var c_out := 1.0 - _cubic(clampf(bt - e["b_end"], 0.0, 1.0))
	return minf(c_in, c_out)


static func _cubic(x: float) -> float:
	if x < 0.5:
		return 4.0 * x * x * x
	var y := -2.0 * x + 2.0
	return 1.0 - y * y * y / 2.0


## Latest Crossed Wires payload active at beat bt, or {}.
func _crossed_at(bt: float) -> Dictionary:
	var found: Dictionary = {}
	for e in _payloads:
		if e["reward"] == Reward.Id.CROSSED_WIRES and bt >= e["b_arr"] and bt < e["b_end"] + 1.0:
			found = e
	return found


func _amount(t: float, rewards: Array) -> float:
	var bt := _beat(t)
	var k := 0.0
	for e in _payloads:
		if rewards.has(e["reward"]):
			k = maxf(k, _k(e, bt))
	return k


func _scroll_target(reward: int) -> float:
	if reward == Reward.Id.PRESSURE_CRACK:
		return _cfg.pressure_crack_mult
	if reward == Reward.Id.GROAN:
		return _cfg.groan_mult
	return 1.0


static func _is_ink(reward: int) -> bool:
	return reward == Reward.Id.INK_CLOUD or reward == Reward.Id.SILT


func _ink_top(reward: int) -> float:
	return _cfg.silt_depth_top if reward == Reward.Id.SILT else _cfg.ink_depth_top


func _remove(id: int) -> void:
	_payloads.assign(_payloads.filter(func(e: Dictionary) -> bool: return e["id"] != id))
