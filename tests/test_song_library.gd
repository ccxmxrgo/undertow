extends GdUnitTestSuite
## SongLibrary: worker scan, signals, build_chart, calibration entry, read-only extra folders.
## Uses its own instance (not the autoload) pointed at temp paths.

const D := "user://test_song_library"
const SONGS := D + "/songs"
const SAMPLE_RATE := 8000


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(SONGS)
	SongScanner.zip_cache_root = D + "/zipcache"


func after_test() -> void:
	SongFixture.rm_tree(D)
	SongScanner.zip_cache_root = "user://song_cache/zips"


func _lib() -> Node:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = SONGS
	lib.cache_path = D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	return lib


func _wait_scan(lib: Node) -> void:
	var t0 := Time.get_ticks_msec()
	while lib.scanning and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	assert_bool(lib.scanning).is_false()


func _scan(lib: Node) -> void:
	lib.rescan()
	await _wait_scan(lib)


func _ids(lib: Node) -> Array:
	var out: Array = []
	for e in lib.entries:
		out.append(e.title)
	return out


func test_calibration_entry_always_present() -> void:
	var lib := _lib()
	assert_int(lib.entries.size()).is_equal(1)
	var c: SongEntry = lib.entries[0]
	assert_str(c.id).is_equal(TestCharts.HAND_CHART_ID)
	assert_str(c.source).is_equal("test")
	assert_str(c.status).is_equal("ok")
	assert_str(c.title).is_equal("Calibration Track")
	assert_str(c.artist).is_equal("Built-in test chart")
	assert_int(c.difficulties.size()).is_equal(1)
	assert_bool(lib.find(TestCharts.HAND_CHART_ID) == c).is_true()
	var chart: ChartData = lib.build_chart(c, "expert")
	assert_object(chart).is_not_null()
	assert_str(chart.id).is_equal(TestCharts.HAND_CHART_ID)
	assert_object(chart.audio_stream).is_not_null()
	lib.queue_free()


