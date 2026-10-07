class_name AudioDeviceInfo
extends RefCounted
## Honest, Godot-only view of the audio output (CAL-01, gap closure 01-09). No OS calls, no threads.
##
## LIMITATION: Godot 4.7.2 cannot resolve which endpoint the "Default" alias points to, so a plain
## Windows default-output switch is NOT detectable. Plug/unplug (device list), mix-rate and
## output-latency changes are, via the signature. The wizard says "System default" under the alias.
## T-09-03: saved signatures are plain data, only compared to live snapshot values.

const ALIAS := "Default"
const LATENCY_BUCKET_MS := 5

## Callable returning {configured: String, devices: PackedStringArray, mix_rate: int, latency_s: float}.
var _provider: Callable


func _init(provider: Callable = Callable()) -> void:
	_provider = provider if provider.is_valid() else Callable(AudioDeviceInfo, "audio_server_provider")


static func audio_server_provider() -> Dictionary:
	return {
		"configured": AudioServer.output_device,
		"devices": AudioServer.get_output_device_list(),
		"mix_rate": int(AudioServer.get_mix_rate()),
		"latency_s": AudioServer.get_output_latency(),
	}


func snapshot() -> Dictionary:
	var raw: Variant = _provider.call()
	var d: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var configured := _str(d.get("configured", ""))
	var devices: Array = []
	var dv: Variant = d.get("devices", PackedStringArray())
	if typeof(dv) == TYPE_PACKED_STRING_ARRAY or typeof(dv) == TYPE_ARRAY:
		for x in dv:
			devices.append(_str(x))
	devices.sort()
	var mix := _int(d.get("mix_rate", 0))
	var lat := _float(d.get("latency_s", 0.0))
	var is_alias := configured.is_empty() or configured == ALIAS
	var endpoints := 0
	for x in devices:
		if x != ALIAS:
			endpoints += 1
	var bucket := roundi(lat * 1000.0 / LATENCY_BUCKET_MS) * LATENCY_BUCKET_MS
	var sig := "%s|%d|%d|%d" % [";".join(PackedStringArray(devices)), mix, bucket, endpoints]
	return {
		"configured": configured,
		"is_alias": is_alias,
		"display": "System default" if is_alias else configured,
		"signature": sig,
		"is_bluetooth": (not is_alias) and DeviceHeuristics.is_bluetooth_name(configured),
	}


func changed_since(saved_signature: String) -> bool:
	if saved_signature.is_empty():
		return false
	return saved_signature != snapshot().signature


static func _str(v: Variant) -> String:
	return v if typeof(v) == TYPE_STRING else ""


static func _int(v: Variant) -> int:
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0


static func _float(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0.0
	var f := float(v)
	return f if is_finite(f) else 0.0
