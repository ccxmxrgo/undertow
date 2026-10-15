extends GdUnitTestSuite
## 03-03 Task 2: buffs in MatchSim (03-SPEC req 6): Decoy Flare, Overclock, Ballast Patch.
## click_chart(120): 0.5 s per beat, 2 s per bar.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const INK := Reward.Id.INK_CLOUD
const DECOY := Reward.Id.DECOY_FLARE
const OVERCLOCK := Reward.Id.OVERCLOCK
const BALLAST := Reward.Id.BALLAST_PATCH

var _ev: Array = []
var _players: Array[PlayerState] = []


func _sim() -> MatchSim:
	var chart := TestCharts.click_chart(120.0, 256, 1000)
	_players = []
	for s in range(4):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	return MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), _players, ch, 11)


func _give(seat: int, id: int) -> void:
	_players[seat].meter.progress = _players[seat].meter.target
	_players[seat].meter.held = id


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_decoy_absorbs_one_disruptor_then_disarms() -> void:
	var sim := _sim()
	_give(0, DECOY)
	sim.request_fire(0, 0.2)
	var ba := _of(GameEvent.BUFF_APPLIED)
	assert_int(ba.size()).is_equal(1)
	assert_int(ba[0]["reward"]).is_equal(DECOY)
	assert_float(ba[0]["until_t"]).is_equal_approx(16.2, 1e-9)
	assert_int(_players[0].meter.held).is_equal(-1)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(2.0)
	var ab := _of(GameEvent.ABSORBED)
	assert_int(ab.size()).is_equal(1)
	assert_int(ab[0]["from"]).is_equal(1)
	assert_int(ab[0]["to"]).is_equal(0)
	assert_int(ab[0]["reward"]).is_equal(INK)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(0)
	assert_float(_players[0].decoy_until).is_equal(-INF)
	assert_float(_players[0].immune_until).is_equal(-INF)
	assert_int(_players[0].absorbed).is_equal(1)
	assert_int(_players[0].incoming_id).is_equal(-1)
	var be := _of(GameEvent.BUFF_ENDED)
	assert_int(be.size()).is_equal(1)
	assert_str(be[0]["reason"]).is_equal("used")
	# Not immune: the next disruptor lands.
	_give(2, INK)
	assert_int(sim.request_fire(2, 2.1)).is_equal(MatchSim.FIRE_OK)
	sim.update(3.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.LANDED)[0]["from"]).is_equal(2)


func test_decoy_expires_after_decoy_bars() -> void:
	var sim := _sim()
	_give(0, DECOY)
	sim.request_fire(0, 1.0)
	sim.update(16.99)
	assert_int(_of(GameEvent.BUFF_ENDED).size()).is_equal(0)
	sim.update(17.0)
	var be := _of(GameEvent.BUFF_ENDED)
	assert_int(be.size()).is_equal(1)
	assert_str(be[0]["reason"]).is_equal("expired")
	assert_float(be[0]["t"]).is_equal_approx(17.0, 1e-9)
	assert_float(_players[0].decoy_until).is_equal(-INF)


func test_decoy_expired_before_arrival_does_not_absorb() -> void:
	var sim := _sim()
	_give(0, DECOY)
	sim.request_fire(0, 0.0)  # armed until 16.0
	_give(1, INK)
	sim.request_fire(1, 15.4)  # launch 15.5, arrive 16.0
	sim.update(16.5)
	assert_int(_of(GameEvent.ABSORBED).size()).is_equal(0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)


func test_overclock_good_counts_within_window_only() -> void:
	var sim := _sim()
	_give(0, OVERCLOCK)
	sim.request_fire(0, 1.0)
	var ba := _of(GameEvent.BUFF_APPLIED)
	assert_float(ba[0]["until_t"]).is_equal_approx(9.0, 1e-9)
	assert_int(_players[0].meter.progress).is_equal(0)
	sim.on_judged(0, 2, G, 1.0)
	sim.on_judged(0, 3, G, 1.5)
	assert_int(_players[0].meter.progress).is_equal(2)
	sim.on_judged(0, 4, M, 2.0)
	assert_int(_players[0].meter.progress).is_equal(0)
	sim.on_judged(0, 5, G, 8.9)
	assert_int(_players[0].meter.progress).is_equal(1)
	sim.on_judged(0, 18, G, 9.0)
	assert_int(_players[0].meter.progress).is_equal(1)
	var be := _of(GameEvent.BUFF_ENDED)
	assert_int(be.size()).is_equal(1)
	assert_int(be[0]["reward"]).is_equal(OVERCLOCK)
	assert_str(be[0]["reason"]).is_equal("expired")


func test_overclock_overlay_good_credits() -> void:
	var sim := _sim()
	sim.on_extra_judged(0, G, 0.5)
	assert_int(_players[0].meter.progress).is_equal(0)
	sim.on_extra_judged(0, P, 0.6)
	assert_int(_players[0].meter.progress).is_equal(1)
	_give(1, OVERCLOCK)
	sim.request_fire(1, 1.0)
	sim.on_extra_judged(1, G, 1.2)
	assert_int(_players[1].meter.progress).is_equal(1)
	sim.on_extra_judged(0, M, 1.3)
	assert_int(_players[0].meter.progress).is_equal(0)


func test_ballast_amount_is_quarter_of_hull_start() -> void:
	var sim := _sim()
	_give(0, BALLAST)
	assert_int(sim.request_fire(0, 3.0)).is_equal(MatchSim.FIRE_OK)
	var ba := _of(GameEvent.BUFF_APPLIED)
	assert_int(ba.size()).is_equal(1)
	assert_float(ba[0]["amount"]).is_equal(25.0)
	assert_int(ba[0]["seat"]).is_equal(0)
	assert_int(_players[0].meter.held).is_equal(-1)
	assert_int(_of(GameEvent.FIRE_QUEUED).size()).is_equal(0)


func test_wreck_cannot_use_ballast() -> void:
	var sim := _sim()
	_give(0, BALLAST)
	sim.on_failed(0, 2.0)
	assert_int(_players[0].meter.held).is_equal(-1)
	_give(0, BALLAST)
	assert_int(sim.request_fire(0, 2.5)).is_equal(MatchSim.FIRE_NOTHING)
	assert_int(_of(GameEvent.BUFF_APPLIED).size()).is_equal(0)
	assert_str(_of(GameEvent.FIRE_REFUSED)[0]["reason"]).is_equal("nothing")


func test_elimination_loses_buffs() -> void:
	var sim := _sim()
	_give(0, DECOY)
	sim.request_fire(0, 1.0)
	_give(0, OVERCLOCK)
	sim.request_fire(0, 1.1)
	sim.on_failed(0, 2.0)
	var be := _of(GameEvent.BUFF_ENDED)
	assert_int(be.size()).is_equal(2)
	for e in be:
		assert_str(e["reason"]).is_equal("lost")
	assert_float(_players[0].decoy_until).is_equal(-INF)
	assert_float(_players[0].overclock_until).is_equal(-INF)


func test_nothing_held_is_refused() -> void:
	var sim := _sim()
	assert_int(sim.request_fire(0, 1.0)).is_equal(MatchSim.FIRE_NOTHING)
	assert_int(_of(GameEvent.FIRE_REFUSED).size()).is_equal(1)
