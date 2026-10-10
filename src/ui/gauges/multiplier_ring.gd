class_name MultiplierRing
extends Control
## Segmented multiplier ring on the left console (UI-SPEC 4.5, 11). Three 110 degree arcs of
## 10 notches each; one notch = one combo toward the next multiplier
## (JudgeConfig.combo_per_multiplier_step = 10). x4 lights all 30 notches in REWARD_GOLD with
## a glow, an orbiting glint and the MAX chip. Read-only: it only listens to HullScore signals.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().
## Animations are delta-driven in _process so tests can step them.

const RECT := Rect2(48.0, 816.0, 192.0, 232.0)  # ring + caption + MAX chip (y 816..1048)
const CENTER := Vector2(144.0, 912.0)
const R_IN := 78.0
const R_OUT := 96.0
const ARC_STARTS: Array[float] = [-85.0, 35.0, 155.0]
const ARC_SPAN := 110.0
const NOTCHES := 10
const NOTCH_GAP := 1.5
const STEP := 10
const MAX_MULT := 4
const UNLIT_ALPHA := 0.70
const NUMERAL_BASE_Y := 920.0
const CAPTION_BASE_Y := 950.0
const CAPTION := "MULTIPLIER"
const MAX_CHIP := "MAX"
const CHIP_Y := 1016.0
const FLASH_SEC := 0.12  # DUR_FAST
const POP_SEC := 0.12  # DUR_FAST
const POP_PEAK := 1.15
const DRAIN_SEC := 0.18
const GLINT_DEG := 20.0
const GLINT_PERIOD := 2.0
const GLINT_ALPHA := 0.55
const ARC_POINTS := 4

var _combo: int = 0
var _mult: int = 1
var _shown: float = 0.0
var _drain_from: float = 0.0
var _drain_t: float = -1.0  # < 0: not draining
var _flash_left: float = 0.0
var _pop_t: float = -1.0  # < 0: not popping
var _glint_phase: float = 0.0
var _low: bool = false
var _reduce: bool = false
var _glow: Node2D


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = Node2D.new()
	_glow.name = "MaxGlow"
	_glow.show_behind_parent = true
	_glow.material = UiKit.additive_material()
	_glow.position = CENTER - RECT.position
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(score: HullScore) -> void:
	score.combo_changed.connect(on_combo)
	score.multiplier_changed.connect(on_multiplier)
	_combo = score.combo
	_mult = score.multiplier()
	_shown = float(filled_total(_combo))
	queue_redraw()


## Lit notches per arc for a combo: [a1, a2, a3]. 30+ lights everything (x4, MAX).
static func lit_notches(combo: int) -> Array[int]:
	var total := filled_total(combo)
	var out: Array[int] = []
	for a in 3:
		out.append(clampi(total - a * NOTCHES, 0, NOTCHES))
	return out


static func filled_total(combo: int) -> int:
	return clampi(combo, 0, STEP * (MAX_MULT - 1))


## Start/end angle in degrees of notch `n` (0..9) on arc `a` (0..2).
static func notch_degrees(a: int, n: int) -> Vector2:
	var w := (ARC_SPAN - NOTCH_GAP * (NOTCHES - 1)) / NOTCHES
	var s := ARC_STARTS[a] + n * (w + NOTCH_GAP)
	return Vector2(s, s + w)


func on_combo(value: int) -> void:
	var old := _combo
	_combo = value
	var target := float(filled_total(value))
	if value < old and not _reduce and _shown > target:
		_drain_from = _shown
		_drain_t = 0.0
	else:
		_drain_t = -1.0
		_shown = target
	queue_redraw()


func on_multiplier(value: int) -> void:
	var rose := value > _mult
	_mult = value
	if rose and not _reduce:
		_flash_left = FLASH_SEC
		_pop_t = 0.0
	if _glow != null:
		_glow.queue_redraw()
	queue_redraw()


func is_max() -> bool:
	return _mult >= MAX_MULT


func max_chip_visible() -> bool:
	return is_max()


func lit_color() -> Color:
	return Palette.REWARD_GOLD if is_max() else Palette.SONAR


func numeral_text() -> String:
	return "×%d" % _mult


func shown_fill() -> float:
	return _shown


func is_flashing() -> bool:
	return _flash_left > 0.0


