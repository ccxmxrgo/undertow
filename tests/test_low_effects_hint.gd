extends GdUnitTestSuite
## 05-06: the slow-frame results hint (D-06, AV-05). LowEffectsHint helper; the results-screen and
## gameplay tests follow below.

const SETTINGS_TMP := "user://test_low_effects_hint_settings.cfg"

var _low: bool
var _reduce: bool
var _save_path: String
var _changed: int = 0


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	_save_path = Settings.save_path
	Settings.save_path = SETTINGS_TMP
	Settings.low_effects = false
	Settings.reduce_motion = false
	_changed = 0
	_rm()


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce
	Settings.save_path = _save_path
	_rm()


func _rm() -> void:
	for p in [SETTINGS_TMP, SETTINGS_TMP + ".tmp", SETTINGS_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _count_changed() -> void:
	_changed += 1


# ---- LowEffectsHint ---------------------------------------------------------------------

func test_wanted_only_for_a_real_true_with_low_effects_off() -> void:
	assert_bool(LowEffectsHint.wanted({"slow_frames": true})).is_true()
	assert_bool(LowEffectsHint.wanted({"slow_frames": false})).is_false()
	assert_bool(LowEffectsHint.wanted({})).is_false()
	assert_bool(LowEffectsHint.wanted({"slow_frames": 1})).is_false()
	assert_bool(LowEffectsHint.wanted({"slow_frames": "true"})).is_false()
	Settings.low_effects = true
	assert_bool(LowEffectsHint.wanted({"slow_frames": true})).is_false()


func test_enable_low_effects_sets_saves_and_signals_once() -> void:
	Settings.settings_changed.connect(_count_changed)
	LowEffectsHint.enable_low_effects()
	Settings.settings_changed.disconnect(_count_changed)
	assert_bool(Settings.low_effects).is_true()
	assert_int(_changed).is_equal(1)
	assert_bool(FileAccess.file_exists(SETTINGS_TMP)).is_true()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SETTINGS_TMP)).is_equal(OK)
	assert_bool(cfg.get_value("display", "low_effects", false)).is_true()


func test_copy_and_rect() -> void:
	assert_str(LowEffectsHint.TEXT).is_equal("Some frames came late on this PC. Low effects can help.")
	assert_str(LowEffectsHint.DONE_TEXT).is_equal("Low effects is on. Change it in Settings > Display.")
	assert_str(LowEffectsHint.BUTTON_TEXT).is_equal("Turn on Low effects")
	assert_str(LowEffectsHint.DONE_BUTTON_TEXT).is_equal("Low effects on")
	assert_object(LowEffectsHint.BUTTON_RECT).is_equal(Rect2(1368.0, 752.0, 400.0, 64.0))
	assert_bool(LowEffectsHint.BUTTON_RECT.end.x <= ResultsScreen.RIGHT_X).is_true()


# ---- results screens --------------------------------------------------------------------

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 40000
const SCORES_TMP := "user://test_low_effects_hint_scores.cfg"


func _holder() -> Control:
	var h := Control.new()
	UiLayout.fill_rect(h)
	add_child(h)
	auto_free(h)
	return h


func _solo(run_info: Dictionary) -> ResultsScreen:
	var s := HullScore.new(JudgeConfig.new())
	var r := ResultsScreen.new()
	_holder().add_child(r)
	r.setup(s, false, {}, false, run_info)
	return r


func _vrows() -> Array:
	return [
		{"seat": 0, "place": 1, "alive": true, "depth": 1200.0, "hull": 88.0, "accuracy": 0.984,
			"eliminated_at": INF, "name": "Nemo", "landed": 4, "reflected": 2},
		{"seat": 1, "place": 2, "alive": true, "depth": 1100.0, "hull": 62.0, "accuracy": 0.9,
			"eliminated_at": INF, "name": "Mako", "landed": 3, "reflected": 1},
	]


