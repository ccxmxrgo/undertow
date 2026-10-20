class_name HostInputQueue
extends Referee
## The online host's referee front (D-04, D-09, D-13, D-16). It is the only object that calls
## MatchSim online; MatchSim rules are unchanged.
##
## Every seat's inputs (the host's own included) are queued and released to MatchSim in
## (t, seat, seq) order, and only once t <= host_song_time - D (the horizon). MatchSim's time
## walk never runs backwards: an input that arrives after the horizon passed its t is applied
## at the last released time and counted in late_inputs, never dropped (RESEARCH Pattern 1).
##
## update(t) is deliberately a no-op: SubRig and the controller call update with the live song
## time, which would bypass the horizon. Only pump(host_song_time) advances MatchSim.
##
## Seats always come from the caller (the session binds them from the sender's peer id), never
## from an item (T-04-13). Items stamped beyond FUTURE_INPUT_S ahead are dropped on push
## (T-04-14). STATUS values get cheap sanity clamps (T-04-15).
##
## Events this queue emits itself (DUEL_LIVE, PLAYER_LEFT) go through the same channel as
## MatchSim's and are appended to extra_log.

## Internal kind for host-local inject_fire (never on the wire).
const _K_INJECT := -1
## WR-01 (F-1): two 60 Hz client frames (the client applies events in _client_pump, after
## versus.update in the same frame, so the real delay is D + L + 2F) plus a little jitter.
const MARGIN_EXTRA_S := 0.050
## One-way latency covered by the cap; past this the lobby already warns HIGH LATENCY.
const L_CAP_S := 0.25
## D_MAX + L_CAP + extra = 0.5 s. payload_span keeps the full bar length when the window start
## moves later, so a larger margin never shortens a payload.
const MARGIN_CAP_S := NetProtocol.D_MAX_S + L_CAP_S + MARGIN_EXTRA_S

var sim: MatchSim
var channel: EventChannel
## Input delay D in seconds.
var d_s: float
## Last song time released to MatchSim (the time walk position).
var released_t: float = NetProtocol.TIME_MIN_S
var late_inputs := 0
var rejected_future := 0
## DUEL_LIVE / PLAYER_LEFT events emitted by this queue, in emission order.
var extra_log: Array[Dictionary] = []

## Queued items: {t, seat, seq, n (arrival order), kind, args}.
var _q: Array[Dictionary] = []
var _dirty := false
var _arrival := 0
## Last host song time given to pump (future bound, local NaN stamps).
var _host_now := 0.0
## seat -> next local seq.
var _local_seq := {}
var _dropped := {}
## seat -> net margin seconds (uncapped value as given).
var _margin := {}
## seat -> last raw approach_s reported.
var _raw_approach := {}
## DUEL_LIVE state.
var _live := {}
var _live_solo := -1
var _live_beat := -1


func _init(p_sim: MatchSim, p_channel: EventChannel, p_d_s: float) -> void:
	sim = p_sim
	channel = p_channel
	d_s = maxf(p_d_s, 0.0)
	players = sim.players


## min(D + L_p90 + 50 ms, 0.5 s) where L_p90 is the one-way p90 latency (rtt_p90 / 2) (D-09,
## WR-01).
static func margin_for(p_d_s: float, rtt_p90_s: float) -> float:
	return minf(p_d_s + rtt_p90_s * 0.5 + MARGIN_EXTRA_S, MARGIN_CAP_S)


# --- Network inputs ------------------------------------------------------------------------

## Queue a NetCodec-validated item [kind, t, seq, ...args] for `seat` (seat from the session).
func push_item(seat: int, item: Array) -> void:
	if not _seat_ok(seat) or item.size() < NetProtocol.ITEM_HEAD:
		return
	var kind: Variant = item[0]
	if not (kind is int) or not NetProtocol.IN_ARITY.has(kind):
		return
	if item.size() != NetProtocol.ITEM_HEAD + int(NetProtocol.IN_ARITY[kind]):
		return
	var tv: Variant = item[1]
	if not (tv is float or tv is int):
		return
	var t := float(tv)
	if not is_finite(t) or t > _host_now + NetProtocol.FUTURE_INPUT_S:
		rejected_future += 1
		return
	_enqueue(seat, int(kind), t, int(item[2]), item.slice(NetProtocol.ITEM_HEAD))


