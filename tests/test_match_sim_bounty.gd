extends GdUnitTestSuite
## 03-03 Task 3: bounty on the leader (03-SPEC req 10, D-31). 1000-note chart -> threshold 120,
## refund 25% = 30. click_chart(120): 0.5 s per beat.

const P := InputJudge.Judgment.PERFECT
const INK := Reward.Id.INK_CLOUD

var _ev: Array = []
var _players: Array[PlayerState] = []


func _sim(warheads: int = 0) -> MatchSim:
	var chart := TestCharts.click_chart(120.0, 1000, 1000)
	var cfg := VersusConfig.new()
	cfg.warhead_count = warheads
	_players = []
	for s in range(4):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	var sim := MatchSim.new(chart, cfg, JudgeConfig.new(), _players, ch, 5)
	# Seat 0 leads and holds the bounty.
	var depths := [900.0, 500.0, 400.0, 300.0]
	for s in range(4):
		sim.report_status(s, 100.0, depths[s], 0.9, 10, 0.25)
	return sim


func _give(seat: int, id: int) -> void:
	_players[seat].meter.progress = _players[seat].meter.target
	_players[seat].meter.held = id


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_leader_holds_bounty() -> void:
	var sim := _sim()
	assert_int(sim.bounty_holder).is_equal(0)
	var bm := _of(GameEvent.BOUNTY_MOVED)
	assert_int(bm.size()).is_equal(1)
	assert_int(bm[0]["from_seat"]).is_equal(-1)
	assert_int(bm[0]["to_seat"]).is_equal(0)


func test_landing_on_holder_refunds_quarter_threshold() -> void:
	var sim := _sim()
	assert_int(sim.threshold).is_equal(120)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	assert_int(_players[1].meter.progress).is_equal(0)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	sim.update(2.0)
	var bc := _of(GameEvent.BOUNTY_CLAIMED)
	assert_int(bc.size()).is_equal(1)
	assert_int(bc[0]["from"]).is_equal(1)
	assert_int(bc[0]["to"]).is_equal(0)
	assert_int(bc[0]["refund"]).is_equal(30)
	assert_float(bc[0]["t"]).is_equal_approx(2.0, 1e-9)
	assert_int(_players[1].meter.progress).is_equal(30)
	assert_int(_players[1].bounties).is_equal(1)


func test_with_warheads_claim_waits_for_reflect_chance() -> void:
	var sim := _sim(4)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(2.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	var id: int = _of(GameEvent.LANDED)[0]["id"]
	assert_bool(sim._pending_bounty.has(id)).is_true()
	assert_int(sim._pending_bounty[id]["shooter"]).is_equal(1)
	assert_int(sim._pending_bounty[id]["holder"]).is_equal(0)
	# 03-06 resolves it: claim on the first failed warhead.
	sim._claim_bounty(id, 2.6)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(1)
	assert_bool(sim._pending_bounty.has(id)).is_false()
	sim._claim_bounty(id, 2.7)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(1)


func test_drop_bounty_forgets_claim() -> void:
	var sim := _sim(4)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(2.0)
	var id: int = _of(GameEvent.LANDED)[0]["id"]
	sim._drop_bounty(id)
	sim._claim_bounty(id, 2.6)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)


func test_absorbed_shot_claims_nothing() -> void:
	var sim := _sim()
	_give(0, Reward.Id.DECOY_FLARE)
	sim.request_fire(0, 0.5)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(3.0)
	assert_int(_of(GameEvent.ABSORBED).size()).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	assert_int(_players[1].meter.progress).is_equal(0)


func test_debris_never_claims() -> void:
	var sim := _sim()
	sim.inject_fire(1, 0, Reward.Id.SILT, 1.1)
	sim.update(2.0)
	var land := _of(GameEvent.LANDED)
	assert_int(land.size()).is_equal(1)
	assert_bool(land[0]["debris"]).is_true()
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)


func test_holder_firing_never_claims() -> void:
	var sim := _sim()
	_give(0, INK)
	sim.request_fire(0, 1.1)
	sim.update(2.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.LANDED)[0]["to"]).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)


