extends GdUnitTestSuite
## VIS-10 / S-10 (UI-SPEC 7.1): no HUD or cockpit-frame element may overlap the note path.
## The keep-out polygon is built from Trench.point (no hard-coded coordinates), expanded by
## 48 px, and intersected with every visible Control rect under Hud, CockpitFrame and
## StreakCounter, and with every keepout_shapes() polygon of the full-screen canvases (W4).
## Allowed exceptions (part of the board): the hull arc and the HULL CRITICAL caption. Early/late
## text, judgment popups and lane numbers live in board layers (Feedback, HighwayNotes) and are
## exempt by layer.

const SCENE := "res://scenes/gameplay.tscn"
const KEEP_OUT_PX := 48.0
const NEAR_D := -0.071
const FAR_D := 1.0

var _saved_no_fail := false


func before_test() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	_saved_no_fail = Settings.no_fail


func after_test() -> void:
	Settings.no_fail = _saved_no_fail
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


static func keep_out_polygon() -> PackedVector2Array:
	var base := PackedVector2Array([Trench.point(-2.0, FAR_D), Trench.point(2.0, FAR_D),
		Trench.point(2.0, NEAR_D), Trench.point(-2.0, NEAR_D)])
	var grown := Geometry2D.offset_polygon(base, KEEP_OUT_PX, Geometry2D.JOIN_MITER)
	return grown[0]


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _hits(poly: PackedVector2Array, keep: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	return not Geometry2D.intersect_polygons(poly, keep).is_empty()


func _launch() -> Gameplay:
	var c := TestCharts.short_chart()
	c.sections.append({"time": 0.6, "name": "verse 1"})
	Gameplay.pending_chart = c
	Gameplay.pending_autoplay = true
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


## Walks `node` and returns offending descriptions.
func _scan(node: Node, keep: PackedVector2Array, allow: Array, vp: Vector2, out: Array) -> void:
	if allow.has(node):
		return
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var c := node as Control
		if c.has_method("keepout_shapes"):
			var shapes: Array = c.call("keepout_shapes")
			for i in shapes.size():
				if _hits(shapes[i], keep):
					out.append("%s keepout_shapes()[%d] %s" % [c.get_path(), i, str(shapes[i])])
		else:
			var r := c.get_global_rect()
			if r.size.x >= vp.x * 0.9 and r.size.y >= vp.y * 0.9:
				out.append("%s is a full-screen canvas without keepout_shapes()" % c.get_path())
			elif _hits(_rect_poly(r), keep):
				out.append("%s rect %s" % [c.get_path(), str(r)])
	for ch in node.get_children():
		_scan(ch, keep, allow, vp, out)


func test_keep_out_polygon_comes_from_trench() -> void:
	var keep := keep_out_polygon()
	# The expanded path contains the board corners and the vanishing point.
	for p in [Trench.point(-2.0, FAR_D), Trench.point(2.0, NEAR_D), Trench.point(0.0, 0.5)]:
		assert_bool(Geometry2D.is_point_in_polygon(p, keep)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Trench.point(0.0, FAR_D) + Vector2(0.0, -KEEP_OUT_PX - 2.0), keep)).is_false()


func test_no_hud_or_frame_element_overlaps_the_note_path() -> void:
	Settings.no_fail = true  # both mode chips on
	var gp := _launch()
	var ok: bool = await _wait_built(gp)
	assert_bool(ok).override_failure_message("gameplay did not build").is_true()
	# Make the transient pieces visible: the section banner mid-hold.
	gp.hud.section_banner.show_section("verse 1")
	gp.hud.section_banner.step(Palette.DUR_BASE + 0.05)
	assert_bool(gp.hud.section_banner.is_visible_in_tree()).is_true()
	await get_tree().process_frame
	var keep := keep_out_polygon()
	var vp := Vector2(1920.0, 1080.0)
	var allow: Array = [gp.hud.hull_arc, gp.hud.hull_caption]
	var bad: Array = []
	for root in [gp.cockpit_frame, gp.hud, gp.streak_counter]:
		_scan(root, keep, allow, vp, bad)
	assert_array(bad).override_failure_message("note-path keep-out violated:\n" + "\n".join(bad)).is_empty()


func test_full_screen_canvases_implement_keepout_shapes() -> void:
	var gp := _launch()
	var ok: bool = await _wait_built(gp)
	assert_bool(ok).is_true()
	for n in [gp.cockpit_frame, gp.hud, gp.streak_counter, gp.hud.progress_track, gp.hud.section_banner]:
		assert_bool((n as Node).has_method("keepout_shapes")).override_failure_message(
			"%s has no keepout_shapes()" % (n as Node).name).is_true()


func test_banner_and_progress_text_sit_outside_the_path() -> void:
	var gp := _launch()
	var ok: bool = await _wait_built(gp)
	assert_bool(ok).is_true()
	var keep := keep_out_polygon()
	var b: SectionBanner = gp.hud.section_banner
	assert_object(b.get_global_rect()).is_equal(Rect2(640.0, 200.0, 640.0, 72.0))
	assert_bool(_hits(_rect_poly(b.get_global_rect()), keep)).is_false()
	var pt: ProgressTrack = gp.hud.progress_track
	for l in [pt.title_label, pt.section_label, pt.time_label]:
		var lab := l as Label
		var base := lab.global_position.y + lab.get_theme_font("font").get_ascent(lab.get_theme_font_size("font_size"))
		assert_float(base).is_less_equal(68.5)
		assert_bool(_hits(_rect_poly(lab.get_global_rect()), keep)).is_false()


func _wait_built(gp: Gameplay) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if gp.hud != null and is_instance_valid(gp.hud) and gp.hud.is_node_ready() and gp.is_began():
			await get_tree().process_frame
			await get_tree().process_frame
			return true
		await get_tree().process_frame
	return false


## The scanner is not vacuous: an intruding Control and a full-screen canvas without
## keepout_shapes() are both reported.
func test_scanner_flags_intruders() -> void:
	var root: Control = auto_free(Control.new())
	add_child(root)
	root.size = Vector2(1920.0, 1080.0)
	var bad_box := Control.new()
	bad_box.position = Trench.point(0.0, 0.5) - Vector2(10.0, 10.0)
	bad_box.size = Vector2(20.0, 20.0)
	root.add_child(bad_box)
	var full := Control.new()
	full.size = Vector2(1920.0, 1080.0)
	root.add_child(full)
	var ok_box := Control.new()
	ok_box.position = Vector2(20.0, 700.0)
	ok_box.size = Vector2(100.0, 100.0)
	root.add_child(ok_box)
	var out: Array = []
	for ch in root.get_children():
		_scan(ch, keep_out_polygon(), [], Vector2(1920.0, 1080.0), out)
	assert_int(out.size()).is_equal(2)
	assert_str(str(out)).contains("without keepout_shapes")
