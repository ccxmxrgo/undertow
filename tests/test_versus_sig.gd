extends GdUnitTestSuite
## 04-01 Task 3: VersusSig.of(chart), the runtime song signature over time_sigs and solos (D-11).


func _chart() -> ChartData:
	var c := ChartData.new()
	c.title = "Song"
	c.artist = "Artist"
	c.difficulty = "expert"
	c.add_note(0, 1.0)
	c.add_note(2, 1.5, 0.25)
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.time_sigs.append({"time": 0.0, "num": 4, "den": 4})
	c.time_sigs.append({"time": 10.0, "num": 3, "den": 4})
	c.solos.append({"start": 20.0, "end": 30.0, "note_count": 12})
	c.finalize()
	return c


func _is_hex16(s: String) -> bool:
	if s.length() != 16:
		return false
	for i in s.length():
		if not "0123456789abcdef".contains(s[i]):
			return false
	return true


func test_shape_and_stability() -> void:
	var a := VersusSig.of(_chart())
	assert_bool(_is_hex16(a)).override_failure_message(a).is_true()
	assert_str(VersusSig.of(_chart())).is_equal(a)


func test_key_order_does_not_matter() -> void:
	var c := _chart()
	c.time_sigs[1] = {"den": 4, "num": 3, "time": 10.0}
	assert_str(VersusSig.of(c)).is_equal(VersusSig.of(_chart()))


func test_time_sig_changes_change_it() -> void:
	var base := VersusSig.of(_chart())
	var c := _chart()
	c.time_sigs[1]["num"] = 6
	assert_str(VersusSig.of(c)).is_not_equal(base)
	c = _chart()
	c.time_sigs[1]["time"] = 10.5
	assert_str(VersusSig.of(c)).is_not_equal(base)
	c = _chart()
	c.time_sigs.pop_back()
	assert_str(VersusSig.of(c)).is_not_equal(base)


func test_solo_changes_change_it() -> void:
	var base := VersusSig.of(_chart())
	var c := _chart()
	c.solos[0]["end"] = 31.0
	assert_str(VersusSig.of(c)).is_not_equal(base)
	c = _chart()
	c.solos.append({"start": 40.0, "end": 45.0, "note_count": 3})
	assert_str(VersusSig.of(c)).is_not_equal(base)
	c = _chart()
	c.solos.clear()
	assert_str(VersusSig.of(c)).is_not_equal(base)


func test_ignores_everything_else() -> void:
	var base := VersusSig.of(_chart())
	var c := _chart()
	c.title = "Other"
	c.artist = "Someone"
	c.difficulty = "easy"
	c.add_note(3, 5.0)
	c.notes[0]["time"] = 0.9
	c.tempo_map[0]["bpm"] = 140.0
	c.sections.append({"time": 2.0, "name": "Intro"})
	c.id = "u1.abc.easy"
	assert_str(VersusSig.of(c)).is_equal(base)


func test_empty_chart_is_stable_and_non_empty() -> void:
	var a := VersusSig.of(ChartData.new())
	assert_bool(_is_hex16(a)).is_true()
	assert_str(VersusSig.of(ChartData.new())).is_equal(a)
	assert_str(a).is_not_equal(VersusSig.of(_chart()))
	# Moving one element between the two lists must not collide.
	var c := ChartData.new()
	c.solos.append({"time": 0.0, "num": 4, "den": 4})
	var d := ChartData.new()
	d.time_sigs.append({"time": 0.0, "num": 4, "den": 4})
	assert_str(VersusSig.of(c)).is_not_equal(VersusSig.of(d))
