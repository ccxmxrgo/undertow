extends GdUnitTestSuite

var _judged: Array = []
var _stray: Array = []


func _make(notes: Array) -> InputJudge:
	var chart := ChartData.new()
	for n in notes:
		chart.add_note(n[0], n[1], n[2] if n.size() > 2 else 0.0)
	chart.finalize()
	var j := InputJudge.new(chart, JudgeConfig.new())
	_judged = []
	_stray = []
	j.judged.connect(func(lane: int, idx: int, jd: int, err: float) -> void: _judged.append([lane, idx, jd, err]))
	j.stray.connect(func(lane: int) -> void: _stray.append(lane))
	return j


func test_press_035_late_is_perfect() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 1.035)
	assert_int(_judged.size()).is_equal(1)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.PERFECT)


func test_press_just_past_035_is_good() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 1.0351)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.GOOD)


func test_press_070_late_is_good() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 1.070)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.GOOD)


func test_press_070_early_is_good() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 0.930)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.GOOD)


func test_press_100_early_is_miss_on_that_note() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 0.900)
	assert_int(_judged.size()).is_equal(1)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.MISS)
	assert_int(_judged[0][1]).is_equal(0)
	assert_int(_stray.size()).is_equal(0)


func test_press_beyond_early_window_is_stray() -> void:
	var j := _make([[0, 1.0]])
	j.press(0, 0.899)
	assert_int(_judged.size()).is_equal(0)
	assert_array(_stray).is_equal([0])


func test_tick_marks_unjudged_note_miss_after_good_window() -> void:
	var j := _make([[0, 1.0]])
	j.tick(1.0699)
	assert_int(_judged.size()).is_equal(0)
	j.tick(1.0701)
	assert_int(_judged.size()).is_equal(1)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.MISS)


func test_error_sign_positive_is_late() -> void:
	var j := _make([[1, 2.0]])
	j.press(1, 2.02)
	assert_float(_judged[0][3]).is_equal_approx(0.02, 1e-9)


func test_stray_in_empty_lane_does_not_affect_other_lanes() -> void:
	var j := _make([[0, 1.0], [1, 1.0]])
	j.press(2, 1.0)
	assert_array(_stray).is_equal([2])
	assert_int(_judged.size()).is_equal(0)
	j.press(0, 1.0)
	j.press(1, 1.0)
	assert_int(_judged.size()).is_equal(2)


func test_late_press_after_window_does_not_hit_expired_note() -> void:
	var j := _make([[0, 1.0], [0, 2.0]])
	j.press(0, 1.5)  # note 0 expired -> MISS; note at 2.0 is 0.5 away -> stray
	assert_int(_judged.size()).is_equal(1)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.MISS)
	assert_array(_stray).is_equal([0])
