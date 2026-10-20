extends GdUnitTestSuite
## 04-12: online variant of VersusResultsScreen (04-UI-SPEC 12, 11.3, 15; D-19, NET-04, NET-05).

var _low: bool
var _reduce: bool


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce


## Rows as the host sends them: player names (no "YOU"), seat 2 left mid-song.
func _rows() -> Array:
	return [
		{"seat": 0, "place": 1, "alive": true, "depth": 1200.0, "hull": 88.0, "accuracy": 0.984,
			"eliminated_at": INF, "name": "Nemo", "landed": 4, "reflected": 2},
		{"seat": 1, "place": 2, "alive": true, "depth": 1100.0, "hull": 62.0, "accuracy": 0.9,
			"eliminated_at": INF, "name": "Mako", "landed": 3, "reflected": 1},
		{"seat": 2, "place": 3, "alive": false, "depth": 400.0, "hull": 0.0, "accuracy": 0.81,
			"eliminated_at": 83.4, "name": "Orca", "landed": 1, "reflected": 0, "left": true, "left_t": 83.4},
	]


func _data(is_host: bool, local_seat: int = 0) -> Dictionary:
	return {"rows": _rows(), "local_seat": local_seat, "medals": {0: ["shredder"]}, "title": "Sea Shanty 2",
		"artist": "Jagex", "difficulty": "expert", "seed": 99, "last_standing_seat": -1,
		"online": true, "is_host": is_host, "host_seat": 0, "host_name": "Nemo"}


func _screen(data: Dictionary) -> VersusResultsScreen:
	var holder := Control.new()
	UiLayout.fill_rect(holder)
	add_child(holder)
	auto_free(holder)
	var r := VersusResultsScreen.new()
	holder.add_child(r)
	r.setup(data)
	return r


