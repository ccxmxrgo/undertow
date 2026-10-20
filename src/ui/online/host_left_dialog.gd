class_name HostLeftDialog
extends Control
## HOST LEFT / CONNECTION LOST dialog (04-UI-SPEC 11.6, D-17, NET-06). Shown on clients on
## MATCH_ABORT ("host_left"), or on a socket drop / the 4 s watchdog ("connection_lost"), after
## gameplay stopped the conductor. Full screen (UiLayout.fill_rect), process_mode ALWAYS,
## ABYSS_900 85% backdrop. Panel (480, 240, 960, 600): danger glass at 82% over the opaque
## ABYSS_900 94% backing (ConfirmDialog pattern), CUT_MD. Body copy, "LAST KNOWN STANDINGS" and
## up to 4 rows (tops 456 / 520 / 584 / 648, 56 tall): place ("1ST" REWARD_GOLD), name ("YOU"
## on your row, ABYSS_600 92% fill + 4 px SONAR bar; host glyph after the host's name) and the
## status ("HULL {h}%" TEXT_MID / "WRECK" WARNING_RED / "LEFT" TEXT_LO). One primary
## "Back to Menu" button (512, 744, 400, 64), focused; Accept, Esc or B emit `back_to_menu`
## (once). Motion: fade + 16 px rise over DUR_BASE; Reduce motion fade only; Low effects no
## panel glow. Nothing is saved.

signal back_to_menu

const DIM_ALPHA := 0.85
const BACKING_ALPHA := 0.94
const PANEL_RECT := Rect2(480, 240, 960, 600)
const RISE_PX := 16.0
const TITLE_AT := Vector2(512, 304)  # baselines are global
const RULE_Y := 320.0
const RULE_X0 := 512.0
const RULE_X1 := 1408.0
const RULE_ALPHA := 0.35
const BRACKET_ALPHA := 0.8
const BODY_AT := Vector2(512, 368)
const BODY_W := 896.0
const CAPTION_AT := Vector2(512, 440)
const ROW_X0 := 512.0
const ROW_X1 := 1408.0
const ROW_H := 56.0
const ROW_TOPS: Array[float] = [456.0, 520.0, 584.0, 648.0]
const PLACE_X := 528.0
const NAME_X := 624.0
const STATUS_RIGHT := 1392.0
const YOU_FILL_ALPHA := 0.92
const HOST_GLYPH := 20.0
const BUTTON_RECT := Rect2(512, 744, 400, 64)
const HINT_RIGHT := 1408.0
const HINT_BASELINE := 784.0
const MAX_ROWS := 4

const TITLE_HOST_LEFT := "HOST LEFT"
const TITLE_CONNECTION_LOST := "CONNECTION LOST"
const BODY_HOST_LEFT := "%s left, so the match ended. Nothing is saved."
const BODY_CONNECTION_LOST := "No signal from %s for 4 seconds. The match ended on this PC. Nothing is saved."
const CAPTION := "LAST KNOWN STANDINGS"
const YOU := "YOU"
const STATUS_HULL := "HULL %d%%"
const STATUS_WRECK := "WRECK"
const STATUS_LEFT := "LEFT"
const BUTTON_TEXT := "Back to Menu"
const HINT_KEYS := "ENTER BACK TO MENU"
const HINT_PAD := "A BACK TO MENU"
const PLACES: Array[String] = ["1ST", "2ND", "3RD", "4TH"]

## Constant copy by font role, for the has_char test.
const COPY := {
	"heading": [TITLE_HOST_LEFT, TITLE_CONNECTION_LOST],
	"body": [BODY_HOST_LEFT, BODY_CONNECTION_LOST, YOU, BUTTON_TEXT, "1ST", "2ND", "3RD", "4TH"],
	"label": [CAPTION, STATUS_HULL, STATUS_WRECK, STATUS_LEFT, HINT_KEYS, HINT_PAD],
}

var panel: Control
var button: Button
var dim: ColorRect

var _kind := "host_left"
var _host_name := ""
var _rows: Array = []
var _pad := false
var _low := false
var _rise := true
var _anim_t := 0.0
var _animating := false
var _done := false
var _sb: StyleBoxFlat


## Draws through a callable (the panel).
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _init() -> void:
	name = "HostLeftDialog"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiLayout.fill_rect(self)
	theme = Palette.load_theme()
	_low = UiKit.low_effects()
	_rise = not UiKit.reduce_motion()
	_rebuild_style()
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.ABYSS_900, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	panel = Painter.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.painter = _paint_panel
	add_child(panel)
	button = UiKit.make_button(BUTTON_TEXT, "", "primary", int(BUTTON_RECT.size.y))
	button.name = "BackToMenu"
	button.position = BUTTON_RECT.position - PANEL_RECT.position
	button.size = BUTTON_RECT.size
	button.pressed.connect(_emit_back)
	var self_path := NodePath(".")
	button.focus_neighbor_left = self_path
	button.focus_neighbor_right = self_path
	button.focus_neighbor_top = self_path
	button.focus_neighbor_bottom = self_path
	button.focus_next = self_path
	button.focus_previous = self_path
	panel.add_child(button)
	UiKit.register_fx(self)


