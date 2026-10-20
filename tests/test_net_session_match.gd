extends GdUnitTestSuite
## 04-10: the NetSession match half over a MemTransport hub (NET-03, NET-04, NET-05, NET-06;
## D-05, D-07, D-16, D-17, D-19). Every session has its own virtual tick origin through ticks_fn
## and is driven by step(now_s); nothing here touches real sockets or real time.

const SESSION := "res://src/autoload/net_session.gd"
const FP := "u3.aaaaaaaaaaaaaaaaaaaaaaaa.expert"
const SONG_LEN := 40.0


class FakeSettings:
	extends RefCounted
	var player_name := "DIVER"


class FakeEntry:
	extends RefCounted
	var fps := {}

	func difficulty(d: String) -> Dictionary:
		if not fps.has(d):
			return {}
		return {"name": d, "fingerprint": fps[d]}


class FakeLib:
	extends RefCounted
	var entries: Array = []
	var charts := {}

	func add(fp: String, diff: String, chart: ChartData) -> void:
		var e := FakeEntry.new()
		e.fps[diff] = fp
		entries.append(e)
		charts[fp] = chart

	func build_chart(entry: Variant, diff: String) -> ChartData:
		return charts.get(entry.difficulty(diff).get("fingerprint", ""))


var hub: MemTransport.Hub
var now := 0.0
var dt := 0.005
var link_lat := 0.03
var link_jit := 0.01
var sessions: Array = []
var sigs := {}  # session -> Array of [name, args]
var start_v := {}  # session -> virtual instant of song_time 0
var errors := {}  # session -> Array of connect_error codes
var lib: FakeLib
var chart: ChartData


func before_test() -> void:
	hub = MemTransport.Hub.new(7)
	now = 0.0
	dt = 0.005
	link_lat = 0.03
	link_jit = 0.01
	sessions.clear()
	sigs.clear()
	start_v.clear()
	errors.clear()
	chart = TestCharts.click_chart(120.0, 64, 1000)
	lib = FakeLib.new()
	lib.add(FP, "expert", chart)


func after_test() -> void:
	for s in sessions:
		if is_instance_valid(s):
			s.free()
	sessions.clear()


# --- Harness -------------------------------------------------------------------------------------

func _song() -> Dictionary:
	return {"fp": FP, "sig": VersusSig.of(chart), "diff": "expert", "title": "Click",
		"artist": "Metronome"}


func _make(pname: String, origin_us: int) -> Node:
	var s: Node = load(SESSION).new()
	s.auto_process = false
	var st := FakeSettings.new()
	st.player_name = pname
	s.settings = st
	s.library = lib
	s.ticks_fn = func() -> int: return origin_us + int(round(now * 1_000_000.0))
	s.transport_factory = func(role: String) -> NetTransport:
		var t: MemTransport = hub.make_host() if role == "host" else hub.make_client()
		if role != "host":
			hub.set_link(t.unique_id(), link_lat, link_jit)
		return t
	sigs[s] = []
	errors[s] = []
	s.connect_error.connect(func(code: String, _i: Dictionary) -> void: errors[s].append(code))
	for n in ["match_loading", "start_scheduled", "returned_to_lobby"]:
		s.connect(n, func() -> void: sigs[s].append([n, []]))
	s.match_aborted_to_lobby.connect(func(code: String, who: String) -> void:
		sigs[s].append(["match_aborted_to_lobby", [code, who]]))
	s.host_left.connect(func(kind: String) -> void: sigs[s].append(["host_left", [kind]]))
	s.results_due.connect(func(t: float) -> void: sigs[s].append(["results_due", [t]]))
	s.results_received.connect(func(d: Dictionary) -> void:
		sigs[s].append(["results_received", [d]]))
	s.link_weak_changed.connect(func(w: bool) -> void: sigs[s].append(["link_weak", [w]]))
	add_child(s)
	sessions.append(s)
	return s


func _step_all() -> void:
	for s in sessions:
		if is_instance_valid(s):
			s.step(now)


## Advances virtual time; in a match, pumps every bound session with its own song time.
func _run(secs: float, pump := false) -> void:
	var end := now + secs
	while now < end - 1e-9:
		now += dt
		_step_all()
		if pump:
			_pump_all()


