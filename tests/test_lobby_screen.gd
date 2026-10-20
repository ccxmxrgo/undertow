extends GdUnitTestSuite
## LobbyScreen (04-UI-SPEC 9, 9.1-9.5, 15, 16; NET-01, NET-02, D-08, D-11, D-12): region rects,
## host vs client controls, start gate order and reason copy, Ready cleared on a song change,
## roster columns, MISSING / CHANGED chips, high latency, kick confirm, log max 6, Start Match,
## match_loading hand-off (chart by fingerprint, load failure), client Ready, song pick round
## trip, flight, Esc confirms, return messages, has_char for every constant string.
## Uses a FakeSession + FakeLibrary and redirects Settings.save_path to a temp file.

const D := "user://test_lobby_screen"
const SETTINGS_TMP := D + "/settings.cfg"
const SCENE := "res://scenes/lobby.tscn"


## Same method names as NetSession; the start gate is the real LobbyState rule over `rows`.
class FakeSession:
	extends Node
	signal lobby_changed
	signal log_line(code: String, info: Dictionary)
	signal left_lobby(code: String)
	signal match_loading
	signal match_aborted_to_lobby(code: String, name: String)
	signal returned_to_lobby
	signal host_left(kind: String)

	var calls: Array = []
	var host := true
	var seat := 0
	var rows: Array = []
	var song := {}
	var flight_beats := 2
	var synced := true
	var ping := 0
	var offline := false
	var pending := {}
	var start_result := ""

	func is_host() -> bool:
		return host

	func is_offline() -> bool:
		return offline

	func local_seat() -> int:
		return seat

	func lobby_rows() -> Array:
		return rows.duplicate(true)

	func lobby_song() -> Dictionary:
		return song.duplicate()

	func flight() -> int:
		return flight_beats

	func is_synced() -> bool:
		return synced

	func ping_ms() -> int:
		return ping

	func my_song_status() -> String:
		return "none"

	func pending_match() -> Dictionary:
		return pending.duplicate(true)

	func start_gate() -> Dictionary:
		var wire: Array = []
		for r: Dictionary in rows:
			wire.append({"seat": r.seat, "peer_id": int(r.seat) + 1, "name": r.name, "ready": r.ready,
				"song_status": "none" if song.is_empty() else ("ok" if r.host else r.song),
				"ping_ms": r.ping_ms, "synced": r.synced, "host": r.host})
		var ls := LobbyState.new()
		ls.apply_wire({"rev": 0, "flight": flight_beats, "song": song, "rows": wire})
		return ls.start_gate()

	func host_set_song(s: Dictionary) -> bool:
		calls.append(["host_set_song", s.duplicate()])
		song = s.duplicate()
		for r: Dictionary in rows:
			if not r.host:
				r.ready = false
				r.song = "checking"
		log_line.emit("song_picked", {"name": "", "n": 0})
		return true

	func host_set_flight(n: int) -> void:
		calls.append(["host_set_flight", n])
		flight_beats = n

	func set_ready(on: bool) -> void:
		calls.append(["set_ready", on])
		for r: Dictionary in rows:
			if r.seat == seat:
				r.ready = on

	func kick(s: int) -> void:
		calls.append(["kick", s])

	func leave() -> void:
		calls.append(["leave"])
		offline = true

	func start_match(opts := {}) -> String:
		calls.append(["start_match", opts])
		return start_result

	func host_choosing() -> void:
		calls.append(["host_choosing"])

	func report_load_failed() -> void:
		calls.append(["report_load_failed"])

	func count(kind: String) -> int:
		var n := 0
		for c: Array in calls:
			if c[0] == kind:
				n += 1
		return n

	func last(kind: String) -> Array:
		for i in range(calls.size() - 1, -1, -1):
			if calls[i][0] == kind:
				return calls[i]
		return []


## SongLibrary stand-in: entries + find + build_chart (null for ids in `broken`).
class FakeLibrary:
	extends Node
	var entries: Array = []
	var broken := {}
	var builds := 0

	func find(id: String) -> SongEntry:
		for e: SongEntry in entries:
			if e.id == id:
				return e
		return null

	func build_chart(e: SongEntry, diff: String) -> ChartData:
		builds += 1
		if broken.has(e.id):
			return null
		var d := e.difficulty(diff)
		if d.is_empty():
			return null
		var c := ChartData.new()
		c.id = str(d.fingerprint)
		c.title = e.title
		c.artist = e.artist
		c.difficulty = diff
		return c


var _old_path: String
var _old_reduce: bool
var _old_port: int
var _old_flight: int
var _nav: Array = []
var _clip: Array = []


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))
	_old_path = Settings.save_path
	Settings.save_path = SETTINGS_TMP
	_old_reduce = Settings.reduce_motion
	_old_port = Settings.net_last_port
	_old_flight = Settings.net_flight_beats
	Settings.reduce_motion = true
	Settings.net_last_port = 47474
	Settings.net_flight_beats = 2
	MatchSetup.pending = null
	Gameplay.pending_chart = null
	SongSelect.run_pick = false
	SongSelect.pick_online = false
	_nav = []
	_clip = []


