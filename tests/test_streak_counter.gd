extends GdUnitTestSuite
## StreakCounter tiers, visibility and popups (D-08, D-13).


func _make() -> Array:
	var c := StreakCounter.new()
	add_child(c)
	auto_free(c)
	var s := HullScore.new(JudgeConfig.new())
	c.bind(s)
	return [c, s]


func test_tiers() -> void:
	assert_int(StreakCounter.tier(4)).is_equal(0)
	assert_int(StreakCounter.tier(5)).is_equal(1)
	assert_int(StreakCounter.tier(9)).is_equal(1)
	assert_int(StreakCounter.tier(10)).is_equal(2)
	assert_int(StreakCounter.tier(49)).is_equal(2)
	assert_int(StreakCounter.tier(50)).is_equal(3)
	assert_int(StreakCounter.tier(99)).is_equal(3)
	assert_int(StreakCounter.tier(100)).is_equal(4)


func test_sizes_and_colors() -> void:
	assert_int(StreakCounter.font_size_for(1)).is_equal(Palette.SIZE_HEADING)
	for t in [2, 3, 4]:
		assert_int(StreakCounter.font_size_for(t)).is_equal(Palette.SIZE_DISPLAY)
		assert_object(StreakCounter.color_for(t)).is_equal(Palette.ACCENT)
	assert_object(StreakCounter.color_for(1)).is_equal(Palette.TEXT)


func test_visibility_and_break() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(4)
	assert_bool(c.is_counter_visible()).is_false()
	s.combo_changed.emit(5)
	assert_bool(c.is_counter_visible()).is_true()
	s.combo_changed.emit(0)
	assert_bool(c.is_counter_visible()).is_false()


func test_mouse_filter_ignore() -> void:
	var r := _make()
	assert_int((r[0] as StreakCounter).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_popup_on_milestone_and_replacement() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(10)
	s.combo_changed.emit(24)
	assert_str(c.popup_text()).is_equal("10 STREAK")
	s.combo_changed.emit(25)
	assert_str(c.popup_text()).is_equal("25 STREAK")
	s.combo_changed.emit(50)
	assert_str(c.popup_text()).is_equal("50 STREAK")
	s.combo_changed.emit(0)
	assert_bool(c.is_counter_visible()).is_false()
	assert_str(c.popup_text()).is_equal("50 STREAK")  # a break lets the popup finish


func test_numeral_fixed_width() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(99)
	assert_int(c.number_text().length()).is_equal(4)
	s.combo_changed.emit(100)
	assert_int(c.number_text().length()).is_equal(4)


func test_trench_anchor_and_caption() -> void:
	assert_float(StreakCounter.RIGHT_X).is_equal(390.0)
	assert_str(StreakCounter.CAPTION).is_equal("STREAK")
	assert_bool(absf(StreakCounter.right_x() - StreakCounter.RIGHT_X) < 3.0).is_true()
