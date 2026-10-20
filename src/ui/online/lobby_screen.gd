class_name LobbyScreen
extends Control
## LOBBY (04-UI-SPEC 9, 9.1-9.5, 15; NET-01, NET-02, D-08, D-11, D-12, D-15). Left glass panel:
## MATCH (Song / Difficulty / Torpedo flight rows), INVITE (host: address, second line, Copy
## Address) or CONNECTION (client: host name, ping and clock), the start gate / client reason
## line and the primary button (host Start Match, client Ready Up / Cancel Ready). Right glass
## panel: the roster (4 rows, 64 tall, pitch 72; NAME, PING with signal bars, SONG chip, READY;
## open seats dashed) and the 6-line LOBBY LOG.
##
## Everything comes from the session (the /root/NetSession autoload unless injected):
## lobby_rows(), lobby_song(), flight(), start_gate(), ping_ms(), is_synced(). lobby_changed
## redraws (plus a 1 Hz re-read for the PING column). Host-only calls (host_set_song,
## host_set_flight, kick, start_match) are no-ops on clients, and client controls never call them
## (T-04-45): clients only reach the Ready button.
##
## Song pick (9.4): the host's Song row sets SongSelect.run_pick + pick_online and opens Song
## Select; the pick comes back in MatchSetup.pending.song_id / difficulty and becomes
## host_set_song({fp, sig, diff, title, artist}) (fingerprint from the local library entry,
## VersusSig of the chart built once). Nothing from a peer is ever used as a path (T-04-44): the
## match chart is found by fingerprint over the local library entries only.
##
## Hand-off (D-07): match_loading -> build the chart for pending_match().fp / diff from this PC's
## library -> Gameplay.pending_chart -> the gameplay scene. A local failure shows the status line
## and calls session.report_load_failed() (the host then aborts everyone to the lobby).
##
## Lobby log carry: a LogCarry node lives under the session (it outlives this screen) and turns
## match_aborted_to_lobby / returned_to_lobby into log lines that the next lobby screen shows
## (9.3: the log is rebuilt on each entry except for these return messages). Across the host's
## own Song Select round trip the log is kept.

const ONLINE_SCENE := "res://scenes/online_menu.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"

## Copy (04-UI-SPEC 15).
const TITLE := "LOBBY"
const HOST_CHIP := "HOST"
const SUBTITLE_HOST := "You are hosting. Friends join with {address}."
const SUBTITLE_CLIENT := "Connected to {HOST}'s lobby."
const CAPTION_MATCH := "MATCH"
const ROW_LABELS: Array[String] = ["Song", "Difficulty", "Torpedo flight"]
const FLIGHT_TILES: Array[String] = ["2 BEATS", "1 BEAT LAN"]
const FLIGHT_VALUES: Array[int] = [2, 1]
const FLIGHT_LINES := {
	2: "Torpedoes fly 2 beats. Safe for internet play.",
	1: "Torpedoes fly 1 beat. For same-room LAN only; warnings get shorter online.",
}
const NO_SONG_HOST := "Choose a song"
const NO_SONG_CLIENT := "Host is choosing a song"
const SONG_SEP := " · "
const CAPTION_INVITE := "INVITE"
const CAPTION_CONNECTION := "CONNECTION"
const INVITE_TS_LINE := "Tailscale address. Friends on your LAN can use {lan}."
const INVITE_TS_ONLY_LINE := "Tailscale address."
const INVITE_LAN_LINE := "LAN address. Friends outside your network need Tailscale."
const INVITE_NONE := "No network address found. Check that this PC is online."
const HOST_LINE := "HOST {HOST}"
const PING_SYNCED := "PING {n} MS · CLOCK SYNCED"
const PING_SYNCING := "PING -- MS · SYNCING CLOCK"
const COPY_TEXT := "Copy Address"
const COPIED_TEXT := "Copied"
const START_TEXT := "Start Match"
const READY_TEXT := "Ready Up"
const CANCEL_READY_TEXT := "Cancel Ready"
const ROSTER_CAPTION := "SUBS IN THIS LOBBY {n}/4"
const HEAD_NAME := "NAME"
const HEAD_PING := "PING"
const HEAD_SONG := "SONG"
const HEAD_READY := "READY"
const PING_FORMAT := "{n} MS"
const PING_HOST := "-"
const PING_SYNC := "SYNC"
const CHIP_OK := "OK"
const CHIP_MISSING := "MISSING"
const CHIP_CHANGED := "CHANGED"
const CHIP_CHECKING := "CHECKING"
const CHIP_NO_SONG := "NO SONG"
const READY_WORD := "READY"
const WAITING_WORD := "WAITING"
const HOST_WORD := "HOST"
const KICK_KEYS := "ENTER KICK"
const KICK_PAD := "A KICK"
const OPEN_SEAT := "OPEN SEAT"
const OPEN_SEAT_LINE := "Waiting for a friend to join."
const CAPTION_LOG := "LOBBY LOG"
const HINT_HOST_KEYS := "UP DOWN MOVE  ·  LEFT RIGHT CHANGE  ·  ENTER SELECT  ·  ESC CLOSE LOBBY"
const HINT_HOST_PAD := "D-PAD MOVE  ·  LEFT RIGHT CHANGE  ·  A SELECT  ·  B CLOSE LOBBY"
const HINT_CLIENT_KEYS := "ENTER READY  ·  ESC LEAVE LOBBY"
const HINT_CLIENT_PAD := "A READY  ·  B LEAVE LOBBY"

## Start gate reasons (host, 9.1 order) and the client reason line.
const GATE_NEED_PLAYERS := "Waiting for at least 1 friend to join."
const GATE_NEED_SONG := "Pick a song first."
const GATE_SYNCING := "Syncing clocks..."
const GATE_MISSING_ONE := "{NAME} is missing the song."
const GATE_MISSING_MANY := "{n} subs are missing the song."
const GATE_CHANGED_ONE := "{NAME} has a different version of this song."
const GATE_NOT_READY_ONE := "Waiting for {NAME} to ready up."
const GATE_NOT_READY_MANY := "Waiting for {n} subs to ready up."
const GATE_OK := "All subs ready. Start when you like."
const CLIENT_NO_SONG := "Waiting for the host to pick a song."
const CLIENT_MISSING := "You are missing this song. Add it to your Songs folder and restart UNDERTOW, or ask the host for another song."
const CLIENT_CHANGED := "Your copy of this song differs from the host's. Ask the host for another song."
const CLIENT_READY_UP := "Ready Up when you are set."
const CLIENT_WAITING := "Waiting for the host to start."

## Lobby log (9.3).
const LOG_HOST_EMPTY := "Lobby open. Share your address to invite friends."
const LOG_CLIENT_EMPTY := "You joined {HOST}'s lobby."
const LOG_JOINED := "{NAME} joined."
const LOG_LEFT := "{NAME} left."
const LOG_KICKED := "{NAME} was removed by the host."
const LOG_CHOOSING := "Host is choosing a song."
const LOG_PICKED := "Host picked {title} ({DIFFICULTY}). Ready cleared."
const LOG_FLIGHT_MANY := "Torpedo flight set to {n} beats."
const LOG_FLIGHT_ONE := "Torpedo flight set to 1 beat."
const LOG_READY := "{NAME} is ready."
const LOG_MISSING := "{NAME} is missing this song."
const LOG_HIGH_LATENCY := "High latency to {NAME} ({n} ms). Torpedo warnings may be shorter than 1 beat."
const LOG_LOAD_TIMEOUT := "{NAME} could not load the song in time. Back in the lobby."
const LOG_START_LATE := "The start signal reached {NAME} too late. Back in the lobby."
const LOG_LOAD_FAIL := "{NAME} could not load this song. Back in the lobby."
const LOG_MATCH_ENDED := "Match ended. Ready up for another."

## Destructive confirmations (15).
const CLOSE_TITLE := "CLOSE LOBBY"
const CLOSE_BODY := "Close the lobby? Everyone is sent back to Play Online."
const CLOSE_CONFIRM := "Close Lobby"
const LEAVE_TITLE := "LEAVE LOBBY"
const LEAVE_BODY := "Leave this lobby? You can join again with the same address."
const LEAVE_CONFIRM := "Leave Lobby"
const STAY_TEXT := "Stay"
const KICK_TITLE := "REMOVE {NAME}"
const KICK_BODY := "Remove {NAME} from the lobby? They can join again."
const KICK_CONFIRM := "Remove"
const KICK_SAFE := "Keep"

