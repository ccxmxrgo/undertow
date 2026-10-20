extends GdUnitTestSuite
## 04-08: online states of the Phase 3 in-match views (04-UI-SPEC 10.3, 11.3, 11.5, 11.7):
## EventBanner MATCH START countdown and WAITING FOR RESULTS, the client "NO HOST SIGNAL" link
## chip (StatusChips + Hud stack and keep-out), and PLAYER_LEFT in Killfeed and PeriscopePanel.

const NAMES := ["YOU", "MAKO", "ORCA", "BARRACUDA"]
const KEEP_OUT_PX := 48.0
const NEAR_D := -0.071
const FAR_D := 1.0

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


func _live(_seat: int) -> float:
	return -1.0


func _section(sections: Array) -> SectionBanner:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 199.0)
	for s in sections:
		c.sections.append({"time": float(s[0]), "name": str(s[1])})
	c.finalize()
	var b: SectionBanner = auto_free(SectionBanner.new())
	add_child(b)
	b.setup(c, null)
	return b


func _banner(ch: EventChannel, section: SectionBanner = null) -> EventBanner:
	var b: EventBanner = auto_free(EventBanner.new())
	add_child(b)
	b.bind(ch, 0, NAMES, VersusConfig.new(), _live, section)
	return b


# ---- EventBanner countdown (10.3) --------------------------------------------------------

func test_countdown_digits_from_song_time() -> void:
	assert_str(EventBanner.countdown_text_at(-2.4)).is_equal("DIVE IN 3")
	assert_str(EventBanner.countdown_text_at(-1.5)).is_equal("DIVE IN 2")
	assert_str(EventBanner.countdown_text_at(-0.2)).is_equal("DIVE IN 1")
	assert_str(EventBanner.countdown_text_at(-7.0)).is_equal("DIVE IN 3")  # clamped 1..3
	assert_str(EventBanner.countdown_text_at(0.0)).is_equal("DIVE")
	assert_str(EventBanner.countdown_text_at(0.5)).is_equal("DIVE")
	assert_str(EventBanner.countdown_text_at(0.95)).is_equal("")


func test_countdown_state_follows_song_time_and_is_gone_by_0_9() -> void:
	var ch := LoopbackChannel.new()
	var b := _banner(ch)
	b.start_countdown(-2.4, 2)
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.COUNTDOWN)
	assert_str(b.caption_text()).is_equal("ALL SUBS LINKED")
	assert_object(b.caption_color()).is_equal(Palette.SONAR)
	assert_str(b.headline_text()).is_equal("DIVE IN 3")
	assert_object(b.headline_color()).is_equal(Palette.TEXT_HI)
	assert_str(b.right_text()).is_equal("FLIGHT 2 BEATS")
	assert_object(b.right_color()).is_equal(Palette.TEXT_MID)
	assert_float(b.slide_offset()).is_less(0.0)  # slides down 24 px on entry
	b.step(Palette.DUR_BASE)
	b.observe(-1.5)
	assert_str(b.headline_text()).is_equal("DIVE IN 2")
	b.observe(-0.2)
	assert_str(b.headline_text()).is_equal("DIVE IN 1")
	b.observe(0.0)
	assert_str(b.headline_text()).is_equal("DIVE")
	assert_object(b.headline_color()).is_equal(Palette.SONAR_PALE)
	b.observe(0.5)
	assert_int(b.phase()).is_equal(EventBanner.Phase.HOLD)  # "DIVE" holds 600 ms
	b.observe(0.7)
	assert_int(b.phase()).is_equal(EventBanner.Phase.OUT)
	assert_float(b.alpha()).is_less(1.0)
	b.observe(0.95)
	assert_bool(b.is_showing()).is_false()
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.NONE)
	assert_str(EventBanner.flight_text(1)).is_equal("FLIGHT 1 BEAT")


