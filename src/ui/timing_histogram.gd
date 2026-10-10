class_name TimingHistogram
extends Control
## Results timing histogram (02.2 UI-SPEC 4.12, D-09, VIS-05). Shows whether the player rushes or
## drags: the run's hit offsets (Perfect and Good, from HitOffsetRecorder) in 28 bins of 5 ms
## from -70 to +70 ms, early on the left. The bins come from RunStats.histogram, so the chart is
## exactly the recorded offsets.
## The control covers the results timing panel (x 1280..1824, y 208..688); every constant below is
## in 1920x1080 layout coordinates and is drawn relative to ORIGIN.
##   bars     bar i at x 1314 + 17 i, 13 wide, baseline y 600, height count / max * 300
##   colours  bins fully inside +/- perfect_window SONAR_PALE, others TEXT_MID; the window is read
##            from JudgeConfig (or the run's run_info.perfect_window), never hard-coded
##   guides   dashed 1 px TEXT_LO 35% at +/- perfect_window; centre line 2 px TEXT_HI 40% at x 1552
##   axis     "-70" / "0" / "+70" baseline 628, "EARLY" / "LATE" baseline 292 (spec 268; moved in the
##            02.2-16 visual review: at 268 "EARLY" stacked under the TIMING caption at baseline 248
##            and read as one caption; 292 keeps 8 px above the tallest bar top, y 300), Label 20 TEXT_LO
##   bars draw an 80% body with a 2 px full-colour top cap (bar_color is the cap / token colour)
##   summary  RunStats.summary_text(mean) Label 20 TEXT_MID at (1314, 664)
##   empty    "No hits to chart." centred in the chart area, no bars, no summary
## Animation: grow(progress 0..1) over GROW_SEC; each bar grows over DUR_SLOW with a 10 ms
## left-to-right stagger. Effect contract (UiKit.register_fx): Reduce motion = no growth or stagger,
## the chart fades in instead (modulate). There is no glow, so Low effects changes nothing.

const ORIGIN := Vector2(1280.0, 208.0)
const PANEL_SIZE := Vector2(544.0, 480.0)
const CHART_X := 1314.0
const CHART_RIGHT := 1790.0
const CHART_TOP := 280.0
const BASELINE_Y := 600.0
const MAX_H := 300.0
const BAR_W := 13.0
const PITCH := 17.0
const GAP := 4.0
const CENTER_X := 1552.0
const AXIS_BASE_Y := 628.0
const SIDE_BASE_Y := 292.0
const SUMMARY_BASE_Y := 664.0
const CENTER_W := 2.0
const CENTER_ALPHA := 0.4
const GUIDE_ALPHA := 0.35
const GUIDE_DASH := 6.0
const AXIS_ALPHA := 0.35
const WINDOW_BAND_ALPHA := 0.05
const BAR_BODY_ALPHA := 0.8
const BAR_CAP := 2.0
const BIN_STAGGER := 0.01
const GROW_SEC := Palette.DUR_SLOW + (RunStats.BIN_COUNT - 1) * BIN_STAGGER
const EMPTY_TEXT := "No hits to chart."
const CAPTION_SPACING := 2

## Bin counts (RunStats.histogram of the offsets).
var bins: PackedInt32Array = PackedInt32Array()
## Perfect window in seconds that drives the colour split and the guides.
var perfect_window: float = 0.035
## One-line summary ("" when there are no hits).
var summary: String = ""

var _offsets: PackedFloat32Array = PackedFloat32Array()
var _max: int = 0
var _grow: float = 1.0
var _reduce: bool = false
var _summary_label: Label
var _empty_label: Label
var _caption_font: FontVariation


func _init() -> void:
	position = ORIGIN
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	bins.resize(RunStats.BIN_COUNT)
	bins.fill(0)
	_reduce = UiKit.reduce_motion()
	_build_labels()
	_refresh_labels()


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()


## Sets the run's offsets (seconds, negative = early). `pw` < 0 reads JudgeConfig.perfect_window.
func set_offsets(offsets: PackedFloat32Array, pw: float = -1.0) -> void:
	perfect_window = pw if pw > 0.0 else JudgeConfig.new().perfect_window
	_offsets = offsets
	bins = RunStats.histogram(offsets)
	_max = 0
	for c in bins:
		_max = maxi(_max, c)
	summary = "" if is_empty() else RunStats.summary_text(RunStats.mean_offset_ms(offsets))
	_refresh_labels()
	queue_redraw()


func is_empty() -> bool:
	return _max <= 0


## Final bar height of bin i (count / max * 300; 0 when there are no hits).
func bar_height(i: int) -> float:
	if _max <= 0 or i < 0 or i >= bins.size():
		return 0.0
	return float(bins[i]) / float(_max) * MAX_H


## Current growth of bin i (0..1) at the current grow() progress.
func bar_factor(i: int) -> float:
	if _reduce:
		return 1.0
	var t := _grow * GROW_SEC - float(i) * BIN_STAGGER
	var k := clampf(t / Palette.DUR_SLOW, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)  # cubic ease-out


## Bar i in layout coordinates at the current growth.
func bar_rect(i: int) -> Rect2:
	var h := bar_height(i) * bar_factor(i)
	return Rect2(CHART_X + PITCH * i, BASELINE_Y - h, BAR_W, h)


## Bins fully inside +/- perfect_window are SONAR_PALE; the rest TEXT_MID.
func bar_color(i: int) -> Color:
	return Palette.SONAR_PALE if _bin_inside_window(i) else Palette.TEXT_MID


