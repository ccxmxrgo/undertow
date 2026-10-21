class_name HullAudioCurve
extends RefCounted
## Pure hull -> sound curves (05-02, D-03 muffle, D-04 creaks). Hull is 0..100.

const MUFFLE_START := 75.0
const OPEN_HZ := 20000.0
const FLOOR_HZ := 1500.0
const SMOOTH_TAU := 0.25
const SLAM_SEC := 0.3  # wreck/implosion: ramp to FLOOR_HZ over this long, then hold

const _CREAK_START := 60.0
const _CREAK_FULL := 10.0
const _CREAK_SLOW_SEC := 12.0
const _CREAK_FAST_SEC := 3.0
const _CREAK_QUIET_DB := -24.0
const _CREAK_LOUD_DB := -12.0
const _DAMAGE_START := 70.0
const _DAMAGE_ALWAYS := 30.0


## Music-bus low-pass cutoff. OPEN_HZ at hull >= MUFFLE_START, then log-interpolated down to
## FLOOR_HZ at hull 0. Non-finite hull -> OPEN_HZ.
static func cutoff_for_hull(hull: float) -> float:
	if not is_finite(hull):
		return OPEN_HZ
	var h := clampf(hull, 0.0, 100.0)
	if h >= MUFFLE_START:
		return OPEN_HZ
	var k := clampf(h / MUFFLE_START, 0.0, 1.0)
	return exp(lerpf(log(FLOOR_HZ), log(OPEN_HZ), k))


## True when the low-pass effect should be enabled.
static func muffle_active(hull: float) -> bool:
	return is_finite(hull) and hull < MUFFLE_START


## One-pole smoothing in log-frequency space; never overshoots the target.
static func smooth_cutoff(current_hz: float, target_hz: float, dt: float, tau: float = SMOOTH_TAU) -> float:
	var tgt := clampf(target_hz, 1.0, OPEN_HZ) if is_finite(target_hz) else OPEN_HZ
	if not is_finite(current_hz) or current_hz <= 0.0:
		return tgt
	if not is_finite(dt) or dt <= 0.0:
		return current_hz
	if not is_finite(tau) or tau <= 0.0:
		return tgt
	var a := 1.0 - exp(-dt / tau)
	return exp(lerpf(log(current_hz), log(tgt), clampf(a, 0.0, 1.0)))


## Mean ambient creak interval in seconds. INF at hull >= 60, 12 s just below, 3 s at hull <= 10.
static func creak_interval_for_hull(hull: float) -> float:
	if not is_finite(hull) or hull >= _CREAK_START:
		return INF
	return lerpf(_CREAK_SLOW_SEC, _CREAK_FAST_SEC, _creak_k(hull))


## Creak loudness in dB: -24 at hull 60 (and above), -12 at hull <= 10.
static func creak_db_for_hull(hull: float) -> float:
	if not is_finite(hull):
		return _CREAK_QUIET_DB
	return lerpf(_CREAK_QUIET_DB, _CREAK_LOUD_DB, _creak_k(hull))


## Chance that a damage event creaks: 0 at hull >= 70, 1.0 at hull <= 30.
static func damage_creak_chance(hull: float) -> float:
	if not is_finite(hull):
		return 0.0
	return clampf((_DAMAGE_START - hull) / (_DAMAGE_START - _DAMAGE_ALWAYS), 0.0, 1.0)


static func _creak_k(hull: float) -> float:
	return clampf((_CREAK_START - hull) / (_CREAK_START - _CREAK_FULL), 0.0, 1.0)
