class_name MatchSim
extends Referee
## The versus referee (RESEARCH Pattern 2, D-28): one pure object decides every rule from
## song-time-stamped inputs and announces each outcome as a GameEvent through an EventChannel.
## Bots, the human, the HUD and (Phase 4) the network host all go through the same code.
##
## Rules covered: firing and beat-snapped flight (TORP-02, D-04), the >= 1 beat telegraph
## (TORP-04), shields and immunity (TORP-05, D-06, D-07), head-on collisions (spec req 9),
## buffs (spec req 6), targeting (D-01..D-03), bounty (spec req 10, D-31), elimination,
## standings and last standing (MATCH-02, D-22, D-23), Return to Sender (PAY-06, D-16, D-17),
## Solo Duel (spec req 11) and wreck debris (MATCH-03, D-24, D-25).
##
## Landed stat (MATCH-05, CONTEXT default "a reflected shot does not count as landed"): the
## shooter's `landed` is incremented at LANDED for disruptors that are neither reflected nor
## debris, and decremented again if the target later reflects that payload. Reflected and debris
## landings never count as landed for anyone.
##
## Determinism (Pitfall 6): a Fire press only records a pending launch for the next whole beat.
## update(t) walks beat boundaries and timed expiries in song-time order; launches resolve per
## beat (collisions first, then the rest in seat order), then arrivals in torpedo id order.
## Every time-stamped input first catches the referee up to its own time, so the event log is
## the same whatever the frame rate. Equal times resolve as: expiries (payload end, decoy,
## overclock; then seat) before the beat boundary at that time.
##
## This class never touches nodes, never reads frame time or Settings, and never changes a
## hull: owners apply heals and damage from the events (ARCHITECTURE anti-pattern 3).

const FIRE_OK := 0
const FIRE_NOTHING := 1
const FIRE_SHIELDED := 2
const FIRE_NO_TARGET := 3
const FIRE_PENDING := 4

const EPS_BEAT := 1e-6
const EPS_T := 1e-9

## Expiry kinds, in tie order.
const _EX_PAYLOAD := 0
const _EX_DECOY := 1
const _EX_OVERCLOCK := 2
## Solo Duel milestones (announce, start, resolution) come after the per-seat expiries.
const _EX_DUEL := 3

## T-03-15: at most this many Solo Duels per chart (imported solo markers are untrusted).
const MAX_DUELS := 64

## Solo Duel states.
const _DUEL_WAIT := 0
const _DUEL_ANNOUNCED := 1
const _DUEL_RUNNING := 2
const _DUEL_DONE := 3

var chart: ChartData
var cfg: VersusConfig
var jcfg: JudgeConfig
var channel: EventChannel
var match_seed: int = 0
## Reward threshold for every meter in this match (D-30).
var threshold: int = 1
## Every event sent, in order (medals, results and determinism tests read it).
var event_log: Array[Dictionary] = []
## Seat holding the bounty, -1 for nobody (spec req 10).
var bounty_holder: int = -1

var _by_seat := {}
var _seats: Array[int] = []
## Last beat index whose boundary has been processed.
var _last_beat: int = -1
## Song time of the item being processed (stamps meter events).
var _now: float = 0.0
## Pending launches: {seat, to, reward, launch_beat, inject, reflected, debris}.
var _pending: Array[Dictionary] = []
## Torpedoes in flight: TORPEDO_LAUNCH fields + arrive_beat.
var _flights: Array[Dictionary] = []
var _next_id: int = 1
## seat -> [mode, target] last announced by TARGET.
var _target_cache := {}
## torpedo id -> {shooter, holder}: bounty claims waiting for the reflect chance to die (03-06).
var _pending_bounty := {}
## seat -> {place, alive, bucket, hull} last announced by STATUS.
var _status_cache := {}
var _last_standing_done := false
var _finished := false
## torpedo id -> {from, to, reward, warheads, k, cleared}: open warhead sets (D-16).
var _heads := {}
## Vector2i(target seat, note index) -> torpedo id, for O(1) warhead lookup.
var _head_notes := {}
## Eligible Solo Duels sorted by start: {solo (chart.solos index), start, end, lo, hi, count,
## announce_t, resolve_t, state, stats: seat -> {judged, perfects, streak, best}, parts: seat ->
## true (set at DUEL_START)}.
var _duels: Array[Dictionary] = []
## seat -> {progress, held, used}: wreck debris meters (D-24). Created at elimination.
var _debris := {}


func _init(p_chart: ChartData, p_cfg: VersusConfig, p_jcfg: JudgeConfig,
		p_players: Array[PlayerState], p_channel: EventChannel, p_match_seed: int) -> void:
	chart = p_chart
	cfg = p_cfg
	jcfg = p_jcfg
	players = p_players
	channel = p_channel
	match_seed = p_match_seed
	threshold = RewardMeter.threshold(chart.notes.size(), cfg.reward_threshold_ratio)
	for p in players:
		_by_seat[p.seat] = p
		_seats.append(p.seat)
		if p.bag == null:
			p.bag = RewardBag.new(RewardBag.seed_for(match_seed, p.seat))
		if p.meter == null:
			p.meter = RewardMeter.new(threshold, p.bag)
		p.meter.progress_changed.connect(_on_meter_progress.bind(p.seat))
		p.meter.slot_changed.connect(_on_meter_slot.bind(p.seat))
		p.meter.queue_changed.connect(_on_meter_queue.bind(p.seat))
		p.meter.reward_earned.connect(_on_meter_reward.bind(p.seat))
	_seats.sort()
	_build_duels()


# --- Statics -------------------------------------------------------------------------------

## D-04: the next whole beat strictly after the press (a press on a beat launches next beat).
static func launch_beat(t: float, tempo_map: Array) -> int:
	return int(floor(BeatClock.beat_at(t, tempo_map) + EPS_BEAT)) + 1


## Quarter beats per bar of the time signature in force at t (num * 4 / den, 4 if none).
static func bar_beats_at(t: float, p_chart: ChartData) -> float:
	var bar := 4.0
	var first := true
	for ts in p_chart.time_sigs:
		if first or float(ts.get("time", 0.0)) <= t + EPS_T:
			var num := clampi(int(ts.get("num", 4)), 1, 32)
			var den := clampi(int(ts.get("den", 4)), 1, 32)
			bar = float(num) * 4.0 / float(den)
			first = false
		else:
			break
	return bar


