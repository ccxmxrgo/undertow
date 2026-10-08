extends GdUnitTestSuite
## Goggles-on intro wiring (plan 01.2-04): conductor/judge/input gating, skip, quick restart,
## 3-beat lead-in, board hand-over and restoration.

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 40000
const SCORES_TMP := "user://test_intro_flow_scores.cfg"
const SPB := 0.5  # short_chart is 120 bpm

var _old_scores_path: String


func before_test() -> void:
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP
	_rm_scores()
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func after_test() -> void:
	ScoreStore.default_path = _old_scores_path
	_rm_scores()
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _rm_scores() -> void:
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _launch(autoplay: bool = false) -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = autoplay
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_until(cond: Callable, msec: int = 8000) -> void:
	var deadline := Time.get_ticks_msec() + msec
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait_done(gp: Gameplay) -> void:
	await _wait_until(func() -> bool: return gp.is_done(), TIMEOUT_MSEC)


func test_gating_before_count_in() -> void:
	var gp := _launch()
	await _frames(3)
	assert_bool(gp.is_began()).is_false()
	assert_int(gp.intro_mode).is_equal(IntroTimeline.Mode.FULL)
	assert_object(gp.intro).is_not_null()
	assert_float(gp.conductor.song_time()).is_equal(0.0)
	assert_bool(gp.lane_input.enabled).is_false()
	assert_int(gp.score.perfect_count + gp.score.good_count + gp.score.miss_count).is_equal(0)
	# the board is hidden while the room/goggles play
	assert_float(gp.arena.reveal).is_equal(0.0)
	assert_float(gp.highway.cable_grow).is_equal(0.0)


func test_skip_begins_three_beat_count_in() -> void:
	var gp := _launch()
	await _frames(2)
	gp.intro.skip()
	await _frames(3)
	assert_bool(gp.is_began()).is_true()
	assert_bool(gp.lane_input.enabled).is_true()
	assert_float(gp.conductor.song_time()).is_between(-3.0 * SPB - 0.05, -3.0 * SPB + 0.2)
	var t_before := gp.conductor.song_time()
	gp.intro.skip()  # second skip does nothing
	await _frames(1)
	assert_float(gp.conductor.song_time()).is_greater_equal(t_before)


func test_fire_action_skips() -> void:
	var gp := _launch()
	await _frames(2)
	var ev := InputEventAction.new()
	ev.action = &"fire"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	assert_bool(gp.is_began()).is_true()


func test_escape_before_count_skips_and_does_not_pause() -> void:
	var gp := _launch()
	await _frames(2)
	var ev := InputEventAction.new()
	ev.action = &"pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	assert_bool(gp.is_began()).is_true()
	assert_bool(gp.pause_menu.is_open()).is_false()


func test_full_precount_then_count_then_overlay_frees_and_restores_board() -> void:
	var gp := _launch()
	await _frames(2)
	var intro: GogglesIntro = gp.intro
	intro.advance(3.0)  # past the 2.6 s pre-count
	await _frames(3)
	assert_bool(gp.is_began()).is_true()
	assert_bool(intro.is_counting()).is_true()
	assert_float(gp.conductor.song_time()).is_less(0.0)
	# 3 beats (1.5 s) + DIVE (0.6 s)
	var iid := intro.get_instance_id()
	await _wait_until(func() -> bool: return not is_instance_id_valid(iid), 6000)
	assert_bool(is_instance_valid(intro)).is_false()
	assert_float(gp.arena.reveal).is_equal(1.0)
	assert_float(gp.highway.cable_grow).is_equal(1.0)
	assert_float(gp.highway.receptor_alpha).is_equal(1.0)
	assert_float(gp.highway.cable_bright).is_equal(0.0)
	assert_float(gp.hud.modulate.a).is_equal(1.0)
	assert_float(gp.streak_counter.modulate.a).is_equal(1.0)


func test_restart_uses_quick_intro_and_one_beat_lead_in() -> void:
	var gp := _launch()
	await _frames(2)
	gp.restart(false)
	await _frames(2)
	assert_int(gp.intro_mode).is_equal(IntroTimeline.Mode.QUICK)
	assert_bool(gp.is_began()).is_false()
	gp.intro.advance(1.0)
	await _frames(3)
	assert_bool(gp.is_began()).is_true()
	assert_float(gp.conductor.song_time()).is_between(-SPB - 0.05, -SPB + 0.2)


func test_restart_with_intro_none_stays_none() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	var gp := _launch()
	await _frames(2)
	assert_bool(gp.is_began()).is_true()
	assert_object(gp.intro).is_null()
	gp.restart(false)
	await _frames(2)
	assert_int(gp.intro_mode).is_equal(IntroTimeline.Mode.NONE)
	assert_bool(gp.is_began()).is_true()
	assert_float(gp.conductor.song_time()).is_between(-3.0 * SPB - 0.05, -3.0 * SPB + 0.3)


func test_restart_mid_intro_does_not_leave_board_hidden() -> void:
	var gp := _launch()
	await _frames(2)
	var old_arena := gp.arena
	var old_highway := gp.highway
	gp.restart(false)  # old nodes are only queue_freed: still valid this frame
	assert_float(old_arena.reveal).is_equal(1.0)
	assert_float(old_highway.cable_grow).is_equal(1.0)
	await _frames(2)  # let the queued frees run


func test_autoplay_with_skip_is_all_perfect() -> void:
	var gp := _launch(true)
	await _frames(2)
	assert_bool(gp.lane_input.enabled).is_false()
	gp.intro.skip()
	await _wait_done(gp)
	assert_bool(gp.is_done()).is_true()
	assert_int(gp.score.miss_count).is_equal(0)
	assert_int(gp.score.good_count).is_equal(0)
	assert_int(gp.score.perfect_count).is_equal(gp.chart.notes.size())


func test_no_preroll_pip_constant_remains() -> void:
	var f := FileAccess.open("res://src/ui/highway.gd", FileAccess.READ)
	assert_bool(f.get_as_text().contains("PREROLL_BEATS")).is_false()


func test_intro_source_has_no_goggles_drawing() -> void:
	var f := FileAccess.open("res://src/ui/goggles_intro.gd", FileAccess.READ)
	assert_object(f).is_not_null()
	var src := f.get_as_text().to_lower()
	f.close()
	for token in ["_frame_sb", "strap", "draw_circle(vector2(0, -70)", "_draw_goggles"]:
		assert_bool(src.contains(token)).is_false()
