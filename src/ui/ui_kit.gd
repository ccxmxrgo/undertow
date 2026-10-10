class_name UiKit
extends RefCounted
## Shared UI component kit (02.2 UI-SPEC section 4). Every style is built from Palette
## tokens; no colour literals here (VIS-01). Plan 04: theme, glass panel, button states.
## Plan 05: make_button (icons, variants, press squash), chips, corner brackets, the glow
## texture, the additive material, fixed numeral boxes, pop_in and the effect contract.
## The focus marker is FocusMarker (src/ui/focus_marker.gd); icons are UiIcons.
##
## Effect-settings contract (AV-05, UI-SPEC 11). Every effect node of the phase:
##   1. calls UiKit.register_fx(self) in _ready (this puts it in FX_GROUP),
##   2. implements apply_effect_settings(): re-reads Settings.low_effects and
##      Settings.reduce_motion and reconfigures itself (called on every
##      Settings.settings_changed while the node is inside the tree),
##   3. implements effect_counts() -> Dictionary: what is active right now (particle
##      counts, bool flags), so tests can enumerate FX_GROUP and check Low/Reduce.
## register_fx connects on tree entry and disconnects on tree exit, so a freed or
## detached node never receives the signal (T-02.2-49).

const PANEL_VARIANTS: Array[String] = ["default", "danger", "reward"]
const BUTTON_STATES: Array[String] = ["normal", "hover", "focus", "pressed", "disabled"]
const BUTTON_VARIANTS: Array[String] = ["default", "primary", "destructive"]

const PANEL_PAD := Palette.SP_LG  # 24 px panel padding (4.1)
const BUTTON_PAD_X := Palette.SP_MD
const BUTTON_PAD_Y := Palette.SP_SM

const FX_GROUP := &"fx_settings_aware"

## make_button geometry (UI-SPEC 4.2): icon box 24x24 at x+24, label at x+64.
const ICON_BOX := 24
const ICON_X := 24
const ICON_LABEL_X := 64
const PRESS_SCALE := 0.98
const PRESS_SEC := 0.08

## Chips (UI-SPEC 4.4).
const CHIP_H := 32
const CHIP_PAD_X := 12
const CHIP_GLYPH := 16
const CHIP_GLYPH_GAP := Palette.SP_XS
const CHIP_SPACING := 1

## pop_in peak scale (UI-SPEC 10 item 1).
const POP_SCALE := 1.06

## Glow texture (UI-SPEC 3.3).
const GLOW_SIZE := 128
const GLOW_OFFSETS: Array[float] = [0.0, 0.25, 0.6, 1.0]
const GLOW_ALPHAS: Array[float] = [1.0, 0.55, 0.12, 0.0]

static var _glow_tex: GradientTexture2D
static var _additive: CanvasItemMaterial
static var _chip_font: FontVariation

## Built themes keyed by the low-effects flag (Full has panel/focus glow, Low has none).
static var _themes: Dictionary = {}


## The Settings autoload, or null (tool scripts run without autoloads).
static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"Settings")


## True when the Low effects setting is on (no glow shadows). Safe without the autoload.
static func low_effects() -> bool:
	var s := _settings()
	return s != null and bool(s.get("low_effects"))


## True when the Reduce motion setting is on. Safe without the autoload.
static func reduce_motion() -> bool:
	var s := _settings()
	return s != null and bool(s.get("reduce_motion"))


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


# ---- Plan 05: buttons with icons ------------------------------------------------------

## Icon colour per button state (UI-SPEC 4.2 "Extra" column).
static func icon_color(state: String, variant: String = "default") -> Color:
	match state:
		"hover", "focus":
			return Palette.WARNING_RED if variant == "destructive" else Palette.SONAR
		"pressed":
			return Palette.SONAR_PALE
		"disabled":
			return Color(Palette.TEXT_LO, 0.6)
	return Palette.TEXT_LO


## Draws a button's icon in the colour of the button's current state.
class ButtonIcon:
	extends Control
	var icon_name := ""

	func _ready() -> void:
		var b := get_parent() as Button
		if b == null:
			return
		for sig: Signal in [b.mouse_entered, b.mouse_exited, b.focus_entered, b.focus_exited,
				b.button_down, b.button_up]:
			sig.connect(queue_redraw)

	func _draw() -> void:
		var b := get_parent() as Button
		var state := "normal"
		var variant := "default"
		if b != null:
			variant = String(b.get_meta(&"ui_variant", "default"))
			if b.disabled:
				state = "disabled"
			elif b.is_pressed():
				state = "pressed"
			elif b.has_focus():
				state = "focus"
			elif b.is_hovered():
				state = "hover"
		UiIcons.draw(self, icon_name, Rect2(Vector2.ZERO, size), UiKit.icon_color(state, variant))


