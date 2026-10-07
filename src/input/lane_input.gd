class_name LaneInput
extends Node
## Captures lane presses in _input (never polled in _process, D-06). The tick stamp is the
## first statement so it is as close to dispatch time as possible, then mapped to song time
## through the Conductor's ticks <-> song-time anchor.

signal lane_pressed(lane: int, ticks: int)

const ACTIONS: Array[StringName] = [&"lane_1", &"lane_2", &"lane_3", &"lane_4"]

var conductor: Conductor
var judge: InputJudge


func _ready() -> void:
	Input.use_accumulated_input = false


func setup(p_conductor: Conductor, p_judge: InputJudge) -> void:
	conductor = p_conductor
	judge = p_judge


func _input(event: InputEvent) -> void:
	var ticks := Time.get_ticks_usec()
	if event.is_echo() or conductor == null or judge == null:
		return
	for lane in range(ACTIONS.size()):
		if event.is_action_pressed(ACTIONS[lane]):
			var t := conductor.song_time_at(ticks)
			judge.press(lane, t)
			lane_pressed.emit(lane, ticks)
			return
