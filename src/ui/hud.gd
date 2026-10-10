class_name Hud
extends Control
## Cockpit HUD (UI-SPEC 7.3). Full-screen canvas over the cockpit frame.
## Left console (02.2-12): MultiplierRing, PERFECT caption + perfect streak value, empty
## TorpedoSocket (the big streak numeral is StreakCounter).
## Right console (02.2-13): DEPTH caption + Heading 40 SONAR depth in a fixed 6-char box with a
## " M" unit, ACCURACY caption + live D-08 accuracy ("--.-%" in TEXT_LO before the first judged
## note), NO-FAIL / AUTOPLAY mode chips, and the Bathymeter.
## Board-attached: the segmented HullArc and the "HULL CRITICAL" caption, the top ProgressTrack
## (title, section name, ticks, time remaining) and the timed SectionBanner (02.2-14).
## combo_value/hull_value/depth_value/mult_value/streak_value stay as hidden live labels so the
## label API (tests/harness) keeps working; hull_caption is the visible critical caption.
## Hull critical = red AND a pulsing arc AND cracks AND the "HULL CRITICAL" caption AND a 30%
## tick, so it never relies on colour alone. Read-only: only listens to HullScore/judge signals.

const CRITICAL_PCT := HullArc.CRITICAL_PCT
const ARC_CENTER := HullArc.CENTER
const ARC_RADIUS := HullArc.RADIUS
const ARC_LEFT := HullArc.ANGLE_LEFT
const ARC_RIGHT := HullArc.ANGLE_RIGHT
const DAMAGE_FLASH_USEC := 200000
const SHRINK_TAU := HullArc.SHRINK_TAU
const CRITICAL_PULSE_HZ := HullArc.PULSE_HZ
const PERFECT_CAPTION := "PERFECT"
const PERFECT_CAPTION_POS := Vector2(264.0, 852.0)
const PERFECT_BASE_Y := 896.0
const PERFECT_LEFT_X := 264.0
const PERFECT_RIGHT_X := 356.0  # 4-digit box 264..356
## Right console (content x 1552..1872).
const RC_X := 1552.0
const DEPTH_CAPTION := "DEPTH"
const DEPTH_CAPTION_Y := 644.0
const DEPTH_BASE_Y := 692.0
const DEPTH_MAX_TEXT := "99,999"  # fixed 6-char box
const DEPTH_UNIT := " M"
const ACCURACY_CAPTION := "ACCURACY"
const ACCURACY_CAPTION_Y := 740.0
const ACCURACY_BASE_Y := 788.0
const ACCURACY_MAX_TEXT := "100.0%"
const CHIP_NO_FAIL := "NO-FAIL"
const CHIP_AUTOPLAY := "AUTOPLAY"
const CHIP_NO_FAIL_Y := 824.0
const CHIP_AUTOPLAY_Y := 864.0
## HULL CRITICAL caption: centred x 960, baseline 1028, 3 px KEYLINE outline.
const CAPTION_CENTER_X := 960.0
const CAPTION_BASE_Y := 1028.0
const CAPTION_W := 400.0
const CAPTION_OUTLINE := 3

var hull_max: float = 100.0
var hull_value: Label
var hull_caption: Label
var depth_value: Label
var combo_value: Label
var mult_value: Label
var streak_value: Label
var accuracy_label: Label
var multiplier_ring: MultiplierRing
var torpedo_socket: TorpedoSocket
var bathymeter: Bathymeter
var hull_arc: HullArc
var progress_track: ProgressTrack
var section_banner: SectionBanner

var _score: HullScore
var _hull: float = 100.0
var _no_fail: bool = false
var _autoplay: bool = false
var _perfect: int = 0
var _depth: float = 0.0
var _scale_est: float = 0.0
var _best: float = -1.0
var _song_chart: ChartData
var _song_conductor: Conductor


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	# Hidden live labels (test/harness API). The visible readouts are drawn or styled below.
	hull_value = _hidden_label("")
	combo_value = _hidden_label("0")
	mult_value = _hidden_label("x1")
	streak_value = _hidden_label("0")
	depth_value = _hidden_label("0 M")
	hull_caption = _make_hull_caption()
	accuracy_label = _make_accuracy_label()
	progress_track = ProgressTrack.new()
	progress_track.name = "ProgressTrack"
	add_child(progress_track)
	section_banner = SectionBanner.new()
	section_banner.name = "SectionBanner"
	add_child(section_banner)
	if _song_chart != null:
		progress_track.setup(_song_chart, _song_conductor)
		section_banner.setup(_song_chart, _song_conductor)
	hull_arc = HullArc.new()
	hull_arc.name = "HullArc"
	add_child(hull_arc)
	multiplier_ring = MultiplierRing.new()
	multiplier_ring.name = "MultiplierRing"
	add_child(multiplier_ring)
	torpedo_socket = TorpedoSocket.new()
	torpedo_socket.name = "TorpedoSocket"
	add_child(torpedo_socket)
	bathymeter = Bathymeter.new()
	bathymeter.name = "Bathymeter"
	add_child(bathymeter)
	bathymeter.setup(_scale_est, _best)
	if _score != null:
		multiplier_ring.bind(_score)
	_refresh_all()


