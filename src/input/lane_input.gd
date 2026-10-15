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
## Crossed Wires (D-10): this highway's modifier stack. When set, a physical lane action is
## mapped through payloads.input_map(song time) to the judged lane at press time; the release
## always releases the lane recorded at press (RESEARCH Pitfall 3). null = identity (solo).
var payloads: PayloadStack = null
## Versus (WR-01): when valid, presses / releases go to press_fn(lane, song_time) /
## release_fn(lane, song_time) instead of judge.press / judge.release, so the VersusController
## can advance every rival to the press time before the human's judgment reaches the referee.
var press_fn: Callable = Callable()
var release_fn: Callable = Callable()
## Pause/countdown suppress note input (UI-SPEC). Disabling releases anything still held.
var enabled: bool = true:
	set(v):
		if enabled and not v:
			_release_all(Time.get_ticks_usec())
		enabled = v

var _held: Array[bool] = [false, false, false, false]  # union of the two sources below
# Per-source state (WR-04): a lane's key/button and its trigger axis must not release each other.
var _key_held: Array[bool] = [false, false, false, false]
var _axis_held: Array[bool] = [false, false, false, false]
## Judged lane each physical action pressed (-1 = up), and how many actions hold each judged
## lane: every action's press edge presses the lane (WR-03), but the lane is released only on
## the 1 -> 0 edge, so two keys mapped onto one lane across a remap never release each other.
var _pressed_lane: Array[int] = [-1, -1, -1, -1]
var _lane_holders: Array[int] = [0, 0, 0, 0]


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
			_set_source(lane, _key_held, true, ticks)
			return
		if event.is_action_released(ACTIONS[lane]):
			_set_source(lane, _key_held, false, ticks)
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
			if not _axis_held[lane] and strength >= PRESS_THRESHOLD:
				_set_source(lane, _axis_held, true, ticks)
			elif _axis_held[lane] and strength <= RELEASE_THRESHOLD:
				_set_source(lane, _axis_held, false, ticks)


## Update one source's flag; press/release fire only on the union's 0->1 / 1->0 edges.
func _set_source(lane: int, source: Array[bool], down: bool, ticks: int) -> void:
	source[lane] = down
	if down:
		_press(lane, ticks)
	elif not _key_held[lane] and not _axis_held[lane]:
		_release(lane, ticks)


## `action` is the physical lane action index; signals and the judge get the judged lane.
func _press(action: int, ticks: int) -> void:
	if _held[action]:
		return
	_held[action] = true
	var lane := _map_action(action, ticks)
	_pressed_lane[action] = lane
	# Every press edge reaches the judge (WR-03): after a Crossed Wires swap a second key can map
	# onto a judged lane an earlier key still holds (e.g. through a sustain end), and that press
	# is a real hit on the next note. The holder count only gates the release (1 -> 0 edge).
	_lane_holders[lane] += 1
	if conductor != null and judge != null:
		var t := conductor.song_time_at(ticks)
		if press_fn.is_valid():
			press_fn.call(lane, t)
		else:
			judge.press(lane, t)
	lane_pressed.emit(lane, ticks)


func _release(action: int, ticks: int) -> void:
	if not _held[action]:
		return
	_held[action] = false
	var lane := _pressed_lane[action]
	_pressed_lane[action] = -1
	if lane < 0:
		return
	_lane_holders[lane] = maxi(_lane_holders[lane] - 1, 0)
	if _lane_holders[lane] > 0:
		return
	if conductor != null and judge != null:
		var t := conductor.song_time_at(ticks)
		if release_fn.is_valid():
			release_fn.call(lane, t)
		else:
			judge.release(lane, t)
	lane_released.emit(lane, ticks)


## Physical action -> judged lane (identity without payloads or a conductor).
func _map_action(action: int, ticks: int) -> int:
	if payloads == null or conductor == null:
		return action
	var m := payloads.input_map(conductor.song_time_at(ticks))
	if action >= m.size():
		return action
	var lane := m[action]
	return lane if lane >= 0 and lane < ACTIONS.size() else action


func _release_all(ticks: int) -> void:
	for lane in range(ACTIONS.size()):
		_key_held[lane] = false
		_axis_held[lane] = false
		_release(lane, ticks)
