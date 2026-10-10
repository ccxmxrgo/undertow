extends GdUnitTestSuite
## Layout regression for in-run overlays (gap 1 of the hardware playtest): every overlay must be
## exactly viewport-sized, carry a full-screen dim layer, block the mouse, and center its panel.

const SCENE := "res://scenes/gameplay.tscn"
const SETTINGS := "res://scenes/settings.tscn"


func _launch() -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


const SCORES_TMP := "user://test_overlay_scores.cfg"
var _old_scores_path: String


func before_test() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP


func after_test() -> void:
	ScoreStore.default_path = _old_scores_path
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _vp(c: Control) -> Vector2:
	return c.get_viewport().get_visible_rect().size


func _describe(c: Control) -> String:
	return "%s size=%s global_rect=%s anchors=(%s,%s,%s,%s) offsets=(%s,%s,%s,%s)" % [
		c.name, c.size, c.get_global_rect(), c.anchor_left, c.anchor_top, c.anchor_right,
		c.anchor_bottom, c.offset_left, c.offset_top, c.offset_right, c.offset_bottom]


func _assert_full(c: Control) -> void:
	var vp := _vp(c)
	assert_bool(c.size.is_equal_approx(vp)).override_failure_message(
		"not viewport-sized (%s): %s" % [vp, _describe(c)]).is_true()
	assert_bool(c.get_global_rect().position.is_equal_approx(Vector2.ZERO)).override_failure_message(
		"not at origin: " + _describe(c)).is_true()


func _find_dim(root: Node) -> ColorRect:
	for n in root.find_children("*", "ColorRect", true, false):
		var cr := n as ColorRect
		if cr.size.is_equal_approx(_vp(cr)):
			return cr
	return null


func _assert_dim(root: Control, alpha: float) -> void:
	var dim := _find_dim(root)
	assert_object(dim).override_failure_message("no viewport-sized dim ColorRect under " + root.name).is_not_null()
	if dim != null:
		assert_float(dim.color.a).is_equal_approx(alpha, 0.001)


func _assert_centered(content: Control) -> void:
	var center := content.get_global_rect().get_center()
	var vc := _vp(content) * 0.5
	assert_bool(center.distance_to(vc) <= 1.0).override_failure_message(
		"content center %s != viewport center %s (%s)" % [center, vc, _describe(content)]).is_true()


func _click_blocked(gp: Gameplay) -> void:
	# Probe button behind the overlays; a click at (5, 5) must not reach it.
	var probe := Button.new()
	probe.custom_minimum_size = Vector2(100.0, 100.0)
	probe.position = Vector2.ZERO
	gp.add_child(probe)
	gp.move_child(probe, 0)
	var hits := [0]
	probe.pressed.connect(func() -> void: hits[0] += 1)
	await _frames(2)
	var vp := gp.get_viewport()
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(5.0, 5.0)
	mm.global_position = mm.position
	vp.push_input(mm)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(5.0, 5.0)
	down.global_position = down.position
	vp.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(5.0, 5.0)
	up.global_position = up.position
	vp.push_input(up)
	await _frames(2)
	assert_int(hits[0]).override_failure_message("click leaked through overlay").is_equal(0)


