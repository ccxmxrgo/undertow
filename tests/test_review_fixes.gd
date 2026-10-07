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


func test_wizard_visual_step_uses_pending_audio_offset() -> void:
	var w: CalibrationWizard = (load("res://scenes/calibration.tscn") as PackedScene).instantiate()
	add_child(w)
	auto_free(w)
	Settings.audio_offset = 0.0
	w.pending_audio = 0.05
	w.show_step(CalibrationWizard.Step.VISUAL)
	assert_float(w.conductor.audio_offset()).is_equal_approx(0.05, 1e-9)
	w.show_step(CalibrationWizard.Step.AUDIO)
	assert_float(w.conductor.audio_offset()).is_equal(Settings.audio_offset)
	await get_tree().process_frame  # let queue_free'd step content go before orphan accounting


func test_overlapping_hold_in_same_lane_ends_previous_hold() -> void:
	var chart := ChartData.new()
	chart.add_note(0, 1.0, 2.0)  # tail at 3.0
	chart.add_note(0, 2.0, 0.5)  # head inside the first hold
	chart.finalize()
	var j := InputJudge.new(chart, JudgeConfig.new())
	var ends: Array = []
	j.sustain_end.connect(func(lane: int, c: bool) -> void: ends.append([lane, c]))
	j.press(0, 1.0)
	j.press(0, 2.0)
	assert_int(ends.size()).is_equal(1)
	assert_int(ends[0][0]).is_equal(0)
	assert_bool(ends[0][1]).is_false()  # cut short, not completed
	j.tick(5.0)
	assert_int(ends.size()).is_equal(2)


func test_key_and_trigger_share_lane_without_releasing_each_other() -> void:
	BindingStore.new().reset_defaults()
	var li: LaneInput = auto_free(LaneInput.new())
	var pressed: Array = []
	var released: Array = []
	li.lane_pressed.connect(func(l: int, _t: int) -> void: pressed.append(l))
	li.lane_released.connect(func(l: int, _t: int) -> void: released.append(l))
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	li.inject(f)  # lane_2 key down
	var idle := InputEventJoypadMotion.new()
	idle.axis = JOY_AXIS_TRIGGER_LEFT
	idle.axis_value = 0.1
	li.inject(idle)  # idle trigger jitter must not release the held key
	assert_int(pressed.size()).is_equal(1)
	assert_int(released.size()).is_equal(0)
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_LEFT
	trig.axis_value = 0.9
	li.inject(trig)  # trigger pressed while key held: no second press
	assert_int(pressed.size()).is_equal(1)
	trig.axis_value = 0.0
	li.inject(trig)  # trigger released, key still down: still held
	assert_int(released.size()).is_equal(0)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_F
	up.pressed = false
	li.inject(up)
	assert_int(released.size()).is_equal(1)
