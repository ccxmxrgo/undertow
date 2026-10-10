class_name GradeEmblem
extends Control
## Results grade emblem (UI-SPEC 4.13, D-08). A 224 x 224 chamfered octagon (48 px cut on all four
## corners: the declared badge exception to the 2-corner chamfer rule), fill ABYSS_600 92%, a 3 px
## edge in the grade colour, an inner ring r 88 at 2 px (grade colour 40%) with 16 px ticks at
## N/E/S/W, and a glow_lg sprite in the grade colour behind it (S 0.30, others 0.15). The letter is
## Display 96 Oxanium in Palette.grade_color, optically centred (baseline 146 px from the top),
## with a 25% text glow.
## Animation (play(delay)): after `delay` the badge and letter pop from scale 1.6 to 1.0 and fade
## 0 -> 1 over DUR_SLOW (back-out). An S fires one gold ring (r 80 -> 220, 0.4 s, alpha 0.6 -> 0)
## when the pop lands. Delta driven (step) so tests can drive it without a clock.
## Effect contract (UiKit.register_fx): Low effects = no glow sprite and no text glow (ring kept);
## Reduce motion = a 0.18 s fade only, no scale, no ring.

const SIZE := 224.0
const CUT := 48.0
const EDGE_W := 3.0
const RING_R := 88.0
const RING_W := 2.0
const RING_ALPHA := 0.4
const TICK_LEN := 16.0
const LETTER_BASE_Y := 146.0  # 426 - 280
const TEXT_GLOW := 12
const TEXT_GLOW_ALPHA := 0.25
const FILL_ALPHA := 0.92
const GLOW_S := 0.30
const POP_FROM := 1.6
const FADE_REDUCED := 0.18
const BURST_R0 := 80.0
const BURST_R1 := 220.0
const BURST_SEC := 0.4
const BURST_ALPHA := 0.6
const BURST_W := 3.0

var letter: String = "-"

var _t: float = 0.0
var _playing: bool = false
var _low: bool = false
var _reduce: bool = false
var _glow: GlowCanvas


## Additive glow sprite behind the badge (show_behind_parent), scaled with the pop.
class GlowCanvas:
	extends Control

	func _draw() -> void:
		var e := get_parent() as GradeEmblem
		if e == null or e._low:
			return
		var s := SIZE * Palette.GLOW_LG[0] * e.anim_scale()
		var c := Vector2(SIZE, SIZE) * 0.5
		draw_texture_rect(UiKit.glow_texture(), Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
			Palette.alpha(e.grade_color(), e.glow_alpha()))


func _init() -> void:
	size = Vector2(SIZE, SIZE)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_glow = GlowCanvas.new()
	_glow.name = "Glow"
	_glow.show_behind_parent = true
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.size = size
	_glow.material = UiKit.additive_material()
	add_child(_glow)


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()


func set_grade(g: String) -> void:
	letter = g if g != "" else "-"
	_redraw()


func grade_color() -> Color:
	return Palette.grade_color(letter)


## glow_lg alpha: S 0.30, every other grade 0.15 (Palette.GLOW_LG).
func glow_alpha() -> float:
	return GLOW_S if letter == "S" else Palette.GLOW_LG[1]


## Starts the pop `delay` seconds from now.
func play(delay: float = 0.2) -> void:
	_t = -maxf(delay, 0.0)
	_playing = true
	_redraw()


## Advances the animation by dt seconds.
func step(dt: float) -> void:
	if not _playing or dt <= 0.0:
		return
	_t += dt
	if _t >= _end_time():
		_playing = false
		_t = _end_time()
	_redraw()


## Jumps to the final state (results entrance skipped): full size, fully visible, no ring.
func finish() -> void:
	_playing = false
	_t = _end_time()
	_redraw()


func _end_time() -> float:
	if _reduce:
		return FADE_REDUCED
	return Palette.DUR_SLOW + (BURST_SEC if letter == "S" else 0.0)


func is_playing() -> bool:
	return _playing


func anim_alpha() -> float:
	if not _playing and _t >= 0.0:
		return 1.0
	if _t < 0.0:
		return 0.0
	var dur := FADE_REDUCED if _reduce else Palette.DUR_SLOW
	return clampf(_t / dur, 0.0, 1.0)


func anim_scale() -> float:
	if _reduce or _t >= Palette.DUR_SLOW:
		return 1.0
	if _t <= 0.0:
		return POP_FROM if _playing else 1.0
	return lerpf(POP_FROM, 1.0, _ease_back_out(_t / Palette.DUR_SLOW))


## The S burst ring is live between the end of the pop and BURST_SEC later.
func ring_active() -> bool:
	if letter != "S" or _reduce:
		return false
	var k := _t - Palette.DUR_SLOW
	return _playing and k >= 0.0 and k < BURST_SEC


static func _ease_back_out(k: float) -> float:
	var x := clampf(k, 0.0, 1.0) - 1.0
	const C1 := 1.70158
	return 1.0 + (C1 + 1.0) * x * x * x + C1 * x * x


## Outline of `rect` with all four corners cut by `cut` (8 points, clockwise from the top edge).
static func octagon_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_reduce = UiKit.reduce_motion()
	if _reduce and _playing and _t > FADE_REDUCED:
		_t = FADE_REDUCED
		_playing = false
	_redraw()


func effect_counts() -> Dictionary:
	return {"glow": not _low, "scale": not _reduce, "ring": letter == "S" and not _reduce}


func _process(delta: float) -> void:
	if _playing:
		step(delta)


func _redraw() -> void:
	modulate.a = anim_alpha()
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()


func _draw() -> void:
	var col := grade_color()
	var c := Vector2(SIZE, SIZE) * 0.5
	var s := anim_scale()
	draw_set_transform(c * (1.0 - s), 0.0, Vector2(s, s))
	var pts := octagon_points(Rect2(Vector2.ZERO, size), CUT)
	draw_colored_polygon(pts, Palette.alpha(Palette.ABYSS_600, FILL_ALPHA))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, EDGE_W, true)
	var ring := Palette.alpha(col, RING_ALPHA)
	draw_arc(c, RING_R, 0.0, TAU, 64, ring, RING_W, true)
	for d: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(c + d * (RING_R - TICK_LEN * 0.5), c + d * (RING_R + TICK_LEN * 0.5), ring, RING_W, true)
	var f := Palette.display_font()
	var fs := Palette.SIZE_DISPLAY
	var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(c.x - w * 0.5, LETTER_BASE_Y)
	if not _low:
		draw_string_outline(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT_GLOW,
			Palette.alpha(col, TEXT_GLOW_ALPHA))
	draw_string(f, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if ring_active():
		var k := clampf((_t - Palette.DUR_SLOW) / BURST_SEC, 0.0, 1.0)
		var r := lerpf(BURST_R0, BURST_R1, 1.0 - pow(1.0 - k, 3.0))
		draw_arc(c, r, 0.0, TAU, 96, Palette.alpha(Palette.REWARD_GOLD, BURST_ALPHA * (1.0 - k)), BURST_W, true)
