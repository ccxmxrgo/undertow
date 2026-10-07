extends GdUnitTestSuite
## TIME-02: the same physical press times must produce identical judgments at any frame
## rate when each press is converted with ClockModel.song_time_at (event tick stamp).

const SAMPLE_RATE := 8000


## Physical presses as tick usec, offset from the nominal note time by a fixed set of ms.
func _presses(chart: ChartData) -> Array[Dictionary]:
	var offsets := [0.0, 20.0, -20.0, 50.0, -50.0]
	var out: Array[Dictionary] = []
	for i in range(chart.notes.size()):
		var n: Dictionary = chart.notes[i]
		var off: float = offsets[i % offsets.size()] / 1000.0
		out.append({"ticks": int(round((n["time"] + off) * 1000000.0)), "lane": n["lane"]})
	return out


func _run(chart: ChartData, fps: float, jitter_seed: int) -> Array:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.reset(0, 0.0)
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var result: Array = []
	judge.judged.connect(func(_l: int, i: int, j: int, e: float) -> void: result.append([i, j, e]))
	var presses := _presses(chart)
	presses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ticks"] < b["ticks"])
	var rng := RandomNumberGenerator.new()
	rng.seed = jitter_seed
	var next := 0
	var end_ticks: int = presses[presses.size() - 1]["ticks"] + 2000000
	while ft.now() < end_ticks:
		var step := 1.0 / fps
		if jitter_seed != 0:
			step *= rng.randf_range(0.5, 1.5)
		ft.advance_sec(step)
		# Input events arrive at the start of the frame, before the clock update.
		while next < presses.size() and presses[next]["ticks"] <= ft.now():
			judge.press(presses[next]["lane"], clock.song_time_at(presses[next]["ticks"]))
			next += 1
		clock.update(ft.now(), ft.now() / 1000000.0, true)
		judge.tick(clock.song_time())
	result.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return result


func test_judgments_identical_across_frame_rates() -> void:
	var chart := TestCharts.click_chart(120.0, 80, SAMPLE_RATE)
	var base := _run(chart, 144.0, 0)
	assert_int(base.size()).is_equal(80)
	for fps in [30.0, 60.0]:
		var other := _run(chart, fps, 0)
		assert_int(other.size()).is_equal(base.size())
		for i in range(base.size()):
			assert_int(other[i][1]).is_equal(base[i][1])
			assert_float(other[i][2]).is_equal_approx(base[i][2], 0.0001)
	var jit := _run(chart, 60.0, 77)
	for i in range(base.size()):
		assert_int(jit[i][1]).is_equal(base[i][1])
		assert_float(jit[i][2]).is_equal_approx(base[i][2], 0.0001)


func test_press_error_matches_physical_offset() -> void:
	var chart := TestCharts.click_chart(120.0, 10, SAMPLE_RATE)
	var res := _run(chart, 60.0, 0)
	var offsets := [0.0, 0.02, -0.02, 0.05, -0.05]
	for i in range(res.size()):
		assert_float(res[i][2]).is_equal_approx(offsets[i % 5], 0.0001)
