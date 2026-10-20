extends GdUnitTestSuite
## 04-14: the online branch of Gameplay driven with a fake NetSession (UI-SPEC 16 row):
## sync overlay states, the scheduled begin and countdown, the keep-out exception, the
## non-pausing Leave overlay, PLAYER_LEFT views, the link chip, HOST LEFT / CONNECTION LOST,
## DONE / results / back to lobby, a late START and the idle conductor before START.

const SCENE := "res://scenes/gameplay.tscn"
const TIMEOUT_MSEC := 15000


## Records every call Gameplay makes; tests emit the session signals by hand.
class FakeSession extends Node:
	signal start_scheduled
	signal results_due(end_t: float)
	signal results_received(data: Dictionary)
	signal returned_to_lobby
	signal host_left(kind: String)
	signal match_aborted_to_lobby(code: String, who: String)
	signal link_weak_changed(weak: bool)
	signal left_lobby(code: String)

	var spec: Dictionary = {}
	var lead: float = 2.4
	var since: float = 0.0
	var still: int = 0
	var calls: Dictionary = {}
	var done_t: float = NAN
	var sent_results: Array = []
	var pumped_nan: int = 0
	var pumped: int = 0
	var bound: String = ""

	func count(k: String) -> int:
		return int(calls.get(k, 0))

	func _hit(k: String) -> void:
		calls[k] = count(k) + 1

	func pending_match() -> Dictionary:
		return spec.duplicate(true)

	func report_loaded() -> void:
		_hit("report_loaded")

	func report_load_failed() -> void:
		_hit("report_load_failed")

	func lead_in_for_start() -> float:
		_hit("lead_in_for_start")
		return lead

	func bind_host_match(_q: HostInputQueue, _c: NetHostChannel, _n: int, _len: float) -> void:
		bound = "host"

	func bind_client_match(_r: RemoteReferee, _c: NetClientChannel, _n: int, _len: float) -> void:
		bound = "client"

	func send_to_host(_msg: Dictionary) -> void:
		_hit("send_to_host")

	func pump_match(t: float) -> void:
		if is_nan(t):
			pumped_nan += 1
		else:
			pumped += 1

	func seconds_since_host_packet() -> float:
		return since

	func ping_ms() -> int:
		return 42

	func leave() -> void:
		_hit("leave")

	func report_done(t: float) -> void:
		_hit("report_done")
		done_t = t

	func still_diving() -> int:
		return still

	func host_send_results(data: Dictionary) -> void:
		_hit("host_send_results")
		sent_results.append(data)

	func host_back_to_lobby() -> void:
		_hit("host_back_to_lobby")


var _navs: Array = []


func before_test() -> void:
	_navs = []
	Gameplay.pending_intro = IntroTimeline.Mode.NONE


func after_test() -> void:
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
	MatchSetup.pending = null


static func _spec(role: String, seat: int, names: Array, max_s: float = 0.0) -> Dictionary:
	var seats: Array = []
	for i in names.size():
		seats.append(i)
	var margins := {}
	if role == "host":
		for i in names.size():
			margins[i] = 0.0 if i == 0 else 0.03
	return {"role": role, "local_seat": seat, "names": PackedStringArray(names), "seats": seats,
		"fp": "x", "sig": "x", "diff": "expert", "title": "Short chart", "artist": "",
		"seed": 7, "flight": 2, "d_s": 0.08, "max_song_s": max_s, "autoplay": false,
		"margins": margins}


func _fake(spec: Dictionary) -> FakeSession:
	var f := FakeSession.new()
	f.spec = spec
	auto_free(f)
	return f


func _launch(f: FakeSession) -> Gameplay:
	Gameplay.pending_chart = TestCharts.short_chart()
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	gp.session = f
	gp.navigate = func(p: String) -> void: _navs.append(p)
	add_child(gp)
	auto_free(gp)
	return gp


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until_time(gp: Gameplay, t: float) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if gp.is_began() and gp.conductor != null and gp.conductor.song_time() >= t:
			return
		await get_tree().process_frame