func after_test() -> void:
	Settings.reduce_motion = _old_reduce
	Settings.net_last_port = _old_port
	Settings.net_flight_beats = _old_flight
	Settings.save_path = _old_path
	MatchSetup.pending = null
	Gameplay.pending_chart = null
	SongSelect.run_pick = false
	SongSelect.pick_online = false
	for p in [SETTINGS_TMP, SETTINGS_TMP + ".tmp", SETTINGS_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func _row(seat: int, row_name: String, ready := false, song := "ok", ping := 40, synced := true) -> Dictionary:
	return {"seat": seat, "name": row_name, "ready": ready, "song": song, "ping_ms": 0 if seat == 0 else ping,
		"synced": true if seat == 0 else synced, "host": seat == 0}


func _entry(id: String, title: String, diffs: Array = ["easy", "hard", "expert"]) -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.artist = "Artist " + id
	e.status = "ok"
	e.source = "songs"
	var ds: Array[Dictionary] = []
	for d: String in diffs:
		ds.append({"name": d, "fingerprint": "fp_%s_%s" % [id, d], "note_count": 100})
	e.difficulties = ds
	return e


func _library() -> FakeLibrary:
	var lib := FakeLibrary.new()
	lib.entries = [_entry("s1", "Deep Song"), _entry("s2", "Other Tune")]
	add_child(lib)
	auto_free(lib)
	return lib


func _song(lib: FakeLibrary, id := "s1", diff := "hard") -> Dictionary:
	var e := lib.find(id)
	var c := lib.build_chart(e, diff)
	return {"fp": c.id, "sig": VersusSig.of(c), "diff": diff, "title": e.title, "artist": e.artist}


func _session(host := true) -> FakeSession:
	var s := FakeSession.new()
	s.name = "FakeSession"
	s.host = host
	s.seat = 0 if host else 1
	s.rows = [_row(0, "HOSTY")]
	add_child(s)
	auto_free(s)
	return s


func _screen(s: FakeSession, lib: FakeLibrary = null,
		addrs: Array = ["100.101.5.7", "192.168.1.20"]) -> LobbyScreen:
	var m: LobbyScreen = (load(SCENE) as PackedScene).instantiate()
	m.session = s
	m.library = lib if lib != null else _library()
	m.navigate = func(p: String) -> void: _nav.append(p)
	m.addrs_fn = func() -> PackedStringArray: return PackedStringArray(addrs)
	m.clipboard_fn = func(t: String) -> void: _clip.append(t)
	add_child(m)
	auto_free(m)
	return m


func _changed(s: FakeSession) -> void:
	s.lobby_changed.emit()


# ---- layout ------------------------------------------------------------------------------

func test_region_rects_match_ui_spec_9() -> void:
	var m := _screen(_session())
	assert_that(LobbyScreen.LEFT_RECT).is_equal(Rect2(64, 176, 880, 728))
	assert_that(LobbyScreen.RIGHT_RECT).is_equal(Rect2(976, 176, 880, 728))
	assert_that(LobbyScreen.SONG_ROW).is_equal(Rect2(96, 240, 816, 64))
	assert_that(LobbyScreen.DIFFICULTY_ROW).is_equal(Rect2(96, 312, 816, 64))
	assert_that(LobbyScreen.FLIGHT_ROW).is_equal(Rect2(96, 384, 816, 64))
	assert_that(LobbyScreen.flight_tile_rect(0)).is_equal(Rect2(400, 392, 208, 48))
	assert_that(LobbyScreen.flight_tile_rect(1)).is_equal(Rect2(624, 392, 208, 48))
	assert_that(LobbyScreen.COPY_RECT).is_equal(Rect2(96, 656, 320, 48))
	assert_that(LobbyScreen.PRIMARY_RECT).is_equal(Rect2(96, 808, 816, 64))
	assert_that(Rect2(m.primary_button.position, m.primary_button.size)).is_equal(LobbyScreen.PRIMARY_RECT)
	assert_that(Rect2(m.copy_button.position, m.copy_button.size)).is_equal(LobbyScreen.COPY_RECT)
	for i in 4:
		assert_that(LobbyScreen.roster_row_rect(i)).is_equal(Rect2(1008, 272 + 72 * i, 816, 64))
	assert_array(Array(LobbyScreen.LOG_BASELINES)).is_equal([656.0, 696.0, 736.0, 776.0, 816.0, 856.0])
	assert_str(m.debug_state()["roster_caption"]).is_equal("SUBS IN THIS LOBBY 1/4")


func test_roster_column_positions() -> void:
	assert_float(LobbyScreen.NAME_X).is_equal(1032.0)
	assert_float(LobbyScreen.PING_RIGHT).is_equal(1440.0)
	assert_float(LobbyScreen.SIGNAL_X).is_equal(1320.0)
	assert_float(LobbyScreen.WARN_X).is_equal(1296.0)
	assert_float(LobbyScreen.SONG_X).is_equal(1480.0)
	assert_float(LobbyScreen.READY_X).is_equal(1664.0)
	assert_float(LobbyScreen.KICK_RIGHT).is_equal(1808.0)
	assert_float(LobbyScreen.HEAD_BASELINE).is_equal(256.0)


func test_no_full_rect_preset_in_source() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/online/lobby_screen.gd")
	assert_bool(src.contains("PRESET_" + "FULL_RECT")).is_false()


# ---- host vs client ----------------------------------------------------------------------

func test_host_controls_and_focus_order() -> void:
	var s := _session()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO"), _row(2, "THREE")]
	var m := _screen(s)
	var st := m.debug_state()
	assert_bool(st["host"]).is_true()
	assert_str(st["section_caption"]).is_equal("INVITE")
	assert_bool(st["copy_visible"]).is_true()
	assert_str(st["invite"]).is_equal("100.101.5.7:47474")
	assert_str(st["second_line"]).is_equal("Tailscale address. Friends on your LAN can use 192.168.1.20.")
	assert_str(st["subtitle"]).is_equal("You are hosting. Friends join with 100.101.5.7:47474.")
	assert_str(st["primary_text"]).is_equal("Start Match")
	assert_array(st["focus_order"]).is_equal(["song", "difficulty", "flight", "copy", "start", "row1", "row2"])
	# No song yet: initial focus is Song.
	assert_str(st["focus"]).is_equal("song")
	assert_str(st["song_value"]).is_equal("Choose a song")
	m.press_key_for_test(KEY_UP)
	assert_str(m.debug_state()["focus"]).is_equal("row2")
	m.press_key_for_test(KEY_DOWN)
	assert_str(m.debug_state()["focus"]).is_equal("song")
	assert_bool(st["rows"][1]["focusable"]).is_true()
	assert_bool(st["rows"][3]["focusable"]).is_false()
	assert_str(st["hint"]).is_equal(LobbyScreen.HINT_HOST_KEYS)


func test_lan_only_invite_line() -> void:
	var m := _screen(_session(), null, ["192.168.1.20"])
	assert_str(m.debug_state()["second_line"]).is_equal("LAN address. Friends outside your network need Tailscale.")
	assert_str(m.debug_state()["invite"]).is_equal("192.168.1.20:47474")


func test_client_controls_are_read_only() -> void:
	var s := _session(false)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "ok")]
	s.ping = 37
	var lib := _library()
	s.song = _song(lib)
	var m := _screen(s, lib)
	var st := m.debug_state()
	assert_bool(st["host"]).is_false()
	assert_array(st["focusable"]).is_equal(["start"])
	assert_array(st["focus_order"]).is_equal(["start"])
	assert_str(st["focus"]).is_equal("start")
	assert_bool(st["copy_visible"]).is_false()
	assert_str(st["section_caption"]).is_equal("CONNECTION")
	assert_str(st["invite"]).is_equal("HOST HOSTY")
	assert_str(st["second_line"]).is_equal("PING 37 MS · CLOCK SYNCED")
	assert_str(st["subtitle"]).is_equal("Connected to HOSTY's lobby.")
	assert_str(st["song_value"]).is_equal("Deep Song · Artist s1")
	assert_str(st["hint"]).is_equal(LobbyScreen.HINT_CLIENT_KEYS)
	assert_str(st["log"][0]).is_equal("You joined HOSTY's lobby.")
	# Host-only actions do nothing for a client.
	m.press_key_for_test(KEY_RIGHT)
	m.open_song_pick()
	m.set_flight(1)
	assert_int(s.count("host_set_flight")).is_equal(0)
	assert_array(_nav).is_empty()
	s.synced = false
	m.tick(1.0)
	assert_str(m.debug_state()["second_line"]).is_equal("PING -- MS · SYNCING CLOCK")


