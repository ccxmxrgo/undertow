class_name HitBurst
extends RefCounted
## Per-judgment hit-burst configuration (UI-SPEC 7.5, 11). Configures one pooled
## CPUParticles2D for PERFECT / GOOD / MISS in the current mode, and holds the shockwave
## ring, flash and crack timelines that FxLayer draws. Colours come from Palette only.
## Sparks, rings and water-like fizzles only (D-02: no flame effects).

## Ring / flash / crack pool kinds (drawn by FxLayer.BurstRings).
const RING_PERFECT := 0
const RING_GOOD := 1
const FLASH := 2
const CRACK := 3
const BLOOM := 4

## Indexed by InputJudge.Judgment (PERFECT, GOOD, MISS).
const AMOUNT_FULL: Array[int] = [24, 10, 6]
const AMOUNT_LOW: Array[int] = [8, 4, 0]
const LIFETIME: Array[float] = [0.35, 0.25, 0.30]
const VEL_MIN: Array[float] = [220.0, 160.0, 30.0]
const VEL_MAX: Array[float] = [380.0, 300.0, 80.0]
const GRAVITY: Array[float] = [1400.0, 1400.0, 200.0]
## Half-angle of the emission cone in degrees (160 degrees upward for hits).
const SPREAD: Array[float] = [80.0, 80.0, 70.0]
const REDUCE_SPEED := 0.5
## Visible dot size 3..6 px; the soft glow texture is drawn at twice that size.
const DOT_MIN_PX := 3.0
const DOT_MAX_PX := 6.0
const GOOD_DOT_SCALE := 0.85
const DOT_TEX_FACTOR := 2.4
const PERFECT_WHITE_MIX := 0.25
const MISS_ALPHA := 0.70
const EXPLOSIVENESS := 0.92
const LIFETIME_RANDOMNESS := 0.35

## Ring timelines (UI-SPEC 7.5): PERFECT r 41 -> 120 over 260 ms, width 6 -> 1, alpha 0.9 -> 0;
## GOOD r 41 -> 80 over 200 ms, alpha 0.5 -> 0.
const RING_R0 := 41.0
const PERFECT_R1 := 120.0
const GOOD_R1 := 80.0
const PERFECT_W0 := 6.0
const GOOD_W0 := 4.0
const RING_W1 := 1.0
const PERFECT_A0 := 0.9
const GOOD_A0 := 0.5
const FLASH_R := 30.0
const LIFE_SEC := {RING_PERFECT: 0.26, RING_GOOD: 0.20, FLASH: 0.12, CRACK: 0.30, BLOOM: 0.24}

static var _ramps: Dictionary = {}
static var _scale_curve: Curve


static func amount(judgment: int, low: bool, reduce: bool) -> int:
	var j := clampi(judgment, 0, 2)
	if j == InputJudge.Judgment.MISS and (low or reduce):
		return 0
	return AMOUNT_LOW[j] if low else AMOUNT_FULL[j]


static func base_color(judgment: int, lane: int) -> Color:
	var lane_col := Palette.lane_color(lane)
	match judgment:
		InputJudge.Judgment.PERFECT:
			return Palette.mix(lane_col, Palette.WHITE, PERFECT_WHITE_MIX)
		InputJudge.Judgment.GOOD:
			return lane_col
		_:
			return Palette.alpha(Palette.WARNING_RED, MISS_ALPHA)


## Configure `p` for one judgment in the current mode. Amount 0 (Low/Reduce Miss) keeps the
## node at 1 particle; FxLayer never restarts it then.
static func configure(p: CPUParticles2D, judgment: int, lane: int, low: bool, reduce: bool) -> void:
	var j := clampi(judgment, 0, 2)
	var amt := maxi(amount(j, low, reduce), 1)
	if p.amount != amt:
		p.amount = amt
	p.one_shot = true
	p.emitting = false
	p.explosiveness = EXPLOSIVENESS
	p.lifetime = LIFETIME[j]
	p.lifetime_randomness = LIFETIME_RANDOMNESS
	p.local_coords = true
	p.use_fixed_seed = true
	var hit := j != InputJudge.Judgment.MISS
	p.direction = Vector2.UP if hit else Vector2.DOWN
	p.spread = SPREAD[j]
	p.gravity = Vector2(0.0, GRAVITY[j])
	var k := REDUCE_SPEED if reduce else 1.0
	p.initial_velocity_min = VEL_MIN[j] * k
	p.initial_velocity_max = VEL_MAX[j] * k
	p.texture = UiKit.glow_texture()
	var tex_px := float(UiKit.GLOW_SIZE)
	var dot := GOOD_DOT_SCALE if j == InputJudge.Judgment.GOOD else 1.0
	p.scale_amount_min = DOT_MIN_PX * DOT_TEX_FACTOR * dot / tex_px
	p.scale_amount_max = DOT_MAX_PX * DOT_TEX_FACTOR * dot / tex_px
	p.scale_amount_curve = _shrink_curve()
	p.color = Palette.WHITE
	p.color_ramp = _ramp(j, lane)
	p.material = UiKit.additive_material() if hit else null


## Fade-out colour ramp per (judgment, lane), built once.
static func _ramp(judgment: int, lane: int) -> Gradient:
	var key := judgment * 8 + lane
	if _ramps.has(key):
		return _ramps[key]
	var c := base_color(judgment, lane)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([c, c, Palette.alpha(c, 0.0)])
	_ramps[key] = g
	return g


static func _shrink_curve() -> Curve:
	if _scale_curve == null:
		_scale_curve = Curve.new()
		_scale_curve.add_point(Vector2(0.0, 1.0))
		_scale_curve.add_point(Vector2(1.0, 0.35))
	return _scale_curve


static func life(kind: int) -> float:
	return float(LIFE_SEC.get(kind, 0.0))


static func flash_radius() -> float:
	return FLASH_R


## Ring state at `age` seconds: {r, w, a}. Radius eases out; width and alpha are linear.
static func ring_state(kind: int, age: float) -> Dictionary:
	var perfect := kind == RING_PERFECT
	var t := clampf(age / life(kind), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, 3.0)
	var r1 := PERFECT_R1 if perfect else GOOD_R1
	var w0 := PERFECT_W0 if perfect else GOOD_W0
	var a0 := PERFECT_A0 if perfect else GOOD_A0
	return {"r": lerpf(RING_R0, r1, e), "w": lerpf(w0, RING_W1, t), "a": a0 * (1.0 - t)}