## Focus slots. Host order (9.5): song, difficulty, flight, copy, start, then occupied client
## roster rows (row1..row3, display order). Client: start (the Ready button) only.
const F_SONG := "song"
const F_DIFFICULTY := "difficulty"
const F_FLIGHT := "flight"
const F_COPY := "copy"
const F_START := "start"
const HOST_FOCUS: Array[String] = ["song", "difficulty", "flight", "copy", "start"]

## Layout (1920x1080 design pixels, 04-UI-SPEC 9).
const TITLE_POS := Vector2(64.0, 104.0)
const SUBTITLE_POS := Vector2(64.0, 140.0)
const HOST_CHIP_Y := 76.0
const HOST_CHIP_GAP := 16.0
const LEFT_RECT := Rect2(64.0, 176.0, 880.0, 728.0)
const RIGHT_RECT := Rect2(976.0, 176.0, 880.0, 728.0)
const CAPTION_MATCH_POS := Vector2(96.0, 216.0)
const ROW_X := 96.0
const ROW_W := 816.0
const ROW_H := 64.0
const SONG_ROW := Rect2(96.0, 240.0, 816.0, 64.0)
const DIFFICULTY_ROW := Rect2(96.0, 312.0, 816.0, 64.0)
const FLIGHT_ROW := Rect2(96.0, 384.0, 816.0, 64.0)
const LABEL_X := 120.0
const VALUE_X := 400.0
const VALUE_W := 456.0
const CHEVRON_LEFT_X := 368.0
const CHEVRON_RIGHT_X := 872.0
const ICON := 24.0
const FLIGHT_TILE_X: Array[float] = [400.0, 624.0]
const FLIGHT_TILE_Y := 392.0
const FLIGHT_TILE_SIZE := Vector2(208.0, 48.0)
const SEL_BAR := Vector2(24.0, 4.0)
const FLIGHT_LINE_POS := Vector2(120.0, 488.0)
const LEFT_DIVIDER_Y := 520.0
const CAPTION_SECTION_POS := Vector2(96.0, 560.0)
const INVITE_POS := Vector2(120.0, 604.0)
const INVITE_MAX_W := 560.0
const SECOND_LINE_POS := Vector2(120.0, 636.0)
const COPY_RECT := Rect2(96.0, 656.0, 320.0, 48.0)
const GATE_POS := Vector2(120.0, 784.0)
const GATE_MAX_W := 792.0
const PRIMARY_RECT := Rect2(96.0, 808.0, 816.0, 64.0)
const KEY_HINT_W := 120.0
const RP_X := 1008.0
const RP_RIGHT := 1824.0
const ROSTER_CAPTION_POS := Vector2(1008.0, 216.0)
const HEAD_BASELINE := 256.0
const NAME_X := 1032.0
const NAME_MAX_W := 240.0
const PING_RIGHT := 1440.0
const SIGNAL_X := 1320.0
const WARN_X := 1296.0
const SONG_X := 1480.0
const READY_X := 1664.0
const KICK_RIGHT := 1808.0
const HOST_GLYPH_X := 1020.0
const ROSTER_TOPS: Array[float] = [272.0, 344.0, 416.0, 488.0]
const ROSTER_H := 64.0
const NAME_BASELINE_OFFSET := 42.0
const OPEN_BASELINE_OFFSET := 40.0
const OPEN_LINE_X := 1312.0
const ROW_GLYPH := 20.0
const WARN_GLYPH := 16.0
const YOU_BAR_W := 4.0
const DASH := 12.0
const DASH_GAP := 8.0
const LOG_DIVIDER_Y := 576.0
const CAPTION_LOG_POS := Vector2(1008.0, 616.0)
const LOG_BASELINES: Array[float] = [656.0, 696.0, 736.0, 776.0, 816.0, 856.0]
const LOG_MAX_W := 816.0
const LOG_MAX := 6
const HINT_POS := Vector2(64.0, 960.0)
const STATUS_POS := Vector2(64.0, 1000.0)
const STATUS_W := 1180.0
const GLYPH_W := 16.0
const DIVIDER_ALPHA := 0.35
const CAPTION_SPACING := 2
const COPIED_SEC := 1.6
const REFRESH_SEC := 1.0
const ROW_SLIDE := 16.0
const OTHER_TILE_ALPHA := 0.5
const ROW_DIVIDER_ALPHA := 0.2
const OPEN_EDGE_ALPHA := 0.35

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()
## The session (the /root/NetSession autoload unless a test injects one).
var session: Node = null
## The song library (the /root/SongLibrary autoload unless a test injects one).
var library: Object = null
## () -> PackedStringArray of this PC's addresses (IP.get_local_addresses unless injected).
var addrs_fn: Callable = Callable()
## (text: String) -> void clipboard write (DisplayServer.clipboard_set unless injected).
var clipboard_fn: Callable = Callable()
## Options passed to session.start_match (04-17 autotest switches: seed, max_song_s, autoplay).
var start_opts: Dictionary = {}

var primary_button: Button
var copy_button: Button
var status_label: Label
var dialog: ConfirmDialog
var focus_marker: FocusMarker

var _is_host := false
var _rows: Array = []
var _song := {}
var _flight := 2
var _gate := {}
var _focus := F_START
var _controls := {}  # focus id -> Control
var _row_buttons: Array[Button] = []  # display rows 1..3 (index 0 unused = null)
var _row_views: Array[Control] = []
var _ready_cells: Array[Control] = []
var _row_tweens: Array = [null, null, null, null]
var _shown_seats: Array = [-2, -2, -2, -2]
var _shown_ready: Array = [false, false, false, false]
var _row_painters: Array[Control] = []
var _layout: Control
var _subtitle: Label
var _flight_line: Label
var _section_caption: Label
var _invite_label: Label
var _second_label: Label
var _gate_label: Label
var _gate_glyph: Control
var _hint_label: Label
var _key_hint: Label
var _roster_caption: Label
var _log_painter: Control
var _title_chip: Control
var _status_glyph: Control
var _status_role := ""
var _log: Array = []  # [{text, fault}]
var _log_fade := 1.0
var _log_tween: Tween
var _pending_pick_log := false
var _logged_song_key := ""
var _copied_t := 0.0
var _refresh_t := 0.0
var _invite := ""
var _last_pad := false
var _leaving := false
## WR-02: a scene change ScreenTransition refused; retried once the wipe is idle.
var _nav_pending := ""
var _carry: LogCarry
var _caption_font: FontVariation


## Non-interactive canvas that draws with a callable.
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## Lives under the session node so it outlives the lobby screen: collects the return messages
## of a match (abort reasons, "Match ended") for the next lobby screen, and keeps the log across
## the host's Song Select round trip.
class LogCarry:
	extends Node
	signal changed
	var pending: Array = []
	var history: Array = []
	var from_pick := false

	func attach(s: Node) -> void:
		if s.has_signal(&"match_aborted_to_lobby"):
			s.connect(&"match_aborted_to_lobby", _on_abort)
		if s.has_signal(&"returned_to_lobby"):
			s.connect(&"returned_to_lobby", _on_returned)
		if s.has_signal(&"left_lobby"):
			s.connect(&"left_lobby", _on_gone)
		if s.has_signal(&"host_left"):
			s.connect(&"host_left", _on_gone)

	func _on_abort(code: String, who: String) -> void:
		var line := LobbyScreen.abort_line(code, who)
		if line != "":
			pending.append({"text": line, "fault": true})
			changed.emit()

	func _on_returned() -> void:
		pending.append({"text": LobbyScreen.LOG_MATCH_ENDED, "fault": false})
		changed.emit()

	func _on_gone(_code: String) -> void:
		pending.clear()
		history.clear()
		from_pick = false

	func take() -> Array:
		var out := pending.duplicate(true)
		pending.clear()
		return out


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	if session == null:
		session = get_node_or_null("/root/NetSession")
	if library == null:
		library = get_node_or_null("/root/SongLibrary")
	if not addrs_fn.is_valid():
		addrs_fn = func() -> PackedStringArray: return IP.get_local_addresses()
	if not clipboard_fn.is_valid():
		clipboard_fn = func(t: String) -> void: DisplayServer.clipboard_set(t)
	_is_host = session != null and bool(_call(&"is_host", false))
	_read_model()
	_build()
	_connect_session()
	_start_log()
	_apply_pick()
	_refresh()
	UiKit.register_fx(self)
	_initial_focus()
	if session == null or bool(_call(&"is_offline", false)):
		# No lobby to show (the session dropped while another screen was up).
		_leaving = true
		_go(ONLINE_SCENE)


