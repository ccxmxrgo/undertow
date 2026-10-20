extends Node
## Autoload "Settings": user-editable ConfigFile at user://settings.cfg.
## Every value is untrusted: type-checked, clamped, defaults on failure (V5).
## Never use the resource loader on user files (T-02-02).
## Plan 04 adds [bindings] (BindingStore), [gameplay] toggles, [audio] bus volumes.

signal settings_changed

const DEFAULT_PATH := "user://settings.cfg"
const OFFSET_LIMIT := 0.5
const SCROLL_MIN := 0.5
const SCROLL_MAX := 3.0
const WINDOWED_SIZE := Vector2i(1600, 900)
const MAX_LIBRARY_FOLDERS := 8
const MAX_PATH_LEN := 1024
const DIFFICULTIES: Array[String] = ["easy", "medium", "hard", "expert"]
## 02.2-27 (gap G2): gameplay background style. Living = moving, beat-pulsing trench (02.2-11);
## Calm = still trench with a soft brightness breathe on the beat.
const BACKGROUND_LIVING := "living"
const BACKGROUND_CALM := "calm"
const BACKGROUND_STYLES: Array[String] = [BACKGROUND_LIVING, BACKGROUND_CALM]
## Phase 4 [net] keys (D-15, D-20, UI-SPEC section 13).
const DEFAULT_PLAYER_NAME := "DIVER"
const PLAYER_NAME_MAX := 12
const PLAYER_NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"
const DEFAULT_NET_PORT := 47474
const NET_PORT_MIN := 1024
const NET_PORT_MAX := 65535
const ADDRESS_MAX := 64
const ADDRESS_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]"
const FLIGHT_BEATS: Array[int] = [2, 1]
## Pitfall 10: `-- --net-profile=<n>` (1-2 digits) gives each local process its own settings file.
const NET_PROFILE_ARG := "--net-profile="

## Seconds. Positive audio_offset = player taps late, song_time is reduced by it.
var audio_offset: float = 0.0
var visual_offset: float = 0.0
var scroll_speed: float = 1.0
var output_device_name: String = ""
## Device-list/mix-rate/latency signature saved with the calibration (see AudioDeviceInfo).
var output_device_signature: String = ""
## Godot-only device snapshot; tests inject a fake provider.
var device_info := AudioDeviceInfo.new()
## True once the player has completed (saved) the calibration wizard.
var calibration_done: bool = false
var early_late_indicator: bool = true
var no_fail: bool = false
var reduce_motion: bool = false
## D-06: borderless fullscreen by default; F11 toggles. Persisted in [display].
var fullscreen: bool = true
## Plan 03 consumes this: turns off vignette, scanlines and edge readouts.
var low_effects: bool = false
## Gameplay background (Settings > Display > Background). Persisted in [display] background.
## Calm is the default in this build so testers see it first (G2).
var background_style: String = BACKGROUND_CALM
## Linear 0-1 volumes for the Master/Music/SFX buses.
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 0.8
## 02.2 D-07: a quiet bundled song preview loops on the main menu (MenuMusic). Persisted in [audio].
var menu_music: bool = true
## D-06: extra library folders (absolute paths, scanned read-only). Persisted in [library].
var library_folders: Array[String] = []
## Last played song id / difficulty (easy|medium|hard|expert|""). Song Select reopens on them.
var last_song_id: String = ""
var last_difficulty: String = ""
## Phase 3 (D-18, D-27): last versus match setup and Solo Dive training choice. Persisted in [versus].
var versus_rivals: int = 3
var versus_skill: String = "regular"
var versus_song_id: String = ""
var versus_difficulty: String = ""
var training_payload: String = "off"
## D-20: name shown to friends online. 1-12 chars of [A-Z0-9 _-], upper-cased. Persisted in [net].
var player_name: String = DEFAULT_PLAYER_NAME
## D-20: true once the player has confirmed a name (the Play Online screen asks once).
var player_name_set: bool = false
## D-15: last address typed into Join (host name, IPv4 or bracketed IPv6; max 64 chars).
var net_last_address: String = ""
## D-15: UDP port used to host and join (1024..65535, default 47474).
var net_last_port: int = DEFAULT_NET_PORT
## Last torpedo flight chosen by the host: 2 beats (internet) or 1 beat (same-room LAN).
var net_flight_beats: int = 2
var bindings := BindingStore.new()
## Where set_* mutators persist to (tests override this).
var save_path: String = DEFAULT_PATH

const BUS_KEYS := {"Master": "master", "Music": "music", "SFX": "sfx"}


func _ready() -> void:
	var profile := profile_path_from_args(OS.get_cmdline_user_args())
	if profile != "":
		save_path = profile
	load_from(save_path)


