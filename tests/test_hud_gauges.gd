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
	assert_dict(ring.effect_counts()).is_equal({"glint": false, "glow": false, "pop": true, "drain": true})
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