func _run_until(cond: Callable, cap: float = 10.0, pump := false) -> bool:
	var end := now + cap
	while now < end:
		now += dt
		_step_all()
		if pump:
			_pump_all()
		if cond.call():
			return true
	return bool(cond.call())


func _pump_all() -> void:
	for s in sessions:
		if is_instance_valid(s) and not s.is_offline():
			s.pump_match(_song_t(s))


func _song_t(s: Node) -> float:
	return now - float(start_v[s]) if start_v.has(s) else NAN


func _fired(s: Node, name: String) -> Array:
	var out: Array = []
	for e in sigs[s]:
		if e[0] == name:
			out.append(e[1])
	return out


func _host() -> Node:
	var h := _make("CAPTAIN", 0)
	assert_int(h.host(NetProtocol.DEFAULT_PORT)).is_equal(OK)
	return h


func _join_wait(pname: String, origin_us: int) -> Node:
	var c := _make(pname, origin_us)
	c.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	assert_bool(_run_until(func() -> bool: return c.is_in_lobby())).is_true()
	return c


## Host + clients (one per origin) in the lobby with the song OK and every client Ready.
func _lobby(origins: Array) -> Array:
	var h := _host()
	var out: Array = [h]
	var names := ["ONE", "TWO", "THREE"]
	for i in origins.size():
		out.append(_join_wait(names[i], origins[i]))
	assert_bool(h.host_set_song(_song())).is_true()
	assert_bool(_run_until(func() -> bool:
		for c in out.slice(1):
			if c.my_song_status() != "ok":
				return false
		return true)).is_true()
	for c in out.slice(1):
		c.set_ready(true)
	assert_bool(_run_until(func() -> bool: return h.start_gate().ok)).is_true()
	return out


## Every peer reports loaded on match_loading and records its start instant on start_scheduled.
func _auto_load(all: Array) -> void:
	for s in all:
		s.match_loading.connect(func() -> void: s.report_loaded())
		s.start_scheduled.connect(func() -> void:
			var lead: float = s.lead_in_for_start()
			if lead >= 0.0:
				start_v[s] = now + lead)


## Lobby -> LOAD -> START for all peers; returns once every peer has its start instant.
func _start(all: Array, opts := {}) -> void:
	_auto_load(all)
	assert_str(all[0].start_match(opts)).is_equal("")
	assert_bool(_run_until(func() -> bool: return start_v.size() == all.size(), 5.0)).is_true()


# --- Match objects (04-05 classes, no SubRigs) ---------------------------------------------------

func _players(n: int) -> Array[PlayerState]:
	var ps: Array[PlayerState] = []
	for s in range(n):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	return ps


## Binds the host's queue + channel; returns {queue, channel, sim}.
func _bind_host(h: Node) -> Dictionary:
	var spec: Dictionary = h.pending_match()
	var hc := NetHostChannel.new()
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(),
		_players(spec.names.size()), hc, int(spec.seed))
	var q := HostInputQueue.new(sim, hc, float(spec.d_s))
	h.bind_host_match(q, hc, chart.notes.size(), SONG_LEN)
	return {"queue": q, "channel": hc, "sim": sim}


## Binds a client's RemoteReferee + NetClientChannel; returns {remote, channel}.
func _bind_client(c: Node) -> Dictionary:
	var spec: Dictionary = c.pending_match()
	var seat: int = spec.local_seat
	var ctx := {"from_host": true, "note_count": chart.notes.size(), "song_len": SONG_LEN,
		"max_seat": 3}
	var cc := NetClientChannel.new(seat, func() -> float: return _song_t(c), ctx)
	var rr := RemoteReferee.new(seat, _players(spec.names.size()), Callable(c, "send_to_host"))
	rr.bind(cc)
	c.bind_client_match(rr, cc, chart.notes.size(), SONG_LEN)
	return {"remote": rr, "channel": cc}


## Full lobby -> started + bound match. Returns {all, host_b, client_b: Array}.
func _match(origins: Array) -> Dictionary:
	var all := _lobby(origins)
	var out := {"all": all, "client_b": []}
	all[0].match_loading.connect(func() -> void: out["host_b"] = _bind_host(all[0]))
	for c in all.slice(1):
		c.match_loading.connect(func() -> void: out.client_b.append(_bind_client(c)))
	_start(all)
	return out