func _exit_tree() -> void:
	if _carry != null and is_instance_valid(_carry):
		_carry.history = _log.duplicate(true)
		if _carry.changed.is_connected(_drain_carry):
			_carry.changed.disconnect(_drain_carry)
	if session != null and is_instance_valid(session):
		for pair in [[&"lobby_changed", _on_lobby_changed], [&"log_line", _on_log_line],
				[&"left_lobby", _on_left_lobby], [&"match_loading", _on_match_loading]]:
			if session.has_signal(pair[0]) and session.is_connected(pair[0], pair[1]):
				session.disconnect(pair[0], pair[1])


# ---- session -----------------------------------------------------------------------------

func _call(method: StringName, fallback: Variant, args: Array = []) -> Variant:
	if session == null or not is_instance_valid(session) or not session.has_method(method):
		return fallback
	return session.callv(method, args)


func _connect_session() -> void:
	if session == null:
		return
	for pair in [[&"lobby_changed", _on_lobby_changed], [&"log_line", _on_log_line],
			[&"left_lobby", _on_left_lobby], [&"match_loading", _on_match_loading]]:
		if session.has_signal(pair[0]) and not session.is_connected(pair[0], pair[1]):
			session.connect(pair[0], pair[1])
	_carry = session.get_node_or_null(^"LobbyLogCarry") as LogCarry
	if _carry == null:
		_carry = LogCarry.new()
		_carry.name = "LobbyLogCarry"
		_carry.attach(session)
		session.add_child(_carry)
	_carry.changed.connect(_drain_carry)


func _read_model() -> void:
	var rows: Variant = _call(&"lobby_rows", [])
	_rows = []
	if rows is Array:
		for r: Variant in rows:
			if r is Dictionary:
				_rows.append(r)
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	var song: Variant = _call(&"lobby_song", {})
	_song = song if song is Dictionary else {}
	_flight = int(_call(&"flight", 2))
	var gate: Variant = _call(&"start_gate", {})
	_gate = gate if gate is Dictionary else {}


func _on_lobby_changed() -> void:
	_read_model()
	_flush_pick_log()
	_refresh()


func _on_log_line(code: String, info: Dictionary) -> void:
	if code == "song_picked":
		_pending_pick_log = true
		_flush_pick_log()
		return
	var line := log_text(code, info)
	if line != "":
		add_log(line, is_fault_code(code))


## "Host picked ..." needs the new song's title: on clients the NOTICE can arrive before the
## LOBBY that carries it, so the line is written once lobby_song() has the new key.
func _flush_pick_log() -> void:
	if not _pending_pick_log:
		return
	var song: Variant = _call(&"lobby_song", {})
	var s: Dictionary = song if song is Dictionary else {}
	var key := _song_key(s)
	if s.is_empty() or key == _logged_song_key:
		return
	_pending_pick_log = false
	_logged_song_key = key
	add_log(LOG_PICKED.replace("{title}", str(s.get("title", ""))).replace("{DIFFICULTY}",
		str(s.get("diff", "")).to_upper()), false)


