class_name ConnectDialog
extends Control
## Connect dialog (04-UI-SPEC 8.3, D-21, D-06, Pitfall 9). Opened by the Play Online screen on
## Join Match. It owns the join: start() connects to the session's connect_stage /
## connect_error signals first (join() may emit an error synchronously) and then calls
## session.join(address, port).
##
## Geometry is ConfirmDialog's (U-9.6): ABYSS_900 70% backdrop, panel x 600..1320 y 380..700 with
## the opaque ABYSS_900 94% backing, Heading title at baseline 444, divider y 460, Body text
## wrapping in 656 px from baseline 500, 304 x 64 buttons at y 604 (x 632 and x 984).
##
## Progress: the stages CONNECTING -> CHECKING VERSION -> SYNCING CLOCKS cross-fade (DUR_BASE;
## instant under Reduce motion), a ping ring at (1272, 428) expands r 8 -> 28 with alpha 1 -> 0
## every 1.0 s (static r 20 at 0.6 under Reduce motion), an elapsed "{n} S" counter and one
## Cancel button (focused). Cancel / Esc / B disconnects and closes (signal closed).
## Error: danger chrome, the 8.3 / section 15 title and body for the code, Try Again (primary,
## focused; re-joins) and Back (Esc / B). Reaching the "lobby" stage emits joined; the screen
## that opened the dialog navigates to the Lobby. The 8 s NO ANSWER timeout lives in NetSession
## (CONNECT_TIMEOUT_S); the dialog only shows it (T-04-36).

signal joined
signal closed

const DIM_ALPHA := 0.7
const PANEL_RECT := Rect2(600, 380, 720, 320)
const TITLE_AT := Vector2(632, 444)  # baseline
const RULE_Y := 460.0
const BODY_AT := Vector2(632, 500)  # first baseline
const BODY_W := 656.0
const BUTTON_SIZE := Vector2(304, 64)
const PRIMARY_POS := Vector2(632, 604)
const SAFE_POS := Vector2(984, 604)
const RULE_ALPHA := 0.35
const BRACKET_ALPHA := 0.8
const BACKING_ALPHA := 0.94
const RING_CENTER := Vector2(1272, 428)
const RING_R_MIN := 8.0
const RING_R_MAX := 28.0
const RING_STATIC_R := 20.0
const RING_STATIC_ALPHA := 0.6
const RING_PERIOD := 1.0
const ELAPSED_RIGHT := 1288.0
const ELAPSED_BASELINE := 568.0
const ELAPSED_W := 160.0

## Copy (04-UI-SPEC 15).
const STAGES: Array[String] = ["connecting", "auth", "sync"]
const STAGE_TITLES := {
	"connecting": "CONNECTING",
	"auth": "CHECKING VERSION",
	"sync": "SYNCING CLOCKS",
}
const STAGE_BODIES := {
	"connecting": "Calling {address}. This can take a few seconds.",
	"auth": "Connected. Checking that you both run the same game build.",
	"sync": "Lining up your clock with {HOST}'s for a synced start.",
}
## Error codes NetSession emits through connect_error; anything else reads as "lost".
const ERROR_CODES: Array[String] = ["timeout", "resolve", "version", "full", "in_match", "lost"]
const ERROR_TITLES := {
	"timeout": "NO ANSWER",
	"resolve": "ADDRESS NOT FOUND",
	"version": "DIFFERENT VERSIONS",
	"full": "LOBBY FULL",
	"in_match": "MATCH IN PROGRESS",
	"lost": "CONNECTION LOST",
}
const ERROR_BODIES := {
	"timeout": "No answer from host after 8 s. Check that the host allowed UNDERTOW through Windows Firewall and that you are both connected in Tailscale.",
	"resolve": "Could not find {address}. Check the spelling, or use the host's 100.x.y.z Tailscale address.",
	"version": "The host runs UNDERTOW {host_version} and you run {my_version}. Everyone needs the same build.",
	"full": "This lobby already has 4 subs.",
	"in_match": "The host is in a match. Try again when they are back in the lobby.",
	"lost": "The link to the host dropped while joining. Try again.",
}
const ELAPSED_FORMAT := "%d S"
const CANCEL_TEXT := "Cancel"
const TRY_AGAIN_TEXT := "Try Again"
const BACK_TEXT := "Back"
## Shown for {HOST} until the host's roster row arrives.
const HOST_FALLBACK := "THE HOST"

## The session (NetSession or a test fake with join / leave and the two signals).
var session: Node = null
var address: String = ""
var port: int = 0

var title_label: Label
var body_label: Label
var elapsed_label: Label
var cancel_button: Button
var try_button: Button
var back_button: Button
var panel: Control