## Song time `bars` bars after t0 (each bar uses the time signature in force where it starts).
static func time_after_bars(t0: float, bars: int, p_chart: ChartData) -> float:
	if bars <= 0:
		return t0
	var tm: Array = p_chart.tempo_map
	var b := BeatClock.beat_at(t0, tm)
	for i in range(mini(bars, BeatClock.MAX_BEATS)):
		b += bar_beats_at(BeatClock.time_at_beat(b, tm), p_chart)
	return BeatClock.time_at_beat(b, tm)


## [start, end] of a payload landing at arrive_t (D-14, Pitfall 1): Ghost Notes and Depth
## Charge start at the first whole beat at or after arrive_t + approach_s (their notes need a
## full approach); every other payload starts on arrival. Lasts VersusConfig.bars_for bars.
static func payload_span(reward: int, arrive_t: float, approach_s: float, p_chart: ChartData,
		p_cfg: VersusConfig) -> Array[float]:
	var start := arrive_t
	if reward == Reward.Id.GHOST_NOTES or reward == Reward.Id.DEPTH_CHARGE:
		var tm: Array = p_chart.tempo_map
		var b := ceilf(BeatClock.beat_at(arrive_t + maxf(approach_s, 0.0), tm) - EPS_BEAT)
		start = BeatClock.time_at_beat(b, tm)
	var out: Array[float] = [start, time_after_bars(start, p_cfg.bars_for(reward), p_chart)]
	return out


## payload_span as a Vector2 (x = active start, y = end). Float32: use payload_span for exact
## rule times.
static func payload_window(reward: int, arrive_t: float, approach_s: float,
		p_chart: ChartData, p_cfg: VersusConfig) -> Vector2:
	var s := payload_span(reward, arrive_t, approach_s, p_chart, p_cfg)
	return Vector2(s[0], s[1])