func test_client_without_song_sees_choosing_text() -> void:
	var s := _session(false)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "checking")]
	var m := _screen(s)
	var st := m.debug_state()
	assert_str(st["song_value"]).is_equal("Host is choosing a song")
	assert_str(st["gate_text"]).is_equal("Waiting for the host to pick a song.")
	assert_bool(st["primary_disabled"]).is_true()


# ---- start gate --------------------------------------------------------------------------

func test_start_gate_order_and_reason_copy() -> void:
	var s := _session()
	var lib := _library()
	var m := _screen(s, lib)
	var gate := func() -> String:
		_changed(s)
		return str(m.debug_state()["gate_text"])
	assert_str(gate.call()).is_equal("Waiting for at least 1 friend to join.")
	assert_bool(m.debug_state()["primary_disabled"]).is_true()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "ok", 40, false)]
	assert_str(gate.call()).is_equal("Pick a song first.")
	s.song = _song(lib)
	assert_str(gate.call()).is_equal("Syncing clocks...")
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "missing")]
	assert_str(gate.call()).is_equal("TWO is missing the song.")
	assert_bool(m.debug_state()["gate_glyph"]).is_true()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "missing"), _row(2, "THREE", false, "missing")]
	assert_str(gate.call()).is_equal("2 subs are missing the song.")
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "changed")]
	assert_str(gate.call()).is_equal("TWO has a different version of this song.")
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "ok")]
	assert_str(gate.call()).is_equal("Waiting for TWO to ready up.")
	assert_bool(m.debug_state()["gate_glyph"]).is_false()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "ok"), _row(2, "THREE", false, "ok")]
	assert_str(gate.call()).is_equal("Waiting for 2 subs to ready up.")
	assert_bool(m.debug_state()["primary_disabled"]).is_true()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", true, "ok"), _row(2, "THREE", true, "ok")]
	assert_str(gate.call()).is_equal("All subs ready. Start when you like.")
	assert_bool(m.debug_state()["primary_disabled"]).is_false()


