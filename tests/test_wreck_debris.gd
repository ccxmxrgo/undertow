extends GdUnitTestSuite
## 03-06 Task 3: wreck debris (MATCH-03, TORP-06, D-24, D-25). click_chart(120, 200): note i at
## i * 0.5 s, threshold ceil(0.12 x 200) = 24. Depths: seat 0 900 (leader, bounty), 1 500,
## 2 400, 3 300. Seat 3 becomes the wreck.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const INK := Reward.Id.INK_CLOUD
const SILT := Reward.Id.SILT
const GROAN := Reward.Id.GROAN

var _ev: Array = []
var _players: Array[PlayerState] = []


func _sim(seats: int = 4) -> MatchSim:
	var chart := TestCharts.click_chart(120.0, 200, 1000)
	_players = []
	for s in range(seats):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), _players, ch, 11)
	var depths := [900.0, 500.0, 400.0, 300.0]
	for s in range(seats):
		sim.report_status(s, 100.0, depths[s], 0.9, 10, 0.01)
	return sim


func _give(seat: int, id: int) -> void:
	_players[seat].meter.progress = _players[seat].meter.target
	_players[seat].meter.held = id


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _debris_meter() -> Array:
	return _of(GameEvent.METER).filter(func(e: Dictionary) -> bool: return e["debris"])


## Seat judges notes first..first+n-1 all Perfect at their note times.
func _fill(sim: MatchSim, seat: int, first: int, n: int) -> void:
	for i in range(first, first + n):
		sim.on_judged(seat, i, P, i * 0.5)


func test_elimination_loses_reward_queue_and_buffs() -> void:
	var sim := _sim()
	_give(2, INK)
	_players[2].meter.queued = Reward.Id.SONAR_JAM
	_give(1, Reward.Id.DECOY_FLARE)
	sim.request_fire(1, 0.1)
	_players[2].decoy_until = _players[1].decoy_until
	_players[2].overclock_until = 20.0
	sim.on_failed(2, 1.0)
	assert_int(_of(GameEvent.IMPLODED).size()).is_equal(1)
	assert_int(_players[2].meter.held).is_equal(-1)
	assert_int(_players[2].meter.queued).is_equal(-1)
	var lost := _of(GameEvent.BUFF_ENDED).filter(
		func(e: Dictionary) -> bool: return e["seat"] == 2 and e["reason"] == "lost")
	assert_int(lost.size()).is_equal(2)
	var dm := _debris_meter()
	assert_int(dm.size()).is_equal(1)
	assert_int(dm[0]["seat"]).is_equal(2)
	assert_int(dm[0]["progress"]).is_equal(0)
	assert_int(dm[0]["held"]).is_equal(-1)
	assert_int(dm[0]["threshold"]).is_equal(24)


func test_perfects_fill_miss_resets_good_does_nothing() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 5)
	assert_int(_debris_meter().back()["progress"]).is_equal(5)
	var n := _debris_meter().size()
	sim.on_judged(3, 6, G, 3.0)
	assert_int(_debris_meter().size()).is_equal(n)
	sim.on_judged(3, 7, M, 3.5)
	assert_int(_debris_meter().back()["progress"]).is_equal(0)
	# The bag meter of a wreck never moves.
	assert_int(_players[3].meter.progress).is_equal(0)
	_fill(sim, 3, 8, 24)
	var last: Dictionary = _debris_meter().back()
	assert_int(last["progress"]).is_equal(24)
	assert_int(last["held"]).is_equal(SILT)
	var earned := _of(GameEvent.REWARD_EARNED)
	assert_int(earned.size()).is_equal(1)
	assert_int(earned[0]["seat"]).is_equal(3)
	assert_int(earned[0]["reward"]).is_equal(SILT)
	assert_str(earned[0]["source"]).is_equal("debris")
	assert_int(_players[3].meter.held).is_equal(-1)


