extends GdUnitTestSuite
## CAL-02/03/04: scroll speed, volumes, toggles, bindings persistence through Settings.

const SettingsScript := preload("res://src/autoload/settings.gd")
const PATH := "user://test_settings_04.cfg"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()
	BindingStore.new().reset_defaults()


func _cleanup() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _settings() -> Node:
	var s: Node = auto_free(SettingsScript.new())
	s.save_path = PATH
	return s


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_scroll_speed_clamps_and_snaps() -> void:
	var s := _settings()
	s.set_scroll_speed(3.14)
	assert_float(s.scroll_speed).is_equal(3.0)
	s.set_scroll_speed(0.2)
	assert_float(s.scroll_speed).is_equal(0.5)
	s.set_scroll_speed(1.23)
	assert_float(s.scroll_speed).is_equal_approx(1.2, 0.0001)
	s.set_scroll_speed(1.26)
	assert_float(s.scroll_speed).is_equal_approx(1.3, 0.0001)


func test_scroll_speed_snapped_on_load() -> void:
	_write("[gameplay]\nscroll_speed=1.27\n")
	var s := _settings()
	s.load_from(PATH)
	assert_float(s.scroll_speed).is_equal_approx(1.3, 0.0001)


func test_volume_defaults() -> void:
	var s := _settings()
	s.reset_defaults()
	assert_float(s.volume_master).is_equal(1.0)
	assert_float(s.volume_music).is_equal(0.8)
	assert_float(s.volume_sfx).is_equal(0.8)


func test_volume_clamps_applies_and_persists() -> void:
	var s := _settings()
	s.set_volume("Music", 0.5)
	var idx := AudioServer.get_bus_index("Music")
	assert_int(idx).is_greater_equal(0)
	assert_float(AudioServer.get_bus_volume_db(idx)).is_equal_approx(linear_to_db(0.5), 0.01)
	s.set_volume("SFX", 7.0)
	assert_float(s.volume_sfx).is_equal(1.0)
	s.set_volume("Master", -3.0)
	assert_float(s.volume_master).is_equal(0.0)
	var s2 := _settings()
	s2.load_from(PATH)
	assert_float(s2.volume_music).is_equal_approx(0.5, 0.0001)
	assert_float(s2.volume_sfx).is_equal(1.0)
	assert_float(s2.volume_master).is_equal(0.0)
	# Restore live bus levels so other suites are unaffected.
	s2.set_volume("Master", 1.0)
	s2.set_volume("Music", 0.8)
	s2.set_volume("SFX", 0.8)


func test_hostile_volumes_fall_back() -> void:
	_write("[audio]\nmaster=\"loud\"\nmusic=9.0\nsfx=-1.0\n")
	var s := _settings()
	s.load_from(PATH)
	assert_float(s.volume_master).is_equal(1.0)
	assert_float(s.volume_music).is_equal(1.0)
	assert_float(s.volume_sfx).is_equal(0.0)
	s.set_volume("Master", 1.0)
	s.set_volume("Music", 0.8)
	s.set_volume("SFX", 0.8)


func test_unknown_bus_ignored() -> void:
	var s := _settings()
	s.set_volume("Nope", 0.3)
	assert_float(s.volume_master).is_equal(1.0)


func test_toggle_defaults_and_persist() -> void:
	var s := _settings()
	s.reset_defaults()
	assert_bool(s.early_late_indicator).is_true()
	assert_bool(s.no_fail).is_false()
	assert_bool(s.reduce_motion).is_false()
	s.early_late_indicator = false
	s.no_fail = true
	s.reduce_motion = true
	assert_int(s.save_to(PATH)).is_equal(OK)
	var s2 := _settings()
	s2.load_from(PATH)
	assert_bool(s2.early_late_indicator).is_false()
	assert_bool(s2.no_fail).is_true()
	assert_bool(s2.reduce_motion).is_true()


func test_non_bool_toggle_falls_back() -> void:
	_write("[gameplay]\nearly_late_indicator=5\nno_fail=\"yes\"\n")
	var s := _settings()
	s.load_from(PATH)
	assert_bool(s.early_late_indicator).is_true()
	assert_bool(s.no_fail).is_false()


func test_bindings_persist_via_settings() -> void:
	var s := _settings()
	s.bindings.bind_key(&"lane_1", KEY_A)
	assert_int(s.save_to(PATH)).is_equal(OK)
	s.bindings.reset_defaults()
	s.load_from(PATH)
	var found := 0
	for ev in InputMap.action_get_events(&"lane_1"):
		if ev is InputEventKey:
			found = (ev as InputEventKey).physical_keycode
	assert_int(found).is_equal(KEY_A)


func test_settings_changed_signal() -> void:
	var s := _settings()
	var count := [0]
	s.settings_changed.connect(func() -> void: count[0] += 1)
	s.set_scroll_speed(2.0)
	assert_int(count[0]).is_greater_equal(1)


# --- device signature (01-09) ---------------------------------------------------------------------

var _dev: Dictionary = {}


func _with_device(s: Node) -> void:
	_dev = {"configured": "Default", "devices": PackedStringArray(["Default", "Speakers"]),
		"mix_rate": 48000, "latency_s": 0.01}
	s.device_info = AudioDeviceInfo.new(func() -> Dictionary: return _dev.duplicate())


func test_device_unchanged_on_same_hardware() -> void:
	var s := _settings()
	_with_device(s)
	s.save_calibration(0.02, 0.0)
	assert_bool(s.device_changed()).is_false()
	var s2 := _settings()
	_with_device(s2)
	s2.load_from(PATH)
	assert_bool(s2.device_changed()).is_false()
	assert_str(s2.output_device_signature).is_equal(s.output_device_signature)


