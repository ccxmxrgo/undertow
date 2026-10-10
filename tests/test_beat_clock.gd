extends GdUnitTestSuite
## BeatClock phase and pulse, including negative lead-in time.


func test_phase_empty_map_uses_120_bpm() -> void:
	var tm: Array[Dictionary] = []
	assert_float(BeatClock.phase(0.25, tm)).is_equal_approx(0.5, 1e-6)


func test_phase_follows_tempo_map() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}, {"time": 10.0, "bpm": 60.0}]
	assert_float(BeatClock.phase(0.25, tm)).is_equal_approx(0.5, 1e-6)
	assert_float(BeatClock.phase(10.5, tm)).is_equal_approx(0.5, 1e-6)


func test_phase_negative_time_leads_in() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}]
	assert_float(BeatClock.phase(-0.25, tm)).is_equal_approx(0.5, 1e-6)
	assert_float(BeatClock.phase(-0.5, tm)).is_equal_approx(0.0, 1e-6)
	var empty: Array[Dictionary] = []
	assert_float(BeatClock.phase(-0.25, empty)).is_equal_approx(0.5, 1e-6)


func test_phase_guards_bad_bpm() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 0.0}]
	assert_bool(is_finite(BeatClock.phase(1.0, tm))).is_true()
	assert_bool(is_finite(BeatClock.phase(-1.0, tm))).is_true()


func test_pulse() -> void:
	assert_float(BeatClock.pulse(0.0)).is_equal_approx(1.0, 1e-9)
	assert_float(BeatClock.pulse(1.0)).is_equal_approx(0.0, 1e-9)
	assert_float(BeatClock.pulse(0.5)).is_equal_approx(0.125, 1e-9)


# ---- beats_between (D-18) ----

func _bars(beats: Array) -> Array:
	var out: Array = []
	for b in beats:
		if b["bar"]:
			out.append(snappedf(b["time"], 0.0001))
	return out


func _times(beats: Array) -> Array:
	var out: Array = []
	for b in beats:
		out.append(snappedf(b["time"], 0.0001))
	return out


func test_beats_between_4_4() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}]
	var ts: Array[Dictionary] = [{"time": 0.0, "num": 4, "den": 4}]
	var b := BeatClock.beats_between(0.0, 4.0, tm, ts)
	assert_array(_times(b)).is_equal([0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0])
	assert_array(_bars(b)).is_equal([0.0, 2.0, 4.0])


func test_beats_between_defaults_when_empty() -> void:
	var tm: Array[Dictionary] = []
	var ts: Array[Dictionary] = []
	var b := BeatClock.beats_between(0.0, 2.0, tm, ts)
	assert_array(_times(b)).is_equal([0.0, 0.5, 1.0, 1.5, 2.0])
	assert_array(_bars(b)).is_equal([0.0, 2.0])


func test_beats_between_3_4() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}]
	var ts: Array[Dictionary] = [{"time": 0.0, "num": 3, "den": 4}]
	assert_array(_bars(BeatClock.beats_between(0.0, 4.6, tm, ts))).is_equal([0.0, 1.5, 3.0, 4.5])


func test_beats_between_6_8_bar_is_three_quarters() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}]
	var ts: Array[Dictionary] = [{"time": 0.0, "num": 6, "den": 8}]
	assert_array(_bars(BeatClock.beats_between(0.0, 3.0, tm, ts))).is_equal([0.0, 1.5, 3.0])


func test_beats_between_ts_change_starts_new_bar() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}]
	# 3/4 for one bar (1.5 s) then 4/4
	var ts: Array[Dictionary] = [{"time": 0.0, "num": 3, "den": 4}, {"time": 1.5, "num": 4, "den": 4}]
	assert_array(_bars(BeatClock.beats_between(0.0, 6.0, tm, ts))).is_equal([0.0, 1.5, 3.5, 5.5])
	# a change in the middle of a bar also restarts the bar
	var mid: Array[Dictionary] = [{"time": 0.0, "num": 4, "den": 4}, {"time": 1.0, "num": 3, "den": 4}]
	assert_array(_bars(BeatClock.beats_between(0.0, 4.0, tm, mid))).is_equal([0.0, 1.0, 2.5, 4.0])


func test_beats_between_tempo_change_keeps_counting() -> void:
	# 120 bpm for 1.0 s (2 beats), then 60 bpm: bar 2 starts 2 beats later at 1.0 + 2.0 s
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}, {"time": 1.0, "bpm": 60.0}]
	var ts: Array[Dictionary] = [{"time": 0.0, "num": 4, "den": 4}]
	var b := BeatClock.beats_between(0.0, 7.0, tm, ts)
	assert_array(_times(b)).is_equal([0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
	assert_array(_bars(b)).is_equal([0.0, 3.0, 7.0])


func test_beats_between_window_and_order() -> void:
	var tm: Array[Dictionary] = [{"time": 0.25, "bpm": 120.0}]
	var ts: Array[Dictionary] = [{"time": 0.25, "num": 4, "den": 4}]
	var b := BeatClock.beats_between(2.0, 3.0, tm, ts)
	assert_array(_times(b)).is_equal([2.25, 2.75])
	assert_array(_bars(b)).is_equal([2.25])
	assert_array(BeatClock.beats_between(3.0, 2.0, tm, ts)).is_empty()
	# lead-in (negative time) keeps the grid
	assert_array(_bars(BeatClock.beats_between(-2.0, 0.3, tm, ts))).is_equal([-1.75, 0.25])
