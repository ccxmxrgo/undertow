extends GdUnitTestSuite
## Solo extraction (SONG-07, D-17). Counts lane-notes in [start, end] inclusive.

const DIR := "res://tests/fixtures/charts/"


func _load(name: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes(DIR + name))


func _inline(body: String, events: String = "") -> ParsedChart:
	var txt := "[Song]\n{\n  Resolution = 192\n}\n[SyncTrack]\n{\n  0 = B 120000\n}\n[Events]\n{\n%s}\n[ExpertSingle]\n{\n%s}\n" % [events, body]
	return ChartParser.parse_bytes(txt.to_utf8_buffer())


func test_track_pair_is_inclusive_and_counts_chords() -> void:
	var c := ChartImporter.build(_load("solo_track.chart"), "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_float(c.solos[0]["start"]).is_equal_approx(1.0, 0.0001)
	assert_float(c.solos[0]["end"]).is_equal_approx(2.0, 0.0001)
	# 384 (1) + 576 (3-lane chord) + 768 (soloend tick, included) = 5
	assert_int(c.solos[0]["note_count"]).is_equal(5)


func test_track_without_markers_has_no_solo_even_if_other_track_has() -> void:
	var c := ChartImporter.build(_load("solo_track.chart"), "hard")
	assert_array(c.solos).is_empty()


func test_global_fallback() -> void:
	var c := ChartImporter.build(_load("solo_global.chart"), "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_float(c.solos[0]["start"]).is_equal_approx(1.0, 0.0001)
	assert_float(c.solos[0]["end"]).is_equal_approx(2.0, 0.0001)
	assert_int(c.solos[0]["note_count"]).is_equal(3)


func test_soloend_tick_note_counts() -> void:
	var c := ChartImporter.build(_load("solo_inclusive.chart"), "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_int(c.solos[0]["note_count"]).is_equal(4)  # 192 (1) + 384 (3 lanes)


func test_no_markers_means_no_solos() -> void:
	assert_array(ChartImporter.build(_load("minimal.chart"), "expert").solos).is_empty()


func test_unmatched_soloend_ignored() -> void:
	var pc := _inline("  0 = N 0 0\n  192 = E soloend\n  384 = N 1 0\n")
	assert_array(ChartImporter.build(pc, "expert").solos).is_empty()


func test_nested_solo_ignored() -> void:
	var pc := _inline("  0 = E solo\n  0 = N 0 0\n  192 = E solo\n  192 = N 1 0\n  384 = E soloend\n  384 = N 2 0\n")
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_float(c.solos[0]["start"]).is_equal(0.0)
	assert_float(c.solos[0]["end"]).is_equal_approx(1.0, 0.0001)
	assert_int(c.solos[0]["note_count"]).is_equal(3)


func test_missing_soloend_ends_at_last_note() -> void:
	var pc := _inline("  192 = E solo\n  192 = N 0 0\n  384 = N 1 0\n  576 = N 2 0\n")
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_float(c.solos[0]["end"]).is_equal_approx(1.5, 0.0001)
	assert_int(c.solos[0]["note_count"]).is_equal(3)


func test_two_solos_kept_in_order() -> void:
	var body := "  0 = E solo\n  0 = N 0 0\n  192 = E soloend\n  192 = N 1 0\n  768 = E solo\n  768 = N 2 0\n  960 = N 3 0\n  960 = E soloend\n"
	var c := ChartImporter.build(_inline(body), "expert")
	assert_int(c.solos.size()).is_equal(2)
	assert_float(c.solos[0]["start"]).is_less(c.solos[1]["start"])
	assert_int(c.solos[0]["note_count"]).is_equal(2)
	assert_int(c.solos[1]["note_count"]).is_equal(2)


func test_solo_times_include_delay() -> void:
	var c := ChartImporter.build(_load("solo_track.chart"), "expert", 100)
	assert_float(c.solos[0]["start"]).is_equal_approx(1.1, 0.0001)
	assert_float(c.solos[0]["end"]).is_equal_approx(2.1, 0.0001)
	assert_int(c.solos[0]["note_count"]).is_equal(5)


func test_global_events_with_quotes_in_events_section() -> void:
	var pc := _inline("  0 = N 0 0\n  192 = N 1 0\n", "  0 = E \"solo\"\n  192 = E \"soloend\"\n")
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.solos.size()).is_equal(1)
	assert_int(c.solos[0]["note_count"]).is_equal(2)