func numeral_scale() -> float:
	if _pop_t < 0.0:
		return 1.0
	var k := clampf(_pop_t / POP_SEC, 0.0, 1.0)
	return 1.0 + (POP_PEAK - 1.0) * sin(PI * k)


func glint_on() -> bool:
	return is_max() and not _low and not _reduce


func glow_on() -> bool:
	return is_max() and not _low


## Effect contract (UI-SPEC 11): Low drops glow and glint; Reduce drops pop, drain and glint.
func apply_effect_settings() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	if _reduce:
		_pop_t = -1.0
		_flash_left = 0.0
		_drain_t = -1.0
		_shown = float(filled_total(_combo))
	if _glow != null:
		_glow.queue_redraw()
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"glint": glint_on(), "glow": glow_on(), "pop": not _reduce, "drain": not _reduce}


func _process(delta: float) -> void:
	var dirty := false
	if _drain_t >= 0.0:
		_drain_t += delta
		var k := clampf(_drain_t / DRAIN_SEC, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)  # cubic-out
		_shown = lerpf(_drain_from, float(filled_total(_combo)), e)
		if k >= 1.0:
			_drain_t = -1.0
			_shown = float(filled_total(_combo))
		dirty = true
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		dirty = true
	if _pop_t >= 0.0:
		_pop_t += delta
		if _pop_t >= POP_SEC:
			_pop_t = -1.0
		dirty = true
	if glint_on():
		_glint_phase = fmod(_glint_phase + delta / GLINT_PERIOD, 1.0)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	draw_set_transform(-RECT.position, 0.0, Vector2.ONE)
	var lit := lit_color()
	if is_flashing():
		lit = Palette.mix(lit, Palette.SONAR_PALE, _flash_left / FLASH_SEC)
	var unlit := Palette.alpha(Palette.ABYSS_500, UNLIT_ALPHA)
	var r := (R_IN + R_OUT) * 0.5
	var w := R_OUT - R_IN
	var shown_n := int(round(_shown))
	for a in 3:
		for n in NOTCHES:
			var deg := notch_degrees(a, n)
			var col := lit if a * NOTCHES + n < shown_n else unlit
			draw_arc(CENTER, r, deg_to_rad(deg.x), deg_to_rad(deg.y), ARC_POINTS, col, w, true)
	if glint_on():
		var g0 := ARC_STARTS[0] + 360.0 * _glint_phase
		draw_arc(CENTER, r, deg_to_rad(g0), deg_to_rad(g0 + GLINT_DEG), 8,
			Palette.alpha(Palette.SONAR_PALE, GLINT_ALPHA), w, true)
	_draw_numeral()
	var cf := Palette.font()
	var cw := cf.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	draw_string(cf, Vector2(CENTER.x - cw * 0.5, CAPTION_BASE_Y), CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_LABEL, Palette.TEXT_LO)
	if max_chip_visible():
		var chip_w := UiKit.chip_width(MAX_CHIP, "reward")
		UiKit.draw_chip(self, Rect2(CENTER.x - chip_w * 0.5, CHIP_Y, chip_w, UiKit.CHIP_H), MAX_CHIP, "reward")
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_numeral() -> void:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var text := numeral_text()
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var s := numeral_scale()
	# Scale about the numeral's centre (x 144, mid-height above the baseline).
	var pivot := Vector2(CENTER.x, NUMERAL_BASE_Y - f.get_ascent(fs) * 0.35)
	draw_set_transform(-RECT.position + pivot - pivot * s, 0.0, Vector2(s, s))
	var col := Palette.REWARD_GOLD if is_max() else Palette.TEXT_HI
	draw_string(f, Vector2(CENTER.x - tw * 0.5, NUMERAL_BASE_Y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(-RECT.position, 0.0, Vector2.ONE)


## glow_md behind the ring at x4 (Full only): additive, 2.4 x the ring, alpha 0.25.
func _draw_glow() -> void:
	if not glow_on():
		return
	var d := R_OUT * 2.0 * Palette.GLOW_MD[0]
	_glow.draw_texture_rect(UiKit.glow_texture(), Rect2(Vector2(-d, -d) * 0.5, Vector2(d, d)), false,
		Palette.alpha(Palette.REWARD_GOLD, Palette.GLOW_MD[1]))
