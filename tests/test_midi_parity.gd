extends GdUnitTestSuite
## .mid vs .chart parity (CONT-01, README "tested to within 1 ms"): the same song written both ways
## must import to identical charts, and long odd-tempo .mid timing must match an integer-first oracle.

const DELAY := 137
const DIFFS := ["easy", "medium", "hard", "expert"]


func _mid_chart(demo: Dictionary, diff: String, delay: int = DELAY) -> ChartData:
	return ChartImporter.build(MidiChartReader.parse_bytes(demo["mid"]), diff, delay)


func _txt_chart(demo: Dictionary, diff: String, delay: int = DELAY) -> ChartData:
	return ChartImporter.build(ChartParser.parse_bytes((demo["chart"] as String).to_utf8_buffer()), diff, delay)


func test_demo_song_is_deterministic() -> void:
	var a := MidiWriter.demo_song()
	var b := MidiWriter.demo_song()
	assert_bool(a["mid"] == b["mid"]).is_true()
	assert_str(a["chart"]).is_equal(b["chart"])


func test_notes_agree_within_a_millisecond() -> void:
	var demo := MidiWriter.demo_song()
	for d in DIFFS:
		var m := _mid_chart(demo, d)
		var c := _txt_chart(demo, d)
		assert_int(m.notes.size()).is_equal(c.notes.size())
		assert_bool(c.notes.size() > 0).is_true()
		for i in c.notes.size():
			assert_int(m.notes[i]["lane"]).is_equal(c.notes[i]["lane"])
			assert_bool(absf(m.notes[i]["time"] - c.notes[i]["time"]) < 0.001).is_true()
			assert_bool(absf(m.notes[i]["duration"] - c.notes[i]["duration"]) < 0.001).is_true()


func test_sections_solos_timesigs_tempo_agree() -> void:
	var demo := MidiWriter.demo_song()
	for d in DIFFS:
		var m := _mid_chart(demo, d)
		var c := _txt_chart(demo, d)
		assert_int(m.tempo_map.size()).is_equal(c.tempo_map.size())
		assert_int(m.sections.size()).is_equal(3)
		assert_int(m.sections.size()).is_equal(c.sections.size())
		for i in c.sections.size():
			assert_str(m.sections[i]["name"]).is_equal(c.sections[i]["name"])
			assert_bool(absf(m.sections[i]["time"] - c.sections[i]["time"]) < 0.001).is_true()
		assert_int(m.solos.size()).is_equal(2)
		assert_int(m.solos.size()).is_equal(c.solos.size())
		for i in c.solos.size():
			assert_bool(absf(m.solos[i]["start"] - c.solos[i]["start"]) < 0.001).is_true()
			assert_bool(absf(m.solos[i]["end"] - c.solos[i]["end"]) < 0.001).is_true()
			assert_int(m.solos[i]["note_count"]).is_equal(c.solos[i]["note_count"])
		assert_int(m.time_sigs.size()).is_equal(c.time_sigs.size())
		for i in c.time_sigs.size():
			assert_int(m.time_sigs[i]["num"]).is_equal(c.time_sigs[i]["num"])
			assert_int(m.time_sigs[i]["den"]).is_equal(c.time_sigs[i]["den"])
			assert_bool(absf(m.time_sigs[i]["time"] - c.time_sigs[i]["time"]) < 0.001).is_true()


func test_fingerprints_identical() -> void:
	var demo := MidiWriter.demo_song()
	for d in DIFFS:
		var fm := ChartImporter.fingerprint(_mid_chart(demo, d), d, 120.0)
		var fc := ChartImporter.fingerprint(_txt_chart(demo, d), d, 120.0)
		assert_str(fm).is_equal(fc)


func test_long_odd_tempo_matches_integer_oracle() -> void:
	var song := MidiWriter.long_odd_tempo_song()
	var res: int = song["resolution"]
	var tempos: Array = song["tempos"]
	var ticks: Array = song["note_ticks"]
	var chart := ChartImporter.build(MidiChartReader.parse_bytes(song["mid"]), "expert", 0)
	assert_int(chart.notes.size()).is_equal(ticks.size())
	for i in ticks.size():
		var tick: int = ticks[i]
		# integer-first: sum(delta_ticks * uspqn) microseconds * res, divided once
		var total := 0
		for k in tempos.size():
			var start: int = tempos[k][0]
			if start >= tick:
				break
			var stop: int = tick
			if k + 1 < tempos.size():
				stop = mini(tick, int(tempos[k + 1][0]))
			total += (stop - start) * int(tempos[k][1])
		var expected := float(total) / (float(res) * 1000000.0)
		assert_bool(absf(chart.notes[i]["time"] - expected) < 0.001).is_true()
	assert_bool(chart.notes[chart.notes.size() - 1]["time"] > 600.0).is_true()
