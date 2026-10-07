extends GdUnitTestSuite
## Autoplay (D-28) must score all-Perfect on every Phase 1 test chart regardless of the
## frame schedule, because it presses at exact note times.

const SAMPLE_RATE := 8000  # keeps generated audio small; timing logic does not use audio


func _schedule(fps: float, length: float, jitter: bool) -> Array[float]:
	var out: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var t := 0.0
	while t < length:
		var dt := 1.0 / fps
		if jitter:
			dt *= rng.randf_range(0.4, 1.8)
			if rng.randf() < 0.01:
				dt += 0.1  # hitch
		t += dt
		out.append(t)
	return out


func _run(chart: ChartData, times: Array[float]) -> Dictionary:
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var hs := HullScore.new(JudgeConfig.new())
	hs.connect_judge(judge)
	var errs: Array[float] = []
	var ends: Array = []
	judge.judged.connect(func(_l: int, _i: int, _j: int, e: float) -> void: errs.append(e))
	judge.sustain_end.connect(func(_l: int, c: bool) -> void: ends.append(c))
	var ap := Autoplay.new(chart, judge)
	for t in times:
		ap.update(t)
		judge.tick(t)
	return {"hs": hs, "errs": errs, "ends": ends, "judge": judge}


func _assert_all_perfect(chart: ChartData, times: Array[float]) -> void:
	var r := _run(chart, times)
	var hs: HullScore = r["hs"]
	assert_int(hs.miss_count).is_equal(0)
	assert_int(hs.good_count).is_equal(0)
	assert_int(hs.stray_count).is_equal(0)
	assert_int(hs.perfect_count).is_equal(chart.notes.size())
	assert_float(hs.hull).is_equal(100.0)
	for e in r["errs"]:
		assert_float(e).is_equal(0.0)
	for c in r["ends"]:
		assert_bool(c).is_true()
	assert_bool((r["judge"] as InputJudge).is_finished()).is_true()


func test_hand_chart_all_perfect_at_each_schedule() -> void:
	var chart := TestCharts.hand_chart(SAMPLE_RATE)
	var last: float = chart.notes[chart.notes.size() - 1]["time"] + 3.0
	for fps in [30.0, 60.0, 144.0]:
		_assert_all_perfect(chart, _schedule(fps, last, false))
	_assert_all_perfect(chart, _schedule(60.0, last, true))


func test_hand_chart_has_tempo_change_chords_and_sustains() -> void:
	var chart := TestCharts.hand_chart(SAMPLE_RATE)
	assert_int(chart.tempo_map.size()).is_equal(2)
	assert_float(chart.tempo_map[1]["bpm"]).is_not_equal(chart.tempo_map[0]["bpm"])
	var sustains := 0
	var same_time := 0
	for i in range(chart.notes.size()):
		if chart.notes[i]["duration"] > 0.0:
			sustains += 1
		if i > 0 and chart.notes[i]["time"] == chart.notes[i - 1]["time"]:
			same_time += 1
	assert_int(sustains).is_greater(3)
	assert_int(same_time).is_greater(3)
	assert_float(chart.notes[chart.notes.size() - 1]["time"]).is_greater(50.0)


func test_five_minute_click_chart_all_perfect_at_each_schedule() -> void:
	var chart := TestCharts.five_minute_click_chart(120.0, SAMPLE_RATE)
	assert_int(chart.notes.size()).is_equal(600)
	for fps in [30.0, 60.0, 144.0]:
		_assert_all_perfect(chart, _schedule(fps, 303.0, false))
	_assert_all_perfect(chart, _schedule(60.0, 303.0, true))
