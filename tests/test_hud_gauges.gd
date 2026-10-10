extends GdUnitTestSuite
## 02.2-12: cockpit frame, multiplier ring and torpedo socket (UI-SPEC 4.5, 4.14, 7.2, 11).

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


func _ring() -> Array:
	var r: MultiplierRing = auto_free(MultiplierRing.new())
	add_child(r)
	var s := HullScore.new(JudgeConfig.new())
	r.bind(s)
	return [r, s]


# ---- MultiplierRing --------------------------------------------------------------------

func test_lit_notches_fill_logic() -> void:
	assert_array(MultiplierRing.lit_notches(0)).is_equal([0, 0, 0])
	assert_array(MultiplierRing.lit_notches(7)).is_equal([7, 0, 0])
	assert_array(MultiplierRing.lit_notches(10)).is_equal([10, 0, 0])
	assert_array(MultiplierRing.lit_notches(13)).is_equal([10, 3, 0])
	assert_array(MultiplierRing.lit_notches(29)).is_equal([10, 10, 9])
	assert_array(MultiplierRing.lit_notches(30)).is_equal([10, 10, 10])
	assert_array(MultiplierRing.lit_notches(250)).is_equal([10, 10, 10])


func test_max_state_follows_multiplier() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	assert_bool(ring.is_max()).is_false()
	s.combo_changed.emit(29)
	s.multiplier_changed.emit(3)
	assert_bool(ring.is_max()).is_false()
	s.combo_changed.emit(30)
	s.multiplier_changed.emit(4)
	assert_bool(ring.is_max()).is_true()
	assert_object(ring.lit_color()).is_equal(Palette.REWARD_GOLD)
	assert_bool(ring.max_chip_visible()).is_true()
	assert_str(ring.numeral_text()).is_equal("×4")


func test_geometry_and_arc_angles() -> void:
	assert_object(MultiplierRing.CENTER).is_equal(Vector2(144.0, 912.0))
	assert_float(MultiplierRing.R_IN).is_equal(78.0)
	assert_float(MultiplierRing.R_OUT).is_equal(96.0)
	assert_array(MultiplierRing.ARC_STARTS).is_equal([-85.0, 35.0, 155.0])
	assert_float(MultiplierRing.ARC_SPAN).is_equal(110.0)
	# First notch starts at the arc start, the last ends at the arc end, 1.5 degree gaps.
	for a in 3:
		var first := MultiplierRing.notch_degrees(a, 0)
		var last := MultiplierRing.notch_degrees(a, 9)
		assert_float(first.x).is_equal_approx(MultiplierRing.ARC_STARTS[a], 0.001)
		assert_float(last.y).is_equal_approx(MultiplierRing.ARC_STARTS[a] + 110.0, 0.001)
		var gap := MultiplierRing.notch_degrees(a, 1).x - first.y
		assert_float(gap).is_equal_approx(1.5, 0.001)
	assert_float(MultiplierRing.notch_degrees(2, 9).y).is_equal_approx(265.0, 0.001)


func test_step_up_flash_and_pop() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(10)
	s.multiplier_changed.emit(2)
	assert_bool(ring.is_flashing()).is_true()
	ring._process(0.06)
	assert_float(ring.numeral_scale()).is_greater(1.0)
	assert_float(ring.numeral_scale()).is_less_equal(1.15 + 0.001)
	ring._process(0.1)
	assert_bool(ring.is_flashing()).is_false()
	assert_float(ring.numeral_scale()).is_equal(1.0)


func test_no_flash_or_pop_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(10)
	s.multiplier_changed.emit(2)
	assert_bool(ring.is_flashing()).is_false()
	ring._process(0.06)
	assert_float(ring.numeral_scale()).is_equal(1.0)


func test_break_drains_over_180_ms() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(15)
	assert_float(ring.shown_fill()).is_equal(15.0)
	s.combo_changed.emit(0)
	s.multiplier_changed.emit(1)
	assert_str(ring.numeral_text()).is_equal("×1")  # numeral returns instantly
	assert_float(ring.shown_fill()).is_equal(15.0)
	ring._process(0.09)
	assert_float(ring.shown_fill()).is_greater(0.0)
	assert_float(ring.shown_fill()).is_less(15.0)
	ring._process(0.1)
	assert_float(ring.shown_fill()).is_equal(0.0)


func test_break_is_instant_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	s.combo_changed.emit(15)
	s.combo_changed.emit(0)
	assert_float(ring.shown_fill()).is_equal(0.0)


