extends GdUnitTestSuite
## OnlineMenu + ConnectDialog (04-UI-SPEC 8, 8.1, 8.2, 8.3, 15; NET-01, NET-07): region rects,
## focus order with the Paste | Join row and a disabled Join, first-visit name editing, the
## address list (Tailscale first and highlighted, loopback / link-local hidden), port
## validation, Esc while editing, host success / failure, join -> Settings + connect dialog,
## dialog stages and error titles, return messages, has_char for every constant string.
## Uses a FakeSession and redirects Settings.save_path to a temp file.

const D := "user://test_online_menu"
const SETTINGS_TMP := D + "/settings.cfg"
const SCENE := "res://scenes/online_menu.tscn"


## Same method names as NetSession; records calls and emits signals on demand.
class FakeSession:
	extends Node
	signal connect_stage(stage: String)
	signal connect_error(code: String, info: Dictionary)
	signal lobby_changed
	signal left_lobby(code: String)

	var calls: Array = []
	var host_result: int = OK
	var join_result: int = OK
	## When set, join() emits this connect_error synchronously (resolve / lost).
	var join_sync_error: String = ""
	var return_message: String = ""
	var offline := true
	var rows: Array = []

	func host(port: int) -> int:
		calls.append(["host", port])
		if host_result == OK:
			offline = false
		return host_result

	func join(address: String, port: int) -> int:
		calls.append(["join", address, port])
		offline = false
		connect_stage.emit("connecting")
		if join_sync_error != "":
			offline = true
			connect_error.emit(join_sync_error, {})
			return ERR_CANT_RESOLVE
		return join_result

	func leave() -> void:
		calls.append(["leave"])
		offline = true

	func is_offline() -> bool:
		return offline

	func take_return_message() -> String:
		var m := return_message
		return_message = ""
		return m

	func lobby_rows() -> Array:
		return rows

	func count(kind: String) -> int:
		var n := 0
		for c: Array in calls:
			if c[0] == kind:
				n += 1
		return n


var _old_path: String
var _old_name: String
var _old_name_set: bool
var _old_addr: String
var _old_port: int
var _old_reduce: bool
var _nav: Array = []


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))
	_old_path = Settings.save_path
	Settings.save_path = SETTINGS_TMP
	_old_name = Settings.player_name
	_old_name_set = Settings.player_name_set
	_old_addr = Settings.net_last_address
	_old_port = Settings.net_last_port
	_old_reduce = Settings.reduce_motion
	Settings.reduce_motion = true
	Settings.player_name = "NEMO"
	Settings.player_name_set = true
	Settings.net_last_address = ""
	Settings.net_last_port = 47474
	_nav = []


