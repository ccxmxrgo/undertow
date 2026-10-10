extends GdUnitTestSuite
## Bundled songs (SONG-04, SONG-07, D-04, D-14, STEM-07): every bundled chart is the committed
## output of tools/autochart. The committed notes.chart is the source of truth; these tests check
## the committed files and never regenerate or re-run ML. Chart rules, the gate report, Autoplay
## and hash checks per song live in test_autochart_songs.gd (AUTOCHART_IDS = all five ids).
## Reads the committed res://songs files only; the library test uses its own user:// folder.

const IDS: Array[String] = ["synth_wave_april", "space_synth_wave", "sea_shanty_2", "hrt", "invisible"]
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]
## Decoded audio lengths (s); the library and the stream must agree within 0.15 s.
const AUDIO_LEN := {"synth_wave_april": 128.0, "space_synth_wave": 192.0, "sea_shanty_2": 127.85,
		"hrt": 161.87, "invisible": 191.63}


func _parsed(id: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes("res://songs/%s/notes.chart" % id))


func _ini(id: String) -> Dictionary:
	return SongIni.parse(FileAccess.get_file_as_string("res://songs/%s/song.ini" % id))


func test_manifest_lists_all_five_songs_in_order_with_existing_files() -> void:
	assert_int(BundledSongs.SONGS.size()).is_equal(IDS.size())
	for i in IDS.size():
		var b: Dictionary = BundledSongs.SONGS[i]
		assert_str(b["id"]).is_equal(IDS[i])
		assert_str(b["dir"]).is_equal("res://songs/" + IDS[i])
		assert_bool(FileAccess.file_exists(b["dir"] + "/notes.chart")).is_true()
		assert_bool(ResourceLoader.exists(b["dir"] + "/" + b["audio"])).is_true()
	assert_bool(FileAccess.file_exists("res://songs/CREDITS.txt")).is_true()
	var credits := FileAccess.get_file_as_string("res://songs/CREDITS.txt")
	for s in ["Pro Sensory", "CC0", "Jagex", "Duran Duran"]:
		assert_bool(credits.contains(s)).override_failure_message("CREDITS.txt lacks %s" % s).is_true()


func test_song_ini_metadata() -> void:
	for id in IDS:
		var ini := _ini(id)
		var p := _parsed(id)
		assert_bool(p.ok).override_failure_message("%s: chart does not parse" % id).is_true()
		assert_str(str(ini.get("charter", ""))).is_equal("UNDERTOW autochart")
		assert_str(str(ini.get("name", ""))).is_not_empty()
		assert_str(str(ini.get("artist", ""))).override_failure_message(
				"%s: song.ini artist differs from the chart [Song] artist" % id).is_equal(str(p.song.get("artist", "")))
		assert_int(SongIni.get_int(ini, "preview_start_time", -1)).is_greater(0)
		assert_int(SongIni.get_int(ini, "song_length", 0)).is_greater(100000)
	for id in ["synth_wave_april", "space_synth_wave"]:
		assert_str(str(_ini(id).get("artist", ""))).is_equal("Pro Sensory (Alex McCulloch)")


# ---- library listing (plan 02-05 task 3) ----

const LIB_D := "user://test_bundled_songs"


func _lib() -> Node:
	SongFixture.rm_tree(LIB_D)
	SongFixture.mkdir(LIB_D + "/songs")
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = LIB_D + "/songs"
	lib.cache_path = LIB_D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	lib.rescan()
	var t0 := Time.get_ticks_msec()
	while lib.scanning and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	return lib


func after_test() -> void:
	SongFixture.rm_tree(LIB_D)


func test_library_lists_all_bundled_songs_playable() -> void:
	var lib := await _lib()
	assert_bool(lib.scanning).is_false()
	for id in IDS:
		var e: SongEntry = null
		for x in lib.entries:
			if x.source == "bundled" and str(x.id).ends_with(id):
				e = x
		assert_object(e).override_failure_message("%s not listed" % id).is_not_null()
		if e == null:
			continue
		assert_str(e.status).is_equal("ok")
		assert_str(e.artist).is_equal(str(_ini(id).get("artist", "")))
		assert_array(e.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(DIFFS)
		assert_bool(e.has_solos).is_true()
		assert_float(e.length_sec).override_failure_message("%s length %.2f" % [id, e.length_sec]).is_equal_approx(AUDIO_LEN[id], 0.15)
	lib.queue_free()


## 02-06: bundled signatures follow chart / ini content, so a same-size delay change in a game
## update (exported res:// files report mtime 0) cannot leave a stale cache entry behind.
func test_bundled_signature_follows_ini_content() -> void:
	for id in IDS:
		var dir := "res://songs/%s" % id
		var sig: String = load("res://src/autoload/song_library.gd").bundled_signature(dir, dir.path_join("song.ini"))
		assert_str(sig).contains("song.ini=" + FileAccess.get_md5(dir.path_join("song.ini")))
		assert_str(sig).contains("notes.chart=" + FileAccess.get_md5(dir.path_join("notes.chart")))
	var d := LIB_D + "_sig"
	SongFixture.rm_tree(d)
	SongFixture.write_text(d + "/song.ini", "[song]\ndelay = 17\n")
	SongFixture.write_text(d + "/notes.chart", SongFixture.CHART)
	var lib_script: GDScript = load("res://src/autoload/song_library.gd")
	var s1: String = lib_script.bundled_signature(d, d + "/song.ini")
	SongFixture.write_text(d + "/song.ini", "[song]\ndelay = 48\n")
	var s2: String = lib_script.bundled_signature(d, d + "/song.ini")
	assert_str(s2).is_not_equal(s1)
	SongFixture.rm_tree(d)
