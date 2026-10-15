extends GdUnitTestSuite
## 03-SPEC reqs 1 and 2, D-30, D-31: the reward meter (RewardMeter) contract.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

var _earned: Array = []


func _make(t: int = 120) -> RewardMeter:
	var m := RewardMeter.new(t, RewardBag.new(77))
	_earned = []
	m.reward_earned.connect(func(id: int, source: String) -> void: _earned.append([id, source]))
	return m


func _hit(m: RewardMeter, j: int, n: int = 1, overclock: bool = false) -> void:
	for i in range(n):
		m.on_judgment(j, overclock)


func test_threshold_values() -> void:
	assert_int(RewardMeter.threshold(1000, 0.12)).is_equal(120)
	assert_int(RewardMeter.threshold(400, 0.12)).is_equal(48)
	assert_int(RewardMeter.threshold(396, 0.12)).is_equal(48)
	assert_int(RewardMeter.threshold(569, 0.12)).is_equal(69)
	assert_int(RewardMeter.threshold(0, 0.12)).is_equal(1)
	assert_int(RewardMeter.threshold(100, 0.07)).is_equal(7)


func test_119_perfects_earn_nothing_120th_earns_once() -> void:
	var m := _make()
	_hit(m, P, 119)
	assert_int(m.held).is_equal(-1)
	assert_int(m.progress).is_equal(119)
	assert_int(_earned.size()).is_equal(0)
	_hit(m, P)
	assert_int(m.held).is_not_equal(-1)
	assert_int(_earned.size()).is_equal(1)
	assert_str(_earned[0][1]).is_equal("meter")
	assert_int(m.progress).is_equal(120)


func test_miss_resets_progress() -> void:
	var m := _make()
	_hit(m, P, 50)
	_hit(m, M)
	assert_int(m.progress).is_equal(0)


func test_good_neither_adds_nor_resets() -> void:
	var m := _make()
	_hit(m, P, 10)
	_hit(m, G, 5)
	assert_int(m.progress).is_equal(10)


func test_good_with_overclock_adds_one() -> void:
	var m := _make()
	_hit(m, P, 10)
	_hit(m, G, 1, true)
	assert_int(m.progress).is_equal(11)


func test_stray_changes_nothing() -> void:
	# A stray press never reaches the meter (no on_judgment call); state is untouched.
	var m := _make()
	_hit(m, P, 7)
	assert_int(m.progress).is_equal(7)
	assert_int(m.held).is_equal(-1)


func test_held_reward_blocks_second_reward() -> void:
	var m := _make()
	_hit(m, P, 120)
	var first := m.held
	_hit(m, P, 50)
	assert_int(m.held).is_equal(first)
	assert_int(m.progress).is_equal(120)
	assert_int(_earned.size()).is_equal(1)


func test_use_returns_held_and_needs_full_threshold_again() -> void:
	var m := _make()
	_hit(m, P, 120)
	var first := m.held
	assert_int(m.use()).is_equal(first)
	assert_int(m.held).is_equal(-1)
	assert_int(m.progress).is_equal(0)
	_hit(m, P, 119)
	assert_int(m.held).is_equal(-1)
	_hit(m, P)
	assert_int(m.held).is_not_equal(-1)
	assert_int(_earned.size()).is_equal(2)


func test_use_with_nothing_held_returns_minus_one() -> void:
	var m := _make()
	assert_int(m.use()).is_equal(-1)


func test_miss_while_holding_keeps_reward_and_resets_progress() -> void:
	var m := _make()
	_hit(m, P, 120)
	var first := m.held
	_hit(m, M)
	assert_int(m.held).is_equal(first)
	assert_int(m.progress).is_equal(0)


func test_queue_prize_waits_and_drops_into_slot() -> void:
	var m := _make()
	_hit(m, P, 120)
	var first := m.held
	assert_bool(m.queue_prize(Reward.Id.OVERCLOCK)).is_true()
	assert_int(m.queued).is_equal(Reward.Id.OVERCLOCK)
	assert_bool(m.queue_prize(Reward.Id.DECOY_FLARE)).is_false()
	assert_int(m.use()).is_equal(first)
	assert_int(m.held).is_equal(Reward.Id.OVERCLOCK)
	assert_int(m.queued).is_equal(-1)


func test_queue_prize_with_empty_slot_goes_straight_in() -> void:
	var m := _make()
	assert_bool(m.queue_prize(Reward.Id.INK_CLOUD)).is_true()
	assert_int(m.held).is_equal(Reward.Id.INK_CLOUD)
	assert_int(m.queued).is_equal(-1)
	assert_int(_earned.size()).is_equal(1)
	assert_str(_earned[0][1]).is_equal("duel")


func test_add_refund_adds_progress() -> void:
	var m := _make()
	assert_bool(m.add_refund(30)).is_false()
	assert_int(m.progress).is_equal(30)


func test_add_refund_overflow_earns_and_drops_extra() -> void:
	var m := _make()
	_hit(m, P, 100)
	assert_bool(m.add_refund(30)).is_true()
	assert_int(m.held).is_not_equal(-1)
	assert_int(m.progress).is_equal(120)
	assert_int(_earned.size()).is_equal(1)
	assert_str(_earned[0][1]).is_equal("bounty")


func test_add_refund_while_holding_changes_nothing() -> void:
	var m := _make()
	_hit(m, P, 120)
	m.use()
	_hit(m, P, 120)
	var held := m.held
	m.on_judgment(M)
	assert_bool(m.add_refund(30)).is_false()
	assert_int(m.progress).is_equal(0)
	assert_int(m.held).is_equal(held)


func test_credit_adds_like_perfect() -> void:
	var m := _make(10)
	m.credit(9)
	assert_int(m.progress).is_equal(9)
	m.credit(5)
	assert_int(m.held).is_not_equal(-1)
	assert_int(m.progress).is_equal(10)
	assert_int(_earned.size()).is_equal(1)


func test_reset_lost_clears_everything() -> void:
	var m := _make()
	_hit(m, P, 120)
	m.queue_prize(Reward.Id.OVERCLOCK)
	m.reset_lost()
	assert_int(m.held).is_equal(-1)
	assert_int(m.queued).is_equal(-1)
	assert_int(m.progress).is_equal(0)


func test_disabled_meter_ignores_judgments() -> void:
	var m := _make()
	m.enabled = false
	_hit(m, P, 200)
	assert_int(m.progress).is_equal(0)
	assert_int(m.held).is_equal(-1)


func test_progress_changed_emitted() -> void:
	var m := _make()
	var seen: Array = []
	m.progress_changed.connect(func(v: int, t: int) -> void: seen.append([v, t]))
	_hit(m, P, 2)
	_hit(m, M)
	assert_array(seen).is_equal([[1, 120], [2, 120], [0, 120]])
