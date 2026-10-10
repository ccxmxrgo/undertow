extends GdUnitTestSuite
## STEM-05 (SPEC req 9): a generated song folder is an ordinary library song. `autochart.py extract`
## writes song.<ext> + notes.chart + song.ini into the Songs folder; this suite copies the bundled
## sea_shanty_2 folder (itself autochart output) into a temp Songs folder and checks that it scans as
## a user song with status ok, the same fingerprints as the bundled copy, all-perfect Autoplay, and that
## the importer maps generated gems 0..3 to lanes 0..3 (identity, no 5->4 folding). Nothing in src/
## special-cases generated songs.

const SRC_DIR := "res://songs/sea_shanty_2"
const FILES: Array[String] = ["notes.chart", "song.ini", "song.mp3"]
const ROOT_D := "user://test_generated_songs"
const COPY_NAME := "sea_shanty_2_copy"
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]


func _copy_song() -> void:
	SongFixture.rm_tree(ROOT_D)
	var dst := ROOT_D + "/songs/" + COPY_NAME
	SongFixture.mkdir(dst)
	for f in FILES:
		var bytes := FileAccess.get_file_as_bytes(SRC_DIR.path_join(f))
		assert_int(bytes.size()).override_failure_message("cannot read %s" % f).is_greater(0)
		SongFixture.write_bytes(dst.path_join(f), bytes)


func _lib() -> Node:
	_copy_song()
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


func _entries(lib: Node) -> Dictionary:
	var out := {"bundled": null, "copy": null}
	for x in lib.entries:
		var e: SongEntry = x
		if e.source == "bundled" and str(e.id).ends_with("sea_shanty_2"):
			out["bundled"] = e
		elif e.source != "bundled" and e.path.trim_suffix("/").ends_with(COPY_NAME):
			out["copy"] = e
	return out


func _fingerprints(e: SongEntry) -> Dictionary:
	var out := {}
	for d in e.difficulties:
		out[d["name"]] = d["fingerprint"]
	return out


func after_test() -> void:
	SongFixture.rm_tree(ROOT_D)


func test_copy_scans_as_ok_user_song_with_four_difficulties() -> void:
	var lib := await _lib()
	assert_bool(lib.scanning).is_false()
	var copy: SongEntry = _entries(lib)["copy"]
	assert_object(copy).override_failure_message("copied folder not listed").is_not_null()
	if copy != null:
		assert_str(copy.source).is_not_equal("bundled")
		assert_str(copy.status).override_failure_message("status %s: %s" % [copy.status, copy.error]).is_equal("ok")
		assert_array(copy.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(DIFFS)
	lib.queue_free()


func test_copy_has_the_same_fingerprints_as_the_bundled_song() -> void:
	var lib := await _lib()
	var found := _entries(lib)
	var bundled: SongEntry = found["bundled"]
	var copy: SongEntry = found["copy"]
	assert_object(bundled).is_not_null()
	assert_object(copy).is_not_null()
	if bundled != null and copy != null:
		var a := _fingerprints(bundled)
		var b := _fingerprints(copy)
		assert_int(b.size()).is_equal(4)
		for d in DIFFS:
			assert_str(str(b.get(d, ""))).override_failure_message("%s fingerprint differs" % d).is_equal(str(a.get(d, "?")))
	lib.queue_free()


func test_copy_expert_autoplay_is_all_perfect() -> void:
	var lib := await _lib()
	var copy: SongEntry = _entries(lib)["copy"]
	assert_object(copy).is_not_null()
	if copy != null:
		var chart: ChartData = lib.build_chart(copy, "expert")
		assert_object(chart).override_failure_message(str(lib.last_build_error)).is_not_null()
		if chart != null:
			assert_object(chart.audio_stream).is_not_null()
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
			assert_int(hs.miss_count).is_equal(0)
			assert_int(hs.good_count).is_equal(0)
			assert_int(hs.perfect_count).is_equal(chart.notes.size())
	lib.queue_free()


## Generated charts use only gems N 0..3; ChartImporter.build must put gem n on lane n at the same time.
func test_generated_gems_map_to_lanes_by_identity() -> void:
	var parsed := ChartParser.parse_bytes(FileAccess.get_file_as_bytes(SRC_DIR + "/notes.chart"))
	assert_bool(parsed.ok).is_true()
	var delay := SongIni.get_int(SongIni.parse(FileAccess.get_file_as_string(SRC_DIR + "/song.ini")), "delay", 0)
	var segs := ChartImporter._segments(parsed)
	var res := maxi(parsed.resolution, 1)
	for d in DIFFS:
		var raw := {}
		var raw_count := 0
		for e in parsed.tracks[ChartImporter._TRACK_NAMES[d]]:
			if e["type"] != "N":
				continue
			var gem := int(e["a"])
			assert_bool(gem >= 0 and gem <= 3).override_failure_message("%s gem %d outside 0..3" % [d, gem]).is_true()
			var t := ChartImporter._tick_to_sec(segs, res, int(e["tick"])) + float(delay) / 1000.0
			var key := "%d:%d" % [int(round(t * 1000000.0)), gem]
			raw[key] = int(raw.get(key, 0)) + 1
			raw_count += 1
		var built := {}
		var chart := ChartImporter.build(parsed, d, delay)
		for n in chart.notes:
			var key := "%d:%d" % [int(round(float(n["time"]) * 1000000.0)), int(n["lane"])]
			built[key] = int(built.get(key, 0)) + 1
		assert_int(chart.notes.size()).override_failure_message("%s note count" % d).is_equal(raw_count)
		assert_dict(built).override_failure_message("%s: (time, lane) differs from (time, gem)" % d).is_equal(raw)