func test_start_match_calls_session_only_when_gate_passes() -> void:
	var s := _session()
	var lib := _library()
	s.song = _song(lib)
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", false, "ok")]
	var m := _screen(s, lib)
	assert_str(m.debug_state()["focus"]).is_equal("start")
	m.press_key_for_test(KEY_ENTER)
	assert_int(s.count("start_match")).is_equal(0)
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", true, "ok")]
	_changed(s)
	m.start_opts = {"seed": 7}
	m.press_key_for_test(KEY_ENTER)
	assert_int(s.count("start_match")).is_equal(1)
	assert_that(s.last("start_match")[1]).is_equal({"seed": 7})


func test_ready_cleared_on_song_change() -> void:
	var s := _session()
	var lib := _library()
	s.song = _song(lib, "s1", "hard")
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", true, "ok")]
	var m := _screen(s, lib)
	assert_str(m.debug_state()["rows"][1]["ready_text"]).is_equal("READY")
	m.focus_row_for_test("difficulty")
	m.press_key_for_test(KEY_RIGHT)
	var call := s.last("host_set_song")
	assert_array(call).is_not_empty()
	var key: Dictionary = call[1]
	assert_str(key["diff"]).is_equal("expert")
	assert_str(key["fp"]).is_equal("fp_s1_expert")
	assert_str(key["sig"]).has_length(16)
	assert_str(key["title"]).is_equal("Deep Song")
	var st := m.debug_state()
	assert_str(st["difficulty"]).is_equal("expert")
	assert_str(st["rows"][1]["ready_text"]).is_equal("WAITING")
	assert_str(st["rows"][1]["song_chip"]).is_equal("CHECKING")
	assert_str(st["log"][st["log"].size() - 1]).is_equal("Host picked Deep Song (EXPERT). Ready cleared.")


# ---- roster ------------------------------------------------------------------------------

func test_roster_rows_chips_ping_and_open_seats() -> void:
	var s := _session()
	var lib := _library()
	s.song = _song(lib)
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO", true, "missing", 50), _row(2, "THREE", false, "changed", 150),
		_row(3, "FOUR", false, "checking", 0, false)]
	var m := _screen(s, lib)
	var rows: Array = m.debug_state()["rows"]
	assert_bool(rows[0]["you"]).is_true()
	assert_bool(rows[0]["host"]).is_true()
	assert_str(rows[0]["ping_text"]).is_equal("-")
	assert_str(rows[0]["song_chip"]).is_equal("OK")
	assert_str(rows[0]["song_variant"]).is_equal("info")
	assert_str(rows[0]["ready_text"]).is_equal("HOST")
	assert_str(rows[1]["song_chip"]).is_equal("MISSING")
	assert_str(rows[1]["song_variant"]).is_equal("danger")
	assert_str(rows[1]["ping_text"]).is_equal("50 MS")
	assert_int(rows[1]["bars"]).is_equal(4)
	assert_str(rows[1]["ready_text"]).is_equal("READY")
	assert_str(rows[2]["song_chip"]).is_equal("CHANGED")
	assert_str(rows[2]["song_variant"]).is_equal("danger")
	assert_int(rows[2]["bars"]).is_equal(2)
	assert_str(rows[2]["ready_text"]).is_equal("WAITING")
	assert_str(rows[3]["ping_text"]).is_equal("SYNC")
	assert_int(rows[3]["bars"]).is_equal(0)
	assert_str(rows[3]["song_chip"]).is_equal("CHECKING")
	assert_str(m.debug_state()["roster_caption"]).is_equal("SUBS IN THIS LOBBY 4/4")
	# Draw once with every state.
	await get_tree().process_frame
	# Two leave: open seats, NO SONG chips once the song is cleared.
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO")]
	s.song = {}
	_changed(s)
	rows = m.debug_state()["rows"]
	assert_bool(rows[2]["open"]).is_true()
	assert_bool(rows[3]["open"]).is_true()
	assert_str(rows[1]["song_chip"]).is_equal("NO SONG")
	assert_str(rows[1]["song_variant"]).is_equal("muted")
	await get_tree().process_frame