## Button (UI-SPEC 4.2). height 64 (menu, pause, fail, results, dialogs) or 48 (rows).
## With an icon the label is left-aligned at x+64 and a 24x24 icon sits at x+24,
## vertically centred; without one the label is centred. variant: default | primary |
## destructive. Pressing squashes to 0.98 for 80 ms unless Reduce motion is on.
static func make_button(text: String, icon: String = "", variant: String = "default", height: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta(&"ui_variant", variant)
	b.set_meta(&"ui_icon", icon)
	if variant != "default":
		b.add_theme_color_override("font_color", button_font_color("normal", variant))
	if icon != "" or variant != "default":
		for st in BUTTON_STATES:
			var sb := style_button(st, variant)
			if icon != "":
				sb.content_margin_left = ICON_LABEL_X
			b.add_theme_stylebox_override(st, sb)
	if icon != "":
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ic := ButtonIcon.new()
		ic.name = "Icon"
		ic.icon_name = icon
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = Vector2(ICON_X, (height - ICON_BOX) * 0.5)
		ic.size = Vector2(ICON_BOX, ICON_BOX)
		b.add_child(ic)
	else:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.button_down.connect(func() -> void: press_squash(b))
	return b


## Press squash: scale 0.98 and back over 80 ms around the centre. Returns the tween, or
## null under Reduce motion (no scale change) or when the control is not in the tree.
static func press_squash(c: Control) -> Tween:
	if c == null:
		return null
	if reduce_motion() or not c.is_inside_tree():
		c.scale = Vector2.ONE
		return null
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * PRESS_SCALE, PRESS_SEC * 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, PRESS_SEC * 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


# ---- Corner brackets and chips --------------------------------------------------------

## The two bracket polylines for `rect`: [top-right, bottom-left], each 3 points with
## BRACKET_ARM arms, inset by half the stroke so the 2 px line sits on the edge.
static func bracket_points(rect: Rect2) -> Array[PackedVector2Array]:
	var r := rect.grow(-Palette.EDGE * 0.5)
	var arm := float(Palette.BRACKET_ARM)
	var tr := PackedVector2Array([
		Vector2(r.end.x - arm, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.position.y + arm)])
	var bl := PackedVector2Array([
		Vector2(r.position.x, r.end.y - arm), Vector2(r.position.x, r.end.y),
		Vector2(r.position.x + arm, r.end.y)])
	return [tr, bl]


## Corner brackets on the un-chamfered corners (TR and BL), 20 px arms, 2 px (UI-SPEC 4.1).
## Default panels pass SONAR at 80%; danger WARNING_RED at 80%; reward REWARD_GOLD.
static func draw_brackets(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	for arm in bracket_points(rect):
		ci.draw_polyline(arm, color, Palette.EDGE, true)


## Outline of a rect with the top-left and bottom-right corners cut by `cut`.
static func chamfer_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x, p.y), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x, e.y), Vector2(p.x, p.y + cut)])


## Chip colours (UI-SPEC 4.4) as {edge, fill, text}. `lane` is used by "difficulty".
static func chip_style(variant: String, lane: int = -1) -> Dictionary:
	match variant:
		"info":
			return {"edge": Color(Palette.SONAR, 0.6), "fill": Color(Palette.ABYSS_700, 0.8), "text": Palette.SONAR}
		"reward":
			return {"edge": Palette.REWARD_GOLD, "fill": Color(Palette.REWARD_GOLD, 0.14), "text": Palette.REWARD_GOLD}
		"muted":
			return {"edge": Color(Palette.TEXT_LO, 0.4), "fill": Color(Palette.TEXT_LO, 0.0), "text": Palette.TEXT_LO}
		"difficulty":
			var lc := Palette.lane_color(maxi(lane, 0))
			return {"edge": lc, "fill": Color(lc, 0.12), "text": Palette.TEXT_HI}
	return {"edge": Color(Palette.TEXT_MID, 0.7), "fill": Color(Palette.ABYSS_700, 0.8), "text": Palette.TEXT_HI}


## Chip label font: Share Tech Mono with +1 px letter spacing (Label 20 UPPERCASE).
static func chip_font() -> Font:
	if _chip_font == null:
		_chip_font = _font_variation(Palette.font(), CHIP_SPACING)
	return _chip_font