# --- Task 1: synced start -----------------------------------------------------------------------

func test_start_match_refuses_without_gate() -> void:
	var h := _host()
	assert_str(h.start_match()).is_equal("gate")
	var c := _join_wait("ONE", 1_000_000)
	assert_str(h.start_match()).is_equal("gate")
	assert_str(c.start_match()).is_not_equal("")
	assert_bool(h.is_in_lobby()).is_true()
	assert_dict(h.pending_match()).is_empty()


func test_start_match_sends_load_with_d_and_pending_match() -> void:
	var all := _lobby([1_000_000, 2_000_000])
	var h: Node = all[0]
	var p90: Dictionary = h.peer_rtt_p90_us()
	var worst := 0
	for k in p90:
		worst = maxi(worst, int(p90[k]))
	var d_s := clampf(worst / 2_000_000.0 + 0.053, NetProtocol.D_MIN_S, NetProtocol.D_MAX_S)
	assert_str(h.start_match({"seed": 99, "max_song_s": 12.5, "autoplay": true})).is_equal("")
	assert_int(h.state).is_equal(h.State.LOADING)
	assert_array(_fired(h, "match_loading")).has_size(1)
	var spec: Dictionary = h.pending_match()
	for key in ["role", "local_seat", "names", "fp", "sig", "diff", "seed", "flight", "d_s",
			"max_song_s", "autoplay", "margins"]:
		assert_bool(spec.has(key)).override_failure_message(key).is_true()
	assert_str(spec.role).is_equal("host")
	assert_int(spec.local_seat).is_equal(0)
	assert_int(spec.seed).is_equal(99)
	assert_float(spec.d_s).is_equal_approx(round(d_s * 1000.0) / 1000.0, 0.0005)
	assert_float(spec.max_song_s).is_equal(12.5)
	assert_bool(spec.autoplay).is_true()
	assert_str(spec.fp).is_equal(FP)
	assert_array(Array(spec.names)).is_equal(["CAPTAIN", "ONE", "TWO"])
	assert_float(spec.margins[0]).is_equal(0.0)
	assert_float(spec.margins[1]).is_greater(0.0)
	assert_bool(_run_until(func() -> bool:
		return all[1].state == h.State.LOADING and all[2].state == h.State.LOADING)).is_true()
	for i in [1, 2]:
		var cs: Dictionary = all[i].pending_match()
		assert_str(cs.role).is_equal("client")
		assert_int(cs.local_seat).is_equal(i)
		assert_int(cs.seed).is_equal(99)
		assert_float(cs.d_s).is_equal(spec.d_s)
		assert_dict(cs.margins).is_empty()
		assert_array(Array(cs.names)).is_equal(["CAPTAIN", "ONE", "TWO"])
		assert_array(_fired(all[i], "match_loading")).has_size(1)
	# The lobby is locked: host-only lobby calls are ignored.
	assert_bool(h.host_set_song({})).is_false()


func test_start_instants_agree_across_tick_origins() -> void:
	dt = 0.001
	var all := _lobby([2_000_000, 5_300_000])
	_run(1.0)
	_start(all)
	var v0: float = start_v[all[0]]
	for s in all:
		assert_int(s.state).is_equal(s.State.PLAYING)
		assert_float(absf(float(start_v[s]) - v0)).is_less_equal(0.002)
	# The start is ~3 s after LOAD complete, never in the past.
	assert_float(v0 - now).is_greater(2.5)


func test_start_instants_median_over_seeds() -> void:
	# The D-06 estimator under uniform jitter: the median error stays within 2 ms.
	var errs: Array = []
	for seed_i in 6:
		after_test()
		before_test()
		hub = MemTransport.Hub.new(100 + seed_i)
		dt = 0.001
		var all := _lobby([2_000_000, 5_300_000])
		_run(1.0)
		_start(all)
		var v0: float = start_v[all[0]]
		for s in all.slice(1):
			errs.append(absf(float(start_v[s]) - v0))
	errs.sort()
	assert_float(errs[errs.size() / 2]).is_less_equal(0.002)
	assert_float(errs.back()).is_less_equal(0.010)


