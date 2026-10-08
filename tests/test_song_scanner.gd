extends GdUnitTestSuite
## SongScanner: folders, community layout, zips, bare audio, broken states, cache, caps.
## Everything lives under user://test_song_scanner (never the real songs folder).

const D := "user://test_song_scanner"
const LIB := D + "/lib"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(LIB)
	SongScanner.zip_cache_root = D + "/zipcache"
	SongScanner.max_candidates = 20000
	SongScanner.max_depth = 6
	SongScanner.parse_count = 0
	SongScanner.decode_count = 0


func after_test() -> void:
	SongFixture.rm_tree(D)
	SongScanner.zip_cache_root = "user://song_cache/zips"
	SongScanner.max_candidates = 20000
	SongScanner.max_depth = 6


func _roots(path: String = LIB, source: String = "test") -> Array:
	return [{"path": path, "source": source, "library_name": "Lib"}]


func _scan(path: String = LIB, cache: SongCache = null) -> Array[SongEntry]:
	return SongScanner.new().scan_sync(_roots(path), cache)


func _by_title(entries: Array, title: String) -> SongEntry:
	for e in entries:
		if e.title == title:
			return e
	return null


func _fixture_bytes(name_s: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes("res://tests/fixtures/charts/" + name_s)


func test_plain_folder_is_playable() -> void:
	SongFixture.make_song(LIB + "/First")
	var es := _scan()
	assert_int(es.size()).is_equal(1)
	var e := es[0]
	assert_str(e.status).is_equal("ok")
	assert_str(e.title).is_equal("Ini Title")
	assert_str(e.artist).is_equal("Ini Artist")
	assert_str(e.charter).is_equal("Ini Charter")
	assert_float(e.length_sec).is_greater(1.5)
	assert_float(e.bpm_min).is_equal_approx(120.0, 0.01)
	assert_float(e.bpm_max).is_equal_approx(120.0, 0.01)
	assert_int(e.difficulties.size()).is_equal(2)
	var names: Array = []
	for d in e.difficulties:
		names.append(d["name"])
		assert_str(d["fingerprint"]).starts_with("u1.")
		assert_int(d["note_count"]).is_greater(0)
	assert_array(names).contains_exactly(["easy", "expert"])
	assert_bool(e.id.ends_with("/First")).is_true()
	assert_str(e.library_name).is_equal("Lib")
	assert_str(e.signature).is_not_empty()


func test_missing_ini_uses_folder_and_chart_names() -> void:
	SongFixture.make_song(LIB + "/Folder Name", false)
	var e := _scan()[0]
	assert_str(e.status).is_equal("ok")
	assert_str(e.title).is_equal("Fixture Song")  # from the chart [Song] Name
	assert_int(e.delay_ms).is_equal(0)


func test_community_folder_and_zip_match() -> void:
	SongFixture.make_community(LIB + "/Community Folder")
	var e := _scan()[0]
	assert_str(e.status).is_equal("ok")
	assert_str(e.title).is_equal("Community Song")
	assert_str(e.charter).is_equal("Somebody")
	assert_int(e.preview_start_ms).is_equal(1500)
	assert_int(e.audio_files.size()).is_equal(5)
	for a in e.audio_files:
		assert_bool(a.ends_with(".png")).is_false()
	# renamed folder: identical fingerprints
	DirAccess.rename_absolute(ProjectSettings.globalize_path(LIB + "/Community Folder"),
			ProjectSettings.globalize_path(LIB + "/Renamed"))
	var renamed := _scan()[0]
	assert_str(renamed.difficulties[0]["fingerprint"]).is_equal(e.difficulties[0]["fingerprint"])
	# zipped copy with a top-level folder
	var zroot := D + "/zroot"
	SongFixture.mkdir(zroot)
	assert_int(SongFixture.zip_folder(LIB + "/Renamed", zroot + "/pack.zip", "Top Folder")).is_equal(OK)
	var z := _scan(zroot)
	assert_int(z.size()).is_equal(1)
	assert_str(z[0].status).is_equal("ok")
	assert_bool(z[0].id.contains("pack.zip::")).is_true()
	assert_int(z[0].difficulties.size()).is_equal(e.difficulties.size())
	for i in e.difficulties.size():
		assert_str(z[0].difficulties[i]["fingerprint"]).is_equal(e.difficulties[i]["fingerprint"])


func test_zip_progress_label_and_cache_reuse() -> void:
	var src := D + "/src"
	SongFixture.make_song(src)
	var zroot := D + "/zroot"
	SongFixture.zip_folder(src, zroot + "/a.zip")
	var labels: Array = []
	var s := SongScanner.new()
	var first := s.scan(_roots(zroot), null, Callable(),
			func(_d: int, _t: int, label: String) -> void: labels.append(label))
	assert_str(first[0].status).is_equal("ok")
	assert_bool(labels.has("Unpacking a.zip")).is_true()
	var cache := SongCache.new()
	for e in first:
		cache.put(e)
	var parses := SongScanner.parse_count
	var decodes := SongScanner.decode_count
	var again := SongScanner.new().scan_sync(_roots(zroot), cache)
	assert_int(again.size()).is_equal(1)
	assert_int(SongScanner.parse_count).is_equal(parses)
	assert_int(SongScanner.decode_count).is_equal(decodes)


func test_bare_audio_needs_chart() -> void:
	SongFixture.write_bytes(LIB + "/tagged.mp3", SongFixture.mp3_bytes("Cool Song", "The Band"))
	SongFixture.make_wav(LIB + "/Some Artist - Some Title.wav")
	SongFixture.write_bytes(LIB + "/untagged_file.mp3", SongFixture.mp3_bytes())
	var es := _scan()
	assert_int(es.size()).is_equal(3)
	var tagged := _by_title(es, "Cool Song")
	assert_object(tagged).is_not_null()
	assert_str(tagged.artist).is_equal("The Band")
	assert_str(tagged.status).is_equal("needs_chart")
	var named := _by_title(es, "Some Title")
	assert_object(named).is_not_null()
	assert_str(named.artist).is_equal("Some Artist")
	assert_object(_by_title(es, "untagged file")).is_not_null()


func test_folder_with_audio_and_no_chart() -> void:
	SongFixture.make_wav(LIB + "/OnlyAudio/song.wav")
	SongFixture.make_wav(LIB + "/Stems/guitar.wav")
	SongFixture.make_wav(LIB + "/Stems/drums.wav")
	SongFixture.make_wav(LIB + "/Loose/one.wav")
	SongFixture.make_wav(LIB + "/Loose/two.wav")
	var es := _scan()
	assert_int(es.size()).is_equal(4)
	for e in es:
		assert_str(e.status).is_equal("needs_chart")
		assert_str(e.error).is_equal(SongEntry.ERR_NEEDS_CHART)
	assert_object(_by_title(es, "OnlyAudio")).is_not_null()
	assert_object(_by_title(es, "Stems")).is_not_null()
	assert_object(_by_title(es, "one")).is_not_null()
	assert_object(_by_title(es, "two")).is_not_null()


func test_broken_songs_have_exact_reasons() -> void:
	SongFixture.make_song(LIB + "/Opus")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIB + "/Opus/song.wav"))
	SongFixture.write_bytes(LIB + "/Opus/song.ogg", SongFixture.opus_bytes())
	SongFixture.make_song(LIB + "/NoGuitar", true, SongFixture.CHART_NO_GUITAR)
	SongFixture.make_song(LIB + "/Garbled")
	SongFixture.write_bytes(LIB + "/Garbled/notes.chart", _fixture_bytes("garbage.chart"))
	SongFixture.make_song(LIB + "/NoAudio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIB + "/NoAudio/song.wav"))
	SongFixture.write_text(LIB + "/MidOnly/notes.mid", "MThd")
	SongFixture.make_song(LIB + "/Unsupported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIB + "/Unsupported/song.wav"))
	SongFixture.write_bytes(LIB + "/Unsupported/song.ogg", SongFixture.garbage_bytes())
	SongFixture.make_song(LIB + "/BadMp3")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIB + "/BadMp3/song.wav"))
	SongFixture.write_bytes(LIB + "/BadMp3/song.mp3", SongFixture.garbage_bytes())
	SongFixture.write_bytes(LIB + "/bad.zip", SongFixture.garbage_bytes())
	SongFixture.make_song(LIB + "/Huge")
	var big := PackedByteArray()
	big.resize(ChartParser.MAX_BYTES + 1)
	SongFixture.write_bytes(LIB + "/Huge/notes.chart", big)
	var es := _scan()
	var want := {
		"Opus": SongEntry.ERR_OPUS,
		"NoGuitar": SongEntry.ERR_NO_GUITAR,
		"NoAudio": SongEntry.ERR_AUDIO_MISSING,
		"MidOnly": SongEntry.ERR_MIDI,
		"Unsupported": SongEntry.ERR_UNSUPPORTED_AUDIO,
		"BadMp3": SongEntry.ERR_AUDIO_BAD,
		"bad": SongEntry.ERR_ZIP,
		"Huge": SongEntry.ERR_TOO_LARGE,
	}
	for k in want:
		var e: SongEntry = null
		for x in es:
			if x.path.get_file().get_basename() == k or x.title == k or x.path.get_file() == k:
				e = x
		assert_object(e).is_not_null()
		if e != null:
			assert_str(e.status).is_equal("broken")
			assert_str(e.error).is_equal(want[k])
			assert_str(e.fix_hint).is_not_empty()
	var garbled: SongEntry = null
	for x in es:
		if x.path.get_file() == "Garbled":
			garbled = x
	assert_object(garbled).is_not_null()
	assert_str(garbled.error).starts_with("Unreadable .chart (line ")
	assert_str(garbled.status).is_equal("broken")