func test_glint_only_at_max_on_full() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	assert_bool(ring.glint_on()).is_false()
	s.combo_changed.emit(30)
	s.multiplier_changed.emit(4)
	assert_bool(ring.glint_on()).is_true()
	assert_bool(ring.glow_on()).is_true()
	Settings.low_effects = true
	ring.apply_effect_settings()
	assert_bool(ring.glint_on()).is_false()
	assert_bool(ring.glow_on()).is_false()
	Settings.low_effects = false
	Settings.reduce_motion = true
	ring.apply_effect_settings()
	assert_bool(ring.glint_on()).is_false()
	assert_bool(ring.glow_on()).is_true()


func test_ring_registers_effect_contract() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	assert_bool(ring.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_dict(ring.effect_counts()).is_equal({"glint": false, "glow": false, "glint_enabled": true,
		"glow_enabled": true, "pop": true, "drain": true})
	assert_int(ring.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_ring_draws_every_state_without_error() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	for c in [0, 7, 13, 29, 30]:
		s.combo_changed.emit(c)
		s.multiplier_changed.emit(mini(1 + c / 10, 4))
		ring.queue_redraw()
		await get_tree().process_frame
	assert_bool(ring.is_inside_tree()).is_true()


# ---- TorpedoSocket ---------------------------------------------------------------------

func test_socket_rect_and_static_draw() -> void:
	var t: TorpedoSocket = auto_free(TorpedoSocket.new())
	add_child(t)
	assert_object(t.socket_rect()).is_equal(Rect2(272.0, 928.0, 80.0, 80.0))
	assert_object(Rect2(t.position, t.size)).is_equal(Rect2(272.0, 928.0, 80.0, 80.0))
	# Same in every effect mode: it is not an effect node and has no children (no text, no icon).
	assert_bool(t.has_method("apply_effect_settings")).is_false()
	assert_bool(t.is_in_group(UiKit.FX_GROUP)).is_false()
	assert_int(t.get_child_count()).is_equal(0)
	assert_int(TorpedoSocket.DASHES).is_equal(12)
	assert_float(TorpedoSocket.R_OUTER).is_equal(36.0)
	assert_float(TorpedoSocket.R_DASH).is_equal(30.0)
	await get_tree().process_frame


# ---- CockpitFrame ----------------------------------------------------------------------

func test_frame_consoles_and_keepout() -> void:
	assert_array(Array(CockpitFrame.LEFT_CONSOLE)).is_equal([
		Vector2(0, 600), Vector2(336, 600), Vector2(400, 664), Vector2(400, 1080), Vector2(0, 1080)])
	assert_array(Array(CockpitFrame.RIGHT_CONSOLE)).is_equal([
		Vector2(1920, 600), Vector2(1584, 600), Vector2(1520, 664), Vector2(1520, 1080), Vector2(1920, 1080)])
	var f: CockpitFrame = auto_free(CockpitFrame.new())
	add_child(f)
	var shapes := f.keepout_shapes()
	assert_int(shapes.size()).is_equal(4)
	assert_array(Array(shapes[0])).is_equal(Array(CockpitFrame.LEFT_CONSOLE))
	# Bezels stay in the top corners.
	for p in shapes[2]:
		assert_bool(p.x <= 280.0 and p.y <= 200.0).is_true()
	for p in shapes[3]:
		assert_bool(p.x >= 1640.0 and p.y <= 200.0).is_true()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_frame_draws_once_and_stays_cached() -> void:
	var f: CockpitFrame = auto_free(CockpitFrame.new())
	add_child(f)
	for i in 60:
		await get_tree().process_frame
	assert_int(f.redraw_count).is_equal(1)
	assert_bool(f.is_processing()).is_false()


# ---- Bathymeter (02.2-13, UI-SPEC 4.6) ----------------------------------------------------

func _chart(notes: Array) -> ChartData:
	var c := ChartData.new()
	for n in notes:
		c.add_note(int(n[0]), float(n[1]), float(n[2]))
	c.finalize()
	return c


func test_estimate_max_depth_singles() -> void:
	var cfg := JudgeConfig.new()
	var notes := []
	for i in 25:
		notes.append([i % 4, 1.0 + i * 0.5, 0.0])
	var expected := 0.0
	for i in 25:
		expected += float(cfg.score_perfect) * mini(1 + i / 10, 4) / cfg.score_per_meter
	assert_float(expected).is_equal_approx(45.0, 0.001)
	assert_float(Bathymeter.estimate_max_depth(_chart(notes), cfg)).is_equal_approx(expected, 0.001)


func test_estimate_max_depth_sustain_ticks() -> void:
	var cfg := JudgeConfig.new()
	var plain := Bathymeter.estimate_max_depth(_chart([[0, 1.0, 0.0]]), cfg)
	var held := Bathymeter.estimate_max_depth(_chart([[0, 1.0, 1.0]]), cfg)
	# floor(1.0 / 0.1) ticks x score_sustain_tick x multiplier 1, in meters.
	var ticks := floori(1.0 / cfg.sustain_tick_interval + 1e-9)
	assert_float(held - plain).is_equal_approx(float(ticks * cfg.score_sustain_tick) / cfg.score_per_meter, 0.001)
	assert_float(Bathymeter.estimate_max_depth(ChartData.new(), cfg)).is_equal(0.0)


func test_estimate_matches_an_all_perfect_hullscore_run() -> void:
	var parsed := ChartParser.parse_bytes(FileAccess.get_file_as_bytes("res://songs/hrt/notes.chart"))
	assert_bool(parsed.ok).is_true()
	var chart := ChartImporter.build(parsed, "expert", 0)
	var has_sustain := false
	for n in chart.notes:
		has_sustain = has_sustain or float(n["duration"]) > 0.0
	assert_bool(has_sustain).is_true()
	var cfg := JudgeConfig.new()
	var judge := InputJudge.new(chart, cfg)
	var hs := HullScore.new(cfg)
	hs.connect_judge(judge)
	var ap := Autoplay.new(chart, judge)
	var lastn: Dictionary = chart.notes[chart.notes.size() - 1]
	var last: float = float(lastn["time"]) + float(lastn["duration"]) + 1.0
	var t := 0.0
	while t < last:
		t += 1.0 / 60.0
		ap.update(t)
		judge.tick(t)
	assert_int(hs.miss_count).is_equal(0)
	assert_float(Bathymeter.estimate_max_depth(chart, cfg)).is_equal_approx(hs.depth(), 1.0)


func _bathy(scale: float, best: float) -> Bathymeter:
	var b: Bathymeter = auto_free(Bathymeter.new())
	add_child(b)
	b.setup(scale, best)
	return b


func test_bathymeter_marker_math_and_scale() -> void:
	assert_float(Bathymeter.marker_y_for(0.0, 100.0)).is_equal(632.0)
	assert_float(Bathymeter.marker_y_for(50.0, 100.0)).is_equal(832.0)
	assert_float(Bathymeter.marker_y_for(500.0, 100.0)).is_equal(1032.0)
	assert_float(Bathymeter.marker_y_for(-5.0, 100.0)).is_equal(632.0)
	assert_float(Bathymeter.marker_y_for(5.0, 0.0)).is_equal(632.0)
	var b := _bathy(100.0, -1.0)
	assert_float(b.scale_m()).is_equal(100.0)
	assert_bool(b.best_visible()).is_false()
	var b2 := _bathy(100.0, 150.0)
	assert_float(b2.scale_m()).is_equal(150.0)
	assert_bool(b2.best_visible()).is_true()
	assert_float(b2.best_y()).is_equal(1032.0)
	var b3 := _bathy(100.0, 0.0)  # a record of 0 m still exists
	assert_bool(b3.best_visible()).is_true()
	var b4 := _bathy(100.0, INF)  # T-02.2-24: non-finite best ignored
	assert_bool(b4.best_visible()).is_false()
	assert_float(b4.scale_m()).is_equal(100.0)


func test_bathymeter_marker_eases_with_tau() -> void:
	var b := _bathy(100.0, -1.0)
	b.set_depth(50.0)
	assert_float(b.target_y()).is_equal(832.0)
	assert_float(b.shown_y()).is_equal(632.0)
	b._process(0.08)
	assert_float(b.shown_y()).is_equal_approx(832.0 - 200.0 * exp(-1.0), 0.01)
	for i in 60:
		b._process(1.0 / 60.0)
	assert_float(b.shown_y()).is_equal_approx(832.0, 0.06)
	b.set_depth(NAN)  # ignored
	assert_float(b.target_y()).is_equal(832.0)


func test_bathymeter_marker_instant_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var b := _bathy(100.0, -1.0)
	b.set_depth(25.0)
	assert_float(b.shown_y()).is_equal(732.0)
	assert_bool(b.is_in_group(UiKit.FX_GROUP)).is_true()


func test_bathymeter_best_flashes_once_when_passed() -> void:
	var b := _bathy(100.0, 40.0)
	b.set_depth(30.0)
	assert_bool(b.best_flashing()).is_false()
	b.set_depth(45.0)
	assert_bool(b.best_flashing()).is_true()
	b._process(Palette.DUR_BASE + 0.01)
	assert_bool(b.best_flashing()).is_false()
	b.set_depth(60.0)
	assert_bool(b.best_flashing()).is_false()
	b.queue_redraw()
	await get_tree().process_frame


# ---- HullArc (02.2-13, UI-SPEC 4.7) -------------------------------------------------------

func _arc() -> HullArc:
	var a: HullArc = auto_free(HullArc.new())
	add_child(a)
	return a


func test_hull_arc_segments_lit() -> void:
	assert_float(HullArc.segments_lit(100.0)).is_equal(20.0)
	assert_float(HullArc.segments_lit(47.5)).is_equal(9.5)
	assert_float(HullArc.segments_lit(0.0)).is_equal(0.0)
	assert_float(HullArc.segments_lit(140.0)).is_equal(20.0)
	assert_float(HullArc.segments_lit(-3.0)).is_equal(0.0)


func test_hull_arc_geometry_kept() -> void:
	assert_object(HullArc.CENTER).is_equal(Vector2(960.0, 450.0))
	assert_float(HullArc.RADIUS).is_equal(612.0)
	assert_float(HullArc.ANGLE_LEFT).is_equal(2.028)
	assert_float(HullArc.ANGLE_RIGHT).is_equal(1.114)
	assert_float(HullArc.R_IN).is_equal(607.0)
	assert_float(HullArc.R_OUT).is_equal(617.0)
	assert_int(HullArc.SEGMENTS).is_equal(20)
	# Segment 0 starts at the left end; gaps of 0.006 rad between neighbours.
	var s0 := HullArc.segment_angles(0)
	var s1 := HullArc.segment_angles(1)
	assert_float(s0.y).is_equal_approx(2.028 - 0.003, 0.0001)
	assert_float(s0.x - s1.y).is_equal_approx(0.006, 0.0001)
	assert_float(HullArc.segment_angles(19).x).is_equal_approx(1.114 + 0.003, 0.0001)
	assert_float(HullArc.angle_for(30.0)).is_equal_approx(Hud.hull_arc_angle(30.0), 0.0001)


func test_hull_arc_colours_by_hull() -> void:
	assert_object(HullArc.color_for(80.0)).is_equal(Palette.SONAR)
	assert_object(HullArc.color_for(50.0)).is_equal(Palette.TEXT_HI)
	assert_object(HullArc.color_for(31.0)).is_equal(Palette.TEXT_HI)
	assert_object(HullArc.color_for(30.0)).is_equal(Palette.WARNING_RED)
	assert_object(HullArc.color_for(0.0)).is_equal(Palette.WARNING_RED)


func test_hull_arc_cracks_near_edge_and_everywhere_when_critical() -> void:
	# 70% -> 14 lit; lost segments 14, 15, 16 crack.
	assert_array(HullArc.cracked_segments(70.0)).is_equal([14, 15, 16])
	# 47.5% -> 9.5 lit; the partial boundary 9 plus 10, 11 (within 3 of the edge).
	assert_array(HullArc.cracked_segments(47.5)).is_equal([9, 10, 11])
	assert_array(HullArc.cracked_segments(100.0)).is_empty()
	# Critical: every unlit segment cracks.
	var crit := HullArc.cracked_segments(25.0)
	assert_int(crit.size()).is_equal(15)
	assert_int(crit[0]).is_equal(5)
	assert_int(crit[14]).is_equal(19)


func test_hull_arc_crack_shapes_are_deterministic() -> void:
	var a := HullArc.crack_lines(7)
	var b := HullArc.crack_lines(7)
	assert_int(a.size()).is_equal(2)
	assert_int(a[0].size()).is_equal(3)
	assert_array(Array(a[0])).is_equal(Array(b[0]))
	assert_array(Array(a[1])).is_equal(Array(b[1]))
	assert_bool(Array(HullArc.crack_lines(8)[0]) != Array(a[0])).is_true()


func test_hull_arc_damage_flash_then_shrink() -> void:
	var a := _arc()
	a.set_hull(100.0, 0.0)
	a.set_hull(90.0, -10.0)
	assert_bool(a.is_flashing()).is_true()
	a._process(0.1)
	assert_float(a.shown_pct()).is_equal(100.0)  # holds while the lost segments flash red
	a._process(0.11)
	assert_bool(a.is_flashing()).is_false()
	for i in 10:
		a._process(0.015)
	assert_float(a.shown_pct()).is_less(91.0)
	for i in 30:
		a._process(0.016)
	assert_float(a.shown_pct()).is_equal(90.0)
	# Regen snaps up.
	a.set_hull(91.0, 1.0)
	assert_float(a.shown_pct()).is_equal(91.0)


func test_hull_arc_pulses_when_critical_static_under_reduce() -> void:
	var a := _arc()
	a.set_hull(25.0, -5.0)
	assert_bool(a.is_critical()).is_true()
	assert_bool(a.pulsing()).is_true()
	var lo := a.fill_alpha(int(1000000.0 / 6.0))  # half a 3 Hz period
	assert_float(lo).is_less(0.5)
	assert_float(a.fill_alpha(0)).is_equal_approx(1.0, 0.001)
	Settings.reduce_motion = true
	a.apply_effect_settings()
	assert_bool(a.pulsing()).is_false()
	assert_float(a.fill_alpha(int(1000000.0 / 6.0))).is_equal(1.0)
	assert_bool(a.is_in_group(UiKit.FX_GROUP)).is_true()
	a.queue_redraw()
	await get_tree().process_frame


# ---- Right console (02.2-13, UI-SPEC 7.3, 14) ---------------------------------------------

const JP := InputJudge.Judgment.PERFECT
const JG := InputJudge.Judgment.GOOD
const JM := InputJudge.Judgment.MISS


func _hud(score: HullScore) -> Hud:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.bind(score)
	return hud


func _judge(hud: Hud, score: HullScore, j: int, idx: int) -> void:
	score.on_judged(0, idx, j, 0.0)
	hud.on_judged(0, idx, j, 0.0)


func test_accuracy_placeholder_then_live_value() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_str(hud.accuracy_label.text).is_equal("--.-%")
	assert_object(hud.accuracy_label.get_theme_color("font_color")).is_equal(Palette.TEXT_LO)
	for i in 3:
		_judge(hud, score, JP, i)
	_judge(hud, score, JG, 3)
	assert_str(hud.accuracy_label.text).is_equal("87.5%")
	assert_object(hud.accuracy_label.get_theme_color("font_color")).is_equal(Palette.TEXT_HI)
	assert_object(hud.accuracy_label.get_theme_font("font")).is_same(Palette.display_font())
	assert_int(hud.accuracy_label.get_theme_font_size("font_size")).is_equal(Palette.SIZE_HEADING)
	assert_float(hud.accuracy_label.position.x).is_equal(1552.0)
	_judge(hud, score, JM, 4)
	assert_str(hud.accuracy_label.text).is_equal("70.0%")


func test_depth_readout_fixed_box_no_layout_shift() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	var box0 := hud.depth_box()
	var unit0 := hud.depth_unit_x()
	assert_float(box0.position.x).is_equal(1552.0)
	assert_str(hud.depth_readout_text()).is_equal("0")
	# Drive the depth to 99,999 m (score 9,999,900) through score_changed.
	score.score = 9999900
	score.score_changed.emit(score.score)
	assert_str(hud.depth_readout_text()).is_equal("99,999")
	assert_object(hud.depth_box()).is_equal(box0)
	assert_float(hud.depth_unit_x()).is_equal(unit0)
	var f := Palette.display_font()
	var w := f.get_string_size("99,999", HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_HEADING).x
	assert_float(box0.size.x).is_greater_equal(w)
	# Hidden test label keeps its format.
	assert_str(hud.depth_value.text).is_equal(hud.depth_text(score.depth()))
	assert_bool(hud.depth_value.visible).is_false()


func test_mode_chips_only_when_active() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_dict(hud.chip_rects()).is_empty()
	hud.set_autoplay(true)
	assert_bool(hud.is_autoplay_shown()).is_true()
	var r: Dictionary = hud.chip_rects()
	assert_array(r.keys()).is_equal(["AUTOPLAY"])
	assert_float((r["AUTOPLAY"] as Rect2).position.y).is_equal(864.0)
	assert_float((r["AUTOPLAY"] as Rect2).end.y).is_equal(896.0)
	var s2 := HullScore.new(JudgeConfig.new())
	s2.no_fail = true
	var hud2 := _hud(s2)
	var r2: Dictionary = hud2.chip_rects()
	assert_float((r2["NO-FAIL"] as Rect2).position.y).is_equal(824.0)
	assert_float((r2["NO-FAIL"] as Rect2).position.x).is_equal(1552.0)
	hud.queue_redraw()
	hud2.queue_redraw()
	await get_tree().process_frame


func test_hull_caption_style_and_hull_arc_child() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_object(hud.hull_arc).is_not_null()
	assert_object(hud.hull_arc.get_parent()).is_same(hud)
	for i in 9:
		score.on_judged(0, i, JM, 0.2)  # 28%
	assert_float(hud.hull_arc.pct()).is_equal_approx(28.0, 0.001)
	assert_bool(hud.hull_caption.visible).is_true()
	assert_str(hud.hull_caption.text).is_equal("HULL CRITICAL")
	assert_object(hud.hull_caption.get_theme_color("font_color")).is_equal(Palette.WARNING_RED)
	assert_int(hud.hull_caption.get_theme_constant("outline_size")).is_equal(3)
	assert_object(hud.hull_caption.get_theme_color("font_outline_color")).is_equal(Palette.KEYLINE)
	assert_int(hud.hull_caption.get_theme_font_size("font_size")).is_equal(Palette.SIZE_LABEL)
	var cx := hud.hull_caption.position.x + hud.hull_caption.size.x * 0.5
	assert_float(cx).is_equal_approx(960.0, 0.5)
	assert_float(hud.hull_caption_baseline()).is_equal_approx(1028.0, 0.5)
	await get_tree().process_frame


func test_bathymeter_child_and_record() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_object(hud.bathymeter).is_not_null()
	assert_object(hud.bathymeter.get_parent()).is_same(hud)
	hud.set_depth_scale(200.0)
	assert_bool(hud.bathymeter.best_visible()).is_false()
	hud.set_record(250.0)
	assert_bool(hud.bathymeter.best_visible()).is_true()
	assert_float(hud.bathymeter.scale_m()).is_equal(250.0)
	score.score = 12500  # 125 m
	score.score_changed.emit(score.score)
	assert_float(hud.bathymeter.target_y()).is_equal(Bathymeter.marker_y_for(125.0, 250.0))


func test_badge_drawing_retired_and_keepout_in_consoles() -> void:
	var score := HullScore.new(JudgeConfig.new())
	score.no_fail = true
	var hud := _hud(score)
	hud.set_autoplay(true)
	assert_bool(hud.has_method("_draw_badge")).is_false()
	var shapes := hud.keepout_shapes()
	assert_int(shapes.size()).is_greater_equal(6)
	for poly in shapes:
		for p in poly:
			assert_bool(p.x <= 400.0 or p.x >= 1520.0).override_failure_message(
				"HUD keep-out point %s outside the consoles" % p).is_true()
			assert_bool(p.y >= 600.0).is_true()


# ---- ProgressTrack (02.2-14, UI-SPEC 4.8) -------------------------------------------------

func _sectioned_chart(sections: Array, length_s: float = 200.0) -> ChartData:
	var c := ChartData.new()
	c.title = "Invisible"
	c.artist = "Duran Duran"
	c.add_note(0, 1.0, 0.0)
	c.add_note(1, length_s, 0.0)
	c.finalize()
	for s in sections:
		c.sections.append({"time": float(s[0]), "name": str(s[1])})
	return c


func _track(chart: ChartData) -> ProgressTrack:
	var p: ProgressTrack = auto_free(ProgressTrack.new())
	add_child(p)
	p.setup(chart, null)
	return p


func test_progress_fill_and_geometry() -> void:
	var p := _track(_sectioned_chart([[10.0, "intro"], [50.0, "verse 1"]], 200.0))
	assert_float(p.song_length()).is_equal_approx(200.0, 0.001)
	assert_object(ProgressTrack.TRACK).is_equal(Rect2(480.0, 60.0, 960.0, 4.0))
	p.set_song_time(-2.0)
	assert_float(p.fill()).is_equal(0.0)
	p.set_song_time(50.0)
	assert_float(p.fill()).is_equal_approx(0.25, 0.0001)
	p.set_song_time(500.0)
	assert_float(p.fill()).is_equal(1.0)
	assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_progress_title_line_and_truncation() -> void:
	var c := _sectioned_chart([])
	var p := _track(c)
	assert_str(p.title_label.text).is_equal("Invisible · Duran Duran")
	assert_float(p.title_label.position.x).is_equal(480.0)
	assert_object(p.title_label.get_theme_color("font_color")).is_equal(Palette.TEXT_MID)
	c.title = "The Extraordinarily Long Title Of A Progressive Rock Epic That Never Ends Part IV"
	p.setup(c, null)
	var t := p.title_label.text
	assert_str(t).ends_with("...")
	var w := Palette.font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	assert_float(w).is_less_equal(560.0)
	assert_bool(p.title_label.clip_text).is_true()
	assert_int(p.title_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)


func test_progress_current_section_name_and_ticks() -> void:
	var p := _track(_sectioned_chart([[10.0, "intro"], [50.0, "verse 1"], [100.0, "chorus 2"]], 200.0))
	assert_str(p.current_section_name(5.0)).is_equal("")
	assert_str(p.current_section_name(10.0)).is_equal("INTRO")
	assert_str(p.current_section_name(99.9)).is_equal("VERSE 1")
	assert_str(p.current_section_name(150.0)).is_equal("CHORUS 2")
	p.set_song_time(120.0)
	assert_str(p.section_label.text).is_equal("CHORUS 2")
	assert_object(p.section_label.get_theme_color("font_color")).is_equal(Palette.SONAR_PALE)
	assert_float(p.section_label.position.x + p.section_label.size.x).is_equal_approx(1440.0, 0.5)
	var ticks := p.tick_xs()
	assert_int(ticks.size()).is_equal(3)
	assert_float(ticks[0]).is_equal_approx(480.0 + 960.0 * 10.0 / 200.0, 0.01)
	assert_float(ticks[2]).is_equal_approx(960.0, 0.01)


func test_progress_time_remaining_text() -> void:
	var p := _track(_sectioned_chart([], 200.0))
	assert_str(p.time_remaining_text(49.0)).is_equal("-2:31")
	assert_str(p.time_remaining_text(200.0)).is_equal("-0:00")
	assert_str(p.time_remaining_text(260.0)).is_equal("-0:00")
	assert_str(p.time_remaining_text(-3.0)).is_equal("-3:20")
	p.set_song_time(49.0)
	assert_str(p.time_label.text).is_equal("-2:31")
	assert_float(p.time_label.position.x).is_equal(1456.0)
	assert_object(p.time_label.get_theme_color("font_color")).is_equal(Palette.TEXT_LO)


func test_progress_scrim_gradient() -> void:
	assert_float(ProgressTrack.scrim_alpha(0.0)).is_equal_approx(0.8, 0.001)
	assert_float(ProgressTrack.scrim_alpha(76.0)).is_equal_approx(0.8, 0.001)
	assert_float(ProgressTrack.scrim_alpha(94.0)).is_equal_approx(0.4, 0.01)
	assert_float(ProgressTrack.scrim_alpha(112.0)).is_equal_approx(0.0, 0.001)
	assert_float(ProgressTrack.scrim_alpha(300.0)).is_equal(0.0)


func test_progress_no_sections_still_draws() -> void:
	var p := _track(_sectioned_chart([], 200.0))
	p.set_song_time(80.0)
	assert_str(p.current_section_name(80.0)).is_equal("")
	assert_str(p.section_label.text).is_equal("")
	assert_array(p.tick_xs()).is_empty()
	assert_bool(p.visible).is_true()
	assert_float(p.fill()).is_equal_approx(0.4, 0.0001)
	for poly in p.keepout_shapes():
		for pt in poly:
			assert_float(pt.y).is_less_equal(112.0)
	p.queue_redraw()
	await get_tree().process_frame


# ---- SectionBanner (02.2-14, UI-SPEC 4.9) -------------------------------------------------

func _banner(chart: ChartData) -> SectionBanner:
	var b: SectionBanner = auto_free(SectionBanner.new())
	add_child(b)
	b.setup(chart, null)
	return b


func test_banner_should_show_rules() -> void:
	assert_bool(SectionBanner.should_show(0.0, 200.0)).is_false()
	assert_bool(SectionBanner.should_show(0.49, 200.0)).is_false()
	assert_bool(SectionBanner.should_show(0.5, 200.0)).is_true()
	assert_bool(SectionBanner.should_show(197.9, 200.0)).is_true()
	assert_bool(SectionBanner.should_show(198.5, 200.0)).is_false()
	assert_object(SectionBanner.RECT).is_equal(Rect2(640.0, 200.0, 640.0, 72.0))


func test_banner_name_truncation() -> void:
	assert_str(SectionBanner.display_name("chorus 2")).is_equal("CHORUS 2")
	var long := SectionBanner.display_name("an extremely long guitar solo section name here")
	assert_str(long).ends_with("...")
	assert_int(long.length()).is_less_equal(31)
	var f := Palette.display_font()
	var w := f.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_HEADING).x
	assert_float(w).is_less_equal(SectionBanner.RECT.size.x - 2.0 * UiKit.PANEL_PAD)


func test_banner_slides_in_holds_and_fades_out() -> void:
	var b := _banner(_sectioned_chart([[0.0, "intro"], [10.0, "verse 1"], [40.0, "chorus"]], 200.0))
	b.observe(0.2)
	assert_bool(b.is_showing()).is_false()  # section at 0 s is before 0.5 s
	b.observe(10.0)
	assert_bool(b.is_showing()).is_true()
	assert_str(b.shown_text()).is_equal("VERSE 1")
	assert_float(b.slide_offset()).is_equal_approx(-24.0, 0.01)
	assert_float(b.modulate.a).is_less(0.05)
	b.step(Palette.DUR_BASE * 0.5)
	assert_float(b.modulate.a).is_between(0.3, 0.99)
	b.step(Palette.DUR_BASE * 0.5 + 0.001)
	assert_float(b.modulate.a).is_equal_approx(1.0, 0.001)
	assert_float(b.slide_offset()).is_equal_approx(0.0, 0.01)
	b.step(1.5)
	assert_float(b.modulate.a).is_equal_approx(1.0, 0.001)
	b.step(0.11)  # hold of 1.6 s is over
	b.step(0.15)
	assert_float(b.modulate.a).is_between(0.3, 0.7)
	b.step(0.2)
	assert_bool(b.is_showing()).is_false()
	assert_bool(b.visible).is_false()


func test_banner_cross_fades_on_new_section_during_hold() -> void:
	var b := _banner(_sectioned_chart([[10.0, "verse"], [11.0, "chorus"]], 200.0))
	b.observe(10.0)
	b.step(0.5)
	b.observe(11.0)
	assert_str(b.shown_text()).is_equal("CHORUS")
	assert_bool(b.is_cross_fading()).is_true()
	assert_float(b.modulate.a).is_equal_approx(1.0, 0.001)
	b.step(0.13)
	assert_bool(b.is_cross_fading()).is_false()
	b.step(1.4)
	assert_float(b.modulate.a).is_equal_approx(1.0, 0.001)  # the hold restarted with the new name


func test_banner_reduce_motion_is_fade_only() -> void:
	Settings.reduce_motion = true
	var b := _banner(_sectioned_chart([[10.0, "verse"]], 200.0))
	b.observe(10.0)
	assert_float(b.slide_offset()).is_equal(0.0)
	b.step(0.09)
	assert_float(b.slide_offset()).is_equal(0.0)
	assert_float(b.modulate.a).is_greater(0.2)
	assert_bool(b.effect_counts()["slide"]).is_false()
	assert_bool(b.is_in_group(UiKit.FX_GROUP)).is_true()


func test_banner_no_sections_never_shows() -> void:
	var b := _banner(_sectioned_chart([], 200.0))
	for t in [0.0, 1.0, 10.0, 100.0, 199.0]:
		b.observe(t)
		b.step(0.1)
		assert_bool(b.is_showing()).is_false()


func test_banner_skips_section_near_the_end() -> void:
	var b := _banner(_sectioned_chart([[199.0, "outro"]], 200.0))
	b.observe(199.0)
	assert_bool(b.is_showing()).is_false()


func test_banner_keepout_inside_its_rect_and_draws() -> void:
	var b := _banner(_sectioned_chart([[10.0, "verse"]], 200.0))
	b.observe(10.0)
	b.step(0.3)
	for poly in b.keepout_shapes():
		for pt in poly:
			assert_bool(SectionBanner.RECT.grow(1.0).has_point(pt)).is_true()
	b.queue_redraw()
	await get_tree().process_frame


func test_hud_hosts_progress_track_and_banner() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_object(hud.progress_track).is_not_null()
	assert_object(hud.section_banner).is_not_null()
	assert_object(hud.progress_track.get_parent()).is_same(hud)
	hud.setup_song(_sectioned_chart([[10.0, "verse"]], 200.0), null)
	hud.progress_track.set_song_time(100.0)
	assert_float(hud.progress_track.fill()).is_equal_approx(0.5, 0.0001)


# ---- 02.2-23: chip pop -------------------------------------------------------------------

func test_max_chip_pops_in_when_x4_is_reached() -> void:
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	assert_bool(ring.max_chip.visible).is_false()
	s.combo_changed.emit(30)
	s.multiplier_changed.emit(4)
	assert_bool(ring.max_chip.visible).is_true()
	assert_object(ring.max_chip_tween).is_not_null()
	var w := UiKit.chip_width(MultiplierRing.MAX_CHIP, "reward")
	assert_object(ring.max_chip.position + ring.position).is_equal(
		Vector2(MultiplierRing.CENTER.x - w * 0.5, MultiplierRing.CHIP_Y))
	# Staying at x4 does not pop again; losing it hides the chip.
	var tw := ring.max_chip_tween
	s.multiplier_changed.emit(4)
	assert_object(ring.max_chip_tween).is_same(tw)
	s.multiplier_changed.emit(1)
	assert_bool(ring.max_chip.visible).is_false()


func test_max_chip_does_not_pop_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var r := _ring()
	var ring: MultiplierRing = r[0]
	var s: HullScore = r[1]
	s.multiplier_changed.emit(4)
	assert_bool(ring.max_chip.visible).is_true()
	assert_object(ring.max_chip_tween).is_null()
	assert_object(ring.max_chip.scale).is_equal(Vector2.ONE)


func test_mode_chips_are_nodes_that_pop_in_at_their_rects() -> void:
	var score := HullScore.new(JudgeConfig.new())
	score.no_fail = true
	var hud := _hud(score)
	var nf: Control = hud.mode_chips["NO-FAIL"]
	var ap: Control = hud.mode_chips["AUTOPLAY"]
	assert_bool(nf.visible).is_true()
	assert_bool(ap.visible).is_false()
	assert_object(Rect2(nf.position, nf.size)).is_equal(hud.chip_rects()["NO-FAIL"])
	hud.set_autoplay(true)
	assert_bool(ap.visible).is_true()
	assert_object(Rect2(ap.position, ap.size)).is_equal(hud.chip_rects()["AUTOPLAY"])
	# Mid-pop the chip is scaled about its centre, then it settles at 1 (tween stepped by hand).
	var tw: Tween = hud.mode_chip_tweens["AUTOPLAY"]
	assert_object(tw).is_not_null()
	tw.pause()
	tw.custom_step(Palette.DUR_BASE * 0.4)
	assert_float(ap.scale.x).is_greater(1.0)
	assert_object(ap.pivot_offset).is_equal(ap.size * 0.5)
	tw.custom_step(Palette.DUR_BASE * 2.0)
	assert_float(ap.scale.x).is_equal_approx(1.0, 0.001)
	hud.set_autoplay(false)
	assert_bool(ap.visible).is_false()
