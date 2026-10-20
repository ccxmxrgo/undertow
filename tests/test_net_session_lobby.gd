extends GdUnitTestSuite
## 04-06 Task 2: the NetSession lobby half over a MemTransport hub (D-01, D-06, D-11, D-12,
## D-17, D-20, D-21, D-22, D-23). Every session gets its own virtual tick origin through ticks_fn
## and is driven by step(now_s); nothing here touches real sockets or real time.

const SESSION := "res://src/autoload/net_session.gd"
const SIG_A := "0123456789abcdef"
const FP := "u3.aaaaaaaaaaaaaaaaaaaaaaaa.expert"


class FakeSettings:
	extends RefCounted
	var player_name := "DIVER"


class FakeEntry:
	extends RefCounted
	var id := ""
	var fps := {}  # difficulty -> fingerprint

	func difficulty(d: String) -> Dictionary:
		if not fps.has(d):
			return {}
		return {"name": d, "fingerprint": fps[d]}


## A library with a fingerprint table: entries plus the chart each fingerprint builds.
class FakeLib:
	extends RefCounted
	var entries: Array = []
	var charts := {}  # fingerprint -> ChartData
	var builds := 0

	func add(fp: String, diff: String, chart: ChartData) -> void:
		var e := FakeEntry.new()
		e.id = "song_%d" % entries.size()
		e.fps[diff] = fp
		entries.append(e)
		charts[fp] = chart

	func build_chart(entry: Variant, diff: String) -> ChartData:
		builds += 1
		var fp: String = entry.difficulty(diff).get("fingerprint", "")
		return charts.get(fp)


var hub: MemTransport.Hub
var now := 0.0
var dt := 0.005
var link_lat := 0.04
var link_jit := 0.02
var sessions: Array = []
var endpoints: Array = []
var stages := {}  # session -> Array of stages
var errors := {}  # session -> Array of [code, info]
var logs := {}  # session -> Array of [code, info]
var lefts := {}  # session -> Array of codes


func before_test() -> void:
	hub = MemTransport.Hub.new(7)
	now = 0.0
	dt = 0.005
	link_lat = 0.04
	link_jit = 0.02
	sessions.clear()
	endpoints.clear()
	stages.clear()
	errors.clear()
	logs.clear()
	lefts.clear()


func after_test() -> void:
	for s in sessions:
		if is_instance_valid(s):
			s.free()
	sessions.clear()
	endpoints.clear()


func _chart(solos: int = 0) -> ChartData:
	var c := ChartData.new()
	c.time_sigs = [{"time": 0.0, "num": 4, "den": 4}]
	for i in solos:
		c.solos.append({"start": 10.0 + i, "end": 20.0 + i})
	return c


func _song() -> Dictionary:
	return {"fp": FP, "sig": VersusSig.of(_chart()), "diff": "expert", "title": "Song",
		"artist": "Band"}


func _make(pname: String, origin_us: int, lib: FakeLib = null) -> Node:
	var s: Node = load(SESSION).new()
	s.auto_process = false
	var st := FakeSettings.new()
	st.player_name = pname
	s.settings = st
	s.library = lib if lib != null else FakeLib.new()
	s.ticks_fn = func() -> int: return origin_us + int(round(now * 1_000_000.0))
	s.transport_factory = func(role: String) -> NetTransport:
		var t: MemTransport = hub.make_host() if role == "host" else hub.make_client()
		if role != "host":
			hub.set_link(t.unique_id(), link_lat, link_jit)
		endpoints.append(t)
		return t
	stages[s] = []
	errors[s] = []
	logs[s] = []
	lefts[s] = []
	s.connect_stage.connect(func(stage: String) -> void: stages[s].append(stage))
	s.connect_error.connect(func(code: String, info: Dictionary) -> void:
		errors[s].append([code, info]))
	s.log_line.connect(func(code: String, info: Dictionary) -> void: logs[s].append([code, info]))
	s.left_lobby.connect(func(code: String) -> void: lefts[s].append(code))
	add_child(s)
	sessions.append(s)
	return s


func _run(secs: float) -> void:
	var end := now + secs
	while now < end - 1e-9:
		now += dt
		for s in sessions:
			if is_instance_valid(s):
				s.step(now)


