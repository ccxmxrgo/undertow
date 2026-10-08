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
	f.physical_keycode = KEY_2
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
	up.physical_keycode = KEY_2
	up.pressed = false
	li.inject(up)
	assert_int(released.size()).is_equal(1)


func test_confirm_dialog_focus_neighbours_stay_inside_dialog() -> void:
	var d := ConfirmDialog.new()
	add_child(d)
	auto_free(d)
	d.setup("T", "B", "Yes", "No")
	for b in [d.confirm_button, d.safe_button]:
		for np in [b.focus_neighbor_top, b.focus_neighbor_bottom, b.focus_neighbor_left,
				b.focus_neighbor_right, b.focus_next, b.focus_previous]:
			assert_bool(np.is_empty()).is_false()
			var target: Node = b.get_node(np)
			assert_bool(target == d.confirm_button or target == d.safe_button).is_true()
	assert_object(d.safe_button.focus_neighbor_top).is_equal(d.safe_button.get_path_to(d.safe_button))
	assert_object(d.safe_button.get_node(d.safe_button.focus_neighbor_left)).is_same(d.confirm_button)
	await get_tree().process_frame
	assert_bool(d.safe_button.has_focus()).is_true()


func test_fail_screen_buttons_inert_until_faded_in() -> void:
	var f := FailScreen.new()
	add_child(f)
	auto_free(f)
	f.setup(120.0)
	f.play(0.05)
	assert_float(f.modulate.a).is_equal(0.0)
	assert_bool(f.retry_button.disabled).is_true()
	assert_bool(f.menu_button.disabled).is_true()
	await get_tree().create_timer(0.05 + FailScreen.FADE_SEC + 0.25).timeout
	assert_float(f.modulate.a).is_equal_approx(1.0, 0.001)
	assert_bool(f.retry_button.disabled).is_false()
	assert_bool(f.menu_button.disabled).is_false()
	assert_bool(f.retry_button.has_focus()).is_true()


func test_settings_save_is_atomic_and_overwrites_existing_file() -> void:
	var path := "user://test_review_atomic.cfg"
	var s: Node = auto_free(preload("res://src/autoload/settings.gd").new())
	s.audio_offset = 0.01
	assert_int(s.save_to(path)).is_equal(OK)
	s.audio_offset = 0.02
	assert_int(s.save_to(path)).is_equal(OK)  # second save replaces the existing file
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(path)).is_equal(OK)
	assert_float(float(cfg.get_value("calibration", "audio_offset"))).is_equal_approx(0.02, 1e-9)
	# Unwritable target directory reports an error instead of silently succeeding.
	assert_int(s.save_to("user://no_such_dir_review/x.cfg")).is_not_equal(OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_no_full_rect_anchor_preset_left_in_ui() -> void:
	var dir := DirAccess.open("res://src/ui")
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "ui_layout.gd":
			var src := FileAccess.get_file_as_string("res://src/ui/" + f)
			assert_bool(src.contains("PRESET_FULL_RECT")).override_failure_message(f).is_false()


func test_quick_intro_draws_no_lens_mask() -> void:
	# CR-01: QUICK has an ARENA phase but lens_open() is 0 there; the mask must not be drawn.
	assert_bool(GogglesIntro.arena_draws_lens(IntroTimeline.Mode.QUICK)).is_false()
	assert_bool(GogglesIntro.arena_draws_lens(IntroTimeline.Mode.FULL)).is_true()


func test_lens_mask_texture_is_cached_across_instances() -> void:
	# WR-02: the 129k-pixel mask is built once per process, not per intro instance.
	var a := GogglesIntro.lens_mask_texture()
	var b := GogglesIntro.lens_mask_texture()
	assert_object(a).is_not_null()
	assert_bool(a == b).is_true()
	assert_int(a.get_width()).is_equal(GogglesIntro.MASK_W)
