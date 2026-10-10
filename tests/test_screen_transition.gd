extends GdUnitTestSuite
## ScreenTransition (02.2 plan 22, UI-SPEC 9.7 / 11, D-13, VIS-09, AV-05): the sonar wipe
## (cover 150 ms cubic-in, swap at full cover, reveal 150 ms cubic-out, hard cap 400 ms),
## input consumption during the cover, the instant flag, the Reduce-motion cross-fade, the
## Low-effects glow switch, the failsafe and the effect contract.
## Each test drives a fresh instance with a fake clock and a swap seam, so no real scene changes.

const SCRIPT := "res://src/ui/screen_transition.gd"
const TARGET := "res://scenes/does_not_matter.tscn"

var _low := false
var _reduce := false
var _now := 0.0
var _swaps: Array = []
var _finished := 0


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false
	_now = 0.0
	_swaps = []
	_finished = 0


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce


func _st() -> Node:
	var st: Node = load(SCRIPT).new()
	st.clock_fn = func() -> float: return _now
	st.swap_fn = func(p: String) -> void: _swaps.append(p)
	add_child(st)
	auto_free(st)
	st.finished.connect(func() -> void: _finished += 1)
	return st


func _at(st: Node, ms: float) -> void:
	_now = ms
	st.step()


func _key(code: int, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.pressed = pressed
	return e


# ---- autoload and idle state ---------------------------------------------------------------

func test_autoload_is_registered_on_layer_100() -> void:
	assert_bool(ProjectSettings.has_setting("autoload/ScreenTransition")).is_true()
	assert_str(str(ProjectSettings.get_setting("autoload/ScreenTransition"))).is_equal("*" + SCRIPT)
	var st := get_tree().root.get_node_or_null("ScreenTransition")
	assert_object(st).is_not_null()
	assert_bool(st is CanvasLayer).is_true()
	assert_int((st as CanvasLayer).layer).is_equal(100)
	assert_bool(st.is_in_group(UiKit.FX_GROUP)).is_true()


func test_idle_is_invisible_and_ignores_the_mouse() -> void:
	var st := _st()
	assert_int(st.layer).is_equal(100)
	assert_bool(st.is_busy()).is_false()
	assert_bool(st.rect.visible).is_false()
	assert_int(st.rect.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_str(st.rect.material.shader.resource_path).is_equal("res://shaders/sonar_wipe.gdshader")


func test_shader_has_uniforms_and_no_colour_literals() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sonar_wipe.gdshader")
	assert_bool(src.is_empty()).is_false()
	for u in ["centre", "radius", "edge_px", "fill_color", "edge_color", "reveal", "glow"]:
		assert_bool(src.contains("uniform") and src.contains(u)).override_failure_message("missing " + u).is_true()
	var re := RegEx.create_from_string("vec[34][ ]*[(][ ]*[-0-9.]")
	assert_object(re.search(src)).is_null()
	assert_bool(src.contains("hint_screen_texture")).is_false()


func test_shader_colours_come_from_palette() -> void:
	var st := _st()
	var mat := st.rect.material as ShaderMaterial
	assert_bool(Color(mat.get_shader_parameter("fill_color")).is_equal_approx(Palette.ABYSS_900)).is_true()
	assert_bool(Color(mat.get_shader_parameter("edge_color")).is_equal_approx(Palette.SONAR_PALE)).is_true()
	assert_float(float(mat.get_shader_parameter("edge_px"))).is_equal_approx(6.0, 0.001)


# ---- wipe timeline ---------------------------------------------------------------------------

func test_wipe_covers_swaps_reveals_and_finishes_in_300_ms() -> void:
	var st := _st()
	assert_bool(st.change_scene(TARGET, Vector2(100, 200))).is_true()
	assert_bool(st.is_busy()).is_true()
	assert_str(st.phase()).is_equal("cover")
	assert_bool(st.rect.visible).is_true()
	assert_vector(st.centre).is_equal(Vector2(100, 200))
	_at(st, 75.0)
	# cubic-in: 2200 * 0.5^3 = 275
	assert_float(st.radius).is_equal_approx(275.0, 1.0)
	assert_bool(st.rect.material.get_shader_parameter("reveal")).is_false()
	assert_array(_swaps).is_empty()
	_at(st, 150.0)
	assert_array(_swaps).is_equal([TARGET])
	assert_str(st.phase()).is_equal("reveal")
	_at(st, 225.0)
	# cubic-out over the reveal: 2200 * (1 - 0.5^3) = 1925
	assert_float(st.radius).is_equal_approx(1925.0, 1.0)
	assert_bool(st.rect.material.get_shader_parameter("reveal")).is_true()
	assert_int(_finished).is_equal(0)
	_at(st, 300.0)
	assert_bool(st.is_busy()).is_false()
	assert_bool(st.rect.visible).is_false()
	assert_int(_finished).is_equal(1)
	assert_int(st.last_duration_msec).is_less_equal(400)
	assert_array(_swaps).is_equal([TARGET])


func test_radius_reaches_2200_at_full_cover() -> void:
	var st := _st()
	st.change_scene(TARGET)
	_at(st, 149.9)
	assert_float(st.radius).is_greater(2190.0)
	assert_float(st.radius).is_less_equal(2200.0)


func test_default_focal_is_screen_centre_without_focus() -> void:
	var st := _st()
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null:
		owner.release_focus()
	st.change_scene(TARGET)
	assert_vector(st.centre).is_equal(Vector2(960, 540))


func test_default_focal_is_the_focused_control_centre() -> void:
	var st := _st()
	var b := Button.new()
	b.position = Vector2(128, 416)
	b.size = Vector2(512, 64)
	add_child(b)
	auto_free(b)
	b.grab_focus()
	st.change_scene(TARGET)
	assert_vector(st.centre).is_equal_approx(Vector2(384, 448), Vector2(0.5, 0.5))
	b.release_focus()


func test_second_change_scene_does_not_double_swap() -> void:
	var st := _st()
	assert_bool(st.change_scene(TARGET)).is_true()
	_at(st, 60.0)
	assert_bool(st.change_scene("res://scenes/other.tscn")).is_false()
	_at(st, 150.0)
	_at(st, 200.0)
	assert_bool(st.change_scene("res://scenes/other.tscn")).is_false()
	_at(st, 300.0)
	assert_array(_swaps).is_equal([TARGET])
	assert_int(_finished).is_equal(1)


func test_failsafe_forces_idle_after_400_ms() -> void:
	var st := _st()
	st.swap_starts_reveal = false  # simulate a scene_changed that never arrives
	st.change_scene(TARGET)
	_at(st, 150.0)
	assert_array(_swaps).is_equal([TARGET])
	assert_str(st.phase()).is_equal("cover")
	_at(st, 399.0)
	assert_bool(st.is_busy()).is_true()
	_at(st, 400.0)
	assert_bool(st.is_busy()).is_false()
	assert_bool(st.rect.visible).is_false()
	assert_int(_finished).is_equal(1)
	assert_int(st.last_duration_msec).is_less_equal(400)


func test_failsafe_swaps_once_when_frames_stall_in_the_cover() -> void:
	var st := _st()
	st.change_scene(TARGET)
	_at(st, 500.0)  # one huge frame: the swap still happens exactly once, then idle
	assert_array(_swaps).is_equal([TARGET])
	assert_bool(st.is_busy()).is_false()
	assert_int(_finished).is_equal(1)


# ---- input ---------------------------------------------------------------------------------

func test_key_press_during_cover_is_consumed_and_jumps_to_the_end() -> void:
	var st := _st()
	st.change_scene(TARGET)
	await get_tree().process_frame  # not the frame that started the wipe
	_at(st, 40.0)
	assert_bool(st.handle_input(_key(KEY_DOWN))).is_true()
	assert_array(_swaps).is_equal([TARGET])
	assert_bool(st.is_busy()).is_false()
	assert_bool(st.rect.visible).is_false()
	assert_int(_finished).is_equal(1)


func test_joypad_button_during_cover_is_consumed_and_skips() -> void:
	var st := _st()
	st.change_scene(TARGET)
	await get_tree().process_frame
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	assert_bool(st.handle_input(e)).is_true()
	assert_array(_swaps).is_equal([TARGET])
	assert_bool(st.is_busy()).is_false()


func test_release_during_cover_is_consumed_without_skipping() -> void:
	var st := _st()
	st.change_scene(TARGET)
	await get_tree().process_frame
	_at(st, 40.0)
	assert_bool(st.handle_input(_key(KEY_ENTER, false))).is_true()
	assert_array(_swaps).is_empty()
	assert_str(st.phase()).is_equal("cover")


func test_the_press_that_started_the_wipe_does_not_skip_it() -> void:
	var st := _st()
	st.change_scene(TARGET)
	st.handle_input(_key(KEY_ESCAPE))  # same frame (a scene _input that called change_scene)
	assert_array(_swaps).is_empty()
	assert_str(st.phase()).is_equal("cover")


func test_input_reaches_the_new_scene_from_the_start_of_the_reveal() -> void:
	var st := _st()
	st.change_scene(TARGET)
	_at(st, 150.0)
	assert_str(st.phase()).is_equal("reveal")
	await get_tree().process_frame
	assert_bool(st.handle_input(_key(KEY_DOWN))).is_false()
	assert_bool(st.is_busy()).is_false()  # the press also completes the reveal visually
	assert_int(_finished).is_equal(1)


func test_idle_never_consumes_input() -> void:
	var st := _st()
	assert_bool(st.handle_input(_key(KEY_DOWN))).is_false()
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	assert_bool(st.handle_input(m)).is_false()


# ---- instant, Reduce motion, Low effects ---------------------------------------------------

func test_instant_swaps_without_animation() -> void:
	var st := _st()
	st.instant = true
	assert_bool(st.change_scene(TARGET)).is_true()
	assert_array(_swaps).is_equal([TARGET])
	assert_bool(st.is_busy()).is_false()
	assert_bool(st.rect.visible).is_false()
	assert_int(_finished).is_equal(1)


func test_reduce_motion_is_a_160_ms_cross_fade_without_ring() -> void:
	Settings.reduce_motion = true
	var st := _st()
	st.change_scene(TARGET)
	assert_str(st.mode()).is_equal("crossfade")
	assert_object(st.rect.material).is_null()
	_at(st, 40.0)
	assert_float(st.rect.color.a).is_equal_approx(0.5, 0.01)
	assert_bool(Color(st.rect.color, 1.0).is_equal_approx(Palette.ABYSS_900)).is_true()
	assert_array(_swaps).is_empty()
	_at(st, 80.0)
	assert_array(_swaps).is_equal([TARGET])
	_at(st, 120.0)
	assert_float(st.rect.color.a).is_equal_approx(0.5, 0.01)
	_at(st, 160.0)
	assert_bool(st.is_busy()).is_false()
	assert_int(_finished).is_equal(1)
	assert_int(st.last_duration_msec).is_less_equal(160)


func test_low_effects_wipe_has_ring_but_no_glow() -> void:
	Settings.low_effects = true
	var st := _st()
	st.change_scene(TARGET)
	assert_str(st.mode()).is_equal("wipe")
	var mat := st.rect.material as ShaderMaterial
	assert_bool(mat.get_shader_parameter("glow")).is_false()
	assert_float(float(mat.get_shader_parameter("edge_px"))).is_equal_approx(6.0, 0.001)


func test_full_wipe_has_glow() -> void:
	var st := _st()
	st.change_scene(TARGET)
	assert_bool((st.rect.material as ShaderMaterial).get_shader_parameter("glow")).is_true()


func test_effect_counts_follow_settings_changed() -> void:
	var st := _st()
	assert_bool(st.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_dict(st.effect_counts()).is_equal({"glow": true, "crossfade": false})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(st.effect_counts()).is_equal({"glow": false, "crossfade": false})
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	assert_dict(st.effect_counts()).is_equal({"glow": true, "crossfade": true})