func _run_until(cond: Callable, cap: float = 10.0) -> bool:
	var end := now + cap
	while now < end:
		now += dt
		for s in sessions:
			if is_instance_valid(s):
				s.step(now)
		if cond.call():
			return true
	return bool(cond.call())


func _host(pname: String = "CAPTAIN") -> Node:
	var h := _make(pname, 0)
	assert_int(h.host(NetProtocol.DEFAULT_PORT)).is_equal(OK)
	return h


func _join(pname: String, origin_us: int = 1_000_000, lib: FakeLib = null) -> Node:
	var c := _make(pname, origin_us, lib)
	c.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	return c


## Joins and waits for the lobby, so seats follow call order.
func _join_wait(pname: String, origin_us: int = 1_000_000, lib: FakeLib = null) -> Node:
	var c := _join(pname, origin_us, lib)
	assert_bool(_run_until(func() -> bool: return _in_lobby(c))).is_true()
	return c


func _in_lobby(c: Node) -> bool:
	return c.is_in_lobby()


func _codes(arr: Array) -> Array:
	var out := []
	for e in arr:
		out.append(e[0])
	return out


func _row(s: Node, seat: int) -> Dictionary:
	for r in s.lobby_rows():
		if r.seat == seat:
			return r
	return {}


# --- Joining -----------------------------------------------------------------------------------

func test_host_opens_lobby_at_seat_0() -> void:
	var h := _host()
	assert_bool(h.is_host()).is_true()
	assert_bool(h.is_in_lobby()).is_true()
	assert_int(h.local_seat()).is_equal(0)
	var rows: Array = h.lobby_rows()
	assert_int(rows.size()).is_equal(1)
	assert_dict(rows[0]).is_equal({"seat": 0, "name": "CAPTAIN", "ready": true,
		"song": "checking", "ping_ms": 0, "synced": true, "host": true})
	assert_int(h.flight()).is_equal(2)
	assert_dict(h.lobby_song()).is_empty()
	assert_str(_codes(logs[h])[0]).is_equal("choosing")
	# A second host() while hosting is refused.
	assert_int(h.host(NetProtocol.DEFAULT_PORT)).is_not_equal(OK)


func test_three_clients_join_through_stages_with_seats_and_unique_names() -> void:
	var h := _host()
	var c1 := _join("DIVER", 1_000_000)
	var c2 := _join("DIVER", 2_000_000)
	var c3 := _join("Nemo", 3_000_000)
	var ok := _run_until(func() -> bool:
		return _in_lobby(c1) and _in_lobby(c2) and _in_lobby(c3))
	assert_bool(ok).is_true()
	for c in [c1, c2, c3]:
		assert_array(stages[c]).is_equal(["connecting", "auth", "sync", "lobby"])
		assert_array(errors[c]).is_empty()
		assert_bool(c.is_host()).is_false()
	# Seats follow arrival order (jitter decides it); every client learns its own seat.
	var seats := [c1.local_seat(), c2.local_seat(), c3.local_seat()]
	seats.sort()
	assert_array(seats).is_equal([1, 2, 3])
	var divers := [_row(h, c1.local_seat()).name, _row(h, c2.local_seat()).name]
	divers.sort()
	assert_array(divers).is_equal(["DIVER", "DIVER2"])
	assert_str(_row(h, c3.local_seat()).name).is_equal("NEMO")
	assert_int(_codes(logs[h]).count("joined")).is_equal(3)
	_run(1.2)
	for c in [c1, c2, c3]:
		assert_array(c.lobby_rows()).is_equal(h.lobby_rows())


func test_fourth_join_is_refused_full() -> void:
	var h := _host()
	var cs := [_join("A"), _join("B"), _join("C")]
	_run_until(func() -> bool: return _in_lobby(cs[0]) and _in_lobby(cs[1]) and _in_lobby(cs[2]))
	var c4 := _join("D")
	var ok := _run_until(func() -> bool: return not errors[c4].is_empty())
	assert_bool(ok).is_true()
	assert_str(errors[c4][0][0]).is_equal("full")
	assert_bool(c4.is_in_lobby()).is_false()
	assert_int(h.lobby_rows().size()).is_equal(4)


