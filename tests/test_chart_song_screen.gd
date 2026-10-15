extends GdUnitTestSuite
## Chart a Song screen, first half (02.2.2 plan 08, D-01 / D-03 / D-14): pack_missing,
## installing, pick and options states, the picker / drop seams, the validated job dictionary,
## ui_cancel per state and gamepad reachability. The installer is real but never touches the
## network (fake fetcher, injected spec, root_override under user://).

const SCENE := "res://scenes/chart_song.tscn"
const D := "user://test_chart_screen"
const GB := 1024 * 1024 * 1024

var _calls: Array = []
var _jobs: Array = []
var _fetches: Array = []
var _picker_paths: Dictionary = {}  # mode -> path ("" = cancelled)
var _picker_modes: Array = []


class FakeLibrary:
	extends RefCounted
	var dir := ""

	func songs_dir() -> String:
		return dir


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)
	AutochartPaths.root_override = D + "/root"
	_calls = []
	_jobs = []
	_fetches = []
	_picker_paths = {}
	_picker_modes = []


func after_test() -> void:
	SongFixture.rm_tree(D)
	AutochartPaths.root_override = ""


func _part(name: String, size: int = 410 * 1000 * 1000) -> Dictionary:
	return {"name": name, "size": size, "sha256": "ab".repeat(32), "roots": ["rt"]}


func _spec(parts: Array, unpacked: int = 1300 * 1000 * 1000) -> Dictionary:
	return {"version": 1, "tag": "autocharter-pack-v1", "base_url": "https://example.invalid/rel/",
		"parts": parts, "unpacked_bytes": unpacked}


func _installer(spec: Dictionary) -> PackInstaller:
	var inst := PackInstaller.new()
	inst.spec = spec
	inst.fetcher = func(url: String, _dest: String, _size: int, _done: Callable) -> void:
		_fetches.append(url.get_file())  # never completes: the run stays in "downloading"
	inst.free_space = func(_p: String) -> int: return 10 * GB
	return inst


## Writes installed.json + rt/python.exe so is_installed() is true for `spec`.
func _fake_install(spec: Dictionary, selftest: bool = true) -> void:
	var parts := {}
	for p in spec["parts"]:
		parts[p["name"]] = p["sha256"]
	SongFixture.mkdir(AutochartPaths.version_dir(1).path_join("rt"))
	SongFixture.write_text(AutochartPaths.python_exe(1), "MZ")
	SongFixture.write_text(AutochartPaths.marker_path(1), JSON.stringify(
		{"pack_version": 1, "parts": parts, "selftest": selftest}))


func _screen(spec: Dictionary, installed: bool = false) -> ChartSongScreen:
	if installed:
		_fake_install(spec)
	var s: ChartSongScreen = (load(SCENE) as PackedScene).instantiate()
	s.installer = _installer(spec)
	var lib := FakeLibrary.new()
	lib.dir = ProjectSettings.globalize_path(D + "/songs").simplify_path()
	s.library = lib
	s.navigate = func(p: String) -> void: _calls.append(p)
	s.file_picker = func(mode: String, done: Callable) -> void:
		_picker_modes.append(mode)
		var p: String = _picker_paths.get(mode, "")
		if p != "":
			done.call(p)
	s.start_requested.connect(func(job: Dictionary) -> void: _jobs.append(job))
	add_child(s)
	auto_free(s)
	return s


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _cancel() -> void:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := InputEventAction.new()
	up.action = &"ui_cancel"
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


# ---- pack_missing --------------------------------------------------------------------------


func test_opens_in_pack_missing_with_size_line_and_download_focused() -> void:
	var s := _screen(_spec([_part("a.zip", 300 * 1000 * 1000), _part("b.zip", 110 * 1000 * 1000)]))
	await get_tree().process_frame
	assert_str(s.state()).is_equal("pack_missing")
	assert_str(s.heading_text()).is_equal("AUTOCHARTER PACK NEEDED")
	var body := s.body_text()
	assert_str(body).contains("Chart a Song turns an audio file you own into a playable chart.")
	assert_str(body).contains("It needs a one-time download of 410 MB (about 1.3 GB on disk).")
	assert_str(body).contains("Charting runs on your PC. Your music never leaves it.")
	assert_bool(s.download_button.disabled).is_false()
	assert_bool(s.install_folder_button.disabled).is_false()
	assert_object(_focus()).is_same(s.download_button)


