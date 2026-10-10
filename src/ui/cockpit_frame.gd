class_name CockpitFrame
extends Control
## The sub's cockpit around the board (UI-SPEC 7.2): left/right consoles from y 600, curved
## top bezels (the viewport glass edge) and faint glass glints. Static: drawn once, never
## redrawn per frame (Godot keeps the canvas commands cached), identical in every effect mode.
## Sits above BoardRoot and below the Hud. Colours come from Palette only.

const LEFT_CONSOLE: PackedVector2Array = [
	Vector2(0, 600), Vector2(336, 600), Vector2(400, 664), Vector2(400, 1080), Vector2(0, 1080)]
const RIGHT_CONSOLE: PackedVector2Array = [
	Vector2(1920, 600), Vector2(1584, 600), Vector2(1520, 664), Vector2(1520, 1080), Vector2(1920, 1080)]
const CONSOLE_ALPHA := 0.82
const CONSOLE_EDGE_ALPHA := 0.40
const BRACKET_AT := Vector2(16, 616)
## The bracket stays at edge strength so the far-left strip keeps reading as dark chrome.
const BRACKET_ALPHA := 0.40
## Bezel: from (0, 0) to (280, 0), bowing to (0, 200) through the quadratic control (40, 40).
const BEZEL_END := Vector2(280, 0)
const BEZEL_TIP := Vector2(0, 200)
const BEZEL_CTRL := Vector2(40, 40)
const BEZEL_SEGMENTS := 24
const BEZEL_ALPHA := 0.90
const BEZEL_EDGE_ALPHA := 0.25
const GLINT_FROM := Vector2(118, 14)
const GLINT_TO := Vector2(16, 96)
const GLINT_ALPHA := 0.08
const SCREEN_W := 1920.0

## Number of _draw() calls (the frame is static, so this stays at 1).
var redraw_count: int = 0


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Points along the left bezel's inner curve, from (280, 0) to (0, 200).
static func bezel_curve() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in BEZEL_SEGMENTS + 1:
		var t := float(i) / BEZEL_SEGMENTS
		var u := 1.0 - t
		pts.append(BEZEL_END * u * u + BEZEL_CTRL * 2.0 * u * t + BEZEL_TIP * t * t)
	return pts


static func left_bezel() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	pts.append_array(bezel_curve())
	return pts


static func mirror(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(SCREEN_W - p.x, p.y))
	return out


## W4 contract for full-screen canvases: global polygons of everything this node draws
## (left console, right console, left bezel, right bezel).
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var out: Array[PackedVector2Array] = []
	for shape in [LEFT_CONSOLE, RIGHT_CONSOLE, left_bezel(), mirror(left_bezel())]:
		out.append(xf * (shape as PackedVector2Array))
	return out


func _draw() -> void:
	redraw_count += 1
	_draw_console(LEFT_CONSOLE, 1.0)
	_draw_console(RIGHT_CONSOLE, -1.0)
	_draw_bezel(left_bezel(), bezel_curve(), GLINT_FROM, GLINT_TO)
	_draw_bezel(mirror(left_bezel()), mirror(bezel_curve()),
		Vector2(SCREEN_W - GLINT_FROM.x, GLINT_FROM.y), Vector2(SCREEN_W - GLINT_TO.x, GLINT_TO.y))


func _draw_console(poly: PackedVector2Array, side: float) -> void:
	draw_colored_polygon(poly, Palette.alpha(Palette.ABYSS_800, CONSOLE_ALPHA))
	# Top edge, chamfer and inner side (points 0..3); the outer screen edges stay bare.
	var edge := PackedVector2Array([poly[0], poly[1], poly[2], poly[3]])
	draw_polyline(edge, Palette.alpha(Palette.SONAR, CONSOLE_EDGE_ALPHA), Palette.EDGE, true)
	var b := Vector2(BRACKET_AT.x if side > 0.0 else SCREEN_W - BRACKET_AT.x, BRACKET_AT.y)
	var arm := float(Palette.BRACKET_ARM)
	draw_polyline(PackedVector2Array([b + Vector2(0, arm), b, b + Vector2(arm * side, 0)]),
		Palette.alpha(Palette.SONAR, BRACKET_ALPHA), Palette.EDGE, true)


func _draw_bezel(shape: PackedVector2Array, curve: PackedVector2Array, g0: Vector2, g1: Vector2) -> void:
	draw_colored_polygon(shape, Palette.alpha(Palette.ABYSS_900, BEZEL_ALPHA))
	draw_polyline(curve, Palette.alpha(Palette.SONAR, BEZEL_EDGE_ALPHA), Palette.EDGE_HAIR, true)
	draw_line(g0, g1, Palette.alpha(Palette.SONAR_PALE, GLINT_ALPHA), Palette.EDGE, true)