## "progress" | "error" | "joined" | "closed"
var mode: String = "progress"
var stage: String = "connecting"
var error_code: String = ""
var elapsed: float = 0.0

var _old_title: Label
var _old_body: Label
var _fade: Tween
var _ring: Control
var _ring_t: float = 0.0
var _connected_signals := false


## Draws through a callable.
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	UiKit.register_fx(self)
	apply_effect_settings()
	_focus_default()


func _exit_tree() -> void:
	_disconnect_session()


## Configures the dialog. Call before start().
func setup(p_session: Node, p_address: String, p_port: int) -> void:
	session = p_session
	address = p_address
	port = p_port


## Connects to the session signals, then joins. Safe to call again (Try Again).
func start() -> void:
	_connect_session()
	_begin_join()


# ---- building ----------------------------------------------------------------------------

func _build() -> void:
	UiLayout.fill_rect(self)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.alpha(Palette.ABYSS_900, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	panel = Painter.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	(panel as Painter).painter = _paint_panel
	add_child(panel)
	_ring = Painter.new()
	_ring.name = "PingRing"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.position = RING_CENTER - Vector2(RING_R_MAX + 2.0, RING_R_MAX + 2.0)
	_ring.size = Vector2(RING_R_MAX + 2.0, RING_R_MAX + 2.0) * 2.0
	(_ring as Painter).painter = _paint_ring
	add_child(_ring)
	_old_title = _title()
	_old_title.name = "OldTitle"
	_old_title.modulate.a = 0.0
	_old_body = _body()
	_old_body.name = "OldBody"
	_old_body.modulate.a = 0.0
	title_label = _title()
	body_label = _body()
	var f := Palette.font()
	elapsed_label = Label.new()
	elapsed_label.name = "Elapsed"
	elapsed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elapsed_label.add_theme_font_override("font", f)
	elapsed_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	elapsed_label.add_theme_color_override("font_color", Palette.TEXT_LO)
	elapsed_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	elapsed_label.position = Vector2(ELAPSED_RIGHT - ELAPSED_W, ELAPSED_BASELINE - f.get_ascent(Palette.SIZE_LABEL))
	elapsed_label.size = Vector2(ELAPSED_W, f.get_height(Palette.SIZE_LABEL))
	add_child(elapsed_label)
	cancel_button = _button("Cancel", CANCEL_TEXT, "default", SAFE_POS, _on_cancel)
	try_button = _button("TryAgain", TRY_AGAIN_TEXT, "primary", PRIMARY_POS, _on_try_again)
	back_button = _button("Back", BACK_TEXT, "default", SAFE_POS, _on_back)
	_wire_focus()
	_show_progress("connecting", false)


func _title() -> Label:
	var hf := Palette.display_font()
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", hf)
	l.add_theme_font_size_override("font_size", Palette.SIZE_HEADING)
	l.add_theme_color_override("font_color", Palette.TEXT_HI)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.clip_text = true
	l.position = Vector2(TITLE_AT.x, TITLE_AT.y - hf.get_ascent(Palette.SIZE_HEADING))
	l.size = Vector2(BODY_W - (RING_R_MAX * 2.0 + Palette.SP_MD), hf.get_height(Palette.SIZE_HEADING))
	add_child(l)
	return l


func _body() -> Label:
	var bf := Palette.font()
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", bf)
	l.add_theme_font_size_override("font_size", Palette.SIZE_BODY)
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.position = Vector2(BODY_AT.x, BODY_AT.y - bf.get_ascent(Palette.SIZE_BODY))
	l.custom_minimum_size = Vector2(BODY_W, 0)
	l.size = Vector2(BODY_W, PRIMARY_POS.y - Palette.SP_MD - l.position.y)
	add_child(l)
	return l


func _button(node_name: String, text: String, variant: String, at: Vector2, cb: Callable) -> Button:
	var b := UiKit.make_button(text, "", variant, int(BUTTON_SIZE.y))
	b.name = node_name
	b.position = at
	b.size = BUTTON_SIZE
	b.pressed.connect(cb)
	add_child(b)
	return b


## Modal focus: every direction and Tab stay on the visible buttons.
func _wire_focus() -> void:
	for b: Button in [cancel_button, try_button, back_button]:
		var own := b.get_path_to(b)
		b.focus_neighbor_top = own
		b.focus_neighbor_bottom = own
		b.focus_neighbor_left = own
		b.focus_neighbor_right = own
		b.focus_next = own
		b.focus_previous = own
	try_button.focus_neighbor_right = try_button.get_path_to(back_button)
	try_button.focus_next = try_button.get_path_to(back_button)
	try_button.focus_previous = try_button.get_path_to(back_button)
	back_button.focus_neighbor_left = back_button.get_path_to(try_button)
	back_button.focus_next = back_button.get_path_to(try_button)
	back_button.focus_previous = back_button.get_path_to(try_button)


# ---- session -----------------------------------------------------------------------------

func _connect_session() -> void:
	if _connected_signals or session == null:
		return
	if session.has_signal(&"connect_stage"):
		session.connect(&"connect_stage", _on_stage)
	if session.has_signal(&"connect_error"):
		session.connect(&"connect_error", _on_error)
	_connected_signals = true


func _disconnect_session() -> void:
	if not _connected_signals or session == null or not is_instance_valid(session):
		return
	if session.is_connected(&"connect_stage", _on_stage):
		session.disconnect(&"connect_stage", _on_stage)
	if session.is_connected(&"connect_error", _on_error):
		session.disconnect(&"connect_error", _on_error)
	_connected_signals = false


func _begin_join() -> void:
	elapsed = 0.0
	_ring_t = 0.0
	error_code = ""
	_show_progress("connecting", false)
	if session == null:
		_show_error("lost", {})
		return
	if session.has_method(&"is_offline") and not bool(session.call(&"is_offline")):
		session.call(&"leave")
	var err: int = int(session.call(&"join", address, port))
	# join() may already have emitted connect_error (resolve / lost); otherwise show "lost".
	if err != OK and mode == "progress":
		_show_error("lost", {})


func _on_stage(s: String) -> void:
	if mode != "progress":
		return
	if s == "lobby":
		mode = "joined"
		_disconnect_session()
		joined.emit()
		return
	if STAGES.has(s):
		_show_progress(s, true)


func _on_error(code: String, info: Dictionary) -> void:
	if mode != "progress":
		return
	_show_error(code, info)


# ---- states ------------------------------------------------------------------------------

## Address as shown: "{address}:{port}", IPv6 in brackets.
func display_address() -> String:
	return NetAddress.host_port(address, port)


func _host_name() -> String:
	if session != null and session.has_method(&"lobby_rows"):
		for r: Variant in session.call(&"lobby_rows"):
			if r is Dictionary and bool((r as Dictionary).get("host", false)):
				var n := str((r as Dictionary).get("name", ""))
				if n != "":
					return n.to_upper()
	return HOST_FALLBACK


static func stage_title(s: String) -> String:
	return str(STAGE_TITLES.get(s, STAGE_TITLES["connecting"]))


func stage_body(s: String) -> String:
	var t := str(STAGE_BODIES.get(s, STAGE_BODIES["connecting"]))
	return t.replace("{address}", display_address()).replace("{HOST}", _host_name())


static func error_title(code: String) -> String:
	return str(ERROR_TITLES.get(code if ERROR_CODES.has(code) else "lost"))


func error_body(code: String, info: Dictionary = {}) -> String:
	var t := str(ERROR_BODIES.get(code if ERROR_CODES.has(code) else "lost"))
	var shown := address if not address.contains(":") or address.begins_with("[") else "[%s]" % address
	var hv := str(info.get("host_version", ""))
	return t.replace("{address}", shown).replace("{host_version}", hv if hv != "" else "?") \
		.replace("{my_version}", NetProtocol.game_version())


func _show_progress(s: String, animate: bool) -> void:
	var changed := mode != "progress" or stage != s
	mode = "progress"
	stage = s
	_set_texts(stage_title(s), stage_body(s), animate and changed)
	cancel_button.visible = true
	try_button.visible = false
	back_button.visible = false
	_ring.visible = true
	_update_elapsed()
	panel.queue_redraw()
	_focus_default()


func _show_error(code: String, info: Dictionary) -> void:
	mode = "error"
	error_code = code if ERROR_CODES.has(code) else "lost"
	_set_texts(error_title(code), error_body(code, info), true)
	cancel_button.visible = false
	try_button.visible = true
	back_button.visible = true
	_ring.visible = false
	elapsed_label.text = ""
	panel.queue_redraw()
	_focus_default()


## Swaps the title and body; the old text fades out while the new fades in (DUR_BASE).
func _set_texts(t: String, b: String, animate: bool) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_old_title.text = title_label.text
	_old_body.text = body_label.text
	title_label.text = t
	body_label.text = b
	if not animate or UiKit.reduce_motion() or not is_inside_tree():
		title_label.modulate.a = 1.0
		body_label.modulate.a = 1.0
		_old_title.modulate.a = 0.0
		_old_body.modulate.a = 0.0
		return
	title_label.modulate.a = 0.0
	body_label.modulate.a = 0.0
	_old_title.modulate.a = 1.0
	_old_body.modulate.a = 1.0
	_fade = create_tween().set_parallel(true)
	for l: Label in [title_label, body_label]:
		_fade.tween_property(l, "modulate:a", 1.0, Palette.DUR_BASE)
	for l: Label in [_old_title, _old_body]:
		_fade.tween_property(l, "modulate:a", 0.0, Palette.DUR_BASE)


func _focus_default() -> void:
	if not is_inside_tree():
		return
	var b := try_button if mode == "error" else cancel_button
	if b.visible and b.is_visible_in_tree():
		b.grab_focus()


func _update_elapsed() -> void:
	elapsed_label.text = ELAPSED_FORMAT % int(floor(elapsed)) if mode == "progress" else ""


# ---- actions -----------------------------------------------------------------------------

func _on_cancel() -> void:
	if mode != "progress":
		return
	_close()


func _on_back() -> void:
	if mode != "error":
		return
	_close()


func _on_try_again() -> void:
	if mode != "error":
		return
	_begin_join()


func _close() -> void:
	mode = "closed"
	_disconnect_session()
	if session != null and is_instance_valid(session) and session.has_method(&"leave"):
		session.call(&"leave")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"ui_cancel"):
		return
	if mode != "progress" and mode != "error":
		return
	get_viewport().set_input_as_handled()
	cancel()


