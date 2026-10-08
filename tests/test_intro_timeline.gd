extends GdUnitTestSuite

const M := IntroTimeline.Mode
const P := IntroTimeline.Phase


func test_pre_count_seconds() -> void:
	assert_float(IntroTimeline.pre_count_seconds(M.FULL)).is_equal_approx(2.6, 0.0001)
	assert_float(IntroTimeline.pre_count_seconds(M.QUICK)).is_equal_approx(0.6, 0.0001)
	assert_float(IntroTimeline.pre_count_seconds(M.NONE)).is_equal(0.0)
	assert_float(IntroTimeline.pre_count_seconds(M.FULL, true)).is_equal_approx(1.6, 0.0001)


func test_lead_in_beats() -> void:
	assert_int(IntroTimeline.lead_in_beats(M.FULL, false)).is_equal(3)
	assert_int(IntroTimeline.lead_in_beats(M.QUICK, false)).is_equal(1)
	assert_int(IntroTimeline.lead_in_beats(M.NONE, false)).is_equal(3)
	assert_int(IntroTimeline.lead_in_beats(M.QUICK, true)).is_equal(3)
	assert_int(IntroTimeline.lead_in_beats(M.FULL, true)).is_equal(3)


func test_full_phase_boundaries() -> void:
	assert_int(IntroTimeline.phase_at(0.0, M.FULL)["phase"]).is_equal(P.ROOM_LENS)
	assert_int(IntroTimeline.phase_at(1.09, M.FULL)["phase"]).is_equal(P.ROOM_LENS)
	assert_int(IntroTimeline.phase_at(1.10, M.FULL)["phase"]).is_equal(P.BLACK)
	assert_int(IntroTimeline.phase_at(1.25, M.FULL)["phase"]).is_equal(P.CRT)
	assert_int(IntroTimeline.phase_at(1.65, M.FULL)["phase"]).is_equal(P.ARENA)
	assert_int(IntroTimeline.phase_at(2.59, M.FULL)["phase"]).is_equal(P.ARENA)
	assert_int(IntroTimeline.phase_at(2.60, M.FULL)["phase"]).is_equal(P.COUNT)
	assert_int(IntroTimeline.phase_at(99.0, M.FULL)["phase"]).is_equal(P.COUNT)
	assert_float(IntroTimeline.phase_at(0.55, M.FULL)["progress"]).is_equal_approx(0.5, 0.0001)
	assert_float(IntroTimeline.phase_at(2.125, M.FULL)["progress"]).is_equal_approx(0.5, 0.0001)


func test_quick_phase_boundaries() -> void:
	assert_int(IntroTimeline.phase_at(0.0, M.QUICK)["phase"]).is_equal(P.BLACK)
	assert_int(IntroTimeline.phase_at(0.05, M.QUICK)["phase"]).is_equal(P.CRT)
	assert_int(IntroTimeline.phase_at(0.40, M.QUICK)["phase"]).is_equal(P.ARENA)
	assert_int(IntroTimeline.phase_at(0.60, M.QUICK)["phase"]).is_equal(P.COUNT)
	assert_int(IntroTimeline.phase_at(0.0, M.NONE)["phase"]).is_equal(P.COUNT)


func test_reduce_motion_phases() -> void:
	assert_int(IntroTimeline.phase_at(0.5, M.FULL, true)["phase"]).is_equal(P.ROOM_LENS)
	assert_int(IntroTimeline.phase_at(0.85, M.FULL, true)["phase"]).is_equal(P.BLACK)
	assert_int(IntroTimeline.phase_at(1.0, M.FULL, true)["phase"]).is_equal(P.ARENA)
	assert_int(IntroTimeline.phase_at(1.6, M.FULL, true)["phase"]).is_equal(P.COUNT)


func test_count_number_flips_exactly() -> void:
	for bpm in [60.0, 120.0, 180.0]:
		var spb := IntroTimeline.seconds_per_beat(bpm)
		assert_int(IntroTimeline.count_number(-3.0 * spb, spb, 3)).is_equal(3)
		assert_int(IntroTimeline.count_number(-2.5 * spb, spb, 3)).is_equal(3)
		assert_int(IntroTimeline.count_number(-2.0 * spb, spb, 3)).is_equal(2)
		assert_int(IntroTimeline.count_number(-1.5 * spb, spb, 3)).is_equal(2)
		assert_int(IntroTimeline.count_number(-1.0 * spb, spb, 3)).is_equal(1)
		assert_int(IntroTimeline.count_number(-0.01 * spb, spb, 3)).is_equal(1)
		assert_int(IntroTimeline.count_number(0.0, spb, 3)).is_equal(0)
		assert_int(IntroTimeline.count_number(-3.01 * spb, spb, 3)).is_equal(0)
		assert_int(IntroTimeline.count_number(-0.5 * spb, spb, 1)).is_equal(1)
		assert_int(IntroTimeline.count_number(-1.0 * spb, spb, 1)).is_equal(1)
		assert_int(IntroTimeline.count_number(-1.5 * spb, spb, 1)).is_equal(0)


func test_dive_progress() -> void:
	assert_float(IntroTimeline.dive_progress(-0.1)).is_equal(-1.0)
	assert_float(IntroTimeline.dive_progress(0.0)).is_equal(0.0)
	assert_float(IntroTimeline.dive_progress(0.3)).is_equal_approx(0.5, 0.0001)
	assert_float(IntroTimeline.dive_progress(0.7)).is_equal(-1.0)
	assert_float(IntroTimeline.dive_progress(0.2, true)).is_equal_approx(0.5, 0.0001)
	assert_float(IntroTimeline.dive_progress(0.5, true)).is_equal(-1.0)


