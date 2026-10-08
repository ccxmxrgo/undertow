class_name VisorFrame
extends ColorRect
## Full-screen goggle lens shader rect (D-03, AV-01 visor portion, recording-frame look).
## Mask/alpha only, never samples the screen. Always visible. Low effects or reduce motion set
## the `effects` uniform to 0 (no scanlines, grain, sweep or slice jitter) and disable the
## glitch burst; the lens mask, red rim (with its static RGB split) and vignette stay.

const SHADER_PATH := "res://shaders/visor.gdshader"
## Highway x 672..1248 plus its 48px margin (UI-SPEC): the shader is exactly 0 in here.
const CLEAR_RECT := Rect2(624.0, 0.0, 672.0, 1080.0)
## Miss / hull-damage glitch burst length (frame only, never the highway).
const GLITCH_SEC := 0.12

var _glitch_until_usec: int = 0
var _glitch_live: bool = false


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var sh := load(SHADER_PATH) as Shader
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter(&"clear_rect", Vector4(CLEAR_RECT.position.x, CLEAR_RECT.position.y,
			CLEAR_RECT.size.x, CLEAR_RECT.size.y))
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
	visible = true
	var m := material as ShaderMaterial
	if m != null:
		m.set_shader_parameter(&"effects", 0.0 if _calm() else 1.0)
	if _calm():
		_glitch_until_usec = 0
		_set_glitch(0.0)


func _calm() -> bool:
	return Settings.low_effects or Settings.reduce_motion


## Whether a miss / damage burst would play (false under Low effects or reduce motion).
func glitch_enabled() -> bool:
	return not _calm()


## Start a GLITCH_SEC burst (RGB split + slice offset on the frame). No-op when calm.
func trigger_glitch() -> void:
	if _calm():
		return
	_glitch_until_usec = Time.get_ticks_usec() + int(GLITCH_SEC * 1000000.0)
	_set_glitch(1.0)


func glitch_active() -> bool:
	return _glitch_live


func _process(_delta: float) -> void:
	if _glitch_live:
		update_glitch(Time.get_ticks_usec())


## Decay the burst linearly to 0 at its end time (now passed in for deterministic tests).
func update_glitch(now_usec: int) -> void:
	var left := _glitch_until_usec - now_usec
	_set_glitch(clampf(float(left) / (GLITCH_SEC * 1000000.0), 0.0, 1.0) if left > 0 else 0.0)


func _set_glitch(v: float) -> void:
	_glitch_live = v > 0.0
	var m := material as ShaderMaterial
	if m != null:
		m.set_shader_parameter(&"glitch", v)


## True while the animated / expensive layers (scanlines, sweep, chromatic tint) are on.
func effects_enabled() -> bool:
	var m := material as ShaderMaterial
	if m == null:
		return false
	return float(m.get_shader_parameter(&"effects")) > 0.5
