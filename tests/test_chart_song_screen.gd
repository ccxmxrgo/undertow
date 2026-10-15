extends GdUnitTestSuite
## Chart a Song screen (02.2.2 plans 08 + 09, D-01 / D-03 / D-05 / D-06 / D-12 / D-14):
## pack_missing, installing, pick, options, running, result and error states, the selftest gate,
## the picker / drop seams, the validated job dictionary, ui_cancel per state and gamepad
## reachability. The installer is real but never touches the network (fake fetcher, injected
## spec, root_override under user://); the runner is real with a scripted fake process.

const SCENE := "res://scenes/chart_song.tscn"
const D := "user://test_chart_screen"
const GB := 1024 * 1024 * 1024

var _calls: Array = []
var _jobs: Array = []
var _fetches: Array = []
var _picker_paths: Dictionary = {}  # mode -> path ("" = cancelled)
var _picker_modes: Array = []
var _fake: FakeAdapter
var _lib: FakeLibrary
var _opened: Array = []
var _music_stops := [0]
var _now := [1000.0]


class FakeLibrary:
	extends RefCounted
	signal scan_finished(count: int, unplayable: int)
	var dir := ""
	var last_song_id := ""
	var scanning := false
	var rescans := 0

	func songs_dir() -> String:
		return dir

	func rescan() -> void:
		rescans += 1


## Scripted child process: tests push JSON lines and decide when it exits.
class FakeAdapter:
	extends ProcessAdapter
	var chunks: Array = []
	var running := false
	var code := 0
	var kill_count := 0
	var starts: Array = []  # [exe, args]

	func start(exe: String, args: PackedStringArray) -> int:
		starts.append([exe, args])
		running = true
		return 4242

	func read_stdout() -> PackedByteArray:
		if chunks.is_empty():
			return PackedByteArray()
		return (chunks.pop_front() as String).to_utf8_buffer()

	func read_stderr() -> PackedByteArray:
		return PackedByteArray()

	func is_running() -> bool:
		return running

	func exit_code() -> int:
		return code

	func kill() -> void:
		kill_count += 1

	func close() -> void:
		pass


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)
	AutochartPaths.root_override = D + "/root"
	_calls = []
	_jobs = []
	_fetches = []
	_picker_paths = {}
	_picker_modes = []
	_fake = FakeAdapter.new()
	_opened = []
	_music_stops = [0]
	_now = [1000.0]


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


func _screen(spec: Dictionary, installed: bool = false, selftest: bool = true) -> ChartSongScreen:
	if installed:
		_fake_install(spec, selftest)
	var s: ChartSongScreen = (load(SCENE) as PackedScene).instantiate()
	s.installer = _installer(spec)
	_lib = FakeLibrary.new()
	_lib.dir = ProjectSettings.globalize_path(D + "/songs").simplify_path()
	s.library = _lib
	s.runner_factory = func() -> AutochartRunner:
		var r := AutochartRunner.new()
		r.adapter = _fake
		return r
	s.shell_opener = func(p: String) -> void: _opened.append(p)
	s.clock = func() -> float: return _now[0]
	s.music_stop = func() -> void: _music_stops[0] += 1
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
	var spec := _spec([_part("a.zip")])
	var s := _screen(spec)
	await get_tree().process_frame
	s.download_button.pressed.emit()
	s.installer.cancel()
	_fake_install(spec, true)  # selftest already passed: no test run (plan 09 gate)
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


# ---- plan 09: running ----------------------------------------------------------------------


func _ev(d: Dictionary) -> String:
	return JSON.stringify(d) + "\n"


## Queues protocol lines and lets the runner drain them once.
func _push(s: ChartSongScreen, events: Array) -> void:
	var text := ""
	for e: Dictionary in events:
		text += _ev(e)
	_fake.chunks.append(text)
	s.runner._process(0.0)