static func _song_key(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	return "%s|%s|%s" % [s.get("fp", ""), s.get("sig", ""), s.get("diff", "")]


func _on_left_lobby(_code: String) -> void:
	# The session keeps the return message; Play Online shows it on open.
	if _leaving:
		return
	_leaving = true
	_close_dialog()
	_go(ONLINE_SCENE)


## match_loading: build this PC's chart by fingerprint and go to gameplay, or report a failure.
func _on_match_loading() -> void:
	if _leaving:
		return
	var raw: Variant = _call(&"pending_match", {})
	var spec: Dictionary = raw if raw is Dictionary else {}
	var chart := build_match_chart(spec)
	if chart == null:
		var src := ""
		var e := find_entry(str(spec.get("fp", "")), str(spec.get("diff", "")))
		if e != null:
			src = str(e.get("source"))
		show_status(SongSelect.AUDIO_ERR_BUNDLED if src == "bundled" or src == "test" else SongSelect.AUDIO_ERR_USER,
			"error")
		_blip("error")
		_call(&"report_load_failed", null)
		return
	_leaving = true
	_close_dialog()
	MatchSetup.pending = null
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	SongSelect.run_pick = false
	SongSelect.pick_online = false
	Gameplay.pending_chart = chart
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	Gameplay.pending_online = true
	if _carry != null:
		_carry.from_pick = false
	var mm := get_node_or_null("/root/MenuMusic") if is_inside_tree() else null
	if mm != null and mm.has_method(&"stop"):
		mm.call(&"stop", 0.4)
	_go(GAMEPLAY_SCENE)


# ---- library -----------------------------------------------------------------------------

## The local library entry whose `diff` fingerprint is `fp` (T-04-44: lookup only, no path).
func find_entry(fp: String, diff: String) -> Object:
	if library == null or fp == "" or diff == "":
		return null
	var entries: Variant = library.get("entries")
	if not (entries is Array):
		return null
	for e: Variant in entries:
		if not (e is Object) or not (e as Object).has_method(&"difficulty"):
			continue
		var d: Variant = (e as Object).call(&"difficulty", diff)
		if d is Dictionary and str((d as Dictionary).get("fingerprint", "")) == fp:
			return e
	return null


## The match chart for a pending_match() spec, from this PC's library (null when missing or
## when it fails to build).
func build_match_chart(spec: Dictionary) -> ChartData:
	var fp := str(spec.get("fp", ""))
	var diff := str(spec.get("diff", ""))
	var e := find_entry(fp, diff)
	if e == null or not library.has_method(&"build_chart"):
		return null
	var c: Variant = library.call(&"build_chart", e, diff)
	return c if c is ChartData else null


## Host: the song key for entry `e` at `diff` ({} when it does not build).
func song_key_for(e: Object, diff: String) -> Dictionary:
	if e == null or library == null or diff == "":
		return {}
	var c: Variant = library.call(&"build_chart", e, diff)
	if not (c is ChartData):
		return {}
	var chart := c as ChartData
	var d: Variant = e.call(&"difficulty", diff)
	var fp := str((d as Dictionary).get("fingerprint", "")) if d is Dictionary else ""
	if fp == "":
		fp = chart.id
	return {"fp": fp, "sig": VersusSig.of(chart), "diff": diff, "title": str(e.get("title")),
		"artist": str(e.get("artist"))}


## Host: sets the song from a library entry. Shows the audio error when it does not build.
func set_song_from_entry(e: Object, diff: String) -> bool:
	if not _is_host or e == null:
		return false
	var key := song_key_for(e, diff)
	if key.is_empty():
		var src := str(e.get("source"))
		show_status(SongSelect.AUDIO_ERR_BUNDLED if src == "bundled" or src == "test" else SongSelect.AUDIO_ERR_USER,
			"error")
		_blip("error")
		return false
	if _status_role == "error":
		show_status("")
	var ok := bool(_call(&"host_set_song", false, [key]))
	_read_model()
	_flush_pick_log()
	_refresh()
	return ok


## Difficulty names the picked song has in this PC's library.
func available_difficulties() -> Array:
	var out: Array = []
	var e := find_entry(str(_song.get("fp", "")), str(_song.get("diff", "")))
	if e == null:
		return out
	var diffs: Variant = e.get("difficulties")
	if diffs is Array:
		for d: Variant in diffs:
			if d is Dictionary:
				out.append(str((d as Dictionary).get("name", "")))
	return out


## Returning from Song Select pick mode: the pick arrives in MatchSetup.pending.
func _apply_pick() -> void:
	var from_pick := _carry != null and _carry.from_pick
	if _carry != null:
		_carry.from_pick = false
	if not from_pick:
		return
	var m := MatchSetup.pending
	MatchSetup.pending = null
	if not _is_host or m == null or m.song_id == "" or library == null or not library.has_method(&"find"):
		return
	var e: Variant = library.call(&"find", m.song_id)
	if e is Object:
		set_song_from_entry(e, m.difficulty)


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

	var title := _label("Title", TITLE, Palette.display_font(), Palette.SIZE_HEADING, Palette.TEXT_HI, TITLE_POS)
	if _is_host:
		var cx := TITLE_POS.x + title.size.x + HOST_CHIP_GAP
		var w := UiKit.chip_width(HOST_CHIP, "info")
		_title_chip = _painter("HostChip", Rect2(cx, HOST_CHIP_Y, w, UiKit.CHIP_H), func(c: CanvasItem) -> void:
			UiKit.draw_chip(c, Rect2(0.0, 0.0, w, UiKit.CHIP_H), HOST_CHIP, "info"))
	_subtitle = _label("Subtitle", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, SUBTITLE_POS)
	_panel("LeftPanel", LEFT_RECT)
	_panel("RightPanel", RIGHT_RECT)

	# Left panel (9.1).
	_label("CaptionMatch", CAPTION_MATCH, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_MATCH_POS)
	_controls[F_SONG] = _row_button("RowSong", SONG_ROW, 0)
	_controls[F_DIFFICULTY] = _row_button("RowDifficulty", DIFFICULTY_ROW, 1)
	_controls[F_FLIGHT] = _row_button("RowFlight", FLIGHT_ROW, 2)
	_flight_line = _label("FlightLine", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, FLIGHT_LINE_POS)
	_divider("LeftDivider", Rect2(ROW_X, LEFT_DIVIDER_Y - Palette.EDGE * 0.5, ROW_W, Palette.EDGE))
	_section_caption = _label("CaptionSection", CAPTION_INVITE if _is_host else CAPTION_CONNECTION, _caption(),
		Palette.SIZE_LABEL, Palette.SONAR, CAPTION_SECTION_POS)
	_invite_label = _label("InviteLine", "", Palette.font(), Palette.SIZE_BODY,
		Palette.SONAR_PALE if _is_host else Palette.TEXT_HI, INVITE_POS)
	_second_label = _label("SecondLine", "", Palette.font(), Palette.SIZE_LABEL,
		Palette.TEXT_LO if _is_host else Palette.TEXT_MID, SECOND_LINE_POS)
	copy_button = UiKit.make_button(COPY_TEXT, "copy", "default", int(COPY_RECT.size.y))
	copy_button.name = "CopyAddress"
	copy_button.position = COPY_RECT.position
	copy_button.size = COPY_RECT.size
	copy_button.visible = _is_host
	copy_button.pressed.connect(copy_address)
	_layout.add_child(copy_button)
	_controls[F_COPY] = copy_button
	_gate_label = _label("GateLine", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, GATE_POS)
	_gate_label.clip_text = true
	_gate_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var g := Painter.new()
	g.name = "Glyph"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.position = Vector2(-(GLYPH_W + Palette.SP_SM), 2.0)
	g.size = Vector2(GLYPH_W, GLYPH_W)
	g.painter = func(c: CanvasItem) -> void:
		UiIcons.draw(c, "warning", Rect2(Vector2.ZERO, Vector2(GLYPH_W, GLYPH_W)), Palette.WARNING_RED)
	_gate_label.add_child(g)
	_gate_glyph = g
	if _is_host:
		primary_button = UiKit.make_button(START_TEXT, "", "primary", int(PRIMARY_RECT.size.y))
		primary_button.name = "StartMatch"
		_key_hint = Label.new()
		_key_hint.name = "KeyHint"
		_key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_key_hint.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		_key_hint.add_theme_color_override("font_color", Palette.TEXT_LO)
		_key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_key_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_key_hint.position = Vector2(ROW_W - Palette.SP_LG - KEY_HINT_W, 0.0)
		_key_hint.size = Vector2(KEY_HINT_W, ROW_H)
		primary_button.add_child(_key_hint)
	else:
		primary_button = UiKit.make_button(READY_TEXT, "check", "primary", int(PRIMARY_RECT.size.y))
		primary_button.name = "ReadyUp"
	primary_button.position = PRIMARY_RECT.position
	primary_button.size = PRIMARY_RECT.size
	primary_button.pressed.connect(_activate.bind(F_START))
	_layout.add_child(primary_button)
	_controls[F_START] = primary_button

	# Right panel (9.2, 9.3).
	_roster_caption = _label("RosterCaption", "", _caption(), Palette.SIZE_LABEL, Palette.SONAR, ROSTER_CAPTION_POS)
	_label("HeadName", HEAD_NAME, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(NAME_X, HEAD_BASELINE))
	var hp := _label("HeadPing", HEAD_PING, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO,
		Vector2(0.0, HEAD_BASELINE))
	hp.position.x = PING_RIGHT - hp.size.x
	_label("HeadSong", HEAD_SONG, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(SONG_X, HEAD_BASELINE))
	_label("HeadReady", HEAD_READY, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(READY_X, HEAD_BASELINE))
	_row_buttons.append(null)
	for i in ROSTER_TOPS.size():
		var rr := roster_row_rect(i)
		var v := _painter("Roster%d" % i, rr, _paint_roster_row.bind(i))
		_row_views.append(v)
		var cell := Painter.new()
		cell.name = "ReadyCell"
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.position = Vector2(READY_X - RP_X, 0.0)
		cell.size = Vector2(KICK_RIGHT - READY_X - 64.0, ROSTER_H)
		cell.painter = _paint_ready_cell.bind(i)
		v.add_child(cell)
		_ready_cells.append(cell)
		if i == 0:
			continue
		var b := Button.new()
		b.name = "RosterButton%d" % i
		b.flat = true
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.position = rr.position
		b.size = rr.size
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(_activate.bind("row%d" % i))
		b.focus_exited.connect(_redraw_rows)
		_layout.add_child(b)
		_row_buttons.append(b)
		_controls["row%d" % i] = b
	_divider("LogDivider", Rect2(RP_X, LOG_DIVIDER_Y - Palette.EDGE * 0.5, RP_RIGHT - RP_X, Palette.EDGE))
	_label("CaptionLog", CAPTION_LOG, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_LOG_POS)
	_log_painter = _painter("LobbyLog", Rect2(RP_X, LOG_BASELINES[0] - 32.0, RP_RIGHT - RP_X,
		LOG_BASELINES[LOG_MAX - 1] - LOG_BASELINES[0] + 48.0), _paint_log)

	# Footer.
	_hint_label = _label("Hint", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, HINT_POS)
	status_label = _status_line()
	_layout.add_child(status_label)

	for id: String in _controls:
		var c: Control = _controls[id]
		c.gui_input.connect(_on_control_input.bind(id))
		c.focus_entered.connect(_on_control_focus.bind(id))
		var own := c.get_path_to(c)
		c.focus_neighbor_top = own
		c.focus_neighbor_bottom = own
		c.focus_neighbor_left = own
		c.focus_neighbor_right = own
		c.focus_next = own
		c.focus_previous = own
		var host_only := id != F_START
		if not _is_host and host_only:
			c.focus_mode = Control.FOCUS_NONE
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)


## A left-panel row (Song / Difficulty / Torpedo flight): button chrome + painted content.
func _row_button(node_name: String, rect: Rect2, i: int) -> Button:
	var b := UiKit.make_button("", "", "default", int(ROW_H))
	b.name = node_name
	var p := Painter.new()
	p.name = "Content"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = rect.size
	p.painter = _paint_left_row.bind(i)
	b.add_child(p)
	_row_painters.append(p)
	b.position = rect.position
	b.size = rect.size
	b.focus_exited.connect(_redraw_rows)
	if i == 0:
		b.pressed.connect(_activate.bind(F_SONG))
	_layout.add_child(b)
	return b


func _status_line() -> Label:
	var l := Label.new()
	l.name = "StatusLine"
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
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


# ---- model / text ------------------------------------------------------------------------

func host_name() -> String:
	for r: Dictionary in _rows:
		if bool(r.get("host", false)) or int(r.get("seat", -1)) == 0:
			return str(r.get("name", ""))
	return ""


func local_seat() -> int:
	return int(_call(&"local_seat", 0 if _is_host else -1))


func my_row() -> Dictionary:
	var me := local_seat()
	for r: Dictionary in _rows:
		if int(r.get("seat", -2)) == me:
			return r
	return {}


## Client: this PC's SONG status (none when no song is picked).
func my_song_status() -> String:
	if _song.is_empty():
		return "none"
	var r := my_row()
	if not r.is_empty():
		return str(r.get("song", "checking"))
	return str(_call(&"my_song_status", "checking"))


func my_ready() -> bool:
	return bool(my_row().get("ready", false))


## The host's start gate reason (9.1 order, copy 15).
static func gate_text(gate: Dictionary) -> String:
	var who := str(gate.get("name", ""))
	var n := int(gate.get("n", 0))
	match str(gate.get("code", "need_players")):
		"ok":
			return GATE_OK
		"need_players":
			return GATE_NEED_PLAYERS
		"need_song":
			return GATE_NEED_SONG
		"syncing":
			return GATE_SYNCING
		"missing":
			return GATE_MISSING_ONE.replace("{NAME}", who) if who != "" \
				else GATE_MISSING_MANY.replace("{n}", str(n))
		"changed":
			return GATE_CHANGED_ONE.replace("{NAME}", who) if who != "" \
				else GATE_MISSING_MANY.replace("{n}", str(n))
		"not_ready":
			return GATE_NOT_READY_ONE.replace("{NAME}", who) if who != "" \
				else GATE_NOT_READY_MANY.replace("{n}", str(n))
	return GATE_NEED_PLAYERS


