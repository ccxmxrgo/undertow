class_name SonarTextField
extends Control
## Text field for player name, port and host address (04-UI-SPEC 4.1). One widget, three
## configs ("name" | "port" | "address") with their own charset, case, max length and commit
## validation. Works with keyboard, mouse and gamepad:
##   focused, not editing: ui_accept (Enter / Space / A) or a click starts editing (caret at the
##     end); Up / Down move focus as usual.
##   editing: typed characters insert at the caret (filtered by the charset; name is upper-cased),
##     Backspace / Delete, Left / Right / Home / End, Ctrl+V pastes (filtered, truncated to max),
##     Enter / A commits, Esc / B reverts. D-pad Up / Down cycle the character at the caret
##     through the config's order, gamepad X deletes before the caret, D-pad Right at the end
##     appends "A" / "0" / "." below max. Losing focus commits.
## A rejected character is not inserted: rejected_count grows, an "error" blip is requested and
## the edge flashes WARNING_RED for 200 ms. Every key or joypad press the field handles while
## editing is consumed, so the screen never sees ui_cancel / ui_accept while a field edits.
##
## The field renders its own well, value, caret and counter (no LineEdit child): a LineEdit
## treats Space as ui_accept-adjacent input and owns its caret blink, while this widget must
## route gamepad cycling, keep Esc away from the screen and follow Reduce motion exactly.
## Size and position come from the parent (no full-rect anchor preset). Effect contract:
## UiKit.register_fx, apply_effect_settings(), effect_counts() = {caret_blink, glow}.

signal committed(value: String)
signal cancelled
signal invalid(code: String)
signal editing_changed(on: bool)

const CONFIGS: Array[String] = ["name", "port", "address"]
const HEIGHT := 48.0  # Palette.SP_2XL field height
const INSET := 16.0  # Palette.SP_MD text inset
const CARET_W := 2.0
const CARET_H := 32.0
const BLINK_PERIOD := 1.0  # 0.5 s on / 0.5 s off (UI-SPEC 3.3)
const REJECT_SEC := 0.2
const IDLE_EDGE_ALPHA := 0.45
const GLOW_ALPHA := 0.28
const ELLIPSIS := "..."
const PORT_MIN := 1024
const PORT_MAX := 65535

const MAX_LEN := {"name": 12, "port": 5, "address": 64}
const PLACEHOLDERS := {"name": "DIVER", "port": "47474", "address": "100.x.y.z or host name"}
## Gamepad D-pad Right at the end appends this character (below max length).
const APPEND_CHAR := {"name": "A", "port": "0", "address": "."}
const DIGITS := "0123456789"
const UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const LOWER := "abcdefghijklmnopqrstuvwxyz"
## Gamepad cycle orders (UI-SPEC 4.1). They are also the full charsets, except that the
## address charset accepts upper-case letters too (typed or pasted; kept as typed).
const ORDERS := {
	"name": UPPER + DIGITS + " _-",
	"port": DIGITS,
	"address": DIGITS + ".:" + LOWER + "-[]",
}

var config: String = "name"
## The current text (the edit buffer while editing).
var value: String = ""
var placeholder: String = "DIVER"
## Caret position (0..value.length()).
var caret: int = 0
var rejected_count: int = 0
## Last blip requested ("" = none). Tests read it; the sound goes through /root/UiSounds.
var last_blip: String = ""
## Clipboard reader; injectable for tests. Returns the clipboard text.
var clipboard_fn: Callable = func() -> String: return DisplayServer.clipboard_get()

var _editing: bool = false
var _before: String = ""
var _reject_left: float = 0.0
var _blink_t: float = 0.0
var _view_start: int = 0
var _blink_enabled: bool = true
var _glow_enabled: bool = true


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_IBEAM
	custom_minimum_size = Vector2(160.0, HEIGHT)
	set_process(false)


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()


## Configures the field. Unknown configs fall back to "name". `initial` is sanitised (charset,
## case, max length) without reject feedback.
func setup(p_config: String, initial: String = "") -> void:
	config = p_config if CONFIGS.has(p_config) else "name"
	placeholder = PLACEHOLDERS[config]
	set_value(initial)


## Sets the value programmatically (sanitised, no signals). Stops editing without committing.
func set_value(v: String) -> void:
	value = _filter(v.strip_edges() if config != "name" else v)[0]
	value = value.substr(0, max_length())
	caret = value.length()
	_view_start = 0
	if _editing:
		_set_editing(false)
	queue_redraw()


func max_length() -> int:
	return MAX_LEN[config]


