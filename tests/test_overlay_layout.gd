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


func after_test() -> void:
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false


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
	_assert_dim(fs, 0.7)
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
	_assert_dim(rs, 0.85)
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
