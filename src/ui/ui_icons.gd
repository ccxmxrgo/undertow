class_name UiIcons
extends RefCounted
## Menu, control and versus icons (02.2 UI-SPEC section 5, 03-UI-SPEC section 4), drawn with polygons and 2 px strokes
## only: Oxanium has no arrow glyphs. Every icon is laid out on a 24x24 grid and scaled
## into the target rect. No colour literals (VIS-01): the caller passes the colour.

const GRID := 24.0
const STROKE := 2.0
const NAMES: Array[String] = [
	"dive", "lifebuoy", "sonar", "sliders", "auto", "folder", "power", "chart",
	"check", "chevron_left", "chevron_right",
	# Phase 3 (03-UI-SPEC section 4): rewards, killfeed, versus, medals.
	"crossed_wires", "ghost_notes", "ink_cloud", "pressure_crack", "sonar_jam",
	"depth_charge", "decoy_flare", "ballast_patch", "overclock",
	"arrow_right", "reflect", "shield", "cross", "skull", "bounty", "target", "debris", "versus",
	"medal_untouchable", "medal_uno_reverse", "medal_bounty_hunter", "medal_shredder",
	"medal_head_on", "medal_grudge", "medal_dogpiled",
	# Phase 4 (04-UI-SPEC section 5): online play.
	"online", "host", "signal", "link_broken", "copy", "warning",
]

## signal glyph (04-UI-SPEC section 5): 4 bars, 3 px wide, bottoms at y 20.
const SIGNAL_BARS := 4
const SIGNAL_X: Array[float] = [4.0, 9.0, 14.0, 19.0]
const SIGNAL_H: Array[float] = [4.0, 8.0, 12.0, 16.0]
const SIGNAL_W := 3.0
const SIGNAL_BOTTOM := 20.0
const SIGNAL_UNLIT_ALPHA := 0.7


static func names() -> Array[String]:
	return NAMES.duplicate()


