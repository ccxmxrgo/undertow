extends GdUnitTestSuite
## Gameplay scene end to end (plan 06 task 1): autoplay run finishes all-Perfect and the
## results screen is flagged AUTOPLAY USED; F4 restarts a manual run with autoplay on.

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 40000

const SCORES_TMP := "user://test_smoke_scores.cfg"

var _saved_no_fail := false
var _old_scores_path: String


func before_test() -> void:
	_saved_no_fail = Settings.no_fail
	Settings.no_fail = false
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP
	_rm_scores()


func _rm_scores() -> void:
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func after_test() -> void:
	ScoreStore.default_path = _old_scores_path
	_rm_scores()
	Settings.no_fail = _saved_no_fail
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false


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


func test_debug_overlay_hidden_by_default_and_records_errors() -> void:
	var gp := _launch(true)
	await get_tree().process_frame
	assert_object(gp.debug_overlay).is_not_null()
	assert_bool(gp.debug_overlay.visible).is_false()
	gp.judge.judged.emit(0, 0, InputJudge.Judgment.PERFECT, 0.012)
	for i in range(25):
		gp.judge.judged.emit(0, 0, InputJudge.Judgment.GOOD, -0.02)
	assert_int(gp.debug_overlay.recent_errors().size()).is_equal(20)


func test_drift_harness_scene_boots_and_logs() -> void:
	const TMP := "user://test_drift_log.csv"
	# Snapshot the player's real log so we can prove the test never touches it (T-08-01).
	var real_before := ""
	var real_existed := FileAccess.file_exists(DriftHarness.LOG_PATH)
	if real_existed:
		real_before = FileAccess.get_file_as_string(DriftHarness.LOG_PATH)
	var h: Node = (load("res://scenes/drift_harness.tscn") as PackedScene).instantiate()
	h.set("log_path", TMP)  # must be set before add_child
	add_child(h)
	auto_free(h)
	for i in range(10):
		await get_tree().process_frame
	assert_object(h.get("conductor")).is_not_null()
	assert_bool(FileAccess.file_exists(TMP)).is_true()
	h.free()  # closes and flushes the CSV
	assert_str(FileAccess.get_file_as_string(TMP)).starts_with("elapsed_s,song_time_s,drift_ms")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	assert_bool(FileAccess.file_exists(DriftHarness.LOG_PATH)).is_equal(real_existed)
	if real_existed:
		assert_str(FileAccess.get_file_as_string(DriftHarness.LOG_PATH)).is_equal(real_before)


func test_practice_forces_no_fail_without_touching_setting_and_survives_restart() -> void:
	Gameplay.pending_practice = true
	var gp := _launch(false)
	await get_tree().process_frame
	assert_bool(gp.practice).is_true()
	assert_bool(gp.score.no_fail).is_true()
	assert_bool(Settings.no_fail).is_false()
	assert_bool(Gameplay.pending_practice).is_false()
	gp.restart(false)
	assert_bool(gp.practice).is_true()
	assert_bool(gp.score.no_fail).is_true()
	gp.restart(true)
	assert_bool(gp.practice).is_true()
	assert_bool(gp.score.no_fail).is_true()
	assert_bool(Settings.no_fail).is_false()
	await get_tree().process_frame


func test_normal_run_is_not_practice() -> void:
	var gp := _launch(false)
	await get_tree().process_frame
	assert_bool(gp.practice).is_false()
	assert_bool(gp.score.no_fail).is_false()


func test_visor_and_streak_layering_and_restart() -> void:
	var gp := _launch(false)
	await get_tree().process_frame
	var order := [gp.highway, gp.feedback, gp.visor, gp.hud, gp.streak_counter, gp.visor_brackets, gp.pause_menu]
	for i in range(order.size() - 1):
		assert_int((order[i] as Node).get_index()).is_less((order[i + 1] as Node).get_index())
	gp.score.combo_changed.emit(10)
	assert_str(gp.streak_counter.popup_text()).is_equal("10 STREAK")
	gp.restart(false)
	await get_tree().process_frame
	for cls in [VisorFrame, StreakCounter, VisorBrackets]:
		var n := 0
		for ch in gp._run_root.get_children():
			if is_instance_of(ch, cls):
				n += 1
		assert_int(n).is_equal(1)


func _manual_finish(gp: Gameplay, depth_score: int) -> void:
	gp.score.score = depth_score
	gp.score.perfect_count = 10
	gp.score.max_combo = 10
	gp._finish()


func test_eligible_finish_saves_record_and_equal_is_not_record() -> void:
	var gp := _launch(false)
	await get_tree().process_frame
	_manual_finish(gp, 5000)
	assert_bool(gp.record_info.eligible).is_true()
	assert_bool(gp.record_info.new_record).is_true()
	assert_float(gp.record_info.previous_depth).is_equal(-1.0)
	assert_bool(FileAccess.file_exists(SCORES_TMP)).is_true()
	var saved := FileAccess.get_file_as_string(SCORES_TMP)
	assert_str(saved).contains("chart:test.short_chart.v1")
	assert_object(gp.results.record_banner).is_not_null()
	gp.restart(false)
	await get_tree().process_frame
	_manual_finish(gp, 5000)
	assert_bool(gp.record_info.new_record).is_false()
	assert_bool(gp.record_info.eligible).is_true()
	assert_str(FileAccess.get_file_as_string(SCORES_TMP)).is_equal(saved)


func test_practice_autoplay_nofail_finishes_write_nothing() -> void:
	Gameplay.pending_practice = true
	var gp := _launch(false)
	await get_tree().process_frame
	_manual_finish(gp, 5000)
	assert_bool(gp.record_info.eligible).is_false()
	assert_bool(FileAccess.file_exists(SCORES_TMP)).is_false()
	assert_bool(gp.results.flags.has("PRACTICE DIVE")).is_true()
	# Retry from practice stays practice and stays ineligible.
	gp.restart(false)
	await get_tree().process_frame
	_manual_finish(gp, 5000)
	assert_bool(gp.practice).is_true()
	assert_bool(gp.record_info.eligible).is_false()
	var gp2 := _launch(true)
	await get_tree().process_frame
	_manual_finish(gp2, 5000)
	assert_bool(gp2.record_info.eligible).is_false()
	Settings.no_fail = true
	var gp3 := _launch(false)
	await get_tree().process_frame
	_manual_finish(gp3, 5000)
	assert_bool(gp3.score.no_fail_used).is_false()
	assert_bool(gp3.record_info.eligible).is_false()
	assert_bool(FileAccess.file_exists(SCORES_TMP)).is_false()


func test_failed_dive_never_writes() -> void:
	var gp := _launch(false)
	await get_tree().process_frame
	_manual_finish(gp, 5000)
	var saved := FileAccess.get_file_as_string(SCORES_TMP)
	var gp2 := _launch(false)
	await get_tree().process_frame
	gp2.score.score = 90000
	gp2.score.max_combo = 77
	gp2._on_failed()
	assert_int(gp2.state).is_equal(Gameplay.State.FAILED)
	assert_str(FileAccess.get_file_as_string(SCORES_TMP)).is_equal(saved)
	assert_str(gp2.fail_screen.stats_label.text).is_equal("Max combo: 77")
	assert_bool(gp2.fail_screen.best_label.text.begins_with("Saved best: ")).is_true()
