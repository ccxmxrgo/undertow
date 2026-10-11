extends GdUnitTestSuite
## G3 (02.2-28): the main flow screens can be operated with gamepad events alone.
## Every interaction here is an InputEventJoypadButton / InputEventJoypadMotion pushed through the
## viewport (GUI path) or Input.parse_input_event (screens that read Input), never a key or a
## direct method call.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SETTINGS_PATH := "user://test_gamepad_menus.cfg"
const D := "user://test_gamepad_menus"
const SCORES := D + "/scores.cfg"

var _old_settings_path: String
var _old_scores: String
var _old_reduce: bool


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))
	_old_settings_path = Settings.save_path
	Settings.save_path = SETTINGS_PATH
	Settings.reset_defaults()
	_old_reduce = Settings.reduce_motion
	Settings.reduce_motion = true
	_old_scores = ScoreStore.default_path
	ScoreStore.default_path = SCORES
	MainMenu.boot_handled = true
	MainMenu.records_error_shown = false
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false


func after_test() -> void:
	Settings.reduce_motion = _old_reduce
	Settings.reset_defaults()
	Settings.save_path = _old_settings_path
	ScoreStore.default_path = _old_scores
	MainMenu.boot_handled = false
	MainMenu.records_error_shown = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	for p in [SETTINGS_PATH, SETTINGS_PATH + ".bak", SCORES, SCORES + ".tmp", SCORES + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ---- helpers ------------------------------------------------------------------------------------


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_msec(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _tap(index: int) -> void:
	await Pad.tap(get_viewport(), index)


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _menu() -> MainMenu:
	var m: MainMenu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(m)
	auto_free(m)
	m.finish_entrance()
	return m


func _lib(entries: Array) -> Node:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = D + "/songs"
	lib.cache_path = D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	auto_free(lib)
	lib.entries.assign(entries)
	return lib


func _entry(id: String, title: String, artist: String) -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.artist = artist
	e.status = "ok"
	e.source = "songs"
	e.length_sec = 100.0
	e.bpm_min = 120.0
	e.bpm_max = 120.0
	for d in ["easy", "medium", "hard", "expert"]:
		e.difficulties.append({"name": d, "note_count": 100, "fingerprint": "fp_%s_%s" % [id, d]})
	return e


func _song_select(entries: Array) -> SongSelect:
	var s: SongSelect = (load(SONG_SELECT_SCENE) as PackedScene).instantiate()
	s.library = _lib(entries)
	add_child(s)
	auto_free(s)
	return s


func _score() -> HullScore:
	var s := HullScore.new(JudgeConfig.new())
	s.perfect_count = 6
	s.good_count = 2
	s.miss_count = 1
	s.max_combo = 6
	s.hull = 80.0
	return s


func _results() -> ResultsScreen:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var r := ResultsScreen.new()
	host.add_child(r)
	r.setup(_score(), false, {"eligible": true, "new_record": false, "previous_depth": -1.0}, false,
		{"title": "Fake", "artist": "Run", "difficulty": "expert", "offsets": PackedFloat32Array([0.0, 0.01]),
		"perfect_window": 0.05})
	return r


func _gameplay() -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	var gp: Gameplay = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _running(gp: Gameplay) -> void:
	var end := Time.get_ticks_msec() + 4000
	while not gp.is_began() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await _wait_msec(300)


# ---- main menu ----------------------------------------------------------------------------------


func test_main_menu_dpad_and_stick_move_focus_and_a_activates() -> void:
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	await _frames(1)
	assert_object(_focus()).is_same(m.start_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(m.practice_button)
	await Pad.flick(get_viewport(), JOY_AXIS_LEFT_Y, 1.0)
	assert_object(_focus()).is_same(m.calibrate_button)
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_object(_focus()).is_same(m.start_button)
	await _tap(JOY_BUTTON_DPAD_UP)  # wraps to the last item like the arrow keys
	assert_object(_focus()).is_same(m.quit_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(m.start_button)
	await _tap(JOY_BUTTON_A)
	assert_array(calls).is_equal([MainMenu.SONG_SELECT_SCENE])
	assert_bool(SongSelect.run_autoplay).is_false()
	assert_bool(SongSelect.run_practice).is_false()


func test_main_menu_a_on_every_item_uses_its_seam() -> void:
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	var folder := [0]
	m.open_folder = func() -> bool:
		folder[0] += 1
		return true
	await _frames(1)
	var expected := [
		[m.start_button, MainMenu.SONG_SELECT_SCENE],
		[m.practice_button, MainMenu.SONG_SELECT_SCENE],
		[m.calibrate_button, MainMenu.CALIBRATION_SCENE],
		[m.settings_button, MainMenu.SETTINGS_SCENE],
		[m.autoplay_button, MainMenu.SONG_SELECT_SCENE],
	]
	for row: Array in expected:
		assert_object(_focus()).is_same(row[0])
		calls.clear()
		await _tap(JOY_BUTTON_A)
		assert_array(calls).override_failure_message("A on %s" % (row[0] as Button).text).is_equal([row[1]])
		await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(m.open_folder_button)
	await _tap(JOY_BUTTON_A)
	assert_int(folder[0]).is_equal(1)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(m.quit_button)  # A here quits the game; reaching it is enough


func test_device_prompt_is_pad_operable() -> void:
	Settings.save_calibration(0.02, 0.0)
	Settings.output_device_signature = "stale|signature"
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	await _frames(1)
	assert_bool(m.prompt_visible()).is_true()
	assert_object(_focus()).is_same(m.prompt_calibrate_button)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focus()).is_same(m.prompt_skip_button)
	# Up / Down must not leak focus to the menu items hidden behind the prompt.
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(m.prompt_skip_button)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_object(_focus()).is_same(m.prompt_calibrate_button)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_object(_focus()).is_same(m.prompt_calibrate_button)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_A)
	assert_bool(m.prompt_visible()).is_false()
	assert_object(_focus()).is_same(m.start_button)
	assert_array(calls).is_empty()


func test_device_prompt_a_on_calibrate_opens_calibration() -> void:
	Settings.save_calibration(0.02, 0.0)
	Settings.output_device_signature = "stale|signature"
	var m := _menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	await _frames(1)
	await _tap(JOY_BUTTON_A)
	assert_array(calls).is_equal([MainMenu.CALIBRATION_SCENE])


# ---- song select --------------------------------------------------------------------------------


func test_song_select_pad_moves_changes_difficulty_sorts_and_dives_once() -> void:
	var a := _entry("a", "Aaa", "Zed")
	var b := _entry("b", "Bbb", "Abe")
	var c := _entry("c", "Ccc", "Mid")
	var s := _song_select([a, b, c])
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	await _frames(1)
	assert_str(s.debug_state()["selected"]).is_equal("a")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_str(s.debug_state()["selected"]).is_equal("b")
	await Pad.flick(get_viewport(), JOY_AXIS_LEFT_Y, 1.0)
	assert_str(s.debug_state()["selected"]).is_equal("c")
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_str(s.debug_state()["selected"]).is_equal("b")
	var before: String = s.debug_state()["difficulty"]
	await _tap(JOY_BUTTON_DPAD_LEFT)
	var after: String = s.debug_state()["difficulty"]
	assert_str(after).is_not_equal(before)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_str(s.debug_state()["difficulty"]).is_equal(before)
	await _tap(JOY_BUTTON_Y)
	assert_int(s.debug_state()["sort"]).is_equal(SongListModel.SortMode.ARTIST)
	assert_array(s.debug_state()["rows"]).is_equal(["b", "c", "a"])
	# No Button inside song select may take focus and steal A through ui_accept.
	for n in s.find_children("*", "BaseButton", true, false):
		assert_int((n as Control).focus_mode).is_equal(Control.FOCUS_NONE)
	assert_object(_focus()).is_same(s)
	calls.clear()


func test_song_select_a_dives_exactly_once() -> void:
	var cal := SongLibrary.calibration_entry()
	var s := _song_select([cal])
	var dives := [0]
	s.navigate = func(p: String) -> void:
		if p == SongSelect.GAMEPLAY_SCENE:
			dives[0] += 1
	await _frames(1)
	assert_bool(s.debug_state()["start_enabled"]).is_true()
	await _tap(JOY_BUTTON_A)
	assert_int(dives[0]).is_equal(1)
	assert_object(Gameplay.pending_chart).is_not_null()


func test_song_select_b_clears_filter_then_goes_back() -> void:
	var s := _song_select([_entry("a", "Aaa", "Zed"), _entry("b", "Bbb", "Abe")])
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	await _frames(1)
	s.type_for_test("b")  # a typed filter; B clears it first
	assert_str(s.debug_state()["filter"]).is_equal("b")
	await _tap(JOY_BUTTON_B)
	assert_str(s.debug_state()["filter"]).is_empty()
	assert_array(calls).is_empty()
	await _tap(JOY_BUTTON_B)
	assert_array(calls).is_equal([SongSelect.MENU_SCENE])


# ---- results and fail ---------------------------------------------------------------------------


func test_results_pad_skips_entrance_then_a_dpad_and_b_work() -> void:
	var r := _results()
	await _frames(2)
	var got: Array[String] = []
	r.retry_pressed.connect(func() -> void: got.append("retry"))
	r.song_select_pressed.connect(func() -> void: got.append("song_select"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	assert_bool(r.entrance_running()).is_true()
	await _tap(JOY_BUTTON_A)  # skips only
	assert_bool(r.entrance_running()).is_false()
	assert_array(got).is_empty()
	assert_object(_focus()).is_same(r.retry_button)
	await _tap(JOY_BUTTON_A)
	assert_array(got).is_equal(["retry"])
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focus()).is_same(r.song_select_button)
	await _tap(JOY_BUTTON_A)
	await Pad.flick(get_viewport(), JOY_AXIS_LEFT_Y, 1.0)
	assert_object(_focus()).is_same(r.menu_button)
	await _tap(JOY_BUTTON_A)
	assert_array(got).is_equal(["retry", "song_select", "menu"])
	await _tap(JOY_BUTTON_B)
	assert_array(got).is_equal(["retry", "song_select", "menu", "menu"])


func test_fail_screen_a_and_dpad() -> void:
	var f := FailScreen.new()
	add_child(f)
	auto_free(f)
	f.setup(120.0)
	f.play(0.05)
	await get_tree().create_timer(0.05 + FailScreen.FADE_SEC + 0.25).timeout
	var got: Array[String] = []
	f.retry_pressed.connect(func() -> void: got.append("retry"))
	f.menu_pressed.connect(func() -> void: got.append("menu"))
	assert_object(_focus()).is_same(f.retry_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(f.menu_button)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_object(_focus()).is_same(f.retry_button)
	await _tap(JOY_BUTTON_A)
	assert_array(got).is_equal(["retry"])
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_A)
	assert_array(got).is_equal(["retry", "menu"])


# ---- pause and confirm dialog -------------------------------------------------------------------


func test_pause_start_opens_dpad_moves_b_and_start_resume() -> void:
	var gp := _gameplay()
	await _running(gp)
	var pm := gp.pause_menu
	await _tap(JOY_BUTTON_START)
	assert_bool(pm.is_open()).is_true()
	assert_object(_focus()).is_same(pm.resume_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.restart_button)
	await Pad.flick(get_viewport(), JOY_AXIS_LEFT_Y, 1.0)
	assert_object(_focus()).is_same(pm.settings_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.menu_button)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.resume_button)
	await _tap(JOY_BUTTON_B)
	assert_bool(pm.is_open()).is_false()
	assert_bool(pm.is_counting_down()).is_true()
	await _wait_msec(2600)  # three-beat countdown on the short chart
	assert_bool(pm.is_counting_down()).is_false()
	await _tap(JOY_BUTTON_START)
	assert_bool(pm.is_open()).is_true()
	await _tap(JOY_BUTTON_START)
	assert_bool(pm.is_open()).is_false()


func test_pause_a_on_resume_resumes() -> void:
	var gp := _gameplay()
	await _running(gp)
	await _tap(JOY_BUTTON_START)
	assert_bool(gp.pause_menu.is_open()).is_true()
	await _tap(JOY_BUTTON_A)
	assert_bool(gp.pause_menu.is_open()).is_false()
	assert_bool(gp.pause_menu.is_counting_down()).is_true()


func test_pause_a_on_settings_opens_overlay() -> void:
	var gp := _gameplay()
	await _running(gp)
	var pm := gp.pause_menu
	await _tap(JOY_BUTTON_START)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.settings_button)
	await _tap(JOY_BUTTON_A)
	assert_bool(pm.has_settings_overlay()).is_true()
	assert_bool(pm.is_open()).is_false()


func test_confirm_dialogs_open_on_safe_b_cancels_a_confirms() -> void:
	var gp := _gameplay()
	await _running(gp)
	var pm := gp.pause_menu
	var left := [0]
	pm.menu_confirmed.disconnect(gp.go_to_menu)  # keep the test scene; count the confirm instead
	pm.menu_confirmed.connect(func() -> void: left[0] += 1)
	gp.score.score = 500  # restart asks only when there is progress to lose
	await _tap(JOY_BUTTON_START)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.restart_button)
	await _tap(JOY_BUTTON_A)
	var dlg := pm.find_children("*", "ConfirmDialog", true, false)
	assert_int(dlg.size()).is_equal(1)
	var d := dlg[0] as ConfirmDialog
	assert_object(_focus()).is_same(d.safe_button)
	await _tap(JOY_BUTTON_B)
	await _frames(1)
	assert_bool(is_instance_valid(d) and d.is_inside_tree()).is_false()
	assert_bool(pm.is_open()).is_true()  # B closed only the dialog
	assert_object(_focus()).is_same(pm.restart_button)
	# Quit: D-pad to the menu button, A opens the dialog on the safe button, D-pad left to confirm.
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(pm.menu_button)
	await _tap(JOY_BUTTON_A)
	dlg = pm.find_children("*", "ConfirmDialog", true, false)
	assert_int(dlg.size()).is_equal(1)
	d = dlg[0] as ConfirmDialog
	assert_object(_focus()).is_same(d.safe_button)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_object(_focus()).is_same(d.confirm_button)
	assert_int(left[0]).is_equal(0)
	await _tap(JOY_BUTTON_A)
	assert_int(left[0]).is_equal(1)