## D-16: indices of the first `count` base notes at or after arrive_t, extended to the whole
## chord of the last one. Empty when count <= 0 or fewer than count notes remain.
static func pick_warheads(p_chart: ChartData, arrive_t: float, count: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0:
		return out
	var notes := p_chart.notes
	var n := notes.size()
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(notes[mid]["time"]) < arrive_t - EPS_T:
			lo = mid + 1
		else:
			hi = mid
	if n - lo < count:
		return out
	for i in range(lo, lo + count):
		out.append(i)
	var last_t := float(notes[lo + count - 1]["time"])
	var j := lo + count
	while j < n and absf(float(notes[j]["time"]) - last_t) <= EPS_T:
		out.append(j)
		j += 1
	return out


# --- Inputs (all time-stamped) -------------------------------------------------------------

## A base-chart judgment on `seat` (raw judgment, before any Overclock upgrade).
func on_judged(seat: int, note_index: int, judgment: int, t: float) -> void:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null:
		return
	if p.alive and not p.is_drone:
		p.meter.on_judgment(judgment, t < p.overclock_until)
	elif not p.is_drone:
		_debris_judged(seat, judgment)
	_on_judged_hook(seat, note_index, judgment, t)


## A Depth Charge overlay note judgment (D-14): Perfect credits 1, Good only under Overclock,
## Miss empties the meter.
func on_extra_judged(seat: int, judgment: int, t: float) -> void:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null or not p.alive or p.is_drone:
		return
	match judgment:
		InputJudge.Judgment.PERFECT:
			p.meter.credit(1)
		InputJudge.Judgment.GOOD:
			if t < p.overclock_until:
				p.meter.credit(1)
		_:
			p.meter.on_judgment(InputJudge.Judgment.MISS)


## A press with no note (spec req 1: strays never change the meter). Ghost Note hits are not
## strays (D-12); they arrive through on_ghost_hit.
func on_stray(_seat: int, t: float) -> void:
	_begin(t)


## A Ghost Note was hit (hull damage is the rig's VersusHull). The meter is reset only when the
## ghost_resets_meter tunable is on (CONTEXT open question 4; default off = the ghost hit does
## not reset the meter). IN-01: the flag used to be read nowhere.
func on_ghost_hit(seat: int, t: float) -> void:
	_begin(t)
	if not cfg.ghost_resets_meter:
		return
	var p: PlayerState = _by_seat.get(seat)
	if p == null or not p.alive or p.is_drone:
		return
	p.meter.on_judgment(InputJudge.Judgment.MISS)


## The owner's current hull/score values. t (optional) stamps any BOUNTY_MOVED; without it the
## last processed song time is used.
func report_status(seat: int, hull: float, depth: float, accuracy: float, max_streak: int,
		t: float = NAN) -> void:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null:
		return
	p.hull = hull
	p.depth = depth
	p.accuracy = accuracy
	p.max_streak = max_streak
	_update_bounty(_now)


## Fire the held reward (TORP-02). Buffs apply at once; disruptors queue a launch for the next
## whole beat (the reward stays held until the launch commits).
func request_fire(seat: int, t: float) -> int:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null:
		return FIRE_NOTHING
	if not p.alive and not p.is_drone:
		return _fire_debris(seat, t)
	if not p.alive or p.is_drone or p.meter.held == -1:
		_refuse(seat, "nothing")
		return FIRE_NOTHING
	if _has_pending(seat):
		return FIRE_PENDING
	var id := p.meter.held
	if Reward.is_buff(id):
		_apply_buff(p, id, t)
		return FIRE_OK
	return _queue_launch(seat, resolve_target(seat), id, t, false)


## Queue a launch without touching any meter (TrainingDrone D-27; the Phase 4 host reuses it).
## Same shield and race rules as request_fire.
func inject_fire(seat: int, to: int, reward: int, t: float) -> int:
	_begin(t)
	if not _by_seat.has(seat):
		return FIRE_NOTHING
	if not (Reward.is_disruptor(reward) or Reward.is_debris(reward)):
		return FIRE_NOTHING
	if _has_pending(seat):
		return FIRE_PENDING
	if to == seat or not _by_seat.has(to):
		_refuse(seat, "no_target")
		return FIRE_NO_TARGET
	return _queue_launch(seat, to, reward, t, true)


## D-01: AUTO -> each living rival in seat order (LOCKED) -> ATTACKERS -> AUTO. Returns the
## resolved target.
func cycle_target(seat: int, t: float = NAN) -> int:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null or p.is_drone:
		return -1
	var rivals := _living_rivals(seat)
	match p.target_mode:
		PlayerState.TargetMode.AUTO:
			if rivals.is_empty():
				p.target_mode = PlayerState.TargetMode.ATTACKERS
			else:
				p.target_mode = PlayerState.TargetMode.LOCKED
				p.locked_target = rivals[0]
		PlayerState.TargetMode.LOCKED:
			var next := -1
			for r in rivals:
				if r > p.locked_target:
					next = r
					break
			if next == -1:
				p.target_mode = PlayerState.TargetMode.ATTACKERS
				p.locked_target = -1
			else:
				p.locked_target = next
		_:
			p.target_mode = PlayerState.TargetMode.AUTO
			p.locked_target = -1
	_emit_target_if_changed(seat)
	return resolve_target(seat)


## Bots pick AUTO or ATTACKERS directly (D-20); LOCKED needs `locked`.
func set_target_mode(seat: int, mode: int, locked: int = -1, t: float = NAN) -> void:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null:
		return
	p.target_mode = mode
	p.locked_target = locked if mode == PlayerState.TargetMode.LOCKED else -1
	_emit_target_if_changed(seat)


## D-02/D-03. Wrecks resolve to the deepest living sub (debris target, D-25).
func resolve_target(seat: int) -> int:
	var p: PlayerState = _by_seat.get(seat)
	if p == null:
		return -1
	if p.alive:
		match p.target_mode:
			PlayerState.TargetMode.LOCKED:
				if _valid_rival(seat, p.locked_target):
					return p.locked_target
			PlayerState.TargetMode.ATTACKERS:
				if _valid_rival(seat, p.last_attacker):
					return p.last_attacker
	return _deepest_alive(seat)


## The sub's hull reached 0 (D-24): it becomes a wreck. Held reward, queue and buffs are lost,
## its pending launch is cancelled, torpedoes already in flight still resolve.
func on_failed(seat: int, t: float) -> void:
	_begin(t)
	var p: PlayerState = _by_seat.get(seat)
	if p == null or not p.alive or p.is_drone:
		return
	p.alive = false
	p.eliminated_at = t
	_emit(GameEvent.IMPLODED, t, {"seat": seat})
	p.meter.reset_lost()
	p.meter.enabled = false
	if is_finite(p.decoy_until):
		p.decoy_until = -INF
		_emit(GameEvent.BUFF_ENDED, t,
			{"seat": seat, "reward": Reward.Id.DECOY_FLARE, "reason": "lost"})
	if is_finite(p.overclock_until):
		p.overclock_until = -INF
		_emit(GameEvent.BUFF_ENDED, t,
			{"seat": seat, "reward": Reward.Id.OVERCLOCK, "reason": "lost"})
	var keep: Array[Dictionary] = []
	for q in _pending:
		if q["seat"] != seat or q.get("reflected", false):
			keep.append(q)
	_pending = keep
	# A wreck cannot reflect: open warhead sets on it are decided (the payload took effect).
	var ids := _heads.keys()
	ids.sort()
	for id in ids:
		if _heads[id]["to"] == seat:
			_kill_heads(id, t)
	# Spec req 11: players eliminated mid-solo leave the duel.
	for d in _duels:
		d["parts"].erase(seat)
	# D-24: the wreck keeps playing with a debris meter (same threshold, Perfects only, no bag).
	_debris[seat] = {"progress": 0, "held": -1, "used": 0}
	_emit_debris_meter(seat)
	_check_targets()
	_update_bounty(t)


## Live Perfect % (0..100) of `seat` in the running Solo Duel; -1.0 when no duel runs, the seat
## does not take part, or it has judged no solo note yet.
func duel_live(seat: int) -> float:
	for d in _duels:
		if d["state"] != _DUEL_RUNNING:
			continue
		if not d["parts"].has(seat):
			return -1.0
		var st: Dictionary = d["stats"].get(seat, {})
		if st.is_empty() or int(st["judged"]) == 0:
			return -1.0
		return float(st["perfects"]) * 100.0 / float(st["judged"])
	return -1.0


## chart.solos index of the running Solo Duel, or -1.
func duel_active() -> int:
	for d in _duels:
		if d["state"] == _DUEL_RUNNING:
			return d["solo"]
	return -1


## Process everything due up to song time t.
func update(t: float) -> void:
	_advance(t)


## D-09: the seconds a gem travels on `seat`'s highway (the same assignment SubRig makes).
func set_approach(seat: int, approach_s: float) -> void:
	var p: PlayerState = _by_seat.get(seat)
	if p != null:
		p.approach_s = approach_s


# --- Time walk -----------------------------------------------------------------------------

func _begin(t: float) -> void:
	if is_nan(t):
		return
	_advance(t)
	_now = t


func _advance(t: float) -> void:
	if not is_finite(t):
		return
	var tm: Array = chart.tempo_map
	var guard := 0
	while guard < BeatClock.MAX_BEATS:
		guard += 1
		var tb := BeatClock.time_at_beat(float(_last_beat + 1), tm)
		var ex := _next_expiry()
		if not ex.is_empty() and ex["time"] <= tb + EPS_T and ex["time"] <= t + EPS_T:
			_process_expiry(ex)
			continue
		if tb <= t + EPS_T:
			_last_beat += 1
			_process_beat(_last_beat, tb)
			continue
		break


func _next_expiry() -> Dictionary:
	var best := {}
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		var items := []
		if not p.active.is_empty():
			items.append([float(p.active["end_t"]), _EX_PAYLOAD])
		if is_finite(p.decoy_until):
			items.append([p.decoy_until, _EX_DECOY])
		if is_finite(p.overclock_until):
			items.append([p.overclock_until, _EX_OVERCLOCK])
		for it in items:
			if best.is_empty() or it[0] < best["time"] \
					or (it[0] == best["time"] and it[1] < best["kind"]):
				best = {"time": it[0], "kind": it[1], "seat": s}
	for i in range(_duels.size()):
		var d: Dictionary = _duels[i]
		var dt := _duel_next_time(d)
		if is_finite(dt) and (best.is_empty() or dt < best["time"]):
			best = {"time": dt, "kind": _EX_DUEL, "seat": i}
	return best


func _process_expiry(ex: Dictionary) -> void:
	var t: float = ex["time"]
	_now = t
	var seat: int = ex["seat"]
	var p: PlayerState = _by_seat.get(seat) if int(ex["kind"]) != _EX_DUEL else null
	match int(ex["kind"]):
		_EX_PAYLOAD:
			var rec := p.active
			p.active = {}
			p.immune_until = time_after_bars(t, cfg.immunity_bars, chart)
			_emit(GameEvent.PAYLOAD_END, t, {"id": rec["id"], "seat": seat,
				"reward": rec["reward"], "reason": rec.get("end_reason", "expired"),
				"immune_until": p.immune_until})
			# Warheads still open when the payload runs out: the reflect chance is gone.
			if _heads.has(rec["id"]):
				_kill_heads(rec["id"], t)
		_EX_DECOY:
			p.decoy_until = -INF
			_emit(GameEvent.BUFF_ENDED, t,
				{"seat": seat, "reward": Reward.Id.DECOY_FLARE, "reason": "expired"})
		_EX_OVERCLOCK:
			p.overclock_until = -INF
			_emit(GameEvent.BUFF_ENDED, t,
				{"seat": seat, "reward": Reward.Id.OVERCLOCK, "reason": "expired"})
		_EX_DUEL:
			_step_duel(_duels[seat], t)


func _process_beat(b: int, tb: float) -> void:
	_now = tb
	_resolve_launches(b, tb)
	_resolve_arrivals(b)
	_now = tb
	_beat_checks(tb)


# --- Launches, collisions, arrivals ---------------------------------------------------------

func _queue_launch(seat: int, to: int, reward: int, t: float, inject: bool,
		wreck: bool = false) -> int:
	if to == -1 or not _by_seat.has(to):
		_refuse(seat, "no_target")
		return FIRE_NO_TARGET
	var target: PlayerState = _by_seat[to]
	if not target.alive and not target.is_drone:
		_refuse(seat, "no_target")
		return FIRE_NO_TARGET
	if target.is_shielded(t):
		_refuse(seat, "shielded")
		return FIRE_SHIELDED
	var lb := maxi(launch_beat(t, chart.tempo_map), _last_beat + 1)
	_pending.append({"seat": seat, "to": to, "reward": reward, "launch_beat": lb,
		"inject": inject, "reflected": false, "debris": Reward.is_debris(reward), "wreck": wreck})
	_emit(GameEvent.FIRE_QUEUED, t, {"seat": seat, "reward": reward, "to": to, "launch_beat": lb})
	return FIRE_OK


## Reflected relaunches are not the seat's own fire, so they never block it.
func _has_pending(seat: int) -> bool:
	for q in _pending:
		if q["seat"] == seat and not q.get("reflected", false):
			return true
	return false


func _resolve_launches(b: int, tb: float) -> void:
	var due: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for q in _pending:
		if int(q["launch_beat"]) <= b:
			due.append(q)
		else:
			keep.append(q)
	if due.is_empty():
		return
	_pending = keep
	due.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["seat"] != y["seat"]:
			return x["seat"] < y["seat"]
		return x.get("reflected", false) and not y.get("reflected", false))
	var travel := cfg.torpedo_travel_beats
	var gone := {}
	# 1. Head-on pairs (spec req 9): opposite disruptors whose flights overlap.
	for i in range(due.size()):
		if gone.has(i) or not _can_collide(due[i]):
			continue
		var a: Dictionary = due[i]
		var paired := false
		for j in range(i + 1, due.size()):
			if gone.has(j) or not _can_collide(due[j]):
				continue
			var c: Dictionary = due[j]
			if c["seat"] == a["to"] and c["to"] == a["seat"]:
				gone[i] = true
				gone[j] = true
				_collide(a, c, -1, tb)
				paired = true
				break
		if paired:
			continue
		for f in _flights:
			if _can_collide(f) and f["from"] == a["to"] and f["to"] == a["seat"] \
					and int(f["launch_beat"]) < b + travel and b < int(f["arrive_beat"]):
				gone[i] = true
				_collide(a, {}, f["id"], tb, f)
				break
	# 2. The rest in seat order: shields and same-beat races.
	for i in range(due.size()):
		if not gone.has(i):
			_commit_launch(due[i], b, tb)


