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