## Gate reasons with a person in them carry the warning glyph.
static func gate_has_glyph(gate: Dictionary) -> bool:
	var code := str(gate.get("code", ""))
	return code == "missing" or code == "changed"


func client_reason() -> String:
	match my_song_status():
		"none":
			return CLIENT_NO_SONG
		"missing":
			return CLIENT_MISSING
		"changed":
			return CLIENT_CHANGED
	return CLIENT_WAITING if my_ready() else CLIENT_READY_UP


func reason_text() -> String:
	return gate_text(_gate) if _is_host else client_reason()


func primary_enabled() -> bool:
	if _leaving:
		return false
	if _is_host:
		return bool(_gate.get("ok", false))
	return my_song_status() == "ok"


## Lobby log text for a session log_line code ("" for codes the log does not show).
static func log_text(code: String, info: Dictionary) -> String:
	var who := str(info.get("name", ""))
	var n := int(info.get("n", 0))
	match code:
		"choosing":
			return LOG_CHOOSING
		"joined":
			return LOG_JOINED.replace("{NAME}", who)
		"left":
			return LOG_LEFT.replace("{NAME}", who)
		"kicked_other":
			return LOG_KICKED.replace("{NAME}", who)
		"flight_set":
			return LOG_FLIGHT_ONE if n == 1 else LOG_FLIGHT_MANY.replace("{n}", str(n))
		"ready":
			return LOG_READY.replace("{NAME}", who)
		"missing":
			return LOG_MISSING.replace("{NAME}", who)
		"high_latency":
			return LOG_HIGH_LATENCY.replace("{NAME}", who).replace("{n}", str(n))
	return abort_line(code, who)


## Abort reasons (load_timeout, start_late, load_fail) as log lines.
static func abort_line(code: String, who: String) -> String:
	match code:
		NetProtocol.R_LOAD_TIMEOUT:
			return LOG_LOAD_TIMEOUT.replace("{NAME}", who)
		NetProtocol.R_START_LATE:
			return LOG_START_LATE.replace("{NAME}", who)
		NetProtocol.R_LOAD_FAIL:
			return LOG_LOAD_FAIL.replace("{NAME}", who)
	return ""


## Lines naming a fault carry the warning glyph and TEXT_HI.
static func is_fault_code(code: String) -> bool:
	return code in ["missing", "high_latency", "kicked_other", NetProtocol.R_LOAD_TIMEOUT,
		NetProtocol.R_START_LATE, NetProtocol.R_LOAD_FAIL]


func add_log(text: String, fault: bool = false) -> void:
	_log.append({"text": text, "fault": fault})
	while _log.size() > LOG_MAX:
		_log.pop_front()
	_fade_log_in()
	if _log_painter != null:
		_log_painter.queue_redraw()


func _start_log() -> void:
	_log = []
	_logged_song_key = _song_key(_song)
	if _carry != null and _carry.from_pick and not _carry.history.is_empty():
		_log = _carry.history.duplicate(true)
	elif _is_host:
		_log.append({"text": LOG_HOST_EMPTY, "fault": false})
	else:
		_log.append({"text": LOG_CLIENT_EMPTY.replace("{HOST}", host_name()), "fault": false})
	_drain_carry()


func _drain_carry() -> void:
	if _carry == null or _leaving:
		return
	for l: Dictionary in _carry.take():
		add_log(str(l.get("text", "")), bool(l.get("fault", false)))


## Provisional D (04-10 formula) over the roster pings, for the high-latency check.
func d_estimate() -> float:
	var worst := 0
	for r: Dictionary in _rows:
		if not bool(r.get("host", false)):
			worst = maxi(worst, int(r.get("ping_ms", 0)))
	return clampf(worst / 2000.0 + 0.053, NetProtocol.D_MIN_S, NetProtocol.D_MAX_S)


func is_row_high_latency(r: Dictionary) -> bool:
	if bool(r.get("host", false)) or not bool(r.get("synced", false)):
		return false
	var ms := int(r.get("ping_ms", 0))
	return ms > 0 and LobbyState.is_high_latency(d_estimate(), float(ms))


## Display data for roster row i (0..3): {open, seat, name, you, host, ping_text, bars, red,
## warn, song_chip, song_variant, ready_text, kick_hint}.
func row_view(i: int) -> Dictionary:
	if i >= _rows.size():
		return {"open": true, "seat": -1}
	var r: Dictionary = _rows[i]
	var host := bool(r.get("host", false))
	var synced := bool(r.get("synced", false))
	var ms := int(r.get("ping_ms", 0))
	var hi := is_row_high_latency(r)
	var ping_text := PING_HOST
	var bars := 0
	if not host:
		if not synced:
			ping_text = PING_SYNC
		else:
			ping_text = PING_FORMAT.replace("{n}", str(ms))
			bars = LobbyState.ping_bars(ms if ms > 0 else -1)
	var chip := CHIP_NO_SONG
	var variant := "muted"
	if not _song.is_empty():
		var st := "ok" if host else str(r.get("song", "checking"))
		match st:
			"ok":
				chip = CHIP_OK
				variant = "info"
			"missing":
				chip = CHIP_MISSING
				variant = "danger"
			"changed":
				chip = CHIP_CHANGED
				variant = "danger"
			_:
				chip = CHIP_CHECKING
				variant = "muted"
	var ready_text := HOST_WORD if host else (READY_WORD if bool(r.get("ready", false)) else WAITING_WORD)
	var focused_row := _is_host and i > 0 and _focus == "row%d" % i
	return {
		"open": false,
		"seat": int(r.get("seat", -1)),
		"name": str(r.get("name", "")),
		"you": int(r.get("seat", -2)) == local_seat(),
		"host": host,
		"ping_text": ping_text,
		"bars": bars,
		"red": hi,
		"warn": hi,
		"song_chip": chip,
		"song_variant": variant,
		"ready_text": ready_text,
		"kick_hint": (KICK_PAD if _last_pad else KICK_KEYS) if focused_row else "",
	}


# ---- refresh -----------------------------------------------------------------------------

func _refresh() -> void:
	if primary_button == null:
		return
	var hn := host_name()
	if _is_host:
		_invite = invite_address()
		_set_text(_subtitle, SUBTITLE_HOST.replace("{address}", _invite) if _invite != "" else INVITE_NONE)
		_set_text(_invite_label, ProgressTrack.truncate_px(_invite if _invite != "" else "-", Palette.font(),
			Palette.SIZE_BODY, INVITE_MAX_W))
		_set_text(_second_label, invite_second_line())
		copy_button.text = COPIED_TEXT if _copied_t > 0.0 else COPY_TEXT
		copy_button.disabled = _invite == ""
		primary_button.text = START_TEXT
		_key_hint.text = "A" if _last_pad else "ENTER"
	else:
		_set_text(_subtitle, SUBTITLE_CLIENT.replace("{HOST}", hn))
		_set_text(_invite_label, HOST_LINE.replace("{HOST}", hn))
		_set_text(_second_label, connection_line())
		var ready := my_ready()
		primary_button.text = CANCEL_READY_TEXT if ready else READY_TEXT
		var ic := primary_button.get_node_or_null(^"Icon") as Control
		if ic != null:
			ic.visible = ready
	primary_button.disabled = not primary_enabled()
	_set_text(_flight_line, str(FLIGHT_LINES.get(_flight, FLIGHT_LINES[2])))
	var reason := reason_text()
	_gate_label.text = reason
	var startable := _is_host and bool(_gate.get("ok", false)) or not _is_host and my_ready()
	_gate_label.add_theme_color_override("font_color", Palette.TEXT_MID if startable else Palette.TEXT_LO)
	var glyph := _is_host and gate_has_glyph(_gate) or not _is_host and my_song_status() in ["missing", "changed"]
	_gate_glyph.visible = glyph
	_gate_label.size.x = GATE_MAX_W
	_set_text(_roster_caption, ROSTER_CAPTION.replace("{n}", str(_rows.size())))
	if _is_host:
		_set_text(_hint_label, HINT_HOST_PAD if _last_pad else HINT_HOST_KEYS)
	else:
		_set_text(_hint_label, HINT_CLIENT_PAD if _last_pad else HINT_CLIENT_KEYS)
	_refresh_roster()
	_redraw_rows()


