class_name VisorFrame
extends ColorRect
## Full-screen alpha-only visor shader rect (D-03). Hidden under Settings.low_effects.

const SHADER_PATH := "res://shaders/visor.gdshader"


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var sh := load(SHADER_PATH) as Shader
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m
	else:
		color = Color(0, 0, 0, 0)
	if not Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.connect(apply_low_effects)
	apply_low_effects()


func _exit_tree() -> void:
	if Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.disconnect(apply_low_effects)


func apply_low_effects() -> void:
	visible = not Settings.low_effects
