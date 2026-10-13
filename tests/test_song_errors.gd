extends GdUnitTestSuite
## ZipExtractor (zip-slip, caps), SongEntry validation and hints, SongCache hostile files.

const D := "user://test_song_errors"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)


func after_test() -> void:
	SongFixture.rm_tree(D)
	SongScanner.zip_cache_root = "user://song_cache/zips"


# ---- ZipExtractor ----

func test_safe_rel() -> void:
	assert_str(ZipExtractor.safe_rel("")).is_equal("")
	assert_str(ZipExtractor.safe_rel("/abs")).is_equal("")
	assert_str(ZipExtractor.safe_rel("C:/x.chart")).is_equal("")
	assert_str(ZipExtractor.safe_rel("a/../../evil")).is_equal("")
	assert_str(ZipExtractor.safe_rel("..\\evil.chart")).is_equal("")
	assert_str(ZipExtractor.safe_rel("a\\..\\..\\evil")).is_equal("")
	assert_str(ZipExtractor.safe_rel("folder/notes.chart")).is_equal("folder/notes.chart")
	assert_str(ZipExtractor.safe_rel("folder\\notes.chart")).is_equal("folder/notes.chart")


func test_extract_nested_and_allow_list() -> void:
	var z := D + "/ok.zip"
	SongFixture.make_zip(z, {
		"Song/notes.chart": SongFixture.CHART,
		"Song/song.ini": SongFixture.INI,
		"Song/song.wav": "RIFFxxxxWAVE",
		"Song/readme.exe": "nope",
		"Song/album.png": "png",
	})
	var before := SongFixture.read_bytes(z)
	var r := ZipExtractor.extract(z, D + "/out")
	assert_bool(r["ok"]).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/Song/notes.chart")).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/Song/song.ini")).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/Song/readme.exe")).is_false()
	# Album art is kept (D-11 / D-19 superseded): png, jpg and jpeg.
	assert_bool(FileAccess.file_exists(D + "/out/Song/album.png")).is_true()
	assert_array(SongFixture.read_bytes(z)).is_equal(before)


func test_extract_keeps_images_with_size_cap() -> void:
	var z := D + "/art.zip"
	SongFixture.make_zip(z, {
		"Song/notes.chart": SongFixture.CHART,
		"Song/album.jpg": "jpgjpg",
		"Song/other.JPEG": "jpegjpeg",
		"Song/big.png": "0123456789",
		"../album.png": "evil",
		"Song/../../album.jpg": "evil",
	})
	assert_bool(ZipExtractor.ALLOWED_EXTS.has("png")).is_true()
	assert_bool(ZipExtractor.ALLOWED_EXTS.has("jpg")).is_true()
	assert_bool(ZipExtractor.ALLOWED_EXTS.has("jpeg")).is_true()
	assert_int(ZipExtractor.MAX_IMAGE_BYTES).is_equal(8 * 1024 * 1024)
	var r := ZipExtractor.extract(z, D + "/out/inner", {"max_image": 8})
	assert_bool(r["ok"]).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/inner/Song/notes.chart")).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/inner/Song/album.jpg")).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/inner/Song/other.JPEG")).is_true()
	# Over the per-image cap: skipped, the song itself still extracts.
	assert_bool(FileAccess.file_exists(D + "/out/inner/Song/big.png")).is_false()
	# Traversal names are still refused for images.
	assert_bool(FileAccess.file_exists(D + "/out/album.png")).is_false()
	assert_bool(FileAccess.file_exists(D + "/album.jpg")).is_false()
	assert_bool(FileAccess.file_exists(D + "/out/album.jpg")).is_false()


