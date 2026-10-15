class_name VersusHull
extends HullScore
## Phase 3 hull/score extensions. Never edit hull_score.gd (pinned 72e21ce).
## Overrides are dispatched through the parent's connect_judge signal connections and the
## parent's _damage/_set_hull are called directly (RESEARCH Pattern 1, Pitfall 4).
## Rules (who heals, when Overclock runs) are decided elsewhere (MatchSim); this class only
## applies them to one player's hull and score.

## Song time until which Goods score as Perfect (Overclock, 03-SPEC req 6). Set by the owner.
var overclock_until: float = -INF
## Song time of the judgment being processed. The owner sets it before each press/tick.
var now: float = 0.0

var _ghost_spent: Dictionary = {}  # payload_id -> hull damage already taken from that payload


func _init(cfg: JudgeConfig) -> void:
	super(cfg)


func on_judged(lane: int, idx: int, judgment: int, err: float) -> void:
	# Score uses the multiplier BEFORE the hit raises the combo (HullScore contract).
	var m := multiplier()
	super.on_judged(lane, idx, judgment, err)
	if judgment == InputJudge.Judgment.GOOD and now < overclock_until:
		# Top up to the Perfect value at the pre-hit multiplier. Not _add_score: it would
		# multiply by the post-hit multiplier.
		score += (_cfg.score_perfect - _cfg.score_good) * m
		score_changed.emit(score)


## Ballast Patch. Never revives a failed hull (Pitfall 5).
func heal(amount: float) -> void:
	if is_failed or not is_finite(amount) or amount <= 0.0:
		return
	_set_hull(minf(hull + amount, _cfg.hull_start))


## A press on a Ghost Note (D-08, D-12): breaks combo and perfect streak like a stray, then costs
## `damage`, capped at `cap` in total per payload. Does not touch the reward meter.
func ghost_hit(payload_id: int, damage: float, cap: float) -> void:
	on_stray(-1)
	var spent: float = _ghost_spent.get(payload_id, 0.0)
	var dmg := minf(maxf(damage, 0.0), cap - spent)
	if dmg > 0.0:
		_ghost_spent[payload_id] = spent + dmg
		_damage(dmg)


## Ghost damage already taken from one payload.
func ghost_damage_spent(payload_id: int) -> float:
	return _ghost_spent.get(payload_id, 0.0)


## Depth Charge overlay judgment: scored, regenerated and damaged like a base note (D-14).
func on_extra_judged(_kind: int, lane: int, judgment: int, err: float) -> void:
	on_judged(lane, -1, judgment, err)


## connect_judge plus the overlay signals of a VersusJudge.
func connect_versus(judge: VersusJudge, cfg: VersusConfig) -> void:
	connect_judge(judge)
	judge.extra_judged.connect(on_extra_judged)
	judge.ghost_hit.connect(func(_lane: int, payload_id: int) -> void:
		ghost_hit(payload_id, cfg.ghost_hull_damage, cfg.ghost_damage_cap))
