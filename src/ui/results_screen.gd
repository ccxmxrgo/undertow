class_name ResultsScreen
extends Control
## "DIVE COMPLETE" results (02.2 UI-SPEC section 8, 4.13; VIS-05, D-08, D-16). Full-screen and
## opaque: the calm AbyssBackdrop with ABYSS_900 55% over it, so nothing of the frozen board shows.
## Layout at the 1920x1080 base:
##   header      x 96..1824, y 64..176: DIVE COMPLETE, title, artist + difficulty chip; on the right
##               the NOT RECORDED chip, flag chips and the kept "Not recorded..." sentence
##   grade panel x 96..576, y 208..688: GRADE, GradeEmblem, ACCURACY (reward brackets on a record)
##   stats panel x 608..1248: DEPTH + NEW RECORD chip + previous best, MAX COMBO / FINAL HULL,
##               PERFECT / GOOD / MISS rows with proportional bars and counts
##   timing panel x 1280..1824: TIMING caption + TimingHistogram (UI-SPEC 4.12) of run_info.offsets
##   buttons     y 752..816: Retry Dive (primary, initial focus), Song Select, Back to Menu; every
##               direction wraps within the three; Esc / B = Back to Menu
## Public API kept for tests and the harness: retry_button, menu_button, flags, rows, record_banner,
## note_label, retry_pressed, menu_pressed. Added: song_select_button, song_select_pressed,
## grade_letter, accuracy_text, grade_emblem, header_chips, bar_widths. Plan 16: histogram,
## panel_groups, entrance_running(), skip_entrance(), apply_entrance(t), bar_fill(i).
## Entrance (UI-SPEC 8, one Tween over ENTRANCE_SEC <= 0.9 s): the grade, stats and timing panels
## fade + rise 16 px (DUR_BASE, STAGGER_RESULTS apart); the grade pops at EMBLEM_DELAY; the NEW
## RECORD chip pops after it; the judgment bars fill (DUR_SLOW, 60 ms stagger) and the histogram
## grows from FILL_AT. Any key / joypad / mouse button / action press while it runs jumps to the
## final state and is consumed (never activates a button). Reduce motion: fades only.

signal retry_pressed
signal menu_pressed
signal song_select_pressed

const PAD_X := 96.0  # 3xl + xl
const RIGHT_X := 1824.0
const GRADE_RECT := Rect2(96.0, 208.0, 480.0, 480.0)
const STATS_RECT := Rect2(608.0, 208.0, 640.0, 480.0)
const TIMING_RECT := Rect2(1280.0, 208.0, 544.0, 480.0)
const EMBLEM_POS := Vector2(224.0, 280.0)
const BUTTON_Y := 752.0
const BUTTON_W := 400.0
const BUTTON_H := 64.0
const BUTTON_X: Array[float] = [96.0, 520.0, 944.0]
const HINT := "ENTER SELECT  ·  ESC BACK TO MENU"
const NOT_RECORDED_TEXT := "Not recorded. Practice, Autoplay and No-Fail dives do not set records."
const TITLE_MAX_W := 1200.0
const SHADE_ALPHA := 0.55
const CAPTION_SPACING := 2
const HEAD_CAPTION_SPACING := 4
const DIVIDER_ALPHA := 0.35
const BRACKET_ALPHA := 0.8
const HULL_CRITICAL := 30
## Judgment bars (UI-SPEC 8): x 768..1120, 16 px tall, track ABYSS_500 60%.
const BAR_X := 768.0
const BAR_MAX := 352.0
const BAR_H := 16.0
const TRACK_ALPHA := 0.6
const ROW_BASES: Array[float] = [552.0, 600.0, 648.0]
const COUNT_RIGHT := 1216.0
const CHIP_GAP := 8.0
const EMBLEM_DELAY := 0.2
const ACCURACY_CAPTION_Y := 532.0
## Entrance timeline (seconds from the screen appearing).
const PANEL_RISE := 16.0
const FILL_AT := 0.32
const RECORD_AT := EMBLEM_DELAY + Palette.DUR_SLOW
const ENTRANCE_SEC := FILL_AT + TimingHistogram.GROW_SEC  # 0.89 s, the longest track