func _ready() -> void:
	apply_effect_settings()
	button.grab_focus()
	_start_anim()


## kind: "host_left" (MATCH_ABORT) or "connection_lost" (watchdog / socket drop). host_name is
## the host's (already validated) player name. rows: up to 4, already ordered, each
## {place, name, is_you, is_host, status: "hull"|"wreck"|"left", hull_pct}.
func setup(kind: String, host_name: String, rows: Array) -> void:
	_kind = "connection_lost" if kind == "connection_lost" else "host_left"
	_host_name = host_name.to_upper()
	_rows.clear()
	for r in rows:
		if _rows.size() >= MAX_ROWS:
			break
		_rows.append((r as Dictionary).duplicate())
	panel.queue_redraw()
	if is_inside_tree():
		button.grab_focus()


## Gamepad hint ("A BACK TO MENU") instead of the keyboard one.
func set_pad(on: bool) -> void:
	_pad = on
	panel.queue_redraw()


func title_text() -> String:
	return TITLE_CONNECTION_LOST if _kind == "connection_lost" else TITLE_HOST_LEFT


func body_text() -> String:
	var fmt := BODY_CONNECTION_LOST if _kind == "connection_lost" else BODY_HOST_LEFT
	return fmt % _host_name


func hint_text() -> String:
	return HINT_PAD if _pad else HINT_KEYS


## "1ST".."4TH" for places 1..4 (anything else is clamped).
static func place_text(place: int) -> String:
	return PLACES[clampi(place, 1, PLACES.size()) - 1]


## [text, colour] of a row status.
static func status_of(r: Dictionary) -> Array:
	match str(r.get("status", "hull")):
		"wreck":
			return [STATUS_WRECK, Palette.WARNING_RED]
		"left":
			return [STATUS_LEFT, Palette.TEXT_LO]
	return [STATUS_HULL % int(round(float(r.get("hull_pct", 0.0)))), Palette.TEXT_MID]


## Displayed rows: [{place, name, status, place_gold, is_you, is_host}].
func row_texts() -> Array:
	var out: Array = []
	for r: Dictionary in _rows:
		var place := int(r.get("place", out.size() + 1))
		out.append({"place": place_text(place), "place_gold": place == 1,
			"name": YOU if bool(r.get("is_you", false)) else str(r.get("name", "")).to_upper(),
			"status": String(status_of(r)[0]), "is_you": bool(r.get("is_you", false)),
			"is_host": bool(r.get("is_host", false))})
	return out


func debug_state() -> Dictionary:
	return {"title": title_text(), "body": body_text(), "rows": row_texts(),
		"focus": "back_to_menu" if button.has_focus() else "", "hint": hint_text()}


## Last known standings rows from the last STATUS fields. statuses: seat -> {hull, depth, alive,
## left}. Order: alive subs by hull, then depth (both descending); then wrecks and leavers by
## depth (descending); ties by seat. Places are 1..n in that order; at most 4 rows.
static func rows_from_status(statuses: Dictionary, names: PackedStringArray, local_seat: int,
		host_seat: int) -> Array:
	var alive: Array = []
	var down: Array = []
	for k in statuses:
		var seat := int(k)
		var s: Dictionary = statuses[k]
		var left := bool(s.get("left", false))
		var is_alive := bool(s.get("alive", true)) and not left
		var row := {"seat": seat, "place": 0,
			"name": names[seat] if seat >= 0 and seat < names.size() else "P%d" % (seat + 1),
			"is_you": seat == local_seat, "is_host": seat == host_seat,
			"status": "left" if left else ("hull" if is_alive else "wreck"),
			"hull_pct": float(s.get("hull", 0.0)), "depth": float(s.get("depth", 0.0))}
		if is_alive:
			alive.append(row)
		else:
			down.append(row)
	alive.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.hull_pct != b.hull_pct:
			return a.hull_pct > b.hull_pct
		if a.depth != b.depth:
			return a.depth > b.depth
		return a.seat < b.seat)
	down.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.depth != b.depth:
			return a.depth > b.depth
		return a.seat < b.seat)
	var out: Array = []
	out.append_array(alive)
	out.append_array(down)
	if out.size() > MAX_ROWS:
		out.resize(MAX_ROWS)
	for i in out.size():
		(out[i] as Dictionary)["place"] = i + 1
	return out


# ---- input -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event == null or event.is_echo():
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel") \
			or (InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		_emit_back()


func _emit_back() -> void:
	if _done:
		return
	_done = true
	back_to_menu.emit()