func _can_collide(q: Dictionary) -> bool:
	return Reward.is_disruptor(int(q["reward"])) and not q.get("reflected", false) \
		and not q.get("debris", false)


## a = pending launch; c = the opposite pending launch, or {} with flight f already in the air.
func _collide(a: Dictionary, c: Dictionary, flight_id: int, tb: float,
		f: Dictionary = {}) -> void:
	var id_a := _next_id
	_next_id += 1
	var other_seat: int
	var other_reward: int
	var id_c: int
	if c.is_empty():
		other_seat = f["from"]
		other_reward = f["reward"]
		id_c = flight_id
		_flights.erase(f)
		_forget_heads(flight_id)
		var victim: PlayerState = _by_seat[f["to"]]
		if victim.incoming_id == flight_id:
			victim.incoming_id = -1
	else:
		other_seat = c["seat"]
		other_reward = c["reward"]
		id_c = _next_id
		_next_id += 1
	var first_is_a: bool = a["seat"] < other_seat
	_emit(GameEvent.COLLISION, tb, {
		"a": a["seat"] if first_is_a else other_seat,
		"b": other_seat if first_is_a else a["seat"],
		"ids": [id_a, id_c] if first_is_a else [id_c, id_a],
		"reward_a": a["reward"] if first_is_a else other_reward,
		"reward_b": other_reward if first_is_a else a["reward"],
	})
	var pa: PlayerState = _by_seat[a["seat"]]
	pa.collisions += 1
	if not a["inject"]:
		pa.meter.use()
	var pc: PlayerState = _by_seat[other_seat]
	pc.collisions += 1
	if not c.is_empty() and not c["inject"]:
		pc.meter.use()


func _commit_launch(q: Dictionary, b: int, tb: float) -> void:
	var seat: int = q["seat"]
	var to: int = q["to"]
	var target: PlayerState = _by_seat.get(to)
	if q.get("reflected", false):
		# D-17: a reflected torpedo fizzles when the sender is gone or shielded (no refusal,
		# no race: nobody pressed Fire).
		if target == null or (not target.alive and not target.is_drone) \
				or target.is_shielded(tb):
			_emit(GameEvent.FIZZLED, tb, {"id": q.get("orig_id", -1), "from": seat, "to": to,
				"reward": q["reward"]})
			return
	if target == null or (not target.alive and not target.is_drone):
		_refuse(seat, "no_target")
		return
	if target.is_shielded(tb):
		_refuse(seat, "race")
		return
	var id := _next_id
	_next_id += 1
	var arrive_beat: int = b + cfg.torpedo_travel_beats
	var arrive_t := BeatClock.time_at_beat(float(arrive_beat), chart.tempo_map)
	var reflected: bool = q.get("reflected", false)
	var debris: bool = q.get("debris", false)
	var warheads: Array[int] = []
	if not reflected and not debris:
		warheads = pick_warheads(chart, arrive_t, cfg.warhead_count)
	var fields := {"id": id, "from": seat, "to": to, "reward": q["reward"], "launch_beat": b,
		"launch_t": tb, "arrive_t": arrive_t, "warheads": warheads, "reflected": reflected,
		"debris": debris}
	var rec := fields.duplicate()
	rec["arrive_beat"] = arrive_beat
	_flights.append(rec)
	target.incoming_id = id
	if not warheads.is_empty():
		_heads[id] = {"from": seat, "to": to, "reward": q["reward"], "warheads": warheads,
			"k": 0, "cleared": false}
		for n in warheads:
			_head_notes[Vector2i(to, n)] = id
	if not reflected and not debris:
		target.last_attacker = seat
	_emit(GameEvent.TORPEDO_LAUNCH, tb, fields)
	if not q["inject"]:
		_by_seat[seat].meter.use()
	if q.get("wreck", false):
		_consume_debris(seat)


