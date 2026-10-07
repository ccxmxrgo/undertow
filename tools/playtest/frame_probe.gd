extends Node
## Per-frame clock probe. Runs after every other node (priority 1000) so it reads the song_time the
## Conductor produced this frame. Read-only: it never changes game state.

var conductor: Node = null
var rows: Array = []  # [ticks_usec, song_time, audio_valid, audio_target, raw_pos, paused, latency]
var enabled: bool = false


func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not enabled or conductor == null or not is_instance_valid(conductor):
		return
	var now := Time.get_ticks_usec()
	var player: AudioStreamPlayer = conductor.get("_player")
	var lat: float = conductor.output_latency()
	var raw: float = player.get_playback_position() if player != null else 0.0
	var target := raw + AudioServer.get_time_since_last_mix() - lat - Settings.audio_offset
	rows.append([now, conductor.song_time(), conductor.audio_valid(), target, raw,
		conductor.is_paused(), lat])
