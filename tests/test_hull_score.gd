extends GdUnitTestSuite

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

var _failed_count := 0


func _make(no_fail: bool = false) -> HullScore:
	var h := HullScore.new(JudgeConfig.new())
	h.no_fail = no_fail
	_failed_count = 0
	h.failed.connect(func() -> void: _failed_count += 1)
	return h


func _hit(h: HullScore, j: int, n: int = 1) -> void:
	for i in range(n):
		h.on_judged(0, 0, j, 0.0)


func test_miss_costs_eight_perfect_restores_quarter() -> void:
	var h := _make()
	_hit(h, M)
	assert_float(h.hull).is_equal(92.0)
	_hit(h, P)
	assert_float(h.hull).is_equal(92.25)


## 03-SPEC req 14: a quarter per Perfect, so 32 Perfects undo one Miss.
func test_thirty_two_perfects_undo_a_miss() -> void:
	var h := _make()
	_hit(h, M)
	assert_float(h.hull).is_equal(92.0)
	_hit(h, P, 31)
	assert_float(h.hull).is_equal(99.75)
	_hit(h, P)
	assert_float(h.hull).is_equal(100.0)


func test_perfect_at_full_stays_capped_and_good_is_neutral() -> void:
	var h := _make()
	_hit(h, P)
	assert_float(h.hull).is_equal(100.0)
	_hit(h, M)
	_hit(h, G)
	assert_float(h.hull).is_equal(92.0)


func test_thirteen_misses_fail_once() -> void:
	var h := _make()
	_hit(h, M, 13)
	assert_float(h.hull).is_less_equal(0.0)
	assert_int(_failed_count).is_equal(1)
	_hit(h, M, 3)
	assert_int(_failed_count).is_equal(1)


func test_no_fail_floors_hull_without_failing() -> void:
	var h := _make(true)
	_hit(h, M, 14)
	assert_float(h.hull).is_equal(0.0)
	assert_int(_failed_count).is_equal(0)
	assert_bool(h.no_fail_used).is_true()
	assert_bool(h.is_failed).is_false()


func test_combo_and_streak_rules() -> void:
	var h := _make()
	_hit(h, P, 3)
	_hit(h, G)
	assert_int(h.combo).is_equal(4)
	assert_int(h.perfect_streak).is_equal(0)
	_hit(h, P, 2)
	assert_int(h.perfect_streak).is_equal(2)
	h.on_stray(1)
	assert_int(h.combo).is_equal(0)
	assert_int(h.perfect_streak).is_equal(0)
	assert_int(h.max_combo).is_equal(6)
	_hit(h, P, 2)
	_hit(h, M)
	assert_int(h.combo).is_equal(0)
	assert_int(h.perfect_streak).is_equal(0)
	assert_int(h.max_perfect_streak).is_equal(3)


func test_stray_does_no_hull_damage_by_default() -> void:
	var h := _make()
	h.on_stray(0)
	assert_float(h.hull).is_equal(100.0)


func test_multiplier_steps_and_cap() -> void:
	var h := _make()
	assert_int(h.multiplier()).is_equal(1)
	_hit(h, G, 9)
	assert_int(h.multiplier()).is_equal(1)
	_hit(h, G)
	assert_int(h.multiplier()).is_equal(2)
	_hit(h, G, 10)
	assert_int(h.multiplier()).is_equal(3)
	_hit(h, G, 10)
	assert_int(h.multiplier()).is_equal(4)
	_hit(h, G, 50)
	assert_int(h.multiplier()).is_equal(4)


func test_score_uses_multiplier_at_hit_time_and_depth() -> void:
	var h := _make()
	_hit(h, P, 10)  # ten hits at x1 = 1000
	assert_int(h.score).is_equal(1000)
	_hit(h, P)  # combo is 10 -> x2
	assert_int(h.score).is_equal(1200)
	h.on_sustain_tick(0)  # +10 * 2
	assert_int(h.score).is_equal(1220)
	assert_float(h.depth()).is_equal_approx(12.2, 0.0001)


func test_connect_judge_wires_signals() -> void:
	var chart := ChartData.new()
	chart.add_note(0, 1.0, 0.3)
	chart.finalize()
	var j := InputJudge.new(chart, JudgeConfig.new())
	var h := _make()
	h.connect_judge(j)
	j.press(0, 1.0)
	j.tick(1.3)
	j.release(0, 1.3)
	assert_int(h.perfect_count).is_equal(1)
	assert_int(h.sustain_ticks).is_equal(3)
	j.press(2, 5.0)
	assert_int(h.stray_count).is_equal(1)