func _resolve_arrivals(b: int) -> void:
	var due: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for f in _flights:
		if int(f["arrive_beat"]) <= b:
			due.append(f)
		else:
			keep.append(f)
	if due.is_empty():
		return
	_flights = keep
	due.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["id"] < y["id"])
	for f in due:
		_arrive(f)


func _arrive(f: Dictionary) -> void:
	var t: float = f["arrive_t"]
	_now = t
	var id: int = f["id"]
	var target: PlayerState = _by_seat[f["to"]]
	if target.incoming_id == id:
		target.incoming_id = -1
	if target.decoy_until > t:
		target.decoy_until = -INF
		target.absorbed += 1
		_forget_heads(id)
		_emit(GameEvent.ABSORBED, t,
			{"id": id, "from": f["from"], "to": f["to"], "reward": f["reward"]})
		_emit(GameEvent.BUFF_ENDED, t,
			{"seat": f["to"], "reward": Reward.Id.DECOY_FLARE, "reason": "used"})
		return
	var span := payload_span(int(f["reward"]), t, target.approach_s, chart, cfg)
	var fields := {"id": id, "from": f["from"], "to": f["to"], "reward": f["reward"],
		"arrive_t": t, "active_start": span[0], "end_t": span[1],
		"seed": hash([match_seed, id]), "reflected": f["reflected"], "debris": f["debris"]}
	var rec := fields.duplicate()
	rec["warheads"] = f["warheads"]
	target.active = rec
	if not f["reflected"] and not f["debris"]:
		_by_seat[f["from"]].landed += 1
	_emit(GameEvent.LANDED, t, fields)
	_on_landed_bounty(rec, t)
	# Every warhead was already judged Perfect before the torpedo arrived (early judgments).
	if _heads.has(id) and _heads[id]["cleared"]:
		_reflect(id, t)


# --- Buffs -----------------------------------------------------------------------------------

func _apply_buff(p: PlayerState, id: int, t: float) -> void:
	var until := t
	var amount := 0.0
	match id:
		Reward.Id.DECOY_FLARE:
			p.decoy_until = time_after_bars(t, cfg.decoy_bars, chart)
			until = p.decoy_until
		Reward.Id.OVERCLOCK:
			p.overclock_until = time_after_bars(t, cfg.overclock_bars, chart)
			until = p.overclock_until
		Reward.Id.BALLAST_PATCH:
			amount = cfg.ballast_restore_ratio * jcfg.hull_start
	p.meter.use()
	_emit(GameEvent.BUFF_APPLIED, t,
		{"seat": p.seat, "reward": id, "until_t": until, "amount": amount})


# --- Targeting -------------------------------------------------------------------------------

func _valid_rival(seat: int, r: int) -> bool:
	return r != seat and _by_seat.has(r) and _by_seat[r].alive


func _living_rivals(seat: int) -> Array[int]:
	var out: Array[int] = []
	for s in _seats:
		if _valid_rival(seat, s):
			out.append(s)
	return out


## Deepest living sub other than `exclude`; ties go to the lower seat (D-02).
func _deepest_alive(exclude: int) -> int:
	var best := -1
	for s in _seats:
		if s == exclude:
			continue
		var p: PlayerState = _by_seat[s]
		if not p.alive:
			continue
		if best == -1 or p.depth > _by_seat[best].depth:
			best = s
	return best


## A dead LOCKED target falls back to AUTO; announce any mode/target change.
func _check_targets() -> void:
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		if p.is_drone:
			continue
		if p.target_mode == PlayerState.TargetMode.LOCKED and not _valid_rival(s, p.locked_target):
			p.target_mode = PlayerState.TargetMode.AUTO
			p.locked_target = -1
		_emit_target_if_changed(s)


func _emit_target_if_changed(seat: int) -> void:
	var p: PlayerState = _by_seat[seat]
	var key := [p.target_mode, resolve_target(seat)]
	if _target_cache.has(seat) and _target_cache[seat] == key:
		return
	_target_cache[seat] = key
	_emit(GameEvent.TARGET, _now, {"seat": seat, "mode": key[0], "target": key[1]})


# --- Standings (MATCH-02, D-22, D-23) --------------------------------------------------------

## Rows {seat, place, alive, depth, hull, accuracy, max_streak, eliminated_at}, best first.
## Survivors by depth, hull, accuracy, max streak (exact equality shares a place); then the
## eliminated by later elimination beat (deaths inside one beat are simultaneous, D-22), ties by
## depth. Training drones are not ranked.
func standings() -> Array[Dictionary]:
	var alive_rows: Array[Dictionary] = []
	var dead_rows: Array[Dictionary] = []
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		if p.is_drone:
			continue
		var row := {"seat": s, "place": 0, "alive": p.alive, "depth": p.depth, "hull": p.hull,
			"accuracy": p.accuracy, "max_streak": p.max_streak, "eliminated_at": p.eliminated_at}
		if p.alive:
			alive_rows.append(row)
		else:
			dead_rows.append(row)
	alive_rows.sort_custom(_cmp_alive)
	dead_rows.sort_custom(_cmp_dead)
	for i in range(alive_rows.size()):
		var r := alive_rows[i]
		if i > 0 and _alive_key(alive_rows[i - 1]) == _alive_key(r):
			r["place"] = alive_rows[i - 1]["place"]
		else:
			r["place"] = i + 1
	var base := alive_rows.size()
	for i in range(dead_rows.size()):
		var r := dead_rows[i]
		if i > 0 and _dead_key(dead_rows[i - 1]) == _dead_key(r):
			r["place"] = dead_rows[i - 1]["place"]
		else:
			r["place"] = base + i + 1
	var out: Array[Dictionary] = []
	out.append_array(alive_rows)
	out.append_array(dead_rows)
	return out


