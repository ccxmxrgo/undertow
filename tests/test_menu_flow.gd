extends GdUnitTestSuite
## Settings screen: rebinding, duplicate/Tab rejection, reset, slider persistence, overlay mode
## (plan 07 task 1) and main menu wiring (task 2).

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const TEST_PATH := "user://test_menu_flow.cfg"

var _old_path: String


func before_test() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save_path = _old_path
	for p in [TEST_PATH, TEST_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _screen(overlay: bool = false) -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.overlay = overlay
	add_child(s)
	auto_free(s)
	return s


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = true
	return e


func test_has_all_seven_actions_with_defaults() -> void:
	var s := _screen()
	assert_int(s.cells.size()).is_equal(14)
	assert_bool(s.cells["lane_1:keyboard"].text == "1").is_true()
	assert_bool(s.cells["lane_1:gamepad"].text == "LB").is_true()
	assert_bool(s.cells["fire:keyboard"].text == "Space").is_true()


func test_rebind_lane1_to_free_key() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	assert_str(cell.text).is_equal("PRESS A KEY...")
	assert_bool(cell.handle_event(_key(KEY_G))).is_true()
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("G")
	assert_str(Settings.bindings.display_name(&"lane_1", &"keyboard")).is_equal("G")


func test_duplicate_rejected_with_copy_and_unchanged() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_2))  # Lane 2 default
	assert_str(s.message_text(&"lane_1")).is_equal("! 2 is already used for Lane 2. Pick a different key.")
	assert_str(cell.text).is_equal("1")
	assert_bool(cell.listening).is_false()


func test_tab_rejected() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_TAB))
	assert_str(s.message_text(&"lane_1")).is_equal("! Tab can't be used. It is reserved for menus.")
	assert_str(cell.text).is_equal("1")


func test_escape_cancels_without_change() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_2:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_ESCAPE))
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("2")
	assert_str(s.message_text(&"lane_2")).is_equal("")


func test_gamepad_stick_ignored_trigger_accepted() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["fire:gamepad"]
	cell.begin_listen()
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	assert_bool(cell.handle_event(stick)).is_false()
	assert_bool(cell.listening).is_true()
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_TRIGGER_LEFT
	weak.axis_value = 0.3
	assert_bool(cell.handle_event(weak)).is_false()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_X
	b.pressed = true
	assert_bool(cell.handle_event(b)).is_true()
	assert_str(cell.text).is_equal("X")


func test_gamepad_b_cancels() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["fire:gamepad"]
	cell.begin_listen()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	cell.handle_event(b)
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("A")


func test_reset_controls_restores_defaults() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_G))
	assert_str(cell.text).is_equal("G")
	s.request_reset()
	assert_object(s.dialog).is_not_null()
	s.dialog.confirmed.emit()
	assert_str(s.cells["lane_1:keyboard"].text).is_equal("1")
	assert_object(s.dialog).is_null()


func test_reset_dialog_keep_bindings_changes_nothing() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_G))
	s.request_reset()
	s.dialog.cancelled.emit()
	assert_str(cell.text).is_equal("G")


func test_slider_changes_persist_to_settings() -> void:
	var s := _screen()
	s.scroll_slider.set_value(2.5)
	assert_float(Settings.scroll_speed).is_equal_approx(2.5, 0.0001)
	s.master_slider.set_value(50.0)
	assert_float(Settings.volume_master).is_equal_approx(0.5, 0.0001)
	s.sfx_slider.step_by(-1)
	assert_float(Settings.volume_sfx).is_equal_approx(0.75, 0.0001)
	s.no_fail_button.pressed.emit()
	assert_bool(Settings.no_fail).is_true()
	assert_str(s.no_fail_button.text).is_equal("[ ON ]")
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TEST_PATH)).is_equal(OK)
	assert_float(float(cfg.get_value("gameplay", "scroll_speed"))).is_equal_approx(2.5, 0.0001)
	assert_bool(bool(cfg.get_value("gameplay", "no_fail"))).is_true()


func test_overlay_back_emits_closed_and_keeps_scene() -> void:
	var s := _screen(true)
	var scene_before := get_tree().current_scene
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	var closed_count := [0]
	s.closed.connect(func() -> void: closed_count[0] += 1)
	s.back_pressed()
	assert_int(closed_count[0]).is_equal(1)
	assert_int(calls.size()).is_equal(0)
	assert_bool(get_tree().current_scene == scene_before).is_true()
	assert_bool(s.recalibrate_button.disabled).is_true()


func test_full_mode_back_goes_to_main_menu() -> void:
	var s := _screen(false)
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	s.back_pressed()
	assert_array(calls).is_equal(["res://scenes/main_menu.tscn"])


func test_initial_focus_set_in_code() -> void:
	var s := _screen()
	await get_tree().process_frame
	assert_bool(s.cells["lane_1:keyboard"].has_focus()).is_true()


func _main_menu() -> MainMenu:
	MainMenu.boot_handled = true
	var m: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(m)
	auto_free(m)
	return m


func test_practice_button_directly_under_start() -> void:
	var m := _main_menu()
	assert_str(m.practice_button.text).is_equal("Practice Dive (No-Fail)")
	assert_int(m.practice_button.get_index()).is_equal(m.start_button.get_index() + 1)
	assert_bool(m.start_button.get_node(m.start_button.focus_neighbor_bottom) == m.practice_button).is_true()
	assert_bool(m.practice_button.get_node(m.practice_button.focus_neighbor_top) == m.start_button).is_true()
	assert_bool(m.start_button.has_focus()).is_true()


func test_launch_practice_sets_pending_and_keeps_no_fail_setting() -> void:
	var m := _main_menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	Settings.no_fail = false
	m.launch_practice()
	assert_bool(Gameplay.pending_practice).is_true()
	assert_bool(Gameplay.pending_autoplay).is_false()
	assert_array(calls).is_equal([MainMenu.GAMEPLAY_SCENE])
	assert_bool(Settings.no_fail).is_false()
	m.launch(false)
	assert_bool(Gameplay.pending_practice).is_false()
	Gameplay.pending_chart = null
	MainMenu.boot_handled = false
