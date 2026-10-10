extends GdUnitTestSuite
## UiSounds autoload and AudioSynth.make_ui_blip (02.2 plan 23, VIS-09, UI-SPEC 10.4):
## move / confirm / back / error blips on the SFX bus, never during gameplay (a running
## Gameplay) and never while the calibration wizard measures (W7, T-02.2-43).

const UiSoundsScript := preload("res://src/autoload/ui_sounds.gd")
const WIZARD_SCENE := "res://scenes/calibration.tscn"
const RATE := 44100
const TEST_PATH := "user://test_ui_sounds.cfg"

var _old_path: String


func before_test() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	UiSounds.muted = false
	Settings.reset_defaults()
	Settings.save_path = _old_path
	MainMenu.boot_handled = false
	for p in [TEST_PATH, TEST_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _sounds() -> Node:
	var s: Node = UiSoundsScript.new()
	add_child(s)
	auto_free(s)
	# A plain menu-like scene: never a running Gameplay.
	var menu := Control.new()
	auto_free(menu)
	s.scene_override = menu
	return s


func _action(action: String, pressed: bool = true) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	return e


## Peak in dBFS and sample count of a 16-bit mono blip.
func _pcm(w: AudioStreamWAV) -> Dictionary:
	var n := w.data.size() / 2
	var peak := 0
	for i in n:
		peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
	return {"n": n, "peak_db": linear_to_db(float(peak) / 32767.0)}


func _assert_blip(name: String, sec: float, peak_db: float) -> void:
	var w: AudioStreamWAV = AudioSynth.make_ui_blip(name, RATE)
	assert_object(w).is_not_null()
	assert_int(w.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_bool(w.stereo).is_false()
	assert_int(w.mix_rate).is_equal(RATE)
	var p := _pcm(w)
	assert_int(p["n"]).is_between(int(sec * RATE) - 1, int(sec * RATE) + 1)
	assert_float(p["peak_db"]).is_between(peak_db - 0.5, peak_db + 0.25)
	# Short attack and release: no click at either end.
	assert_int(absi(w.data.decode_s16(0))).is_less(200)
	assert_int(absi(w.data.decode_s16((p["n"] - 1) * 2))).is_less(200)


## Zero crossings per second in [from, to) seconds -> roughly 2 x frequency.
func _freq(w: AudioStreamWAV, from: float, to: float) -> float:
	var a := int(from * RATE)
	var b := int(to * RATE)
	var crossings := 0
	var prev := w.data.decode_s16(a * 2)
	for i in range(a + 1, b):
		var s := w.data.decode_s16(i * 2)
		if (prev < 0 and s >= 0) or (prev >= 0 and s < 0):
			crossings += 1
		prev = s
	return crossings * 0.5 / (to - from)


# ---- AudioSynth.make_ui_blip --------------------------------------------------------------

func test_move_blip_is_1600hz_30ms_at_minus_18_dbfs() -> void:
	_assert_blip("move", 0.030, -18.0)
	assert_float(_freq(AudioSynth.make_ui_blip("move", RATE), 0.004, 0.026)).is_between(1450.0, 1750.0)


func test_confirm_blip_steps_880_to_1320hz_over_70ms_at_minus_14_dbfs() -> void:
	_assert_blip("confirm", 0.070, -14.0)
	var w := AudioSynth.make_ui_blip("confirm", RATE)
	assert_float(_freq(w, 0.004, 0.033)).is_between(800.0, 960.0)
	assert_float(_freq(w, 0.037, 0.066)).is_between(1220.0, 1420.0)


func test_back_blip_falls_1320_to_660hz_over_60ms_at_minus_16_dbfs() -> void:
	_assert_blip("back", 0.060, -16.0)
	var w := AudioSynth.make_ui_blip("back", RATE)
	assert_float(_freq(w, 0.003, 0.027)).is_greater(_freq(w, 0.033, 0.057))
	assert_float(_freq(w, 0.003, 0.010)).is_between(1150.0, 1450.0)
	assert_float(_freq(w, 0.048, 0.057)).is_between(560.0, 780.0)


func test_error_blip_is_220hz_square_90ms_at_minus_18_dbfs() -> void:
	_assert_blip("error", 0.090, -18.0)
	var w := AudioSynth.make_ui_blip("error", RATE)
	assert_float(_freq(w, 0.005, 0.080)).is_between(200.0, 240.0)
	# Square: most mid-blip samples sit at the full level.
	var amp := db_to_linear(-18.0) * 32767.0
	var flat := 0
	var a := int(0.02 * RATE)
	var b := int(0.07 * RATE)
	for i in range(a, b):
		if absf(absf(float(w.data.decode_s16(i * 2))) - amp) < amp * 0.02:
			flat += 1
	assert_float(float(flat) / float(b - a)).is_greater(0.9)


func test_unknown_blip_name_returns_null() -> void:
	assert_object(AudioSynth.make_ui_blip("nope", RATE)).is_null()


# ---- UiSounds ------------------------------------------------------------------------------

func test_ui_sounds_is_an_autoload() -> void:
	var n := get_tree().root.get_node_or_null("UiSounds")
	assert_object(n).is_not_null()
	assert_bool(n.has_method("play")).is_true()
	assert_bool(n.muted).is_false()


func test_play_uses_the_sfx_bus_and_sets_last_played() -> void:
	var s := _sounds()
	assert_str(String(s.bus_name())).is_equal("SFX")
	assert_bool(s.play("confirm")).is_true()
	assert_str(s.last_played).is_equal("confirm")
	assert_int(s.play_count).is_equal(1)
	var p: AudioStreamPlayer = s.last_player()
	assert_str(String(p.bus)).is_equal("SFX")
	assert_bool(p.stream is AudioStreamWAV).is_true()


func test_unknown_names_are_ignored() -> void:
	var s := _sounds()
	s.play("move")
	assert_bool(s.play("kaboom")).is_false()
	assert_str(s.last_played).is_equal("move")
	assert_int(s.play_count).is_equal(1)


func test_muted_play_does_nothing() -> void:
	var s := _sounds()
	s.muted = true
	assert_bool(s.play("move")).is_false()
	assert_str(s.last_played).is_equal("")
	assert_int(s.play_count).is_equal(0)


func test_accept_and_cancel_play_confirm_and_back_without_consuming() -> void:
	var s := _sounds()
	var acc := _action("ui_accept")
	s.handle_input(acc)
	assert_str(s.last_played).is_equal("confirm")
	s.handle_input(_action("ui_cancel"))
	assert_str(s.last_played).is_equal("back")
	# Releases do nothing.
	s.handle_input(_action("ui_accept", false))
	assert_int(s.play_count).is_equal(2)


func test_focus_move_after_a_navigation_press_plays_move() -> void:
	var s := _sounds()
	var b := Button.new()
	add_child(b)
	auto_free(b)
	s.handle_input(_action("ui_down"))
	s.on_focus_changed(b)
	assert_str(s.last_played).is_equal("move")


func test_programmatic_focus_without_navigation_is_silent() -> void:
	var s := _sounds()
	var b := Button.new()
	add_child(b)
	auto_free(b)
	s.on_focus_changed(b)
	assert_str(s.last_played).is_equal("")
	assert_int(s.play_count).is_equal(0)


func test_autoload_listens_to_viewport_focus_changes() -> void:
	var vp := get_tree().root
	assert_bool(vp.gui_focus_changed.is_connected(UiSounds.on_focus_changed)).is_true()


func test_nothing_plays_while_a_gameplay_runs() -> void:
	var s := _sounds()
	var g := Gameplay.new()
	auto_free(g)
	g.state = Gameplay.State.RUNNING
	s.scene_override = g
	assert_bool(s.suppressed()).is_true()
	assert_bool(s.play("move")).is_false()
	s.handle_input(_action("ui_accept"))
	s.handle_input(_action("ui_cancel"))
	assert_str(s.last_played).is_equal("")
	# Results / fail screens (the run is over) are menus again.
	g.state = Gameplay.State.DONE
	assert_bool(s.suppressed()).is_false()
	assert_bool(s.play("confirm")).is_true()


func test_calibration_measuring_mutes_ui_sounds() -> void:
	var w: CalibrationWizard = (load(WIZARD_SCENE) as PackedScene).instantiate()
	add_child(w)
	assert_bool(UiSounds.muted).is_false()
	w.show_step(CalibrationWizard.Step.AUDIO)
	assert_bool(UiSounds.muted).is_true()
	var before: String = UiSounds.last_played
	UiSounds.play("move")
	assert_str(UiSounds.last_played).is_equal(before)
	w.show_step(CalibrationWizard.Step.VISUAL)
	assert_bool(UiSounds.muted).is_true()
	w.show_step(CalibrationWizard.Step.SUMMARY)
	assert_bool(UiSounds.muted).is_false()
	w.show_step(CalibrationWizard.Step.AUDIO)
	assert_bool(UiSounds.muted).is_true()
	# Leaving the wizard (scene freed mid-measure) unmutes.
	remove_child(w)
	w.free()
	assert_bool(UiSounds.muted).is_false()
