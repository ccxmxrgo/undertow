extends GdUnitTestSuite
## NotePainter gems (02.2-08, UI-SPEC 4.15): one draw function keyed by note type, ordered
## layers, full lane-colour cores, rim colours/widths, cached unit geometry, missed remnant.

var _saved_low := false


class DrawProbe extends Control:
	var calls := 0
	var type := NotePainter.NOTE_NORMAL
	var state := NotePainter.STATE_READY
	var drawn := false
	var alpha := 1.0

	func _draw() -> void:
		for i in range(calls):
			var lane := i % 4
			NotePainter.draw_note(self, type, lane, Vector2(200.0 + 60.0 * lane, 200.0), 30.0, state, 0.0, 1.0, alpha)
		NotePainter.draw_chord_bar(self, Vector2(100, 300), Vector2(300, 300), 0.8, alpha)
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


func test_faded_scales_alpha_and_full_alpha_is_untouched() -> void:
	var col := Palette.alpha(Palette.lane_color(0), 0.8)
	assert_float(NotePainter.faded(col, 0.5).a).is_equal_approx(0.4, 0.0001)
	assert_bool(NotePainter.faded(col, 1.0) == col).is_true()
	assert_float(NotePainter.faded(col, 0.0).a).is_equal(0.0)


func test_faded_draw_with_alpha_runs_for_every_state() -> void:
	var probe: DrawProbe = auto_free(DrawProbe.new())
	probe.calls = 4
	probe.alpha = 0.5
	add_child(probe)
	probe.queue_redraw()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(probe.drawn).is_true()


# ---- Phase 3 (03-02): ghost, depth charge, jam, warhead ring (03-UI-SPEC 7.1-7.3, 7.6) ----

class WarheadProbe extends Control:
	var drawn := false

	func _draw() -> void:
		var x := 60.0
		for st in [NotePainter.WARHEAD_OPEN, NotePainter.WARHEAD_CONFIRMED, NotePainter.WARHEAD_DEAD]:
			for fk: float in [0.0, 0.5, 1.0]:
				NotePainter.draw_note(self, NotePainter.NOTE_NORMAL, 0, Vector2(x, 100), 30.0, NotePainter.STATE_READY, 0.0)
				NotePainter.draw_warhead_ring(self, Vector2(x, 100), 30.0, st, fk)
				NotePainter.draw_warhead_ring(self, Vector2(x, 200), 30.0, st, fk, false, 0.5)
				x += 90.0
		drawn = true


class JamFadeProbe extends Control:
	var drawn := false

	func _draw() -> void:
		for lane in range(4):
			for k: float in [0.25, 0.5, 0.75]:
				NotePainter.draw_jam_fade(self, lane, Vector2(60 + 80 * lane, 60 + 80 * k), 24.0, NotePainter.STATE_READY, 0.0, k, 1.0, 1.0, lane == 2)
		drawn = true


func test_phase3_types_resolve_to_themselves() -> void:
	assert_int(NotePainter.NOTE_GHOST).is_equal(1)
	assert_int(NotePainter.NOTE_DISRUPTOR).is_equal(2)
	assert_int(NotePainter.NOTE_JAM).is_equal(3)
	assert_int(NotePainter.resolve_type(NotePainter.NOTE_GHOST)).is_equal(NotePainter.NOTE_GHOST)
	assert_int(NotePainter.resolve_type(NotePainter.NOTE_DISRUPTOR)).is_equal(NotePainter.NOTE_DISRUPTOR)
	assert_int(NotePainter.resolve_type(NotePainter.NOTE_JAM)).is_equal(NotePainter.NOTE_JAM)
	assert_int(NotePainter.resolve_type(99)).is_equal(NotePainter.NOTE_NORMAL)


func test_ghost_layers_hollow_dashed_in_every_mode() -> void:
	for lane in range(4):
		for st in [NotePainter.STATE_FAR, NotePainter.STATE_READY, NotePainter.STATE_MISSED]:
			for low: bool in [false, true]:
				var l := NotePainter.layers(NotePainter.NOTE_GHOST, lane, st, low)
				assert_array(l).is_equal(["keyline", "rim_dashed"])
				assert_bool(l.has("core") or l.has("halo") or l.has("halo_ring") or l.has("x")).is_false()


