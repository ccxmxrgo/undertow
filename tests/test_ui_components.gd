extends GdUnitTestSuite
## Smoke tests for the Phase 1 UI building blocks (plan 05): palette/theme, NoteShape,
## Highway, Hud, Feedback, SfxPool and the synthesized hit sounds.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

var _saved_reduce_motion := false


func before_test() -> void:
	_saved_reduce_motion = Settings.reduce_motion


func after_test() -> void:
	Settings.reduce_motion = _saved_reduce_motion


func _hud(score: HullScore) -> Hud:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.bind(score)
	return hud


func test_palette_theme_and_fonts_load() -> void:
	var theme := Palette.load_theme()
	assert_object(theme).is_not_null()
	assert_object(theme.default_font).is_not_null()
	assert_object(Palette.font()).is_not_null()
	assert_object(Palette.bold()).is_not_null()
	assert_bool(theme.has_stylebox("focus", "Button")).is_true()
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_int(focus.border_width_left).is_equal(Palette.EDGE_FOCUS)
	assert_bool(focus.border_color.is_equal_approx(Palette.SONAR)).is_true()
	assert_that(Palette.DESTRUCTIVE).is_equal(Palette.WARNING_RED)


## Legacy aliases point at the Abyssal Cockpit tokens (plan 04 flip; removed in plan 24).
func test_legacy_aliases_follow_new_tokens() -> void:
	assert_that(Palette.ACCENT).is_equal(Palette.SONAR)
	assert_that(Palette.TEXT).is_equal(Palette.TEXT_MID)
	assert_that(Palette.PANEL).is_equal(Palette.ABYSS_700)
	assert_that(Palette.DIM).is_equal(Palette.ABYSS_500)
	assert_that(Palette.BG).is_equal(Palette.ABYSS_900)
	assert_that(Palette.REC_TEXT).is_equal(Palette.TEXT_HI)
	assert_that(Palette.DESTRUCTIVE).is_equal(Palette.WARNING_RED)


func _assert_chamfer(sb: StyleBoxFlat, cut: int) -> void:
	assert_int(sb.corner_radius_top_left).is_equal(cut)
	assert_int(sb.corner_radius_bottom_right).is_equal(cut)
	assert_int(sb.corner_radius_top_right).is_equal(0)
	assert_int(sb.corner_radius_bottom_left).is_equal(0)
	assert_int(sb.corner_detail).is_equal(1)


func test_build_theme_type_variations() -> void:
	var t := UiKit.build_theme()
	assert_that(t.get_color("font_color", "Label")).is_equal(Palette.TEXT_MID)
	assert_int(t.get_font_size("font_size", "Label")).is_equal(Palette.SIZE_BODY)
	assert_that(t.get_color("font_color", "CaptionLabel")).is_equal(Palette.TEXT_LO)
	assert_int(t.get_font_size("font_size", "CaptionLabel")).is_equal(Palette.SIZE_LABEL)
	assert_that(t.get_color("font_color", "HeadingLabel")).is_equal(Palette.TEXT_HI)
	assert_int(t.get_font_size("font_size", "HeadingLabel")).is_equal(Palette.SIZE_HEADING)
	assert_object(t.get_font("font", "HeadingLabel")).is_equal(Palette.display_font())
	assert_that(t.get_color("font_color", "DisplayLabel")).is_equal(Palette.TEXT_HI)
	assert_int(t.get_font_size("font_size", "DisplayLabel")).is_equal(Palette.SIZE_DISPLAY)
	assert_object(t.get_font("font", "DisplayLabel")).is_equal(Palette.display_font())
	for v in ["CaptionLabel", "HeadingLabel", "DisplayLabel"]:
		assert_str(String(t.get_type_variation_base(v))).is_equal("Label")
	assert_object(t.get_font("font", "Button")).is_equal(Palette.bold())
	assert_that(t.get_color("font_color", "Button")).is_equal(Palette.TEXT_MID)
	assert_that(t.get_color("font_focus_color", "Button")).is_equal(Palette.TEXT_HI)