func _refresh_roster() -> void:
	for i in ROSTER_TOPS.size():
		var v := row_view(i)
		var seat := int(v.get("seat", -1))
		var was := int(_shown_seats[i])
		_shown_seats[i] = seat
		if was != -2 and seat != was and seat >= 0:
			_slide_row_in(i)
		var ready := not bool(v.get("open", true)) and str(v.get("ready_text", "")) == READY_WORD
		if ready and not bool(_shown_ready[i]) and seat == was:
			UiKit.pop_in(_ready_cells[i])
		_shown_ready[i] = ready
		if i > 0 and i < _row_buttons.size():
			var b := _row_buttons[i]
			var can := _is_host and not bool(v.get("open", true))
			b.focus_mode = Control.FOCUS_ALL if can else Control.FOCUS_NONE
			b.mouse_filter = Control.MOUSE_FILTER_STOP if can else Control.MOUSE_FILTER_IGNORE
			if not can and _focus == "row%d" % i:
				_set_focus(F_START)
		_row_views[i].queue_redraw()
		_ready_cells[i].queue_redraw()
	_log_painter.queue_redraw()


## Row in (join): fade in + slide 16 px from the right over DUR_BASE (Reduce motion: fade only).
func _slide_row_in(i: int) -> void:
	var v := _row_views[i]
	var tw: Tween = _row_tweens[i]
	if tw != null and tw.is_valid():
		tw.kill()
	var home := roster_row_rect(i).position
	if not is_inside_tree():
		v.position = home
		v.modulate.a = 1.0
		return
	v.modulate.a = 0.0
	tw = create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 1.0, Palette.DUR_BASE)
	if not UiKit.reduce_motion():
		v.position = home + Vector2(ROW_SLIDE, 0.0)
		tw.tween_property(v, "position", home, Palette.DUR_BASE)
	else:
		v.position = home
	_row_tweens[i] = tw


func _fade_log_in() -> void:
	if _log_tween != null and _log_tween.is_valid():
		_log_tween.kill()
	if not is_inside_tree():
		_log_fade = 1.0
		return
	_log_fade = 0.0
	_log_tween = create_tween()
	_log_tween.tween_method(func(a: float) -> void:
		_log_fade = a
		if _log_painter != null:
			_log_painter.queue_redraw(), 0.0, 1.0, Palette.DUR_BASE)


func _redraw_rows() -> void:
	for p in _row_painters:
		p.queue_redraw()
	for v in _row_views:
		v.queue_redraw()


func invite_address() -> String:
	var ip := NetAddress.invite_address(_addrs())
	if ip == "":
		return ""
	return NetAddress.host_port(ip, Settings.net_last_port)


func invite_second_line() -> String:
	var addrs := _addrs()
	var ip := NetAddress.invite_address(addrs)
	if ip == "":
		return ""
	if NetAddress.classify(ip) == NetAddress.TAILSCALE:
		for a in addrs:
			if NetAddress.classify(a) == NetAddress.LAN:
				return INVITE_TS_LINE.replace("{lan}", a)
		return INVITE_TS_ONLY_LINE
	return INVITE_LAN_LINE


func connection_line() -> String:
	if bool(_call(&"is_synced", false)):
		return PING_SYNCED.replace("{n}", str(int(_call(&"ping_ms", 0))))
	return PING_SYNCING


func _addrs() -> PackedStringArray:
	var raw: Variant = addrs_fn.call() if addrs_fn.is_valid() else PackedStringArray()
	if raw is PackedStringArray:
		return raw
	var out := PackedStringArray()
	if raw is Array:
		for a: Variant in raw:
			out.append(str(a))
	return out


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

func focus_order() -> Array[String]:
	var out: Array[String] = []
	if not _is_host:
		out.append(F_START)
		return out
	for id in HOST_FOCUS:
		if id == F_COPY and copy_button.disabled:
			continue
		out.append(id)
	for i in range(1, mini(_rows.size(), ROSTER_TOPS.size())):
		out.append("row%d" % i)
	return out


func _initial_focus() -> void:
	if _is_host and _song.is_empty():
		_set_focus(F_SONG)
	else:
		_set_focus(F_START)


func _on_control_focus(id: String) -> void:
	_focus = id
	_redraw_rows()


func _set_focus(id: String) -> void:
	if not focus_order().has(id):
		id = F_START
	_focus = id
	var c: Control = _controls.get(id)
	if c != null and is_inside_tree() and c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()
	_redraw_rows()


func _step_focus(dir: int) -> void:
	if not _is_host:
		return
	var order := focus_order()
	var at := order.find(_focus)
	_set_focus(order[posmod(at + dir, order.size())])


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


func _on_control_input(event: InputEvent, id: String) -> void:
	if dialog != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _is_host:
			_click(id, mb.position)
		return
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"ui_up", true):
		_step_focus(-1)
	elif event.is_action_pressed(&"ui_down", true):
		_step_focus(1)
	elif event.is_action_pressed(&"ui_left", true):
		_change(-1)
	elif event.is_action_pressed(&"ui_right", true):
		_change(1)
	elif event.is_action_pressed(&"ui_accept"):
		if not event.is_echo():
			_activate(id)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if dialog != null:
			return
		get_viewport().set_input_as_handled()
		back()


func _click(id: String, local: Vector2) -> void:
	match id:
		F_DIFFICULTY:
			_focus = id
			_change(-1 if local.x < ROW_W * 0.5 else 1)
		F_FLIGHT:
			var p := local + FLIGHT_ROW.position
			for k in FLIGHT_VALUES.size():
				if flight_tile_rect(k).has_point(p):
					set_flight(FLIGHT_VALUES[k])
					return


## Left / Right on Difficulty and Torpedo flight (host); elsewhere nothing.
func _change(dir: int) -> void:
	if not _is_host or _leaving:
		return
	match _focus:
		F_DIFFICULTY:
			var avail := available_difficulties()
			var cur := str(_song.get("diff", ""))
			var next := SongListModel.next_difficulty(avail, cur, dir)
			if next != "" and next != cur:
				var e := find_entry(str(_song.get("fp", "")), cur)
				_blip("move")
				set_song_from_entry(e, next)
		F_FLIGHT:
			var k := FLIGHT_VALUES.find(_flight)
			set_flight(FLIGHT_VALUES[posmod(k + dir, FLIGHT_VALUES.size())])


## Host: torpedo flight 2 or 1 (saved as the next default).
func set_flight(n: int) -> void:
	if not _is_host or not FLIGHT_VALUES.has(n) or n == _flight:
		return
	_call(&"host_set_flight", null, [n])
	Settings.net_flight_beats = n
	Settings.save_to(Settings.save_path)
	_blip("move")
	_read_model()
	_refresh()


func _activate(id: String) -> void:
	if dialog != null or _leaving:
		return
	match id:
		F_SONG:
			if _is_host:
				open_song_pick()
		F_COPY:
			if _is_host:
				copy_address()
		F_START:
			if _is_host:
				start_match()
			else:
				toggle_ready()
		_:
			if _is_host and id.begins_with("row"):
				open_kick(int(id.substr(3)))


## Host: Song Select pick mode (9.4). The lobby stays connected (NetSession is an autoload).
func open_song_pick() -> void:
	if not _is_host or _leaving:
		return
	# song_id stays empty until Pick Song stores the choice; Back leaves it empty (no change).
	var m := MatchSetup.new()
	m.difficulty = str(_song.get("diff", ""))
	MatchSetup.pending = m
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	SongSelect.run_pick = true
	SongSelect.pick_online = true
	if _carry != null:
		_carry.from_pick = true
	_leaving = true
	# WR-07 (UI-SPEC 9.4): clients log "Host is choosing a song." while the host is in Song Select.
	_call(&"host_choosing", null)
	_go(SONG_SELECT_SCENE)


func copy_address() -> void:
	if not _is_host or _invite == "":
		_blip("error")
		return
	if clipboard_fn.is_valid():
		clipboard_fn.call(_invite)
	_copied_t = COPIED_SEC
	_blip("confirm")
	_refresh()


## Host Start Match (D-07): every peer moves on match_loading. A blocked gate plays error.
func start_match() -> void:
	if not _is_host or _leaving:
		return
	if not primary_enabled():
		_blip("error")
		return
	var r := str(_call(&"start_match", "not_host", [start_opts]))
	if r != "":
		_blip("error")
		_read_model()
		_refresh()
		return
	_blip("confirm")