func reset_defaults() -> void:
	audio_offset = 0.0
	visual_offset = 0.0
	scroll_speed = 1.0
	output_device_name = ""
	output_device_signature = ""
	calibration_done = false
	early_late_indicator = true
	no_fail = false
	reduce_motion = false
	fullscreen = true
	low_effects = false
	background_style = BACKGROUND_CALM
	volume_master = 1.0
	volume_music = 0.8
	volume_sfx = 0.8
	menu_music = true
	library_folders = []
	last_song_id = ""
	last_difficulty = ""
	versus_rivals = 3
	versus_skill = "regular"
	versus_song_id = ""
	versus_difficulty = ""
	training_payload = "off"
	player_name = DEFAULT_PLAYER_NAME
	player_name_set = false
	net_last_address = ""
	net_last_port = DEFAULT_NET_PORT
	net_flight_beats = 2
	bindings.reset_defaults()


## True when the audio setup differs from the one calibrated on (plug/unplug, mix rate, latency).
## A plain Windows default-output switch is NOT detectable (Godot limitation, see AudioDeviceInfo).
## T-06-01 / T-09-03: stored values are plain data compared only to live snapshot values.
## Legacy files without a signature never prompt.
func device_changed() -> bool:
	return calibration_done and device_info.changed_since(output_device_signature)


## Persists the wizard result. Offsets are clamped to +-0.5 s (T-06-03).
func save_calibration(p_audio: float, p_visual: float) -> void:
	audio_offset = CalibrationMath.clamp_offset(p_audio if is_finite(p_audio) else 0.0)
	visual_offset = CalibrationMath.visual_offset_clamp(p_visual if is_finite(p_visual) else 0.0)
	var snap := device_info.snapshot()
	output_device_name = snap.configured
	output_device_signature = snap.signature
	calibration_done = true
	save_to(save_path)
	settings_changed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_F11:
			set_fullscreen(not fullscreen)
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()


func set_fullscreen(v: bool) -> void:
	fullscreen = v
	apply_window()
	save_to(save_path)
	settings_changed.emit()


## Borderless fullscreen or a centered 1600x900 window. No-op headless (tests).
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	# Pitfall 4: set the mode first; a size set while fullscreen is discarded.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOWED_SIZE)
	var scr := DisplayServer.window_get_current_screen()
	var pos := DisplayServer.screen_get_position(scr)
	var sz := DisplayServer.screen_get_size(scr)
	DisplayServer.window_set_position(pos + (sz - WINDOWED_SIZE) / 2)


## Validates (unknown -> Calm), persists to save_path and notifies (effect contract re-reads it).
func set_background_style(v: Variant) -> void:
	background_style = _background(v)
	save_to(save_path)
	settings_changed.emit()


## T-02.2-51: the stored value is untrusted; only the exact strings "living" / "calm" are accepted.
static func _background(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and BACKGROUND_STYLES.has(v):
		return v
	return BACKGROUND_CALM


func set_scroll_speed(v: float) -> void:
	scroll_speed = _snap_scroll(v)
	save_to(save_path)
	settings_changed.emit()


## bus_name is one of Master, Music, SFX. Unknown buses are ignored.
func set_volume(bus_name: String, linear: float) -> void:
	if not BUS_KEYS.has(bus_name) or not is_finite(linear):
		return
	linear = clampf(linear, 0.0, 1.0)
	match bus_name:
		"Master":
			volume_master = linear
		"Music":
			volume_music = linear
		"SFX":
			volume_sfx = linear
	_apply_bus(bus_name, linear)
	save_to(save_path)
	settings_changed.emit()


func apply_audio() -> void:
	_apply_bus("Master", volume_master)
	_apply_bus("Music", volume_music)
	_apply_bus("SFX", volume_sfx)


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear) if linear > 0.0001 else -80.0)


func _snap_scroll(v: float) -> float:
	if not is_finite(v):
		return 1.0
	return snappedf(clampf(v, SCROLL_MIN, SCROLL_MAX), 0.1)


