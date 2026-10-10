class_name UiIcons
extends RefCounted
## Menu and control icons (02.2 UI-SPEC section 5), drawn with polygons and 2 px strokes
## only: Oxanium has no arrow glyphs. Every icon is laid out on a 24x24 grid and scaled
## into the target rect. No colour literals (VIS-01): the caller passes the colour.

const GRID := 24.0
const STROKE := 2.0
const NAMES: Array[String] = [
	"dive", "lifebuoy", "sonar", "sliders", "auto", "folder", "power",
	"check", "chevron_left", "chevron_right",
]


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
		"check":
			_line(ci, o, k, [Vector2(4, 12), Vector2(10, 18), Vector2(20, 6)], color, w)
		"chevron_left":
			_line(ci, o, k, [Vector2(15, 5), Vector2(8, 12), Vector2(15, 19)], color, w)
		"chevron_right":
			_line(ci, o, k, [Vector2(9, 5), Vector2(16, 12), Vector2(9, 19)], color, w)
	return true


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
