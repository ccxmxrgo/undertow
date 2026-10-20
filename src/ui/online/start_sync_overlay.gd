class_name StartSyncOverlay
extends Control
## Start sync overlay (04-UI-SPEC 10.2, D-07, NET-03). Shown from the online gameplay scene entry
## until START arrives and the lead-in is scheduled. The node IS the panel rect
## (600, 340, 720, 400): glass ABYSS_700 at HUD_GLASS_ALPHA, CUT_MD, SONAR 80% brackets, no
## backdrop dim. This is the only in-game element allowed inside the note-path keep-out, and
## only before the conductor begins (declared exception, tests/test_layout_keepout.gd).
## Title "LOADING SONG" / "LINKING SUBS", body with the waiting count, up to 4 roster lines
## (name + LOADED / LOADING) and the leave hint. dismiss() fades out over DUR_BASE (every
## effect mode), emits `dismissed` and frees the node.
## Animation runs through step(dt) (driven by _process) so tests can advance it directly.

signal dismissed

const RECT := Rect2(600, 340, 720, 400)
const TITLE_AT := Vector2(632, 404)  # baseline (global)
const RULE_Y := 420.0
const RULE_X0 := 632.0
const RULE_X1 := 1288.0
const RULE_ALPHA := 0.35
const BRACKET_ALPHA := 0.8
const BODY_AT := Vector2(632, 468)
const LINE_X := 632.0
const STATUS_RIGHT := 1288.0
const LINE_BASELINES: Array[float] = [516.0, 556.0, 596.0, 636.0]
const HINT_AT := Vector2(632, 708)
const CHECK_SIZE := 16.0
const MAX_LINES := 4

const TITLE_LOADING := "LOADING SONG"
const TITLE_LINKING := "LINKING SUBS"
const BODY_WAITING := "Waiting for %d of %d subs to load."
const BODY_ALL := "All loaded. Waiting for the start signal."
const STATUS_LOADED := "LOADED"
const STATUS_LOADING := "LOADING"
const YOU := "YOU"
const HINT_KEYS := "ESC LEAVE MATCH"
const HINT_PAD := "START LEAVE MATCH"

## Constant copy by font role, for the has_char test: "heading" (Oxanium) and "label" / "body"
## (Share Tech Mono). The format strings are listed with their placeholders.
const COPY := {
	"heading": [TITLE_LOADING, TITLE_LINKING],
	"body": [BODY_WAITING, BODY_ALL],
	"label": [STATUS_LOADED, STATUS_LOADING, YOU, HINT_KEYS, HINT_PAD],
}

var _rows: Array = []  # [{seat, name, is_you, loaded}]
var _stage := "loading"
var _pad := false
var _low := false
var _dismissing := false
var _fade_t := 0.0
var _freed_emitted := false
var _sb: StyleBoxFlat


func _init() -> void:
	name = "StartSyncOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = RECT.position
	size = RECT.size
	_low = UiKit.low_effects()
	_rebuild_style()
	UiKit.register_fx(self)


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	apply_effect_settings()


## rows: [{seat, name, is_you}] in seat order (max 4 shown). Every sub starts LOADING.
func setup(rows: Array) -> void:
	_rows.clear()
	for r in rows:
		if _rows.size() >= MAX_LINES:
			break
		var d := r as Dictionary
		_rows.append({"seat": int(d.get("seat", _rows.size())), "name": str(d.get("name", "")).to_upper(),
			"is_you": bool(d.get("is_you", false)), "loaded": false})
	queue_redraw()


## "loading" (this PC builds the chart) or "linking" (waiting for the others / START).
func set_stage(stage: String) -> void:
	_stage = "linking" if stage == "linking" else "loading"
	queue_redraw()


func set_loaded(seat: int, on: bool) -> void:
	for r in _rows:
		if int(r["seat"]) == seat:
			r["loaded"] = on
	queue_redraw()


## Gamepad hint ("START LEAVE MATCH") instead of the keyboard one.
func set_pad(on: bool) -> void:
	_pad = on
	queue_redraw()


func title_text() -> String:
	return TITLE_LINKING if _stage == "linking" else TITLE_LOADING


