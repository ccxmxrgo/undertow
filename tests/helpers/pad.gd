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


## Sends a stick deflection, then a return to centre, one frame apart, and awaits a frame.
## Always goes through Input.parse_input_event: Godot's GUI moves focus on a JoypadMotion only
## when Input also reports the action as just pressed, which a bare Viewport.push_input skips.
## `target` is kept for symmetry with tap() and is unused.
static func flick(_target: Object, axis: int, value: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Input.parse_input_event(motion(axis, value))
	await tree.process_frame
	Input.parse_input_event(motion(axis, 0.0))
	await tree.process_frame


static func _send(target: Object, ev: InputEvent) -> void:
	if target is Viewport:
		(target as Viewport).push_input(ev)
	else:
		Input.parse_input_event(ev)
