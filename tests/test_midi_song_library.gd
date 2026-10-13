extends GdUnitTestSuite
## CONT-01 end to end: a generated notes.mid song is an ordinary library song (scan, build, Autoplay).
## No copyrighted data (D-10).

const ROOT_D := "user://test_midi_song_library"
const FOLDER := "mid_demo"
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]


func _lib() -> Node:
	SongFixture.rm_tree(ROOT_D)
	var dst := ROOT_D + "/songs/" + FOLDER
	SongFixture.make_mid_song(dst, MidiWriter.demo_song()["mid"])
	# Replace the short default wav with one long enough to cover the whole demo chart.
	SongFixture.make_wav(dst.path_join("song.wav"), 40.0)
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = ROOT_D + "/songs"
	lib.cache_path = ROOT_D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	lib.rescan()
	var t0 := Time.get_ticks_msec()
	while lib.scanning and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	return lib


func _entry(lib: Node) -> SongEntry:
	for x in lib.entries:
		var e: SongEntry = x
		if e.source != "bundled" and e.path.trim_suffix("/").ends_with(FOLDER):
			return e
	return null


func after_test() -> void:
	SongFixture.rm_tree(ROOT_D)


func _autoplay(chart: ChartData) -> Array:
	var cfg := JudgeConfig.new()
	var judge := InputJudge.new(chart, cfg)
	var hs := HullScore.new(cfg)
	hs.connect_judge(judge)
	var ap := Autoplay.new(chart, judge)
	var tail: Dictionary = chart.notes[chart.notes.size() - 1]
	var last: float = float(tail["time"]) + float(tail["duration"]) + 3.0
	var t := 0.0
	while t < last:
		t += 1.0 / 60.0
		ap.update(t)
		judge.tick(t)
	return [hs.miss_count, hs.good_count, hs.perfect_count]


func test_mid_song_scans_ok_with_four_difficulties() -> void:
	var lib := await _lib()
	var e := _entry(lib)
	assert_object(e).override_failure_message("mid folder not listed").is_not_null()
	if e != null:
		assert_str(e.status).override_failure_message("status %s: %s" % [e.status, e.error]).is_equal("ok")
		assert_str(e.source).is_not_equal("bundled")
		assert_str(e.error).is_equal("")
		assert_array(e.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(DIFFS)
	lib.queue_free()


func test_mid_song_builds_every_difficulty_with_matching_fingerprint() -> void:
	var lib := await _lib()
	var e := _entry(lib)
	assert_object(e).is_not_null()
	if e != null:
		for d in DIFFS:
			var chart: ChartData = lib.build_chart(e, d)
			assert_object(chart).override_failure_message("%s: %s" % [d, str(lib.last_build_error)]).is_not_null()
			assert_str(str(lib.last_build_error)).is_equal("")
			if chart != null:
				assert_str(chart.id).is_equal(str(e.difficulty(d)["fingerprint"]))
	lib.queue_free()


func test_mid_song_expert_and_easy_autoplay_all_perfect() -> void:
	var lib := await _lib()
	var e := _entry(lib)
	assert_object(e).is_not_null()
	if e != null:
		for d in ["expert", "easy"]:
			var chart: ChartData = lib.build_chart(e, d)
			assert_object(chart).is_not_null()
			if chart != null:
				var r := _autoplay(chart)
				assert_int(r[0]).override_failure_message("%s misses" % d).is_equal(0)
				assert_int(r[1]).override_failure_message("%s goods" % d).is_equal(0)
				assert_int(r[2]).override_failure_message("%s perfects" % d).is_equal(chart.notes.size())
	lib.queue_free()


func test_mid_song_expert_keeps_sections_and_solos() -> void:
	var lib := await _lib()
	var e := _entry(lib)
	assert_object(e).is_not_null()
	if e != null:
		var chart: ChartData = lib.build_chart(e, "expert")
		assert_object(chart).is_not_null()
		if chart != null:
			var names: Array = chart.sections.map(func(s: Dictionary) -> String: return str(s["name"]))
			assert_bool(names.has("Intro")).override_failure_message(str(names)).is_true()
			assert_int(chart.solos.size()).is_greater_equal(1)
	lib.queue_free()
