class_name DiveAudio
extends Node
## Underwater dive audio (05-04, AV-03). One node per run, a child of Gameplay's run root.
##
##   D-02 sonar pings - a soft ping on every bar start at song time >= 0, scheduled by the pure
##        DownbeatScheduler. Godot has no scheduled play(), so the ping sample carries
##        AudioSynth.PING_LEAD_SEC of leading silence and is started early with
##        play(from_position):
##            head = song_t + output_latency + audio_offset + time_to_next_mix
##            from_position = lead - (bar_time - head)
##        Never during pause, the count-in before 0 or after the song end.
##   D-03 muffle - a runtime AudioEffectLowPassFilter on bus Music only. Disabled at hull >= 75,
##        follows HullAudioCurve.cutoff_for_hull down to the 1500 Hz floor with SMOOTH_TAU
##        smoothing, and slams to the floor in ~SLAM_SEC when the hull breaks (failed).
##   D-04 hull creaks - damage creaks (below 70 hull) and ambient creaks (below 60 hull) picked by
##        CreakDirector, louder and more frequent as the hull drops.
##
## Rules: SFX and Master are never filtered. The filter is added when the node enters the tree
## (stale filters left on Music are removed first, so there is always exactly one) and removed
## by instance when it leaves, so menus and Song Select previews are never muffled.
## default_bus_layout.tres is never edited. Audio only: never registered as an fx node (Pitfall 3).
## Reads the pinned Conductor's public API only.

const PING_PLAYERS := 2
const CREAK_PLAYERS := 2
const CUTOFF_WRITE_EPS := 0.005  # write cutoff_hz only when it moved more than 0.5 %
const MUSIC_BUS := &"Music"
## Slam smoothing: the log-space one-pole reaches FLOOR_HZ * 1.05 from OPEN_HZ in 4 tau
## (ln(20000/1500) * e^-4 = 0.047 < ln 1.05), i.e. within SLAM_SEC. SLAM_SEC / 3 would still be
## 8 % above the floor at 0.35 s because the glide runs in log frequency.
const SLAM_TAU := HullAudioCurve.SLAM_SEC / 4.0

var _conductor: Conductor
var _score: HullScore
var _scheduler: DownbeatScheduler
var _director: CreakDirector
var _song_len: float = 0.0
var _hull: float = 100.0
var _live: bool = false
var _slammed: bool = false
var _needs_reset: bool = false
var _was_paused: bool = false
var _last_song_t: float = 0.0

var _ping_stream: AudioStreamWAV
var _creak_streams: Array = []
var _ping_players: Array[AudioStreamPlayer] = []
var _creak_players: Array[AudioStreamPlayer] = []
var _next_ping: int = 0
var _next_creak: int = 0
var _ping_count: int = 0
var _creak_count: int = 0

var _lpf: AudioEffectLowPassFilter
var _lpf_on: bool = false
var _cutoff: float = HullAudioCurve.OPEN_HZ
var _written_cutoff: float = HullAudioCurve.OPEN_HZ


func _ready() -> void:
	var bank := AudioSynth.sfx_bank()  # cached once per process; never built mid-song
	_ping_stream = bank.get("sonar_ping")
	_creak_streams = bank.get("creaks", [])
	var bus: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	for i in range(PING_PLAYERS):
		_ping_players.append(_new_player(bus))
	for i in range(CREAK_PLAYERS):
		_creak_players.append(_new_player(bus))


func _enter_tree() -> void:
	_install_lpf()


func _exit_tree() -> void:
	_remove_lpf()


func _new_player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


## Wires the run: conductor (resumed -> scheduler reset), chart (bars, song length, creak seed)
## and score (hull_changed -> muffle target and damage creaks, failed -> slam).
func bind(p_conductor: Conductor, p_chart: ChartData, p_score: HullScore) -> void:
	_conductor = p_conductor
	_score = p_score
	_song_len = ProgressTrack.song_length_of(p_chart)
	_hull = p_score.hull if p_score != null else 100.0
	_scheduler = DownbeatScheduler.new(p_chart.tempo_map, p_chart.time_sigs, AudioSynth.PING_LEAD_SEC)
	_director = CreakDirector.new(hash(p_chart.id) & 0x7FFFFFFF, 4 if _creak_streams.is_empty() else _creak_streams.size())
	if p_score != null:
		if not p_score.hull_changed.is_connected(_on_hull_changed):
			p_score.hull_changed.connect(_on_hull_changed)
		if not p_score.failed.is_connected(slam):
			p_score.failed.connect(slam)
	if p_conductor != null and not p_conductor.resumed.is_connected(_on_resumed):
		p_conductor.resumed.connect(_on_resumed)


## Pings and creaks only play while live (set by Gameplay when the conductor begins; cleared on
## fail, finish and online exits). The muffle runs regardless.
func set_live(on: bool) -> void:
	_live = on


## Wreck / implosion: ramp the Music filter to FLOOR_HZ over ~SLAM_SEC and hold it there.
func slam() -> void:
	_slammed = true


