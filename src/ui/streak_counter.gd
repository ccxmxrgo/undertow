class_name StreakCounter
extends Control
## STREAK (combo) instrument on the left cockpit console plus milestone popups (UI-SPEC 7.3,
## D-08, D-13, VIS-04, VIS-09). The numeral is always visible (also at 0) in a fixed 4-digit
## box, right-aligned at x 368. Milestones (10/25/50/100, then every 100) pop a label with a
## SONAR_PALE spark burst and flash both highway outer rails. Lane colours are never used here.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().
## Animations are delta-driven in _process so tests can step them.

const RIGHT_X := 368.0
const NUMBER_BASE_Y := 736.0
const BOX_DIGITS := 4
const BOX_MIN_W := 222.0  # 146..368
const CAPTION_POS := Vector2(48.0, 644.0)
const CAPTION := "STREAK"
const POPUP_CX := 208.0
const POPUP_BASE_Y := 584.0
const POPUP_SEC := 0.7
const POPUP_RISE := 32.0
const POPUP_POP_SEC := 0.12  # DUR_FAST, back-out
const POPUP_POP_FROM := 1.3
const POPUP_STATIC_SEC := 0.7
const POPUP_STATIC_FADE := 0.2
const POPUP_OUTLINE_PX := 6  # 3 px KEYLINE each side
const POPUP_SAMPLE := "9999 STREAK"
const PULSE_SEC := 0.08
const PULSE_PEAK := 1.08
const PULSE_PIVOT := Vector2(257.0, 700.0)
const TEXT_GLOW_PX := 12
const TEXT_GLOW_ALPHA := 0.25
const NUM_CHARS := 4
const SPARK_ORIGIN := Vector2(257.0, 700.0)
const SPARKS_FULL := 24
const SPARKS_LOW := 8
const SPARK_LIFETIME := 0.5
const SPARK_VEL_MIN := 180.0
const SPARK_VEL_MAX := 320.0
const SPARK_SCALE_MIN := 0.05
const SPARK_SCALE_MAX := 0.09
const RAIL_FLASH_ALPHA := 0.6
const RAIL_FLASH_SEC := 0.16

## Board highway whose outer rails flash on a milestone (set by Gameplay; may stay null).
var highway: Highway

var _combo: int = 0
var _pulse_t: float = -1.0  # < 0: no pop
var _popup_text: String = ""
var _popup_age: float = 0.0
var _low: bool = false
var _reduce: bool = false
var _sparks: CPUParticles2D
var _sparks_fired: int = 0


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sparks = CPUParticles2D.new()
	_sparks.name = "MilestoneSparks"
	_sparks.position = SPARK_ORIGIN
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 1.0
	_sparks.lifetime = SPARK_LIFETIME
	_sparks.local_coords = false
	_sparks.direction = Vector2.UP
	_sparks.spread = 180.0
	_sparks.gravity = Vector2.ZERO
	_sparks.initial_velocity_min = SPARK_VEL_MIN
	_sparks.initial_velocity_max = SPARK_VEL_MAX
	_sparks.texture = UiKit.glow_texture()
	_sparks.material = UiKit.additive_material()
	_sparks.scale_amount_min = SPARK_SCALE_MIN
	_sparks.scale_amount_max = SPARK_SCALE_MAX
	_sparks.color = Palette.SONAR_PALE
	var fade := Gradient.new()
	fade.set_color(0, Palette.WHITE)
	fade.set_color(1, Palette.alpha(Palette.WHITE, 0.0))
	_sparks.color_ramp = fade
	add_child(_sparks)
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(score: HullScore) -> void:
	score.combo_changed.connect(on_combo)
	_combo = score.combo
	queue_redraw()


## Colour tier: 0 below 10, 1 for 10..49, 2 for 50..99, 3 for 100+ (glow).
static func tier(n: int) -> int:
	if n < 10:
		return 0
	if n < 50:
		return 1
	if n < 100:
		return 2
	return 3


static func font_size_for(_t: int) -> int:
	return Palette.SIZE_DISPLAY


static func color_for(t: int) -> Color:
	match t:
		0:
			return Palette.TEXT_LO
		1:
			return Palette.TEXT_HI
	return Palette.SONAR_PALE


static func color_for_streak(n: int) -> Color:
	return color_for(tier(n))


static func glows(n: int) -> bool:
	return tier(n) >= 3


## Right edge of the numeral box on the left console (UI-SPEC 7.3).
static func right_x() -> float:
	return RIGHT_X


static func spark_count(low: bool, reduce: bool) -> int:
	if reduce:
		return 0
	return SPARKS_LOW if low else SPARKS_FULL


func on_combo(value: int) -> void:
	var old := _combo
	_combo = value
	if value < old:
		_pulse_t = -1.0  # break: instant reset
	elif value > old and value / 10 > old / 10 and not _reduce:
		_pulse_t = 0.0
	var m := StreakMilestones.reached(old, value)
	if m > 0:
		_popup_text = "%d STREAK" % m
		_popup_age = 0.0
		_fire_burst()
	queue_redraw()


func _fire_burst() -> void:
	var n := spark_count(_low, _reduce)
	if n > 0 and _sparks != null:
		if _sparks.amount != n:
			_sparks.amount = n
		_sparks.restart()
		_sparks_fired += 1
	if highway != null and is_instance_valid(highway):
		highway.flash_rails(RAIL_FLASH_ALPHA, RAIL_FLASH_SEC)