func _vdata(online: bool = false, is_host: bool = false) -> Dictionary:
	var d := {"rows": _vrows(), "local_seat": 0, "medals": {0: ["shredder"]}, "title": "Sea Shanty 2",
		"artist": "Jagex", "difficulty": "expert", "seed": 99, "last_standing_seat": -1}
	if online:
		d["online"] = true
		d["is_host"] = is_host
		d["host_seat"] = 0
		d["host_name"] = "Nemo"
	return d


func _versus(data: Dictionary) -> VersusResultsScreen:
	var r := VersusResultsScreen.new()
	_holder().add_child(r)
	r.setup(data)
	return r


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func _assert_hint_layout(b: Button, l: Label) -> void:
	assert_object(b).is_not_null()
	assert_bool(b.visible).is_true()
	assert_str(b.text).is_equal(LowEffectsHint.BUTTON_TEXT)
	assert_object(Rect2(b.position, b.size)).is_equal(LowEffectsHint.BUTTON_RECT)
	assert_object(l).is_not_null()
	assert_str(l.text).is_equal(LowEffectsHint.TEXT)
	assert_float(l.position.x + l.size.x).is_less_equal(LowEffectsHint.LINE_RIGHT + 1.0)
	assert_object(l.get_theme_color("font_color")).is_equal(Palette.TEXT_MID)


func test_solo_results_show_the_hint_on_a_slow_run() -> void:
	var r := _solo({"title": "Short", "slow_frames": true})
	_assert_hint_layout(r.low_effects_button, r.slow_hint_label)
	assert_object(_focused()).is_same(r.retry_button)
	# The hint button joins the end of the wrap loop.
	assert_object(r.menu_button.get_node(r.menu_button.focus_neighbor_right)).is_same(r.low_effects_button)
	var b := r.low_effects_button
	assert_object(b.get_node(b.focus_neighbor_right)).is_same(r.retry_button)
	assert_object(r.retry_button.get_node(r.retry_button.focus_neighbor_left)).is_same(b)
	assert_object(b.get_node(b.focus_neighbor_left)).is_same(r.menu_button)


func test_solo_press_turns_low_effects_on() -> void:
	var r := _solo({"slow_frames": true})
	r.skip_entrance()
	r.low_effects_button.grab_focus()
	r.low_effects_button.pressed.emit()
	assert_bool(Settings.low_effects).is_true()
	assert_bool(FileAccess.file_exists(SETTINGS_TMP)).is_true()
	assert_bool(r.low_effects_button.disabled).is_true()
	assert_str(r.low_effects_button.text).is_equal(LowEffectsHint.DONE_BUTTON_TEXT)
	assert_str(r.slow_hint_label.text).is_equal(LowEffectsHint.DONE_TEXT)
	assert_object(_focused()).is_same(r.menu_button)
	# The loop closes over the three original buttons again.
	assert_object(r.menu_button.get_node(r.menu_button.focus_neighbor_right)).is_same(r.retry_button)


func test_solo_no_hint_when_smooth_or_already_low() -> void:
	assert_object(_solo({}).low_effects_button).is_null()
	assert_object(_solo({"slow_frames": false}).low_effects_button).is_null()
	assert_object(_solo({}).slow_hint_label).is_null()
	Settings.low_effects = true
	assert_object(_solo({"slow_frames": true}).low_effects_button).is_null()


func test_versus_offline_hint() -> void:
	var d := _vdata()
	d["slow_frames"] = true
	var r := _versus(d)
	_assert_hint_layout(r.low_effects_button, r.slow_hint_label)
	assert_object(_focused()).is_same(r.rematch_button)
	assert_int(r.focus_buttons().size()).is_equal(3)
	assert_object(r.menu_button.get_node(r.menu_button.focus_neighbor_right)).is_same(r.low_effects_button)
	r.low_effects_button.pressed.emit()
	assert_bool(Settings.low_effects).is_true()
	assert_bool(r.low_effects_button.disabled).is_true()
	assert_str(r.slow_hint_label.text).is_equal(LowEffectsHint.DONE_TEXT)
	assert_object(_versus(_vdata()).low_effects_button).is_null()