# ---- animation ---------------------------------------------------------------------------

func _start_anim() -> void:
	_anim_t = 0.0
	_animating = true
	_apply_anim()


func step(dt: float) -> void:
	if not _animating or dt <= 0.0:
		return
	_anim_t += dt
	_apply_anim()


func _process(delta: float) -> void:
	step(delta)


func _apply_anim() -> void:
	var k := clampf(_anim_t / Palette.DUR_BASE, 0.0, 1.0)
	modulate.a = k
	var off := (1.0 - k) * RISE_PX if _rise else 0.0
	panel.position = PANEL_RECT.position + Vector2(0.0, off)
	if k >= 1.0:
		_animating = false


# ---- effect contract ---------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_rise = not UiKit.reduce_motion()
	_rebuild_style()
	if not _animating:
		panel.position = PANEL_RECT.position
	panel.queue_redraw()


## Rise + fade (Reduce motion: fade only); Low effects drops the panel glow.
func effect_counts() -> Dictionary:
	return {"rise": _rise, "glow": not _low}


func _rebuild_style() -> void:
	_sb = UiKit.style_panel("danger", _low)
	_sb.shadow_color = Color(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)


# ---- drawing -----------------------------------------------------------------------------

func _paint_panel(ci: CanvasItem) -> void:
	var o := PANEL_RECT.position
	var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
	ci.draw_colored_polygon(UiKit.chamfer_points(r, Palette.CUT_MD), Color(Palette.ABYSS_900, BACKING_ALPHA))
	ci.draw_style_box(_sb, r)
	UiKit.draw_brackets(ci, r, Color(Palette.WARNING_RED, BRACKET_ALPHA))
	ci.draw_line(Vector2(RULE_X0, RULE_Y) - o, Vector2(RULE_X1, RULE_Y) - o,
		Color(Palette.WARNING_RED, RULE_ALPHA), Palette.EDGE)
	var hf := Palette.display_font()
	var bf := Palette.font()
	ci.draw_string(hf, TITLE_AT - o, title_text(), HORIZONTAL_ALIGNMENT_LEFT, BODY_W,
		Palette.SIZE_HEADING, Palette.TEXT_HI)
	ci.draw_multiline_string(bf, BODY_AT - o, body_text(), HORIZONTAL_ALIGNMENT_LEFT, BODY_W,
		Palette.SIZE_BODY, 2, Palette.TEXT_MID)
	ci.draw_string(bf, CAPTION_AT - o, CAPTION, HORIZONTAL_ALIGNMENT_LEFT, BODY_W, Palette.SIZE_LABEL,
		Palette.TEXT_LO)
	var rows := row_texts()
	var bo := (bf.get_ascent(Palette.SIZE_BODY) - bf.get_descent(Palette.SIZE_BODY)) * 0.5
	var lo := (bf.get_ascent(Palette.SIZE_LABEL) - bf.get_descent(Palette.SIZE_LABEL)) * 0.5
	for i in rows.size():
		var row: Dictionary = rows[i]
		var top := ROW_TOPS[i] - o.y
		var cy := top + ROW_H * 0.5
		if bool(row["is_you"]):
			ci.draw_rect(Rect2(ROW_X0 - o.x, top, ROW_X1 - ROW_X0, ROW_H),
				Color(Palette.ABYSS_600, YOU_FILL_ALPHA))
			ci.draw_rect(Rect2(ROW_X0 - o.x, top, Palette.FOCUS_BAR, ROW_H), Palette.SONAR)
		ci.draw_string(bf, Vector2(PLACE_X - o.x, cy + bo), String(row["place"]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, Palette.SIZE_BODY, Palette.REWARD_GOLD if bool(row["place_gold"]) else Palette.TEXT_HI)
		var nm := String(row["name"])
		ci.draw_string(bf, Vector2(NAME_X - o.x, cy + bo), nm, HORIZONTAL_ALIGNMENT_LEFT, 480.0,
			Palette.SIZE_BODY, Palette.TEXT_HI)
		if bool(row["is_host"]):
			var nw := minf(bf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_BODY).x, 480.0)
			var gx := NAME_X - o.x + nw + Palette.SP_XS
			UiIcons.draw(ci, "host", Rect2(gx, cy - HOST_GLYPH * 0.5, HOST_GLYPH, HOST_GLYPH), Palette.TEXT_HI)
		var st := status_of(_rows[i])
		var sw := bf.get_string_size(String(st[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
		ci.draw_string(bf, Vector2(STATUS_RIGHT - o.x - sw, cy + lo), String(st[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, st[1])
	var hw := bf.get_string_size(hint_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	ci.draw_string(bf, Vector2(HINT_RIGHT - hw, HINT_BASELINE) - o, hint_text(), HORIZONTAL_ALIGNMENT_LEFT,
		-1, Palette.SIZE_LABEL, Palette.TEXT_LO)