## Subscribe to a HullScore. Safe to call before or after the node enters the tree.
func bind(score: HullScore, p_hull_max: float = 100.0) -> void:
	_score = score
	hull_max = p_hull_max
	_hull = score.hull
	_no_fail = score.no_fail or Settings.no_fail
	score.hull_changed.connect(_on_hull_changed)
	score.combo_changed.connect(_on_combo_changed)
	score.multiplier_changed.connect(_on_multiplier_changed)
	score.streak_changed.connect(_on_streak_changed)
	score.score_changed.connect(_on_score_changed)
	if multiplier_ring != null:
		multiplier_ring.bind(score)
	if is_node_ready():
		_refresh_all()


## Song for the progress track and section banner (UI-SPEC 4.8, 4.9). Both only read
## conductor.song_time(). Safe before or after the node enters the tree.
func setup_song(chart: ChartData, conductor: Conductor) -> void:
	_song_chart = chart
	_song_conductor = conductor
	if progress_track != null:
		progress_track.setup(chart, conductor)
		section_banner.setup(chart, conductor)


## Judge listener (connected by Gameplay after HullScore): recomputes the live accuracy from
## the bound score's counts (D-08).
func on_judged(_lane: int, _idx: int, _judgment: int, _err: float) -> void:
	_update_accuracy()


## All-Perfect depth estimate for this chart (Bathymeter.estimate_max_depth).
func set_depth_scale(estimate_m: float) -> void:
	_scale_est = estimate_m
	if bathymeter != null:
		bathymeter.setup(_scale_est, _best)
		bathymeter.set_depth(_depth)


## Saved best depth for this chart (< 0 = no record): the bathymeter's gold BEST marker.
func set_record(best_depth: float) -> void:
	_best = best_depth
	if bathymeter != null:
		bathymeter.setup(_scale_est, _best)
		bathymeter.set_depth(_depth)


## AUTOPLAY mode chip (UI-SPEC copy "AUTOPLAY").
func set_autoplay(on: bool) -> void:
	_autoplay = on
	queue_redraw()


func is_autoplay_shown() -> bool:
	return _autoplay


func is_critical() -> bool:
	return _hull / hull_max * 100.0 <= CRITICAL_PCT


func _hidden_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_hull_caption() -> Label:
	var l := Label.new()
	var f := Palette.bold()
	var fs := Palette.SIZE_LABEL
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Palette.WARNING_RED)
	l.add_theme_color_override("font_outline_color", Palette.KEYLINE)
	l.add_theme_constant_override("outline_size", CAPTION_OUTLINE)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(CAPTION_CENTER_X - CAPTION_W * 0.5, CAPTION_BASE_Y - f.get_ascent(fs))
	l.size = Vector2(CAPTION_W, f.get_height(fs))
	l.visible = false
	add_child(l)
	return l


