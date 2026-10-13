extends GdUnitTestSuite
## CONT-01: ChartFile is the one chart-parse choke point (.chart and .mid).

const D := "user://test_chart_file"


func after_test() -> void:
	SongFixture.rm_tree(D)


func _demo_mid_path() -> String:
	var p := D + "/notes.mid"
	SongFixture.write_bytes(p, MidiWriter.demo_song()["mid"])
	return p


func test_is_chart_ext() -> void:
	assert_bool(ChartFile.is_chart_ext("chart")).is_true()
	assert_bool(ChartFile.is_chart_ext("MID")).is_true()
	assert_bool(ChartFile.is_chart_ext("midi")).is_false()
	assert_bool(ChartFile.is_chart_ext("txt")).is_false()


func test_chart_matches_chart_parser() -> void:
	var p := D + "/notes.chart"
	SongFixture.write_text(p, SongFixture.CHART)
	var a := ChartFile.parse(p)
	var b := ChartParser.parse_bytes(SongFixture.read_bytes(p))
	assert_bool(a.ok).is_true()
	assert_bool(a.ok).is_equal(b.ok)
	assert_int(a.resolution).is_equal(b.resolution)
	assert_array(a.tracks.keys()).is_equal(b.tracks.keys())
	assert_int(a.tracks["ExpertSingle"].size()).is_equal(b.tracks["ExpertSingle"].size())


func test_mid_parses_four_difficulties() -> void:
	var parsed := ChartFile.parse(_demo_mid_path())
	assert_bool(parsed.ok).is_true()
	assert_array(ChartImporter.difficulties(parsed)).contains_exactly_in_any_order(["easy", "medium", "hard", "expert"])


func test_failures() -> void:
	var missing := ChartFile.parse(D + "/nope.mid")
	assert_bool(missing.ok).is_false()
	assert_str(missing.error).is_not_empty()
	var chart_missing := ChartFile.parse(D + "/nope.chart")
	assert_bool(chart_missing.ok).is_false()
	assert_str(chart_missing.error).is_not_empty()
	var huge := D + "/huge.mid"
	SongFixture.write_bytes(huge, PackedByteArray())
	var f := FileAccess.open(huge, FileAccess.WRITE)
	f.resize(MidiChartReader.MAX_BYTES + 1)
	f.close()
	assert_str(ChartFile.parse(huge).error).is_equal(SongEntry.ERR_TOO_LARGE)
	var bad := D + "/bad.mid"
	SongFixture.write_bytes(bad, "MThd".to_ascii_buffer())
	assert_str(ChartFile.parse(bad).error).is_equal(SongEntry.ERR_MIDI_BAD)
	var other := D + "/notes.txt"
	SongFixture.write_text(other, "x")
	var o := ChartFile.parse(other)
	assert_bool(o.ok).is_false()
	assert_str(o.error).is_not_empty()


func test_parse_sections_on_hand_built_mid_entry() -> void:
	var e := SongEntry.new()
	e.status = "ok"
	e.chart_path = _demo_mid_path()
	e.difficulties = [{"name": "expert"}]
	e.delay_ms = 0
	var secs: Array = SongSelect.parse_sections(e)
	assert_int(secs.size()).is_equal(3)
	assert_str(str(secs[0]["name"])).is_equal("Intro")
	assert_str(str(secs[1]["name"])).is_equal("verse 1")
	assert_str(str(secs[2]["name"])).is_equal("Chorus")


const LIBD := D + "/songs"


func _lib() -> Node:
	SongFixture.make_mid_song(LIBD + "/MidSong", MidiWriter.demo_song()["mid"])
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = LIBD
	lib.cache_path = D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	lib.rescan()
	var t0 := Time.get_ticks_msec()
	while lib.scanning and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	return lib


func _mid_entry(lib: Node) -> SongEntry:
	for x in lib.entries:
		var e: SongEntry = x
		if e.path.trim_suffix("/").ends_with("MidSong"):
			return e
	return null


func test_library_builds_scanned_mid_with_scan_fingerprint() -> void:
	var lib := await _lib()
	var e := _mid_entry(lib)
	assert_object(e).is_not_null()
	assert_str(e.status).is_equal("ok")
	assert_int(e.difficulties.size()).is_equal(4)
	for d in e.difficulties:
		var chart: ChartData = lib.build_chart(e, d["name"])
		assert_object(chart).is_not_null()
		assert_str(lib.last_build_error).is_equal("")
		assert_str(chart.id).is_equal(d["fingerprint"])


func test_parse_sections_on_scanned_mid_entry() -> void:
	var lib := await _lib()
	var e := _mid_entry(lib)
	var secs: Array = SongSelect.parse_sections(e)
	assert_int(secs.size()).is_equal(3)
	assert_str(str(secs[0]["name"])).is_equal("Intro")
	assert_str(str(secs[1]["name"])).is_equal("verse 1")
	assert_str(str(secs[2]["name"])).is_equal("Chorus")