## The single first-placed seat, or -1 for a shared first place (or no players).
func winner() -> int:
	var rows := standings()
	if rows.is_empty():
		return -1
	if rows.size() > 1 and rows[1]["place"] == 1:
		return -1
	return rows[0]["seat"]


## The song ended: MATCH_END {standings} (once).
func finish(t: float) -> void:
	_begin(t)
	if _finished:
		return
	_finished = true
	_emit(GameEvent.MATCH_END, t, {"standings": standings()})


func _elim_beat(eliminated_at: float) -> int:
	return int(floor(BeatClock.beat_at(eliminated_at, chart.tempo_map) + EPS_BEAT))


func _alive_key(r: Dictionary) -> Array:
	return [r["depth"], r["hull"], r["accuracy"], r["max_streak"]]


func _dead_key(r: Dictionary) -> Array:
	return [_elim_beat(r["eliminated_at"]), r["depth"]]


func _cmp_alive(a: Dictionary, b: Dictionary) -> bool:
	var ka := _alive_key(a)
	var kb := _alive_key(b)
	for i in range(ka.size()):
		if ka[i] != kb[i]:
			return ka[i] > kb[i]
	return a["seat"] < b["seat"]


func _cmp_dead(a: Dictionary, b: Dictionary) -> bool:
	var ka := _dead_key(a)
	var kb := _dead_key(b)
	for i in range(ka.size()):
		if ka[i] != kb[i]:
			return ka[i] > kb[i]
	return a["seat"] < b["seat"]


# --- Beat-boundary checks --------------------------------------------------------------------

func _beat_checks(tb: float) -> void:
	_update_bounty(tb)
	_check_last_standing(tb)
	_check_targets()
	_check_status(tb)


## D-22: decided at beat boundaries only, once; never when the last subs die in one beat.
func _check_last_standing(tb: float) -> void:
	if _last_standing_done:
		return
	var started := 0
	var alive_seat := -1
	var alive_n := 0
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		if p.is_drone:
			continue
		started += 1
		if p.alive:
			alive_n += 1
			alive_seat = s
	if started >= 2 and alive_n == 1:
		_last_standing_done = true
		_emit(GameEvent.LAST_STANDING, tb, {"seat": alive_seat})
	elif started >= 2 and alive_n == 0:
		_last_standing_done = true  # everyone left died inside one beat: no last standing


## STATUS per seat when place, alive, 10 m depth bucket or hull changed (once per beat max).
func _check_status(tb: float) -> void:
	var places := {}
	for r in standings():
		places[r["seat"]] = r["place"]
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		var key := [int(places.get(s, 0)), p.alive, int(floor(p.depth / 10.0)), p.hull]
		if _status_cache.has(s) and _status_cache[s] == key:
			continue
		_status_cache[s] = key
		_emit(GameEvent.STATUS, tb, {"seat": s, "hull": p.hull, "depth": p.depth,
			"alive": p.alive, "place": key[0], "accuracy": p.accuracy})


# --- Bounty (spec req 10, D-31) ---------------------------------------------------------------

## The alive leader by depth holds the bounty; ties keep the holder; nobody holds it before
## anyone has any depth. Drones never hold it.
func _update_bounty(t: float) -> void:
	var best := -1
	for s in _seats:
		var p: PlayerState = _by_seat[s]
		if not p.alive or p.is_drone:
			continue
		if best == -1 or p.depth > _by_seat[best].depth:
			best = s
	var holder := -1
	if bounty_holder != -1 and best != -1:
		var h: PlayerState = _by_seat[bounty_holder]
		if h.alive and not h.is_drone and h.depth >= _by_seat[best].depth:
			holder = bounty_holder
	if holder == -1 and best != -1 and _by_seat[best].depth > 0.0:
		holder = best
	if holder == bounty_holder:
		return
	var old := bounty_holder
	bounty_holder = holder
	_emit(GameEvent.BOUNTY_MOVED, t, {"from_seat": old, "to_seat": holder})


## A disruptor (not debris, not reflected) took effect on the holder from another seat. With no
## warheads there is no reflect chance, so it is claimed now; otherwise 03-06 claims it on the
## first failed warhead (_claim_bounty) or drops it on reflection (_drop_bounty).
func _on_landed_bounty(rec: Dictionary, t: float) -> void:
	if rec["debris"] or rec["reflected"] or not Reward.is_disruptor(int(rec["reward"])):
		return
	var from: int = rec["from"]
	var to: int = rec["to"]
	if from == to or to != bounty_holder or _by_seat[from].is_drone:
		return
	_pending_bounty[rec["id"]] = {"shooter": from, "holder": to}
	# Decide from the live warhead state, not the launch snapshot (CR-01): a non-Perfect
	# warhead judged early (before arrival) already closed the reflect chance and erased
	# _heads[id], so the claim is due now. A still-open (or already cleared) set waits for
	# _kill_heads / _reflect.
	if not _heads.has(rec["id"]):
		_claim_bounty(rec["id"], t)


## Refund round(bounty_refund_ratio x threshold) to the shooter (D-31 overflow rule lives in
## RewardMeter.add_refund). A shooter that has since become a wreck gets nothing.
func _claim_bounty(id: int, t: float) -> void:
	if not _pending_bounty.has(id):
		return
	var c: Dictionary = _pending_bounty[id]
	_pending_bounty.erase(id)
	var shooter: PlayerState = _by_seat[c["shooter"]]
	if not shooter.alive:
		return
	var refund := int(round(cfg.bounty_refund_ratio * threshold))
	shooter.bounties += 1
	_now = t
	_emit(GameEvent.BOUNTY_CLAIMED, t, {"from": c["shooter"], "to": c["holder"], "refund": refund})
	shooter.meter.add_refund(refund)


func _drop_bounty(id: int) -> void:
	_pending_bounty.erase(id)


# --- Return to Sender (PAY-06, D-16, D-17) ---------------------------------------------------

## Called for every base judgment on every seat (wrecks and drones included), after the meter.
func _on_judged_hook(seat: int, note_index: int, judgment: int, t: float) -> void:
	_warhead_judged(seat, note_index, judgment, t)
	_duel_judged(seat, note_index, judgment)


