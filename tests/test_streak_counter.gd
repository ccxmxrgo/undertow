extends GdUnitTestSuite
## StreakCounter on the left console (02.2-12, UI-SPEC 7.3, 11): always-visible instrument
## numeral, colour tiers, fixed-width box, pop on every 10, milestone popup + sparks + rail flash.

var _saved_low := false
var _saved_rm := false


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm


class FakeRails:
	extends Highway
	var flashes: Array = []

	func flash_rails(alpha: float, dur: float) -> void:
		flashes.append([alpha, dur])


func _make() -> Array:
	var c := StreakCounter.new()
	add_child(c)
	auto_free(c)
	var s := HullScore.new(JudgeConfig.new())
	c.bind(s)
	return [c, s]


func test_tiers() -> void:
	assert_int(StreakCounter.tier(0)).is_equal(0)
	assert_int(StreakCounter.tier(9)).is_equal(0)
	assert_int(StreakCounter.tier(10)).is_equal(1)
	assert_int(StreakCounter.tier(49)).is_equal(1)
	assert_int(StreakCounter.tier(50)).is_equal(2)
	assert_int(StreakCounter.tier(99)).is_equal(2)
	assert_int(StreakCounter.tier(100)).is_equal(3)


func test_sizes_and_colors() -> void:
	for t in [0, 1, 2, 3]:
		assert_int(StreakCounter.font_size_for(t)).is_equal(Palette.SIZE_DISPLAY)
	assert_object(StreakCounter.color_for(0)).is_equal(Palette.TEXT_LO)
	assert_object(StreakCounter.color_for(1)).is_equal(Palette.TEXT_HI)
	assert_object(StreakCounter.color_for(2)).is_equal(Palette.SONAR_PALE)
	assert_object(StreakCounter.color_for(3)).is_equal(Palette.SONAR_PALE)
	assert_object(StreakCounter.color_for_streak(7)).is_equal(Palette.TEXT_LO)
	assert_object(StreakCounter.color_for_streak(88)).is_equal(Palette.SONAR_PALE)
	assert_bool(StreakCounter.glows(99)).is_false()
	assert_bool(StreakCounter.glows(100)).is_true()


func test_always_visible_and_break() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	assert_bool(c.is_counter_visible()).is_true()
	s.combo_changed.emit(4)
	assert_bool(c.is_counter_visible()).is_true()
	s.combo_changed.emit(0)
	assert_bool(c.is_counter_visible()).is_true()
	assert_str(c.number_text().strip_edges()).is_equal("0")


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
	assert_str(c.popup_text()).is_equal("50 STREAK")  # a break lets the popup finish
	c._process(0.8)
	assert_str(c.popup_text()).is_equal("")


func test_numeral_fixed_width() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	var box := c.numeral_box()
	for n in [0, 7, 88, 999, 9999]:
		s.combo_changed.emit(n)
		assert_int(c.number_text().length()).is_equal(4)
		assert_object(c.numeral_box()).is_equal(box)
	assert_float(box.end.x).is_equal(368.0)
	assert_float(box.position.x).is_less_equal(146.0)


func test_console_geometry_and_caption() -> void:
	assert_float(StreakCounter.RIGHT_X).is_equal(368.0)
	assert_float(StreakCounter.right_x()).is_equal(368.0)
	assert_float(StreakCounter.NUMBER_BASE_Y).is_equal(736.0)
	assert_object(StreakCounter.CAPTION_POS).is_equal(Vector2(48.0, 644.0))
	assert_float(StreakCounter.POPUP_CX).is_equal(208.0)
	assert_float(StreakCounter.POPUP_BASE_Y).is_equal(584.0)
	assert_str(StreakCounter.CAPTION).is_equal("STREAK")


func test_pop_on_each_ten() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(9)
	assert_float(c.numeral_scale()).is_equal(1.0)
	s.combo_changed.emit(10)
	c._process(0.04)
	assert_float(c.numeral_scale()).is_greater(1.0)
	assert_float(c.numeral_scale()).is_less_equal(1.08 + 0.001)
	c._process(0.05)
	assert_float(c.numeral_scale()).is_equal(1.0)
	s.combo_changed.emit(11)
	c._process(0.04)
	assert_float(c.numeral_scale()).is_equal(1.0)  # only multiples of ten pop
	s.combo_changed.emit(20)
	s.combo_changed.emit(0)  # a break resets instantly
	assert_float(c.numeral_scale()).is_equal(1.0)


func test_no_pop_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(10)
	c._process(0.04)
	assert_float(c.numeral_scale()).is_equal(1.0)


func test_milestone_sparks_and_rail_flash() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	var rails: FakeRails = auto_free(FakeRails.new())
	c.highway = rails
	assert_dict(c.effect_counts()).is_equal({"milestone_sparks": 24})
	assert_bool(c.is_in_group(UiKit.FX_GROUP)).is_true()
	s.combo_changed.emit(10)
	assert_int(c.sparks_fired()).is_equal(1)
	assert_object(c.sparks().position).is_equal(StreakCounter.SPARK_ORIGIN)
	assert_int(c.sparks().amount).is_equal(24)
	assert_array(rails.flashes).is_equal([[0.6, 0.16]])
	s.combo_changed.emit(11)
	assert_int(c.sparks_fired()).is_equal(1)
	Settings.low_effects = true
	c.apply_effect_settings()
	assert_dict(c.effect_counts()).is_equal({"milestone_sparks": 8})
	s.combo_changed.emit(25)
	assert_int(c.sparks().amount).is_equal(8)
	assert_int(c.sparks_fired()).is_equal(2)


func test_reduce_motion_fades_text_only() -> void:
	Settings.reduce_motion = true
	var r := _make()
	var c: StreakCounter = r[0]
	var s: HullScore = r[1]
	assert_dict(c.effect_counts()).is_equal({"milestone_sparks": 0})
	s.combo_changed.emit(10)
	assert_str(c.popup_text()).is_equal("10 STREAK")
	assert_int(c.sparks_fired()).is_equal(0)


func test_keepout_shapes_cover_the_drawn_areas() -> void:
	var r := _make()
	var c: StreakCounter = r[0]
	var shapes := c.keepout_shapes()
	assert_int(shapes.size()).is_equal(3)
	for shape in shapes:
		for p in shape:
			assert_bool(p.x >= 0.0 and p.x <= 400.0).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(300.0, 700.0), shapes[0])).is_true()
