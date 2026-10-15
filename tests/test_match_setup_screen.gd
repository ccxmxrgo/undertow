extends GdUnitTestSuite
## MatchSetupScreen (03 UI-SPEC 9.2, MATCH-01, D-18): rows, preview, roster, focus order and
## the Start Match / song pick / back flows. Uses its own SongLibrary instance with injected
## entries and redirects Settings.save_path to a temp file.

const D := "user://test_match_setup_screen"
const SETTINGS_TMP := D + "/settings.cfg"
const SCENE := "res://scenes/match_setup.tscn"

var _old_settings_path: String
var _old_vs_song: String
var _old_vs_diff: String
var _old_vs_rivals: int
var _old_vs_skill: String
var _old_reduce: bool


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))
	_old_settings_path = Settings.save_path
	Settings.save_path = SETTINGS_TMP
	_old_vs_song = Settings.versus_song_id
	_old_vs_diff = Settings.versus_difficulty
	_old_vs_rivals = Settings.versus_rivals
	_old_vs_skill = Settings.versus_skill
	_old_reduce = Settings.reduce_motion
	Settings.reduce_motion = true
	Settings.versus_song_id = ""
	Settings.versus_difficulty = ""
	Settings.versus_rivals = 3
	Settings.versus_skill = "regular"
	_reset_statics()


