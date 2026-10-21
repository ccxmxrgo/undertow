class_name CreakDirector
extends RefCounted
## Seeded hull-creak director (05-02, D-04). Pure and deterministic: given the same seed and the
## same call sequence (hull, delta, song time) it returns the same creaks. No nodes, no audio.
##
## Damage creaks: on a hull drop below 70, with chance HullAudioCurve.damage_creak_chance
## (1.0 at hull <= 30), 3 dB louder than ambient. Ambient creaks: below 60 hull, at a mean
## interval from HullAudioCurve.creak_interval_for_hull, jittered x0.6..x1.4. Both share one
## COOLDOWN_SEC on song time. Results: {} or {variant: int, db: float, pitch: float}.

const COOLDOWN_SEC := 0.8
const DAMAGE_DB_BOOST := 3.0
const PITCH_MIN := 0.85
const PITCH_MAX := 1.15
const JITTER_MIN := 0.6
const JITTER_MAX := 1.4
const RESCHEDULE_FRACTION := 0.2

var _seed: int
var _variants: int
var _rng := RandomNumberGenerator.new()
var _last_variant := -1
var _last_creak_t := -INF
var _next_ambient_t := INF
var _sched_interval := INF


func _init(rng_seed: int, variants: int = 4) -> void:
	_seed = rng_seed
	_variants = maxi(variants, 1)
	reset()


## Call from HullScore.hull_changed(value, delta). Returns a damage creak or {}.
func on_hull_changed(hull: float, delta: float, song_t: float) -> Dictionary:
	if not is_finite(hull) or not is_finite(delta) or not is_finite(song_t):
		return {}
	if delta >= 0.0 or hull >= 70.0:
		return {}
	if song_t - _last_creak_t < COOLDOWN_SEC:
		return {}
	if _rng.randf() >= HullAudioCurve.damage_creak_chance(hull):
		return {}
	return _emit(HullAudioCurve.creak_db_for_hull(hull) + DAMAGE_DB_BOOST, song_t)


## Call every frame while playing. Returns an ambient creak or {}.
func tick(hull: float, song_t: float) -> Dictionary:
	if not is_finite(hull) or not is_finite(song_t):
		return {}
	var interval := HullAudioCurve.creak_interval_for_hull(hull)
	if is_inf(interval):
		_sched_interval = INF
		_next_ambient_t = INF
		return {}
	if is_inf(_sched_interval) or absf(interval - _sched_interval) > RESCHEDULE_FRACTION * _sched_interval:
		_sched_interval = interval
		var base := _last_creak_t if is_finite(_last_creak_t) else song_t
		_next_ambient_t = base + interval * _rng.randf_range(JITTER_MIN, JITTER_MAX)
	if song_t < _next_ambient_t or song_t - _last_creak_t < COOLDOWN_SEC:
		return {}
	var out := _emit(HullAudioCurve.creak_db_for_hull(hull), song_t)
	_next_ambient_t = song_t + _sched_interval * _rng.randf_range(JITTER_MIN, JITTER_MAX)
	return out


## Back to the freshly constructed state (same seed): use on retry / new dive.
func reset() -> void:
	_rng.seed = _seed
	_last_variant = -1
	_last_creak_t = -INF
	_next_ambient_t = INF
	_sched_interval = INF


func _emit(db: float, song_t: float) -> Dictionary:
	var v := 0
	if _variants > 1:
		if _last_variant < 0:
			v = _rng.randi_range(0, _variants - 1)
		else:
			v = _rng.randi_range(0, _variants - 2)
			if v >= _last_variant:
				v += 1
	var pitch := _rng.randf_range(PITCH_MIN, PITCH_MAX)
	_last_variant = v
	_last_creak_t = song_t
	return {"variant": v, "db": db, "pitch": pitch}
