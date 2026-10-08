extends GdUnitTestSuite
## Song fingerprint (SONG-05, D-15) plus an end-to-end import of a community-style chart.

const DIR := "res://tests/fixtures/charts/"

const BASE := "[Song]\n{\n  Name = \"A\"\n  Resolution = 192\n}\n[SyncTrack]\n{\n  0 = TS 4\n  0 = B 120000\n}\n[Events]\n{\n  0 = E \"section Intro\"\n}\n[ExpertSingle]\n{\n  0 = N 0 0\n  192 = N 1 96\n  384 = N 2 0\n  384 = N 3 0\n}\n"


func _fx(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(DIR + name)


func _fp_text(text: String, diff: String = "expert", delay: int = 0, dur: float = 100.0, versions: Dictionary = {}) -> String:
	return _fp(text.to_utf8_buffer(), diff, delay, dur, versions)


func _fp(bytes: PackedByteArray, diff: String = "expert", delay: int = 0, dur: float = 100.0, versions: Dictionary = {}) -> String:
	var pc := ChartParser.parse_bytes(bytes)
	var c := ChartImporter.build(pc, diff, delay)
	return ChartImporter.fingerprint(c, diff, dur, versions)


func test_format() -> void:
	var f := _fp_text(BASE)
	var re := RegEx.new()
	re.compile("^u1\\.[0-9a-f]{24}\\.x$")
	assert_bool(re.search(f) != null).is_true()
	assert_bool(f.length() <= 31).is_true()
	assert_str(ScoreStore.sanitize_id(f)).is_equal(f)
	for pair in [["easy", "e"], ["medium", "m"], ["hard", "h"], ["expert", "x"]]:
		assert_bool(_fp_text(BASE, pair[0]).ends_with("." + pair[1])).is_true()


func test_stable_under_resave_and_reorder() -> void:
	var base := _fp_text(BASE)
	# CRLF + BOM + trailing whitespace + comments
	var resaved := "// c\r\n" + BASE.replace("\n", "  \r\n")
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF])
	bytes.append_array(resaved.to_utf8_buffer())
	assert_str(_fp(bytes)).is_equal(base)
	# reordered track events
	var reordered := BASE.replace("  0 = N 0 0\n  192 = N 1 96\n  384 = N 2 0\n  384 = N 3 0\n", "  384 = N 3 0\n  384 = N 2 0\n  192 = N 1 96\n  0 = N 0 0\n")
	assert_str(_fp_text(reordered)).is_equal(base)
	# unknown sections, forced/tap markers, metadata changes
	var noisy := BASE.replace("Name = \"A\"", "Name = \"Totally different\"\n  Artist = \"X\"") + "[ExpertDrums]\n{\n  0 = N 0 0\n}\n[Whatever]\n{\n  x = y\n}\n"
	noisy = noisy.replace("  0 = N 0 0\n  192", "  0 = N 0 0\n  0 = N 5 0\n  0 = N 6 0\n  192")
	assert_str(_fp_text(noisy)).is_equal(base)


func test_changes_with_one_note() -> void:
	var base := _fp_text(BASE)
	assert_str(_fp_text(BASE.replace("384 = N 3 0", "385 = N 3 0"))).is_not_equal(base)
	assert_str(_fp_text(BASE.replace("384 = N 3 0", "384 = N 0 0"))).is_not_equal(base)
	assert_str(_fp_text(BASE.replace("384 = N 3 0\n", "384 = N 3 0\n  576 = N 0 0\n"))).is_not_equal(base)


func test_one_millisecond_matters() -> void:
	var pc := ChartParser.parse_bytes(BASE.to_utf8_buffer())
	var a := ChartImporter.build(pc, "expert")
	var b := ChartImporter.build(pc, "expert")
	b.notes[1]["time"] += 0.001
	assert_str(ChartImporter.fingerprint(a, "expert", 100.0)).is_not_equal(ChartImporter.fingerprint(b, "expert", 100.0))


func test_changes_with_difficulty_duration_delay_versions() -> void:
	var pc := ChartParser.parse_bytes(BASE.to_utf8_buffer())
	var c := ChartImporter.build(pc, "expert")
	var base := ChartImporter.fingerprint(c, "expert", 100.0)
	assert_str(ChartImporter.fingerprint(c, "hard", 100.0)).is_not_equal(base)
	assert_str(ChartImporter.fingerprint(c, "expert", 100.1)).is_not_equal(base)
	assert_str(ChartImporter.fingerprint(c, "expert", 100.04)).is_equal(base)  # 0.1 s buckets
	assert_str(_fp_text(BASE, "expert", 5)).is_not_equal(_fp_text(BASE, "expert", 0))
	assert_str(ChartImporter.fingerprint(c, "expert", 100.0, {"mapping": ChartImporter.MAPPING_VERSION + 1})).is_not_equal(base)
	var imp := ChartImporter.fingerprint(c, "expert", 100.0, {"importer": ChartImporter.IMPORTER_VERSION + 1})
	assert_str(imp).is_not_equal(base)
	assert_bool(imp.begins_with("u2.")).is_true()
	assert_str(ChartImporter.fingerprint(c, "expert", 100.0, {})).is_equal(base)


func test_deterministic_across_runs() -> void:
	assert_str(_fp_text(BASE)).is_equal(_fp_text(BASE))
	assert_str(_fp(_fx("community_style.chart"))).is_equal(_fp(_fx("community_style.chart")))


func test_community_style_import() -> void:
	var pc := ChartParser.parse_bytes(_fx("community_style.chart"))
	assert_bool(pc.ok).is_true()
	assert_array(ChartImporter.difficulties(pc)).is_equal(["hard", "expert"])
	var c := ChartImporter.build(pc, "expert")
	assert_str(c.title).is_equal("Community Style")
	assert_str(c.artist).is_equal("Some Band")
	# 23 N entries minus: forced/tap (2) -> gems; blue+orange merge (-1); open (+1); chord 2880 counted as 2 lanes
	# lane notes: 768,960,1152,1344,1536(B+O merged=1),1728,1920,2112,2304,2496,2688(open=2),2880(2),3072,3264,4608,4800
	assert_int(c.notes.size()).is_equal(18)
	assert_int(c.solos.size()).is_equal(1)
	# solo ticks 1920..3072: 1920,2112,2304,2496,2688(2),2880(2),3072 = 9
	assert_int(c.solos[0]["note_count"]).is_equal(9)
	assert_bool(c.tempo_map.size() >= 4).is_true()
	var hard := ChartImporter.build(pc, "hard")
	assert_int(hard.notes.size()).is_equal(3)
	assert_array(hard.solos).is_empty()
	var f := ChartImporter.fingerprint(c, "expert", 60.0)
	assert_str(ScoreStore.sanitize_id(f)).is_equal(f)
