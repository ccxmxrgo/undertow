class_name LogoWordmark
extends TextureRect
## The menu "UNDERTOW" wordmark (02.2 UI-SPEC section 5 "Logo"): the generated wordmark PNG
## (tools/make_wordmark.gd, rendered from the OFL Oxanium font) drawn in the 960 x 152 rect
## at (120, 168), tinted TEXT_HI, with logo_shimmer.gdshader and an additive SONAR 25% glow
## sprite behind it (child "Glow", show_behind_parent).
## Effect node (UiKit contract): Low effects = no shimmer, glow hidden; Reduce motion = no
## shimmer (the static glow stays, UI-SPEC 11 "glow sprites: on" under Reduce motion).

const WORDMARK_PATH := "res://assets/ui/undertow_wordmark.png"
const GLOW_PATH := "res://assets/ui/undertow_wordmark_glow.png"
const SHADER_PATH := "res://shaders/logo_shimmer.gdshader"
const RECT := Rect2(120.0, 168.0, 960.0, 152.0)
const GLOW_ALPHA := 0.25
const WOBBLE_PX := 2.0

var glow: TextureRect

var _shimmer := true


func _init() -> void:
	name = "Logo"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture = load(WORDMARK_PATH) as Texture2D
	position = RECT.position
	size = RECT.size
	self_modulate = Palette.TEXT_HI
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter("caustic_color", Palette.SONAR_PALE)
	mat.set_shader_parameter("wobble_uv", WOBBLE_PX / RECT.size.y)
	mat.set_shader_parameter("time_scale", 1.0)
	material = mat
	glow = TextureRect.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glow.texture = load(GLOW_PATH) as Texture2D
	glow.show_behind_parent = true
	glow.material = UiKit.additive_material()
	glow.self_modulate = Color(Palette.SONAR, GLOW_ALPHA)
	glow.position = Vector2.ZERO
	glow.size = RECT.size
	add_child(glow)


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	apply_effect_settings()
	UiKit.register_fx(self)


## Effect contract: shimmer off on Low effects or Reduce motion; glow hidden on Low effects.
func apply_effect_settings() -> void:
	var low := UiKit.low_effects()
	_shimmer = not (low or UiKit.reduce_motion())
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("enabled", _shimmer)
	glow.visible = not low


## Effect contract: what is active right now.
func effect_counts() -> Dictionary:
	return {"shimmer": _shimmer, "glow": glow.visible}


## Fade in over DUR_SLOW (first show of the menu). Returns the tween or null outside the tree.
func fade_in() -> Tween:
	if not is_inside_tree():
		return null
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, Palette.DUR_SLOW) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw
