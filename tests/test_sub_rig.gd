extends GdUnitTestSuite
## 03-07 Task 1 (D-28): SubRig wires one seat's VersusJudge + VersusHull + PayloadStack to the
## MatchSim referee through time-stamped calls and EventChannel events.
## click_chart(120): a note every 0.5 s (lane = beat % 4), 2 s per bar.

const P := InputJudge.Judgment.PERFECT

var _ev: Array = []
var _players: Array[PlayerState] = []
var _chart: ChartData
var _ch: LoopbackChannel
var _sim: MatchSim


func _rig(beats: int = 200, no_fail: bool = false) -> SubRig:
	_chart = TestCharts.click_chart(120.0, beats, 1000)
	_players = []
	for s in range(2):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	_ch = LoopbackChannel.new()
	_ev = []
	_ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	var cfg := VersusConfig.new()
	_sim = MatchSim.new(_chart, cfg, JudgeConfig.new(), _players, _ch, 3)
	return SubRig.new(0, _chart, JudgeConfig.new(), cfg, _sim, _ch, no_fail)


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _landed(rig_seat: int, id: int, reward: int, start: float, end: float) -> Dictionary:
	return GameEvent.make(GameEvent.LANDED, start - 1.5, {"id": id, "from": 1, "to": rig_seat,
		"reward": reward, "arrive_t": start - 1.5, "active_start": start, "end_t": end,
		"seed": 77, "reflected": false, "debris": false})


func test_perfect_press_reaches_the_meter_and_status() -> void:
	var rig := _rig()
	rig.press(1, 0.5)  # beat 1 -> lane 1 at 0.5 s
	assert_int(_players[0].meter.progress).is_equal(1)
	assert_int(rig.perfect).is_equal(1)
	assert_float(_players[0].depth).is_equal_approx(rig.hull.depth(), 1e-9)
	assert_float(_players[0].depth).is_greater(0.0)
	assert_float(_players[0].accuracy).is_equal_approx(1.0, 1e-9)
	assert_float(_players[0].hull).is_equal(rig.hull.hull)


func test_judgment_time_is_note_time_plus_error() -> void:
	var rig := _rig()
	var seen: Array = []
	rig.judgment_reported.connect(func(idx: int, j: int, t: float) -> void: seen.append([idx, j, t]))
	rig.press(1, 0.53)
	assert_int(seen.size()).is_equal(1)
	assert_float(seen[0][2]).is_equal_approx(0.53, 1e-9)
	# The note at 0.0 was expired by that press: MISS stamped at the press time (deterministic).
	rig.tick(2.0)
	for s in seen:
		assert_bool(s[2] <= 2.0).is_true()


func test_overclock_upgrades_good_score_because_rig_sets_hull_now() -> void:
	var rig := _rig()
	_ch.send(GameEvent.make(GameEvent.BUFF_APPLIED, 0.2,
		{"seat": 0, "reward": Reward.Id.OVERCLOCK, "until_t": 8.0, "amount": 0.0}))
	assert_float(rig.hull.overclock_until).is_equal(8.0)
	rig.press(1, 0.57)  # GOOD (70 ms) at t < 8 -> Perfect value
	assert_int(rig.hull.score).is_equal(100)


func test_ballast_heals_amount_and_other_seats_are_ignored() -> void:
	var rig := _rig()
	rig.hull.ghost_hit(9, 40.0, 40.0)
	assert_float(rig.hull.hull).is_equal(60.0)
	_ch.send(GameEvent.make(GameEvent.BUFF_APPLIED, 1.0,
		{"seat": 1, "reward": Reward.Id.BALLAST_PATCH, "until_t": 1.0, "amount": 25.0}))
	assert_float(rig.hull.hull).is_equal(60.0)
	_ch.send(GameEvent.make(GameEvent.BUFF_APPLIED, 1.0,
		{"seat": 0, "reward": Reward.Id.BALLAST_PATCH, "until_t": 1.0, "amount": 25.0}))
	assert_float(rig.hull.hull).is_equal(85.0)
	assert_float(_players[0].hull).is_equal(85.0)


