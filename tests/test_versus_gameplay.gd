extends GdUnitTestSuite
## 03-14 end to end: Gameplay with MatchSetup.pending builds a versus match through the
## VersusController (MATCH-01, D-18, D-28); fire / target input (TORP-02, TORP-03); the wreck
## path instead of the FailScreen (D-22, D-24); versus results without records (MATCH-05, D-23);
## Solo Dive training (MATCH-06, D-27); the >= 1 beat telegraph in a running match (TORP-04);
## a plain solo dive and the stale-launch-record regression (T-03-35).

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 40000
const SCORES_TMP := "user://test_versus_gameplay_scores.cfg"
const SEED := 424242

var _saved_no_fail := false
var _saved_training := "off"
var _old_scores_path := ""


func before_test() -> void:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	_saved_no_fail = Settings.no_fail
	_saved_training = Settings.training_payload
	Settings.no_fail = false
	Settings.training_payload = "off"
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP
	_rm_scores()


func after_test() -> void:
	ScoreStore.default_path = _old_scores_path
	_rm_scores()
	Settings.no_fail = _saved_no_fail
	Settings.training_payload = _saved_training
	MatchSetup.pending = null
	VersusController.test_autoplay_human = false
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _rm_scores() -> void:
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _scores_exist() -> bool:
	return FileAccess.file_exists(SCORES_TMP)


static func _setup(rivals: int = 3) -> MatchSetup:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = rivals
	m.skill = "regular"
	m.seed = SEED
	return m


func _launch(autoplay: bool = false, practice: bool = false) -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = autoplay
	Gameplay.pending_practice = practice
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _launch_versus(rivals: int = 3, auto_human: bool = true) -> Gameplay:
	MatchSetup.pending = _setup(rivals)
	VersusController.test_autoplay_human = auto_human
	return _launch()


func _wait_done(gp: Gameplay) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not gp.is_done() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait_time(gp: Gameplay, t: float) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if gp.is_began() and gp.conductor != null and gp.conductor.song_time() >= t:
			return
		await get_tree().process_frame


static func _events(gp: Gameplay, type: String, seat_key: String = "", seat: int = -1) -> Array:
	var out: Array = []
	for e in gp.versus.sim.event_log:
		if e["type"] == type and (seat_key == "" or int(e.get(seat_key, -2)) == seat):
			out.append(e)
	return out


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


# ---- versus end to end ----------------------------------------------------------------------

func test_versus_match_builds_plays_and_ends_on_versus_results() -> void:
	var gp := _launch_versus(3)
	await get_tree().process_frame
	assert_object(gp.versus).is_not_null()
	assert_object(gp.match_setup).is_not_null()
	assert_object(MatchSetup.pending).is_null()  # one-shot
	assert_bool(gp.judge is VersusJudge).is_true()
	assert_bool(gp.score is VersusHull).is_true()
	assert_bool(gp.score.no_fail).is_false()  # versus never uses No-Fail
	assert_int(gp.versus.bots.size()).is_equal(3)
	assert_object(gp.find_child("VersusController", true, false)).is_not_null()
	assert_object(gp.find_child("VersusHud", true, false)).is_not_null()
	assert_object(gp.find_child("Killfeed", true, false)).is_not_null()
	assert_object(gp.find_child("RewardSocket", true, false)).is_not_null()
	assert_object(gp.find_child("TargetReadout", true, false)).is_not_null()
	assert_object(gp.find_child("InkCloudLayer", true, false)).is_not_null()
	var col := gp.find_child("PeriscopeColumn", true, false) as PeriscopeColumn
	assert_object(col).is_not_null()
	assert_int(col.panels().size()).is_equal(3)
	# Render order (UI-SPEC 1): ink above HighwayNotes; VersusHud between Hud and StreakCounter.
	var br := gp.board_root
	assert_int(gp.versus.ink_cloud.get_index()).is_greater(gp.highway_notes.get_index())
	assert_int(gp.versus.ink_top.get_index()).is_greater(gp.versus.ink_cloud.get_index())
	assert_object(gp.versus.ink_cloud.get_parent()).is_equal(br)
	var vh := gp.versus.versus_hud
	assert_int(vh.get_index()).is_greater(gp.hud.get_index())
	assert_int(vh.get_index()).is_less(gp.streak_counter.get_index())
	assert_bool(gp.pause_menu.match_mode).is_true()
	await _wait_done(gp)
	assert_int(gp.state).is_equal(Gameplay.State.DONE)
	assert_object(gp.results).is_null()
	assert_object(gp.versus_results).is_not_null()
	assert_int(gp.versus_results.row_count()).is_equal(4)
	assert_int(_events(gp, GameEvent.MATCH_END).size()).is_equal(1)
	assert_bool(_scores_exist()).override_failure_message("versus wrote ScoreStore").is_false()


