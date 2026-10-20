class_name OnlineMenu
extends Control
## PLAY ONLINE (04-UI-SPEC 8, NET-01, NET-07, D-14, D-15, D-20). Left glass panel: YOUR SUB
## (Name and Port fields), HOST (Host Match) and JOIN (Address field, Paste | Join Match).
## Right glass panel (8.1): this PC's addresses (Tailscale 100.64.0.0/10 first and highlighted,
## then LAN; loopback and link-local never listed; refreshed on open and every 5 s), the four
## HOW TO CONNECT steps (port read from the Port field), the guide and firewall lines.
## VERSION {v} bottom right so friends can compare builds (D-21).
##
## Focus (8.2, wraps): Name -> Port -> Host Match -> Address -> (Paste | Join Match) -> Name.
## On the button row Left / Right move between Paste and Join Match; a disabled Join Match
## (empty address) is skipped. Fields start editing on Enter / A / click and own every key
## while editing (SonarTextField consumes Esc / Enter), so Esc while a field edits only reverts
## that field. Esc / B with no field editing wipes back to the main menu (nothing is lost).
## Row key handling runs in each control's gui_input signal (before the control's own
## _gui_input and before GUI focus navigation), so UiSounds still sees every press in _input.
##
## Initial focus: first visit (Settings.player_name_set false) puts the Name field in editing
## mode with the prompt on the status line; committing sets player_name_set and saves.
## Otherwise Join Match when a saved address exists, else Host Match. A return message from
## the session (kicked / closed / lost) is shown on the status line on open, with focus on
## Join Match.

const MENU_SCENE := "res://scenes/main_menu.tscn"
## Plan 04-15 creates the lobby scene; referenced only by path here.
const LOBBY_SCENE := "res://scenes/lobby.tscn"

## Copy (04-UI-SPEC 15).
const TITLE := "PLAY ONLINE"
const SUBTITLE := "Host a match or join a friend. 2 to 4 subs, same song, same game version."
const CAPTION_SUB := "YOUR SUB"
const CAPTION_HOST := "HOST"
const CAPTION_JOIN := "JOIN"
const ROW_LABELS := {"name": "Name", "port": "Port", "address": "Address"}
const HINT_NAME := "Shown to friends. Up to 12 letters, digits, spaces, _ or -."
const HINT_PORT := "UDP port. Host and friends must use the same number. Default 47474."
const HOST_LINE := "Open a lobby on this PC. Friends join with your address."
const JOIN_LINE := "Ask the host for their address. Tailscale addresses start with 100."
const HOST_TEXT := "Host Match"
const PASTE_TEXT := "Paste"
const JOIN_TEXT := "Join Match"
const VERSION_FORMAT := "VERSION %s"
const FIRST_VISIT_PROMPT := "Pick a name your friends will see, then press Enter."
const CAPTION_CONNECT := "CONNECT WITH FRIENDS"
const CAPTION_ADDRESSES := "THIS PC'S ADDRESSES"
const CHIP_TAILSCALE := "TAILSCALE"
const CHIP_LAN := "LAN"
const ADDR_TAILSCALE := "Give the Tailscale address to friends."
const ADDR_NO_TAILSCALE := "No Tailscale address. Friends outside your home network need Tailscale."
const ADDR_NONE := "No network address found. Check that this PC is online."
const CAPTION_HOW := "HOW TO CONNECT"
const STEPS: Array[String] = [
	"1. Everyone installs Tailscale (free) and joins the host's tailnet.",
	"2. The host picks Host Match and shares the Tailscale address above.",
	"3. Friends type that address, keep port {port}, and pick Join Match.",
	"4. Same Wi-Fi or LAN? Use the LAN address instead.",
]
const GUIDE_LINE := "Full guide: ONLINE_SETUP.md in the game folder."
const FIREWALL_LINE := "First time hosting? Click Allow when Windows Firewall asks."
const HINT_KEYS := "UP DOWN MOVE  ·  ENTER SELECT OR EDIT  ·  CTRL+V PASTE  ·  ESC BACK"
const HINT_PAD := "D-PAD MOVE  ·  A SELECT OR EDIT  ·  X DELETE  ·  B BACK"
const HINT_KEYS_EDIT := "TYPE TO EDIT  ·  ENTER DONE  ·  ESC UNDO"
const HINT_PAD_EDIT := "D-PAD UP DOWN LETTER  ·  LEFT RIGHT MOVE  ·  X DELETE  ·  A DONE  ·  B UNDO"
const ERR_PORT_BUSY := "Could not open port {port}. Another program or another UNDERTOW is using it. Pick another port."
const ERR_HOST := "Could not start hosting (error {code}). Check your network and try again."
const ERR_PORT_RANGE := "Port must be between 1024 and 65535."
const ERR_CLIPBOARD := "Clipboard has no address to paste."
const RETURN_MESSAGES := {
	"kicked": "The host removed you from the lobby.",
	"closed": "The host closed the lobby.",
	"lost": "Lost the connection to the host's lobby.",
}

## Focus slots in order.
const FOCUS: Array[String] = ["name", "port", "host", "address", "paste", "join"]
const F_NAME := 0
const F_PORT := 1
const F_HOST := 2
const F_ADDRESS := 3
const F_PASTE := 4
const F_JOIN := 5

## Layout (1920x1080 design pixels, UI-SPEC 8 / 8.1).
const TITLE_POS := Vector2(64.0, 104.0)
const SUBTITLE_POS := Vector2(64.0, 140.0)
const LEFT_RECT := Rect2(64.0, 176.0, 880.0, 728.0)
const RIGHT_RECT := Rect2(976.0, 176.0, 880.0, 728.0)
const CAPTION_SUB_POS := Vector2(96.0, 216.0)
const CAPTION_HOST_POS := Vector2(96.0, 472.0)
const CAPTION_JOIN_POS := Vector2(96.0, 648.0)
const ROW_X := 96.0
const ROW_W := 816.0
const ROW_H := 64.0
const LABEL_X := 120.0
const NAME_ROW := Rect2(96.0, 240.0, 816.0, 64.0)
const PORT_ROW := Rect2(96.0, 312.0, 816.0, 64.0)
const HOST_RECT := Rect2(96.0, 520.0, 816.0, 64.0)
const ADDRESS_ROW := Rect2(96.0, 664.0, 816.0, 64.0)
const PASTE_RECT := Rect2(96.0, 744.0, 200.0, 64.0)
const JOIN_RECT := Rect2(312.0, 744.0, 600.0, 64.0)
const NAME_WELL := Rect2(400.0, 248.0, 496.0, 48.0)
const PORT_WELL := Rect2(400.0, 320.0, 160.0, 48.0)
const ADDRESS_WELL := Rect2(400.0, 672.0, 496.0, 48.0)
const ROW_HINT_POS := Vector2(120.0, 408.0)
const DIVIDER_YS: Array[float] = [432.0, 608.0]
const HOST_LINE_POS := Vector2(120.0, 504.0)
const JOIN_LINE_POS := Vector2(120.0, 848.0)
const HINT_POS := Vector2(64.0, 960.0)
const STATUS_POS := Vector2(64.0, 1000.0)
const STATUS_W := 1180.0
const VERSION_RIGHT := 1856.0
const VERSION_BASELINE := 1040.0
const RP_X := 1008.0
const RP_RIGHT := 1824.0
const CAPTION_CONNECT_POS := Vector2(1008.0, 216.0)
const CAPTION_ADDRESSES_POS := Vector2(1008.0, 256.0)
const ADDR_TOPS: Array[float] = [272.0, 312.0, 352.0, 392.0]
const ADDR_H := 40.0
const ADDR_TEXT_X := 1032.0
const ADDR_BASELINE_OFFSET := 30.0
const ADDR_CHIP_RIGHT := 1808.0
const ADDR_LINE_POS := Vector2(1008.0, 464.0)
const RP_DIVIDER_Y := 488.0
const CAPTION_HOW_POS := Vector2(1008.0, 528.0)
const STEP_BASELINES: Array[float] = [568.0, 608.0, 648.0, 688.0]
const GUIDE_POS := Vector2(1008.0, 736.0)
const FIREWALL_POS := Vector2(1008.0, 776.0)
const KEY_HINT_W := 120.0
const GLYPH_W := 16.0
const TS_BAR_W := 4.0
const DIVIDER_ALPHA := 0.35
const CAPTION_SPACING := 2
const ADDRESS_REFRESH_SEC := 5.0

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()
## The session (the /root/NetSession autoload unless a test injects one).
var session: Node = null
## () -> PackedStringArray of this PC's addresses (IP.get_local_addresses unless injected).
var addrs_fn: Callable = Callable()
## () -> String clipboard text (DisplayServer.clipboard_get unless injected).
var clipboard_fn: Callable = Callable()

var name_field: SonarTextField
var port_field: SonarTextField
var address_field: SonarTextField
var host_button: Button
var paste_button: Button
var join_button: Button
var status_label: Label
var version_label: Label
var dialog: ConnectDialog

