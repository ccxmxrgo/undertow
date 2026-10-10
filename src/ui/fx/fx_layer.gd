class_name FxLayer
extends Node2D
## Juice on the board (UI-SPEC 7.5, 7.6 trail column, 11; VIS-03 e/f, VIS-09). Lives in
## BoardRoot between the Highway (surface, receptors) and Feedback; gems (HighwayNotes) are
## drawn above it, so an effect never hides the next note.
##
## FxLayer (Node2D, unclipped)
##   BurstClip (Control, rect (0, 840, 1920, 240), clip_contents): everything near the hit
##   line that could cross upcoming gems is clipped to y >= Trench.HIT_Y - 90.
##     BurstOrigin (Node2D at (0, -840): children use screen coordinates)
##       BurstRings (shockwave rings, Miss crack and X; normal blend)
##       16 pooled CPUParticles2D bursts (per lane 2 PERFECT round-robin, 1 GOOD, 1 MISS)
##       BurstFlashes (additive: the Perfect white core flash and the lane bloom)
##   RailSparks (2 emitters rising along the outer rails at x3 / x4; not clipped)
##   SustainSparks (4 emitters at the receptors while a sustain is held; not clipped)
## Miss shake moves only the board (request_shake -> board_root.position). Hit sounds stay in
## Feedback. Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const FX_RING_PERFECT := HitBurst.RING_PERFECT
const FX_RING_GOOD := HitBurst.RING_GOOD
const FX_FLASH := HitBurst.FLASH
const FX_CRACK := HitBurst.CRACK
const FX_BLOOM := HitBurst.BLOOM

const LANES := 4
const CLIP_TOP := Trench.HIT_Y - 90.0
const CLIP_RECT := Rect2(0.0, Trench.HIT_Y - 90.0, 1920.0, 240.0)
const RING_POOL := 32
const PREWARM_POS := Vector2(-4000.0, -4000.0)

const SHAKE_PX := 6.0
const SHAKE_USEC := 120000
const SHAKE_GAP_USEC := 150000
const SHAKE_TURNS := 2.5

## Rail sparks per rail per second, by tier (index = multiplier).
const RAIL_RATE: Array[float] = [0.0, 0.0, 0.0, 20.0, 40.0]
const RAIL_LIFE := 0.6
const RAIL_SAMPLES := 24
const RAIL_D0 := -0.03
const RAIL_D1 := 0.55
const RAIL_VEL_MIN := 150.0
const RAIL_VEL_MAX := 260.0
const SPARK_DOT_MIN := 3.0
const SPARK_DOT_MAX := 5.0

const SUSTAIN_RATE := 30.0
const SUSTAIN_LIFE := 0.3
const SUSTAIN_VEL_MIN := 110.0
const SUSTAIN_VEL_MAX := 230.0
const SUSTAIN_GRAVITY := 900.0
const SUSTAIN_SPREAD := 38.0
const SUSTAIN_WHITE_MIX := 0.35

## Drawing.
const RING_SEGMENTS := 64
const RING_GLOW_EXTRA_W := 8.0
const RING_GLOW_ALPHA := 0.30
const PERFECT_RING_WHITE_MIX := 0.35
const CRACK_W := 2.0
const CRACK_GLOW_W := 6.0
const CRACK_GLOW_ALPHA := 0.25
const X_HALF := 14.0
const X_W := 3.0
const BLOOM_PX := 210.0
const BLOOM_ALPHA := 0.55
const GOOD_BLOOM_ALPHA := 0.30
const FLASH_GLOW_PX := 150.0

var perfect_emitters: Array[CPUParticles2D] = []
var good_emitters: Array[CPUParticles2D] = []
var miss_emitters: Array[CPUParticles2D] = []
var rail_emitters: Array[CPUParticles2D] = []
var sustain_emitters: Array[CPUParticles2D] = []
var burst_clip: Control
var rings: BurstRings
var flashes: BurstFlashes
## Test clock override (microseconds); -1 = real time.
var clock_usec: int = -1
var tier: int = 1