func test_build_theme_button_states_match_ui_spec() -> void:
	var t := UiKit.build_theme()
	var want := {
		"normal": [Color(Palette.ABYSS_700, 0.7), Color(Palette.SONAR, 0.3)],
		"hover": [Color(Palette.ABYSS_700, 0.85), Color(Palette.SONAR, 0.6)],
		"focus": [Color(Palette.ABYSS_600, 0.92), Palette.SONAR],
		"pressed": [Palette.mix(Palette.ABYSS_600, Palette.SONAR, 0.22), Palette.SONAR_PALE],
		"disabled": [Color(Palette.ABYSS_800, 0.5), Color(Palette.TEXT_LO, 0.2)],
	}
	for st: String in want:
		var sb := t.get_stylebox(st, "Button") as StyleBoxFlat
		assert_object(sb).is_not_null()
		assert_bool(sb.bg_color.is_equal_approx(want[st][0])).override_failure_message(st + " fill").is_true()
		assert_bool(sb.border_color.is_equal_approx(want[st][1])).override_failure_message(st + " edge").is_true()
		assert_int(sb.border_width_top).is_equal(Palette.EDGE)
		_assert_chamfer(sb, Palette.CUT_SM)
	var focus := t.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_int(focus.shadow_size).is_equal(Palette.PANEL_GLOW_SIZE)
	assert_float(focus.shadow_color.a).is_equal_approx(Palette.PANEL_GLOW_FOCUS, 0.001)
	var low_focus := UiKit.build_theme(true).get_stylebox("focus", "Button") as StyleBoxFlat
	assert_int(low_focus.shadow_size).is_equal(0)


func test_style_button_variants() -> void:
	var prim := UiKit.style_button("normal", "primary", false)
	assert_bool(prim.bg_color.is_equal_approx(Palette.mix(Palette.ABYSS_600, Palette.SONAR, 0.14))).is_true()
	assert_bool(prim.border_color.is_equal_approx(Color(Palette.SONAR, 0.8))).is_true()
	var dn := UiKit.style_button("normal", "destructive", false)
	assert_bool(dn.bg_color.is_equal_approx(Color(Palette.ABYSS_700, 0.7))).is_true()
	assert_bool(dn.border_color.is_equal_approx(Color(Palette.WARNING_RED, 0.6))).is_true()
	var df := UiKit.style_button("focus", "destructive", false)
	assert_bool(df.bg_color.is_equal_approx(Color(Palette.WARNING_RED, 0.16))).is_true()
	assert_bool(df.border_color.is_equal_approx(Palette.WARNING_RED)).is_true()
	for v in UiKit.BUTTON_VARIANTS:
		for st in UiKit.BUTTON_STATES:
			_assert_chamfer(UiKit.style_button(st, v, false), Palette.CUT_SM)
	assert_that(UiKit.button_font_color("normal", "primary")).is_equal(Palette.TEXT_HI)
	assert_that(UiKit.button_font_color("disabled")).is_equal(Color(Palette.TEXT_LO, 0.6))


func test_style_panel_variants_and_low_effects() -> void:
	var p := UiKit.style_panel("default", false)
	assert_bool(p.bg_color.is_equal_approx(Color(Palette.ABYSS_700, 0.82))).is_true()
	assert_bool(p.border_color.is_equal_approx(Color(Palette.SONAR, 0.45))).is_true()
	assert_int(p.border_width_left).is_equal(Palette.EDGE)
	_assert_chamfer(p, Palette.CUT_MD)
	assert_bool(p.shadow_color.is_equal_approx(Color(Palette.SONAR, 0.18))).is_true()
	assert_int(p.shadow_size).is_equal(12)
	assert_float(p.content_margin_left).is_equal(24.0)
	var d := UiKit.style_panel("danger", false)
	assert_bool(d.border_color.is_equal_approx(Color(Palette.WARNING_RED, 0.6))).is_true()
	var r := UiKit.style_panel("reward", false)
	assert_bool(r.border_color.is_equal_approx(Color(Palette.SONAR, 0.45))).is_true()
	assert_int(UiKit.style_panel("default", true).shadow_size).is_equal(0)
	var saved := Settings.low_effects
	Settings.low_effects = true
	assert_int(UiKit.style_panel().shadow_size).is_equal(0)
	Settings.low_effects = false
	assert_int(UiKit.style_panel().shadow_size).is_equal(12)
	Settings.low_effects = saved