var retry_button: Button
var song_select_button: Button
var menu_button: Button
## Flag texts shown, e.g. "NO-FAIL USED", "AUTOPLAY USED", "PRACTICE DIVE".
var flags: Array[String] = []
## Header chip texts in display order (difficulty, flags, NOT RECORDED).
var header_chips: Array[String] = []
## [label, value text] pairs (data view of the stats, kept for the harness).
var rows: Array[Array] = []
## NEW RECORD chip label (null unless the run set a record).
var record_banner: Label
## The kept "Not recorded..." sentence for Practice / Autoplay / No-Fail runs (null otherwise).
var note_label: Label
var title_label: Label
var previous_label: Label
var hull_label: Label
var grade_emblem: GradeEmblem
## D-08 grade letter ("-" when nothing was judged) and accuracy text ("--.-%").
var grade_letter: String = "-"
var accuracy_text: String = "--.-%"
## Final widths of the PERFECT / GOOD / MISS bars (352 * count / judged).
var bar_widths: Array[float] = [0.0, 0.0, 0.0]
## "reward" on a new record (gold brackets on the grade panel), else "default".
var grade_panel_variant: String = "default"
var histogram: TimingHistogram
## The screen's focus marker (UI-SPEC 4.3, one per screen; added in 02.2-24).
var focus_marker: FocusMarker
## Grade, stats and timing panel groups (each holds its panel and contents; animated together).
var panel_groups: Array[Control] = []

var _backdrop: AbyssBackdrop
var _layout: Control
var _caption_font: FontVariation
var _head_caption_font: FontVariation
var _into: Control
var _bar_nodes: Array[Control] = []
var _bar_k: Array[float] = [1.0, 1.0, 1.0]
var _entrance_tween: Tween
var _entrance_running: bool = false
var _record_popped: bool = false
var _record_tween: Tween
var _reduce: bool = false


## A non-interactive canvas that draws with a callable (panels, chips, bars).
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func setup(score: HullScore, autoplay_used: bool, record_info: Dictionary = {},
		practice: bool = false, run_info: Dictionary = {}) -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_backdrop()
	_layout = Control.new()
	_layout.name = "Layout"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(_layout)
	add_child(_layout)
	_into = _layout
	panel_groups.clear()
	_bar_nodes.clear()
	_bar_k = [1.0, 1.0, 1.0]
	_kill_entrance()
	_entrance_running = false

	var p := score.perfect_count
	var g := score.good_count
	var m := score.miss_count
	var acc := RunStats.accuracy(p, g, m)
	grade_letter = RunStats.grade(acc, m)
	accuracy_text = RunStats.accuracy_text(acc)
	var judged := p + g + m
	bar_widths = [0.0, 0.0, 0.0]
	if judged > 0:
		bar_widths = [BAR_MAX * p / judged, BAR_MAX * g / judged, BAR_MAX * m / judged]

	var is_record: bool = record_info.get("new_record", false)
	var eligible: bool = record_info.get("eligible", true)
	grade_panel_variant = "reward" if is_record else "default"
	flags.clear()
	if score.no_fail_used:
		flags.append("NO-FAIL USED")
	if autoplay_used:
		flags.append("AUTOPLAY USED")
	if practice:
		flags.append("PRACTICE DIVE")
	var not_recorded := not eligible

	rows = [
		["Depth", "%d m" % int(score.depth())],
		["Max combo", str(score.max_combo)],
		["Perfect", str(p)],
		["Good", str(g)],
		["Miss", str(m)],
		["Final hull", "%d%%" % int(round(score.hull))],
	]
	if is_record:
		var prev: float = record_info.get("previous_depth", -1.0)
		rows.append(["Previous best", "%s m" % Palette.fmt_depth(int(prev)) if prev >= 0.0 else "none"])

	_build_header(run_info, not_recorded)
	_begin_group("GradeGroup")
	_build_grade_panel(is_record)
	_begin_group("StatsGroup")
	_build_stats_panel(score, record_info, is_record, eligible)
	_begin_group("TimingGroup")
	_build_timing_panel(run_info)
	_into = _layout
	_build_buttons()
	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)
	_label("Hint", HINT, _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(PAD_X, 872.0))
	if is_inside_tree():
		_start_animation()
		retry_button.grab_focus()


## True when the screen's composite is fully opaque (the calm backdrop's gradient is opaque).
func backdrop_opaque() -> bool:
	return _backdrop != null and _backdrop.variant == "calm" and _backdrop.visible


# ---- building ---------------------------------------------------------------------------