func test_countdown_digit_cross_fade_and_reduce_motion_swap() -> void:
	var b := _banner(LoopbackChannel.new())
	b.start_countdown(-2.5, 2)
	b.step(Palette.DUR_BASE)
	b.observe(-1.9)
	b.step(Palette.DUR_FAST * 0.5)  # mid cross-fade: still showing, panel alpha 1
	assert_str(b.headline_text()).is_equal("DIVE IN 2")
	Settings.reduce_motion = true
	var r := _banner(LoopbackChannel.new())
	r.start_countdown(-2.5, 2)
	assert_float(r.slide_offset()).is_equal(0.0)  # fade in only
	r.observe(-1.9)
	assert_str(r.headline_text()).is_equal("DIVE IN 2")


func test_countdown_progress_drains_from_receipt_to_zero() -> void:
	var b := _banner(LoopbackChannel.new())
	b.start_countdown(-2.0, 2)
	assert_float(b.countdown_progress()).is_equal_approx(1.0, 1e-6)
	b.observe(-1.0)
	assert_float(b.countdown_progress()).is_equal_approx(0.5, 1e-6)
	b.observe(0.0)
	assert_float(b.countdown_progress()).is_equal_approx(0.0, 1e-6)


func test_countdown_beats_section_and_other_banners() -> void:
	var sec := _section([[-5.0, "intro"], [30.0, "chorus"]])
	var ch := LoopbackChannel.new()
	var b := _banner(ch, sec)
	b.start_countdown(-2.0, 2)
	assert_bool(sec.suppressed).is_true()  # the section name waits in the progress track
	assert_bool(EventBanner.priority_of(EventBanner.Kind.COUNTDOWN)
		> EventBanner.priority_of(EventBanner.Kind.IMPLOSION)).is_true()
	ch.send(GameEvent.make(GameEvent.LAST_STANDING, -1.0, {"seat": 1}))
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.COUNTDOWN)
	assert_array(b.pending_kinds()).contains([EventBanner.Kind.LAST_STANDING])
	b.observe(0.95)
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.LAST_STANDING)  # comes back afterwards


func test_countdown_late_receipt_never_shows() -> void:
	var b := _banner(LoopbackChannel.new())
	b.start_countdown(0.92, 2)
	assert_bool(b.is_showing()).is_false()


# ---- EventBanner waiting (11.7) ----------------------------------------------------------

func test_waiting_state_copy() -> void:
	var b := _banner(LoopbackChannel.new())
	b.show_waiting(2)
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.WAITING)
	assert_str(b.caption_text()).is_equal("MATCH COMPLETE")
	assert_object(b.caption_color()).is_equal(Palette.SONAR)
	assert_str(b.headline_text()).is_equal("WAITING FOR RESULTS")
	assert_object(b.headline_color()).is_equal(Palette.TEXT_HI)
	assert_str(b.right_text()).is_equal("2 SUBS STILL DIVING")
	b.show_waiting(0)
	assert_str(b.right_text()).is_equal("")
	b.step(Palette.DUR_BASE)
	b.step(10.0)
	assert_int(b.current_kind()).is_equal(EventBanner.Kind.WAITING)  # stays until hidden
	b.hide_waiting()
	assert_int(b.phase()).is_equal(EventBanner.Phase.OUT)
	b.step(0.31)
	assert_bool(b.is_showing()).is_false()


# ---- Link chip (11.5) --------------------------------------------------------------------

func _hud() -> Hud:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.bind(HullScore.new(JudgeConfig.new()))
	return hud


func _chips(hud: Hud) -> StatusChips:
	var sc: StatusChips = auto_free(StatusChips.new())
	add_child(sc)
	sc.bind(LoopbackChannel.new(), 0, hud, VersusConfig.new(), null, 4, false)
	return sc