func test_debris_alternates_and_stops_after_cap() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 24)  # 0.5..12.0
	assert_int(sim.request_fire(3, 12.1)).is_equal(MatchSim.FIRE_OK)
	sim.update(13.0)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(1)
	assert_bool(l[0]["debris"]).is_true()
	assert_int(l[0]["reward"]).is_equal(SILT)
	assert_int(l[0]["from"]).is_equal(3)
	assert_int(l[0]["to"]).is_equal(0)
	assert_array(l[0]["warheads"]).is_empty()
	assert_bool(l[0]["reflected"]).is_false()
	assert_int(_players[3].debris_used).is_equal(1)
	var land := _of(GameEvent.LANDED)
	assert_int(land.size()).is_equal(1)
	assert_bool(land[0]["debris"]).is_true()
	assert_float(land[0]["end_t"] - land[0]["active_start"]).is_equal_approx(2.0, 1e-9)
	sim.update(15.0)
	var pe := _of(GameEvent.PAYLOAD_END)
	assert_int(pe.size()).is_equal(1)
	assert_float(pe[0]["immune_until"]).is_equal_approx(17.0, 1e-9)
	_fill(sim, 3, 25, 24)  # 12.5..24.0
	assert_int(_debris_meter().back()["held"]).is_equal(GROAN)
	assert_int(sim.request_fire(3, 24.1)).is_equal(MatchSim.FIRE_OK)
	sim.update(24.5)
	l = _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(2)
	assert_int(l[1]["reward"]).is_equal(GROAN)
	assert_int(_players[3].debris_used).is_equal(2)
	var n := _debris_meter().size()
	_fill(sim, 3, 49, 30)
	assert_int(_debris_meter().size()).is_equal(n)
	assert_int(sim.request_fire(3, 40.0)).is_equal(MatchSim.FIRE_NOTHING)
	# Wrecks never draw from the bag and never earn bag rewards.
	assert_int(_players[3].meter.held).is_equal(-1)
	# Debris landings never count as landed.
	assert_int(_players[3].landed).is_equal(0)


func test_debris_at_shielded_leader_refused_and_kept() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 24)
	_players[0].immune_until = 30.0
	assert_int(sim.request_fire(3, 12.1)).is_equal(MatchSim.FIRE_SHIELDED)
	assert_str(_of(GameEvent.FIRE_REFUSED)[0]["reason"]).is_equal("shielded")
	assert_int(_debris_meter().back()["held"]).is_equal(SILT)
	sim.update(14.0)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(0)
	assert_int(_players[3].debris_used).is_equal(0)


func test_decoy_on_leader_absorbs_debris() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_give(0, Reward.Id.DECOY_FLARE)
	sim.request_fire(0, 0.3)
	_fill(sim, 3, 1, 24)
	sim.request_fire(3, 12.1)
	sim.update(14.0)
	var a := _of(GameEvent.ABSORBED)
	assert_int(a.size()).is_equal(1)
	assert_int(a[0]["from"]).is_equal(3)
	assert_int(a[0]["reward"]).is_equal(SILT)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(0)


func test_target_is_leader_never_lowest_living() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	sim.report_status(1, 100.0, 2000.0, 0.9, 10, 0.3)
	_fill(sim, 3, 1, 24)
	sim.request_fire(3, 12.1)
	var q := _of(GameEvent.FIRE_QUEUED)
	assert_int(q.size()).is_equal(1)
	assert_int(q[0]["to"]).is_equal(1)
	assert_int(q[0]["to"]).is_not_equal(2)


func test_debris_on_bounty_holder_claims_nothing() -> void:
	var sim := _sim()
	assert_int(sim.bounty_holder).is_equal(0)
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 24)
	sim.request_fire(3, 12.1)
	sim.update(20.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	assert_bool(sim._pending_bounty.is_empty()).is_true()


func test_debris_never_collides() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 24)
	# A debris launch and a normal disruptor from the leader at another seat share the beat.
	_give(0, INK)
	sim.set_target_mode(0, PlayerState.TargetMode.LOCKED, 1, 12.05)
	sim.request_fire(3, 12.1)
	sim.request_fire(0, 12.1)
	sim.update(14.0)
	assert_int(_of(GameEvent.COLLISION).size()).is_equal(0)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(2)


func test_no_living_sub_is_no_target() -> void:
	var sim := _sim(2)
	sim.on_failed(1, 0.2)
	_fill(sim, 1, 1, 24)
	sim.on_failed(0, 12.05)
	assert_int(sim.request_fire(1, 12.1)).is_equal(MatchSim.FIRE_NO_TARGET)
	assert_str(_of(GameEvent.FIRE_REFUSED).back()["reason"]).is_equal("no_target")


func test_second_press_while_debris_pending() -> void:
	var sim := _sim()
	sim.on_failed(3, 0.2)
	_fill(sim, 3, 1, 24)
	assert_int(sim.request_fire(3, 12.1)).is_equal(MatchSim.FIRE_OK)
	assert_int(sim.request_fire(3, 12.2)).is_equal(MatchSim.FIRE_PENDING)