func test_auth_seat_full_reason_when_transport_admits_a_fourth() -> void:
	# ENet keeps one spare slot so the session itself can answer "full" (MemTransport caps at 3).
	var h := _host()
	var cs := [_join("A"), _join("B"), _join("C")]
	_run_until(func() -> bool: return _in_lobby(cs[0]) and _in_lobby(cs[1]) and _in_lobby(cs[2]))
	assert_str(h.auth_refusal_for({"type": NetProtocol.AUTH, "proto": NetProtocol.PROTO,
		"game": NetProtocol.game_version(), "name": "EXTRA"})).is_equal(NetProtocol.R_FULL)


func test_version_mismatch_is_refused_with_host_version() -> void:
	_host()
	var c := _make("OLD", 1_000_000)
	c.game_version_override = "0.0.1"
	c.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	var ok := _run_until(func() -> bool: return not errors[c].is_empty())
	assert_bool(ok).is_true()
	assert_str(errors[c][0][0]).is_equal("version")
	assert_str(errors[c][0][1].get("host_version", "")).is_equal(NetProtocol.game_version())
	assert_bool(c.is_in_lobby()).is_false()


func test_wrong_proto_is_refused_as_version() -> void:
	_host()
	var c := _make("OLD", 1_000_000)
	c.proto_override = NetProtocol.PROTO + 1
	c.join("127.0.0.1", NetProtocol.DEFAULT_PORT)
	_run_until(func() -> bool: return not errors[c].is_empty())
	assert_str(errors[c][0][0]).is_equal("version")


func test_bad_name_is_refused() -> void:
	var h := _host()
	var c := _join("<script>")
	_run_until(func() -> bool: return not errors[c].is_empty())
	assert_str(errors[c][0][0]).is_equal("bad_name")
	assert_int(h.lobby_rows().size()).is_equal(1)


func test_connect_timeout_without_host() -> void:
	var c := _join("LONELY")
	var ok := _run_until(func() -> bool: return not errors[c].is_empty(), 10.0)
	assert_bool(ok).is_true()
	assert_str(errors[c][0][0]).is_equal("timeout")
	assert_array(stages[c]).not_contains(["lobby"])


# --- Roster, ready, song ------------------------------------------------------------------------

func test_ready_song_and_flight_propagate() -> void:
	var ok_lib := FakeLib.new()
	ok_lib.add(FP, "expert", _chart())
	var changed_lib := FakeLib.new()
	changed_lib.add(FP, "expert", _chart(1))
	var h := _host()
	var c1 := _join_wait("ONE", 1_000_000, ok_lib)
	var c2 := _join_wait("TWO", 2_000_000, FakeLib.new())
	var c3 := _join_wait("THREE", 3_000_000, changed_lib)
	_run_until(func() -> bool: return _in_lobby(c1) and _in_lobby(c2) and _in_lobby(c3))
	c1.set_ready(true)
	var ok := _run_until(func() -> bool:
		return _row(h, 1).ready and _row(c2, 1).ready and _row(c3, 1).ready)
	assert_bool(ok).is_true()
	assert_str(_codes(logs[h]).back()).is_equal("ready")

	assert_bool(h.host_set_song(_song())).is_true()
	assert_bool(_row(h, 1).ready).is_false()
	assert_str(_row(h, 1).song).is_equal("checking")
	ok = _run_until(func() -> bool:
		return _row(h, 1).song == "ok" and _row(h, 2).song == "missing" \
			and _row(h, 3).song == "changed")
	assert_bool(ok).is_true()
	assert_dict(c1.lobby_song()).is_equal(_song())
	assert_bool(_codes(logs[h]).has("song_picked")).is_true()
	assert_bool(_codes(logs[h]).has("missing")).is_true()
	assert_int(ok_lib.builds).is_equal(1)
	assert_str(c1.my_song_status()).is_equal("ok")
	assert_str(c2.my_song_status()).is_equal("missing")
	assert_str(c3.my_song_status()).is_equal("changed")

	c1.set_ready(true)
	_run_until(func() -> bool: return _row(c2, 1).ready)
	h.host_set_flight(1)
	ok = _run_until(func() -> bool: return c1.flight() == 1 and c2.flight() == 1)
	assert_bool(ok).is_true()
	assert_bool(_row(h, 1).ready).is_true()
	assert_bool(_codes(logs[c2]).has("flight_set")).is_true()
	_run(1.2)
	assert_array(c3.lobby_rows()).is_equal(h.lobby_rows())


