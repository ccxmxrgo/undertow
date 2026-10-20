extends GdUnitTestSuite
## Plan 04-03 Task 1: [net] Settings keys (D-15, D-20), the --net-profile switch (Pitfall 10)
## and the game version (D-21). Uses a temp save_path; never touches user://settings.cfg.

const SettingsScript := preload("res://src/autoload/settings.gd")
const PATH := "user://test_settings_net.cfg"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _fresh() -> Node:
	var s: Node = auto_free(SettingsScript.new())
	s.save_path = PATH
	return s


func test_defaults() -> void:
	var s := _fresh()
	s.reset_defaults()
	assert_str(s.player_name).is_equal("DIVER")
	assert_bool(s.player_name_set).is_false()
	assert_str(s.net_last_address).is_equal("")
	assert_int(s.net_last_port).is_equal(47474)
	assert_int(s.net_flight_beats).is_equal(2)


func test_missing_file_gives_defaults() -> void:
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("DIVER")
	assert_int(s.net_last_port).is_equal(47474)


func test_roundtrip_all_five_keys() -> void:
	var a := _fresh()
	a.reset_defaults()
	a.player_name = "CAPTAIN NEMO"
	a.player_name_set = true
	a.net_last_address = "100.101.5.7"
	a.net_last_port = 50000
	a.net_flight_beats = 1
	assert_int(a.save_to(PATH)).is_equal(OK)
	var b := _fresh()
	b.load_from(PATH)
	assert_str(b.player_name).is_equal("CAPTAIN NEMO")
	assert_bool(b.player_name_set).is_true()
	assert_str(b.net_last_address).is_equal("100.101.5.7")
	assert_int(b.net_last_port).is_equal(50000)
	assert_int(b.net_flight_beats).is_equal(1)


func test_roundtrip_ipv6_address() -> void:
	var a := _fresh()
	a.reset_defaults()
	a.net_last_address = "[fd7a:115c::1]"
	a.save_to(PATH)
	var b := _fresh()
	b.load_from(PATH)
	assert_str(b.net_last_address).is_equal("[fd7a:115c::1]")


func test_junk_name_is_filtered() -> void:
	_write("[net]\nplayer_name=\"di<ver>\\n\"\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("DIVER")


func test_long_name_truncated_to_12() -> void:
	_write("[net]\nplayer_name=\"abcdefghijklmnopqrst\"\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("ABCDEFGHIJKL")


func test_all_invalid_name_falls_back() -> void:
	_write("[net]\nplayer_name=\"<<>>!!\"\nplayer_name_set=\"yes\"\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("DIVER")
	assert_bool(s.player_name_set).is_false()


func test_name_wrong_type_falls_back() -> void:
	_write("[net]\nplayer_name=42\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("DIVER")


func test_lower_case_name_upper_cased() -> void:
	_write("[net]\nplayer_name=\"sub-1_a\"\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.player_name).is_equal("SUB-1_A")


func test_bad_ports_fall_back() -> void:
	for bad in ["80", "\"abc\"", "70000", "1023", "true", "[1]"]:
		_write("[net]\nnet_last_port=%s\n" % bad)
		var s := _fresh()
		s.load_from(PATH)
		assert_int(s.net_last_port).override_failure_message("port %s" % bad).is_equal(47474)


func test_port_edges_accepted() -> void:
	_write("[net]\nnet_last_port=1024\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_int(s.net_last_port).is_equal(1024)
	_write("[net]\nnet_last_port=65535\n")
	s.load_from(PATH)
	assert_int(s.net_last_port).is_equal(65535)


func test_bad_flight_falls_back() -> void:
	for bad in ["3", "0", "\"1\"", "1.5"]:
		_write("[net]\nnet_flight_beats=%s\n" % bad)
		var s := _fresh()
		s.load_from(PATH)
		assert_int(s.net_flight_beats).override_failure_message("flight %s" % bad).is_equal(2)


func test_bad_address_falls_back() -> void:
	var long := "a".repeat(65)
	for bad in ["\"%s\"" % long, "\"host;rm\"", "\"a b\"", "5", "\"../x/y\""]:
		_write("[net]\nnet_last_address=%s\n" % bad)
		var s := _fresh()
		s.load_from(PATH)
		assert_str(s.net_last_address).override_failure_message("addr %s" % bad).is_equal("")


func test_address_trimmed() -> void:
	_write("[net]\nnet_last_address=\"  192.168.1.4 \"\n")
	var s := _fresh()
	s.load_from(PATH)
	assert_str(s.net_last_address).is_equal("192.168.1.4")


func test_clean_player_name() -> void:
	assert_str(SettingsScript.clean_player_name(" ab  c ")).is_equal("AB C")
	assert_str(SettingsScript.clean_player_name("")).is_equal("")
	assert_str(SettingsScript.clean_player_name("   ")).is_equal("")
	assert_str(SettingsScript.clean_player_name("é!@#")).is_equal("")
	assert_str(SettingsScript.clean_player_name("x".repeat(30))).is_equal("XXXXXXXXXXXX")


func test_clean_address() -> void:
	assert_str(SettingsScript.clean_address(" 10.0.0.2 ")).is_equal("10.0.0.2")
	assert_str(SettingsScript.clean_address("my-pc.local")).is_equal("my-pc.local")
	assert_str(SettingsScript.clean_address("[::1]")).is_equal("[::1]")
	assert_str(SettingsScript.clean_address("a/b")).is_equal("")
	assert_str(SettingsScript.clean_address("a".repeat(65))).is_equal("")
	assert_str(SettingsScript.clean_address("a".repeat(64))).is_equal("a".repeat(64))


func test_profile_path_from_args() -> void:
	var f := func(a: Array) -> String: return SettingsScript.profile_path_from_args(PackedStringArray(a))
	assert_str(f.call(["--net-profile=3"])).is_equal("user://settings_net3.cfg")
	assert_str(f.call(["--mute", "--net-profile=12"])).is_equal("user://settings_net12.cfg")
	assert_str(f.call(["--net-profile=../x"])).is_equal("")
	assert_str(f.call(["--net-profile="])).is_equal("")
	assert_str(f.call(["--net-profile=123"])).is_equal("")
	assert_str(f.call(["--net-profile=a"])).is_equal("")
	assert_str(f.call(["--net-profile"])).is_equal("")
	assert_str(f.call([])).is_equal("")


func test_game_version() -> void:
	assert_str(str(ProjectSettings.get_setting("application/config/version", ""))).is_equal("0.7.0")