func test_not_available_disables_download_and_focuses_back() -> void:
	var s := _screen(_spec([]))
	await get_tree().process_frame
	assert_str(s.state()).is_equal("pack_missing")
	assert_str(s.body_text()).contains(PackInstaller.NOT_AVAILABLE_TEXT)
	assert_str(s.body_text()).not_contains("one-time download")
	assert_bool(s.download_button.disabled).is_true()
	assert_bool(s.install_folder_button.disabled).is_true()
	assert_object(_focus()).is_same(s.pack_back_button)


func test_download_starts_installer_and_progress_updates_label_and_bar() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.download_button.pressed.emit()
	assert_str(s.state()).is_equal("installing")
	assert_str(s.heading_text()).is_equal("INSTALLING THE AUTOCHARTER")
	assert_array(_fetches).is_equal(["a.zip"])
	assert_str(s.installer.state()).is_equal("downloading")
	s.installer.progress_changed.emit(123, 410, "Downloading 123 / 410 MB")
	assert_str(s.progress_label.text).is_equal("Downloading 123 / 410 MB")
	assert_float(s.progress_bar.value / s.progress_bar.max_value).is_equal_approx(123.0 / 410.0, 0.001)
	assert_object(_focus()).is_same(s.cancel_install_button)
	s.installer.cancel()


func test_install_failure_returns_to_pack_missing_with_red_footer() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.download_button.pressed.emit()
	s.installer.cancel()
	s.installer.failed.emit("network", PackInstaller.NETWORK_TEXT)
	assert_str(s.state()).is_equal("pack_missing")
	assert_str(s.footer_text()).is_equal(PackInstaller.NETWORK_TEXT)
	assert_bool(s.footer_is_error()).is_true()


func test_installed_signal_moves_to_pick() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.download_button.pressed.emit()
	s.installer.cancel()
	s.installer.installed.emit()
	assert_str(s.state()).is_equal("pick")
	assert_str(s.heading_text()).is_equal("PICK A SONG")


func test_install_from_folder_sets_source_dir_and_starts() -> void:
	var folder := ProjectSettings.globalize_path(D + "/parts").simplify_path()
	SongFixture.mkdir(D + "/parts")
	_picker_paths["dir"] = folder
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.install_folder_button.pressed.emit()
	assert_array(_picker_modes).is_equal(["dir"])
	assert_str(s.installer.source_dir).is_equal(folder)
	assert_array(_fetches).is_empty()
	# The part is missing from the folder, so the installer fails and the screen says why.
	assert_str(s.state()).is_equal("pack_missing")
	assert_str(s.footer_text()).contains("a.zip")


func test_install_from_folder_cancelled_picker_does_nothing() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.install_folder_button.pressed.emit()
	assert_str(s.state()).is_equal("pack_missing")
	assert_str(s.installer.state()).is_equal("idle")


# ---- pick ----------------------------------------------------------------------------------


func test_installed_pack_opens_in_pick() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	assert_str(s.state()).is_equal("pick")
	assert_object(_focus()).is_same(s.choose_file_button)


func test_picked_flac_goes_to_options_with_prefill() -> void:
	_picker_paths["file"] = "C:/x/song.flac"
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.choose_file_button.pressed.emit()
	assert_array(_picker_modes).is_equal(["file"])
	assert_str(s.state()).is_equal("options")
	assert_str(s.heading_text()).is_equal("CHART OPTIONS")
	assert_str(s.name_edit.text).is_equal("song")
	assert_str(s.artist_edit.text).is_equal("Unknown")
	assert_str(s.file_label.text).is_equal("File: song.flac")
	assert_int(s.name_edit.max_length).is_equal(120)
	assert_int(s.artist_edit.max_length).is_equal(120)
	assert_str(s.selected_instrument()).is_equal("auto")


func test_mp3_prefill_reads_id3() -> void:
	var p := D + "/tagged.mp3"
	SongFixture.write_bytes(p, SongFixture.mp3_bytes("Deep Water", "The Divers"))
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.pick_file(ProjectSettings.globalize_path(p))
	assert_str(s.state()).is_equal("options")
	assert_str(s.name_edit.text).is_equal("Deep Water")
	assert_str(s.artist_edit.text).is_equal("The Divers")


