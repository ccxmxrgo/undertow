class_name BotPlayer
extends RefCounted
## A seeded bot rival (RESEARCH Pattern 4, D-19, D-20, MATCH-01). It plays the real chart through
## its own SubRig, so the referee judges it with exactly the human's rules code.
##
## Timing (D-19): every base note entering a LOOKAHEAD_S window is sampled once, in note order,
## with the profile in effect at the note's time (payload penalties from the rig's stack): lapse
## (no press) or a press at note time + N(bias, sigma). Presses outside the judge's reach are
## dropped (a miss, never a stray press). Ghost Notes are pressed with ghost_press_p, Depth Charge
## notes are played like base notes; both are sampled when their payload lands.
##
## Fire policy (D-20): a held disruptor fires 1-8 beats (seeded) after it was earned, at AUTO
## or (p bot_attackers_p) ATTACKERS; refused shots re-pick AUTO and retry on the next beat.
## Decoy and Overclock fire at once; Ballast at hull <= bot_ballast_hull or after
## bot_ballast_wait_bars bars; wreck debris fires as soon as it is held.
##
## Determinism: every action happens at an exact song time (next_time / step), and the RNG is
## private and seeded, so a driver that steps actors in global time order (MatchHarness) gets the
## same match at any frame rate. update(t) is the simple per-frame driver.

const LOOKAHEAD_S := 1.0
const EPS_BEAT := 1e-6

var rig: SubRig
var profile: BotProfile
var sim: MatchSim
var cfg: VersusConfig
var chart: ChartData
var seat: int
## Every press made: [t, lane] (tests, determinism).
var press_log: Array = []
## Every fire attempt: {t, reward, result}.
var fire_log: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _sample_next: int = 0
## Pending inputs {time, kind (0 release, 1 press), lane}, sorted; _q_head = next to play.
var _queue: Array[Dictionary] = []
var _q_head: int = 0
## Fire plan: {reward, debris, fire_t, waiting, mode_chosen}, or {} when nothing to fire.
var _plan: Dictionary = {}
var _jcfg: JudgeConfig


func _init(p_rig: SubRig, p_profile: BotProfile, p_sim: MatchSim, p_cfg: VersusConfig,
		p_chart: ChartData, p_seed: int) -> void:
	rig = p_rig
	profile = p_profile
	sim = p_sim
	cfg = p_cfg
	chart = p_chart
	seat = rig.seat
	_jcfg = rig.jcfg
	_rng.seed = p_seed
	rig.overlay_added.connect(_on_overlay_added)
	rig.hull.hull_changed.connect(_on_hull_changed)
	rig.channel.received.connect(_on_event)


## The profile in effect at song time t (D-19 payload penalties from this bot's stack).
func effective_profile(t: float) -> BotProfile:
	return profile.effective_for(rig.stack.active_reward(t))


## Song time of this bot's next action (INF when idle).
func next_time() -> float:
	var best := INF
	if _sample_next < chart.notes.size():
		best = float(chart.notes[_sample_next]["time"]) - LOOKAHEAD_S
	if _q_head < _queue.size():
		best = minf(best, float(_queue[_q_head]["time"]))
	if not _plan.is_empty() and not _plan["waiting"]:
		best = minf(best, float(_plan["fire_t"]))
	return best


## Performs the earliest pending action (ties: fire, then inputs, then sampling).
func step() -> void:
	var t := next_time()
	if not is_finite(t):
		return
	if not _plan.is_empty() and not _plan["waiting"] and float(_plan["fire_t"]) <= t:
		_attempt(t)
		return
	if _q_head < _queue.size() and float(_queue[_q_head]["time"]) <= t:
		var e: Dictionary = _queue[_q_head]
		_q_head += 1
		if e["kind"] == 1:
			press_log.append([e["time"], e["lane"]])
			rig.press(e["lane"], e["time"])
		else:
			rig.release(e["lane"], e["time"])
		return
	_sample_base(_sample_next)
	_sample_next += 1


## Simple per-frame driver: every action due by t in time order, then the rig's tick.
func update(t: float) -> void:
	var guard := 0
	while next_time() <= t and guard < 100000:
		guard += 1
		step()
	rig.tick(t)


# --- timing ------------------------------------------------------------------------------------

func _gauss() -> float:
	var u1 := maxf(_rng.randf(), 1e-12)
	var u2 := _rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func _sample_base(i: int) -> void:
	var n: Dictionary = chart.notes[i]
	var nt := float(n["time"])
	var p := effective_profile(nt)
	if _rng.randf() < p.lapse:
		return
	var err := p.bias_s + p.sigma_s * _gauss()
	if err < -_jcfg.early_miss_window or err > _jcfg.good_window:
		return  # outside the judge's reach: a miss, never a stray press (D-19)
	_enqueue(nt + err, 1, int(n["lane"]))
	var dur := float(n["duration"])
	if dur > 0.0:
		_enqueue(maxf(nt + dur, nt + err + 1e-4), 0, int(n["lane"]))


