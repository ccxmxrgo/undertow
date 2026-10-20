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
	MatchSetup.pending = null
	VersusController.test_autoplay_human = false
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


## Versus launch (03-14): MatchSetup.pending with 3 rivals; the human is the test autoplay seam.
func _launch_versus() -> Gameplay:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = 3
	m.skill = "regular"
	m.seed = 777
	MatchSetup.pending = m
	VersusController.test_autoplay_human = true
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


## Feeds one event straight to every versus view (no referee or rig side effects).
func _feed(v: VersusController, e: Dictionary) -> void:
	v.periscope_column.call("_on_event", e)
	for n: Object in [v.killfeed, v.incoming_alert, v.event_banner, v.reward_popup, v.reward_socket,
			v.target_readout, v.status_chips]:
		n.call("on_event", e)


## UI-SPEC 13: every versus element in its largest state sits at its exact rect and outside the
## note-path keep-out (VersusHud children plus the new Hud children and the 6-chip stack).
func test_versus_hud_elements_keep_out_of_the_note_path() -> void:
	var gp := _launch_versus()
	var ok: bool = await _wait_built(gp)
	assert_bool(ok).override_failure_message("versus gameplay did not build").is_true()
	gp.set_process(false)  # freeze the match: only the views' own animation steps run
	var v := gp.versus
	var t := gp.conductor.song_time()
	# Longest names, so one killfeed line needs the overflow fallback.
	v.killfeed.bind(v.channel, 0, PackedStringArray(["YOU", "BARRACUDA", "LAMPREY", "NARWHAL"]), v.cfg)
	var ev := func(type: String, fields: Dictionary) -> Dictionary: return GameEvent.make(type, t, fields)
	# Periscopes: bounty on P1, reticle on P1; socket held + queued; readout locked.
	_feed(v, ev.call(GameEvent.BOUNTY_MOVED, {"from_seat": -1, "to_seat": 1}))
	_feed(v, ev.call(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.LOCKED, "target": 1}))
	_feed(v, ev.call(GameEvent.METER, {"seat": 0, "progress": 3, "threshold": 3,
		"held": Reward.Id.INK_CLOUD, "queued": Reward.Id.OVERCLOCK, "debris": false}))
	# Killfeed: 4 lines, one long bounty claim.
	_feed(v, ev.call(GameEvent.LANDED, {"id": 90, "from": 1, "to": 2, "reward": Reward.Id.INK_CLOUD}))
	_feed(v, ev.call(GameEvent.COLLISION, {"a": 2, "b": 3, "ids": [91, 92],
		"reward_a": Reward.Id.SONAR_JAM, "reward_b": Reward.Id.GHOST_NOTES}))
	_feed(v, ev.call(GameEvent.REFLECTED, {"id": 93, "by": 3, "to": 1, "reward": Reward.Id.DEPTH_CHARGE}))
	_feed(v, ev.call(GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 3, "refund": 2}))
	# Alert slot INCOMING; event banner SOLO DUEL live; reward popup.
	_feed(v, ev.call(GameEvent.TORPEDO_LAUNCH, {"id": 94, "from": 1, "to": 0, "reward": Reward.Id.INK_CLOUD,
		"launch_beat": 1, "launch_t": t, "arrive_t": t + 2.0, "warheads": [], "reflected": false,
		"debris": false}))
	_feed(v, ev.call(GameEvent.DUEL_ANNOUNCE, {"solo": 0, "start": t, "end": t + 20.0, "note_count": 24}))
	_feed(v, ev.call(GameEvent.DUEL_START, {"solo": 0}))
	_feed(v, ev.call(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	# Status chips at the 6-chip maximum.
	_feed(v, ev.call(GameEvent.STATUS, {"seat": 0, "hull": 80.0, "depth": 100.0, "alive": true, "place": 1,
		"accuracy": 1.0}))
	_feed(v, ev.call(GameEvent.BUFF_APPLIED, {"seat": 0, "reward": Reward.Id.DECOY_FLARE, "until_t": t + 8.0}))
	_feed(v, ev.call(GameEvent.BUFF_APPLIED, {"seat": 0, "reward": Reward.Id.OVERCLOCK, "until_t": t + 8.0}))
	_feed(v, ev.call(GameEvent.BUFF_APPLIED, {"seat": 0, "reward": Reward.Id.BALLAST_PATCH, "until_t": t,
		"amount": 25.0}))
	_feed(v, ev.call(GameEvent.PAYLOAD_END, {"id": 95, "seat": 0, "reward": Reward.Id.SONAR_JAM,
		"reason": "expired", "immune_until": t + 6.0}))
	gp.hud.set_chip("BOUNTY", "BOUNTY ON YOU", "reward", "bounty", true)
	v.incoming_alert.observe(t + 0.05)
	v.event_banner.observe(t + 0.05)
	v.periscope_column.update(t + 0.05)
	for i in 30:  # slides, pops and the reticle glide settle
		await get_tree().process_frame
	# Everything is showing.
	var col := v.periscope_column
	assert_int(col.panels().size()).is_equal(3)
	assert_bool(col.panels()[0].bounty()).is_true()
	assert_bool(col.has_reticle()).is_true()
	assert_int(v.killfeed.lines().size()).is_equal(4)
	assert_bool(v.incoming_alert.is_showing()).is_true()
	assert_bool(v.event_banner.is_showing()).is_true()
	assert_bool(v.reward_popup.showing()).is_true()
	assert_int(gp.hud.chip_rects().size()).is_equal(6)
	# Exact rects (UI-SPEC 13).
	var want_panels := [Rect2(24, 216, 352, 88), Rect2(24, 312, 352, 88), Rect2(24, 408, 352, 88)]
	for i in 3:
		assert_object(col.panels()[i].get_global_rect()).is_equal(want_panels[i])
	assert_object(v.killfeed.get_global_rect()).is_equal(Rect2(1544, 216, 352, 184))
	assert_object(v.incoming_alert.get_global_rect()).is_equal(Rect2(640, 120, 640, 72))
	assert_object((v.event_banner.get_node("Panel") as Control).get_global_rect()).is_equal(
		Rect2(640, 200, 640, 72))
	assert_object(v.target_readout.get_global_rect()).is_equal(Rect2(248, 752, 144, 88))
	assert_object(v.reward_socket.get_global_rect()).is_equal(Rect2(272, 928, 80, 80))
	# Nothing intersects the keep-out polygon.
	var keep := keep_out_polygon()
	var vp := Vector2(1920.0, 1080.0)
	var allow: Array = [gp.hud.hull_arc, gp.hud.hull_caption]
	var bad: Array = []
	for root in [gp.cockpit_frame, gp.hud, v.versus_hud, gp.streak_counter]:
		_scan(root, keep, allow, vp, bad)
	assert_array(bad).override_failure_message("versus keep-out violated:\n" + "\n".join(bad)).is_empty()
	assert_int(v.versus_hud.keepout_shapes().size()).is_greater_equal(6)
	for s in v.versus_hud.keepout_shapes():
		assert_bool(_hits(s, keep)).override_failure_message("VersusHud shape %s" % str(s)).is_false()


func test_versus_full_screen_canvases_implement_keepout_shapes() -> void:
	var gp := _launch_versus()
	var ok: bool = await _wait_built(gp)
	assert_bool(ok).is_true()
	var v := gp.versus
	for n in [v.versus_hud, v.periscope_column, v.event_banner, v.edge_flash, v.reward_popup]:
		assert_bool((n as Node).has_method("keepout_shapes")).override_failure_message(
			"%s has no keepout_shapes()" % (n as Node).name).is_true()


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


## 04-07 (04-UI-SPEC 11.4, 16): the Leave Match overlay sits at its exact rect (640, 120, 640, 152)
## and entirely outside the note-path keep-out, so it can stay open while the song keeps playing.
## StartSyncOverlay (600, 340, 720, 400) is the DECLARED EXCEPTION (UI-SPEC 10.2, Defaults Log
## 11): it lies inside the keep-out but is only shown before the conductor begins, when no note
## exists on the board. Here we only pin its declared rect; the "hidden before notes can draw"
## proof (gone by conductor.begin + DUR_BASE) lives with the gameplay wiring in 04-14.
func test_online_overlays_rects_and_keep_out() -> void:
	var root: Control = auto_free(Control.new())
	root.size = Vector2(1920.0, 1080.0)
	add_child(root)
	var leave := LeaveOverlay.new()
	root.add_child(leave)
	leave.open(false, 30)
	leave.step(1.0)  # past the slide-in
	await get_tree().process_frame
	var keep := keep_out_polygon()
	assert_object(leave.get_global_rect()).is_equal(Rect2(640, 120, 640, 152))
	assert_bool(_hits(_rect_poly(leave.get_global_rect()), keep)).override_failure_message(
		"LeaveOverlay intersects the note-path keep-out").is_false()
	var bad: Array = []
	_scan(leave, keep, [], Vector2(1920.0, 1080.0), bad)
	assert_array(bad).override_failure_message("LeaveOverlay children:\n" + "\n".join(bad)).is_empty()
	# Its bottom edge (272) is above the keep-out's top (the SPEC's y 348 note-path edge).
	var top := INF
	for p in keep:
		top = minf(top, p.y)
	assert_float(leave.get_global_rect().end.y).is_less(top)
	var sync := StartSyncOverlay.new()
	root.add_child(sync)
	await get_tree().process_frame
	assert_object(sync.get_global_rect()).is_equal(Rect2(600, 340, 720, 400))
	# Documented: the exception really is inside the keep-out (so the 04-14 proof matters).
	assert_bool(_hits(_rect_poly(sync.get_global_rect()), keep)).is_true()