func is_editing() -> bool:
	return _editing


## The characters D-pad Up / Down cycle through for `cfg`, in order.
static func cycle_order(cfg: String) -> Array[String]:
	var out: Array[String] = []
	var s: String = ORDERS.get(cfg, ORDERS["name"])
	for i in s.length():
		out.append(s[i])
	return out


# ---- editing lifecycle ------------------------------------------------------------------

## Starts editing (grabs focus, caret at the end).
func begin_editing() -> void:
	if _editing:
		return
	if not has_focus() and is_inside_tree() and is_visible_in_tree():
		grab_focus()
	_before = value
	caret = value.length()
	_set_editing(true)


## Validates and stops editing. Emits committed(value), or reverts (with invalid(code) for an
## out-of-range port, invalid("empty") for an empty name).
func commit() -> void:
	if not _editing:
		return
	var v := value
	match config:
		"name":
			v = v.strip_edges()
			while v.contains("  "):
				v = v.replace("  ", " ")
			if v.is_empty():
				_revert()
				invalid.emit("empty")
				return
		"port":
			var n := v.to_int() if v.is_valid_int() else -1
			if n < PORT_MIN or n > PORT_MAX:
				_revert()
				invalid.emit("port_range")
				return
			v = str(n)
		"address":
			v = v.strip_edges()
	value = v
	caret = value.length()
	_set_editing(false)
	committed.emit(value)


## Reverts to the value before editing and stops editing.
func cancel() -> void:
	if not _editing:
		return
	_revert()
	cancelled.emit()


func _revert() -> void:
	value = _before
	caret = value.length()
	_set_editing(false)


func _set_editing(on: bool) -> void:
	if _editing == on:
		return
	_editing = on
	_blink_t = 0.0
	_view_start = 0
	set_process(on or _reject_left > 0.0)
	set_process_input(on)
	queue_redraw()
	editing_changed.emit(on)


# ---- input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _editing:
				begin_editing()
				_blip("confirm")
			else:
				caret = _caret_from_x(mb.position.x)
				_blink_t = 0.0
				queue_redraw()
			accept_event()
		return
	if not _editing:
		if event.is_action_pressed(&"ui_accept") and not event.is_echo():
			begin_editing()
			_blip("confirm", event)
			accept_event()
		return
	if event is InputEventKey:
		if _key_input(event as InputEventKey):
			accept_event()
	elif event is InputEventJoypadButton:
		if _joy_input(event as InputEventJoypadButton):
			accept_event()
	elif event is InputEventJoypadMotion:
		accept_event()  # the stick must not move focus away mid-edit


## A click outside the field while editing commits it (the click may not move focus).
func _input(event: InputEvent) -> void:
	if not _editing or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and not get_global_rect().has_point(mb.global_position):
		commit()


func _key_input(k: InputEventKey) -> bool:
	if not k.pressed:
		# Swallow releases of keys we act on, so the screen sees no half events.
		return k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE] or _printable(k)
	var cmd := k.ctrl_pressed or k.meta_pressed
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				commit()
				_blip("confirm", k)
			return true
		KEY_ESCAPE:
			if not k.echo:
				cancel()
				_blip("back", k)
			return true
		KEY_BACKSPACE:
			_delete_before()
			return true
		KEY_DELETE:
			if caret < value.length():
				value = value.erase(caret, 1)
				_changed()
			return true
		KEY_LEFT:
			_move_caret(-1)
			return true
		KEY_RIGHT:
			_move_caret(1)
			return true
		KEY_HOME:
			caret = 0
			_changed()
			return true
		KEY_END:
			caret = value.length()
			_changed()
			return true
		KEY_UP, KEY_DOWN:
			return true  # keep focus while editing
		KEY_V:
			if cmd:
				paste()
				return true
	if cmd:
		return false
	if _printable(k):
		insert_text(char(k.unicode))
		return true
	return false


func _printable(k: InputEventKey) -> bool:
	return k.unicode >= 32 and k.unicode != 127 and not (k.ctrl_pressed or k.meta_pressed)


func _joy_input(b: InputEventJoypadButton) -> bool:
	if not b.pressed:
		return b.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_DPAD_UP,
				JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
	match b.button_index:
		JOY_BUTTON_A:
			commit()
			_blip("confirm", b)
			return true
		JOY_BUTTON_B:
			cancel()
			_blip("back", b)
			return true
		JOY_BUTTON_X:
			_delete_before()
			return true
		JOY_BUTTON_DPAD_UP:
			cycle(1)
			return true
		JOY_BUTTON_DPAD_DOWN:
			cycle(-1)
			return true
		JOY_BUTTON_DPAD_LEFT:
			_move_caret(-1)
			return true
		JOY_BUTTON_DPAD_RIGHT:
			if caret >= value.length():
				if value.length() < max_length():
					insert_text(APPEND_CHAR[config])
			else:
				_move_caret(1)
			return true
	return false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_EXIT:
			if _editing:
				commit()
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_RESIZED:
			queue_redraw()


