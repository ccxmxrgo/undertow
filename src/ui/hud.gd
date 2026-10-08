class_name Hud
extends Control
## HUD bound to HullScore signals (UI-SPEC Gameplay layout). Hull bar 480x24 at (32,32) with a
## 30% notch, right column of depth / combo / multiplier / perfect streak (right-aligned at
## x = 1888, fixed-width boxes), NO-FAIL badge. Colors via Palette only.
## Deviation from the sketch: the HULL caption sits under the bar so everything stays inside
## the 32 px safe margin.
## 01.1-06 recording-frame chrome: off-white captions/values and hull fill (sonar green retired
## for HUD chrome; PERFECT STREAK keeps the accent). Hull critical = red AND a pulsing bar AND
## the "HULL CRITICAL" caption, so it never relies on color alone (the chrome also uses a red).

const BAR_POS := Vector2(32.0, 32.0)
const BAR_SIZE := Vector2(480.0, 24.0)
const CRITICAL_PCT := 30.0
const RIGHT_EDGE := 1888.0
const COL_W := 320.0
const ROW_H := 94.0
const PULSE_SEC := 0.08
const PULSE_SCALE := 1.1
const DAMAGE_FLASH_USEC := 200000
const SHRINK_TAU := 0.05  # ~150 ms to settle
const CRITICAL_PULSE_HZ := 3.0

var hull_max: float = 100.0
var hull_value: Label
var hull_caption: Label
var depth_value: Label
var combo_value: Label
var mult_value: Label
var streak_value: Label

var _score: HullScore
var _hull: float = 100.0
var _shown_hull: float = 100.0
var _flash_until: int = 0
var _no_fail: bool = false
var _autoplay: bool = false
var _pulses: Dictionary = {}  # Label -> Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	hull_value = _make_label(Vector2(BAR_POS.x + BAR_SIZE.x + Palette.SP_MD, BAR_POS.y - 8.0), Vector2(160.0, 48.0), "", true, HORIZONTAL_ALIGNMENT_LEFT)
	hull_caption = _make_label(Vector2(BAR_POS.x, BAR_POS.y + BAR_SIZE.y + Palette.SP_XS), Vector2(BAR_SIZE.x, 30.0), "HULL", false, HORIZONTAL_ALIGNMENT_LEFT)
	var x := RIGHT_EDGE - COL_W
	_make_caption(Vector2(x, 32.0), "DEPTH")
	depth_value = _make_label(Vector2(x, 56.0), Vector2(COL_W, 48.0), "0 M", true, HORIZONTAL_ALIGNMENT_RIGHT)
	_make_caption(Vector2(x, 32.0 + ROW_H), "COMBO")
	combo_value = _make_label(Vector2(x, 56.0 + ROW_H), Vector2(COL_W, 48.0), "0", true, HORIZONTAL_ALIGNMENT_RIGHT)
	_make_caption(Vector2(x, 32.0 + ROW_H * 2.0), "MULTIPLIER")
	mult_value = _make_label(Vector2(x, 56.0 + ROW_H * 2.0), Vector2(COL_W, 48.0), "x1", true, HORIZONTAL_ALIGNMENT_RIGHT)
	_make_caption(Vector2(x, 32.0 + ROW_H * 3.0), "PERFECT STREAK")
	streak_value = _make_label(Vector2(x, 56.0 + ROW_H * 3.0), Vector2(COL_W, 48.0), "0", true, HORIZONTAL_ALIGNMENT_RIGHT)
	streak_value.add_theme_color_override("font_color", Palette.ACCENT)
	for l in [combo_value, mult_value, streak_value]:
		l.pivot_offset = Vector2(COL_W, 24.0)
	_refresh_all()


## Subscribe to a HullScore. Safe to call before or after the node enters the tree.
func bind(score: HullScore, p_hull_max: float = 100.0) -> void:
	_score = score
	hull_max = p_hull_max
	_hull = score.hull
	_shown_hull = score.hull
	_no_fail = score.no_fail or Settings.no_fail
	score.hull_changed.connect(_on_hull_changed)
	score.combo_changed.connect(_on_combo_changed)
	score.multiplier_changed.connect(_on_multiplier_changed)
	score.streak_changed.connect(_on_streak_changed)
	score.score_changed.connect(_on_score_changed)
	if is_node_ready():
		_refresh_all()


## Outlined AUTOPLAY badge, same style as NO-FAIL (UI-SPEC copy "AUTOPLAY").
func set_autoplay(on: bool) -> void:
	_autoplay = on
	queue_redraw()


func is_autoplay_shown() -> bool:
	return _autoplay


func is_critical() -> bool:
	return _hull / hull_max * 100.0 <= CRITICAL_PCT


