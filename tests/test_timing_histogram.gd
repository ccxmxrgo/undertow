extends GdUnitTestSuite
## 02.2-16 (VIS-05, D-09, UI-SPEC 4.12 / 8): the results timing histogram and the skippable
## results entrance. A fake run with known offsets must produce the expected bins, colours,
## summary and geometry; any input during the entrance jumps to the final state and is consumed.

const FAKE: Array[float] = [-0.068, -0.012, -0.011, 0.0, 0.004, 0.033, 0.070, 0.2]

var _saved_rm: bool
var _saved_low: bool


func before_test() -> void:
	_saved_rm = Settings.reduce_motion
	_saved_low = Settings.low_effects
	Settings.reduce_motion = false
	Settings.low_effects = false


func after_test() -> void:
	Settings.reduce_motion = _saved_rm
	Settings.low_effects = _saved_low


func _offsets(values: Array[float] = FAKE) -> PackedFloat32Array:
	return PackedFloat32Array(values)


func _hist(values: Array[float] = FAKE, pw: float = 0.035) -> TimingHistogram:
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var h := TimingHistogram.new()
	host.add_child(h)
	h.set_offsets(_offsets(values), pw)
	h.grow(1.0)
	return h


func _label_texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			out.append((c as Label).text)
	return out


func _find_label(n: Node, text: String) -> Label:
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).text == text:
			return c as Label
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- bins, heights, colours ----------------------------------------------------------------------


func test_fake_run_bins_match_expected() -> void:
	var h := _hist()
	var expect := PackedInt32Array()
	expect.resize(28)
	expect.fill(0)
	expect[0] = 1
	expect[11] = 2
	expect[14] = 2
	expect[20] = 1
	expect[27] = 2
	assert_array(Array(h.bins)).is_equal(Array(expect))
	assert_array(Array(h.bins)).is_equal(Array(RunStats.histogram(_offsets())))
	# Heights: count / max * 300 (max = 2).
	for i in 28:
		assert_float(h.bar_height(i)).override_failure_message("bin %d" % i) \
			.is_equal_approx(float(expect[i]) / 2.0 * 300.0, 0.001)


func test_bar_geometry_and_centre_line() -> void:
	var h := _hist()
	for i in 28:
		var hh := h.bar_height(i)
		assert_object(h.bar_rect(i)).override_failure_message("bin %d" % i) \
			.is_equal(Rect2(1314.0 + 17.0 * i, 600.0 - hh, 13.0, hh))
	assert_float(TimingHistogram.CENTER_X).is_equal(1552.0)
	assert_float(TimingHistogram.BASELINE_Y).is_equal(600.0)
	assert_float(TimingHistogram.CHART_X + 28 * 17.0 - 4.0).is_equal(1790.0)
	# Placed in the timing panel at the 1920x1080 layout.
	assert_object(h.get_global_rect()).is_equal(Rect2(1280, 208, 544, 480))


func test_colour_split_reads_perfect_window() -> void:
	var h := _hist()
	for i in 28:
		var inside := i >= 7 and i <= 20  # bins fully inside -35..+35 ms
		var want := Palette.SONAR_PALE if inside else Palette.TEXT_MID
		assert_bool(h.bar_color(i).is_equal_approx(want)).override_failure_message("bin %d" % i).is_true()
	var g := h.guide_xs()
	assert_int(g.size()).is_equal(2)
	assert_float(g[0]).is_less(1552.0)
	assert_float(g[1]).is_greater(1552.0)
	assert_float(1552.0 - g[0]).is_equal_approx(g[1] - 1552.0, 0.001)
	# A different window moves both the colour split and the guides (never hard-coded).
	var narrow := _hist(FAKE, 0.020)
	for i in 28:
		var inside := i >= 10 and i <= 17
		var want := Palette.SONAR_PALE if inside else Palette.TEXT_MID
		assert_bool(narrow.bar_color(i).is_equal_approx(want)).override_failure_message("narrow bin %d" % i).is_true()
	assert_float(narrow.guide_xs()[1]).is_less(g[1])
	# Default window comes from JudgeConfig.
	var d := TimingHistogram.new()
	auto_free(d)
	d.set_offsets(_offsets())
	assert_float(d.perfect_window).is_equal(JudgeConfig.new().perfect_window)


