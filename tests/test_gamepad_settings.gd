extends GdUnitTestSuite
## G3 part 2 (02.2-29): Settings (rows, toggles, sliders, Background row, rebind cells, reset
## dialog, back, the overlay over pause) and the calibration wizard can be operated with gamepad
## events alone, and a pad-only player never gets stuck. Every interaction is an
## InputEventJoypadButton / InputEventJoypadMotion pushed through the viewport (GUI path) or
## Input.parse_input_event (sticks, screens that read Input); never a key or a direct method call.

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const WIZARD_SCENE := "res://scenes/calibration.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SETTINGS_PATH := "user://test_gamepad_settings.cfg"

var _old_settings_path: String


func before_test() -> void:
	_old_settings_path = Settings.save_path
	Settings.save_path = SETTINGS_PATH
	Settings.reset_defaults()
	Settings.reduce_motion = true
	MainMenu.boot_handled = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false


func after_test() -> void:
	# Release anything a test left held in Input (sticks / buttons sent via parse_input_event).
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_START]:
		Input.parse_input_event(Pad.button(b, false))
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_X, 0.0))
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_Y, 0.0))
	Settings.reset_defaults()
	Settings.save_path = _old_settings_path
	MainMenu.boot_handled = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	for p in [SETTINGS_PATH, SETTINGS_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ---- helpers ------------------------------------------------------------------------------------


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_msec(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _tap(index: int) -> void:
	await Pad.tap(get_viewport(), index)


func _press(index: int) -> void:
	get_viewport().push_input(Pad.button(index, true))
	await get_tree().process_frame


func _release(index: int) -> void:
	get_viewport().push_input(Pad.button(index, false))
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _screen(overlay: bool = false) -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.overlay = overlay
	s.library = null
	add_child(s)
	auto_free(s)
	return s


func _wizard() -> CalibrationWizard:
	var w: CalibrationWizard = (load(WIZARD_SCENE) as PackedScene).instantiate()
	add_child(w)
	auto_free(w)
	return w


## Focuses `target` by walking down with the D-pad from the current focus (max 60 steps).
func _walk_to(target: Control) -> void:
	for i in range(60):
		if _focus() == target:
			return
		await _tap(JOY_BUTTON_DPAD_DOWN)


## One focusable control per settings row, in screen order: the KEYBOARD rebind cell of a
## binding row, otherwise the first focusable control of the row.
func _expected_rows(s: SettingsScreen) -> Array[Control]:
	var out: Array[Control] = []
	for n in s.scroll.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree():
			continue
		if c is RebindCell and (c as RebindCell).device == &"gamepad":
			continue
		if c is ScrollBar:
			continue
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		out.append(c)
	return out


func _inside_scroll(s: SettingsScreen, c: Control) -> bool:
	var view := s.scroll.get_global_rect()
	var r := c.get_global_rect()
	return r.position.y >= view.position.y - 0.5 and r.end.y <= view.end.y + 0.5


# ---- settings: rows, scroll, toggles, sliders, Background ----------------------------------------


func test_settings_dpad_walks_every_row_in_order_and_scroll_follows() -> void:
	var s := _screen()
	await _frames(2)
	var expected := _expected_rows(s)
	assert_int(expected.size()).is_greater(15)
	assert_object(_focus()).is_same(expected[0])
	for i in range(1, expected.size()):
		await _tap(JOY_BUTTON_DPAD_DOWN)
		await _frames(1)
		var got := _focus()
		assert_object(got).override_failure_message("row %d: expected %s, got %s" % [
			i, expected[i], got]).is_same(expected[i])
		assert_bool(_inside_scroll(s, got)).override_failure_message(
			"row %d (%s) focused but outside the visible scroll area" % [i, got]).is_true()
	assert_object(_focus()).is_same(s.back_button)
	# And back up to the top.
	for i in range(expected.size() - 2, -1, -1):
		await _tap(JOY_BUTTON_DPAD_UP)
		await _frames(1)
		assert_object(_focus()).override_failure_message("up row %d: expected %s, got %s" % [
			i, expected[i], _focus()]).is_same(expected[i])
		assert_bool(_inside_scroll(s, _focus())).is_true()


func test_settings_a_flips_a_toggle() -> void:
	var s := _screen()
	await _frames(2)
	await _walk_to(s.no_fail_button)
	assert_object(_focus()).is_same(s.no_fail_button)
	assert_bool(Settings.no_fail).is_false()
	await _tap(JOY_BUTTON_A)
	assert_bool(Settings.no_fail).is_true()
	await _tap(JOY_BUTTON_A)
	assert_bool(Settings.no_fail).is_false()


func test_settings_dpad_left_right_steps_a_slider_once() -> void:
	var s := _screen()
	await _frames(2)
	await _walk_to(s.scroll_slider)
	assert_object(_focus()).is_same(s.scroll_slider)
	var v0 := s.scroll_slider.value
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_float(s.scroll_slider.value).is_equal_approx(v0 + 0.1, 0.0001)
	assert_float(Settings.scroll_speed).is_equal_approx(v0 + 0.1, 0.0001)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_float(s.scroll_slider.value).is_equal_approx(v0 - 0.1, 0.0001)
	assert_object(_focus()).is_same(s.scroll_slider)  # left/right never leave the slider


func test_settings_stick_steps_a_slider_once_per_push_and_hold_stops_on_release() -> void:
	Settings.volume_master = 0.5  # room both ways
	var s := _screen()
	await _frames(2)
	await _walk_to(s.master_slider)
	assert_object(_focus()).is_same(s.master_slider)
	var v0 := s.master_slider.value
	# A real stick sends a stream of rising values for one push: that is ONE step.
	for v in [0.55, 0.7, 0.85, 1.0]:
		Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_X, v))
		await get_tree().process_frame
	assert_float(s.master_slider.value).is_equal_approx(v0 + 5.0, 0.0001)
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_X, 0.0))
	await _frames(2)
	var after_release := s.master_slider.value
	await _wait_msec(700)  # past HOLD_DELAY: no repeat once released
	assert_float(s.master_slider.value).is_equal_approx(after_release, 0.0001)
	# Holding the D-pad repeats, releasing stops the repeat.
	Input.parse_input_event(Pad.button(JOY_BUTTON_DPAD_LEFT, true))
	await _wait_msec(700)
	Input.parse_input_event(Pad.button(JOY_BUTTON_DPAD_LEFT, false))
	await _frames(2)
	var held := s.master_slider.value
	assert_float(held).is_less(after_release - 5.0)  # stepped and repeated
	await _wait_msec(500)
	assert_float(s.master_slider.value).is_equal_approx(held, 0.0001)
	assert_object(_focus()).is_same(s.master_slider)