## Esc / B: Cancel while connecting, Back on an error.
func cancel() -> void:
	if mode == "progress":
		_on_cancel()
	elif mode == "error":
		_on_back()


# ---- time and painting -------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Advances the elapsed counter and the ping ring by `delta` seconds.
func tick(delta: float) -> void:
	if mode != "progress":
		return
	var before := int(floor(elapsed))
	elapsed += delta
	_ring_t = fmod(_ring_t + delta, RING_PERIOD)
	if int(floor(elapsed)) != before:
		_update_elapsed()
	if _ring != null:
		_ring.queue_redraw()


## [radius, alpha] of the ping ring now.
func ring_state() -> Array[float]:
	if UiKit.reduce_motion():
		return [RING_STATIC_R, RING_STATIC_ALPHA]
	var p := _ring_t / RING_PERIOD
	return [lerpf(RING_R_MIN, RING_R_MAX, p), 1.0 - p]


func _paint_ring(c: CanvasItem) -> void:
	var st := ring_state()
	c.draw_arc(Vector2(RING_R_MAX + 2.0, RING_R_MAX + 2.0), st[0], 0.0, TAU, 48,
		Palette.alpha(Palette.SONAR, st[1]), Palette.EDGE, true)


func _paint_panel(c: CanvasItem) -> void:
	var err := mode == "error"
	var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
	c.draw_colored_polygon(UiKit.chamfer_points(r, Palette.CUT_MD), Palette.alpha(Palette.ABYSS_900, BACKING_ALPHA))
	var sb := UiKit.style_panel("danger" if err else "default")
	if err:
		sb.shadow_color = Palette.alpha(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)
	c.draw_style_box(sb, r)
	var accent := Palette.WARNING_RED if err else Palette.SONAR
	UiKit.draw_brackets(c, r, Palette.alpha(accent, BRACKET_ALPHA))
	var y := RULE_Y - PANEL_RECT.position.y
	var x0 := TITLE_AT.x - PANEL_RECT.position.x
	c.draw_line(Vector2(x0, y), Vector2(x0 + BODY_W, y), Palette.alpha(accent, RULE_ALPHA), Palette.EDGE)


# ---- effects contract --------------------------------------------------------------------

func apply_effect_settings() -> void:
	if UiKit.reduce_motion() and _fade != null and _fade.is_valid():
		_fade.kill()
		title_label.modulate.a = 1.0
		body_label.modulate.a = 1.0
		_old_title.modulate.a = 0.0
		_old_body.modulate.a = 0.0
	if _ring != null:
		_ring.queue_redraw()


func effect_counts() -> Dictionary:
	var reduce := UiKit.reduce_motion()
	return {"ping_ring": not reduce, "stage_fade": not reduce}


# ---- test seams --------------------------------------------------------------------------

func debug_state() -> Dictionary:
	var buttons: Array = []
	for b: Button in [try_button, back_button, cancel_button]:
		if b.visible:
			buttons.append(b.text)
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return {
		"mode": mode,
		"stage": stage,
		"title": title_label.text,
		"body": body_label.text,
		"elapsed": elapsed_label.text,
		"error_code": error_code,
		"buttons": buttons,
		"focus": (fo as Button).text if fo is Button else "",
		"ring_visible": _ring.visible,
	}