## Launch, let LOADED go out, then START with the fake's lead.
func _started(f: FakeSession, lead: float = 0.6) -> Gameplay:
	var gp := _launch(f)
	await _frames(2)
	f.lead = lead
	f.start_scheduled.emit()
	return gp


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


static func _action(a: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	return ev


static func _conductor_idle(gp: Gameplay) -> bool:
	return gp.conductor.clock.state == ClockModel.State.IDLE


# ---- 1. sync overlay -----------------------------------------------------------------------

func test_sync_overlay_loading_then_linking_and_no_intro() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO", "ORCA"]))
	var gp := _launch(f)
	assert_bool(gp.is_online()).is_true()
	assert_object(gp.intro).is_null()
	assert_object(gp.start_sync_overlay).is_not_null()
	assert_str(gp.start_sync_overlay.title_text()).is_equal("LOADING SONG")
	assert_int(gp.start_sync_overlay.line_texts().size()).is_equal(3)
	assert_str(f.bound).is_equal("client")
	assert_bool(gp.versus.net_send.is_valid()).is_true()
	await _frames(1)
	assert_str(gp.start_sync_overlay.title_text()).is_equal("LINKING SUBS")
	assert_int(f.count("report_loaded")).is_equal(1)
	var lines := gp.start_sync_overlay.line_texts()
	assert_str(str(lines[1]["name"])).is_equal("YOU")
	assert_str(str(lines[1]["status"])).is_equal("LOADED")
	assert_str(str(lines[0]["status"])).is_equal("LOADING")
	# Render order: VersusHud < StartSyncOverlay < LeaveOverlay < PauseMenu.
	var root := gp.start_sync_overlay.get_parent()
	assert_int(gp.versus.versus_hud.get_index()).is_less(gp.start_sync_overlay.get_index())
	assert_int(gp.start_sync_overlay.get_index()).is_less(gp.leave_overlay.get_index())
	assert_int(gp.leave_overlay.get_index()).is_less(gp.pause_menu.get_index())
	assert_object(gp.leave_overlay.get_parent()).is_same(root)


# ---- 9. idle before START ------------------------------------------------------------------

func test_conductor_idle_until_start_scheduled() -> void:
	var f := _fake(_spec("host", 0, ["NEMO", "MAKO"]))
	var gp := _launch(f)
	assert_str(f.bound).is_equal("host")
	await _frames(30)
	assert_int(f.count("report_loaded")).is_equal(1)
	assert_bool(gp.is_began()).is_false()
	assert_bool(_conductor_idle(gp)).is_true()
	assert_bool(gp.lane_input.enabled).is_false()
	assert_int(f.pumped_nan).is_greater_equal(25)  # control packets flow before START
	assert_int(f.pumped).is_equal(0)
	f.lead = 2.4
	f.start_scheduled.emit()
	assert_bool(gp.is_began()).is_true()
	assert_bool(_conductor_idle(gp)).is_false()
	assert_bool(gp.lane_input.enabled).is_true()
	assert_float(gp.conductor.song_time()).is_less(-2.3)
	await _frames(2)
	assert_int(f.pumped).is_greater(0)


# ---- 8. late START -------------------------------------------------------------------------

func test_late_lead_never_begins_the_conductor() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := _launch(f)
	await _frames(2)
	f.lead = -1.0
	f.start_scheduled.emit()
	await _frames(10)
	assert_int(f.count("lead_in_for_start")).is_equal(1)
	assert_bool(gp.is_began()).is_false()
	assert_bool(_conductor_idle(gp)).is_true()
	assert_bool(gp.lane_input.enabled).is_false()
	# The host then aborts everyone to the lobby.
	f.match_aborted_to_lobby.emit("start_late", "MAKO")
	assert_int(_navs.size()).is_equal(1)
	assert_bool(str(_navs[0]) in [Gameplay.LOBBY_SCENE, Gameplay.ONLINE_MENU_SCENE]).is_true()


# ---- 2. countdown + keep-out exception -----------------------------------------------------

func test_countdown_digits_follow_song_time_and_sync_overlay_is_gone_before_notes() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := _launch(f)
	await _frames(2)
	f.lead = 2.4
	f.start_scheduled.emit()
	var begin_t := gp.conductor.song_time()
	assert_float(begin_t).is_less_equal(-2.39)
	var overlay := gp.start_sync_overlay
	assert_bool(overlay.is_dismissing()).is_true()
	var banner := gp.versus.event_banner
	var gone_t := NAN
	var seen := {}
	var first_text := ""
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var t := gp.conductor.song_time()
		if is_nan(gone_t) and not is_instance_valid(overlay):
			gone_t = t
		var txt := banner.headline_text()
		if first_text == "" and txt != "":
			first_text = txt
		if txt != "":
			if t < -2.0 and txt == "DIVE IN 3":
				seen["3"] = true
			if t >= -0.95 and t < 0.0 and txt == "DIVE IN 1":
				seen["1"] = true
			if t >= 0.0 and t < 0.6 and txt == "DIVE":
				seen["dive"] = true
		if t >= 0.5:
			break
	assert_str(first_text).is_equal("DIVE IN 3")
	assert_bool(seen.has("3")).is_true()
	assert_bool(seen.has("1")).is_true()
	assert_bool(seen.has("dive")).is_true()
	assert_str(EventBanner.countdown_text_at(-2.4)).is_equal("DIVE IN 3")
	assert_str(EventBanner.countdown_text_at(-0.2)).is_equal("DIVE IN 1")
	assert_str(EventBanner.countdown_text_at(0.0)).is_equal("DIVE")
	# Gone within DUR_BASE (+ frame slack) of begin, before the first note can be drawn.
	assert_bool(is_nan(gone_t)).is_false()
	assert_float(gone_t).is_less_equal(begin_t + Palette.DUR_BASE + 0.1)
	var first_note := float(gp.chart.notes[0]["time"])
	assert_float(gone_t).is_less(first_note - Trench.approach_for(Settings.scroll_speed))


# ---- 3. leave overlay never pauses ---------------------------------------------------------

func test_leave_overlay_is_non_pausing_and_space_does_not_fire() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	await _until_time(gp, 0.1)
	var presses := [0]
	gp.lane_input.lane_pressed.connect(func(_l: int, _t: int) -> void: presses[0] += 1)
	var judged := [0]
	gp.judge.judged.connect(func(_a: int, _b: int, _c: int, _d: float) -> void: judged[0] += 1)
	gp.judge.stray.connect(func(_a: int) -> void: judged[0] += 1)
	_key(KEY_NONE, KEY_ESCAPE)
	await _frames(1)
	assert_bool(gp.leave_overlay.is_open()).is_true()
	assert_bool(gp.pause_menu.is_open()).is_false()
	assert_str(gp.leave_overlay.ping_text()).is_equal("PING 42 MS")
	var t0 := gp.conductor.song_time()
	await _frames(10)
	assert_float(gp.conductor.song_time()).is_greater(t0)
	assert_bool(gp.conductor.is_paused()).is_false()
	assert_bool(get_tree().paused).is_false()
	# A lane press is judged behind the overlay.
	_key(KEY_NONE, KEY_1, 49)
	await _frames(1)
	assert_int(presses[0]).is_greater_equal(1)
	assert_int(judged[0]).is_greater_equal(1)
	assert_bool(gp.leave_overlay.is_open()).is_true()
	# Space (ui_accept + fire) picks Stay and does not fire.
	_key(KEY_SPACE, KEY_SPACE, 32)
	await _frames(1)
	assert_int(gp.fire_count).is_equal(0)
	assert_bool(gp.leave_overlay.is_open()).is_false()
	assert_bool(gp.pause_menu.is_open()).is_false()
	# Closed: Space fires again (the probe above was meaningful).
	_key(KEY_SPACE, KEY_SPACE, 32)
	await _frames(1)
	assert_int(gp.fire_count).is_equal(1)
	# Reopen and confirm Leave Match: session.leave, then the main menu.
	_key(KEY_NONE, KEY_ESCAPE)
	await _frames(1)
	assert_bool(gp.leave_overlay.is_open()).is_true()
	assert_bool(gp.leave_overlay.handle_event(_action(&"ui_left"))).is_true()
	assert_str(gp.leave_overlay.focus_name()).is_equal("leave")
	assert_bool(gp.leave_overlay.handle_event(_action(&"ui_accept"))).is_true()
	assert_int(f.count("leave")).is_equal(1)
	assert_array(_navs).contains([Gameplay.MENU_SCENE])
	assert_bool(gp.pause_menu.is_open()).is_false()


func test_f4_restart_is_disabled_online() -> void:
	var f := _fake(_spec("host", 0, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	await _until_time(gp, 0.0)
	var c := gp.conductor
	gp._unhandled_input(_action(&"debug_autoplay"))
	await _frames(1)
	assert_object(gp.conductor).is_same(c)
	assert_bool(gp.autoplay_used).is_false()


# ---- 4. PLAYER_LEFT ------------------------------------------------------------------------

func test_player_left_marks_periscope_and_replaces_killfeed_line() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO", "ORCA"]))
	var gp := await _started(f, 0.6)
	await _until_time(gp, 0.1)
	var t := gp.conductor.song_time()
	gp.versus.client_channel.receive({"seq": 1, "events": [
		{"type": GameEvent.IMPLODED, "t": t, "seat": 2},
		{"type": GameEvent.PLAYER_LEFT, "t": t, "seat": 2, "reason": "disconnected"}]})
	await _frames(2)
	assert_int(gp.versus.client_channel.rejected_events).is_equal(0)
	assert_bool(gp.versus.periscope_column.panel_for(2).is_left()).is_true()
	var lines := gp.versus.killfeed.lines()
	assert_int(lines.size()).is_equal(1)
	assert_str(str(lines[0]["text"]).to_lower()).contains("left")
	var st: Dictionary = gp.last_status()[2]
	assert_bool(st["left"]).is_true()
	assert_bool(st["alive"]).is_false()


# ---- 5. link chip --------------------------------------------------------------------------

func test_link_chip_follows_seconds_since_host_packet() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	await _frames(2)
	assert_bool(gp.versus.status_chips.is_link_weak()).is_false()
	f.since = 1.2
	await _frames(2)
	assert_bool(gp.versus.status_chips.is_link_weak()).is_true()
	f.since = 0.1
	await _frames(2)
	assert_bool(gp.versus.status_chips.is_link_weak()).is_false()


func test_host_never_shows_the_link_chip() -> void:
	var f := _fake(_spec("host", 0, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	f.since = 9.0
	await _frames(3)
	assert_bool(gp.versus.status_chips.is_link_weak()).is_false()


# ---- 6. host left --------------------------------------------------------------------------

func test_host_left_stops_the_song_and_shows_last_standings() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	await _until_time(gp, 0.1)
	var t := gp.conductor.song_time()
	gp.versus.client_channel.receive({"seq": 1, "events": [
		{"type": GameEvent.STATUS, "t": t, "seat": 0, "hull": 37.5, "depth": 120.0, "alive": true,
			"place": 2, "accuracy": 0.9},
		{"type": GameEvent.STATUS, "t": t, "seat": 1, "hull": 80.0, "depth": 100.0, "alive": true,
			"place": 1, "accuracy": 0.95}]})
	await _frames(1)
	f.host_left.emit("host_left")
	assert_object(gp.host_left_dialog).is_not_null()
	assert_str(gp.host_left_dialog.title_text()).is_equal("HOST LEFT")
	assert_bool(_conductor_idle(gp)).is_true()
	assert_bool(gp.lane_input.enabled).is_false()
	var rows: Array = gp.host_left_dialog.debug_state()["rows"]
	assert_int(rows.size()).is_equal(2)
	var pumps := f.pumped
	await _frames(5)
	assert_int(f.pumped).is_equal(pumps)  # the match is over on this PC
	gp.host_left_dialog.back_to_menu.emit()
	assert_array(_navs).contains([Gameplay.MENU_SCENE])


func test_connection_lost_during_sync_shows_connection_lost() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := _launch(f)
	await _frames(2)
	f.host_left.emit("connection_lost")
	assert_str(gp.host_left_dialog.title_text()).is_equal("CONNECTION LOST")
	assert_object(gp.start_sync_overlay).is_null()
	assert_bool(gp.is_began()).is_false()
	assert_bool(gp.lane_input.enabled).is_false()
	# A START arriving after the loss never begins the song.
	f.start_scheduled.emit()
	assert_bool(gp.is_began()).is_false()


# ---- 7. DONE / results / back to lobby -----------------------------------------------------

func test_host_done_results_due_sends_results_once_and_back_to_lobby() -> void:
	var f := _fake(_spec("host", 0, ["NEMO", "MAKO"], 1.5))
	f.still = 1
	var gp := await _started(f, 0.6)
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while f.count("report_done") == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(f.count("report_done")).is_equal(1)
	assert_float(f.done_t).is_between(1.5, 1.8)
	assert_bool(gp.lane_input.enabled).is_false()
	assert_object(gp.versus_results).is_null()
	await _frames(2)
	assert_str(gp.versus.event_banner.headline_text()).is_equal("WAITING FOR RESULTS")
	assert_int(f.count("report_done")).is_equal(1)
	f.results_due.emit(f.done_t)
	f.results_due.emit(f.done_t)  # a second emission changes nothing
	assert_int(f.count("host_send_results")).is_equal(1)
	var data: Dictionary = f.sent_results[0]
	assert_bool(data["online"]).is_true()
	assert_bool(data["is_host"]).is_true()
	assert_str(str(data["host_name"])).is_equal("NEMO")
	assert_int((data["rows"] as Array).size()).is_equal(2)
	assert_object(gp.versus_results).is_not_null()
	var st := gp.versus_results.online_state()
	assert_array(st["buttons"]).contains(["Back to Lobby"])
	assert_bool(gp.is_done()).is_true()
	gp.versus_results.back_to_lobby_pressed.emit()
	assert_int(f.count("host_back_to_lobby")).is_equal(1)
	assert_int(_navs.size()).is_equal(1)


func test_client_done_then_results_received_shows_leave_lobby() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"], 1.2))
	var gp := await _started(f, 0.6)
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while f.count("report_done") == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(f.count("report_done")).is_equal(1)
	await _frames(2)
	assert_str(gp.versus.event_banner.headline_text()).is_equal("WAITING FOR RESULTS")
	var rows := [
		{"seat": 0, "place": 1, "alive": true, "depth": 300.0, "hull": 90.0, "accuracy": 0.9,
			"eliminated_at": INF, "name": "NEMO", "landed": 0, "reflected": 0},
		{"seat": 1, "place": 2, "alive": true, "depth": 200.0, "hull": 70.0, "accuracy": 0.8,
			"eliminated_at": INF, "name": "MAKO", "landed": 0, "reflected": 0}]
	f.results_received.emit({"rows": rows, "local_seat": 1, "medals": {}, "title": "Short chart",
		"artist": "", "difficulty": "expert", "seed": 7, "last_standing_seat": -1,
		"online": true, "is_host": false, "host_seat": 0, "host_name": "NEMO"})
	assert_object(gp.versus_results).is_not_null()
	assert_int(f.count("host_send_results")).is_equal(0)
	var st := gp.versus_results.online_state()
	assert_array(st["buttons"]).contains(["Leave Lobby"])
	assert_str(str(st["waiting_line"])).contains("NEMO")
	# The host closes the lobby from RESULTS.
	f.left_lobby.emit("closed")
	assert_bool(gp.versus_results.online_state()["lobby_closed"]).is_true()
	assert_object(gp.host_left_dialog).is_null()


func test_returned_to_lobby_navigates_to_the_lobby() -> void:
	var f := _fake(_spec("client", 1, ["NEMO", "MAKO"]))
	var gp := await _started(f, 0.6)
	assert_bool(gp.is_began()).is_true()
	f.returned_to_lobby.emit()
	assert_int(_navs.size()).is_equal(1)
	assert_bool(str(_navs[0]) in [Gameplay.LOBBY_SCENE, Gameplay.ONLINE_MENU_SCENE]).is_true()