func test_cache_hit_does_no_work_and_changes_invalidate_one() -> void:
	SongFixture.make_song(LIB + "/A")
	SongFixture.make_song(LIB + "/B")
	var first := _scan()
	assert_int(first.size()).is_equal(2)
	var cache := SongCache.new()
	for e in first:
		cache.put(e)
	var p0 := SongScanner.parse_count
	var d0 := SongScanner.decode_count
	var second := _scan(LIB, cache)
	assert_int(second.size()).is_equal(2)
	assert_int(SongScanner.parse_count).is_equal(p0)
	assert_int(SongScanner.decode_count).is_equal(d0)
	assert_str(second[0].difficulties[0]["fingerprint"]).is_equal(first[0].difficulties[0]["fingerprint"])
	# chart size change invalidates only that song
	SongFixture.write_text(LIB + "/A/notes.chart", SongFixture.CHART + "\n[Extra]\n{\n}\n")
	var third := _scan(LIB, cache)
	assert_int(third.size()).is_equal(2)
	assert_int(SongScanner.parse_count).is_equal(p0 + 1)
	assert_int(SongScanner.decode_count).is_equal(d0 + 1)
	cache = SongCache.new()
	for e in third:
		cache.put(e)
	# audio change invalidates too
	SongFixture.make_wav(LIB + "/B/song.wav", 3.0)
	var fourth := _scan(LIB, cache)
	assert_int(SongScanner.parse_count).is_equal(p0 + 2)
	for e in fourth:
		if e.path.ends_with("/B"):
			assert_float(e.length_sec).is_greater(2.5)
	# deleted folder disappears
	SongFixture.rm_tree(LIB + "/B")
	assert_int(_scan(LIB, cache).size()).is_equal(1)