func test_only_host_shows_three_open_seats() -> void:
	var m := _screen(_session())
	var rows: Array = m.debug_state()["rows"]
	for i in range(1, 4):
		assert_bool(rows[i]["open"]).is_true()
	assert_str(m.debug_state()["log"][0]).is_equal("Lobby open. Share your address to invite friends.")


func test_high_latency_red_glyph_and_log_line() -> void:
	var s := _session()
	s.rows = [_row(0, "HOSTY"), _row(1, "FAR", false, "ok", 400), _row(2, "NEAR", false, "ok", 30)]
	var m := _screen(s)
	var rows: Array = m.debug_state()["rows"]
	assert_bool(rows[1]["red"]).is_true()
	assert_bool(rows[1]["warn"]).is_true()
	assert_int(rows[1]["bars"]).is_equal(1)
	# D is the worst link's estimate, so with FAR at 400 ms even NEAR's 30 ms stays under 250 ms total.
	assert_bool(rows[2]["red"]).is_false()
	s.log_line.emit("high_latency", {"name": "FAR", "n": 400})
	var st := m.debug_state()
	assert_str(st["log"][st["log"].size() - 1]).is_equal(
		"High latency to FAR (400 ms). Torpedo warnings may be shorter than 1 beat.")
	assert_bool(st["log_faults"][st["log_faults"].size() - 1]).is_true()
	await get_tree().process_frame


func test_kick_confirm_then_session_kick() -> void:
	var s := _session()
	s.rows = [_row(0, "HOSTY"), _row(1, "TWO"), _row(2, "THREE")]
	var m := _screen(s)
	m.focus_row_for_test("row2")
	assert_str(m.debug_state()["rows"][2]["kick_hint"]).is_equal("ENTER KICK")
	m.press_key_for_test(KEY_ENTER)
	assert_str(m.debug_state()["dialog"]).is_equal("REMOVE THREE")
	assert_bool(m.dialog.safe_button.has_focus()).is_true()
	assert_str(m.dialog.safe_button.text).is_equal("Keep")
	m.press_key_for_test(KEY_ESCAPE)
	assert_str(m.debug_state()["dialog"]).is_equal("")
	assert_int(s.count("kick")).is_equal(0)
	m.focus_row_for_test("row2")
	m.press_key_for_test(KEY_ENTER)
	m.dialog.confirm_button.grab_focus()
	m.press_key_for_test(KEY_ENTER)
	assert_array(s.last("kick")).is_equal(["kick", 2])
	await get_tree().process_frame


# ---- lobby log ---------------------------------------------------------------------------

func test_log_keeps_at_most_six_lines_and_maps_codes() -> void:
	var s := _session()
	var m := _screen(s)
	s.log_line.emit("joined", {"name": "TWO", "n": 1})
	s.log_line.emit("ready", {"name": "TWO", "n": 0})
	s.log_line.emit("flight_set", {"name": "", "n": 1})
	s.log_line.emit("flight_set", {"name": "", "n": 2})
	s.log_line.emit("missing", {"name": "TWO", "n": 0})
	s.log_line.emit("kicked_other", {"name": "TWO", "n": 1})
	s.log_line.emit("left", {"name": "THREE", "n": 2})
	s.log_line.emit("choosing", {"name": "", "n": 0})
	var lines: Array = m.debug_state()["log"]
	assert_int(lines.size()).is_equal(6)
	assert_array(lines).is_equal([
		"Torpedo flight set to 1 beat.",
		"Torpedo flight set to 2 beats.",
		"TWO is missing this song.",
		"TWO was removed by the host.",
		"THREE left.",
		"Host is choosing a song.",
	])
	assert_array(m.debug_state()["log_faults"]).is_equal([false, false, true, true, false, false])


func test_client_song_picked_line_waits_for_the_new_song() -> void:
	var s := _session(false)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "checking")]
	var lib := _library()
	var m := _screen(s, lib)
	s.log_line.emit("song_picked", {"name": "", "n": 0})
	assert_int(m.debug_state()["log"].size()).is_equal(1)
	s.song = _song(lib, "s2", "easy")
	_changed(s)
	var lines: Array = m.debug_state()["log"]
	assert_str(lines[lines.size() - 1]).is_equal("Host picked Other Tune (EASY). Ready cleared.")


func test_abort_and_return_messages_carry_into_the_next_lobby() -> void:
	var s := _session()
	var m := _screen(s)
	m.free()
	s.match_aborted_to_lobby.emit("load_timeout", "TWO")
	s.match_aborted_to_lobby.emit("start_late", "THREE")
	s.match_aborted_to_lobby.emit("load_fail", "FOUR")
	s.returned_to_lobby.emit()
	var m2 := _screen(s)
	assert_array(m2.debug_state()["log"]).is_equal([
		"Lobby open. Share your address to invite friends.",
		"TWO could not load the song in time. Back in the lobby.",
		"The start signal reached THREE too late. Back in the lobby.",
		"FOUR could not load this song. Back in the lobby.",
		"Match ended. Ready up for another.",
	])
	assert_array(m2.debug_state()["log_faults"]).is_equal([false, true, true, true, false])
	m2.free()
	var m3 := _screen(s)
	assert_int(m3.debug_state()["log"].size()).is_equal(1)