## A judged warhead note: raw PERFECT advances k (Overclock never counts); anything else ends
## the reflect chance, which decides a pending bounty claim (spec req 10 with D-17).
func _warhead_judged(seat: int, note_index: int, judgment: int, t: float) -> void:
	var key := Vector2i(seat, note_index)
	if not _head_notes.has(key):
		return
	var id: int = _head_notes[key]
	_head_notes.erase(key)
	if not _heads.has(id):
		return
	var h: Dictionary = _heads[id]
	var n: int = h["warheads"].size()
	if judgment != InputJudge.Judgment.PERFECT:
		_emit(GameEvent.WARHEAD, t,
			{"id": id, "seat": seat, "note": note_index, "k": h["k"], "n": n, "ok": false})
		_kill_heads(id, t)
		return
	h["k"] = int(h["k"]) + 1
	_emit(GameEvent.WARHEAD, t,
		{"id": id, "seat": seat, "note": note_index, "k": h["k"], "n": n, "ok": true})
	if int(h["k"]) < n:
		return
	var target: PlayerState = _by_seat[seat]
	if target.active.get("id", -1) == id:
		_reflect(id, t)
	elif _in_flight(id):
		h["cleared"] = true  # reflect the moment it lands
	else:
		_kill_heads(id, t)


func _in_flight(id: int) -> bool:
	for f in _flights:
		if f["id"] == id:
			return true
	return false


## D-17: the payload ends on the target at the next whole beat (1-beat ease out, then immunity)
## and relaunches at the sender on that beat with no warheads. The original shot stops counting
## as landed; a pending bounty claim is dropped.
func _reflect(id: int, t: float) -> void:
	var h: Dictionary = _heads[id]
	_forget_heads(id)
	var by: int = h["to"]
	var sender: int = h["from"]
	var p: PlayerState = _by_seat[by]
	var rec := p.active
	p.reflected += 1
	_by_seat[sender].landed = maxi(0, _by_seat[sender].landed - 1)
	_drop_bounty(id)
	var lb := maxi(launch_beat(t, chart.tempo_map), _last_beat + 1)
	var te := BeatClock.time_at_beat(float(lb), chart.tempo_map)
	if te < float(rec["end_t"]):
		rec["end_t"] = te
	rec["end_reason"] = "reflected"
	_emit(GameEvent.REFLECTED, t, {"id": id, "by": by, "to": sender, "reward": h["reward"]})
	_pending.append({"seat": by, "to": sender, "reward": h["reward"], "launch_beat": lb,
		"inject": true, "reflected": true, "debris": false, "orig_id": id})


## The reflect chance died: forget the warheads and claim any pending bounty now.
func _kill_heads(id: int, t: float) -> void:
	_forget_heads(id)
	_claim_bounty(id, t)


func _forget_heads(id: int) -> void:
	if not _heads.has(id):
		return
	var h: Dictionary = _heads[id]
	for n in h["warheads"]:
		var key := Vector2i(int(h["to"]), int(n))
		if _head_notes.get(key, -1) == id:
			_head_notes.erase(key)
	_heads.erase(id)


# --- Solo Duel (spec req 11, Pitfall 9) --------------------------------------------------------

## Eligible duels from the untrusted chart.solos (T-03-15): finite start < end, start not after
## the last note, base notes recounted with start <= time <= end, at least solo_duel_min_notes,
## no overlap with an earlier kept solo, at most MAX_DUELS.
func _build_duels() -> void:
	_duels = []
	var notes := chart.notes
	if notes.is_empty():
		return
	var last_t := float(notes[notes.size() - 1]["time"])
	var cands: Array[Dictionary] = []
	for i in range(chart.solos.size()):
		var so = chart.solos[i]
		if not (so is Dictionary):
			continue
		var st := float(so.get("start", NAN))
		var en := float(so.get("end", NAN))
		if not is_finite(st) or not is_finite(en) or en <= st or st > last_t + EPS_T:
			continue
		var lo := _first_note_at_or_after(st - EPS_T)
		var hi := _first_note_at_or_after(en + EPS_T) - 1
		var count := hi - lo + 1
		if count < maxi(1, cfg.solo_duel_min_notes):
			continue
		cands.append({"solo": i, "start": st, "end": en, "lo": lo, "hi": hi, "count": count})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["start"] != b["start"]:
			return a["start"] < b["start"]
		return a["solo"] < b["solo"])
	var tm: Array = chart.tempo_map
	var prev_end := -INF
	for c in cands:
		if _duels.size() >= MAX_DUELS:
			break
		if c["start"] <= prev_end + EPS_T:
			continue
		prev_end = c["end"]
		var st: float = c["start"]
		var ab := BeatClock.beat_at(st, tm) - bar_beats_at(st, chart)
		c["announce_t"] = clampf(BeatClock.time_at_beat(ab, tm), 0.0, st)
		c["resolve_t"] = float(c["end"]) + jcfg.good_window + 0.001
		c["state"] = _DUEL_WAIT
		c["stats"] = {}
		c["parts"] = {}
		_duels.append(c)


func _first_note_at_or_after(t: float) -> int:
	var notes := chart.notes
	var lo := 0
	var hi := notes.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(notes[mid]["time"]) < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


func _duel_next_time(d: Dictionary) -> float:
	match int(d["state"]):
		_DUEL_WAIT:
			return d["announce_t"]
		_DUEL_ANNOUNCED:
			return d["start"]
		_DUEL_RUNNING:
			return d["resolve_t"]
	return INF


func _step_duel(d: Dictionary, t: float) -> void:
	match int(d["state"]):
		_DUEL_WAIT:
			d["state"] = _DUEL_ANNOUNCED
			_emit(GameEvent.DUEL_ANNOUNCE, t, {"solo": d["solo"], "start": d["start"],
				"end": d["end"], "note_count": d["count"]})
		_DUEL_ANNOUNCED:
			d["state"] = _DUEL_RUNNING
			for s in _seats:
				var p: PlayerState = _by_seat[s]
				if p.alive and not p.is_drone:
					d["parts"][s] = true
			_emit(GameEvent.DUEL_START, t, {"solo": d["solo"]})
		_DUEL_RUNNING:
			d["state"] = _DUEL_DONE
			_resolve_duel(d, t)


