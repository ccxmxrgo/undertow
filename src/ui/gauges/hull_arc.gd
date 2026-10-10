class_name HullArc
extends Control
## Segmented hull gauge around the hit zone (UI-SPEC 4.7; 01.2 geometry kept). 20 segments of
## 5% fill left to right; the boundary segment is drawn at partial alpha. Colour: SONAR above
## 50%, TEXT_HI from 30 to 50%, WARNING_RED at 30% and below with a 3 Hz pulse (static under
## Reduce motion). Lost segments near the fill edge show crack glyphs, and every unlit segment
## cracks while critical, so the hull never relies on colour alone (segment count + cracks +
## 30% tick + the Hud's HULL CRITICAL caption).
## Damage: the lost part flashes WARNING_RED for 200 ms, then shrinks over ~150 ms (ease-out).
## Regen snaps up with a short bright nudge on the boundary segment.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().
## Timers are delta-driven in _process so tests can step them.

const RECT := Rect2(680.0, 986.0, 560.0, 88.0)  # arc band + 30% tick (x 686..1234, y 992..1070)
const CENTER := Vector2(960.0, 450.0)
const RADIUS := 612.0
const ANGLE_LEFT := 2.028
const ANGLE_RIGHT := 1.114
const R_IN := 607.0
const R_OUT := 617.0
const SEGMENTS := 20
const GAP := 0.006
const SEG_POINTS := 4
const CRITICAL_PCT := 30.0
const WARN_PCT := 50.0
const UNLIT_ALPHA := 0.60
const FLASH_SEC := 0.2
const FLASH_ALPHA := 0.9
const SHRINK_TAU := 0.05  # ~150 ms to settle
const SNAP_PCT := 0.05
const PULSE_HZ := 3.0
const NUDGE_SEC := 0.12  # DUR_FAST
const NUDGE_MIX := 0.5
const CRACK_RANGE := 3
const CRACK_ALPHA := 0.60
const CRACK_WIDTH := 1.5
const TICK_HALF := 8.0  # 16 px tick across the band
const TICK_WIDTH := 2.0

static var _cracks: Array = []

var _pct: float = 100.0
var _shown: float = 100.0
var _flash_left: float = 0.0
var _flash_from: float = 100.0
var _nudge_left: float = 0.0
var _reduce: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


## Jump to a hull percentage with no animation (bind / restart).
func reset(pct: float) -> void:
	_pct = clampf(pct, 0.0, 100.0)
	_shown = _pct
	_flash_left = 0.0
	_nudge_left = 0.0
	queue_redraw()


## Hull in percent and its change (negative = damage).
func set_hull(pct: float, delta: float) -> void:
	var v := clampf(pct, 0.0, 100.0) if is_finite(pct) else _pct
	if delta < 0.0:
		if _flash_left <= 0.0:
			_flash_from = _shown
		_flash_left = FLASH_SEC
	elif v > _shown:
		_shown = v
		if delta > 0.0 and not _reduce:
			_nudge_left = NUDGE_SEC
	_pct = v
	queue_redraw()


func pct() -> float:
	return _pct


func shown_pct() -> float:
	return _shown


func is_flashing() -> bool:
	return _flash_left > 0.0


func is_critical() -> bool:
	return _pct <= CRITICAL_PCT


func pulsing() -> bool:
	return is_critical() and not _reduce


## Fill alpha: 1.0 normally; 0.45..1.0 at 3 Hz while critical (static under Reduce motion).
func fill_alpha(now_usec: int) -> float:
	if not pulsing():
		return 1.0
	var ph := float(now_usec) / 1000000.0 * PULSE_HZ * TAU
	return 0.725 + 0.275 * cos(ph)


## Lit segments for a hull percentage (0..20, fractional at the boundary).
static func segments_lit(hull_pct: float) -> float:
	return clampf(hull_pct, 0.0, 100.0) * SEGMENTS / 100.0


## Angle on the arc for a hull percentage: 0% is the left end, 100% the right end.
static func angle_for(hull_pct: float) -> float:
	return ANGLE_LEFT - clampf(hull_pct, 0.0, 100.0) / 100.0 * (ANGLE_LEFT - ANGLE_RIGHT)


## (low angle, high angle) of segment k (0 = leftmost), with half a gap trimmed on each side.
static func segment_angles(k: int) -> Vector2:
	var span := (ANGLE_LEFT - ANGLE_RIGHT) / SEGMENTS
	return Vector2(ANGLE_LEFT - (k + 1) * span + GAP * 0.5, ANGLE_LEFT - k * span - GAP * 0.5)


static func color_for(hull_pct: float) -> Color:
	if hull_pct <= CRITICAL_PCT:
		return Palette.WARNING_RED
	if hull_pct <= WARN_PCT:
		return Palette.TEXT_HI
	return Palette.SONAR


