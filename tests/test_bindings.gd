extends GdUnitTestSuite
## CAL-02/03: default bindings, validated rebind, persistence round trip, reset.

var store: BindingStore


func before_test() -> void:
	store = BindingStore.new()
	store.reset_defaults()


func after_test() -> void:
	store.reset_defaults()


func _key_of(action: StringName) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0


func _motion_of(action: StringName) -> InputEventJoypadMotion:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			return ev
	return null


func _button_of(action: StringName) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return (ev as InputEventJoypadButton).button_index
	return -1


func test_defaults_keyboard() -> void:
	assert_int(_key_of(&"lane_1")).is_equal(KEY_D)
	assert_int(_key_of(&"lane_2")).is_equal(KEY_F)
	assert_int(_key_of(&"lane_3")).is_equal(KEY_J)
	assert_int(_key_of(&"lane_4")).is_equal(KEY_K)
	assert_int(_key_of(&"fire")).is_equal(KEY_SPACE)
	assert_int(_key_of(&"target_cycle")).is_equal(KEY_H)
	assert_int(_key_of(&"pause")).is_equal(KEY_ESCAPE)


func test_defaults_gamepad() -> void:
	assert_int(_button_of(&"lane_1")).is_equal(JOY_BUTTON_LEFT_SHOULDER)
	assert_int(_motion_of(&"lane_2").axis).is_equal(JOY_AXIS_TRIGGER_LEFT)
	assert_int(_motion_of(&"lane_3").axis).is_equal(JOY_AXIS_TRIGGER_RIGHT)
	assert_int(_button_of(&"lane_4")).is_equal(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(_button_of(&"fire")).is_equal(JOY_BUTTON_A)
	assert_int(_button_of(&"target_cycle")).is_equal(JOY_BUTTON_Y)
	assert_int(_button_of(&"pause")).is_equal(JOY_BUTTON_START)


func test_trigger_events_value_and_deadzone() -> void:
	for a in [&"lane_2", &"lane_3"]:
		assert_float(_motion_of(a).axis_value).is_equal(1.0)
	for a in BindingStore.GAMEPLAY_ACTIONS:
		assert_float(InputMap.action_get_deadzone(a)).is_equal(0.5)


func test_project_godot_declares_all_actions() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.parse(FileAccess.get_file_as_string("res://project.godot"))).is_equal(OK)
	for a in BindingStore.GAMEPLAY_ACTIONS:
		assert_bool(cfg.has_section_key("input", String(a))).is_true()
		var d: Dictionary = cfg.get_value("input", String(a))
		assert_int((d["events"] as Array).size()).is_equal(2)


func test_no_tab_anywhere_by_default() -> void:
	for a in BindingStore.GAMEPLAY_ACTIONS:
		assert_int(_key_of(a)).is_not_equal(KEY_TAB)


func test_bind_key_applies_live() -> void:
	var r := store.bind_key(&"lane_1", KEY_A)
	assert_int(r["result"]).is_equal(BindingStore.Result.OK)
	assert_int(_key_of(&"lane_1")).is_equal(KEY_A)
	assert_int(InputMap.action_get_events(&"lane_1").size()).is_equal(2)


func test_duplicate_rejected_without_change() -> void:
	var r := store.bind_key(&"lane_1", KEY_F)
	assert_int(r["result"]).is_equal(BindingStore.Result.DUPLICATE)
	assert_str(String(r["conflict_action"])).is_equal("lane_2")
	assert_int(_key_of(&"lane_1")).is_equal(KEY_D)
	assert_int(_key_of(&"lane_2")).is_equal(KEY_F)


func test_tab_is_reserved() -> void:
	var r := store.bind_key(&"fire", KEY_TAB)
	assert_int(r["result"]).is_equal(BindingStore.Result.RESERVED)
	assert_int(_key_of(&"fire")).is_equal(KEY_SPACE)


func test_escape_only_for_pause() -> void:
	assert_int(store.bind_key(&"fire", KEY_ESCAPE)["result"]).is_equal(BindingStore.Result.RESERVED)
	assert_int(_key_of(&"fire")).is_equal(KEY_SPACE)
	store.bind_key(&"pause", KEY_P)
	assert_int(store.bind_key(&"pause", KEY_ESCAPE)["result"]).is_equal(BindingStore.Result.OK)


func test_invalid_action_and_key() -> void:
	assert_int(store.bind_key(&"ui_accept", KEY_A)["result"]).is_equal(BindingStore.Result.INVALID)
	assert_int(store.bind_key(&"fire", 0)["result"]).is_equal(BindingStore.Result.INVALID)
	assert_int(store.bind_key(&"fire", -5)["result"]).is_equal(BindingStore.Result.INVALID)


func test_rebinding_same_key_to_same_action_ok() -> void:
	assert_int(store.bind_key(&"lane_1", KEY_D)["result"]).is_equal(BindingStore.Result.OK)


