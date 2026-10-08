extends GdUnitTestSuite
## Visor shader, VisorFrame and VisorBrackets (D-03, T-1.1-07/08).

var _saved_low := false


func before_test() -> void:
	_saved_low = Settings.low_effects


func after_test() -> void:
	Settings.low_effects = _saved_low


func test_shader_loads_and_is_alpha_only() -> void:
	var sh := load("res://shaders/visor.gdshader") as Shader
	assert_object(sh).is_not_null()
	assert_str(sh.code).contains("shader_type canvas_item")
	assert_bool(sh.code.contains("hint_screen_texture")).is_false()
	assert_bool(sh.code.contains("screen_texture")).is_false()


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


func test_frame_ignores_mouse_and_has_shader() -> void:
	Settings.low_effects = false
	var f := _frame()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(f.material is ShaderMaterial).is_true()
	assert_object((f.material as ShaderMaterial).shader).is_equal(load("res://shaders/visor.gdshader"))
	assert_bool(f.visible).is_true()


func test_frame_hidden_in_low_effects() -> void:
	Settings.low_effects = true
	var f := _frame()
	assert_bool(f.visible).is_false()
	Settings.low_effects = false
	f.apply_low_effects()
	assert_bool(f.visible).is_true()


func test_brackets_readouts_follow_low_effects() -> void:
	Settings.low_effects = false
	var b := _brackets()
	assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(b.readouts_visible()).is_true()
	assert_bool(b.brackets_visible()).is_true()
	Settings.low_effects = true
	b.apply_low_effects()
	assert_bool(b.readouts_visible()).is_false()
	assert_bool(b.brackets_visible()).is_true()


func test_nodes_react_to_settings_changed() -> void:
	Settings.low_effects = false
	var f := _frame()
	var b := _brackets()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_bool(f.visible).is_false()
	assert_bool(b.readouts_visible()).is_false()
	Settings.low_effects = false
	Settings.settings_changed.emit()
	assert_bool(f.visible).is_true()
	assert_bool(b.readouts_visible()).is_true()