func test_settings_background_row_dpad_and_stick_switch_once() -> void:
	var s := _screen()
	await _frames(2)
	await _walk_to(s.background_button)
	assert_object(_focus()).is_same(s.background_button)
	var start := Settings.background_style
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_str(Settings.background_style).is_not_equal(start)
	assert_str(s.background_button.text).is_equal(SettingsScreen.background_label(Settings.background_style))
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_str(Settings.background_style).is_equal(start)
	for v in [0.55, 0.7, 0.85, 1.0]:  # one stick push = one switch
		Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_X, v))
		await get_tree().process_frame
	assert_str(Settings.background_style).is_not_equal(start)
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_X, 0.0))
	await _frames(1)
	await _tap(JOY_BUTTON_A)  # A flips it too
	assert_str(Settings.background_style).is_equal(start)
	assert_object(_focus()).is_same(s.background_button)


func test_settings_b_leaves_full_mode_through_the_menu_seam() -> void:
	var s := _screen()
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	await _frames(2)
	await _tap(JOY_BUTTON_B)
	assert_array(calls).is_equal([SettingsScreen.MENU_SCENE])


func test_settings_b_closes_overlay_mode() -> void:
	var s := _screen(true)
	var closed := [0]
	s.closed.connect(func() -> void: closed[0] += 1)
	await _frames(2)
	await _tap(JOY_BUTTON_B)
	assert_int(closed[0]).is_equal(1)