func _build_backdrop() -> void:
	_backdrop = AbyssBackdrop.new()
	_backdrop.name = "Backdrop"
	_backdrop.variant = "calm"
	UiLayout.fill_rect(_backdrop)
	add_child(_backdrop)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Palette.alpha(Palette.ABYSS_900, SHADE_ALPHA)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(shade)
	add_child(shade)


func _build_header(run_info: Dictionary, not_recorded: bool) -> void:
	var cap := _label("DiveComplete", "DIVE COMPLETE", _head_caption(), Palette.SIZE_LABEL, Palette.SONAR,
		Vector2(PAD_X, 88.0))
	cap.name = "DiveComplete"
	# Right side first: its left edge limits the title width.
	var right_left := RIGHT_X
	header_chips.clear()
	var chip_texts: Array[String] = []
	var chip_variants: Array[String] = []
	for f in flags:
		chip_texts.append(f)
		chip_variants.append("mode")
	if not_recorded:
		chip_texts.append("NOT RECORDED")
		chip_variants.append("muted")
	var x := RIGHT_X
	var placed: Array[Rect2] = []
	for i in range(chip_texts.size() - 1, -1, -1):
		var w := UiKit.chip_width(chip_texts[i], chip_variants[i])
		x -= w
		placed.push_front(Rect2(x, 72.0, w, UiKit.CHIP_H))
		x -= CHIP_GAP
	for i in chip_texts.size():
		_chip(chip_texts[i], chip_variants[i], placed[i])
	if not chip_texts.is_empty():
		right_left = minf(right_left, placed[0].position.x)
	if not_recorded:
		note_label = _label("NotRecorded", NOT_RECORDED_TEXT, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO,
			Vector2(RIGHT_X, 136.0), HORIZONTAL_ALIGNMENT_RIGHT)
		right_left = minf(right_left, note_label.position.x)
	else:
		note_label = null
	# Title (Heading 40, truncated) and artist + difficulty chip.
	var title := str(run_info.get("title", ""))
	var tf := _title_font()
	var max_w := minf(TITLE_MAX_W, right_left - PAD_X - Palette.SP_XL)
	title_label = _label("Title", ProgressTrack.truncate_px(title, tf, Palette.SIZE_HEADING, max_w), tf,
		Palette.SIZE_HEADING, Palette.TEXT_HI, Vector2(PAD_X, 136.0))
	var artist := str(run_info.get("artist", ""))
	var ax := PAD_X
	if artist != "":
		var al := _label("Artist", ProgressTrack.truncate_px(artist, Palette.font(), Palette.SIZE_BODY, TITLE_MAX_W),
			Palette.font(), Palette.SIZE_BODY, Palette.TEXT_MID, Vector2(PAD_X, 172.0))
		ax = al.position.x + al.size.x + Palette.SP_MD
	var diff := str(run_info.get("difficulty", ""))
	if diff != "":
		var dt := diff.to_upper()
		var dw := UiKit.chip_width(dt, "difficulty")
		_chip(dt, "difficulty", Rect2(ax, 148.0, dw, UiKit.CHIP_H), MainMenu.difficulty_lane(diff.to_lower()))


func _build_grade_panel(is_record: bool) -> void:
	var bracket := Palette.REWARD_GOLD if is_record else Palette.alpha(Palette.SONAR, BRACKET_ALPHA)
	_panel("GradePanel", GRADE_RECT, bracket)
	_label("GradeCaption", "GRADE", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(128.0, 248.0))
	grade_emblem = GradeEmblem.new()
	grade_emblem.name = "GradeEmblem"
	grade_emblem.position = EMBLEM_POS
	grade_emblem.set_grade(grade_letter)
	_into.add_child(grade_emblem)
	var cx := GRADE_RECT.get_center().x
	# Baseline 532, not the spec's 520: at 520 the caption's cap height touches the emblem's 3 px
	# bottom edge (y 504). Visual-review fix; the accuracy numeral keeps baseline 616.
	_label("AccuracyCaption", "ACCURACY", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(cx, ACCURACY_CAPTION_Y),
		HORIZONTAL_ALIGNMENT_CENTER)
	_label("Accuracy", accuracy_text, Palette.display_font(), Palette.SIZE_DISPLAY, Palette.TEXT_HI,
		Vector2(cx, 616.0), HORIZONTAL_ALIGNMENT_CENTER)