# ---- text operations --------------------------------------------------------------------

## Inserts `s` at the caret after the charset filter and the max length. Anything dropped is a
## rejection (error blip + red flash). Returns the number of characters inserted.
func insert_text(s: String) -> int:
	var res := _filter(s)
	var ok: String = res[0]
	var dropped: bool = res[1]
	var room := maxi(max_length() - value.length(), 0)
	if ok.length() > room:
		ok = ok.substr(0, room)
		dropped = true
	if not ok.is_empty():
		value = value.insert(caret, ok)
		caret += ok.length()
		_changed()
	if dropped:
		_reject()
	return ok.length()


## Pastes the clipboard (outer whitespace trimmed, filtered, truncated to max length).
func paste() -> void:
	var raw := ""
	if clipboard_fn.is_valid():
		raw = str(clipboard_fn.call())
	# Bound the work on a huge clipboard before filtering (T-04-12).
	raw = raw.strip_edges().substr(0, max_length() * 4 + 16)
	if raw.is_empty():
		return
	insert_text(raw)


## Cycles the character at the caret (the last one when the caret is at the end) through the
## config order; dir +1 = next, -1 = previous. An empty field starts at the order's first
## (or last) character.
func cycle(dir: int) -> void:
	var order := cycle_order(config)
	if value.is_empty():
		if max_length() > 0:
			value = order[0] if dir > 0 else order[order.size() - 1]
			caret = 1
			_changed()
			_blip("move")
		return
	var idx := caret if caret < value.length() else value.length() - 1
	var cur := order.find(value[idx])
	var nxt: int
	if cur < 0:
		nxt = 0 if dir > 0 else order.size() - 1
	else:
		nxt = posmod(cur + dir, order.size())
	value = value.substr(0, idx) + order[nxt] + value.substr(idx + 1)
	_changed()
	_blip("move")


func _delete_before() -> void:
	if caret > 0:
		value = value.erase(caret - 1, 1)
		caret -= 1
		_changed()


func _move_caret(d: int) -> void:
	caret = clampi(caret + d, 0, value.length())
	_changed()


func _changed() -> void:
	caret = clampi(caret, 0, value.length())
	_blink_t = 0.0
	queue_redraw()


## [kept text, any character dropped] for `s` under the config charset and case.
func _filter(s: String) -> Array:
	var out := ""
	var dropped := false
	for i in s.length():
		var c := s[i]
		match config:
			"name":
				c = c.to_upper()
			"address":
				if UPPER.contains(c):
					out += c
					continue
		if c.length() == 1 and ORDERS[config].contains(c):
			out += c
		else:
			dropped = true
	return [out, dropped]


func _reject() -> void:
	rejected_count += 1
	_reject_left = REJECT_SEC
	set_process(true)
	_blip("error")
	queue_redraw()


## Requests a blip. confirm / back caused by a real ui_accept / ui_cancel event are already
## played by the UiSounds observer, so only the request is recorded for those.
func _blip(blip_name: String, event: InputEvent = null) -> void:
	last_blip = blip_name
	if event != null and ((blip_name == "confirm" and event.is_action_pressed(&"ui_accept"))
			or (blip_name == "back" and event.is_action_pressed(&"ui_cancel"))):
		return
	var snd := get_node_or_null(^"/root/UiSounds")
	if snd != null and snd.has_method(&"play"):
		snd.call(&"play", blip_name)


# ---- time -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Advances the caret blink and the reject flash by `delta` seconds.
func tick(delta: float) -> void:
	var redraw := false
	if _reject_left > 0.0:
		_reject_left = maxf(_reject_left - delta, 0.0)
		redraw = true
	if _editing:
		var was := caret_visible()
		_blink_t += delta
		redraw = redraw or was != caret_visible()
	if not _editing and _reject_left <= 0.0:
		set_process(false)
	if redraw:
		queue_redraw()


## True when the caret is drawn now: editing, and on the "on" half of the blink (always on
## under Reduce motion).
func caret_visible() -> bool:
	if not _editing:
		return false
	if not _blink_enabled:
		return true
	return fmod(_blink_t, BLINK_PERIOD) < BLINK_PERIOD * 0.5