func test_settings_reset_dialog_opens_on_safe_button_and_b_cancels() -> void:
	var s := _screen()
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	Settings.bindings.bind_key(&"lane_1", KEY_G)
	await _frames(2)
	await _walk_to(s.reset_button)
	assert_object(_focus()).is_same(s.reset_button)
	await _tap(JOY_BUTTON_A)
	assert_object(s.dialog).is_not_null()
	assert_object(_focus()).is_same(s.dialog.safe_button)
	await _tap(JOY_BUTTON_B)
	await _frames(1)
	assert_object(s.dialog).is_null()
	assert_object(_focus()).is_same(s.reset_button)
	assert_array(calls).is_empty()  # B closed the dialog only
	assert_str(Settings.bindings.display_name(&"lane_1", &"keyboard")).is_equal("G")
	# A on the safe button keeps the bindings too.
	await _tap(JOY_BUTTON_A)
	assert_object(_focus()).is_same(s.dialog.safe_button)
	await _tap(JOY_BUTTON_A)
	await _frames(1)
	assert_object(s.dialog).is_null()
	assert_str(Settings.bindings.display_name(&"lane_1", &"keyboard")).is_equal("G")


func test_settings_overlay_over_pause_b_closes_overlay_only() -> void:
	Gameplay.pending_chart = TestCharts.short_chart()
	var gp: Gameplay = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	var end := Time.get_ticks_msec() + 4000
	while not gp.is_began() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await _wait_msec(300)
	var pm := gp.pause_menu
	await _tap(JOY_BUTTON_START)
	assert_bool(pm.is_open()).is_true()
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.settings_button)
	await _tap(JOY_BUTTON_A)
	await _frames(2)
	assert_bool(pm.has_settings_overlay()).is_true()
	var overlay_focus := _focus()
	assert_object(overlay_focus).is_not_null()
	assert_bool(overlay_focus is RebindCell).is_true()
	await _tap(JOY_BUTTON_B)
	await _frames(2)
	assert_bool(pm.has_settings_overlay()).is_false()
	assert_bool(pm.is_open()).is_true()
	assert_bool(pm.is_counting_down()).is_false()
	assert_object(_focus()).is_same(pm.settings_button)


# ---- rebind cells -------------------------------------------------------------------------------


func test_rebind_a_opens_listening_without_binding_that_press() -> void:
	var s := _screen()
	await _frames(2)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var cell: RebindCell = s.cells["lane_1:gamepad"]
	assert_object(_focus()).is_same(cell)
	var before := cell.text
	await _press(JOY_BUTTON_A)
	await _release(JOY_BUTTON_A)
	await _frames(1)
	assert_bool(cell.listening).is_true()
	assert_str(cell.text).is_equal(RebindCell.LISTEN_TEXT_PAD)
	assert_str(Settings.bindings.display_name(&"lane_1", &"gamepad")).is_equal(before)
	# Same for a keyboard cell: the opening A neither binds nor leaves listening.
	await _tap(JOY_BUTTON_B)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	var kcell: RebindCell = s.cells["lane_1:keyboard"]
	assert_object(_focus()).is_same(kcell)
	await _tap(JOY_BUTTON_A)
	assert_bool(kcell.listening).is_true()
	assert_str(kcell.text).is_equal(RebindCell.LISTEN_TEXT_KEY)