func _build_stats_panel(score: HullScore, record_info: Dictionary, is_record: bool, eligible: bool) -> void:
	_panel("StatsPanel", STATS_RECT, Palette.alpha(Palette.SONAR, BRACKET_ALPHA))
	var x0 := STATS_RECT.position.x + 32.0
	_label("DepthCaption", "DEPTH", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(x0, 248.0))
	var depth := _label("Depth", Palette.fmt_depth(int(score.depth())), Palette.display_font(),
		Palette.SIZE_DISPLAY, Palette.SONAR, Vector2(x0, 336.0))
	_label("DepthUnit", " M", Palette.display_font(), Palette.SIZE_HEADING, Palette.SONAR,
		Vector2(depth.position.x + depth.size.x, 336.0))
	record_banner = null
	if is_record:
		var w := UiKit.chip_width("NEW RECORD", "reward")
		record_banner = _chip("NEW RECORD", "reward", Rect2(COUNT_RIGHT - w, 224.0, w, UiKit.CHIP_H))
	previous_label = null
	if eligible and not record_info.is_empty():
		var prev: float = record_info.get("previous_depth", -1.0)
		var best: float = record_info.get("best_depth", -1.0)
		var text := ""
		if is_record:
			text = "PREVIOUS BEST %s M" % Palette.fmt_depth(int(prev)) if prev >= 0.0 else "First record for this song."
		elif best >= 0.0:
			text = "PREVIOUS BEST %s M" % Palette.fmt_depth(int(best))
		if text != "":
			# Captions are spaced UPPERCASE; the first-record sentence keeps plain spacing.
			var pf := _caption() if text.begins_with("PREVIOUS") else Palette.font()
			previous_label = _label("PreviousBest", text, pf, Palette.SIZE_LABEL, Palette.TEXT_LO,
				Vector2(x0, 372.0))
	var col2 := 944.0
	_label("ComboCaption", "MAX COMBO", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(x0, 436.0))
	_label("FinalHullCaption", "FINAL HULL", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(col2, 436.0))
	_label("MaxCombo", Palette.fmt_depth(score.max_combo), Palette.display_font(), Palette.SIZE_HEADING,
		Palette.TEXT_HI, Vector2(x0, 484.0))
	var hull := int(round(score.hull))
	hull_label = _label("FinalHull", "%d%%" % hull, Palette.display_font(), Palette.SIZE_HEADING,
		Palette.WARNING_RED if hull <= HULL_CRITICAL else Palette.TEXT_HI, Vector2(col2, 484.0))
	var names: Array[String] = ["PERFECT", "GOOD", "MISS"]
	var colors: Array[Color] = [Palette.SONAR_PALE, Palette.TEXT_MID, Palette.WARNING_RED]
	var counts: Array[int] = [score.perfect_count, score.good_count, score.miss_count]
	for i in 3:
		var base := ROW_BASES[i]
		_label(names[i].capitalize() + "Caption", names[i], _caption(), Palette.SIZE_LABEL, colors[i], Vector2(x0, base))
		_bar(names[i].capitalize() + "Bar", Rect2(BAR_X, base - BAR_H, BAR_MAX, BAR_H), bar_widths[i], colors[i])
		_label(names[i].capitalize() + "Count", Palette.fmt_depth(counts[i]), Palette.font(), Palette.SIZE_BODY,
			Palette.TEXT_HI, Vector2(COUNT_RIGHT, base), HORIZONTAL_ALIGNMENT_RIGHT)
	# Dividers at y 396 and 508.
	for y: float in [396.0, 508.0]:
		var d := ColorRect.new()
		d.color = Palette.alpha(Palette.SONAR, DIVIDER_ALPHA)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.position = Vector2(x0, y - Palette.EDGE * 0.5)
		d.size = Vector2(COUNT_RIGHT - x0, Palette.EDGE)
		_into.add_child(d)


func _build_timing_panel(run_info: Dictionary) -> void:
	_panel("TimingPanel", TIMING_RECT, Palette.alpha(Palette.SONAR, BRACKET_ALPHA))
	_label("TimingCaption", "TIMING", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(1312.0, 248.0))
	histogram = TimingHistogram.new()
	histogram.name = "TimingHistogram"
	var offs: Variant = run_info.get("offsets", PackedFloat32Array())
	var packed := PackedFloat32Array(offs) if (offs is PackedFloat32Array or offs is Array) else PackedFloat32Array()
	histogram.set_offsets(packed, float(run_info.get("perfect_window", -1.0)))
	_into.add_child(histogram)