var _focus := F_HOST
var _controls: Array[Control] = []
var _row_painters: Array[Control] = []
var _layout: Control
var _row_hint: Label
var _hint_label: Label
var _key_hint: Label
var _addr_line: Label
var _addr_painter: Control
var _step_labels: Array[Label] = []
var _status_glyph: Control
var _status_role := ""
var _addresses: Array[Dictionary] = []
var _addr_t := 0.0
var _last_pad := false
var _busy := false
var _caption_font: FontVariation


## Non-interactive canvas that draws with a callable.
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	if session == null:
		session = get_node_or_null("/root/NetSession")
	if not addrs_fn.is_valid():
		addrs_fn = func() -> PackedStringArray: return IP.get_local_addresses()
	if not clipboard_fn.is_valid():
		clipboard_fn = func() -> String: return DisplayServer.clipboard_get()
	_build()
	refresh_addresses()
	_refresh()
	UiKit.register_fx(self)
	_initial_focus()


# ---- building ----------------------------------------------------------------------------

func _build() -> void:
	var backdrop := AbyssBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.variant = "table"
	add_child(backdrop)
	_layout = Control.new()
	_layout.name = "Layout"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(_layout)
	add_child(_layout)

	_label("Title", TITLE, Palette.display_font(), Palette.SIZE_HEADING, Palette.TEXT_HI, TITLE_POS)
	_label("Subtitle", SUBTITLE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, SUBTITLE_POS)
	_panel("LeftPanel", LEFT_RECT)
	_panel("RightPanel", RIGHT_RECT)

	# Left panel.
	_label("CaptionSub", CAPTION_SUB, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_SUB_POS)
	_row_painter("NameRow", NAME_ROW, "name")
	_row_painter("PortRow", PORT_ROW, "port")
	_row_hint = _label("RowHint", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, ROW_HINT_POS)
	for y in DIVIDER_YS:
		_divider("Divider%d" % int(y), Rect2(ROW_X, y - Palette.EDGE * 0.5, ROW_W, Palette.EDGE))
	_label("CaptionHost", CAPTION_HOST, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_HOST_POS)
	_label("HostLine", HOST_LINE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, HOST_LINE_POS)
	_label("CaptionJoin", CAPTION_JOIN, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_JOIN_POS)
	_row_painter("AddressRow", ADDRESS_ROW, "address")
	_label("JoinLine", JOIN_LINE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, JOIN_LINE_POS)

	name_field = _field("NameField", "name", Settings.player_name, NAME_WELL)
	port_field = _field("PortField", "port", str(Settings.net_last_port), PORT_WELL)
	host_button = _button("HostMatch", HOST_TEXT, "host", "primary", HOST_RECT)
	_key_hint = Label.new()
	_key_hint.name = "KeyHint"
	_key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_hint.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	_key_hint.add_theme_color_override("font_color", Palette.TEXT_LO)
	_key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_hint.position = Vector2(ROW_W - Palette.SP_LG - KEY_HINT_W, 0.0)
	_key_hint.size = Vector2(KEY_HINT_W, ROW_H)
	host_button.add_child(_key_hint)
	address_field = _field("AddressField", "address", Settings.net_last_address, ADDRESS_WELL)
	paste_button = _button("Paste", PASTE_TEXT, "copy", "default", PASTE_RECT)
	join_button = _button("JoinMatch", JOIN_TEXT, "online", "default", JOIN_RECT)
	_controls = [name_field, port_field, host_button, address_field, paste_button, join_button]
	for i in _controls.size():
		var c := _controls[i]
		c.gui_input.connect(_on_control_input.bind(i))
		c.focus_entered.connect(_on_control_focus.bind(i))
		c.focus_exited.connect(_redraw_rows)
		var own := c.get_path_to(c)
		c.focus_neighbor_top = own
		c.focus_neighbor_bottom = own
		c.focus_neighbor_left = own
		c.focus_neighbor_right = own
	for i in _controls.size():
		var c := _controls[i]
		c.focus_next = c.get_path_to(_controls[(i + 1) % _controls.size()])
		c.focus_previous = c.get_path_to(_controls[(i + _controls.size() - 1) % _controls.size()])
	host_button.pressed.connect(host_match)
	paste_button.pressed.connect(paste_address)
	join_button.pressed.connect(join_match)
	name_field.committed.connect(_on_name_committed)
	name_field.cancelled.connect(_on_name_cancelled)
	port_field.committed.connect(func(_v: String) -> void: _refresh())
	port_field.invalid.connect(_on_port_invalid)
	address_field.committed.connect(func(_v: String) -> void: _refresh())
	for f: SonarTextField in [name_field, port_field, address_field]:
		f.editing_changed.connect(func(_on: bool) -> void: _refresh())

	# Right panel (8.1).
	_label("CaptionConnect", CAPTION_CONNECT, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_CONNECT_POS)
	_label("CaptionAddresses", CAPTION_ADDRESSES, _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO,
		CAPTION_ADDRESSES_POS)
	_addr_painter = _painter("AddressList", Rect2(RP_X, ADDR_TOPS[0], RP_RIGHT - RP_X, ADDR_H * ADDR_TOPS.size()),
		_paint_addresses)
	_addr_line = _label("AddressLine", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, ADDR_LINE_POS)
	_divider("RightDivider", Rect2(RP_X, RP_DIVIDER_Y - Palette.EDGE * 0.5, RP_RIGHT - RP_X, Palette.EDGE))
	_label("CaptionHow", CAPTION_HOW, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_HOW_POS)
	for i in STEP_BASELINES.size():
		_step_labels.append(_label("Step%d" % (i + 1), "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID,
			Vector2(RP_X, STEP_BASELINES[i])))
	_label("Guide", GUIDE_LINE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, GUIDE_POS)
	_label("Firewall", FIREWALL_LINE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, FIREWALL_POS)

	# Footer.
	_hint_label = _label("Hint", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, HINT_POS)
	status_label = _status_line()
	_layout.add_child(status_label)
	version_label = _label("Version", VERSION_FORMAT % NetProtocol.game_version(), Palette.font(), Palette.SIZE_LABEL,
		Palette.TEXT_LO, Vector2(0.0, VERSION_BASELINE))
	version_label.position.x = VERSION_RIGHT - version_label.size.x
	var marker := FocusMarker.new()
	marker.name = "FocusMarker"
	add_child(marker)


