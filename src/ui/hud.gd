class_name Hud
extends Control
## Minimal floating HUD (01.2 D-07). Depth + small multiplier/perfect-streak column right of the
## board, thin hull arc under it, badges below the column. Nothing persistent in the outer 32 px.
## The streak number itself is drawn by StreakCounter; combo_value/hull_value stay as hidden live
## labels so the label API (tests/harness) keeps working.
## Hull critical = red AND a pulsing arc AND the "HULL CRITICAL" caption AND a 30% tick, so it
## never relies on colour alone.

const CRITICAL_PCT := 30.0
const COL_X := 1530.0
const VAL_X := 1694.0
const ARC_CENTER := Vector2(960.0, 428.0)
const ARC_RADIUS := 612.0
const ARC_LEFT := 2.028
const ARC_RIGHT := 1.114
const ARC_WIDTH := 4.0
const CAPTION_COLOR := Color("8A93AD")
const DEPTH_COLOR := Color("05D9E8")
const BADGE_COLOR := Color("8FD98A")
const BADGE_Y_FIRST := 861.0
const BADGE_Y_SECOND := 905.0
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
	hull_value = _make_label(Vector2(COL_X, 940.0), Vector2(160.0, 48.0), "", true, HORIZONTAL_ALIGNMENT_LEFT)
	hull_value.visible = false
	hull_caption = _make_label(Vector2(760.0, 1006.0), Vector2(400.0, 30.0), "", false, HORIZONTAL_ALIGNMENT_CENTER)
	hull_caption.visible = false
	depth_value = _make_label(Vector2(COL_X, 671.0), Vector2(320.0, 48.0), "0 M", true, HORIZONTAL_ALIGNMENT_LEFT)
	depth_value.add_theme_color_override("font_color", DEPTH_COLOR)
	_make_caption(Vector2(COL_X, 723.0), "DEPTH", 320.0)
	combo_value = _make_label(Vector2(COL_X, 700.0), Vector2(120.0, 48.0), "0", true, HORIZONTAL_ALIGNMENT_LEFT)
	combo_value.visible = false
	_make_caption(Vector2(COL_X, 763.0), "MULTIPLIER", 164.0)
	mult_value = _make_label(Vector2(VAL_X, 763.0), Vector2(120.0, 30.0), "x1", false, HORIZONTAL_ALIGNMENT_LEFT)
	mult_value.add_theme_color_override("font_color", Palette.REC_TEXT)
	_make_caption(Vector2(COL_X, 795.0), "PERFECT STREAK", 164.0)
	streak_value = _make_label(Vector2(VAL_X, 795.0), Vector2(120.0, 30.0), "0", false, HORIZONTAL_ALIGNMENT_LEFT)
	streak_value.add_theme_color_override("font_color", Palette.ACCENT)
	for l in [combo_value, mult_value, streak_value]:
		l.pivot_offset = Vector2(0.0, 15.0)
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
		l.add_theme_color_override("font_color", CAPTION_COLOR)
	add_child(l)
	return l


func _make_caption(pos: Vector2, text: String, w: float) -> void:
	_make_label(pos, Vector2(w, 30.0), text, false, HORIZONTAL_ALIGNMENT_LEFT)


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
	hull_caption.text = "HULL CRITICAL" if is_critical() else ""
	hull_caption.visible = is_critical()
	hull_caption.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
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


## Angle on the hull arc for a hull percentage: 0% is the left end, 100% the right end.
static func hull_arc_angle(pct: float) -> float:
	return ARC_LEFT - clampf(pct, 0.0, 100.0) / 100.0 * (ARC_LEFT - ARC_RIGHT)


func _draw() -> void:
	draw_arc(ARC_CENTER, ARC_RADIUS, ARC_RIGHT, ARC_LEFT, 96, Color(0.909, 0.902, 0.941, 0.25), ARC_WIDTH, true)
	var pct := clampf(_shown_hull / hull_max, 0.0, 1.0)
	var fill_col := Palette.DESTRUCTIVE if is_critical() else Palette.ACCENT
	fill_col.a = hull_fill_alpha(Time.get_ticks_usec())
	if pct > 0.0:
		draw_arc(ARC_CENTER, ARC_RADIUS, hull_arc_angle(pct * 100.0), ARC_LEFT, 96, fill_col, ARC_WIDTH, true)
	var now := Time.get_ticks_usec()
	if now < _flash_until:
		var a := float(_flash_until - now) / DAMAGE_FLASH_USEC
		draw_arc(ARC_CENTER, ARC_RADIUS, ARC_RIGHT, ARC_LEFT, 96, Palette.alpha(Palette.DESTRUCTIVE, 0.7 * a), ARC_WIDTH, true)
	# 30% tick across the arc: shape cue for the critical zone.
	var ang := hull_arc_angle(CRITICAL_PCT)
	var dir := Vector2(cos(ang), sin(ang))
	var mid := ARC_CENTER + dir * ARC_RADIUS
	draw_line(mid - dir * 6.0, mid + dir * 6.0, Palette.DESTRUCTIVE, 2.0)
	var row := 0
	if _no_fail:
		_draw_badge("NO-FAIL", BADGE_Y_FIRST)
		row = 1
	if _autoplay:
		_draw_badge("AUTOPLAY", BADGE_Y_FIRST if row == 0 else BADGE_Y_SECOND)


func _draw_badge(text: String, y: float) -> void:
	draw_rect(Rect2(COL_X, y, 144.0, 32.0), BADGE_COLOR, false, 2.0)
	draw_string(Palette.font(), Vector2(COL_X, y + 22.0), text, HORIZONTAL_ALIGNMENT_CENTER, 144.0, Palette.SIZE_LABEL, Palette.REC_TEXT)