func after_test() -> void:
	Settings.player_name = _old_name
	Settings.player_name_set = _old_name_set
	Settings.net_last_address = _old_addr
	Settings.net_last_port = _old_port
	Settings.reduce_motion = _old_reduce
	Settings.save_path = _old_path
	for p in [SETTINGS_TMP, SETTINGS_TMP + ".tmp", SETTINGS_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _session() -> FakeSession:
	var s := FakeSession.new()
	add_child(s)
	auto_free(s)
	return s


func _screen(session: FakeSession = null, addrs: Array = ["100.101.5.7", "192.168.1.20"],
		clip: String = "") -> OnlineMenu:
	var m: OnlineMenu = (load(SCENE) as PackedScene).instantiate()
	m.session = session if session != null else _session()
	m.navigate = func(p: String) -> void: _nav.append(p)
	m.addrs_fn = func() -> PackedStringArray: return PackedStringArray(addrs)
	m.clipboard_fn = func() -> String: return clip
	add_child(m)
	auto_free(m)
	return m


func _row(st: Dictionary, id: String) -> Dictionary:
	for r: Dictionary in st["rows"]:
		if r["id"] == id:
			return r
	return {}


# ---- layout ------------------------------------------------------------------------------

func test_region_rects_match_ui_spec_8() -> void:
	var m := _screen()
	assert_that(OnlineMenu.LEFT_RECT).is_equal(Rect2(64, 176, 880, 728))
	assert_that(OnlineMenu.RIGHT_RECT).is_equal(Rect2(976, 176, 880, 728))
	var st := m.debug_state()
	assert_that(_row(st, "name")["rect"]).is_equal(Rect2(400, 248, 496, 48))
	assert_that(_row(st, "port")["rect"]).is_equal(Rect2(400, 320, 160, 48))
	assert_that(_row(st, "host")["rect"]).is_equal(Rect2(96, 520, 816, 64))
	assert_that(_row(st, "address")["rect"]).is_equal(Rect2(400, 672, 496, 48))
	assert_that(_row(st, "paste")["rect"]).is_equal(Rect2(96, 744, 200, 64))
	assert_that(_row(st, "join")["rect"]).is_equal(Rect2(312, 744, 600, 64))
	assert_that(OnlineMenu.address_row_rect(0)).is_equal(Rect2(1008, 272, 816, 40))
	assert_that(OnlineMenu.address_row_rect(3)).is_equal(Rect2(1008, 392, 816, 40))
	var f := Palette.font()
	var title := m.find_child("Title", true, false) as Label
	assert_float(title.position.y + Palette.display_font().get_ascent(Palette.SIZE_HEADING)).is_equal_approx(104.0, 0.5)
	assert_str(title.text).is_equal("PLAY ONLINE")
	# VERSION {v} right-aligned to x 1856 at baseline 1040.
	assert_str(m.version_label.text).is_equal("VERSION %s" % NetProtocol.game_version())
	assert_float(m.version_label.position.x + m.version_label.size.x).is_equal_approx(1856.0, 0.5)
	assert_float(m.version_label.position.y + f.get_ascent(Palette.SIZE_LABEL)).is_equal_approx(1040.0, 0.5)
	assert_float(m.status_label.position.y + f.get_ascent(Palette.SIZE_LABEL)).is_equal_approx(1000.0, 0.5)
	var steps := m.find_child("Step1", true, false) as Label
	assert_float(steps.position.x).is_equal(1008.0)
	assert_float(steps.position.y + f.get_ascent(Palette.SIZE_LABEL)).is_equal_approx(568.0, 0.5)
	assert_bool(m.find_child("FocusMarker", true, false) != null).is_true()


func test_buttons_use_spec_icons_and_variants() -> void:
	var m := _screen()
	assert_str(String(m.host_button.get_meta(&"ui_variant"))).is_equal("primary")
	assert_str(String(m.host_button.get_meta(&"ui_icon"))).is_equal("host")
	assert_str(String(m.paste_button.get_meta(&"ui_icon"))).is_equal("copy")
	assert_str(String(m.join_button.get_meta(&"ui_icon"))).is_equal("online")
	assert_str(m.host_button.text).is_equal("Host Match")
	assert_str(m.join_button.text).is_equal("Join Match")


# ---- focus -------------------------------------------------------------------------------

func test_focus_order_wraps_with_paste_join_row() -> void:
	Settings.net_last_address = "100.64.1.2"
	var m := _screen()
	assert_str(m.debug_state()["focus"]).is_equal("join")  # saved address -> Join Match
	m.press_key_for_test(KEY_LEFT)
	assert_str(m.debug_state()["focus"]).is_equal("paste")
	m.press_key_for_test(KEY_RIGHT)
	assert_str(m.debug_state()["focus"]).is_equal("join")
	m.press_key_for_test(KEY_DOWN)
	assert_str(m.debug_state()["focus"]).is_equal("name")
	var seen: Array = []
	for i in 5:
		seen.append(m.debug_state()["focus"])
		m.press_key_for_test(KEY_DOWN)
	assert_array(seen).is_equal(["name", "port", "host", "address", "join"])
	assert_str(m.debug_state()["focus"]).is_equal("name")
	m.press_key_for_test(KEY_UP)
	assert_str(m.debug_state()["focus"]).is_equal("join")
	m.press_key_for_test(KEY_LEFT)
	m.press_key_for_test(KEY_UP)
	assert_str(m.debug_state()["focus"]).is_equal("address")
	assert_bool(m.address_field.has_focus()).is_true()


func test_disabled_join_is_skipped() -> void:
	var m := _screen()
	var st := m.debug_state()
	assert_str(st["focus"]).is_equal("host")  # no saved address -> Host Match
	assert_bool(st["join_enabled"]).is_false()
	assert_bool(_row(st, "join")["disabled"]).is_true()
	m.press_key_for_test(KEY_DOWN)  # address
	m.press_key_for_test(KEY_DOWN)  # button row: Join disabled -> Paste
	assert_str(m.debug_state()["focus"]).is_equal("paste")
	m.press_key_for_test(KEY_RIGHT)
	assert_str(m.debug_state()["focus"]).is_equal("paste")
	m.focus_row_for_test("join")
	assert_str(m.debug_state()["focus"]).is_equal("paste")
	m.press_key_for_test(KEY_UP)
	m.press_key_for_test(KEY_UP)
	m.press_key_for_test(KEY_UP)
	m.press_key_for_test(KEY_UP)
	m.press_key_for_test(KEY_UP)  # wraps from Name to the button row -> Paste
	assert_str(m.debug_state()["focus"]).is_equal("paste")


func test_row_hint_follows_focus() -> void:
	var m := _screen()
	m.focus_row_for_test("name")
	assert_str(m.debug_state()["row_hint"]).is_equal(OnlineMenu.HINT_NAME)
	m.focus_row_for_test("port")
	assert_str(m.debug_state()["row_hint"]).is_equal(OnlineMenu.HINT_PORT)
	m.focus_row_for_test("host")
	assert_str(m.debug_state()["row_hint"]).is_equal("")


func test_first_visit_edits_name_with_prompt_and_commit_saves() -> void:
	Settings.player_name_set = false
	Settings.player_name = "DIVER"
	var m := _screen()
	var st := m.debug_state()
	assert_str(st["focus"]).is_equal("name")
	assert_bool(m.name_field.is_editing()).is_true()
	assert_bool(m.name_field.has_focus()).is_true()
	assert_str(st["status"]).is_equal("Pick a name your friends will see, then press Enter.")
	assert_str(st["status_role"]).is_equal("info")
	assert_str(st["hint"]).is_equal(OnlineMenu.HINT_KEYS_EDIT)
	m.name_field.set_value("")
	m.name_field.begin_editing()
	m.name_field.insert_text("orca  7")
	m.press_key_for_test(KEY_ENTER)
	assert_bool(m.name_field.is_editing()).is_false()
	assert_str(Settings.player_name).is_equal("ORCA 7")
	assert_bool(Settings.player_name_set).is_true()
	assert_str(m.debug_state()["status"]).is_equal("")
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SETTINGS_TMP)).is_equal(OK)
	assert_str(str(cfg.get_value("net", "player_name"))).is_equal("ORCA 7")
	assert_bool(bool(cfg.get_value("net", "player_name_set"))).is_true()


