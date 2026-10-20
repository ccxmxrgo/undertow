extends GdUnitTestSuite
## 04-02 Task 1 (D-03, D-09): the Referee seam. MatchSim is a Referee; SubRig talks to any
## Referee with the same call shapes it used with MatchSim; the base methods are safe no-ops.
## click_chart(120): a note every 0.5 s (lane = beat % 4).

const P := InputJudge.Judgment.PERFECT


## Records every call SubRig makes; no rules.
class FakeReferee extends Referee:
	var calls: Array = []

	func on_judged(seat: int, note_index: int, judgment: int, t: float) -> void:
		calls.append(["on_judged", seat, note_index, judgment, t])

	func on_extra_judged(seat: int, judgment: int, t: float) -> void:
		calls.append(["on_extra_judged", seat, judgment, t])

	func on_stray(seat: int, t: float) -> void:
		calls.append(["on_stray", seat, t])

	func on_ghost_hit(seat: int, t: float) -> void:
		calls.append(["on_ghost_hit", seat, t])

	func report_status(seat: int, hull: float, depth: float, accuracy: float, max_streak: int,
			t: float = NAN) -> void:
		calls.append(["report_status", seat, hull, depth, accuracy, max_streak, t])

	func on_failed(seat: int, t: float) -> void:
		calls.append(["on_failed", seat, t])

	func set_approach(seat: int, approach_s: float) -> void:
		calls.append(["set_approach", seat, approach_s])

	func of(kind: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == kind)


func _players() -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for s in range(2):
		out.append(PlayerState.new(s, "P%d" % s, s == 0))
	return out


func _sim(chart: ChartData, players: Array[PlayerState]) -> MatchSim:
	return MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), players,
		LoopbackChannel.new(), 3)


func test_match_sim_is_a_referee() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var players := _players()
	var r: Referee = _sim(chart, players)
	assert_bool(r is Referee).is_true()
	assert_int(r.players.size()).is_equal(2)
	assert_int(r.players[1].seat).is_equal(1)


func test_base_methods_are_safe_no_ops() -> void:
	var r := Referee.new()
	assert_int(Referee.FIRE_REMOTE).is_equal(5)
	assert_int(r.request_fire(0, 1.0)).is_equal(Referee.FIRE_REMOTE)
	assert_int(r.cycle_target(0, 1.0)).is_equal(-1)
	assert_float(r.duel_live(0)).is_equal(-1.0)
	assert_int(r.duel_active()).is_equal(-1)
	assert_int(r.players.size()).is_equal(0)
	r.on_judged(0, 0, P, 0.0)
	r.on_extra_judged(0, P, 0.0)
	r.on_stray(0, 0.0)
	r.on_ghost_hit(0, 0.0)
	r.report_status(0, 1.0, 0.0, 1.0, 0)
	r.set_target_mode(0, PlayerState.TargetMode.AUTO)
	r.on_failed(0, 0.0)
	r.update(1.0)
	r.set_approach(0, 2.0)


func test_fire_remote_does_not_collide_with_match_sim_results() -> void:
	for v in [MatchSim.FIRE_OK, MatchSim.FIRE_NOTHING, MatchSim.FIRE_SHIELDED,
			MatchSim.FIRE_NO_TARGET, MatchSim.FIRE_PENDING]:
		assert_bool(v == Referee.FIRE_REMOTE).is_false()


func test_sub_rig_calls_a_fake_referee_with_match_sim_shapes() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var fake := FakeReferee.new()
	var ch := LoopbackChannel.new()
	var rig := SubRig.new(0, chart, JudgeConfig.new(), VersusConfig.new(), fake, ch, false)
	rig.press(1, 0.5)  # beat 1 -> lane 1: PERFECT on note 1 (note 0 expires as MISS)
	var judged := fake.of("on_judged")
	assert_bool(judged.size() >= 1).is_true()
	var last: Array = judged[judged.size() - 1]
	assert_int(last[1]).is_equal(0)
	assert_int(last[2]).is_equal(1)
	assert_int(last[3]).is_equal(P)
	assert_float(last[4]).is_equal_approx(0.5, 1e-9)
	var st := fake.of("report_status")
	assert_bool(st.size() >= 1).is_true()
	var s: Array = st[st.size() - 1]
	assert_int(s[1]).is_equal(0)
	assert_float(s[2]).is_equal(rig.hull.hull)
	assert_float(s[3]).is_equal_approx(rig.hull.depth(), 1e-9)
	assert_bool(s[5] is int).is_true()  # max_streak (reported before the combo ticks over)
	# A press with no note in reach is a stray.
	rig.press(3, 0.75)
	var strays := fake.of("on_stray")
	assert_int(strays.size()).is_equal(1)
	assert_int(strays[0][1]).is_equal(0)
	assert_float(strays[0][2]).is_equal_approx(0.75, 1e-9)


func test_sub_rig_reports_failure_to_the_referee() -> void:
	var chart := TestCharts.click_chart(120.0, 400, 1000)
	var fake := FakeReferee.new()
	var rig := SubRig.new(0, chart, JudgeConfig.new(), VersusConfig.new(), fake,
		LoopbackChannel.new(), false)
	rig.tick(150.0)  # every note expires as MISS: the hull fails
	var failed := fake.of("on_failed")
	assert_int(failed.size()).is_equal(1)
	assert_int(failed[0][1]).is_equal(0)


func test_approach_setter_reports_through_the_referee() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var fake := FakeReferee.new()
	var rig := SubRig.new(1, chart, JudgeConfig.new(), VersusConfig.new(), fake,
		LoopbackChannel.new(), false)
	fake.calls.clear()
	rig.approach_s = 2.0
	var a := fake.of("set_approach")
	assert_int(a.size()).is_equal(1)
	assert_int(a[0][1]).is_equal(1)
	assert_float(a[0][2]).is_equal(2.0)


func test_approach_setter_reaches_match_sim_player() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var players := _players()
	var sim := _sim(chart, players)
	var rig := SubRig.new(0, chart, JudgeConfig.new(), VersusConfig.new(), sim,
		LoopbackChannel.new(), false)
	rig.approach_s = 2.0
	assert_float(players[0].approach_s).is_equal(2.0)
	sim.set_approach(1, 3.0)
	assert_float(players[1].approach_s).is_equal(3.0)
