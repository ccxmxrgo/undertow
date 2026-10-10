class_name Wcag
extends RefCounted
## WCAG 2.x relative luminance and contrast ratio, plus sRGB alpha compositing
## exactly as the UI-SPEC section 13 table computes it (blend in gamma space).


## One sRGB channel (0..1) to linear light.
static func channel_lin(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## Relative luminance of an opaque colour (alpha ignored).
static func luminance(c: Color) -> float:
	return 0.2126 * channel_lin(c.r) + 0.7152 * channel_lin(c.g) + 0.0722 * channel_lin(c.b)


## Contrast ratio (1..21), order independent.
static func ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## fg at alpha a over bg, blended per sRGB channel; the result is opaque.
static func over(fg: Color, a: float, bg: Color) -> Color:
	return Color(
		fg.r * a + bg.r * (1.0 - a),
		fg.g * a + bg.g * (1.0 - a),
		fg.b * a + bg.b * (1.0 - a),
		1.0
	)
