class_name InkTopLayer
extends Control
## Drawn ABOVE InkCloudLayer (03-UI-SPEC 7.4 InkTopLayer row, PAY-04): while the ink is up,
## the hit-line ticks (60%), receptor outlines in the lane colour (60%, 4 px), the receptor
## press fill (lane colour 40% while the lane is lit) and the lane numbers (90%) stay visible,
## so presses still register visually. Everything fades with PayloadStack.ink_amount.
##
## It does NOT call UiKit.register_fx: its output is identical in every effect mode, and
## tests/test_effect_settings.gd requires registered nodes to change effect_counts() under Low
## or Reduce. effect_counts() exists for debugging only. Board layer (keep-out exempt).

const TICK_ALPHA := 0.60
const OUTLINE_ALPHA := 0.60
const OUTLINE_W := 4.0
const PRESS_FILL := 0.40

var highway: Highway
var _ring := PackedVector2Array()
var _dbg := {"drawn": false, "ticks": 0, "outlines": 0, "fills": 0}
var _ink_shown := false


func _init() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_highway: Highway) -> void:
	highway = p_highway
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"ink_top": true}


func ink_alpha() -> float:
	if highway == null or highway.payloads == null:
		return 0.0
	return clampf(highway.payloads.ink_amount(highway._vt), 0.0, 1.0)


func debug_state() -> Dictionary:
	return _dbg.duplicate()


func _process(_delta: float) -> void:
	# Redraw only while ink is visible, plus one frame to clear it (WR-10).
	if highway == null:
		return
	var on := ink_alpha() > 0.0
	if on or _ink_shown:
		queue_redraw()
	_ink_shown = on


func _draw() -> void:
	# Reset in place: no Dictionary allocation per draw (WR-10).
	_dbg["drawn"] = false
	_dbg["ticks"] = 0
	_dbg["outlines"] = 0
	_dbg["fills"] = 0
	var a := ink_alpha()
	if a <= 0.0:
		return
	_dbg["drawn"] = true
	var tick := Palette.alpha(Palette.SONAR_PALE, TICK_ALPHA * a)
	var hh := Highway.HIT_TICK_H * 0.5
	for f in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		var p := Trench.point(f, 0.0)
		draw_line(Vector2(p.x, p.y - hh), Vector2(p.x, p.y + hh), tick, Highway.HIT_TICK_W)
		_dbg["ticks"] += 1
	var ra := clampf(highway.receptor_alpha, 0.0, 1.0) * a
	var now := Time.get_ticks_usec()
	for lane in range(Highway.LANES):
		var col := Palette.lane_color(lane)
		var kind := NoteShape.kind_for_lane(lane)
		var lit := highway.lane_lit(lane, now)
		for c in highway.lane_columns(lane):
			var center := Trench.point(c.x, 0.0)
			var ca := ra * c.y
			if lit:
				var unit: PackedVector2Array = NotePainter.unit_shape(kind)["poly"]
				draw_set_transform(center, 0.0, Vector2(Highway.RECEPTOR_R, Highway.RECEPTOR_R))
				draw_colored_polygon(unit, Palette.alpha(col, PRESS_FILL * ca))
				draw_set_transform_matrix(Transform2D.IDENTITY)
				_dbg["fills"] += 1
			_outline(kind, center, Highway.RECEPTOR_R - 2.0, Palette.alpha(col, OUTLINE_ALPHA * ca))
			_dbg["outlines"] += 1
	highway.draw_lane_numbers_into(self, a)


func _outline(kind: int, center: Vector2, k: float, col: Color) -> void:
	var ring := NotePainter.outline_ring(kind)
	var n := ring.size()
	if _ring.size() != n:
		_ring.resize(n)
	for i in range(n):
		_ring[i] = center + ring[i] * k
	draw_polyline(_ring, col, OUTLINE_W, true)
