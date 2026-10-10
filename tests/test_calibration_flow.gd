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
	assert_str(w.result_label.text).is_equal("+16 MS")
	assert_str(w.offset_caption_label.text).is_equal("VISUAL OFFSET")
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
	Settings.output_device_signature = "stale|signature"
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
	assert_str(calls[0]).is_equal("res://scenes/song_select.tscn")
	assert_bool(SongSelect.run_autoplay).is_false()
	m.autoplay_button.pressed.emit()
	assert_bool(SongSelect.run_autoplay).is_true()
	SongSelect.run_autoplay = false
	assert_str(m.autoplay_button.text).is_equal("Autoplay Dive (test)")


func _fake_info(configured: String) -> AudioDeviceInfo:
	return AudioDeviceInfo.new(func() -> Dictionary:
		return {"configured": configured, "devices": PackedStringArray(["Default", configured]),
			"mix_rate": 48000, "latency_s": 0.01})


func test_bluetooth_warning_follows_device_name() -> void:
	var old := Settings.device_info
	Settings.device_info = _fake_info("AirPods Pro")
	var w := _wizard()
	assert_bool(w.bluetooth_warning_visible()).is_true()
	Settings.device_info = _fake_info("Default")
	w.refresh_info()
	assert_bool(w.bluetooth_warning_visible()).is_false()
	Settings.device_info = old


func test_readout_says_system_default_under_alias_and_note_shown() -> void:
	var old := Settings.device_info
	Settings.device_info = _fake_info("Default")
	var w := _wizard()
	assert_str(w._info_label.text).contains("Output device: System default")
	assert_str(w.note_label.text).is_equal("Switched headphones or speakers? Calibrate Sonar again.")
	Settings.device_info = old


func test_rerun_shows_absolute_offset_and_previous_caption() -> void:
	Settings.audio_offset = 0.041
	Settings.calibration_done = true
	var w := _wizard()
	_to_audio(w)
	for c in w.click_times():
		w.record_tap(float(c) + 0.041 - 0.041)  # conductor domain: applied offset subtracted
	w.evaluate_audio()
	assert_float(w.audio_result).is_equal_approx(0.041, 0.002)
	assert_str(w.result_label.text).is_equal("+41 MS")
	assert_str(w.previous_label.text).contains("+41 MS")
	assert_str(w.previous_label.text).contains("Previously saved")


func test_no_previous_caption_when_not_calibrated() -> void:
	Settings.calibration_done = false
	var w := _wizard()
	_to_audio(w)
	for c in w.click_times():
		w.record_tap(float(c) + 0.03)
	w.evaluate_audio()
	assert_str(w.previous_label.text).is_empty()


func test_buttons_are_not_window_wide() -> void:
	var w := _wizard()
	await get_tree().process_frame
	await get_tree().process_frame
	for b in [w.begin_button, w.skip_button]:
		assert_float(b.size.x).is_between(280.0, 480.0)
	_to_audio(w)
	w.evaluate_audio()
	w.retry_button.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(w.retry_button.size.x).is_between(280.0, 480.0)
	w.show_step(CalibrationWizard.Step.SUMMARY)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(w.save_button.size.x).is_between(280.0, 480.0)


# ---- 02.2-21: calibration restyle (UI-SPEC 9.4, 14) ------------------------------------------


func test_step_chips_states_and_geometry() -> void:
	assert_array(CalibrationWizard.STEP_CHIPS).is_equal(["1 AUDIO", "2 VISUAL", "3 DONE"])
	var S := CalibrationWizard.Step
	assert_array(CalibrationWizard.chip_states(S.INTRO)).is_equal(["upcoming", "upcoming", "upcoming"])
	assert_array(CalibrationWizard.chip_states(S.AUDIO)).is_equal(["current", "upcoming", "upcoming"])
	assert_array(CalibrationWizard.chip_states(S.VISUAL)).is_equal(["done", "current", "upcoming"])
	assert_array(CalibrationWizard.chip_states(S.SUMMARY)).is_equal(["done", "done", "current"])
	for i in 3:
		var r := CalibrationWizard.chip_rect(i)
		assert_float(r.position.y).is_equal(64.0)
		assert_float(r.end.y).is_equal(112.0)
	assert_float(CalibrationWizard.chip_rect(0).position.x).is_equal(64.0)
	assert_float(CalibrationWizard.chip_rect(1).position.x).is_greater(CalibrationWizard.chip_rect(0).end.x)


