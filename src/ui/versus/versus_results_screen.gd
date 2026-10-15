class_name VersusResultsScreen
extends Control
## "MATCH COMPLETE" versus results (03-UI-SPEC 9.4; MATCH-05, spec req 13, D-22, D-23).
## Full-screen and opaque like ResultsScreen: the calm AbyssBackdrop with ABYSS_900 55% over it.
## Layout at the 1920x1080 base:
##   header     x 96..1824, y 64..176: MATCH COMPLETE, the winner headline, title · artist +
##              difficulty chip; on the right the NOT RECORDED chip, the "do not set records"
##              sentence and SEED {n} (D-18 repro)
##   standings  x 96..1824, y 208..712 glass panel; column captions at baseline 248; rows at
##              y 272 / 376 / 480 / 584 (96 tall) in placement order: place, callsign + status,
##              depth, accuracy, landed, reflected, up to 3 medal badges (168 px columns from x 1264)
##   buttons    y 752..816: Rematch (primary, initial focus), Change Match, Back to Menu in a closed
##              loop; Esc / B = Back to Menu
##   hint       (96, 872); YOUR MEDALS legend at baselines 920 / 952 / 984 / 1016
## Versus never writes records (D-23): this screen has no ScoreStore call.
## Entrance (<= ENTRANCE_SEC = 0.78 s): header fades (DUR_BASE); rows rise 16 px + fade with a
## 60 ms stagger; then medals pop (scale 1.4 -> 1.0 back-out, alpha 0 -> 1, DUR_BASE, 60 ms per
## row); the winner's place label gets a REWARD_GOLD glow_sm (Full only). Any input while it runs
## jumps to the final state and is consumed. Reduce motion: fades only. Low effects: no glow.
##
## setup(data) keys:
##   rows: Array[Dictionary] - MatchSim.standings() rows {seat, place, alive, depth, hull,
##         accuracy (0..1, -1 = nothing judged), eliminated_at (s, INF alive)} merged with
##         name (callsign, "YOU" for the human), landed, reflected
##   local_seat: int; medals: Dictionary seat -> Array of MedalRules keys
##   title, artist, difficulty: String; seed: int; last_standing_seat: int (-1 none)

signal rematch_pressed
signal change_match_pressed
signal menu_pressed

const PAD_X := 96.0
const RIGHT_X := 1824.0
const PANEL_RECT := Rect2(96.0, 208.0, 1728.0, 504.0)
const ROW_TOPS: Array[float] = [272.0, 376.0, 480.0, 584.0]
const ROW_H := 96.0
const CAPTION_Y := 248.0
const PLACE_X := 128.0
const SUB_X := 248.0
const SUB_MAX_W := 384.0
const DEPTH_RIGHT := 744.0
const DEPTH_UNIT_X := 752.0
const DEPTH_CAPTION_RIGHT := 776.0
const ACC_RIGHT := 960.0
const LANDED_X := 1072.0
const REFLECTED_X := 1184.0
const MEDAL_X: Array[float] = [1264.0, 1444.0, 1624.0]
const MEDAL_COL_W := 168.0
const BADGE := 48.0
const BADGE_CUT := 16.0
const BADGE_GLYPH := 24.0
const BADGE_FILL_ALPHA := 0.92
const YOU_FILL_ALPHA := 0.92
const YOU_BAR_W := 4.0
const DIVIDER_ALPHA := 0.2
const BRACKET_ALPHA := 0.8
const SHADE_ALPHA := 0.55
const BUTTON_Y := 752.0
const BUTTON_W := 400.0
const BUTTON_H := 64.0
const BUTTON_X: Array[float] = [96.0, 520.0, 944.0]
const HINT_KEYS := "ENTER SELECT  ·  ESC BACK TO MENU"
const HINT_PAD := "A SELECT  ·  B BACK TO MENU"
const LEGEND_BASES: Array[float] = [920.0, 952.0, 984.0, 1016.0]
const NO_MEDALS_TEXT := "No medals this time. Reflect a torpedo, win a solo or survive a dogpile to earn one."
const NOT_RECORDED_TEXT := "Versus matches do not set records."
const TITLE_MAX_W := 1100.0
const CAPTION_SPACING := 2
const HEAD_CAPTION_SPACING := 4
const CHIP_GAP := 8.0
const ORDINALS: Array[String] = ["1ST", "2ND", "3RD", "4TH"]
## Entrance timeline (seconds from the screen appearing).
const ROW_RISE := 16.0
const ROWS_AT := Palette.STAGGER_RESULTS
const MEDALS_AT := ROWS_AT + 3.0 * Palette.STAGGER_RESULTS + Palette.DUR_BASE  # 0.42 s
const MEDAL_FROM := 1.4
const ENTRANCE_SEC := MEDALS_AT + 3.0 * Palette.STAGGER_RESULTS + Palette.DUR_BASE  # 0.78 s