# --- Host-local inputs (Referee) -----------------------------------------------------------

func on_judged(seat: int, note_index: int, judgment: int, t: float) -> void:
	_local(seat, NetProtocol.IN_JUDGED, t, [note_index, judgment])


func on_extra_judged(seat: int, judgment: int, t: float) -> void:
	_local(seat, NetProtocol.IN_EXTRA, t, [judgment])


func on_stray(seat: int, t: float) -> void:
	_local(seat, NetProtocol.IN_STRAY, t, [])


func on_ghost_hit(seat: int, t: float) -> void:
	_local(seat, NetProtocol.IN_GHOST, t, [])


func report_status(seat: int, hull: float, depth: float, accuracy: float, max_streak: int,
		t: float = NAN) -> void:
	_local(seat, NetProtocol.IN_STATUS, t, [hull, depth, accuracy, max_streak])


func request_fire(seat: int, t: float) -> int:
	_local(seat, NetProtocol.IN_FIRE, t, [])
	return FIRE_REMOTE


func inject_fire(seat: int, to: int, reward: int, t: float) -> int:
	_local(seat, _K_INJECT, t, [to, reward])
	return FIRE_REMOTE


func cycle_target(seat: int, t: float = NAN) -> int:
	_local(seat, NetProtocol.IN_CYCLE, t, [])
	return -1


func set_target_mode(seat: int, mode: int, locked: int = -1, t: float = NAN) -> void:
	_local(seat, NetProtocol.IN_TARGET_MODE, t, [mode, locked])


func on_failed(seat: int, t: float) -> void:
	_local(seat, NetProtocol.IN_FAILED, t, [])


## Deliberately a no-op: only pump() advances MatchSim (see the header).
func update(_t: float) -> void:
	pass


## Immediate: stores the raw value and applies raw + capped margin (D-09).
func set_approach(seat: int, approach_s: float) -> void:
	if not is_finite(approach_s):
		return
	_raw_approach[seat] = maxf(approach_s, 0.0)
	_apply_approach(seat)


## The network margin for `seat` (use margin_for). Re-applies to the last reported approach_s.
func set_net_margin(seat: int, margin_s: float) -> void:
	if not is_finite(margin_s):
		return
	_margin[seat] = maxf(margin_s, 0.0)
	if not _raw_approach.has(seat):
		for p in sim.players:
			if p.seat == seat:
				_raw_approach[seat] = p.approach_s
	_apply_approach(seat)


func duel_live(seat: int) -> float:
	return float(_live.get(seat, -1.0))


func duel_active() -> int:
	return sim.duel_active()


# --- Pump ----------------------------------------------------------------------------------

## Release every item with t <= host_song_time - D in (t, seat, seq) order, then advance
## MatchSim to the horizon and emit DUEL_LIVE when due.
func pump(host_song_time: float) -> void:
	if not is_finite(host_song_time):
		return
	_host_now = host_song_time
	var horizon := host_song_time - d_s
	if _dirty:
		_q.sort_custom(_cmp)
		_dirty = false
	var k := 0
	while k < _q.size() and float(_q[k]["t"]) <= horizon:
		var it: Dictionary = _q[k]
		k += 1
		var t: float = it["t"]
		if t < released_t:
			late_inputs += 1
			t = released_t
		released_t = t
		_apply(it, t)
	if k > 0:
		_q = _q.slice(k)
	if horizon > released_t:
		sim.update(horizon)
		released_t = horizon
	_duel_live_tick()


## A seat's link dropped (D-16): its queued inputs are dropped, MatchSim implodes it at the
## current released time, then PLAYER_LEFT follows. A second drop is a no-op.
func drop_seat(seat: int, reason: String) -> void:
	if not _seat_ok(seat):
		return
	_dropped[seat] = true
	var keep: Array[Dictionary] = []
	for it in _q:
		if int(it["seat"]) != seat:
			keep.append(it)
	_q = keep
	sim.on_failed(seat, released_t)
	_emit_extra(GameEvent.make(GameEvent.PLAYER_LEFT, released_t,
		{"seat": seat, "reason": reason}))