func test_load_timeout_aborts_to_lobby_with_name() -> void:
	var all := _lobby([1_000_000, 2_000_000])
	var h: Node = all[0]
	h.match_loading.connect(func() -> void: h.report_loaded())
	all[1].match_loading.connect(func() -> void: all[1].report_loaded())
	assert_str(h.start_match()).is_equal("")
	_run(NetProtocol.LOAD_TIMEOUT_S - 0.5)
	assert_int(h.state).is_equal(h.State.LOADING)
	assert_bool(_run_until(func() -> bool: return all[2].is_in_lobby() and all[1].is_in_lobby(),
		3.0)).is_true()
	for s in all:
		assert_array(_fired(s, "match_aborted_to_lobby")).is_equal([["load_timeout", "TWO"]])
		assert_dict(s.pending_match()).is_empty()
	assert_bool(h.is_in_lobby()).is_true()
	assert_bool(h.lobby_state().row(1).ready).is_false()
	assert_str(h.start_gate().code).is_equal("not_ready")


func test_late_lead_sends_start_late_and_host_aborts() -> void:
	var all := _lobby([1_000_000])
	var h: Node = all[0]
	var c: Node = all[1]
	for s in all:
		s.match_loading.connect(func() -> void: s.report_loaded())
	assert_str(h.start_match()).is_equal("")
	assert_bool(_run_until(func() -> bool: return not _fired(c, "start_scheduled").is_empty()))\
		.is_true()
	_run(2.6)
	assert_float(c.lead_in_for_start()).is_equal(-1.0)
	assert_bool(_run_until(func() -> bool: return c.is_in_lobby() and h.is_in_lobby()))\
		.is_true()
	for s in all:
		assert_array(_fired(s, "match_aborted_to_lobby")).is_equal([["start_late", "ONE"]])


func test_unsynced_client_at_start_replies_start_late() -> void:
	var all := _lobby([1_000_000])
	var h: Node = all[0]
	var c: Node = all[1]
	c.match_loading.connect(func() -> void: c.report_loaded())
	h.match_loading.connect(func() -> void: pass)
	assert_str(h.start_match()).is_equal("")
	assert_bool(_run_until(func() -> bool: return h.state == h.State.LOADING and \
		c.state == c.State.LOADING)).is_true()
	_run(0.2)
	c.clock.reset()
	h.report_loaded()
	assert_bool(_run_until(func() -> bool: return not _fired(c, "start_scheduled").is_empty()))\
		.is_true()
	assert_bool(c.clock.sample_count() < ClockSync.MIN_SAMPLES).is_true()
	assert_float(c.lead_in_for_start()).is_equal(-1.0)
	assert_bool(_run_until(func() -> bool: return h.is_in_lobby() and c.is_in_lobby()))\
		.is_true()
	assert_array(_fired(h, "match_aborted_to_lobby")).is_equal([["start_late", "ONE"]])


func test_load_fail_aborts_to_lobby() -> void:
	var all := _lobby([1_000_000])
	var c: Node = all[1]
	c.match_loading.connect(func() -> void: c.report_load_failed())
	assert_str(all[0].start_match()).is_equal("")
	assert_bool(_run_until(func() -> bool: return all[0].is_in_lobby() and c.is_in_lobby()))\
		.is_true()
	for s in all:
		assert_array(_fired(s, "match_aborted_to_lobby")).is_equal([["load_fail", "ONE"]])


func test_join_during_loading_and_playing_is_refused_in_match() -> void:
	var all := _lobby([1_000_000])
	_auto_load([all[1]])
	assert_str(all[0].start_match()).is_equal("")
	var late := _make("LATE", 9_000_000)
	late.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	assert_bool(_run_until(func() -> bool: return late.is_offline(), 3.0)).is_true()
	assert_array(errors[late]).is_equal(["in_match"])
	all[0].report_loaded()
	assert_bool(_run_until(func() -> bool: return all[0].state == all[0].State.PLAYING))\
		.is_true()
	var late2 := _make("LATER", 9_000_000)
	late2.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	assert_bool(_run_until(func() -> bool: return late2.is_offline(), 3.0)).is_true()
	assert_array(errors[late2]).is_equal(["in_match"])
	assert_int(all[0].lobby_rows().size()).is_equal(2)