func _build_buttons() -> void:
	retry_button = UiKit.make_button("Retry Dive", "", "primary", int(BUTTON_H))
	song_select_button = UiKit.make_button("Song Select", "", "default", int(BUTTON_H))
	menu_button = UiKit.make_button("Back to Menu", "", "default", int(BUTTON_H))
	retry_button.name = "RetryDive"
	song_select_button.name = "SongSelect"
	menu_button.name = "BackToMenu"
	retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	song_select_button.pressed.connect(func() -> void: song_select_pressed.emit())
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	var order: Array[Button] = [retry_button, song_select_button, menu_button]
	for i in order.size():
		var b := order[i]
		b.position = Vector2(BUTTON_X[i], BUTTON_Y)
		b.size = Vector2(BUTTON_W, BUTTON_H)
		_layout.add_child(b)
	# Closed focus loop: Right / Down / Tab go to the next button, Left / Up / Shift+Tab to the
	# previous one, wrapping within the three.
	for i in order.size():
		var b := order[i]
		var nxt := b.get_path_to(order[(i + 1) % order.size()])
		var prv := b.get_path_to(order[(i + order.size() - 1) % order.size()])
		b.focus_neighbor_right = nxt
		b.focus_neighbor_bottom = nxt
		b.focus_next = nxt
		b.focus_neighbor_left = prv
		b.focus_neighbor_top = prv
		b.focus_previous = prv


# ---- helpers ----------------------------------------------------------------------------

func _caption() -> Font:
	if _caption_font == null:
		_caption_font = _spaced(Palette.font(), CAPTION_SPACING)
	return _caption_font


func _head_caption() -> Font:
	if _head_caption_font == null:
		_head_caption_font = _spaced(Palette.font(), HEAD_CAPTION_SPACING)
	return _head_caption_font