func save_to(path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("calibration", "audio_offset", audio_offset)
	cfg.set_value("calibration", "visual_offset", visual_offset)
	cfg.set_value("calibration", "output_device", output_device_name)
	cfg.set_value("calibration", "output_signature", output_device_signature)
	cfg.set_value("calibration", "done", calibration_done)
	cfg.set_value("gameplay", "scroll_speed", scroll_speed)
	cfg.set_value("gameplay", "early_late_indicator", early_late_indicator)
	cfg.set_value("gameplay", "no_fail", no_fail)
	cfg.set_value("gameplay", "reduce_motion", reduce_motion)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "low_effects", low_effects)
	cfg.set_value("display", "background", background_style)
	cfg.set_value("audio", "master", volume_master)
	cfg.set_value("audio", "music", volume_music)
	cfg.set_value("audio", "sfx", volume_sfx)
	cfg.set_value("audio", "menu_music", menu_music)
	cfg.set_value("library", "folders", PackedStringArray(library_folders))
	cfg.set_value("library", "last_song_id", last_song_id)
	cfg.set_value("library", "last_difficulty", last_difficulty)
	cfg.set_value("versus", "rivals", versus_rivals)
	cfg.set_value("versus", "skill", versus_skill)
	cfg.set_value("versus", "song_id", versus_song_id)
	cfg.set_value("versus", "difficulty", versus_difficulty)
	cfg.set_value("versus", "training", training_payload)
	cfg.set_value("net", "player_name", player_name)
	cfg.set_value("net", "player_name_set", player_name_set)
	cfg.set_value("net", "net_last_address", net_last_address)
	cfg.set_value("net", "net_last_port", net_last_port)
	cfg.set_value("net", "net_flight_beats", net_flight_beats)
	bindings.to_config(cfg)
	# Atomic save (WR-08): write a temp file, then rename over the target, so a crash mid-write
	# cannot leave a truncated settings file.
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [path, err])
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
	return err