func test_landed_ghost_notes_adds_tagged_overlay_inside_window() -> void:
	var rig := _rig()
	var added: Array = []
	rig.overlay_added.connect(func(id: int, notes: Array) -> void: added.append([id, notes]))
	_ch.send(_landed(0, 5, Reward.Id.GHOST_NOTES, 10.0, 18.0))
	var ov := rig.judge.overlay_notes()
	assert_int(ov.size()).is_greater(0)
	for n in ov:
		assert_int(n["kind"]).is_equal(VersusJudge.GHOST)
		assert_int(n["payload_id"]).is_equal(5)
		assert_bool(n["time"] >= 10.0 - 1e-6 and n["time"] < 18.0).is_true()
	assert_int(rig.stack.active_reward(12.0)).is_equal(Reward.Id.GHOST_NOTES)
	assert_int(added.size()).is_equal(1)
	assert_int(added[0][0]).is_equal(5)
	# A LANDED on another seat changes nothing here.
	_ch.send(_landed(1, 6, Reward.Id.GHOST_NOTES, 30.0, 38.0))
	assert_int(rig.judge.overlay_notes().size()).is_equal(ov.size())


func test_landed_depth_charge_adds_depth_notes() -> void:
	var rig := _rig()
	_ch.send(_landed(0, 8, Reward.Id.DEPTH_CHARGE, 10.0, 14.0))
	var ov := rig.judge.overlay_notes()
	assert_int(ov.size()).is_greater_equal(2)
	for n in ov:
		assert_int(n["kind"]).is_equal(VersusJudge.DEPTH)
		assert_int(n["payload_id"]).is_equal(8)


func test_depth_perfect_credits_the_meter() -> void:
	var rig := _rig()
	_ch.send(_landed(0, 8, Reward.Id.DEPTH_CHARGE, 10.0, 14.0))
	var n: Dictionary = rig.judge.overlay_notes()[0]
	# Play every base note before it perfectly so only the overlay decides the delta.
	for note in _chart.notes:
		if note["time"] < n["time"]:
			rig.press(note["lane"], note["time"])
	var before := _players[0].meter.progress
	var held_before := _players[0].meter.held
	rig.press(n["lane"], n["time"])
	assert_int(rig.depth_perfect).is_equal(1)
	if held_before == -1:
		assert_bool(_players[0].meter.progress == before + 1 or _players[0].meter.held != -1).is_true()


func test_reflected_payload_end_clears_overlay_and_ends_stack_early() -> void:
	var rig := _rig()
	_ch.send(_landed(0, 5, Reward.Id.GHOST_NOTES, 10.0, 18.0))
	_ch.send(GameEvent.make(GameEvent.PAYLOAD_END, 12.0,
		{"id": 5, "seat": 0, "reward": Reward.Id.GHOST_NOTES, "reason": "reflected",
		"immune_until": 14.0}))
	for n in rig.judge.overlay_notes():
		assert_bool(n["time"] < 12.0).is_true()
	assert_int(rig.stack.active_reward(16.0)).is_equal(-1)


func test_warhead_events_mark_confirm_and_kill() -> void:
	var rig := _rig()
	_ch.send(GameEvent.make(GameEvent.TORPEDO_LAUNCH, 3.0, {"id": 4, "from": 1, "to": 0,
		"reward": Reward.Id.INK_CLOUD, "launch_beat": 6, "launch_t": 3.0, "arrive_t": 3.5,
		"warheads": [7, 8, 9, 10], "reflected": false, "debris": false}))
	assert_int(rig.stack.warhead_state(7)).is_equal(PayloadStack.OPEN)
	_ch.send(GameEvent.make(GameEvent.WARHEAD, 3.5,
		{"id": 4, "seat": 0, "note": 7, "k": 1, "n": 4, "ok": true}))
	assert_int(rig.stack.warhead_state(7)).is_equal(PayloadStack.CONFIRMED)
	_ch.send(GameEvent.make(GameEvent.WARHEAD, 4.0,
		{"id": 4, "seat": 0, "note": 8, "k": 1, "n": 4, "ok": false}))
	assert_int(rig.stack.warhead_state(9)).is_equal(PayloadStack.DEAD)


func test_hull_failure_eliminates_through_on_failed() -> void:
	var rig := _rig()
	rig.tick(20.0)  # every note up to ~19.9 s missed: 8 damage each
	assert_bool(rig.hull.is_failed).is_true()
	assert_bool(_players[0].alive).is_false()
	var imp := _of(GameEvent.IMPLODED)
	assert_int(imp.size()).is_equal(1)
	assert_float(imp[0]["t"]).is_less_equal(20.0)


func test_no_fail_rig_never_eliminates() -> void:
	var rig := _rig(200, true)
	rig.tick(20.0)
	assert_bool(_players[0].alive).is_true()
	assert_int(_of(GameEvent.IMPLODED).size()).is_equal(0)


func test_approach_s_feeds_player_state() -> void:
	var rig := _rig()
	rig.approach_s = 0.9
	assert_float(_players[0].approach_s).is_equal(0.9)
