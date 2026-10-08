extends GdUnitTestSuite
## Visor shader, VisorFrame, VisorBrackets and VisorHud (D-03, 01.1-06 recording-frame visor).

var _saved_low := false
var _saved_rm := false


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm


func _frame() -> VisorFrame:
	var f := VisorFrame.new()
	add_child(f)
	auto_free(f)
	return f


func _brackets() -> VisorBrackets:
	var b := VisorBrackets.new()
	add_child(b)
	auto_free(b)
	return b


func _hud() -> VisorHud:
	var h := VisorHud.new()
	add_child(h)
	auto_free(h)
	return h


func _param(f: VisorFrame, name: StringName) -> Variant:
	return (f.material as ShaderMaterial).get_shader_parameter(name)


func test_shader_loads_mask_only_with_clear_rect() -> void:
	var sh := load("res://shaders/visor.gdshader") as Shader
	assert_object(sh).is_not_null()
	assert_str(sh.code).contains("shader_type canvas_item")
	assert_str(sh.code).contains("clear_rect")
	assert_bool(sh.code.contains("hint_screen_texture")).is_false()
	assert_bool(sh.code.to_lower().contains("screen_texture")).is_false()
	assert_bool(sh.code.contains("SCREEN_UV")).is_false()


func test_frame_ignores_mouse_and_clears_the_highway() -> void:
	var f := _frame()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(f.material is ShaderMaterial).is_true()
	assert_object((f.material as ShaderMaterial).shader).is_equal(load("res://shaders/visor.gdshader"))
	assert_bool(f.visible).is_true()
	var cr: Vector4 = _param(f, &"clear_rect")
	# Highway x 672..1248 plus the 48 px margin, full height.
	assert_float(cr.x).is_equal(624.0)
	assert_float(cr.x + cr.z).is_equal(1296.0)
	assert_float(cr.y).is_equal(0.0)
	assert_float(cr.w).is_equal(1080.0)


func test_low_effects_keeps_lens_but_drops_animated_layers() -> void:
	var f := _frame()
	assert_bool(f.effects_enabled()).is_true()
	Settings.low_effects = true
	f.apply_low_effects()
	assert_bool(f.visible).is_true()  # lens mask, rim, vignette stay
	assert_bool(f.effects_enabled()).is_false()
	assert_float(float(_param(f, &"effects"))).is_equal(0.0)
	Settings.low_effects = false
	f.apply_low_effects()
	assert_bool(f.effects_enabled()).is_true()


func test_reduce_motion_also_drops_animated_layers() -> void:
	var f := _frame()
	Settings.reduce_motion = true
	f.apply_low_effects()
	assert_bool(f.effects_enabled()).is_false()
	assert_bool(f.glitch_enabled()).is_false()


func test_glitch_trigger_runs_120ms_burst() -> void:
	var f := _frame()
	assert_bool(f.glitch_active()).is_false()
	var t0 := Time.get_ticks_usec()
	f.trigger_glitch()
	assert_bool(f.glitch_active()).is_true()
	assert_float(float(_param(f, &"glitch"))).is_equal(1.0)
	f.update_glitch(t0 + 60000)  # half-way: still bursting, decaying
	assert_bool(f.glitch_active()).is_true()
	assert_float(float(_param(f, &"glitch"))).is_between(0.3, 0.7)
	f.update_glitch(t0 + int(VisorFrame.GLITCH_SEC * 1000000.0) + 20000)
	assert_bool(f.glitch_active()).is_false()
	assert_float(float(_param(f, &"glitch"))).is_equal(0.0)


func test_glitch_trigger_is_noop_in_low_effects_and_reduce_motion() -> void:
	var f := _frame()
	Settings.low_effects = true
	f.apply_low_effects()
	f.trigger_glitch()
	assert_bool(f.glitch_active()).is_false()
	assert_float(float(_param(f, &"glitch"))).is_equal(0.0)
	Settings.low_effects = false
	Settings.reduce_motion = true
	f.apply_low_effects()
	f.trigger_glitch()
	assert_bool(f.glitch_active()).is_false()


func test_low_effects_mid_burst_cancels_it() -> void:
	var f := _frame()
	f.trigger_glitch()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_bool(f.glitch_active()).is_false()
	assert_float(float(_param(f, &"glitch"))).is_equal(0.0)