func _field(node_name: String, cfg: String, initial: String, well: Rect2) -> SonarTextField:
	var f := SonarTextField.new()
	f.name = node_name
	f.setup(cfg, initial)
	f.position = well.position
	f.size = well.size
	_layout.add_child(f)
	return f


func _button(node_name: String, text: String, icon: String, variant: String, rect: Rect2) -> Button:
	var b := UiKit.make_button(text, icon, variant, int(rect.size.y))
	b.name = node_name
	b.position = rect.position
	b.size = rect.size
	_layout.add_child(b)
	return b


## Row backdrop behind a field (match setup row look): button idle, "focus" while its field has
## focus; the row label in Body 28 TEXT_MID at x 120.
func _row_painter(node_name: String, rect: Rect2, cfg: String) -> void:
	var p := _painter(node_name, rect, func(c: CanvasItem) -> void: _paint_field_row(c, rect, cfg))
	_row_painters.append(p)


func _paint_field_row(c: CanvasItem, rect: Rect2, cfg: String) -> void:
	var f := field_for(cfg)
	var focused := f != null and f.has_focus()
	c.draw_style_box(UiKit.style_button("focus" if focused else "normal"), Rect2(Vector2.ZERO, rect.size))
	var font := Palette.font()
	var fs := Palette.SIZE_BODY
	var base := rect.size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	c.draw_string(font, Vector2(LABEL_X - rect.position.x, base), str(ROW_LABELS[cfg]), HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, fs, Palette.TEXT_MID)


func _status_line() -> Label:
	var l := Label.new()
	l.name = "StatusLine"
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = GLYPH_W + Palette.SP_SM
	l.add_theme_stylebox_override("normal", pad)
	var f := Palette.font()
	l.position = Vector2(STATUS_POS.x, STATUS_POS.y - f.get_ascent(Palette.SIZE_LABEL))
	l.size = Vector2(STATUS_W, f.get_height(Palette.SIZE_LABEL))
	var g := Painter.new()
	g.name = "Glyph"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.position = Vector2(0.0, 2.0)
	g.size = Vector2(GLYPH_W, GLYPH_W)
	g.painter = func(c: CanvasItem) -> void:
		UiIcons.draw(c, "warning", Rect2(Vector2.ZERO, Vector2(GLYPH_W, GLYPH_W)), Palette.WARNING_RED)
	l.add_child(g)
	_status_glyph = g
	return l


# ---- model / refresh ---------------------------------------------------------------------

func field_for(cfg: String) -> SonarTextField:
	match cfg:
		"name":
			return name_field
		"port":
			return port_field
		"address":
			return address_field
	return null


