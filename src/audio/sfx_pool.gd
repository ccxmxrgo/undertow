class_name SfxPool
extends Node
## Round-robin pool of AudioStreamPlayers on the SFX bus playing procedural hit sounds
## (Perfect tick, lower Good tick, dull Miss clunk). Streams are built once.

const POOL_SIZE := 8
const GOOD_PITCH := 0.75

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _perfect: AudioStreamWAV
var _good: AudioStreamWAV
var _miss: AudioStreamWAV


func _ready() -> void:
	_perfect = AudioSynth.make_tick(1.0)
	_good = AudioSynth.make_tick(GOOD_PITCH)
	_miss = AudioSynth.make_clunk()
	var bus: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)


func play_judgment(judgment: int) -> void:
	match judgment:
		InputJudge.Judgment.PERFECT:
			_play(_perfect)
		InputJudge.Judgment.GOOD:
			_play(_good)
		_:
			_play(_miss)


func _play(stream: AudioStreamWAV) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.play()
