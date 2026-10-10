class_name ProgressTrack
extends Control
## Song progress across the top of the board (UI-SPEC 4.8, 7.3 "Board-attached"):
## a scrim (ABYSS_900 80% to y 76, fading to 0 by y 112), the "{title} · {artist}" line
## (Label 20 TEXT_MID at x 480, baseline 48, truncated at 560 px), the current section name
## (Label 20 SONAR_PALE, right-aligned at x 1440, truncated at 360 px, empty without sections),
## the 4 px track x 480..1440 at y 60 (ABYSS_500 60% / SONAR fill), section ticks and the time
## remaining ("-2:31", Label 20 TEXT_LO at x 1456, baseline 68).
## Polish (identical in all modes, UI-SPEC 4.8 Low/Reduce row): a stroke glow under the filled
## part, a SONAR_PALE playhead (bar + diamond) at the fill end, hairline end caps, and ticks of sections already
## reached drawn in SONAR so the track reads as a route with stops.
## Read-only: polls Conductor.song_time() each frame and never drives it.

const RECT := Rect2(0.0, 0.0, 1920.0, 112.0)
const TRACK := Rect2(480.0, 60.0, 960.0, 4.0)
const TITLE_POS := Vector2(480.0, 48.0)
const TITLE_MAX_W := 560.0
const SECTION_RIGHT_X := 1440.0
const SECTION_BASE_Y := 48.0
const SECTION_MAX_W := 360.0
const TIME_POS := Vector2(1456.0, 68.0)
const TIME_MAX_TEXT := "-00:00"
const TICK_Y := Vector2(57.0, 67.0)
const TICK_W := 2.0
const TICK_ALPHA := 0.6
const TRACK_ALPHA := 0.6
const SCRIM_ALPHA := 0.8
const SCRIM_FLAT_Y := 76.0
const SCRIM_END_Y := 112.0
const ELLIPSIS := "..."
const SEPARATOR := " · "
## Polish layers (all modes).
const GLOW_WIDE := 16.0
const GLOW_WIDE_ALPHA := 0.06
const GLOW_NEAR := 8.0
const GLOW_NEAR_ALPHA := 0.12
const PLAYHEAD_Y := Vector2(54.0, 70.0)
const PLAYHEAD_W := 2.0
const CAP_Y := Vector2(56.0, 68.0)
const CAP_ALPHA := 0.5
const PASSED_TICK_ALPHA := 0.9
const PLAYHEAD_DIAMOND := 5.0

var title_label: Label
var section_label: Label
var time_label: Label

