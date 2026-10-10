extends Node
## Autoload "MenuMusic" (02.2 D-07, UI-SPEC 5): a random bundled song's preview loops quietly
## on the main menu. It plays on the "Preview" bus (sends to Music, so the Music and Master
## volumes apply, and carries the spectrum analyzer for the song-select visualizer) at -12 dB,
## fades in over 600 ms and loops a 30 s window from the song's preview start with a 400 ms
## cross-fade between two players. stop(fade) is called by Song Select (own preview, dive),
## the menu's Calibrate action and the calibration wizard (RESEARCH Pitfall 7).
## T-02.2-12: only bundled res:// songs are ever auto-played; user library files never are.
## Fades are stepped from _process (or step() in tests), not tweens, so they are deterministic.

const BUS := &"Preview"
const VOLUME_DB := -12.0
const FADE_IN_SEC := 0.6
const LOOP_SEC := 30.0
const XFADE_SEC := 0.4
const MIN_DB := -80.0
const DEFAULT_PULSE_HZ := 0.5

## Seconds into the stream where the loop window starts / ends.
var loop_start: float = 0.0
var loop_end: float = 0.0
## Tests: when >= 0 replaces the active player's playback position for the loop check.
var debug_position: float = -1.0
## Tests set false and call step() by hand.
var auto_process: bool = true
## Null = the Settings / SongLibrary autoloads.
var settings_ref: Node = null
var library_ref: Node = null

var _players: Array[AudioStreamPlayer] = []
var _active := 0
## idle | waiting (no bundled entry listed yet) | loading | playing | stopping
var _state := "idle"
var _gain := 0.0
var _gain_target := 0.0
var _gain_rate := 0.0
var _xfade := -1.0
var _bpm_hz := DEFAULT_PULSE_HZ
var _rng := RandomNumberGenerator.new()
var _request := 0
var _tasks: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % i
		p.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
		p.volume_db = MIN_DB
		add_child(p)
		_players.append(p)
	var s := _settings()
	if s != null and s.has_signal("settings_changed"):
		s.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	_request += 1
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _process(delta: float) -> void:
	if auto_process:
		step(delta)
	_reap(false)


# ---- public API ----

## Starts the menu music (no-op when disabled or already playing; resumes a fade-out).
func start() -> void:
	if not _enabled():
		return
	match _state:
		"playing", "loading", "waiting":
			return
		"stopping":
			_state = "playing"
			_fade_to(1.0, FADE_IN_SEC)
			return
	var lib := _library()
	var pick := _pick(lib)
	if pick == null:
		# The boot scan lists the bundled songs a moment after launch; start when they arrive.
		_state = "waiting"
		if lib != null and lib.has_signal("entries_added") \
				and not lib.entries_added.is_connected(_on_entries_added):
			lib.entries_added.connect(_on_entries_added)
		return
	_load(lib, pick)


## Fades out over `fade_sec` and stops (0 stops at once). Safe to call at any time.
func stop(fade_sec: float = 0.4) -> void:
	_request += 1
	_disconnect_library()
	if _state in ["idle", "waiting", "loading"]:
		_stop_now()
		return
	if fade_sec <= 0.0:
		_stop_now()
		return
	_state = "stopping"
	_fade_to(0.0, fade_sec)


## True while audible (playing, fading in or fading out).
func is_playing() -> bool:
	return _state == "playing" or _state == "stopping"


func state() -> String:
	return _state


## Beat pulse for the abyss specks: bpm / 60 for a constant-tempo song, else 0.5 Hz.
func pulse_hz() -> float:
	return _bpm_hz if is_playing() else DEFAULT_PULSE_HZ


## Test seam (and the loader's main-thread half): plays `stream` from `preview_s`.
func start_with_stream(stream: AudioStream, preview_s: float, bpm: float) -> void:
	if not _enabled() or stream == null or _players.is_empty():
		return
	var length := stream.get_length()
	var w := loop_window(preview_s, length if length > 0.0 else preview_s + LOOP_SEC)
	loop_start = w.x
	loop_end = w.y
	_bpm_hz = pulse_for(bpm, bpm)
	for p in _players:
		p.stop()
		p.stream = stream
	_active = 0
	_xfade = -1.0
	_gain = 0.0
	_players[_active].play(loop_start)
	_state = "playing"
	_fade_to(1.0, FADE_IN_SEC)
	_apply_volumes()


func active_player() -> AudioStreamPlayer:
	return _players[_active] if not _players.is_empty() else null


func gain() -> float:
	return _gain


func crossfading() -> bool:
	return _xfade >= 0.0


