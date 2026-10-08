class_name StreakCounter
extends Control
## Large STREAK (combo) counter left of the hit ring plus milestone popups (D-08, D-13).
## The Perfect streak stays in the HUD; lane colors are never used here.

## Fallback/spec value; the live anchor is Trench.point(-2.6, 0.0).x - 24 (see right_x()).
const RIGHT_X := 390.0
const ANCHOR_F := -2.6
const NUMBER_BASE_Y := 709.0
const CAPTION_BASE_Y := 745.0
const POPUP_BASE_Y := 600.0
const MIN_SHOWN := 5
const FADE_IN_SEC := 0.12
const PULSE_SEC := 0.08
const POPUP_SEC := 0.7
const POPUP_RISE := 32.0
const POPUP_STATIC_SEC := 0.7
const POPUP_STATIC_FADE := 0.2
const NUM_CHARS := 4
const CAPTION := "STREAK"
const CAPTION_COLOR := Color("8A93AD")

var _combo: int = 0
var _shown_since_msec: int = 0
var _pulse_msec: int = -100000
var _popup_text: String = ""
var _popup_born_msec: int = 0


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(score: HullScore) -> void:
	score.combo_changed.connect(on_combo)


static func tier(n: int) -> int:
	if n < MIN_SHOWN:
		return 0
	if n < 10:
		return 1
	if n < 50:
		return 2
	if n < 100:
		return 3
	return 4


static func font_size_for(t: int) -> int:
	return Palette.SIZE_HEADING if t <= 1 else Palette.SIZE_DISPLAY


static func color_for(t: int) -> Color:
	return Palette.TEXT if t <= 1 else Palette.ACCENT


## Right edge of the number/caption/popup, derived from the trench (D-07).
static func right_x() -> float:
	return Trench.point(ANCHOR_F, 0.0).x - 24.0


func on_combo(value: int) -> void:
	var old := _combo
	_combo = value
	if value < MIN_SHOWN:
		_shown_since_msec = 0
	elif old < MIN_SHOWN:
		_shown_since_msec = Time.get_ticks_msec()
	if value > old:
		_pulse_msec = Time.get_ticks_msec()
	var m := StreakMilestones.reached(old, value)
	if m > 0:
		_popup_text = "%d STREAK" % m
		_popup_born_msec = Time.get_ticks_msec()
	queue_redraw()


func is_counter_visible() -> bool:
	return _combo >= MIN_SHOWN


func popup_text() -> String:
	return _popup_text


func number_text() -> String:
	return ("%" + str(NUM_CHARS) + "d") % _combo


func _popup_age() -> float:
	return float(Time.get_ticks_msec() - _popup_born_msec) / 1000.0


func _popup_life() -> float:
	if Settings.reduce_motion:
		return POPUP_STATIC_SEC + POPUP_STATIC_FADE
	return POPUP_SEC


func _animating() -> bool:
	var now := Time.get_ticks_msec()
	if _popup_text != "" and _popup_age() < _popup_life():
		return true
	if is_counter_visible() and not Settings.reduce_motion:
		if float(now - _shown_since_msec) / 1000.0 < FADE_IN_SEC:
			return true
		if float(now - _pulse_msec) / 1000.0 < PULSE_SEC:
			return true
	return false


func _process(_delta: float) -> void:
	if _animating():
		queue_redraw()
	elif _popup_text != "" and _popup_age() >= _popup_life():
		_popup_text = ""
		queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	if is_counter_visible():
		_draw_counter(now)
	if _popup_text != "":
		_draw_popup()


func _draw_counter(now: int) -> void:
	var t := tier(_combo)
	var size := font_size_for(t)
	var col := color_for(t)
	var a := 1.0
	var scale_f := 1.0
	if not Settings.reduce_motion:
		var since := float(now - _shown_since_msec) / 1000.0
		a = clampf(since / FADE_IN_SEC, 0.0, 1.0)
		var p := float(now - _pulse_msec) / 1000.0
		if p < PULSE_SEC:
			scale_f = 1.0 + 0.1 * sin(PI * p / PULSE_SEC)
	var font := Palette.bold()
	var text := number_text()
	var rx := right_x()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	# Scale about the number's right baseline so the box does not shift.
	var pivot := Vector2(rx, NUMBER_BASE_Y)
	draw_set_transform(pivot - pivot * scale_f, 0.0, Vector2(scale_f, scale_f))
	var pos := Vector2(rx - w, NUMBER_BASE_Y)
	if t >= 3:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Palette.alpha(Palette.ACCENT, 0.3 * a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.alpha(col, a))
	if t >= 4:
		draw_rect(Rect2(rx - w, NUMBER_BASE_Y + 8.0, w, 2.0), Palette.alpha(Palette.ACCENT, a))
	var cap_font := Palette.font()
	var cw := cap_font.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	draw_string(cap_font, Vector2(rx - cw, CAPTION_BASE_Y), CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.alpha(CAPTION_COLOR, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_popup() -> void:
	var age := _popup_age()
	var a := 1.0
	var rise := 0.0
	if Settings.reduce_motion:
		if age > POPUP_STATIC_SEC:
			a = clampf(1.0 - (age - POPUP_STATIC_SEC) / POPUP_STATIC_FADE, 0.0, 1.0)
	else:
		var k := clampf(age / POPUP_SEC, 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)  # ease-out
		rise = POPUP_RISE * e
		a = 1.0 - k
	if a <= 0.0:
		return
	var font := Palette.bold()
	var size := Palette.SIZE_HEADING
	var text := _popup_text.to_upper()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(right_x() - w, POPUP_BASE_Y - rise)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.alpha(Palette.ACCENT, a))
