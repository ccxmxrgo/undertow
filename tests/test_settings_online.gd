extends GdUnitTestSuite
## Settings > ONLINE (04-16, UI-SPEC 13): Player name and Online port SonarTextFields between AUDIO
## and LIBRARY, U-9.3 positions, saving through Settings (temp save_path), port range revert with
## the error line, Esc while editing staying in Settings, focus order and glyph coverage.

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const SettingsScript := preload("res://src/autoload/settings.gd")
const TEST_PATH := "user://test_settings_online.cfg"

var _old_path: String
var _old_name: String
var _old_name_set: bool
var _old_port: int


func before_test() -> void:
	_old_path = Settings.save_path
	_old_name = Settings.player_name
	_old_name_set = Settings.player_name_set
	_old_port = Settings.net_last_port
	Settings.save_path = TEST_PATH
	Settings.player_name = Settings.DEFAULT_PLAYER_NAME
	Settings.player_name_set = false
	Settings.net_last_port = Settings.DEFAULT_NET_PORT
	_clean()


func after_test() -> void:
	Settings.save_path = _old_path
	Settings.player_name = _old_name
	Settings.player_name_set = _old_name_set
	Settings.net_last_port = _old_port
	_clean()


func _clean() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _screen() -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.library = null
	s.navigate = func(_p: String) -> void: pass
	add_child(s)
	auto_free(s)
	return s


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _section_names(s: SettingsScreen) -> Array[String]:
	var out: Array[String] = []
	for p in s.section_panels:
		out.append(String(p.name))
	return out


func test_online_section_sits_between_audio_and_library() -> void:
	var s := _screen()
	var names := _section_names(s)
	var i := names.find("OnlineSection")
	assert_int(i).is_greater(0)
	assert_str(names[i - 1]).is_equal("AudioSection")
	assert_str(names[i + 1]).is_equal("LibrarySection")
	var titles := s.row_titles()
	var n := titles.find("Player name")
	assert_int(n).is_greater(0)
	assert_str(titles[n - 1]).is_equal("SFX")
	assert_str(titles[n + 1]).is_equal("Online port")
	assert_str(titles[n + 2]).is_equal("Songs folder")


func test_fields_are_sonar_text_fields_at_spec_positions() -> void:
	var s := _screen()
	await _frames(2)
	assert_object(s.name_field).is_instanceof(SonarTextField)
	assert_object(s.port_field).is_instanceof(SonarTextField)
	assert_str(s.name_field.config).is_equal("name")
	assert_str(s.port_field.config).is_equal("port")
	var panel_x := s.section_panels[0].global_position.x
	for pair: Array in [[s.name_field, 440.0, 952.0], [s.port_field, 440.0, 600.0]]:
		var f: SonarTextField = pair[0]
		var r := f.get_global_rect()
		var x0 := r.position.x - panel_x + SettingsScreen.PANEL_X0
		assert_float(x0).is_equal_approx(pair[1], 0.5)
		assert_float(x0 + r.size.x).is_equal_approx(pair[2], 0.5)
		assert_float(r.size.y).is_equal_approx(SonarTextField.HEIGHT, 0.5)
	assert_str(s.name_field.value).is_equal("DIVER")
	assert_str(s.port_field.value).is_equal("47474")


func test_committing_a_name_saves_upper_case_and_marks_it_set() -> void:
	var s := _screen()
	await _frames(1)
	_clear_begin(s.name_field)
	s.name_field.insert_text("nemo_7")
	s.name_field.commit()
	assert_str(Settings.player_name).is_equal("NEMO_7")
	assert_bool(Settings.player_name_set).is_true()
	assert_str(s.name_field.value).is_equal("NEMO_7")
	var t: Node = auto_free(SettingsScript.new())
	t.load_from(TEST_PATH)
	assert_str(t.player_name).is_equal("NEMO_7")
	assert_bool(t.player_name_set).is_true()