# ---- look -------------------------------------------------------------------------------

## idle | focused | editing | rejected
func edge_role() -> String:
	if _reject_left > 0.0:
		return "rejected"
	if _editing:
		return "editing"
	if has_focus():
		return "focused"
	return "idle"


static func role_color(role: String) -> Color:
	match role:
		"rejected":
			return Palette.WARNING_RED
		"editing":
			return Palette.SONAR_PALE
		"focused":
			return Palette.SONAR
	return Color(Palette.SONAR, IDLE_EDGE_ALPHA)


func edge_color() -> Color:
	return role_color(edge_role())


## "{n}/{max}" while editing a name or address; "" otherwise.
func counter_text() -> String:
	if not _editing or config == "port":
		return ""
	return "%d/%d" % [value.length(), max_length()]


func _font() -> Font:
	return Palette.font()


func _text_w(s: String) -> float:
	return _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_BODY).x


## Width available for the value text.
func _avail() -> float:
	var w := size.x - INSET * 2.0
	var ct := counter_text()
	if not ct.is_empty():
		w -= _font().get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x + INSET
	return maxf(w, 1.0)


## The text drawn now: while editing, the window that keeps the caret visible; otherwise the
## value truncated with "..." to the well.
func display_text() -> String:
	var avail := _avail()
	if _editing:
		_view_start = clampi(_view_start, 0, caret)
		while _view_start < caret and _text_w(value.substr(_view_start, caret - _view_start)) > avail:
			_view_start += 1
		var end := caret
		while end < value.length() and _text_w(value.substr(_view_start, end + 1 - _view_start)) <= avail:
			end += 1
		return value.substr(_view_start, end - _view_start)
	if _text_w(value) <= avail:
		return value
	var n := value.length()
	while n > 0 and _text_w(value.substr(0, n) + ELLIPSIS) > avail:
		n -= 1
	return value.substr(0, n) + ELLIPSIS


func _caret_from_x(x: float) -> int:
	var shown := display_text()
	var rel := x - INSET
	for i in shown.length() + 1:
		var w := _text_w(shown.substr(0, i))
		var nx := _text_w(shown.substr(0, i + 1)) if i < shown.length() else w
		if rel <= (w + nx) * 0.5:
			return clampi(_view_start + i, 0, value.length())
	return value.length()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var pts := UiKit.chamfer_points(r, Palette.CUT_SM)
	if _editing and _glow_enabled:
		# Panel glow SONAR 28% (Full only; static under Reduce motion).
		for g: Array in [[8.0, GLOW_ALPHA * 0.5], [4.0, GLOW_ALPHA]]:
			var gr: float = g[0]
			draw_colored_polygon(UiKit.chamfer_points(r.grow(gr), Palette.CUT_SM + gr * 0.5),
					Color(Palette.SONAR, g[1]))
	draw_colored_polygon(pts, Palette.ABYSS_800)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, edge_color(), Palette.EDGE, true)
	var f := _font()
	var fs := Palette.SIZE_BODY
	var base := size.y * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	var shown := display_text()
	if value.is_empty() and not _editing:
		draw_string(f, Vector2(INSET, base), placeholder, HORIZONTAL_ALIGNMENT_LEFT, _avail(), fs, Palette.TEXT_LO)
	elif not shown.is_empty():
		draw_string(f, Vector2(INSET, base), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT_HI)
	if caret_visible():
		var cx := INSET + _text_w(value.substr(_view_start, caret - _view_start))
		draw_rect(Rect2(cx, (size.y - CARET_H) * 0.5, CARET_W, CARET_H), Palette.SONAR_PALE)
	var ct := counter_text()
	if not ct.is_empty():
		var ls := Palette.SIZE_LABEL
		var cw := f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		var cb := size.y * 0.5 + (f.get_ascent(ls) - f.get_descent(ls)) * 0.5
		draw_string(f, Vector2(size.x - INSET - cw, cb), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Palette.TEXT_LO)


# ---- effect contract --------------------------------------------------------------------

## Low effects: no editing glow (caret still blinks). Reduce motion: steady caret, static glow.
func apply_effect_settings() -> void:
	_blink_enabled = not UiKit.reduce_motion()
	_glow_enabled = not UiKit.low_effects()
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"caret_blink": _blink_enabled, "glow": _glow_enabled}


func debug_state() -> Dictionary:
	return {
		"config": config,
		"value": value,
		"editing": _editing,
		"caret": caret,
		"rejected_count": rejected_count,
		"edge_color_role": edge_role(),
	}
