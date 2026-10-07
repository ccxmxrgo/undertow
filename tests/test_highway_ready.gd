extends GdUnitTestSuite
## Lane palette, outline-only shapes, ready predicate and receptor pulse (Plan 01.1-02).


func test_lane_colors_exact_and_wrap() -> void:
	assert_int(Palette.LANE_COLORS.size()).is_equal(4)
	assert_that(Palette.LANE_COLORS[0]).is_equal(Color("22D3EE"))
	assert_that(Palette.LANE_COLORS[1]).is_equal(Color("FBBF24"))
	assert_that(Palette.LANE_COLORS[2]).is_equal(Color("F472B6"))
	assert_that(Palette.LANE_COLORS[3]).is_equal(Color("A3E635"))
	for i in range(4):
		assert_that(Palette.lane_color(i)).is_equal(Palette.LANE_COLORS[i])
	assert_that(Palette.lane_color(5)).is_equal(Palette.LANE_COLORS[1])
	assert_that(Palette.lane_color(-1)).is_equal(Palette.LANE_COLORS[3])


func test_dim_keeps_alpha_and_scales_rgb() -> void:
	assert_float(Palette.NOTE_DIM).is_equal(0.60)
	var c := Color(0.5, 0.8, 1.0, 0.7)
	var d := Palette.dim(c)
	assert_float(d.r).is_equal_approx(0.30, 0.0001)
	assert_float(d.g).is_equal_approx(0.48, 0.0001)
	assert_float(d.b).is_equal_approx(0.60, 0.0001)
	assert_float(d.a).is_equal(c.a)
	assert_float(Palette.dim(Palette.lane_color(0)).a).is_equal(1.0)


func test_core_colors_unchanged() -> void:
	assert_that(Palette.DESTRUCTIVE).is_equal(Color("FF4A3D"))
	assert_that(Palette.ACCENT).is_equal(Color("39FF14"))


func test_shape_mapping_unchanged() -> void:
	assert_int(NoteShape.kind_for_lane(0)).is_equal(NoteShape.Kind.DIAMOND)
	assert_int(NoteShape.kind_for_lane(1)).is_equal(NoteShape.Kind.CIRCLE)
	assert_int(NoteShape.kind_for_lane(2)).is_equal(NoteShape.Kind.TRIANGLE)
	assert_int(NoteShape.kind_for_lane(3)).is_equal(NoteShape.Kind.SQUARE)


func test_note_is_ready_boundaries() -> void:
	var gw := 0.070
	assert_bool(Highway.note_is_ready(0.0, gw)).is_true()
	assert_bool(Highway.note_is_ready(gw, gw)).is_true()
	assert_bool(Highway.note_is_ready(-gw, gw)).is_true()
	assert_bool(Highway.note_is_ready(gw + 0.001, gw)).is_false()
	assert_bool(Highway.note_is_ready(-(gw + 0.001), gw)).is_false()
	assert_bool(Highway.note_is_ready(NAN, gw)).is_false()


func test_setup_stores_good_window_with_fallback() -> void:
	var chart := TestCharts.hand_chart()
	var conductor: Conductor = auto_free(Conductor.new())
	add_child(conductor)
	var hw: Highway = auto_free(Highway.new())
	add_child(hw)
	hw.setup(chart, conductor)
	assert_float(hw._good_window).is_equal(JudgeConfig.new().good_window)
	var cfg := JudgeConfig.new()
	cfg.good_window = 0.05
	hw.setup(chart, conductor, cfg)
	assert_float(hw._good_window).is_equal(0.05)


func test_on_lane_pressed_records_only_that_lane() -> void:
	var hw: Highway = auto_free(Highway.new())
	hw.on_lane_pressed(2, 123)
	assert_bool(hw._press_ticks[2] >= 0).is_true()
	assert_int(hw._press_ticks[0]).is_equal(-1)
	assert_int(hw._press_ticks[1]).is_equal(-1)
	assert_int(hw._press_ticks[3]).is_equal(-1)
	hw.on_lane_pressed(-1, 0)
	hw.on_lane_pressed(4, 0)
	assert_int(hw._press_ticks.size()).is_equal(4)


func test_receptor_pulse_values() -> void:
	var p0 := Highway.receptor_pulse(0, false)
	assert_float(p0["scale"]).is_equal_approx(1.0, 0.0001)
	var mid := Highway.receptor_pulse(30000, false)
	assert_float(mid["scale"]).is_equal_approx(1.2, 0.001)
	assert_float(mid["fill_alpha"]).is_equal(0.40)
	assert_float(mid["outline_alpha"]).is_equal(1.0)
	var after := Highway.receptor_pulse(120000, false)
	assert_float(after["scale"]).is_equal(1.0)
	assert_float(after["fill_alpha"]).is_equal(0.0)
	assert_float(after["outline_alpha"]).is_equal(0.70)
	var rm := Highway.receptor_pulse(30000, true)
	assert_float(rm["scale"]).is_equal(1.0)
	assert_float(rm["fill_alpha"]).is_equal(0.40)
	assert_float(Highway.receptor_pulse(120000, true)["fill_alpha"]).is_equal(0.0)


func test_layout_constants() -> void:
	assert_float(Highway.LABEL_Y).is_equal(936.0)
	assert_float(Highway.HULL_Y).is_equal(880.0)
