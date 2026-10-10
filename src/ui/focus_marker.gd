class_name FocusMarker
extends Control
## The animated focus marker (02.2 UI-SPEC 4.3), one per screen. Add it as a child of
## the screen root: it follows keyboard/gamepad focus for controls inside that screen
## only and ignores focus elsewhere (other screens, dialogs on their own layer).
##
## Draws a 4 px bar (control height - 16) at x+8 inside the focused control and a
## 12x16 caret 12 px left of it, pointing right, in SONAR (WARNING_RED for destructive
## buttons). When focus moves it glides over DUR_FAST (cubic out) and its edge glow
## breathes 20%..32% over BREATH_SEC. Reduce motion: jumps, static 28% glow. Low effects:
## no glow halo (glide and breathing stay, UI-SPEC 11). Effect node: see UiKit contract.

const BAR_INSET := Palette.SP_SM  # bar at x+8, 8 px from top and bottom
const CARET_W := 12.0
const CARET_H := 16.0
const CARET_GAP := 12.0
const GLOW_MIN := 0.20
const GLOW_MAX := 0.32
const GLOW_STATIC := 0.28

## Current glow alpha (breathes between GLOW_MIN and GLOW_MAX).
var glow_alpha := GLOW_STATIC

var _target: Control
var _from := Rect2()
var _glide_t := 1.0
var _breath_t := 0.0
var _reduce := false
var _low := false


static func bar_rect(control_size: Vector2) -> Rect2:
	return Rect2(BAR_INSET, BAR_INSET, Palette.FOCUS_BAR, maxf(control_size.y - BAR_INSET * 2, 0.0))


static func caret_points(control_size: Vector2) -> PackedVector2Array:
	var cy := control_size.y * 0.5
	var tip := -CARET_GAP
	return PackedVector2Array([
		Vector2(tip - CARET_W, cy - CARET_H * 0.5),
		Vector2(tip, cy),
		Vector2(tip - CARET_W, cy + CARET_H * 0.5)])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	top_level = true
	z_index = 10
	visible = false
	apply_effect_settings()
	UiKit.register_fx(self)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var owner_now := get_viewport().gui_get_focus_owner()
	if owner_now != null:
		_on_focus_changed(owner_now)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.gui_focus_changed.is_connected(_on_focus_changed):
		vp.gui_focus_changed.disconnect(_on_focus_changed)


func _process(delta: float) -> void:
	advance(delta)


## Effect contract: re-read Low effects / Reduce motion.
func apply_effect_settings() -> void:
	_reduce = UiKit.reduce_motion()
	_low = UiKit.low_effects()
	if _reduce:
		_glide_t = 1.0
		glow_alpha = GLOW_STATIC
	queue_redraw()


## Effect contract: what is animating right now.
func effect_counts() -> Dictionary:
	return {"glide": not _reduce, "breathing": not _reduce, "glow": not _low}


func target() -> Control:
	return _target if is_instance_valid(_target) else null


## SONAR, or WARNING_RED when the focused button is a destructive variant.
func marker_color() -> Color:
	var t := target()
	if t != null and String(t.get_meta(&"ui_variant", "")) == "destructive":
		return Palette.WARNING_RED
	return Palette.SONAR


func _in_screen(c: Control) -> bool:
	var screen := get_parent()
	return c != null and c != self and screen != null and screen.is_ancestor_of(c)


func _on_focus_changed(c: Control) -> void:
	if not _in_screen(c):
		return
	var had := target() != null and visible
	_from = Rect2(position, size)
	_target = c
	if had and not _reduce:
		_glide_t = 0.0
	else:
		_glide_t = 1.0
		_snap()
	queue_redraw()


func _snap() -> void:
	var t := target()
	if t == null:
		return
	var r := t.get_global_rect()
	position = r.position
	size = r.size
	visible = t.is_visible_in_tree()


## Steps the glide and the breathing by `delta` seconds (called from _process).
func advance(delta: float) -> void:
	_reduce = UiKit.reduce_motion()
	var t := target()
	if t == null or not t.is_visible_in_tree():
		visible = false
		return
	var goal := t.get_global_rect()
	if _reduce:
		_glide_t = 1.0
	else:
		_glide_t = minf(_glide_t + delta / Palette.DUR_FAST, 1.0)
	if _glide_t >= 1.0:
		position = goal.position
		size = goal.size
	else:
		var e := 1.0 - pow(1.0 - _glide_t, 3.0)
		position = _from.position.lerp(goal.position, e)
		size = _from.size.lerp(goal.size, e)
	visible = true
	if _reduce:
		glow_alpha = GLOW_STATIC
	else:
		_breath_t = fmod(_breath_t + delta, Palette.BREATH_SEC)
		var mid := (GLOW_MIN + GLOW_MAX) * 0.5
		var amp := (GLOW_MAX - GLOW_MIN) * 0.5
		glow_alpha = mid + amp * sin(TAU * _breath_t / Palette.BREATH_SEC)
	queue_redraw()


func _draw() -> void:
	if target() == null:
		return
	var col := marker_color()
	if not _low:
		# Breathing edge glow: two soft strokes outside the focused control's edge.
		for i in 2:
			var grow := 3.0 + i * 4.0
			var pts := UiKit.chamfer_points(Rect2(Vector2.ZERO, size).grow(grow), Palette.CUT_SM + grow * 0.5)
			pts.append(pts[0])
			draw_polyline(pts, Color(col, glow_alpha * (0.5 - i * 0.25)), Palette.EDGE * 2.0, true)
	draw_rect(bar_rect(size), col)
	draw_colored_polygon(caret_points(size), col)