static func _spaced(base: Font, spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	return fv


## Song titles: the display font (Oxanium, with Palette's fallback chain for non-Latin titles).
static func _title_font() -> Font:
	return Palette.display_font()


## A label whose text baseline sits at `at.y`. `align` LEFT anchors at at.x, RIGHT ends at at.x,
## CENTER centres on at.x. The label is sized to its text so nothing is clipped.
func _label(node_name: String, text: String, font: Font, font_size: int, color: Color, at: Vector2,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var h := font.get_height(font_size)
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	l.position = Vector2(x, at.y - font.get_ascent(font_size))
	l.size = Vector2(ceilf(w), ceilf(h))
	_into.add_child(l)
	return l


func _painter(node_name: String, rect: Rect2, fn: Callable) -> Painter:
	var c := Painter.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size
	c.painter = fn
	_into.add_child(c)
	return c


## Glass panel (UiKit.style_panel) with corner brackets in `bracket`.
func _panel(node_name: String, rect: Rect2, bracket: Color) -> void:
	var sb := UiKit.style_panel("default")
	_painter(node_name, rect, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, bracket))


## A chip box drawn by UiKit.draw_chip; its text is a Label child (returned) so tests can read it.
func _chip(text: String, variant: String, rect: Rect2, lane: int = -1) -> Label:
	if variant != "reward":
		header_chips.append(text)
	var holder := _painter("Chip" + text.capitalize().replace(" ", ""), rect, func(ci: CanvasItem) -> void:
		UiKit.draw_chip(ci, Rect2(Vector2.ZERO, rect.size), "", variant, lane))
	var st := UiKit.chip_style(variant, lane)
	var f := UiKit.chip_font()
	var fs := Palette.SIZE_LABEL
	var l := Label.new()
	l.name = "Text"
	l.text = text.to_upper()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", st.text)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var tx := float(UiKit.CHIP_PAD_X)
	if variant == "difficulty":
		tx += UiKit.CHIP_GLYPH + UiKit.CHIP_GLYPH_GAP
	var base := rect.size.y * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	l.position = Vector2(tx, base - f.get_ascent(fs))
	l.size = Vector2(maxf(rect.size.x - tx - UiKit.CHIP_PAD_X, 1.0), f.get_height(fs))
	holder.add_child(l)
	return l


## Judgment bar: track ABYSS_500 60% across BAR_MAX, fill `width` x the entrance fill in `color`.
func _bar(node_name: String, rect: Rect2, width: float, color: Color) -> void:
	var idx := _bar_nodes.size()
	var node := _painter(node_name, rect, func(ci: CanvasItem) -> void:
		ci.draw_rect(Rect2(Vector2.ZERO, rect.size), Palette.alpha(Palette.ABYSS_500, TRACK_ALPHA))
		var w := width * _bar_k[idx]
		if w > 0.0:
			ci.draw_rect(Rect2(0.0, 0.0, w, rect.size.y), color))
	_bar_nodes.append(node)


## Starts a panel group: a full-screen, input-transparent Control at (0, 0) that holds one panel
## and its contents, so the entrance can fade and raise them together. At rest it changes no
## global position.
func _begin_group(node_name: String) -> void:
	var gp := Control.new()
	gp.name = node_name
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(gp)
	_layout.add_child(gp)
	panel_groups.append(gp)
	_into = gp


## Current width of judgment bar i (0 PERFECT, 1 GOOD, 2 MISS) during the entrance.
func bar_fill(i: int) -> float:
	return bar_widths[i] * _bar_k[i]


# ---- entrance --------------------------------------------------------------------------

func _start_animation() -> void:
	_reduce = UiKit.reduce_motion()
	UiKit.register_fx(self)
	_record_popped = false
	if grade_emblem != null:
		grade_emblem.play(EMBLEM_DELAY)
	_kill_entrance()
	_entrance_running = true
	apply_entrance(0.0)
	_entrance_tween = create_tween()
	_entrance_tween.tween_method(apply_entrance, 0.0, ENTRANCE_SEC, ENTRANCE_SEC)
	_entrance_tween.tween_callback(func() -> void: _entrance_running = false)


func entrance_running() -> bool:
	return _entrance_running


## Puts every entrance element in its state `t` seconds after the screen appeared (the Tween
## drives this; tests call it directly). The grade emblem runs its own pop from play().
func apply_entrance(t: float) -> void:
	for i in panel_groups.size():
		var k := _ease_out(clampf((t - i * Palette.STAGGER_RESULTS) / Palette.DUR_BASE, 0.0, 1.0))
		var gp := panel_groups[i]
		gp.modulate.a = k
		gp.position.y = 0.0 if _reduce else PANEL_RISE * (1.0 - k)
	for i in _bar_nodes.size():
		var k := _ease_out(clampf((t - FILL_AT - i * Palette.STAGGER_RESULTS) / Palette.DUR_SLOW, 0.0, 1.0))
		_bar_k[i] = 1.0 if _reduce else k
		_bar_nodes[i].modulate.a = k if _reduce else 1.0
		_bar_nodes[i].queue_redraw()
	if histogram != null:
		histogram.grow(clampf((t - FILL_AT) / TimingHistogram.GROW_SEC, 0.0, 1.0))
	if record_banner != null:
		var chip := record_banner.get_parent() as Control
		if _reduce:
			chip.modulate.a = clampf((t - RECORD_AT) / Palette.DUR_BASE, 0.0, 1.0)
		else:
			chip.modulate.a = 1.0 if t >= RECORD_AT else 0.0
			if t >= RECORD_AT and not _record_popped and t < ENTRANCE_SEC:
				_record_popped = true
				_record_tween = UiKit.pop_in(chip)


## Jumps every entrance element to its final state (any input while the entrance runs).
func skip_entrance() -> void:
	_kill_entrance()
	_record_popped = true
	apply_entrance(ENTRANCE_SEC)
	if _record_tween != null and _record_tween.is_valid():
		_record_tween.kill()
	if record_banner != null:
		(record_banner.get_parent() as Control).scale = Vector2.ONE
	if grade_emblem != null:
		grade_emblem.finish()
	_entrance_running = false


func _kill_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


## Effect contract: Reduce motion switched on mid-entrance jumps to the final state.
func apply_effect_settings() -> void:
	var was := _reduce
	_reduce = UiKit.reduce_motion()
	if _reduce and not was and _entrance_running:
		skip_entrance()


func effect_counts() -> Dictionary:
	return {"rise": not _reduce, "bar_grow": not _reduce}


static func _is_skip_press(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton \
		or event is InputEventAction or event is InputEventScreenTouch


func _input(event: InputEvent) -> void:
	if _entrance_running and _is_skip_press(event):
		skip_entrance()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	if retry_button != null:
		_start_animation()
		retry_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if retry_button == null or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		menu_pressed.emit()
