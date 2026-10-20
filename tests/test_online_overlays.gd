extends GdUnitTestSuite
## 04-07 (04-UI-SPEC 10.2, 11.4, 11.6, 15; NET-03/05/06, D-17, D-18): the three in-match online
## overlays as standalone widgets. StartSyncOverlay copy states and dismiss(); LeaveOverlay copy,
## focus, input consumption (lane and target actions pass through) and no pause; HostLeftDialog
## copy, rows, focus and rows_from_status ordering; has_char for every constant string.

## Counts lane_1 / ui_accept presses that reach _unhandled_input (i.e. were not consumed).
const PROBE_SRC := """extends Node
var lanes := 0
var accepts := 0
var targets := 0
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lane_1"):
		lanes += 1
	if event.is_action_pressed(&"target_cycle"):
		targets += 1
	if event.is_action_pressed(&"ui_accept"):
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
	get_tree().paused = false


# ---- helpers ----------------------------------------------------------------------------

func _host() -> Control:
	var host: Control = auto_free(Control.new())
	UiLayout.fill_rect(host)
	add_child(host)
	return host


func _probe() -> Node:
	var s := GDScript.new()
	s.source_code = PROBE_SRC
	s.reload()
	var n: Node = auto_free(Node.new())
	n.set_script(s)
	add_child(n)
	return n


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _key(keycode: Key, physical: Key = KEY_NONE, unicode: int = 0) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = physical
	ev.unicode = unicode
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)


func _action(a: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	return ev


func _sync(n: int = 4) -> StartSyncOverlay:
	var o := StartSyncOverlay.new()
	_host().add_child(o)
	var rows: Array = []
	var names := ["MAKO", "BARRACUDA", "LAMPREY", "NARWHAL"]
	for i in n:
		rows.append({"seat": i, "name": names[i], "is_you": i == 1})
	o.setup(rows)
	return o


func _leave() -> LeaveOverlay:
	var o := LeaveOverlay.new()
	_host().add_child(o)
	return o


func _std_rows() -> Array:
	return [
		{"place": 1, "name": "MAKO", "is_you": false, "is_host": true, "status": "hull", "hull_pct": 74.0},
		{"place": 2, "name": "DIVER", "is_you": true, "is_host": false, "status": "hull", "hull_pct": 41.6},
		{"place": 3, "name": "LAMPREY", "is_you": false, "is_host": false, "status": "wreck", "hull_pct": 0.0},
		{"place": 4, "name": "NARWHAL", "is_you": false, "is_host": false, "status": "left", "hull_pct": 30.0},
	]


func _dialog(kind: String = "host_left") -> HostLeftDialog:
	var d := HostLeftDialog.new()
	_host().add_child(d)
	d.setup(kind, "mako", _std_rows())
	return d


# ---- StartSyncOverlay -------------------------------------------------------------------

func test_sync_overlay_stage_body_and_roster_copy() -> void:
	var o := _sync(4)
	await _frames(1)
	var s := o.debug_state()
	assert_str(s.title).is_equal("LOADING SONG")
	assert_str(s.body).is_equal("Waiting for 4 of 4 subs to load.")
	o.set_stage("linking")
	o.set_loaded(0, true)
	o.set_loaded(1, true)
	s = o.debug_state()
	assert_str(s.title).is_equal("LINKING SUBS")
	assert_str(s.body).is_equal("Waiting for 2 of 4 subs to load.")
	var lines: Array = s.lines
	assert_int(lines.size()).is_equal(4)
	assert_dict(lines[0]).is_equal({"name": "MAKO", "status": "LOADED"})
	assert_dict(lines[1]).is_equal({"name": "YOU", "status": "LOADED"})
	assert_dict(lines[2]).is_equal({"name": "LAMPREY", "status": "LOADING"})
	assert_dict(lines[3]).is_equal({"name": "NARWHAL", "status": "LOADING"})
	o.set_loaded(2, true)
	o.set_loaded(3, true)
	assert_str(o.debug_state().body).is_equal("All loaded. Waiting for the start signal.")
	o.set_loaded(3, false)
	assert_str(o.debug_state().body).is_equal("Waiting for 1 of 4 subs to load.")


func test_sync_overlay_rect_hint_and_effects() -> void:
	var o := _sync(2)
	await _frames(1)
	assert_object(o.get_global_rect()).is_equal(Rect2(600, 340, 720, 400))
	assert_str(o.hint_text()).is_equal("ESC LEAVE MATCH")
	o.set_pad(true)
	assert_str(o.hint_text()).is_equal("START LEAVE MATCH")
	assert_bool(o.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_dict(o.effect_counts()).is_equal({"fade_out": true, "glow": true})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(o.effect_counts()).is_equal({"fade_out": true, "glow": false})


func test_sync_overlay_dismiss_frees_within_dur_base() -> void:
	var o := _sync(2)
	await _frames(1)
	var got := [false]
	o.dismissed.connect(func() -> void: got[0] = true)
	o.set_process(false)  # drive time by hand
	o.dismiss()
	assert_bool(o.is_dismissing()).is_true()
	o.step(Palette.DUR_BASE * 0.5)
	assert_float(o.modulate.a).is_between(0.3, 0.7)
	assert_bool(got[0]).is_false()
	var t := Palette.DUR_BASE * 0.5
	while t < Palette.DUR_BASE + 0.05 and not got[0]:
		o.step(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_bool(got[0]).override_failure_message("not dismissed after %.3f s" % t).is_true()
	assert_float(t).is_less_equal(Palette.DUR_BASE + 0.05)
	await _frames(1)
	assert_bool(is_instance_valid(o)).is_false()


func test_sync_overlay_dismiss_in_every_effect_mode() -> void:
	for mode in [[true, false], [false, true]]:
		Settings.low_effects = mode[0]
		Settings.reduce_motion = mode[1]
		Settings.settings_changed.emit()
		var o := _sync(1)
		await _frames(1)
		o.set_process(false)
		o.dismiss()
		o.step(Palette.DUR_BASE * 0.5)
		assert_float(o.modulate.a).is_less(1.0)
		o.step(Palette.DUR_BASE)
		await _frames(1)
		assert_bool(is_instance_valid(o)).is_false()


# ---- LeaveOverlay -----------------------------------------------------------------------

func test_leave_overlay_rect_buttons_and_initial_focus() -> void:
	var o := _leave()
	await _frames(1)
	assert_bool(o.visible).is_false()
	assert_bool(o.is_open()).is_false()
	o.open(false, 42)
	o.step(1.0)
	await _frames(1)
	assert_object(o.get_global_rect()).is_equal(Rect2(640, 120, 640, 152))
	assert_object(o.leave_button.get_global_rect()).is_equal(Rect2(656, 208, 296, 48))
	assert_object(o.stay_button.get_global_rect()).is_equal(Rect2(968, 208, 296, 48))
	assert_str(String(o.leave_button.get_meta(&"ui_variant", ""))).is_equal("destructive")
	assert_str(String(o.stay_button.get_meta(&"ui_variant", ""))).is_equal("default")
	assert_str(o.leave_button.text).is_equal("Leave Match")
	assert_str(o.stay_button.text).is_equal("Stay")
	assert_bool(o.stay_button.has_focus()).is_true()
	assert_str(o.debug_state().focus).is_equal("stay")


func test_leave_overlay_client_vs_host_copy() -> void:
	var o := _leave()
	await _frames(1)
	o.open(false, 42)
	var s := o.debug_state()
	assert_bool(s.open).is_true()
	assert_str(s.title).is_equal("LEAVE MATCH?")
	assert_str(s.body).is_equal("The song keeps playing. Leaving makes your sub a wreck.")
	assert_str(s.body_role).is_equal("mid")
	assert_str(s.ping).is_equal("PING 42 MS")
	o.set_ping(-1)
	assert_str(o.ping_text()).is_equal("PING -- MS")
	o.close()
	o.open(true, 10)
	s = o.debug_state()
	assert_str(s.body).is_equal("You are the host. Leaving ends the match for everyone.")
	assert_str(s.body_role).is_equal("warning")
	assert_str(s.ping).is_equal("")


func test_leave_overlay_accept_on_stay_emits_stayed() -> void:
	var o := _leave()
	await _frames(1)
	var got := {"stay": 0, "leave": 0}
	o.stayed.connect(func() -> void: got.stay += 1)
	o.leave_confirmed.connect(func() -> void: got.leave += 1)
	o.open(false, 30)
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(1)
	assert_int(got.stay).is_equal(1)
	assert_int(got.leave).is_equal(0)
	assert_bool(o.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_leave_overlay_right_then_accept_emits_leave() -> void:
	var o := _leave()
	await _frames(1)
	var got := {"stay": 0, "leave": 0}
	o.stayed.connect(func() -> void: got.stay += 1)
	o.leave_confirmed.connect(func() -> void: got.leave += 1)
	o.open(false, 30)
	await _frames(1)
	_key(KEY_LEFT)
	assert_str(o.focus_name()).is_equal("leave")
	_key(KEY_LEFT)  # two buttons: focus wraps
	assert_str(o.focus_name()).is_equal("stay")
	assert_bool(o.handle_event(_action(&"ui_right"))).is_true()
	assert_str(o.focus_name()).is_equal("leave")
	assert_bool(o.leave_button.has_focus()).is_true()
	assert_bool(o.handle_event(_action(&"ui_accept"))).is_true()
	assert_int(got.leave).is_equal(1)
	assert_int(got.stay).is_equal(0)
	assert_bool(o.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_leave_overlay_cancel_and_pause_mean_stay() -> void:
	var o := _leave()
	await _frames(1)
	var got := {"stay": 0, "leave": 0}
	o.stayed.connect(func() -> void: got.stay += 1)
	o.leave_confirmed.connect(func() -> void: got.leave += 1)
	o.open(false, 30)
	# The press that opened it (same frame) is swallowed, not treated as Stay.
	assert_bool(o.handle_event(_action(&"pause"))).is_true()
	assert_bool(o.is_open()).is_true()
	await _frames(1)
	o.handle_event(_action(&"ui_left"))
	assert_bool(o.handle_event(_action(&"pause"))).is_true()
	assert_int(got.stay).is_equal(1)
	o.open(true, 30)
	await _frames(1)
	_key(KEY_ESCAPE, KEY_ESCAPE)
	assert_int(got.stay).is_equal(2)
	assert_int(got.leave).is_equal(0)
	assert_bool(get_tree().paused).is_false()


func test_leave_overlay_lane_and_target_pass_through_space_is_consumed() -> void:
	var o := _leave()
	await _frames(1)
	var probe := _probe()
	o.open(false, 30)
	await _frames(1)
	# Synthetic lane / target actions are not consumed.
	assert_bool(o.handle_event(_action(&"lane_1"))).is_false()
	assert_bool(o.handle_event(_action(&"lane_4"))).is_false()
	assert_bool(o.handle_event(_action(&"target_cycle"))).is_false()
	assert_bool(o.handle_event(_action(&"fire"))).is_false()
	# Real key presses through the viewport: lane 1 (physical 1) and H reach the game.
	_key(KEY_NONE, KEY_1, 49)
	_key(KEY_NONE, KEY_H, 104)
	assert_int(probe.lanes).is_equal(1)
	assert_int(probe.targets).is_equal(1)
	assert_bool(o.is_open()).is_true()
	# Space (ui_accept + fire) is consumed: it picks Stay and never reaches the game.
	_key(KEY_SPACE, KEY_SPACE, 32)
	assert_int(probe.accepts).is_equal(0)
	assert_bool(o.is_open()).is_false()
	# Closed: nothing is consumed any more.
	assert_bool(o.handle_event(_action(&"ui_accept"))).is_false()
	assert_bool(get_tree().paused).is_false()


func test_leave_overlay_motion_and_effects() -> void:
	var o := _leave()
	await _frames(1)
	o.set_process(false)
	o.open(false, 1)
	o.step(Palette.DUR_FAST * 0.5)
	assert_float(o.position.y).is_less(120.0)
	assert_float(o.position.y).is_greater_equal(104.0)
	o.step(Palette.DUR_FAST)
	assert_float(o.position.y).is_equal(120.0)
	assert_float(o.modulate.a).is_equal(1.0)
	assert_dict(o.effect_counts()).is_equal({"slide": true, "glow": true})
	o.close()
	o.step(Palette.DUR_FAST + 0.01)
	assert_bool(o.visible).is_false()
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	assert_dict(o.effect_counts()).is_equal({"slide": false, "glow": true})
	o.open(true, 1)
	o.step(Palette.DUR_FAST * 0.5)
	assert_float(o.position.y).is_equal(120.0)
	assert_float(o.modulate.a).is_between(0.2, 0.8)
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(o.effect_counts()).is_equal({"slide": false, "glow": false})


# ---- HostLeftDialog ---------------------------------------------------------------------

func test_host_left_dialog_titles_and_bodies() -> void:
	var d := _dialog("host_left")
	await _frames(1)
	var s := d.debug_state()
	assert_str(s.title).is_equal("HOST LEFT")
	assert_str(s.body).is_equal("MAKO left, so the match ended. Nothing is saved.")
	d.setup("connection_lost", "Mako", _std_rows())
	s = d.debug_state()
	assert_str(s.title).is_equal("CONNECTION LOST")
	assert_str(s.body).is_equal(
		"No signal from MAKO for 4 seconds. The match ended on this PC. Nothing is saved.")
	assert_str(d.hint_text()).is_equal("ENTER BACK TO MENU")
	d.set_pad(true)
	assert_str(d.hint_text()).is_equal("A BACK TO MENU")


func test_host_left_dialog_rows_and_focus() -> void:
	var d := _dialog()
	await _frames(2)
	var s := d.debug_state()
	var rows: Array = s.rows
	assert_int(rows.size()).is_equal(4)
	assert_array(rows.map(func(r: Dictionary) -> String: return r.place)).is_equal(["1ST", "2ND", "3RD", "4TH"])
	assert_array(rows.map(func(r: Dictionary) -> String: return r.name)).is_equal(["MAKO", "YOU", "LAMPREY", "NARWHAL"])
	assert_array(rows.map(func(r: Dictionary) -> String: return r.status)).is_equal(
		["HULL 74%", "HULL 42%", "WRECK", "LEFT"])
	assert_bool(rows[0].place_gold).is_true()
	assert_bool(rows[1].place_gold).is_false()
	assert_bool(rows[0].is_host).is_true()
	assert_bool(rows[1].is_you).is_true()
	assert_bool(HostLeftDialog.status_of({"status": "wreck"})[1] == Palette.WARNING_RED).is_true()
	assert_bool(HostLeftDialog.status_of({"status": "left"})[1] == Palette.TEXT_LO).is_true()
	assert_bool(HostLeftDialog.status_of({"status": "hull", "hull_pct": 5.0})[1] == Palette.TEXT_MID).is_true()
	assert_str(s.focus).is_equal("back_to_menu")
	assert_bool(d.button.has_focus()).is_true()
	assert_str(d.button.text).is_equal("Back to Menu")
	assert_str(String(d.button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_int(d.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	# More than 4 rows are cut to 4.
	var many := _std_rows()
	many.append({"place": 5, "name": "EXTRA", "status": "hull", "hull_pct": 1.0})
	d.setup("host_left", "MAKO", many)
	assert_int((d.debug_state().rows as Array).size()).is_equal(4)


func test_host_left_dialog_accept_cancel_emit_back_once() -> void:
	for key in [KEY_ENTER, KEY_ESCAPE]:
		var d := _dialog()
		await _frames(1)
		var got := [0]
		d.back_to_menu.connect(func() -> void: got[0] += 1)
		_key(key, key)
		_key(key, key)
		assert_int(got[0]).override_failure_message("key %d" % key).is_equal(1)
		d.queue_free()
		await _frames(1)


func test_host_left_dialog_motion_and_effects() -> void:
	var d := HostLeftDialog.new()
	d.set_process(false)
	_host().add_child(d)
	d.setup("host_left", "MAKO", _std_rows())
	d.step(Palette.DUR_BASE * 0.5)
	assert_float(d.panel.position.y).is_greater(240.0)
	assert_float(d.panel.position.y).is_less_equal(256.0)
	assert_float(d.modulate.a).is_between(0.2, 0.8)
	d.step(Palette.DUR_BASE)
	assert_float(d.panel.position.y).is_equal(240.0)
	assert_float(d.modulate.a).is_equal(1.0)
	assert_dict(d.effect_counts()).is_equal({"rise": true, "glow": true})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(d.effect_counts()).is_equal({"rise": true, "glow": false})
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	assert_dict(d.effect_counts()).is_equal({"rise": false, "glow": true})
	var d2 := HostLeftDialog.new()
	d2.set_process(false)
	_host().add_child(d2)
	d2.step(Palette.DUR_BASE * 0.5)
	assert_float(d2.panel.position.y).is_equal(240.0)
	assert_float(d2.modulate.a).is_less(1.0)


func test_rows_from_status_orders_alive_by_hull_then_depth_then_wrecks() -> void:
	var statuses := {
		0: {"hull": 50.0, "depth": 300.0, "alive": true, "left": false},
		1: {"hull": 80.0, "depth": 100.0, "alive": true, "left": false},
		2: {"hull": 0.0, "depth": 500.0, "alive": false, "left": false},
		3: {"hull": 50.0, "depth": 400.0, "alive": true, "left": false},
	}
	var rows := HostLeftDialog.rows_from_status(statuses, PackedStringArray(["MAKO", "DIVER", "LAMPREY", "NARWHAL"]), 1, 0)
	assert_array(rows.map(func(r: Dictionary) -> int: return r.seat)).is_equal([1, 3, 0, 2])
	assert_array(rows.map(func(r: Dictionary) -> int: return r.place)).is_equal([1, 2, 3, 4])
	assert_array(rows.map(func(r: Dictionary) -> String: return r.status)).is_equal(["hull", "hull", "hull", "wreck"])
	assert_bool(rows[0].is_you).is_true()
	assert_bool(rows[2].is_host).is_true()
	assert_str(rows[1].name).is_equal("NARWHAL")
	# A seat that left counts as down (after the alive), ordered with the wrecks by depth.
	statuses[3] = {"hull": 90.0, "depth": 600.0, "alive": true, "left": true}
	rows = HostLeftDialog.rows_from_status(statuses, PackedStringArray(["MAKO", "DIVER", "LAMPREY", "NARWHAL"]), 1, 0)
	assert_array(rows.map(func(r: Dictionary) -> int: return r.seat)).is_equal([1, 0, 3, 2])
	assert_str(rows[2].status).is_equal("left")
	# Missing names fall back; the result feeds setup() directly.
	rows = HostLeftDialog.rows_from_status({5: {"hull": 10.0, "depth": 1.0, "alive": true}}, PackedStringArray(), -1, -1)
	assert_str(rows[0].name).is_equal("P6")
	var d := _dialog()
	d.setup("host_left", "MAKO", HostLeftDialog.rows_from_status(statuses,
		PackedStringArray(["MAKO", "DIVER", "LAMPREY", "NARWHAL"]), 1, 0))
	assert_array((d.debug_state().rows as Array).map(func(r: Dictionary) -> String: return r.name)).is_equal(
		["YOU", "MAKO", "NARWHAL", "LAMPREY"])


func test_overlays_draw_without_errors() -> void:
	var o := _sync(4)
	o.set_loaded(0, true)
	var l := _leave()
	l.open(true, 5)
	var d := _dialog()
	await _frames(3)
	assert_bool(is_instance_valid(o) and is_instance_valid(l) and is_instance_valid(d)).is_true()


# ---- fonts ------------------------------------------------------------------------------

func test_every_constant_string_has_its_glyphs() -> void:
	var label := Palette.font()
	var heading: Font = load(Palette.DISPLAY_FONT_PATH) as Font
	assert_object(heading).is_not_null()
	var bad: Array[String] = []
	for copy: Dictionary in [StartSyncOverlay.COPY, LeaveOverlay.COPY, HostLeftDialog.COPY]:
		for role: String in copy:
			var f: Font = heading if role == "heading" else label
			for t: String in copy[role]:
				for i in t.length():
					if not f.has_char(t.unicode_at(i)):
						bad.append("'%s' in '%s' (%s)" % [t[i], t, role])
	assert_array(bad).override_failure_message("missing glyphs:\n" + "\n".join(bad)).is_empty()
