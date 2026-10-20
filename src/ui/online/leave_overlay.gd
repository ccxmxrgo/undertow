class_name LeaveOverlay
extends Control
## Leave Match overlay (04-UI-SPEC 11.4, D-18). Opened by Esc / Start in an online match. It
## NEVER pauses: the conductor keeps running, lane input stays live, get_tree().paused is never
## touched and the screen is not dimmed. The node IS the rect (640, 120, 640, 152): it covers
## the alert slot and event banner band, entirely above the note-path keep-out (top y 348).
## Chrome: danger glass at HUD_GLASS_ALPHA, CUT_SM, WARNING_RED 80% brackets. Title
## "LEAVE MATCH?", clients get a "PING {n} MS" readout and the TEXT_MID body; the host gets the
## WARNING_RED warning body. Buttons 48 tall: "Leave Match" (destructive, x 656..952) and
## "Stay" (default, x 968..1264); initial focus Stay.
## Input while open (handled in _input so it wins over gameplay): ui_left / ui_right move focus
## to the other button (wrapping), ui_accept activates the focused button, ui_cancel or `pause` = Stay. Only those are consumed;
## lane_* and target_cycle events always pass through, even when rebound onto a ui_* input.
## In: fade + slide down 16 px over DUR_FAST (Reduce motion: fade only). Out: fade DUR_FAST.

signal leave_confirmed
signal stayed

const RECT := Rect2(640, 120, 640, 152)
const SLIDE_PX := 16.0
const TITLE_AT := Vector2(656, 168)  # baseline (global)
const PING_RIGHT := 1264.0
const PING_BASELINE := 160.0
const BODY_AT := Vector2(656, 196)
const BODY_W := 608.0
const BUTTON_SIZE := Vector2(296, 48)
const LEAVE_POS := Vector2(656, 208)
const STAY_POS := Vector2(968, 208)
const BRACKET_ALPHA := 0.8

const TITLE := "LEAVE MATCH?"
const PING_FMT := "PING %d MS"
const PING_UNKNOWN := "PING -- MS"
const BODY_CLIENT := "The song keeps playing. Leaving makes your sub a wreck."
const BODY_HOST := "You are the host. Leaving ends the match for everyone."
const LEAVE_TEXT := "Leave Match"
const STAY_TEXT := "Stay"

## Constant copy by font role, for the has_char test.
const COPY := {
	"heading": [TITLE],
	"label": [PING_FMT, PING_UNKNOWN, BODY_CLIENT, BODY_HOST],
	"body": [LEAVE_TEXT, STAY_TEXT],
}

## Actions the overlay never consumes (D-18: lanes and targeting keep playing).
const PASS_THROUGH: Array[StringName] = [&"lane_1", &"lane_2", &"lane_3", &"lane_4", &"target_cycle"]

var leave_button: Button
var stay_button: Button

var _open := false
var _is_host := false
var _ping_ms := -1
var _focus := 1  # 0 = Leave Match, 1 = Stay
var _anim := ""  # "", "in", "out"
var _anim_t := 0.0
var _slide := true
var _low := false
var _opened_frame := -1
var _sb: StyleBoxFlat


func _init() -> void:
	name = "LeaveOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = RECT.position
	size = RECT.size
	visible = false
	theme = Palette.load_theme()
	_low = UiKit.low_effects()
	_slide = not UiKit.reduce_motion()
	_rebuild_style()
	leave_button = UiKit.make_button(LEAVE_TEXT, "", "destructive", int(BUTTON_SIZE.y))
	leave_button.name = "Leave"
	leave_button.position = LEAVE_POS - RECT.position
	leave_button.size = BUTTON_SIZE
	leave_button.pressed.connect(func() -> void: _activate(0))
	leave_button.focus_entered.connect(func() -> void: _focus = 0)
	add_child(leave_button)
	stay_button = UiKit.make_button(STAY_TEXT, "", "default", int(BUTTON_SIZE.y))
	stay_button.name = "Stay"
	stay_button.position = STAY_POS - RECT.position
	stay_button.size = BUTTON_SIZE
	stay_button.pressed.connect(func() -> void: _activate(1))
	stay_button.focus_entered.connect(func() -> void: _focus = 1)
	add_child(stay_button)
	# Focus stays inside the overlay (the arrows are handled in _input; this covers Tab).
	for b: Button in [leave_button, stay_button]:
		b.focus_neighbor_top = NodePath(".")
		b.focus_neighbor_bottom = NodePath(".")
	UiKit.register_fx(self)


func _ready() -> void:
	apply_effect_settings()
	leave_button.focus_next = leave_button.get_path_to(stay_button)
	leave_button.focus_previous = leave_button.get_path_to(stay_button)
	stay_button.focus_next = stay_button.get_path_to(leave_button)
	stay_button.focus_previous = stay_button.get_path_to(leave_button)


