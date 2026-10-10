extends GdUnitTestSuite
## Settings screen: rebinding, duplicate/Tab rejection, reset, slider persistence, overlay mode
## (plan 07 task 1) and main menu wiring (task 2).

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const TEST_PATH := "user://test_menu_flow.cfg"

const SCORES_TMP := "user://test_menu_scores.cfg"

var _old_path: String
var _old_scores_path: String


func before_test() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	Settings.reset_defaults()
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP
	MainMenu.records_error_shown = false
	_rm_scores()


func _rm_scores() -> void:
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func after_test() -> void:
	SongSelect.run_autoplay = false
	SongSelect.run_practice = false
	ScoreStore.default_path = _old_scores_path
	MainMenu.records_error_shown = false
	_rm_scores()
	Settings.reset_defaults()
	Settings.save_path = _old_path
	for p in [TEST_PATH, TEST_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _screen(overlay: bool = false) -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.overlay = overlay
	add_child(s)
	auto_free(s)
	return s


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = true
	return e


func test_has_all_seven_actions_with_defaults() -> void:
	var s := _screen()
	assert_int(s.cells.size()).is_equal(14)
	assert_bool(s.cells["lane_1:keyboard"].text == "1").is_true()
	assert_bool(s.cells["lane_1:gamepad"].text == "LB").is_true()
	assert_bool(s.cells["fire:keyboard"].text == "Space").is_true()


func test_rebind_lane1_to_free_key() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	assert_str(cell.text).is_equal("PRESS A KEY")
	assert_bool(cell.handle_event(_key(KEY_G))).is_true()
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("G")
	assert_str(Settings.bindings.display_name(&"lane_1", &"keyboard")).is_equal("G")


func test_duplicate_rejected_with_copy_and_unchanged() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_2))  # Lane 2 default
	assert_str(s.message_text(&"lane_1")).is_equal("! 2 is already used for Lane 2. Pick a different key.")
	assert_str(cell.text).is_equal("1")
	assert_bool(cell.listening).is_false()


func test_tab_rejected() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_TAB))
	assert_str(s.message_text(&"lane_1")).is_equal("! Tab can't be used. It is reserved for menus.")
	assert_str(cell.text).is_equal("1")


func test_escape_cancels_without_change() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_2:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_ESCAPE))
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("2")
	assert_str(s.message_text(&"lane_2")).is_equal("")


func test_gamepad_stick_ignored_trigger_accepted() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["fire:gamepad"]
	cell.begin_listen()
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	assert_bool(cell.handle_event(stick)).is_false()
	assert_bool(cell.listening).is_true()
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_TRIGGER_LEFT
	weak.axis_value = 0.3
	assert_bool(cell.handle_event(weak)).is_false()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_X
	b.pressed = true
	assert_bool(cell.handle_event(b)).is_true()
	assert_str(cell.text).is_equal("X")


func test_gamepad_b_cancels() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["fire:gamepad"]
	cell.begin_listen()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	cell.handle_event(b)
	assert_bool(cell.listening).is_false()
	assert_str(cell.text).is_equal("A")


func test_reset_controls_restores_defaults() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_G))
	assert_str(cell.text).is_equal("G")
	s.request_reset()
	assert_object(s.dialog).is_not_null()
	s.dialog.confirmed.emit()
	assert_str(s.cells["lane_1:keyboard"].text).is_equal("1")
	assert_object(s.dialog).is_null()


func test_reset_dialog_keep_bindings_changes_nothing() -> void:
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	cell.handle_event(_key(KEY_G))
	s.request_reset()
	s.dialog.cancelled.emit()
	assert_str(cell.text).is_equal("G")


func test_slider_changes_persist_to_settings() -> void:
	var s := _screen()
	s.scroll_slider.set_value(2.5)
	assert_float(Settings.scroll_speed).is_equal_approx(2.5, 0.0001)
	s.master_slider.set_value(50.0)
	assert_float(Settings.volume_master).is_equal_approx(0.5, 0.0001)
	s.sfx_slider.step_by(-1)
	assert_float(Settings.volume_sfx).is_equal_approx(0.75, 0.0001)
	s.no_fail_button.pressed.emit()
	assert_bool(Settings.no_fail).is_true()
	assert_str(s.no_fail_button.text).is_equal("ON")
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TEST_PATH)).is_equal(OK)
	assert_float(float(cfg.get_value("gameplay", "scroll_speed"))).is_equal_approx(2.5, 0.0001)
	assert_bool(bool(cfg.get_value("gameplay", "no_fail"))).is_true()


