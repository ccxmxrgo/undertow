class_name NoteShape
extends RefCounted
## One distinct shape per lane (D-24): shape carries identity, not color.
## Phase 3 Ghost Notes: add a fifth Kind entry (and its _polygon case) here; nothing else changes.

enum Kind { DIAMOND, CIRCLE, TRIANGLE, SQUARE }

const SIZE := 80.0
const OUTLINE_W := 4.0


static func kind_for_lane(lane: int) -> int:
	return lane % 4


## size is the bounding box edge; outline in `color`, fill at 25% of its alpha.
static func draw(canvas: CanvasItem, kind: int, center: Vector2, size: float, color: Color) -> void:
	var h := size * 0.5
	var fill := Palette.alpha(color, color.a * 0.25)
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
