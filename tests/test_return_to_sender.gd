extends GdUnitTestSuite
## 03-06 Task 1: Return to Sender (PAY-06, D-16, D-17, spec req 10 with D-17).
## click_chart(120, 1000): one note per beat, 0.5 s per beat, 2 s per bar, threshold 120. Seat 1 fires Ink Cloud at
## 1.1 -> launch beat 3 (1.5 s), lands on seat 0 at 2.0 s with warheads = notes 4..7.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const INK := Reward.Id.INK_CLOUD
const DECOY := Reward.Id.DECOY_FLARE

var _ev: Array = []
var _players: Array[PlayerState] = []
var _chart: ChartData


func _sim(beats: int = 1000, bounty: bool = false) -> MatchSim:
	_chart = TestCharts.click_chart(120.0, beats, 1000)
	_players = []
	for s in range(4):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	var sim := MatchSim.new(_chart, VersusConfig.new(), JudgeConfig.new(), _players, ch, 7)
	if bounty:
		var depths := [900.0, 500.0, 400.0, 300.0]
		for s in range(4):
			sim.report_status(s, 100.0, depths[s], 0.9, 10, 0.25)
	return sim


func _give(seat: int, id: int) -> void:
	_players[seat].meter.progress = _players[seat].meter.target
	_players[seat].meter.held = id


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Seat 1 -> seat 0 Ink Cloud landing at 2.0 s. Returns the torpedo id.
func _land_on_0(sim: MatchSim) -> int:
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(2.0)
	return _of(GameEvent.LANDED)[0]["id"]


func _judge_heads(sim: MatchSim, judgments: Array) -> void:
	for i in range(judgments.size()):
		var n := 4 + i
		sim.on_judged(0, n, judgments[i], n * 0.5)


func test_launch_carries_four_warheads() -> void:
	var sim := _sim()
	_land_on_0(sim)
	var l: Array = _of(GameEvent.TORPEDO_LAUNCH)[0]["warheads"]
	assert_array(l).is_equal([4, 5, 6, 7])


func test_four_perfect_warheads_reflect() -> void:
	var sim := _sim()
	var id := _land_on_0(sim)
	_judge_heads(sim, [P, P, P, P])
	var w := _of(GameEvent.WARHEAD)
	assert_int(w.size()).is_equal(4)
	for i in range(4):
		assert_int(w[i]["id"]).is_equal(id)
		assert_int(w[i]["seat"]).is_equal(0)
		assert_int(w[i]["note"]).is_equal(4 + i)
		assert_int(w[i]["k"]).is_equal(i + 1)
		assert_int(w[i]["n"]).is_equal(4)
		assert_bool(w[i]["ok"]).is_true()
	var r := _of(GameEvent.REFLECTED)
	assert_int(r.size()).is_equal(1)
	assert_int(r[0]["id"]).is_equal(id)
	assert_int(r[0]["by"]).is_equal(0)
	assert_int(r[0]["to"]).is_equal(1)
	assert_int(r[0]["reward"]).is_equal(INK)
	assert_float(r[0]["t"]).is_equal_approx(3.5, 1e-9)
	assert_int(_players[0].reflected).is_equal(1)
	# The payload eases out over the next beat (4.0 s), then immunity for one bar.
	assert_int(_of(GameEvent.PAYLOAD_END).size()).is_equal(0)
	sim.update(4.0)
	var pe := _of(GameEvent.PAYLOAD_END)
	assert_int(pe.size()).is_equal(1)
	assert_str(pe[0]["reason"]).is_equal("reflected")
	assert_int(pe[0]["seat"]).is_equal(0)
	assert_float(pe[0]["t"]).is_equal_approx(4.0, 1e-9)
	assert_float(pe[0]["immune_until"]).is_equal_approx(6.0, 1e-9)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(2)
	assert_int(l[1]["from"]).is_equal(0)
	assert_int(l[1]["to"]).is_equal(1)
	assert_bool(l[1]["reflected"]).is_true()
	assert_array(l[1]["warheads"]).is_empty()
	assert_float(l[1]["launch_t"]).is_equal_approx(4.0, 1e-9)
	assert_float(l[1]["arrive_t"]).is_equal_approx(4.5, 1e-9)
	sim.update(4.5)
	var land := _of(GameEvent.LANDED)
	assert_int(land.size()).is_equal(2)
	assert_int(land[1]["to"]).is_equal(1)
	assert_bool(land[1]["reflected"]).is_true()
	assert_bool(_players[1].active.is_empty()).is_false()


func test_three_perfect_one_good_does_not_reflect() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_judge_heads(sim, [P, P, P, G])
	var w := _of(GameEvent.WARHEAD)
	assert_int(w.size()).is_equal(4)
	assert_bool(w[3]["ok"]).is_false()
	assert_int(w[3]["k"]).is_equal(3)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(0)
	sim.update(9.99)
	assert_int(_of(GameEvent.PAYLOAD_END).size()).is_equal(0)
	sim.update(10.0)
	var pe := _of(GameEvent.PAYLOAD_END)
	assert_int(pe.size()).is_equal(1)
	assert_str(pe[0]["reason"]).is_equal("expired")
	assert_int(_players[1].landed).is_equal(1)


func test_no_more_warhead_events_after_first_failure() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_judge_heads(sim, [P, M, P, P])
	assert_int(_of(GameEvent.WARHEAD).size()).is_equal(2)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(0)


func test_good_under_overclock_is_not_perfect() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_players[0].overclock_until = 50.0
	_judge_heads(sim, [P, G, P, P])
	assert_bool(_of(GameEvent.WARHEAD)[1]["ok"]).is_false()
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(0)


