extends GdUnitTestSuite
## 03-12 Task 2: VersusResultsScreen (03-UI-SPEC 9.4, MATCH-05, spec req 13, D-23).

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


func _rows() -> Array:
	# Deliberately out of placement order: the screen sorts by place.
	return [
		{"seat": 2, "place": 3, "alive": false, "depth": 400.0, "hull": 0.0, "accuracy": 0.81,
			"eliminated_at": 83.4, "name": "ORCA", "landed": 1, "reflected": 0},
		{"seat": 0, "place": 1, "alive": true, "depth": 1200.0, "hull": 88.0, "accuracy": 0.984,
			"eliminated_at": INF, "name": "YOU", "landed": 4, "reflected": 2},
		{"seat": 3, "place": 4, "alive": false, "depth": 200.0, "hull": 0.0, "accuracy": -1.0,
			"eliminated_at": 40.0, "name": "BARRACUDA", "landed": 0, "reflected": 0},
		{"seat": 1, "place": 2, "alive": true, "depth": 1100.0, "hull": 62.0, "accuracy": 0.9,
			"eliminated_at": INF, "name": "MAKO", "landed": 3, "reflected": 1},
	]


func _data(rows: Array = _rows(), medals: Dictionary = {0: ["shredder", "head_on"]},
		last_seat: int = 0) -> Dictionary:
	return {"rows": rows, "local_seat": 0, "medals": medals, "title": "Sea Shanty 2", "artist": "Jagex",
		"difficulty": "expert", "seed": 123456, "last_standing_seat": last_seat}


func _screen(data: Dictionary = _data()) -> VersusResultsScreen:
	var host := Control.new()
	UiLayout.fill_rect(host)
	add_child(host)
	auto_free(host)
	var r := VersusResultsScreen.new()
	host.add_child(r)
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


func _label_color(l: Label) -> Color:
	return l.get_theme_color("font_color")


func test_header_headline_not_recorded_and_seed() -> void:
	var r := _screen()
	assert_str(r.headline_text()).is_equal("YOU WIN")
	assert_object(r.headline_color()).is_equal(Palette.REWARD_GOLD)
	assert_object(_find_text(r, "MATCH COMPLETE")).is_not_null()
	assert_object(_find_text(r, "SEED 123456")).is_not_null()
	assert_object(_find_text(r, "Versus matches do not set records.")).is_not_null()
	var found := false
	for n in r.find_children("Chip*", "", true, false):
		if n.get_meta(&"text", "") == "NOT RECORDED":
			found = true
	assert_bool(found).is_true()
	assert_bool(r.backdrop_opaque()).is_true()


func test_rows_in_placement_order_with_statuses() -> void:
	var r := _screen()
	assert_int(r.row_count()).is_equal(4)
	var names: Array[String] = []
	for i in 4:
		names.append(r.row_texts(i)["name"])
	assert_array(names).is_equal(["YOU", "MAKO", "ORCA", "BARRACUDA"])
	assert_str(r.row_texts(0)["place"]).is_equal("1ST")
	assert_str(r.row_texts(0)["status"]).is_equal("LAST HULL STANDING")
	assert_str(r.row_texts(1)["status"]).is_equal("SURVIVED · HULL 62%")
	assert_str(r.row_texts(2)["status"]).is_equal("IMPLODED AT 1:23")
	assert_object(r.row_texts(2)["status_color"]).is_equal(Palette.WARNING_RED)
	assert_str(r.row_texts(3)["status"]).is_equal("IMPLODED AT 0:40")
	assert_str(r.row_texts(0)["accuracy"]).is_equal("98.4%")
	assert_str(r.row_texts(3)["accuracy"]).is_equal("--.-%")
	assert_str(r.row_texts(0)["depth"]).is_equal(Palette.fmt_depth(1200))
	assert_str(r.row_texts(0)["landed"]).is_equal("4")
	assert_str(r.row_texts(0)["reflected"]).is_equal("2")
	assert_str(r.row_texts(1)["landed"]).is_equal("3")
	# 1ST is gold, other places TEXT_HI.
	var place1 := r.row_group(0).find_child("Place", true, false) as Label
	var place2 := r.row_group(1).find_child("Place", true, false) as Label
	assert_object(_label_color(place1)).is_equal(Palette.REWARD_GOLD)
	assert_object(_label_color(place2)).is_equal(Palette.TEXT_HI)


func test_survived_status_when_not_last_standing() -> void:
	var r := _screen(_data(_rows(), {}, -1))
	assert_str(r.row_texts(0)["status"]).is_equal("SURVIVED · HULL 88%")


func test_you_row_highlight() -> void:
	var r := _screen()
	assert_int(r.you_row).is_equal(0)
	assert_bool(r.row_texts(0)["you"]).is_true()
	assert_bool(r.row_texts(1)["you"]).is_false()
	var chrome := r.row_group(0).find_child("Chrome", true, false)
	assert_bool(chrome.get_meta(&"you")).is_true()
	assert_bool(r.row_group(1).find_child("Chrome", true, false).get_meta(&"you")).is_false()
	assert_float(VersusResultsScreen.YOU_BAR_W).is_equal(4.0)


func test_draw_and_other_winner_headlines() -> void:
	var rows := _rows()
	rows[3]["place"] = 1  # MAKO shares first place
	assert_str(_screen(_data(rows)).headline_text()).is_equal("DRAW")
	var rows2 := _rows()
	rows2[1]["place"] = 2
	rows2[3]["place"] = 1
	var r := _screen(_data(rows2, {}, 1))
	assert_str(r.headline_text()).is_equal("MAKO WINS")
	assert_object(r.headline_color()).is_equal(Palette.TEXT_HI)


