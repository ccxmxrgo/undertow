extends GdUnitTestSuite
## MidiChartReader: Clone Hero .mid semantics (CONT-01, SONG-07; D-02..D-06, D-10).
## All .mid bytes come from MidiWriter; nothing is committed as a fixture.

const NO_GUITAR := "No guitar part in .mid"
const BAD := "Unreadable .mid"


func _e(tick: int, bytes: PackedByteArray) -> Dictionary:
	return MidiWriter.ev(tick, bytes)


func _tempo_track(extra: Array = []) -> PackedByteArray:
	var ev: Array = [_e(0, MidiWriter.tempo(500000)), _e(0, MidiWriter.ts(4, 2))]
	ev.append_array(extra)
	return MidiWriter.track(ev)


## notes: [[pitch, on_tick, off_tick], ...]
func _part(track_name: String, notes: Array, extra: Array = []) -> PackedByteArray:
	var ev: Array = [_e(0, MidiWriter.name(track_name))]
	for n in notes:
		ev.append(_e(n[1], MidiWriter.on(n[0])))
		ev.append(_e(n[2], MidiWriter.off(n[0])))
	ev.append_array(extra)
	return MidiWriter.track(ev)


func _mid(tracks: Array, division: int = 480) -> PackedByteArray:
	return MidiWriter.file([_tempo_track()] + tracks, division)


func _gems(pc: ParsedChart, diff: String) -> Array:
	var out: Array = []
	for e in pc.tracks.get(diff, []):
		if e["type"] == "N":
			out.append([e["tick"], e["a"], e["b"]])
	return out


func _frets(pc: ParsedChart, diff: String) -> Array:
	var out: Array = []
	for g in _gems(pc, diff):
		out.append(g[1])
	return out


func test_track_choice_first_candidate_with_gems() -> void:
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART BASS", [[96, 0, 100]])]))
	assert_bool(pc.ok).is_true()
	assert_int(_gems(pc, "ExpertSingle").size()).is_equal(1)
	# empty PART GUITAR is skipped for PART RHYTHM
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", []), _part("PART RHYTHM", [[97, 0, 100]])]))
	assert_array(_frets(pc, "ExpertSingle")).is_equal([1])
	# T1 GEMS beats PART GUITAR COOP, whatever the file order
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR COOP", [[96, 0, 100]]), _part("T1 GEMS", [[98, 0, 100]])]))
	assert_array(_frets(pc, "ExpertSingle")).is_equal([2])
	# case-insensitive
	pc = MidiChartReader.parse_bytes(_mid([_part("part guitar", [[99, 0, 100]])]))
	assert_array(_frets(pc, "ExpertSingle")).is_equal([3])


func test_no_guitar_part() -> void:
	var tracks := [_part("PART DRUMS", [[96, 0, 100]]), _part("PART VOCALS", [[96, 0, 100]]),
			_part("PART GUITAR GHL", [[96, 0, 100]]), _part("PART KEYS", [[96, 0, 100]])]
	var pc := MidiChartReader.parse_bytes(_mid(tracks))
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).is_equal(NO_GUITAR)
	# format 0: a single track, never a candidate
	var f0 := MidiWriter.file([_part("PART GUITAR", [[96, 0, 100]])], 480, 0)
	pc = MidiChartReader.parse_bytes(f0)
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).is_equal(NO_GUITAR)


func test_difficulties_never_mixed_across_tracks() -> void:
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", [[96, 0, 100]]), _part("PART BASS", [[60, 0, 100]])]))
	assert_bool(pc.tracks.has("ExpertSingle")).is_true()
	assert_bool(pc.tracks.has("EasySingle")).is_false()
	assert_array(ChartImporter.difficulties(pc)).is_equal(["expert"])


func test_pitch_ranges_per_difficulty() -> void:
	var notes: Array = []
	var t := 0
	for base in [60, 72, 84, 96]:
		for k in 5:
			notes.append([base + k, t, t + 100])
			t += 480
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes)]))
	for d in ["EasySingle", "MediumSingle", "HardSingle", "ExpertSingle"]:
		assert_array(_frets(pc, d)).is_equal([0, 1, 2, 3, 4])
	assert_array(ChartImporter.difficulties(pc)).is_equal(["easy", "medium", "hard", "expert"])


func test_non_gem_pitches_create_nothing() -> void:
	var notes: Array = []
	var t := 0
	for p in [65, 66, 77, 78, 89, 90, 101, 102, 104, 105, 106, 116, 120, 127]:
		notes.append([p, t, t + 100])
		t += 480
	notes.append([96, t, t + 100])
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes)]))
	assert_bool(pc.ok).is_true()
	assert_int(_gems(pc, "ExpertSingle").size()).is_equal(1)
	assert_array(ChartImporter.difficulties(pc)).is_equal(["expert"])


