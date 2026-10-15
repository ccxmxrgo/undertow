class_name TrainingDrone
extends RefCounted
## Solo Dive training target and launcher (D-27, MATCH-06). A dummy rival seat (PlayerState
## is_drone: no rig, never presses, never fails, never ranked) that fires the chosen disruptor,
## or all six in Reward.ALL order (mode -2), at the human every training_interval_bars bars,
## starting at the first whole bar 4 bars into the song. Fires go through MatchSim.inject_fire,
## so telegraph, shields and warheads are the real rules. A refused fire retries each beat.
## Mode -1 (off) does nothing. Pure RefCounted; time is always a parameter.

const FIRST_BAR := 4
const EPS_BEAT := 1e-6

var sim: MatchSim
var chart: ChartData
var cfg: VersusConfig
var drone_seat: int
var target_seat: int
## -1 off, -2 all disruptors in turn, else a disruptor id.
var mode: int
## Every attempt: {t, reward, result}.
var fire_log: Array[Dictionary] = []

## Scheduled slot time and the time of the next attempt at it (later on refusal).
var _slot_t: float = INF
var _attempt_t: float = INF
var _waiting := false
var _turn: int = 0


func _init(p_sim: MatchSim, p_chart: ChartData, p_cfg: VersusConfig, p_drone_seat: int,
		p_target_seat: int, p_mode: int) -> void:
	sim = p_sim
	chart = p_chart
	cfg = p_cfg
	drone_seat = p_drone_seat
	target_seat = p_target_seat
	mode = p_mode
	if mode == -1 or (mode != -2 and not Reward.is_disruptor(mode)):
		mode = -1
		return
	_slot_t = MatchSim.time_after_bars(0.0, FIRST_BAR, chart)
	_attempt_t = _slot_t
	sim.channel.received.connect(_on_event)


## The disruptor the next slot fires (-1 when off).
func current_reward() -> int:
	if mode == -1:
		return -1
	if mode == -2:
		var all: Array[int] = []
		for id in Reward.ALL:
			if Reward.is_disruptor(id):
				all.append(id)
		return all[_turn % all.size()]
	return mode


func next_time() -> float:
	if mode == -1 or _waiting:
		return INF
	return _attempt_t


func step() -> void:
	var t := next_time()
	if not is_finite(t):
		return
	var reward := current_reward()
	var r := sim.inject_fire(drone_seat, target_seat, reward, t)
	fire_log.append({"t": t, "reward": reward, "result": r})
	if r == MatchSim.FIRE_OK:
		_waiting = true
	else:
		_attempt_t = _next_beat_t(t)


## Per-frame driver: every attempt due by t.
func update(t: float) -> void:
	var guard := 0
	while next_time() <= t and guard < 10000:
		guard += 1
		step()


## Whole bars (rounded up) until the next scheduled fire, for "NEXT IN {n} BARS"; 0 when due
## or when off.
func bars_until_next(t: float) -> int:
	if mode == -1 or not is_finite(_slot_t):
		return 0
	var tm: Array = chart.tempo_map
	var beats := BeatClock.beat_at(_slot_t, tm) - BeatClock.beat_at(t, tm)
	if beats <= EPS_BEAT:
		return 0
	return int(ceil(beats / MatchSim.bar_beats_at(t, chart) - EPS_BEAT))


func _next_beat_t(t: float) -> float:
	var tm: Array = chart.tempo_map
	return BeatClock.time_at_beat(floorf(BeatClock.beat_at(t, tm) + EPS_BEAT) + 1.0, tm)


## The slot is done (launched, or cancelled in a collision): schedule the next one.
func _advance_slot(t: float) -> void:
	_waiting = false
	_turn += 1
	var interval := maxi(1, cfg.training_interval_bars)
	_slot_t = MatchSim.time_after_bars(_slot_t, interval, chart)
	var guard := 0
	while _slot_t <= t + 1e-9 and guard < 1000:
		guard += 1
		_slot_t = MatchSim.time_after_bars(_slot_t, interval, chart)
	_attempt_t = _slot_t


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		GameEvent.TORPEDO_LAUNCH:
			if _waiting and int(e.get("from", -1)) == drone_seat and not e.get("reflected", false):
				_advance_slot(float(e["t"]))
		GameEvent.COLLISION:
			if _waiting and (int(e.get("a", -1)) == drone_seat or int(e.get("b", -1)) == drone_seat):
				_advance_slot(float(e["t"]))
		GameEvent.FIRE_REFUSED:
			if _waiting and int(e.get("seat", -1)) == drone_seat:
				_waiting = false
				_attempt_t = _next_beat_t(float(e["t"]))