func _process(delta: float) -> void:
	if _scheduler == null or _conductor == null or not is_instance_valid(_conductor):
		return
	step(delta, _conductor.song_time(), _conductor.output_latency(), _conductor.audio_offset(),
		AudioServer.get_time_to_next_mix(), _conductor.is_paused())


## The whole per-frame logic (tests drive it with synthetic values).
func step(dt: float, song_t: float, latency: float, offset: float, to_next_mix: float, paused: bool) -> void:
	_step_muffle(dt)
	if _scheduler == null:
		return
	if is_finite(song_t):
		_last_song_t = song_t
	if paused:
		_was_paused = true
		return
	if _was_paused:
		_was_paused = false
		_needs_reset = true
	if not _live or not is_finite(song_t):
		return
	if Settings.sonar_pings and song_t <= _song_len:
		if _needs_reset:
			_scheduler.reset(song_t, latency, offset, to_next_mix)
			_needs_reset = false
		var from := _scheduler.tick(song_t, latency, offset, to_next_mix)
		if from >= 0.0 and _play_ping(from):
			_ping_count += 1
	if Settings.hull_sounds and _director != null:
		_play_creak(_director.tick(_hull, song_t))


func _step_muffle(dt: float) -> void:
	if _lpf == null:
		return
	if not Settings.hull_sounds:
		_cutoff = HullAudioCurve.OPEN_HZ
		_write_cutoff(true)
		_set_lpf_enabled(false)
		return
	var target := HullAudioCurve.FLOOR_HZ if _slammed else HullAudioCurve.cutoff_for_hull(_hull)
	var tau := SLAM_TAU if _slammed else HullAudioCurve.SMOOTH_TAU
	_cutoff = HullAudioCurve.smooth_cutoff(_cutoff, target, dt, tau)
	_write_cutoff(false)
	_set_lpf_enabled(HullAudioCurve.muffle_active(_hull) or _slammed
		or _cutoff < HullAudioCurve.OPEN_HZ * 0.98)


func _write_cutoff(force: bool) -> void:
	if force or absf(_cutoff - _written_cutoff) > _written_cutoff * CUTOFF_WRITE_EPS:
		if _cutoff != _written_cutoff:
			_lpf.cutoff_hz = _cutoff
			_written_cutoff = _cutoff


func _set_lpf_enabled(on: bool) -> void:
	if on == _lpf_on:
		return
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	var idx := _lpf_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_effect_enabled(bus, idx, on)
	_lpf_on = on


func _on_hull_changed(value: float, delta: float) -> void:
	if not is_finite(value):
		return
	_hull = value
	if _live and Settings.hull_sounds and _director != null:
		_play_creak(_director.on_hull_changed(value, delta, _last_song_t))


func _on_resumed() -> void:
	_needs_reset = true


func _play_ping(from: float) -> bool:
	if _ping_players.is_empty() or _ping_stream == null or not is_inside_tree():
		return false
	var p := _ping_players[_next_ping]
	_next_ping = (_next_ping + 1) % _ping_players.size()
	p.stream = _ping_stream
	p.volume_db = 0.0
	p.play(from)
	return true


func _play_creak(c: Dictionary) -> void:
	if c.is_empty() or _creak_players.is_empty() or _creak_streams.is_empty() or not is_inside_tree():
		return
	var v := clampi(int(c.get("variant", 0)), 0, _creak_streams.size() - 1)
	var p := _creak_players[_next_creak]
	_next_creak = (_next_creak + 1) % _creak_players.size()
	p.stream = _creak_streams[v]
	p.volume_db = float(c.get("db", -18.0))
	p.pitch_scale = float(c.get("pitch", 1.0))
	p.play()
	_creak_count += 1


# --- Music bus filter lifetime ------------------------------------------------------------

func _install_lpf() -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			AudioServer.remove_bus_effect(bus, i)
	if _lpf == null:
		_lpf = AudioEffectLowPassFilter.new()
		_lpf.resonance = 0.5
		_lpf.db = AudioEffectFilter.FILTER_12DB
	_lpf.cutoff_hz = _cutoff
	_written_cutoff = _cutoff
	AudioServer.add_bus_effect(bus, _lpf)
	AudioServer.set_bus_effect_enabled(bus, AudioServer.get_bus_effect_count(bus) - 1, false)
	_lpf_on = false


func _remove_lpf() -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	var idx := _lpf_index(bus)
	if idx >= 0:
		AudioServer.remove_bus_effect(bus, idx)
	_lpf_on = false


## Index of this node's own filter on `bus` (searched by instance, so shifted indices are fine).
func _lpf_index(bus: int) -> int:
	if bus < 0 or _lpf == null:
		return -1
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _lpf:
			return i
	return -1


# --- Getters ---------------------------------------------------------------------------------

func ping_count() -> int:
	return _ping_count


func creak_count() -> int:
	return _creak_count


func current_cutoff() -> float:
	return _cutoff


func lpf_enabled() -> bool:
	return _lpf_on


func slammed() -> bool:
	return _slammed


func is_live() -> bool:
	return _live


static func music_lpf_count() -> int:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return 0
	var n := 0
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			n += 1
	return n
