extends GdUnitTestSuite
## Deterministic half of D-30: five simulated minutes at jittered ~60 fps with injected
## 100 ms hitches and a constant 0.4 ms/s device drift between the audio clock and the
## system clock. Autoplayed presses (made at the moment the audio reaches each note) must
## be judged within 2 ms and the ClockModel output must never decrease. Real-audio drift on
## real hardware is verified by the Drift Harness in plan 06 (research Pitfall 7).

const SAMPLE_RATE := 8000
const DRIFT := 0.0004  # audio seconds advance 0.4 ms faster per real second
const MAX_ERR := 0.002


func test_five_minute_drift_with_hitches_stays_within_2ms() -> void:
	var chart := TestCharts.five_minute_click_chart(120.0, SAMPLE_RATE)
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var errs: Array[float] = []
	var perfect := [0]
	judge.judged.connect(func(_l: int, _i: int, j: int, e: float) -> void:
		errs.append(e)
		if j == InputJudge.Judgment.PERFECT:
			perfect[0] += 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var clock := ClockModel.new()
	clock.reset(0, 0.0)

	# Physical press time for note n: the real time at which the (drifting) audio hits it.
	var presses: Array[Dictionary] = []
	for n in chart.notes:
		presses.append({"ticks": int(round(n["time"] / (1.0 + DRIFT) * 1000000.0)), "lane": n["lane"]})
	var next := 0

	var now := 0
	var prev_song := 0.0
	var end_ticks: int = presses[presses.size() - 1]["ticks"] + 2000000
	var hitches := 0
	while now < end_ticks:
		var step := (1.0 / 60.0) * rng.randf_range(0.7, 1.3)
		if rng.randf() < 0.002:
			step += 0.1
			hitches += 1
		now += int(round(step * 1000000.0))
		# Events first (they are stamped before this frame's clock update).
		while next < presses.size() and presses[next]["ticks"] <= now:
			judge.press(presses[next]["lane"], clock.song_time_at(presses[next]["ticks"]))
			next += 1
		var truth := now / 1000000.0 * (1.0 + DRIFT)
		var target := truth + rng.randf_range(-0.001, 0.001)  # mix-chunk noise
		var st := clock.update(now, target, true)
		assert_float(st).is_greater_equal(prev_song)
		prev_song = st
		judge.tick(st)

	assert_int(hitches).is_greater(5)
	assert_int(errs.size()).is_equal(chart.notes.size())
	var worst := 0.0
	for e in errs:
		worst = maxf(worst, absf(e))
	assert_float(worst).is_less(MAX_ERR)
	assert_int(perfect[0]).is_equal(chart.notes.size())