## The child exits with `code` after the queued events.
func _exit(s: ChartSongScreen, code: int = 0) -> void:
	_fake.running = false
	_fake.code = code
	s.runner._process(0.0)


func _running_screen(instrument: String = "auto") -> ChartSongScreen:
	var s: ChartSongScreen = await _options_screen()
	s.select_instrument(instrument)
	s.start_button.pressed.emit()
	return s


func _job_path() -> String:
	var args: PackedStringArray = _fake.starts[-1][1]
	return args[args.size() - 1]


func _make_work(name: String, t: float, finished: bool = true) -> String:
	var dir := AutochartPaths.work_root().path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	if finished:
		SongFixture.write_text(dir.path_join("analyze_done.json"), JSON.stringify({"t": t}))
	SongFixture.write_text(dir.path_join("last_used.json"), JSON.stringify({"t": t}))
	return dir


func _done(stem: String = "bass", mode: String = "single",
		ranking: Array = ["other", "bass", "vocals", "drums"]) -> Dictionary:
	return {"ev": "done", "folder": ProjectSettings.globalize_path(D + "/songs/song").replace("/", "\\"),
		"slug": "song", "stem": stem, "mode": mode, "expert_nps": 2.37, "reused": false,
		"ranking": ranking, "log": ""}


func test_start_writes_job_and_runs_with_exact_args() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	assert_str(s.state()).is_equal("running")
	assert_str(s.heading_text()).is_equal("CHARTING SONG")
	assert_int(_fake.starts.size()).is_equal(1)
	assert_str(_fake.starts[0][0]).is_equal(AutochartPaths.python_exe())
	var job_path := _job_path()
	assert_str(job_path.get_file()).is_equal("job.json")
	assert_str(job_path.get_base_dir().get_base_dir()).is_equal(AutochartPaths.work_root().path_join("jobs"))
	assert_array(Array(_fake.starts[0][1])).is_equal(
		Array(AutochartJob.build_args(AutochartPaths.app_dir(), "job", job_path)))
	var written = JSON.parse_string(FileAccess.get_file_as_string(job_path))
	assert_str(written["stem"]).is_equal("bass")
	assert_str(written["mode"]).is_equal("single")
	assert_str(AutochartJob.validate(written)).is_equal("")
	assert_int(_music_stops[0]).is_equal(1)
	assert_object(_focus()).is_same(s.cancel_job_button)
	assert_str(s.body_text()).contains("This can take a few minutes. You can leave the game open.")


func test_stage_rows_follow_stage_events_and_progress_fills_bar() -> void:
	var s: ChartSongScreen = await _running_screen()
	var labels: Array = []
	for l: Label in s.stage_labels:
		labels.append(l.text)
	assert_array(labels).is_equal(["Separating instruments", "Finding the beat", "Finding notes",
		"Reading pitch", "Writing chart"])
	assert_array(s.stage_row_states()).is_equal(["current", "pending", "pending", "pending", "pending"])
	_push(s, [{"ev": "start", "pid": 1}, {"ev": "stage", "k": 1, "n": 8, "name": "decode"},
		{"ev": "stage", "k": 2, "n": 8, "name": "separate"}, {"ev": "stage", "k": 3, "n": 8, "name": "beats"},
		{"ev": "progress", "frac": 0.5}])
	assert_array(s.stage_row_states()).is_equal(["done", "current", "pending", "pending", "pending"])
	assert_float(s.job_bar.value).is_equal_approx(50.0, 0.001)
	_push(s, [{"ev": "stage", "k": 7, "n": 8, "name": "chart"}])
	assert_array(s.stage_row_states()).is_equal(["done", "done", "done", "done", "current"])


func test_warn_event_shows_in_footer() -> void:
	var s: ChartSongScreen = await _running_screen()
	_push(s, [{"ev": "warn", "msg": "Reusing separated instruments"}])
	assert_str(s.footer_text()).is_equal("Reusing separated instruments")
	assert_bool(s.footer_is_error()).is_false()


