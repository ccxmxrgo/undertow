extends GdUnitTestSuite
## ChartImporter: 5-to-4 mapping, tempo/delay seconds, sustain threshold (SONG-01, SONG-02).

const DIR := "res://tests/fixtures/charts/"


func _load(name: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes(DIR + name))


func _inline(body: String, sync: String = "  0 = B 120000\n") -> ParsedChart:
	var txt := "[Song]\n{\n  Resolution = 192\n}\n[SyncTrack]\n{\n%s}\n[ExpertSingle]\n{\n%s}\n" % [sync, body]
	return ChartParser.parse_bytes(txt.to_utf8_buffer())


func _at(chart: ChartData, time: float) -> Array:
	var out: Array = []
	for n in chart.notes:
		if absf(n["time"] - time) < 0.0005:
			out.append(n)
	return out


func _lanes(notes: Array) -> Array:
	var out: Array = []
	for n in notes:
		out.append(n["lane"])
	out.sort()
	return out


func test_frets_mapping() -> void:
	var pc := _load("frets_all.chart")
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.notes.size()).is_equal(15)
	assert_array(_lanes(_at(c, 0.0))).is_equal([0])
	assert_array(_lanes(_at(c, 0.5))).is_equal([1])
	assert_array(_lanes(_at(c, 1.0))).is_equal([2])
	assert_array(_lanes(_at(c, 1.5))).is_equal([3])
	assert_array(_lanes(_at(c, 2.0))).is_equal([3])  # orange -> lane 4


func test_blue_orange_merge_keeps_longest() -> void:
	var c := ChartImporter.build(_load("frets_all.chart"), "expert")
	var n := _at(c, 2.5)
	assert_int(n.size()).is_equal(1)
	assert_int(n[0]["lane"]).is_equal(3)
	assert_float(n[0]["duration"]).is_equal_approx(1.0, 0.0001)


func test_open_is_lane_2_3_chord_and_unions() -> void:
	var c := ChartImporter.build(_load("frets_all.chart"), "expert")
	assert_array(_lanes(_at(c, 3.0))).is_equal([1, 2])
	assert_array(_lanes(_at(c, 3.5))).is_equal([0, 1, 2])


func test_forced_and_tap_create_no_notes() -> void:
	var c := ChartImporter.build(_load("frets_all.chart"), "expert")
	assert_array(_lanes(_at(c, 4.0))).is_equal([0])


func test_same_lane_duplicates_keep_longest() -> void:
	var c := ChartImporter.build(_load("frets_all.chart"), "expert")
	var n := _at(c, 4.5)
	assert_int(n.size()).is_equal(1)
	assert_float(n[0]["duration"]).is_equal_approx(0.5, 0.0001)


func test_sustain_threshold() -> void:
	var c := ChartImporter.build(_load("frets_all.chart"), "expert")
	var tap := _at(c, 5.0)
	assert_float(tap[0]["duration"]).is_equal(0.0)  # 48 * 4 <= 192
	var held := _at(c, 5.5)
	assert_float(held[0]["duration"]).is_equal_approx(49.0 / 192.0 * 0.5, 0.0001)  # 49 * 4 > 192


func test_tempo_change_and_sustain_across_it() -> void:
	var c := ChartImporter.build(_load("tempo_change.chart"), "expert")
	assert_int(c.notes.size()).is_equal(3)
	assert_float(c.notes[0]["time"]).is_equal(0.0)
	assert_float(c.notes[1]["time"]).is_equal_approx(1.5, 0.0001)
	# 576 -> 768 at 120 (0.5 s) + 768 -> 960 at 180 (1/3 s)
	assert_float(c.notes[1]["duration"]).is_equal_approx(0.5 + 1.0 / 3.0, 0.0001)
	assert_float(c.notes[2]["time"]).is_equal_approx(2.0 + 384.0 / 192.0 * 60.0 / 180.0, 0.0001)
	assert_int(c.tempo_map.size()).is_equal(2)
	assert_float(c.tempo_map[0]["time"]).is_equal(0.0)
	assert_float(c.tempo_map[0]["bpm"]).is_equal_approx(120.0, 0.0001)
	assert_float(c.tempo_map[1]["time"]).is_equal_approx(2.0, 0.0001)
	assert_float(c.tempo_map[1]["bpm"]).is_equal_approx(180.0, 0.0001)