var _origin: Node2D
var _rail_root: Node2D
var _sustain_root: Node2D
var _board: Control
var _highway: Highway
var _low: bool = false
var _reduce: bool = false
var _held: Array[bool] = [false, false, false, false]
var _rr: Array[int] = [0, 0, 0, 0]
var _rail_rate: float = 0.0
var _shake_active: bool = false
var _shake_start: int = 0
var _last_shake: int = -1000000000
var _shake_base: Vector2 = Vector2.ZERO
static var _cracks: Array = []


## Three jagged 4-point polylines radiating 30..60 px from the hit point (relative), fixed
## per lane (deterministic, so harness shots are stable).
static func crack_polylines(lane: int) -> Array:
	if _cracks.size() != LANES:
		_cracks.clear()
		for l in range(LANES):
			var rng := RandomNumberGenerator.new()
			rng.seed = 7919 * (l + 1) + 13
			var set: Array = []
			for k in range(3):
				var ang := deg_to_rad(-90.0 + 120.0 * k + rng.randf_range(-25.0, 25.0))
				var dir := Vector2(cos(ang), sin(ang))
				var nrm := Vector2(-dir.y, dir.x)
				var reach := rng.randf_range(36.0, 54.0)
				var pl := PackedVector2Array()
				pl.resize(4)
				for i in range(4):
					var f := (0.18 + 0.82 * float(i) / 3.0) * reach
					var j := 0.0 if i == 3 else rng.randf_range(-6.0, 6.0)
					pl[i] = dir * f + nrm * j
				set.append(pl)
			_cracks.append(set)
	return _cracks[clampi(lane, 0, LANES - 1)]


func _init() -> void:
	name = "FxLayer"
	burst_clip = Control.new()
	burst_clip.name = "BurstClip"
	burst_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst_clip.clip_contents = true
	burst_clip.position = CLIP_RECT.position
	burst_clip.size = CLIP_RECT.size
	add_child(burst_clip)
	_origin = Node2D.new()
	_origin.name = "BurstOrigin"
	_origin.position = -CLIP_RECT.position
	burst_clip.add_child(_origin)
	rings = BurstRings.new()
	rings.layer = self
	_origin.add_child(rings)
	for lane in range(LANES):
		for k in range(2):
			perfect_emitters.append(_burst("Perfect%d_%d" % [lane, k], 101 + lane * 10 + k))
	for lane in range(LANES):
		good_emitters.append(_burst("Good%d" % lane, 201 + lane))
	for lane in range(LANES):
		miss_emitters.append(_burst("Miss%d" % lane, 301 + lane))
	flashes = BurstFlashes.new()
	flashes.rings = rings
	flashes.material = UiKit.additive_material()
	_origin.add_child(flashes)
	_rail_root = Node2D.new()
	_rail_root.name = "RailSparks"
	add_child(_rail_root)
	for side in [-1, 1]:
		rail_emitters.append(_rail_emitter(side))
	_sustain_root = Node2D.new()
	_sustain_root.name = "SustainSparks"
	add_child(_sustain_root)
	for lane in range(LANES):
		sustain_emitters.append(_sustain_emitter(lane))


