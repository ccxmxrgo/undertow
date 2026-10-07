extends GdUnitTestSuite
## Regression tests for the phase 01 code-review fixes (CR-01, WR-*).


func test_pause_during_preroll_never_seeks_negative() -> void:
	var c := Conductor.new()
	add_child(c)
	auto_free(c)
	c.begin(AudioStreamGenerator.new(), 2.0)
	c.pause()
	assert_bool(c.is_paused()).is_true()
	assert_float(c.clock.paused_position()).is_less(0.0)
	c.resume(1)
	assert_float(c._start_pos).is_equal(0.0)
	assert_bool(c._deferred_start).is_true()
	await get_tree().create_timer(0.7).timeout
	# Countdown over: still in the lead-in, audio must not have started early.
	assert_bool(c.is_paused()).is_false()
	assert_bool(c._playing_requested).is_false()
	assert_bool(c._preroll).is_true()
	assert_float(c.song_time()).is_less(0.0)


func test_clock_slews_instead_of_freezing_when_audio_is_behind() -> void:
	var ft := FakeTime.new()
	var clock := ClockModel.new()
	clock.reset(0, 10.0)
	var prev := clock.song_time()
	var advanced := 0.0
	# Audio target stuck 0.5 s behind the system-clock prediction (far beyond snap_s).
	for i in range(60):
		ft.advance_sec(1.0 / 60.0)
		var st := clock.update(ft.now(), clock.song_time() - 0.5, true)
		assert_float(st).is_greater(prev)
		advanced += st - prev
		prev = st
	assert_float(advanced).is_equal_approx(0.5, 0.02)