func _on_overlay_added(_payload_id: int, notes: Array) -> void:
	var sorted := notes.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time"] == b["time"]:
			return a["lane"] < b["lane"]
		return a["time"] < b["time"])
	for n in sorted:
		var nt := float(n["time"])
		var p := effective_profile(nt)
		if int(n["kind"]) == VersusJudge.GHOST:
			if _rng.randf() >= p.ghost_press_p:
				continue
			var gerr := p.sigma_s * _gauss()
			if absf(gerr) <= _jcfg.good_window:
				_enqueue(nt + gerr, 1, int(n["lane"]))
		else:
			if _rng.randf() < p.lapse:
				continue
			var err := p.bias_s + p.sigma_s * _gauss()
			if err >= -_jcfg.early_miss_window and err <= _jcfg.good_window:
				_enqueue(nt + err, 1, int(n["lane"]))


func _enqueue(t: float, kind: int, lane: int) -> void:
	var e := {"time": t, "kind": kind, "lane": lane}
	var i := _q_head
	while i < _queue.size() and not _before(e, _queue[i]):
		i += 1
	_queue.insert(i, e)
	if _q_head > 512:
		_queue = _queue.slice(_q_head)
		_q_head = 0


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["time"] == b["time"]:
		if a["kind"] == b["kind"]:
			return a["lane"] < b["lane"]
		return a["kind"] < b["kind"]
	return a["time"] < b["time"]


# --- fire policy (D-20) --------------------------------------------------------------------------

func _next_beat_t(t: float) -> float:
	var tm: Array = chart.tempo_map
	return BeatClock.time_at_beat(floorf(BeatClock.beat_at(t, tm) + EPS_BEAT) + 1.0, tm)


func _new_plan(reward: int, t: float, debris: bool) -> void:
	_plan = {"reward": reward, "debris": debris, "fire_t": t, "waiting": false,
		"mode_chosen": false}
	if debris:
		return
	if Reward.is_disruptor(reward):
		var tm: Array = chart.tempo_map
		var k := _rng.randi_range(cfg.bot_fire_delay_min_beats, cfg.bot_fire_delay_max_beats)
		_plan["fire_t"] = BeatClock.time_at_beat(
			floorf(BeatClock.beat_at(t, tm) + EPS_BEAT) + float(k), tm)
	elif reward == Reward.Id.BALLAST_PATCH and rig.hull.hull > cfg.bot_ballast_hull:
		_plan["fire_t"] = MatchSim.time_after_bars(t, cfg.bot_ballast_wait_bars, chart)


func _attempt(t: float) -> void:
	var reward: int = _plan["reward"]
	if Reward.is_disruptor(reward) and not _plan["mode_chosen"]:
		_plan["mode_chosen"] = true
		var mode := PlayerState.TargetMode.AUTO
		if _rng.randf() < cfg.bot_attackers_p:
			mode = PlayerState.TargetMode.ATTACKERS
		sim.set_target_mode(seat, mode, -1, t)
	var r := sim.request_fire(seat, t)
	fire_log.append({"t": t, "reward": reward, "result": r})
	if _plan.is_empty():
		return  # the fire resolved synchronously (buff applied) and cleared the plan
	match r:
		MatchSim.FIRE_OK:
			_plan["waiting"] = true
		MatchSim.FIRE_NOTHING:
			if _plan["debris"]:
				_plan["fire_t"] = _next_beat_t(t)
			else:
				_plan = {}
		_:
			if Reward.is_disruptor(reward):
				sim.set_target_mode(seat, PlayerState.TargetMode.AUTO, -1, t)  # re-pick
			_plan["fire_t"] = _next_beat_t(t)


func _on_hull_changed(value: float, _delta: float) -> void:
	if _plan.is_empty() or _plan["waiting"] or _plan["reward"] != Reward.Id.BALLAST_PATCH:
		return
	if value <= cfg.bot_ballast_hull and float(_plan["fire_t"]) > rig.now:
		_plan["fire_t"] = rig.now


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		GameEvent.METER:
			if int(e.get("seat", -1)) != seat or e.get("debris", false):
				return
			var held := int(e.get("held", -1))
			if held == -1:
				if not _plan.is_empty() and not _plan["debris"]:
					_plan = {}
			elif _plan.is_empty() or _plan["reward"] != held:
				_new_plan(held, float(e["t"]), false)
		GameEvent.REWARD_EARNED:
			if int(e.get("seat", -1)) == seat and e.get("source", "") == "debris":
				_new_plan(int(e["reward"]), float(e["t"]), true)
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("from", -1)) == seat and not e.get("reflected", false):
				_plan = {}
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == seat:
				_plan = {}
		GameEvent.COLLISION:
			if int(e.get("a", -1)) == seat or int(e.get("b", -1)) == seat:
				_plan = {}
		GameEvent.FIRE_REFUSED:
			if int(e.get("seat", -1)) == seat and not _plan.is_empty() and _plan["waiting"]:
				_plan["waiting"] = false
				_plan["fire_t"] = _next_beat_t(float(e["t"]))
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == seat:
				_plan = {}