func _make_accuracy_label() -> Label:
	var l := Label.new()
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Palette.TEXT_LO)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = RunStats.accuracy_text(-1.0)
	var w := f.get_string_size(ACCURACY_MAX_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	l.position = Vector2(RC_X, ACCURACY_BASE_Y - f.get_ascent(fs))
	l.size = Vector2(ceilf(w), f.get_height(fs))
	add_child(l)
	return l


## Baseline y of the HULL CRITICAL caption.
func hull_caption_baseline() -> float:
	var f := hull_caption.get_theme_font("font")
	return hull_caption.position.y + f.get_ascent(hull_caption.get_theme_font_size("font_size"))


func _refresh_all() -> void:
	if _score == null:
		_update_hull_text()
		_update_accuracy()
		return
	_depth = _score.depth()
	depth_value.text = depth_text(_depth)
	combo_value.text = str(_score.combo)
	mult_value.text = "x%d" % _score.multiplier()
	streak_value.text = str(_score.perfect_streak)
	_perfect = _score.perfect_streak
	if hull_arc != null:
		hull_arc.reset(_hull / hull_max * 100.0)
	if bathymeter != null:
		bathymeter.set_depth(_depth)
	_update_hull_text()
	_update_accuracy()
	queue_redraw()


func depth_text(meters: float) -> String:
	var s := str(int(meters))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "%s%s M" % [s, out]


## Visible depth numeral, e.g. "1,240" (the unit " M" is drawn after the fixed box).
func depth_readout_text() -> String:
	return Palette.fmt_depth(int(_depth))


## Fixed 6-char depth box (x 1552, baseline 692): the same for 0 and 99,999 (S-4).
func depth_box() -> Rect2:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var w := ceilf(f.get_string_size(DEPTH_MAX_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return Rect2(RC_X, DEPTH_BASE_Y - f.get_ascent(fs), w, f.get_height(fs))


func depth_unit_x() -> float:
	return depth_box().end.x


## Visible mode chips: {text: Rect2}; NO-FAIL at y 824..856, AUTOPLAY at 864..896.
func chip_rects() -> Dictionary:
	var out := {}
	if _no_fail:
		out[CHIP_NO_FAIL] = Rect2(RC_X, CHIP_NO_FAIL_Y, UiKit.chip_width(CHIP_NO_FAIL), UiKit.CHIP_H)
	if _autoplay:
		out[CHIP_AUTOPLAY] = Rect2(RC_X, CHIP_AUTOPLAY_Y, UiKit.chip_width(CHIP_AUTOPLAY), UiKit.CHIP_H)
	return out


func _update_accuracy() -> void:
	if accuracy_label == null:
		return
	var acc := -1.0
	if _score != null:
		acc = RunStats.accuracy(_score.perfect_count, _score.good_count, _score.miss_count)
	accuracy_label.text = RunStats.accuracy_text(acc)
	accuracy_label.add_theme_color_override("font_color", Palette.TEXT_LO if acc < 0.0 else Palette.TEXT_HI)


func _update_hull_text() -> void:
	hull_value.text = "%d%%" % int(round(_hull / hull_max * 100.0))
	hull_caption.text = "HULL CRITICAL" if is_critical() else ""
	hull_caption.visible = is_critical()
	hull_value.add_theme_color_override("font_color", Palette.WARNING_RED if is_critical() else Palette.TEXT_HI)


func _on_hull_changed(value: float, delta: float) -> void:
	_hull = value
	if hull_arc != null:
		hull_arc.set_hull(value / hull_max * 100.0, delta / hull_max * 100.0)
	_update_hull_text()


func _on_combo_changed(value: int) -> void:
	combo_value.text = str(value)


func _on_multiplier_changed(value: int) -> void:
	mult_value.text = "x%d" % value


func _on_streak_changed(value: int) -> void:
	streak_value.text = str(value)
	_perfect = value
	queue_redraw()


func _on_score_changed(_value: int) -> void:
	if _score == null:
		return
	_depth = _score.depth()
	depth_value.text = depth_text(_depth)  # depth never pulses
	if bathymeter != null:
		bathymeter.set_depth(_depth)
	queue_redraw()


## The hull arc pulses while critical (shape/motion cue in addition to colour and caption).
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
	return HullArc.angle_for(pct)


func _draw() -> void:
	_draw_perfect()
	_draw_caption(Vector2(RC_X, DEPTH_CAPTION_Y), DEPTH_CAPTION)
	_draw_depth()
	_draw_caption(Vector2(RC_X, ACCURACY_CAPTION_Y), ACCURACY_CAPTION)
	var chips := chip_rects()
	for text in chips:
		UiKit.draw_chip(self, chips[text], text, "mode")


func _draw_caption(pos: Vector2, text: String) -> void:
	draw_string(Palette.font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT_LO)


func _caption_rect(pos: Vector2, text: String) -> Rect2:
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Rect2(pos.x, pos.y - f.get_ascent(fs), w, f.get_height(fs))


## Depth numeral right-aligned in the fixed 6-char box, then " M" in Label 20 TEXT_LO.
func _draw_depth() -> void:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var box := depth_box()
	var text := depth_readout_text()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(box.end.x - w, DEPTH_BASE_Y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SONAR)
	draw_string(Palette.font(), Vector2(depth_unit_x(), DEPTH_BASE_Y), DEPTH_UNIT, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_LABEL, Palette.TEXT_LO)


func _unit_rect() -> Rect2:
	return _caption_rect(Vector2(depth_unit_x(), DEPTH_BASE_Y), DEPTH_UNIT)


func _perfect_box() -> Rect2:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	return Rect2(PERFECT_LEFT_X, PERFECT_BASE_Y - f.get_ascent(fs), PERFECT_RIGHT_X - PERFECT_LEFT_X, f.get_height(fs))


## Global-space polygons of everything Hud draws itself (W4 keep-out contract for full-screen
## canvases): captions, readouts and chips. The hull arc and HULL CRITICAL are allow-listed
## board elements and are not included.
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var rects: Array[Rect2] = [
		_caption_rect(PERFECT_CAPTION_POS, PERFECT_CAPTION), _perfect_box(),
		_caption_rect(Vector2(RC_X, DEPTH_CAPTION_Y), DEPTH_CAPTION), depth_box(), _unit_rect(),
		_caption_rect(Vector2(RC_X, ACCURACY_CAPTION_Y), ACCURACY_CAPTION),
		Rect2(accuracy_label.position, accuracy_label.size),
	]
	var chips := chip_rects()
	for text in chips:
		rects.append(chips[text])
	var out: Array[PackedVector2Array] = []
	for r in rects:
		out.append(PackedVector2Array([
			xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)]))
	return out


## Left console perfect streak (UI-SPEC 7.3): caption at (264, 852), Heading 40 Oxanium
## SONAR_PALE value right-aligned in the 4-digit box 264..356, baseline 896.
func _draw_perfect() -> void:
	_draw_caption(PERFECT_CAPTION_POS, PERFECT_CAPTION)
	var f := Palette.display_font()
	var text := perfect_text()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_HEADING).x
	draw_string(f, Vector2(PERFECT_RIGHT_X - w, PERFECT_BASE_Y), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_HEADING, Palette.SONAR_PALE)


func perfect_text() -> String:
	return str(_perfect)
