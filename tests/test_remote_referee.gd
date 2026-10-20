extends GdUnitTestSuite
## 04-05 Task 2: RemoteReferee, the client proxy (D-13, D-23, Pitfall 5).

const PF := InputJudge.Judgment.PERFECT

var _sent: Array = []


func _capture(msg: Dictionary) -> void:
	_sent.append(msg)


func _rr(seat: int = 1) -> RemoteReferee:
	_sent = []
	var ps: Array[PlayerState] = []
	for s in range(3):
		ps.append(PlayerState.new(s, "P%d" % s, s == seat))
	return RemoteReferee.new(seat, ps, _capture)


func _ctx() -> Dictionary:
	return {"from_host": false, "note_count": 100, "song_len": 60.0}


func test_players_kept_for_sub_rig() -> void:
	var rr := _rr(1)
	assert_int(rr.players.size()).is_equal(3)
	assert_int(rr.players[1].seat).is_equal(1)


func test_own_inputs_serialized_with_increasing_seq() -> void:
	var rr := _rr(1)
	rr.on_judged(1, 4, PF, 2.0)
	rr.on_extra_judged(1, PF, 2.1)
	rr.on_stray(1, 2.2)
	rr.on_ghost_hit(1, 2.3)
	rr.report_status(1, 90.0, 1200.0, 0.95, 7, 2.4)
	assert_int(rr.request_fire(1, 2.5)).is_equal(Referee.FIRE_REMOTE)
	assert_int(rr.cycle_target(1, 2.6)).is_equal(-1)
	rr.set_target_mode(1, PlayerState.TargetMode.LOCKED, 2, 2.7)
	rr.on_failed(1, 2.8)
	rr.set_approach(1, 1.4)
	rr.flush()
	assert_int(_sent.size()).is_equal(1)
	var msg: Dictionary = _sent[0]
	assert_str(msg["type"]).is_equal(NetProtocol.INPUTS)
	var items: Array = msg["items"]
	assert_int(items.size()).is_equal(10)
	var kinds := [NetProtocol.IN_JUDGED, NetProtocol.IN_EXTRA, NetProtocol.IN_STRAY,
		NetProtocol.IN_GHOST, NetProtocol.IN_STATUS, NetProtocol.IN_FIRE, NetProtocol.IN_CYCLE,
		NetProtocol.IN_TARGET_MODE, NetProtocol.IN_FAILED, NetProtocol.IN_APPROACH]
	for k in range(items.size()):
		assert_int(items[k][0]).is_equal(kinds[k])
		assert_int(items[k][2]).is_equal(k)
	assert_array(items[0]).is_equal([NetProtocol.IN_JUDGED, 2.0, 0, 4, PF])
	assert_array(items[4]).is_equal([NetProtocol.IN_STATUS, 2.4, 4, 90.0, 1200.0, 0.95, 7])
	assert_array(items[7]).is_equal([NetProtocol.IN_TARGET_MODE, 2.7, 7,
		PlayerState.TargetMode.LOCKED, 2])
	# The batch passes the host's NetCodec validation as-is.
	var dec := NetCodec.decode(NetCodec.encode(msg), _ctx())
	assert_bool(dec.is_empty()).is_false()
	# seq keeps increasing across flushes; an empty flush sends nothing.
	rr.flush()
	assert_int(_sent.size()).is_equal(1)
	rr.on_stray(1, 3.0)
	rr.flush()
	assert_int(_sent[1]["items"][0][2]).is_equal(10)


func test_foreign_seat_ignored() -> void:
	var rr := _rr(1)
	rr.on_judged(0, 4, PF, 2.0)
	rr.on_stray(2, 2.0)
	rr.report_status(3, 1.0, 1.0, 1.0, 1, 2.0)
	assert_int(rr.request_fire(0, 2.0)).is_equal(Referee.FIRE_REMOTE)
	rr.on_failed(2, 2.0)
	assert_int(rr.ignored_foreign).is_equal(5)
	rr.flush()
	assert_int(_sent.size()).is_equal(0)