func test_unsupported_type_stays_in_pick_with_reason() -> void:
	_picker_paths["file"] = "C:/x/song.m4a"
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.choose_file_button.pressed.emit()
	assert_str(s.state()).is_equal("pick")
	assert_str(s.footer_text()).is_equal(AutochartJob.error_text("bad_type"))
	assert_bool(s.footer_is_error()).is_true()


func test_dropped_mp3_in_pick_goes_to_options() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.drop_files(PackedStringArray(["C:/music/Track One.mp3", "C:/music/other.wav"]))
	assert_str(s.state()).is_equal("options")
	assert_str(s.name_edit.text).is_equal("Track One")


func test_drop_ignored_while_pack_missing() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.drop_files(PackedStringArray(["C:/music/a.mp3"]))
	assert_str(s.state()).is_equal("pack_missing")


func test_clear_cache_button_emits_signal() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	var n := [0]
	s.clear_cache_requested.connect(func() -> void: n[0] += 1)
	s.clear_cache_button.pressed.emit()
	assert_int(n[0]).is_equal(1)


func test_remove_pack_confirms_then_returns_to_pack_missing() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.remove_pack_button.pressed.emit()
	assert_object(s.dialog).is_not_null()
	assert_str(s.dialog.title_label.text).is_equal("REMOVE THE AUTOCHARTER?")
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.version_dir(1))).is_true()
	s.dialog.confirmed.emit()
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.version_dir(1))).is_false()
	assert_str(s.state()).is_equal("pack_missing")


func test_remove_pack_keep_leaves_pack() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.remove_pack_button.pressed.emit()
	s.dialog.cancelled.emit()
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.version_dir(1))).is_true()
	assert_str(s.state()).is_equal("pick")
	assert_object(s.dialog).is_null()


# ---- options -> job ------------------------------------------------------------------------


func _options_screen() -> ChartSongScreen:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	s.pick_file("C:/x/song.flac")
	return s


func test_bass_start_emits_validated_single_bass_job() -> void:
	var s: ChartSongScreen = await _options_screen()
	s.instrument_buttons["bass"].pressed.emit()
	s.instrument_buttons["bass"].button_pressed = true
	assert_str(s.selected_instrument()).is_equal("bass")
	assert_str(s.instrument_description.text).is_equal("Follows the bass line on the 4 lanes.")
	s.start_button.pressed.emit()
	assert_int(_jobs.size()).is_equal(1)
	var job: Dictionary = _jobs[0]
	assert_str(job["mode"]).is_equal("single")
	assert_str(job["stem"]).is_equal("bass")
	assert_str(job["src"]).is_equal("C:/x/song.flac")
	assert_str(job["name"]).is_equal("song")
	assert_str(AutochartJob.validate(job)).is_equal("")
	assert_str(job["models_root"]).is_equal(AutochartPaths.models_dir())
	assert_str(job["work_root"]).is_equal(AutochartPaths.work_root())


func test_mode_mapping_for_every_instrument() -> void:
	var s: ChartSongScreen = await _options_screen()
	var expect := {"auto": ["auto", "other"], "melody": ["single", "other"], "bass": ["single", "bass"],
		"drums": ["single", "drums"], "vocals": ["single", "vocals"], "lanes": ["lanes", "other"]}
	for key: String in expect:
		s.select_instrument(key)
		_jobs.clear()
		s.start_button.pressed.emit()
		assert_int(_jobs.size()).override_failure_message(key).is_equal(1)
		var job: Dictionary = _jobs[0]
		assert_str(job["mode"]).override_failure_message(key).is_equal(expect[key][0])
		assert_str(job["stem"]).override_failure_message(key).is_equal(expect[key][1])
		assert_str(AutochartJob.validate(job)).is_equal("")