## Draws icon `icon_name` into `rect` on `ci`. Returns false (and draws nothing) for an
## unknown name.
static func draw(ci: CanvasItem, icon_name: String, rect: Rect2, color: Color) -> bool:
	if ci == null or not NAMES.has(icon_name):
		return false
	var k := minf(rect.size.x, rect.size.y) / GRID
	var o := rect.position + (rect.size - Vector2(GRID, GRID) * k) * 0.5
	var w := STROKE * maxf(k, 0.5)
	match icon_name:
		"dive":
			# Down chevron over a wave line.
			_line(ci, o, k, [Vector2(6, 4), Vector2(12, 10), Vector2(18, 4)], color, w)
			_line(ci, o, k, [Vector2(12, 2), Vector2(12, 10)], color, w)
			_line(ci, o, k, _wave(3.0, 21.0, 17.0, 2.5), color, w)
		"lifebuoy":
			ci.draw_arc(o + Vector2(12, 12) * k, 8.0 * k, 0.0, TAU, 32, color, w, true)
			ci.draw_arc(o + Vector2(12, 12) * k, 3.5 * k, 0.0, TAU, 20, color, w, true)
			for i in 4:
				var a := PI * 0.25 + i * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				_line(ci, o, k, [Vector2(12, 12) + d * 3.5, Vector2(12, 12) + d * 8.0], color, w)
		"sonar":
			ci.draw_circle(o + Vector2(6, 12) * k, 2.5 * k, color)
			ci.draw_arc(o + Vector2(6, 12) * k, 8.0 * k, -PI * 0.3, PI * 0.3, 12, color, w, true)
			ci.draw_arc(o + Vector2(6, 12) * k, 14.0 * k, -PI * 0.3, PI * 0.3, 16, color, w, true)
		"sliders":
			var knobs := [8.0, 16.0, 11.0]
			for i in 3:
				var y := 6.0 + i * 6.0
				_line(ci, o, k, [Vector2(3, y), Vector2(21, y)], color, w)
				var kx: float = knobs[i]
				_poly(ci, o, k, [Vector2(kx - 2, y - 2.5), Vector2(kx + 2, y - 2.5),
						Vector2(kx + 2, y + 2.5), Vector2(kx - 2, y + 2.5)], color)
		"auto":
			_poly(ci, o, k, [Vector2(8, 6), Vector2(17, 12), Vector2(8, 18)], color)
			ci.draw_arc(o + Vector2(12, 12) * k, 10.0 * k, PI * 0.9, PI * 1.6, 12, color, w, true)
			ci.draw_circle(o + (Vector2(12, 12) + Vector2.from_angle(PI * 1.6) * 10.0) * k, 2.0 * k, color)
		"folder":
			_line(ci, o, k, [Vector2(3, 7), Vector2(3, 19), Vector2(21, 19), Vector2(21, 9),
					Vector2(11, 9), Vector2(9, 6), Vector2(3, 6), Vector2(3, 7)], color, w)
		"power":
			ci.draw_arc(o + Vector2(12, 13) * k, 8.0 * k, -PI * 0.3, PI * 1.3, 24, color, w, true)
			_line(ci, o, k, [Vector2(12, 3), Vector2(12, 12)], color, w)
		"chart":
			# Audio waveform on the left feeding three short note bars on the right.
			_line(ci, o, k, _wave(2.0, 11.0, 12.0, 4.0), color, w)
			_line(ci, o, k, [Vector2(11, 12), Vector2(13, 12)], color, w)
			for y: float in [6.0, 12.0, 18.0]:
				_poly(ci, o, k, [Vector2(15, y - 1.5), Vector2(22, y - 1.5),
						Vector2(22, y + 1.5), Vector2(15, y + 1.5)], color)
		"check":
			_line(ci, o, k, [Vector2(4, 12), Vector2(10, 18), Vector2(20, 6)], color, w)
		"chevron_left":
			_line(ci, o, k, [Vector2(15, 5), Vector2(8, 12), Vector2(15, 19)], color, w)
		"chevron_right":
			_line(ci, o, k, [Vector2(9, 5), Vector2(16, 12), Vector2(9, 19)], color, w)
		# ---- Phase 3 glyphs (03-UI-SPEC section 4) ----
		"crossed_wires":
			_line(ci, o, k, [Vector2(3, 6), Vector2(10, 6), Vector2(14, 18), Vector2(21, 18)], color, w)
			_line(ci, o, k, [Vector2(3, 18), Vector2(10, 18), Vector2(14, 6), Vector2(21, 6)], color, w)
		"ghost_notes":
			# Dashed diamond: one dash per edge (middle 60%), 4 separate segments.
			var dia := [Vector2(12, 4), Vector2(20, 12), Vector2(12, 20), Vector2(4, 12)]
			for i in 4:
				var a: Vector2 = dia[i]
				var b: Vector2 = dia[(i + 1) % 4]
				_line(ci, o, k, [a.lerp(b, 0.2), a.lerp(b, 0.8)], color, w)
			_poly(ci, o, k, _diamond(Vector2(19, 5), 3.0), color)
		"ink_cloud":
			for c: Vector2 in [Vector2(7, 14), Vector2(12, 10), Vector2(17, 14)]:
				ci.draw_circle(o + c * k, 5.0 * k, color)
			_poly(ci, o, k, [Vector2(7, 14), Vector2(17, 14), Vector2(17, 19), Vector2(7, 19)], color)
		"pressure_crack":
			_line(ci, o, k, [Vector2(5, 5), Vector2(12, 11), Vector2(19, 5)], color, w)
			_line(ci, o, k, [Vector2(5, 12), Vector2(12, 18), Vector2(19, 12)], color, w)
		"sonar_jam":
			ci.draw_arc(o + Vector2(12, 12) * k, 8.0 * k, 0.0, TAU, 32, color, w, true)
			_line(ci, o, k, [Vector2(6, 18), Vector2(18, 6)], color, w)
		"depth_charge":
			ci.draw_circle(o + Vector2(12, 14) * k, 6.0 * k, color)
			_poly(ci, o, k, [Vector2(11, 3), Vector2(13, 3), Vector2(13, 8), Vector2(11, 8)], color)
			_line(ci, o, k, [Vector2(8, 1), Vector2(10, 3)], color, w)
			_line(ci, o, k, [Vector2(16, 1), Vector2(14, 3)], color, w)
			_line(ci, o, k, [Vector2(12, 0), Vector2(12, 1.5)], color, w)
		"decoy_flare":
			_shield(ci, o, k, color, w)
			_poly(ci, o, k, [Vector2(12, 7), Vector2(14.5, 11), Vector2(14, 13.5), Vector2(12, 15),
					Vector2(10, 13.5), Vector2(9.5, 11)], color)
		"ballast_patch":
			_line(ci, o, k, [Vector2(5, 2), Vector2(19, 2), Vector2(22, 5), Vector2(22, 19),
					Vector2(19, 22), Vector2(5, 22), Vector2(2, 19), Vector2(2, 5), Vector2(5, 2)], color, w)
			_line(ci, o, k, [Vector2(12, 5), Vector2(12, 19)], color, w)
			_line(ci, o, k, [Vector2(5, 12), Vector2(19, 12)], color, w)
		"overclock":
			# 200 degree gauge arc open at the bottom, needle to the upper right.
			ci.draw_arc(o + Vector2(12, 14) * k, 8.0 * k, deg_to_rad(170.0), deg_to_rad(370.0), 28, color, w, true)
			_line(ci, o, k, [Vector2(12, 14), Vector2(18, 8)], color, w)
		"arrow_right":
			_line(ci, o, k, [Vector2(3, 12), Vector2(16, 12)], color, w)
			_poly(ci, o, k, [Vector2(15, 8), Vector2(21, 12), Vector2(15, 16)], color)
		"reflect":
			var u: Array = [Vector2(19, 6)]
			u.append_array(_arc_pts(Vector2(8, 11), 5.0, -PI * 0.5, -PI * 1.5, 10))
			u.append(Vector2(13, 16))
			_line(ci, o, k, u, color, w)
			_poly(ci, o, k, [Vector2(13, 13), Vector2(17, 16), Vector2(13, 19)], color)
		"shield":
			_shield(ci, o, k, color, w)
		"cross":
			_line(ci, o, k, [Vector2(5, 5), Vector2(19, 19)], color, w)
			_line(ci, o, k, [Vector2(19, 5), Vector2(5, 19)], color, w)
		"skull":
			_line(ci, o, k, [Vector2(7, 4), Vector2(17, 4), Vector2(19, 6), Vector2(19, 14),
					Vector2(17, 16), Vector2(7, 16), Vector2(5, 14), Vector2(5, 6), Vector2(7, 4)], color, w)
			_poly(ci, o, k, [Vector2(7, 8), Vector2(11, 8), Vector2(11, 12), Vector2(7, 12)], color)
			_poly(ci, o, k, [Vector2(13, 8), Vector2(17, 8), Vector2(17, 12), Vector2(13, 12)], color)
			for x: float in [9.0, 12.0, 15.0]:
				_line(ci, o, k, [Vector2(x, 17), Vector2(x, 20)], color, w)
		"bounty":
			_crosshair(ci, o, k, color, w)
			ci.draw_circle(o + Vector2(12, 12) * k, 2.0 * k, color)
		"target":
			_line(ci, o, k, [Vector2(4, 10), Vector2(4, 4), Vector2(10, 4)], color, w)
			_line(ci, o, k, [Vector2(14, 4), Vector2(20, 4), Vector2(20, 10)], color, w)
			_line(ci, o, k, [Vector2(20, 14), Vector2(20, 20), Vector2(14, 20)], color, w)
			_line(ci, o, k, [Vector2(10, 20), Vector2(4, 20), Vector2(4, 14)], color, w)
			ci.draw_circle(o + Vector2(12, 12) * k, 2.0 * k, color)
		"debris":
			_poly(ci, o, k, [Vector2(4, 16), Vector2(9, 10), Vector2(11, 18)], color)
			_poly(ci, o, k, [Vector2(11, 8), Vector2(16, 4), Vector2(17, 11)], color)
			_poly(ci, o, k, [Vector2(14, 15), Vector2(20, 12), Vector2(19, 20)], color)
		"versus":
			_capsule(ci, o, k, Vector2(3, 8), Vector2(21, 16), color, w)
			_capsule(ci, o, k, Vector2(3, 16), Vector2(21, 8), color, w)
		"medal_untouchable":
			_shield(ci, o, k, color, w)
			_line(ci, o, k, [Vector2(8, 12), Vector2(11, 15), Vector2(16, 9)], color, w)
		"medal_uno_reverse":
			var c0 := Vector2(12, 12)
			for start: float in [deg_to_rad(-165.0), deg_to_rad(15.0)]:
				var stop := start + deg_to_rad(150.0)
				_line(ci, o, k, _arc_pts(c0, 8.0, start, stop, 12), color, w)
				var p := c0 + Vector2.from_angle(stop) * 8.0
				var t := Vector2(-sin(stop), cos(stop))
				var n := Vector2.from_angle(stop)
				_poly(ci, o, k, [p + n * 2.5, p + t * 3.0, p - n * 2.5], color)
		"medal_bounty_hunter":
			_crosshair(ci, o, k, color, w)
			_poly(ci, o, k, _diamond(Vector2(12, 12), 3.0), color)
		"medal_shredder":
			_poly(ci, o, k, [Vector2(13, 2), Vector2(6, 13), Vector2(11, 13), Vector2(9, 22),
					Vector2(18, 10), Vector2(13, 10), Vector2(15, 2)], color)
		"medal_head_on":
			_line(ci, o, k, [Vector2(2, 12), Vector2(7, 12)], color, w)
			_poly(ci, o, k, [Vector2(7, 9), Vector2(10, 12), Vector2(7, 15)], color)
			_line(ci, o, k, [Vector2(22, 12), Vector2(17, 12)], color, w)
			_poly(ci, o, k, [Vector2(17, 9), Vector2(14, 12), Vector2(17, 15)], color)
			for s: float in [-1.0, 1.0]:
				_line(ci, o, k, [Vector2(12, 12 + s * 5), Vector2(12, 12 + s * 8)], color, w)
				_line(ci, o, k, [Vector2(10, 12 + s * 5), Vector2(8, 12 + s * 8)], color, w)
				_line(ci, o, k, [Vector2(14, 12 + s * 5), Vector2(16, 12 + s * 8)], color, w)
		"medal_grudge":
			for x: float in [6.0, 11.0, 16.0]:
				_line(ci, o, k, [Vector2(x - 2, 6), Vector2(x + 2, 12), Vector2(x - 2, 18)], color, w)
		"medal_dogpiled":
			ci.draw_circle(o + Vector2(12, 12) * k, 3.0 * k, color)
			for src: Vector2 in [Vector2(3, 4), Vector2(21, 4), Vector2(12, 22)]:
				_arrow(ci, o, k, src, src.lerp(Vector2(12, 12), 0.62), color, w)
		# ---- Phase 4 glyphs (04-UI-SPEC section 5) ----
		"online":
			# Two subs with signal arcs between them.
			ci.draw_circle(o + Vector2(4, 17) * k, 3.0 * k, color)
			ci.draw_circle(o + Vector2(20, 17) * k, 3.0 * k, color)
			_line(ci, o, k, _arc_pts(Vector2(12, 17), 6.0, deg_to_rad(200.0), deg_to_rad(340.0), 12), color, w)
			_line(ci, o, k, _arc_pts(Vector2(12, 17), 11.0, deg_to_rad(205.0), deg_to_rad(335.0), 16), color, w)
		"host":
			# Broadcast mast.
			_line(ci, o, k, [Vector2(12, 9), Vector2(12, 21)], color, w)
			_line(ci, o, k, [Vector2(7, 21), Vector2(17, 21)], color, w)
			ci.draw_circle(o + Vector2(12, 8) * k, 2.0 * k, color)
			for r: float in [5.0, 9.0]:
				_line(ci, o, k, _arc_pts(Vector2(12, 8), r, deg_to_rad(220.0), deg_to_rad(320.0), 10), color, w)
		"signal":
			# All four bars lit in `color`; use draw_signal() for a lit count.
			_signal_bars(ci, o, k, signal_bar_colors(SIGNAL_BARS, color))
		"link_broken":
			_line(ci, o, k, _chamfer_loop(Vector2(2, 9), Vector2(11, 15), 2.0), color, w)
			_line(ci, o, k, _chamfer_loop(Vector2(13, 9), Vector2(22, 15), 2.0), color, w)
			_line(ci, o, k, [Vector2(10, 20), Vector2(14, 4)], color, w)
		"copy":
			# Back square outline, then the front one filled ABYSS_800 so the back reads behind it.
			_line(ci, o, k, _chamfer_loop(Vector2(8, 4), Vector2(20, 16), 2.0), color, w)
			var front := _chamfer_loop(Vector2(4, 8), Vector2(16, 20), 2.0)
			front.pop_back()
			_poly(ci, o, k, front, Palette.ABYSS_800)
			_line(ci, o, k, _chamfer_loop(Vector2(4, 8), Vector2(16, 20), 2.0), color, w)
		"warning":
			_line(ci, o, k, [Vector2(12, 3), Vector2(22, 20), Vector2(2, 20), Vector2(12, 3)], color, w)
			_poly(ci, o, k, [Vector2(11, 9), Vector2(13, 9), Vector2(13, 15), Vector2(11, 15)], color)
			ci.draw_circle(o + Vector2(12, 17.5) * k, 1.5 * k, color)
	return true