func test_elapsed_time_reads_the_clock() -> void:
	var s: ChartSongScreen = await _running_screen()
	assert_str(s.elapsed_label.text).is_equal("0:00")
	_now[0] += 75.4
	s.elapsed_timer.timeout.emit()
	assert_str(s.elapsed_label.text).is_equal("1:15")


func test_cancel_confirmed_kills_child_and_removes_unfinished_work_dir() -> void:
	var s: ChartSongScreen = await _running_screen()
	var work := _make_work("w_0123456789abcdef", 1.0, false)
	_push(s, [{"ev": "work", "dir": work.replace("/", "\\")}])
	s.cancel_job_button.pressed.emit()
	assert_object(s.dialog).is_not_null()
	assert_str(s.dialog.title_label.text).is_equal("STOP CHARTING?")
	assert_str(s.dialog.body_label.text).is_equal("The chart for song will not be saved.")
	s.dialog.confirmed.emit()
	assert_int(_fake.kill_count).is_equal(1)
	# The process is not gone yet: nothing is deleted before the runner reports it.
	assert_bool(DirAccess.dir_exists_absolute(work)).is_true()
	_exit(s, 1)
	assert_bool(DirAccess.dir_exists_absolute(work)).is_false()
	assert_str(s.state()).is_equal("options")
	assert_str(s.footer_text()).is_equal("Charting stopped.")
	assert_str(s.name_edit.text).is_equal("song")


func test_ui_cancel_while_running_asks_and_keep_continues() -> void:
	var s: ChartSongScreen = await _running_screen()
	await _cancel()
	assert_object(s.dialog).is_not_null()
	assert_str(s.dialog.title_label.text).is_equal("STOP CHARTING?")
	s.dialog.cancelled.emit()
	assert_int(_fake.kill_count).is_equal(0)
	assert_str(s.state()).is_equal("running")
	assert_array(_calls).is_empty()


func test_leaving_the_screen_while_running_kills_the_child() -> void:
	var s: ChartSongScreen = await _running_screen()
	remove_child(s)
	assert_int(_fake.kill_count).is_greater_equal(1)
	add_child(s)


func test_close_request_while_running_kills_the_child() -> void:
	var s: ChartSongScreen = await _running_screen()
	s.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_fake.kill_count).is_greater_equal(1)


# ---- plan 09: result -----------------------------------------------------------------------


func test_finished_shows_result_and_prunes_cache() -> void:
	var now := Time.get_unix_time_from_system()
	var olds: Array = []
	for i in 4:
		olds.append(_make_work("w_old%d" % i, now - 1000.0 + i))
	var s: ChartSongScreen = await _running_screen("bass")
	var cur := _make_work("w_current", now)
	_push(s, [{"ev": "work", "dir": cur}, _done()])
	_exit(s, 0)
	assert_str(s.state()).is_equal("result")
	assert_str(s.heading_text()).is_equal("READY")
	assert_str(s.body_text()).contains("song - Unknown")
	assert_str(s.body_text()).contains("Instrument: Bass   Expert: 2.4 notes/s")
	assert_object(_focus()).is_same(s.play_now_button)
	# keep 3: the current dir plus the two newest older ones
	assert_bool(DirAccess.dir_exists_absolute(cur)).is_true()
	assert_bool(DirAccess.dir_exists_absolute(olds[3])).is_true()
	assert_bool(DirAccess.dir_exists_absolute(olds[2])).is_true()
	assert_bool(DirAccess.dir_exists_absolute(olds[1])).is_false()
	assert_bool(DirAccess.dir_exists_absolute(olds[0])).is_false()


