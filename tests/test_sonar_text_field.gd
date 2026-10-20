extends GdUnitTestSuite
## 04-04 (04-UI-SPEC 4.1, NET-01/02): SonarTextField, driven with synthetic key and joypad
## events through the viewport (so accept_event / propagation is real): charset rejection per
## config, upper-casing, max length, port range revert, Esc revert without propagation,
## gamepad cycling order, paste filtering, Reduce motion caret.

## Records ui_cancel / ui_accept that reach _unhandled_input (the screen level).
const PROBE_SRC := """extends Node
var cancels := 0
var accepts := 0
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		cancels += 1
	elif event.is_action_pressed(&"ui_accept"):
		accepts += 1
"""

var _low := false
var _reduce := false


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false
	Settings.settings_changed.emit()


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce
	Settings.settings_changed.emit()


# ---- helpers ----------------------------------------------------------------------------

func _field(config: String, value: String = "") -> SonarTextField:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1200, 200)
	add_child(host)
	var f := SonarTextField.new()
	f.setup(config, value)
	f.position = Vector2(40, 40)
	f.size = Vector2(512, 48)
	host.add_child(f)
	f.grab_focus()
	return f


func _probe() -> Node:
	var s := GDScript.new()
	s.source_code = PROBE_SRC
	s.reload()
	var n: Node = auto_free(Node.new())
	n.set_script(s)
	add_child(n)
	return n


func _key(keycode: Key, unicode: int = 0, ctrl: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.unicode = unicode
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)


func _type(s: String) -> void:
	for i in s.length():
		var c := s.unicode_at(i)
		var kc: Key = KEY_SPACE if c == 32 else (OS.find_keycode_from_string(s[i].to_upper()) as Key)
		_key(kc, c)


