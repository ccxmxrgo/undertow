class_name Pad
extends RefCounted
## Gamepad event helpers for tests (G3, plans 02.2-28 / 02.2-29). Events use device 0 so they
## match the InputMap's "all devices" (-1) entries like a real controller would.


static func button(index: int, pressed: bool = true, device: int = 0) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = index as JoyButton
	ev.pressed = pressed
	ev.pressure = 1.0 if pressed else 0.0
	return ev


static func motion(axis: int, value: float, device: int = 0) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis as JoyAxis
	ev.axis_value = value
	return ev


## Sends a press then a release of `index` and awaits one process frame.
## `target` is a Viewport (GUI path via push_input) or null (Input.parse_input_event path).
static func tap(target: Object, index: int) -> void:
	_send(target, button(index, true))
	_send(target, button(index, false))
	await (Engine.get_main_loop() as SceneTree).process_frame


## Pushes a stick deflection then a return to centre and awaits one process frame.
static func flick(target: Object, axis: int, value: float) -> void:
	_send(target, motion(axis, value))
	_send(target, motion(axis, 0.0))
	await (Engine.get_main_loop() as SceneTree).process_frame


static func _send(target: Object, ev: InputEvent) -> void:
	if target is Viewport:
		(target as Viewport).push_input(ev)
	else:
		Input.parse_input_event(ev)
