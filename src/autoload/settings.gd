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
## Linear 0-1 volumes for the Master/Music/SFX buses.
var volume_master: float = 1.0
var volume_music: float = 0.8
var volume_sfx: float = 0.8
var bindings := BindingStore.new()
## Where set_* mutators persist to (tests override this).
var save_path: String = DEFAULT_PATH

const BUS_KEYS := {"Master": "master", "Music": "music", "SFX": "sfx"}


func _ready() -> void:
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
	volume_master = 1.0
	volume_music = 0.8
	volume_sfx = 0.8
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
	cfg.set_value("audio", "master", volume_master)
	cfg.set_value("audio", "music", volume_music)
	cfg.set_value("audio", "sfx", volume_sfx)
	bindings.to_config(cfg)
	return cfg.save(path)


func load_from(path: String = DEFAULT_PATH) -> void:
	reset_defaults()
	if not FileAccess.file_exists(path):
		apply_audio()
		settings_changed.emit()
		return
	var text := FileAccess.get_file_as_string(path)
	var cfg := ConfigFile.new()
	var err := cfg.parse(text)
	if err != OK:
		_back_up_bad_file(path)
		reset_defaults()
		apply_audio()
		settings_changed.emit()
		return
	audio_offset = _num(cfg, "calibration", "audio_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	visual_offset = _num(cfg, "calibration", "visual_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	scroll_speed = _snap_scroll(_num(cfg, "gameplay", "scroll_speed", 1.0, SCROLL_MIN, SCROLL_MAX))
	early_late_indicator = _bool(cfg, "gameplay", "early_late_indicator", true)
	no_fail = _bool(cfg, "gameplay", "no_fail", false)
	reduce_motion = _bool(cfg, "gameplay", "reduce_motion", false)
	volume_master = _num(cfg, "audio", "master", 1.0, 0.0, 1.0)
	volume_music = _num(cfg, "audio", "music", 0.8, 0.0, 1.0)
	volume_sfx = _num(cfg, "audio", "sfx", 0.8, 0.0, 1.0)
	bindings.from_config(cfg)
	var dev: Variant = cfg.get_value("calibration", "output_device", "")
	output_device_name = dev.left(512) if typeof(dev) == TYPE_STRING else ""
	var sig: Variant = cfg.get_value("calibration", "output_signature", "")
	output_device_signature = sig.left(512) if typeof(sig) == TYPE_STRING else ""
	calibration_done = _bool(cfg, "calibration", "done", false)
	apply_audio()
	settings_changed.emit()


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
