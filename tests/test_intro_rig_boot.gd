extends GdUnitTestSuite
## 02.2-20 (UI-SPEC 9.5, D-12): the intro room is replaced by the rig-boot stage. Stage
## boundaries (IntroTimeline) are unchanged; this suite covers the rig-boot drawing model,
## the Cinematic count numerals and the effect contract. Timing itself is covered by
## test_intro_timeline.gd and test_intro_flow.gd (unchanged).

const SRC := "res://src/ui/goggles_intro.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(SRC)


func test_room_drawing_and_hot_red_are_gone() -> void:
	var src := _src()
	for token in ["_draw_room", "FF1F4B", "HOT_RED", "draw_circle(Vector2(1216"]:
		assert_bool(src.contains(token)).override_failure_message("still in goggles_intro.gd: " + token).is_false()
	assert_bool(src.contains("_draw_rig_boot")).is_true()


func test_rig_rings_expand_and_fade() -> void:
	assert_array(GogglesIntro.RING_STARTS).is_equal([0.05, 0.45])
	assert_float(GogglesIntro.RING_SEC).is_equal_approx(0.7, 0.0001)
	assert_float(GogglesIntro.RING_MAX_R).is_equal(420.0)
	assert_object(GogglesIntro.RIG_CENTER).is_equal(Vector2(960, 540))
	# Before its start a ring is not drawn.
	assert_float(GogglesIntro.rig_ring(0.0, 0, false)["a"]).is_equal(0.0)
	assert_float(GogglesIntro.rig_ring(0.4, 1, false)["a"]).is_equal(0.0)
	# At its start: r 0, alpha 0.35. Half-way: r 210, alpha 0.175. After 0.7 s: gone.
	var s0: Dictionary = GogglesIntro.rig_ring(0.05, 0, false)
	assert_float(s0["r"]).is_equal_approx(0.0, 0.001)
	assert_float(s0["a"]).is_equal_approx(0.35, 0.001)
	var mid: Dictionary = GogglesIntro.rig_ring(0.45 + 0.35, 1, false)
	assert_float(mid["r"]).is_equal_approx(210.0, 0.01)
	assert_float(mid["a"]).is_equal_approx(0.175, 0.001)
	assert_float(GogglesIntro.rig_ring(0.05 + 0.71, 0, false)["a"]).is_equal(0.0)
	# Reduce motion: static rings at r 300, alpha 0.2, from the start.
	for i in 2:
		var rm: Dictionary = GogglesIntro.rig_ring(0.0, i, true)
		assert_float(rm["r"]).is_equal(300.0)
		assert_float(rm["a"]).is_equal_approx(0.2, 0.0001)


func test_rig_text_types_at_40_chars_per_second() -> void:
	assert_str(GogglesIntro.RIG_TEXT).is_equal("NEURAL DIVE RIG · READY")
	assert_object(GogglesIntro.RIG_TEXT_AT).is_equal(Vector2(960, 548))
	assert_int(GogglesIntro.rig_text_chars(0.05, false)).is_equal(0)
	assert_int(GogglesIntro.rig_text_chars(0.10, false)).is_equal(0)
	assert_int(GogglesIntro.rig_text_chars(0.10 + 0.25, false)).is_equal(10)
	var n := GogglesIntro.RIG_TEXT.length()
	assert_int(GogglesIntro.rig_text_chars(1.0, false)).is_equal(n)
	assert_int(GogglesIntro.rig_text_chars(0.0, true)).is_equal(n)  # Reduce motion: shown at once


func test_count_numerals_are_cinematic_oxanium() -> void:
	assert_int(GogglesIntro.NUMERAL_SIZE).is_equal(176)
	assert_int(GogglesIntro.numeral_size(0.0, false)).is_equal(211)
	assert_int(GogglesIntro.numeral_size(1.0, false)).is_equal(176)
	assert_int(GogglesIntro.numeral_size(0.0, true)).is_equal(176)
	assert_object(GogglesIntro.numeral_font()).is_same(Palette.display_font())


func test_intro_is_an_effect_node() -> void:
	var saved_rm: bool = Settings.reduce_motion
	var saved_low: bool = Settings.low_effects
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var intro := GogglesIntro.new()
	host.add_child(intro)
	assert_bool(intro.is_in_group(UiKit.FX_GROUP)).is_true()
	Settings.reduce_motion = false
	Settings.low_effects = false
	intro.apply_effect_settings()
	var c := intro.effect_counts()
	assert_bool(c["rings_animated"]).is_true()
	assert_bool(c["numeral_glow"]).is_true()
	Settings.low_effects = true
	intro.apply_effect_settings()
	assert_bool(intro.effect_counts()["numeral_glow"]).is_false()
	assert_bool(intro.effect_counts()["rings_animated"]).is_true()
	Settings.reduce_motion = true
	intro.apply_effect_settings()
	assert_bool(intro.effect_counts()["rings_animated"]).is_false()
	Settings.reduce_motion = saved_rm
	Settings.low_effects = saved_low
