extends GdUnitTestSuite
## 03-03 Task 3: standings, last standing and STATUS (MATCH-02, D-22, D-23).
## click_chart(120): 0.5 s per beat.

var _ev: Array = []
var _players: Array[PlayerState] = []


func _sim(n: int = 4) -> MatchSim:
	var chart := TestCharts.click_chart(120.0, 256, 1000)
	_players = []
	for s in range(n):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	return MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), _players, ch, 3)


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _row(rows: Array, seat: int) -> Dictionary:
	for r in rows:
		if r["seat"] == seat:
			return r
	return {}


func test_survivors_by_depth_then_hull() -> void:
	var sim := _sim()
	sim.report_status(0, 50.0, 900.0, 0.9, 10, 0.1)
	sim.report_status(1, 70.0, 900.0, 0.8, 5, 0.1)
	sim.report_status(2, 100.0, 300.0, 1.0, 50, 0.1)
	sim.report_status(3, 100.0, 100.0, 1.0, 50, 0.1)
	var rows := sim.standings()
	assert_int(rows[0]["seat"]).is_equal(1)
	assert_int(rows[0]["place"]).is_equal(1)
	assert_int(rows[1]["seat"]).is_equal(0)
	assert_int(rows[1]["place"]).is_equal(2)
	assert_int(rows[2]["seat"]).is_equal(2)
	assert_int(rows[3]["seat"]).is_equal(3)
	assert_int(sim.winner()).is_equal(1)
	for k in ["seat", "place", "alive", "depth", "hull", "accuracy", "max_streak",
			"eliminated_at"]:
		assert_bool(rows[0].has(k)).is_true()


func test_accuracy_then_streak_break_ties() -> void:
	var sim := _sim(3)
	sim.report_status(0, 80.0, 500.0, 0.90, 10, 0.1)
	sim.report_status(1, 80.0, 500.0, 0.95, 10, 0.1)
	sim.report_status(2, 80.0, 500.0, 0.95, 30, 0.1)
	var rows := sim.standings()
	assert_array(rows.map(func(r: Dictionary) -> int: return r["seat"])).is_equal([2, 1, 0])
	assert_array(rows.map(func(r: Dictionary) -> int: return r["place"])).is_equal([1, 2, 3])


func test_exact_equality_shares_place() -> void:
	var sim := _sim()
	sim.report_status(0, 80.0, 500.0, 0.9, 10, 0.1)
	sim.report_status(1, 80.0, 500.0, 0.9, 10, 0.1)
	sim.report_status(2, 80.0, 400.0, 0.9, 10, 0.1)
	sim.report_status(3, 80.0, 400.0, 0.9, 10, 0.1)
	var rows := sim.standings()
	assert_int(_row(rows, 0)["place"]).is_equal(1)
	assert_int(_row(rows, 1)["place"]).is_equal(1)
	assert_int(_row(rows, 2)["place"]).is_equal(3)
	assert_int(_row(rows, 3)["place"]).is_equal(3)
	assert_int(sim.winner()).is_equal(-1)


func test_all_four_tied_survivors_share_first() -> void:
	var sim := _sim()
	for r in sim.standings():
		assert_int(r["place"]).is_equal(1)


func test_eliminated_after_survivors_later_death_first() -> void:
	var sim := _sim()
	sim.report_status(0, 10.0, 100.0, 0.5, 1, 0.1)
	sim.report_status(1, 90.0, 900.0, 0.9, 1, 0.1)
	sim.report_status(2, 90.0, 800.0, 0.9, 1, 0.1)
	sim.report_status(3, 90.0, 900.0, 0.9, 1, 0.1)
	sim.on_failed(3, 40.0)
	sim.on_failed(2, 60.0)
	var rows := sim.standings()
	assert_array(rows.map(func(r: Dictionary) -> int: return r["seat"])).is_equal([1, 0, 2, 3])
	assert_array(rows.map(func(r: Dictionary) -> int: return r["place"])).is_equal([1, 2, 3, 4])
	assert_bool(_row(rows, 2)["alive"]).is_false()
	assert_float(_row(rows, 2)["eliminated_at"]).is_equal(60.0)
	assert_float(_row(rows, 0)["eliminated_at"]).is_equal(INF)


func test_same_beat_deaths_ordered_by_depth() -> void:
	var sim := _sim()
	sim.report_status(2, 0.0, 300.0, 0.5, 1, 0.1)
	sim.report_status(3, 0.0, 500.0, 0.5, 1, 0.1)
	sim.on_failed(3, 40.1)
	sim.on_failed(2, 40.3)
	var rows := sim.standings()
	assert_int(rows[2]["seat"]).is_equal(3)
	assert_int(rows[3]["seat"]).is_equal(2)
	assert_int(rows[2]["place"]).is_equal(3)
	assert_int(rows[3]["place"]).is_equal(4)