## Effect contract (UI-SPEC 11): milestone sparks 24 Full / 8 Low / 0 Reduce; no pop under Reduce.
func apply_effect_settings() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	if _reduce:
		_pulse_t = -1.0
	var n := spark_count(_low, _reduce)
	if _sparks != null and n > 0 and _sparks.amount != n:
		_sparks.amount = n
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"milestone_sparks": spark_count(_low, _reduce)}


func sparks() -> CPUParticles2D:
	return _sparks


func sparks_fired() -> int:
	return _sparks_fired


## Always true: the streak is a cockpit instrument (kept for the harness/tests API).
func is_counter_visible() -> bool:
	return true


func popup_text() -> String:
	return _popup_text


func number_text() -> String:
	return ("%" + str(NUM_CHARS) + "d") % _combo


func numeral_scale() -> float:
	if _pulse_t < 0.0:
		return 1.0
	var k := clampf(_pulse_t / PULSE_SEC, 0.0, 1.0)
	return 1.0 + (PULSE_PEAK - 1.0) * sin(PI * k)


## Fixed numeral box (identical for every value, so nothing shifts).
func numeral_box() -> Rect2:
	var f := Palette.display_font()
	var fs := Palette.SIZE_DISPLAY
	var w := maxf(UiKit.fixed_number_box(f, fs, BOX_DIGITS), BOX_MIN_W)
	var asc := f.get_ascent(fs)
	return Rect2(RIGHT_X - w, NUMBER_BASE_Y - asc, w, asc + f.get_descent(fs))


func _caption_rect() -> Rect2:
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var w := f.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	return Rect2(CAPTION_POS.x, CAPTION_POS.y - asc, w, asc + f.get_descent(fs))


func _popup_rect() -> Rect2:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var w := f.get_string_size(POPUP_SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * POPUP_POP_FROM
	var top := POPUP_BASE_Y - POPUP_RISE - f.get_ascent(fs) * POPUP_POP_FROM
	var x0 := maxf(POPUP_CX - w * 0.5, 0.0)
	var x1 := minf(POPUP_CX + w * 0.5, 400.0)
	return Rect2(x0, top, x1 - x0, POPUP_BASE_Y + f.get_descent(fs) - top)


static func _rect_poly(r: Rect2, xf: Transform2D) -> PackedVector2Array:
	return xf * PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])


## W4 contract for full-screen canvases: global polygons of everything this node draws
## (numeral box, caption, milestone popup area).
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var out: Array[PackedVector2Array] = []
	for r in [numeral_box(), _caption_rect(), _popup_rect()]:
		out.append(_rect_poly(r, xf))
	return out


func _popup_life() -> float:
	if _reduce:
		return POPUP_STATIC_SEC + POPUP_STATIC_FADE
	return POPUP_SEC


func _process(delta: float) -> void:
	var dirty := false
	if _pulse_t >= 0.0:
		_pulse_t += delta
		if _pulse_t >= PULSE_SEC:
			_pulse_t = -1.0
		dirty = true
	if _popup_text != "":
		_popup_age += delta
		if _popup_age >= _popup_life():
			_popup_text = ""
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	_draw_counter()
	if _popup_text != "":
		_draw_popup()


func _draw_counter() -> void:
	var f := Palette.display_font()
	var fs := font_size_for(tier(_combo))
	var col := color_for_streak(_combo)
	var text := str(_combo)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var s := numeral_scale()
	draw_set_transform(PULSE_PIVOT - PULSE_PIVOT * s, 0.0, Vector2(s, s))
	var pos := Vector2(RIGHT_X - w, NUMBER_BASE_Y)
	if glows(_combo) and not _low:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT_GLOW_PX,
			Palette.alpha(col, TEXT_GLOW_ALPHA))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(Palette.font(), CAPTION_POS, CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL,
		Palette.TEXT_LO)


static func _ease_out_back(k: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)


func _draw_popup() -> void:
	var age := _popup_age
	var a := 1.0
	var rise := 0.0
	var s := 1.0
	if _reduce:
		if age > POPUP_STATIC_SEC:
			a = clampf(1.0 - (age - POPUP_STATIC_SEC) / POPUP_STATIC_FADE, 0.0, 1.0)
	else:
		var k := clampf(age / POPUP_SEC, 0.0, 1.0)
		rise = POPUP_RISE * (1.0 - (1.0 - k) * (1.0 - k))  # ease-out
		a = 1.0 - k
		var kp := clampf(age / POPUP_POP_SEC, 0.0, 1.0)
		s = lerpf(POPUP_POP_FROM, 1.0, _ease_out_back(kp))
	if a <= 0.0:
		return
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var text := _popup_text.to_upper()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var anchor := Vector2(POPUP_CX, POPUP_BASE_Y - rise)
	draw_set_transform(anchor, 0.0, Vector2(s, s))
	var pos := Vector2(-w * 0.5, 0.0)
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, POPUP_OUTLINE_PX,
		Palette.alpha(Palette.KEYLINE, Palette.KEYLINE.a * a))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.alpha(Palette.SONAR_PALE, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