## Segments that show a crack: lost segments within 3 of the fill edge (the partial boundary
## counts as lost); every unlit segment at 30% and below.
static func cracked_segments(hull_pct: float) -> Array[int]:
	var n := segments_lit(hull_pct)
	var edge := floori(n)
	var out: Array[int] = []
	for k in SEGMENTS:
		if n - k >= 1.0:
			continue
		if hull_pct <= CRITICAL_PCT or k < edge + CRACK_RANGE:
			out.append(k)
	return out


## Two jagged 3-point polylines across the band of segment k, in screen space. Deterministic
## per index (precomputed once).
static func crack_lines(k: int) -> Array[PackedVector2Array]:
	if _cracks.is_empty():
		for i in SEGMENTS:
			_cracks.append(_make_crack(i))
	var src: Array = _cracks[clampi(k, 0, SEGMENTS - 1)]
	var out: Array[PackedVector2Array] = []
	for line in src:
		out.append(line)
	return out


static func _jit(k: int, j: int) -> float:
	var v := sin(float(k) * 12.9898 + float(j) * 78.233) * 43758.5453
	return v - floorf(v)  # 0..1


static func _make_crack(k: int) -> Array:
	var a := segment_angles(k)
	var w := a.y - a.x
	var mid_r := (R_IN + R_OUT) * 0.5
	var lines: Array = []
	for l in 2:
		var base := a.x + w * (0.25 + 0.4 * l + 0.15 * _jit(k, l * 5))
		var pts := PackedVector2Array()
		var ang := [base, base + w * (_jit(k, l * 5 + 1) - 0.5) * 0.35, base + w * (_jit(k, l * 5 + 2) - 0.5) * 0.3]
		var rad := [R_OUT + 1.0, mid_r + (_jit(k, l * 5 + 3) - 0.5) * 4.0, R_IN - 1.0]
		for p in 3:
			pts.append(CENTER + Vector2(cos(ang[p]), sin(ang[p])) * float(rad[p]))
		lines.append(pts)
	return lines


## Effect contract (UI-SPEC 11): the critical pulse and the regen nudge stop under Reduce
## motion; the gauge itself is identical in every mode.
func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	if _reduce:
		_nudge_left = 0.0
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"pulse": pulsing(), "nudge": not _reduce}


func _process(delta: float) -> void:
	var dirty := pulsing()
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		dirty = true
	elif _shown > _pct:
		_shown = lerpf(_pct, _shown, exp(-delta / SHRINK_TAU))
		if absf(_shown - _pct) < SNAP_PCT:
			_shown = _pct
		dirty = true
	elif _shown < _pct:
		_shown = _pct
		dirty = true
	if _nudge_left > 0.0:
		_nudge_left = maxf(_nudge_left - delta, 0.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	draw_set_transform(-RECT.position, 0.0, Vector2.ONE)
	var band := R_OUT - R_IN
	var n := segments_lit(_shown)
	var lit := color_for(_pct)
	lit.a = fill_alpha(Time.get_ticks_usec())
	var unlit := Palette.alpha(Palette.ABYSS_500, UNLIT_ALPHA)
	var edge_k := clampi(ceili(n) - 1, 0, SEGMENTS - 1)  # last (possibly partial) lit segment
	for k in SEGMENTS:
		var a := segment_angles(k)
		var f := clampf(n - k, 0.0, 1.0)
		if f < 1.0:
			draw_arc(CENTER, RADIUS, a.x, a.y, SEG_POINTS, unlit, band, true)
		if f > 0.0:
			var c := lit
			if _nudge_left > 0.0 and k == edge_k:
				c = Palette.mix(c, Palette.SONAR_PALE, NUDGE_MIX * _nudge_left / NUDGE_SEC)
			c.a *= f
			draw_arc(CENTER, RADIUS, a.x, a.y, SEG_POINTS, c, band, true)
	# Damage flash over the lost part.
	if is_flashing():
		var n_new := segments_lit(_pct)
		var n_old := segments_lit(_flash_from)
		var fa := FLASH_ALPHA * _flash_left / FLASH_SEC
		for k in SEGMENTS:
			var lost := clampf(n_old - k, 0.0, 1.0) - clampf(n_new - k, 0.0, 1.0)
			if lost > 0.0:
				var a := segment_angles(k)
				draw_arc(CENTER, RADIUS, a.x, a.y, SEG_POINTS, Palette.alpha(Palette.WARNING_RED, fa * maxf(lost, 0.5)),
					band, true)
	# Cracks.
	var crack := Palette.alpha(Palette.TEXT_HI, CRACK_ALPHA)
	for k in cracked_segments(_shown):
		for line in crack_lines(k):
			draw_polyline(line, crack, CRACK_WIDTH, true)
	# 30% tick across the band: shape cue for the critical zone.
	var ang := angle_for(CRITICAL_PCT)
	var dir := Vector2(cos(ang), sin(ang))
	var mid := CENTER + dir * RADIUS
	draw_line(mid - dir * TICK_HALF, mid + dir * TICK_HALF, Palette.TEXT_HI, TICK_WIDTH)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
