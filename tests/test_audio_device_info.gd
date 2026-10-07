extends GdUnitTestSuite
## AudioDeviceInfo with an injected provider (no real audio needed).

var _state: Dictionary


func before_test() -> void:
	_state = {"configured": "Default", "devices": PackedStringArray(["Default", "Speakers", "Headphones"]),
		"mix_rate": 48000, "latency_s": 0.0100}


func _info() -> AudioDeviceInfo:
	return AudioDeviceInfo.new(func() -> Dictionary: return _state.duplicate())


func test_list_order_does_not_change_signature() -> void:
	var a: String = _info().snapshot().signature
	_state["devices"] = PackedStringArray(["Headphones", "Default", "Speakers"])
	assert_str(_info().snapshot().signature).is_equal(a)


func test_extra_endpoint_changes() -> void:
	var saved: String = _info().snapshot().signature
	_state["devices"] = PackedStringArray(["Default", "Speakers", "Headphones", "USB DAC"])
	assert_bool(_info().changed_since(saved)).is_true()


func test_mix_rate_changes() -> void:
	var saved: String = _info().snapshot().signature
	_state["mix_rate"] = 44100
	assert_bool(_info().changed_since(saved)).is_true()


func test_latency_bucket() -> void:
	_state["latency_s"] = 0.0100
	var saved: String = _info().snapshot().signature
	_state["latency_s"] = 0.0123
	assert_bool(_info().changed_since(saved)).is_false()
	_state["latency_s"] = 0.0160
	assert_bool(_info().changed_since(saved)).is_true()


func test_alias_shows_system_default_and_no_bt_warning() -> void:
	_state["devices"] = PackedStringArray(["Default", "AirPods Pro"])
	var s := _info().snapshot()
	assert_str(s.display).is_equal("System default")
	assert_bool(s.is_alias).is_true()
	assert_bool(s.is_bluetooth).is_false()


func test_named_device_displays_and_flags_bluetooth() -> void:
	_state["configured"] = "AirPods Pro"
	var s := _info().snapshot()
	assert_str(s.display).is_equal("AirPods Pro")
	assert_bool(s.is_bluetooth).is_true()


func test_named_wired_device_not_bluetooth() -> void:
	_state["configured"] = "Headset Earphone (Razer BlackShark V2 Pro 2.4)"
	assert_bool(_info().snapshot().is_bluetooth).is_false()


func test_odd_provider_data_does_not_crash() -> void:
	var bad := AudioDeviceInfo.new(func() -> Variant: return 42)
	assert_str(bad.snapshot().display).is_equal("System default")
	var odd := AudioDeviceInfo.new(func() -> Dictionary:
		return {"configured": 5, "devices": "x", "mix_rate": "a", "latency_s": NAN})
	assert_str(odd.snapshot().display).is_equal("System default")


func test_empty_saved_signature_is_unchanged() -> void:
	assert_bool(_info().changed_since("")).is_false()


func test_default_constructor_headless_does_not_crash() -> void:
	var info := AudioDeviceInfo.new()
	assert_str(info.snapshot().signature).is_not_empty()


func test_same_state_save_and_startup_not_changed() -> void:
	var saved: String = _info().snapshot().signature
	var startup := _info()  # fresh object, same provider values
	assert_bool(startup.changed_since(saved)).is_false()