func body_text() -> String:
	var waiting := 0
	for r in _rows:
		if not bool(r["loaded"]):
			waiting += 1
	if waiting == 0:
		return BODY_ALL
	return BODY_WAITING % [waiting, _rows.size()]


func hint_text() -> String:
	return HINT_PAD if _pad else HINT_KEYS


## [{name, status}] as displayed (your line reads "YOU").
func line_texts() -> Array:
	var out: Array = []
	for r in _rows:
		out.append({"name": YOU if bool(r["is_you"]) else String(r["name"]),
			"status": STATUS_LOADED if bool(r["loaded"]) else STATUS_LOADING})
	return out


## Fade out over DUR_BASE (all effect modes), then emit `dismissed` and free.
func dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	_fade_t = 0.0


func is_dismissing() -> bool:
	return _dismissing


func step(dt: float) -> void:
	if not _dismissing or _freed_emitted or dt <= 0.0:
		return
	_fade_t += dt
	modulate.a = clampf(1.0 - _fade_t / Palette.DUR_BASE, 0.0, 1.0)
	if _fade_t >= Palette.DUR_BASE:
		_freed_emitted = true
		visible = false
		dismissed.emit()
		queue_free()


func _process(delta: float) -> void:
	step(delta)


func debug_state() -> Dictionary:
	return {"title": title_text(), "body": body_text(), "lines": line_texts(), "hint": hint_text(),
		"dismissing": _dismissing}


# ---- effect contract -------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_rebuild_style()
	queue_redraw()


## The fade out is identical in every mode (UI-SPEC 14); Low effects drops the panel glow.
func effect_counts() -> Dictionary:
	return {"fade_out": true, "glow": not _low}


func _rebuild_style() -> void:
	_sb = UiKit.style_panel("default", _low)
	_sb.bg_color = Color(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA)


# ---- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, RECT.size)
	var o := RECT.position
	draw_style_box(_sb, r)
	UiKit.draw_brackets(self, r, Color(Palette.SONAR, BRACKET_ALPHA))
	draw_line(Vector2(RULE_X0, RULE_Y) - o, Vector2(RULE_X1, RULE_Y) - o,
		Color(Palette.SONAR, RULE_ALPHA), Palette.EDGE)
	var hf := Palette.display_font()
	var bf := Palette.font()
	var w := RULE_X1 - RULE_X0
	draw_string(hf, TITLE_AT - o, title_text(), HORIZONTAL_ALIGNMENT_LEFT, w, Palette.SIZE_HEADING,
		Palette.TEXT_HI)
	draw_string(bf, BODY_AT - o, body_text(), HORIZONTAL_ALIGNMENT_LEFT, w, Palette.SIZE_BODY,
		Palette.TEXT_MID)
	var lines := line_texts()
	for i in lines.size():
		var base := LINE_BASELINES[i] - o.y
		var l: Dictionary = lines[i]
		draw_string(bf, Vector2(LINE_X - o.x, base), String(l["name"]), HORIZONTAL_ALIGNMENT_LEFT,
			w * 0.6, Palette.SIZE_LABEL, Palette.TEXT_HI)
		var loaded: bool = l["status"] == STATUS_LOADED
		var col := Palette.SONAR if loaded else Palette.TEXT_LO
		var tw := bf.get_string_size(String(l["status"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
		var x := STATUS_RIGHT - o.x - tw
		draw_string(bf, Vector2(x, base), String(l["status"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
			Palette.SIZE_LABEL, col)
		if loaded:
			var cy := base - (bf.get_ascent(Palette.SIZE_LABEL) - bf.get_descent(Palette.SIZE_LABEL)) * 0.5
			var gr := Rect2(x - Palette.SP_XS - CHECK_SIZE, cy - CHECK_SIZE * 0.5, CHECK_SIZE, CHECK_SIZE)
			UiIcons.draw(self, "check", gr, Palette.SONAR)
	draw_string(bf, HINT_AT - o, hint_text(), HORIZONTAL_ALIGNMENT_LEFT, w, Palette.SIZE_LABEL,
		Palette.TEXT_LO)