func test_last_b_wins_and_default_tempo() -> void:
	var pc := _inline("  192 = N 0 0\n", "  0 = B 60000\n  0 = B 120000\n")
	assert_float(ChartImporter.build(pc, "expert").notes[0]["time"]).is_equal_approx(0.5, 0.0001)
	var none := _inline("  192 = N 0 0\n", "")
	var c := ChartImporter.build(none, "expert")
	assert_float(c.notes[0]["time"]).is_equal_approx(0.5, 0.0001)  # default 120
	assert_float(c.tempo_map[0]["bpm"]).is_equal_approx(120.0, 0.0001)


func test_time_signature_does_not_change_seconds() -> void:
	var a := _inline("  384 = N 0 0\n", "  0 = B 120000\n")
	var b := _inline("  384 = N 0 0\n", "  0 = TS 7 3\n  0 = B 120000\n")
	assert_float(ChartImporter.build(a, "expert").notes[0]["time"]).is_equal(ChartImporter.build(b, "expert").notes[0]["time"])


func test_bpm_clamped() -> void:
	var pc := _inline("  0 = N 0 0\n", "  0 = B 5000000\n")
	assert_float(ChartImporter.build(pc, "expert").tempo_map[0]["bpm"]).is_equal(2000.0)


func test_delay_shifts_times() -> void:
	var pc := _load("tempo_change.chart")
	var c := ChartImporter.build(pc, "expert", 250)
	assert_float(c.notes[0]["time"]).is_equal_approx(0.25, 0.0001)
	assert_float(c.tempo_map[0]["time"]).is_equal_approx(0.25, 0.0001)
	assert_float(c.tempo_map[1]["time"]).is_equal_approx(2.25, 0.0001)
	assert_int(int(c.meta["delay_ms"])).is_equal(250)


func test_negative_delay_drops_notes_without_assert() -> void:
	var pc := _load("minimal.chart")  # notes at 0.0, 0.5, 1.0 s
	var c := ChartImporter.build(pc, "expert", -1000)
	assert_int(c.notes.size()).is_equal(1)
	assert_float(c.notes[0]["time"]).is_equal(0.0)
	assert_int(int(c.meta["warnings"])).is_equal(2)
	assert_float(c.tempo_map[0]["time"]).is_equal(0.0)
	var c2 := ChartImporter.build(pc, "expert", -500)
	assert_int(c2.notes.size()).is_equal(2)
	for n in ChartImporter.build(pc, "expert", -100000).notes:
		assert_bool(is_finite(n["time"]) and n["time"] >= 0.0).is_true()


func test_difficulties_listing() -> void:
	assert_array(ChartImporter.difficulties(_load("frets_all.chart"))).is_equal(["hard", "expert"])
	assert_array(ChartImporter.difficulties(_load("no_guitar.chart"))).is_empty()
	assert_array(ChartImporter.difficulties(_load("garbage.chart"))).is_empty()


func test_meta_and_fields() -> void:
	var c := ChartImporter.build(_load("minimal.chart"), "expert")
	assert_int(int(c.meta["mapping_version"])).is_equal(ChartImporter.MAPPING_VERSION)
	assert_int(int(c.meta["importer_version"])).is_equal(ChartImporter.IMPORTER_VERSION)
	assert_str(c.difficulty).is_equal("expert")
	assert_str(c.title).is_equal("Minimal")
	assert_str(c.artist).is_equal("Tester")
	assert_str(c.id).is_equal("")
	assert_array(c.solos).is_empty()


func test_hostile_fixture_imports_safely() -> void:
	var c := ChartImporter.build(_load("hostile.chart"), "expert")
	assert_int(c.notes.size()).is_equal(1)
	assert_bool(c.notes[0]["time"] >= 0.0).is_true()
