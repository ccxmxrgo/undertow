extends GdUnitTestSuite
## Gameplay scene end to end (plan 06 task 1): autoplay run finishes all-Perfect and the
## results screen is flagged AUTOPLAY USED; F4 restarts a manual run with autoplay on.

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 40000

var _saved_no_fail := false


func before_test() -> void:
	_saved_no_fail = Settings.no_fail
	Settings.no_fail = false


func after_test() -> void:
	Settings.no_fail = _saved_no_fail
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false


func _launch(autoplay: bool) -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = autoplay
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _wait_done(gp: Gameplay) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not gp.is_done() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func test_autoplay_run_is_all_perfect_and_flagged() -> void:
	var gp := _launch(true)
	await _wait_done(gp)
	assert_bool(gp.is_done()).is_true()
	assert_int(gp.state).is_equal(Gameplay.State.DONE)
	assert_int(gp.score.miss_count).is_equal(0)
	assert_int(gp.score.good_count).is_equal(0)
	assert_int(gp.score.perfect_count).is_equal(gp.chart.notes.size())
	assert_float(gp.score.hull).is_equal(100.0)
	assert_object(gp.results).is_not_null()
	assert_bool(gp.results.flags.has("AUTOPLAY USED")).is_true()
	assert_bool(gp.hud.is_autoplay_shown()).is_true()


func test_f4_restarts_with_autoplay_and_shows_badge() -> void:
	var gp := _launch(false)
	await get_tree().process_frame
	assert_bool(gp.autoplay).is_false()
	assert_bool(gp.hud.is_autoplay_shown()).is_false()
	var old_conductor := gp.conductor
	var ev := InputEventAction.new()
	ev.action = &"debug_autoplay"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(gp.autoplay).is_true()
	assert_bool(gp.autoplay_used).is_true()
	assert_bool(gp.hud.is_autoplay_shown()).is_true()
	assert_bool(gp.conductor != old_conductor).is_true()
	assert_float(gp.conductor.song_time()).is_less(0.5)  # restarted from the chart start
	await _wait_done(gp)
	assert_int(gp.score.miss_count).is_equal(0)
	assert_bool(gp.results.flags.has("AUTOPLAY USED")).is_true()