func test_link_chip_shows_first_and_hides() -> void:
	var hud := _hud()
	var sc := _chips(hud)
	hud.set_chip("PLACE", "2ND OF 4", "info", "", true)
	assert_bool(hud.chip_rects().has(Hud.CHIP_LINK)).is_false()
	sc.set_link_weak(true)
	assert_bool(sc.is_link_weak()).is_true()
	var keys: Array = hud.chip_rects().keys()
	assert_str(str(keys[0])).is_equal(Hud.CHIP_LINK)
	assert_float((hud.chip_rects()[Hud.CHIP_LINK] as Rect2).position.y).is_equal(824.0)
	assert_float((hud.chip_rects()["PLACE"] as Rect2).position.y).is_equal(864.0)
	assert_str(hud.chip_text(Hud.CHIP_LINK)).is_equal("NO HOST SIGNAL")
	assert_str(hud.chip_variant(Hud.CHIP_LINK)).is_equal("danger")
	assert_float((hud.chip_rects()[Hud.CHIP_LINK] as Rect2).size.x).is_less_equal(Hud.CHIP_MAX_W)
	sc.set_link_weak(false)
	assert_bool(hud.chip_rects().has(Hud.CHIP_LINK)).is_false()
	assert_float((hud.chip_rects()["PLACE"] as Rect2).position.y).is_equal(824.0)
	await get_tree().process_frame


func _six_others(hud: Hud) -> void:
	hud.set_chip("PLACE", "2ND OF 4", "info", "", true)
	hud.set_chip("BOUNTY", "BOUNTY ON YOU", "reward", "bounty", true)
	hud.set_chip("DECOY", "DECOY ARMED 2", "info", "decoy_flare", true)
	hud.set_chip("OVERCLOCK", "OVERCLOCK 3", "info", "overclock", true)
	hud.set_chip("BALLAST", "HULL +25", "info", "ballast_patch", true)
	hud.set_chip("IMMUNE", "IMMUNE", "muted", "shield", true)


func test_link_chip_overflow_hides_ballast_then_immune() -> void:
	var hud := _hud()
	var sc := _chips(hud)
	_six_others(hud)
	assert_int(hud.chip_rects().size()).is_equal(6)
	sc.set_link_weak(true)
	var r := hud.chip_rects()
	assert_int(r.size()).is_equal(6)
	assert_bool(r.has(Hud.CHIP_LINK)).is_true()
	assert_bool(r.has("BALLAST")).is_false()  # BALLAST hides first
	assert_bool(r.has("IMMUNE")).is_true()
	hud.set_autoplay(true)  # 8 wanted: IMMUNE hides next
	r = hud.chip_rects()
	assert_int(r.size()).is_equal(6)
	assert_bool(r.has("IMMUNE")).is_false()
	assert_bool(r.has("OVERCLOCK")).is_true()
	sc.set_link_weak(false)  # without the link chip the Phase 3 cut-off is unchanged
	r = hud.chip_rects()
	assert_int(r.size()).is_equal(6)
	assert_array(r.keys()).is_equal(["AUTOPLAY", "PLACE", "BOUNTY", "DECOY", "OVERCLOCK", "BALLAST"])
	await get_tree().process_frame


static func _keep_out_polygon() -> PackedVector2Array:
	var base := PackedVector2Array([Trench.point(-2.0, FAR_D), Trench.point(2.0, FAR_D),
		Trench.point(2.0, NEAR_D), Trench.point(-2.0, NEAR_D)])
	return Geometry2D.offset_polygon(base, KEEP_OUT_PX, Geometry2D.JOIN_MITER)[0]


func test_link_chip_stack_keeps_out_of_the_note_path() -> void:
	var hud := _hud()
	var sc := _chips(hud)
	_six_others(hud)
	sc.set_link_weak(true)
	var keep := _keep_out_polygon()
	var shapes := hud.keepout_shapes()
	var r := hud.chip_rects()
	var found_link := false
	for key in r:
		var rect: Rect2 = r[key]
		var poly := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
		assert_bool(Geometry2D.intersect_polygons(poly, keep).is_empty()).override_failure_message(
			"%s chip %s overlaps the note path" % [key, str(rect)]).is_true()
		if key == Hud.CHIP_LINK:
			found_link = true
	assert_bool(found_link).is_true()
	for s in shapes:
		assert_bool(Geometry2D.intersect_polygons(s, keep).is_empty()).is_true()
	assert_int(shapes.size()).is_greater_equal(7 + 6)  # 7 fixed readouts + 6 chips
	await get_tree().process_frame
