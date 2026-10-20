class_name RemoteReferee
extends Referee
## The client's referee proxy (D-03, D-13, D-23). Clients run no rules: SubRig's calls for this
## client's own seat are serialized as INPUTS items [kind, t, seq, ...args] (NetProtocol.IN_*)
## and sent to the host by flush(), at most one batch of <= MAX_BATCH items per chunk. Calls for
## any other seat are ignored (counted, T-04-13).
##
## Pitfall 5: request_fire / inject_fire return FIRE_REMOTE and cycle_target returns -1; the
## real outcome arrives later as events (FIRE_QUEUED / FIRE_REFUSED / TARGET). duel_live and
## duel_active are answered from the host's latest DUEL_LIVE / DUEL_START / DUEL_RESULT events.
##
## Times: the last known song time `_now` (set_now / update) starts at 0.0. Any non-finite t
## (the NaN defaults of cycle_target / set_target_mode, or INF) is stamped at flush time with
## maxf(_now, TIME_MIN_S), so no item ever leaves with a non-finite time.

var seat: int
var ignored_foreign := 0

var _send_fn: Callable
var _items: Array = []
var _seq := 0
var _now := 0.0
var _live := {}
var _solo := -1
var _channel: EventChannel


func _init(p_seat: int, p_players: Array[PlayerState], p_send_fn: Callable) -> void:
	seat = p_seat
	players = p_players
	_send_fn = p_send_fn


## Subscribe to the client's event channel (method callable, CR-02).
func bind(channel: EventChannel) -> void:
	if _channel != null and _channel.received.is_connected(_on_event):
		_channel.received.disconnect(_on_event)
	_channel = channel
	if channel != null:
		channel.received.connect(_on_event)


## The client's current song time (stamps non-finite input times at flush).
func set_now(t: float) -> void:
	if is_finite(t):
		_now = t


## Send every queued item, in chunks of at most MAX_BATCH, then clear. Nothing when empty.
func flush() -> void:
	if _items.is_empty():
		return
	var stamp := maxf(_now, NetProtocol.TIME_MIN_S)
	for it in _items:
		var t: float = it[1]
		it[1] = maxf(t, NetProtocol.TIME_MIN_S) if is_finite(t) else stamp
	var all := _items
	_items = []
	var k := 0
	while k < all.size():
		var chunk := all.slice(k, mini(k + NetProtocol.MAX_BATCH, all.size()))
		k += chunk.size()
		_send_fn.call({"type": NetProtocol.INPUTS, "items": chunk})


## Items waiting for the next flush (tests, debug overlay).
func pending_count() -> int:
	return _items.size()


# --- Referee ---------------------------------------------------------------------------------

func on_judged(p_seat: int, note_index: int, judgment: int, t: float) -> void:
	_push(p_seat, NetProtocol.IN_JUDGED, t, [note_index, judgment])


func on_extra_judged(p_seat: int, judgment: int, t: float) -> void:
	_push(p_seat, NetProtocol.IN_EXTRA, t, [judgment])


func on_stray(p_seat: int, t: float) -> void:
	_push(p_seat, NetProtocol.IN_STRAY, t, [])


func on_ghost_hit(p_seat: int, t: float) -> void:
	_push(p_seat, NetProtocol.IN_GHOST, t, [])


func report_status(p_seat: int, hull: float, depth: float, accuracy: float, max_streak: int,
		t: float = NAN) -> void:
	_push(p_seat, NetProtocol.IN_STATUS, t,
		[_fin(hull), _fin(depth), _fin(accuracy), maxi(max_streak, 0)])


func request_fire(p_seat: int, t: float) -> int:
	_push(p_seat, NetProtocol.IN_FIRE, t, [])
	return FIRE_REMOTE


## Clients never inject launches (training drones are offline only).
func inject_fire(_seat: int, _to: int, _reward: int, _t: float) -> int:
	return FIRE_REMOTE


func cycle_target(p_seat: int, t: float = NAN) -> int:
	_push(p_seat, NetProtocol.IN_CYCLE, t, [])
	return -1


func set_target_mode(p_seat: int, mode: int, locked: int = -1, t: float = NAN) -> void:
	_push(p_seat, NetProtocol.IN_TARGET_MODE, t, [mode, clampi(locked, -1,
		NetProtocol.MAX_SEATS - 1)])


func on_failed(p_seat: int, t: float) -> void:
	_push(p_seat, NetProtocol.IN_FAILED, t, [])


func duel_live(p_seat: int) -> float:
	return float(_live.get(p_seat, -1.0))


func duel_active() -> int:
	return _solo


## Only records the song time; the host advances the rules.
func update(t: float) -> void:
	set_now(t)


## D-09: the host adds the network margin to this raw value.
func set_approach(p_seat: int, approach_s: float) -> void:
	if not is_finite(approach_s):
		return
	_push(p_seat, NetProtocol.IN_APPROACH, NAN, [clampf(approach_s, 0.0, 10.0)])


# --- Internals -------------------------------------------------------------------------------

func _push(p_seat: int, kind: int, t: float, args: Array) -> void:
	if p_seat != seat:
		ignored_foreign += 1
		return
	var it: Array = [kind, t, _seq]
	it.append_array(args)
	_seq += 1
	_items.append(it)


static func _fin(v: float) -> float:
	return v if is_finite(v) else 0.0


func _on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		GameEvent.DUEL_LIVE:
			var pct: Variant = e.get("pct")
			_live = {}
			if pct is Dictionary:
				for k in pct:
					var v: Variant = pct[k]
					if (k is int) and (v is float or v is int):
						_live[k] = float(v)
			var solo: Variant = e.get("solo")
			if solo is int:
				_solo = solo
		GameEvent.DUEL_START:
			_live = {}
			var solo: Variant = e.get("solo")
			if solo is int:
				_solo = solo
		GameEvent.DUEL_RESULT, GameEvent.MATCH_END:
			_live = {}
			_solo = -1