func load_from(path: String = DEFAULT_PATH) -> void:
	reset_defaults()
	if not FileAccess.file_exists(path):
		apply_window()
		apply_audio()
		settings_changed.emit()
		return
	var text := FileAccess.get_file_as_string(path)
	var cfg := ConfigFile.new()
	var err := cfg.parse(text)
	if err != OK:
		_back_up_bad_file(path)
		reset_defaults()
		apply_window()
		apply_audio()
		settings_changed.emit()
		return
	audio_offset = _num(cfg, "calibration", "audio_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	visual_offset = _num(cfg, "calibration", "visual_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	scroll_speed = _snap_scroll(_num(cfg, "gameplay", "scroll_speed", 1.0, SCROLL_MIN, SCROLL_MAX))
	early_late_indicator = _bool(cfg, "gameplay", "early_late_indicator", true)
	no_fail = _bool(cfg, "gameplay", "no_fail", false)
	reduce_motion = _bool(cfg, "gameplay", "reduce_motion", false)
	fullscreen = _bool(cfg, "display", "fullscreen", true)
	low_effects = _bool(cfg, "display", "low_effects", false)
	background_style = _background(cfg.get_value("display", "background", BACKGROUND_CALM))
	volume_master = _num(cfg, "audio", "master", 1.0, 0.0, 1.0)
	volume_music = _num(cfg, "audio", "music", 0.8, 0.0, 1.0)
	volume_sfx = _num(cfg, "audio", "sfx", 0.8, 0.0, 1.0)
	menu_music = _bool(cfg, "audio", "menu_music", true)
	bindings.from_config(cfg)
	var dev: Variant = cfg.get_value("calibration", "output_device", "")
	output_device_name = dev.left(512) if typeof(dev) == TYPE_STRING else ""
	var sig: Variant = cfg.get_value("calibration", "output_signature", "")
	output_device_signature = sig.left(512) if typeof(sig) == TYPE_STRING else ""
	calibration_done = _bool(cfg, "calibration", "done", false)
	_load_library(cfg)
	_load_versus(cfg)
	_load_net(cfg)
	apply_window()
	apply_audio()
	settings_changed.emit()


## T-02-18: every [library] value is untrusted. Non-strings dropped, list capped, strings capped.
func _load_library(cfg: ConfigFile) -> void:
	var folders: Variant = cfg.get_value("library", "folders", [])
	var out: Array[String] = []
	if typeof(folders) == TYPE_ARRAY or typeof(folders) == TYPE_PACKED_STRING_ARRAY:
		for item in folders:
			if out.size() >= MAX_LIBRARY_FOLDERS:
				break
			if typeof(item) != TYPE_STRING:
				continue
			var p: String = item
			if p == "" or p.length() > MAX_PATH_LEN or out.has(p):
				continue
			out.append(p)
	library_folders = out
	var sid: Variant = cfg.get_value("library", "last_song_id", "")
	last_song_id = sid if typeof(sid) == TYPE_STRING and sid.length() <= MAX_PATH_LEN else ""
	var diff: Variant = cfg.get_value("library", "last_difficulty", "")
	last_difficulty = diff if typeof(diff) == TYPE_STRING and DIFFICULTIES.has(diff) else ""


## T-03-02: every [versus] value is untrusted. Rivals clamped 1..3, skill and training whitelisted
## (MatchSetup.SKILLS / TRAINING_VALUES), difficulty whitelisted, song id capped at MAX_PATH_LEN.
func _load_versus(cfg: ConfigFile) -> void:
	var r: Variant = cfg.get_value("versus", "rivals", 3)
	if (typeof(r) == TYPE_INT or typeof(r) == TYPE_FLOAT) and is_finite(float(r)):
		versus_rivals = clampi(int(r), MatchSetup.MIN_RIVALS, MatchSetup.MAX_RIVALS)
	else:
		versus_rivals = 3
	var sk: Variant = cfg.get_value("versus", "skill", "regular")
	versus_skill = sk if typeof(sk) == TYPE_STRING and MatchSetup.SKILLS.has(sk) else "regular"
	var sid: Variant = cfg.get_value("versus", "song_id", "")
	versus_song_id = sid if typeof(sid) == TYPE_STRING and sid.length() <= MAX_PATH_LEN else ""
	var diff: Variant = cfg.get_value("versus", "difficulty", "")
	versus_difficulty = diff if typeof(diff) == TYPE_STRING and DIFFICULTIES.has(diff) else ""
	var tr: Variant = cfg.get_value("versus", "training", "off")
	var tr_ok := typeof(tr) == TYPE_STRING and MatchSetup.TRAINING_VALUES.has(tr)
	training_payload = tr if tr_ok else "off"


## T-04-09: every [net] value is untrusted. Name filtered to the charset (else DIVER), port
## range-checked (else 47474), flight whitelisted (else 2), address charset/length-checked (else "").
func _load_net(cfg: ConfigFile) -> void:
	var n: Variant = cfg.get_value("net", "player_name", DEFAULT_PLAYER_NAME)
	var clean := clean_player_name(n) if typeof(n) == TYPE_STRING else ""
	player_name = clean if clean != "" else DEFAULT_PLAYER_NAME
	player_name_set = _bool(cfg, "net", "player_name_set", false)
	var a: Variant = cfg.get_value("net", "net_last_address", "")
	net_last_address = clean_address(a) if typeof(a) == TYPE_STRING else ""
	var p := _whole(cfg.get_value("net", "net_last_port", DEFAULT_NET_PORT))
	net_last_port = p if p >= NET_PORT_MIN and p <= NET_PORT_MAX else DEFAULT_NET_PORT
	var fb := _whole(cfg.get_value("net", "net_flight_beats", 2))
	net_flight_beats = fb if FLIGHT_BEATS.has(fb) else 2


## An int, or a finite float with no fraction, as int; anything else -> -1.
static func _whole(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 1e9:
			return int(f)
	return -1


## D-20: upper-case, keep [A-Z0-9 _-], collapse runs of spaces, trim, cap at 12 chars.
## Returns "" when nothing valid is left (callers fall back to DIVER or reject the edit).
static func clean_player_name(s: String) -> String:
	var up := s.to_upper()
	var out := ""
	for i in up.length():
		var c := up[i]
		if not PLAYER_NAME_CHARS.contains(c):
			continue
		if c == " " and (out == "" or out.ends_with(" ")):
			continue
		out += c
	return out.strip_edges().left(PLAYER_NAME_MAX).strip_edges()


## D-15: trimmed address of [a-zA-Z0-9 . - : [ ]] up to 64 chars; any other input returns "".
static func clean_address(s: String) -> String:
	var t := s.strip_edges()
	if t.length() > ADDRESS_MAX:
		return ""
	for i in t.length():
		if not ADDRESS_CHARS.contains(t[i]):
			return ""
	return t


## Pitfall 10 / T-04-08: "--net-profile=<1-2 digits>" -> "user://settings_net<n>.cfg", else "".
## The file name is built here from digits only, so no path traversal is possible.
static func profile_path_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if not arg.begins_with(NET_PROFILE_ARG):
			continue
		var v := arg.substr(NET_PROFILE_ARG.length())
		if v.length() < 1 or v.length() > 2:
			return ""
		for i in v.length():
			if not "0123456789".contains(v[i]):
				return ""
		return "user://settings_net%s.cfg" % v
	return ""


## Remembers the last played song/difficulty (called by SongLibrary); saves only on change.
func set_last_played(song_id: String, difficulty: String) -> void:
	var d := difficulty if DIFFICULTIES.has(difficulty) else ""
	var s := song_id.left(MAX_PATH_LEN)
	if s == last_song_id and d == last_difficulty:
		return
	last_song_id = s
	last_difficulty = d
	save_to(save_path)


func _bool(cfg: ConfigFile, section: String, key: String, def: bool) -> bool:
	var v: Variant = cfg.get_value(section, key, def)
	return v if typeof(v) == TYPE_BOOL else def


func _num(cfg: ConfigFile, section: String, key: String, def: float, lo: float, hi: float) -> float:
	var v: Variant = cfg.get_value(section, key, def)
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return def
	var f := float(v)
	if not is_finite(f):
		return def
	return clampf(f, lo, hi)


func _back_up_bad_file(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.rename_absolute(abs_path, abs_path + ".bak")
