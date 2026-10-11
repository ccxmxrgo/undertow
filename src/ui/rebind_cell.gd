class_name RebindCell
extends Button
## One KEYBOARD or GAMEPAD binding cell (UI-SPEC Settings, restyled in 02.2 UI-SPEC 9.3): a
## compact 48 px theme button. Activating enters a listening state ("PRESS A KEY" /
## "PRESS A BUTTON" in SONAR_PALE, edge pulsing SONAR at 1.2 Hz, static under Reduce motion).
## A rejected bind keeps the inline message copy and shows a WARNING_RED edge until cleared. Keyboard listening takes the next key; gamepad listening
## takes a button or a trigger axis at |value| >= 0.5 (sticks and mouse are ignored). Esc or pad B
## cancels with no change (pad B also cancels a KEYBOARD cell, whose other pad input is swallowed). Results go through BindingStore (duplicates and Tab
## rejected); `message` reports the inline error copy and `bound` fires after a successful bind.

signal bound(action: StringName)
signal message(action: StringName, text: String)

const ACTION_NAMES := {
	&"lane_1": "Lane 1", &"lane_2": "Lane 2", &"lane_3": "Lane 3", &"lane_4": "Lane 4",
	&"fire": "Fire", &"target_cycle": "Target", &"pause": "Pause",
}

var action: StringName = &""
var device: StringName = &"keyboard"
var store: BindingStore
var listening: bool = false
## True after a duplicate / Tab rejection, until the next listen, bind or clear_rejected().
var rejected: bool = false

const PULSE_HZ := 1.2
const LISTEN_TEXT_KEY := "PRESS A KEY"
const LISTEN_TEXT_PAD := "PRESS A BUTTON"

var _pulse: float = 0.0


func setup(p_action: StringName, p_device: StringName, p_store: BindingStore) -> void:
	action = p_action
	device = p_device
	store = p_store
	custom_minimum_size = Vector2(280.0, 48.0)
	focus_mode = Control.FOCUS_ALL
	# Listening starts when the activating press is RELEASED (mouse, Enter / Space, pad A), so
	# the press that opens the cell can never be taken as the new binding (02.2-29).
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	pressed.connect(begin_listen)
	refresh()


func refresh() -> void:
	_apply_text_colour()
	if listening:
		text = LISTEN_TEXT_KEY if device == &"keyboard" else LISTEN_TEXT_PAD
		return
	var name_text := store.display_name(action, device)
	text = "UNBOUND" if name_text == "Unbound" else name_text


func begin_listen() -> void:
	listening = true
	rejected = false
	_pulse = 0.0
	refresh()
	set_process(true)
	queue_redraw()


func cancel_listen() -> void:
	listening = false
	set_process(false)
	refresh()
	queue_redraw()


func clear_rejected() -> void:
	if rejected:
		rejected = false
		queue_redraw()


## Listening edge alpha at `t` seconds: a 1.2 Hz sine between 0.4 and 1.0, or a static 1.0
## under Reduce motion.
static func listen_edge_alpha(t: float, reduce: bool) -> float:
	if reduce:
		return 1.0
	return 0.4 + 0.6 * (0.5 + 0.5 * sin(t * TAU * PULSE_HZ))


## The extra edge drawn over the theme button: WARNING_RED when rejected, pulsing SONAR while
## listening, transparent otherwise.
func edge_color() -> Color:
	if rejected:
		return Palette.WARNING_RED
	if listening:
		return Color(Palette.SONAR, listen_edge_alpha(_pulse, UiKit.reduce_motion()))
	return Color(Palette.SONAR, 0.0)


func _apply_text_colour() -> void:
	if listening:
		for k in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			add_theme_color_override(k, Palette.SONAR_PALE)
	else:
		for k in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			remove_theme_color_override(k)


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var col := edge_color()
	if col.a <= 0.0:
		return
	var pts := UiKit.chamfer_points(Rect2(Vector2.ZERO, size).grow(-1.0), Palette.CUT_SM)
	pts.append(pts[0])
	draw_polyline(pts, col, Palette.EDGE, true)


func _input(event: InputEvent) -> void:
	if listening and handle_event(event):
		get_viewport().set_input_as_handled()


## Feeds one event to the listening cell. Returns true when the event was consumed.
func handle_event(event: InputEvent) -> bool:
	if not listening or event.is_echo():
		return false
	if device == &"keyboard":
		# G3 (02.2-29): a pad-only player must never be stuck on a keyboard cell. Pad B cancels;
		# every other pad event is swallowed so it neither binds nor moves focus / leaves the
		# screen while the cell waits for a key.
		if event is InputEventJoypadButton:
			var pb := event as InputEventJoypadButton
			if pb.pressed and pb.button_index == JOY_BUTTON_B:
				cancel_listen()
			return true
		if event is InputEventJoypadMotion:
			return true
		if not (event is InputEventKey) or not event.is_pressed():
			return false
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			cancel_listen()
			return true
		_apply(store.bind_key(action, k), OS.get_keycode_string(k))
		return true
	# Gamepad listening: only buttons and trigger axes.
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return false
		if jb.button_index == JOY_BUTTON_B:
			cancel_listen()
			return true
		_apply(store.bind_pad(action, event), _pad_label(event))
		return true
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) < BindingStore.TRIGGER_DEADZONE:
			return false
		if not BindingStore.TRIGGER_AXES.has(jm.axis):
			return false  # sticks never bind
		var norm := InputEventJoypadMotion.new()
		norm.axis = jm.axis
		norm.axis_value = absf(jm.axis_value)
		_apply(store.bind_pad(action, norm), _pad_label(norm))
		return true
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		cancel_listen()
		return true
	return false


func _apply(res: Dictionary, input_name: String) -> void:
	match int(res["result"]):
		BindingStore.Result.OK:
			listening = false
			set_process(false)
			refresh()
			queue_redraw()
			bound.emit(action)
		BindingStore.Result.DUPLICATE:
			var other: StringName = res["conflict_action"]
			message.emit(action, "%s is already used for %s. Pick a different key."
				% [input_name, ACTION_NAMES.get(other, String(other))])
			cancel_listen()
			rejected = true
			queue_redraw()
		BindingStore.Result.RESERVED:
			message.emit(action, "Tab can't be used. It is reserved for menus.")
			cancel_listen()
			rejected = true
			queue_redraw()
		_:
			pass  # INVALID: keep listening


static func _pad_label(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var idx := (event as InputEventJoypadButton).button_index
		return BindingStore.PAD_BUTTON_NAMES.get(idx, "Btn %d" % idx)
	if event is InputEventJoypadMotion:
		match (event as InputEventJoypadMotion).axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
	return "Input"
