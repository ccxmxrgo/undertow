extends GdUnitTestSuite
## Pause menu, 3-beat countdown resume and the Settings CanvasLayer overlay (plan 06 task 2).

const SCENE := "res://scenes/gameplay.tscn"


## Stand-in for scenes/settings.tscn: exposes `overlay` and a `closed` signal.
class StubSettings extends Control:
	signal closed
	var overlay: bool = false


func _launch() -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func before_test() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE


func after_test() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_msec(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func test_pause_freezes_song_time_without_scene_tree_pause() -> void:
	var gp := _launch()
	await _wait_msec(1500)
	assert_float(gp.conductor.song_time()).is_greater(0.0)
	gp.pause_menu.open()
	assert_bool(gp.pause_menu.is_open()).is_true()
	assert_bool(get_tree().paused).is_false()
	assert_bool(gp.lane_input.enabled).is_false()
	await _frames(2)
	var frozen := gp.conductor.song_time()
	await _wait_msec(400)
	assert_float(gp.conductor.song_time()).is_equal_approx(frozen, 1e-6)


func test_resume_counts_3_2_1_then_reenables_input() -> void:
	var gp := _launch()
	await _wait_msec(1200)
	gp.pause_menu.open()
	await _frames(2)
	var paused_at := gp.conductor.song_time()
	var ticks: Array[int] = []
	gp.conductor.countdown_tick.connect(func(n: int) -> void: ticks.append(n))
	gp.pause_menu.resume_dive()
	assert_bool(gp.pause_menu.is_open()).is_false()
	assert_bool(gp.pause_menu.is_counting_down()).is_true()
	var deadline := Time.get_ticks_msec() + 5000
	while gp.pause_menu.is_counting_down() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_array(ticks).is_equal([3, 2, 1])
	assert_bool(gp.pause_menu.is_counting_down()).is_false()
	assert_bool(gp.lane_input.enabled).is_true()
	# Song time continues from the paused position, not from a jump.
	assert_float(gp.conductor.song_time()).is_between(paused_at - 0.01, paused_at + 0.5)


func test_restart_confirms_only_when_score_above_zero() -> void:
	var gp := _launch()
	await _frames(2)
	gp.pause_menu.open()
	var restarts: Array[int] = []
	gp.pause_menu.restart_confirmed.connect(func() -> void: restarts.append(1))
	gp.score.score = 500
	gp.pause_menu.request_restart()
	await _frames(2)
	assert_array(restarts).is_empty()
	var dialog: ConfirmDialog = null
	for c in gp.pause_menu.get_children():
		if c is ConfirmDialog:
			dialog = c
	assert_object(dialog).is_not_null()
	assert_str(dialog.safe_button.text).is_equal("Keep Playing")
	assert_str(dialog.confirm_button.text).is_equal("Restart Dive")
	assert_bool(dialog.safe_button.has_focus()).is_true()
	dialog.safe_button.pressed.emit()  # Keep Playing
	await _frames(2)
	assert_array(restarts).is_empty()
	# Score 0: no dialog, restart is requested directly (and the run is rebuilt).
	gp.score.score = 0
	var old_conductor := gp.conductor
	gp.pause_menu.request_restart()
	await _frames(3)
	assert_array(restarts).has_size(1)
	assert_bool(gp.conductor != old_conductor).is_true()


func test_settings_overlay_keeps_run_intact_and_is_freed_on_close() -> void:
	var gp := _launch()
	await _wait_msec(1000)
	gp.pause_menu.open()
	await _frames(2)
	gp.score.score = 1234
	var frozen := gp.conductor.song_time()
	var conductor_before := gp.conductor
	var scene_before := get_tree().current_scene
	var stub := StubSettings.new()
	gp.pause_menu.open_settings_with(stub)
	assert_bool(gp.pause_menu.has_settings_overlay()).is_true()
	assert_bool(stub.overlay).is_true()
	assert_bool(stub.get_parent() is CanvasLayer).is_true()
	var layer := stub.get_parent() as CanvasLayer
	assert_int(layer.layer).is_equal(100)
	assert_bool(gp.pause_menu.is_open()).is_false()  # pause panel hidden under the overlay
	await _wait_msec(200)
	assert_float(gp.conductor.song_time()).is_equal_approx(frozen, 1e-6)
	stub.closed.emit()
	await _frames(3)
	assert_bool(is_instance_valid(layer)).is_false()
	assert_bool(gp.pause_menu.has_settings_overlay()).is_false()
	assert_bool(gp.pause_menu.is_open()).is_true()
	assert_bool(gp.pause_menu.settings_button.has_focus()).is_true()
	assert_object(gp.conductor).is_same(conductor_before)
	assert_int(gp.score.score).is_equal(1234)
	assert_float(gp.conductor.song_time()).is_equal_approx(frozen, 1e-6)
	assert_object(get_tree().current_scene).is_same(scene_before)