func test_offset_value_sign_font_and_caption() -> void:
	assert_str(CalibrationWizard.format_ms(0.051)).is_equal("+51 MS")
	assert_str(CalibrationWizard.format_ms(-0.012)).is_equal("-12 MS")
	assert_str(CalibrationWizard.format_ms(0.0)).is_equal("+0 MS")
	assert_that(CalibrationWizard.CAPTION_AT).is_equal(Vector2(64.0, 384.0))
	assert_that(CalibrationWizard.VALUE_AT).is_equal(Vector2(64.0, 476.0))
	var w := _wizard()
	_to_audio(w)
	assert_str(w.offset_caption_label.text).is_equal("AUDIO OFFSET")
	for c in w.click_times():
		w.record_tap(float(c) + 0.051)
	w.evaluate_audio()
	assert_str(w.result_label.text).is_equal("+51 MS")
	assert_int(w.result_label.get_theme_font_size("font_size")).is_equal(Palette.SIZE_DISPLAY)
	assert_that(w.result_label.get_theme_color("font_color")).is_equal(Palette.SONAR)
	assert_object(w.result_label.get_theme_font("font")).is_same(Palette.display_font())
	assert_float(w.result_label.position.x).is_equal(64.0)
	await get_tree().process_frame


func test_stage_draws_gem_hit_line_and_perfect_ring() -> void:
	assert_that(CalibrationWizard.STAGE_RECT).is_equal(Rect2(640.0, 440.0, 640.0, 320.0))
	assert_that(CalibrationWizard.NOTE_CENTER).is_equal(Vector2(960.0, 560.0))
	assert_float(CalibrationWizard.NOTE_R).is_equal(41.0)
	assert_float(CalibrationWizard.HIT_LINE_Y).is_equal(700.0)
	assert_that(CalibrationWizard.HIT_LINE_X).is_equal(Vector2(840.0, 1080.0))
	var src := FileAccess.get_file_as_string("res://src/ui/calibration_wizard.gd")
	assert_bool(src.contains("NotePainter.draw_note")).is_true()
	# The flash is the Perfect shockwave ring (HitBurst timeline), gone after its life.
	assert_that(CalibrationWizard.flash_ring(0.05)).is_equal(HitBurst.ring_state(HitBurst.RING_PERFECT, 0.05))
	assert_bool(CalibrationWizard.flash_ring(HitBurst.life(HitBurst.RING_PERFECT) + 0.01).is_empty()).is_true()
	assert_bool(CalibrationWizard.flash_ring(-0.01).is_empty()).is_true()
	# Visual test note: reaches the hit line exactly on the click.
	assert_float(CalibrationWizard.visual_note_y(1.0)).is_equal_approx(CalibrationWizard.HIT_LINE_Y, 0.001)
	assert_float(CalibrationWizard.visual_note_y(0.0)).is_less(CalibrationWizard.NOTE_CENTER.y)


func test_design_system_frame() -> void:
	var w := _wizard()
	assert_object(w.backdrop).is_not_null()
	assert_str(w.backdrop.variant).is_equal("table")
	assert_bool(w.focus_marker is FocusMarker).is_true()
	assert_bool(w.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_that(CalibrationWizard.DEVICE_PANEL).is_equal(Rect2(64.0, 136.0, 640.0, 160.0))
	assert_that(CalibrationWizard.INSTRUCTION_AT).is_equal(Vector2(64.0, 340.0))
	_to_audio(w)
	for c in w.click_times():
		w.record_tap(float(c) + 0.03)
	w.evaluate_audio()
	assert_str(String(w.accept_button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_float(w.accept_button.custom_minimum_size.y).is_equal(48.0)
	w.accept_audio()
	var s := w.visual_slider
	assert_float(s.position.x).is_equal(64.0)
	assert_float(s.position.x + s.size.x).is_equal(1856.0)
	assert_float(s.position.y + s.size.y * 0.5).is_equal(852.0)
	await get_tree().process_frame