## Colours of the 4 signal bars for `lit` (clamped 0..4): lit bars `color_lit`, unlit
## ABYSS_500 at 70% (04-UI-SPEC section 5).
static func signal_bar_colors(lit: int, color_lit: Color) -> Array[Color]:
	var n := clampi(lit, 0, SIGNAL_BARS)
	var out: Array[Color] = []
	for i in SIGNAL_BARS:
		out.append(color_lit if i < n else Color(Palette.ABYSS_500, SIGNAL_UNLIT_ALPHA))
	return out


## The signal glyph with `lit` bars (0..4, clamped) in `color_lit` (SONAR, or WARNING_RED
## for high latency). Returns false for a null canvas item.
static func draw_signal(ci: CanvasItem, rect: Rect2, lit: int, color_lit: Color) -> bool:
	if ci == null:
		return false
	var k := minf(rect.size.x, rect.size.y) / GRID
	var o := rect.position + (rect.size - Vector2(GRID, GRID) * k) * 0.5
	_signal_bars(ci, o, k, signal_bar_colors(lit, color_lit))
	return true


static func _signal_bars(ci: CanvasItem, o: Vector2, k: float, cols: Array[Color]) -> void:
	for i in SIGNAL_BARS:
		var x: float = SIGNAL_X[i]
		var top: float = SIGNAL_BOTTOM - SIGNAL_H[i]
		_poly(ci, o, k, [Vector2(x, top), Vector2(x + SIGNAL_W, top),
				Vector2(x + SIGNAL_W, SIGNAL_BOTTOM), Vector2(x, SIGNAL_BOTTOM)], cols[i])