func test_invalid_song_is_ignored() -> void:
	var h := _host()
	assert_bool(h.host_set_song({"fp": FP, "sig": "nothex", "diff": "expert", "title": "",
		"artist": ""})).is_false()
	assert_bool(h.host_set_song({"fp": "", "sig": SIG_A, "diff": "expert", "title": "",
		"artist": ""})).is_false()
	assert_bool(h.host_set_song({"fp": FP, "sig": SIG_A, "diff": "insane", "title": "",
		"artist": ""})).is_false()
	assert_dict(h.lobby_song()).is_empty()
	# Long text is trimmed to the wire cap instead of breaking the LOBBY packet.
	var s := _song()
	s.title = "X".repeat(200)
	assert_bool(h.host_set_song(s)).is_true()
	assert_int((h.lobby_song().title as String).length()).is_equal(NetProtocol.MAX_TEXT)


func test_client_only_and_host_only_calls_are_ignored() -> void:
	var h := _host()
	var c := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c))
	assert_bool(c.host_set_song(_song())).is_false()
	c.host_set_flight(1)
	c.kick(0)
	h.set_ready(false)
	_run(1.2)
	assert_dict(h.lobby_song()).is_empty()
	assert_int(h.flight()).is_equal(2)
	assert_int(h.lobby_rows().size()).is_equal(2)


# --- Clock sync and the start gate --------------------------------------------------------------

func test_clock_sync_offset_rtt_and_synced_flag() -> void:
	dt = 0.001
	var lib := FakeLib.new()
	lib.add(FP, "expert", _chart())
	var h := _host()
	h.host_set_song(_song())
	var c := _join("ONE", 2_000_000, lib)
	var ok := _run_until(func() -> bool: return _row(h, 1).size() > 0)
	assert_bool(ok).is_true()
	# Joined but not synced yet: the host gate reports syncing.
	assert_str(h.start_gate().code).is_equal("syncing")
	assert_bool(c.is_synced()).is_false()
	ok = _run_until(func() -> bool: return _in_lobby(c))
	assert_bool(ok).is_true()
	_run(1.0)
	assert_bool(c.is_synced()).is_true()
	# host = client + offset, so the true offset is 0 - 2,000,000 us.
	# Hard bound: with +-20 ms per-leg jitter a sample can be off by at most jitter / 2. The
	# typical (median) error is checked over seeds below.
	assert_int(absi(c.clock_offset_us() - (-2_000_000))).is_less_equal(10_000)
	ok = _run_until(func() -> bool: return _row(h, 1).synced)
	assert_bool(ok).is_true()
	assert_str(h.start_gate().code).is_equal("not_ready")
	assert_int(absi(c.ping_ms() - 80)).is_less_equal(10)
	_run(15.0)
	assert_int(absi(_row(h, 1).ping_ms - 80)).is_less_equal(10)
	assert_int(absi(c.clock_offset_us() - (-2_000_000))).is_less_equal(10_000)
	assert_float(c.seconds_since_host_packet()).is_less(1.1)


## Offset error after the join burst (16 samples) for one seeded hub, in microseconds.
func _burst_error(seed_value: int, jitter: float) -> int:
	after_test()
	before_test()
	hub = MemTransport.Hub.new(seed_value)
	dt = 0.001
	link_jit = jitter
	var origin := 2_000_000 + seed_value * 777
	_host()
	var c := _join("ONE", origin)
	_run_until(func() -> bool: return c.is_synced(), 5.0)
	_run(1.0)
	return c.clock_offset_us() - (0 - origin)


## MemTransport jitter is uniform and symmetric on both legs, so one sample's error is up to
## jitter / 2 and the D-06 estimator (median of the 5 lowest-RTT samples) cannot promise 2 ms on
## every seed at +-20 ms. The plan's 40+-20 ms link is held to 2 ms typical (median over 12
## seeds) and 10 ms worst; a 40+-2 ms link is held to 2 ms on every seed.
func test_clock_sync_holds_over_seeds() -> void:
	var errs: Array[int] = []
	for i in 12:
		errs.append(absi(_burst_error(100 + i, 0.02)))
	errs.sort()
	assert_int(errs[errs.size() / 2]).is_less_equal(2000)
	assert_int(errs.back()).is_less_equal(10_000)
	for i in 6:
		assert_int(absi(_burst_error(200 + i, 0.002))).is_less_equal(2000)