## The port to host or join with: the Port field when valid, else the saved port.
func current_port() -> int:
	var v := port_field.value if port_field != null else ""
	if v.is_valid_int():
		var n := v.to_int()
		if n >= Settings.NET_PORT_MIN and n <= Settings.NET_PORT_MAX:
			return n
	return Settings.net_last_port


## [address, port] from the Address field: "host:port" and "[v6]:port" (the lobby's Copy
## Address string) are split; a bare address keeps the Port field value.
func target() -> Array:
	return split_host_port(address_field.value.strip_edges(), current_port())


static func split_host_port(text: String, default_port: int) -> Array:
	var s := text.strip_edges()
	if s.begins_with("["):
		var close := s.find("]")
		if close > 0:
			var inner := s.substr(1, close - 1)
			var rest := s.substr(close + 1)
			if rest.begins_with(":") and _valid_port(rest.substr(1)):
				return [inner, rest.substr(1).to_int()]
			return [inner, default_port]
		return [s, default_port]
	if s.count(":") == 1:
		var at := s.find(":")
		var p := s.substr(at + 1)
		if _valid_port(p) and at > 0:
			return [s.substr(0, at), p.to_int()]
	return [s, default_port]


static func _valid_port(p: String) -> bool:
	if not p.is_valid_int():
		return false
	var n := p.to_int()
	return n >= SonarTextField.PORT_MIN and n <= SonarTextField.PORT_MAX


func join_enabled() -> bool:
	return address_field != null and not address_field.value.strip_edges().is_empty() and dialog == null \
		and not _busy


func any_field_editing() -> bool:
	for f: SonarTextField in [name_field, port_field, address_field]:
		if f != null and f.is_editing():
			return true
	return false


func steps() -> Array[String]:
	var out: Array[String] = []
	var p := str(current_port())
	for s in STEPS:
		out.append(s.replace("{port}", p))
	return out


## Re-reads this PC's addresses through addrs_fn (open + every 5 s).
func refresh_addresses() -> void:
	_addr_t = 0.0
	var raw: Variant = addrs_fn.call() if addrs_fn.is_valid() else PackedStringArray()
	var list := PackedStringArray()
	if raw is PackedStringArray:
		list = raw
	elif raw is Array:
		for a: Variant in raw:
			list.append(str(a))
	_addresses = NetAddress.display_list(list)
	if _addr_line == null:
		return
	var role := address_line_role()
	_set_text(_addr_line, address_line())
	_addr_line.add_theme_color_override("font_color", Palette.WARNING_RED if role == "none"
		else (Palette.TEXT_MID if role == "tailscale" else Palette.TEXT_LO))
	_addr_painter.queue_redraw()


## "tailscale" | "lan" (addresses but no Tailscale) | "none"
func address_line_role() -> String:
	if _addresses.is_empty():
		return "none"
	for e in _addresses:
		if str(e["kind"]) == NetAddress.TAILSCALE:
			return "tailscale"
	return "lan"


func address_line() -> String:
	match address_line_role():
		"tailscale":
			return ADDR_TAILSCALE
		"lan":
			return ADDR_NO_TAILSCALE
	return ADDR_NONE


func _refresh() -> void:
	if join_button == null:
		return
	join_button.disabled = not join_enabled()
	var editing := any_field_editing()
	_key_hint.text = "A" if _last_pad else "ENTER"
	if editing:
		_set_text(_hint_label, HINT_PAD_EDIT if _last_pad else HINT_KEYS_EDIT)
	else:
		_set_text(_hint_label, HINT_PAD if _last_pad else HINT_KEYS)
	var focus_name := FOCUS[_focus]
	_set_text(_row_hint, HINT_NAME if focus_name == "name" else (HINT_PORT if focus_name == "port" else ""))
	var st := steps()
	for i in _step_labels.size():
		_set_text(_step_labels[i], st[i])
	_redraw_rows()


func _redraw_rows() -> void:
	for p in _row_painters:
		p.queue_redraw()


## Status line: role "info" (TEXT_MID) or "error" (WARNING_RED + warning glyph); "" hides it.
func show_status(text: String, role: String = "info") -> void:
	_status_role = role if text != "" else ""
	status_label.text = text
	status_label.visible = text != ""
	var err := role == "error"
	status_label.add_theme_color_override("font_color", Palette.WARNING_RED if err else Palette.TEXT_MID)
	_status_glyph.visible = err
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = (GLYPH_W + Palette.SP_SM) if err else 0.0
	status_label.add_theme_stylebox_override("normal", pad)