func test_result_instrument_names() -> void:
	var s: ChartSongScreen = await _running_screen("lanes")
	_push(s, [_done("lanes", "lanes")])
	_exit(s, 0)
	assert_str(s.body_text()).contains("Instrument: Instrument Lanes   Expert: 2.4 notes/s")
	s.chart_another_button.pressed.emit()
	s.select_instrument("auto")
	s.start_button.pressed.emit()
	_push(s, [_done("other", "auto")])
	_exit(s, 0)
	assert_str(s.body_text()).contains("Instrument: Melody   Expert: 2.4 notes/s")


func test_play_now_rescans_then_selects_new_song_in_song_select() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	var done := _done()
	_push(s, [done])
	_exit(s, 0)
	s.play_now_button.pressed.emit()
	assert_int(_lib.rescans).is_equal(1)
	assert_str(s.footer_text()).is_equal("Adding to your library...")
	assert_array(_calls).is_empty()
	_lib.scan_finished.emit(5, 0)
	assert_str(_lib.last_song_id).is_equal(SongScanner.norm(String(done["folder"])))
	assert_array(_calls).is_equal([ChartSongScreen.SONG_SELECT_SCENE])
	assert_str(ChartSongScreen.SONG_SELECT_SCENE).is_equal("res://scenes/song_select.tscn")


## WR-05: the song id comes from the library's own Songs folder plus the reported slug, so a
## done folder with other casing (or another form of the same path) still selects the new song.
func test_play_now_uses_songs_dir_and_slug_not_the_child_path() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	var done := _done()
	done["folder"] = String(done["folder"]).to_upper()
	done["slug"] = "song_2"
	_push(s, [done])
	_exit(s, 0)
	s.play_now_button.pressed.emit()
	_lib.scan_finished.emit(5, 0)
	assert_str(_lib.last_song_id).is_equal(SongScanner.norm(_lib.dir.path_join("song_2")))
	assert_array(_calls).is_equal([ChartSongScreen.SONG_SELECT_SCENE])


func test_play_now_with_a_bad_slug_selects_nothing() -> void:
	assert_bool(ChartSongScreen.is_valid_slug("song")).is_true()
	assert_bool(ChartSongScreen.is_valid_slug("song_99")).is_true()
	for bad in ["", "../x", "Song", "a/b", "x".repeat(60)]:
		assert_bool(ChartSongScreen.is_valid_slug(bad)).override_failure_message(bad).is_false()
	var s: ChartSongScreen = await _running_screen("bass")
	var done := _done()
	done["slug"] = "../evil"
	_push(s, [done])
	_exit(s, 0)
	s.play_now_button.pressed.emit()
	_lib.scan_finished.emit(5, 0)
	assert_str(_lib.last_song_id).is_equal("")
	assert_array(_calls).is_equal([ChartSongScreen.SONG_SELECT_SCENE])


## WR-05: the cancelled run's work dir is found even when the child reports it in other casing.
func test_cancel_removes_unfinished_work_dir_reported_in_other_case() -> void:
	if OS.get_name() != "Windows":
		return
	var s: ChartSongScreen = await _running_screen()
	var work := _make_work("w_0123456789abcdef", 1.0, false)
	# Python resolves the parent folders (real casing); the w_<sha> name is its own lowercase.
	var reported := work.get_base_dir().to_upper().path_join(work.get_file())
	_push(s, [{"ev": "work", "dir": reported.replace("/", "\\")}])
	s.cancel_job_button.pressed.emit()
	s.dialog.confirmed.emit()
	_exit(s, 1)
	assert_bool(DirAccess.dir_exists_absolute(work)).is_false()


func test_play_now_waits_for_a_running_scan_first() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	_push(s, [_done()])
	_exit(s, 0)
	_lib.scanning = true
	s.play_now_button.pressed.emit()
	assert_int(_lib.rescans).is_equal(0)
	_lib.scanning = false
	_lib.scan_finished.emit(4, 0)  # the old scan, without the new song
	assert_int(_lib.rescans).is_equal(1)
	assert_array(_calls).is_empty()
	_lib.scan_finished.emit(5, 0)
	assert_array(_calls).is_equal([ChartSongScreen.SONG_SELECT_SCENE])