func test_not_first_visit_does_not_edit() -> void:
	var m := _screen()
	assert_bool(m.name_field.is_editing()).is_false()
	assert_str(m.debug_state()["status"]).is_equal("")


# ---- right panel -------------------------------------------------------------------------

func test_tailscale_first_and_highlighted_loopback_link_local_hidden() -> void:
	var m := _screen(null, ["127.0.0.1", "192.168.1.20", "169.254.3.4", "100.101.5.7", "::1", "fe80::1"])
	var a: Array = m.debug_state()["addresses"]
	assert_int(a.size()).is_equal(2)
	assert_str(a[0]["ip"]).is_equal("100.101.5.7")
	assert_str(a[0]["chip"]).is_equal("TAILSCALE")
	assert_bool(a[0]["highlight"]).is_true()
	assert_str(a[1]["ip"]).is_equal("192.168.1.20")
	assert_str(a[1]["chip"]).is_equal("LAN")
	assert_bool(a[1]["highlight"]).is_false()
	assert_str(m.debug_state()["address_line"]).is_equal("Give the Tailscale address to friends.")


func test_address_line_states_and_refresh_every_5_s() -> void:
	var list := ["192.168.1.20"]
	var m := _screen(null, [])
	m.addrs_fn = func() -> PackedStringArray: return PackedStringArray(list)
	m.refresh_addresses()
	assert_str(m.debug_state()["address_line"]).is_equal(
		"No Tailscale address. Friends outside your home network need Tailscale.")
	list.clear()
	m.refresh_addresses()
	assert_str(m.debug_state()["address_line"]).is_equal("No network address found. Check that this PC is online.")
	assert_str(m.address_line_role()).is_equal("none")
	# Tailscale connects after launch: the list picks it up on the next 5 s refresh.
	m.addrs_fn = func() -> PackedStringArray: return PackedStringArray(["100.70.0.9"])
	m.tick(4.9)
	assert_int((m.debug_state()["addresses"] as Array).size()).is_equal(0)
	m.tick(0.2)
	assert_str(m.debug_state()["addresses"][0]["ip"]).is_equal("100.70.0.9")