## Base solo notes only (overlay notes never reach this hook). Judgments are tracked from the
## announcement, so a solo note judged early (before DUEL_START) still counts.
func _duel_judged(seat: int, note_index: int, judgment: int) -> void:
	for d in _duels:
		var state: int = d["state"]
		if state != _DUEL_ANNOUNCED and state != _DUEL_RUNNING:
			continue
		if note_index < int(d["lo"]) or note_index > int(d["hi"]):
			continue
		if state == _DUEL_RUNNING and not d["parts"].has(seat):
			continue
		var stats: Dictionary = d["stats"]
		if not stats.has(seat):
			stats[seat] = {"judged": 0, "perfects": 0, "streak": 0, "best": 0}
		var st: Dictionary = stats[seat]
		st["judged"] = int(st["judged"]) + 1
		if judgment == InputJudge.Judgment.PERFECT:
			st["perfects"] = int(st["perfects"]) + 1
			st["streak"] = int(st["streak"]) + 1
			st["best"] = maxi(int(st["best"]), int(st["streak"]))
		else:
			st["streak"] = 0


## Final % = Perfects / solo note count. Best % at or above solo_duel_min_accuracy wins; ties
## by longest in-solo Perfect streak; still tied -> winner -1, tied true. pct is the winner's %
## (-1.0 without a winner); best_pct is the best % of any participant.
func _resolve_duel(d: Dictionary, t: float) -> void:
	var count: int = d["count"]
	var best_pct := 0.0
	var top: Array[int] = []
	var top_p := -1
	var top_s := -1
	var min_p := cfg.solo_duel_min_accuracy * 100.0 - 1e-9
	var parts: Array = d["parts"].keys()
	parts.sort()
	for s in parts:
		var p: PlayerState = _by_seat[s]
		if not p.alive:
			continue
		var st: Dictionary = d["stats"].get(s, {"perfects": 0, "best": 0})
		var perf: int = st["perfects"]
		var pct := float(perf) * 100.0 / float(count)
		best_pct = maxf(best_pct, pct)
		if pct < min_p:
			continue
		var streak: int = st["best"]
		if perf > top_p or (perf == top_p and streak > top_s):
			top = [s]
			top_p = perf
			top_s = streak
		elif perf == top_p and streak == top_s:
			top.append(s)
	var winner: int = top[0] if top.size() == 1 else -1
	var tied := top.size() > 1
	var wpct: float = float(top_p) * 100.0 / float(count) if winner != -1 else -1.0
	_now = t
	_emit(GameEvent.DUEL_RESULT, t, {"solo": d["solo"], "winner": winner, "pct": wpct,
		"best_pct": best_pct, "tied": tied})
	if winner == -1:
		return
	var w: PlayerState = _by_seat[winner]
	w.duels_won += 1
	# Prize: next bag item into the slot, else the one-item queue; dropped if both are full.
	# queue_prize emits REWARD_EARNED "duel" / REWARD_QUEUED through the meter signals.
	if w.meter.held == -1 or w.meter.queued == -1:
		w.meter.queue_prize(w.bag.draw())


# --- Wreck debris (MATCH-03, TORP-06, D-24, D-25) ----------------------------------------------

## Perfect +1, Miss resets, Good nothing (Overclock was lost with the hull). At the threshold
## the debris is SILT on an even debris count, GROAN on an odd one. After
## debris_max_per_wreck launches the meter is disabled (no more fills).
func _debris_judged(seat: int, judgment: int) -> void:
	if not _debris.has(seat):
		return
	var d: Dictionary = _debris[seat]
	if int(d["used"]) >= cfg.debris_max_per_wreck:
		return
	match judgment:
		InputJudge.Judgment.PERFECT:
			if int(d["held"]) != -1:
				return
			d["progress"] = int(d["progress"]) + 1
			if int(d["progress"]) >= threshold:
				d["progress"] = threshold
				d["held"] = Reward.Id.SILT if int(d["used"]) % 2 == 0 else Reward.Id.GROAN
				_emit_debris_meter(seat)
				_emit(GameEvent.REWARD_EARNED, _now,
					{"seat": seat, "reward": d["held"], "source": "debris"})
			else:
				_emit_debris_meter(seat)
		InputJudge.Judgment.GOOD:
			pass
		_:
			if int(d["progress"]) != 0:
				d["progress"] = 0
				_emit_debris_meter(seat)


## D-25: auto-target only, the living leader by depth (never the lowest-depth sub with 3+
## alive); shields, races and Decoy as for disruptors; no warheads, bounty or collision.
func _fire_debris(seat: int, t: float) -> int:
	var d: Dictionary = _debris.get(seat, {})
	if d.is_empty() or int(d["held"]) == -1:
		_refuse(seat, "nothing")
		return FIRE_NOTHING
	if _has_pending(seat):
		return FIRE_PENDING
	var to := _deepest_alive(seat)
	if to == -1:
		_refuse(seat, "no_target")
		return FIRE_NO_TARGET
	return _queue_launch(seat, to, int(d["held"]), t, true, true)


## The debris left the tube: empty the meter and count it (PlayerState.debris_used for views).
func _consume_debris(seat: int) -> void:
	if not _debris.has(seat):
		return
	var d: Dictionary = _debris[seat]
	d["held"] = -1
	d["progress"] = 0
	d["used"] = int(d["used"]) + 1
	_by_seat[seat].debris_used = d["used"]
	_emit_debris_meter(seat)


func _emit_debris_meter(seat: int) -> void:
	var d: Dictionary = _debris[seat]
	_emit(GameEvent.METER, _now, {"seat": seat, "progress": d["progress"],
		"threshold": threshold, "held": d["held"], "queued": -1, "debris": true})


# --- Events ----------------------------------------------------------------------------------

func _emit(type: String, t: float, fields: Dictionary = {}) -> void:
	var e := GameEvent.make(type, t, fields)
	event_log.append(e)
	channel.send(e)


func _refuse(seat: int, reason: String) -> void:
	_emit(GameEvent.FIRE_REFUSED, _now, {"seat": seat, "reason": reason})


func _emit_meter(seat: int) -> void:
	var m: RewardMeter = _by_seat[seat].meter
	_emit(GameEvent.METER, _now, {"seat": seat, "progress": m.progress, "threshold": m.target,
		"held": m.held, "queued": m.queued, "debris": false})


func _on_meter_progress(_v: int, _th: int, seat: int) -> void:
	_emit_meter(seat)


func _on_meter_slot(_id: int, seat: int) -> void:
	_emit_meter(seat)


func _on_meter_queue(id: int, seat: int) -> void:
	if id != -1:
		_emit(GameEvent.REWARD_QUEUED, _now, {"seat": seat, "reward": id})
	_emit_meter(seat)


func _on_meter_reward(id: int, source: String, seat: int) -> void:
	_emit(GameEvent.REWARD_EARNED, _now, {"seat": seat, "reward": id, "source": source})