func test_versus_online_host_and_client_hint() -> void:
	var h := _vdata(true, true)
	h["slow_frames"] = true
	var rh := _versus(h)
	_assert_hint_layout(rh.low_effects_button, rh.slow_hint_label)
	assert_object(_focused()).is_same(rh.back_to_lobby_button)
	assert_int(rh.online_state()["buttons"].size()).is_equal(2)
	var c := _vdata(true, false)
	c["slow_frames"] = true
	var rc := _versus(c)
	_assert_hint_layout(rc.low_effects_button, rc.slow_hint_label)
	assert_object(_focused()).is_same(rc.leave_button)
	assert_object(rc.leave_button.get_node(rc.leave_button.focus_neighbor_right)).is_same(rc.low_effects_button)
	assert_object(_versus(_vdata(true, false)).low_effects_button).is_null()


# ---- gameplay end to end ----------------------------------------------------------------

class FakeHostSession:
	extends Node
	var sent: Array = []

	func host_send_results(data: Dictionary) -> void:
		sent.append(data)


var _old_scores: String


func _launch(practice: bool = false) -> Gameplay:
	_old_scores = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = true
	Gameplay.pending_practice = practice
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _end_launch() -> void:
	ScoreStore.default_path = _old_scores
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _wait_done(gp: Gameplay) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not gp.is_done() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _stutter(gp: Gameplay) -> void:
	for i in 700:
		gp.frame_watch.sample(0.05, 5.0, false)


func test_gameplay_slow_run_offers_the_hint() -> void:
	var gp := _launch()
	_stutter(gp)
	await _wait_done(gp)
	_end_launch()
	assert_object(gp.results).is_not_null()
	assert_object(gp.results.low_effects_button).is_not_null()


func test_gameplay_smooth_run_has_no_hint() -> void:
	var gp := _launch()
	await _wait_done(gp)
	_end_launch()
	assert_object(gp.results).is_not_null()
	assert_object(gp.results.low_effects_button).is_null()


func test_online_results_flag_is_local_only() -> void:
	# A Solo Dive run supplies a VersusController; then the online results path runs on it.
	var gp := _launch(true)
	await _wait_done(gp)
	_end_launch()
	_stutter(gp)
	var fake := FakeHostSession.new()
	auto_free(fake)
	gp.session = fake
	gp.online_spec = {"role": "host", "local_seat": 0}
	gp.versus_results = null
	gp._host_results(1.0)
	gp.online_spec = {}
	assert_int(fake.sent.size()).is_equal(1)
	var sent: Dictionary = fake.sent[0]
	assert_bool(sent.has("slow_frames")).is_false()
	assert_object(gp.versus_results).is_not_null()
	assert_object(gp.versus_results.low_effects_button).is_not_null()


func test_client_overwrites_a_host_sent_flag() -> void:
	var gp := _launch(true)
	await _wait_done(gp)
	_end_launch()
	# Smooth here: a host-injected slow_frames never shows the hint, and the input is not mutated.
	var d := _vdata(true, false)
	d["slow_frames"] = true
	gp.online_spec = {"role": "client", "local_seat": 0}
	gp._show_online_results(d)
	assert_bool(d["slow_frames"]).is_true()
	assert_object(gp.versus_results).is_not_null()
	assert_object(gp.versus_results.low_effects_button).is_null()
	var d2 := _vdata(true, false)
	gp.versus_results.queue_free()
	gp.versus_results = null
	_stutter(gp)
	gp._show_online_results(d2)
	gp.online_spec = {}
	assert_bool(d2.has("slow_frames")).is_false()
	assert_object(gp.versus_results.low_effects_button).is_not_null()