func test_steps_read_the_port_field() -> void:
	var m := _screen()
	var steps: Array = m.debug_state()["steps"]
	assert_int(steps.size()).is_equal(4)
	assert_str(steps[2]).is_equal("3. Friends type that address, keep port 47474, and pick Join Match.")
	m.port_field.set_value("50000")
	m.port_field.committed.emit("50000")
	assert_str(m.debug_state()["steps"][2]).is_equal("3. Friends type that address, keep port 50000, and pick Join Match.")


# ---- fields ------------------------------------------------------------------------------

func test_port_out_of_range_reverts_with_status() -> void:
	var m := _screen()
	m.focus_row_for_test("port")
	m.press_key_for_test(KEY_ENTER)
	assert_bool(m.port_field.is_editing()).is_true()
	m.port_field.set_value("")
	m.port_field.begin_editing()
	m.port_field.insert_text("80")
	m.press_key_for_test(KEY_ENTER)
	assert_str(m.port_field.value).is_equal("")  # reverted to the value before editing
	var st := m.debug_state()
	assert_str(st["status"]).is_equal("Port must be between 1024 and 65535.")
	assert_str(st["status_role"]).is_equal("error")
	# A good value commits.
	m.port_field.begin_editing()
	m.port_field.insert_text("40000")
	m.press_key_for_test(KEY_ENTER)
	assert_str(m.port_field.value).is_equal("40000")
	assert_int(m.current_port()).is_equal(40000)


func test_address_field_charset_and_length() -> void:
	var m := _screen()
	m.address_field.begin_editing()
	m.address_field.insert_text("100.64.1.2; rm -rf")
	assert_str(m.address_field.value).is_equal("100.64.1.2rm-rf")
	m.address_field.set_value("x".repeat(100))
	assert_int(m.address_field.value.length()).is_equal(64)


func test_esc_while_editing_does_not_leave() -> void:
	var m := _screen()
	m.focus_row_for_test("address")
	m.press_key_for_test(KEY_ENTER)
	assert_bool(m.address_field.is_editing()).is_true()
	m.press_key_for_test(KEY_ESCAPE)
	assert_bool(m.address_field.is_editing()).is_false()
	assert_array(_nav).is_empty()
	# A real Esc key while editing is consumed by the field.
	m.address_field.begin_editing()
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	assert_bool(m.address_field.is_editing()).is_false()
	assert_array(_nav).is_empty()
	# Esc with nothing editing goes back to the main menu.
	m.press_key_for_test(KEY_ESCAPE)
	assert_array(_nav).is_equal([OnlineMenu.MENU_SCENE])


func test_paste_fills_address_and_empty_clipboard_errors() -> void:
	var m := _screen(null, [], "  \n ")
	m.paste_address()
	assert_str(m.debug_state()["status"]).is_equal("Clipboard has no address to paste.")
	assert_str(m.address_field.value).is_equal("")
	m.clipboard_fn = func() -> String: return "%%%"
	m.paste_address()
	assert_str(m.debug_state()["status"]).is_equal("Clipboard has no address to paste.")
	m.clipboard_fn = func() -> String: return " 100.101.5.7:47480\n"
	m.focus_row_for_test("paste")
	m.press_key_for_test(KEY_ENTER)
	assert_str(m.address_field.value).is_equal("100.101.5.7")
	assert_str(m.port_field.value).is_equal("47480")
	assert_str(m.debug_state()["status"]).is_equal("")
	assert_bool(m.debug_state()["join_enabled"]).is_true()
	assert_str(m.debug_state()["focus"]).is_equal("join")


