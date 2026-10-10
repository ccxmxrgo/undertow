class_name FailScreen
extends Control
## IMPLOSION (D-15, 02.2 UI-SPEC 9.2): fades in after the 400 ms board squash. Backdrop
## ABYSS_900 90% + red corner vignette + 6 static crack lines, a danger glass panel with the
## Display "IMPLOSION" title (red text glow on Full, a 120 ms 8 px shake unless Reduce motion),
## the kept run lines, the song progress row, Retry Dive (primary, initial focus) and Back to
## Menu. Buttons stay disabled until the panel is visible (WR-06). Effect node (UiKit contract).

signal retry_pressed
signal menu_pressed

const SQUASH_SEC := 0.4
const FADE_SEC := 0.3

## Layout (UI-SPEC 9.2), 1920x1080 design pixels.
const DIM_ALPHA := 0.9
const PANEL_RECT := Rect2(600, 240, 720, 600)
const CENTER_X := 960.0
const TITLE_BASELINE := 368.0
const BODY_BASELINE := 432.0
const STATS_BASELINE := 488.0
const BEST_BASELINE := 528.0
const NOTE_BASELINE := 576.0
const PROGRESS_AT := Vector2(680, 612)
const TRACK_RECT := Rect2(680, 624, 560, 4)
const RETRY_RECT := Rect2(680, 664, 560, 64)
const MENU_RECT := Rect2(680, 744, 560, 64)
const TRACK_FILL_ALPHA := 0.7
const TRACK_BG_ALPHA := 0.6
const BRACKET_ALPHA := 0.8
const TITLE_GLOW_ALPHA := 0.3
const TITLE_GLOW_SIZE := 12
## Red vignette: WARNING_RED 22% at the corners fading to 0 at 60% of the half-diagonal.
const VIGNETTE_ALPHA := 0.22
const VIGNETTE_CLEAR := 0.6
## Crack overlay: 6 jagged polylines from the screen corners inward, up to 360 px.
const CRACK_COUNT := 6
const CRACK_REACH := 360.0
const CRACK_ALPHA := 0.35
const CRACK_SEED := 20220
## Title shake on appear.
const SHAKE_SEC := 0.12
const SHAKE_PX := 8.0
const SHAKE_CYCLES := 3.0

static var _cracks: Array[PackedVector2Array] = []
static var _vignette: GradientTexture2D

var retry_button: Button
var menu_button: Button
var title_label: Label
var body_label: Label

## Extra body lines in UI-SPEC order after body_label (never any NEW RECORD text).
var stats_label: Label
var best_label: Label
var note_label: Label
var progress_label: Label
var panel: Control
var panel_variant := "danger"
## Song progress 0..100, or -1 when unknown (progress row hidden).
var progress_pct := -1.0

var _backdrop: Control
var _track: Control
var _panel_sb: StyleBoxFlat
var _title_x := 0.0
var _low := false
var _reduce := false