func test_fire_and_target_input() -> void:
	var gp := _launch_versus(3, false)
	await _wait_time(gp, 0.05)
	var v := gp.versus
	# Nothing held: no launch, no blip.
	await _press(&"fire")
	assert_int(_events(gp, GameEvent.FIRE_QUEUED, "seat", 0).size()).is_equal(0)
	assert_int(v.error_blips).is_equal(0)
	# Target cycle works without a reward (pre-aim): AUTO -> LOCKED on the first rival.
	var before := _events(gp, GameEvent.TARGET, "seat", 0).size()
	await _press(&"target_cycle")
	var targets := _events(gp, GameEvent.TARGET, "seat", 0)
	assert_int(targets.size()).is_greater(before)
	assert_int(int(targets[-1]["mode"])).is_equal(PlayerState.TargetMode.LOCKED)
	assert_int(int(targets[-1]["target"])).is_equal(1)
	# A held disruptor: the fire action queues a launch at the locked target.
	assert_bool(v.players[0].meter.queue_prize(Reward.Id.INK_CLOUD)).is_true()
	await _press(&"fire")
	var q := _events(gp, GameEvent.FIRE_QUEUED, "seat", 0)
	assert_int(q.size()).is_equal(1)
	assert_int(int(q[0]["to"])).is_equal(1)
	assert_int(int(q[0]["reward"])).is_equal(Reward.Id.INK_CLOUD)
	assert_int(v.error_blips).is_equal(0)


func test_refused_fire_plays_the_error_blip() -> void:
	var gp := _launch_versus(1, false)
	await _wait_time(gp, 0.05)
	var v := gp.versus
	v.players[1].immune_until = 999.0  # the only rival is shielded
	assert_bool(v.players[0].meter.queue_prize(Reward.Id.INK_CLOUD)).is_true()
	await _press(&"fire")
	assert_int(v.error_blips).is_equal(1)
	var refused := _events(gp, GameEvent.FIRE_REFUSED, "seat", 0)
	assert_str(str(refused[-1]["reason"])).is_equal("shielded")
	assert_int(v.players[0].meter.held).is_equal(Reward.Id.INK_CLOUD)  # reward kept


func test_wreck_keeps_the_song_running_and_ends_on_versus_results() -> void:
	var gp := _launch_versus(3)
	await _wait_time(gp, 1.0)
	gp.score._damage(1000.0)
	var t0 := gp.conductor.song_time()
	for i in 10:
		await get_tree().process_frame
	assert_int(gp.state).is_equal(Gameplay.State.RUNNING)
	assert_object(gp.fail_screen).is_null()
	assert_int(gp.find_children("*", "FailScreen", true, false).size()).is_equal(0)
	assert_float(gp.conductor.song_time()).is_greater(t0)  # the song keeps playing
	assert_bool(gp.lane_input.enabled).is_true()
	assert_bool(gp.hud.is_wreck()).is_true()
	assert_str(gp.hud.hull_caption.text).is_equal(Hud.WRECK_CAPTION)
	assert_int(_events(gp, GameEvent.IMPLODED, "seat", 0).size()).is_equal(1)
	await _wait_done(gp)
	assert_object(gp.versus_results).is_not_null()
	assert_int(gp.versus_results.row_count()).is_equal(4)
	assert_bool(_scores_exist()).is_false()


func test_telegraph_alert_visible_at_launch_one_beat_before_arrival() -> void:
	var gp := _launch_versus(1)
	await _wait_time(gp, 0.1)
	var v := gp.versus
	var t := gp.conductor.song_time()
	assert_int(v.sim.inject_fire(1, 0, Reward.Id.INK_CLOUD, t)).is_equal(MatchSim.FIRE_OK)
	var alert := v.incoming_alert
	var seen_t := -1.0
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if alert.visible and alert.is_showing():
			seen_t = gp.conductor.song_time()
			break
	assert_float(seen_t).override_failure_message("alert never showed").is_greater_equal(0.0)
	var launches := _events(gp, GameEvent.TORPEDO_LAUNCH, "to", 0)
	assert_int(launches.size()).is_greater_equal(1)
	var e: Dictionary = launches[0]
	var beat: float = 60.0 / float(gp.chart.tempo_map[0]["bpm"])
	# Event-stamped: visible from launch_t, at least one beat before arrive_t (TORP-04).
	assert_float(alert.first_visible_t()).is_equal_approx(float(e["launch_t"]), 1e-6)
	assert_float(alert.arrive_t() - alert.first_visible_t()).is_greater_equal(beat - 1e-6)
	# Frame-observed: on screen within a frame or two of the launch, well before arrival.
	assert_float(seen_t).is_less(float(e["arrive_t"]) - 0.5 * beat)


# ---- Solo Dive training ---------------------------------------------------------------------