func test_non_finite_times_stamped_at_flush() -> void:
	var rr := _rr(1)
	rr.cycle_target(1)  # NaN default before any set_now
	rr.flush()
	assert_float(float(_sent[0]["items"][0][1])).is_equal(0.0)
	rr.set_now(12.5)
	rr.set_target_mode(1, PlayerState.TargetMode.AUTO)
	rr.flush()
	assert_float(float(_sent[1]["items"][0][1])).is_equal(12.5)
	rr.on_stray(1, INF)
	rr.update(13.0)  # update only records now
	rr.flush()
	assert_float(float(_sent[2]["items"][0][1])).is_equal(13.0)
	rr.set_now(-50.0)
	rr.on_stray(1, NAN)
	rr.flush()
	assert_float(float(_sent[3]["items"][0][1])).is_equal(-10.0)
	for m in _sent:
		for it in m["items"]:
			assert_bool(is_finite(float(it[1]))).is_true()


func test_flush_chunks_at_max_batch() -> void:
	var rr := _rr(1)
	for k in range(300):
		rr.report_status(1, 80.0, float(k), 0.5, k, 1.0 + k * 0.01)
	rr.flush()
	assert_int(_sent.size()).is_equal(3)
	assert_int(_sent[0]["items"].size()).is_equal(NetProtocol.MAX_BATCH)
	assert_int(_sent[1]["items"].size()).is_equal(NetProtocol.MAX_BATCH)
	assert_int(_sent[2]["items"].size()).is_equal(300 - 2 * NetProtocol.MAX_BATCH)
	for m in _sent:
		var bytes := NetCodec.encode(m)
		assert_int(bytes.size()).is_less_equal(NetProtocol.MAX_PACKET)
		assert_bool(NetCodec.decode(bytes, _ctx()).is_empty()).is_false()


func test_duel_live_from_events() -> void:
	var rr := _rr(1)
	var ch := EventChannel.new()
	rr.bind(ch)
	assert_float(rr.duel_live(1)).is_equal(-1.0)
	ch.send(GameEvent.make(GameEvent.DUEL_START, 20.0, {"solo": 0}))
	assert_int(rr.duel_active()).is_equal(0)
	ch.send(GameEvent.make(GameEvent.DUEL_LIVE, 21.0, {"solo": 0, "pct": {0: 50.0, 1: 75.0}}))
	assert_float(rr.duel_live(1)).is_equal(75.0)
	assert_float(rr.duel_live(0)).is_equal(50.0)
	assert_float(rr.duel_live(2)).is_equal(-1.0)
	ch.send(GameEvent.make(GameEvent.DUEL_LIVE, 21.5, {"solo": 0, "pct": {1: 80.0}}))
	assert_float(rr.duel_live(1)).is_equal(80.0)
	ch.send(GameEvent.make(GameEvent.DUEL_RESULT, 30.0,
		{"solo": 0, "winner": 1, "pct": 80.0, "best_pct": 80.0, "tied": false}))
	assert_float(rr.duel_live(1)).is_equal(-1.0)
	assert_int(rr.duel_active()).is_equal(-1)
	ch.send(GameEvent.make(GameEvent.DUEL_LIVE, 40.0, {"solo": 1, "pct": {1: 10.0}}))
	assert_float(rr.duel_live(1)).is_equal(10.0)
	ch.send(GameEvent.make(GameEvent.MATCH_END, 50.0, {"standings": []}))
	assert_float(rr.duel_live(1)).is_equal(-1.0)


func test_sub_rig_accepts_remote_referee() -> void:
	var rr := _rr(1)
	assert_bool(rr is Referee).is_true()
	rr.set_approach(1, 2.0)
	rr.flush()
	assert_float(float(_sent[0]["items"][0][3])).is_equal(2.0)