# ---- focus -------------------------------------------------------------------------------

func _initial_focus() -> void:
	var msg := ""
	if session != null and session.has_method(&"take_return_message"):
		msg = str(session.call(&"take_return_message"))
	if RETURN_MESSAGES.has(msg):
		show_status(str(RETURN_MESSAGES[msg]), "error" if msg == "lost" else "info")
		_set_focus(F_JOIN if join_enabled() else F_ADDRESS)
		return
	if not Settings.player_name_set:
		_set_focus(F_NAME)
		show_status(FIRST_VISIT_PROMPT, "info")
		name_field.begin_editing()
		_refresh()
		return
	_set_focus(F_JOIN if join_enabled() else F_HOST)


func _on_control_focus(i: int) -> void:
	_focus = i
	_refresh()


func _set_focus(i: int) -> void:
	_focus = clampi(i, 0, FOCUS.size() - 1)
	if _focus == F_JOIN and not join_enabled():
		_focus = F_PASTE
	var c := _controls[_focus]
	if is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()
	_refresh()


## Up / Down through the 8.2 ring (the button row counts as one stop).
func _step_focus(dir: int) -> void:
	var stop := mini(_focus, F_PASTE)  # 0 name, 1 port, 2 host, 3 address, 4 button row
	stop = posmod(stop + dir, 5)
	if stop == F_PASTE:
		_set_focus(F_JOIN if join_enabled() else F_PASTE)
	else:
		_set_focus(stop)


## Left / Right on the button row (Paste <-> Join Match; a disabled Join is skipped).
func _step_row(dir: int) -> void:
	if _focus == F_PASTE and dir > 0 and join_enabled():
		_set_focus(F_JOIN)
	elif _focus == F_JOIN and dir < 0:
		_set_focus(F_PASTE)


# ---- input -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Device tracking only (never consumed): hints follow the last device used.
	var pad := _last_pad
	if event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion
			and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad = true
	if pad != _last_pad:
		_last_pad = pad
		_refresh()


func _on_control_input(event: InputEvent, i: int) -> void:
	if dialog != null or not event.is_pressed():
		return
	var c := _controls[i]
	if c is SonarTextField and (c as SonarTextField).is_editing():
		return  # the field owns every key while editing
	if event.is_action_pressed(&"ui_up", true):
		_step_focus(-1)
	elif event.is_action_pressed(&"ui_down", true):
		_step_focus(1)
	elif event.is_action_pressed(&"ui_left", true):
		_step_row(-1)
	elif event.is_action_pressed(&"ui_right", true):
		_step_row(1)
	elif event.is_action_pressed(&"ui_accept") and not (c is SonarTextField):
		if not event.is_echo():
			_activate(i)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if dialog != null or any_field_editing():
			return
		get_viewport().set_input_as_handled()
		back()


func _activate(i: int) -> void:
	match i:
		F_HOST:
			host_match()
		F_PASTE:
			paste_address()
		F_JOIN:
			join_match()


# ---- actions -----------------------------------------------------------------------------

func _on_name_committed(v: String) -> void:
	var clean := Settings.clean_player_name(v)
	if clean == "":
		clean = Settings.DEFAULT_PLAYER_NAME
	name_field.set_value(clean)
	Settings.player_name = clean
	Settings.player_name_set = true
	_save_settings()
	if status_label.text == FIRST_VISIT_PROMPT:
		show_status("")
	_refresh()


func _on_name_cancelled() -> void:
	_refresh()


func _on_port_invalid(code: String) -> void:
	if code == "port_range":
		show_status(ERR_PORT_RANGE, "error")
		_error_blip()
	_refresh()


## Host Match: opens the server on the Port value (D-01). Success wipes to the Lobby; failure
## shows the status-line error and keeps focus.
func host_match() -> void:
	if _busy or dialog != null:
		return
	var port := current_port()
	if session == null:
		_host_failed(ERR_UNAVAILABLE, port)
		return
	if session.has_method(&"is_offline") and not bool(session.call(&"is_offline")):
		session.call(&"leave")
	var err := int(session.call(&"host", port))
	if err != OK:
		_host_failed(err, port)
		return
	_busy = true
	Settings.net_last_port = port
	_save_settings()
	show_status("")
	_go(LOBBY_SCENE)


func _host_failed(err: int, port: int) -> void:
	var text := ERR_PORT_BUSY if err == ERR_CANT_CREATE or err == ERR_ALREADY_IN_USE else ERR_HOST
	show_status(text.replace("{port}", str(port)).replace("{code}", str(err)), "error")
	_error_blip()


