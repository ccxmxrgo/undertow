extends GdUnitTestSuite
## D-17: Bluetooth warning is a name heuristic only.

func test_flags_bluetooth_like_names() -> void:
	for n in ["Bluetooth Headphones", "AirPods Pro", "Galaxy Buds", "USB Headset",
			"bluetooth speaker", "Hands-Free AG Audio", "Wireless Stereo (Sony)"]:
		assert_bool(DeviceHeuristics.is_bluetooth_name(n)).is_true()


func test_does_not_flag_wired_or_empty() -> void:
	for n in ["Speakers (Realtek Audio)", "", "Digital Output (HDMI)", "Line Out"]:
		assert_bool(DeviceHeuristics.is_bluetooth_name(n)).is_false()