func test_cancel_stops_between_songs() -> void:
	for i in 6:
		SongFixture.make_song(LIB + "/S%d" % i)
	var seen := [0]
	var progress := func(_d: int, _t: int, _l: String) -> void: seen[0] += 1
	var cancel := func() -> bool: return seen[0] >= 3
	var es := SongScanner.new().scan(_roots(), null, Callable(), progress, cancel)
	assert_int(es.size()).is_less(6)
	assert_int(es.size()).is_greater(0)


func test_extra_root_is_read_only() -> void:
	var extra := D + "/extra"
	SongFixture.make_song(extra + "/Song")
	SongFixture.zip_folder(extra + "/Song", extra + "/pack.zip")
	var before := _snapshot(extra)
	var es := SongScanner.new().scan_sync(_roots(extra, "library"))
	assert_int(es.size()).is_greater(0)
	assert_str(es[0].source).is_equal("library")
	assert_array(_snapshot(extra)).is_equal(before)


func _snapshot(dir: String) -> Array:
	var out: Array = []
	var abs_dir := ProjectSettings.globalize_path(dir)
	for f in DirAccess.get_files_at(abs_dir):
		out.append("%s:%d:%d" % [f, FileAccess.get_modified_time(abs_dir.path_join(f)), FileAccess.get_file_as_bytes(abs_dir.path_join(f)).size()])
	for d in DirAccess.get_directories_at(abs_dir):
		out.append(d)
		out.append_array(_snapshot(dir.path_join(d)))
	out.sort()
	return out


func test_many_entries_and_caps() -> void:
	var wav := PackedByteArray()
	SongFixture.make_wav(D + "/tmp.wav", 1.0)
	wav = SongFixture.read_bytes(D + "/tmp.wav")
	for i in 200:
		var dir := LIB + "/Song %03d" % i
		SongFixture.write_text(dir + "/notes.chart", SongFixture.CHART)
		SongFixture.write_bytes(dir + "/song.wav", wav)
	var es := _scan()
	assert_int(es.size()).is_equal(200)
	for e in es:
		assert_str(e.status).is_equal("ok")
	SongScanner.max_candidates = 5
	assert_int(_scan().size()).is_equal(5)


func test_depth_cap_and_nested_folder() -> void:
	SongFixture.make_song(LIB + "/Pack/Nested Song")
	SongFixture.make_song(LIB + "/a/b/c/d/e/f/g/Deep")
	var es := _scan()
	assert_int(es.size()).is_equal(1)
	assert_str(es[0].title).is_equal("Ini Title")
	assert_bool(es[0].id.contains("Nested Song")).is_true()


func test_zip_slip_entry_does_not_escape() -> void:
	var zroot := D + "/zroot"
	SongFixture.make_zip(zroot + "/evil.zip", {
		"../escape.chart": "x",
		"Song/notes.chart": SongFixture.CHART,
		"Song/song.wav": SongFixture.read_bytes(_tmp_wav()),
	})
	var es := _scan(zroot)
	assert_int(es.size()).is_equal(1)
	assert_str(es[0].status).is_equal("ok")
	assert_bool(FileAccess.file_exists(D + "/zipcache/escape.chart")).is_false()
	assert_bool(FileAccess.file_exists(D + "/escape.chart")).is_false()


func _tmp_wav() -> String:
	SongFixture.make_wav(D + "/tmpwav.wav", 1.0)
	return D + "/tmpwav.wav"


func test_id3_reader_handles_garbage() -> void:
	SongFixture.write_bytes(D + "/g.mp3", PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0x7F, 0x7F, 1, 2, 3]))
	var t := SongScanner.read_id3(D + "/g.mp3")
	assert_bool(t.is_empty()).is_true()
	assert_bool(SongScanner.read_id3(D + "/none.mp3").is_empty()).is_true()