func test_brackets_always_drawn() -> void:
	var b := _brackets()
	assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(b.brackets_visible()).is_true()
	assert_bool(b.readouts_visible()).is_false()  # text lives in VisorHud now


func test_hud_builds_and_ignores_mouse() -> void:
	var h := _hud()
	assert_int(h.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(h.text_rects().size() > 10).is_true()
	assert_bool(h.animated()).is_true()


func test_hud_text_never_enters_note_entry_zone() -> void:
	var h := _hud()
	var zone := Rect2(672.0, 0.0, 576.0, 120.0)
	for r in h.text_rects():
		assert_bool(r.intersects(zone)).override_failure_message("visor text %s overlaps the note entry zone" % r).is_false()


func test_hud_text_stays_out_of_highway_columns_and_gameplay_band() -> void:
	var h := _hud()
	var highway := Rect2(624.0, 0.0, 672.0, 990.0)
	var band := Rect2(0.0, 840.0, 1920.0, 120.0)
	for r in h.text_rects():
		assert_bool(r.intersects(highway)).override_failure_message("text %s in highway" % r).is_false()
		assert_bool(r.intersects(band)).override_failure_message("text %s in y 840..960" % r).is_false()


func test_hud_low_effects_is_static() -> void:
	var h := _hud()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_bool(h.animated()).is_false()
	assert_float(h.audio_pulse()).is_equal(0.0)
	Settings.low_effects = false
	Settings.settings_changed.emit()
	assert_bool(h.animated()).is_true()


func test_hud_binds_real_hull_and_depth() -> void:
	var h := _hud()
	var score := HullScore.new(JudgeConfig.new())
	h.bind(score)
	assert_str(h.hull_text()).is_equal("HULL %d%%" % int(round(score.hull)))
	score.hull_changed.emit(25.0, -5.0)
	assert_str(h.hull_text()).is_equal("HULL 25%")
	assert_bool(h.is_hull_critical()).is_true()


func test_timeline_progress_is_clamped_ratio() -> void:
	assert_float(VisorHud.progress_for(30.0, 120.0)).is_equal_approx(0.25, 1e-6)
	assert_float(VisorHud.progress_for(-2.0, 120.0)).is_equal(0.0)
	assert_float(VisorHud.progress_for(500.0, 120.0)).is_equal(1.0)
	assert_float(VisorHud.progress_for(10.0, 0.0)).is_equal(0.0)
	assert_float(VisorHud.progress_for(120.0, 120.0)).is_equal(1.0)


func test_timecode_mm_ss_ff() -> void:
	assert_str(VisorHud.timecode(0.0)).is_equal("00:00:00")
	assert_str(VisorHud.timecode(-1.5)).is_equal("00:00:00")
	assert_str(VisorHud.timecode(62.5)).is_equal("01:02:15")
	assert_str(VisorHud.timecode(3.0 + 29.0 / 30.0 + 0.001)).is_equal("00:03:29")


func test_beat_phase_follows_tempo_map() -> void:
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}, {"time": 10.0, "bpm": 60.0}]
	assert_float(VisorHud.beat_phase(0.25, tm)).is_equal_approx(0.5, 1e-6)
	assert_float(VisorHud.beat_phase(10.5, tm)).is_equal_approx(0.5, 1e-6)
	assert_float(VisorHud.beat_phase(-1.0, tm)).is_equal(0.0)


func test_timeline_playhead_and_keyframes_track_conductor() -> void:
	var h := _hud()
	var tm: Array[Dictionary] = [{"time": 0.0, "bpm": 120.0}, {"time": 30.0, "bpm": 90.0}]
	var c := FakeSongClock.new()
	add_child(c)
	auto_free(c)
	h.setup_timeline(c, tm, 120.0)
	assert_int(h.keyframe_count()).is_equal(2)
	c.t = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(h.progress()).is_equal_approx(0.5, 1e-3)
	assert_float(h.playhead_x()).is_equal_approx(lerpf(VisorHud.TL_X.x, VisorHud.TL_X.y, 0.5), 0.5)
	assert_str(h.timecode_text()).is_equal("01:00:00")


## Conductor stand-in with a settable song time.
class FakeSongClock:
	extends Conductor
	var t: float = 0.0

	func song_time() -> float:
		return t

	func _process(_delta: float) -> void:
		pass
