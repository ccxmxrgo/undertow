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


func test_menu_music_defaults_on_and_roundtrips() -> void:
	var a: Node = auto_free(SettingsScript.new())
	assert_bool(a.menu_music).is_true()
	a.menu_music = false
	assert_int(a.save_to(PATH)).is_equal(OK)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	assert_bool(cfg.get_value("audio", "menu_music", true)).is_false()
	var b: Node = auto_free(SettingsScript.new())
	b.load_from(PATH)
	assert_bool(b.menu_music).is_false()
	b.reset_defaults()
	assert_bool(b.menu_music).is_true()


func test_menu_music_missing_or_wrong_type_loads_true() -> void:
	_write("[audio]\nmusic=0.5\n")
	var s: Node = auto_free(SettingsScript.new())
	s.menu_music = false
	s.load_from(PATH)
	assert_bool(s.menu_music).is_true()
	_write("[audio]\nmenu_music=\"no\"\n")
	s.load_from(PATH)
	assert_bool(s.menu_music).is_true()


func test_library_roundtrip() -> void:
	var a: Node = auto_free(SettingsScript.new())
	a.library_folders = ["C:/songs/one", "D:/ch"] as Array[String]
	a.last_song_id = "u1.abc.x"
	a.last_difficulty = "hard"
	assert_int(a.save_to(PATH)).is_equal(OK)
	var b: Node = auto_free(SettingsScript.new())
	b.load_from(PATH)
	assert_array(b.library_folders).is_equal(["C:/songs/one", "D:/ch"])
	assert_str(b.last_song_id).is_equal("u1.abc.x")
	assert_str(b.last_difficulty).is_equal("hard")
	b.reset_defaults()
	assert_array(b.library_folders).is_empty()
	assert_str(b.last_song_id).is_equal("")
	assert_str(b.last_difficulty).is_equal("")


func test_old_config_without_library_loads_defaults() -> void:
	_write("[gameplay]\nscroll_speed=1.5\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_array(s.library_folders).is_empty()
	assert_str(s.last_difficulty).is_equal("")
	assert_float(s.scroll_speed).is_equal_approx(1.5, 1e-9)


func test_garbage_library_section_is_sanitised() -> void:
	_write("[gameplay]\nscroll_speed=2.0\n[library]\nfolders=5\nlast_song_id=[1,2]\nlast_difficulty=\"nightmare\"\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_array(s.library_folders).is_empty()
	assert_str(s.last_song_id).is_equal("")
	assert_str(s.last_difficulty).is_equal("")
	assert_float(s.scroll_speed).is_equal_approx(2.0, 1e-9)


func test_library_list_caps_and_filters() -> void:
	var items := ["1", 2, "", "x".repeat(1025)]
	for i in range(12):
		items.append("C:/f%d" % i)
	var cfg := ConfigFile.new()
	cfg.set_value("library", "folders", items)
	cfg.set_value("library", "last_song_id", "y".repeat(2000))
	cfg.set_value("library", "last_difficulty", "expert")
	cfg.save(PATH)
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_int(s.library_folders.size()).is_equal(8)
	assert_str(s.library_folders[0]).is_equal("1")
	assert_str(s.library_folders[1]).is_equal("C:/f0")
	assert_str(s.last_song_id).is_equal("")
	assert_str(s.last_difficulty).is_equal("expert")


func test_versus_defaults() -> void:
	var s: Node = auto_free(SettingsScript.new())
	s.versus_rivals = 1
	s.versus_skill = "veteran"
	s.training_payload = "all"
	s.reset_defaults()
	assert_int(s.versus_rivals).is_equal(3)
	assert_str(s.versus_skill).is_equal("regular")
	assert_str(s.versus_song_id).is_equal("")
	assert_str(s.versus_difficulty).is_equal("")
	assert_str(s.training_payload).is_equal("off")


func test_versus_roundtrip() -> void:
	var a: Node = auto_free(SettingsScript.new())
	a.versus_rivals = 2
	a.versus_skill = "veteran"
	a.versus_song_id = "builtin:hrt"
	a.versus_difficulty = "expert"
	a.training_payload = "ink_cloud"
	assert_int(a.save_to(PATH)).is_equal(OK)
	var b: Node = auto_free(SettingsScript.new())
	b.load_from(PATH)
	assert_int(b.versus_rivals).is_equal(2)
	assert_str(b.versus_skill).is_equal("veteran")
	assert_str(b.versus_song_id).is_equal("builtin:hrt")
	assert_str(b.versus_difficulty).is_equal("expert")
	assert_str(b.training_payload).is_equal("ink_cloud")


func test_versus_garbage_is_sanitised() -> void:
	_write("[versus]\nrivals=9\nskill=\"boss\"\nsong_id=5\ndifficulty=\"nightmare\"\ntraining=\"lane_flip\"\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_int(s.versus_rivals).is_equal(3)
	assert_str(s.versus_skill).is_equal("regular")
	assert_str(s.versus_song_id).is_equal("")
	assert_str(s.versus_difficulty).is_equal("")
	assert_str(s.training_payload).is_equal("off")
	_write("[versus]\nrivals=0\nskill=[1]\ntraining=7\n")
	s.load_from(PATH)
	assert_int(s.versus_rivals).is_equal(1)
	assert_str(s.versus_skill).is_equal("regular")
	assert_str(s.training_payload).is_equal("off")


func test_old_config_without_versus_loads_defaults() -> void:
	_write("[gameplay]\nscroll_speed=1.5\n")
	var s: Node = auto_free(SettingsScript.new())
	s.load_from(PATH)
	assert_int(s.versus_rivals).is_equal(3)
	assert_str(s.training_payload).is_equal("off")
