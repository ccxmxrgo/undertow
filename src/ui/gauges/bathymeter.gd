class_name Bathymeter
extends Control
## Vertical depth gauge on the right console (UI-SPEC 4.6). A glass tube from 0 m (top) to
## scale_m (bottom), where scale_m = max(all-Perfect estimate, saved best). The water column
## fills down to a SONAR marker that eases toward the live depth (tau 0.08 s, instant under
## Reduce motion). A gold BEST line marks the record and flashes once when the dive passes it.
## Read-only: estimate_max_depth() reads JudgeConfig values and never edits them (T-02.2-25).
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const RECT := Rect2(1760.0, 616.0, 112.0, 432.0)  # ticks, tube + caps, BEST label
const TUBE_X0 := 1792.0
const TUBE_X1 := 1808.0
const TOP_Y := 632.0
const HEIGHT := 400.0
const CAP_R := 8.0
const OUTLINE_ALPHA := 0.35
const WATER_ALPHA := 0.35
const WATER_INSET := 2.0
const MINOR_STEPS := 20
const MAJOR_EVERY := 5  # every 5 minor steps = 1/4 of the scale
const MINOR_X := Vector2(1778.0, 1788.0)
const MAJOR_X := Vector2(1768.0, 1788.0)
const MINOR_ALPHA := 0.5
const MARKER_TIP_X := 1790.0
const MARKER_SIZE := 16.0
const BEST_X := Vector2(1786.0, 1814.0)
const BEST_LABEL_X := 1822.0
const BEST_LABEL_DY := 7.0
const BEST_TEXT := "BEST"
const EASE_TAU := 0.08
const SNAP_PX := 0.05
## Sustain ticks per hold are capped so a corrupt chart cannot stall the estimate.
const MAX_TICKS_PER_NOTE := 100000
const TICK_EPS := 1e-9

var _estimate: float = 0.0
var _best: float = -1.0
var _depth: float = 0.0
var _shown_y: float = TOP_Y
var _flash_left: float = 0.0
var _passed_best: bool = false
var _reduce: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


## Scale estimate (m) and saved best (m, < 0 or non-finite = no record).
func setup(scale_estimate_m: float, best_m: float) -> void:
	_estimate = scale_estimate_m if is_finite(scale_estimate_m) and scale_estimate_m > 0.0 else 0.0
	_best = best_m if is_finite(best_m) and best_m >= 0.0 else -1.0
	_passed_best = _best >= 0.0 and _depth >= _best and _depth > 0.0
	_flash_left = 0.0
	_shown_y = target_y()
	queue_redraw()


## Live depth in meters. Non-finite values are ignored (T-02.2-24).
func set_depth(m: float) -> void:
	if not is_finite(m):
		return
	_depth = maxf(m, 0.0)
	if best_visible() and not _passed_best and _depth >= _best and _depth > 0.0:
		_passed_best = true
		_flash_left = Palette.DUR_BASE
	if _reduce:
		_shown_y = target_y()
	queue_redraw()


func scale_m() -> float:
	return maxf(_estimate, _best)


func best_visible() -> bool:
	return _best >= 0.0


func best_y() -> float:
	return marker_y_for(_best, scale_m())


func target_y() -> float:
	return marker_y_for(_depth, scale_m())


func shown_y() -> float:
	return _shown_y


func best_flashing() -> bool:
	return _flash_left > 0.0


## y = 632 + 400 * clamp(depth / scale, 0, 1); the top when the scale is unknown.
static func marker_y_for(depth_m: float, scale: float) -> float:
	if not is_finite(depth_m) or not is_finite(scale) or scale <= 0.0:
		return TOP_Y
	return TOP_Y + HEIGHT * clampf(depth_m / scale, 0.0, 1.0)


## Depth (m) of an all-Perfect run: notes in time order score score_perfect x the multiplier
## in effect before the hit (min(1 + combo / step, max)); each sustain adds
## floor(duration / sustain_tick_interval) ticks of score_sustain_tick x the multiplier at the
## tick time. Divided by score_per_meter. Mirrors HullScore without driving it.
static func estimate_max_depth(chart: ChartData, cfg: JudgeConfig) -> float:
	if chart == null or cfg == null or cfg.score_per_meter <= 0.0 or chart.notes.is_empty():
		return 0.0
	var events: Array[Vector2] = []  # x = time, y = 0 head / 1 tick (heads first at equal time)
	var interval := cfg.sustain_tick_interval
	for n in chart.notes:
		var t := float(n["time"])
		var dur := float(n["duration"])
		if not is_finite(t):
			continue
		events.append(Vector2(t, 0.0))
		if interval > 0.0 and dur > 0.0 and is_finite(dur):
			var ticks := mini(int(floor(dur / interval + TICK_EPS)), MAX_TICKS_PER_NOTE)
			for k in range(1, ticks + 1):
				events.append(Vector2(t + k * interval, 1.0))
	events.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x)
	var step := maxi(cfg.combo_per_multiplier_step, 1)
	var combo := 0
	var total := 0.0
	for e in events:
		var mult := mini(1 + combo / step, cfg.max_multiplier)
		if e.y == 0.0:
			total += float(cfg.score_perfect * mult)
			combo += 1
		else:
			total += float(cfg.score_sustain_tick * mult)
	return total / cfg.score_per_meter