func test_rebind_gamepad_cell_next_pad_button_binds() -> void:
	var s := _screen()
	await _frames(2)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var cell: RebindCell = s.cells["lane_1:gamepad"]
	await _tap(JOY_BUTTON_A)
	assert_bool(cell.listening).is_true()
	await _tap(JOY_BUTTON_X)
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal(BindingStore.PAD_BUTTON_NAMES[JOY_BUTTON_X])
	assert_str(Settings.bindings.display_name(&"lane_1", &"gamepad")).is_equal(cell.text)
	assert_object(_focus()).is_same(cell)


func test_rebind_gamepad_cell_b_cancels() -> void:
	var s := _screen()
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	await _frames(2)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var cell: RebindCell = s.cells["lane_1:gamepad"]
	var before := cell.text
	await _tap(JOY_BUTTON_A)
	await _tap(JOY_BUTTON_B)
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal(before)
	assert_array(calls).is_empty()  # B cancelled listening only, the screen stays


func test_rebind_keyboard_cell_pad_b_cancels_and_other_pad_input_is_ignored() -> void:
	var s := _screen()
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	await _frames(2)
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	assert_object(_focus()).is_same(cell)
	var before := cell.text
	await _tap(JOY_BUTTON_A)
	assert_bool(cell.listening).is_true()
	# Pad input other than B neither binds nor moves focus away from the listening cell.
	for b in [JOY_BUTTON_X, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A, JOY_BUTTON_START]:
		await _tap(b)
		assert_bool(cell.listening).override_failure_message("pad button %d" % b).is_true()
		assert_object(_focus()).is_same(cell)
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_Y, 1.0))
	await get_tree().process_frame
	Input.parse_input_event(Pad.motion(JOY_AXIS_LEFT_Y, 0.0))
	await get_tree().process_frame
	assert_bool(cell.listening).is_true()
	assert_object(_focus()).is_same(cell)
	await _tap(JOY_BUTTON_B)
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal(before)
	assert_str(Settings.bindings.display_name(&"lane_1", &"keyboard")).is_equal(before)
	assert_array(calls).is_empty()  # B cancelled listening; settings still open
	await _tap(JOY_BUTTON_B)
	assert_array(calls).is_equal([SettingsScreen.MENU_SCENE])


# ---- calibration wizard -------------------------------------------------------------------------


func test_calibration_a_on_begin_starts_the_audio_step() -> void:
	var w := _wizard()
	await _frames(2)
	assert_int(w.step).is_equal(CalibrationWizard.Step.INTRO)
	assert_object(_focus()).is_same(w.begin_button)
	await _tap(JOY_BUTTON_A)
	assert_int(w.step).is_equal(CalibrationWizard.Step.AUDIO)
	assert_int(w.audio_phase).is_equal(CalibrationWizard.AudioPhase.RUNNING)
	assert_int(w.taps_recorded).is_equal(0)  # the Begin press is not a tap


func test_calibration_each_a_records_one_tap_and_presses_no_button() -> void:
	var w := _wizard()
	var calls: Array = []
	w.navigate = func(p: String) -> void: calls.append(p)
	await _frames(2)
	await _tap(JOY_BUTTON_A)
	assert_int(w.audio_phase).is_equal(CalibrationWizard.AudioPhase.RUNNING)
	var pressed := [0]
	for b in w.find_children("*", "BaseButton", true, false):
		(b as BaseButton).pressed.connect(func() -> void: pressed[0] += 1)
	for i in range(3):
		await _tap(JOY_BUTTON_A)
		assert_int(w.taps_recorded).is_equal(i + 1)
	assert_int(pressed[0]).is_equal(0)
	assert_array(calls).is_empty()
	assert_int(w.step).is_equal(CalibrationWizard.Step.AUDIO)