func test_axis_labels_and_summary() -> void:
	var h := _hist()
	var t := _label_texts(h)
	for s in ["-70", "0", "+70", "EARLY", "LATE"]:
		assert_bool(t.has(s)).override_failure_message("missing " + s).is_true()
	var want := RunStats.summary_text(RunStats.mean_offset_ms(_offsets()))
	assert_str(h.summary).is_equal(want)
	assert_bool(t.has(want)).is_true()
	assert_bool(t.has(TimingHistogram.EMPTY_TEXT)).is_false()
	# Axis anchors: "-70" left at 1314, "+70" right-aligned at 1790, "0" centred at 1552.
	var lo := _find_label(h, "-70").get_global_rect()
	var hi := _find_label(h, "+70").get_global_rect()
	var zero := _find_label(h, "0").get_global_rect()
	assert_float(lo.position.x).is_equal_approx(1314.0, 0.5)
	assert_float(hi.end.x).is_equal_approx(1790.0, 1.0)
	assert_float(zero.get_center().x).is_equal_approx(1552.0, 1.0)


func test_empty_state() -> void:
	var h := _hist([])
	assert_bool(h.is_empty()).is_true()
	var t := _label_texts(h)
	assert_bool(t.has("No hits to chart.")).is_true()
	assert_str(TimingHistogram.EMPTY_TEXT).is_equal("No hits to chart.")
	for i in 28:
		assert_float(h.bar_height(i)).is_equal(0.0)
	assert_str(h.summary).is_equal("")
	var e := _find_label(h, "No hits to chart.").get_global_rect()
	assert_float(e.get_center().x).is_equal_approx(1552.0, 1.0)
	assert_float(e.get_center().y).is_between(400.0, 500.0)


func test_grow_staggers_left_to_right() -> void:
	var h := _hist()
	h.grow(0.0)
	for i in 28:
		assert_float(h.bar_rect(i).size.y).is_equal(0.0)
	h.grow(0.5)
	assert_float(h.bar_factor(0)).is_greater(h.bar_factor(27))
	h.grow(1.0)
	for i in 28:
		assert_float(h.bar_rect(i).size.y).is_equal_approx(h.bar_height(i), 0.001)
	assert_float(TimingHistogram.GROW_SEC).is_equal_approx(Palette.DUR_SLOW + 27 * 0.01, 0.0001)
	assert_bool(h.is_in_group(UiKit.FX_GROUP)).is_true()


func test_reduce_motion_grows_by_fade_only() -> void:
	Settings.reduce_motion = true
	var h := _hist()
	h.apply_effect_settings()
	h.grow(0.5)
	# No height growth or stagger: every bar is at full height, the chart fades in.
	assert_float(h.bar_factor(0)).is_equal(1.0)
	assert_float(h.bar_factor(27)).is_equal(1.0)
	assert_float(h.modulate.a).is_equal_approx(0.5, 0.001)
	assert_bool(h.effect_counts()["stagger"]).is_false()


# --- results integration and the entrance --------------------------------------------------------


func _score(p: int, gd: int, m: int) -> HullScore:
	var s := HullScore.new(JudgeConfig.new())
	s.perfect_count = p
	s.good_count = gd
	s.miss_count = m
	s.max_combo = p
	s.hull = 80.0
	return s


func _results(offsets: PackedFloat32Array, pw: float = 0.035) -> ResultsScreen:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var r := ResultsScreen.new()
	host.add_child(r)
	r.setup(_score(6, 2, 1), false, {"eligible": true, "new_record": true, "previous_depth": -1.0}, false,
		{"title": "Fake", "artist": "Run", "difficulty": "expert", "offsets": offsets, "perfect_window": pw})
	return r


func test_results_hosts_histogram_in_timing_panel() -> void:
	var r := _results(_offsets())
	assert_object(r.histogram).is_not_null()
	assert_array(Array(r.histogram.bins)).is_equal(Array(RunStats.histogram(_offsets())))
	assert_float(r.histogram.perfect_window).is_equal(0.035)
	r.skip_entrance()
	assert_object(r.histogram.get_global_rect()).is_equal(Rect2(1280, 208, 544, 480))
	var empty := _results(PackedFloat32Array())
	assert_bool(empty.histogram.is_empty()).is_true()


