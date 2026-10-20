extends GdUnitTestSuite
## 04-05 Task 2: NetHostChannel fan-out and batching, NetClientChannel ordering and validation
## (D-23, Pitfall 6, T-04-16).

const CUT := 12 * 1024

var _local: Array = []
var _now := 0.0


func _on_local(e: Dictionary) -> void:
	_local.append(e)


func _now_fn() -> float:
	return _now


func _ctx() -> Dictionary:
	return {"from_host": true, "note_count": 1000, "song_len": 600.0}


func _landed(id: int, to: int, t: float) -> Dictionary:
	return GameEvent.make(GameEvent.LANDED, t, {"id": id, "from": 0, "to": to,
		"reward": Reward.Id.INK_CLOUD, "arrive_t": t, "active_start": t + 1.0, "end_t": t + 5.0,
		"seed": 12345, "reflected": false, "debris": false})


func _big(i: int) -> Dictionary:
	# A fat but valid event (16-entry arrays of flat dicts) to force the size cut.
	var rows: Array = []
	for k in range(16):
		rows.append({"seat": k % 4, "place": k % 4 + 1, "alive": true, "depth": 1000.0 + k,
			"hull": 50.0, "accuracy": 0.9, "max_streak": k, "eliminated_at": INF})
	return GameEvent.make(GameEvent.MATCH_END, float(i) * 0.01, {"standings": rows})


func test_host_emits_locally_first_and_fans_out() -> void:
	var ch := NetHostChannel.new()
	_local = []
	ch.received.connect(_on_local)
	ch.add_peer(2)
	ch.add_peer(3)
	var e := GameEvent.make(GameEvent.IMPLODED, 1.0, {"seat": 1})
	ch.send(e)
	assert_int(_local.size()).is_equal(1)
	assert_int(ch.broadcast_log.size()).is_equal(1)
	ch.update(99.0)  # no-op
	var b := ch.take_batches()
	assert_int(b.size()).is_equal(2)
	for pid in [2, 3]:
		var msgs: Array = b[pid]
		assert_int(msgs.size()).is_equal(1)
		assert_str(msgs[0]["type"]).is_equal(NetProtocol.EVENTS)
		assert_int(msgs[0]["seq"]).is_equal(1)
		assert_array(msgs[0]["events"]).is_equal([e])
	# Outboxes cleared; the next batch gets seq 2.
	var empty := ch.take_batches()
	assert_bool(empty.get(2, []).is_empty()).is_true()
	ch.send(e)
	ch.remove_peer(3)
	var b2 := ch.take_batches()
	assert_int(b2[2][0]["seq"]).is_equal(2)
	assert_bool(b2.has(3)).is_false()
	# A peer added late starts at seq 1 with only later events.
	ch.add_peer(4)
	ch.send(e)
	var b3 := ch.take_batches()
	assert_int(b3[4][0]["seq"]).is_equal(1)
	assert_int(b3[4][0]["events"].size()).is_equal(1)


func test_host_batches_cut_at_128_events() -> void:
	var ch := NetHostChannel.new()
	ch.add_peer(2)
	for k in range(300):
		ch.send(GameEvent.make(GameEvent.IMPLODED, float(k) * 0.01, {"seat": k % 4}))
	var msgs: Array = ch.take_batches()[2]
	assert_int(msgs.size()).is_equal(3)
	assert_int(msgs[0]["events"].size()).is_equal(NetProtocol.MAX_BATCH)
	assert_int(msgs[1]["events"].size()).is_equal(NetProtocol.MAX_BATCH)
	assert_int(msgs[2]["events"].size()).is_equal(300 - 2 * NetProtocol.MAX_BATCH)
	for k in range(msgs.size()):
		assert_int(msgs[k]["seq"]).is_equal(k + 1)


func test_host_batches_cut_at_12_kib() -> void:
	var ch := NetHostChannel.new()
	ch.add_peer(2)
	assert_bool(NetCodec.validate_event(_big(0))).is_true()
	for k in range(60):
		ch.send(_big(k))
	var msgs: Array = ch.take_batches()[2]
	assert_int(msgs.size()).is_greater(1)
	var total := 0
	for m in msgs:
		var bytes := NetCodec.encode(m)
		assert_int(bytes.size()).is_less_equal(CUT)
		assert_int(m["events"].size()).is_less_equal(NetProtocol.MAX_BATCH)
		assert_bool(NetCodec.decode(bytes, _ctx()).is_empty()).is_false()
		total += m["events"].size()
	assert_int(total).is_equal(60)


