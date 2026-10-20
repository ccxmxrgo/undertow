class_name Palette
extends RefCounted
## Single source of UI colors, spacing tokens and fonts (UI-SPEC). No other hues exist.
## Only file allowed to contain colour literals (VIS-01).

## Per-lane identity colors (D-02), lane order.
const LANE_COLORS: Array[Color] = [Color("22D3EE"), Color("FBBF24"), Color("F472B6"), Color("A3E635")]

## ---- Abyssal Cockpit tokens (02.2 UI-SPEC section 3.1).
const ABYSS_900 := Color("03060D")  # dominant base (60%)
const ABYSS_850 := Color("06101E")  # menu backdrop gradient mid-stop
const ABYSS_800 := Color("060D1A")  # deep fills, gauge tubes, console base
const ABYSS_700 := Color("0A1A2E")  # glass panel fill (at PANEL_ALPHA)
const ABYSS_600 := Color("10263F")  # raised fill: focused row, pressed button
const ABYSS_500 := Color("183A5A")  # unlit gauge segments; never a text background
const HIGHWAY_BASE := Color("040A16")  # highway surface (at HIGHWAY_ALPHA)
const VP_GLOW := Color("123A52")  # arena centre glow
const VP_GLOW_MID := Color("0A1428")  # arena centre glow mid-stop (used at 60%)
const MARINE_SNOW := Color("A0E6FF")  # gameplay marine snow (decoration)
const WALL_TEAL := Color("1E8CB4")
const WALL_VIOLET := Color("5A3CAA")
const SONAR := Color("05D9E8")  # UI chrome accent
const SONAR_PALE := Color("A0FFF0")  # hit line core, PERFECT, highlights
const TEXT_HI := Color("E8E6F0")  # primary text, numerals
const TEXT_MID := Color("A9B4CC")  # secondary text, GOOD
const TEXT_LO := Color("8A93AD")  # captions, hints; never on ABYSS_500
const BIO_VIOLET := Color("8C6CFF")  # decoration only
const REWARD_GOLD := Color("FFD36B")  # records, grade S; never in the note-path keep-out
const WARNING_RED := Color("FF4A3D")  # miss, hull critical, IMPLOSION, errors
const KEYLINE := Color(0.011764706, 0.023529412, 0.050980393, 0.9)  # #03060D at 90%
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)  # #000000 at 35%
const WHITE := Color(1.0, 1.0, 1.0, 1.0)  # top-light mixes; the only neutral
const SILHOUETTE_FAR := Color("081526")
const SILHOUETTE_MID := Color("0A1D2C")
const SILHOUETTE_NEAR := Color("02050B")
## Generated album-cover gradients [top-left, bottom-right] (UI-SPEC 4.10).
const COVER_GRADIENTS: Array = [
	[Color("0A1A2E"), Color("03060D")],
	[Color("10263F"), Color("060D1A")],
	[Color("0B2A3A"), Color("03060D")],
	[Color("1A1640"), Color("060D1A")],
	[Color("0A2A2E"), Color("03060D")],
	[Color("141E3C"), Color("03060D")],
	[Color("0E3046"), Color("060D1A")],
	[Color("1B1236"), Color("03060D")],
]
const PANEL_ALPHA := 0.82
const HIGHWAY_ALPHA := 0.90
const HUD_GLASS_ALPHA := 0.92  # in-game versus glass fill alpha (UI-SPEC 3.1: WARNING_RED text passes 4.5:1 over WALL_TEAL)
const JAM_GREY := TEXT_MID  # Sonar Jam gem core (D-15), alias: no new hue

const GRADE_COLORS := {
	"S": REWARD_GOLD,
	"A": SONAR_PALE,
	"B": TEXT_HI,
	"C": TEXT_MID,
	"D": TEXT_LO,
	"-": TEXT_LO,
}

## Edges and chamfer cuts (UI-SPEC 2), pixels.
const EDGE_HAIR := 1
const EDGE := 2
const EDGE_FOCUS := 2
const FOCUS_BAR := 4
const CUT_SM := 8
const CUT_MD := 12
const CUT_LG := 64
const BRACKET_ARM := 20

## Motion (UI-SPEC 3.4), seconds.
const DUR_FAST := 0.12
const DUR_BASE := 0.18
const DUR_SLOW := 0.30
const DUR_MAX := 0.40
const STAGGER_MENU := 0.030
const STAGGER_RESULTS := 0.06
const BREATH_SEC := 1.6

## Glow (UI-SPEC 3.3): [size multiplier, alpha].
const GLOW_SM: Array[float] = [1.6, 0.35]
const GLOW_MD: Array[float] = [2.4, 0.25]
const GLOW_LG: Array[float] = [3.5, 0.15]
const PANEL_GLOW_ALPHA := 0.18
const PANEL_GLOW_FOCUS := 0.28
const PANEL_GLOW_SIZE := 12

## Streak tier lane tint (UI-SPEC 7.6); index = multiplier - 1.
const TIER_TINT: Array[float] = [0.07, 0.09, 0.11, 0.14]

const SP_XS := 4
const SP_SM := 8
const SP_MD := 16
const SP_LG := 24
const SP_XL := 32
const SP_2XL := 48
const SP_3XL := 64

const FONT_PATH := "res://assets/fonts/ShareTechMono-Regular.ttf"
## Oxanium variable font (OFL, D-03); weight 700 applied in display_font().
const DISPLAY_FONT_PATH := "res://assets/fonts/Oxanium[wght].ttf"
const DISPLAY_WEIGHT := 700
const THEME_PATH := "res://ui/undertow_theme.tres"
const SIZE_LABEL := 20
const SIZE_BODY := 28
const SIZE_HEADING := 40
const SIZE_DISPLAY := 96

static var _font: Font
static var _bold: Font
static var _display: Font


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


## RGB lerp from a to b by t; alpha of a.
static func mix(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), a.a)


## Ready-gem rim: lane colour mixed 55% toward white.
static func rim_ready(lane: int) -> Color:
	return mix(lane_color(lane), WHITE, 0.55)


## Far (not yet ready) gem rim: lane colour mixed 25% toward white.
static func rim_far(lane: int) -> Color:
	return mix(lane_color(lane), WHITE, 0.25)


## Grade letter colour; unknown letters use TEXT_LO.
static func grade_color(letter: String) -> Color:
	return GRADE_COLORS.get(letter, TEXT_LO)


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


## Oxanium Bold: the variable font with wght = 700 set through the INTEGER OpenType tag
## (D-21; a String key is silently ignored and renders the axis default 200). Falls back
## to Share Tech Mono for missing glyphs, and to it entirely if the file is missing.
static func display_font() -> Font:
	if _display == null:
		var v := FontVariation.new()
		var base: Font = null
		if ResourceLoader.exists(DISPLAY_FONT_PATH):
			base = load(DISPLAY_FONT_PATH) as Font
		if base == null:
			v.base_font = font()
			v.variation_embolden = 0.5
		else:
			v.base_font = base
			var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
			v.variation_opentype = {tag: DISPLAY_WEIGHT}
			v.fallbacks = [font()]
		_display = v
	return _display


## The shared Theme: ui/undertow_theme.tres (generated from tokens by tools/make_theme.gd),
## or UiKit.build_theme() when the file is missing. Low effects uses the glow-free build.
static func load_theme() -> Theme:
	if UiKit.low_effects():
		return UiKit.build_theme(true)
	if ResourceLoader.exists(THEME_PATH):
		var t := load(THEME_PATH) as Theme
		if t != null:
			return t
	return UiKit.build_theme(false)
