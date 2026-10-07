class_name CalibrationMath
extends RefCounted
## Pure calibration math (CAL-01).
##
## SIGN CONVENTION (research Pitfall 1): offsets are seconds. A POSITIVE audio_offset means the
## player taps LATE relative to the audible click (output latency, slow Bluetooth), and the
## game compensates by reducing song_time by that amount. delta = tap_time - click_time.
##
## Domains: tap_times passed to audio_offset_from_taps must be in the same time domain as
## click_times. If taps were captured through Conductor.song_time_at while an offset was already
## applied, they have that offset subtracted; remove_applied_offset converts them back to raw
## (pre-offset) times so the measured value is the absolute offset, not a residual. Measured
## without removing, a re-measurement after applying the correct offset returns about 0.

const OFFSET_LIMIT := 0.5
const SUSPICIOUS_LIMIT := 0.3
const VISUAL_UI_RANGE := 0.2
const DEFAULT_DISCARD := 4
const DEFAULT_MIN_VALID := 8


## Median tap error against the nearest click, after discarding the first `discard` taps.
## Returns NAN when fewer than `min_valid` taps remain ("not enough taps").
static func audio_offset_from_taps(
		tap_times: Array, click_times: Array,
		discard: int = DEFAULT_DISCARD, min_valid: int = DEFAULT_MIN_VALID) -> float:
	if click_times.is_empty() or tap_times.size() <= discard:
		return NAN
	var deltas: Array[float] = []
	for i in range(discard, tap_times.size()):
		var t: float = tap_times[i]
		if not is_finite(t):
			continue
		var best := INF
		for c in click_times:
			var d: float = t - float(c)
			if absf(d) < absf(best):
				best = d
		if is_finite(best):
			deltas.append(best)
	if deltas.size() < min_valid:
		return NAN
	return _median(deltas)


## Converts taps recorded in offset-adjusted song time back to raw (pre-offset) times.
static func remove_applied_offset(tap_times: Array, applied_offset: float) -> Array[float]:
	var out: Array[float] = []
	for t in tap_times:
		out.append(float(t) + applied_offset)
	return out


static func is_suspicious(offset: float) -> bool:
	return absf(offset) > SUSPICIOUS_LIMIT


## Stored audio offset clamp (+-0.5 s).
static func clamp_offset(v: float) -> float:
	return clampf(v, -OFFSET_LIMIT, OFFSET_LIMIT)


## Visual offset: stored +-0.5 s, the settings UI exposes only +-0.2 s.
static func visual_offset_clamp(v: float, ui_range: bool = false) -> float:
	var lim := VISUAL_UI_RANGE if ui_range else OFFSET_LIMIT
	return clampf(v, -lim, lim)


static func _median(values: Array[float]) -> float:
	var s := values.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return s[n / 2]
	return (s[n / 2 - 1] + s[n / 2]) * 0.5
