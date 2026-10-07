class_name DeviceHeuristics
extends RefCounted
## Name-based output-device heuristics (D-17). Heuristic only: Windows does not reliably
## report the transport, so a Bluetooth warning is advisory, never authoritative.
## D-17 refined in gap closure 01-09: bare "headset" matches wired/dongle endpoints such as
## "Headset Earphone (Razer BlackShark V2 Pro 2.4)", so "headset" counts only together with
## "hands-free" or "bluetooth" (both of which are already markers on their own).

const BLUETOOTH_MARKERS: Array[String] = [
	"bluetooth", "airpods", "buds", "hands-free", "wireless stereo",
]


static func is_bluetooth_name(device_name: String) -> bool:
	var lowered := device_name.to_lower()
	if lowered.is_empty():
		return false
	for marker in BLUETOOTH_MARKERS:
		if lowered.contains(marker):
			return true
	return false