func test_training_drone_no_fail_and_solo_results() -> void:
	Settings.training_payload = "ink_cloud"
	var gp := _launch(true, true)
	await _wait_time(gp, 0.5)
	var v := gp.versus
	assert_object(v).is_not_null()
	assert_object(gp.match_setup).is_null()
	assert_bool(v.training).is_true()
	assert_int(v.bots.size()).is_equal(0)
	assert_object(v.drone).is_not_null()
	assert_bool(gp.score.no_fail).is_true()
	var col := v.periscope_column
	assert_object(col).is_not_null()
	assert_int(col.panels().size()).is_equal(1)
	assert_str(col.panels()[0].callsign).is_equal("DRONE")
	assert_bool(col.panels()[0].status_text().begins_with("NEXT IN ")).is_true()
	assert_bool(col.panels()[0].status_text().ends_with(" BAR") or col.panels()[0].status_text().ends_with(" BARS")).is_true()
	assert_object(v.killfeed).is_not_null()
	assert_bool(gp.pause_menu.match_mode).is_false()
	gp.score._damage(1000.0)  # forced No-Fail: the run goes on
	await get_tree().process_frame
	assert_int(gp.state).is_equal(Gameplay.State.RUNNING)
	assert_object(gp.fail_screen).is_null()
	await _wait_done(gp)
	assert_int(gp.state).is_equal(Gameplay.State.DONE)
	assert_object(gp.versus_results).is_null()
	assert_object(gp.results).is_not_null()  # the Solo Dive results path
	assert_bool(gp.record_info["eligible"]).is_false()
	assert_bool(_scores_exist()).is_false()


func test_training_off_keeps_socket_without_rival_views() -> void:
	Settings.training_payload = "off"
	var gp := _launch(false, true)
	await get_tree().process_frame
	var v := gp.versus
	assert_object(v).is_not_null()
	assert_object(v.drone).is_null()
	assert_int(v.bots.size()).is_equal(0)
	assert_object(v.periscope_column).is_null()
	assert_object(v.killfeed).is_null()
	assert_object(gp.find_child("PeriscopeColumn", true, false)).is_null()
	assert_object(gp.find_child("Killfeed", true, false)).is_null()
	assert_object(gp.find_child("RewardSocket", true, false)).is_not_null()
	assert_bool(gp.score.no_fail).is_true()


# ---- solo path and the stale launch record ------------------------------------------------

func test_plain_solo_dive_has_no_controller() -> void:
	var gp := _launch(false, false)
	await get_tree().process_frame
	assert_object(gp.versus).is_null()
	assert_object(gp.find_child("VersusController", true, false)).is_null()
	assert_object(gp.find_child("VersusHud", true, false)).is_null()
	assert_bool(gp.judge is VersusJudge).is_false()
	assert_str(gp.judge.get_script().get_global_name()).is_equal("InputJudge")


func _main_menu() -> MainMenu:
	MainMenu.boot_handled = true
	var m: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	m.navigate = func(_p: String) -> void: pass
	add_child(m)
	auto_free(m)
	return m


func test_stale_versus_record_is_cleared_by_start_dive() -> void:
	MatchSetup.pending = _setup(3)  # Versus Bots opened, then the player went back
	var m := _main_menu()
	await get_tree().process_frame
	m.launch(false)  # Start Dive
	assert_object(MatchSetup.pending).is_null()
	var gp := _launch(false, false)
	await get_tree().process_frame
	assert_object(gp.versus).is_null()
	assert_str(gp.judge.get_script().get_global_name()).is_equal("InputJudge")
	assert_object(MatchSetup.pending).is_null()


func test_stale_versus_record_is_cleared_by_solo_dive() -> void:
	MatchSetup.pending = _setup(3)
	var m := _main_menu()
	await get_tree().process_frame
	m.launch_practice()
	assert_object(MatchSetup.pending).is_null()
	var gp := _launch(false, true)
	await get_tree().process_frame
	assert_object(gp.match_setup).is_null()
	assert_object(gp.versus).is_not_null()  # Solo Dive runs through the controller
	assert_int(gp.versus.bots.size()).is_equal(0)
	assert_object(gp.versus.periscope_column).is_null()
	assert_object(MatchSetup.pending).is_null()


func test_pending_record_is_ignored_for_practice_and_autoplay_launches() -> void:
	MatchSetup.pending = _setup(3)
	var gp := _launch(true, false)  # autoplay dive
	await get_tree().process_frame
	assert_object(gp.match_setup).is_null()
	assert_object(gp.versus).is_null()
	assert_object(MatchSetup.pending).is_null()
	MatchSetup.pending = _setup(2)
	var gp2 := _launch(false, true)  # practice dive
	await get_tree().process_frame
	assert_object(gp2.match_setup).is_null()
	assert_int(gp2.versus.bots.size()).is_equal(0)
	assert_object(MatchSetup.pending).is_null()


func test_rematch_rebuilds_with_a_new_seed() -> void:
	var gp := _launch_versus(2, false)
	await get_tree().process_frame
	var old_seed := gp.versus.match_seed
	var old_ctrl := gp.versus
	gp._on_rematch()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(gp.versus).is_not_null()
	assert_bool(gp.versus != old_ctrl).is_true()
	assert_int(gp.versus.match_seed).is_not_equal(old_seed)
	assert_int(gp.versus.bots.size()).is_equal(2)
	assert_bool(gp.pause_menu.match_mode).is_true()