func test_split_host_port() -> void:
	assert_array(OnlineMenu.split_host_port("100.1.2.3:5000", 47474)).is_equal(["100.1.2.3", 5000])
	assert_array(OnlineMenu.split_host_port("100.1.2.3", 47474)).is_equal(["100.1.2.3", 47474])
	assert_array(OnlineMenu.split_host_port("[fd7a::1]:5000", 47474)).is_equal(["fd7a::1", 5000])
	assert_array(OnlineMenu.split_host_port("fd7a::1", 47474)).is_equal(["fd7a::1", 47474])
	assert_array(OnlineMenu.split_host_port("box.lan:80", 47474)).is_equal(["box.lan:80", 47474])


# ---- host --------------------------------------------------------------------------------

func test_host_success_navigates_to_lobby() -> void:
	var s := _session()
	var m := _screen(s)
	m.port_field.set_value("47500")
	m.focus_row_for_test("host")
	m.press_key_for_test(KEY_ENTER)
	assert_array(s.calls).is_equal([["host", 47500]])
	assert_array(_nav).is_equal([OnlineMenu.LOBBY_SCENE])
	assert_str(OnlineMenu.LOBBY_SCENE).is_equal("res://scenes/lobby.tscn")
	assert_int(Settings.net_last_port).is_equal(47500)
	m.host_match()  # double press guard
	assert_int(s.count("host")).is_equal(1)


func test_host_failure_shows_status_copy() -> void:
	var s := _session()
	s.host_result = ERR_CANT_CREATE
	var m := _screen(s)
	m.host_match()
	assert_array(_nav).is_empty()
	var st := m.debug_state()
	assert_str(st["status"]).is_equal(
		"Could not open port 47474. Another program or another UNDERTOW is using it. Pick another port.")
	assert_str(st["status_role"]).is_equal("error")
	assert_str(st["focus"]).is_equal("host")
	s.host_result = ERR_UNAVAILABLE
	m.host_match()
	assert_str(m.debug_state()["status"]).is_equal(
		"Could not start hosting (error %d). Check your network and try again." % ERR_UNAVAILABLE)


# ---- join + dialog -----------------------------------------------------------------------

func _join(m: OnlineMenu, addr: String = "100.101.5.7") -> ConnectDialog:
	m.address_field.set_value(addr)
	m.address_field.committed.emit(addr)
	m.focus_row_for_test("join")
	m.press_key_for_test(KEY_ENTER)
	return m.dialog


func test_join_saves_settings_and_opens_dialog_stages() -> void:
	var s := _session()
	s.rows = [{"seat": 0, "name": "ORCA", "host": true}]
	var m := _screen(s)
	m.port_field.set_value("47480")
	var d := _join(m)
	assert_object(d).is_not_null()
	assert_array(s.calls).is_equal([["join", "100.101.5.7", 47480]])
	assert_str(Settings.net_last_address).is_equal("100.101.5.7")
	assert_int(Settings.net_last_port).is_equal(47480)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SETTINGS_TMP)).is_equal(OK)
	assert_str(str(cfg.get_value("net", "net_last_address"))).is_equal("100.101.5.7")
	var st := d.debug_state()
	assert_str(st["title"]).is_equal("CONNECTING")
	assert_str(st["body"]).is_equal("Calling 100.101.5.7:47480. This can take a few seconds.")
	assert_array(st["buttons"]).is_equal(["Cancel"])
	assert_str(st["focus"]).is_equal("Cancel")
	assert_bool(st["ring_visible"]).is_true()
	assert_that(ConnectDialog.PANEL_RECT).is_equal(ConfirmDialog.PANEL_RECT)
	d.tick(2.4)
	assert_str(d.debug_state()["elapsed"]).is_equal("2 S")
	s.connect_stage.emit("auth")
	assert_str(d.debug_state()["title"]).is_equal("CHECKING VERSION")
	assert_str(d.debug_state()["body"]).is_equal("Connected. Checking that you both run the same game build.")
	s.connect_stage.emit("sync")
	assert_str(d.debug_state()["title"]).is_equal("SYNCING CLOCKS")
	assert_str(d.debug_state()["body"]).is_equal("Lining up your clock with ORCA's for a synced start.")
	assert_array(_nav).is_empty()
	s.connect_stage.emit("lobby")
	assert_array(_nav).is_equal([OnlineMenu.LOBBY_SCENE])


