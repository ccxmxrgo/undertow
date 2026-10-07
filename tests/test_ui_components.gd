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
	assert_int(focus.border_width_left).is_equal(4)
	assert_bool(focus.border_color.is_equal_approx(Palette.ACCENT)).is_true()
	assert_that(Palette.DESTRUCTIVE).is_equal(Color("FF4A3D"))


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
	assert_str(hud.hull_caption.text).is_equal("HULL")


func test_hud_critical_state_below_thirty_percent() -> void:
	var score := HullScore.new(JudgeConfig.new())
	var hud := _hud(score)
	for i in range(8):
		score.on_judged(0, i, M, 0.2)  # 100 - 64 = 36
	assert_bool(hud.is_critical()).is_false()
	score.on_judged(0, 8, M, 0.2)  # 28
	assert_bool(hud.is_critical()).is_true()
	assert_str(hud.hull_caption.text).is_equal("HULL CRITICAL")
	await get_tree().process_frame
	await get_tree().process_frame


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
	assert_float(Highway.HULL_Y - Feedback.FLOAT_START_OFFSET).is_equal(816.0)
