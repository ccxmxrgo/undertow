class_name Conductor
extends Node
## Single source of song_time (D-05). Wraps an AudioStreamPlayer (Music bus) and a pure
## ClockModel. Start routine (D-07): song_time runs from the system clock while negative,
## play() fires so the audible start lands at song_time == 0, then the clock is disciplined
## onto the audio clock. Never accumulates frame delta.

const LATENCY_REFRESH_USEC := 1000000

var clock: ClockModel
var _player: AudioStreamPlayer
var _latency_cache: float = 0.0
var _latency_next_refresh_ticks: int = 0
var _playing_requested: bool = false  # play() has been called
var _preroll: bool = false
var _active: bool = false
var _play_at: float = 0.0
var _audio_valid: bool = false


func _init() -> void:
	clock = ClockModel.new()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	# Run before every other node's _process so consumers read a fresh song_time.
	process_priority = -1000


## Start from song_time = -lead_in_s. The stream's position 0 is heard at song_time 0.
func begin(stream: AudioStream, lead_in_s: float) -> void:
	var now := Time.get_ticks_usec()
	_refresh_latency_if_due(now)
	_player.stream = stream
	clock.reset(now, -lead_in_s)
	var time_delay := AudioServer.get_time_to_next_mix() + _latency_cache
	# Heard position p maps to song_time p - audio_offset, so start must be heard at -audio_offset.
	_play_at = -time_delay - Settings.audio_offset
	_playing_requested = false
	_audio_valid = false
	_preroll = true
	_active = true
	if _play_at <= clock.song_time():
		_start_audio()


func stop() -> void:
	_player.stop()
	_active = false
	_preroll = false
	_playing_requested = false
	_audio_valid = false


func song_time() -> float:
	return clock.song_time()


func song_time_at(ticks: int) -> float:
	return clock.song_time_at(ticks)


## Raw player position for the spike readout / F3 overlay.
func raw_position() -> float:
	return _player.get_playback_position() if _playing_requested else 0.0


func audio_valid() -> bool:
	return _audio_valid


func output_latency() -> float:
	return _latency_cache


func _process(_delta: float) -> void:
	if not _active:
		return
	var now := Time.get_ticks_usec()
	_refresh_latency_if_due(now)
	if _preroll and not _playing_requested and clock.song_time() >= _play_at:
		_start_audio()
	_audio_valid = _playing_requested and _player.playing and _player.get_playback_position() > 0.0
	var target := 0.0
	if _audio_valid:
		target = _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- _latency_cache - Settings.audio_offset
	clock.update(now, target, _audio_valid)


func _start_audio() -> void:
	_player.play(0.0)
	_playing_requested = true


## Output latency can be expensive to query: cached, refreshed about once per second.
func _refresh_latency_if_due(now_ticks: int) -> void:
	if now_ticks >= _latency_next_refresh_ticks:
		_latency_cache = AudioServer.get_output_latency()
		_latency_next_refresh_ticks = now_ticks + LATENCY_REFRESH_USEC