var rematch_button: Button
var change_match_button: Button
var menu_button: Button
var focus_marker: FocusMarker
var hint_label: Label
## Index of the YOU row in placement order (-1 when the local seat has no row).
var you_row: int = -1

var _backdrop: AbyssBackdrop
var _layout: Control
var _into: Control
var _caption_font: FontVariation
var _head_caption_font: FontVariation
var _headline: String = ""
var _headline_color: Color = Palette.TEXT_HI
var _header_group: Control
var _row_groups: Array[Control] = []
var _row_texts: Array[Dictionary] = []
var _row_medals: Array = []  # per row: Array[String] keys
var _medal_nodes: Array = []  # per row: Array[Control] badge holders
var _legend: Array[String] = []
var _winner_glow: Control
var _entrance_tween: Tween
var _entrance_running: bool = false
var _reduce: bool = false
var _low: bool = false
var _last_pad: bool = false


## A non-interactive canvas that draws with a callable.
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func setup(data: Dictionary) -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_kill_entrance()
	_entrance_running = false
	_row_groups.clear()
	_row_texts.clear()
	_row_medals.clear()
	_medal_nodes.clear()
	_legend.clear()
	_winner_glow = null
	_reduce = UiKit.reduce_motion()
	_low = UiKit.low_effects()
	_build_backdrop()
	_layout = Control.new()
	_layout.name = "Layout"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(_layout)
	add_child(_layout)

	var rows := _sorted_rows(data.get("rows", []))
	var local_seat: int = int(data.get("local_seat", 0))
	var medals: Dictionary = data.get("medals", {}) if data.get("medals", {}) is Dictionary else {}
	var last_seat: int = int(data.get("last_standing_seat", -1))
	_compute_headline(rows, local_seat)

	_header_group = _begin_group("HeaderGroup")
	_build_header(data)
	_into = _layout
	_build_panel()
	you_row = -1
	for i in mini(rows.size(), ROW_TOPS.size()):
		var r: Dictionary = rows[i]
		var seat: int = int(r.get("seat", -1))
		if seat == local_seat:
			you_row = i
		var keys: Array[String] = []
		for k in medals.get(seat, []):
			if MedalRules.NAMES.has(str(k)) and keys.size() < MedalRules.MAX_PER_SEAT:
				keys.append(str(k))
		_row_medals.append(keys)
		_row_groups.append(_begin_group("Row%d" % i))
		_build_row(i, r, seat == local_seat, seat == last_seat, keys, i < mini(rows.size(), ROW_TOPS.size()) - 1)
	_into = _layout
	_build_buttons()
	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)
	_into = _header_group
	hint_label = _label("Hint", HINT_KEYS, _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(PAD_X, 872.0))
	var mine: Array[String] = _row_medals[you_row] if you_row >= 0 else ([] as Array[String])
	_build_legend(mine)
	_into = _layout
	UiKit.register_fx(self)
	if is_inside_tree():
		_start_animation()
		rematch_button.grab_focus()


# ---- data -------------------------------------------------------------------------------

static func _sorted_rows(raw: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if raw is Array:
		for r in raw:
			if r is Dictionary:
				rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("place", 99))
		var pb := int(b.get("place", 99))
		if pa != pb:
			return pa < pb
		return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	return rows


func _compute_headline(rows: Array[Dictionary], local_seat: int) -> void:
	var firsts: Array[Dictionary] = []
	for r in rows:
		if int(r.get("place", 0)) == 1:
			firsts.append(r)
	if firsts.size() != 1:
		_headline = "DRAW"
		_headline_color = Palette.TEXT_HI
	elif int(firsts[0].get("seat", -1)) == local_seat:
		_headline = "YOU WIN"
		_headline_color = Palette.REWARD_GOLD
	else:
		_headline = "%s WINS" % _name_of(firsts[0])
		_headline_color = Palette.TEXT_HI


static func _name_of(r: Dictionary) -> String:
	return str(r.get("name", "P%d" % int(r.get("seat", 0)))).to_upper()