func test_medal_badges_and_legend() -> void:
	var r := _screen()
	assert_array(r.medal_names(0)).is_equal(["SHREDDER", "HEAD-ON"])
	assert_array(r.medal_columns(0)).is_equal([1264.0, 1444.0])
	var badge := (r.medal_nodes(0)[0] as Node).find_child("Badge", true, false)
	assert_str(badge.get_meta(&"glyph")).is_equal("medal_shredder")
	assert_array(r.medal_names(1)).is_empty()
	assert_object(r.row_group(1).find_child("NoMedals", true, false)).is_not_null()
	assert_array(r.legend_lines()).is_equal(["SHREDDER: won a Solo Duel.",
		"HEAD-ON: your torpedo collided with a rival's."])
	assert_object(_find_text(r, "YOUR MEDALS")).is_not_null()


func test_three_medals_max_and_empty_legend() -> void:
	var r := _screen(_data(_rows(), {1: ["untouchable", "uno_reverse", "bounty_hunter", "grudge"]}))
	assert_array(r.medal_names(1)).is_equal(["UNTOUCHABLE", "UNO REVERSE", "BOUNTY HUNTER"])
	assert_array(r.medal_columns(1)).is_equal([1264.0, 1444.0, 1624.0])
	assert_array(r.legend_lines()).is_equal([VersusResultsScreen.NO_MEDALS_TEXT])


func test_buttons_focus_loop_and_signals() -> void:
	var r := _screen()
	await await_idle_frame()
	var b := r.focus_buttons()
	assert_array(b.map(func(x: Button) -> String: return x.text)).is_equal(["Rematch", "Change Match", "Back to Menu"])
	assert_bool(r.rematch_button.has_focus()).is_true()
	for i in 3:
		assert_object(b[i].get_node(b[i].focus_neighbor_right)).is_same(b[(i + 1) % 3])
		assert_object(b[i].get_node(b[i].focus_neighbor_left)).is_same(b[(i + 2) % 3])
		assert_object(b[i].get_node(b[i].focus_neighbor_bottom)).is_same(b[(i + 1) % 3])
	var got: Array[String] = []
	r.rematch_pressed.connect(func() -> void: got.append("rematch"))
	r.change_match_pressed.connect(func() -> void: got.append("change"))
	r.menu_pressed.connect(func() -> void: got.append("menu"))
	for x in b:
		x.pressed.emit()
	assert_array(got).is_equal(["rematch", "change", "menu"])
	# Only the three buttons take focus.
	var focusable := r.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c.focus_mode != Control.FOCUS_NONE)
	assert_int(focusable.size()).is_equal(3)


func test_escape_is_back_to_menu() -> void:
	var r := _screen()
	await await_idle_frame()
	r.skip_entrance()
	var got: Array[int] = []
	r.menu_pressed.connect(func() -> void: got.append(1))
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	r._unhandled_input(ev)
	assert_array(got).has_size(1)


func test_entrance_within_budget_and_skip() -> void:
	assert_float(VersusResultsScreen.ENTRANCE_SEC).is_less_equal(0.9)
	var r := _screen()
	await await_idle_frame()
	assert_bool(r.entrance_running()).is_true()
	r.apply_entrance(0.0)
	assert_float(r.header_group().modulate.a).is_equal(0.0)
	assert_float(r.row_group(0).position.y).is_equal(VersusResultsScreen.ROW_RISE)
	var m := r.medal_nodes(0)[0] as Control
	assert_float(m.modulate.a).is_equal(0.0)
	var key := InputEventKey.new()
	key.keycode = KEY_X
	key.pressed = true
	r._input(key)
	assert_bool(r.entrance_running()).is_false()
	assert_float(r.header_group().modulate.a).is_equal(1.0)
	for i in 4:
		assert_float(r.row_group(i).modulate.a).is_equal(1.0)
		assert_float(r.row_group(i).position.y).is_equal(0.0)
	assert_float(m.modulate.a).is_equal(1.0)
	assert_vector(m.scale).is_equal_approx(Vector2.ONE, Vector2(0.001, 0.001))
	assert_bool(r.winner_glow().visible).is_true()


func test_entrance_finishes_by_itself() -> void:
	var r := _screen()
	var end := Time.get_ticks_msec() + 1500
	while r.entrance_running() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	assert_bool(r.entrance_running()).is_false()


func test_reduce_motion_fades_only() -> void:
	Settings.reduce_motion = true
	var r := _screen()
	await await_idle_frame()
	r.apply_entrance(VersusResultsScreen.MEDALS_AT + 0.05)
	assert_float(r.row_group(0).position.y).is_equal(0.0)
	var m := r.medal_nodes(0)[0] as Control
	assert_vector(m.scale).is_equal(Vector2.ONE)
	assert_float(m.modulate.a).is_between(0.01, 0.99)
	assert_bool(r.effect_counts()["rise"]).is_false()
	assert_bool(r.effect_counts()["medal_pop"]).is_false()


func test_low_effects_no_glow() -> void:
	Settings.low_effects = true
	var r := _screen()
	await await_idle_frame()
	r.skip_entrance()
	assert_bool(r.winner_glow().visible).is_false()
	assert_bool(r.effect_counts()["glow"]).is_false()
	assert_bool(r.is_in_group(UiKit.FX_GROUP)).is_true()


func test_medal_pop_scales_down_from_1_4() -> void:
	var r := _screen()
	await await_idle_frame()
	r.apply_entrance(VersusResultsScreen.MEDALS_AT)
	var m := r.medal_nodes(0)[0] as Control
	assert_float(m.scale.x).is_equal_approx(1.4, 0.001)
