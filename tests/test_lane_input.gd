extends GdUnitTestSuite
## D-06/D-16/D-19: edge-detecting lane input (keys, buttons, analog triggers).

var li: LaneInput
var pressed: Array
var released: Array


func before_test() -> void:
	BindingStore.new().reset_defaults()
	li = auto_free(LaneInput.new())
	pressed = []
	released = []
	li.lane_pressed.connect(func(l: int, t: int) -> void: pressed.append([l, t]))
	li.lane_released.connect(func(l: int, t: int) -> void: released.append([l, t]))


func _key(code: Key, down: bool, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	e.echo = echo
	return e


func _trigger(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _button(idx: JoyButton, down: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = down
	return e


func test_trigger_stream_one_press_one_release() -> void:
	for v in [0.0, 0.3, 0.6, 0.8, 0.9, 0.4, 0.0]:
		li.inject(_trigger(JOY_AXIS_TRIGGER_LEFT, v))
	assert_int(pressed.size()).is_equal(1)
	assert_int(released.size()).is_equal(1)
	assert_int(pressed[0][0]).is_equal(1)  # lane_2 = left trigger


func test_trigger_noise_around_threshold_does_not_chatter() -> void:
	for v in [0.6, 0.45, 0.55, 0.48, 0.52, 0.3]:
		li.inject(_trigger(JOY_AXIS_TRIGGER_RIGHT, v))
	assert_int(pressed.size()).is_equal(1)
	assert_int(released.size()).is_equal(1)
	assert_int(pressed[0][0]).is_equal(2)


func test_wrong_direction_or_other_axis_ignored() -> void:
	li.inject(_trigger(JOY_AXIS_TRIGGER_LEFT, -0.9))
	li.inject(_trigger(JOY_AXIS_LEFT_X, 0.9))
	assert_int(pressed.size()).is_equal(0)


func test_keyboard_press_release_and_echo() -> void:
	li.inject(_key(KEY_1, true))
	li.inject(_key(KEY_1, true, true))
	li.inject(_key(KEY_1, true))
	assert_int(pressed.size()).is_equal(1)
	assert_int(pressed[0][0]).is_equal(0)
	li.inject(_key(KEY_1, false))
	assert_int(released.size()).is_equal(1)
	li.inject(_key(KEY_1, false))
	assert_int(released.size()).is_equal(1)


func test_button_behaves_like_key() -> void:
	li.inject(_button(JOY_BUTTON_LEFT_SHOULDER, true))
	li.inject(_button(JOY_BUTTON_LEFT_SHOULDER, true))
	assert_int(pressed.size()).is_equal(1)
	li.inject(_button(JOY_BUTTON_LEFT_SHOULDER, false))
	assert_int(released.size()).is_equal(1)
	assert_int(released[0][0]).is_equal(0)


func test_focus_loss_releases_all_held_lanes() -> void:
	li.inject(_key(KEY_1, true))
	li.inject(_key(KEY_4, true))
	li._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(released.size()).is_equal(2)
	li.inject(_key(KEY_1, false))
	assert_int(released.size()).is_equal(2)


func test_event_carries_tick_captured_in_input() -> void:
	var before := Time.get_ticks_usec()
	li.inject(_key(KEY_2, true))
	var after := Time.get_ticks_usec()
	assert_int(pressed[0][1]).is_between(before, after)


func test_disabled_ignores_input_and_releases_held() -> void:
	li.inject(_key(KEY_1, true))
	li.enabled = false
	assert_int(released.size()).is_equal(1)
	li.inject(_key(KEY_2, true))
	assert_int(pressed.size()).is_equal(1)
	li.enabled = true
	li.inject(_key(KEY_2, true))
	assert_int(pressed.size()).is_equal(2)


func test_drives_judge_when_connected() -> void:
	var chart := TestCharts.click_chart(120.0, 4, 8000)
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var conductor: Conductor = auto_free(Conductor.new())
	var hits := [0]
	judge.judged.connect(func(_l: int, _i: int, _j: int, _e: float) -> void: hits[0] += 1)
	li.setup(conductor, judge)
	li.inject(_key(KEY_1, true))
	li.inject(_key(KEY_1, false))
	# No crash and signals still emitted with a connected (idle) conductor.
	assert_int(pressed.size()).is_equal(1)
	assert_int(released.size()).is_equal(1)
