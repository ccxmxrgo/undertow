extends GdUnitTestSuite
## G3 (02.2-28): the input map lets a controller drive every Button-based screen.
## A/South confirms (ui_accept), B/East goes back (ui_cancel), D-pad + left stick move focus,
## Start pauses; keyboard defaults are kept and no ui_* action reuses a lane pad binding.

const UI_ACTIONS: Array[StringName] = [
	&"ui_accept", &"ui_cancel", &"ui_select", &"ui_up", &"ui_down", &"ui_left", &"ui_right",
	&"ui_focus_next", &"ui_focus_prev", &"ui_page_up", &"ui_page_down",
]


func before_test() -> void:
	# Other suites may rebind lanes; start every test from the shipped defaults.
	BindingStore.new().reset_defaults()


func _has_key(action: StringName, keycode: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.keycode == keycode or k.physical_keycode == keycode:
				return true
	return false


func _has_button(action: StringName, index: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == index:
			return true
	return false


func _has_motion(action: StringName, axis: int, sign_value: float) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			var m := ev as InputEventJoypadMotion
			if m.axis == axis and signf(m.axis_value) == signf(sign_value):
				return true
	return false


func test_ui_accept_has_pad_a_and_keyboard_defaults() -> void:
	assert_bool(_has_button(&"ui_accept", JOY_BUTTON_A)).is_true()
	assert_bool(_has_key(&"ui_accept", KEY_ENTER)).is_true()
	assert_bool(_has_key(&"ui_accept", KEY_KP_ENTER)).is_true()
	assert_bool(_has_key(&"ui_accept", KEY_SPACE)).is_true()


func test_ui_accept_pad_binding_is_all_devices() -> void:
	for ev in InputMap.action_get_events(&"ui_accept"):
		if ev is InputEventJoypadButton:
			assert_int(ev.device).is_equal(-1)


func test_ui_cancel_has_pad_b_and_escape() -> void:
	assert_bool(_has_button(&"ui_cancel", JOY_BUTTON_B)).is_true()
	assert_bool(_has_key(&"ui_cancel", KEY_ESCAPE)).is_true()


func test_pad_events_match_the_actions() -> void:
	assert_bool(Pad.button(JOY_BUTTON_A).is_action_pressed(&"ui_accept")).is_true()
	assert_bool(Pad.button(JOY_BUTTON_B).is_action_pressed(&"ui_cancel")).is_true()
	assert_bool(Pad.button(JOY_BUTTON_START).is_action_pressed(&"pause")).is_true()
	assert_bool(Pad.button(JOY_BUTTON_DPAD_DOWN).is_action_pressed(&"ui_down")).is_true()
	assert_bool(Pad.motion(JOY_AXIS_LEFT_Y, 1.0).is_action_pressed(&"ui_down")).is_true()


func test_directions_keep_arrow_dpad_and_left_stick() -> void:
	var table := {
		&"ui_up": [KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
		&"ui_down": [KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
		&"ui_left": [KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0],
		&"ui_right": [KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
	}
	for action: StringName in table:
		var row: Array = table[action]
		assert_bool(_has_key(action, row[0])).override_failure_message("%s key" % action).is_true()
		assert_bool(_has_button(action, row[1])).override_failure_message("%s dpad" % action).is_true()
		assert_bool(_has_motion(action, row[2], row[3])).override_failure_message("%s stick" % action).is_true()


func test_pause_keeps_escape_and_start() -> void:
	assert_bool(_has_key(&"pause", KEY_ESCAPE)).is_true()
	assert_bool(_has_button(&"pause", JOY_BUTTON_START)).is_true()


func test_no_ui_action_uses_a_lane_pad_binding() -> void:
	var defaults: Dictionary = BindingStore._defaults()
	var lane_pads: Array = []
	for lane: StringName in [&"lane_1", &"lane_2", &"lane_3", &"lane_4"]:
		lane_pads.append(defaults[lane]["pad"])
	assert_int(lane_pads.size()).is_equal(4)
	for action in UI_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for pad: Dictionary in lane_pads:
			if pad["kind"] == "button":
				assert_bool(_has_button(action, pad["index"])) \
					.override_failure_message("%s uses lane button %d" % [action, pad["index"]]).is_false()
			else:
				for ev in InputMap.action_get_events(action):
					if ev is InputEventJoypadMotion:
						assert_int((ev as InputEventJoypadMotion).axis) \
							.override_failure_message("%s uses lane axis %d" % [action, pad["axis"]]) \
							.is_not_equal(pad["axis"])


func test_binding_store_reset_and_load_leave_ui_actions_alone() -> void:
	var before := {}
	for action in UI_ACTIONS:
		if InputMap.has_action(action):
			before[action] = InputMap.action_get_events(action).size()
	var store := BindingStore.new()
	store.reset_defaults()
	var cfg := ConfigFile.new()
	store.to_config(cfg)
	store.from_config(cfg)
	for action: StringName in before:
		assert_int(InputMap.action_get_events(action).size()).is_equal(before[action])
	assert_bool(_has_button(&"ui_accept", JOY_BUTTON_A)).is_true()
	assert_bool(_has_button(&"ui_cancel", JOY_BUTTON_B)).is_true()