func test_bind_pad_button_and_duplicate() -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_X
	assert_int(store.bind_pad(&"fire", ev)["result"]).is_equal(BindingStore.Result.OK)
	assert_int(_button_of(&"fire")).is_equal(JOY_BUTTON_X)
	var dup := InputEventJoypadButton.new()
	dup.button_index = JOY_BUTTON_X
	var r := store.bind_pad(&"target_cycle", dup)
	assert_int(r["result"]).is_equal(BindingStore.Result.DUPLICATE)
	assert_str(String(r["conflict_action"])).is_equal("fire")


func test_bind_pad_accepts_only_strong_triggers_for_axes() -> void:
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	assert_int(store.bind_pad(&"fire", stick)["result"]).is_equal(BindingStore.Result.INVALID)
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_TRIGGER_LEFT
	weak.axis_value = 0.3
	assert_int(store.bind_pad(&"fire", weak)["result"]).is_equal(BindingStore.Result.INVALID)
	var good := InputEventJoypadMotion.new()
	good.axis = JOY_AXIS_TRIGGER_RIGHT
	good.axis_value = 0.9
	# Right trigger belongs to lane_3 by default: duplicate elsewhere, fine on lane_3.
	assert_int(store.bind_pad(&"fire", good)["result"]).is_equal(BindingStore.Result.DUPLICATE)
	assert_int(store.bind_pad(&"lane_3", good)["result"]).is_equal(BindingStore.Result.OK)
	assert_float(_motion_of(&"lane_3").axis_value).is_equal(1.0)


func _snapshot() -> Dictionary:
	var d := {}
	for a in BindingStore.GAMEPLAY_ACTIONS:
		var list := []
		for ev in InputMap.action_get_events(a):
			list.append(ev.as_text())
		list.sort()
		d[a] = list
	return d


func test_roundtrip_identical() -> void:
	store.bind_key(&"lane_1", KEY_A)
	store.bind_key(&"fire", KEY_ENTER)
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_X
	store.bind_pad(&"fire", ev)
	var cfg := ConfigFile.new()
	store.to_config(cfg)
	var text := cfg.encode_to_text()
	var snap := _snapshot()
	store.reset_defaults()
	assert_bool(_snapshot() == snap).is_false()
	var cfg2 := ConfigFile.new()
	assert_int(cfg2.parse(text)).is_equal(OK)
	store.from_config(cfg2)
	assert_bool(_snapshot() == snap).is_true()


func test_invalid_entries_fall_back_to_default() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "lane_1_key", "banana")
	cfg.set_value("bindings", "lane_2_key", KEY_TAB)
	cfg.set_value("bindings", "lane_3_key", 999999999)
	cfg.set_value("bindings", "lane_4_pad", [99, 7])
	cfg.set_value("bindings", "fire_pad", 100000)
	cfg.set_value("bindings", "target_cycle_key", KEY_ESCAPE)
	store.bind_key(&"lane_1", KEY_Z)
	store.from_config(cfg)
	assert_int(_key_of(&"lane_1")).is_equal(KEY_D)
	assert_int(_key_of(&"lane_2")).is_equal(KEY_F)
	assert_int(_key_of(&"lane_3")).is_equal(KEY_J)
	assert_int(_button_of(&"lane_4")).is_equal(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(_button_of(&"fire")).is_equal(JOY_BUTTON_A)
	assert_int(_key_of(&"target_cycle")).is_equal(KEY_H)


func test_duplicates_in_file_leave_no_duplicates() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "lane_1_key", KEY_F)
	cfg.set_value("bindings", "lane_2_key", KEY_F)
	store.from_config(cfg)
	var seen := {}
	for a in BindingStore.GAMEPLAY_ACTIONS:
		var k := _key_of(a)
		assert_bool(seen.has(k)).is_false()
		seen[k] = true


func test_missing_section_gives_defaults() -> void:
	store.bind_key(&"lane_1", KEY_Z)
	store.from_config(ConfigFile.new())
	assert_int(_key_of(&"lane_1")).is_equal(KEY_D)


func test_reset_restores_defaults() -> void:
	store.bind_key(&"pause", KEY_P)
	store.bind_key(&"lane_1", KEY_A)
	store.reset_defaults()
	assert_int(_key_of(&"pause")).is_equal(KEY_ESCAPE)
	assert_int(_key_of(&"lane_1")).is_equal(KEY_D)


func test_display_names() -> void:
	assert_str(store.display_name(&"lane_1", &"keyboard")).is_equal("D")
	assert_str(store.display_name(&"lane_2", &"gamepad")).is_equal("LT")
	assert_str(store.display_name(&"lane_3", &"gamepad")).is_equal("RT")
	assert_str(store.display_name(&"lane_1", &"gamepad")).is_equal("LB")