## Advances fades and the loop cross-fade by `delta` seconds.
func step(delta: float) -> void:
	if _state != "playing" and _state != "stopping":
		return
	if _gain_rate > 0.0:
		_gain = move_toward(_gain, _gain_target, _gain_rate * delta)
	else:
		_gain = _gain_target
	if _state == "stopping" and _gain <= 0.0001:
		_stop_now()
		return
	var cur := _players[_active]
	var other := _players[1 - _active]
	if _xfade < 0.0:
		var pos := debug_position if debug_position >= 0.0 else cur.get_playback_position()
		if not cur.playing or pos >= loop_end - XFADE_SEC:
			other.volume_db = MIN_DB
			other.play(loop_start)
			_xfade = 0.0
	else:
		_xfade += delta / XFADE_SEC
		if _xfade >= 1.0:
			cur.stop()
			_active = 1 - _active
			_xfade = -1.0
	_apply_volumes()


# ---- pure helpers (tested) ----

## Bundled, playable entries whose audio lives under res:// (T-02.2-12).
static func bundled_candidates(entries: Array) -> Array:
	var out: Array = []
	for item in entries:
		var e := item as SongEntry
		if e == null or e.source != "bundled" or e.status != "ok" or e.audio_files.is_empty():
			continue
		var ok := true
		for f in e.audio_files:
			if not String(f).begins_with("res://"):
				ok = false
		if ok:
			out.append(e)
	return out


static func pulse_for(bpm_min: float, bpm_max: float) -> float:
	if bpm_min > 0.0 and is_equal_approx(bpm_min, bpm_max):
		return bpm_min / 60.0
	return DEFAULT_PULSE_HZ


## Loop window (start, end) in seconds: 30 s from the preview start, inside the stream.
static func loop_window(preview_s: float, length: float) -> Vector2:
	var s := maxf(preview_s, 0.0)
	if length <= 0.0:
		return Vector2(s, s + LOOP_SEC)
	var e := minf(s + LOOP_SEC, length)
	if e - s < LOOP_SEC:
		# A late preview start: slide the window back so it still spans 30 s (or the whole song).
		s = maxf(0.0, e - LOOP_SEC)
	return Vector2(s, e)


# ---- internals ----

func _enabled() -> bool:
	var s := _settings()
	return s == null or not ("menu_music" in s) or bool(s.menu_music)


func _settings() -> Node:
	if settings_ref != null:
		return settings_ref
	return get_node_or_null("/root/Settings") if is_inside_tree() else null


func _library() -> Node:
	if library_ref != null:
		return library_ref
	return get_node_or_null("/root/SongLibrary") if is_inside_tree() else null


func _pick(lib: Node) -> SongEntry:
	if lib == null or not ("entries" in lib):
		return null
	var c := bundled_candidates(lib.entries)
	if c.is_empty():
		return null
	return c[_rng.randi_range(0, c.size() - 1)]


func _load(lib: Node, e: SongEntry) -> void:
	_state = "loading"
	_request += 1
	var req := _request
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var s: AudioStream = lib.load_audio(e)
		_on_loaded.call_deferred(req, s, e)))


func _on_loaded(req: int, stream: AudioStream, e: SongEntry) -> void:
	if req != _request or _state != "loading":
		return
	_state = "idle"
	if stream == null:
		return
	var length := stream.get_length()
	var start_s := SongListModel.preview_start_sec(e.preview_start_ms, length if length > 0.0 else e.length_sec)
	start_with_stream(stream, start_s, 0.0)
	_bpm_hz = pulse_for(e.bpm_min, e.bpm_max)


func _on_entries_added(_batch: Array) -> void:
	if _state != "waiting":
		return
	var lib := _library()
	var pick := _pick(lib)
	if pick == null:
		return
	_disconnect_library()
	_load(lib, pick)


func _disconnect_library() -> void:
	var lib := _library()
	if lib != null and lib.has_signal("entries_added") and lib.entries_added.is_connected(_on_entries_added):
		lib.entries_added.disconnect(_on_entries_added)


func _on_settings_changed() -> void:
	if not _enabled() and _state != "idle":
		stop(0.4)


func _fade_to(target: float, sec: float) -> void:
	_gain_target = target
	_gain_rate = (absf(target - _gain) / sec) if sec > 0.0 else 0.0
	if _gain_rate <= 0.0:
		_gain = target


func _stop_now() -> void:
	for p in _players:
		p.stop()
		p.volume_db = MIN_DB
	_state = "idle"
	_gain = 0.0
	_gain_target = 0.0
	_xfade = -1.0


func _apply_volumes() -> void:
	if _players.is_empty():
		return
	var x := _xfade if _xfade >= 0.0 else 0.0
	_players[_active].volume_db = _db(_gain * (1.0 - x))
	if _xfade >= 0.0:
		_players[1 - _active].volume_db = _db(_gain * x)


static func _db(g: float) -> float:
	if g <= 0.0001:
		return MIN_DB
	return maxf(MIN_DB, VOLUME_DB + linear_to_db(g))


func _reap(all: bool) -> void:
	var keep: Array[int] = []
	for id in _tasks:
		if all or WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			keep.append(id)
	_tasks = keep