func test_last_standing_once_at_next_beat_boundary() -> void:
	var sim := _sim(3)
	sim.update(10.0)
	sim.on_failed(1, 10.1)
	sim.update(12.0)
	sim.on_failed(2, 12.2)
	assert_int(_of(GameEvent.LAST_STANDING).size()).is_equal(0)
	sim.update(12.49)
	assert_int(_of(GameEvent.LAST_STANDING).size()).is_equal(0)
	sim.update(12.5)
	var ls := _of(GameEvent.LAST_STANDING)
	assert_int(ls.size()).is_equal(1)
	assert_int(ls[0]["seat"]).is_equal(0)
	assert_float(ls[0]["t"]).is_equal_approx(12.5, 1e-9)
	sim.update(60.0)
	assert_int(_of(GameEvent.LAST_STANDING).size()).is_equal(1)


func test_last_two_die_in_same_beat_no_last_standing() -> void:
	var sim := _sim(3)
	sim.report_status(1, 0.0, 200.0, 0.5, 1, 0.1)
	sim.report_status(2, 0.0, 400.0, 0.5, 1, 0.1)
	sim.on_failed(0, 5.0)
	sim.update(10.0)
	sim.on_failed(1, 10.1)
	sim.on_failed(2, 10.4)
	sim.update(30.0)
	assert_int(_of(GameEvent.LAST_STANDING).size()).is_equal(0)
	var rows := sim.standings()
	assert_int(rows[0]["seat"]).is_equal(2)
	assert_int(rows[1]["seat"]).is_equal(1)
	assert_int(rows[2]["seat"]).is_equal(0)
	assert_int(sim.winner()).is_equal(2)


func test_status_emitted_on_change_at_most_once_per_beat() -> void:
	var sim := _sim()
	sim.update(0.0)
	var st := _of(GameEvent.STATUS)
	assert_int(st.size()).is_equal(4)
	sim.report_status(1, 100.0, 25.0, 0.9, 1, 0.1)
	sim.report_status(1, 100.0, 35.0, 0.9, 2, 0.2)
	sim.update(0.5)
	var s1 := _of(GameEvent.STATUS).filter(func(e: Dictionary) -> bool: return e["seat"] == 1)
	assert_int(s1.size()).is_equal(2)
	assert_float(s1[1]["depth"]).is_equal(35.0)
	assert_int(s1[1]["place"]).is_equal(1)
	var s0 := _of(GameEvent.STATUS).filter(func(e: Dictionary) -> bool: return e["seat"] == 0)
	assert_int(s0[s0.size() - 1]["place"]).is_equal(2)
	sim.report_status(1, 100.0, 37.0, 0.9, 3, 0.6)
	sim.update(1.0)
	s1 = _of(GameEvent.STATUS).filter(func(e: Dictionary) -> bool: return e["seat"] == 1)
	assert_int(s1.size()).is_equal(2)
	sim.on_failed(3, 1.1)
	sim.update(1.5)
	var s3 := _of(GameEvent.STATUS).filter(func(e: Dictionary) -> bool: return e["seat"] == 3)
	assert_bool(s3[s3.size() - 1]["alive"]).is_false()


func test_finish_emits_match_end_once() -> void:
	var sim := _sim()
	sim.report_status(2, 100.0, 50.0, 0.9, 1, 0.1)
	sim.finish(20.0)
	sim.finish(21.0)
	var me := _of(GameEvent.MATCH_END)
	assert_int(me.size()).is_equal(1)
	assert_int(me[0]["standings"][0]["seat"]).is_equal(2)


func test_drones_are_not_ranked_and_never_last_standing() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var ps: Array[PlayerState] = [PlayerState.new(0, "YOU", true),
		PlayerState.new(1, "DRONE", false, true)]
	var ch := LoopbackChannel.new()
	var got: Array = []
	ch.received.connect(func(e: Dictionary) -> void: got.append(e))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps, ch, 1)
	sim.on_failed(1, 1.0)
	assert_bool(ps[1].alive).is_true()
	sim.update(10.0)
	assert_int(sim.standings().size()).is_equal(1)
	assert_int(got.filter(func(e: Dictionary) -> bool:
		return e["type"] == GameEvent.LAST_STANDING).size()).is_equal(0)
