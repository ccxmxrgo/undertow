extends GdUnitTestSuite


func test_extrapolates_from_system_ticks_when_audio_invalid() -> void:
	var c := ClockModel.new()
	c.reset(0, -1.0)
	var t := c.update(500000, 0.0, false)
	assert_float(t).is_equal_approx(-0.5, 1e-9)
	t = c.update(1000000, 123.0, false)
	assert_float(t).is_equal_approx(0.0, 1e-9)


func test_small_error_slews_toward_audio_target() -> void:
	var c := ClockModel.new(0.050, 0.15)
	c.reset(0, 1.0)
	# predicted = 1.016667, target = 1.026667 -> err 0.01 -> +0.0015
	var t := c.update(16667, 1.026667, true)
	assert_float(t).is_equal_approx(1.016667 + 0.01 * 0.15, 1e-6)


func test_large_error_snaps_to_audio_target() -> void:
	var c := ClockModel.new(0.050, 0.15)
	c.reset(0, 1.0)
	var t := c.update(16667, 1.5, true)
	assert_float(t).is_equal_approx(1.5, 1e-9)


func test_never_returns_less_than_prior_value() -> void:
	var c := ClockModel.new(0.050, 0.15)
	c.reset(0, 10.0)
	var prev := 10.0
	var now := 0
	# audio target jumps far behind (thread jitter): the clock must not go back
	for i in range(100):
		now += 16667
		var target := 5.0 if i % 7 == 0 else 10.0 + now / 1000000.0
		var t := c.update(now, target, true)
		assert_bool(t >= prev).is_true()
		prev = t


func test_song_time_at_maps_ticks_after_anchor() -> void:
	var c := ClockModel.new()
	c.reset(1000000, 2.0)
	c.update(2000000, 0.0, false)  # song_time 3.0 at ticks 2_000_000
	assert_float(c.song_time_at(2250000)).is_equal_approx(3.25, 1e-9)
	assert_float(c.song_time_at(1750000)).is_equal_approx(2.75, 1e-9)


func test_defaults_come_from_judge_config() -> void:
	var cfg := JudgeConfig.new()
	var c := ClockModel.new()
	assert_float(c.snap_s).is_equal(cfg.clock_snap_s)
	assert_float(c.slew).is_equal(cfg.clock_slew)