func test_each_error_code_shows_its_title_and_try_again_rejoins() -> void:
	var s := _session()
	var m := _screen(s)
	var d := _join(m)
	var expected := {
		"timeout": "NO ANSWER",
		"resolve": "ADDRESS NOT FOUND",
		"version": "DIFFERENT VERSIONS",
		"full": "LOBBY FULL",
		"in_match": "MATCH IN PROGRESS",
		"lost": "CONNECTION LOST",
		"bad_name": "CONNECTION LOST",
	}
	var joins := 1
	for code: String in expected:
		s.connect_error.emit(code, {"host_version": "0.6.9"} if code == "version" else {})
		var st := d.debug_state()
		assert_str(st["mode"]).is_equal("error")
		assert_str(st["title"]).override_failure_message(code).is_equal(expected[code])
		assert_array(st["buttons"]).is_equal(["Try Again", "Back"])
		assert_str(st["focus"]).is_equal("Try Again")
		assert_bool(st["ring_visible"]).is_false()
		if code == "version":
			assert_str(st["body"]).is_equal("The host runs UNDERTOW 0.6.9 and you run %s. Everyone needs the same build."
				% NetProtocol.game_version())
		if code == "resolve":
			assert_str(st["body"]).starts_with("Could not find 100.101.5.7.")
		d.try_button.pressed.emit()
		joins += 1
		assert_int(s.count("join")).is_equal(joins)
		assert_str(d.debug_state()["title"]).is_equal("CONNECTING")


func test_sync_resolve_error_and_back_returns_focus_to_join() -> void:
	var s := _session()
	s.join_sync_error = "resolve"
	var m := _screen(s)
	var d := _join(m, "nohost.example")
	assert_str(d.debug_state()["title"]).is_equal("ADDRESS NOT FOUND")
	assert_str(d.debug_state()["body"]).is_equal(
		"Could not find nohost.example. Check the spelling, or use the host's 100.x.y.z Tailscale address.")
	m.press_key_for_test(KEY_ESCAPE)  # Esc = Back on an error
	assert_object(m.dialog).is_null()
	assert_str(m.debug_state()["focus"]).is_equal("join")
	assert_array(_nav).is_empty()


func test_cancel_disconnects_and_closes() -> void:
	var s := _session()
	var m := _screen(s)
	var d := _join(m)
	d.cancel_button.pressed.emit()
	assert_int(s.count("leave")).is_equal(1)
	assert_object(m.dialog).is_null()
	assert_str(m.debug_state()["focus"]).is_equal("join")
	# A late stage event after Cancel does nothing.
	s.connect_stage.emit("lobby")
	assert_array(_nav).is_empty()


func test_ipv6_shown_in_brackets() -> void:
	var s := _session()
	var m := _screen(s)
	var d := _join(m, "fd7a:115c::1")
	assert_str(d.debug_state()["body"]).is_equal("Calling [fd7a:115c::1]:47474. This can take a few seconds.")
	s.connect_error.emit("resolve", {})
	assert_str(d.debug_state()["body"]).starts_with("Could not find [fd7a:115c::1].")