func _joy(button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	get_viewport().push_input(up)


# ---- configs ----------------------------------------------------------------------------

func test_configs_and_defaults() -> void:
	var n := _field("name", "diver one")
	assert_str(n.value).is_equal("DIVER ONE")
	assert_int(n.max_length()).is_equal(12)
	assert_str(n.placeholder).is_equal("DIVER")
	var p := _field("port", "47474")
	assert_int(p.max_length()).is_equal(5)
	assert_str(p.placeholder).is_equal("47474")
	var a := _field("address", "100.64.0.1")
	assert_int(a.max_length()).is_equal(64)
	assert_str(a.placeholder).is_equal("100.x.y.z or host name")
	var d := a.debug_state()
	for k: String in ["config", "value", "editing", "caret", "rejected_count", "edge_color_role"]:
		assert_bool(d.has(k)).override_failure_message("debug_state missing " + k).is_true()
	assert_str(d.config).is_equal("address")
	assert_bool(d.editing).is_false()
	# Setup sanitises: charset filter and max length, no reject feedback.
	var bad := _field("name", "ab!c?defghijklmnop")
	assert_str(bad.value).is_equal("ABCDEFGHIJKL")
	assert_int(bad.rejected_count).is_equal(0)


func test_unknown_config_falls_back_to_name() -> void:
	var f := _field("bogus", "x")
	assert_str(f.config).is_equal("name")


func test_accept_starts_editing_caret_at_end_and_enter_commits() -> void:
	var f := _field("name", "MAKO")
	var probe := _probe()
	var changes: Array = []
	var commits: Array = []
	f.editing_changed.connect(func(on: bool) -> void: changes.append(on))
	f.committed.connect(func(v: String) -> void: commits.append(v))
	assert_str(f.debug_state().edge_color_role).is_equal("focused")
	_key(KEY_ENTER)
	assert_bool(f.is_editing()).is_true()
	assert_int(f.caret).is_equal(4)
	assert_str(f.debug_state().edge_color_role).is_equal("editing")
	assert_str(f.last_blip).is_equal("confirm")
	_type(" ray")
	assert_str(f.value).is_equal("MAKO RAY")
	_key(KEY_ENTER)
	assert_bool(f.is_editing()).is_false()
	assert_array(commits).is_equal(["MAKO RAY"])
	assert_array(changes).is_equal([true, false])
	assert_int(probe.accepts).override_failure_message("Enter reached the screen").is_equal(0)


func test_name_upper_cases_and_rejects_outside_charset() -> void:
	var f := _field("name", "")
	f.begin_editing()
	_type("ab_1-")
	assert_str(f.value).is_equal("AB_1-")
	assert_int(f.rejected_count).is_equal(0)
	_type("!")
	assert_str(f.value).is_equal("AB_1-")
	assert_int(f.rejected_count).is_equal(1)
	assert_str(f.last_blip).is_equal("error")
	assert_str(f.debug_state().edge_color_role).is_equal("rejected")
	assert_that(f.edge_color()).is_equal(Palette.WARNING_RED)
	# The red flash lasts 200 ms.
	f.tick(0.15)
	assert_str(f.debug_state().edge_color_role).is_equal("rejected")
	f.tick(0.1)
	assert_str(f.debug_state().edge_color_role).is_equal("editing")
	assert_that(f.edge_color()).is_equal(Palette.SONAR_PALE)


func test_name_max_length_12() -> void:
	var f := _field("name", "")
	f.begin_editing()
	_type("abcdefghijklmn")
	assert_str(f.value).is_equal("ABCDEFGHIJKL")
	assert_int(f.rejected_count).is_equal(2)


func test_name_commit_trims_collapses_and_empty_reverts() -> void:
	var f := _field("name", "MAKO")
	f.begin_editing()
	for i in 4:
		_key(KEY_BACKSPACE)
	_type("  a   b ")
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("A B")
	f.begin_editing()
	for i in 3:
		_key(KEY_BACKSPACE)
	_type("   ")
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("A B")


func test_port_digits_only_and_range_revert() -> void:
	var f := _field("port", "47474")
	var invalid: Array = []
	f.invalid.connect(func(code: String) -> void: invalid.append(code))
	f.begin_editing()
	_type("x")
	assert_int(f.rejected_count).is_equal(1)
	assert_str(f.value).is_equal("47474")
	_type("1")
	assert_str(f.value).override_failure_message("max length 5").is_equal("47474")
	for i in 5:
		_key(KEY_BACKSPACE)
	_type("80")
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("47474")
	assert_array(invalid).is_equal(["port_range"])
	f.begin_editing()
	for i in 5:
		_key(KEY_BACKSPACE)
	_type("65535")
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("65535")
	f.begin_editing()
	for i in 5:
		_key(KEY_BACKSPACE)
	_type("1024")
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("1024")
	assert_array(invalid).is_equal(["port_range"])


func test_address_keeps_case_and_charset() -> void:
	var f := _field("address", "")
	f.begin_editing()
	_type("Host.lan:[1]")
	assert_str(f.value).is_equal("Host.lan:[1]")
	_type(" ")
	_type("/")
	assert_int(f.rejected_count).is_equal(2)
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("Host.lan:[1]")
	# Empty is allowed.
	f.begin_editing()
	for i in 20:
		_key(KEY_BACKSPACE)
	_key(KEY_ENTER)
	assert_str(f.value).is_equal("")


func test_esc_reverts_without_reaching_the_screen() -> void:
	var f := _field("name", "MAKO")
	var probe := _probe()
	var cancelled := [0]
	f.cancelled.connect(func() -> void: cancelled[0] += 1)
	f.begin_editing()
	_type("ZZ")
	assert_str(f.value).is_equal("MAKOZZ")
	_key(KEY_ESCAPE)
	assert_bool(f.is_editing()).is_false()
	assert_str(f.value).is_equal("MAKO")
	assert_int(cancelled[0]).is_equal(1)
	assert_int(probe.cancels).override_failure_message("Esc while editing reached the screen").is_equal(0)
	assert_bool(f.has_focus()).is_true()
	# Not editing: Esc is the screen's.
	_key(KEY_ESCAPE)
	assert_int(probe.cancels).is_equal(1)


func test_gamepad_b_reverts_and_a_commits() -> void:
	var f := _field("port", "47474")
	var probe := _probe()
	_joy(JOY_BUTTON_A)
	assert_bool(f.is_editing()).is_true()
	_joy(JOY_BUTTON_X)
	assert_str(f.value).is_equal("4747")
	_joy(JOY_BUTTON_B)
	assert_str(f.value).is_equal("47474")
	assert_bool(f.is_editing()).is_false()
	assert_int(probe.cancels).is_equal(0)
	_joy(JOY_BUTTON_A)
	_joy(JOY_BUTTON_X)
	_joy(JOY_BUTTON_A)
	assert_bool(f.is_editing()).is_false()
	assert_str(f.value).is_equal("4747")


func test_gamepad_cycles_charset_order() -> void:
	var f := _field("name", "")
	f.begin_editing()
	_joy(JOY_BUTTON_DPAD_RIGHT)
	assert_str(f.value).is_equal("A")
	_joy(JOY_BUTTON_DPAD_UP)
	assert_str(f.value).is_equal("B")
	assert_str(f.last_blip).is_equal("move")
	_joy(JOY_BUTTON_DPAD_DOWN)
	_joy(JOY_BUTTON_DPAD_DOWN)
	# Wraps from A to the end of the order (-).
	assert_str(f.value).is_equal("-")
	_joy(JOY_BUTTON_DPAD_DOWN)
	assert_str(f.value).is_equal("_")
	_joy(JOY_BUTTON_DPAD_DOWN)
	assert_str(f.value).is_equal(" ")
	_joy(JOY_BUTTON_DPAD_DOWN)
	assert_str(f.value).is_equal("9")
	# Order checks against the spec lists.
	assert_str("".join(SonarTextField.cycle_order("name"))).is_equal(
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-")
	assert_str("".join(SonarTextField.cycle_order("port"))).is_equal("0123456789")
	assert_str("".join(SonarTextField.cycle_order("address"))).is_equal(
		"0123456789.:abcdefghijklmnopqrstuvwxyz-[]")


func test_gamepad_right_appends_defaults_and_left_moves_caret() -> void:
	var p := _field("port", "")
	p.begin_editing()
	_joy(JOY_BUTTON_DPAD_RIGHT)
	assert_str(p.value).is_equal("0")
	var a := _field("address", "10")
	a.begin_editing()
	_joy(JOY_BUTTON_DPAD_RIGHT)
	assert_str(a.value).is_equal("10.")
	_joy(JOY_BUTTON_DPAD_LEFT)
	_joy(JOY_BUTTON_DPAD_LEFT)
	assert_int(a.caret).is_equal(1)
	_joy(JOY_BUTTON_DPAD_RIGHT)
	assert_int(a.caret).is_equal(2)
	assert_str(a.value).is_equal("10.")
	# Cycling acts on the character at the caret ("." at index 2): next in the order is ":".
	_joy(JOY_BUTTON_DPAD_UP)
	assert_str(a.value).is_equal("10:")
	# Below max only.
	var full := _field("port", "12345")
	full.begin_editing()
	_joy(JOY_BUTTON_DPAD_RIGHT)
	assert_str(full.value).is_equal("12345")


func test_keyboard_caret_keys_and_delete() -> void:
	var f := _field("address", "abc")
	f.begin_editing()
	_key(KEY_HOME)
	assert_int(f.caret).is_equal(0)
	_key(KEY_DELETE)
	assert_str(f.value).is_equal("bc")
	_key(KEY_RIGHT)
	_type("x")
	assert_str(f.value).is_equal("bxc")
	_key(KEY_END)
	assert_int(f.caret).is_equal(3)
	_key(KEY_LEFT)
	_key(KEY_BACKSPACE)
	assert_str(f.value).is_equal("bc")


func test_paste_filters_and_truncates() -> void:
	var f := _field("address", "")
	f.clipboard_fn = func() -> String: return "  100.64.1.2\n"
	f.begin_editing()
	_key(KEY_V, 0, true)
	assert_str(f.value).is_equal("100.64.1.2")
	assert_int(f.rejected_count).is_equal(0)
	var n := _field("name", "AB")
	n.clipboard_fn = func() -> String: return "c\td!e\u0007fghijklmnopq"
	n.begin_editing()
	_key(KEY_V, 0, true)
	assert_str(n.value).is_equal("ABCDEFGHIJKL")
	assert_int(n.rejected_count).is_equal(1)
	assert_str(n.last_blip).is_equal("error")
	# A huge paste is truncated before insertion (T-04-12).
	var p := _field("port", "")
	p.clipboard_fn = func() -> String: return "9".repeat(100000)
	p.begin_editing()
	_key(KEY_V, 0, true)
	assert_str(p.value).is_equal("99999")


func test_focus_loss_commits() -> void:
	var f := _field("name", "MAKO")
	var other: Button = auto_free(Button.new())
	f.get_parent().add_child(other)
	var commits: Array = []
	f.committed.connect(func(v: String) -> void: commits.append(v))
	f.begin_editing()
	_type("X")
	other.grab_focus()
	assert_bool(f.is_editing()).is_false()
	assert_array(commits).is_equal(["MAKOX"])


func test_counter_text_only_for_name_and_address_while_editing() -> void:
	var n := _field("name", "MAKO")
	assert_str(n.counter_text()).is_equal("")
	n.begin_editing()
	assert_str(n.counter_text()).is_equal("4/12")
	var p := _field("port", "47474")
	p.begin_editing()
	assert_str(p.counter_text()).is_equal("")


func test_display_text_truncates_with_ellipsis_when_not_editing() -> void:
	var a := _field("address", "a".repeat(64))
	a.size = Vector2(200, 48)
	var shown := a.display_text()
	assert_bool(shown.ends_with("...")).is_true()
	assert_int(shown.length()).is_less(64)
	a.begin_editing()
	assert_bool(a.display_text().ends_with("...")).is_false()


func test_caret_blinks_on_full_and_low_and_is_steady_under_reduce_motion() -> void:
	var f := _field("name", "MAKO")
	f.begin_editing()
	assert_bool(f.caret_visible()).is_true()
	f.tick(0.6)
	assert_bool(f.caret_visible()).is_false()
	f.tick(0.5)
	assert_bool(f.caret_visible()).is_true()
	assert_dict(f.effect_counts()).is_equal({"caret_blink": true, "glow": true})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(f.effect_counts()).is_equal({"caret_blink": true, "glow": false})
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	assert_dict(f.effect_counts()).is_equal({"caret_blink": false, "glow": true})
	for i in 7:
		f.tick(0.3)
		assert_bool(f.caret_visible()).is_true()


func test_draws_in_every_state_without_error() -> void:
	var f := _field("address", "")
	await await_idle_frame()
	f.begin_editing()
	_type("100.64.0.1")
	f.queue_redraw()
	await await_idle_frame()
	_type("/")
	f.queue_redraw()
	await await_idle_frame()
	_key(KEY_ENTER)
	f.release_focus()
	f.tick(SonarTextField.REJECT_SEC)
	f.queue_redraw()
	await await_idle_frame()
	assert_str(f.debug_state().edge_color_role).is_equal("idle")
	assert_that(f.edge_color()).is_equal(Color(Palette.SONAR, 0.45))
	assert_bool(f.is_in_group(UiKit.FX_GROUP)).is_true()


func test_source_has_no_full_rect_preset() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/online/sonar_text_field.gd")
	assert_bool(src.contains("PRESET_FULL" + "_RECT")).is_false()
	assert_bool(src.contains("UiKit.register_fx(self)")).is_true()
