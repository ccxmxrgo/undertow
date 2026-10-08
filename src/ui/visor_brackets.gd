class_name VisorBrackets
extends Control
## Visor bracket corners (always drawn) and decorative edge readouts (hidden in Low effects).
## Static, decorative only: no lane colors, accent or red.

const INSET := 16.0
const LEG := 64.0
const STROKE := 2.0
const W := 1920.0
const H := 1080.0
const TOP_TEXT := "UNDERTOW // VISOR"
const LEFT_TEXT := "HULL SCAN"
const RIGHT_TEXT := "SONAR ACTIVE"

var _readouts: bool = true


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.connect(apply_low_effects)
	apply_low_effects()


func _exit_tree() -> void:
	if Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.disconnect(apply_low_effects)


func apply_low_effects() -> void:
	_readouts = not Settings.low_effects
	queue_redraw()


func readouts_visible() -> bool:
	return _readouts


func brackets_visible() -> bool:
	return true


func _draw() -> void:
	var c := Palette.DIM
	var x0 := INSET
	var x1 := W - INSET
	var y0 := INSET
	var y1 := H - INSET
	# top-left, top-right, bottom-left, bottom-right
	_bracket(Vector2(x0, y0), 1.0, 1.0, c)
	_bracket(Vector2(x1, y0), -1.0, 1.0, c)
	_bracket(Vector2(x0, y1), 1.0, -1.0, c)
	_bracket(Vector2(x1, y1), -1.0, -1.0, c)
	if not _readouts:
		return
	var f := Palette.font()
	var s := Palette.SIZE_LABEL
	var asc := f.get_ascent(s)
	var tw := f.get_string_size(TOP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(f, Vector2((W - tw) * 0.5, 16.0 + asc), TOP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)
	var base_y := 1064.0 - f.get_descent(s)
	draw_string(f, Vector2(96.0, base_y), LEFT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)
	var rw := f.get_string_size(RIGHT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(f, Vector2(W - 96.0 - rw, base_y), RIGHT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)


func _bracket(corner: Vector2, sx: float, sy: float, c: Color) -> void:
	var h := Rect2(corner, Vector2(LEG * sx, STROKE * sy)).abs()
	var v := Rect2(corner, Vector2(STROKE * sx, LEG * sy)).abs()
	draw_rect(h, c)
	draw_rect(v, c)