## Client: Ready Up / Cancel Ready (disabled while this PC's SONG is not OK).
func toggle_ready() -> void:
	if _is_host or _leaving:
		return
	if not primary_enabled():
		_blip("error")
		return
	_call(&"set_ready", null, [not my_ready()])
	_blip("confirm")
	_read_model()
	_refresh()


## Host: REMOVE {NAME} confirm for display row k (Keep focused).
func open_kick(k: int) -> void:
	if not _is_host or k <= 0 or k >= _rows.size():
		return
	var r: Dictionary = _rows[k]
	var who := str(r.get("name", ""))
	var seat := int(r.get("seat", -1))
	_open_dialog(KICK_TITLE.replace("{NAME}", who), KICK_BODY.replace("{NAME}", who), KICK_CONFIRM, KICK_SAFE,
		func() -> void:
			_call(&"kick", null, [seat])
			_read_model()
			_refresh())


## Esc / B: host CLOSE LOBBY, client LEAVE LOBBY confirm.
func back() -> void:
	if dialog != null or _leaving:
		return
	if _is_host:
		_open_dialog(CLOSE_TITLE, CLOSE_BODY, CLOSE_CONFIRM, STAY_TEXT, leave_lobby)
	else:
		_open_dialog(LEAVE_TITLE, LEAVE_BODY, LEAVE_CONFIRM, STAY_TEXT, leave_lobby)


## Confirmed close / leave: disconnect and wipe to Play Online.
func leave_lobby() -> void:
	if _leaving:
		return
	_leaving = true
	if _carry != null:
		_carry.pending.clear()
		_carry.history.clear()
		_carry.from_pick = false
	_call(&"leave", null)
	_go(ONLINE_SCENE)


func _open_dialog(title: String, body: String, confirm_text: String, safe_text: String, on_confirm: Callable) -> void:
	if dialog != null:
		return
	var back_to := _focus
	dialog = ConfirmDialog.new()
	dialog.name = "ConfirmDialog"
	if focus_marker != null:
		focus_marker.set_process(false)  # the dialog has its own marker
		focus_marker.visible = false
	add_child(dialog)
	dialog.setup(title, body, confirm_text, safe_text)
	dialog.safe_button.grab_focus()
	dialog.cancelled.connect(func() -> void:
		_close_dialog()
		_set_focus(back_to))
	dialog.confirmed.connect(func() -> void:
		_close_dialog()
		on_confirm.call()
		if not _leaving:
			_set_focus(back_to))


func _close_dialog() -> void:
	if dialog != null:
		dialog.visible = false
		dialog.process_mode = Node.PROCESS_MODE_DISABLED
		dialog.queue_free()
		dialog = null
	if focus_marker != null:
		focus_marker.set_process(true)


func _blip(blip_name: String) -> void:
	var snd := get_node_or_null(^"/root/UiSounds") if is_inside_tree() else null
	if snd != null and snd.has_method(&"play"):
		snd.call(&"play", blip_name)


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		# WR-02: a refused change (wipe still running) is retried from _process once idle.
		if not ScreenTransition.change_scene(path):
			_nav_pending = path


# ---- time --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _nav_pending != "" and not ScreenTransition.is_busy():
		var p := _nav_pending
		_nav_pending = ""
		_go(p)
	tick(delta)


## "Copied" timer and the 1 Hz roster re-read (PING column).
func tick(delta: float) -> void:
	if _copied_t > 0.0:
		_copied_t = maxf(_copied_t - delta, 0.0)
		if _copied_t == 0.0:
			_refresh()
	_refresh_t += delta
	if _refresh_t >= REFRESH_SEC:
		_refresh_t = 0.0
		if not _leaving:
			_read_model()
			_refresh()


# ---- painting ----------------------------------------------------------------------------

static func _baseline(h: float, f: Font, fs: int) -> float:
	return h * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5


func song_value_text() -> String:
	if _song.is_empty():
		return NO_SONG_HOST if _is_host else NO_SONG_CLIENT
	var t := str(_song.get("title", ""))
	var a := str(_song.get("artist", ""))
	return t + SONG_SEP + a if a != "" else t