## Pitfall 3: the saved theme must equal the token-built one (regenerate with
## tools/make_theme.gd when a token changes).
func test_saved_theme_matches_build_theme() -> void:
	var saved := ResourceLoader.load(Palette.THEME_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Theme
	assert_object(saved).is_not_null()
	var built := UiKit.build_theme(false)
	for st in ["normal", "focus", "hover", "pressed", "disabled"]:
		var a := saved.get_stylebox(st, "Button") as StyleBoxFlat
		var b := built.get_stylebox(st, "Button") as StyleBoxFlat
		assert_object(a).override_failure_message("saved Button/" + st).is_not_null()
		assert_bool(a.bg_color.is_equal_approx(b.bg_color)).override_failure_message(st + " bg").is_true()
		assert_bool(a.border_color.is_equal_approx(b.border_color)).override_failure_message(st + " edge").is_true()
	for v in ["Label", "CaptionLabel", "HeadingLabel", "DisplayLabel"]:
		assert_bool(saved.get_color("font_color", v).is_equal_approx(built.get_color("font_color", v))) \
			.override_failure_message(v + " font_color").is_true()
	var pa := saved.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var pb := built.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_bool(pa.bg_color.is_equal_approx(pb.bg_color)).is_true()
	var hf := saved.get_font("font", "HeadingLabel") as FontVariation
	assert_object(hf).is_not_null()
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	assert_int(int(hf.variation_opentype.get(tag, 0))).is_equal(700)


func test_note_shapes_cover_four_lanes() -> void:
	assert_int(NoteShape.Kind.size()).is_equal(4)
	assert_int(NoteShape.kind_for_lane(0)).is_equal(NoteShape.Kind.DIAMOND)
	assert_int(NoteShape.kind_for_lane(1)).is_equal(NoteShape.Kind.CIRCLE)
	assert_int(NoteShape.kind_for_lane(2)).is_equal(NoteShape.Kind.TRIANGLE)
	assert_int(NoteShape.kind_for_lane(3)).is_equal(NoteShape.Kind.SQUARE)


func test_synth_sounds_are_non_empty() -> void:
	var tick := AudioSynth.make_tick(1.0, 44100)
	var low := AudioSynth.make_tick(0.75, 44100)
	var clunk := AudioSynth.make_clunk(44100)
	assert_int(tick.data.size()).is_greater(0)
	assert_int(low.data.size()).is_equal(tick.data.size())
	assert_int(clunk.data.size()).is_greater(tick.data.size())
	assert_bool(tick.data == low.data).is_false()


func test_highway_draws_hand_chart_with_sustains_and_pips() -> void:
	var chart := TestCharts.hand_chart()
	var conductor: Conductor = auto_free(Conductor.new())
	add_child(conductor)
	var highway: Highway = auto_free(Highway.new())
	add_child(highway)
	highway.setup(chart, conductor)
	conductor.begin(chart.audio_stream, 1.2)  # lead-in exercises the pre-roll pips
	await get_tree().process_frame
	await get_tree().process_frame
	# Feed state transitions for the first sustain and a normal note.
	var sustain_idx := -1
	for i in range(chart.notes.size()):
		if float(chart.notes[i]["duration"]) > 0.0:
			sustain_idx = i
			break
	assert_int(sustain_idx).is_greater(-1)
	var lane: int = chart.notes[sustain_idx]["lane"]
	highway.on_judged(lane, sustain_idx, P, -0.012)
	highway.on_sustain_end(lane, false)
	highway.on_judged(0, 0, M, 0.09)
	highway.on_stray(2)
	highway.queue_redraw()
	await get_tree().process_frame
	assert_bool(highway.is_inside_tree()).is_true()
	conductor.stop()


func test_hud_values_update_from_hull_score() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	assert_str(hud.hull_value.text).is_equal("100%")
	assert_str(hud.mult_value.text).is_equal("x1")
	for i in range(12):
		score.on_judged(0, i, P, 0.0)
	assert_str(hud.combo_value.text).is_equal("12")
	assert_str(hud.streak_value.text).is_equal("12")
	assert_str(hud.mult_value.text).is_equal("x2")
	assert_str(hud.depth_text(1240.0)).is_equal("1,240 M")
	assert_bool(hud.depth_value.text.ends_with(" M")).is_true()
	score.on_judged(0, 12, M, 0.2)
	assert_str(hud.combo_value.text).is_equal("0")
	assert_str(hud.streak_value.text).is_equal("0")
	assert_str(hud.hull_value.text).is_equal("92%")
	assert_str(hud.hull_caption.text).is_equal("")
	assert_bool(hud.hull_caption.visible).is_false()
	assert_bool(hud.combo_value.visible).is_false()
	assert_bool(hud.hull_value.visible).is_false()


func test_hud_critical_state_below_thirty_percent() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	for i in range(8):
		score.on_judged(0, i, M, 0.2)  # 100 - 64 = 36
	assert_bool(hud.is_critical()).is_false()
	score.on_judged(0, 8, M, 0.2)  # 28
	assert_bool(hud.is_critical()).is_true()
	assert_str(hud.hull_caption.text).is_equal("HULL CRITICAL")
	assert_bool(hud.hull_caption.visible).is_true()
	await get_tree().process_frame
	await get_tree().process_frame


func test_hull_arc_angle_maps_percent_to_arc() -> void:
	assert_float(Hud.hull_arc_angle(100.0)).is_equal_approx(1.114, 0.0001)
	assert_float(Hud.hull_arc_angle(0.0)).is_equal_approx(2.028, 0.0001)
	assert_float(Hud.hull_arc_angle(30.0)).is_equal_approx(2.028 - 0.3 * 0.914, 0.0001)
	assert_float(Hud.hull_arc_angle(150.0)).is_equal_approx(1.114, 0.0001)


func test_hud_no_fail_and_reduce_motion_paths_run() -> void:
	Settings.reduce_motion = true
	var score := HullScore.new(JudgeConfig.new())
	score.no_fail = true
	var hud := _hud(score)
	score.on_judged(0, 0, P, 0.0)
	score.on_judged(0, 1, M, 0.2)
	await get_tree().process_frame
	assert_str(hud.combo_value.text).is_equal("0")
	assert_vector(hud.combo_value.scale).is_equal(Vector2.ONE)


func test_feedback_floating_text_pool_capped_at_six() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	add_child(fb)
	for i in range(20):
		fb.on_judged(i % 4, i, [P, G, M][i % 3], 0.0)
		assert_int(fb.floating_count()).is_less_equal(Feedback.MAX_FLOATING)
	assert_int(fb.floating_count()).is_equal(Feedback.MAX_FLOATING)
	fb.on_stray(1)
	await get_tree().process_frame
	assert_int(fb.floating_count()).is_equal(Feedback.MAX_FLOATING)  # stray spawns no text


func test_feedback_reacts_to_real_judge_signals() -> void:
	var chart := TestCharts.hand_chart()
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	add_child(fb)
	fb.connect_judge(judge)
	var first: Dictionary = chart.notes[0]
	judge.press(first["lane"], first["time"])  # perfect
	assert_int(fb.floating_count()).is_equal(1)
	judge.press((int(first["lane"]) + 1) % 4, 0.0)  # nothing there: stray or early miss, never an error
	judge.tick(first["time"] + 10.0)  # expires the rest as misses
	assert_int(fb.floating_count()).is_equal(Feedback.MAX_FLOATING)
	await get_tree().process_frame


func test_feedback_miss_nudge_and_reduce_motion() -> void:
	var target: Control = auto_free(Control.new())
	add_child(target)
	target.position = Vector2(10.0, 20.0)
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	fb.nudge_target = target
	add_child(fb)
	Settings.reduce_motion = false
	fb.on_judged(0, 0, M, 0.2)
	assert_vector(target.position).is_equal(Vector2(18.0, 20.0))
	var end := Time.get_ticks_usec() + 250000
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
	assert_vector(target.position).is_equal(Vector2(10.0, 20.0))
	Settings.reduce_motion = true
	fb.on_judged(0, 1, M, 0.2)
	assert_vector(target.position).is_equal(Vector2(10.0, 20.0))


func test_feedback_with_sfx_pool_plays_without_error() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	add_child(fb)
	assert_object(fb.sfx).is_not_null()
	fb.on_judged(0, 0, P, 0.0)
	fb.on_judged(1, 1, G, 0.04)
	fb.on_judged(2, 2, M, 0.2)
	await get_tree().process_frame


func test_feedback_flash_state_per_lane_and_spawn_offset() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	add_child(fb)
	fb.on_judged(2, 0, P, 0.0)
	assert_object(fb._flashes[2]).is_not_null()
	assert_object(fb._flashes[0]).is_null()
	assert_int(fb.floating_count()).is_equal(1)
	assert_float(Trench.hit_point(1).y - Feedback.FLOAT_START_OFFSET).is_equal_approx(Trench.HIT_Y - Feedback.FLOAT_START_OFFSET, 0.5)