# ---- hand-off ----------------------------------------------------------------------------

func test_match_loading_builds_chart_by_fingerprint_and_navigates() -> void:
	var s := _session(false)
	var lib := _library()
	s.song = _song(lib, "s2", "expert")
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", true, "ok")]
	var m := _screen(s, lib)
	MatchSetup.pending = MatchSetup.new()
	s.pending = {"fp": "fp_s2_expert", "diff": "expert", "sig": s.song.sig}
	s.match_loading.emit()
	assert_array(_nav).is_equal([LobbyScreen.GAMEPLAY_SCENE])
	assert_str(LobbyScreen.GAMEPLAY_SCENE).is_equal("res://scenes/gameplay.tscn")
	assert_object(Gameplay.pending_chart).is_not_null()
	assert_str(Gameplay.pending_chart.id).is_equal("fp_s2_expert")
	assert_object(MatchSetup.pending).is_null()
	assert_int(s.count("report_load_failed")).is_equal(0)
	assert_bool(m.debug_state()["leaving"]).is_true()


func test_match_loading_library_miss_reports_load_fail() -> void:
	var s := _session(false)
	var lib := _library()
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", true, "ok")]
	var m := _screen(s, lib)
	s.pending = {"fp": "fp_unknown", "diff": "expert", "sig": "0123456789abcdef"}
	s.match_loading.emit()
	assert_array(_nav).is_empty()
	assert_object(Gameplay.pending_chart).is_null()
	assert_int(s.count("report_load_failed")).is_equal(1)
	assert_str(m.debug_state()["status_role"]).is_equal("error")
	# A found entry that fails to build also reports.
	lib.broken["s1"] = true
	s.pending = {"fp": "fp_s1_hard", "diff": "hard", "sig": "0123456789abcdef"}
	s.match_loading.emit()
	assert_int(s.count("report_load_failed")).is_equal(2)
	assert_array(_nav).is_empty()


# ---- client Ready ------------------------------------------------------------------------

func test_client_ready_toggles_and_is_disabled_when_missing() -> void:
	var s := _session(false)
	var lib := _library()
	s.song = _song(lib)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "ok")]
	var m := _screen(s, lib)
	var st := m.debug_state()
	assert_str(st["primary_text"]).is_equal("Ready Up")
	assert_bool(st["primary_disabled"]).is_false()
	assert_str(st["gate_text"]).is_equal("Ready Up when you are set.")
	m.press_key_for_test(KEY_ENTER)
	assert_array(s.last("set_ready")).is_equal(["set_ready", true])
	st = m.debug_state()
	assert_str(st["primary_text"]).is_equal("Cancel Ready")
	assert_str(st["gate_text"]).is_equal("Waiting for the host to start.")
	m.press_key_for_test(KEY_ENTER)
	assert_array(s.last("set_ready")).is_equal(["set_ready", false])
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "missing")]
	_changed(s)
	st = m.debug_state()
	assert_bool(st["primary_disabled"]).is_true()
	assert_str(st["gate_text"]).is_equal(LobbyScreen.CLIENT_MISSING)
	assert_bool(st["gate_glyph"]).is_true()
	m.press_key_for_test(KEY_ENTER)
	assert_int(s.count("set_ready")).is_equal(2)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME", false, "changed")]
	_changed(s)
	assert_str(m.debug_state()["gate_text"]).is_equal(LobbyScreen.CLIENT_CHANGED)


# ---- host choices ------------------------------------------------------------------------

func test_song_pick_round_trip_sets_the_song_key() -> void:
	var s := _session()
	var lib := _library()
	var m := _screen(s, lib)
	m.press_key_for_test(KEY_ENTER)  # focus starts on Song
	assert_array(_nav).is_equal([LobbyScreen.SONG_SELECT_SCENE])
	assert_bool(SongSelect.run_pick).is_true()
	assert_bool(SongSelect.pick_online).is_true()
	assert_object(MatchSetup.pending).is_not_null()
	# Song Select stores the pick, then the lobby scene opens again.
	MatchSetup.pending.song_id = "s2"
	MatchSetup.pending.difficulty = "easy"
	m.free()
	var m2 := _screen(s, lib)
	var key: Dictionary = s.last("host_set_song")[1]
	assert_str(key["fp"]).is_equal("fp_s2_easy")
	assert_str(key["diff"]).is_equal("easy")
	assert_str(key["title"]).is_equal("Other Tune")
	assert_str(key["artist"]).is_equal("Artist s2")
	assert_str(key["sig"]).is_equal(VersusSig.of(lib.build_chart(lib.find("s2"), "easy")))
	assert_object(MatchSetup.pending).is_null()
	var st := m2.debug_state()
	assert_str(st["song_value"]).is_equal("Other Tune · Artist s2")
	assert_str(st["log"][st["log"].size() - 1]).is_equal("Host picked Other Tune (EASY). Ready cleared.")