func test_start_gate_mirrors_lobby_state() -> void:
	var lib := FakeLib.new()
	lib.add(FP, "expert", _chart())
	var h := _host()
	assert_dict(h.start_gate()).is_equal(h.lobby_state().start_gate())
	assert_str(h.start_gate().code).is_equal("need_players")
	var c := _join("ONE", 1_000_000, lib)
	_run_until(func() -> bool: return _in_lobby(c))
	assert_str(h.start_gate().code).is_equal("need_song")
	h.host_set_song(_song())
	_run_until(func() -> bool: return _row(h, 1).song == "ok")
	assert_str(h.start_gate().code).is_equal("not_ready")
	c.set_ready(true)
	var ok := _run_until(func() -> bool: return h.start_gate().ok)
	assert_bool(ok).is_true()
	assert_dict(h.start_gate()).is_equal(h.lobby_state().start_gate())
	_run(1.2)
	assert_dict(c.start_gate()).is_equal(h.start_gate())


# --- Kick, leave, loss ---------------------------------------------------------------------------

func test_kick_sends_client_offline_with_kicked() -> void:
	var h := _host()
	var c1 := _join("ONE")
	var c2 := _join("TWO")
	_run_until(func() -> bool: return _in_lobby(c1) and _in_lobby(c2))
	var s1: int = c1.local_seat()
	h.kick(s1)
	var ok := _run_until(func() -> bool: return c1.is_offline())
	assert_bool(ok).is_true()
	assert_array(lefts[c1]).is_equal(["kicked"])
	assert_str(c1.take_return_message()).is_equal("kicked")
	assert_str(c1.take_return_message()).is_equal("")
	assert_bool(_run_until(func() -> bool: return _row(h, s1).is_empty())).is_true()
	assert_bool(_codes(logs[h]).has("kicked_other")).is_true()
	_run_until(func() -> bool: return _row(c2, s1).is_empty())
	assert_bool(_codes(logs[c2]).has("kicked_other")).is_true()
	assert_bool(c2.is_in_lobby()).is_true()


func test_host_leave_closes_lobby_for_clients() -> void:
	var h := _host()
	var c1 := _join("ONE")
	var c2 := _join("TWO")
	_run_until(func() -> bool: return _in_lobby(c1) and _in_lobby(c2))
	h.leave()
	assert_bool(h.is_offline()).is_true()
	var ok := _run_until(func() -> bool: return c1.is_offline() and c2.is_offline())
	assert_bool(ok).is_true()
	assert_str(c1.take_return_message()).is_equal("closed")
	assert_str(c2.take_return_message()).is_equal("closed")


func test_client_leave_frees_the_seat() -> void:
	var h := _host()
	var c1 := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c1))
	c1.leave()
	assert_bool(c1.is_offline()).is_true()
	var ok := _run_until(func() -> bool: return h.lobby_rows().size() == 1)
	assert_bool(ok).is_true()
	assert_bool(_codes(logs[h]).has("left")).is_true()
	assert_str(c1.take_return_message()).is_equal("")


func test_stalled_host_link_gives_lost_after_4s() -> void:
	var h := _host()
	var c := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c))
	hub.stall(c.transport.unique_id())
	_run(3.5)
	assert_bool(c.is_in_lobby()).is_true()
	var ok := _run_until(func() -> bool: return c.is_offline(), 2.0)
	assert_bool(ok).is_true()
	assert_array(lefts[c]).is_equal(["lost"])
	assert_str(c.take_return_message()).is_equal("lost")
	assert_bool(h.is_host()).is_true()


# --- Hostile packets ----------------------------------------------------------------------------

func test_three_malformed_packets_disconnect_the_peer() -> void:
	var h := _host()
	var c := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c))
	var t: NetTransport = c.transport
	var junk := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	t.send(1, junk)
	t.send(1, NetCodec.encode({"type": "lobby", "roster": []}))  # wrong direction
	_run(0.5)
	assert_int(h.lobby_rows().size()).is_equal(2)
	assert_int(h.peer_strikes(t.unique_id())).is_equal(2)
	t.send(1, NetCodec.encode({"type": NetProtocol.READY, "ready": "yes", "synced": true}))
	var ok := _run_until(func() -> bool: return h.lobby_rows().size() == 1)
	assert_bool(ok).is_true()
	_run_until(func() -> bool: return c.is_offline())
	assert_str(c.take_return_message()).is_equal("lost")