func test_old_zip_cache_marker_reextracts_once() -> void:
	var lib := D + "/lib"
	var src := D + "/src"
	SongFixture.make_song(src)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.save_png(src + "/album.png")
	SongFixture.zip_folder(src, lib + "/pack.zip")
	var old_root := SongScanner.zip_cache_root
	SongScanner.zip_cache_root = D + "/zipcache"
	var roots := [{"path": lib, "source": "test", "library_name": "Lib"}]
	var first := SongScanner.new().scan_sync(roots, null)
	assert_str(first[0].status).is_equal("ok")
	# The entry's own extraction folder (not a directory count: another suite's background
	# library scan may still be unpacking into the shared static zip_cache_root).
	var dest: String = first[0].chart_path.get_base_dir()
	assert_str(dest.get_base_dir()).is_equal(D + "/zipcache")
	assert_str(FileAccess.get_file_as_string(dest + "/.done")).is_equal(SongScanner.EXTRACT_VERSION)
	assert_bool(FileAccess.file_exists(dest + "/album.png")).is_true()
	# Simulate a cache written by the old extractor: "ok" marker, images dropped.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dest + "/album.png"))
	SongFixture.write_text(dest + "/.done", "ok")
	SongScanner.new().scan_sync(roots, null)
	assert_bool(FileAccess.file_exists(dest + "/album.png")).is_true()
	assert_str(FileAccess.get_file_as_string(dest + "/.done")).is_equal(SongScanner.EXTRACT_VERSION)
	# Current marker: no re-extract (a file removed from the cache stays removed).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dest + "/album.png"))
	SongScanner.new().scan_sync(roots, null)
	assert_bool(FileAccess.file_exists(dest + "/album.png")).is_false()
	SongScanner.zip_cache_root = old_root


func test_extract_zip_slip_writes_nothing_outside() -> void:
	var z := D + "/evil.zip"
	SongFixture.make_zip(z, {
		"../evil.chart": "x",
		"C:/x.chart": "x",
		"/abs.chart": "x",
		"..\\back.chart": "x",
		"fine/notes.chart": "ok",
	})
	var r := ZipExtractor.extract(z, D + "/out/inner")
	assert_bool(r["ok"]).is_true()
	assert_bool(FileAccess.file_exists(D + "/out/evil.chart")).is_false()
	assert_bool(FileAccess.file_exists(D + "/evil.chart")).is_false()
	assert_bool(FileAccess.file_exists(D + "/out/back.chart")).is_false()
	assert_bool(FileAccess.file_exists("user://abs.chart")).is_false()
	assert_bool(FileAccess.file_exists(D + "/out/inner/fine/notes.chart")).is_true()
	assert_int(DirAccess.get_files_at(ProjectSettings.globalize_path(D + "/out")).size()).is_equal(0)


func test_extract_caps() -> void:
	var z := D + "/many.zip"
	var entries := {}
	for i in 12:
		entries["f%d.chart" % i] = "x"
	SongFixture.make_zip(z, entries)
	var r := ZipExtractor.extract(z, D + "/o1", {"max_entries": 10})
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(SongEntry.ERR_ZIP)
	var big := D + "/big.zip"
	SongFixture.make_zip(big, {"a.chart": "0123456789", "b.chart": "0123456789"})
	assert_bool(ZipExtractor.extract(big, D + "/o2", {"max_entry": 5})["ok"]).is_false()
	assert_bool(ZipExtractor.extract(big, D + "/o3", {"max_total": 15})["ok"]).is_false()
	assert_bool(FileAccess.file_exists(D + "/o2/a.chart")).is_false()
	assert_bool(ZipExtractor.extract(big, D + "/o4")["ok"]).is_true()


func test_extract_real_entry_cap() -> void:
	# Default cap: 4,000 entries; 4,001 tiny files must be refused.
	var z := D + "/huge.zip"
	var entries := {}
	for i in 4001:
		entries["f%d.chart" % i] = "x"
	SongFixture.make_zip(z, entries)
	assert_bool(ZipExtractor.extract(z, D + "/o")["ok"]).is_false()


func test_extract_corrupt() -> void:
	SongFixture.write_bytes(D + "/bad.zip", SongFixture.garbage_bytes())
	var r := ZipExtractor.extract(D + "/bad.zip", D + "/o")
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(SongEntry.ERR_ZIP)
	assert_bool(ZipExtractor.extract(D + "/nope.zip", D + "/o")["ok"]).is_false()


# ---- SongEntry ----

func _entry() -> SongEntry:
	var e := SongEntry.new()
	e.id = "C:/songs/a"
	e.path = "C:/songs/a"
	e.title = "T"
	e.artist = "A"
	e.length_sec = 12.5
	e.bpm_min = 100.0
	e.bpm_max = 140.0
	e.preview_start_ms = 1500
	e.difficulties = [{"name": "expert", "note_count": 8, "fingerprint": "u1.abc.x"}]
	e.audio_files = ["C:/songs/a/song.wav"]
	e.signature = "sig"
	return e


