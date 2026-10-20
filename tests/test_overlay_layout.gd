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


func _assert_dim_colour(root: Control, token: Color) -> void:
	var dim := _find_dim(root)
	if dim != null:
		assert_bool(Color(dim.color, 1.0).is_equal_approx(token)).override_failure_message(
			"dim colour %s is not the token %s" % [dim.color, token]).is_true()


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
	_assert_dim(pm, 0.85)  # 02.2-20: ABYSS_900 85% (UI-SPEC 9.1)
	_assert_dim_colour(pm, Palette.ABYSS_900)
	assert_int(pm._panel_root.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(pm.panel.get_global_rect()).is_equal(PauseMenu.PANEL_RECT)
	_assert_centered(pm.panel)
	await _click_blocked(gp)


func test_fail_screen_fills_viewport_dims_and_blocks() -> void:
	var gp := _launch()
	await _frames(3)
	gp._on_failed()
	await _frames(3)
	var fs: FailScreen = gp.fail_screen
	_assert_full(fs)
	_assert_dim(fs, 0.9)
	_assert_dim_colour(fs, Palette.ABYSS_900)
	assert_int(fs.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(fs.panel.get_global_rect()).is_equal(FailScreen.PANEL_RECT)
	_assert_centered(fs.panel)
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
	_assert_results_opaque(rs)
	assert_int(rs.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
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
	_assert_dim_colour(dlg, Palette.ABYSS_900)
	assert_int(dlg.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(dlg.panel.get_global_rect()).is_equal(ConfirmDialog.PANEL_RECT)
	_assert_centered(dlg.panel)
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
	assert_object(dlg.panel.get_global_rect()).is_equal(ConfirmDialog.PANEL_RECT)
	_assert_centered(dlg.panel)


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
	assert_bool(_texts(r).has("Not recorded. Solo, Autoplay and No-Fail dives do not set records.")).is_true()
	assert_bool(r.flags.has("SOLO DIVE")).is_true()
	var b := _results({"eligible": true, "new_record": false, "previous_depth": 100.0, "best_depth": 2500.0})
	assert_bool(_texts(b).has("PREVIOUS BEST 2,500 M")).is_true()
	assert_object(b.record_banner).is_null()
	var a := _results({"eligible": false}, false, true)
	assert_bool(a.flags.has("AUTOPLAY USED")).is_true()
	assert_bool(a.flags.has("SOLO DIVE")).is_false()


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
	# Results backdrop is fully opaque (calm AbyssBackdrop + ABYSS_900 55%).
	_assert_results_opaque(gp.results)




# --- 02.2-15: opaque design-system results (UI-SPEC 8, 4.13) --------------------------------------


## Results are opaque: the first child is the calm AbyssBackdrop, then a viewport-sized ABYSS_900 55%
## layer. The backdrop's own gradient is opaque, so nothing of the frozen board shows through.
func _assert_results_opaque(rs: ResultsScreen) -> void:
	assert_int(rs.get_child_count()).is_greater(2)
	var bd := rs.get_child(0) as AbyssBackdrop
	assert_object(bd).override_failure_message("first child is not an AbyssBackdrop").is_not_null()
	if bd != null:
		assert_str(bd.variant).is_equal("calm")
	_assert_dim(rs, 0.55)
	var dim := _find_dim(rs)
	if dim != null:
		assert_bool(Color(dim.color, 1.0).is_equal_approx(Palette.ABYSS_900)).is_true()
	assert_bool(rs.backdrop_opaque()).is_true()


func _score(p: int, g: int, m: int, hull: float = 82.0) -> HullScore:
	var s := HullScore.new(JudgeConfig.new())
	s.perfect_count = p
	s.good_count = g
	s.miss_count = m
	s.max_combo = p
	s.hull = hull
	return s


func _results_run(score: HullScore, info: Dictionary, run_info: Dictionary = {}, practice: bool = false) -> ResultsScreen:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var r := ResultsScreen.new()
	host.add_child(r)
	r.setup(score, false, info, practice, run_info)
	return r


func _rect_of(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


func test_results_three_buttons_geometry_and_signals() -> void:
	var r := _results_run(_score(10, 0, 0), {"eligible": true, "new_record": false})
	await _frames(2)
	assert_object(r.song_select_button).is_not_null()
	assert_str(r.retry_button.text).is_equal("Retry Dive")
	assert_str(r.song_select_button.text).is_equal("Song Select")
	assert_str(r.menu_button.text).is_equal("Back to Menu")
	assert_str(String(r.retry_button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_object(_rect_of(r.retry_button)).is_equal(Rect2(96, 752, 400, 64))
	assert_object(_rect_of(r.song_select_button)).is_equal(Rect2(520, 752, 400, 64))
	assert_object(_rect_of(r.menu_button)).is_equal(Rect2(944, 752, 400, 64))
	assert_bool(r.retry_button.has_focus()).is_true()
	var got: Array[String] = []
	r.retry_pressed.connect(func() -> void: got.append("retry"))
	r.song_select_pressed.connect(func() -> void: got.append("song"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	r.retry_button.pressed.emit()
	r.song_select_button.pressed.emit()
	r.menu_button.pressed.emit()
	assert_array(got).is_equal(["retry", "song", "menu"])
	# Esc / B = Back to Menu (once the entrance is over: during it, any press only skips; 02.2-16).
	r.skip_entrance()
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	get_viewport().push_input(esc)
	var esc_up := InputEventAction.new()
	esc_up.action = "ui_cancel"
	esc_up.pressed = false
	get_viewport().push_input(esc_up)
	await _frames(1)
	assert_array(got).is_equal(["retry", "song", "menu", "menu"])


func test_results_buttons_form_closed_focus_loop() -> void:
	var gp := _launch()
	await _frames(3)
	gp._finish()
	await _frames(3)
	var rs: ResultsScreen = gp.results
	rs.skip_entrance()  # 02.2-16: presses during the entrance only skip it
	var order: Array[Button] = [rs.retry_button, rs.song_select_button, rs.menu_button]
	for i in order.size():
		var a := order[i]
		var nxt := order[(i + 1) % 3]
		var prv := order[(i + 2) % 3]
		for side in [SIDE_RIGHT, SIDE_BOTTOM]:
			assert_object(a.get_node_or_null(a.get_focus_neighbor(side))).override_failure_message(
				"%s side %d" % [a.text, side]).is_same(nxt)
		for side in [SIDE_LEFT, SIDE_TOP]:
			assert_object(a.get_node_or_null(a.get_focus_neighbor(side))).override_failure_message(
				"%s side %d" % [a.text, side]).is_same(prv)
		assert_object(a.get_node_or_null(a.focus_next)).is_same(nxt)
		assert_object(a.get_node_or_null(a.focus_previous)).is_same(prv)
	# Real ui_* navigation stays inside the three buttons and wraps.
	rs.retry_button.grab_focus()
	await _frames(1)
	var expect := {"ui_right": rs.song_select_button, "ui_down": rs.menu_button, "ui_left": rs.song_select_button,
		"ui_up": rs.retry_button}
	for action in ["ui_right", "ui_down", "ui_left", "ui_up"]:
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
		assert_object(after).override_failure_message("%s -> %s" % [action, after]).is_same(expect[action])
	# Up from Retry wraps to Back to Menu.
	var w := InputEventAction.new()
	w.action = "ui_up"
	w.pressed = true
	gp.get_viewport().push_input(w)
	var wu := InputEventAction.new()
	wu.action = "ui_up"
	wu.pressed = false
	gp.get_viewport().push_input(wu)
	await _frames(1)
	assert_object(gp.get_viewport().gui_get_focus_owner()).is_same(rs.menu_button)


func test_results_legacy_four_arg_setup_derives_grade() -> void:
	# 90 P, 10 G, 0 M -> (9000 + 500) / 100 = 95.0% -> A.
	var r := _results_run(_score(90, 10, 0), {"eligible": true, "new_record": false})
	var acc := RunStats.accuracy(90, 10, 0)
	assert_str(r.accuracy_text).is_equal(RunStats.accuracy_text(acc))
	assert_str(r.accuracy_text).is_equal("95.0%")
	assert_str(r.grade_letter).is_equal(RunStats.grade(acc, 0))
	assert_str(r.grade_letter).is_equal("A")
	assert_str(r.grade_emblem.letter).is_equal("A")
	assert_bool(_texts(r).has("95.0%")).is_true()
	# Old 4-argument call (no run_info) still works.
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var old := ResultsScreen.new()
	host.add_child(old)
	old.setup(_score(50, 0, 1), false, {"eligible": true, "new_record": false}, false)
	assert_str(old.grade_letter).is_equal(RunStats.grade(RunStats.accuracy(50, 0, 1), 1))
	# 98+% with a Miss is A, not S.
	var s := _results_run(_score(200, 0, 1), {})
	assert_str(s.grade_letter).is_equal("A")
	var perfect := _results_run(_score(50, 0, 0), {})
	assert_str(perfect.grade_letter).is_equal("S")


func test_results_zero_judged_notes() -> void:
	var r := _results_run(_score(0, 0, 0), {})
	assert_str(r.accuracy_text).is_equal("--.-%")
	assert_str(r.grade_letter).is_equal("-")
	assert_array(r.bar_widths).is_equal([0.0, 0.0, 0.0])


func test_results_header_uses_run_info() -> void:
	var info := {"title": "Sea Shanty 2", "artist": "Jagex", "difficulty": "expert", "grade": "B", "accuracy": 88.0}
	var r := _results_run(_score(70, 20, 10), {"eligible": true, "new_record": false}, info)
	var t := _texts(r)
	assert_bool(t.has("DIVE COMPLETE")).is_true()
	assert_bool(t.has("Sea Shanty 2")).is_true()
	assert_bool(t.has("Jagex")).is_true()
	assert_bool(r.header_chips.has("EXPERT")).is_true()
	assert_bool(t.has("ENTER SELECT  ·  ESC BACK TO MENU")).is_true()
	for cap in ["GRADE", "ACCURACY", "DEPTH", "MAX COMBO", "FINAL HULL", "PERFECT", "GOOD", "MISS", "TIMING"]:
		assert_bool(t.has(cap)).override_failure_message("missing caption " + cap).is_true()
	# Long titles are cut to fit 1200 px.
	var long_title := "An Extremely Long Song Title ".repeat(8)
	var lr := _results_run(_score(1, 0, 0), {}, {"title": long_title})
	assert_float(lr.title_label.size.x).is_less_equal(1200.0)
	assert_bool(lr.title_label.text.ends_with("...")).is_true()


func test_results_judgment_bars_are_proportional() -> void:
	var r := _results_run(_score(60, 30, 10), {})
	assert_float(r.bar_widths[0]).is_equal_approx(352.0 * 0.6, 0.01)
	assert_float(r.bar_widths[1]).is_equal_approx(352.0 * 0.3, 0.01)
	assert_float(r.bar_widths[2]).is_equal_approx(352.0 * 0.1, 0.01)
	assert_float(ResultsScreen.BAR_MAX).is_equal(352.0)


func test_results_final_hull_red_when_critical() -> void:
	var ok := _results_run(_score(10, 0, 0, 31.0), {})
	assert_bool(ok.hull_label.get_theme_color("font_color").is_equal_approx(Palette.TEXT_HI)).is_true()
	assert_str(ok.hull_label.text).is_equal("31%")
	var low := _results_run(_score(10, 0, 0, 30.0), {})
	assert_bool(low.hull_label.get_theme_color("font_color").is_equal_approx(Palette.WARNING_RED)).is_true()


func test_results_previous_best_line_variants() -> void:
	var rec := _results_run(_score(10, 0, 0), {"eligible": true, "new_record": true, "previous_depth": 466.0, "best_depth": 500.0})
	assert_str(rec.previous_label.text).is_equal("PREVIOUS BEST 466 M")
	assert_bool(rec.record_banner != null and rec.record_banner.is_visible_in_tree()).is_true()
	var first := _results_run(_score(10, 0, 0), {"eligible": true, "new_record": true, "previous_depth": -1.0, "best_depth": 5.0})
	assert_str(first.previous_label.text).is_equal("First record for this song.")
	var nr := _results_run(_score(10, 0, 0), {"eligible": false, "new_record": false}, {}, true)
	assert_bool(nr.previous_label == null or not nr.previous_label.is_visible_in_tree()).is_true()


func test_results_practice_shows_not_recorded_chip() -> void:
	var r := _results_run(_score(10, 2, 3), {"eligible": false, "new_record": false, "previous_depth": -1.0, "best_depth": -1.0}, {}, true)
	assert_bool(r.header_chips.has("NOT RECORDED")).is_true()
	assert_bool(r.header_chips.has("SOLO DIVE")).is_true()
	assert_bool(r.flags.has("SOLO DIVE")).is_true()
	assert_object(r.note_label).is_not_null()
	assert_bool(r.note_label.text.begins_with("Not recorded")).is_true()
	assert_object(r.record_banner).is_null()
	var ok := _results_run(_score(10, 2, 3), {"eligible": true, "new_record": false})
	assert_bool(ok.header_chips.has("NOT RECORDED")).is_false()


func test_results_grade_panel_reward_brackets_on_record() -> void:
	var rec := _results_run(_score(10, 0, 0), {"eligible": true, "new_record": true, "previous_depth": -1.0})
	assert_str(rec.grade_panel_variant).is_equal("reward")
	var plain := _results_run(_score(10, 0, 0), {"eligible": true, "new_record": false})
	assert_str(plain.grade_panel_variant).is_equal("default")
	rec.skip_entrance()  # 02.2-16: the panels rise 16 px during the entrance
	assert_object(rec.grade_emblem.get_global_rect()).is_equal(Rect2(224, 280, 224, 224))


# --- GradeEmblem (UI-SPEC 4.13) -------------------------------------------------------------------


func _emblem(letter: String) -> GradeEmblem:
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var e := GradeEmblem.new()
	host.add_child(e)
	e.set_grade(letter)
	return e


func test_grade_emblem_geometry_and_colour() -> void:
	var e := _emblem("S")
	assert_object(e.size).is_equal(Vector2(224, 224))
	var pts := GradeEmblem.octagon_points(Rect2(0, 0, 224, 224), 48.0)
	assert_int(pts.size()).is_equal(8)
	assert_bool(pts.has(Vector2(48, 0))).is_true()
	assert_bool(pts.has(Vector2(224, 176))).is_true()
	assert_bool(e.grade_color().is_equal_approx(Palette.grade_color("S"))).is_true()
	assert_bool(e.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_float(e.glow_alpha()).is_equal_approx(0.30, 0.001)
	e.set_grade("B")
	assert_float(e.glow_alpha()).is_equal_approx(0.15, 0.001)
	assert_str(e.letter).is_equal("B")


func test_grade_emblem_pop_animation() -> void:
	var saved_rm: bool = Settings.reduce_motion
	var saved_low: bool = Settings.low_effects
	Settings.reduce_motion = false
	Settings.low_effects = false
	var e := _emblem("S")
	e.apply_effect_settings()
	e.play(0.2)
	assert_float(e.anim_alpha()).is_equal(0.0)
	e.step(0.2)
	assert_float(e.anim_scale()).is_equal_approx(1.6, 0.01)
	e.step(Palette.DUR_SLOW)
	assert_float(e.anim_scale()).is_equal_approx(1.0, 0.001)
	assert_float(e.anim_alpha()).is_equal_approx(1.0, 0.001)
	var c := e.effect_counts()
	assert_bool(c["glow"]).is_true()
	assert_bool(c["scale"]).is_true()
	assert_bool(c["ring"]).is_true()
	e.step(0.1)
	assert_bool(e.ring_active()).is_true()
	e.step(0.5)
	assert_bool(e.ring_active()).is_false()
	var a := _emblem("A")
	assert_bool(a.effect_counts()["ring"]).is_false()
	Settings.reduce_motion = saved_rm
	Settings.low_effects = saved_low


func test_grade_emblem_reduce_motion_and_low() -> void:
	var saved_rm: bool = Settings.reduce_motion
	var saved_low: bool = Settings.low_effects
	Settings.reduce_motion = true
	Settings.low_effects = true
	var e := _emblem("S")
	e.apply_effect_settings()
	e.play(0.2)
	e.step(0.2 + 0.09)
	assert_float(e.anim_scale()).is_equal(1.0)
	assert_float(e.anim_alpha()).is_equal_approx(0.5, 0.01)
	e.step(0.1)
	assert_float(e.anim_alpha()).is_equal_approx(1.0, 0.001)
	assert_bool(e.ring_active()).is_false()
	var c := e.effect_counts()
	assert_bool(c["glow"]).is_false()
	assert_bool(c["scale"]).is_false()
	assert_bool(c["ring"]).is_false()
	Settings.reduce_motion = saved_rm
	Settings.low_effects = saved_low


# --- 02.2-20: pause, IMPLOSION and confirm dialog in the design system (UI-SPEC 9.1, 9.2, 9.6) ---


func _host() -> Control:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	return host


func test_pause_panel_geometry_buttons_and_copy() -> void:
	var gp := _launch()
	await _frames(3)
	var pm: PauseMenu = gp.pause_menu
	pm.set_run_info("Sea Shanty 2", "expert", 42.6)
	pm.open()
	await _frames(2)
	assert_object(PauseMenu.PANEL_RECT).is_equal(Rect2(672, 288, 576, 504))
	var order: Array[Button] = [pm.resume_button, pm.restart_button, pm.settings_button, pm.menu_button]
	var texts := ["Resume Dive", "Restart Dive", "Settings", "Back to Menu"]
	var tops := [416.0, 488.0, 560.0, 632.0]
	for i in order.size():
		assert_str(order[i].text).is_equal(texts[i])
		assert_object(_rect_of(order[i])).is_equal(Rect2(704, tops[i], 512, 64))
	assert_str(String(pm.resume_button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_str(pm.title_label.text).is_equal("PAUSED")
	assert_int(pm.title_label.get_theme_font_size("font_size")).is_equal(Palette.SIZE_HEADING)
	assert_str(pm.run_label.text).is_equal("Sea Shanty 2 · EXPERT · 42%")
	assert_str(pm.hint_label.text).is_equal("ESC RESUME")
	assert_str(PauseMenu.run_line("A", "hard", 0.0)).is_equal("A · HARD · 0%")
	assert_str(PauseMenu.run_line("A", "hard", 100.0)).is_equal("A · HARD · 100%")
	# One focus marker that lives inside the pause panel (not over a dialog).
	assert_int(pm._panel_root.find_children("*", "FocusMarker", true, false).size()).is_equal(1)
	assert_bool(pm.resume_button.has_focus()).is_true()


func test_pause_countdown_numeral_and_ring() -> void:
	var host := _host()
	var pm := PauseMenu.new()
	host.add_child(pm)
	await _frames(1)
	var lbl: Label = pm.countdown_label
	assert_int(lbl.get_theme_font_size("font_size")).is_equal(Palette.SIZE_DISPLAY)
	assert_bool(lbl.get_global_rect().get_center().is_equal_approx(PauseMenu.COUNTDOWN_CENTER)).is_true()
	assert_float(PauseMenu.RING_R).is_equal(80.0)
	assert_float(PauseMenu.ring_fraction_at(0.0, 0.5)).is_equal_approx(1.0, 0.001)
	assert_float(PauseMenu.ring_fraction_at(0.25, 0.5)).is_equal_approx(0.5, 0.001)
	assert_float(PauseMenu.ring_fraction_at(0.9, 0.5)).is_equal(0.0)


func test_fail_screen_panel_title_progress_and_buttons() -> void:
	var host := _host()
	var f := FailScreen.new()
	host.add_child(f)
	f.setup(612.0, 17, 716.0, 37.4)
	await _frames(1)
	assert_object(FailScreen.PANEL_RECT).is_equal(Rect2(600, 240, 720, 600))
	assert_object(f.panel.get_global_rect()).is_equal(FailScreen.PANEL_RECT)
	assert_str(f.panel_variant).is_equal("danger")
	assert_str(f.title_label.text).is_equal("IMPLOSION")
	assert_int(f.title_label.get_theme_font_size("font_size")).is_equal(Palette.SIZE_DISPLAY)
	assert_bool(f.title_label.get_theme_color("font_color").is_equal_approx(Palette.WARNING_RED)).is_true()
	assert_float(f.title_label.get_global_rect().get_center().x).is_equal_approx(960.0, 1.0)
	assert_str(f.progress_label.text).is_equal("SONG PROGRESS 37%")
	assert_float(f.progress_fill_width()).is_equal_approx(560.0 * 0.374, 0.5)
	assert_object(_rect_of(f.retry_button)).is_equal(Rect2(680, 664, 560, 64))
	assert_object(_rect_of(f.menu_button)).is_equal(Rect2(680, 744, 560, 64))
	assert_str(String(f.retry_button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_str(f.retry_button.text).is_equal("Retry Dive")
	assert_str(f.menu_button.text).is_equal("Back to Menu")
	assert_int(f.find_children("*", "FocusMarker", true, false).size()).is_equal(1)
	# Kept copy and the old 3-argument setup.
	assert_str(f.body_label.text).is_equal("Hull breached at 612 m.")
	var g := FailScreen.new()
	host.add_child(g)
	g.setup(5.0)
	assert_str(g.body_label.text).is_equal("Hull breached at 5 m.")


func test_fail_screen_cracks_shake_and_effects() -> void:
	var cracks := FailScreen.crack_lines()
	assert_int(cracks.size()).is_equal(6)
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1920, 0), Vector2(0, 1080), Vector2(1920, 1080)]
	for line: PackedVector2Array in cracks:
		assert_int(line.size()).is_greater_equal(4)
		var start := line[0]
		var nearest := 1e9
		for c in corners:
			nearest = minf(nearest, start.distance_to(c))
		assert_float(nearest).is_less_equal(1.0)
		for p in line:
			assert_float(p.distance_to(start)).is_less_equal(360.0)
	assert_bool(FailScreen.crack_lines() == cracks).is_true()  # static, same every time
	assert_float(FailScreen.SHAKE_SEC).is_equal_approx(0.12, 0.0001)
	var peak := 0.0
	for i in 12:
		peak = maxf(peak, absf(FailScreen.shake_offset(i * 0.01)))
	assert_float(peak).is_less_equal(8.0)
	assert_float(peak).is_greater(4.0)
	assert_float(FailScreen.shake_offset(0.12)).is_equal(0.0)
	var saved_rm: bool = Settings.reduce_motion
	var saved_low: bool = Settings.low_effects
	var host := _host()
	var f := FailScreen.new()
	host.add_child(f)
	f.setup(10.0, 1, -1.0, 20.0)
	Settings.reduce_motion = false
	Settings.low_effects = false
	f.apply_effect_settings()
	assert_bool(f.is_in_group(UiKit.FX_GROUP)).is_true()
	var c := f.effect_counts()
	assert_bool(c["shake"]).is_true()
	assert_bool(c["glow"]).is_true()
	assert_bool(c["cracks"]).is_true()
	assert_int(f.title_label.get_theme_constant("outline_size")).is_equal(12)
	Settings.low_effects = true
	f.apply_effect_settings()
	assert_bool(f.effect_counts()["glow"]).is_false()
	assert_int(f.title_label.get_theme_constant("outline_size")).is_equal(0)
	assert_bool(f.effect_counts()["cracks"]).is_true()
	Settings.reduce_motion = true
	f.apply_effect_settings()
	assert_bool(f.effect_counts()["shake"]).is_false()
	Settings.reduce_motion = saved_rm
	Settings.low_effects = saved_low
	f.apply_effect_settings()


func test_fail_screen_buttons_inert_until_visible() -> void:
	var host := _host()
	var f := FailScreen.new()
	host.add_child(f)
	f.setup(10.0, 1, -1.0, 50.0)
	f.play(0.05)
	assert_bool(f.retry_button.disabled).is_true()
	assert_bool(f.menu_button.disabled).is_true()
	await _wait_sec(0.6)
	assert_bool(f.retry_button.disabled).is_false()
	assert_bool(f.retry_button.has_focus()).is_true()
	assert_float(f.title_label.position.x).is_equal_approx(f.title_rest_x(), 0.01)


func _wait_sec(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func test_confirm_dialog_geometry_variants_and_focus() -> void:
	var host := _host()
	var dlg := ConfirmDialog.new()
	host.add_child(dlg)
	dlg.setup("BACK TO MENU", "Leave this dive? Your progress will be lost.", "Leave Dive", "Stay")
	await _frames(2)
	assert_object(ConfirmDialog.PANEL_RECT).is_equal(Rect2(600, 380, 720, 320))
	assert_object(_rect_of(dlg.confirm_button)).is_equal(Rect2(632, 604, 304, 64))
	assert_object(_rect_of(dlg.safe_button)).is_equal(Rect2(984, 604, 304, 64))
	assert_str(String(dlg.confirm_button.get_meta(&"ui_variant", ""))).is_equal("destructive")
	assert_str(String(dlg.safe_button.get_meta(&"ui_variant", "default"))).is_equal("default")
	assert_bool(dlg.safe_button.has_focus()).is_true()
	assert_str(dlg.title_label.text).is_equal("BACK TO MENU")
	assert_int(dlg.title_label.get_theme_font_size("font_size")).is_equal(Palette.SIZE_HEADING)
	assert_float(dlg.body_label.size.x).is_equal(656.0)
	assert_float(dlg.body_label.position.x).is_equal(632.0)
	assert_int(dlg.body_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_bool(dlg.body_label.get_theme_color("font_color").is_equal_approx(Palette.TEXT_MID)).is_true()
	assert_int(dlg.find_children("*", "FocusMarker", true, false).size()).is_equal(1)


func test_pause_run_line_skips_an_empty_difficulty() -> void:
	assert_str(PauseMenu.run_line("Hand chart", "", 16.2)).is_equal("Hand chart · 16%")
	assert_str(PauseMenu.run_line("", "expert", 3.0)).is_equal("EXPERT · 3%")


# --- 04-07: HOST LEFT / CONNECTION LOST dialog (04-UI-SPEC 11.6, 16) ---


func test_host_left_dialog_fills_viewport_panel_and_button_rects() -> void:
	var host := _host()
	var dlg := HostLeftDialog.new()
	host.add_child(dlg)
	dlg.setup("connection_lost", "MAKO", [
		{"place": 1, "name": "MAKO", "is_you": false, "is_host": true, "status": "hull", "hull_pct": 60.0},
		{"place": 2, "name": "DIVER", "is_you": true, "is_host": false, "status": "wreck", "hull_pct": 0.0}])
	dlg.step(1.0)  # past the rise
	await _frames(2)
	_assert_full(dlg)
	_assert_dim(dlg, 0.85)
	_assert_dim_colour(dlg, Palette.ABYSS_900)
	assert_int(dlg.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(HostLeftDialog.PANEL_RECT).is_equal(Rect2(480, 240, 960, 600))
	assert_object(dlg.panel.get_global_rect()).is_equal(Rect2(480, 240, 960, 600))
	assert_object(_rect_of(dlg.button)).is_equal(Rect2(512, 744, 400, 64))
	assert_object(HostLeftDialog.BUTTON_RECT).is_equal(Rect2(512, 744, 400, 64))
	_assert_centered(dlg.panel)
	assert_bool(dlg.button.has_focus()).is_true()
	assert_str(String(dlg.button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_array(HostLeftDialog.ROW_TOPS).is_equal([456.0, 520.0, 584.0, 648.0])