func debug_stats() -> Dictionary:
	return {"late_inputs": late_inputs, "rejected_future": rejected_future,
		"pending": _q.size(), "released_t": released_t}


# --- Internals -----------------------------------------------------------------------------

func _seat_ok(seat: int) -> bool:
	if _dropped.has(seat):
		return false
	for p in sim.players:
		if p.seat == seat:
			return true
	return false


func _local(seat: int, kind: int, t: float, args: Array) -> void:
	if not _seat_ok(seat):
		return
	if not is_finite(t):
		t = _host_now
	var seq: int = _local_seq.get(seat, 0)
	_local_seq[seat] = seq + 1
	_enqueue(seat, kind, t, seq, args)


func _enqueue(seat: int, kind: int, t: float, seq: int, args: Array) -> void:
	_q.append({"t": t, "seat": seat, "seq": seq, "n": _arrival, "kind": kind, "args": args})
	_arrival += 1
	_dirty = true


## Explicit total order: (t, seat, seq, arrival).
func _cmp(a: Dictionary, b: Dictionary) -> bool:
	if a["t"] != b["t"]:
		return a["t"] < b["t"]
	if a["seat"] != b["seat"]:
		return a["seat"] < b["seat"]
	if a["seq"] != b["seq"]:
		return a["seq"] < b["seq"]
	return a["n"] < b["n"]


func _apply(it: Dictionary, t: float) -> void:
	var seat: int = it["seat"]
	var a: Array = it["args"]
	match int(it["kind"]):
		NetProtocol.IN_JUDGED:
			sim.on_judged(seat, int(a[0]), int(a[1]), t)
		NetProtocol.IN_EXTRA:
			sim.on_extra_judged(seat, int(a[0]), t)
		NetProtocol.IN_STRAY:
			sim.on_stray(seat, t)
		NetProtocol.IN_GHOST:
			sim.on_ghost_hit(seat, t)
		NetProtocol.IN_STATUS:
			var hull_max := sim.jcfg.hull_start if sim.jcfg != null else 100.0
			sim.report_status(seat, clampf(_num(a[0]), 0.0, hull_max), maxf(_num(a[1]), 0.0),
				clampf(_num(a[2]), -1.0, 1.0), maxi(int(a[3]), 0), t)
		NetProtocol.IN_FIRE:
			sim.request_fire(seat, t)  # the client learns the result from events
		NetProtocol.IN_CYCLE:
			sim.cycle_target(seat, t)
		NetProtocol.IN_TARGET_MODE:
			sim.set_target_mode(seat, int(a[0]), int(a[1]), t)
		NetProtocol.IN_FAILED:
			sim.on_failed(seat, t)
		NetProtocol.IN_APPROACH:
			sim.update(t)
			set_approach(seat, _num(a[0]))
		_K_INJECT:
			sim.inject_fire(seat, int(a[0]), int(a[1]), t)


static func _num(v: Variant) -> float:
	var f := float(v) if (v is float or v is int) else 0.0
	return f if is_finite(f) else 0.0


func _apply_approach(seat: int) -> void:
	if not _raw_approach.has(seat):
		return
	var m := minf(float(_margin.get(seat, 0.0)), MARGIN_CAP_S)
	sim.set_approach(seat, float(_raw_approach[seat]) + m)


## D-13: at most one DUEL_LIVE per whole beat of the horizon while a Solo Duel runs.
func _duel_live_tick() -> void:
	var solo := sim.duel_active()
	if solo == -1:
		_live = {}
		_live_solo = -1
		return
	if solo != _live_solo:
		_live = {}
		_live_solo = solo
	var b := int(floor(BeatClock.beat_at(released_t, sim.chart.tempo_map) + MatchSim.EPS_BEAT))
	if b <= _live_beat:
		return
	var pct := {}
	for p in sim.players:
		var v := sim.duel_live(p.seat)
		if v >= 0.0:
			pct[p.seat] = v
	if pct.is_empty():
		return
	_live_beat = b
	_live = pct.duplicate()
	_emit_extra(GameEvent.make(GameEvent.DUEL_LIVE, released_t, {"solo": solo, "pct": pct}))


func _emit_extra(e: Dictionary) -> void:
	extra_log.append(e)
	channel.send(e)