## Draws through a callable (backdrop, panel, progress track).
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func setup(depth_m: float, max_combo: int = 0, saved_best: float = -1.0, p_progress_pct: float = -1.0) -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	progress_pct = p_progress_pct
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.ABYSS_900, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	_backdrop = _painter("Backdrop", Rect2(0, 0, Highway.SCREEN_W, Highway.SCREEN_H), _draw_backdrop)
	UiLayout.fill_rect(_backdrop)
	panel = _painter("Panel", PANEL_RECT, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
		ci.draw_style_box(_panel_style(), r)
		UiKit.draw_brackets(ci, r, Color(Palette.WARNING_RED, BRACKET_ALPHA)))
	title_label = _text("Title", "IMPLOSION", Palette.display_font(), Palette.SIZE_DISPLAY,
		Palette.WARNING_RED, TITLE_BASELINE)
	title_label.add_theme_color_override("font_outline_color", Color(Palette.WARNING_RED, TITLE_GLOW_ALPHA))
	_title_x = title_label.position.x
	body_label = _text("Body", "Hull breached at %d m." % int(depth_m), Palette.font(), Palette.SIZE_BODY,
		Palette.TEXT_HI, BODY_BASELINE)
	stats_label = _text("Stats", "Max combo: %d" % max_combo, Palette.font(), Palette.SIZE_BODY,
		Palette.TEXT_MID, STATS_BASELINE)
	var best_text := "Saved best: %s m" % Palette.fmt_depth(int(saved_best)) if saved_best >= 0.0 \
		else "No saved best yet."
	best_label = _text("Best", best_text, Palette.font(), Palette.SIZE_BODY, Palette.TEXT_MID, BEST_BASELINE)
	note_label = _text("Note", "Records are saved only when a dive is finished.", Palette.font(),
		Palette.SIZE_LABEL, Palette.TEXT_LO, NOTE_BASELINE)
	progress_label = _text("Progress", "SONG PROGRESS %d%%" % int(clampf(progress_pct, 0.0, 100.0)),
		_spaced(Palette.font(), 2), Palette.SIZE_LABEL, Palette.TEXT_LO, PROGRESS_AT.y, PROGRESS_AT.x)
	_track = _painter("ProgressTrack", TRACK_RECT, func(ci: CanvasItem) -> void:
		ci.draw_rect(Rect2(Vector2.ZERO, TRACK_RECT.size), Color(Palette.ABYSS_500, TRACK_BG_ALPHA))
		var w := progress_fill_width()
		if w > 0.0:
			ci.draw_rect(Rect2(0, 0, w, TRACK_RECT.size.y), Color(Palette.WARNING_RED, TRACK_FILL_ALPHA)))
	progress_label.visible = progress_pct >= 0.0
	_track.visible = progress_pct >= 0.0
	retry_button = _button("Retry Dive", "primary", RETRY_RECT)
	retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	menu_button = _button("Back to Menu", "default", MENU_RECT)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(menu_button)
	retry_button.focus_neighbor_top = retry_button.get_path_to(menu_button)
	menu_button.focus_neighbor_top = menu_button.get_path_to(retry_button)
	menu_button.focus_neighbor_bottom = menu_button.get_path_to(retry_button)
	var marker := FocusMarker.new()
	marker.name = "FocusMarker"
	add_child(marker)
	UiKit.register_fx(self)
	apply_effect_settings()


## Fade the panel in over 300 ms after `delay` seconds (the highway squash).
func play(delay: float = SQUASH_SEC) -> void:
	modulate.a = 0.0
	if is_inside_tree():
		# Inert until visible (WR-06): a mashed Space/Enter must not hit an invisible Retry.
		retry_button.disabled = true
		menu_button.disabled = true
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(_start_shake)
		tw.tween_property(self, "modulate:a", 1.0, FADE_SEC)
		tw.tween_callback(func() -> void:
			retry_button.disabled = false
			menu_button.disabled = false
			retry_button.grab_focus())
	else:
		modulate.a = 1.0


# ---- effects ------------------------------------------------------------------------------

## Effect contract: re-read Low effects / Reduce motion (title glow, panel glow, shake).
func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_reduce = UiKit.reduce_motion()
	_panel_sb = null
	if title_label != null:
		title_label.add_theme_constant_override("outline_size", 0 if _low else TITLE_GLOW_SIZE)
	if _reduce and title_label != null:
		title_label.position.x = _title_x
	for c: CanvasItem in [panel, _backdrop]:
		if c != null:
			c.queue_redraw()


## Effect contract: what is active right now.
func effect_counts() -> Dictionary:
	return {"shake": not _reduce, "glow": not _low, "cracks": true}


## Horizontal title offset `t` seconds into the shake: 8 px peak, decaying to 0 at 120 ms.
static func shake_offset(t: float) -> float:
	if t < 0.0 or t >= SHAKE_SEC:
		return 0.0
	var k := t / SHAKE_SEC
	return SHAKE_PX * sin(TAU * SHAKE_CYCLES * k + PI * 0.5) * (1.0 - k)


## The title's resting x (no shake).
func title_rest_x() -> float:
	return _title_x


