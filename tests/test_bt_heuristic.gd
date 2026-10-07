extends GdUnitTestSuite
## D-17 (refined in 01-09): Bluetooth warning is a name heuristic only.


func test_flags_bluetooth_like_names() -> void:
	for n in ["Bluetooth Headphones", "AirPods Pro", "Galaxy Buds",
			"bluetooth speaker", "Hands-Free AG Audio", "Wireless Stereo (Sony)",
			"Headset (Galaxy Buds2 Hands-Free)", "Headset (Foo Bluetooth)"]:
		assert_bool(DeviceHeuristics.is_bluetooth_name(n)).is_true()


func test_does_not_flag_wired_or_empty() -> void:
	for n in ["Speakers (Realtek Audio)", "", "Digital Output (HDMI)", "Line Out"]:
		assert_bool(DeviceHeuristics.is_bluetooth_name(n)).is_false()


## Reason: bare "headset" no longer counts (D-17 refinement); it false-positives on wired/dongle gear.
func test_bare_headset_is_not_bluetooth() -> void:
	for n in ["Razer BlackShark V2 Pro 2.4", "Headset Earphone (Razer BlackShark V2 Pro 2.4)",
			"Headset", "USB Headset"]:
		assert_bool(DeviceHeuristics.is_bluetooth_name(n)).is_false()