func test_instrument_labels_and_descriptions() -> void:
	var s: ChartSongScreen = await _options_screen()
	var labels: Array = []
	for key: String in ["auto", "melody", "bass", "drums", "vocals", "lanes"]:
		labels.append((s.instrument_buttons[key] as Button).text)
	assert_array(labels).is_equal(["Auto (recommended)", "Melody", "Bass", "Drums", "Vocals", "Instrument Lanes"])
	s.select_instrument("lanes")
	assert_str(s.instrument_description.text).is_equal("Each lane is one instrument: bass, drums, melody, vocals.")
	s.select_instrument("auto")
	assert_str(s.instrument_description.text).is_equal("Picks the clearest instrument for you.")


func test_empty_name_shows_reason_and_emits_nothing() -> void:
	var s: ChartSongScreen = await _options_screen()
	s.name_edit.text = "   "
	s.start_button.pressed.emit()
	assert_array(_jobs).is_empty()
	assert_str(s.footer_text()).is_equal("Enter a song name.")
	assert_bool(s.footer_is_error()).is_true()


# ---- ui_cancel -----------------------------------------------------------------------------


func test_cancel_in_options_returns_to_pick() -> void:
	var s: ChartSongScreen = await _options_screen()
	s.start_button.grab_focus()
	await _cancel()
	assert_str(s.state()).is_equal("pick")
	assert_array(_calls).is_empty()


func test_cancel_in_pick_and_pack_missing_goes_to_menu() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	await _cancel()
	assert_array(_calls).is_equal([ChartSongScreen.MENU_SCENE])
	var s2 := _screen(_spec([]))
	s.queue_free()
	await get_tree().process_frame
	_calls.clear()
	await _cancel()
	assert_str(s2.state()).is_equal("pack_missing")
	assert_array(_calls).is_equal([ChartSongScreen.MENU_SCENE])


func test_cancel_while_installing_asks_then_stops() -> void:
	var s := _screen(_spec([_part("a.zip")]))
	await get_tree().process_frame
	s.download_button.pressed.emit()
	await _cancel()
	assert_object(s.dialog).is_not_null()
	assert_str(s.dialog.title_label.text).is_equal("STOP THE INSTALL?")
	assert_str(s.state()).is_equal("installing")
	s.dialog.confirmed.emit()
	assert_str(s.installer.state()).is_equal("idle")
	assert_str(s.state()).is_equal("pack_missing")
	assert_array(_calls).is_empty()


# ---- gamepad reachability ------------------------------------------------------------------


func _interactive(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if (c is Button and not (c as Button).disabled) or c is LineEdit:
			if (c as Control).focus_mode != Control.FOCUS_NONE:
				out.append(c)
		_interactive(c, out)


func _walk(from: Control) -> Array:
	var seen: Array = [from]
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
			var p := c.get_focus_neighbor(side)
			if p.is_empty():
				continue
			var n := c.get_node_or_null(p) as Control
			if n != null and not seen.has(n):
				seen.append(n)
				queue.append(n)
	return seen


func _assert_reachable(s: ChartSongScreen) -> void:
	var want: Array = []
	_interactive(s.state_container(), want)
	assert_int(want.size()).is_greater(0)
	var got := _walk(_focus())
	for c in want:
		assert_bool(got.has(c)).override_failure_message("%s not reachable in %s" % [c.name, s.state()]).is_true()
	for c in got:
		assert_bool(want.has(c)).override_failure_message("%s leaks out of %s" % [c.name, s.state()]).is_true()


func test_every_control_reachable_by_focus_in_each_state() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	_assert_reachable(s)  # pick
	s.pick_file("C:/x/song.wav")
	await get_tree().process_frame
	_assert_reachable(s)  # options
	s.show_state("pack_missing")
	await get_tree().process_frame
	_assert_reachable(s)
	s.show_state("installing")
	await get_tree().process_frame
	_assert_reachable(s)


func test_not_available_state_focus_ring_skips_disabled() -> void:
	var s := _screen(_spec([]))
	await get_tree().process_frame
	_assert_reachable(s)
	assert_array(_walk(_focus())).is_equal([s.pack_back_button])


func test_pad_down_moves_focus_in_options() -> void:
	var s: ChartSongScreen = await _options_screen()
	await get_tree().process_frame
	var first := _focus()
	assert_object(first).is_same(s.name_edit)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(s.artist_edit)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(s.instrument_buttons["auto"])
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focus()).is_same(s.instrument_buttons["melody"])
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	assert_object(_focus()).is_same(s.start_button)
