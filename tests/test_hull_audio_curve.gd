extends GdUnitTestSuite
## HullAudioCurve (05-02, D-03, D-04): hull -> muffle cutoff and creak curves.


func test_cutoff_open_above_start() -> void:
	assert_float(HullAudioCurve.cutoff_for_hull(100.0)).is_equal(20000.0)
	assert_float(HullAudioCurve.cutoff_for_hull(75.0)).is_equal(20000.0)
	assert_float(HullAudioCurve.cutoff_for_hull(250.0)).is_equal(20000.0)


func test_cutoff_floor_and_midpoint() -> void:
	assert_float(HullAudioCurve.cutoff_for_hull(0.0)).is_equal_approx(1500.0, 0.5)
	assert_float(HullAudioCurve.cutoff_for_hull(-20.0)).is_equal_approx(1500.0, 0.5)
	var mid := exp(lerpf(log(1500.0), log(20000.0), 0.5))
	assert_float(HullAudioCurve.cutoff_for_hull(37.5)).is_equal_approx(mid, 1.0)


func test_cutoff_monotonic() -> void:
	var prev := HullAudioCurve.cutoff_for_hull(75.0)
	var h := 74.5
	while h >= 0.0:
		var c := HullAudioCurve.cutoff_for_hull(h)
		assert_float(c).is_less(prev)
		prev = c
		h -= 0.5


func test_cutoff_non_finite_is_open() -> void:
	assert_bool(is_finite(HullAudioCurve.cutoff_for_hull(NAN))).is_true()


func test_muffle_active() -> void:
	assert_bool(HullAudioCurve.muffle_active(74.9)).is_true()
	assert_bool(HullAudioCurve.muffle_active(75.0)).is_false()
	assert_bool(HullAudioCurve.muffle_active(100.0)).is_false()
	assert_bool(HullAudioCurve.muffle_active(0.0)).is_true()


func test_smooth_cutoff_log_space() -> void:
	var cur := 20000.0
	var tgt := 1500.0
	var out := HullAudioCurve.smooth_cutoff(cur, tgt, HullAudioCurve.SMOOTH_TAU)
	var covered := (log(cur) - log(out)) / (log(cur) - log(tgt))
	assert_float(covered).is_equal_approx(1.0 - exp(-1.0), 0.01)
	assert_float(HullAudioCurve.smooth_cutoff(cur, tgt, 0.0)).is_equal(cur)
	# Never overshoots, both directions, even for a huge dt.
	assert_float(HullAudioCurve.smooth_cutoff(cur, tgt, 100.0)).is_greater_equal(tgt)
	assert_float(HullAudioCurve.smooth_cutoff(tgt, cur, 100.0)).is_less_equal(cur)
	var c := 1500.0
	for i in 600:
		var n := HullAudioCurve.smooth_cutoff(c, 20000.0, 1.0 / 60.0)
		assert_float(n).is_greater_equal(c)
		assert_float(n).is_less_equal(20000.0)
		c = n
	assert_float(c).is_equal_approx(20000.0, 1.0)


func test_creak_interval() -> void:
	assert_bool(is_inf(HullAudioCurve.creak_interval_for_hull(60.0))).is_true()
	assert_bool(is_inf(HullAudioCurve.creak_interval_for_hull(90.0))).is_true()
	assert_float(HullAudioCurve.creak_interval_for_hull(59.999)).is_equal_approx(12.0, 0.01)
	assert_float(HullAudioCurve.creak_interval_for_hull(10.0)).is_equal_approx(3.0, 1e-6)
	assert_float(HullAudioCurve.creak_interval_for_hull(0.0)).is_equal_approx(3.0, 1e-6)
	assert_float(HullAudioCurve.creak_interval_for_hull(35.0)).is_equal_approx(7.5, 1e-6)


func test_creak_db() -> void:
	assert_float(HullAudioCurve.creak_db_for_hull(60.0)).is_equal_approx(-24.0, 1e-6)
	assert_float(HullAudioCurve.creak_db_for_hull(10.0)).is_equal_approx(-12.0, 1e-6)
	assert_float(HullAudioCurve.creak_db_for_hull(0.0)).is_equal_approx(-12.0, 1e-6)
	assert_float(HullAudioCurve.creak_db_for_hull(35.0)).is_equal_approx(-18.0, 1e-6)


func test_damage_creak_chance() -> void:
	assert_float(HullAudioCurve.damage_creak_chance(70.0)).is_equal(0.0)
	assert_float(HullAudioCurve.damage_creak_chance(95.0)).is_equal(0.0)
	assert_float(HullAudioCurve.damage_creak_chance(30.0)).is_equal(1.0)
	assert_float(HullAudioCurve.damage_creak_chance(5.0)).is_equal(1.0)
	assert_float(HullAudioCurve.damage_creak_chance(50.0)).is_equal_approx(0.5, 1e-6)


func test_constants() -> void:
	assert_float(HullAudioCurve.MUFFLE_START).is_equal(75.0)
	assert_float(HullAudioCurve.OPEN_HZ).is_equal(20000.0)
	assert_float(HullAudioCurve.FLOOR_HZ).is_equal(1500.0)
	assert_float(HullAudioCurve.SMOOTH_TAU).is_equal(0.25)
	assert_float(HullAudioCurve.SLAM_SEC).is_equal(0.3)