func _start_shake() -> void:
	if _reduce or title_label == null or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		title_label.position.x = _title_x + shake_offset(t), 0.0, SHAKE_SEC, SHAKE_SEC)
	tw.tween_callback(func() -> void: title_label.position.x = _title_x)


func progress_fill_width() -> float:
	return TRACK_RECT.size.x * clampf(progress_pct, 0.0, 100.0) / 100.0


## Six static crack polylines from the screen corners inward (each within CRACK_REACH of its
## corner). Deterministic (fixed seed), built once.
static func crack_lines() -> Array[PackedVector2Array]:
	if not _cracks.is_empty():
		return _cracks
	var rng := RandomNumberGenerator.new()
	rng.seed = CRACK_SEED
	var w := Highway.SCREEN_W
	var h := Highway.SCREEN_H
	# Corner, aim angle (towards the inside of the screen).
	var starts: Array = [
		[Vector2(0, 0), 0.62], [Vector2(0, 0), 1.12],
		[Vector2(w, 0), PI - 0.75],
		[Vector2(0, h), -0.55],
		[Vector2(w, h), PI + 0.5], [Vector2(w, h), PI + 1.05],
	]
	for s: Array in starts:
		var origin: Vector2 = s[0]
		var ang: float = s[1]
		var pts := PackedVector2Array([origin])
		var p := origin
		var reach := rng.randf_range(0.7, 1.0) * CRACK_REACH
		while true:
			var step := rng.randf_range(34.0, 62.0)
			var a := ang + rng.randf_range(-0.55, 0.55)
			var nxt := p + Vector2(cos(a), sin(a)) * step
			if nxt.distance_to(origin) > reach:
				break
			pts.append(nxt)
			p = nxt
		_cracks.append(pts)
	return _cracks


static func red_vignette() -> GradientTexture2D:
	if _vignette != null:
		return _vignette
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, VIGNETTE_CLEAR, 1.0])
	g.colors = PackedColorArray([Color(Palette.WARNING_RED, 0.0), Color(Palette.WARNING_RED, 0.0),
		Color(Palette.WARNING_RED, VIGNETTE_ALPHA)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)  # radius = half-diagonal
	tex.width = 256
	tex.height = 144
	_vignette = tex
	return tex


func _draw_backdrop(ci: CanvasItem) -> void:
	var sz: Vector2 = ci.get("size")
	ci.draw_texture_rect(red_vignette(), Rect2(Vector2.ZERO, sz), false)
	var sx := sz.x / Highway.SCREEN_W
	var sy := sz.y / Highway.SCREEN_H
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, sy))
	for line in crack_lines():
		if not _low:  # faint stroke glow under each crack (Low: none)
			ci.draw_polyline(line, Color(Palette.WARNING_RED, 0.08), Palette.EDGE + 6.0, true)
		ci.draw_polyline(line, Color(Palette.WARNING_RED, CRACK_ALPHA), Palette.EDGE, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _panel_style() -> StyleBoxFlat:
	if _panel_sb == null:
		_panel_sb = UiKit.style_panel(panel_variant)
		_panel_sb.shadow_color = Color(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)
	return _panel_sb


# ---- helpers ------------------------------------------------------------------------------

func _painter(node_name: String, rect: Rect2, fn: Callable) -> Painter:
	var p := Painter.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = rect.position
	p.size = rect.size
	p.painter = fn
	add_child(p)
	return p


static func _spaced(base: Font, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	return v


## Label with its baseline at `baseline`, centred on CENTER_X (or left-aligned at `left_x`).
func _text(node_name: String, text: String, font: Font, font_size: int, color: Color, baseline: float,
		left_x: float = -1.0) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var w := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var x := left_x if left_x >= 0.0 else CENTER_X - w * 0.5
	l.position = Vector2(x, baseline - font.get_ascent(font_size))
	l.size = Vector2(maxf(w, 1.0), ceilf(font.get_height(font_size)))
	add_child(l)
	return l


func _button(text: String, variant: String, rect: Rect2) -> Button:
	var b := UiKit.make_button(text, "", variant, int(rect.size.y))
	b.name = text.replace(" ", "")
	b.position = rect.position
	b.size = rect.size
	add_child(b)
	return b
