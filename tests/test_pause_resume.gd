extends GdUnitTestSuite
## Pure ClockModel pause/resume/handoff behavior driven by injected ticks (D-03, D-07, D-26).

const FRAME := 1.0 / 60.0


func test_delayed_audio_handoff_is_monotonic_with_small_steps() -> void:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.begin_preroll(ft.now(), 2.0, 0.0)
	assert_int(clock.state).is_equal(ClockModel.State.PREROLL)
	var prev := clock.song_time()
	var worst_excess := 0.0
	# Audio becomes valid late (at song_time ~0.25), with a 30 ms disagreement vs the system clock.
	for i in range(600):
		ft.advance_sec(FRAME)
		var truth := ft.now() / 1000000.0 - 2.0
		var valid := truth > 0.25
		var st := clock.update(ft.now(), truth + 0.03, valid)
		assert_float(st).is_greater_equal(prev)
		worst_excess = maxf(worst_excess, (st - prev) - FRAME)
		prev = st
	assert_int(clock.state).is_equal(ClockModel.State.PLAYING)
	assert_float(worst_excess).is_less(0.005)


func test_pause_freezes_song_time() -> void:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.reset(0, 12.0)
	ft.advance_sec(0.3)
	clock.update(ft.now(), 0.0, false)
	assert_float(clock.song_time()).is_equal_approx(12.3, 1e-6)
	clock.pause(ft.now())
	assert_bool(clock.is_paused()).is_true()
	for i in range(300):  # 5 s of frames
		ft.advance_sec(FRAME)
		assert_float(clock.update(ft.now(), 99.0, true)).is_equal_approx(12.3, 1e-6)
	assert_float(clock.song_time_at(ft.now())).is_equal_approx(12.3, 1e-6)
	assert_float(clock.paused_position()).is_equal_approx(12.3, 1e-6)


func test_resume_countdown_then_continues_without_jump() -> void:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.reset(0, 12.3)
	clock.pause(ft.now())
	ft.advance_sec(5.0)
	var countdown := 3.0 * 60.0 / 120.0  # 3 beats at 120 BPM
	assert_float(countdown).is_equal(1.5)
	clock.resume(ft.now(), countdown)
	assert_bool(clock.is_counting_down()).is_true()
	assert_float(clock.paused_position()).is_equal_approx(12.3, 1e-6)
	var prev := clock.song_time()
	var max_step := 0.0
	var t_after := -1.0
	for i in range(150):  # 2.5 s of frames
		ft.advance_sec(FRAME)
		var st := clock.update(ft.now(), 0.0, false)
		max_step = maxf(max_step, st - prev)
		prev = st
		if ft.now() < clock.resume_ticks() and clock.is_counting_down():
			assert_float(st).is_equal_approx(12.3, 1e-6)
		elif t_after < 0.0:
			t_after = st
	assert_bool(clock.is_paused()).is_false()
	assert_int(clock.state).is_equal(ClockModel.State.PLAYING)
	assert_float(max_step).is_less_equal(FRAME + 0.005)
	assert_float(t_after).is_greater_equal(12.3)
	assert_float(t_after).is_less(12.3 + FRAME + 0.005)
	# One second of play after the countdown ends: roughly 1.0 s of song advanced.
	assert_float(prev).is_equal_approx(13.3, 0.02)


func test_pause_during_countdown_cancels_it() -> void:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.reset(0, 4.0)
	clock.pause(ft.now())
	clock.resume(ft.now(), 1.5)
	ft.advance_sec(0.5)
	clock.pause(ft.now())
	assert_bool(clock.is_counting_down()).is_false()
	ft.advance_sec(5.0)
	assert_float(clock.update(ft.now(), 0.0, false)).is_equal_approx(4.0, 1e-6)
	assert_bool(clock.is_paused()).is_true()


func test_conductor_source_does_not_use_scene_tree_pause() -> void:
	var src := FileAccess.get_file_as_string("res://src/core/conductor.gd")
	assert_bool(src.contains("get_tree().paused")).is_false()
	assert_bool(src.contains("_player.stop()")).is_true()
