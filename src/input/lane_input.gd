class_name LaneInput
extends Node
## Captures lane presses/releases in _input (never polled in _process, D-06). The tick stamp is
## the first statement so it is as close to dispatch time as possible, then mapped to song time
## through the Conductor's ticks <-> song-time anchor.
##
## Emits only on state EDGES: key/button echoes and repeated downs never re-press (D-16), and an
## analog trigger is turned into a digital lane with hysteresis (press at >= 0.5, release at
## <= 0.4) so a held or noisy trigger yields exactly one press and one release (D-19).

signal lane_pressed(lane: int, ticks: int)
signal lane_released(lane: int, ticks: int)

const ACTIONS: Array[StringName] = [&"lane_1", &"lane_2", &"lane_3", &"lane_4"]
const PRESS_THRESHOLD := 0.5
const RELEASE_THRESHOLD := 0.4

var conductor: Conductor
var judge: InputJudge
## Pause/countdown suppress note input (UI-SPEC). Disabling releases anything still held.
var enabled: bool = true:
	set(v):
		if enabled and not v:
			_release_all(Time.get_ticks_usec())
		enabled = v

var _held: Array[bool] = [false, false, false, false]


func _ready() -> void:
	Input.use_accumulated_input = false


func setup(p_conductor: Conductor, p_judge: InputJudge) -> void:
	conductor = p_conductor
	judge = p_judge


## Test seam: feeds an event through the exact production path.
func inject(event: InputEvent) -> void:
	_input(event)


func _input(event: InputEvent) -> void:
	var ticks := Time.get_ticks_usec()
	if not enabled or event.is_echo():
		return
	if event is InputEventJoypadMotion:
		_handle_motion(event as InputEventJoypadMotion, ticks)
		return
	for lane in range(ACTIONS.size()):
		if event.is_action_pressed(ACTIONS[lane]):
			_press(lane, ticks)
			return
		if event.is_action_released(ACTIONS[lane]):
			_release(lane, ticks)
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all(Time.get_ticks_usec())


func _handle_motion(m: InputEventJoypadMotion, ticks: int) -> void:
	for lane in range(ACTIONS.size()):
		for mapped in InputMap.action_get_events(ACTIONS[lane]):
			if not (mapped is InputEventJoypadMotion) or (mapped as InputEventJoypadMotion).axis != m.axis:
				continue
			var sign_dir := -1.0 if (mapped as InputEventJoypadMotion).axis_value < 0.0 else 1.0
			var strength := m.axis_value * sign_dir
			if not _held[lane] and strength >= PRESS_THRESHOLD:
				_press(lane, ticks)
			elif _held[lane] and strength <= RELEASE_THRESHOLD:
				_release(lane, ticks)


func _press(lane: int, ticks: int) -> void:
	if _held[lane]:
		return
	_held[lane] = true
	if conductor != null and judge != null:
		judge.press(lane, conductor.song_time_at(ticks))
	lane_pressed.emit(lane, ticks)


func _release(lane: int, ticks: int) -> void:
	if not _held[lane]:
		return
	_held[lane] = false
	if conductor != null and judge != null:
		judge.release(lane, conductor.song_time_at(ticks))
	lane_released.emit(lane, ticks)


func _release_all(ticks: int) -> void:
	for lane in range(ACTIONS.size()):
		_release(lane, ticks)