## Natural chip width for `text` (padding 12 each side; difficulty adds a 16 px glyph + 4).
static func chip_width(text: String, variant: String = "mode") -> float:
	var w := chip_font().get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	w += CHIP_PAD_X * 2
	if variant == "difficulty":
		w += CHIP_GLYPH + CHIP_GLYPH_GAP
	return w


## Chip (UI-SPEC 4.4): CUT_SM chamfer, 2 px edge, Label 20 UPPERCASE text. Variants:
## mode | info | reward | muted | difficulty (lane colour, 16 px lane glyph at left).
static func draw_chip(ci: CanvasItem, rect: Rect2, text: String, variant: String = "mode", lane: int = -1) -> void:
	var st := chip_style(variant, lane)
	var outline := chamfer_points(rect, Palette.CUT_SM)
	var fill: Color = st.fill
	if fill.a > 0.0:
		ci.draw_colored_polygon(outline, fill)
	var closed := outline.duplicate()
	closed.append(outline[0])
	ci.draw_polyline(closed, st.edge, Palette.EDGE, true)
	var x := rect.position.x + CHIP_PAD_X
	var cy := rect.position.y + rect.size.y * 0.5
	if variant == "difficulty":
		var g := CHIP_GLYPH * 0.5
		var c := Vector2(x + g, cy)
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0)]), st.edge)
		x += CHIP_GLYPH + CHIP_GLYPH_GAP
	var f := chip_font()
	var fs := Palette.SIZE_LABEL
	var base := cy + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	var max_w := maxf(rect.end.x - CHIP_PAD_X - x, 1.0)
	ci.draw_string(f, Vector2(x, base), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, st.text)


# ---- Glow, numerals, pop ---------------------------------------------------------------

## The one shared 128x128 radial white glow (UI-SPEC 3.3 GLOW_TEX). Tint with modulate,
## draw with additive_material(). Sizes/alphas: Palette.GLOW_SM / GLOW_MD / GLOW_LG.
static func glow_texture() -> GradientTexture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := Gradient.new()
	var colors := PackedColorArray()
	for a in GLOW_ALPHAS:
		colors.append(Color(Palette.WHITE, a))
	g.offsets = PackedFloat32Array(GLOW_OFFSETS)
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = GLOW_SIZE
	tex.height = GLOW_SIZE
	_glow_tex = tex
	return tex


## The one shared additive CanvasItemMaterial (all additive sprites of a screen share it,
## so the material switch happens once per FxLayer/GlowLayer).
static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## Width of a right-aligned numeral box sized for `digits` digits (S-4: nothing shifts).
## Uses the zero glyph; the tabular fonts give every digit the same advance.
static func fixed_number_box(font: Font, size: int, digits: int) -> float:
	if font == null or digits <= 0:
		return 0.0
	return font.get_string_size("0".repeat(digits), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Chip/element pop (UI-SPEC 10.1): scale 1.0 -> 1.06 -> 1.0 over DUR_BASE, back-out.
## Returns the tween, or null under Reduce motion (scale stays 1) or outside the tree.
static func pop_in(node: CanvasItem) -> Tween:
	if node == null:
		return null
	node.set("scale", Vector2.ONE)
	if reduce_motion() or not node.is_inside_tree():
		return null
	if node is Control:
		var c := node as Control
		c.pivot_offset = c.size * 0.5
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * POP_SCALE, Palette.DUR_BASE * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, Palette.DUR_BASE * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


# ---- Effect-settings contract ---------------------------------------------------------

## Registers an effect node (see the header contract): adds it to FX_GROUP and calls its
## apply_effect_settings() on Settings.settings_changed while it is inside the tree.
## Connects on tree entry, disconnects on tree exit. Safe to call more than once.
static func register_fx(node: Node) -> void:
	if node == null:
		return
	node.add_to_group(FX_GROUP)
	if not node.has_meta(&"_fx_registered"):
		node.set_meta(&"_fx_registered", true)
		node.tree_entered.connect(func() -> void: _fx_connect(node))
		node.tree_exiting.connect(func() -> void: _fx_disconnect(node))
	if node.is_inside_tree():
		_fx_connect(node)


static func _fx_connect(node: Node) -> void:
	var s := _settings()
	if s == null or not node.has_method(&"apply_effect_settings"):
		return
	var cb := Callable(node, &"apply_effect_settings")
	if not s.is_connected(&"settings_changed", cb):
		s.connect(&"settings_changed", cb)


static func _fx_disconnect(node: Node) -> void:
	var s := _settings()
	if s == null:
		return
	var cb := Callable(node, &"apply_effect_settings")
	if s.is_connected(&"settings_changed", cb):
		s.disconnect(&"settings_changed", cb)