func _bin_inside_window(i: int) -> bool:
	var pw_us := int(roundf(perfect_window * 1000000.0))
	var lo_us := (-RunStats.RANGE_MS + RunStats.BIN_MS * i) * 1000
	var hi_us := lo_us + RunStats.BIN_MS * 1000
	return lo_us >= -pw_us and hi_us <= pw_us


## x of a time offset (ms) on the chart: bin edges at 1314 + 17 i, so 0 ms = 1552.
static func x_of_ms(ms: float) -> float:
	return CHART_X + (ms + RunStats.RANGE_MS) / RunStats.BIN_MS * PITCH


## Window guides at -/+ perfect_window, on the same convention as the spec's centre line (x 1552 =
## the left edge of the bin that starts at 0 ms), so both guides sit symmetric about it.
func guide_xs() -> Array[float]:
	var ms := perfect_window * 1000.0
	return [x_of_ms(-ms), x_of_ms(ms)]


## Animation progress 0..1 (bars grow with a stagger; Reduce motion fades the chart instead).
func grow(progress: float) -> void:
	_grow = clampf(progress, 0.0, 1.0)
	modulate.a = _grow if _reduce else 1.0
	queue_redraw()


func apply_effect_settings() -> void:
	_reduce = UiKit.reduce_motion()
	grow(_grow)


func effect_counts() -> Dictionary:
	return {"stagger": not _reduce, "grow": not _reduce}


# ---- drawing -------------------------------------------------------------------------------

func _draw() -> void:
	draw_set_transform(-ORIGIN)
	var top := CHART_TOP
	# Perfect-window band: a faint SONAR_PALE wash between the guides (reads as "the target zone").
	var g := guide_xs()
	draw_rect(Rect2(g[0], top, g[1] - g[0], BASELINE_Y - top), Palette.alpha(Palette.SONAR_PALE, WINDOW_BAND_ALPHA))
	# Baseline axis.
	draw_line(Vector2(CHART_X, BASELINE_Y + 0.5), Vector2(CHART_RIGHT, BASELINE_Y + 0.5),
		Palette.alpha(Palette.TEXT_LO, AXIS_ALPHA), 1.0)
	# Window guides (dashed) and the centre line.
	var guide := Palette.alpha(Palette.TEXT_LO, GUIDE_ALPHA)
	for x in g:
		draw_dashed_line(Vector2(x, top), Vector2(x, BASELINE_Y), guide, 1.0, GUIDE_DASH)
	# Bars.
	if not is_empty():
		for i in bins.size():
			var r := bar_rect(i)
			if r.size.y <= 0.0:
				continue
			var col := bar_color(i)
			draw_rect(r, Palette.alpha(col, BAR_BODY_ALPHA))
			draw_rect(Rect2(r.position, Vector2(r.size.x, minf(BAR_CAP, r.size.y))), col)
	draw_line(Vector2(CENTER_X, top), Vector2(CENTER_X, BASELINE_Y), Palette.alpha(Palette.TEXT_HI, CENTER_ALPHA),
		CENTER_W)
	draw_set_transform(Vector2.ZERO)


# ---- labels --------------------------------------------------------------------------------

func _caption() -> Font:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = Palette.font()
		_caption_font.spacing_glyph = CAPTION_SPACING
	return _caption_font


func _build_labels() -> void:
	var f := Palette.font()
	_label("AxisEarlyMs", "-70", f, Palette.TEXT_LO, Vector2(CHART_X, AXIS_BASE_Y), HORIZONTAL_ALIGNMENT_LEFT)
	_label("AxisZero", "0", f, Palette.TEXT_LO, Vector2(CENTER_X, AXIS_BASE_Y), HORIZONTAL_ALIGNMENT_CENTER)
	_label("AxisLateMs", "+70", f, Palette.TEXT_LO, Vector2(CHART_RIGHT, AXIS_BASE_Y), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Early", "EARLY", _caption(), Palette.TEXT_LO, Vector2(CHART_X, SIDE_BASE_Y), HORIZONTAL_ALIGNMENT_LEFT)
	_label("Late", "LATE", _caption(), Palette.TEXT_LO, Vector2(CHART_RIGHT, SIDE_BASE_Y), HORIZONTAL_ALIGNMENT_RIGHT)
	_summary_label = _label("Summary", "", f, Palette.TEXT_MID, Vector2(CHART_X, SUMMARY_BASE_Y),
		HORIZONTAL_ALIGNMENT_LEFT)
	# Centred in the chart area (x 1314..1790, y 280..600).
	var mid_base := (CHART_TOP + BASELINE_Y) * 0.5 + (f.get_ascent(Palette.SIZE_LABEL) - f.get_descent(Palette.SIZE_LABEL)) * 0.5
	_empty_label = _label("Empty", EMPTY_TEXT, f, Palette.TEXT_LO, Vector2(CENTER_X, mid_base),
		HORIZONTAL_ALIGNMENT_CENTER)


func _refresh_labels() -> void:
	if _summary_label != null:
		_summary_label.text = summary
		_summary_label.visible = summary != ""
		var f := _summary_label.get_theme_font("font")
		_summary_label.size.x = ceilf(f.get_string_size(summary, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x)
	if _empty_label != null:
		_empty_label.visible = is_empty()


## A Label whose baseline sits at `at.y` (layout coordinates). LEFT anchors at at.x, RIGHT ends at
## at.x, CENTER centres on at.x.
func _label(node_name: String, text: String, font: Font, color: Color, at: Vector2,
		align: HorizontalAlignment) -> Label:
	var fs := Palette.SIZE_LABEL
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	l.position = Vector2(x, at.y - font.get_ascent(fs)) - ORIGIN
	l.size = Vector2(ceilf(w), ceilf(font.get_height(fs)))
	add_child(l)
	return l