func test_device_changed_on_endpoint_mix_rate_latency() -> void:
	var s := _settings()
	_with_device(s)
	s.save_calibration(0.02, 0.0)
	_dev["latency_s"] = 0.0123
	assert_bool(s.device_changed()).is_false()
	_dev["devices"] = PackedStringArray(["Default", "Speakers", "USB DAC"])
	assert_bool(s.device_changed()).is_true()
	_dev["devices"] = PackedStringArray(["Default", "Speakers"])
	_dev["mix_rate"] = 44100
	assert_bool(s.device_changed()).is_true()


func test_legacy_file_without_signature_never_prompts() -> void:
	_write("[calibration]
audio_offset=0.02
done=true
output_device=\"Old\"
")
	var s := _settings()
	_with_device(s)
	s.load_from(PATH)
	assert_bool(s.calibration_done).is_true()
	assert_bool(s.device_changed()).is_false()


func test_tampered_signature_is_sanitised() -> void:
	_write("[calibration]
done=true
output_signature=42
output_device=[1,2]
")
	var s := _settings()
	_with_device(s)
	s.load_from(PATH)
	assert_str(s.output_device_signature).is_empty()
	assert_str(s.output_device_name).is_empty()
	assert_bool(s.device_changed()).is_false()



func test_display_defaults() -> void:
	var s := _settings()
	assert_bool(s.fullscreen).is_true()
	assert_bool(s.low_effects).is_false()


func test_display_wrong_types_fall_back() -> void:
	_write("[display]\nfullscreen=\"yes\"\nlow_effects=5\n")
	var s := _settings()
	s.load_from(PATH)
	assert_bool(s.fullscreen).is_true()
	assert_bool(s.low_effects).is_false()


func test_set_fullscreen_persists_and_emits() -> void:
	var s := _settings()
	var count := [0]
	s.settings_changed.connect(func() -> void: count[0] += 1)
	s.set_fullscreen(false)
	assert_bool(s.fullscreen).is_false()
	assert_int(count[0]).is_equal(1)
	var s2 := _settings()
	s2.load_from(PATH)
	assert_bool(s2.fullscreen).is_false()
	s.apply_window()  # headless no-op, must not error


func _f11(pressed: bool, echo: bool, key: Key = KEY_F11) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = pressed
	ev.echo = echo
	return ev


func test_f11_toggles_fullscreen() -> void:
	var s := _settings()
	s._input(_f11(true, false))
	assert_bool(s.fullscreen).is_false()
	s._input(_f11(true, true))
	assert_bool(s.fullscreen).is_false()
	s._input(_f11(true, false, KEY_F10))
	assert_bool(s.fullscreen).is_false()
	s._input(_f11(true, false))
	assert_bool(s.fullscreen).is_true()


func test_reset_defaults_restores_display() -> void:
	var s := _settings()
	s.fullscreen = false
	s.low_effects = true
	s.reset_defaults()
	assert_bool(s.fullscreen).is_true()
	assert_bool(s.low_effects).is_false()


## Godot 4.7.2 on Windows: a window CREATED fullscreen (window/size/mode=3) can never return to
## windowed (window_set_mode(WINDOWED) reports EXCLUSIVE_FULLSCREEN and ignores the size; found
## by the 01.1-05 windowed harness). The window must be created windowed at 1600x900 and
## Settings.apply_window() switches to fullscreen at boot.
func test_project_creates_window_windowed_1600x900() -> void:
	assert_int(int(ProjectSettings.get_setting("display/window/size/mode", -1))).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))).is_equal(1600)
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))).is_equal(900)


# ---- 02.2-27: background style (gap G2, T-02.2-51) ----------------------------------------

func test_background_defaults_to_calm() -> void:
	var s := _settings()
	assert_str(s.background_style).is_equal("calm")
	assert_str(s.BACKGROUND_CALM).is_equal("calm")
	assert_str(s.BACKGROUND_LIVING).is_equal("living")
	s.background_style = "living"
	s.reset_defaults()
	assert_str(s.background_style).is_equal("calm")


func test_background_missing_key_in_existing_file_is_calm() -> void:
	_write("[display]\nfullscreen=false\nlow_effects=true\n")
	var s := _settings()
	s.background_style = "living"
	s.load_from(PATH)
	assert_str(s.background_style).is_equal("calm")
	assert_bool(s.low_effects).is_true()


func test_background_round_trips_in_display_section() -> void:
	var s := _settings()
	s.background_style = "living"
	s.save_to(PATH)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PATH)).is_equal(OK)
	assert_str(String(cfg.get_value("display", "background", ""))).is_equal("living")
	var s2 := _settings()
	s2.load_from(PATH)
	assert_str(s2.background_style).is_equal("living")


func test_background_invalid_values_fall_back_to_calm() -> void:
	for bad in ["background=5", "background=\"neon\"", "background=true", "background=[\"living\"]",
			"background=\"LIVING\""]:
		_write("[display]\n%s\n" % bad)
		var s := _settings()
		s.background_style = "living"
		s.load_from(PATH)
		assert_str(s.background_style).override_failure_message(bad).is_equal("calm")


func test_set_background_style_validates_persists_and_emits() -> void:
	var s := _settings()
	var count := [0]
	s.settings_changed.connect(func() -> void: count[0] += 1)
	s.set_background_style("living")
	assert_str(s.background_style).is_equal("living")
	assert_int(count[0]).is_equal(1)
	var s2 := _settings()
	s2.load_from(PATH)
	assert_str(s2.background_style).is_equal("living")
	s.set_background_style("disco")
	assert_str(s.background_style).is_equal("calm")
	assert_int(count[0]).is_equal(2)