func test_song_pick_back_keeps_the_song() -> void:
	var s := _session()
	var lib := _library()
	s.song = _song(lib)
	var m := _screen(s, lib)
	m.focus_row_for_test("song")
	m.press_key_for_test(KEY_ENTER)
	m.free()  # Back from Song Select: song_id stays empty
	_screen(s, lib)
	assert_int(s.count("host_set_song")).is_equal(0)


func test_flight_tiles_change_and_save() -> void:
	var s := _session()
	var m := _screen(s)
	assert_str(m.debug_state()["flight_line"]).is_equal("Torpedoes fly 2 beats. Safe for internet play.")
	m.focus_row_for_test("flight")
	m.press_key_for_test(KEY_RIGHT)
	assert_array(s.last("host_set_flight")).is_equal(["host_set_flight", 1])
	assert_int(Settings.net_flight_beats).is_equal(1)
	assert_bool(FileAccess.file_exists(SETTINGS_TMP)).is_true()
	assert_str(m.debug_state()["flight_line"]).is_equal(
		"Torpedoes fly 1 beat. For same-room LAN only; warnings get shorter online.")
	m.press_key_for_test(KEY_LEFT)
	assert_array(s.last("host_set_flight")).is_equal(["host_set_flight", 2])


func test_copy_address_writes_clipboard_and_reads_copied() -> void:
	var s := _session()
	var m := _screen(s)
	m.focus_row_for_test("copy")
	m.press_key_for_test(KEY_ENTER)
	assert_array(_clip).is_equal(["100.101.5.7:47474"])
	assert_str(m.debug_state()["copy_text"]).is_equal("Copied")
	m.tick(1.0)
	assert_str(m.debug_state()["copy_text"]).is_equal("Copied")
	m.tick(0.7)
	assert_str(m.debug_state()["copy_text"]).is_equal("Copy Address")


# ---- leaving -----------------------------------------------------------------------------

func test_host_esc_close_lobby_confirm() -> void:
	var s := _session()
	var m := _screen(s)
	m.press_key_for_test(KEY_ESCAPE)
	assert_str(m.debug_state()["dialog"]).is_equal("CLOSE LOBBY")
	assert_str(m.dialog.confirm_button.text).is_equal("Close Lobby")
	assert_bool(m.dialog.safe_button.has_focus()).is_true()
	m.press_key_for_test(KEY_ESCAPE)
	assert_int(s.count("leave")).is_equal(0)
	assert_array(_nav).is_empty()
	m.press_key_for_test(KEY_ESCAPE)
	m.dialog.confirm_button.grab_focus()
	m.press_key_for_test(KEY_ENTER)
	assert_int(s.count("leave")).is_equal(1)
	assert_array(_nav).is_equal([LobbyScreen.ONLINE_SCENE])
	await get_tree().process_frame


func test_client_esc_leave_lobby_confirm() -> void:
	var s := _session(false)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME")]
	var m := _screen(s)
	m.press_key_for_test(KEY_ESCAPE)
	assert_str(m.debug_state()["dialog"]).is_equal("LEAVE LOBBY")
	m.dialog.confirm_button.grab_focus()
	m.press_key_for_test(KEY_ENTER)
	assert_int(s.count("leave")).is_equal(1)
	assert_array(_nav).is_equal(["res://scenes/online_menu.tscn"])
	await get_tree().process_frame


func test_left_lobby_goes_to_play_online() -> void:
	var s := _session(false)
	s.rows = [_row(0, "HOSTY"), _row(1, "ME")]
	_screen(s)
	s.left_lobby.emit("kicked")
	assert_array(_nav).is_equal([LobbyScreen.ONLINE_SCENE])
	assert_int(s.count("leave")).is_equal(0)


func test_offline_session_on_open_goes_to_play_online() -> void:
	var s := _session()
	s.offline = true
	_screen(s)
	assert_array(_nav).is_equal([LobbyScreen.ONLINE_SCENE])


# ---- effects / copy ----------------------------------------------------------------------

func test_effect_contract() -> void:
	var m := _screen(_session())
	assert_bool(m.is_in_group(UiKit.FX_GROUP)).is_true()
	m.apply_effect_settings()
	var fx := m.effect_counts()
	assert_bool(fx["row_slide"]).is_false()  # Reduce motion on in these tests
	assert_bool(fx["log_fade"]).is_true()


