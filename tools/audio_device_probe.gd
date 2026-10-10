extends SceneTree
## DEV-ONLY probe (never referenced by game code; tools/* is excluded from export).
## Run WINDOWED on a real audio device:
##   & $env:GODOT_BIN --path . -s tools/audio_device_probe.gd
## Headless uses the dummy audio driver and lists only "Default".
## Prints what Godot 4.7.2 exposes about the output device.


func _init() -> void:
	preload("res://tools/test_screen.gd").move_window()  # windowed tools open on the test (secondary) screen
	print("Godot: ", Engine.get_version_info().get("string", "?"))
	print("Audio driver: ", AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "n/a")
	print("output_device: '", AudioServer.output_device, "'")
	print("device list: ", AudioServer.get_output_device_list())
	print("mix rate: ", AudioServer.get_mix_rate())
	var info := AudioDeviceInfo.new()
	print("signature #1: ", info.snapshot().signature)
	var buckets := {}
	for i in range(5):
		var l := AudioServer.get_output_latency()
		print("latency sample %d: %.4f s" % [i, l])
		buckets[roundi(l * 1000.0 / 5.0) * 5] = true
		await create_timer(1.0).timeout
	print("distinct 5 ms buckets: ", buckets.keys())
	print("signature #2: ", info.snapshot().signature)
	quit()