func test_overlay_back_emits_closed_and_keeps_scene() -> void:
	var s := _screen(true)
	var scene_before := get_tree().current_scene
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	var closed_count := [0]
	s.closed.connect(func() -> void: closed_count[0] += 1)
	s.back_pressed()
	assert_int(closed_count[0]).is_equal(1)
	assert_int(calls.size()).is_equal(0)
	assert_bool(get_tree().current_scene == scene_before).is_true()
	assert_bool(s.recalibrate_button.disabled).is_true()


func test_full_mode_back_goes_to_main_menu() -> void:
	var s := _screen(false)
	var calls: Array = []
	s.navigate = func(p: String) -> void: calls.append(p)
	s.back_pressed()
	assert_array(calls).is_equal(["res://scenes/main_menu.tscn"])


func test_initial_focus_set_in_code() -> void:
	var s := _screen()
	await get_tree().process_frame
	assert_bool(s.cells["lane_1:keyboard"].has_focus()).is_true()


func _main_menu() -> MainMenu:
	MainMenu.boot_handled = true
	var m: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(m)
	auto_free(m)
	return m


func test_practice_button_directly_under_start() -> void:
	var m := _main_menu()
	assert_str(m.practice_button.text).is_equal("Practice Dive (No-Fail)")
	assert_int(m.practice_button.get_index()).is_equal(m.start_button.get_index() + 1)
	assert_bool(m.start_button.get_node(m.start_button.focus_neighbor_bottom) == m.practice_button).is_true()
	assert_bool(m.practice_button.get_node(m.practice_button.focus_neighbor_top) == m.start_button).is_true()
	assert_bool(m.start_button.has_focus()).is_true()


func test_launch_practice_sets_run_flags_and_keeps_no_fail_setting() -> void:
	var m := _main_menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	Settings.no_fail = false
	m.launch_practice()
	assert_bool(SongSelect.run_practice).is_true()
	assert_bool(SongSelect.run_autoplay).is_false()
	assert_array(calls).is_equal([MainMenu.SONG_SELECT_SCENE])
	assert_bool(Settings.no_fail).is_false()
	m.launch(false)
	assert_bool(SongSelect.run_practice).is_false()
	SongSelect.run_practice = false
	MainMenu.boot_handled = false


func test_launch_opens_song_select_and_does_not_preset_chart() -> void:
	var m := _main_menu()
	var calls: Array = []
	m.navigate = func(p: String) -> void: calls.append(p)
	Gameplay.pending_chart = null
	m.launch(true)
	assert_array(calls).is_equal(["res://scenes/song_select.tscn"])
	assert_bool(SongSelect.run_autoplay).is_true()
	assert_bool(SongSelect.run_practice).is_false()
	assert_object(Gameplay.pending_chart).is_null()
	m.launch(false)
	assert_bool(SongSelect.run_autoplay).is_false()
	assert_object(Gameplay.pending_chart).is_null()
	assert_int(calls.size()).is_equal(2)
	MainMenu.boot_handled = false


func test_item_order_and_focus_ring_include_open_songs_folder() -> void:
	var m := _main_menu()
	var order: Array = [m.start_button, m.practice_button, m.calibrate_button, m.settings_button,
		m.autoplay_button, m.open_folder_button, m.quit_button]
	assert_str(m.open_folder_button.text).is_equal("Open Songs Folder")
	for i in order.size():
		var b: Button = order[i]
		var next: Button = order[(i + 1) % order.size()]
		var prev: Button = order[(i + order.size() - 1) % order.size()]
		assert_bool(b.get_node(b.focus_neighbor_bottom) == next).is_true()
		assert_bool(b.get_node(b.focus_neighbor_top) == prev).is_true()
	for i in range(order.size() - 1):
		assert_bool((order[i] as Button).get_index() < (order[i + 1] as Button).get_index()).is_true()