func test_committing_a_port_saves_it() -> void:
	var s := _screen()
	await _frames(1)
	_clear_begin(s.port_field)
	s.port_field.insert_text("50000")
	s.port_field.commit()
	assert_int(Settings.net_last_port).is_equal(50000)
	var t: Node = auto_free(SettingsScript.new())
	t.load_from(TEST_PATH)
	assert_int(t.net_last_port).is_equal(50000)
	assert_str(s.online_message_text()).is_equal("")


func test_invalid_port_reverts_and_shows_the_error() -> void:
	var s := _screen()
	await _frames(1)
	_clear_begin(s.port_field)
	s.port_field.insert_text("80")
	s.port_field.commit()
	assert_int(Settings.net_last_port).is_equal(47474)
	assert_str(s.port_field.value).is_equal("47474")
	assert_bool(s.port_field.is_editing()).is_false()
	assert_str(s.online_message_text()).is_equal("! " + SettingsScreen.ERR_PORT_RANGE)
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()
	# Editing again clears the line.
	s.port_field.begin_editing()
	assert_str(s.online_message_text()).is_equal("")


func test_esc_while_editing_reverts_and_stays_in_settings() -> void:
	var s := _screen()
	var went: Array[String] = []
	s.navigate = func(p: String) -> void: went.append(p)
	var closed_count := [0]
	s.closed.connect(func() -> void: closed_count[0] += 1)
	await _frames(1)
	s.name_field.begin_editing()
	s.name_field.insert_text("X")
	assert_bool(s.online_editing()).is_true()
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	await _frames(1)
	assert_bool(s.name_field.is_editing()).is_false()
	assert_str(s.name_field.value).is_equal("DIVER")
	assert_array(went).is_empty()
	assert_int(closed_count[0]).is_equal(0)
	assert_bool(Settings.player_name_set).is_false()
	# The screen-level handler also refuses while a field edits, whatever routed the event.
	s.port_field.begin_editing()
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	s._unhandled_input(ev)
	assert_array(went).is_empty()
	s.port_field.cancel()
	# Not editing: Esc leaves as before.
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ESCAPE, false))
	await _frames(1)
	assert_array(went).contains([SettingsScreen.MENU_SCENE])


func test_down_from_last_audio_row_focuses_player_name_then_port_then_library() -> void:
	var s := _screen()
	await _frames(2)
	s.sfx_slider.grab_focus()
	await _frames(1)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(s.name_field)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(s.port_field)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(s.open_songs_button)
	await Pad.tap(get_viewport(), JOY_BUTTON_DPAD_UP)
	await _frames(1)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(s.port_field)


func test_settings_changed_refreshes_idle_fields() -> void:
	var s := _screen()
	await _frames(1)
	Settings.player_name = "ORCA"
	Settings.settings_changed.emit()
	assert_str(s.name_field.value).is_equal("ORCA")


func test_hint_strings_have_their_glyphs() -> void:
	var s := _screen()
	assert_str(s.hint_for("Player name")).is_equal(SettingsScreen.HINT_PLAYER_NAME)
	assert_str(s.hint_for("Online port")).is_equal(SettingsScreen.HINT_ONLINE_PORT)
	var f := Palette.font()
	var bad: Array[String] = []
	for t: String in [SettingsScreen.HINT_PLAYER_NAME, SettingsScreen.HINT_ONLINE_PORT,
			"! " + SettingsScreen.ERR_PORT_RANGE, "Player name", "Online port", "ONLINE"]:
		for i in t.length():
			if not f.has_char(t.unicode_at(i)):
				bad.append("'%s' in '%s'" % [t[i], t])
	var hf := Palette.display_font()
	for i in "ONLINE".length():
		if not hf.has_char("ONLINE".unicode_at(i)):
			bad.append("heading '%s'" % "ONLINE"[i])
	assert_array(bad).override_failure_message("missing glyphs:\n" + "\n".join(bad)).is_empty()


## Starts editing and empties the edit buffer (as if the player deleted every character), so a
## cancel / invalid commit reverts to the value from before editing.
func _clear_begin(f: SonarTextField) -> void:
	f.begin_editing()
	f.value = ""
	f.caret = 0
