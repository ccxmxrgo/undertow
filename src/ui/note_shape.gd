class_name NoteShape
extends RefCounted
## One distinct shape per lane (D-24): shape carries identity, not color. A fifth shape
## (Phase 3 Ghost Notes) is added by extending Kind.

enum Kind { DIAMOND, CIRCLE, TRIANGLE, SQUARE }

const SIZE := 80.0
const OUTLINE_W := 4.0


static func kind_for_lane(lane: int) -> int:
	return lane % 4


static func draw(canvas: CanvasItem, kind: int, center: Vector2, color: Color) -> void:
	var h := SIZE * 0.5
	var fill := Color(color.r, color.g, color.b, color.a * 0.25)
	match kind:
		Kind.CIRCLE:
			canvas.draw_circle(center, h - OUTLINE_W * 0.5, fill)
			canvas.draw_arc(center, h - OUTLINE_W * 0.5, 0.0, TAU, 48, color, OUTLINE_W, true)
		_:
			var pts := _polygon(kind, center, h)
			canvas.draw_colored_polygon(pts, fill)
			var closed := pts.duplicate()
			closed.append(pts[0])
			canvas.draw_polyline(closed, color, OUTLINE_W, true)


static func _polygon(kind: int, c: Vector2, h: float) -> PackedVector2Array:
	match kind:
		Kind.DIAMOND:
			return PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
		Kind.TRIANGLE:
			return PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, h * 0.9), c + Vector2(-h, h * 0.9)])
		_:
			return PackedVector2Array([c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h)])