## Closed outline (grid units) of the rect a..b with its TL and BR corners cut by `cut`.
static func _chamfer_loop(a: Vector2, b: Vector2, cut: float) -> Array:
	return [Vector2(a.x + cut, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y - cut),
			Vector2(b.x - cut, b.y), Vector2(a.x, b.y), Vector2(a.x, a.y + cut),
			Vector2(a.x + cut, a.y)]


static func _pts(o: Vector2, k: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(o + (p as Vector2) * k)
	return out


static func _line(ci: CanvasItem, o: Vector2, k: float, pts: Array, color: Color, w: float) -> void:
	ci.draw_polyline(_pts(o, k, pts), color, w, true)


static func _poly(ci: CanvasItem, o: Vector2, k: float, pts: Array, color: Color) -> void:
	ci.draw_colored_polygon(_pts(o, k, pts), color)


## A gentle sine wave from x0 to x1 around y (grid units).
static func _wave(x0: float, x1: float, y: float, amp: float) -> Array:
	var pts: Array = []
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(lerpf(x0, x1, t), y + sin(t * TAU) * amp))
	return pts


## Points on a circle arc (grid units) from angle a0 to a1, inclusive.
static func _arc_pts(c: Vector2, r: float, a0: float, a1: float, steps: int) -> Array:
	var pts: Array = []
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * r)
	return pts