func test_pause_menu_fills_viewport_dims_and_centers() -> void:
	var gp := _launch()
	await _frames(3)
	gp.pause_menu.open()
	await _frames(2)
	var pm: PauseMenu = gp.pause_menu
	_assert_full(pm)
	_assert_full(pm._panel_root)
	_assert_dim(pm, 0.7)
	assert_int(pm._panel_root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_centered(pm.resume_button.get_parent())
	await _click_blocked(gp)


func test_fail_screen_fills_viewport_dims_and_blocks() -> void:
	var gp := _launch()
	await _frames(3)
	gp._on_failed()
	await _frames(3)
	var fs: FailScreen = gp.fail_screen
	_assert_full(fs)
	_assert_dim(fs, 0.9)
	assert_int(fs.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_centered(fs.retry_button.get_parent())
	await _click_blocked(gp)


func test_fail_screen_setup_after_add_child_and_before() -> void:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var a := FailScreen.new()
	host.add_child(a)
	a.setup(10.0)
	var b := FailScreen.new()
	b.setup(10.0)
	host.add_child(b)
	await _frames(3)
	_assert_full(a)
	_assert_full(b)


func test_results_screen_fills_viewport_dims_and_blocks() -> void:
	var gp := _launch()
	await _frames(3)
	gp._finish()
	await _frames(3)
	var rs: ResultsScreen = gp.results
	_assert_full(rs)
	_assert_dim(rs, 1.0)
	assert_int(rs.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_centered(rs.retry_button.get_parent())
	await _click_blocked(gp)


func test_confirm_dialog_from_pause_fills_viewport() -> void:
	var gp := _launch()
	await _frames(3)
	gp.pause_menu.open()
	gp.pause_menu.request_menu()
	await _frames(3)
	var dlg: ConfirmDialog = gp.pause_menu._dialog
	assert_object(dlg).is_not_null()
	_assert_full(dlg)
	_assert_dim(dlg, 0.7)
	assert_int(dlg.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_centered(dlg.safe_button.get_parent().get_parent().get_parent())
	await _click_blocked(gp)


func test_confirm_dialog_standalone_fills_viewport() -> void:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var dlg := ConfirmDialog.new()
	host.add_child(dlg)
	dlg.setup("T", "Body", "Yes", "No")
	await _frames(3)
	_assert_full(dlg)
	_assert_dim(dlg, 0.7)
	_assert_centered(dlg.safe_button.get_parent().get_parent().get_parent())


func test_settings_overlay_fills_viewport() -> void:
	var gp := _launch()
	await _frames(3)
	gp.pause_menu.open()
	gp.pause_menu.open_settings()
	await _frames(3)
	assert_bool(gp.pause_menu.has_settings_overlay()).is_true()
	var screen := gp.pause_menu._overlay.get_child(0) as Control
	assert_object(screen).is_not_null()
	assert_bool(screen.size.is_equal_approx(_vp(screen))).override_failure_message(
		_describe(screen)).is_true()


func test_fail_screen_shows_run_stats_and_saved_best() -> void:
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var f := FailScreen.new()
	host.add_child(f)
	f.setup(310.7, 42, 1240.0)
	assert_str(f.body_label.text).is_equal("Hull breached at 310 m.")
	assert_str(f.stats_label.text).is_equal("Max combo: 42")
	assert_str(f.best_label.text).is_equal("Saved best: 1,240 m")
	assert_str(f.note_label.text).is_equal("Records are saved only when a dive is finished.")
	var g := FailScreen.new()
	host.add_child(g)
	g.setup(5.0, 1, -1.0)
	assert_str(g.best_label.text).is_equal("No saved best yet.")
	var h := FailScreen.new()
	host.add_child(h)
	h.setup(5.0)
	assert_str(h.body_label.text).is_equal("Hull breached at 5 m.")


func _results(info: Dictionary, practice: bool = false, autoplay: bool = false) -> ResultsScreen:
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var r := ResultsScreen.new()
	host.add_child(r)
	r.setup(HullScore.new(JudgeConfig.new()), autoplay, info, practice)
	return r


func _texts(r: ResultsScreen) -> Array[String]:
	var out: Array[String] = []
	for n in r.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out


func test_results_new_record_and_previous_best() -> void:
	var r := _results({"eligible": true, "new_record": true, "previous_depth": 1240.0, "best_depth": 1500.0})
	assert_object(r.record_banner).is_not_null()
	assert_str(r.record_banner.text).is_equal("NEW RECORD")
	assert_bool(r.rows.has(["Previous best", "1,240 m"])).is_true()
	var first := _results({"eligible": true, "new_record": true, "previous_depth": -1.0, "best_depth": 5.0})
	assert_bool(first.rows.has(["Previous best", "none"])).is_true()
	assert_bool(r.retry_button.has_focus() or r.retry_button.is_inside_tree()).is_true()


func test_results_ineligible_and_non_record_copy() -> void:
	var r := _results({"eligible": false, "new_record": false, "previous_depth": -1.0, "best_depth": -1.0}, true)
	assert_object(r.record_banner).is_null()
	assert_bool(_texts(r).has("Not recorded. Practice, Autoplay and No-Fail dives do not set records.")).is_true()
	assert_bool(r.flags.has("PRACTICE DIVE")).is_true()
	var b := _results({"eligible": true, "new_record": false, "previous_depth": 100.0, "best_depth": 2500.0})
	assert_bool(_texts(b).has("Best: 2,500 m")).is_true()
	assert_object(b.record_banner).is_null()
	var a := _results({"eligible": false}, false, true)
	assert_bool(a.flags.has("AUTOPLAY USED")).is_true()
	assert_bool(a.flags.has("PRACTICE DIVE")).is_false()


# --- VIS-05 / D-20: results never show the main menu behind them ---------------------------------


## Mirrors SceneTree.change_scene_to_file for a scene hosted under the test: the old scene leaves the
## tree and is freed, the new one takes its place (MainMenu/SongSelect navigate hooks call this).
func _change_scene(old: Node, path: String) -> Node:
	var host := old.get_parent()
	host.remove_child(old)
	old.queue_free()
	var nxt: Node = (load(path) as PackedScene).instantiate()
	host.add_child(nxt)
	auto_free(nxt)
	return nxt


func _visible_menus() -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "MainMenu", true, false):
		if n.is_inside_tree() and not n.is_queued_for_deletion() and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func test_results_after_menu_show_no_main_menu() -> void:
	MainMenu.boot_handled = true
	var menu: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(3)
	# A real MainMenu exists in the tree before the dive.
	assert_int(get_tree().root.find_children("*", "MainMenu", true, false).size()).is_greater_equal(1)
	var target := [null]
	menu.navigate = func(path: String) -> void: target[0] = _change_scene(menu, path)
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	menu.navigate.call(SCENE)
	await _frames(3)
	var gp := target[0] as Gameplay
	assert_object(gp).is_not_null()
	gp._finish()
	await _frames(3)
	assert_object(gp.results).is_not_null()
	assert_int(gp.state).is_equal(Gameplay.State.DONE)
	var vis := _visible_menus()
	assert_array(vis).override_failure_message("MainMenu visible behind results: %s" % [vis]).is_empty()
	# Nothing outside the results screen is in the focus graph.
	var fo := gp.get_viewport().gui_get_focus_owner()
	if fo != null:
		assert_bool(gp.results.is_ancestor_of(fo)).override_failure_message(
			"focus outside results: %s" % fo).is_true()
	# Results backdrop is fully opaque.
	_assert_dim(gp.results, 1.0)


func test_results_buttons_form_closed_focus_loop() -> void:
	var gp := _launch()
	await _frames(3)
	gp._finish()
	await _frames(3)
	var rs: ResultsScreen = gp.results
	var pairs := [[rs.retry_button, rs.menu_button], [rs.menu_button, rs.retry_button]]
	for pair in pairs:
		var a: Button = pair[0]
		var b: Button = pair[1]
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var np: NodePath = a.get_focus_neighbor(side)
			assert_bool(not np.is_empty() and a.get_node_or_null(np) == b).override_failure_message(
				"%s side %d -> %s, expected %s" % [a.text, side, np, b.text]).is_true()
			assert_object(a.find_valid_focus_neighbor(side)).is_same(b)
		assert_object(a.get_node_or_null(a.focus_next)).is_same(b)
		assert_object(a.get_node_or_null(a.focus_previous)).is_same(b)
	# Real ui_* navigation stays inside the two buttons.
	rs.retry_button.grab_focus()
	await _frames(1)
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		var before := gp.get_viewport().gui_get_focus_owner()
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		gp.get_viewport().push_input(ev)
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		gp.get_viewport().push_input(up)
		await _frames(1)
		var after := gp.get_viewport().gui_get_focus_owner()
		assert_bool(after == rs.retry_button or after == rs.menu_button).override_failure_message(
			"%s left the results buttons: %s" % [action, after]).is_true()
		assert_bool(after != before).override_failure_message("%s did not move focus" % action).is_true()