func test_calibration_accept_slider_save_with_pad() -> void:
	var w := _wizard()
	var calls: Array = []
	w.navigate = func(p: String) -> void: calls.append(p)
	await _frames(2)
	await _tap(JOY_BUTTON_A)
	for c in w.click_times():
		w.record_tap(float(c) + 0.030)  # synthetic taps; the pad path is covered above
	w.evaluate_audio()
	await _frames(1)
	assert_object(_focus()).is_same(w.accept_button)
	await _tap(JOY_BUTTON_A)
	assert_int(w.step).is_equal(CalibrationWizard.Step.VISUAL)
	assert_object(_focus()).is_same(w.visual_slider)
	var v0 := w.visual_slider.value
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_float(w.visual_slider.value).is_equal_approx(v0 + 1.0, 0.0001)
	# Down reaches Accept / Retry; Retry resets the slider; up returns to the slider.
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(w.accept_button)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focus()).is_same(w.retry_button)
	await _tap(JOY_BUTTON_A)
	assert_float(w.visual_slider.value).is_equal_approx(0.0, 0.0001)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_object(_focus()).is_same(w.visual_slider)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(w.accept_button)
	await _tap(JOY_BUTTON_A)
	assert_int(w.step).is_equal(CalibrationWizard.Step.SUMMARY)
	assert_object(_focus()).is_same(w.save_button)
	await _tap(JOY_BUTTON_A)
	assert_array(calls).is_equal([CalibrationWizard.MENU_SCENE])
	assert_bool(Settings.calibration_done).is_true()
	assert_float(Settings.audio_offset).is_equal_approx(0.030, 0.002)
	assert_float(Settings.visual_offset).is_equal_approx(0.001, 0.0001)
	await get_tree().process_frame


func test_calibration_retry_after_few_taps_with_pad() -> void:
	var w := _wizard()
	await _frames(2)
	await _tap(JOY_BUTTON_A)
	w.evaluate_audio()  # no taps -> "not enough taps", Retry focused
	await _frames(1)
	assert_object(_focus()).is_same(w.retry_button)
	await _tap(JOY_BUTTON_A)
	assert_int(w.audio_phase).is_equal(CalibrationWizard.AudioPhase.RUNNING)
	assert_int(w.taps_recorded).is_equal(0)


func test_calibration_b_skips_from_every_step() -> void:
	for s in [CalibrationWizard.Step.INTRO, CalibrationWizard.Step.AUDIO,
			CalibrationWizard.Step.VISUAL, CalibrationWizard.Step.SUMMARY]:
		var w := _wizard()
		var calls: Array = []
		w.navigate = func(p: String) -> void: calls.append(p)
		await _frames(1)
		if s != CalibrationWizard.Step.INTRO:
			w.show_step(s)
			await _frames(1)
		await _tap(JOY_BUTTON_B)
		assert_array(calls).override_failure_message("B on step %d" % s).is_equal([CalibrationWizard.MENU_SCENE])
		assert_bool(Settings.calibration_done).is_false()
		w.queue_free()
		await _frames(1)
	# Also from the audio result (after the test ran).
	var w2 := _wizard()
	var calls2: Array = []
	w2.navigate = func(p: String) -> void: calls2.append(p)
	await _frames(1)
	w2.show_step(CalibrationWizard.Step.AUDIO)
	w2.evaluate_audio()
	await _frames(1)
	await _tap(JOY_BUTTON_B)
	assert_array(calls2).is_equal([CalibrationWizard.MENU_SCENE])


# ---- fail screen (deviation: B = Back to Menu, like results) ------------------------------------


func test_fail_screen_b_goes_back_to_menu_once_visible() -> void:
	var f := FailScreen.new()
	add_child(f)
	auto_free(f)
	f.setup(120.0)
	f.play(0.05)
	var got: Array[String] = []
	f.retry_pressed.connect(func() -> void: got.append("retry"))
	f.menu_pressed.connect(func() -> void: got.append("menu"))
	await _tap(JOY_BUTTON_B)  # still fading in: inert
	assert_array(got).is_empty()
	await get_tree().create_timer(0.05 + FailScreen.FADE_SEC + 0.25).timeout
	await _tap(JOY_BUTTON_B)
	assert_array(got).is_equal(["menu"])