func test_reflected_torpedo_absorbed_by_sender_decoy() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_give(1, DECOY)
	sim.request_fire(1, 2.2)
	_judge_heads(sim, [P, P, P, P])
	sim.update(4.5)
	var a := _of(GameEvent.ABSORBED)
	assert_int(a.size()).is_equal(1)
	assert_int(a[0]["from"]).is_equal(0)
	assert_int(a[0]["to"]).is_equal(1)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)


func test_reflected_fizzles_when_sender_eliminated() -> void:
	var sim := _sim()
	var id := _land_on_0(sim)
	_judge_heads(sim, [P, P, P, P])
	sim.on_failed(1, 3.7)
	sim.update(5.0)
	var f := _of(GameEvent.FIZZLED)
	assert_int(f.size()).is_equal(1)
	assert_int(f[0]["id"]).is_equal(id)
	assert_int(f[0]["from"]).is_equal(0)
	assert_int(f[0]["to"]).is_equal(1)
	assert_int(f[0]["reward"]).is_equal(INK)
	assert_float(f[0]["t"]).is_equal_approx(4.0, 1e-9)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(1)
	assert_int(_players[0].reflected).is_equal(1)
	assert_int(_of(GameEvent.FIRE_REFUSED).size()).is_equal(0)


func test_reflected_fizzles_when_sender_shielded() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_judge_heads(sim, [P, P, P, P])
	_players[1].immune_until = 10.0
	sim.update(5.0)
	assert_int(_of(GameEvent.FIZZLED).size()).is_equal(1)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(1)
	assert_int(_players[0].reflected).is_equal(1)


func test_reflection_on_bounty_holder_never_claims() -> void:
	var sim := _sim(1000, true)
	assert_int(sim.bounty_holder).is_equal(0)
	_land_on_0(sim)
	var before := _players[1].meter.progress
	_judge_heads(sim, [P, P, P, P])
	sim.update(8.0)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	assert_int(_players[1].meter.progress).is_equal(before)
	assert_bool(sim._pending_bounty.is_empty()).is_true()


func test_failed_warhead_claims_bounty_for_holder_at_landing() -> void:
	var sim := _sim(1000, true)
	_land_on_0(sim)
	# The lead changes after landing: the claim still names the holder at landing.
	sim.report_status(2, 100.0, 2000.0, 0.9, 10, 2.1)
	assert_int(sim.bounty_holder).is_equal(2)
	_judge_heads(sim, [P, G])
	var bc := _of(GameEvent.BOUNTY_CLAIMED)
	assert_int(bc.size()).is_equal(1)
	assert_int(bc[0]["from"]).is_equal(1)
	assert_int(bc[0]["to"]).is_equal(0)
	assert_int(bc[0]["refund"]).is_equal(30)
	assert_float(bc[0]["t"]).is_equal_approx(2.5, 1e-9)
	var w := _of(GameEvent.WARHEAD)
	assert_bool(w[1]["ok"]).is_false()
	assert_int(_players[1].meter.progress).is_equal(30)


func test_reflected_landing_on_holder_no_bounty_and_landed_stats() -> void:
	var sim := _sim(1000, true)
	# Seat 1 holds the bounty; seat 0 (trailing) fires at it, seat 1 reflects.
	sim.report_status(1, 100.0, 5000.0, 0.9, 10, 0.3)
	sim.report_status(0, 100.0, 100.0, 0.9, 10, 0.3)
	assert_int(sim.bounty_holder).is_equal(1)
	_give(0, INK)
	sim.set_target_mode(0, PlayerState.TargetMode.LOCKED, 1, 0.4)
	sim.request_fire(0, 1.1)
	sim.update(2.0)
	for i in range(4):
		sim.on_judged(1, 4 + i, P, (4 + i) * 0.5)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(1)
	sim.update(6.0)
	var land := _of(GameEvent.LANDED)
	assert_int(land.size()).is_equal(2)
	assert_int(land[1]["to"]).is_equal(0)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	# Neither the original shot nor the reflected one counts as landed.
	assert_int(_players[0].landed).is_equal(0)
	assert_int(_players[1].landed).is_equal(0)
	assert_int(_players[1].reflected).is_equal(1)


func test_too_few_notes_left_means_no_warheads() -> void:
	var sim := _sim(10)
	_give(1, INK)
	sim.request_fire(1, 2.6)  # launch beat 6 (3.0), arrive 3.5 = note 7; notes 7..9 left
	sim.update(3.5)
	var l: Array = _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(1)
	assert_array(l[0]["warheads"]).is_empty()
	sim.on_judged(0, 7, P, 3.5)
	sim.on_judged(0, 8, P, 4.0)
	sim.on_judged(0, 9, P, 4.5)
	assert_int(_of(GameEvent.WARHEAD).size()).is_equal(0)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(0)


func test_reflected_torpedo_cannot_be_reflected_again() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_judge_heads(sim, [P, P, P, P])
	sim.update(4.5)
	for i in range(9, 13):
		sim.on_judged(1, i, P, i * 0.5)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(1)
	assert_int(_of(GameEvent.WARHEAD).size()).is_equal(4)


func test_reflector_can_fire_while_reflection_pending() -> void:
	var sim := _sim()
	_land_on_0(sim)
	_judge_heads(sim, [P, P, P, P])
	_give(0, Reward.Id.SONAR_JAM)
	sim.set_target_mode(0, PlayerState.TargetMode.LOCKED, 2, 3.6)
	assert_int(sim.request_fire(0, 3.6)).is_equal(MatchSim.FIRE_OK)