func test_refund_overflow_earns_reward_and_drops_extra() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	for i in range(100):
		sim.on_judged(1, i, P, 1.7)
	assert_int(_players[1].meter.progress).is_equal(100)
	sim.update(2.0)
	var re := _of(GameEvent.REWARD_EARNED)
	assert_int(re.size()).is_equal(1)
	assert_str(re[0]["source"]).is_equal("bounty")
	assert_int(re[0]["seat"]).is_equal(1)
	assert_int(_players[1].meter.progress).is_equal(120)
	assert_int(_players[1].meter.held).is_not_equal(-1)


func test_leader_change_moves_bounty_in_same_call() -> void:
	var sim := _sim()
	sim.update(1.0)
	var before := _of(GameEvent.BOUNTY_MOVED).size()
	sim.report_status(2, 100.0, 950.0, 0.9, 10, 1.1)
	var bm := _of(GameEvent.BOUNTY_MOVED)
	assert_int(bm.size()).is_equal(before + 1)
	assert_int(bm[bm.size() - 1]["from_seat"]).is_equal(0)
	assert_int(bm[bm.size() - 1]["to_seat"]).is_equal(2)
	assert_float(bm[bm.size() - 1]["t"]).is_equal_approx(1.1, 1e-9)
	assert_int(sim.bounty_holder).is_equal(2)


func test_tie_keeps_holder() -> void:
	var sim := _sim()
	sim.report_status(1, 100.0, 900.0, 0.9, 10, 1.0)
	assert_int(sim.bounty_holder).is_equal(0)
	assert_int(_of(GameEvent.BOUNTY_MOVED).size()).is_equal(1)


func test_dead_holder_passes_bounty_to_alive_leader() -> void:
	var sim := _sim()
	sim.on_failed(0, 3.0)
	assert_int(sim.bounty_holder).is_equal(1)
	var bm := _of(GameEvent.BOUNTY_MOVED)
	assert_int(bm[bm.size() - 1]["to_seat"]).is_equal(1)


func test_nobody_holds_before_anyone_scores() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var ps: Array[PlayerState] = [PlayerState.new(0, "A"), PlayerState.new(1, "B")]
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps,
		LoopbackChannel.new(), 1)
	sim.update(2.0)
	assert_int(sim.bounty_holder).is_equal(-1)
	sim.report_status(1, 100.0, 10.0, 1.0, 1, 2.1)
	assert_int(sim.bounty_holder).is_equal(1)


## CR-01 regression: the first warhead (on the arrival beat) judged early and below Perfect
## closes the reflect chance before the torpedo lands. The arrival must then claim at once
## instead of parking a _pending_bounty entry that nothing will ever resolve.
func test_early_non_perfect_first_warhead_claims_on_arrival() -> void:
	var sim := _sim(4)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	var launch := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(launch.size()).is_equal(1)
	var heads: Array = launch[0]["warheads"]
	assert_bool(heads.is_empty()).is_false()
	var arrive_t: float = launch[0]["arrive_t"]
	var id: int = launch[0]["id"]
	# Early Good on the first warhead, 60 ms before the torpedo arrives.
	sim.on_judged(0, int(heads[0]), InputJudge.Judgment.GOOD, arrive_t - 0.06)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	sim.update(arrive_t + 0.01)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	var bc := _of(GameEvent.BOUNTY_CLAIMED)
	assert_int(bc.size()).is_equal(1)
	assert_int(bc[0]["from"]).is_equal(1)
	assert_float(bc[0]["t"]).is_equal_approx(arrive_t, 1e-9)
	assert_bool(sim._pending_bounty.has(id)).is_false()
	assert_int(_players[1].bounties).is_equal(1)


## CR-01 companion: every warhead cleared Perfect before arrival reflects on landing and the
## bounty is dropped, not claimed.
func test_all_warheads_cleared_early_drops_bounty() -> void:
	var sim := _sim(4)
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	var launch := _of(GameEvent.TORPEDO_LAUNCH)
	var heads: Array = launch[0]["warheads"]
	var arrive_t: float = launch[0]["arrive_t"]
	var id: int = launch[0]["id"]
	for n in heads:
		sim.on_judged(0, int(n), P, arrive_t - 0.04)
	sim.update(arrive_t + 0.01)
	assert_int(_of(GameEvent.REFLECTED).size()).is_equal(1)
	assert_int(_of(GameEvent.BOUNTY_CLAIMED).size()).is_equal(0)
	assert_bool(sim._pending_bounty.has(id)).is_false()