## Paste: clipboard -> Address (filtered by the address charset, truncated to 64). A
## "host:port" paste also fills the Port field.
func paste_address() -> void:
	if dialog != null:
		return
	var raw := str(clipboard_fn.call()) if clipboard_fn.is_valid() else ""
	raw = raw.strip_edges().substr(0, Settings.ADDRESS_MAX * 4 + 16)
	var kept := ""
	var allowed: String = SonarTextField.ORDERS["address"] + SonarTextField.UPPER
	for i in raw.length():
		if allowed.contains(raw[i]):
			kept += raw[i]
	kept = kept.substr(0, Settings.ADDRESS_MAX)
	if kept.is_empty():
		show_status(ERR_CLIPBOARD, "error")
		_error_blip()
		return
	var hp := split_host_port(kept, current_port())
	address_field.set_value(str(hp[0]))
	if int(hp[1]) != current_port():
		port_field.set_value(str(hp[1]))
	if _status_role == "error":
		show_status("")
	_blip("confirm")
	_refresh()
	if join_enabled():
		_set_focus(F_JOIN)


## Join Match: saves the address and port, then opens the connect dialog (8.3).
func join_match() -> void:
	if not join_enabled():
		return
	var hp := target()
	var addr := Settings.clean_address(str(hp[0]))
	if addr == "":
		show_status(str(ConnectDialog.ERROR_BODIES["resolve"]).replace("{address}", str(hp[0])), "error")
		_error_blip()
		return
	var port := int(hp[1])
	Settings.net_last_address = addr
	Settings.net_last_port = port
	_save_settings()
	show_status("")
	dialog = ConnectDialog.new()
	dialog.name = "ConnectDialog"
	dialog.setup(session, addr, port)
	dialog.joined.connect(_on_joined)
	dialog.closed.connect(_on_dialog_closed)
	add_child(dialog)
	_refresh()
	dialog.start()


func _on_joined() -> void:
	_busy = true
	_go(LOBBY_SCENE)


func _on_dialog_closed() -> void:
	if dialog != null:
		# Hidden now, freed at the end of the frame (it is still a child until then).
		dialog.visible = false
		dialog.queue_free()
	dialog = null
	_refresh()
	_set_focus(F_JOIN)


## Esc / B with no field editing: back to the main menu (no confirm; nothing is lost).
func back() -> void:
	if dialog != null or any_field_editing() or _busy:
		return
	_go(MENU_SCENE)


func _save_settings() -> void:
	Settings.save_to(Settings.save_path)
	Settings.settings_changed.emit()


func _error_blip() -> void:
	_blip("error")


func _blip(blip_name: String) -> void:
	var snd := get_node_or_null(^"/root/UiSounds") if is_inside_tree() else null
	if snd != null and snd.has_method(&"play"):
		snd.call(&"play", blip_name)


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		ScreenTransition.change_scene(path)


# ---- time --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Address list refresh clock (every ADDRESS_REFRESH_SEC while open).
func tick(delta: float) -> void:
	_addr_t += delta
	if _addr_t >= ADDRESS_REFRESH_SEC:
		refresh_addresses()


# ---- painting ----------------------------------------------------------------------------

func _paint_addresses(c: CanvasItem) -> void:
	var f := Palette.font()
	var fs := Palette.SIZE_BODY
	for i in mini(_addresses.size(), ADDR_TOPS.size()):
		var e: Dictionary = _addresses[i]
		var r := address_row_rect(i)
		r.position -= Vector2(RP_X, ADDR_TOPS[0])
		var kind := str(e["kind"])
		var ts := kind == NetAddress.TAILSCALE
		if ts:
			c.draw_rect(r, Palette.alpha(Palette.ABYSS_600, Palette.HUD_GLASS_ALPHA))
			c.draw_rect(Rect2(r.position, Vector2(TS_BAR_W, r.size.y)), Palette.SONAR)
		c.draw_string(f, Vector2(ADDR_TEXT_X - RP_X, r.position.y + ADDR_BASELINE_OFFSET), str(e["ip"]),
			HORIZONTAL_ALIGNMENT_LEFT, ADDR_CHIP_RIGHT - ADDR_TEXT_X - 160.0, fs,
			Palette.SONAR_PALE if ts else Palette.TEXT_MID)
		var chip := address_chip(kind)
		if chip != "":
			var variant := "info" if ts else "muted"
			var w := UiKit.chip_width(chip, variant)
			UiKit.draw_chip(c, Rect2(ADDR_CHIP_RIGHT - RP_X - w, r.position.y + (ADDR_H - UiKit.CHIP_H) * 0.5, w,
				UiKit.CHIP_H), chip, variant)