func after_test() -> void:
	_reset_statics()
	Settings.versus_song_id = _old_vs_song
	Settings.versus_difficulty = _old_vs_diff
	Settings.versus_rivals = _old_vs_rivals
	Settings.versus_skill = _old_vs_skill
	Settings.reduce_motion = _old_reduce
	Settings.save_path = _old_settings_path
	for p in [SETTINGS_TMP, SETTINGS_TMP + ".tmp", SETTINGS_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _reset_statics() -> void:
	MatchSetup.pending = null
	SongSelect.run_pick = false
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false


func _entry(id: String, title: String, diffs: Array = ["easy", "medium", "hard", "expert"]) -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.artist = "Artist"
	e.status = "ok"
	e.source = "songs"
	e.length_sec = 100.0
	for d in diffs:
		e.difficulties.append({"name": d, "note_count": 100, "fingerprint": "fp_%s_%s" % [id, d]})
	return e


func _lib(entries: Array) -> Node:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = D + "/songs"
	lib.cache_path = D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	auto_free(lib)
	lib.entries.assign(entries)
	return lib


func _screen(lib: Node) -> MatchSetupScreen:
	var s: MatchSetupScreen = (load(SCENE) as PackedScene).instantiate()
	s.library = lib
	add_child(s)
	auto_free(s)
	return s


func _nav(s: MatchSetupScreen) -> Array:
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	return calls


func _cal_screen() -> MatchSetupScreen:
	var cal := SongLibrary.calibration_entry()
	Settings.versus_song_id = cal.id
	Settings.versus_difficulty = "expert"
	return _screen(_lib([cal]))


# ---- Task 1: layout, rows, preview, roster ----

func test_scene_root_and_script() -> void:
	var s := _cal_screen()
	assert_str(s.name).is_equal("MatchSetup")
	assert_object(s).is_instanceof(MatchSetupScreen)


func test_calibration_song_preview_and_initial_focus() -> void:
	var s := _cal_screen()
	var cal := SongLibrary.calibration_entry()
	var st := s.debug_state()
	assert_str(st["song_id"]).is_equal(cal.id)
	assert_str(st["song_value"]).is_equal(cal.title)
	assert_str(st["difficulty"]).is_equal("expert")
	var n := int(cal.difficulty("expert")["note_count"])
	var t := RewardMeter.threshold(n, VersusConfig.new().reward_threshold_ratio)
	assert_int(t).is_equal(RewardMeter.threshold(n, 0.12))
	assert_str(st["notes_line"]).is_equal("%d NOTES · REWARD EVERY %d PERFECTS" % [n, t])
	assert_str(st["focused"]).is_equal("start")
	assert_bool(st["start_enabled"]).is_true()


func test_empty_library_state() -> void:
	var s := _screen(_lib([]))
	var st := s.debug_state()
	assert_str(st["song_value"]).is_equal("No songs installed")
	assert_that(s.song_value_label.get_theme_color("font_color")).is_equal(Palette.TEXT_LO)
	assert_str(st["skill_line"]).is_equal("Add songs with Open Songs Folder on the main menu.")
	assert_bool(st["start_enabled"]).is_false()
	assert_bool(s.start_button.disabled).is_true()
	assert_str(st["focused"]).is_equal("song")


func test_down_cycles_rows_and_wraps() -> void:
	var s := _cal_screen()
	s.press_key_for_test(KEY_DOWN)
	assert_str(s.debug_state()["focused"]).is_equal("song")
	var order := ["difficulty", "rivals", "skill", "start", "song"]
	for want: String in order:
		s.press_key_for_test(KEY_DOWN)
		assert_str(s.debug_state()["focused"]).is_equal(want)
	s.press_key_for_test(KEY_UP)
	assert_str(s.debug_state()["focused"]).is_equal("start")


func test_rivals_right_wraps_and_roster_follows() -> void:
	var s := _cal_screen()
	assert_int(s.debug_state()["rivals"]).is_equal(3)
	assert_int((s.debug_state()["roster"] as Array).size()).is_equal(4)
	s.focus_row_for_test("rivals")
	s.press_key_for_test(KEY_RIGHT)
	var st := s.debug_state()
	assert_int(st["rivals"]).is_equal(1)
	var roster: Array = st["roster"]
	assert_int(roster.size()).is_equal(2)
	assert_str(roster[0]).is_equal("YOU")
	var names := MatchSetup.callsigns(int(st["seed"]), 1)
	assert_str(roster[1]).is_equal(names[0])
	assert_array(st["roster_chips"]).is_equal(["YOU", "REGULAR"])
	s.press_key_for_test(KEY_RIGHT)
	assert_int((s.debug_state()["roster"] as Array).size()).is_equal(3)
	s.press_key_for_test(KEY_LEFT)
	s.press_key_for_test(KEY_LEFT)
	assert_int(s.debug_state()["rivals"]).is_equal(3)


func test_skill_right_regular_to_veteran_with_description() -> void:
	var s := _cal_screen()
	assert_str(s.debug_state()["skill_line"]).is_equal("Solid timing. Earns a reward now and then.")
	s.focus_row_for_test("skill")
	s.press_key_for_test(KEY_RIGHT)
	var st := s.debug_state()
	assert_str(st["skill"]).is_equal("veteran")
	assert_str(st["skill_line"]).is_equal("Tight timing. Earns about 3 rewards a song.")
	assert_array(st["roster_chips"]).is_equal(["YOU", "VETERAN", "VETERAN", "VETERAN"])
	s.press_key_for_test(KEY_RIGHT)
	assert_str(s.debug_state()["skill"]).is_equal("rookie")
	assert_str(s.debug_state()["skill_line"]).is_equal("Loose timing and frequent misses. Rarely earns a reward.")


func test_left_right_on_song_and_start_do_nothing() -> void:
	var s := _cal_screen()
	var before := s.debug_state()
	s.press_key_for_test(KEY_RIGHT)
	s.focus_row_for_test("song")
	s.press_key_for_test(KEY_LEFT)
	var after := s.debug_state()
	for k in ["rivals", "skill", "song_id", "difficulty"]:
		assert_that(after[k]).is_equal(before[k])


func test_difficulty_cycles_available_difficulties() -> void:
	Settings.versus_song_id = "a"
	Settings.versus_difficulty = "hard"
	var s := _screen(_lib([_entry("a", "Alpha", ["easy", "hard", "expert"])]))
	assert_str(s.debug_state()["difficulty"]).is_equal("hard")
	s.focus_row_for_test("difficulty")
	s.press_key_for_test(KEY_RIGHT)
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")
	s.press_key_for_test(KEY_LEFT)
	s.press_key_for_test(KEY_LEFT)
	assert_str(s.debug_state()["difficulty"]).is_equal("easy")


func test_how_rewards_lines_use_current_bindings() -> void:
	var s := _cal_screen()
	var lines: Array = s.debug_state()["how_lines"]
	assert_int(lines.size()).is_equal(4)
	assert_str(lines[0]).is_equal("Unbroken Perfects fill your torpedo tube. A full tube loads a random reward.")
	assert_str(lines[1]).is_equal("SPACE fires it. Disruptors hit your target. Buffs help you.")
	assert_str(lines[2]).is_equal("H switches target: AUTO, each rival, ATTACKERS.")
	assert_str(lines[3]).is_equal("Hit the red-ringed notes Perfect to send a torpedo back.")


func test_defaults_from_pending_then_settings() -> void:
	var m := MatchSetup.new()
	m.rivals = 2
	m.skill = "rookie"
	MatchSetup.pending = m
	var s := _cal_screen()
	var st := s.debug_state()
	assert_int(st["rivals"]).is_equal(2)
	assert_str(st["skill"]).is_equal("rookie")


func test_out_of_range_settings_are_clamped() -> void:
	var m := MatchSetup.new()
	m.rivals = 9
	m.skill = "godlike"
	MatchSetup.pending = m
	var s := _cal_screen()
	var st := s.debug_state()
	assert_int(st["rivals"]).is_equal(3)
	assert_str(st["skill"]).is_equal("regular")


func test_unknown_song_falls_back_to_last_played() -> void:
	Settings.versus_song_id = "gone"
	var lib := _lib([_entry("a", "Alpha"), _entry("b", "Beta")])
	lib.last_song_id = "b"
	var s := _screen(lib)
	assert_str(s.debug_state()["song_id"]).is_equal("b")
	assert_str(s.debug_state()["song_value"]).is_equal("Beta")


func test_unknown_song_without_last_played_disables_start() -> void:
	Settings.versus_song_id = "gone"
	var s := _screen(_lib([_entry("a", "Alpha")]))
	var st := s.debug_state()
	assert_str(st["song_id"]).is_equal("")
	assert_bool(st["start_enabled"]).is_false()
	assert_str(st["focused"]).is_equal("song")


func test_layout_rects() -> void:
	var s := _cal_screen()
	assert_that(s.row_rect("song")).is_equal(Rect2(96, 240, 816, 64))
	assert_that(s.row_rect("difficulty")).is_equal(Rect2(96, 312, 816, 64))
	assert_that(s.row_rect("rivals")).is_equal(Rect2(96, 384, 816, 64))
	assert_that(s.row_rect("skill")).is_equal(Rect2(96, 456, 816, 64))
	assert_that(s.row_rect("start")).is_equal(Rect2(96, 808, 816, 64))
	assert_that(MatchSetupScreen.tile_rect("rivals", 0)).is_equal(Rect2(400, 392, 96, 48))
	assert_that(MatchSetupScreen.tile_rect("rivals", 2)).is_equal(Rect2(608, 392, 96, 48))
	assert_that(MatchSetupScreen.tile_rect("skill", 1)).is_equal(Rect2(568, 464, 160, 48))
	assert_that(MatchSetupScreen.roster_row_rect(3)).is_equal(Rect2(1008, 712, 848 - 32, 56))
