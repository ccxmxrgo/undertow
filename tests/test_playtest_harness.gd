extends GdUnitTestSuite
## Keeps the windowed harness compiling (it is only run by tools/playtest/run_all.ps1) and pins the
## harness / self-test hooks in SongLibrary to "off" in a normal game.


func test_playtest_driver_compiles() -> void:
	var s: GDScript = load("res://tools/playtest/playtest_driver.gd")
	assert_object(s).is_not_null()
	assert_bool(s.can_instantiate()).is_true()
	var src := s.source_code
	assert_bool(src.contains("\"songs\": await sc_songs()")).is_true()


func test_run_all_lists_songs_and_passes_no_boot_scan() -> void:
	var txt := FileAccess.get_file_as_string("res://tools/playtest/run_all.ps1")
	assert_bool(txt.contains("\"songs\"")).is_true()
	assert_bool(txt.contains("--no-boot-scan")).is_true()


func test_library_hooks_default_off() -> void:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.auto_scan = false
	add_child(lib)
	assert_int(lib.test_scan_throttle_msec).is_equal(0)
	assert_bool(lib.selftest_bundled).is_false()
	assert_str(lib.songs_root_override).is_equal("")
	assert_str(lib.cache_path).is_equal(lib.CACHE_PATH)
	lib.queue_free()


func test_export_filter_packs_charts_and_ini() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var inc: String = cfg.get_value("preset.0", "include_filter", "")
	for pat in ["*.json", "*.cfg", "*.chart", "*.ini"]:
		assert_bool(inc.split(",").has(pat)).is_true()
	var exc: String = cfg.get_value("preset.0", "exclude_filter", "")
	assert_bool(exc.contains("tests/*") and exc.contains("tools/*")).is_true()