func _make_label(pos: Vector2, sz: Vector2, text: String, heading: bool, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if heading:
		l.theme_type_variation = &"HeadingLabel"
		l.add_theme_color_override("font_color", Palette.REC_TEXT)
	else:
		l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		l.add_theme_color_override("font_color", Palette.alpha(Palette.REC_TEXT, 0.7))
	add_child(l)
	return l


func _make_caption(pos: Vector2, text: String) -> void:
	_make_label(pos, Vector2(COL_W, 30.0), text, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _refresh_all() -> void:
	if _score == null:
		_update_hull_text()
		return
	depth_value.text = depth_text(_score.depth())
	combo_value.text = str(_score.combo)
	mult_value.text = "x%d" % _score.multiplier()
	streak_value.text = str(_score.perfect_streak)
	_update_hull_text()


func depth_text(meters: float) -> String:
	var s := str(int(meters))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "%s%s M" % [s, out]


func _update_hull_text() -> void:
	hull_value.text = "%d%%" % int(round(_hull / hull_max * 100.0))
	hull_caption.text = "HULL CRITICAL" if is_critical() else "HULL"
	hull_caption.add_theme_color_override("font_color", Palette.DESTRUCTIVE if is_critical() else Palette.alpha(Palette.REC_TEXT, 0.7))
	hull_value.add_theme_color_override("font_color", Palette.DESTRUCTIVE if is_critical() else Palette.REC_TEXT)


func _on_hull_changed(value: float, delta: float) -> void:
	_hull = value
	if delta < 0.0:
		_flash_until = Time.get_ticks_usec() + DAMAGE_FLASH_USEC
	_update_hull_text()
	queue_redraw()


func _on_combo_changed(value: int) -> void:
	combo_value.text = str(value)
	_pulse(combo_value)


func _on_multiplier_changed(value: int) -> void:
	mult_value.text = "x%d" % value
	_pulse(mult_value)


func _on_streak_changed(value: int) -> void:
	streak_value.text = str(value)
	_pulse(streak_value)


func _on_score_changed(_value: int) -> void:
	if _score != null:
		depth_value.text = depth_text(_score.depth())  # depth never pulses


func _pulse(l: Label) -> void:
	if Settings.reduce_motion or not is_inside_tree():
		return
	if _pulses.has(l) and is_instance_valid(_pulses[l]):
		(_pulses[l] as Tween).kill()
	l.scale = Vector2(PULSE_SCALE, PULSE_SCALE)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, PULSE_SEC).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_pulses[l] = tw


func _process(delta: float) -> void:
	var prev := _shown_hull
	# Ease-out shrink (about 150 ms); growth snaps.
	if _shown_hull > _hull:
		_shown_hull = lerpf(_hull, _shown_hull, exp(-delta / SHRINK_TAU))
		if absf(_shown_hull - _hull) < 0.05:
			_shown_hull = _hull
	else:
		_shown_hull = _hull
	if _shown_hull != prev or Time.get_ticks_usec() < _flash_until or critical_pulsing():
		queue_redraw()


## The hull bar pulses while critical (shape/motion cue in addition to color and caption).
func critical_pulsing() -> bool:
	return is_critical() and not Settings.reduce_motion


## Hull fill alpha: 1.0 normally; 0.45..1.0 at CRITICAL_PULSE_HZ while critical.
func hull_fill_alpha(now_usec: int) -> float:
	if not critical_pulsing():
		return 1.0
	var ph := float(now_usec) / 1000000.0 * CRITICAL_PULSE_HZ * TAU
	return 0.725 + 0.275 * cos(ph)


func _draw() -> void:
	var track := Rect2(BAR_POS, BAR_SIZE)
	draw_rect(track, Palette.PANEL)
	var pct := clampf(_shown_hull / hull_max, 0.0, 1.0)
	var fill_col := Palette.DESTRUCTIVE if is_critical() else Palette.REC_TEXT
	fill_col.a = hull_fill_alpha(Time.get_ticks_usec())
	if pct > 0.0:
		draw_rect(Rect2(BAR_POS + Vector2(2.0, 2.0), Vector2((BAR_SIZE.x - 4.0) * pct, BAR_SIZE.y - 4.0)), fill_col)
	var now := Time.get_ticks_usec()
	if now < _flash_until:
		var a := float(_flash_until - now) / DAMAGE_FLASH_USEC
		draw_rect(track, Palette.alpha(Palette.DESTRUCTIVE, 0.7 * a))
	draw_rect(track, Palette.alpha(Palette.REC_TEXT, 0.5), false, 2.0)
	# 30% notch: a tick through the bar so the critical zone has a shape cue.
	var nx := BAR_POS.x + BAR_SIZE.x * CRITICAL_PCT / 100.0
	draw_line(Vector2(nx, BAR_POS.y - 6.0), Vector2(nx, BAR_POS.y + BAR_SIZE.y + 6.0), Palette.REC_RED, 2.0)
	if _no_fail:
		var bx := BAR_POS.x
		var by := BAR_POS.y + BAR_SIZE.y + 38.0
		var r := Rect2(bx, by, 144.0, 32.0)
		draw_rect(r, Palette.REC_TEXT, false, 2.0)
		draw_string(Palette.font(), Vector2(bx, by + 22.0), "NO-FAIL", HORIZONTAL_ALIGNMENT_CENTER, 144.0, Palette.SIZE_LABEL, Palette.REC_TEXT)
	if _autoplay:
		var ax := BAR_POS.x + (144.0 + Palette.SP_MD if _no_fail else 0.0)
		var ay := BAR_POS.y + BAR_SIZE.y + 38.0
		draw_rect(Rect2(ax, ay, 144.0, 32.0), Palette.REC_TEXT, false, 2.0)
		draw_string(Palette.font(), Vector2(ax, ay + 22.0), "AUTOPLAY", HORIZONTAL_ALIGNMENT_CENTER, 144.0, Palette.SIZE_LABEL, Palette.REC_TEXT)
