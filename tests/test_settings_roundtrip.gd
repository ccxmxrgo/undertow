extends GdUnitTestSuite

const SettingsScript := preload("res://src/autoload/settings.gd")
const PATH := "user://test_settings.cfg"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_roundtrip_offsets_and_scroll() -> void:
	var a: Node = auto_free(SettingsScript.new())
	a.audio_offset = 0.037
	a.visual_offset = -0.012
	a.scroll_speed = 1.7
	a.output_device_name = "Speakers"
	assert_int(a.save_to(PATH)).is_equal(OK)
	var b: Node = auto_free(SettingsScript.new())
	b.load_from(PATH)
	assert_float(b.audio_offset).is_equal_approx(0.037, 1e-9)
	assert_float(b.visual_offset).is_equal_approx(-0.012, 1e-9)
	assert_float(b.scroll_speed).is_equal_approx(1.7, 1e-9)
	assert_str(b.output_device_name).is_equal("Speakers")


func test_out_of_range_values_clamp() -> void:
	_write("[calibration]\naudio_offset=9999.0\nvisual_offset=-9999\n[gameplay]\nscroll_speed=50.0\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_float(s.audio_offset).is_equal(0.5)
	assert_float(s.visual_offset).is_equal(-0.5)
	assert_float(s.scroll_speed).is_equal(3.0)


func test_wrong_type_falls_back_to_default() -> void:
	_write("[calibration]\naudio_offset=\"abc\"\nvisual_offset=[1,2]\noutput_device=5\n[gameplay]\nscroll_speed=true\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_float(s.audio_offset).is_equal(0.0)
	assert_float(s.visual_offset).is_equal(0.0)
	assert_float(s.scroll_speed).is_equal(1.0)
	assert_str(s.output_device_name).is_equal("")


func test_corrupt_file_restores_defaults_and_backs_up() -> void:
	_write("[calibration]\naudio_offset=\nscroll_speed=[1,\n")
	var s: Node = auto_free(SettingsScript.new())
	s.audio_offset = 0.2
	s.load_from(PATH)
	assert_float(s.audio_offset).is_equal(0.0)
	assert_float(s.scroll_speed).is_equal(1.0)
	assert_bool(FileAccess.file_exists(PATH + ".bak")).is_true()


func test_missing_file_gives_defaults() -> void:
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_float(s.audio_offset).is_equal(0.0)
	assert_float(s.scroll_speed).is_equal(1.0)


func test_click_chart_has_16_notes_cycling_lanes_at_beat_times() -> void:
	var c := TestCharts.click_chart(120.0, 16, 44100)
	assert_int(c.notes.size()).is_equal(16)
	for i in range(16):
		assert_int(c.notes[i]["lane"]).is_equal(i % 4)
		assert_float(c.notes[i]["time"]).is_equal_approx(i * 0.5, 1e-9)
	assert_object(c.audio_stream).is_not_null()


func test_roundtrip_display_flags() -> void:
	var a: Node = auto_free(SettingsScript.new())
	a.fullscreen = false
	a.low_effects = true
	assert_int(a.save_to(PATH)).is_equal(OK)
	var b: Node = auto_free(SettingsScript.new())
	b.load_from(PATH)
	assert_bool(b.fullscreen).is_false()
	assert_bool(b.low_effects).is_true()