func _burst(n: String, seed_val: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = n
	p.emitting = false
	p.one_shot = true
	p.use_fixed_seed = true
	p.seed = seed_val
	_origin.add_child(p)
	return p


func _spark_common(p: CPUParticles2D, color: Color) -> void:
	p.emitting = false
	p.texture = UiKit.glow_texture()
	var tex_px := float(UiKit.GLOW_SIZE)
	p.scale_amount_min = SPARK_DOT_MIN * HitBurst.DOT_TEX_FACTOR / tex_px
	p.scale_amount_max = SPARK_DOT_MAX * HitBurst.DOT_TEX_FACTOR / tex_px
	p.scale_amount_curve = HitBurst._shrink_curve()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([color, color, Palette.alpha(color, 0.0)])
	p.color_ramp = g
	p.material = UiKit.additive_material()
	p.local_coords = false


func _rail_emitter(side: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Rail%s" % ("L" if side < 0 else "R")
	_spark_common(p, Palette.SONAR_PALE)
	var f := 2.0 * float(side)
	var pts := PackedVector2Array()
	for i in range(RAIL_SAMPLES):
		pts.append(Trench.point(f, lerpf(RAIL_D0, RAIL_D1, float(i) / float(RAIL_SAMPLES - 1))))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = pts
	p.direction = (Trench.VP - Trench.point(f, 0.0)).normalized()
	p.spread = 4.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = RAIL_VEL_MIN
	p.initial_velocity_max = RAIL_VEL_MAX
	p.lifetime = RAIL_LIFE
	p.amount = int(RAIL_RATE[4] * RAIL_LIFE)
	_rail_root.add_child(p)
	return p


func _sustain_emitter(lane: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Sustain%d" % lane
	_spark_common(p, Palette.mix(Palette.lane_color(lane), Palette.WHITE, SUSTAIN_WHITE_MIX))
	p.position = Trench.hit_point(lane)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 10.0
	p.direction = Vector2.UP
	p.spread = SUSTAIN_SPREAD
	p.gravity = Vector2(0.0, SUSTAIN_GRAVITY)
	p.initial_velocity_min = SUSTAIN_VEL_MIN
	p.initial_velocity_max = SUSTAIN_VEL_MAX
	p.lifetime = SUSTAIN_LIFE
	p.amount = int(round(SUSTAIN_RATE * SUSTAIN_LIFE))
	_sustain_root.add_child(p)
	return p


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(highway: Highway, board_root: Control) -> void:
	_highway = highway
	_board = board_root


func now() -> int:
	return clock_usec if clock_usec >= 0 else Time.get_ticks_usec()


func burst_emitters() -> Array[CPUParticles2D]:
	var out: Array[CPUParticles2D] = []
	out.append_array(perfect_emitters)
	out.append_array(good_emitters)
	out.append_array(miss_emitters)
	return out


# ---- Effect contract -------------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	for lane in range(LANES):
		for k in range(2):
			HitBurst.configure(perfect_emitters[lane * 2 + k], InputJudge.Judgment.PERFECT, lane, _low, _reduce)
		HitBurst.configure(good_emitters[lane], InputJudge.Judgment.GOOD, lane, _low, _reduce)
		HitBurst.configure(miss_emitters[lane], InputJudge.Judgment.MISS, lane, _low, _reduce)
	if _reduce:
		_end_shake()
	_update_rails()
	_update_sustains()


func _flash_on() -> bool:
	return not _low and not _reduce


func _sparks_on() -> bool:
	return not _low and not _reduce


func effect_counts() -> Dictionary:
	return {
		"perfect_amount": HitBurst.amount(InputJudge.Judgment.PERFECT, _low, _reduce),
		"good_amount": HitBurst.amount(InputJudge.Judgment.GOOD, _low, _reduce),
		"miss_amount": HitBurst.amount(InputJudge.Judgment.MISS, _low, _reduce),
		"flash": _flash_on(),
		"rail_rate": _rail_rate,
		"sustain_rate": SUSTAIN_RATE if _sparks_on() else 0.0,
		"shake": not _reduce,
	}


## Worst case live particles in Full (UI-SPEC 12 budget: <= 450).
func max_live_particles() -> int:
	var n := 0
	for j in range(3):
		n += HitBurst.AMOUNT_FULL[j] * (2 * LANES if j == 0 else LANES)
	n += int(RAIL_RATE[4] * RAIL_LIFE) * rail_emitters.size()
	n += int(round(SUSTAIN_RATE * SUSTAIN_LIFE)) * sustain_emitters.size()
	return n


# ---- Judgments -------------------------------------------------------------------------------

func on_judged(lane: int, _note_index: int, judgment: int, _error_s: float) -> void:
	if lane < 0 or lane >= LANES:
		return
	var t := now()
	match judgment:
		InputJudge.Judgment.PERFECT:
			var e := perfect_emitters[lane * 2 + _rr[lane]]
			_rr[lane] = 1 - _rr[lane]
			_emit(e, lane, HitBurst.amount(judgment, _low, _reduce))
			rings.add(FX_RING_PERFECT, lane, t)
			if not _low:
				rings.add(FX_BLOOM, lane, t)
			if _flash_on():
				rings.add(FX_FLASH, lane, t)
		InputJudge.Judgment.GOOD:
			_emit(good_emitters[lane], lane, HitBurst.amount(judgment, _low, _reduce))
			rings.add(FX_RING_GOOD, lane, t)
		_:
			_emit(miss_emitters[lane], lane, HitBurst.amount(InputJudge.Judgment.MISS, _low, _reduce))
			rings.add(FX_CRACK, lane, t)
			request_shake()


func _emit(e: CPUParticles2D, lane: int, amt: int) -> void:
	if amt <= 0:
		return
	e.position = Trench.hit_point(lane)
	e.restart(true)


## Emit every burst once off-screen (during the intro / count-in) so the first real hit has
## no first-use hitch. Nothing is visible: the emit point is far outside the clip rect.
func prewarm() -> void:
	for e in burst_emitters():
		e.position = PREWARM_POS
		e.restart(true)


## Stop every continuous emitter (fail / teardown).
func stop() -> void:
	for l in range(LANES):
		_held[l] = false
	tier = 1
	_update_rails()
	_update_sustains()
	_end_shake()


# ---- Tiers and sustains ----------------------------------------------------------------------

func set_tier(m: int) -> void:
	tier = clampi(m, 1, 4)
	_update_rails()


func _update_rails() -> void:
	_rail_rate = RAIL_RATE[clampi(tier, 1, 4)] if _sparks_on() else 0.0
	for e in rail_emitters:
		if _rail_rate > 0.0:
			var amt := int(round(_rail_rate * RAIL_LIFE))
			if e.amount != amt:
				e.amount = amt
			e.emitting = true
		else:
			e.emitting = false


func on_sustain_state(lane: int, held: bool) -> void:
	if lane < 0 or lane >= LANES:
		return
	_held[lane] = held
	_update_sustains()


func _update_sustains() -> void:
	var on := _sparks_on()
	for lane in range(LANES):
		sustain_emitters[lane].emitting = on and _held[lane]


# ---- Shake -----------------------------------------------------------------------------------

## Board-only shake: 6 px decaying over 120 ms, at most one per 150 ms, off under Reduce
## motion. Returns true when a shake started.
func request_shake() -> bool:
	if _reduce or _board == null or not is_instance_valid(_board):
		return false
	var t := now()
	if t - _last_shake < SHAKE_GAP_USEC:
		return false
	_last_shake = t
	if not _shake_active:
		_shake_base = Vector2.ZERO
	_shake_active = true
	_shake_start = t
	return true


func shaking() -> bool:
	return _shake_active


func advance_shake(t: int) -> void:
	if not _shake_active:
		return
	if _board == null or not is_instance_valid(_board):
		_shake_active = false
		return
	var k := float(t - _shake_start) / float(SHAKE_USEC)
	if k >= 1.0 or k < 0.0:
		_end_shake()
		return
	var amp := SHAKE_PX * pow(1.0 - k, 2.0)
	var ang := k * TAU * SHAKE_TURNS
	var dir := Vector2(cos(ang), 0.5 * sin(ang)).limit_length(1.0)
	_board.position = _shake_base + dir * amp


func _end_shake() -> void:
	if _shake_active and _board != null and is_instance_valid(_board):
		_board.position = _shake_base
	_shake_active = false


func _exit_tree() -> void:
	_end_shake()


func _process(_delta: float) -> void:
	var t := now()
	advance_shake(t)
	if rings.live_count() > 0:
		rings.expire(t)
		rings.queue_redraw()
		flashes.queue_redraw()


# ---- Ring / flash / crack pool ---------------------------------------------------------------

class BurstRings:
	extends Node2D
	## Fixed pool of ring, flash, bloom and crack entries; draws rings and cracks.

	var layer: FxLayer
	var kinds := PackedInt32Array()
	var lanes := PackedInt32Array()
	var born := PackedInt64Array()

	func _init() -> void:
		name = "BurstRings"
		kinds.resize(FxLayer.RING_POOL)
		kinds.fill(-1)
		lanes.resize(FxLayer.RING_POOL)
		born.resize(FxLayer.RING_POOL)

	func add(kind: int, lane: int, t: int) -> void:
		var slot := -1
		var oldest := 0
		for i in range(kinds.size()):
			if kinds[i] < 0:
				slot = i
				break
			if born[i] < born[oldest]:
				oldest = i
		if slot < 0:
			slot = oldest
		kinds[slot] = kind
		lanes[slot] = lane
		born[slot] = t
		queue_redraw()

	func count_kind(kind: int) -> int:
		var n := 0
		for k in kinds:
			if k == kind:
				n += 1
		return n

	func live_count() -> int:
		var n := 0
		for k in kinds:
			if k >= 0:
				n += 1
		return n

	func expire(t: int) -> void:
		for i in range(kinds.size()):
			if kinds[i] >= 0 and float(t - born[i]) / 1e6 >= HitBurst.life(kinds[i]):
				kinds[i] = -1

	func age(i: int) -> float:
		return float(layer.now() - born[i]) / 1e6

	func _draw() -> void:
		if layer == null:
			return
		for i in range(kinds.size()):
			var k := kinds[i]
			if k != FxLayer.FX_RING_PERFECT and k != FxLayer.FX_RING_GOOD and k != FxLayer.FX_CRACK:
				continue
			var a := age(i)
			if a < 0.0 or a >= HitBurst.life(k):
				continue
			var hit := Trench.hit_point(lanes[i])
			var lane_col := Palette.lane_color(lanes[i])
			if k == FxLayer.FX_CRACK:
				var fade := 1.0 - a / HitBurst.life(k)
				var red := Palette.WARNING_RED
				for pl in FxLayer.crack_polylines(lanes[i]):
					var pts := PackedVector2Array()
					for p in pl:
						pts.append(hit + p)
					draw_polyline(pts, Palette.alpha(red, CRACK_GLOW_ALPHA * fade), CRACK_GLOW_W, true)
					draw_polyline(pts, Palette.alpha(red, fade), CRACK_W, true)
				var h := FxLayer.X_HALF
				var xc := Palette.alpha(red, fade)
				draw_line(hit + Vector2(-h, -h), hit + Vector2(h, h), xc, FxLayer.X_W, true)
				draw_line(hit + Vector2(-h, h), hit + Vector2(h, -h), xc, FxLayer.X_W, true)
				continue
			var s := HitBurst.ring_state(k, a)
			var col := lane_col
			if k == FxLayer.FX_RING_PERFECT:
				col = Palette.mix(lane_col, Palette.WHITE, FxLayer.PERFECT_RING_WHITE_MIX)
			var r: float = s["r"]
			var w: float = s["w"]
			var al: float = s["a"]
			if not layer._low:
				draw_arc(hit, r, 0.0, TAU, FxLayer.RING_SEGMENTS,
					Palette.alpha(lane_col, al * FxLayer.RING_GLOW_ALPHA), w + FxLayer.RING_GLOW_EXTRA_W, true)
			draw_arc(hit, r, 0.0, TAU, FxLayer.RING_SEGMENTS, Palette.alpha(col, al), w, true)


class BurstFlashes:
	extends Node2D
	## Additive child: the Perfect white core flash and the lane-colour bloom at the receptor.

	var rings: BurstRings

	func _init() -> void:
		name = "BurstFlashes"

	func _draw() -> void:
		if rings == null or rings.layer == null:
			return
		var tex := UiKit.glow_texture()
		for i in range(rings.kinds.size()):
			var k := rings.kinds[i]
			if k != FxLayer.FX_FLASH and k != FxLayer.FX_BLOOM:
				continue
			var a := rings.age(i)
			var lf := HitBurst.life(k)
			if a < 0.0 or a >= lf:
				continue
			var fade := 1.0 - a / lf
			var hit := Trench.hit_point(rings.lanes[i])
			if k == FxLayer.FX_BLOOM:
				var sz := FxLayer.BLOOM_PX * (0.8 + 0.4 * (a / lf))
				draw_texture_rect(tex, Rect2(hit - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
					Palette.alpha(Palette.lane_color(rings.lanes[i]), FxLayer.BLOOM_ALPHA * fade))
			else:
				var g := FxLayer.FLASH_GLOW_PX
				draw_texture_rect(tex, Rect2(hit - Vector2(g, g) * 0.5, Vector2(g, g)), false,
					Palette.alpha(Palette.WHITE, 0.8 * fade))
				draw_circle(hit, HitBurst.flash_radius() * (0.7 + 0.3 * fade), Palette.alpha(Palette.WHITE, 0.85 * fade), true, -1.0, true)
