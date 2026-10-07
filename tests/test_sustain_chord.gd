extends GdUnitTestSuite

var _judged: Array = []
var _stray: Array = []
var _ticks: Array = []
var _ends: Array = []


func _make(notes: Array) -> InputJudge:
	var chart := ChartData.new()
	for n in notes:
		chart.add_note(n[0], n[1], n[2] if n.size() > 2 else 0.0)
	chart.finalize()
	var j := InputJudge.new(chart, JudgeConfig.new())
	_judged = []
	_stray = []
	_ticks = []
	_ends = []
	j.judged.connect(func(lane: int, idx: int, jd: int, err: float) -> void: _judged.append([lane, idx, jd, err]))
	j.stray.connect(func(lane: int) -> void: _stray.append(lane))
	j.sustain_tick.connect(func(lane: int) -> void: _ticks.append(lane))
	j.sustain_end.connect(func(lane: int, c: bool) -> void: _ends.append([lane, c]))
	return j


func _judgment_for_lane(lane: int) -> int:
	for e in _judged:
		if e[0] == lane:
			return e[2]
	return -1


func test_chord_lanes_are_independent() -> void:
	var j := _make([[0, 2.0], [1, 2.0], [2, 2.0]])
	j.press(0, 2.0)
	assert_int(_judged.size()).is_equal(1)
	j.tick(2.0701)
	assert_int(_judged.size()).is_equal(3)
	assert_int(_judgment_for_lane(0)).is_equal(InputJudge.Judgment.PERFECT)
	assert_int(_judgment_for_lane(1)).is_equal(InputJudge.Judgment.MISS)
	assert_int(_judgment_for_lane(2)).is_equal(InputJudge.Judgment.MISS)


func test_sustain_full_hold_emits_ten_ticks_and_completes() -> void:
	var j := _make([[0, 1.0, 1.0]])
	j.press(0, 1.0)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.PERFECT)
	j.tick(1.5)
	assert_int(_ticks.size()).is_equal(5)
	j.tick(2.0)
	assert_int(_ticks.size()).is_equal(10)
	j.release(0, 2.0)
	assert_int(_ticks.size()).is_equal(10)
	assert_array(_ends).is_equal([[0, true]])


func test_sustain_tick_count_independent_of_tick_cadence() -> void:
	var a := _make([[0, 1.0, 1.0]])
	a.press(0, 1.0)
	var t := 1.0
	while t < 2.0:
		t += 1.0 / 144.0
		a.tick(t)
	a.release(0, 2.0)
	var fast := _ticks.size()
	var b := _make([[0, 1.0, 1.0]])
	b.press(0, 1.0)
	b.tick(1.33)
	b.tick(2.0)
	b.release(0, 2.0)
	assert_int(fast).is_equal(10)
	assert_int(_ticks.size()).is_equal(10)


func test_early_release_ends_quietly() -> void:
	var j := _make([[0, 1.0, 1.0]])
	j.press(0, 1.0)
	j.release(0, 1.5)
	assert_array(_ends).is_equal([[0, false]])
	assert_int(_ticks.size()).is_equal(5)
	j.tick(3.0)
	assert_int(_ticks.size()).is_equal(5)
	assert_int(_judged.size()).is_equal(1)  # no MISS for the tail


func test_release_within_forgive_window_counts_full() -> void:
	var j := _make([[0, 1.0, 1.0]])
	j.press(0, 1.0)
	j.release(0, 1.91)
	assert_array(_ends).is_equal([[0, true]])
	assert_int(_ticks.size()).is_equal(10)


func test_missed_sustain_head_gives_miss_and_no_ticks() -> void:
	var j := _make([[0, 1.0, 1.0]])
	j.tick(1.0701)
	assert_int(_judged.size()).is_equal(1)
	assert_int(_judged[0][2]).is_equal(InputJudge.Judgment.MISS)
	j.tick(3.0)
	assert_int(_ticks.size()).is_equal(0)
	assert_int(_ends.size()).is_equal(0)


func test_stray_press_with_no_candidate() -> void:
	var j := _make([[0, 1.0]])
	j.press(2, 1.0)
	assert_array(_stray).is_equal([2])
	assert_int(_judged.size()).is_equal(0)


func test_release_without_hold_is_ignored() -> void:
	var j := _make([[0, 1.0]])
	j.release(0, 1.0)
	j.release(3, 5.0)
	assert_int(_ends.size()).is_equal(0)
	assert_int(_ticks.size()).is_equal(0)


func test_unreleased_hold_auto_completes_after_tail() -> void:
	var j := _make([[0, 1.0, 0.5]])
	j.press(0, 1.0)
	j.tick(1.5)
	assert_bool(j.is_finished()).is_false()
	j.tick(1.5701)
	assert_array(_ends).is_equal([[0, true]])
	assert_int(_ticks.size()).is_equal(5)
	assert_bool(j.is_finished()).is_true()
	assert_int(j.remaining_unjudged()).is_equal(0)