var _chart: ChartData
var _conductor: Conductor
var _len: float = 0.0
var _t: float = 0.0
var _scrim: GradientTexture2D
var _sections: Array[Dictionary] = []
## Change detection so the per-frame poll only touches labels / redraws when something visible changed.
var _shown_section: int = -2
var _shown_secs: int = -1
var _shown_px: int = -1


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = _make_scrim()
	title_label = _make_label(Palette.TEXT_MID, HORIZONTAL_ALIGNMENT_LEFT,
		Rect2(TITLE_POS.x, TITLE_POS.y, TITLE_MAX_W, 0.0))
	section_label = _make_label(Palette.SONAR_PALE, HORIZONTAL_ALIGNMENT_RIGHT,
		Rect2(SECTION_RIGHT_X - SECTION_MAX_W, SECTION_BASE_Y, SECTION_MAX_W, 0.0))
	var tw := ceilf(Palette.font().get_string_size(TIME_MAX_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x)
	time_label = _make_label(Palette.TEXT_LO, HORIZONTAL_ALIGNMENT_LEFT, Rect2(TIME_POS.x, TIME_POS.y, tw, 0.0))
	if _chart != null:
		_apply_chart()
	_refresh(true)


## Chart for the title, sections and length; conductor for the live song time (may be null in tests).
func setup(chart: ChartData, conductor: Conductor) -> void:
	_chart = chart
	_conductor = conductor
	_t = 0.0
	if is_node_ready():
		_apply_chart()
		_refresh(true)


func _apply_chart() -> void:
	_len = song_length_of(_chart)
	_sections.clear()
	if _chart != null:
		for s in _chart.sections:
			var st := float(s.get("time", 0.0))
			if is_finite(st):
				_sections.append({"time": st, "name": str(s.get("name", ""))})
		_sections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	title_label.text = title_text()


## Length of the song: the audio length when known, else the end of the last note.
static func song_length_of(chart: ChartData) -> float:
	if chart == null:
		return 0.0
	if chart.audio_stream != null:
		var l := chart.audio_stream.get_length()
		if is_finite(l) and l > 0.0:
			return l
	var end := 0.0
	for n in chart.notes:
		end = maxf(end, float(n["time"]) + float(n["duration"]))
	return end


func song_length() -> float:
	return _len


## Test/harness seam: the time the track shows (the live path polls the conductor).
func set_song_time(t: float) -> void:
	if not is_finite(t):
		return
	_t = t
	_refresh()


func fill() -> float:
	if _len <= 0.0:
		return 0.0
	return clampf(_t / _len, 0.0, 1.0)


## "{title} · {artist}" ("{title}" alone without an artist), truncated with "..." at 560 px.
func title_text() -> String:
	if _chart == null:
		return ""
	var s := _chart.title
	if _chart.artist != "":
		s += SEPARATOR + _chart.artist
	return truncate_px(s, Palette.font(), Palette.SIZE_LABEL, TITLE_MAX_W)


## Index of the last section starting at or before t, or -1.
static func section_index(sections: Array, t: float) -> int:
	var idx := -1
	for i in sections.size():
		if float(sections[i]["time"]) <= t:
			idx = i
		else:
			break
	return idx


## Current section name (UPPERCASE), "" before the first section or without sections.
func current_section_name(t: float) -> String:
	var i := section_index(_sections, t)
	return "" if i < 0 else str(_sections[i]["name"]).to_upper()


## x of each section-start tick on the track (sections inside (0, length)).
func tick_xs() -> Array[float]:
	var out: Array[float] = []
	if _len <= 0.0:
		return out
	for s in _sections:
		var st := float(s["time"])
		if st > 0.0 and st < _len:
			out.append(TRACK.position.x + TRACK.size.x * st / _len)
	return out


## "-m:ss" for the time left (rounded up, so "-0:00" only at the end).
func time_remaining_text(t: float) -> String:
	var left := maxf(_len - maxf(t, 0.0), 0.0)
	var secs := int(ceil(left - 1e-6))
	return "-%d:%02d" % [secs / 60, secs % 60]


## Scrim alpha at screen y: 80% flat to y 76, linear to 0 at y 112.
static func scrim_alpha(y: float) -> float:
	if y <= SCRIM_FLAT_Y:
		return SCRIM_ALPHA
	if y >= SCRIM_END_Y:
		return 0.0
	return SCRIM_ALPHA * (1.0 - (y - SCRIM_FLAT_Y) / (SCRIM_END_Y - SCRIM_FLAT_Y))


## Cuts text with "..." until it fits max_w at the given font size.
static func truncate_px(text: String, font: Font, font_size: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var n := text.length()
	while n > 0:
		n -= 1
		var cut := text.substr(0, n).strip_edges(false, true) + ELLIPSIS
		if font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return cut
	return ELLIPSIS


func _make_label(col: Color, align: HorizontalAlignment, at: Rect2) -> Label:
	var l := Label.new()
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(at.position.x, at.position.y - f.get_ascent(fs))
	l.size = Vector2(at.size.x, f.get_height(fs))
	add_child(l)
	return l


func _make_scrim() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, SCRIM_FLAT_Y / SCRIM_END_Y, 1.0])
	g.colors = PackedColorArray([Palette.alpha(Palette.ABYSS_900, SCRIM_ALPHA),
		Palette.alpha(Palette.ABYSS_900, SCRIM_ALPHA), Palette.alpha(Palette.ABYSS_900, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 64
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _process(_delta: float) -> void:
	if _conductor == null or not is_instance_valid(_conductor):
		return
	var t := _conductor.song_time()
	if t != _t:
		set_song_time(t)


func _refresh(force: bool = false) -> void:
	if section_label == null:
		return
	var si := section_index(_sections, _t)
	if force or si != _shown_section:
		_shown_section = si
		section_label.text = truncate_px(current_section_name(_t), Palette.font(), Palette.SIZE_LABEL, SECTION_MAX_W)
	var secs := int(ceil(maxf(_len - maxf(_t, 0.0), 0.0) - 1e-6)) if _len > 0.0 else -1
	if force or secs != _shown_secs:
		_shown_secs = secs
		time_label.text = time_remaining_text(_t) if _len > 0.0 else ""
	var px := int(round(TRACK.size.x * fill()))
	if force or px != _shown_px:
		_shown_px = px
		queue_redraw()


## W4 keep-out contract: global polygons of the scrim band, the text and the track.
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var rects: Array[Rect2] = [Rect2(Vector2.ZERO, RECT.size), TRACK.grow_individual(0, 6, 0, 6)]
	for l in [title_label, section_label, time_label]:
		rects.append(Rect2((l as Label).position, (l as Label).size))
	var out: Array[PackedVector2Array] = []
	for r in rects:
		out.append(PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
			xf * Vector2(r.position.x, r.end.y)]))
	return out


func _draw() -> void:
	draw_texture_rect(_scrim, Rect2(Vector2.ZERO, RECT.size), false)
	var x0 := TRACK.position.x
	var x1 := TRACK.end.x
	var cy := TRACK.position.y + TRACK.size.y * 0.5
	var fx := x0 + TRACK.size.x * fill()
	# Unfilled track and hairline end caps.
	draw_rect(TRACK, Palette.alpha(Palette.ABYSS_500, TRACK_ALPHA))
	var cap := Palette.alpha(Palette.TEXT_LO, CAP_ALPHA)
	draw_line(Vector2(x0, CAP_Y.x), Vector2(x0, CAP_Y.y), cap, 1.0)
	draw_line(Vector2(x1, CAP_Y.x), Vector2(x1, CAP_Y.y), cap, 1.0)
	# Filled part with a stroke glow under it (+16 px at 6%, +8 px at 12%).
	if fx > x0:
		draw_line(Vector2(x0, cy), Vector2(fx, cy), Palette.alpha(Palette.SONAR, GLOW_WIDE_ALPHA), TRACK.size.y + GLOW_WIDE)
		draw_line(Vector2(x0, cy), Vector2(fx, cy), Palette.alpha(Palette.SONAR, GLOW_NEAR_ALPHA), TRACK.size.y + GLOW_NEAR)
		draw_rect(Rect2(x0, TRACK.position.y, fx - x0, TRACK.size.y), Palette.SONAR)
	# Section ticks: reached sections lit SONAR, upcoming ones TEXT_LO 60%.
	for tx in tick_xs():
		var col := Palette.alpha(Palette.SONAR, PASSED_TICK_ALPHA) if tx <= fx else Palette.alpha(Palette.TEXT_LO, TICK_ALPHA)
		draw_rect(Rect2(tx - TICK_W * 0.5, TICK_Y.x, TICK_W, TICK_Y.y - TICK_Y.x), col)
	# Playhead at the fill end.
	if _len > 0.0:
		draw_rect(Rect2(fx - PLAYHEAD_W * 0.5, PLAYHEAD_Y.x, PLAYHEAD_W, PLAYHEAD_Y.y - PLAYHEAD_Y.x), Palette.SONAR_PALE)
		var dm := PLAYHEAD_DIAMOND
		draw_colored_polygon(PackedVector2Array([Vector2(fx, cy - dm), Vector2(fx + dm, cy), Vector2(fx, cy + dm),
			Vector2(fx - dm, cy)]), Palette.SONAR_PALE)
