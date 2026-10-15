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


## 02.2-20: Gameplay passes the run line (title, difficulty, progress) when the pause action opens it.
func test_pause_action_fills_run_line_from_gameplay() -> void:
	var gp := _launch()
	await _wait_msec(1200)
	assert_bool(gp.is_began()).is_true()
	var ev := InputEventAction.new()
	ev.action = &"pause"
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := InputEventAction.new()
	up.action = &"pause"
	up.pressed = false
	get_viewport().push_input(up)
	await _frames(2)
	assert_bool(gp.pause_menu.is_open()).is_true()
	var expect := PauseMenu.run_line(gp.chart.title, gp.chart.difficulty, gp.progress_pct())
	assert_str(gp.pause_menu.run_label.text).is_equal(expect)
	assert_bool(gp.pause_menu.run_label.text.begins_with(gp.chart.title + " · ")).is_true()
	assert_float(gp.progress_pct()).is_between(0.0, 100.0)


# ---- 03-12: versus pause copy (03-UI-SPEC 9.5) ---------------------------------------------

func _dialog_of(pm: PauseMenu) -> ConfirmDialog:
	for c in pm.get_children():
		if c is ConfirmDialog:
			return c
	return null


func test_match_mode_run_line_and_buttons() -> void:
	var gp := _launch()
	await _frames(2)
	var pm := gp.pause_menu
	pm.match_mode = true
	pm.set_run_info("Sea Shanty 2", "expert", 42.0)
	assert_str(pm.run_label.text).is_equal("Sea Shanty 2 · EXPERT · VERSUS · 42%")
	assert_str(PauseMenu.run_line("T", "hard", 7.0, true)).is_equal("T · HARD · VERSUS · 7%")
	assert_str(pm.resume_button.text).is_equal("Resume Match")
	assert_str(pm.restart_button.text).is_equal("Restart Match")
	assert_str(pm.settings_button.text).is_equal("Settings")
	assert_str(pm.menu_button.text).is_equal("Leave Match")
	pm.match_mode = false
	assert_str(pm.resume_button.text).is_equal("Resume Dive")
	assert_str(pm.restart_button.text).is_equal("Restart Dive")
	assert_str(pm.menu_button.text).is_equal("Back to Menu")
	pm.set_run_info("Sea Shanty 2", "expert", 42.0)
	assert_str(pm.run_label.text).is_equal("Sea Shanty 2 · EXPERT · 42%")


func test_match_mode_restart_confirm_copy() -> void:
	var gp := _launch()
	await _frames(2)
	var pm := gp.pause_menu
	pm.match_mode = true
	pm.open()
	var restarts: Array[int] = []
	pm.restart_confirmed.connect(func() -> void: restarts.append(1))
	gp.score.score = 0  # versus confirms even at score 0
	pm.request_restart()
	await _frames(2)
	assert_array(restarts).is_empty()
	var d := _dialog_of(pm)
	assert_object(d).is_not_null()
	assert_str(d.title_label.text).is_equal("RESTART")
	assert_str(d.body_label.text).is_equal("Restart this match from the beginning? Everyone's progress will be lost.")
	assert_str(d.confirm_button.text).is_equal("Restart Match")
	assert_str(d.safe_button.text).is_equal("Keep Playing")
	assert_bool(d.safe_button.has_focus()).is_true()
	d.safe_button.pressed.emit()
	await _frames(2)
	assert_array(restarts).is_empty()
	assert_bool(pm.restart_button.has_focus()).is_true()


func test_match_mode_leave_confirm_copy() -> void:
	var gp := _launch()
	await _frames(2)
	var pm := gp.pause_menu
	pm.match_mode = true
	pm.open()
	var leaves: Array[int] = []
	pm.menu_confirmed.connect(func() -> void: leaves.append(1))
	pm.request_menu()
	await _frames(2)
	var d := _dialog_of(pm)
	assert_object(d).is_not_null()
	assert_str(d.title_label.text).is_equal("LEAVE MATCH")
	assert_str(d.body_label.text).is_equal("Leave this match? It ends now and nothing is saved.")
	assert_str(d.confirm_button.text).is_equal("Leave Match")
	assert_str(d.safe_button.text).is_equal("Stay")
	assert_bool(d.safe_button.has_focus()).is_true()
	# Disconnect the gameplay's own handler effect by only checking our capture on confirm.
	d.confirm_button.pressed.emit()
	await _frames(1)
	assert_array(leaves).has_size(1)