static func address_chip(kind: String) -> String:
	match kind:
		NetAddress.TAILSCALE:
			return CHIP_TAILSCALE
		NetAddress.LAN:
			return CHIP_LAN
	return ""


static func address_row_rect(i: int) -> Rect2:
	return Rect2(RP_X, ADDR_TOPS[i], RP_RIGHT - RP_X, ADDR_H)


# ---- helpers -----------------------------------------------------------------------------

func _caption() -> Font:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = Palette.font()
		_caption_font.spacing_glyph = CAPTION_SPACING
	return _caption_font


func _set_text(l: Label, text: String) -> void:
	l.text = text
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	l.size.x = ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


## A label whose first baseline sits at `at.y`, sized to its text.
func _label(node_name: String, text: String, font: Font, font_size: int, color: Color, at: Vector2) -> Label:
	var l := Label.new()
	l.name = node_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.position = Vector2(at.x, at.y - font.get_ascent(font_size))
	l.size = Vector2(0.0, ceilf(font.get_height(font_size)))
	_layout.add_child(l)
	_set_text(l, text)
	return l


func _painter(node_name: String, rect: Rect2, fn: Callable) -> Painter:
	var c := Painter.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size
	c.painter = fn
	_layout.add_child(c)
	return c


func _panel(node_name: String, rect: Rect2) -> void:
	var sb := UiKit.style_panel("default")
	_painter(node_name, rect, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, Palette.alpha(Palette.SONAR, 0.8)))


func _divider(node_name: String, rect: Rect2) -> void:
	var d := ColorRect.new()
	d.name = node_name
	d.color = Palette.alpha(Palette.SONAR, DIVIDER_ALPHA)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = rect.position
	d.size = rect.size
	_layout.add_child(d)


# ---- effects contract --------------------------------------------------------------------

func apply_effect_settings() -> void:
	_redraw_rows()
	if _addr_painter != null:
		_addr_painter.queue_redraw()


func effect_counts() -> Dictionary:
	# Static screen: the animated parts are the fields, the focus marker and the dialog,
	# each registered on its own.
	return {"static": true}


# ---- test seams --------------------------------------------------------------------------

func debug_state() -> Dictionary:
	var rows: Array = []
	for i in FOCUS.size():
		var c := _controls[i]
		rows.append({
			"id": FOCUS[i],
			"rect": Rect2(c.position, c.size),
			"focused": c.has_focus(),
			"disabled": (c as Button).disabled if c is Button else false,
			"editing": (c as SonarTextField).is_editing() if c is SonarTextField else false,
			"value": (c as SonarTextField).value if c is SonarTextField else (c as Button).text,
		})
	var addrs: Array = []
	for e in _addresses:
		addrs.append({"ip": e["ip"], "kind": e["kind"], "chip": address_chip(str(e["kind"])),
			"highlight": str(e["kind"]) == NetAddress.TAILSCALE})
	return {
		"focus": FOCUS[_focus],
		"status": status_label.text if status_label.visible else "",
		"status_role": _status_role,
		"rows": rows,
		"join_enabled": join_enabled(),
		"addresses": addrs,
		"address_line": address_line(),
		"row_hint": _row_hint.text,
		"hint": _hint_label.text,
		"steps": Array(steps()),
		"version": version_label.text,
		"dialog": dialog != null,
	}


func focus_row_for_test(row: String) -> void:
	_set_focus(FOCUS.find(row))


## Keys as the screen sees them. While a field edits, Enter commits and Esc reverts it (the
## field consumes both), exactly as a real key press would.
func press_key_for_test(keycode: int) -> void:
	var f := _controls[_focus] as SonarTextField if _controls[_focus] is SonarTextField else null
	if dialog != null:
		if keycode == KEY_ESCAPE:
			dialog.cancel()
		return
	if f != null and f.is_editing():
		match keycode:
			KEY_ENTER, KEY_KP_ENTER:
				f.commit()
			KEY_ESCAPE:
				f.cancel()
		return
	match keycode:
		KEY_UP:
			_step_focus(-1)
		KEY_DOWN:
			_step_focus(1)
		KEY_LEFT:
			_step_row(-1)
		KEY_RIGHT:
			_step_row(1)
		KEY_ENTER, KEY_KP_ENTER:
			if f != null:
				f.begin_editing()
			else:
				_activate(_focus)
		KEY_ESCAPE:
			back()