func test_ping_ring_animates_and_is_static_under_reduce_motion() -> void:
	var s := _session()
	var m := _screen(s)
	var d := _join(m)
	Settings.reduce_motion = false
	d.tick(0.5)
	var r := d.ring_state()
	assert_float(r[0]).is_greater(8.0)
	assert_float(r[0]).is_less(28.0)
	assert_float(r[1]).is_less(1.0)
	assert_bool(d.effect_counts()["ping_ring"]).is_true()
	Settings.reduce_motion = true
	assert_array(d.ring_state()).is_equal([20.0, 0.6])
	assert_bool(d.effect_counts()["ping_ring"]).is_false()
	assert_bool(d.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_bool(m.is_in_group(UiKit.FX_GROUP)).is_true()


# ---- return messages ---------------------------------------------------------------------

func test_return_message_shown_on_open() -> void:
	for pair: Array in [["kicked", "The host removed you from the lobby."], ["closed", "The host closed the lobby."],
			["lost", "Lost the connection to the host's lobby."]]:
		Settings.net_last_address = "100.101.5.7"
		var s := _session()
		s.return_message = pair[0]
		var m := _screen(s)
		var st := m.debug_state()
		assert_str(st["status"]).is_equal(pair[1])
		assert_str(st["focus"]).is_equal("join")
		assert_str(s.return_message).is_equal("")  # consumed


# ---- fonts -------------------------------------------------------------------------------

func test_every_constant_string_has_its_glyphs() -> void:
	var label := Palette.font()
	var heading := Palette.display_font()
	var body: Array[String] = [OnlineMenu.SUBTITLE, OnlineMenu.CAPTION_SUB, OnlineMenu.CAPTION_HOST,
		OnlineMenu.CAPTION_JOIN, OnlineMenu.HINT_NAME, OnlineMenu.HINT_PORT, OnlineMenu.HOST_LINE, OnlineMenu.JOIN_LINE,
		OnlineMenu.HOST_TEXT, OnlineMenu.PASTE_TEXT, OnlineMenu.JOIN_TEXT, OnlineMenu.VERSION_FORMAT,
		OnlineMenu.FIRST_VISIT_PROMPT, OnlineMenu.CAPTION_CONNECT, OnlineMenu.CAPTION_ADDRESSES,
		OnlineMenu.CHIP_TAILSCALE, OnlineMenu.CHIP_LAN, OnlineMenu.ADDR_TAILSCALE, OnlineMenu.ADDR_NO_TAILSCALE,
		OnlineMenu.ADDR_NONE, OnlineMenu.CAPTION_HOW, OnlineMenu.GUIDE_LINE, OnlineMenu.FIREWALL_LINE,
		OnlineMenu.HINT_KEYS, OnlineMenu.HINT_PAD, OnlineMenu.HINT_KEYS_EDIT, OnlineMenu.HINT_PAD_EDIT,
		OnlineMenu.ERR_PORT_BUSY, OnlineMenu.ERR_HOST, OnlineMenu.ERR_PORT_RANGE, OnlineMenu.ERR_CLIPBOARD,
		ConnectDialog.ELAPSED_FORMAT, ConnectDialog.CANCEL_TEXT, ConnectDialog.TRY_AGAIN_TEXT,
		ConnectDialog.BACK_TEXT, ConnectDialog.HOST_FALLBACK]
	body.append_array(OnlineMenu.STEPS)
	for k in OnlineMenu.ROW_LABELS:
		body.append(str(OnlineMenu.ROW_LABELS[k]))
	for k in OnlineMenu.RETURN_MESSAGES:
		body.append(str(OnlineMenu.RETURN_MESSAGES[k]))
	for k in ConnectDialog.STAGE_BODIES:
		body.append(str(ConnectDialog.STAGE_BODIES[k]))
	for k in ConnectDialog.ERROR_BODIES:
		body.append(str(ConnectDialog.ERROR_BODIES[k]))
	var heads: Array[String] = [OnlineMenu.TITLE]
	for k in ConnectDialog.STAGE_TITLES:
		heads.append(str(ConnectDialog.STAGE_TITLES[k]))
	for k in ConnectDialog.ERROR_TITLES:
		heads.append(str(ConnectDialog.ERROR_TITLES[k]))
	var bad: Array[String] = []
	for pair: Array in [[label, body], [heading, heads]]:
		var f: Font = pair[0]
		for t: String in pair[1]:
			for i in t.length():
				if not f.has_char(t.unicode_at(i)):
					bad.append("'%s' in '%s'" % [t[i], t])
	assert_array(bad).override_failure_message("missing glyphs:\n" + "\n".join(bad)).is_empty()


func test_no_full_rect_preset_in_sources() -> void:
	for p in ["res://src/ui/online/online_menu.gd", "res://src/ui/online/connect_dialog.gd"]:
		var src := FileAccess.get_file_as_string(p)
		assert_bool(src.contains("PRESET_" + "FULL_RECT")).override_failure_message(p).is_false()