## Show the overlay. `is_host` picks the warning copy; `ping_ms` (< 0 = unknown) feeds the
## client readout. Focus starts on Stay.
func open(is_host: bool, ping_ms: int = -1) -> void:
	_is_host = is_host
	_ping_ms = ping_ms
	_open = true
	_opened_frame = Engine.get_process_frames()
	visible = true
	_anim = "in"
	_anim_t = 0.0
	_apply_anim()
	_set_focus(1)
	queue_redraw()


## Update the client ping readout while open.
func set_ping(ping_ms: int) -> void:
	_ping_ms = ping_ms
	queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	_anim = "out"
	_anim_t = 0.0
	for b: Button in [leave_button, stay_button]:
		if b.has_focus():
			b.release_focus()
	_apply_anim()


func is_open() -> bool:
	return _open


func focus_name() -> String:
	return "leave" if _focus == 0 else "stay"


func body_text() -> String:
	return BODY_HOST if _is_host else BODY_CLIENT


func ping_text() -> String:
	if _is_host:
		return ""
	return PING_UNKNOWN if _ping_ms < 0 else PING_FMT % _ping_ms


## body_role: "warning" (host, WARNING_RED) or "mid" (client, TEXT_MID).
func debug_state() -> Dictionary:
	return {"open": _open, "focus": focus_name(), "body": body_text(),
		"body_role": "warning" if _is_host else "mid", "ping": ping_text(), "title": TITLE}


# ---- input -------------------------------------------------------------------------------

## Handles one event; returns true when the overlay consumed it (it is then marked handled).
func handle_event(event: InputEvent) -> bool:
	if not _open or event == null or event.is_echo():
		return false
	for a in PASS_THROUGH:
		if InputMap.has_action(a) and event.is_action(a):
			return false
	# Two buttons: left and right both move to the other one (wrapping), so from Stay either
	# direction reaches Leave Match and back.
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		_set_focus(1 - _focus)
		return true
	if event.is_action_pressed(&"ui_accept"):
		_activate(_focus)
		return true
	if event.is_action_pressed(&"ui_cancel") or (InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")):
		# The press that opened the overlay (same frame) must not close it again.
		if Engine.get_process_frames() == _opened_frame:
			return true
		_activate(1)
		return true
	return false


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


func _set_focus(i: int) -> void:
	_focus = clampi(i, 0, 1)
	var b := leave_button if _focus == 0 else stay_button
	if b.is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()
	queue_redraw()


func _activate(i: int) -> void:
	if not _open:
		return
	close()
	if i == 0:
		leave_confirmed.emit()
	else:
		stayed.emit()


# ---- animation ---------------------------------------------------------------------------

func step(dt: float) -> void:
	if _anim == "" or dt <= 0.0:
		return
	_anim_t += dt
	_apply_anim()


func _process(delta: float) -> void:
	step(delta)


func _apply_anim() -> void:
	var k := clampf(_anim_t / Palette.DUR_FAST, 0.0, 1.0)
	match _anim:
		"in":
			modulate.a = k
			var off := (1.0 - k) * SLIDE_PX if _slide else 0.0
			position = RECT.position - Vector2(0.0, off)
			if k >= 1.0:
				_anim = ""
		"out":
			modulate.a = 1.0 - k
			position = RECT.position
			if k >= 1.0:
				_anim = ""
				visible = false
		_:
			position = RECT.position
			modulate.a = 1.0 if _open else 0.0


# ---- effect contract ---------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_slide = not UiKit.reduce_motion()
	_rebuild_style()
	queue_redraw()


## Slide + fade in every mode except Reduce motion (fade only); Low effects drops the glow.
func effect_counts() -> Dictionary:
	return {"slide": _slide, "glow": not _low}


func _rebuild_style() -> void:
	_sb = UiKit.style_panel("danger", _low)
	_sb.bg_color = Color(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA)
	_sb.corner_radius_top_left = Palette.CUT_SM
	_sb.corner_radius_bottom_right = Palette.CUT_SM
	_sb.shadow_color = Color(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)


# ---- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, RECT.size)
	var o := RECT.position
	draw_style_box(_sb, r)
	UiKit.draw_brackets(self, r, Color(Palette.WARNING_RED, BRACKET_ALPHA))
	var hf := Palette.display_font()
	var bf := Palette.font()
	draw_string(hf, TITLE_AT - o, TITLE, HORIZONTAL_ALIGNMENT_LEFT, BODY_W, Palette.SIZE_HEADING,
		Palette.TEXT_HI)
	var pt := ping_text()
	if pt != "":
		var w := bf.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
		draw_string(bf, Vector2(PING_RIGHT - w, PING_BASELINE) - o, pt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Palette.SIZE_LABEL, Palette.TEXT_LO)
	draw_string(bf, BODY_AT - o, body_text(), HORIZONTAL_ALIGNMENT_LEFT, BODY_W, Palette.SIZE_LABEL,
		Palette.WARNING_RED if _is_host else Palette.TEXT_MID)
