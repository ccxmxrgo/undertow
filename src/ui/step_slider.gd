class_name StepSlider
extends Control
## Focusable slider (02.2 UI-SPEC 9.3): 8 px ABYSS_600 track, SONAR fill, 16 x 32 chamfered
## TEXT_HI thumb; focus adds a SONAR stroke glow (none on Low effects) and a 2 px SONAR_PALE
## thumb edge. The track is inset PAD_X on both sides so the screen's FocusMarker bar (x+8) sits
## left of it. Left/Right (ui_left/ui_right) change the value by one `step`; holding past 400 ms
## repeats at 10 Hz using `repeat_step` (defaults to `step`). Mouse click/drag sets the value.
## `released` fires when a key hold or mouse drag ends (used to play a sample once).

signal value_changed(v: float)
signal released

const HOLD_DELAY := 0.4
const REPEAT_INTERVAL := 0.1
const TRACK_H := 8.0
const HANDLE_W := 16.0
const HANDLE_H := 32.0
const HEIGHT := 48.0  # compact row height (UI-SPEC 4.2)
const PAD_X := 24.0

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.1
var repeat_step: float = 0.0
var value: float = 0.0

var _hold_dir: int = 0
var _hold_time: float = 0.0
var _repeat_time: float = 0.0
var _dragging: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(320.0, HEIGHT)
	set_process(false)


func setup(p_min: float, p_max: float, p_step: float, p_value: float, p_repeat_step: float = 0.0) -> void:
	min_value = p_min
	max_value = p_max
	step = p_step
	repeat_step = p_repeat_step
	value = _snap(p_value)
	queue_redraw()


## Sets the value (snapped and clamped). Emits value_changed only when it actually changes.
func set_value(v: float) -> void:
	var nv := _snap(v)
	if is_equal_approx(nv, value):
		return
	value = nv
	queue_redraw()
	value_changed.emit(value)


## Moves by `dir` steps (dir -1 or +1) of the given size.
func step_by(dir: int, size: float = 0.0) -> void:
	set_value(value + dir * (size if size > 0.0 else step))


func _snap(v: float) -> float:
	if not is_finite(v):
		return min_value
	return snappedf(clampf(v, min_value, max_value), step)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		_dragging = mb.pressed
		if mb.pressed:
			grab_focus()
			_set_from_x(mb.position.x)
		else:
			released.emit()
		accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
		return
	for dir in [-1, 1]:
		var action: StringName = &"ui_left" if dir < 0 else &"ui_right"
		if event.is_action(action):
			if event.is_echo():
				accept_event()  # our own timing handles repeat (400 ms, 10 Hz)
			elif event.is_pressed():
				step_by(dir)
				_hold_dir = dir
				_hold_time = 0.0
				_repeat_time = 0.0
				set_process(true)
				accept_event()
			else:
				if _hold_dir == dir:
					_hold_dir = 0
					set_process(false)
				released.emit()
				accept_event()
			return


func _process(delta: float) -> void:
	if _hold_dir == 0 or not has_focus():
		_hold_dir = 0
		set_process(false)
		return
	var action: StringName = &"ui_left" if _hold_dir < 0 else &"ui_right"
	if not Input.is_action_pressed(action):
		_hold_dir = 0
		set_process(false)
		released.emit()
		return
	_hold_time += delta
	if _hold_time < HOLD_DELAY:
		return
	_repeat_time += delta
	while _repeat_time >= REPEAT_INTERVAL:
		_repeat_time -= REPEAT_INTERVAL
		step_by(_hold_dir, repeat_step if repeat_step > 0.0 else step)


## Colours per focus state (UI-SPEC 9.3): track, fill, thumb, thumb_edge, glow (bool).
static func colors(focused: bool) -> Dictionary:
	return {
		"track": Palette.ABYSS_600,
		"fill": Palette.SONAR,
		"thumb": Palette.TEXT_HI,
		"thumb_edge": Palette.SONAR_PALE if focused else Palette.TEXT_HI,
		"glow": focused,
	}


## The usable track span in local coordinates (between the PAD_X insets).
func track_rect() -> Rect2:
	var w := maxf(size.x - PAD_X * 2.0, 1.0)
	return Rect2(PAD_X, (size.y - TRACK_H) * 0.5, w, TRACK_H)


## Thumb centre x for the current value.
func thumb_x() -> float:
	var span := maxf(max_value - min_value, 0.0001)
	var tr := track_rect()
	return tr.position.x + clampf((value - min_value) / span, 0.0, 1.0) * tr.size.x


func thumb_rect() -> Rect2:
	return Rect2(thumb_x() - HANDLE_W * 0.5, (size.y - HANDLE_H) * 0.5, HANDLE_W, HANDLE_H)


func _set_from_x(x: float) -> void:
	var tr := track_rect()
	var t := clampf((x - tr.position.x) / tr.size.x, 0.0, 1.0)
	set_value(min_value + t * (max_value - min_value))


func _draw() -> void:
	var col := colors(has_focus())
	var tr := track_rect()
	draw_rect(tr, col.track)
	var fill := Rect2(tr.position, Vector2(thumb_x() - tr.position.x, TRACK_H))
	if fill.size.x > 0.0:
		draw_rect(fill, col.fill)
	var th := thumb_rect()
	var pts := UiKit.chamfer_points(th, Palette.CUT_SM * 0.5)
	if col.glow and not UiKit.low_effects():
		# Stroke glow (UI-SPEC 3.3): +8 px at 12% and +16 px at 6% around the thumb.
		for g: Array in [[16.0, 0.06], [8.0, 0.12]]:
			var gp := UiKit.chamfer_points(th.grow(g[0] * 0.5), Palette.CUT_SM * 0.5 + g[0] * 0.25)
			draw_colored_polygon(gp, Color(Palette.SONAR, g[1]))
	draw_colored_polygon(pts, col.thumb)
	if has_focus():
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col.thumb_edge, Palette.EDGE, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_RESIZED:
		queue_redraw()
