extends Node
## Autoload "Settings": user-editable ConfigFile at user://settings.cfg.
## Every value is untrusted: type-checked, clamped, defaults on failure (V5).
## Never use the resource loader on user files (T-02-02). Plan 04 adds bindings/volumes.

const DEFAULT_PATH := "user://settings.cfg"
const OFFSET_LIMIT := 0.5
const SCROLL_MIN := 0.5
const SCROLL_MAX := 3.0

## Seconds. Positive audio_offset = player taps late, song_time is reduced by it.
var audio_offset: float = 0.0
var visual_offset: float = 0.0
var scroll_speed: float = 1.0
var output_device_name: String = ""


func _ready() -> void:
	load_from(DEFAULT_PATH)


func reset_defaults() -> void:
	audio_offset = 0.0
	visual_offset = 0.0
	scroll_speed = 1.0
	output_device_name = ""


func save_to(path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("calibration", "audio_offset", audio_offset)
	cfg.set_value("calibration", "visual_offset", visual_offset)
	cfg.set_value("calibration", "output_device", output_device_name)
	cfg.set_value("gameplay", "scroll_speed", scroll_speed)
	return cfg.save(path)


func load_from(path: String = DEFAULT_PATH) -> void:
	reset_defaults()
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var cfg := ConfigFile.new()
	var err := cfg.parse(text)
	if err != OK:
		_back_up_bad_file(path)
		reset_defaults()
		return
	audio_offset = _num(cfg, "calibration", "audio_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	visual_offset = _num(cfg, "calibration", "visual_offset", 0.0, -OFFSET_LIMIT, OFFSET_LIMIT)
	scroll_speed = _num(cfg, "gameplay", "scroll_speed", 1.0, SCROLL_MIN, SCROLL_MAX)
	var dev: Variant = cfg.get_value("calibration", "output_device", "")
	output_device_name = dev if typeof(dev) == TYPE_STRING else ""


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