func test_ease_and_lens() -> void:
	assert_float(IntroTimeline.ease_out(-1.0)).is_equal(0.0)
	assert_float(IntroTimeline.ease_out(2.0)).is_equal(1.0)
	assert_float(IntroTimeline.ease_out(0.5)).is_equal_approx(0.875, 0.0001)


func test_lens_close_full() -> void:
	assert_float(IntroTimeline.lens_close(0.0, M.FULL)).is_equal(0.0)
	assert_float(IntroTimeline.lens_close(0.6, M.FULL)).is_equal(1.0)
	assert_float(IntroTimeline.lens_close(5.0, M.FULL)).is_equal(1.0)
	assert_float(IntroTimeline.lens_close(-1.0, M.FULL)).is_equal(0.0)
	var prev := -1.0
	for i in range(0, 61):
		var v := IntroTimeline.lens_close(float(i) * 0.01, M.FULL)
		assert_bool(v >= prev and v >= 0.0 and v <= 1.0).is_true()
		prev = v


func test_lens_focus_full() -> void:
	assert_float(IntroTimeline.lens_focus(0.0, M.FULL)).is_equal(0.0)
	assert_float(IntroTimeline.lens_focus(0.6, M.FULL)).is_equal(0.0)
	assert_float(IntroTimeline.lens_focus(IntroTimeline.FULL_LENS_END, M.FULL)).is_equal(1.0)
	var prev := -1.0
	for i in range(0, 130):
		var v := IntroTimeline.lens_focus(float(i) * 0.01, M.FULL)
		assert_bool(v >= prev and v >= 0.0 and v <= 1.0).is_true()
		prev = v


func test_lens_open_full() -> void:
	assert_float(IntroTimeline.lens_open(0.0, M.FULL)).is_equal(0.0)
	assert_float(IntroTimeline.lens_open(IntroTimeline.FULL_CRT_END, M.FULL)).is_equal(0.0)
	assert_float(IntroTimeline.lens_open(IntroTimeline.FULL_ARENA_END, M.FULL)).is_equal(1.0)
	var mid := IntroTimeline.lens_open(2.125, M.FULL)
	assert_bool(mid > 0.0 and mid < 1.0).is_true()


func test_lens_quick_none() -> void:
	for t in [0.0, 0.3, 0.5, 0.7]:
		assert_float(IntroTimeline.lens_close(t, M.QUICK)).is_equal(0.0)
		assert_float(IntroTimeline.lens_focus(t, M.QUICK)).is_equal(0.0)
		assert_float(IntroTimeline.lens_open(t, M.QUICK)).is_equal(0.0)
		assert_float(IntroTimeline.lens_close(t, M.NONE)).is_equal(0.0)


func test_lens_reduce_motion() -> void:
	assert_float(IntroTimeline.lens_close(0.0, M.FULL, true)).is_equal(0.0)
	assert_float(IntroTimeline.lens_close(0.4, M.FULL, true)).is_equal(1.0)
	assert_float(IntroTimeline.lens_close(0.8, M.FULL, true)).is_equal(1.0)
	assert_float(IntroTimeline.lens_focus(0.39, M.FULL, true)).is_equal(0.0)
	assert_float(IntroTimeline.lens_focus(0.4, M.FULL, true)).is_equal(1.0)
	assert_float(IntroTimeline.lens_open(0.9, M.FULL, true)).is_equal(0.0)
	assert_float(IntroTimeline.lens_open(1.6, M.FULL, true)).is_equal(1.0)
	var mid := IntroTimeline.lens_open(1.25, M.FULL, true)
	assert_bool(mid > 0.0 and mid < 1.0).is_true()


func test_guarded_spb_is_finite() -> void:
	for bpm in [0.0, -5.0, 0.5]:
		var spb := IntroTimeline.seconds_per_beat(bpm)
		assert_bool(is_finite(spb)).is_true()
		assert_float(spb).is_equal_approx(60.0, 0.0001)
	assert_bool(is_finite(IntroTimeline.beat_fraction(-0.3, 0.5))).is_true()


func test_lead_in_seconds_is_bounded() -> void:
	# WR-06: 1 beat at 240 bpm (0.25 s) is raised to the minimum; 3 beats at 40 bpm (4.5 s) capped.
	assert_float(IntroTimeline.lead_in_seconds(1, 240.0)).is_equal(IntroTimeline.LEAD_IN_MIN_SEC)
	assert_float(IntroTimeline.lead_in_seconds(3, 40.0)).is_equal(IntroTimeline.LEAD_IN_MAX_SEC)
	assert_float(IntroTimeline.lead_in_seconds(3, 120.0)).is_equal_approx(1.5, 1e-9)
	assert_float(IntroTimeline.count_beat_seconds(1, 240.0)).is_equal(IntroTimeline.LEAD_IN_MIN_SEC)
	assert_float(IntroTimeline.count_beat_seconds(3, 40.0)).is_equal_approx(4.0 / 3.0, 1e-9)
	assert_float(IntroTimeline.count_beat_seconds(3, 120.0)).is_equal_approx(0.5, 1e-9)
