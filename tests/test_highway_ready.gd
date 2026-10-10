extends GdUnitTestSuite
## Lane palette, ready predicate, receptor pulse/squash, gem rim states and the board layer
## split (Plan 01.1-02, restyled in 02.2-08).


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


## UI-SPEC 4.15: far vs ready reads through rim brightness + halo; the core is never dimmed.
func test_far_and_ready_gems_differ_by_rim_and_halo_not_core() -> void:
	for lane in range(4):
		var lane_col := Palette.lane_color(lane)
		assert_that(NotePainter.core_color(lane)).is_equal(lane_col)
		var ready_rim := NotePainter.rim_color(lane, true)
		var far_rim := NotePainter.rim_color(lane, false)
		assert_that(ready_rim).is_equal(Palette.mix(lane_col, Palette.WHITE, 0.55))
		assert_that(far_rim).is_equal(Palette.mix(lane_col, Palette.WHITE, 0.25))
		assert_float(ready_rim.get_luminance()).is_greater(far_rim.get_luminance())
	assert_bool(NotePainter.layers(NotePainter.NOTE_NORMAL, 0, NotePainter.STATE_READY, false).has("halo")).is_true()
	assert_bool(NotePainter.layers(NotePainter.NOTE_NORMAL, 0, NotePainter.STATE_FAR, false).has("halo")).is_false()


func test_highway_source_has_no_dimming() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	assert_bool(src.contains("NOTE_DIM")).is_false()
	assert_bool(src.contains("Palette.dim(")).is_false()
	assert_bool(src.contains("NotePainter.draw_note")).is_true()


func test_core_colors_unchanged() -> void:
	assert_that(Palette.DESTRUCTIVE).is_equal(Palette.WARNING_RED)
	assert_that(Palette.ACCENT).is_equal(Palette.SONAR)


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
	assert_int(Highway.LANES).is_equal(4)
	var h0 := Trench.hit_point(0)
	var h1 := Trench.hit_point(1)
	assert_float(h0.x).is_equal_approx(645.0, 1.0)
	assert_float(h0.y).is_equal_approx(Trench.HIT_Y, 1.0)
	assert_float(h1.x).is_equal_approx(855.0, 1.0)
	assert_float(h1.y).is_equal_approx(Trench.HIT_Y, 1.0)


func test_receptor_squash_on_press_and_recovery() -> void:
	var saved: bool = Settings.reduce_motion
	Settings.reduce_motion = false
	var hw: Highway = auto_free(Highway.new())
	assert_that(hw.receptor_scale(1)).is_equal(Vector2.ONE)
	hw.on_lane_pressed(1, 0)
	var t0: int = hw._press_ticks[1]
	var s0 := hw.receptor_scale(1, t0)
	assert_float(s0.x).is_equal_approx(1.12, 0.0001)
	assert_float(s0.y).is_equal_approx(0.88, 0.0001)
	var mid := hw.receptor_scale(1, t0 + int(Palette.DUR_FAST * 500000.0))
	assert_bool(mid.x > 1.0 and mid.x < 1.12).is_true()
	assert_that(hw.receptor_scale(1, t0 + int(Palette.DUR_FAST * 1000000.0))).is_equal(Vector2.ONE)
	assert_that(hw.receptor_scale(0, t0)).is_equal(Vector2.ONE)
	Settings.reduce_motion = true
	assert_that(hw.receptor_scale(1, t0)).is_equal(Vector2.ONE)
	Settings.reduce_motion = saved


func test_strip_tint_is_tier_one_at_multiplier_one() -> void:
	var hw: Highway = auto_free(Highway.new())
	assert_int(hw.tier_multiplier).is_equal(1)
	assert_float(hw.cable_bright).is_equal(0.0)
	assert_float(hw.strip_tint_alpha()).is_equal_approx(Palette.TIER_TINT[0], 0.00001)
	assert_float(hw.strip_tint_alpha()).is_equal_approx(0.07, 0.00001)


func test_strip_edges_follow_the_lane_projection() -> void:
	for f in [-2.0, -0.5, 1.0, 2.0]:
		for d in [0.0, 0.5, 1.0]:
			var p := Trench.point(f, d)
			assert_float(Highway.edge_x(f, p.y)).is_equal_approx(p.x, 0.01)


func test_highway_notes_halos_child_draws_behind_the_gems() -> void:
	var hn: HighwayNotes = auto_free(HighwayNotes.new())
	var halos := hn.get_node("Halos") as CanvasItem
	assert_object(halos).is_not_null()
	assert_bool(halos.show_behind_parent).is_true()
	assert_object(halos.material).is_same(UiKit.additive_material())
	assert_int(hn.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_notes_layer_draws_gems_and_highway_does_not() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/highway_notes.gd")
	assert_bool(src.contains("highway.draw_notes_into(self)")).is_true()
	var hsrc := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	var draw_body := hsrc.substr(hsrc.find("func _draw() -> void:"), 600)
	assert_bool(draw_body.contains("draw_note")).is_false()
	assert_bool(draw_body.contains("_draw_receptors()")).is_true()