func test_disruptor_layers_are_normal_plus_charge_mark() -> void:
	for st in [NotePainter.STATE_FAR, NotePainter.STATE_READY, NotePainter.STATE_MISSED]:
		for low: bool in [false, true]:
			var want := NotePainter.layers(NotePainter.NOTE_NORMAL, 1, st, low)
			want.append("charge_mark")
			assert_array(NotePainter.layers(NotePainter.NOTE_DISRUPTOR, 1, st, low)).is_equal(want)


func test_jam_layers_plain_circle_in_every_mode() -> void:
	for st in [NotePainter.STATE_FAR, NotePainter.STATE_READY]:
		for low: bool in [false, true]:
			var l := NotePainter.layers(NotePainter.NOTE_JAM, 0, st, low)
			assert_array(l).is_equal(["keyline", "core", "rim"])
			assert_bool(l.has("halo") or l.has("halo_ring") or l.has("toplight") or l.has("specular")).is_false()


func test_jam_mix_endpoints() -> void:
	for lane in range(4):
		assert_bool(NotePainter.jam_mix(lane, 0.0).is_equal_approx(NotePainter.core_color(lane))).is_true()
		assert_bool(NotePainter.jam_mix(lane, 1.0).is_equal_approx(Palette.JAM_GREY)).is_true()
		assert_bool(NotePainter.jam_mix(lane, 2.0).is_equal_approx(Palette.JAM_GREY)).is_true()
		assert_bool(NotePainter.jam_mix(lane, -1.0).is_equal_approx(NotePainter.core_color(lane))).is_true()


func test_ghost_dashes_eight_per_shape_sixty_percent() -> void:
	for kind in range(4):
		var dashes: Array = NotePainter.ghost_dashes(kind)
		assert_int(dashes.size()).is_equal(NotePainter.GHOST_DASHES)
		var ring := NotePainter.outline_ring(kind)
		var total := 0.0
		for i in range(1, ring.size()):
			total += ring[i - 1].distance_to(ring[i])
		var dashed := 0.0
		for d: PackedVector2Array in dashes:
			assert_bool(d.size() >= 2).is_true()
			for i in range(1, d.size()):
				dashed += d[i - 1].distance_to(d[i])
		# Dashes cut corners, so allow a small shortfall below exactly 60%.
		assert_float(dashed / total).is_between(0.5, 0.6 + 0.0001)
		assert_bool(is_same(NotePainter.ghost_dashes(kind), dashes)).is_true()


func test_phase3_types_draw_every_state_and_mode() -> void:
	for low: bool in [false, true]:
		Settings.low_effects = low
		for type in [NotePainter.NOTE_GHOST, NotePainter.NOTE_DISRUPTOR, NotePainter.NOTE_JAM]:
			for st in [NotePainter.STATE_FAR, NotePainter.STATE_READY, NotePainter.STATE_MISSED]:
				var probe: DrawProbe = auto_free(DrawProbe.new())
				probe.size = Vector2(600, 400)
				probe.calls = 4
				probe.type = type
				probe.state = st
				probe.alpha = 0.7
				add_child(probe)
				probe.queue_redraw()
				await await_idle_frame()
				assert_bool(probe.drawn).is_true()


func test_warhead_ring_draws_open_confirmed_dead() -> void:
	assert_int(NotePainter.WARHEAD_OPEN).is_equal(0)
	assert_int(NotePainter.WARHEAD_CONFIRMED).is_equal(1)
	assert_int(NotePainter.WARHEAD_DEAD).is_equal(2)
	var probe: WarheadProbe = auto_free(WarheadProbe.new())
	probe.size = Vector2(900, 300)
	add_child(probe)
	probe.queue_redraw()
	await await_idle_frame()
	assert_bool(probe.drawn).is_true()


func test_jam_fade_draws_normal_gem_with_mixed_core() -> void:
	var probe: JamFadeProbe = auto_free(JamFadeProbe.new())
	probe.size = Vector2(400, 200)
	add_child(probe)
	probe.queue_redraw()
	await await_idle_frame()
	assert_bool(probe.drawn).is_true()