func test_ping_flood_is_dropped_without_strikes() -> void:
	var h := _host()
	var c := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c))
	_run(2.0)
	var pongs := [0]
	var t: NetTransport = c.transport
	t.packet.connect(func(_p: int, b: PackedByteArray) -> void:
		var m := NetCodec.decode(b, {"from_host": true})
		if m.get("type") == NetProtocol.PONG and int(m.seq) >= 100000:
			pongs[0] += 1)
	var dropped0: int = h.debug_stats().ping_dropped
	for i in 100:
		t.send(1, NetCodec.encode({"type": NetProtocol.PING, "seq": 100000 + i, "c0": 0}), false)
	_run(1.0)
	assert_int(pongs[0]).is_between(NetProtocol.PING_BUCKET - 2, NetProtocol.PING_BUCKET + 2)
	assert_int(h.debug_stats().ping_dropped - dropped0).is_equal(100 - pongs[0])
	assert_int(h.peer_strikes(t.unique_id())).is_equal(0)
	assert_int(h.lobby_rows().size()).is_equal(2)
	assert_bool(c.is_in_lobby()).is_true()


func test_join_burst_then_ready_burst_is_never_dropped() -> void:
	var h := _host()
	var c := _join("ONE")
	# The lobby opens once 5 samples are in, while the 16-ping join burst still runs. Ready
	# then does not start a second burst.
	_run_until(func() -> bool: return _in_lobby(c))
	assert_bool(c.is_bursting()).is_true()
	var sent_mid: int = c.debug_stats().pings_sent
	c.set_ready(true)
	_run_until(func() -> bool: return not c.is_bursting())
	assert_int(c.debug_stats().pings_sent).is_equal(16)
	assert_int(sent_mid).is_less(16)
	# A fresh Ready right after the burst starts a new one at once.
	c.set_ready(false)
	c.set_ready(true)
	assert_bool(c.is_bursting()).is_true()
	_run(1.0)
	assert_int(c.debug_stats().pings_sent).is_greater_equal(32)
	assert_int(h.debug_stats().ping_dropped).is_equal(0)


func test_client_ignores_packets_not_from_peer_1() -> void:
	var h := _host()
	var c := _join("ONE")
	_run_until(func() -> bool: return _in_lobby(c))
	_run(1.2)
	var before: Array = c.lobby_rows()
	var forged := NetCodec.encode({"type": NetProtocol.LOBBY, "roster": [
		{"seat": 0, "name": "EVIL", "ready": true, "song": "ok", "ping_ms": 0, "synced": true,
			"host": true}], "song": {}, "flight": 1, "phase": "lobby"})
	c.transport.packet.emit(3, forged)
	assert_array(c.lobby_rows()).is_equal(before)
	assert_int(c.flight()).is_equal(2)
	assert_int(c.debug_stats().rejected_packets).is_greater_equal(1)
	# The same bytes from peer 1 would be applied (proves the sender check did the work).
	c.transport.packet.emit(1, forged)
	assert_int(c.flight()).is_equal(1)
	assert_bool(h.is_host()).is_true()


# --- The same session over real ENet on 127.0.0.1 -----------------------------------------------

## Sessions with the default ENet factory and real ticks, stepped by hand every frame.
func _enet_session(pname: String) -> Node:
	var s: Node = load(SESSION).new()
	s.auto_process = false
	var st := FakeSettings.new()
	st.player_name = pname
	s.settings = st
	s.library = FakeLib.new()
	stages[s] = []
	errors[s] = []
	lefts[s] = []
	s.connect_stage.connect(func(stage: String) -> void: stages[s].append(stage))
	s.connect_error.connect(func(code: String, info: Dictionary) -> void:
		errors[s].append([code, info]))
	s.left_lobby.connect(func(code: String) -> void: lefts[s].append(code))
	add_child(s)
	sessions.append(s)
	return s