func test_enhanced_opens() -> void:
	var notes := [[96, 0, 100], [95, 480, 580], [83, 960, 1060], [71, 1440, 1540], [59, 1920, 2020]]
	for tag in ["[ENHANCED_OPENS]", "ENHANCED_OPENS"]:
		var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes, [_e(0, MidiWriter.text(tag))])]))
		assert_array(_frets(pc, "ExpertSingle")).is_equal([0, 7])
		assert_array(_frets(pc, "HardSingle")).is_equal([7])
		assert_array(_frets(pc, "MediumSingle")).is_equal([7])
		assert_array(_frets(pc, "EasySingle")).is_equal([7])
	var plain := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes)]))
	assert_array(_frets(plain, "ExpertSingle")).is_equal([0])
	assert_bool(plain.tracks.has("HardSingle")).is_false()


func test_ps_open_sysex() -> void:
	var notes := [[96, 480, 540], [97, 720, 780], [98, 960, 1020]]
	var extra := [_e(480, MidiWriter.ps_open(3, true)), _e(960, MidiWriter.ps_open(3, false))]
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes, extra)]))
	assert_array(_frets(pc, "ExpertSingle")).is_equal([7, 7, 2])
	# diff 0xFF applies to every difficulty
	var multi := [[60, 0, 60], [72, 0, 60], [84, 0, 60], [96, 0, 60]]
	var all_ev := [_e(0, MidiWriter.ps_open(0xFF, true)), _e(120, MidiWriter.ps_open(0xFF, false))]
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", multi, all_ev)]))
	for d in ["EasySingle", "MediumSingle", "HardSingle", "ExpertSingle"]:
		assert_array(_frets(pc, d)).is_equal([7])
	# other difficulty is untouched
	var only_easy := [_e(0, MidiWriter.ps_open(0, true)), _e(120, MidiWriter.ps_open(0, false))]
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", multi, only_easy)]))
	assert_array(_frets(pc, "EasySingle")).is_equal([7])
	assert_array(_frets(pc, "ExpertSingle")).is_equal([0])


func test_sustain_cutoff() -> void:
	var notes := [[96, 0, 120], [97, 1000, 1159], [98, 2000, 2160], [99, 3000, 3161]]
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes)]))
	var g := _gems(pc, "ExpertSingle")
	assert_int(g[0][2]).is_equal(0)
	assert_int(g[1][2]).is_equal(0)
	assert_int(g[2][2]).is_equal(160)
	assert_int(g[3][2]).is_equal(161)
	var c := ChartImporter.build(pc, "expert")
	assert_float(c.notes[2]["duration"]).is_greater(0.0)
	assert_float(c.notes[1]["duration"]).is_equal(0.0)


func test_pairing_back_to_back_and_orders() -> void:
	var a := MidiWriter.track([_e(0, MidiWriter.name("PART GUITAR")), _e(0, MidiWriter.on(96)), _e(480, MidiWriter.off(96)),
			_e(480, MidiWriter.on(96)), _e(960, MidiWriter.off(96))])
	var b := MidiWriter.track([_e(0, MidiWriter.name("PART GUITAR")), _e(0, MidiWriter.on(96)), _e(480, MidiWriter.on(96)),
			_e(480, MidiWriter.off(96)), _e(960, MidiWriter.off(96))])
	var ga := _gems(MidiChartReader.parse_bytes(_mid([a])), "ExpertSingle")
	var gb := _gems(MidiChartReader.parse_bytes(_mid([b])), "ExpertSingle")
	assert_array(ga).is_equal([[0, 0, 480], [480, 0, 480]])
	assert_array(gb).is_equal(ga)


func test_pairing_zero_orphan_open_end() -> void:
	var z := _part("PART GUITAR", [[96, 100, 100]])
	var pc := MidiChartReader.parse_bytes(_mid([z]))
	assert_array(_gems(pc, "ExpertSingle")).is_equal([[100, 0, 0]])
	var orphan := MidiWriter.track([_e(0, MidiWriter.name("PART GUITAR")), _e(50, MidiWriter.off(97)),
			_e(100, MidiWriter.on(96)), _e(200, MidiWriter.off(96))])
	pc = MidiChartReader.parse_bytes(_mid([orphan]))
	assert_int(_gems(pc, "ExpertSingle").size()).is_equal(1)
	assert_int(pc.warnings).is_greater_equal(1)
	var unclosed := MidiWriter.track([_e(0, MidiWriter.name("PART GUITAR")), _e(100, MidiWriter.on(96))])
	pc = MidiChartReader.parse_bytes(_mid([unclosed]))
	assert_array(_gems(pc, "ExpertSingle")).is_equal([[100, 0, 0]])
	# output sorted by (tick, seq) even when written out of pitch order
	var chord := _part("PART GUITAR", [[98, 480, 600], [96, 0, 100], [97, 0, 100]])
	pc = MidiChartReader.parse_bytes(_mid([chord]))
	var prev_tick := -1
	for e in pc.tracks["ExpertSingle"]:
		assert_bool(e["tick"] >= prev_tick).is_true()
		prev_tick = e["tick"]