## Host -> client end to end: every event arrives in order exactly once with reordering and
## duplicated delivery.
func test_client_orders_and_dedups() -> void:
	var host := NetHostChannel.new()
	host.add_peer(2)
	var msgs: Array = []
	for k in range(5):
		for j in range(3):
			host.send(GameEvent.make(GameEvent.IMPLODED, float(k * 3 + j), {"seat": j}))
		msgs.append_array(host.take_batches()[2])
	assert_int(msgs.size()).is_equal(5)
	_local = []
	var cl := NetClientChannel.new(1, _now_fn, _ctx())
	cl.received.connect(_on_local)
	# Delivery order: 1, 3, 3, 2, 1, 5, 4, 5
	for i in [0, 2, 2, 1, 0, 4, 3, 4]:
		var dec := NetCodec.decode(NetCodec.encode(msgs[i]), _ctx())
		cl.receive(dec)
	assert_int(_local.size()).is_equal(15)
	for k in range(15):
		assert_float(float(_local[k]["t"])).is_equal(float(k))
	assert_int(cl.received_log.size()).is_equal(15)
	var st := cl.debug_stats()
	assert_int(int(st["last_seq"])).is_equal(5)
	assert_int(int(st["received"])).is_equal(15)
	assert_int(int(st["rejected_events"])).is_equal(0)


func test_client_revalidates_events() -> void:
	_local = []
	var cl := NetClientChannel.new(1, _now_fn, _ctx())
	cl.received.connect(_on_local)
	var good := GameEvent.make(GameEvent.IMPLODED, 1.0, {"seat": 1})
	var bad_type := {"type": "nope", "t": 1.0}
	var bad_t := {"type": GameEvent.IMPLODED, "t": NAN, "seat": 1}
	var bad_seat := {"type": GameEvent.IMPLODED, "t": 1.0, "seat": 9}
	cl.receive({"type": NetProtocol.EVENTS, "seq": 1,
		"events": [bad_type, good, bad_t, bad_seat, "junk", good]})
	assert_int(_local.size()).is_equal(2)
	assert_int(cl.rejected_events).is_equal(4)
	assert_int(int(cl.debug_stats()["rejected_events"])).is_equal(4)
	# Malformed messages are ignored without crashing.
	cl.receive({"type": NetProtocol.EVENTS, "seq": "x", "events": []})
	cl.receive({"type": NetProtocol.EVENTS, "seq": 2})
	cl.receive({})
	assert_int(cl.last_seq).is_equal(1)


func test_client_landed_late_for_local_target() -> void:
	_local = []
	var cl := NetClientChannel.new(1, _now_fn, _ctx())
	_now = 10.08
	cl.receive({"type": NetProtocol.EVENTS, "seq": 1, "events": [_landed(1, 1, 10.0)]})
	assert_float(cl.landed_late_last_ms).is_equal_approx(80.0, 1e-6)
	assert_float(cl.landed_late_max_ms).is_equal_approx(80.0, 1e-6)
	_now = 20.03
	cl.receive({"type": NetProtocol.EVENTS, "seq": 2,
		"events": [_landed(2, 2, 19.0), _landed(3, 1, 20.0)]})  # seat 2 is not local
	assert_float(cl.landed_late_last_ms).is_equal_approx(30.0, 1e-6)
	assert_float(cl.landed_late_max_ms).is_equal_approx(80.0, 1e-6)
	_now = 29.0  # early arrival clamps to 0
	cl.receive({"type": NetProtocol.EVENTS, "seq": 3, "events": [_landed(4, 1, 30.0)]})
	assert_float(cl.landed_late_last_ms).is_equal(0.0)
	var st := cl.debug_stats()
	for key in ["last_seq", "rejected_events", "landed_late_last_ms", "landed_late_max_ms",
			"received"]:
		assert_bool(st.has(key)).is_true()


## Real MatchSim events through HostInputQueue -> NetHostChannel -> NetClientChannel: the client
## sees exactly the host's broadcast log.
func test_host_queue_to_client_end_to_end() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var host := NetHostChannel.new()
	host.add_peer(2)
	var ps: Array[PlayerState] = []
	for s in range(2):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps, host, 5)
	var q := HostInputQueue.new(sim, host, 0.1)
	_local = []
	var cl := NetClientChannel.new(1, _now_fn, _ctx())
	cl.received.connect(_on_local)
	for n in range(40):
		q.on_judged(0, n, InputJudge.Judgment.PERFECT, n * 0.5)
		q.report_status(0, 100.0, n * 100.0, 1.0, n + 1, n * 0.5)
	var frame := 0
	while frame < 60 * 22:
		frame += 1
		q.pump(frame / 60.0)
		for m in host.take_batches().get(2, []):
			cl.receive(NetCodec.decode(NetCodec.encode(m), _ctx()))
	q.drop_seat(1, "disconnected")
	for m in host.take_batches().get(2, []):
		cl.receive(NetCodec.decode(NetCodec.encode(m), _ctx()))
	assert_int(host.broadcast_log.size()).is_greater(10)
	assert_int(cl.rejected_events).is_equal(0)
	assert_str(var_to_str(cl.received_log)).is_equal(var_to_str(host.broadcast_log))
	assert_str(cl.received_log[-1]["type"]).is_equal(GameEvent.PLAYER_LEFT)
