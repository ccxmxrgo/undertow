class_name RebindCell
extends Button
## One KEYBOARD or GAMEPAD binding cell (UI-SPEC Settings). Activating enters a listening state
## ("PRESS A KEY..." / "PRESS A BUTTON..."). Keyboard listening takes the next key; gamepad listening
## takes a button or a trigger axis at |value| >= 0.5 (sticks and mouse are ignored). Esc (keyboard)
## or B (gamepad) cancels with no change. Results go through BindingStore (duplicates and Tab
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

var _pulse: float = 0.0


func setup(p_action: StringName, p_device: StringName, p_store: BindingStore) -> void:
	action = p_action
	device = p_device
	store = p_store
	custom_minimum_size = Vector2(280.0, 48.0)
	focus_mode = Control.FOCUS_ALL
	pressed.connect(begin_listen)
	refresh()


func refresh() -> void:
	if listening:
		text = "PRESS A KEY..." if device == &"keyboard" else "PRESS A BUTTON..."
		return
	var name_text := store.display_name(action, device)
	text = "UNBOUND" if name_text == "Unbound" else name_text


func begin_listen() -> void:
	listening = true
	_pulse = 0.0
	refresh()
	set_process(true)
	queue_redraw()


func cancel_listen() -> void:
	listening = false
	set_process(false)
	refresh()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	if listening:
		var a := 0.5 + 0.5 * sin(_pulse * TAU * 1.5)
		draw_rect(Rect2(Vector2.ZERO, size), Palette.alpha(Palette.ACCENT, 0.4 + 0.6 * a), false, 4.0)
	elif has_focus():
		draw_string(Palette.font(), Vector2(8.0, size.y * 0.5 + 8.0), "▶",
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.ACCENT)


func _input(event: InputEvent) -> void:
	if listening and handle_event(event):
		get_viewport().set_input_as_handled()


## Feeds one event to the listening cell. Returns true when the event was consumed.
func handle_event(event: InputEvent) -> bool:
	if not listening or event.is_echo():
		return false
	if device == &"keyboard":
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
		BindingStore.Result.RESERVED:
			message.emit(action, "Tab can't be used. It is reserved for menus.")
			cancel_listen()
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
