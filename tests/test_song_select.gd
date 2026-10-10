extends GdUnitTestSuite
## SongSelect: list, selection, filter rules, dive wiring, preview timing, empty states.
## Uses its own SongLibrary instance with injected entries (no scanning, no real user://songs).

const D := "user://test_song_select"
const SCORES := D + "/scores.cfg"

var _old_reduce: bool
var _old_scores: String
var _old_music: float
var _old_low: bool


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))
	_old_reduce = Settings.reduce_motion
	_old_music = Settings.volume_music
	_old_low = Settings.low_effects
	Settings.reduce_motion = true
	Settings.volume_music = 0.8
	_old_scores = ScoreStore.default_path
	ScoreStore.default_path = SCORES
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false


func after_test() -> void:
	Settings.reduce_motion = _old_reduce
	Settings.volume_music = _old_music
	Settings.low_effects = _old_low
	ScoreStore.default_path = _old_scores
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	for p in [SCORES, SCORES + ".tmp", SCORES + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _entry(id: String, title: String, diffs: Array = ["easy", "medium", "hard", "expert"],
		status: String = "ok", source: String = "songs") -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.artist = "Artist"
	e.status = status
	e.source = source
	e.length_sec = 100.0
	e.bpm_min = 120.0
	e.bpm_max = 120.0
	if status == "broken":
		e.error = SongEntry.ERR_OPUS
		e.fix_hint = SongEntry.hint_for(e.error)
	if status == "needs_chart":
		e.error = SongEntry.ERR_NEEDS_CHART
	if status == "ok":
		for d in diffs:
			e.difficulties.append({"name": d, "note_count": 100, "fingerprint": "fp_%s_%s" % [id, d]})
	return e


func _songs(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(_entry("s%02d" % i, "Song %02d" % i))
	return out


func _lib(entries: Array) -> Node:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = D + "/songs"
	lib.cache_path = D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	auto_free(lib)
	lib.entries.assign(entries)
	return lib


func _screen(lib: Node) -> SongSelect:
	var s: SongSelect = (load("res://scenes/song_select.tscn") as PackedScene).instantiate()
	s.library = lib
	add_child(s)
	auto_free(s)
	return s


func _nav(s: SongSelect) -> Array:
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	return calls


func test_scene_loads_with_contract_node_names() -> void:
	var s := _screen(_lib(_songs(3)))
	for n in ["SongList", "DetailPanel", "FilterField", "SortChip", "ScanStatus", "FooterHints", "CreditsLine"]:
		assert_object(s.get_node_or_null(n)).is_not_null()
		assert_int((s.get_node(n) as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_str(s.name).is_equal("SongSelect")


func test_nine_rows_visible_for_long_list() -> void:
	var s := _screen(_lib(_songs(30)))
	var st := s.debug_state()
	assert_int((st["rows"] as Array).size()).is_equal(9)
	assert_int(st["view_size"]).is_equal(30)


func test_initial_selection_is_first_playable_not_calibration() -> void:
	var cal := SongLibrary.calibration_entry()
	var s := _screen(_lib([cal] + _songs(3)))
	assert_str(s.debug_state()["selected"]).is_equal("s00")


func test_initial_selection_uses_last_song_and_difficulty() -> void:
	var lib := _lib(_songs(30))
	lib.last_song_id = "s20"
	lib.last_difficulty = "hard"
	var s := _screen(lib)
	var st := s.debug_state()
	assert_str(st["selected"]).is_equal("s20")
	assert_str(st["difficulty"]).is_equal("hard")
	assert_bool((st["rows"] as Array).has("s20")).is_true()


func test_selection_keeps_screen_row_when_scan_inserts_rows_above() -> void:
	var lib := _lib(_songs(30))
	var s := _screen(lib)
	for i in 12:
		s.press_key_for_test(KEY_DOWN)
	var before := s.debug_state()
	var row_before: int = (before["rows"] as Array).find(before["selected"])
	var batch: Array = []
	for i in 5:
		batch.append(_entry("a%02d" % i, "Aaa %02d" % i))
	lib.entries.append_array(batch)
	lib.entries_added.emit(batch)
	var after := s.debug_state()
	assert_str(after["selected"]).is_equal(before["selected"])
	assert_int((after["rows"] as Array).find(after["selected"])).is_equal(row_before)


## 02-06 windowed finding: a full rescan (scan_started, batches, scan_finished) must not clear the
## list, so the selection stays on the same screen row when new songs sort above it.
func test_full_rescan_keeps_selection_row_and_drops_missing_entries() -> void:
	var lib := _lib(_songs(30))
	var s := _screen(lib)
	for i in 12:
		s.press_key_for_test(KEY_DOWN)
	var before := s.debug_state()
	var row_before: int = (before["rows"] as Array).find(before["selected"])
	lib.scan_started.emit()
	assert_str(s.debug_state()["selected"]).is_equal(before["selected"])
	var fresh := _songs(30)
	fresh.remove_at(29)  # s29 was deleted from disk
	# First batch does not contain the selected song (bundled songs arrive first in the real scan).
	lib.entries_added.emit(fresh.slice(20))
	var added: Array = []
	for i in 3:
		added.append(_entry("a%02d" % i, "Aaa %02d" % i))
	lib.entries_added.emit(added + fresh.slice(0, 20))
	lib.scan_finished.emit(32, 0)
	var after := s.debug_state()
	assert_str(after["selected"]).is_equal(before["selected"])
	assert_int((after["rows"] as Array).find(after["selected"])).is_equal(row_before)
	assert_int(int(after["offset"])).is_equal(int(before["offset"]) + 3)
	assert_int(int(after["view_size"])).is_equal(32)
	assert_bool(s._view_ids().has("s29")).is_false()


## 02-06 windowed finding: the filter field counted the Calibration Track ("36 songs") while the
## footer status did not ("35 songs").
func test_filter_count_excludes_calibration_track() -> void:
	var cal := SongLibrary.calibration_entry()
	var s := _screen(_lib([cal] + _songs(3)))
	assert_str(s.filter_count_text()).is_equal("3 songs")
	s.set_filter_for_test("song 0")
	assert_str(s.filter_count_text()).is_equal("3 / 3")
	s.set_filter_for_test("calibration")
	assert_str(s.filter_count_text()).is_equal("0 / 3")


## 02-06 windowed finding: the empty-state path broke inside a folder name.
func test_wrap_path_breaks_after_separators() -> void:
	var s := _screen(_lib(_songs(1)))
	var path := "C:/Users/someone/AppData/Roaming/Godot/app_userdata/UNDERTOW/songs"
	var lines: Array = s.wrap_path(path, Palette.SIZE_BODY, 800.0)
	assert_str("".join(lines)).is_equal(path)
	assert_int(lines.size()).is_greater(1)
	for i in lines.size() - 1:
		assert_bool(String(lines[i]).ends_with("/")).is_true()
	for ln in lines:
		assert_float(s._w(ln, Palette.SIZE_BODY)).is_less_equal(800.0)


func test_digits_navigate_only_while_filter_empty() -> void:
	var s := _screen(_lib(_songs(30)))
	s.press_key_for_test(KEY_2, 50)
	assert_str(s.debug_state()["selected"]).is_equal("s01")
	s.press_key_for_test(KEY_4, 52)
	assert_str(s.debug_state()["selected"]).is_equal("s10")
	s.press_key_for_test(KEY_3, 51)
	assert_str(s.debug_state()["selected"]).is_equal("s01")
	s.press_key_for_test(KEY_1, 49)
	assert_str(s.debug_state()["selected"]).is_equal("s00")
	# Typing a letter starts the filter; digits then type instead of navigate.
	s.type_for_test("s")
	s.press_key_for_test(KEY_2, 50)
	assert_str(s.debug_state()["filter"]).is_equal("s2")
	assert_str(s.debug_state()["empty_state"]).is_equal("no_matches")


func test_slash_enters_typing_mode_so_digits_type() -> void:
	var s := _screen(_lib(_songs(5)))
	s.press_key_for_test(KEY_SLASH, 47)
	assert_str(s.debug_state()["filter"]).is_equal("")
	assert_bool(s.debug_state()["typing"]).is_true()
	s.press_key_for_test(KEY_2, 50)
	assert_str(s.debug_state()["filter"]).is_equal("2")


func test_escape_clears_filter_first_then_goes_back() -> void:
	var s := _screen(_lib(_songs(5)))
	var calls := _nav(s)
	s.type_for_test("song")
	assert_str(s.debug_state()["filter"]).is_equal("song")
	s.press_key_for_test(KEY_ESCAPE)
	assert_str(s.debug_state()["filter"]).is_equal("")
	assert_int(calls.size()).is_equal(0)
	s.press_key_for_test(KEY_ESCAPE)
	assert_array(calls).is_equal([SongSelect.MENU_SCENE])


func test_filter_capped_at_40_chars() -> void:
	var s := _screen(_lib(_songs(5)))
	s.type_for_test("x".repeat(60))
	assert_int((s.debug_state()["filter"] as String).length()).is_equal(40)


func test_no_matches_and_empty_states() -> void:
	var s := _screen(_lib(_songs(5)))
	s.set_filter_for_test("zzzz")
	assert_str(s.debug_state()["empty_state"]).is_equal("no_matches")
	assert_bool(s.debug_state()["start_enabled"]).is_false()
	s.press_key_for_test(KEY_ESCAPE)
	assert_str(s.debug_state()["empty_state"]).is_equal("")
	var lib := _lib([])
	var s2 := _screen(lib)
	assert_str(s2.debug_state()["empty_state"]).is_equal("no_songs")


func test_enter_ignored_on_broken_and_needs_chart() -> void:
	var list := _songs(2)
	list.append(_entry("nc", "Needs one", [], "needs_chart"))
	list.append(_entry("bad", "Broken one", [], "broken"))
	var s := _screen(_lib(list))
	var calls := _nav(s)
	for id in ["bad", "nc"]:
		s.select_for_test(id)
		assert_bool(s.debug_state()["start_enabled"]).is_false()
		s.press_key_for_test(KEY_ENTER)
	assert_int(calls.size()).is_equal(0)
	assert_object(Gameplay.pending_chart).is_null()
	assert_bool(s.debug_state()["diving"]).is_false()


func test_broken_and_needs_chart_sort_last_and_are_selectable() -> void:
	var list := [_entry("bad", "Aaa broken", [], "broken"), _entry("nc", "Aaa needs", [], "needs_chart")]
	list.append_array(_songs(2))
	var s := _screen(_lib(list))
	assert_array(s.debug_state()["rows"]).is_equal(["s00", "s01", "nc", "bad"])
	s.press_key_for_test(KEY_END)
	assert_str(s.debug_state()["selected"]).is_equal("bad")


func test_difficulty_snaps_when_song_changes_and_remembers_wish() -> void:
	var list := [_entry("a", "Aaa", ["easy", "expert"]), _entry("b", "Bbb", ["easy", "medium"]),
		_entry("c", "Ccc", ["easy", "medium", "hard", "expert"])]
	var s := _screen(_lib(list))
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")
	s.press_key_for_test(KEY_DOWN)
	assert_str(s.debug_state()["difficulty"]).is_equal("medium")
	s.press_key_for_test(KEY_DOWN)
	# The wish was expert; song c has it.
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")
	s.press_key_for_test(KEY_LEFT)
	assert_str(s.debug_state()["difficulty"]).is_equal("hard")
	s.press_key_for_test(KEY_RIGHT)
	s.press_key_for_test(KEY_RIGHT)
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")


func test_difficulty_snap_tie_prefers_lower() -> void:
	var list := [_entry("a", "Aaa", ["easy", "hard"])]
	var lib := _lib(list)
	lib.last_difficulty = "medium"
	var s := _screen(lib)
	assert_str(s.debug_state()["difficulty"]).is_equal("easy")


func test_dive_sets_pending_flags_and_navigates_once() -> void:
	var cal := SongLibrary.calibration_entry()
	var lib := _lib([cal])
	SongSelect.run_practice = true
	SongSelect.run_autoplay = true
	var s := _screen(lib)
	var calls := _nav(s)
	assert_str(s.debug_state()["selected"]).is_equal(cal.id)
	assert_bool(s.debug_state()["start_enabled"]).is_true()
	s.press_key_for_test(KEY_ENTER)
	s.press_key_for_test(KEY_ENTER)
	assert_array(calls).is_equal([SongSelect.GAMEPLAY_SCENE])
	assert_object(Gameplay.pending_chart).is_not_null()
	assert_str(Gameplay.pending_chart.id).is_equal(TestCharts.HAND_CHART_ID)
	assert_bool(Gameplay.pending_practice).is_true()
	assert_bool(Gameplay.pending_autoplay).is_true()
	assert_str(lib.last_song_id).is_equal(cal.id)
	assert_str(lib.last_difficulty).is_equal("expert")
	Gameplay.pending_chart = null


func test_dive_without_flags_is_normal_run() -> void:
	var cal := SongLibrary.calibration_entry()
	var s := _screen(_lib([cal]))
	_nav(s)
	s.press_key_for_test(KEY_ENTER)
	assert_bool(Gameplay.pending_practice).is_false()
	assert_bool(Gameplay.pending_autoplay).is_false()
	Gameplay.pending_chart = null


func test_run_flags_reset_when_screen_exits() -> void:
	SongSelect.run_practice = true
	SongSelect.run_autoplay = true
	var s := _screen(_lib(_songs(2)))
	s.free()
	assert_bool(SongSelect.run_practice).is_false()
	assert_bool(SongSelect.run_autoplay).is_false()


func test_failed_build_shows_message_and_stays() -> void:
	# An ok entry whose files do not exist: build_chart returns null.
	var e := _entry("ghost", "Ghost song")
	e.chart_path = D + "/none/notes.chart"
	var s := _screen(_lib([e, _entry("zz", "Zzz other")]))
	var calls := _nav(s)
	s.press_key_for_test(KEY_ENTER)
	assert_int(calls.size()).is_equal(0)
	assert_str(s.debug_state()["message"]).is_equal("This song's audio could not be loaded. Choose another song.")
	assert_bool(s.debug_state()["diving"]).is_false()
	s.press_key_for_test(KEY_DOWN)
	assert_str(s.debug_state()["message"]).is_equal("")


func test_preview_waits_for_gate_then_plays_and_stops_on_dive() -> void:
	var cal := SongLibrary.calibration_entry()
	var lib := _lib([cal])
	var s := _screen(lib)
	_nav(s)
	var stream := AudioSynth.make_click_track(120.0, 8.0)
	s.preview_loader = func(_e: SongEntry) -> AudioStream: return stream
	# Force a fresh highlight change so the debounce starts now.
	s.set_filter_for_test("a")
	s.set_filter_for_test("")
	assert_str(s.debug_state()["preview_state"]).is_equal("pending")
	s.tick_preview(Time.get_ticks_msec() + 100)
	assert_str(s.debug_state()["preview_state"]).is_equal("pending")
	s.tick_preview(Time.get_ticks_msec() + 600)
	var st: String = s.debug_state()["preview_state"]
	assert_bool(st == "loading" or st == "playing").is_true()
	var t0 := Time.get_ticks_msec()
	while s.debug_state()["preview_state"] != "playing" and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_str(s.debug_state()["preview_state"]).is_equal("playing")
	s.press_key_for_test(KEY_ENTER)
	assert_str(s.debug_state()["preview_state"]).is_equal("none")
	Gameplay.pending_chart = null


## 02-06 windowed finding: unreaped WorkerThreadPool preview tasks crashed the game on quit.
func test_preview_load_tasks_are_reaped() -> void:
	var cal := SongLibrary.calibration_entry()
	var s := _screen(_lib([cal]))
	_nav(s)
	var stream := AudioSynth.make_click_track(120.0, 4.0)
	s.preview_loader = func(_e: SongEntry) -> AudioStream: return stream
	s.set_filter_for_test("a")
	s.set_filter_for_test("")
	s.tick_preview(Time.get_ticks_msec() + 600)
	assert_int(s._preview_tasks.size()).is_equal(1)
	var t0 := Time.get_ticks_msec()
	while not s._preview_tasks.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_int(s._preview_tasks.size()).is_equal(0)
	# A load still running when the screen leaves the tree is waited for in _exit_tree.
	var slow := func(_e: SongEntry) -> AudioStream:
		OS.delay_msec(200)
		return stream
	s.preview_loader = slow
	s._stream_cache.clear()
	s.set_filter_for_test("a")
	s.set_filter_for_test("")
	s.tick_preview(Time.get_ticks_msec() + 600)
	assert_int(s._preview_tasks.size()).is_equal(1)
	remove_child(s)
	assert_int(s._preview_tasks.size()).is_equal(0)


func test_preview_not_started_for_broken_song() -> void:
	var list := [_entry("bad", "Broken one", [], "broken")]
	var s := _screen(_lib(list))
	s.preview_loader = func(_e: SongEntry) -> AudioStream: return AudioSynth.make_click_track(120.0, 4.0)
	s.select_for_test("bad")
	s.set_filter_for_test("b")
	s.set_filter_for_test("")
	s.tick_preview(Time.get_ticks_msec() + 1000)
	assert_str(s.debug_state()["preview_state"]).is_equal("none")


func test_open_folder_failure_message_and_success() -> void:
	var lib := _lib(_songs(2))
	var s := _screen(lib)
	lib.shell_opener = func(_p: String) -> bool: return false
	s.open_folder_for_test()
	assert_str(s.debug_state()["message"]).starts_with("Could not open the Songs folder. It is at ")
	assert_str(s.debug_state()["message"]).contains(lib.songs_dir())
	var s2 := _screen(lib)
	lib.shell_opener = func(_p: String) -> bool: return true
	s2.open_folder_for_test()
	assert_str(s2.debug_state()["message"]).is_equal("")


func test_open_folder_works_before_any_scan() -> void:
	var lib := _lib([])
	var s := _screen(lib)
	var seen: Array = []
	lib.shell_opener = func(p: String) -> bool:
		seen.append(p)
		return true
	s.press_key_for_test(KEY_F6)
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0]).is_equal(lib.songs_dir())


func test_onboarding_row_is_skipped_by_navigation() -> void:
	var cal := SongLibrary.calibration_entry()
	var bundled := _entry("b1", "Bundled", ["easy"], "ok", "bundled")
	var s := _screen(_lib([bundled, cal]))
	var st := s.debug_state()
	assert_bool(st["onboarding"]).is_true()
	assert_array(st["rows"]).is_equal(["b1", cal.id, ""])
	s.press_key_for_test(KEY_DOWN)
	assert_str(s.debug_state()["selected"]).is_equal(cal.id)
	s.press_key_for_test(KEY_DOWN)
	assert_str(s.debug_state()["selected"]).is_equal(cal.id)


func test_sort_key_cycles_and_orders_by_artist() -> void:
	var a := _entry("a", "Aaa")
	a.artist = "Zed"
	var b := _entry("b", "Bbb")
	b.artist = "Abe"
	var s := _screen(_lib([a, b]))
	assert_array(s.debug_state()["rows"]).is_equal(["a", "b"])
	s.press_key_for_test(KEY_F2)
	assert_int(s.debug_state()["sort"]).is_equal(SongListModel.SortMode.ARTIST)
	assert_array(s.debug_state()["rows"]).is_equal(["b", "a"])


func test_best_prefetch_feeds_best_sort() -> void:
	var store := ScoreStore.new(SCORES)
	store.submit("fp_b_expert", 900.0, 90.0, 10, true, "2026-10-08")
	store.save()
	var s := _screen(_lib([_entry("a", "Aaa"), _entry("b", "Bbb")]))
	s.set_sort_for_test(SongListModel.SortMode.BEST)
	assert_array(s.debug_state()["rows"]).is_equal(["b", "a"])


func test_scan_status_text_follows_library_state() -> void:
	var lib := _lib(_songs(3))
	var s := _screen(lib)
	lib.progress.emit(2, 10, "x")
	lib.scan_finished.emit(3, 1)
	assert_str(s.debug_state()["scan_text"]).is_equal("3 songs  ·  1 unplayable")


## UI-SPEC 4.11: notes per second over the chart length -> 1..5 pips.
func test_intensity_thresholds() -> void:
	var cases := [[100, 100.0, 1], [199, 100.0, 1], [200, 100.0, 2], [349, 100.0, 2], [350, 100.0, 3],
		[499, 100.0, 3], [500, 100.0, 4], [699, 100.0, 4], [700, 100.0, 5], [5000, 100.0, 5],
		[0, 100.0, 1], [1204, 0.0, 1], [1204, -1.0, 1]]
	for c in cases:
		assert_int(SongSelect.intensity(int(c[0]), float(c[1]))).override_failure_message(str(c)).is_equal(int(c[2]))


func test_tiles_are_176_by_96_at_y_468() -> void:
	var s := _screen(_lib(_songs(1)))
	assert_float(SongSelect.TILE_Y).is_equal(468.0)
	assert_float(SongSelect.TILE_H).is_equal(96.0)
	for i in 4:
		assert_object(s.tile_rect(i)).is_equal(Rect2(SongSelect.TILE_X[i], 468.0, 176.0, 96.0))
	assert_float(s.tile_rect(3).end.x).is_equal(1832.0)
	assert_float(s.tile_rect(0).end.y).is_equal(564.0)


func test_tile_click_uses_new_rect() -> void:
	var s := _screen(_lib([_entry("a", "Aaa", ["easy", "medium", "hard", "expert"])]))
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")
	# y 560 was outside the old 72 px tile (488..560); the new tile spans 468..564.
	s._click(Vector2(1272.0 + 88.0, 562.0), false)
	assert_str(s.debug_state()["difficulty"]).is_equal("medium")
	s._click(Vector2(1080.0 + 10.0, 470.0), false)
	assert_str(s.debug_state()["difficulty"]).is_equal("easy")
	# Above the tile row (caption area) and in the gap between tiles: no change.
	s._click(Vector2(1464.0 + 20.0, 466.0), false)
	s._click(Vector2(1260.0, 500.0), false)
	assert_str(s.debug_state()["difficulty"]).is_equal("easy")


func test_unavailable_tile_click_is_ignored() -> void:
	var s := _screen(_lib([_entry("a", "Aaa", ["easy", "expert"])]))
	s._click(Vector2(1272.0 + 88.0, 520.0), false)
	assert_str(s.debug_state()["difficulty"]).is_equal("expert")


func test_debug_state_tiles_show_note_count_and_intensity() -> void:
	var e := _entry("a", "Aaa", ["easy", "expert"])
	e.length_sec = 100.0
	e.difficulties[0]["note_count"] = 150
	e.difficulties[1]["note_count"] = 1204
	var s := _screen(_lib([e]))
	var tiles: Array = s.debug_state()["tiles"]
	assert_int(tiles.size()).is_equal(4)
	assert_dict(tiles[0]).is_equal({"name": "easy", "available": true, "text": "150 NOTES", "intensity": 1})
	assert_dict(tiles[1]).is_equal({"name": "medium", "available": false, "text": "-", "intensity": 0})
	assert_dict(tiles[2]).is_equal({"name": "hard", "available": false, "text": "-", "intensity": 0})
	assert_dict(tiles[3]).is_equal({"name": "expert", "available": true, "text": "1,204 NOTES", "intensity": 5})


func test_debug_state_tiles_for_broken_song_are_unavailable() -> void:
	var s := _screen(_lib([_entry("bad", "Broken one", [], "broken")]))
	for t in s.debug_state()["tiles"]:
		assert_bool(t["available"]).is_false()
		assert_str(t["text"]).is_equal("-")


func test_preview_player_uses_preview_bus() -> void:
	var s := _screen(_lib(_songs(1)))
	assert_str(String(s._preview_player.bus)).is_equal("Preview")


func test_visualizer_band_edges_are_log_spaced_60_to_12k() -> void:
	var edges: PackedFloat32Array = SongSelect.visualizer_band_edges()
	assert_int(edges.size()).is_equal(SongSelect.VIZ_BARS + 1)
	assert_int(SongSelect.VIZ_BARS).is_equal(30)
	assert_float(edges[0]).is_equal_approx(60.0, 0.01)
	assert_float(edges[30]).is_equal_approx(12000.0, 0.5)
	var ratio := edges[1] / edges[0]
	for i in 30:
		assert_float(edges[i + 1] / edges[i]).is_equal_approx(ratio, 0.001)


func test_visualizer_is_zero_without_preview() -> void:
	Settings.reduce_motion = false
	var s := _screen(_lib(_songs(1)))
	s.apply_effect_settings()
	var calls := [0]
	s.magnitude_source = func(_lo: float, _hi: float) -> float:
		calls[0] += 1
		return 1.0
	assert_str(s.debug_state()["preview_state"]).is_not_equal("playing")
	for k in 10:
		s.step_visualizer(0.05)
	var lv: PackedFloat32Array = s.visualizer_levels()
	assert_int(lv.size()).is_equal(30)
	for v in lv:
		assert_float(v).is_equal(0.0)
	assert_int(calls[0]).is_equal(0)


func test_visualizer_attack_and_release_smoothing() -> void:
	Settings.reduce_motion = false
	var s := _screen(_lib(_songs(1)))
	s.apply_effect_settings()
	var mag := [1.0]
	var bands: Array = []
	s.magnitude_source = func(lo: float, hi: float) -> float:
		bands.append(Vector2(lo, hi))
		return mag[0]
	s._preview_state = "playing"
	s.step_visualizer(0.016)
	assert_int(bands.size()).is_equal(30)
	assert_float(s.visualizer_levels()[0]).is_between(0.4, 0.7)
	s.step_visualizer(0.016)
	# 0 dB rises to full within 30 ms.
	for v in s.visualizer_levels():
		assert_float(v).is_equal_approx(1.0, 0.0001)
	# -30 dB maps to 0.5.
	mag[0] = db_to_linear(-30.0)
	s.step_visualizer(0.03)
	assert_float(s.visualizer_levels()[5]).is_greater(0.8)
	s.step_visualizer(0.06)
	assert_float(s.visualizer_levels()[5]).is_equal_approx(0.5, 0.01)
	# Silence falls from 0.5 to 0 over 90 ms (180 ms for full scale), not at once.
	mag[0] = 0.0
	s.step_visualizer(0.045)
	assert_float(s.visualizer_levels()[5]).is_equal_approx(0.25, 0.01)
	s.step_visualizer(0.05)
	assert_float(s.visualizer_levels()[5]).is_equal(0.0)
	# Preview stops: the bars fall back to zero.
	mag[0] = 1.0
	s.step_visualizer(0.05)
	s._preview_state = "none"
	s.step_visualizer(0.2)
	for v in s.visualizer_levels():
		assert_float(v).is_equal(0.0)


func test_visualizer_reduce_motion_static_mid_height_low_keeps_animation() -> void:
	Settings.reduce_motion = true
	var s := _screen(_lib(_songs(1)))
	s.apply_effect_settings()
	s.magnitude_source = func(_lo: float, _hi: float) -> float: return 1.0
	s._preview_state = "playing"
	s.step_visualizer(0.05)
	for v in s.visualizer_levels():
		assert_float(v).is_equal(0.5)
	assert_bool(s.effect_counts()["visualizer_animated"]).is_false()
	assert_bool(s.effect_counts()["sweep"]).is_false()
	Settings.reduce_motion = false
	Settings.low_effects = true
	s.apply_effect_settings()
	assert_bool(s.effect_counts()["visualizer_animated"]).is_true()
	s.step_visualizer(0.05)
	assert_float(s.visualizer_levels()[0]).is_equal_approx(1.0, 0.0001)


func test_song_select_registers_effect_contract() -> void:
	Settings.reduce_motion = false
	var s := _screen(_lib(_songs(1)))
	assert_bool(s.is_in_group(UiKit.FX_GROUP)).is_true()
	var c: Dictionary = s.effect_counts()
	assert_bool(c.has("visualizer_animated") and c.has("sweep")).is_true()
	assert_bool(c["visualizer_animated"]).is_true()


func test_drawing_every_state_runs_without_errors() -> void:
	# _draw runs on the next frames; script errors there show in the log (checked by the runner output).
	var list := _songs(12)
	list.append(_entry("nc", "Needs one", [], "needs_chart"))
	list.append(_entry("bad", "Broken one " + "long ".repeat(30), [], "broken"))
	list.append(_entry("cjk", "日本語のタイトル Привет", ["hard"]))
	var lib := _lib(list)
	var s := _screen(lib)
	SongSelect.run_practice = true
	for id in ["s03", "nc", "bad", "cjk"]:
		s.select_for_test(id)
		await get_tree().process_frame
		await get_tree().process_frame
	s.set_filter_for_test("zzz")
	await get_tree().process_frame
	s.set_filter_for_test("")
	s.press_key_for_test(KEY_F2)
	await get_tree().process_frame
	lib.shell_opener = func(_p: String) -> bool: return false
	s.open_folder_for_test()
	await get_tree().process_frame
	var empty := _screen(_lib([]))
	await get_tree().process_frame
	assert_bool(s.is_inside_tree() and empty.is_inside_tree()).is_true()


# ---- 02.2-19: table backdrop, glass rows, sections ----

func _screen_with_sections(lib: Node, loader: Callable) -> SongSelect:
	var s: SongSelect = (load("res://scenes/song_select.tscn") as PackedScene).instantiate()
	s.library = lib
	s.section_loader = loader
	add_child(s)
	auto_free(s)
	return s


func _wait_sections(s: SongSelect, state: String) -> bool:
	for i in 120:
		if s.debug_state()["sections"]["state"] == state:
			return true
		await get_tree().process_frame
	return s.debug_state()["sections"]["state"] == state


func test_background_is_table_backdrop_not_arena() -> void:
	var s := _screen(_lib(_songs(3)))
	var bd := s.get_node_or_null("Backdrop") as AbyssBackdrop
	assert_object(bd).is_not_null()
	assert_str(bd.variant).is_equal("table")
	assert_int(bd.get_index()).is_equal(0)
	for c in s.get_children():
		assert_bool(c is Arena).override_failure_message("menu_mode Arena still present").is_false()


func test_sweep_off_in_low_and_reduce_on_in_full() -> void:
	Settings.reduce_motion = false
	Settings.low_effects = false
	var s := _screen(_lib(_songs(1)))
	s.apply_effect_settings()
	assert_bool(s.effect_counts()["sweep"]).is_true()
	Settings.low_effects = true
	s.apply_effect_settings()
	assert_bool(s.effect_counts()["sweep"]).is_false()
	Settings.low_effects = false
	Settings.reduce_motion = true
	s.apply_effect_settings()
	assert_bool(s.effect_counts()["sweep"]).is_false()


func test_row_colors_use_focus_style_and_glass_rows() -> void:
	var sel: Dictionary = SongSelect.row_colors(true, false)
	assert_that(sel["fill"]).is_equal(Palette.alpha(Palette.ABYSS_600, 0.92))
	assert_that(sel["edge"]).is_equal(Palette.SONAR)
	var idle: Dictionary = SongSelect.row_colors(false, false)
	assert_that(idle["fill"]).is_equal(Palette.alpha(Palette.ABYSS_700, 0.6))
	assert_that(idle["edge"]).is_equal(Palette.alpha(Palette.SONAR, 0.3))
	var hov: Dictionary = SongSelect.row_colors(false, true)
	assert_that(hov["edge"]).is_equal(Palette.alpha(Palette.SONAR, 0.6))


func test_section_block_geometry() -> void:
	assert_float(SongSelect.SECTIONS_BASELINE).is_equal(688.0)
	assert_object(SongSelect.SECTION_STRIP).is_equal(Rect2(1080.0, 700.0, 752.0, 8.0))
	assert_float(SongSelect.SECTION_NAMES_BASELINE).is_equal(736.0)
	assert_float(SongSelect.SECTION_NAMES_W).is_equal(752.0)
	assert_float(SongSelect.section_tick_x(0.0, 100.0)).is_equal(1080.0)
	assert_float(SongSelect.section_tick_x(50.0, 100.0)).is_equal(1080.0 + 376.0)
	assert_float(SongSelect.section_tick_x(500.0, 100.0)).is_equal(1830.0)
	assert_float(SongSelect.section_tick_x(5.0, 0.0)).is_equal(1080.0)


func test_parse_sections_reads_chart_events() -> void:
	var e := _entry("c", "Community")
	e.chart_path = "res://tests/fixtures/charts/community_style.chart"
	var secs: Array = SongSelect.parse_sections(e)
	var names: Array = []
	for x in secs:
		names.append(x["name"])
	assert_array(names).is_equal(["Intro", "Verse 1", "Chorus"])
	assert_float(float(secs[1]["time"])).is_greater(float(secs[0]["time"]))
	var bad := _entry("b", "Broken", [], "broken")
	bad.chart_path = e.chart_path
	assert_array(SongSelect.parse_sections(bad)).is_empty()
	var missing := _entry("m", "Missing")
	missing.chart_path = D + "/no_such.chart"
	assert_array(SongSelect.parse_sections(missing)).is_empty()
	assert_array(SongSelect.parse_sections(null)).is_empty()


func test_section_names_text_joins_and_truncates_at_752() -> void:
	var s := _screen(_lib(_songs(1)))
	assert_str(s.section_names_text([])).is_equal("No section markers in this chart.")
	assert_str(s.section_names_text([{"time": 0.0, "name": "Intro"}, {"time": 3.0, "name": "Verse 1"}])) \
		.is_equal("Intro, Verse 1")
	var many: Array = []
	for i in 40:
		many.append({"time": float(i), "name": "Section Number %d" % i})
	var txt := s.section_names_text(many)
	assert_str(txt).ends_with("...")
	assert_float(s._w(txt, Palette.SIZE_LABEL)).is_less_equal(752.0)


func test_sections_load_lazily_for_selected_song_and_cache_per_id() -> void:
	var calls: Array = []
	var loader := func(e: SongEntry) -> Array:
		calls.append(e.id)
		return [{"time": 1.0, "name": "Intro " + e.id}, {"time": 50.0, "name": "Outro"}]
	var s := _screen_with_sections(_lib([_entry("a", "Aaa"), _entry("b", "Bbb"), _entry("c", "Ccc")]), loader)
	assert_bool(await _wait_sections(s, "ready")).is_true()
	assert_array(calls).is_equal(["a"])
	var sec: Dictionary = s.debug_state()["sections"]
	assert_int(sec["count"]).is_equal(2)
	assert_array(sec["names"]).is_equal(["Intro a", "Outro"])
	s.select_for_test("b")
	assert_bool(await _wait_sections(s, "ready")).is_true()
	assert_array(s.debug_state()["sections"]["names"]).is_equal(["Intro b", "Outro"])
	s.select_for_test("a")
	# Cached: ready at once, no second parse.
	assert_str(s.debug_state()["sections"]["state"]).is_equal("ready")
	assert_array(calls).is_equal(["a", "b"])


func test_sections_not_parsed_for_unplayable_songs() -> void:
	var calls: Array = []
	var loader := func(e: SongEntry) -> Array:
		calls.append(e.id)
		return []
	var s := _screen_with_sections(_lib([_entry("bad", "Broken one", [], "broken")]), loader)
	await get_tree().process_frame
	assert_str(s.debug_state()["sections"]["state"]).is_equal("none")
	assert_array(calls).is_empty()


func test_stale_section_result_is_dropped() -> void:
	var loader := func(_e: SongEntry) -> Array: return []
	var s := _screen_with_sections(_lib([_entry("a", "Aaa"), _entry("b", "Bbb")]), loader)
	await _wait_sections(s, "ready")
	s.select_for_test("b")
	var req: int = s._section_request
	# A late result for the old request (song a) must not land on song b, nor be cached for b.
	s.sections_loaded(req - 1, "b", [{"time": 0.0, "name": "Wrong"}])
	assert_array(s.debug_state()["sections"]["names"]).is_not_equal(["Wrong"])
	s.sections_loaded(req, "b", [{"time": 0.0, "name": "Right"}])
	assert_array(s.debug_state()["sections"]["names"]).is_equal(["Right"])