## "LAST HULL STANDING" / "SURVIVED · HULL {h}%" / "IMPLODED AT {m:ss}" and its colour.
static func status_of(r: Dictionary, last_standing: bool) -> Array:
	if last_standing:
		return ["LAST HULL STANDING", Palette.SONAR_PALE]
	if r.get("alive", true):
		return ["SURVIVED · HULL %d%%" % int(round(float(r.get("hull", 0.0)))), Palette.TEXT_MID]
	return ["IMPLODED AT %s" % clock_text(float(r.get("eliminated_at", 0.0))), Palette.WARNING_RED]


## m:ss of a song time.
static func clock_text(t: float) -> String:
	if not is_finite(t) or t < 0.0:
		t = 0.0
	var s := int(floor(t))
	return "%d:%02d" % [s / 60, s % 60]


## Row accuracy (0..1, -1 none) as the U-4.13 text ("98.4%" / "--.-%").
static func accuracy_of(r: Dictionary) -> String:
	var a := float(r.get("accuracy", -1.0))
	return RunStats.accuracy_text(a * 100.0 if a >= 0.0 else -1.0)


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


func backdrop_opaque() -> bool:
	return _backdrop != null and _backdrop.variant == "calm" and _backdrop.visible


func _build_header(data: Dictionary) -> void:
	_label("MatchComplete", "MATCH COMPLETE", _head_caption(), Palette.SIZE_LABEL, Palette.SONAR, Vector2(PAD_X, 88.0))
	_label("Headline", _headline, Palette.display_font(), Palette.SIZE_HEADING, _headline_color, Vector2(PAD_X, 136.0))
	# Right: NOT RECORDED chip, sentence, seed.
	var cw := UiKit.chip_width("NOT RECORDED", "muted")
	_chip("NOT RECORDED", "muted", Rect2(RIGHT_X - cw, 72.0, cw, UiKit.CHIP_H))
	var note := _label("NotRecorded", NOT_RECORDED_TEXT, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO,
		Vector2(RIGHT_X, 136.0), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("Seed", "SEED %d" % int(data.get("seed", 0)), _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO,
		Vector2(RIGHT_X, 168.0), HORIZONTAL_ALIGNMENT_RIGHT)
	# Left: "{title} · {artist}" then the difficulty chip 16 px after it.
	var parts: Array[String] = []
	for p in [str(data.get("title", "")).strip_edges(), str(data.get("artist", "")).strip_edges()]:
		if p != "":
			parts.append(p)
	var max_w := minf(TITLE_MAX_W, note.position.x - PAD_X - Palette.SP_XL - 160.0)
	var ax := PAD_X
	if not parts.is_empty():
		var sl := _label("SongLine", ProgressTrack.truncate_px(" · ".join(parts), Palette.font(), Palette.SIZE_BODY, max_w),
			Palette.font(), Palette.SIZE_BODY, Palette.TEXT_MID, Vector2(PAD_X, 172.0))
		ax = sl.position.x + sl.size.x + Palette.SP_MD
	var diff := str(data.get("difficulty", ""))
	if diff != "":
		var dt := diff.to_upper()
		var dw := UiKit.chip_width(dt, "difficulty")
		_chip(dt, "difficulty", Rect2(ax, 148.0, dw, UiKit.CHIP_H), MainMenu.difficulty_lane(diff.to_lower()))


func _build_panel() -> void:
	var sb := UiKit.style_panel("default")
	_painter("StandingsPanel", PANEL_RECT, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, Palette.alpha(Palette.SONAR, BRACKET_ALPHA)))
	var c := _caption()
	var fs := Palette.SIZE_LABEL
	_label("CapPlace", "PLACE", c, fs, Palette.TEXT_LO, Vector2(PLACE_X, CAPTION_Y))
	_label("CapSub", "SUB", c, fs, Palette.TEXT_LO, Vector2(SUB_X, CAPTION_Y))
	_label("CapDepth", "DEPTH", c, fs, Palette.TEXT_LO, Vector2(DEPTH_CAPTION_RIGHT, CAPTION_Y), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("CapAccuracy", "ACCURACY", c, fs, Palette.TEXT_LO, Vector2(ACC_RIGHT, CAPTION_Y), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("CapLanded", "LANDED", c, fs, Palette.TEXT_LO, Vector2(LANDED_X, CAPTION_Y), HORIZONTAL_ALIGNMENT_CENTER)
	_label("CapReflected", "REFLECTED", c, fs, Palette.TEXT_LO, Vector2(REFLECTED_X, CAPTION_Y), HORIZONTAL_ALIGNMENT_CENTER)
	_label("CapMedals", "MEDALS", c, fs, Palette.TEXT_LO, Vector2(MEDAL_X[0], CAPTION_Y))


func _build_row(i: int, r: Dictionary, is_you: bool, last_standing: bool, keys: Array[String],
		divider: bool) -> void:
	var yr := ROW_TOPS[i]
	var row_rect := Rect2(PANEL_RECT.position.x, yr, PANEL_RECT.size.x, ROW_H)
	var chrome := _painter("Chrome", row_rect, func(ci: CanvasItem) -> void:
		var sz: Vector2 = ci.get("size")
		if is_you:
			ci.draw_rect(Rect2(Vector2.ZERO, sz), Palette.alpha(Palette.ABYSS_600, YOU_FILL_ALPHA))
			ci.draw_rect(Rect2(0.0, 0.0, YOU_BAR_W, sz.y), Palette.SONAR)
		if divider:
			ci.draw_rect(Rect2(0.0, sz.y + Palette.SP_XS - 0.5, sz.x, 1.0), Palette.alpha(Palette.SONAR, DIVIDER_ALPHA)))
	chrome.set_meta(&"you", is_you)
	var place := int(r.get("place", i + 1))
	var place_text := ORDINALS[clampi(place - 1, 0, ORDINALS.size() - 1)]
	var hf := Palette.display_font()
	var hs := Palette.SIZE_HEADING
	if place == 1:
		var glow_rect := Rect2(PLACE_X - 24.0, yr + 20.0, 104.0, 56.0)
		_winner_glow = _painter("WinnerGlow", glow_rect, func(ci: CanvasItem) -> void:
			var sz: Vector2 = ci.get("size")
			var k: float = Palette.GLOW_SM[0]
			var gr := Rect2(sz * 0.5 - sz * k * 0.5, sz * k)
			ci.draw_texture_rect(UiKit.glow_texture(), gr, false, Palette.alpha(Palette.REWARD_GOLD, Palette.GLOW_SM[1])))
		_winner_glow.material = UiKit.additive_material()
		_winner_glow.visible = not _low
	_label("Place", place_text, hf, hs, Palette.REWARD_GOLD if place == 1 else Palette.TEXT_HI, Vector2(PLACE_X, yr + 60.0))
	var name_text := ProgressTrack.truncate_px(_name_of(r), hf, hs, SUB_MAX_W)
	_label("Callsign", name_text, hf, hs, Palette.TEXT_HI, Vector2(SUB_X, yr + 48.0))
	var st := status_of(r, last_standing)
	_label("Status", st[0], Palette.font(), Palette.SIZE_LABEL, st[1], Vector2(SUB_X, yr + 80.0))
	var depth_text := Palette.fmt_depth(int(float(r.get("depth", 0.0))))
	_label("Depth", depth_text, hf, hs, Palette.SONAR, Vector2(DEPTH_RIGHT, yr + 60.0), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("DepthUnit", " M", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(DEPTH_UNIT_X, yr + 60.0))
	var acc := accuracy_of(r)
	_label("Accuracy", acc, hf, hs, Palette.TEXT_HI, Vector2(ACC_RIGHT, yr + 60.0), HORIZONTAL_ALIGNMENT_RIGHT)
	var landed := str(int(r.get("landed", 0)))
	var reflected := str(int(r.get("reflected", 0)))
	_label("Landed", landed, hf, hs, Palette.TEXT_HI, Vector2(LANDED_X, yr + 60.0), HORIZONTAL_ALIGNMENT_CENTER)
	_label("Reflected", reflected, hf, hs, Palette.TEXT_HI, Vector2(REFLECTED_X, yr + 60.0), HORIZONTAL_ALIGNMENT_CENTER)
	var names: Array[String] = []
	var holders: Array[Control] = []
	if keys.is_empty():
		_label("NoMedals", "-", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(MEDAL_X[0], yr + 60.0))
	for j in keys.size():
		holders.append(_build_medal(keys[j], Vector2(MEDAL_X[j], yr)))
		names.append(MedalRules.NAMES[keys[j]])
	_medal_nodes.append(holders)
	_row_texts.append({
		"place": place_text, "name": name_text, "status": st[0], "status_color": st[1],
		"depth": depth_text, "accuracy": acc, "landed": landed, "reflected": reflected,
		"medals": names, "you": is_you,
	})


## One medal: a 168 x 96 column holder (badge + name) whose pivot is the badge centre.
func _build_medal(key: String, at: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "Medal_" + key
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = at
	holder.size = Vector2(MEDAL_COL_W, ROW_H)
	holder.pivot_offset = Vector2(MEDAL_COL_W * 0.5, 8.0 + BADGE * 0.5)
	holder.set_meta(&"medal", key)
	_into.add_child(holder)
	var prev := _into
	_into = holder
	var glyph: String = MedalRules.GLYPHS[key]
	var badge := _painter("Badge", Rect2((MEDAL_COL_W - BADGE) * 0.5, 8.0, BADGE, BADGE), func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, Vector2(BADGE, BADGE))
		var pts := UiKit.chamfer_points(r, BADGE_CUT)
		ci.draw_colored_polygon(pts, Palette.alpha(Palette.ABYSS_600, BADGE_FILL_ALPHA))
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, Palette.REWARD_GOLD, Palette.EDGE, true)
		var g := (BADGE - BADGE_GLYPH) * 0.5
		UiIcons.draw(ci, glyph, Rect2(g, g, BADGE_GLYPH, BADGE_GLYPH), Palette.REWARD_GOLD))
	badge.set_meta(&"glyph", glyph)
	_label("Name", MedalRules.NAMES[key], Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_HI,
		Vector2(MEDAL_COL_W * 0.5, 84.0), HORIZONTAL_ALIGNMENT_CENTER)
	_into = prev
	return holder


func _build_legend(keys: Array[String]) -> void:
	_label("LegendCaption", "YOUR MEDALS", _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(PAD_X, LEGEND_BASES[0]))
	if keys.is_empty():
		_legend.append(NO_MEDALS_TEXT)
	for k in keys:
		_legend.append(MedalRules.legend_line(k))
	for i in _legend.size():
		_label("Legend%d" % i, _legend[i], Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID,
			Vector2(PAD_X, LEGEND_BASES[i + 1]))


func _build_buttons() -> void:
	rematch_button = UiKit.make_button("Rematch", "", "primary", int(BUTTON_H))
	change_match_button = UiKit.make_button("Change Match", "", "default", int(BUTTON_H))
	menu_button = UiKit.make_button("Back to Menu", "", "default", int(BUTTON_H))
	rematch_button.name = "Rematch"
	change_match_button.name = "ChangeMatch"
	menu_button.name = "BackToMenu"
	rematch_button.pressed.connect(func() -> void: rematch_pressed.emit())
	change_match_button.pressed.connect(func() -> void: change_match_pressed.emit())
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	var order := focus_buttons()
	for i in order.size():
		var b := order[i]
		b.position = Vector2(BUTTON_X[i], BUTTON_Y)
		b.size = Vector2(BUTTON_W, BUTTON_H)
		_layout.add_child(b)
	# Closed focus loop: Right / Down / Tab next, Left / Up / Shift+Tab previous, wrapping.
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


# ---- getters for tests ------------------------------------------------------------------

func headline_text() -> String:
	return _headline


func headline_color() -> Color:
	return _headline_color


func row_count() -> int:
	return _row_texts.size()


## Display texts of row i (placement order): place, name, status, status_color, depth, accuracy,
## landed, reflected, medals (names), you.
func row_texts(i: int) -> Dictionary:
	return _row_texts[i] if i >= 0 and i < _row_texts.size() else {}


func medal_names(i: int) -> Array[String]:
	var out: Array[String] = []
	if i >= 0 and i < _row_texts.size():
		out.assign(_row_texts[i]["medals"])
	return out


## Column left x of each medal badge holder in row i.
func medal_columns(i: int) -> Array[float]:
	var out: Array[float] = []
	if i >= 0 and i < _medal_nodes.size():
		for h: Control in _medal_nodes[i]:
			out.append(h.position.x)
	return out


func medal_nodes(i: int) -> Array:
	return _medal_nodes[i] if i >= 0 and i < _medal_nodes.size() else []


func row_group(i: int) -> Control:
	return _row_groups[i] if i >= 0 and i < _row_groups.size() else null


func header_group() -> Control:
	return _header_group


func winner_glow() -> Control:
	return _winner_glow


func legend_lines() -> Array[String]:
	return _legend.duplicate()


func focus_buttons() -> Array[Button]:
	return [rematch_button, change_match_button, menu_button]


# ---- helpers ----------------------------------------------------------------------------

func _caption() -> Font:
	if _caption_font == null:
		_caption_font = ResultsScreen._spaced(Palette.font(), CAPTION_SPACING)
	return _caption_font


func _head_caption() -> Font:
	if _head_caption_font == null:
		_head_caption_font = ResultsScreen._spaced(Palette.font(), HEAD_CAPTION_SPACING)
	return _head_caption_font


## A label whose baseline sits at `at.y` (LEFT anchors at at.x, RIGHT ends at at.x, CENTER centres).
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
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	l.position = Vector2(x, at.y - font.get_ascent(font_size))
	l.size = Vector2(ceilf(w), ceilf(font.get_height(font_size)))
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


func _chip(text: String, variant: String, rect: Rect2, lane: int = -1) -> void:
	var holder := _painter("Chip" + text.capitalize().replace(" ", ""), rect, func(ci: CanvasItem) -> void:
		UiKit.draw_chip(ci, Rect2(Vector2.ZERO, rect.size), text, variant, lane))
	holder.set_meta(&"text", text)


## A full-screen, input-transparent group at (0, 0) that the entrance fades and raises.
func _begin_group(node_name: String) -> Control:
	var gp := Control.new()
	gp.name = node_name
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(gp)
	_layout.add_child(gp)
	_into = gp
	return gp


# ---- entrance --------------------------------------------------------------------------

func _start_animation() -> void:
	_reduce = UiKit.reduce_motion()
	_low = UiKit.low_effects()
	_kill_entrance()
	_entrance_running = true
	apply_entrance(0.0)
	_entrance_tween = create_tween()
	_entrance_tween.tween_method(apply_entrance, 0.0, ENTRANCE_SEC, ENTRANCE_SEC)
	_entrance_tween.tween_callback(func() -> void: _entrance_running = false)


func entrance_running() -> bool:
	return _entrance_running


## Every entrance element in its state `t` seconds after the screen appeared.
func apply_entrance(t: float) -> void:
	if _header_group != null:
		_header_group.modulate.a = clampf(t / Palette.DUR_BASE, 0.0, 1.0)
	for i in _row_groups.size():
		var k := _ease_out(clampf((t - ROWS_AT - i * Palette.STAGGER_RESULTS) / Palette.DUR_BASE, 0.0, 1.0))
		_row_groups[i].modulate.a = k
		_row_groups[i].position.y = 0.0 if _reduce else ROW_RISE * (1.0 - k)
	for i in _medal_nodes.size():
		var k := clampf((t - MEDALS_AT - i * Palette.STAGGER_RESULTS) / Palette.DUR_BASE, 0.0, 1.0)
		for h: Control in _medal_nodes[i]:
			h.modulate.a = k
			var s := 1.0 if _reduce else float(Tween.interpolate_value(MEDAL_FROM, 1.0 - MEDAL_FROM, k, 1.0,
				Tween.TRANS_BACK, Tween.EASE_OUT))
			h.scale = Vector2(s, s)
	if _winner_glow != null:
		_winner_glow.visible = not _low
		_winner_glow.modulate.a = clampf((t - MEDALS_AT) / Palette.DUR_BASE, 0.0, 1.0)


func skip_entrance() -> void:
	_kill_entrance()
	apply_entrance(ENTRANCE_SEC)
	_entrance_running = false


func _kill_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


## Effect contract: Reduce motion mid-entrance jumps to the final state; Low drops the glow.
func apply_effect_settings() -> void:
	var was := _reduce
	_reduce = UiKit.reduce_motion()
	_low = UiKit.low_effects()
	if _winner_glow != null:
		_winner_glow.visible = not _low
	if _reduce and not was and _entrance_running:
		skip_entrance()


func effect_counts() -> Dictionary:
	return {"rise": not _reduce, "medal_pop": not _reduce, "glow": _winner_glow != null and not _low}


static func _is_skip_press(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton \
		or event is InputEventAction or event is InputEventScreenTouch


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if (pad or event is InputEventKey) and pad != _last_pad:
		_last_pad = pad
		if hint_label != null:
			hint_label.text = HINT_PAD if pad else HINT_KEYS
	if _entrance_running and _is_skip_press(event):
		skip_entrance()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	if rematch_button != null:
		_start_animation()
		rematch_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if rematch_button == null or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		menu_pressed.emit()
