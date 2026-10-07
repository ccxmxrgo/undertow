class_name Conductor
extends Node
## Single source of song_time (D-05). Wraps an AudioStreamPlayer (Music bus) and a pure
## ClockModel. Start routine (D-07): song_time runs from the system clock while negative,
## play() fires so the audible start lands at song_time == 0, then the clock is disciplined
## onto the audio clock. Never accumulates frame delta.

signal paused
signal resumed
signal countdown_tick(n: int)

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
var _start_pos: float = 0.0  # stream position the current/next audio start plays from
## {time, bpm} entries (sorted); lets resume() compute the countdown from the chart BPM.
var tempo_map: Array[Dictionary] = []
var _resume_pending: bool = false
var _deferred_start: bool = false  # resumed from a negative (pre-roll) position: audio starts later
var _cd_beats: int = 0
var _cd_spb: float = 0.5
var _cd_start_ticks: int = 0
var _cd_emitted: int = 0


func _init() -> void:
	clock = ClockModel.new()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	# Run before every other node's _process so consumers read a fresh song_time.
	process_priority = -1000


## Start from song_time = -lead_in_s. The stream's position 0 is heard at song_time 0.
func begin(stream: AudioStream, lead_in_s: float) -> void:
	_player.stream = stream
	_start(0.0, lead_in_s)


## The one begin path (D-26): song_time runs from start_pos - lead_in_s on the system clock
## and audio is scheduled so position start_pos is heard at song_time == start_pos.
func _start(start_pos: float, lead_in_s: float) -> void:
	var now := Time.get_ticks_usec()
	_refresh_latency_if_due(now)
	_start_pos = start_pos
	clock.begin_preroll(now, lead_in_s, start_pos)
	var time_delay := AudioServer.get_time_to_next_mix() + _latency_cache
	# Heard position p maps to song_time p - audio_offset, so start must be heard at -audio_offset.
	_play_at = start_pos - time_delay - Settings.audio_offset
	_playing_requested = false
	_audio_valid = false
	_resume_pending = false
	_preroll = true
	_active = true
	if _play_at <= clock.song_time():
		_start_audio()


## Freeze song_time and stop the player. Does not touch SceneTree pause (Pitfall 8).
func pause() -> void:
	if not _active or clock.is_paused():
		return
	clock.pause(Time.get_ticks_usec())
	_player.stop()
	_playing_requested = false
	_audio_valid = false
	_preroll = false
	_resume_pending = false
	_deferred_start = false
	paused.emit()


## Count `beats` beats at the chart BPM (song_time stays frozen), then continue from the
## paused position; audio restarts via play(paused_position) early enough to be heard on time.
func resume(beats: int = 3) -> void:
	if not _active or not clock.is_paused():
		return
	var now := Time.get_ticks_usec()
	_refresh_latency_if_due(now)
	var paused_pos := clock.paused_position()
	# Never seek the stream to a negative position (CR-01): a pause during the lead-in resumes
	# as pre-roll and the audio is scheduled so stream position 0 is heard at song_time 0.
	_start_pos = maxf(paused_pos, 0.0)
	_deferred_start = paused_pos < 0.0
	if _deferred_start:
		_play_at = -(AudioServer.get_time_to_next_mix() + _latency_cache) - Settings.audio_offset
	_cd_beats = beats
	_cd_spb = 60.0 / bpm_at(paused_pos)
	_cd_start_ticks = now
	_cd_emitted = 0
	clock.resume(now, beats * _cd_spb)
	_resume_pending = true
	_emit_countdown_ticks(now)


func is_paused() -> bool:
	return clock.is_paused()


func bpm_at(song_pos: float) -> float:
	var bpm := 120.0
	for e in tempo_map:
		if float(e["time"]) <= song_pos + 1e-9:
			bpm = float(e["bpm"])
	return bpm


func stop() -> void:
	_player.stop()
	_active = false
	_preroll = false
	_playing_requested = false
	_audio_valid = false
	_resume_pending = false
	_deferred_start = false
	clock.state = ClockModel.State.IDLE


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
	if _resume_pending:
		_emit_countdown_ticks(now)
		var lead_ticks := int((AudioServer.get_time_to_next_mix() + _latency_cache + Settings.audio_offset) * 1000000.0)
		if not _deferred_start and not _playing_requested and now >= clock.resume_ticks() - lead_ticks:
			_start_audio()
	elif _preroll and not _playing_requested and clock.song_time() >= _play_at:
		_start_audio()
	_audio_valid = _playing_requested and _player.playing and _player.get_playback_position() > _start_pos
	var target := 0.0
	if _audio_valid:
		target = _player.get_playback_position() + AudioServer.get_time_since_last_mix() 			- _latency_cache - Settings.audio_offset
	clock.update(now, target, _audio_valid)
	if _resume_pending and not clock.is_paused():
		_resume_pending = false
		if _deferred_start:
			_deferred_start = false
			_preroll = true
		resumed.emit()


func _emit_countdown_ticks(now_ticks: int) -> void:
	while _cd_emitted < _cd_beats 			and (now_ticks - _cd_start_ticks) / 1000000.0 >= _cd_emitted * _cd_spb - 1e-9:
		countdown_tick.emit(_cd_beats - _cd_emitted)
		_cd_emitted += 1


func _start_audio() -> void:
	_player.play(_start_pos)
	_playing_requested = true


## Output latency can be expensive to query: cached, refreshed about once per second.
func _refresh_latency_if_due(now_ticks: int) -> void:
	if now_ticks >= _latency_next_refresh_ticks:
		_latency_cache = AudioServer.get_output_latency()
		_latency_next_refresh_ticks = now_ticks + LATENCY_REFRESH_USEC
