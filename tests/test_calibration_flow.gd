extends GdUnitTestSuite
## Calibration wizard + main menu routing driven by synthetic taps (plan 07 task 2).

const WIZARD_SCENE := "res://scenes/calibration.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TEST_PATH := "user://test_calibration_flow.cfg"

var _old_path: String


func before_test() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	Settings.reset_defaults()
	MainMenu.boot_handled = false


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save_path = _old_path
	MainMenu.boot_handled = false
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	for p in [TEST_PATH, TEST_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _wizard() -> CalibrationWizard:
	var w: CalibrationWizard = (load(WIZARD_SCENE) as PackedScene).instantiate()
	add_child(w)
	auto_free(w)
	return w


func _menu() -> MainMenu:
	var m: MainMenu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(m)
	auto_free(m)
	return m


func _to_audio(w: CalibrationWizard) -> void:
	w.show_step(CalibrationWizard.Step.AUDIO)
	assert_int(w.audio_phase).is_equal(CalibrationWizard.AudioPhase.RUNNING)


func test_synthetic_taps_measure_37ms_and_save() -> void:
	var w := _wizard()
	var calls: Array = []
	w.navigate = func(p: String) -> void: calls.append(p)
	_to_audio(w)
	for c in w.click_times():
		w.record_tap(float(c) + 0.037)
	assert_int(w.taps_recorded).is_equal(16)
	w.evaluate_audio()
	assert_float(w.audio_result).is_equal_approx(0.037, 0.002)
	assert_str(w.result_label.text).is_equal("+37 MS")
	assert_bool(w.accept_button.visible).is_true()
	w.accept_audio()
	assert_int(w.step).is_equal(CalibrationWizard.Step.VISUAL)
	w.visual_slider.set_value(16.0)
	assert_str(w.result_label.text).is_equal("VISUAL OFFSET +16 MS")
	w.accept_visual()
	assert_int(w.step).is_equal(CalibrationWizard.Step.SUMMARY)
	w.save_and_continue()
	assert_float(Settings.audio_offset).is_equal_approx(0.037, 0.002)
	assert_float(Settings.visual_offset).is_equal_approx(0.016, 0.0001)
	assert_bool(Settings.calibration_done).is_true()
	assert_array(calls).is_equal([MENU_SCENE])
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TEST_PATH)).is_equal(OK)
	assert_bool(bool(cfg.get_value("calibration", "done"))).is_true()
	await get_tree().process_frame  # let queue_free'd step content go before orphan accounting


func test_applied_offset_is_removed_so_remeasure_gives_absolute_value() -> void:
	Settings.audio_offset = 0.04
	var w := _wizard()
	_to_audio(w)
	# The Conductor reports song time with the applied offset subtracted.
	for c in w.click_times():
		w.record_tap(float(c) + 0.037 - 0.04)
	w.evaluate_audio()
	assert_float(w.audio_result).is_equal_approx(0.037, 0.002)


func test_too_few_taps_shows_error_and_no_accept() -> void:
	var w := _wizard()
	_to_audio(w)
	for i in range(6):
		w.record_tap(i * 0.6 + 0.03)
	w.evaluate_audio()
	assert_bool(is_nan(w.audio_result)).is_true()
	assert_str(w.status_label.text).is_equal("Not enough taps recorded. Tap along to all the pings and try again.")
	assert_bool(w.accept_button.visible).is_false()
	w.accept_audio()
	assert_int(w.step).is_equal(CalibrationWizard.Step.AUDIO)


func test_near_half_beat_offset_is_still_measured() -> void:
	# Taps can only measure up to half a beat (300 ms at 100 BPM); the "unusually large" copy
	# guards values at the edge via CalibrationMath.is_suspicious.
	var w := _wizard()
	_to_audio(w)
	for c in w.click_times():
		w.record_tap(float(c) + 0.28)
	w.evaluate_audio()
	assert_float(w.audio_result).is_equal_approx(0.28, 0.002)
	assert_bool(w.accept_button.visible).is_true()


func test_warmup_caption_and_counter() -> void:
	var w := _wizard()
	_to_audio(w)
	assert_str(w.caption_label.text).is_equal("WARM-UP")
	assert_str(w.counter_label.text).is_equal("TAP 0 / 16")
	for i in range(4):
		w.record_tap(i * 0.6)
	assert_str(w.caption_label.text).is_equal("RECORDING")
	assert_str(w.counter_label.text).is_equal("TAP 4 / 16")


func test_taps_ignored_outside_running_phase() -> void:
	var w := _wizard()
	w.record_tap(1.0)
	assert_int(w.taps_recorded).is_equal(0)


func test_skip_leaves_offsets_untouched() -> void:
	Settings.audio_offset = 0.01
	var w := _wizard()
	var calls: Array = []
	w.navigate = func(p: String) -> void: calls.append(p)
	w.skip()
	assert_array(calls).is_equal([MENU_SCENE])
	assert_float(Settings.audio_offset).is_equal_approx(0.01, 0.0001)
	assert_bool(Settings.calibration_done).is_false()
	assert_bool(MainMenu.boot_handled).is_true()


func test_first_launch_routes_to_wizard_then_skip_reaches_menu_once() -> void:
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	await get_tree().process_frame
	assert_array(calls).is_equal(["res://scenes/calibration.tscn"])
	# After Skip the menu loads again in the same session and stays put.
	var m2 := _menu()
	var calls2: Array = []
	m2.navigate = func(p: String) -> void: calls2.append(p)
	await get_tree().process_frame
	assert_array(calls2).is_empty()
	assert_bool(m2.empty_state_visible()).is_true()


func test_calibrated_boot_stays_on_menu_without_prompt() -> void:
	Settings.save_calibration(0.02, 0.0)
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	await get_tree().process_frame
	assert_array(calls).is_empty()
	assert_bool(m.empty_state_visible()).is_false()
	assert_bool(m.prompt_visible()).is_false()


func test_device_change_shows_prompt_with_focus_and_skip() -> void:
	Settings.save_calibration(0.02, 0.0)
	Settings.output_device_name = "Some Other Device"
	assert_bool(Settings.device_changed()).is_true()
	var m := _menu()
	await get_tree().process_frame
	assert_bool(m.prompt_visible()).is_true()
	assert_bool(m.prompt_calibrate_button.has_focus()).is_true()
	m.prompt_skip_button.pressed.emit()
	assert_bool(m.prompt_visible()).is_false()


func test_menu_start_and_autoplay_set_launch_params() -> void:
	Settings.save_calibration(0.0, 0.0)
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	m.start_button.pressed.emit()
	assert_str(calls[0]).is_equal("res://scenes/gameplay.tscn")
	assert_object(Gameplay.pending_chart).is_not_null()
	assert_bool(Gameplay.pending_autoplay).is_false()
	m.autoplay_button.pressed.emit()
	assert_bool(Gameplay.pending_autoplay).is_true()
	assert_str(m.autoplay_button.text).is_equal("Autoplay Dive (test)")


func test_bluetooth_warning_follows_device_name() -> void:
	var w := _wizard()
	assert_bool(w.bluetooth_warning_visible()).is_equal(
		DeviceHeuristics.is_bluetooth_name(AudioServer.output_device))