func test_chart_another_instrument_preselects_next_ranked() -> void:
	var s: ChartSongScreen = await _running_screen("auto")
	_push(s, [_done("other", "auto")])
	_exit(s, 0)
	s.chart_another_button.pressed.emit()
	assert_str(s.state()).is_equal("options")
	assert_str(s.name_edit.text).is_equal("song")
	assert_str(s.file_label.text).is_equal("File: song.flac")
	assert_str(s.selected_instrument()).is_equal("bass")
	assert_bool((s.instrument_buttons["bass"] as Button).button_pressed).is_true()
	s.start_button.pressed.emit()
	assert_str(_jobs[-1]["src"]).is_equal("C:/x/song.flac")
	assert_str(_jobs[-1]["stem"]).is_equal("bass")


func test_chart_another_after_single_stem_without_ranking_offers_lanes() -> void:
	var s: ChartSongScreen = await _running_screen("drums")
	_push(s, [_done("drums", "single", [])])
	_exit(s, 0)
	s.chart_another_button.pressed.emit()
	assert_str(s.selected_instrument()).is_equal("lanes")


func test_back_to_menu_from_result() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	_push(s, [_done()])
	_exit(s, 0)
	s.result_back_button.pressed.emit()
	assert_array(_calls).is_equal([ChartSongScreen.MENU_SCENE])


# ---- plan 09: error ------------------------------------------------------------------------


func test_failure_shows_reason_and_details_opens_log() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	var log_path := _job_path().get_base_dir().path_join("log.txt")
	_push(s, [{"ev": "error", "code": "too_long", "stage": "decode", "msg": "x",
		"log": log_path.replace("/", "\\")}])
	_exit(s, 2)
	assert_str(s.state()).is_equal("error")
	assert_str(s.heading_text()).is_equal("CHARTING FAILED")
	assert_str(s.body_text()).contains("Songs longer than 10 minutes are not supported.")
	assert_str(s.body_text()).contains("Details: log.txt in the autocharter folder")
	assert_object(_focus()).is_same(s.retry_button)
	s.details_button.pressed.emit()
	assert_int(_opened.size()).is_equal(1)
	assert_str(String(_opened[0]).replace("\\", "/")).is_equal(log_path)
	s.retry_button.pressed.emit()
	assert_str(s.state()).is_equal("options")
	assert_str(s.selected_instrument()).is_equal("bass")
	assert_str(s.name_edit.text).is_equal("song")


func test_crash_without_log_falls_back_to_job_dir_log() -> void:
	var s: ChartSongScreen = await _running_screen()
	var job_dir := _job_path().get_base_dir()
	_exit(s, 7)
	assert_str(s.state()).is_equal("error")
	assert_str(s.body_text()).contains(AutochartJob.error_text("crash"))
	s.details_button.pressed.emit()
	assert_str(_opened[0]).is_equal(job_dir.path_join("log.txt"))


func test_log_path_outside_the_pack_root_is_not_opened() -> void:
	var s: ChartSongScreen = await _running_screen()
	var job_dir := _job_path().get_base_dir()
	_push(s, [{"ev": "error", "code": "decode", "msg": "x", "log": "C:\\Windows\\System32\\cmd.exe"}])
	_exit(s, 2)
	s.details_button.pressed.emit()
	assert_str(_opened[0]).is_equal(job_dir.path_join("log.txt"))


func test_back_from_error_goes_to_pick() -> void:
	var s: ChartSongScreen = await _running_screen()
	_exit(s, 7)
	s.error_back_button.pressed.emit()
	assert_str(s.state()).is_equal("pick")


# ---- plan 09: selftest gate ----------------------------------------------------------------