# --- Task 2: match link ---------------------------------------------------------------------------

func test_inputs_reach_host_queue_under_sender_seat() -> void:
	var m := _match([1_000_000, 2_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	var q: HostInputQueue = m.host_b.queue
	var c2: Node = all[2]
	# Before the song (song_time < 0) the pump still keeps the link alive.
	assert_bool(_run_until(func() -> bool: return _song_t(h) >= 1.0, 5.0, true)).is_true()
	var rr: RemoteReferee = m.client_b[1].remote if m.client_b[1].remote.seat == 2 \
		else m.client_b[0].remote
	assert_int(rr.seat).is_equal(c2.local_seat())
	var t0 := _song_t(h) + 1.0
	for n in range(3):
		rr.on_judged(rr.seat, n, InputJudge.Judgment.PERFECT, t0 + n * 0.1)
	_run(0.1, true)
	assert_int(rr.pending_count()).is_equal(0)
	assert_int(q._q.size()).is_equal(3)
	for it in q._q:
		assert_int(int(it.seat)).is_equal(2)
	assert_int(q.rejected_future).is_equal(0)


func test_input_flood_is_rate_limited_and_struck() -> void:
	var m := _match([1_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	var q: HostInputQueue = m.host_b.queue
	var rr: RemoteReferee = m.client_b[0].remote
	var peer: int = h.lobby_state().peer_of(1)
	assert_bool(_run_until(func() -> bool: return _song_t(h) >= 1.0, 5.0, true)).is_true()
	var t0 := _song_t(h) + 1.0
	for n in range(300):
		rr.on_stray(rr.seat, t0 + n * 0.001)
	_run(0.2, true)
	assert_int(q._q.size()).is_between(NetProtocol.MAX_INPUTS_PER_S,
		NetProtocol.MAX_INPUTS_PER_S + 20)
	assert_int(h.peer_strikes(peer)).is_between(1, 2)
	assert_int(h.lobby_rows().size()).is_equal(2)
	# A second flood reaches 3 strikes: the peer is disconnected and its seat dropped.
	_run(1.0, true)
	t0 = _song_t(h) + 1.0
	for n in range(600):
		rr.on_stray(rr.seat, t0 + n * 0.001)
	assert_bool(_run_until(func() -> bool: return h.lobby_rows().size() == 1, 2.0, true))\
		.is_true()
	var left := false
	for e in m.host_b.channel.broadcast_log:
		if e.type == GameEvent.PLAYER_LEFT and e.seat == 1:
			left = true
	assert_bool(left).is_true()


func test_events_reach_clients_in_order() -> void:
	var m := _match([1_000_000, 2_000_000])
	var hc: NetHostChannel = m.host_b.channel
	for i in 300:
		hc.send(GameEvent.make(GameEvent.PLAYER_LEFT, 1.0 + i * 0.01, {"seat": 3,
			"reason": "left"}))
		if i % 50 == 0:
			_run(0.02, true)
	_run(0.5, true)
	for cb in m.client_b:
		var cc: NetClientChannel = cb.channel
		assert_int(cc.rejected_events).is_equal(0)
		assert_str(var_to_str(cc.received_log)).is_equal(var_to_str(hc.broadcast_log))


func test_heartbeat_measures_skew_only() -> void:
	var m := _match([1_000_000])
	var h: Node = m.all[0]
	var c: Node = m.all[1]
	_run(3.5, true)
	var hs: Dictionary = h.debug_stats()
	var cs: Dictionary = c.debug_stats()
	assert_float(absf(float(cs.skew_ms))).is_less_equal(5.0)
	assert_float(absf(float(hs.skew_ms))).is_less_equal(10.0)
	assert_int(h.heartbeats_received()).is_between(5, 9)


func test_client_disconnect_drops_seat_and_match_continues() -> void:
	var m := _match([1_000_000, 2_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	var hc: NetHostChannel = m.host_b.channel
	_run(4.0, true)
	var gone: Node = all[1]
	var seat: int = gone.local_seat()
	hub.drop_peer(gone.transport.unique_id())
	assert_bool(_run_until(func() -> bool: return h.lobby_rows().size() == 2, 2.0, true))\
		.is_true()
	_run(1.0, true)
	var types: Array = []
	for e in hc.broadcast_log:
		if e.get("seat") == seat:
			types.append(e.type)
	assert_bool(types.has(GameEvent.IMPLODED)).is_true()
	assert_bool(types.has(GameEvent.PLAYER_LEFT)).is_true()
	assert_int(h.state).is_equal(h.State.PLAYING)
	var other: Node = all[2]
	assert_int(other.state).is_equal(other.State.PLAYING)
	var cc: NetClientChannel = m.client_b[1].channel if m.client_b[1].channel.local_seat \
		== other.local_seat() else m.client_b[0].channel
	assert_str(var_to_str(cc.received_log)).is_equal(var_to_str(hc.broadcast_log))
	assert_array(hc.peers()).has_size(1)


func test_host_leave_in_match_sends_match_abort() -> void:
	var m := _match([1_000_000, 2_000_000])
	var all: Array = m.all
	_run(1.0, true)
	all[0].leave()
	assert_bool(all[0].is_offline()).is_true()
	assert_bool(_run_until(func() -> bool: return all[1].is_offline() and all[2].is_offline(),
		1.0)).is_true()
	for c in all.slice(1):
		assert_array(_fired(c, "host_left")).is_equal([["host_left"]])
		assert_str(c.take_return_message()).is_equal("closed")


func test_server_lost_gives_connection_lost() -> void:
	var m := _match([1_000_000])
	var c: Node = m.all[1]
	_run(1.0, true)
	hub.drop_peer(c.transport.unique_id())
	assert_bool(_run_until(func() -> bool: return c.is_offline(), 1.0, true)).is_true()
	assert_array(_fired(c, "host_left")).is_equal([["connection_lost"]])
	assert_str(c.take_return_message()).is_equal("lost")


func test_stalled_host_link_weak_then_host_left_once() -> void:
	var m := _match([1_000_000])
	var c: Node = m.all[1]
	_run(1.0, true)
	assert_bool(c.is_link_weak()).is_false()
	hub.stall(c.transport.unique_id())
	_run(1.5, true)
	assert_float(c.seconds_since_host_packet()).is_greater(1.0)
	assert_bool(c.is_link_weak()).is_true()
	assert_array(_fired(c, "link_weak")).is_equal([[true]])
	assert_bool(c.is_offline()).is_false()
	assert_bool(_run_until(func() -> bool: return c.is_offline(), 3.0, true)).is_true()
	assert_float(c.seconds_since_host_packet()).is_equal(0.0)
	_run(2.0, true)
	assert_array(_fired(c, "host_left")).is_equal([["connection_lost"]])


func _results_data() -> Dictionary:
	return {"rows": [{"seat": 0, "place": 1, "name": "CAPTAIN"},
		{"seat": 1, "place": 2, "name": "ONE"}, {"seat": 2, "place": 3, "name": "TWO"}],
		"medals": {0: ["sharpshooter"]}, "last_standing_seat": 0, "local_seat": 0,
		"title": "Click", "artist": "Metronome", "difficulty": "expert", "seed": 5,
		"online": true, "is_host": true, "host_seat": 0, "host_name": "CAPTAIN"}


func test_done_barrier_then_results_with_own_local_seat() -> void:
	var m := _match([1_000_000, 2_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	_run(2.0, true)
	assert_int(h.still_diving()).is_equal(2)
	h.report_done(10.0)
	all[1].report_done(10.01)
	_run(0.3, true)
	assert_int(h.still_diving()).is_equal(1)
	assert_array(_fired(h, "results_due")).is_empty()
	all[2].report_done(10.02)
	assert_bool(_run_until(func() -> bool: return not _fired(h, "results_due").is_empty(), 1.0,
		true)).is_true()
	assert_array(_fired(h, "results_due")).is_equal([[10.0]])
	assert_int(h.still_diving()).is_equal(0)
	h.host_send_results(_results_data())
	assert_int(h.state).is_equal(h.State.RESULTS)
	assert_bool(_run_until(func() -> bool:
		return not _fired(all[1], "results_received").is_empty() \
			and not _fired(all[2], "results_received").is_empty(), 1.0, true)).is_true()
	for c in all.slice(1):
		var d: Dictionary = _fired(c, "results_received")[0][0]
		assert_int(d.local_seat).is_equal(c.local_seat())
		assert_bool(d.is_host).is_false()
		assert_int(d.rows.size()).is_equal(3)
		assert_int(c.state).is_equal(c.State.RESULTS)
	_run(1.0, true)
	assert_array(_fired(h, "results_due")).has_size(1)


func test_done_barrier_times_out_after_d_plus_3s() -> void:
	var m := _match([1_000_000])
	var h: Node = m.all[0]
	_run(1.0, true)
	h.report_done(10.0)
	var d_s: float = h.pending_match().d_s
	_run(3.0 + d_s - 0.1, true)
	assert_array(_fired(h, "results_due")).is_empty()
	_run(0.2, true)
	assert_array(_fired(h, "results_due")).is_equal([[10.0]])


func test_back_to_lobby_clears_ready_keeps_song() -> void:
	var m := _match([1_000_000, 2_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	h.host_set_flight(1)  # ignored in a match
	for s in all:
		s.report_done(5.0)
	assert_bool(_run_until(func() -> bool: return not _fired(h, "results_due").is_empty(), 1.0,
		true)).is_true()
	h.host_send_results(_results_data())
	_run(0.3, true)
	h.host_back_to_lobby()
	assert_bool(_run_until(func() -> bool: return all[1].is_in_lobby() and all[2].is_in_lobby(),
		1.0)).is_true()
	for s in all:
		assert_bool(s.is_in_lobby()).is_true()
		assert_array(_fired(s, "returned_to_lobby")).has_size(1)
		assert_dict(s.pending_match()).is_empty()
	assert_bool(_run_until(func() -> bool:
		for r in all[1].lobby_rows():
			if not r.host and r.ready:
				return false
		return true, 2.0)).is_true()
	assert_dict(h.lobby_song()).is_equal(_song())
	assert_int(h.flight()).is_equal(2)
	assert_str(h.start_gate().code).is_equal("not_ready")
	# Joining works again in the lobby.
	assert_str(h.auth_refusal_for({"type": NetProtocol.AUTH, "proto": NetProtocol.PROTO,
		"game": NetProtocol.game_version(), "name": "NEW"})).is_equal("")
	# A second match can start.
	for c in all.slice(1):
		c.set_ready(true)
	assert_bool(_run_until(func() -> bool: return h.start_gate().ok)).is_true()


func test_host_leave_in_results_closes_lobby() -> void:
	var m := _match([1_000_000])
	var all: Array = m.all
	for s in all:
		s.report_done(5.0)
	assert_bool(_run_until(func() -> bool: return not _fired(all[0], "results_due").is_empty(),
		1.0, true)).is_true()
	all[0].host_send_results(_results_data())
	_run(0.3, true)
	all[0].leave()
	assert_bool(_run_until(func() -> bool: return all[1].is_offline(), 1.0)).is_true()
	assert_str(all[1].take_return_message()).is_equal("closed")


func test_debug_stats_keys() -> void:
	var keys := ["role", "seat", "peers", "rtt_p50_ms", "rtt_p90_ms", "per_peer", "offset_us",
		"horizon_ms", "late_inputs", "skew_ms", "landed_late_last_ms", "landed_late_max_ms",
		"rejected_packets", "event_seq"]
	var lone: Node = _make("SOLO", 0)
	var d0: Dictionary = lone.debug_stats()
	for k in keys:
		assert_bool(d0.has(k)).override_failure_message(k).is_true()
	assert_int(d0.horizon_ms).is_equal(0)
	var m := _match([1_000_000])
	_run(1.0, true)
	var hd: Dictionary = m.all[0].debug_stats()
	var cd: Dictionary = m.all[1].debug_stats()
	for k in keys:
		assert_bool(hd.has(k)).override_failure_message(k).is_true()
		assert_bool(cd.has(k)).override_failure_message(k).is_true()
	assert_str(hd.role).is_equal("host")
	assert_int(hd.horizon_ms).is_greater_equal(60)
	assert_int(hd.per_peer.size()).is_equal(1)
	assert_str(hd.per_peer[0].name).is_equal("ONE")
	assert_str(cd.role).is_equal("client")
	assert_int(cd.horizon_ms).is_equal(hd.horizon_ms)


# --- Review fix CR-02: a leave in LOADING after the bind is still eliminated ----------------------

func test_client_leaving_in_loading_after_bind_is_dropped_at_start() -> void:
	var all := _lobby([1_000_000, 2_000_000])
	var h: Node = all[0]
	var stay: Node = all[1]
	var gone: Node = all[2]
	var hb := {}
	h.match_loading.connect(func() -> void: hb.merge(_bind_host(h)))
	stay.match_loading.connect(func() -> void: stay.report_loaded())
	for s in all:
		s.start_scheduled.connect(func() -> void:
			var lead: float = s.lead_in_for_start()
			if lead >= 0.0:
				start_v[s] = now + lead)
	assert_str(h.start_match()).is_equal("")
	assert_bool(hb.has("queue")).is_true()
	assert_bool(_run_until(func() -> bool: return gone.state == gone.State.LOADING)).is_true()
	var seat: int = gone.local_seat()
	hub.drop_peer(gone.transport.unique_id())
	assert_bool(_run_until(func() -> bool: return h.lobby_rows().size() == 2, 2.0, true)) \
		.is_true()
	assert_int(h.state).is_equal(h.State.LOADING)
	h.report_loaded()
	assert_bool(_run_until(func() -> bool: return h.state == h.State.PLAYING, 3.0, true)) \
		.is_true()
	_run(0.5, true)
	var left := false
	for e in (hb.channel as NetHostChannel).broadcast_log:
		if e.type == GameEvent.PLAYER_LEFT and int(e.seat) == seat:
			left = true
	assert_bool(left).is_true()
	var alive := true
	for p in (hb.sim as MatchSim).players:
		if p.seat == seat:
			alive = p.alive
	assert_bool(alive).is_false()


# --- Review fix CR-03: long / C1 titles never make clients drop RESULTS ---------------------------

func test_results_with_a_long_title_reach_clients_clipped() -> void:
	var m := _match([1_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	for s in all:
		s.report_done(5.0)
	assert_bool(_run_until(func() -> bool: return not _fired(h, "results_due").is_empty(), 1.0,
		true)).is_true()
	var data := _results_data()
	data["rows"] = [{"seat": 0, "place": 1, "name": "CAPTAIN"}, {"seat": 1, "place": 2,
		"name": "ONE"}]
	data["title"] = "T".repeat(100)
	data["artist"] = "Art" + String.chr(0x85) + "ist"
	h.host_send_results(data)
	assert_bool(_run_until(func() -> bool:
		return not _fired(all[1], "results_received").is_empty(), 1.0, true)).is_true()
	var got: Dictionary = _fired(all[1], "results_received")[0][0]
	assert_int(str(got.title).length()).is_equal(NetProtocol.MAX_TEXT)
	assert_str(got.artist).is_equal("Artist")
	assert_int(all[1].state).is_equal(all[1].State.RESULTS)


# --- Review fix WR-04: the last INPUTS reach the queue before results_due -------------------------

func test_final_inputs_sent_with_done_are_queued_before_results_due() -> void:
	link_jit = 0.0
	var m := _match([1_000_000])
	var all: Array = m.all
	var h: Node = all[0]
	var c: Node = all[1]
	var q: HostInputQueue = m.host_b.queue
	var rr: RemoteReferee = m.client_b[0].remote
	assert_bool(_run_until(func() -> bool: return _song_t(h) >= 2.0, 6.0, true)).is_true()
	h.report_done(_song_t(h))
	var at_due := {}
	h.results_due.connect(func(_t: float) -> void:
		var n := 0
		for it in q._q:
			if int(it.seat) == 1:
				n += 1
		at_due["n"] = n)
	var t0 := _song_t(c)
	for k in range(3):
		rr.on_stray(rr.seat, t0 - 0.05 + k * 0.01)
	rr.flush()
	c.report_done(t0)
	# Step only (no pump): INPUTS and DONE land in the same host poll.
	assert_bool(_run_until(func() -> bool: return at_due.has("n"), 1.0, false)).is_true()
	assert_int(int(at_due["n"])).is_equal(3)