func _paint_left_row(c: CanvasItem, i: int) -> void:
	var f := Palette.font()
	var fs := Palette.SIZE_BODY
	var base := _baseline(ROW_H, f, fs)
	c.draw_string(f, Vector2(LABEL_X - ROW_X, base), ROW_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Palette.TEXT_MID)
	var focused := _is_host and _focus == HOST_FOCUS[i]
	var icon_y := (ROW_H - ICON) * 0.5
	var chev := Palette.SONAR if focused else Palette.TEXT_LO
	match i:
		0:
			var txt := ProgressTrack.truncate_px(song_value_text(), f, fs, VALUE_W)
			c.draw_string(f, Vector2(VALUE_X - ROW_X, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
				Palette.TEXT_LO if _song.is_empty() else Palette.TEXT_HI)
			if _is_host:
				UiIcons.draw(c, "chevron_right", Rect2(CHEVRON_RIGHT_X - ROW_X, icon_y, ICON, ICON), chev)
		1:
			if _is_host:
				UiIcons.draw(c, "chevron_left", Rect2(CHEVRON_LEFT_X - ROW_X, icon_y, ICON, ICON), chev)
				UiIcons.draw(c, "chevron_right", Rect2(CHEVRON_RIGHT_X - ROW_X, icon_y, ICON, ICON), chev)
			var d := str(_song.get("diff", ""))
			if d != "":
				var t := d.to_upper()
				var w := UiKit.chip_width(t, "difficulty")
				UiKit.draw_chip(c, Rect2(VALUE_X - ROW_X, (ROW_H - UiKit.CHIP_H) * 0.5, w, UiKit.CHIP_H), t,
					"difficulty", MainMenu.difficulty_lane(d))
		2:
			for k in FLIGHT_VALUES.size():
				_paint_tile(c, flight_tile_rect(k), FLIGHT_TILES[k], _flight == FLIGHT_VALUES[k], focused)


## Segmented tile (P3-9.2 look). Clients: the other tile at 50% alpha.
func _paint_tile(c: CanvasItem, global_rect: Rect2, text: String, selected: bool, row_focused: bool) -> void:
	var r := Rect2(global_rect.position - FLIGHT_ROW.position, global_rect.size)
	var a := 1.0 if _is_host or selected else OTHER_TILE_ALPHA
	var sb := UiKit.style_button("focus", "default", not row_focused) if selected else UiKit.style_button("normal")
	sb = sb.duplicate() as StyleBoxFlat
	sb.bg_color.a *= a
	sb.border_color.a *= a
	c.draw_style_box(sb, r)
	var fs := Palette.SIZE_LABEL
	var f := Palette.bold() if selected else Palette.font()
	var col := Palette.TEXT_HI if selected else Palette.TEXT_MID
	col.a *= a
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	c.draw_string(f, Vector2(r.get_center().x - w * 0.5, r.position.y + _baseline(r.size.y, f, fs)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)
	if selected:
		c.draw_rect(Rect2(r.get_center().x - SEL_BAR.x * 0.5, r.end.y + 2.0, SEL_BAR.x, SEL_BAR.y), Palette.SONAR)


func _paint_roster_row(c: CanvasItem, i: int) -> void:
	var v := row_view(i)
	var r := Rect2(Vector2.ZERO, Vector2(RP_RIGHT - RP_X, ROSTER_H))
	var f := Palette.font()
	if bool(v.get("open", true)):
		_dashed_rect(c, r.grow(-0.5), Palette.alpha(Palette.TEXT_LO, OPEN_EDGE_ALPHA))
		c.draw_string(f, Vector2(NAME_X - RP_X, OPEN_BASELINE_OFFSET), OPEN_SEAT, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			Palette.SIZE_LABEL, Palette.TEXT_LO)
		c.draw_string(f, Vector2(OPEN_LINE_X - RP_X, OPEN_BASELINE_OFFSET), OPEN_SEAT_LINE, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, Palette.SIZE_LABEL, Palette.TEXT_LO)
		return
	var focused := i > 0 and i < _row_buttons.size() and _row_buttons[i].has_focus()
	if focused:
		c.draw_style_box(UiKit.style_button("focus"), r)
	elif bool(v.get("you", false)):
		c.draw_rect(r, Palette.alpha(Palette.ABYSS_600, Palette.HUD_GLASS_ALPHA))
	else:
		c.draw_rect(Rect2(0.0, r.size.y - 1.0, r.size.x, 1.0), Palette.alpha(Palette.SONAR, ROW_DIVIDER_ALPHA))
	if bool(v.get("you", false)):
		c.draw_rect(Rect2(0.0, 0.0, YOU_BAR_W, r.size.y), Palette.SONAR)
	var gy := (ROSTER_H - ROW_GLYPH) * 0.5
	if bool(v.get("host", false)):
		UiIcons.draw(c, "host", Rect2(HOST_GLYPH_X - RP_X - ROW_GLYPH * 0.5 + 2.0, gy, ROW_GLYPH, ROW_GLYPH),
			Palette.SONAR)
	var fs := Palette.SIZE_BODY
	c.draw_string(f, Vector2(NAME_X - RP_X, NAME_BASELINE_OFFSET), ProgressTrack.truncate_px(str(v.get("name", "")), f, fs,
		NAME_MAX_W), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Palette.TEXT_HI)
	# PING: glyph at 1320, value right-aligned at 1440, warning glyph at 1296 when high.
	var red := bool(v.get("red", false))
	var host := bool(v.get("host", false))
	var pt := str(v.get("ping_text", ""))
	var pcol := Palette.WARNING_RED if red else (Palette.TEXT_LO if host or pt == PING_SYNC else Palette.TEXT_HI)
	if not host:
		UiIcons.draw_signal(c, Rect2(SIGNAL_X - RP_X, gy, ROW_GLYPH, ROW_GLYPH), int(v.get("bars", 0)),
			Palette.WARNING_RED if red else Palette.SONAR)
	if bool(v.get("warn", false)):
		UiIcons.draw(c, "warning", Rect2(WARN_X - RP_X - WARN_GLYPH, (ROSTER_H - WARN_GLYPH) * 0.5, WARN_GLYPH,
			WARN_GLYPH), Palette.WARNING_RED)
	var pw := f.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var pfs := fs
	if pt == PING_SYNC:
		pfs = Palette.SIZE_LABEL
		pw = f.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pfs).x
	c.draw_string(f, Vector2(PING_RIGHT - RP_X - pw, NAME_BASELINE_OFFSET), pt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pfs,
		pcol)
	# SONG chip at 1480.
	var chip := str(v.get("song_chip", ""))
	var variant := str(v.get("song_variant", "muted"))
	var cw := UiKit.chip_width(chip, variant)
	UiKit.draw_chip(c, Rect2(SONG_X - RP_X, (ROSTER_H - UiKit.CHIP_H) * 0.5, cw, UiKit.CHIP_H), chip, variant)
	# Kick hint (host, focused client row).
	var kh := str(v.get("kick_hint", ""))
	if kh != "":
		var kw := f.get_string_size(kh, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Palette.SIZE_LABEL).x
		c.draw_string(f, Vector2(KICK_RIGHT - RP_X - kw, OPEN_BASELINE_OFFSET), kh, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			Palette.SIZE_LABEL, Palette.TEXT_LO)


## READY column cell (its own node so the check can pop).
func _paint_ready_cell(c: CanvasItem, i: int) -> void:
	var v := row_view(i)
	if bool(v.get("open", true)):
		return
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var t := str(v.get("ready_text", ""))
	match t:
		READY_WORD:
			UiIcons.draw(c, "check", Rect2(0.0, (ROSTER_H - ROW_GLYPH) * 0.5, ROW_GLYPH, ROW_GLYPH), Palette.SONAR)
			c.draw_string(f, Vector2(ROW_GLYPH + Palette.SP_XS, OPEN_BASELINE_OFFSET), t, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				fs, Palette.SONAR)
		HOST_WORD:
			c.draw_string(f, Vector2(0.0, OPEN_BASELINE_OFFSET), t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Palette.TEXT_MID)
		_:
			c.draw_string(f, Vector2(0.0, OPEN_BASELINE_OFFSET), t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Palette.TEXT_LO)


func _dashed_rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for k in 4:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var length := a.distance_to(b)
		var dirv := (b - a) / length
		var t := 0.0
		while t < length:
			var e := minf(t + DASH, length)
			c.draw_line(a + dirv * t, a + dirv * e, col, 1.0)
			t += DASH + DASH_GAP


func _paint_log(c: CanvasItem) -> void:
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var top := LOG_BASELINES[0] - 32.0
	for k in _log.size():
		var l: Dictionary = _log[k]
		var y := LOG_BASELINES[k] - top
		var fault := bool(l.get("fault", false))
		var a := _log_fade if k == _log.size() - 1 else 1.0
		var x := 0.0
		if fault:
			UiIcons.draw(c, "warning", Rect2(0.0, y - GLYPH_W, GLYPH_W, GLYPH_W), Palette.alpha(Palette.WARNING_RED, a))
			x = GLYPH_W + Palette.SP_SM
		var col := Palette.TEXT_HI if fault else Palette.TEXT_MID
		col.a *= a
		c.draw_string(f, Vector2(x, y), ProgressTrack.truncate_px(str(l.get("text", "")), f, fs, LOG_MAX_W - x),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


# ---- helpers -----------------------------------------------------------------------------

static func roster_row_rect(i: int) -> Rect2:
	return Rect2(RP_X, ROSTER_TOPS[i], RP_RIGHT - RP_X, ROSTER_H)


static func flight_tile_rect(k: int) -> Rect2:
	return Rect2(FLIGHT_TILE_X[k], FLIGHT_TILE_Y, FLIGHT_TILE_SIZE.x, FLIGHT_TILE_SIZE.y)


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
	if UiKit.reduce_motion():
		for i in _row_tweens.size():
			var tw: Tween = _row_tweens[i]
			if tw != null and tw.is_valid():
				tw.kill()
				_row_tweens[i] = null
				_row_views[i].position = roster_row_rect(i).position
				_row_views[i].modulate.a = 1.0
	_redraw_rows()


func effect_counts() -> Dictionary:
	# Roster row in: fade + slide (fade only under Reduce motion); ready check pop (none under
	# Reduce motion); log line fade in every mode.
	return {"row_slide": not UiKit.reduce_motion(), "ready_pop": not UiKit.reduce_motion(), "log_fade": true}


# ---- test seams --------------------------------------------------------------------------

func debug_state() -> Dictionary:
	var rows: Array = []
	for i in ROSTER_TOPS.size():
		var v := row_view(i)
		v["rect"] = roster_row_rect(i)
		v["focusable"] = i > 0 and i < _row_buttons.size() and _row_buttons[i].focus_mode != Control.FOCUS_NONE
		rows.append(v)
	var log_lines: Array = []
	for l: Dictionary in _log:
		log_lines.append(str(l.get("text", "")))
	var focusable: Array = []
	for id: String in _controls:
		var c: Control = _controls[id]
		if c.focus_mode != Control.FOCUS_NONE and c.visible:
			focusable.append(id)
	return {
		"host": _is_host,
		"focus": _focus,
		"focus_order": Array(focus_order()),
		"focusable": focusable,
		"gate_text": _gate_label.text,
		"gate_glyph": _gate_glyph.visible,
		"primary_text": primary_button.text,
		"primary_disabled": primary_button.disabled,
		"rows": rows,
		"log": log_lines,
		"log_faults": _log.map(func(l: Dictionary) -> bool: return bool(l.get("fault", false))),
		"song_value": song_value_text(),
		"difficulty": str(_song.get("diff", "")),
		"flight": _flight,
		"flight_line": _flight_line.text,
		"subtitle": _subtitle.text,
		"section_caption": _section_caption.text,
		"invite": _invite_label.text,
		"second_line": _second_label.text,
		"copy_text": copy_button.text,
		"copy_visible": copy_button.visible,
		"roster_caption": _roster_caption.text,
		"hint": _hint_label.text,
		"status": status_label.text if status_label.visible else "",
		"status_role": _status_role,
		"dialog": dialog.title_label.text if dialog != null else "",
		"leaving": _leaving,
	}


func focus_row_for_test(id: String) -> void:
	_set_focus(id)


func press_key_for_test(keycode: int) -> void:
	if dialog != null:
		match keycode:
			KEY_ESCAPE:
				dialog.cancelled.emit()
			KEY_ENTER, KEY_KP_ENTER:
				if dialog.confirm_button.has_focus():
					dialog.confirmed.emit()
				else:
					dialog.cancelled.emit()
		return
	match keycode:
		KEY_UP:
			_step_focus(-1)
		KEY_DOWN:
			_step_focus(1)
		KEY_LEFT:
			_change(-1)
		KEY_RIGHT:
			_change(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_focus)
		KEY_ESCAPE:
			back()
