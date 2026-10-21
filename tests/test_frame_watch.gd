extends GdUnitTestSuite
## 05-06 Task 1: FrameWatch late-frame counter (D-06, AV-05). Counts only; never a clock.


func _feed(w: FrameWatch, n: int, late_every: int, late_dt: float, dt: float = 1.0 / 60.0,
		song_t: float = 3.0) -> void:
	for i in n:
		var d := late_dt if late_every > 0 and i % late_every == 0 else dt
		w.sample(d, song_t + i * dt, false)


func test_smooth_run_never_hints() -> void:
	var w := FrameWatch.new(60.0)
	_feed(w, 1200, 0, 0.0)
	assert_int(w.counted_frames()).is_equal(1200)
	assert_int(w.late_frames()).is_equal(0)
	assert_float(w.late_ratio()).is_equal(0.0)
	assert_bool(w.should_hint(false)).is_false()


func test_five_percent_late_hints_unless_low_effects_on() -> void:
	var w := FrameWatch.new(60.0)
	_feed(w, 1200, 20, 0.030)
	assert_int(w.late_frames()).is_equal(60)
	assert_float(w.late_ratio()).is_equal_approx(0.05, 1e-6)
	assert_bool(w.should_hint(false)).is_true()
	assert_bool(w.should_hint(true)).is_false()


func test_two_percent_late_does_not_hint() -> void:
	var w := FrameWatch.new(60.0)
	_feed(w, 1200, 50, 0.030)
	assert_float(w.late_ratio()).is_equal_approx(0.02, 1e-6)
	assert_bool(w.should_hint(false)).is_false()


func test_warmup_and_pause_are_not_counted() -> void:
	var w := FrameWatch.new(60.0)
	w.sample(0.05, 0.5, false)
	w.sample(0.05, 1.99, false)
	w.sample(0.05, 5.0, true)
	assert_int(w.counted_frames()).is_equal(0)
	assert_int(w.late_frames()).is_equal(0)
	w.sample(0.05, 2.0, false)
	assert_int(w.counted_frames()).is_equal(1)
	assert_int(w.late_frames()).is_equal(1)


func test_too_few_frames_never_hint() -> void:
	var w := FrameWatch.new(60.0)
	_feed(w, 599, 2, 0.05)
	assert_float(w.late_ratio()).is_greater(0.4)
	assert_bool(w.should_hint(false)).is_false()


func test_refresh_fallback_and_clamps() -> void:
	assert_float(FrameWatch.new(-1.0).late_threshold()).is_equal_approx(1.5 / 60.0, 1e-9)
	assert_float(FrameWatch.new(0.0).late_threshold()).is_equal_approx(1.5 / 60.0, 1e-9)
	assert_float(FrameWatch.new(NAN).late_threshold()).is_equal_approx(1.5 / 60.0, 1e-9)
	assert_float(FrameWatch.new(INF).late_threshold()).is_equal_approx(1.5 / 60.0, 1e-9)
	assert_float(FrameWatch.new(240.0).late_threshold()).is_equal_approx(1.5 / 144.0, 1e-9)
	assert_float(FrameWatch.new(20.0).late_threshold()).is_equal_approx(1.5 / 30.0, 1e-9)
	assert_float(FrameWatch.new(120.0).late_threshold()).is_equal_approx(1.5 / 120.0, 1e-9)
	# A steady 120 fps on a 240 Hz panel is not late (the 144 Hz clamp).
	var w := FrameWatch.new(240.0)
	_feed(w, 700, 0, 0.0, 1.0 / 120.0)
	assert_int(w.late_frames()).is_equal(0)


func test_bad_dt_is_ignored() -> void:
	var w := FrameWatch.new(60.0)
	w.sample(NAN, 5.0, false)
	w.sample(INF, 5.0, false)
	w.sample(-0.1, 5.0, false)
	w.sample(0.05, NAN, false)
	assert_int(w.counted_frames()).is_equal(0)


func test_reset_zeroes_everything() -> void:
	var w := FrameWatch.new(60.0)
	_feed(w, 1200, 2, 0.05)
	assert_bool(w.should_hint(false)).is_true()
	w.reset()
	assert_int(w.counted_frames()).is_equal(0)
	assert_int(w.late_frames()).is_equal(0)
	assert_float(w.late_ratio()).is_equal(0.0)
	assert_bool(w.should_hint(false)).is_false()