## Effect contract (UI-SPEC 11): Reduce motion makes the marker jump instead of easing.
func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	if _reduce:
		_shown_y = target_y()
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"ease": not _reduce, "best_flash": best_visible()}


func _process(delta: float) -> void:
	var dirty := false
	var target := target_y()
	if _shown_y != target:
		if _reduce:
			_shown_y = target
		else:
			_shown_y = lerpf(target, _shown_y, exp(-delta / EASE_TAU))
			if absf(_shown_y - target) < SNAP_PX:
				_shown_y = target
		dirty = true
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	draw_set_transform(-RECT.position, 0.0, Vector2.ONE)
	var cx := (TUBE_X0 + TUBE_X1) * 0.5
	var bottom := TOP_Y + HEIGHT
	# Ticks left of the tube: minor every 1/20, major every 1/4.
	for i in MINOR_STEPS + 1:
		var y := TOP_Y + HEIGHT * float(i) / MINOR_STEPS
		if i % MAJOR_EVERY == 0:
			draw_line(Vector2(MAJOR_X.x, y), Vector2(MAJOR_X.y, y), Palette.TEXT_LO, 2.0)
		else:
			draw_line(Vector2(MINOR_X.x, y), Vector2(MINOR_X.y, y), Palette.alpha(Palette.TEXT_LO, MINOR_ALPHA), 1.0)
	# Glass tube with rounded caps.
	draw_rect(Rect2(TUBE_X0, TOP_Y, TUBE_X1 - TUBE_X0, HEIGHT), Palette.ABYSS_800)
	draw_circle(Vector2(cx, TOP_Y), CAP_R, Palette.ABYSS_800)
	draw_circle(Vector2(cx, bottom), CAP_R, Palette.ABYSS_800)
	# Water column from the top to the marker.
	var water := Palette.alpha(Palette.SONAR, WATER_ALPHA)
	var wr := CAP_R - WATER_INSET
	draw_circle(Vector2(cx, TOP_Y), wr, water)
	if _shown_y > TOP_Y:
		draw_rect(Rect2(TUBE_X0 + WATER_INSET, TOP_Y, TUBE_X1 - TUBE_X0 - WATER_INSET * 2.0, _shown_y - TOP_Y), water)
	var edge := Palette.alpha(Palette.SONAR, OUTLINE_ALPHA)
	draw_line(Vector2(TUBE_X0, TOP_Y), Vector2(TUBE_X0, bottom), edge, 1.0)
	draw_line(Vector2(TUBE_X1, TOP_Y), Vector2(TUBE_X1, bottom), edge, 1.0)
	draw_arc(Vector2(cx, TOP_Y), CAP_R, PI, TAU, 12, edge, 1.0, true)
	draw_arc(Vector2(cx, bottom), CAP_R, 0.0, PI, 12, edge, 1.0, true)
	# Best marker (gold line + label); flashes once when passed.
	if best_visible():
		var by := best_y()
		var k := _flash_left / Palette.DUR_BASE if best_flashing() else 0.0
		var col := Palette.mix(Palette.REWARD_GOLD, Palette.WHITE, 0.6 * k)
		draw_line(Vector2(BEST_X.x, by), Vector2(BEST_X.y, by), col, 2.0 + 2.0 * k)
		draw_string(Palette.font(), Vector2(BEST_LABEL_X, by + BEST_LABEL_DY), BEST_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
			-1, Palette.SIZE_LABEL, Palette.REWARD_GOLD)
	# Live marker: right-pointing triangle, tip at (1790, y).
	var h := MARKER_SIZE * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(MARKER_TIP_X - MARKER_SIZE, _shown_y - h), Vector2(MARKER_TIP_X, _shown_y),
		Vector2(MARKER_TIP_X - MARKER_SIZE, _shown_y + h)]), Palette.SONAR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
