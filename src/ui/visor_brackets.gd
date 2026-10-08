class_name VisorBrackets
extends Control
## Visor bracket corners (always drawn) plus reticle marks around the playfield.
## Text readouts moved to VisorHud in 01.1-06. Static, decorative only. Recording-frame chrome:
## off-white corner brackets, hot red reticle marks. No lane colors.

const INSET := 16.0
const LEG := 64.0
const STROKE := 2.0
const W := 1920.0
const H := 1080.0
## Reticle: small L marks framing the lens interior, outside the highway clear rect.
const RETICLE_LEG := 24.0
const RETICLE_PTS: Array[Vector2] = [Vector2(232.0, 240.0), Vector2(1688.0, 240.0),
	Vector2(232.0, 840.0), Vector2(1688.0, 840.0)]


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Text readouts are owned by VisorHud since 01.1-06; kept for API compatibility.
func readouts_visible() -> bool:
	return false


func brackets_visible() -> bool:
	return true


func _draw() -> void:
	var c := Palette.alpha(Palette.REC_TEXT, 0.7)
	var x0 := INSET
	var x1 := W - INSET
	var y0 := INSET
	var y1 := H - INSET
	# top-left, top-right, bottom-left, bottom-right
	_bracket(Vector2(x0, y0), 1.0, 1.0, LEG, c)
	_bracket(Vector2(x1, y0), -1.0, 1.0, LEG, c)
	_bracket(Vector2(x0, y1), 1.0, -1.0, LEG, c)
	_bracket(Vector2(x1, y1), -1.0, -1.0, LEG, c)
	for i in RETICLE_PTS.size():
		var p := RETICLE_PTS[i]
		var sx := 1.0 if p.x < W * 0.5 else -1.0
		var sy := 1.0 if p.y < H * 0.5 else -1.0
		_bracket(p, sx, sy, RETICLE_LEG, Palette.REC_RED)


func _bracket(corner: Vector2, sx: float, sy: float, leg: float, c: Color) -> void:
	var h := Rect2(corner, Vector2(leg * sx, STROKE * sy)).abs()
	var v := Rect2(corner, Vector2(STROKE * sx, leg * sy)).abs()
	draw_rect(h, c)
	draw_rect(v, c)