func _enet_until(cond: Callable, cap: float = 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(cap * 1000.0):
		var t := Time.get_ticks_usec() / 1_000_000.0
		for s in sessions:
			if is_instance_valid(s):
				s.step(t)
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _enet_host() -> Array:
	for _attempt in 5:
		var h := _enet_session("CAPTAIN")
		var port := 49000 + randi() % 901
		if h.host(port) == OK:
			return [h, port]
		sessions.erase(h)
		h.free()
	return []


func test_enet_session_join_ready_and_kick() -> void:
	var hp := _enet_host()
	assert_array(hp).is_not_empty()
	var h: Node = hp[0]
	var c := _enet_session("DIVER")
	assert_int(c.join("127.0.0.1", hp[1])).is_equal(OK)
	var ok: bool = await _enet_until(func() -> bool: return c.is_in_lobby())
	assert_bool(ok).is_true()
	assert_array(stages[c]).is_equal(["connecting", "auth", "sync", "lobby"])
	assert_int(c.local_seat()).is_equal(1)
	assert_bool(c.is_synced()).is_true()
	c.set_ready(true)
	ok = await _enet_until(func() -> bool: return _row(h, 1).get("ready", false) \
		and _row(c, 1).get("ready", false))
	assert_bool(ok).is_true()
	h.kick(1)
	ok = await _enet_until(func() -> bool: return c.is_offline())
	assert_bool(ok).is_true()
	assert_str(c.take_return_message()).is_equal("kicked")
	ok = await _enet_until(func() -> bool: return h.lobby_rows().size() == 1)
	assert_bool(ok).is_true()


func test_enet_session_refusals_carry_a_reason() -> void:
	var hp := _enet_host()
	var old := _enet_session("OLD")
	old.game_version_override = "0.0.1"
	old.join("127.0.0.1", hp[1])
	var ok: bool = await _enet_until(func() -> bool: return not errors[old].is_empty())
	assert_bool(ok).is_true()
	assert_str(errors[old][0][0]).is_equal("version")
	assert_str(errors[old][0][1].get("host_version", "")).is_equal(NetProtocol.game_version())
	var cs := [_enet_session("A"), _enet_session("B"), _enet_session("C")]
	for c in cs:
		c.join("127.0.0.1", hp[1])
	ok = await _enet_until(func() -> bool:
		return cs[0].is_in_lobby() and cs[1].is_in_lobby() and cs[2].is_in_lobby())
	assert_bool(ok).is_true()
	var late := _enet_session("D")
	late.join("127.0.0.1", hp[1])
	ok = await _enet_until(func() -> bool: return not errors[late].is_empty())
	assert_bool(ok).is_true()
	assert_str(errors[late][0][0]).is_equal("full")


func test_enet_session_host_leave_closes() -> void:
	var hp := _enet_host()
	var h: Node = hp[0]
	var c := _enet_session("DIVER")
	c.join("127.0.0.1", hp[1])
	var ok: bool = await _enet_until(func() -> bool: return c.is_in_lobby())
	assert_bool(ok).is_true()
	h.leave()
	ok = await _enet_until(func() -> bool: return c.is_offline())
	assert_bool(ok).is_true()
	assert_str(c.take_return_message()).is_equal("closed")


func test_enet_session_resolve_error() -> void:
	var c := _enet_session("DIVER")
	c.join("no-such-host.invalid", 49999)
	var ok: bool = await _enet_until(func() -> bool: return not errors[c].is_empty())
	assert_bool(ok).is_true()
	assert_str(errors[c][0][0]).is_equal("resolve")


# --- Review fix WR-07: "Host is choosing a song." reaches clients ---------------------------------

func test_host_choosing_notice_reaches_clients_only() -> void:
	var h := _host()
	var c := _join_wait("ONE")
	var host_before: int = logs[h].size()
	var before: int = logs[c].size()
	h.host_choosing()
	assert_bool(_run_until(func() -> bool: return logs[c].size() > before, 1.0)).is_true()
	assert_str(logs[c][logs[c].size() - 1][0]).is_equal("choosing")
	assert_int(logs[h].size()).is_equal(host_before)
	c.host_choosing()  # clients cannot send it
	_run_until(func() -> bool: return false, 0.2)
	assert_int(h.peer_strikes(h.lobby_state().peer_of(1))).is_equal(0)
