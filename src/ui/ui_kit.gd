class_name UiKit
extends RefCounted
## Shared UI component kit (02.2 UI-SPEC section 4). Every style is built from Palette
## tokens; no colour literals here (VIS-01). Plan 04: theme, glass panel, button states.
## Plan 05 adds make_button (icons), chips, brackets, glow texture and the focus marker.

const PANEL_VARIANTS: Array[String] = ["default", "danger", "reward"]
const BUTTON_STATES: Array[String] = ["normal", "hover", "focus", "pressed", "disabled"]
const BUTTON_VARIANTS: Array[String] = ["default", "primary", "destructive"]

const PANEL_PAD := Palette.SP_LG  # 24 px panel padding (4.1)
const BUTTON_PAD_X := Palette.SP_MD
const BUTTON_PAD_Y := Palette.SP_SM

## Built themes keyed by the low-effects flag (Full has panel/focus glow, Low has none).
static var _themes: Dictionary = {}


## True when the Low effects setting is on (no glow shadows). Safe without the autoload.
static func low_effects() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var s := tree.root.get_node_or_null(^"Settings")
	return s != null and bool(s.get("low_effects"))


## Chamfered StyleBoxFlat: top-left and bottom-right cut by `cut`, other corners square
## (UI-SPEC 2 chamfer rule; corner_detail 1 = one straight 45 degree segment).
static func chamfer_box(fill: Color, edge: Color, edge_w: int, cut: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(edge_w)
	sb.corner_radius_top_left = cut
	sb.corner_radius_bottom_right = cut
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_detail = 1
	sb.anti_aliasing = true
	return sb


static func _glow(sb: StyleBoxFlat, color: Color, a: float, low: bool) -> void:
	sb.shadow_color = Color(color, a)
	sb.shadow_size = 0 if low else Palette.PANEL_GLOW_SIZE
	sb.shadow_offset = Vector2.ZERO


## Glass panel (UI-SPEC 4.1): ABYSS_700 at 82%, 2 px SONAR 45% edge (danger: WARNING_RED
## 60%), CUT_MD chamfer, SONAR glow 18% size 12 (none on Low effects), 24 px padding.
## Variants: "default", "danger", "reward" (reward differs only in its brackets, plan 05).
static func style_panel(variant: String = "default", low: Variant = null) -> StyleBoxFlat:
	var is_low: bool = low_effects() if low == null else bool(low)
	var edge := Color(Palette.SONAR, 0.45)
	if variant == "danger":
		edge = Color(Palette.WARNING_RED, 0.6)
	var sb := chamfer_box(Color(Palette.ABYSS_700, Palette.PANEL_ALPHA), edge, Palette.EDGE, Palette.CUT_MD)
	_glow(sb, Palette.SONAR, Palette.PANEL_GLOW_ALPHA, is_low)
	sb.set_content_margin_all(PANEL_PAD)
	return sb


## Button state style (UI-SPEC 4.2). state: normal | hover | focus | pressed | disabled;
## variant: default | primary | destructive. CUT_SM chamfer, 2 px edge.
static func style_button(state: String, variant: String = "default", low: Variant = null) -> StyleBoxFlat:
	var is_low: bool = low_effects() if low == null else bool(low)
	var fill: Color
	var edge: Color
	var glow_a := 0.0
	var glow_col := Palette.SONAR
	match state:
		"hover":
			fill = Color(Palette.ABYSS_700, 0.85)
			edge = Color(Palette.SONAR, 0.6)
		"focus":
			fill = Color(Palette.ABYSS_600, 0.92)
			edge = Palette.SONAR
			glow_a = Palette.PANEL_GLOW_FOCUS
		"pressed":
			fill = Palette.mix(Palette.ABYSS_600, Palette.SONAR, 0.22)
			edge = Palette.SONAR_PALE
		"disabled":
			fill = Color(Palette.ABYSS_800, 0.5)
			edge = Color(Palette.TEXT_LO, 0.2)
		_:
			fill = Color(Palette.ABYSS_700, 0.7)
			edge = Color(Palette.SONAR, 0.3)
	if variant == "primary" and (state == "normal" or state == "hover"):
		fill = Palette.mix(Palette.ABYSS_600, Palette.SONAR, 0.14)
		edge = Palette.SONAR if state == "hover" else Color(Palette.SONAR, 0.8)
	elif variant == "destructive" and state != "disabled":
		glow_col = Palette.WARNING_RED
		match state:
			"hover":
				edge = Color(Palette.WARNING_RED, 0.8)
			"focus":
				fill = Color(Palette.WARNING_RED, 0.16)
				edge = Palette.WARNING_RED
			"pressed":
				fill = Palette.mix(Palette.ABYSS_600, Palette.WARNING_RED, 0.22)
				edge = Palette.WARNING_RED
			_:
				edge = Color(Palette.WARNING_RED, 0.6)
	var sb := chamfer_box(fill, edge, Palette.EDGE, Palette.CUT_SM)
	if glow_a > 0.0:
		_glow(sb, glow_col, glow_a, is_low)
	sb.content_margin_left = BUTTON_PAD_X
	sb.content_margin_right = BUTTON_PAD_X
	sb.content_margin_top = BUTTON_PAD_Y
	sb.content_margin_bottom = BUTTON_PAD_Y
	return sb


## Button text colour per state (UI-SPEC 4.2).
static func button_font_color(state: String, variant: String = "default") -> Color:
	match state:
		"hover", "focus":
			return Palette.TEXT_HI
		"pressed":
			return Palette.SONAR_PALE
		"disabled":
			return Color(Palette.TEXT_LO, 0.6)
	return Palette.TEXT_HI if variant != "default" else Palette.TEXT_MID


## Apply a non-default button variant to one Button through theme overrides.
static func apply_button_variant(b: Button, variant: String) -> void:
	for st in BUTTON_STATES:
		b.add_theme_stylebox_override(st, style_button(st, variant))
	b.add_theme_color_override("font_color", button_font_color("normal", variant))


static func _font_variation(base: Font, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	return v


## The shared Theme built from tokens (UI-SPEC 3.2, 4.1, 4.2). Cached per effects level.
## ui/undertow_theme.tres is this theme with low = false, saved by tools/make_theme.gd.
static func build_theme(low: bool = false) -> Theme:
	if _themes.has(low):
		return _themes[low]
	var t := Theme.new()
	t.default_font = Palette.font()
	t.default_font_size = Palette.SIZE_BODY

	# Type variations (3.2).
	t.set_color("font_color", "Label", Palette.TEXT_MID)
	t.set_font_size("font_size", "Label", Palette.SIZE_BODY)
	for v in ["CaptionLabel", "HeadingLabel", "DisplayLabel"]:
		t.set_type_variation(v, "Label")
	t.set_color("font_color", "CaptionLabel", Palette.TEXT_LO)
	t.set_font_size("font_size", "CaptionLabel", Palette.SIZE_LABEL)
	t.set_font("font", "CaptionLabel", _font_variation(Palette.font(), 2))
	t.set_color("font_color", "HeadingLabel", Palette.TEXT_HI)
	t.set_font_size("font_size", "HeadingLabel", Palette.SIZE_HEADING)
	t.set_font("font", "HeadingLabel", Palette.display_font())
	t.set_color("font_color", "DisplayLabel", Palette.TEXT_HI)
	t.set_font_size("font_size", "DisplayLabel", Palette.SIZE_DISPLAY)
	t.set_font("font", "DisplayLabel", Palette.display_font())

	# Buttons (4.2): Body 28 STM bold.
	t.set_font("font", "Button", Palette.bold())
	t.set_font_size("font_size", "Button", Palette.SIZE_BODY)
	t.set_constant("h_separation", "Button", Palette.SP_SM)
	for st in BUTTON_STATES:
		t.set_stylebox(st, "Button", style_button(st, "default", low))
	t.set_color("font_color", "Button", button_font_color("normal"))
	t.set_color("font_hover_color", "Button", button_font_color("hover"))
	t.set_color("font_focus_color", "Button", button_font_color("focus"))
	t.set_color("font_pressed_color", "Button", button_font_color("pressed"))
	t.set_color("font_hover_pressed_color", "Button", button_font_color("pressed"))
	t.set_color("font_disabled_color", "Button", button_font_color("disabled"))

	# Panels (4.1).
	var panel := style_panel("default", low)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)

	# Progress bars: deep tube with a hairline edge, SONAR fill.
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.ABYSS_800
	track.border_color = Color(Palette.SONAR, 0.3)
	track.set_border_width_all(Palette.EDGE_HAIR)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.SONAR
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)

	# Layout constants (kept from the Phase 1 theme).
	t.set_constant("separation", "VBoxContainer", Palette.SP_MD)
	t.set_constant("separation", "HBoxContainer", Palette.SP_MD)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		t.set_constant(side, "MarginContainer", Palette.SP_XL)
	_themes[low] = t
	return t