func test_entry_round_trip() -> void:
	var e := _entry()
	var back := SongEntry.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert_object(back).is_not_null()
	assert_str(back.id).is_equal(e.id)
	assert_float(back.length_sec).is_equal_approx(12.5, 0.001)
	assert_int(back.preview_start_ms).is_equal(1500)
	assert_int(back.difficulties.size()).is_equal(1)
	assert_str(back.difficulties[0]["fingerprint"]).is_equal("u1.abc.x")
	assert_array(back.audio_files).contains_exactly(["C:/songs/a/song.wav"])


func test_entry_rejects_bad_data() -> void:
	assert_object(SongEntry.from_dict("x")).is_null()
	var d := _entry().to_dict()
	d["length_sec"] = -1.0
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["length_sec"] = NAN
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["title"] = 5
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["title"] = "x".repeat(2000)
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["status"] = "weird"
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["difficulties"] = [{"name": 1, "note_count": 2, "fingerprint": "x"}]
	assert_object(SongEntry.from_dict(d)).is_null()
	d = _entry().to_dict()
	d["audio_files"] = [5]
	assert_object(SongEntry.from_dict(d)).is_null()


func test_hints_cover_all_errors() -> void:
	for err in [SongEntry.ERR_OPUS, SongEntry.ERR_NO_GUITAR, SongEntry.ERR_AUDIO_MISSING,
			SongEntry.ERR_MIDI, SongEntry.ERR_UNSUPPORTED_AUDIO, SongEntry.ERR_AUDIO_BAD,
			SongEntry.ERR_ZIP, SongEntry.ERR_TOO_LARGE, SongEntry.err_unreadable(42),
			SongEntry.ERR_MIDI_BAD, SongEntry.ERR_MIDI_NO_GUITAR]:
		assert_bool(SongEntry.hint_for(err) != "").is_true()
	assert_str(SongEntry.ERR_MIDI_BAD).is_equal("Unreadable .mid")
	assert_str(SongEntry.ERR_MIDI_NO_GUITAR).is_equal("No guitar part in .mid")
	assert_str(SongEntry.err_unreadable(7)).is_equal("Unreadable .chart (line 7)")
	assert_str(SongEntry.hint_for(SongEntry.err_unreadable(7))).contains("near line 7")
	assert_str(SongEntry.hint_for("whatever")).is_equal("")


# ---- SongCache ----

func test_cache_round_trip_and_signature() -> void:
	var p := D + "/cache.json"
	var c := SongCache.new(p)
	c.put(_entry())
	assert_int(c.save()).is_equal(OK)
	assert_bool(FileAccess.file_exists(p + ".tmp")).is_false()
	var d := SongCache.new(p)
	d.load()
	assert_object(d.lookup("C:/songs/a", "sig")).is_not_null()
	assert_object(d.lookup("C:/songs/a", "other")).is_null()
	assert_object(d.lookup("C:/songs/zzz", "sig")).is_null()


func test_cache_discards_bad_files() -> void:
	var p := D + "/cache.json"
	var good := {"v": 1, "importer": ChartImporter.IMPORTER_VERSION,
			"mapping": ChartImporter.MAPPING_VERSION, "entries": [_entry().to_dict()]}
	var bad_entry := _entry().to_dict()
	bad_entry["bpm_max"] = "x"
	var cases: Array = [
		"not json",
		"[1,2]",
		JSON.stringify({"v": 2, "importer": 1, "mapping": 1, "entries": []}),
		JSON.stringify({"v": 1, "importer": 999, "mapping": 1, "entries": []}),
		JSON.stringify({"v": 1, "importer": 1, "mapping": 999, "entries": []}),
		JSON.stringify({"v": 1, "importer": ChartImporter.IMPORTER_VERSION,
				"mapping": ChartImporter.MAPPING_VERSION, "entries": "x"}),
		JSON.stringify({"v": 1, "importer": ChartImporter.IMPORTER_VERSION,
				"mapping": ChartImporter.MAPPING_VERSION, "entries": [good["entries"][0], bad_entry]}),
	]
	for text in cases:
		SongFixture.write_text(p, text)
		var c := SongCache.new(p)
		c.load()
		assert_int(c.entries.size()).is_equal(0)
	SongFixture.write_text(p, JSON.stringify(good))
	var ok := SongCache.new(p)
	ok.load()
	assert_int(ok.entries.size()).is_equal(1)
	assert_object(SongCache.new(D + "/missing.json").lookup("a", "b")).is_null()