func test_open_songs_folder_calls_seam_and_shows_error_on_failure() -> void:
	var m := _main_menu()
	var calls := [0]
	m.open_folder = func() -> bool:
		calls[0] += 1
		return true
	m.open_folder_button.pressed.emit()
	assert_int(calls[0]).is_equal(1)
	assert_bool(m.folder_message_label.visible).is_false()
	m.open_folder = func() -> bool: return false
	m.open_songs_folder()
	assert_bool(m.folder_message_label.visible).is_true()
	assert_str(m.folder_message_label.text).starts_with("Could not open the Songs folder. It is at ")


func test_best_line_is_hidden_but_still_present() -> void:
	var m := _main_menu()
	assert_object(m.best_label).is_not_null()
	assert_bool(m.best_label.visible).is_false()


func test_best_line_empty_state_and_saved_record() -> void:
	var m := _main_menu()
	assert_str(m.best_label.text).is_equal("No record yet. Finish a dive to set one.")
	var store := ScoreStore.new(SCORES_TMP)
	store.submit(TestCharts.HAND_CHART_ID, 1240.0, 96.0, 50, true, "2026-10-08")
	var m2 := _main_menu()
	assert_str(m2.best_label.text).is_equal("Best: 1,240 m   Accuracy 96%")


func test_best_label_not_focusable_and_after_practice() -> void:
	var m := _main_menu()
	assert_int(m.best_label.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_int(m.best_label.get_index()).is_equal(m.practice_button.get_index() + 1)
	assert_int(m.practice_button.get_index()).is_equal(m.start_button.get_index() + 1)
	assert_bool(m.start_button.has_focus()).is_true()


func test_records_load_error_shown_once() -> void:
	var f := FileAccess.open(SCORES_TMP, FileAccess.WRITE)
	f.store_string("garbage [[ = =
[oops")
	f.close()
	var m := _main_menu()
	assert_object(m.records_error_label).is_not_null()
	assert_str(m.records_error_label.text).is_equal(
		"Records could not be loaded. Starting with an empty record book.")
	assert_bool(FileAccess.file_exists(SCORES_TMP + ".bak")).is_true()
	var m2 := _main_menu()
	assert_object(m2.records_error_label).is_null()


# ---- 02.2 plan 06: living title screen ----------------------------------------------------

const MENU_TEXTS: Array[String] = ["Start Dive", "Practice Dive (No-Fail)", "Calibrate Sonar", "Settings",
	"Autoplay Dive (test)", "Open Songs Folder", "Quit Game"]
const MENU_ICONS: Array[String] = ["dive", "lifebuoy", "sonar", "sliders", "auto", "folder", "power"]
const MENU_TOPS: Array[float] = [416.0, 488.0, 560.0, 632.0, 704.0, 776.0, 848.0]
const MENU_DESCRIPTIONS: Array[String] = [
	"Pick a song and dive. Your hull is on the line.",
	"Dive without imploding. Records are not saved.",
	"Line up audio and visuals for tight timing.",
	"Controls, scroll speed, effects and volume.",
	"Watch the sub play a song by itself.",
	"Add Clone Hero song folders or .zip files.",
	"Surface and close UNDERTOW.",
]


func _menu_buttons(m: MainMenu) -> Array:
	return [m.start_button, m.practice_button, m.calibrate_button, m.settings_button,
		m.autoplay_button, m.open_folder_button, m.quit_button]


func test_menu_buttons_have_fixed_rects_icons_and_order() -> void:
	var m := _main_menu()
	m.finish_entrance()
	var order := _menu_buttons(m)
	for i in order.size():
		var b: Button = order[i]
		assert_str(b.text).is_equal(MENU_TEXTS[i])
		assert_vector(b.position).override_failure_message("%s at %s" % [b.text, b.position]) \
			.is_equal(Vector2(128.0, MENU_TOPS[i]))
		assert_vector(b.size).override_failure_message("%s size %s" % [b.text, b.size]).is_equal(Vector2(512.0, 64.0))
		assert_str(String(b.get_meta(&"ui_icon", ""))).is_equal(MENU_ICONS[i])
		assert_float(b.modulate.a).is_equal(1.0)
	assert_str(String(m.start_button.get_meta(&"ui_variant", ""))).is_equal("primary")
	assert_str(String(m.quit_button.get_meta(&"ui_variant", ""))).is_equal("default")


func test_focus_sets_description_for_every_item() -> void:
	var m := _main_menu()
	await get_tree().process_frame
	var order := _menu_buttons(m)
	for i in order.size():
		(order[i] as Button).grab_focus()
		assert_str(m.description_label.text).is_equal(MENU_DESCRIPTIONS[i])
	m.start_button.grab_focus()
	assert_str(m.description_label.text).is_equal(MENU_DESCRIPTIONS[0])


func test_wordmark_assets_are_1920x304_with_wide_coverage() -> void:
	for path in [LogoWordmark.WORDMARK_PATH, LogoWordmark.GLOW_PATH]:
		var tex := load(path) as Texture2D
		assert_object(tex).override_failure_message("missing " + path).is_not_null()
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		assert_int(img.get_width()).is_equal(1920)
		assert_int(img.get_height()).is_equal(304)
	var mark := (load(LogoWordmark.WORDMARK_PATH) as Texture2D).get_image()
	mark.clear_mipmaps()
	var cols := 0
	for x in mark.get_width():
		for y in range(0, mark.get_height(), 4):
			if mark.get_pixel(x, y).a > 0.5:
				cols += 1
				break
	assert_float(float(cols) / mark.get_width()).override_failure_message("ink columns %d" % cols) \
		.is_greater_equal(0.3)


func test_backdrop_first_and_logo_layout() -> void:
	var m := _main_menu()
	var bd := m.get_child(0) as AbyssBackdrop
	assert_object(bd).is_not_null()
	assert_str(bd.variant).is_equal("title")
	assert_object(m.logo).is_not_null()
	assert_bool(m.logo is TextureRect).is_true()
	assert_vector(m.logo.position).is_equal(Vector2(120.0, 168.0))
	assert_vector(m.logo.size).is_equal(Vector2(960.0, 152.0))
	assert_str(m.logo.texture.resource_path).is_equal(LogoWordmark.WORDMARK_PATH)
	assert_object(m.logo.material as ShaderMaterial).is_not_null()
	assert_object(m.description_label).is_not_null()


func test_logo_shimmer_and_glow_follow_effect_settings() -> void:
	var m := _main_menu()
	var logo: LogoWordmark = m.logo
	assert_bool(logo.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_dict(logo.effect_counts()).is_equal({"shimmer": true, "glow": true})
	assert_bool(logo.glow.visible).is_true()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(logo.effect_counts()).is_equal({"shimmer": false, "glow": false})
	assert_bool(logo.glow.visible).is_false()
	assert_bool(bool((logo.material as ShaderMaterial).get_shader_parameter("enabled"))).is_false()
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	assert_dict(logo.effect_counts()).is_equal({"shimmer": false, "glow": true})
	Settings.reduce_motion = false
	Settings.settings_changed.emit()
	assert_bool(bool((logo.material as ShaderMaterial).get_shader_parameter("enabled"))).is_true()


func test_glow_hidden_when_built_in_low_effects() -> void:
	Settings.low_effects = true
	var m := _main_menu()
	assert_bool(m.logo.glow.visible).is_false()
	assert_int(int((m.get_child(0) as AbyssBackdrop).effect_counts()["snow"])).is_equal(30)


# ---- 02.2 plan 07: last-dive card ----

func test_last_dive_card_hidden_without_a_last_song() -> void:
	Settings.last_song_id = ""
	var m := _main_menu()
	assert_object(m.last_dive_card).is_not_null()
	assert_bool(m.last_dive_card.visible).is_false()
	Settings.last_song_id = "no/such/song"
	Settings.last_difficulty = "expert"
	var m2 := _main_menu()
	assert_bool(m2.last_dive_card.visible).is_false()


func test_last_dive_card_shows_title_and_no_record() -> void:
	Settings.last_song_id = TestCharts.HAND_CHART_ID
	Settings.last_difficulty = "expert"
	var m := _main_menu()
	var card: MainMenu.LastDiveCard = m.last_dive_card
	assert_bool(card.visible).is_true()
	assert_vector(card.position).is_equal(Vector2(1376.0, 840.0))
	assert_vector(card.size).is_equal(Vector2(480.0, 160.0))
	assert_str(card.caption_label.text).is_equal("LAST DIVE")
	assert_str(card.title_label.text).is_equal("Calibration Track")
	assert_str(card.chip_text).is_equal("EXPERT")
	assert_int(card.chip_lane).is_equal(3)
	assert_str(card.length_label.text).contains(":")
	assert_bool(card.empty_label.visible).is_true()
	assert_str(card.empty_label.text).is_equal("No record yet.")
	assert_bool(card.best_value_label.visible).is_false()


func test_last_dive_card_shows_best_depth_in_gold() -> void:
	var store := ScoreStore.new(SCORES_TMP)
	store.submit(TestCharts.HAND_CHART_ID, 1240.0, 96.0, 50, true, "2026-10-08")
	Settings.last_song_id = TestCharts.HAND_CHART_ID
	Settings.last_difficulty = "expert"
	var m := _main_menu()
	var card: MainMenu.LastDiveCard = m.last_dive_card
	assert_bool(card.best_value_label.visible).is_true()
	assert_str(card.best_value_label.text).is_equal("1,240 M")
	assert_bool(card.empty_label.visible).is_false()
	assert_that(card.best_value_label.get_theme_color("font_color")).is_equal(Palette.REWARD_GOLD)
	# Right edge of the depth sits at x 1832 (card-local 456).
	assert_float(card.best_value_label.position.x + card.best_value_label.size.x).is_equal_approx(456.0, 0.5)


func test_last_dive_card_difficulty_lanes() -> void:
	assert_int(MainMenu.difficulty_lane("easy")).is_equal(0)
	assert_int(MainMenu.difficulty_lane("medium")).is_equal(1)
	assert_int(MainMenu.difficulty_lane("hard")).is_equal(2)
	assert_int(MainMenu.difficulty_lane("expert")).is_equal(3)


# ---- 02.2-21: Settings restyle (UI-SPEC 9.3, 14) ---------------------------------------------


func test_toggle_is_pill_with_on_off_text_and_styles() -> void:
	var s := _screen()
	assert_bool(s.no_fail_button is SettingsScreen.PillToggle).is_true()
	assert_str(s.no_fail_button.text).is_equal("OFF")
	assert_that(s.no_fail_button.custom_minimum_size).is_equal(Vector2(160.0, 40.0))
	var on := SettingsScreen.PillToggle.style_for(true)
	assert_that(on["fill"]).is_equal(Color(Palette.SONAR, 0.22))
	assert_that(on["edge"]).is_equal(Palette.SONAR)
	assert_that(on["text"]).is_equal(Palette.TEXT_HI)
	var off := SettingsScreen.PillToggle.style_for(false)
	assert_that(off["fill"]).is_equal(Palette.ABYSS_800)
	assert_that(off["edge"]).is_equal(Color(Palette.TEXT_LO, 0.35))
	assert_that(off["text"]).is_equal(Palette.TEXT_MID)
	# Knob 16 x 24: left when OFF, right when ON.
	assert_that(SettingsScreen.PillToggle.knob_rect(0.0).size).is_equal(Vector2(16.0, 24.0))
	assert_float(SettingsScreen.PillToggle.knob_rect(1.0).position.x).is_greater(
		SettingsScreen.PillToggle.knob_rect(0.0).position.x + 80.0)


func test_toggle_knob_slides_then_jumps_under_reduce_motion() -> void:
	Settings.reduce_motion = false
	var s := _screen()
	var t: SettingsScreen.PillToggle = s.no_fail_button
	assert_float(t.knob_t).is_equal(0.0)
	t.pressed.emit()
	assert_str(t.text).is_equal("ON")
	assert_float(t.knob_t).is_less(1.0)  # slides over DUR_FAST
	await get_tree().create_timer(Palette.DUR_FAST + 0.1).timeout
	assert_float(t.knob_t).is_equal_approx(1.0, 0.001)
	Settings.reduce_motion = true
	t.pressed.emit()
	assert_str(t.text).is_equal("OFF")
	assert_float(t.knob_t).is_equal(0.0)  # jumps


func test_reduce_motion_row_renamed_with_spec_hints() -> void:
	var s := _screen()
	var titles := s.row_titles()
	assert_bool(titles.has("Reduce motion")).is_true()
	assert_bool(titles.has("Reduce screen shake")).is_false()
	assert_str(s.hint_for("Reduce motion")).is_equal(
		"Turns off screen shake, parallax and big movement. Effects fade instead of moving.")
	assert_str(s.hint_for("Low effects")).is_equal(
		"Fewer particles, no glow or CRT effect, simpler backgrounds. Notes and lanes stay fully bright.")
	assert_str(s.hint_for("Menu music")).is_equal("Plays a quiet song preview on the main menu.")
	var src := FileAccess.get_file_as_string("res://src/ui/settings_screen.gd")
	assert_bool(src.contains("Reduce screen shake")).is_false()
	assert_bool(src.contains("[ ON ]")).is_false()


func test_step_slider_style_and_value_column() -> void:
	assert_float(StepSlider.TRACK_H).is_equal(8.0)
	assert_float(StepSlider.HANDLE_W).is_equal(16.0)
	assert_float(StepSlider.HANDLE_H).is_equal(32.0)
	var idle := StepSlider.colors(false)
	assert_that(idle["track"]).is_equal(Palette.ABYSS_600)
	assert_that(idle["fill"]).is_equal(Palette.SONAR)
	assert_that(idle["thumb"]).is_equal(Palette.TEXT_HI)
	assert_bool(idle["glow"]).is_false()
	var focused := StepSlider.colors(true)
	assert_that(focused["thumb_edge"]).is_equal(Palette.SONAR_PALE)
	assert_bool(focused["glow"]).is_true()
	var s := _screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var vl: Label = s.scroll_value_label
	assert_float(vl.get_global_rect().end.x).is_equal_approx(SettingsScreen.VALUE_RIGHT, 1.0)
	assert_int(vl.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	assert_that(vl.get_theme_color("font_color")).is_equal(Palette.TEXT_HI)
	assert_float(SettingsScreen.VALUE_RIGHT).is_equal(1840.0)


func test_rebind_listening_and_rejected_styles() -> void:
	Settings.reduce_motion = false
	var s := _screen()
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	cell.begin_listen()
	assert_str(cell.text).is_equal("PRESS A KEY")
	assert_that(cell.get_theme_color("font_color")).is_equal(Palette.SONAR_PALE)
	assert_that(cell.edge_color()).is_equal(Color(Palette.SONAR, cell.edge_color().a))
	# Edge pulses at 1.2 Hz; static under Reduce motion.
	var period := 1.0 / RebindCell.PULSE_HZ
	assert_float(RebindCell.PULSE_HZ).is_equal(1.2)
	assert_float(RebindCell.listen_edge_alpha(0.1, false)).is_not_equal_approx(
		RebindCell.listen_edge_alpha(0.1 + period * 0.5, false), 0.05)
	assert_float(RebindCell.listen_edge_alpha(0.1, false)).is_equal_approx(
		RebindCell.listen_edge_alpha(0.1 + period, false), 0.0001)
	assert_float(RebindCell.listen_edge_alpha(0.1, true)).is_equal(RebindCell.listen_edge_alpha(0.4, true))
	# Rejected: existing copy, WARNING_RED edge.
	cell.handle_event(_key(KEY_2))
	assert_str(s.message_text(&"lane_1")).is_equal("! 2 is already used for Lane 2. Pick a different key.")
	assert_bool(cell.rejected).is_true()
	assert_that(cell.edge_color()).is_equal(Palette.WARNING_RED)
	s.clear_message(&"lane_1")
	assert_bool(cell.rejected).is_false()


func test_standalone_has_table_backdrop_title_and_glass_sections() -> void:
	var s := _screen(false)
	assert_object(s.backdrop).is_not_null()
	assert_str(s.backdrop.variant).is_equal("table")
	assert_object(s.shade).is_null()
	assert_str(s.title_label.text).is_equal("SETTINGS")
	assert_str(String(s.title_label.theme_type_variation)).is_equal("HeadingLabel")
	assert_that(SettingsScreen.TITLE_POS).is_equal(Vector2(64.0, 104.0))
	assert_float(s.title_label.position.x).is_equal(64.0)
	assert_bool(s.focus_marker is FocusMarker).is_true()
	assert_bool(s.is_in_group(UiKit.FX_GROUP)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(s.section_panels.size()).is_equal(6)
	for p: Control in s.section_panels:
		var r := p.get_global_rect()
		assert_float(r.position.x).is_equal_approx(64.0, 0.5)
		assert_float(r.end.x).is_equal_approx(1856.0, 0.5)


func test_overlay_mode_has_opaque_shade_and_no_backdrop() -> void:
	var s := _screen(true)
	assert_object(s.backdrop).is_null()
	assert_object(s.shade).is_not_null()
	assert_that(s.shade.color).is_equal(Color(Palette.ABYSS_900, 0.85))
	assert_int(s.find_children("*", "AbyssBackdrop", true, false).size()).is_equal(0)
