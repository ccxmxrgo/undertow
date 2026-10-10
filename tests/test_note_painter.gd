extends GdUnitTestSuite
## NotePainter gems (02.2-08, UI-SPEC 4.15): one draw function keyed by note type, ordered
## layers, full lane-colour cores, rim colours/widths, cached unit geometry, missed remnant.

var _saved_low := false


class DrawProbe extends Control:
	var calls := 0
	var type := NotePainter.NOTE_NORMAL
	var state := NotePainter.STATE_READY
	var drawn := false

	func _draw() -> void:
		for i in range(calls):
			var lane := i % 4
			NotePainter.draw_note(self, type, lane, Vector2(200.0 + 60.0 * lane, 200.0), 30.0, state, 0.0)
		NotePainter.draw_chord_bar(self, Vector2(100, 300), Vector2(300, 300), 0.8)
		drawn = true


func before_test() -> void:
	_saved_low = Settings.low_effects


func after_test() -> void:
	Settings.low_effects = _saved_low


func test_note_normal_is_zero_and_unknown_type_falls_back() -> void:
	assert_int(NotePainter.NOTE_NORMAL).is_equal(0)
	assert_int(NotePainter.resolve_type(NotePainter.NOTE_NORMAL)).is_equal(NotePainter.NOTE_NORMAL)
	assert_int(NotePainter.resolve_type(99)).is_equal(NotePainter.NOTE_NORMAL)
	assert_int(NotePainter.resolve_type(-3)).is_equal(NotePainter.NOTE_NORMAL)
	assert_array(NotePainter.layers(99, 0, NotePainter.STATE_READY, false)) \
		.is_equal(NotePainter.layers(NotePainter.NOTE_NORMAL, 0, NotePainter.STATE_READY, false))


func test_layers_ready_full() -> void:
	assert_array(NotePainter.layers(NotePainter.NOTE_NORMAL, 1, NotePainter.STATE_READY, false)) \
		.is_equal(["halo", "keyline", "core", "toplight", "specular", "rim"])


func test_layers_far_has_no_halo() -> void:
	var l := NotePainter.layers(NotePainter.NOTE_NORMAL, 2, NotePainter.STATE_FAR, false)
	assert_array(l).is_equal(["keyline", "core", "toplight", "specular", "rim"])
	assert_array(NotePainter.layers(NotePainter.NOTE_NORMAL, 2, NotePainter.STATE_FAR, true)).is_equal(l)


func test_layers_ready_low_uses_halo_ring() -> void:
	assert_array(NotePainter.layers(NotePainter.NOTE_NORMAL, 3, NotePainter.STATE_READY, true)) \
		.is_equal(["halo_ring", "keyline", "core", "toplight", "specular", "rim"])


func test_layers_missed_core_and_x_only() -> void:
	var l := NotePainter.layers(NotePainter.NOTE_NORMAL, 0, NotePainter.STATE_MISSED, false)
	assert_array(l).is_equal(["core", "x"])
	assert_bool(l.has("rim") or l.has("halo") or l.has("halo_ring")).is_false()


func test_core_colour_is_full_lane_colour() -> void:
	for lane in range(4):
		assert_that(NotePainter.core_color(lane)).is_equal(Palette.lane_color(lane))
		assert_float(NotePainter.core_color(lane).a).is_equal(1.0)


func test_missed_core_is_25_percent_and_x_is_warning_red() -> void:
	for lane in range(4):
		var c := NotePainter.missed_core_color(lane, 1.0)
		assert_float(c.a).is_equal_approx(0.25, 0.0001)
		assert_float(c.r).is_equal_approx(Palette.lane_color(lane).r, 0.0001)
	assert_float(NotePainter.missed_core_color(0, 0.5).a).is_equal_approx(0.125, 0.0001)
	var x := NotePainter.missed_x_color(1.0)
	assert_float(x.r).is_equal_approx(Palette.WARNING_RED.r, 0.0001)
	assert_float(x.g).is_equal_approx(Palette.WARNING_RED.g, 0.0001)
	assert_float(x.a).is_equal(1.0)


func test_rim_colour_and_width() -> void:
	for lane in range(4):
		assert_that(NotePainter.rim_color(lane, true)).is_equal(Palette.rim_ready(lane))
		assert_that(NotePainter.rim_color(lane, false)).is_equal(Palette.rim_far(lane))
	assert_float(NotePainter.rim_width(1.0)).is_equal_approx(4.0, 0.0001)
	assert_float(NotePainter.rim_width(0.5)).is_equal_approx(3.0, 0.0001)
	# r = 36 s + 5 is inverted exactly.
	assert_float(NotePainter.scale_for_radius(Trench.note_radius(0.7))).is_equal_approx(0.7, 0.0001)


func test_unit_polygons_cached_per_kind() -> void:
	NotePainter.clear_cache()
	var probe: DrawProbe = auto_free(DrawProbe.new())
	probe.size = Vector2(600, 400)
	probe.calls = 1000
	add_child(probe)
	probe.queue_redraw()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(probe.drawn).is_true()
	assert_int(NotePainter.cache_size()).is_equal(4)
	var first := NotePainter.unit_shape(0)
	probe.queue_redraw()
	await await_idle_frame()
	assert_int(NotePainter.cache_size()).is_equal(4)
	assert_bool(is_same(NotePainter.unit_shape(0), first)).is_true()


func test_unknown_type_draws_without_error() -> void:
	var probe: DrawProbe = auto_free(DrawProbe.new())
	probe.calls = 8
	probe.type = 42
	probe.state = NotePainter.STATE_MISSED
	add_child(probe)
	probe.queue_redraw()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(probe.drawn).is_true()


func test_unit_shape_has_core_toplight_and_specular() -> void:
	for kind in range(4):
		var u: Dictionary = NotePainter.unit_shape(kind)
		var poly: PackedVector2Array = u["poly"]
		var top: PackedVector2Array = u["top"]
		var spec: PackedVector2Array = u["spec"]
		assert_bool(poly.size() >= 3).is_true()
		assert_bool(top.size() >= 3).is_true()
		assert_bool(spec.size() >= 3).is_true()
		# Top-light lies wholly above the clip line at -0.2 (unit space, y down).
		for p in top:
			assert_bool(p.y <= -0.2 + 0.0001).is_true()
		# Specular sits inside the shape.
		for p in spec:
			assert_bool(Geometry2D.is_point_in_polygon(p, poly)).is_true()


func test_source_has_no_colour_literals() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/note_painter.gd")
	assert_bool(src.contains("const NOTE_NORMAL")).is_true()
	assert_bool(src.contains("static func draw_note(")).is_true()
	var re := RegEx.create_from_string("Color\\(\\s*\"|Color\\(\\s*[0-9.]|Color8\\(")
	assert_object(re.search(src)).is_null()