func test_tempo_and_time_signature() -> void:
	var t0 := MidiWriter.track([_e(0, MidiWriter.tempo(500000)), _e(0, MidiWriter.ts(4, 2)),
			_e(960, MidiWriter.tempo(461538)), _e(960, MidiWriter.ts(3, 3)), _e(1920, MidiWriter.tempo(0))])
	var other := _part("PART GUITAR", [[96, 0, 100]], [_e(10, MidiWriter.tempo(300000))])
	var pc := MidiChartReader.parse_bytes(MidiWriter.file([t0, other], 960))
	assert_bool(pc.ok).is_true()
	assert_int(pc.resolution).is_equal(960)
	assert_int(pc.tempo.size()).is_equal(2)
	assert_float(pc.tempo[0]["milli_bpm"]).is_equal_approx(120000.0, 1e-6)
	assert_float(pc.tempo[1]["milli_bpm"]).is_equal_approx(60000000000.0 / 461538.0, 1e-6)
	assert_bool(pc.tempo[1]["milli_bpm"] is float).is_true()
	assert_int(pc.warnings).is_greater_equal(1)
	assert_int(pc.time_sigs.size()).is_equal(2)
	assert_int(pc.time_sigs[1]["num"]).is_equal(3)
	assert_int(pc.time_sigs[1]["exp"]).is_equal(3)


func test_sections_from_events_track() -> void:
	var ev := MidiWriter.track([_e(0, MidiWriter.name("EVENTS")), _e(0, MidiWriter.text("[music_start]")),
			_e(480, MidiWriter.text("[section Verse 1]")), _e(960, MidiWriter.text("[prc_chorus_2]")),
			_e(1440, MidiWriter.text("section_bridge")), _e(1920, MidiWriter.text("[end]"))])
	var pc := MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", [[96, 0, 100], [96, 2000, 2100]]), ev]))
	var texts: Array = []
	for e in pc.events:
		texts.append(e["text"])
	assert_array(texts).is_equal(["section Verse 1", "section chorus 2", "section bridge"])
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.sections.size()).is_equal(3)
	assert_str(c.sections[0]["name"]).is_equal("Verse 1")
	assert_str(c.sections[1]["name"]).is_equal("chorus 2")
	assert_str(c.sections[2]["name"]).is_equal("bridge")


func _solo_part(with_116: bool) -> PackedByteArray:
	var notes := [[96, 0, 100], [97, 1920, 2000], [98, 3000, 3100], [60, 2000, 2100], [99, 3840, 3900]]
	var extra: Array = [_e(1920, MidiWriter.on(103)), _e(3840, MidiWriter.off(103))]
	if with_116:
		extra.append(_e(0, MidiWriter.on(116)))
		extra.append(_e(480, MidiWriter.off(116)))
	return _part("PART GUITAR", notes, extra)


func test_solos_with_star_power_note() -> void:
	var pc := MidiChartReader.parse_bytes(_mid([_solo_part(true)]))
	for d in ["EasySingle", "ExpertSingle"]:
		var marks: Array = []
		for e in pc.tracks[d]:
			if e["type"] == "E":
				marks.append([e["tick"], e["text"]])
		assert_array(marks).is_equal([[1920, "solo"], [3839, "soloend"]])
	var c := ChartImporter.build(pc, "expert")
	assert_int(c.solos.size()).is_equal(1)
	# expert notes in [1920, 3839]: 1920 and 3000 (3840 is outside)
	assert_int(c.solos[0]["note_count"]).is_equal(2)


func test_no_solos_without_116_or_103() -> void:
	var pc := MidiChartReader.parse_bytes(_mid([_solo_part(false)]))
	assert_array(ChartImporter.build(pc, "expert").solos).is_empty()
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", [[96, 0, 100]], [_e(0, MidiWriter.on(116)), _e(10, MidiWriter.off(116))])]))
	assert_array(ChartImporter.build(pc, "expert").solos).is_empty()


func test_song_metadata_empty() -> void:
	var t0 := MidiWriter.track([_e(0, MidiWriter.name("Some Song")), _e(0, MidiWriter.tempo(500000))])
	var pc := MidiChartReader.parse_bytes(MidiWriter.file([t0, _part("PART GUITAR", [[96, 0, 100]])]))
	assert_bool(pc.song.is_empty()).is_true()


func test_errors_and_limits() -> void:
	var pc := MidiChartReader.parse_bytes(PackedByteArray([1, 2, 3]))
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).is_equal(BAD)
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", [[96, 0, 100]])]), {"max_bytes": 20})
	assert_str(pc.error).is_equal("Chart too large")
	var notes := [[96, 0, 100], [96, 480, 580], [96, 960, 1060], [96, 1440, 1540], [96, 1920, 2020]]
	pc = MidiChartReader.parse_bytes(_mid([_part("PART GUITAR", notes)]), {"max_entries": 2})
	assert_bool(pc.ok).is_true()
	assert_int(_gems(pc, "ExpertSingle").size()).is_equal(2)
	assert_int(pc.warnings).is_greater_equal(1)