func _find_text(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n
	for c in n.get_children():
		var f := _find_text(c, text)
		if f != null:
			return f
	return null


func _cancel() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	return ev


func _baseline(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	return l.position.y + f.get_ascent(l.get_theme_font_size("font_size"))


func _chip_texts(r: Node) -> Array:
	var out := []
	for n in r.find_children("Chip*", "", true, false):
		out.append(str(n.get_meta(&"text", "")))
	return out


func _chip(r: Node, text: String) -> Control:
	for n in r.find_children("Chip*", "", true, false):
		if n.get_meta(&"text", "") == text:
			return n
	return null


# ---- rows -------------------------------------------------------------------------------

func test_names_you_row_and_host_glyph() -> void:
	var r := _screen(_data(false, 1))
	assert_str(r.row_texts(0)["name"]).is_equal("NEMO")
	assert_str(r.row_texts(1)["name"]).is_equal("YOU")
	assert_bool(r.row_texts(1)["you"]).is_true()
	assert_str(r.headline_text()).is_equal("NEMO WINS")
	assert_bool(r.row_texts(0)["host"]).is_true()
	assert_bool(r.row_texts(1)["host"]).is_false()
	var glyphs := r.find_children("HostGlyph", "", true, false)
	assert_int(glyphs.size()).is_equal(1)
	var g: Control = glyphs[0]
	assert_str(str(g.get_meta(&"glyph", ""))).is_equal("host")
	assert_float(g.size.x).is_equal(20.0)
	assert_float(g.size.y).is_equal(20.0)
	# After the host's name in the Sub column.
	var name_label: Label = r.row_group(0).find_child("Callsign", true, false)
	assert_float(g.position.x).is_greater_equal(name_label.position.x + name_label.size.x)
	assert_float(g.position.x).is_less(VersusResultsScreen.DEPTH_RIGHT - 200.0)


func test_left_row_status_and_glyph() -> void:
	var r := _screen(_data(true))
	var t := r.row_texts(2)
	assert_str(t["status"]).is_equal("LEFT AT 1:23")
	assert_object(t["status_color"]).is_equal(Palette.TEXT_LO)
	assert_bool(t["left"]).is_true()
	var g: Control = r.row_group(2).find_child("LeftGlyph", true, false)
	assert_object(g).is_not_null()
	assert_str(str(g.get_meta(&"glyph", ""))).is_equal("link_broken")
	assert_float(g.size.x).is_equal(16.0)
	var st: Label = r.row_group(2).find_child("Status", true, false)
	assert_float(g.position.x + g.size.x).is_less_equal(st.position.x)
	# Rows that did not leave keep the P3 statuses and no glyph.
	assert_str(r.row_texts(0)["status"]).is_equal("SURVIVED · HULL 88%")
	assert_object(r.row_group(0).find_child("LeftGlyph", true, false)).is_null()


func test_status_of_left_beats_imploded() -> void:
	var st := VersusResultsScreen.status_of({"alive": false, "eliminated_at": 50.0, "left": true, "left_t": 61.9}, false)
	assert_str(st[0]).is_equal("LEFT AT 1:01")
	assert_object(st[1]).is_equal(Palette.TEXT_LO)


# ---- header -----------------------------------------------------------------------------

func test_online_chip_left_of_not_recorded() -> void:
	var r := _screen(_data(true))
	var on := _chip(r, "ONLINE")
	var nr := _chip(r, "NOT RECORDED")
	assert_object(on).is_not_null()
	assert_object(nr).is_not_null()
	assert_float(on.position.x + on.size.x).is_equal_approx(nr.position.x - 8.0, 0.01)
	assert_float(on.position.y).is_equal(nr.position.y)
	assert_array(r.online_state()["chips"]).contains(["ONLINE", "NOT RECORDED"])


# ---- host -------------------------------------------------------------------------------

func test_host_buttons_focus_and_signals() -> void:
	var r := _screen(_data(true))
	await await_idle_frame()
	var b := r.focus_buttons()
	assert_array(b.map(func(x: Button) -> String: return x.text)).is_equal(["Back to Lobby", "Back to Menu"])
	assert_float(b[0].position.x).is_equal(96.0)
	assert_float(b[0].size.x).is_equal(400.0)
	assert_float(b[1].position.x).is_equal(520.0)
	assert_float(b[0].position.y).is_equal(752.0)
	assert_bool(b[0].has_focus()).is_true()
	assert_object(r.rematch_button).is_null()
	assert_object(r.change_match_button).is_null()
	assert_object(_find_text(r, "Rematch")).is_null()
	assert_array(r.online_state()["buttons"]).is_equal(["Back to Lobby", "Back to Menu"])
	assert_str(r.hint_label.text).is_equal("ENTER SELECT  ·  ESC BACK TO LOBBY")
	assert_object(b[0].get_node(b[0].focus_neighbor_right)).is_same(b[1])
	assert_object(b[1].get_node(b[1].focus_neighbor_right)).is_same(b[0])
	var got: Array[String] = []
	r.back_to_lobby_pressed.connect(func() -> void: got.append("lobby"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r.close_lobby_pressed.connect(func() -> void: got.append("close"))
	b[0].pressed.emit()
	assert_array(got).is_equal(["lobby"])


func test_host_back_to_menu_confirms_close_lobby() -> void:
	var r := _screen(_data(true))
	await await_idle_frame()
	r.skip_entrance()
	var got: Array[String] = []
	r.close_lobby_pressed.connect(func() -> void: got.append("close"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r.menu_button.pressed.emit()
	var d := r.dialog()
	assert_object(d).is_not_null()
	assert_str(d.title_label.text).is_equal("CLOSE LOBBY")
	assert_str(d.body_label.text).is_equal("Close the lobby? Everyone is sent back to Play Online.")
	assert_str(d.confirm_button.text).is_equal("Close Lobby")
	assert_str(d.safe_button.text).is_equal("Stay")
	await await_idle_frame()
	assert_bool(d.safe_button.has_focus()).is_true()
	assert_array(got).is_empty()
	# Stay closes the dialog and returns focus.
	d.safe_button.pressed.emit()
	assert_object(r.dialog()).is_null()
	await await_idle_frame()
	assert_bool(r.menu_button.has_focus()).is_true()
	assert_array(got).is_empty()
	# Confirm emits close_lobby_pressed.
	r.menu_button.pressed.emit()
	r.dialog().confirm_button.pressed.emit()
	assert_array(got).is_equal(["close"])
	assert_object(r.dialog()).is_null()


func test_host_escape_is_back_to_lobby() -> void:
	var r := _screen(_data(true))
	await await_idle_frame()
	r.skip_entrance()
	var got: Array[String] = []
	r.back_to_lobby_pressed.connect(func() -> void: got.append("lobby"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r._unhandled_input(_cancel())
	assert_array(got).is_equal(["lobby"])
	assert_object(r.dialog()).is_null()


# ---- client -----------------------------------------------------------------------------

func test_client_leave_lobby_and_waiting_line() -> void:
	var r := _screen(_data(false, 1))
	await await_idle_frame()
	var b := r.focus_buttons()
	assert_array(b.map(func(x: Button) -> String: return x.text)).is_equal(["Leave Lobby"])
	assert_float(b[0].position.x).is_equal(96.0)
	assert_float(b[0].size.x).is_equal(400.0)
	assert_bool(b[0].has_focus()).is_true()
	assert_str(r.online_state()["waiting_line"]).is_equal("Waiting for NEMO to return to the lobby.")
	var w := _find_text(r, "Waiting for NEMO to return to the lobby.")
	assert_object(w).is_not_null()
	assert_float(w.position.x).is_equal(520.0)
	assert_float(_baseline(w)).is_equal_approx(792.0, 0.5)
	assert_object(w.get_theme_color("font_color")).is_equal(Palette.TEXT_MID)
	assert_int(w.get_theme_font_size("font_size")).is_equal(Palette.SIZE_LABEL)
	assert_str(r.hint_label.text).is_equal("ESC LEAVE LOBBY")
	assert_array(r.online_state()["buttons"]).is_equal(["Leave Lobby"])
	var focusable := r.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c.focus_mode != Control.FOCUS_NONE)
	assert_int(focusable.size()).is_equal(1)


func test_client_accept_confirms_leave_lobby() -> void:
	var r := _screen(_data(false, 1))
	await await_idle_frame()
	r.skip_entrance()
	var got: Array[String] = []
	r.leave_lobby_pressed.connect(func() -> void: got.append("leave"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r.leave_button.pressed.emit()
	var d := r.dialog()
	assert_object(d).is_not_null()
	assert_str(d.title_label.text).is_equal("LEAVE LOBBY")
	assert_str(d.body_label.text).is_equal("Leave this lobby? You can join again with the same address.")
	assert_str(d.confirm_button.text).is_equal("Leave Lobby")
	assert_str(d.safe_button.text).is_equal("Stay")
	await await_idle_frame()
	assert_bool(d.safe_button.has_focus()).is_true()
	d.confirm_button.pressed.emit()
	assert_array(got).is_equal(["leave"])


func test_client_escape_confirms_leave_lobby() -> void:
	var r := _screen(_data(false, 1))
	await await_idle_frame()
	r.skip_entrance()
	var got: Array[String] = []
	r.leave_lobby_pressed.connect(func() -> void: got.append("leave"))
	r._unhandled_input(_cancel())
	assert_object(r.dialog()).is_not_null()
	assert_array(got).is_empty()
	# Esc while the dialog is open does not open a second one or leave.
	r._unhandled_input(_cancel())
	r.dialog().safe_button.pressed.emit()
	assert_object(r.dialog()).is_null()
	assert_array(got).is_empty()


func test_client_lobby_closed() -> void:
	var r := _screen(_data(false, 1))
	await await_idle_frame()
	r.skip_entrance()
	r.leave_button.pressed.emit()  # a confirm open when the lobby closes is dismissed
	r.set_lobby_closed()
	assert_object(r.dialog()).is_null()
	assert_str(r.online_state()["waiting_line"]).is_equal("The host closed the lobby.")
	assert_object(_find_text(r, "The host closed the lobby.")).is_not_null()
	assert_array(r.online_state()["buttons"]).is_equal(["Back to Menu"])
	var got: Array[String] = []
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r.leave_lobby_pressed.connect(func() -> void: got.append("leave"))
	r.leave_button.pressed.emit()
	assert_array(got).is_equal(["menu"])
	assert_object(r.dialog()).is_null()
	r._unhandled_input(_cancel())
	assert_array(got).is_equal(["menu", "menu"])


func test_set_lobby_closed_is_noop_for_host_and_offline() -> void:
	var r := _screen(_data(true))
	r.set_lobby_closed()
	assert_array(r.online_state()["buttons"]).is_equal(["Back to Lobby", "Back to Menu"])
	var off := _data(true)
	off.erase("online")
	var o := _screen(off)
	o.set_lobby_closed()
	assert_array(o.focus_buttons().map(func(x: Button) -> String: return x.text)).is_equal(
		["Rematch", "Change Match", "Back to Menu"])
	assert_bool(o.online_state()["online"]).is_false()


# ---- robustness / copy ------------------------------------------------------------------

func test_missing_and_malformed_keys() -> void:
	var r := _screen({"online": true, "is_host": false, "rows": [
		{"seat": 1, "left": "yes", "left_t": "abc"},
		{},
		{"seat": 3, "left": true},
	], "local_seat": 1})
	assert_int(r.row_count()).is_equal(3)
	assert_bool(r.online_state()["waiting_line"].begins_with("Waiting for ")).is_true()
	assert_str(r.row_texts(2)["status"]).is_equal("LEFT AT 0:00")
	var r2 := _screen({"online": true})
	assert_array(r2.online_state()["buttons"]).is_equal(["Leave Lobby"])


func test_new_strings_have_glyphs() -> void:
	var f := Palette.font()
	var strings: Array[String] = [
		VersusResultsScreen.HINT_HOST_KEYS, VersusResultsScreen.HINT_HOST_PAD,
		VersusResultsScreen.HINT_CLIENT_KEYS, VersusResultsScreen.HINT_CLIENT_PAD,
		VersusResultsScreen.HINT_CLOSED_KEYS, VersusResultsScreen.HINT_CLOSED_PAD,
		VersusResultsScreen.WAITING_TEXT, VersusResultsScreen.LOBBY_CLOSED_TEXT,
		VersusResultsScreen.CLOSE_LOBBY_TITLE, VersusResultsScreen.CLOSE_LOBBY_BODY,
		VersusResultsScreen.LEAVE_LOBBY_TITLE, VersusResultsScreen.LEAVE_LOBBY_BODY,
		"Back to Lobby", "Back to Menu", "Leave Lobby", "Close Lobby", "Stay", "ONLINE", "LEFT AT 0:00",
	]
	var hf := Palette.display_font()
	for t in strings:
		for i in t.length():
			assert_bool(f.has_char(t.unicode_at(i)) and hf.has_char(t.unicode_at(i))).override_failure_message(
				"'%s' in '%s' missing from a font" % [t[i], t]).is_true()