static func _diamond(c: Vector2, r: float) -> Array:
	return [c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]


## Shield outline shared by shield, decoy_flare and medal_untouchable.
static func _shield(ci: CanvasItem, o: Vector2, k: float, color: Color, w: float) -> void:
	_line(ci, o, k, [Vector2(6, 4), Vector2(18, 4), Vector2(18, 12), Vector2(12, 20),
			Vector2(6, 12), Vector2(6, 4)], color, w)


## Crosshair (circle r 7 plus 4 ticks) shared by bounty and medal_bounty_hunter.
static func _crosshair(ci: CanvasItem, o: Vector2, k: float, color: Color, w: float) -> void:
	ci.draw_arc(o + Vector2(12, 12) * k, 7.0 * k, 0.0, TAU, 32, color, w, true)
	_line(ci, o, k, [Vector2(12, 1), Vector2(12, 5)], color, w)
	_line(ci, o, k, [Vector2(12, 19), Vector2(12, 23)], color, w)
	_line(ci, o, k, [Vector2(1, 12), Vector2(5, 12)], color, w)
	_line(ci, o, k, [Vector2(19, 12), Vector2(23, 12)], color, w)


## Rounded-end line (torpedo capsule).
static func _capsule(ci: CanvasItem, o: Vector2, k: float, a: Vector2, b: Vector2, color: Color, w: float) -> void:
	_line(ci, o, k, [a, b], color, w * 1.5)
	ci.draw_circle(o + a * k, w * 0.75, color)
	ci.draw_circle(o + b * k, w * 0.75, color)


## Line from `a` to `b` with a filled head whose tip is at `b` (grid units).
static func _arrow(ci: CanvasItem, o: Vector2, k: float, a: Vector2, b: Vector2, color: Color, w: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var base := b - d * 4.0
	_line(ci, o, k, [a, base], color, w)
	_poly(ci, o, k, [base + n * 2.5, b, base - n * 2.5], color)