func test_selftest_runs_first_and_passes_to_pick() -> void:
	var s := _screen(_spec([_part("a.zip")]), true, false)
	await get_tree().process_frame
	assert_str(s.state()).is_equal("installing")
	assert_str(s.progress_label.text).is_equal("Testing the autocharter...")
	assert_int(_fake.starts.size()).is_equal(1)
	assert_array(Array(_fake.starts[0][1])).is_equal(
		Array(AutochartJob.build_args(AutochartPaths.app_dir(), "selftest")))
	_push(s, [{"ev": "selftest", "ok": true, "seconds": 6.3}])
	_exit(s, 0)
	assert_bool(s.installer.selftest_ok()).is_true()
	assert_str(s.state()).is_equal("pick")


func test_selftest_failure_shows_error_with_remove_pack() -> void:
	var s := _screen(_spec([_part("a.zip")]), true, false)
	await get_tree().process_frame
	_push(s, [{"ev": "error", "code": "selftest", "stage": "selftest", "msg": "x", "log": ""}])
	_exit(s, 2)
	assert_str(s.state()).is_equal("error")
	assert_str(s.body_text()).contains(AutochartJob.error_text("selftest"))
	assert_bool(s.installer.selftest_ok()).is_false()
	assert_bool(s.error_remove_button.visible).is_true()
	_assert_reachable(s)
	s.error_remove_button.pressed.emit()
	assert_str(s.dialog.title_label.text).is_equal("REMOVE THE AUTOCHARTER?")
	s.dialog.confirmed.emit()
	assert_str(s.state()).is_equal("pack_missing")


func test_installed_signal_runs_selftest_when_not_passed() -> void:
	var spec := _spec([_part("a.zip")])
	var s := _screen(spec)
	await get_tree().process_frame
	_fake_install(spec, false)
	s.installer.installed.emit()
	assert_str(s.state()).is_equal("installing")
	assert_str(s.progress_label.text).is_equal("Testing the autocharter...")
	assert_int(_fake.starts.size()).is_equal(1)


func test_job_error_has_no_remove_pack_button() -> void:
	var s: ChartSongScreen = await _running_screen()
	_exit(s, 7)
	assert_bool(s.error_remove_button.visible).is_false()


# ---- plan 09: cache / pack buttons ---------------------------------------------------------


func test_clear_cache_confirmed_clears_and_reports_megabytes() -> void:
	var s := _screen(_spec([_part("a.zip")]), true)
	await get_tree().process_frame
	var w := _make_work("w_cache", 1.0)
	var data := PackedByteArray()
	data.resize(3 * 1000 * 1000)
	SongFixture.write_bytes(w.path_join("stems/other.wav"), data)
	s.clear_cache_button.pressed.emit()
	assert_str(s.dialog.title_label.text).is_equal("CLEAR CHART CACHE?")
	assert_str(s.dialog.body_label.text).is_equal(
		"Separated instruments of recent songs are deleted. Your charted songs stay.")
	s.dialog.confirmed.emit()
	assert_bool(DirAccess.dir_exists_absolute(w)).is_false()
	assert_str(s.footer_text()).is_equal("Chart cache cleared (3 MB freed).")


func test_cache_and_pack_buttons_disabled_while_a_job_runs() -> void:
	var s: ChartSongScreen = await _running_screen()
	s.show_state("pick")
	assert_bool(s.clear_cache_button.disabled).is_true()
	assert_bool(s.remove_pack_button.disabled).is_true()
	_fake.running = false
	s.runner._process(0.0)
	s.show_state("pick")
	assert_bool(s.clear_cache_button.disabled).is_false()
	assert_bool(s.remove_pack_button.disabled).is_false()


func test_new_states_are_focus_reachable() -> void:
	var s: ChartSongScreen = await _running_screen("bass")
	await get_tree().process_frame
	_assert_reachable(s)  # running
	_push(s, [_done()])
	_exit(s, 0)
	await get_tree().process_frame
	_assert_reachable(s)  # result
	s.show_state("error")
	await get_tree().process_frame
	_assert_reachable(s)
