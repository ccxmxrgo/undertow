class_name Palette
extends RefCounted
## Single source of UI colors, spacing tokens and fonts (UI-SPEC). No other hues exist.

const BG := Color("000000")  # dominant 60%
const PANEL := Color("0A1F0A")  # panels, hull track
const DIM := Color("1F8F0C")  # dividers, borders
const TEXT := Color("8FD98A")  # secondary text, GOOD
const ACCENT := Color("39FF14")  # hull line, notes, focus, PERFECT
const DESTRUCTIVE := Color("FF4A3D")  # MISS, critical hull

## HUD off-white text (#E8E6F0): multiplier values and badge text.
const REC_TEXT := Color("E8E6F0")

## Per-lane identity colors (D-02), lane order. ACCENT stays for hull line, edges, HUD.
const LANE_COLORS: Array[Color] = [Color("22D3EE"), Color("FBBF24"), Color("F472B6"), Color("A3E635")]
## RGB multiplier for notes outside the Good window (alpha is never reduced).
const NOTE_DIM := 0.60

const SP_XS := 4
const SP_SM := 8
const SP_MD := 16
const SP_LG := 24
const SP_XL := 32
const SP_2XL := 48
const SP_3XL := 64

const FONT_PATH := "res://assets/fonts/ShareTechMono-Regular.ttf"
const THEME_PATH := "res://ui/undertow_theme.tres"
const SIZE_LABEL := 20
const SIZE_BODY := 28
const SIZE_HEADING := 40
const SIZE_DISPLAY := 96

static var _font: Font
static var _bold: Font


## c with its alpha replaced.
## Integer meters with a thousands separator, e.g. 1240 -> "1,240".
static func fmt_depth(meters: int) -> String:
	var digits := str(absi(meters))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if meters < 0 else "") + out


static func alpha(c: Color, a: float) -> Color:
	return Color(c, a)


static func lane_color(lane: int) -> Color:
	return LANE_COLORS[posmod(lane, LANE_COLORS.size())]


## RGB scaled by NOTE_DIM; alpha preserved exactly.
static func dim(c: Color) -> Color:
	return Color(c.r * NOTE_DIM, c.g * NOTE_DIM, c.b * NOTE_DIM, c.a)


## Share Tech Mono, or Godot's fallback font when the file is missing (T-05-01).
static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH) as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## Bold = the regular font embolden 0.5 (Share Tech Mono ships one weight).
static func bold() -> Font:
	if _bold == null:
		var v := FontVariation.new()
		v.base_font = font()
		v.variation_embolden = 0.5
		_bold = v
	return _bold


## The shared Theme; a minimal palette-only Theme if the .tres cannot be loaded.
static func load_theme() -> Theme:
	if ResourceLoader.exists(THEME_PATH):
		var t := load(THEME_PATH) as Theme
		if t != null:
			return t
	var fb := Theme.new()
	fb.default_font = font()
	fb.default_font_size = SIZE_BODY
	fb.set_color("font_color", "Label", TEXT)
	return fb
