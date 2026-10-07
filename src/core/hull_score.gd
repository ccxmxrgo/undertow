class_name HullScore
extends RefCounted
## Hull, combo, perfect streak, multiplier, score and depth (D-12..D-15). Pure logic; every
## number comes from JudgeConfig. Score for a hit uses the multiplier in effect BEFORE that
## hit raises the combo. Hull floors at zero; `failed` fires once unless no_fail is set.

signal hull_changed(value: float, delta: float)
signal combo_changed(value: int)
signal multiplier_changed(value: int)
signal streak_changed(value: int)
signal score_changed(value: int)
signal failed

var no_fail: bool = false
var no_fail_used: bool = false
var is_failed: bool = false

var hull: float
var combo: int = 0
var max_combo: int = 0
var perfect_streak: int = 0
var max_perfect_streak: int = 0
var score: int = 0
var perfect_count: int = 0
var good_count: int = 0
var miss_count: int = 0
var stray_count: int = 0
var sustain_ticks: int = 0

var _cfg: JudgeConfig


func _init(cfg: JudgeConfig) -> void:
	_cfg = cfg
	hull = cfg.hull_start


func connect_judge(judge: InputJudge) -> void:
	judge.judged.connect(on_judged)
	judge.stray.connect(on_stray)
	judge.sustain_tick.connect(on_sustain_tick)


func depth() -> float:
	return float(score) / _cfg.score_per_meter


func multiplier() -> int:
	return mini(1 + combo / _cfg.combo_per_multiplier_step, _cfg.max_multiplier)


func on_judged(_lane: int, _idx: int, judgment: int, _err: float) -> void:
	match judgment:
		InputJudge.Judgment.PERFECT:
			perfect_count += 1
			_add_score(_cfg.score_perfect)
			_set_hull(minf(hull + _cfg.perfect_regen, _cfg.hull_start))
			_set_combo(combo + 1)
			_set_streak(perfect_streak + 1)
		InputJudge.Judgment.GOOD:
			good_count += 1
			_add_score(_cfg.score_good)
			_set_combo(combo + 1)
			_set_streak(0)
		_:
			miss_count += 1
			_damage(_cfg.miss_damage)
			_set_combo(0)
			_set_streak(0)


func on_stray(_lane: int) -> void:
	stray_count += 1
	_set_combo(0)
	_set_streak(0)
	if _cfg.stray_hull_damage > 0.0:
		_damage(_cfg.stray_hull_damage)


func on_sustain_tick(_lane: int) -> void:
	sustain_ticks += 1
	_add_score(_cfg.score_sustain_tick)


func _add_score(base: int) -> void:
	score += base * multiplier()
	score_changed.emit(score)


func _damage(amount: float) -> void:
	var before := hull
	hull = maxf(hull - amount, 0.0)
	hull_changed.emit(hull, hull - before)
	if hull <= 0.0:
		if no_fail:
			no_fail_used = true
		elif not is_failed:
			is_failed = true
			failed.emit()


func _set_hull(v: float) -> void:
	var delta := v - hull
	hull = v
	if delta != 0.0:
		hull_changed.emit(hull, delta)


func _set_combo(v: int) -> void:
	var old_mult := multiplier()
	combo = v
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo)
	if multiplier() != old_mult:
		multiplier_changed.emit(multiplier())


func _set_streak(v: int) -> void:
	perfect_streak = v
	max_perfect_streak = maxi(max_perfect_streak, v)
	streak_changed.emit(v)