# ---- goggles intro and the unpaused dive --------------------------------------------------------


func test_goggles_intro_a_skips() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	var gp := _gameplay()
	await _frames(2)
	assert_bool(gp.is_began()).is_false()
	Input.parse_input_event(Pad.button(JOY_BUTTON_A, true))
	Input.parse_input_event(Pad.button(JOY_BUTTON_A, false))
	await _frames(3)
	assert_bool(gp.is_began()).is_true()


func test_goggles_intro_start_skips_without_pausing() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	var gp := _gameplay()
	await _frames(2)
	Input.parse_input_event(Pad.button(JOY_BUTTON_START, true))
	Input.parse_input_event(Pad.button(JOY_BUTTON_START, false))
	await _frames(3)
	assert_bool(gp.is_began()).is_true()
	assert_bool(gp.pause_menu.is_open()).is_false()


func test_unpaused_dive_ignores_menu_buttons_and_lanes_still_work() -> void:
	var gp := _gameplay()
	await _running(gp)
	var lanes: Array[int] = []
	gp.lane_input.lane_pressed.connect(func(l: int, _t: int) -> void: lanes.append(l))
	for idx in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		await _tap(idx)
		assert_bool(gp.pause_menu.is_open()).override_failure_message("pad %d opened pause" % idx).is_false()
		var f := _focus()
		assert_bool(f == null or not (f is BaseButton)) \
			.override_failure_message("pad %d focused %s" % [idx, f]).is_true()
	assert_bool(gp.pause_menu.is_counting_down()).is_false()
	# The default lane pad bindings still reach LaneInput.
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	Pad._send(get_viewport(), Pad.motion(JOY_AXIS_TRIGGER_LEFT, 1.0))
	Pad._send(get_viewport(), Pad.motion(JOY_AXIS_TRIGGER_LEFT, 0.0))
	Pad._send(get_viewport(), Pad.motion(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	Pad._send(get_viewport(), Pad.motion(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_array(lanes).is_equal([0, 1, 2, 3])


func test_after_pause_resume_no_button_keeps_focus() -> void:
	var gp := _gameplay()
	await _running(gp)
	await _tap(JOY_BUTTON_START)
	await _tap(JOY_BUTTON_B)
	await _wait_msec(2600)
	assert_bool(gp.pause_menu.is_counting_down()).is_false()
	var f := _focus()
	assert_bool(f == null or not (f is BaseButton) or not f.is_visible_in_tree()).is_true()
	await _tap(JOY_BUTTON_A)  # a hidden Resume button must not resume / restart anything
	assert_bool(gp.pause_menu.is_open()).is_false()
	assert_bool(gp.pause_menu.is_counting_down()).is_false()