func test_scan_finds_dropped_folder_and_builds_playable_chart() -> void:
	SongFixture.make_song(SONGS + "/Dropped")
	var lib := _lib()
	var added: Array = []
	var finished: Array = []
	var progresses: Array = []
	lib.entries_added.connect(func(b: Array) -> void: added.append_array(b))
	lib.progress.connect(func(d: int, t: int, l: String) -> void: progresses.append([d, t, l]))
	lib.scan_finished.connect(func(c: int, u: int) -> void: finished.append([c, u]))
	await _scan(lib)
	assert_array(finished).is_equal([[1, 0]])
	assert_bool(_ids(lib).has("Ini Title")).is_true()
	assert_bool(added.size() >= 2).is_true()  # calibration + the song
	assert_bool(progresses.size() > 0).is_true()
	var e: SongEntry = null
	for x in lib.entries:
		if x.title == "Ini Title":
			e = x
	assert_object(e).is_not_null()
	assert_array(e.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(["easy", "expert"])
	var chart: ChartData = lib.build_chart(e, "expert")
	assert_object(chart).is_not_null()
	assert_str(chart.id).is_equal(e.difficulty("expert")["fingerprint"])
	assert_object(chart.audio_stream).is_not_null()
	assert_str(chart.title).is_equal("Ini Title")
	assert_str(chart.artist).is_equal("Ini Artist")
	assert_int(chart.notes.size()).is_equal(e.difficulty("expert")["note_count"])
	_assert_autoplay_perfect(chart)
	assert_object(lib.load_audio(e)).is_not_null()
	assert_object(lib.build_chart(e, "hard")).is_null()
	assert_str(lib.last_build_error).is_not_empty()
	# cache file was written and a second scan reuses it
	assert_bool(FileAccess.file_exists(D + "/cache.json")).is_true()
	lib.queue_free()


func _assert_autoplay_perfect(chart: ChartData) -> void:
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var hs := HullScore.new(JudgeConfig.new())
	hs.connect_judge(judge)
	var ap := Autoplay.new(chart, judge)
	var last: float = chart.notes[chart.notes.size() - 1]["time"] + 3.0
	var t := 0.0
	while t < last:
		t += 1.0 / 60.0
		ap.update(t)
		judge.tick(t)
	assert_int(hs.miss_count).is_equal(0)
	assert_int(hs.perfect_count).is_equal(chart.notes.size())
	assert_bool(judge.is_finished()).is_true()


func test_rescan_picks_up_new_folder_and_ignores_overlap() -> void:
	SongFixture.make_song(SONGS + "/One")
	var lib := _lib()
	await _scan(lib)
	assert_int(lib.entries.size()).is_equal(2)
	SongFixture.make_community(SONGS + "/Two")
	lib.rescan()
	lib.rescan()  # ignored while scanning
	assert_bool(lib.scanning).is_true()
	await _wait_scan(lib)
	assert_int(lib.entries.size()).is_equal(3)
	assert_str(lib.entries[0].id).is_equal(TestCharts.HAND_CHART_ID)
	lib.queue_free()


func test_extra_folder_read_only_and_missing_folder_reported() -> void:
	var extra := D + "/extra"
	SongFixture.make_song(extra + "/Extra Song")
	var before := _snapshot(extra)
	var lib := _lib()
	lib.extra_folders.assign([ProjectSettings.globalize_path(extra), ProjectSettings.globalize_path(D + "/not_there")])
	await _scan(lib)
	assert_str(lib.folder_error).contains("not_there")
	var found: SongEntry = null
	for e in lib.entries:
		if e.source == "library":
			found = e
	assert_object(found).is_not_null()
	assert_str(found.library_name).is_equal("extra")
	assert_array(_snapshot(extra)).is_equal(before)
	lib.queue_free()


func _snapshot(dir: String) -> Array:
	var out: Array = []
	var abs_dir := ProjectSettings.globalize_path(dir)
	for f in DirAccess.get_files_at(abs_dir):
		out.append("%s:%d" % [f, FileAccess.get_modified_time(abs_dir.path_join(f))])
	for d in DirAccess.get_directories_at(abs_dir):
		out.append(d)
		out.append_array(_snapshot(dir.path_join(d)))
	out.sort()
	return out


func test_opus_song_listed_broken_and_not_buildable() -> void:
	SongFixture.make_song(SONGS + "/OpusSong")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SONGS + "/OpusSong/song.wav"))
	SongFixture.write_bytes(SONGS + "/OpusSong/song.ogg", SongFixture.opus_bytes())
	var lib := _lib()
	var finished: Array = []
	lib.scan_finished.connect(func(c: int, u: int) -> void: finished.append([c, u]))
	await _scan(lib)
	assert_array(finished).is_equal([[1, 1]])
	var e: SongEntry = lib.entries[1]
	assert_str(e.status).is_equal("broken")
	assert_str(e.error).is_equal(SongEntry.ERR_OPUS)
	assert_object(lib.build_chart(e, "expert")).is_null()
	assert_str(lib.last_build_error).is_equal(SongEntry.ERR_OPUS)
	lib.queue_free()


func test_build_chart_rejects_changed_song() -> void:
	SongFixture.make_song(SONGS + "/Changing")
	var lib := _lib()
	await _scan(lib)
	var e: SongEntry = lib.entries[1]
	SongFixture.write_text(SONGS + "/Changing/notes.chart", SongFixture.CHART.replace("768 = N 0 0", "770 = N 0 0"))
	assert_object(lib.build_chart(e, "expert")).is_null()
	assert_str(lib.last_build_error).contains("Rescan")
	lib.queue_free()


func test_open_songs_folder_works_before_any_scan() -> void:
	var lib := _lib()
	SongFixture.rm_tree(SONGS)
	var calls: Array = []
	lib.shell_opener = func(p: String) -> bool:
		calls.append(p)
		return true
	assert_bool(lib.open_songs_folder()).is_true()
	assert_int(calls.size()).is_equal(1)
	assert_bool(DirAccess.dir_exists_absolute(calls[0])).is_true()
	assert_bool(lib.scanning).is_false()
	lib.shell_opener = Callable()
	assert_bool(lib.open_songs_folder()).is_true()  # headless: directory check only
	lib.queue_free()


func test_songs_dir_is_absolute() -> void:
	var lib := _lib()
	var p: String = lib.songs_dir()
	assert_bool(p.is_absolute_path()).is_true()
	assert_bool(DirAccess.dir_exists_absolute(p)).is_true()
	lib.queue_free()