func test_every_constant_string_has_glyphs() -> void:
	var body := [LobbyScreen.SUBTITLE_HOST, LobbyScreen.SUBTITLE_CLIENT, LobbyScreen.NO_SONG_HOST,
		LobbyScreen.NO_SONG_CLIENT, LobbyScreen.SONG_SEP, LobbyScreen.HOST_LINE, LobbyScreen.COPY_TEXT,
		LobbyScreen.COPIED_TEXT, LobbyScreen.START_TEXT, LobbyScreen.READY_TEXT, LobbyScreen.CANCEL_READY_TEXT,
		LobbyScreen.PING_FORMAT, LobbyScreen.PING_HOST, LobbyScreen.PING_SYNC, LobbyScreen.CLOSE_BODY,
		LobbyScreen.CLOSE_CONFIRM, LobbyScreen.LEAVE_BODY, LobbyScreen.LEAVE_CONFIRM, LobbyScreen.STAY_TEXT,
		LobbyScreen.KICK_BODY, LobbyScreen.KICK_CONFIRM, LobbyScreen.KICK_SAFE]
	body.append_array(LobbyScreen.ROW_LABELS)
	var label := [LobbyScreen.CAPTION_MATCH, LobbyScreen.CAPTION_INVITE, LobbyScreen.CAPTION_CONNECTION,
		LobbyScreen.INVITE_TS_LINE, LobbyScreen.INVITE_TS_ONLY_LINE, LobbyScreen.INVITE_LAN_LINE,
		LobbyScreen.INVITE_NONE, LobbyScreen.PING_SYNCED, LobbyScreen.PING_SYNCING, LobbyScreen.ROSTER_CAPTION,
		LobbyScreen.HEAD_NAME, LobbyScreen.HEAD_PING, LobbyScreen.HEAD_SONG, LobbyScreen.HEAD_READY,
		LobbyScreen.CHIP_OK, LobbyScreen.CHIP_MISSING, LobbyScreen.CHIP_CHANGED, LobbyScreen.CHIP_CHECKING,
		LobbyScreen.CHIP_NO_SONG, LobbyScreen.READY_WORD, LobbyScreen.WAITING_WORD, LobbyScreen.HOST_WORD,
		LobbyScreen.KICK_KEYS, LobbyScreen.KICK_PAD, LobbyScreen.OPEN_SEAT, LobbyScreen.OPEN_SEAT_LINE,
		LobbyScreen.CAPTION_LOG, LobbyScreen.HINT_HOST_KEYS, LobbyScreen.HINT_HOST_PAD, LobbyScreen.HINT_CLIENT_KEYS,
		LobbyScreen.HINT_CLIENT_PAD, LobbyScreen.GATE_NEED_PLAYERS, LobbyScreen.GATE_NEED_SONG,
		LobbyScreen.GATE_SYNCING, LobbyScreen.GATE_MISSING_ONE, LobbyScreen.GATE_MISSING_MANY,
		LobbyScreen.GATE_CHANGED_ONE, LobbyScreen.GATE_NOT_READY_ONE, LobbyScreen.GATE_NOT_READY_MANY,
		LobbyScreen.GATE_OK, LobbyScreen.CLIENT_NO_SONG, LobbyScreen.CLIENT_MISSING, LobbyScreen.CLIENT_CHANGED,
		LobbyScreen.CLIENT_READY_UP, LobbyScreen.CLIENT_WAITING, LobbyScreen.LOG_HOST_EMPTY,
		LobbyScreen.LOG_CLIENT_EMPTY, LobbyScreen.LOG_JOINED, LobbyScreen.LOG_LEFT, LobbyScreen.LOG_KICKED,
		LobbyScreen.LOG_CHOOSING, LobbyScreen.LOG_PICKED, LobbyScreen.LOG_FLIGHT_MANY, LobbyScreen.LOG_FLIGHT_ONE,
		LobbyScreen.LOG_READY, LobbyScreen.LOG_MISSING, LobbyScreen.LOG_HIGH_LATENCY, LobbyScreen.LOG_LOAD_TIMEOUT,
		LobbyScreen.LOG_START_LATE, LobbyScreen.LOG_LOAD_FAIL, LobbyScreen.LOG_MATCH_ENDED, LobbyScreen.HOST_CHIP]
	label.append_array(LobbyScreen.FLIGHT_TILES)
	label.append_array(LobbyScreen.FLIGHT_LINES.values())
	var heading := [LobbyScreen.TITLE, LobbyScreen.CLOSE_TITLE, LobbyScreen.LEAVE_TITLE, LobbyScreen.KICK_TITLE]
	var bad: Array = []
	for pair: Array in [[Palette.font(), body + label], [Palette.display_font(), heading]]:
		var f: Font = pair[0]
		for t: String in pair[1]:
			for i in t.length():
				if not f.has_char(t.unicode_at(i)):
					bad.append("'%s' in '%s'" % [t[i], t])
	assert_array(bad).override_failure_message("missing glyphs:\n" + "\n".join(bad)).is_empty()


## WR-07 (UI-SPEC 9.4): opening Song Select tells the clients the host is choosing.
func test_open_song_pick_notifies_host_choosing() -> void:
	var s := _session()
	var m := _screen(s, _library())
	m.open_song_pick()
	assert_int(s.count("host_choosing")).is_equal(1)
	assert_array(_nav).is_equal([LobbyScreen.SONG_SELECT_SCENE])