func test_entrance_timeline_and_total() -> void:
	assert_float(ResultsScreen.ENTRANCE_SEC).is_less_equal(0.9)
	var r := _results(_offsets())
	assert_bool(r.entrance_running()).is_true()
	r.apply_entrance(0.0)
	# Panels start transparent and 16 px low, the bars and histogram empty.
	for gp in r.panel_groups:
		assert_float(gp.modulate.a).is_equal(0.0)
		assert_float(gp.position.y).is_equal(16.0)
	assert_float(r.bar_fill(0)).is_equal(0.0)
	assert_float(r.histogram.bar_factor(14)).is_equal(0.0)
	# Panels stagger 60 ms: the grade panel moves before the timing panel.
	r.apply_entrance(0.1)
	assert_float(r.panel_groups[0].modulate.a).is_greater(r.panel_groups[2].modulate.a)
	r.apply_entrance(ResultsScreen.ENTRANCE_SEC)
	for gp in r.panel_groups:
		assert_float(gp.modulate.a).is_equal(1.0)
		assert_float(gp.position.y).is_equal(0.0)
	for i in 3:
		assert_float(r.bar_fill(i)).is_equal_approx(r.bar_widths[i], 0.001)
	assert_float(r.histogram.bar_factor(27)).is_equal(1.0)


func test_entrance_finishes_by_itself() -> void:
	var r := _results(_offsets())
	await get_tree().create_timer(ResultsScreen.ENTRANCE_SEC + 0.2).timeout
	assert_bool(r.entrance_running()).is_false()
	assert_float(r.histogram.bar_factor(27)).is_equal(1.0)
	assert_float(r.panel_groups[2].position.y).is_equal(0.0)


func test_any_key_skips_entrance_and_is_consumed() -> void:
	var r := _results(_offsets())
	await _frames(2)
	assert_bool(r.entrance_running()).is_true()
	assert_bool(r.retry_button.has_focus()).is_true()
	var got: Array[String] = []
	r.retry_pressed.connect(func() -> void: got.append("retry"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	# Enter on the focused Retry Dive during the entrance only skips.
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		ev.pressed = pressed
		get_viewport().push_input(ev)
		await _frames(1)
	assert_bool(r.entrance_running()).is_false()
	assert_array(got).is_empty()
	for gp in r.panel_groups:
		assert_float(gp.modulate.a).is_equal(1.0)
		assert_float(gp.position.y).is_equal(0.0)
	assert_float(r.histogram.bar_factor(0)).is_equal(1.0)
	assert_float(r.bar_fill(0)).is_equal_approx(r.bar_widths[0], 0.001)
	assert_bool(r.grade_emblem.is_playing()).is_false()
	assert_float(r.grade_emblem.anim_alpha()).is_equal(1.0)
	# After the skip, Enter activates the button as usual.
	for pressed: bool in [true, false]:
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_ENTER
		ev2.physical_keycode = KEY_ENTER
		ev2.pressed = pressed
		get_viewport().push_input(ev2)
		await _frames(1)
	assert_array(got).is_equal(["retry"])


func test_joypad_and_esc_skip_without_acting() -> void:
	var r := _results(_offsets())
	await _frames(1)
	var got: Array[String] = []
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	get_viewport().push_input(esc)
	await _frames(1)
	assert_bool(r.entrance_running()).is_false()
	assert_array(got).is_empty()
	var r2 := _results(_offsets())
	await _frames(1)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	get_viewport().push_input(jb)
	await _frames(1)
	assert_bool(r2.entrance_running()).is_false()


func test_entrance_reduce_motion_fades_only() -> void:
	Settings.reduce_motion = true
	var r := _results(_offsets())
	r.apply_entrance(0.0)
	for gp in r.panel_groups:
		assert_float(gp.position.y).is_equal(0.0)
		assert_float(gp.modulate.a).is_equal(0.0)
	# Bars appear at full width and fade in.
	r.apply_entrance(0.5)
	assert_float(r.bar_fill(0)).is_equal_approx(r.bar_widths[0], 0.001)
	assert_float(r.histogram.bar_factor(14)).is_equal(1.0)
	assert_bool(r.effect_counts()["rise"]).is_false()
