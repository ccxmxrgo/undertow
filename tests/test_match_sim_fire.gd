extends GdUnitTestSuite
## 03-03 Task 2: MatchSim firing, beat-snapped flight, shields, races, collisions, immunity and
## targeting (TORP-02..05, D-01..D-07, spec req 9). click_chart(120): 0.5 s per beat, 2 s per bar.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const INK := Reward.Id.INK_CLOUD
const DECOY := Reward.Id.DECOY_FLARE

var _ev: Array = []
var _players: Array[PlayerState] = []
var _chart: ChartData


func _sim(beats: int = 256, cfg: VersusConfig = null) -> MatchSim:
	_chart = TestCharts.click_chart(120.0, beats, 1000)
	if cfg == null:
		cfg = VersusConfig.new()
	_players = []
	for s in range(4):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	return MatchSim.new(_chart, cfg, JudgeConfig.new(), _players, ch, 7)


## Test setup: force a held reward without playing notes.
func _give(seat: int, id: int) -> void:
	_players[seat].meter.progress = _players[seat].meter.target
	_players[seat].meter.held = id


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_threshold_from_chart() -> void:
	var sim := _sim()
	assert_int(sim.threshold).is_equal(31)
	assert_int(_players[2].meter.target).is_equal(31)


func test_press_mid_beat_launches_next_beat_and_arrives_one_beat_later() -> void:
	var sim := _sim()
	_give(1, INK)
	assert_int(sim.request_fire(1, 1.10)).is_equal(MatchSim.FIRE_OK)
	var q := _of(GameEvent.FIRE_QUEUED)
	assert_int(q.size()).is_equal(1)
	assert_int(q[0]["launch_beat"]).is_equal(3)
	assert_int(q[0]["to"]).is_equal(0)
	assert_int(_players[1].meter.held).is_equal(INK)
	sim.update(1.49)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(0)
	sim.update(1.50)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(1)
	assert_float(l[0]["launch_t"]).is_equal_approx(1.5, 1e-9)
	assert_float(l[0]["arrive_t"]).is_equal_approx(2.0, 1e-9)
	assert_float(l[0]["t"]).is_equal_approx(1.5, 1e-9)
	assert_int(l[0]["from"]).is_equal(1)
	assert_int(l[0]["to"]).is_equal(0)
	assert_int(_players[1].meter.held).is_equal(-1)
	assert_int(_players[0].incoming_id).is_equal(l[0]["id"])
	sim.update(1.99)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(0)
	sim.update(2.0)
	var land := _of(GameEvent.LANDED)
	assert_int(land.size()).is_equal(1)
	assert_int(land[0]["to"]).is_equal(0)
	assert_int(_players[0].incoming_id).is_equal(-1)
	assert_bool(_players[0].active.is_empty()).is_false()
	assert_int(_players[1].landed).is_equal(1)


func test_press_exactly_on_beat_launches_next_beat() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 2.0)
	assert_int(_of(GameEvent.FIRE_QUEUED)[0]["launch_beat"]).is_equal(5)
	assert_int(MatchSim.launch_beat(2.0, _chart.tempo_map)).is_equal(5)
	assert_int(MatchSim.launch_beat(1.9999999, _chart.tempo_map)).is_equal(5)


func test_every_launch_is_telegraphed_at_least_one_beat() -> void:
	var sim := _sim()
	var t := 1.1
	for k in range(6):
		_give(1 + k % 3, INK)
		sim.request_fire(1 + k % 3, t)
		t += 7.3
		sim.update(t)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_greater(0)
	for e in l:
		assert_float(e["arrive_t"] - e["launch_t"]).is_greater_equal(0.5 - 1e-9)


func test_fire_at_target_with_incoming_is_refused_and_kept() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	_give(2, Reward.Id.SONAR_JAM)
	assert_int(sim.request_fire(2, 1.7)).is_equal(MatchSim.FIRE_SHIELDED)
	var r := _of(GameEvent.FIRE_REFUSED)
	assert_int(r.size()).is_equal(1)
	assert_str(r[0]["reason"]).is_equal("shielded")
	assert_int(_players[2].meter.held).is_equal(Reward.Id.SONAR_JAM)


func test_fire_at_target_with_active_payload_is_refused() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(3.0)
	_give(2, INK)
	assert_int(sim.request_fire(2, 3.1)).is_equal(MatchSim.FIRE_SHIELDED)
	assert_int(_players[2].meter.held).is_equal(INK)


func test_same_beat_race_lower_seat_launches_other_keeps_reward() -> void:
	var sim := _sim()
	_give(1, INK)
	_give(2, Reward.Id.SONAR_JAM)
	assert_int(sim.request_fire(1, 1.1)).is_equal(MatchSim.FIRE_OK)
	assert_int(sim.request_fire(2, 1.2)).is_equal(MatchSim.FIRE_OK)
	sim.update(1.5)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(1)
	assert_int(l[0]["from"]).is_equal(1)
	var r := _of(GameEvent.FIRE_REFUSED)
	assert_int(r.size()).is_equal(1)
	assert_int(r[0]["seat"]).is_equal(2)
	assert_str(r[0]["reason"]).is_equal("race")
	assert_int(_players[2].meter.held).is_equal(Reward.Id.SONAR_JAM)


func test_race_order_is_seat_order_not_press_order() -> void:
	var sim := _sim()
	_give(1, INK)
	_give(2, INK)
	sim.request_fire(2, 1.05)
	sim.request_fire(1, 1.2)
	sim.update(1.5)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH)[0]["from"]).is_equal(1)


func test_second_fire_while_pending_returns_pending() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	assert_int(sim.request_fire(1, 1.2)).is_equal(MatchSim.FIRE_PENDING)
	assert_int(_of(GameEvent.FIRE_QUEUED).size()).is_equal(1)


func test_head_on_same_beat_collides() -> void:
	var sim := _sim()
	_give(0, INK)
	_give(1, Reward.Id.GHOST_NOTES)
	# All depths 0: AUTO for seat 0 is seat 1 and for seat 1 is seat 0.
	sim.request_fire(0, 1.1)
	sim.request_fire(1, 1.3)
	sim.update(4.0)
	var c := _of(GameEvent.COLLISION)
	assert_int(c.size()).is_equal(1)
	assert_int(c[0]["a"]).is_equal(0)
	assert_int(c[0]["b"]).is_equal(1)
	assert_int(c[0]["reward_a"]).is_equal(INK)
	assert_int(c[0]["reward_b"]).is_equal(Reward.Id.GHOST_NOTES)
	assert_int(c[0]["ids"].size()).is_equal(2)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(0)
	assert_int(_players[0].meter.held).is_equal(-1)
	assert_int(_players[1].meter.held).is_equal(-1)
	assert_int(_players[0].collisions).is_equal(1)
	assert_int(_players[1].collisions).is_equal(1)
	# Collisions start no immunity.
	assert_bool(_players[0].is_shielded(4.0)).is_false()
	assert_bool(_players[1].is_shielded(4.0)).is_false()


func test_fire_back_after_arrival_does_not_collide() -> void:
	var sim := _sim()
	_give(0, INK)
	sim.request_fire(0, 1.1)
	sim.update(2.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	_give(1, Reward.Id.SONAR_JAM)
	assert_int(sim.request_fire(1, 2.1)).is_equal(MatchSim.FIRE_OK)
	sim.update(3.5)
	assert_int(_of(GameEvent.COLLISION).size()).is_equal(0)
	var l := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(l.size()).is_equal(2)
	assert_int(l[1]["from"]).is_equal(1)
	assert_int(l[1]["to"]).is_equal(0)


func test_fire_back_during_flight_snaps_to_arrival_beat_no_collision() -> void:
	var sim := _sim()
	_give(0, INK)
	sim.request_fire(0, 1.1)
	sim.update(1.6)
	_give(1, Reward.Id.SONAR_JAM)
	sim.request_fire(1, 1.7)
	assert_int(_of(GameEvent.FIRE_QUEUED)[1]["launch_beat"]).is_equal(4)
	sim.update(3.0)
	assert_int(_of(GameEvent.COLLISION).size()).is_equal(0)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(2)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(2)


func test_buff_never_queues_or_collides_and_decoy_survives_collision() -> void:
	var sim := _sim()
	_give(2, DECOY)
	assert_int(sim.request_fire(2, 1.0)).is_equal(MatchSim.FIRE_OK)
	assert_int(_of(GameEvent.FIRE_QUEUED).size()).is_equal(0)
	assert_int(_of(GameEvent.BUFF_APPLIED).size()).is_equal(1)
	_give(0, INK)
	_give(1, INK)
	sim.request_fire(0, 1.1)
	sim.request_fire(1, 1.2)
	sim.update(2.5)
	assert_int(_of(GameEvent.COLLISION).size()).is_equal(1)
	assert_float(_players[2].decoy_until).is_greater(2.5)
	assert_int(_of(GameEvent.BUFF_ENDED).size()).is_equal(0)


func test_payload_end_starts_one_bar_immunity() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(9.99)
	assert_int(_of(GameEvent.PAYLOAD_END).size()).is_equal(0)
	sim.update(10.0)
	var pe := _of(GameEvent.PAYLOAD_END)
	assert_int(pe.size()).is_equal(1)
	assert_str(pe[0]["reason"]).is_equal("expired")
	assert_int(pe[0]["seat"]).is_equal(0)
	assert_float(pe[0]["immune_until"]).is_equal_approx(12.0, 1e-9)
	assert_float(pe[0]["t"]).is_equal_approx(10.0, 1e-9)
	_give(2, INK)
	assert_int(sim.request_fire(2, 11.0)).is_equal(MatchSim.FIRE_SHIELDED)
	assert_int(sim.request_fire(2, 12.0)).is_equal(MatchSim.FIRE_OK)


func test_landed_window_for_plain_payload() -> void:
	var sim := _sim()
	_give(1, Reward.Id.SONAR_JAM)
	sim.request_fire(1, 1.1)
	sim.update(2.0)
	var land: Dictionary = _of(GameEvent.LANDED)[0]
	assert_float(land["active_start"]).is_equal_approx(2.0, 1e-9)
	assert_float(land["end_t"]).is_equal_approx(8.0, 1e-9)  # 3 bars
	assert_int(land["seed"]).is_equal(hash([7, land["id"]]))


func test_payload_window_for_ghost_and_depth_waits_for_approach() -> void:
	var cfg := VersusConfig.new()
	var c := TestCharts.click_chart(120.0, 64, 1000)
	var w := MatchSim.payload_window(Reward.Id.GHOST_NOTES, 2.0, 1.3, c, cfg)
	assert_float(w.x).is_equal_approx(3.5, 1e-5)  # first whole beat at/after 3.3
	assert_float(w.y).is_equal_approx(11.5, 1e-5)
	var d := MatchSim.payload_window(Reward.Id.DEPTH_CHARGE, 2.0, 1.5, c, cfg)
	assert_float(d.x).is_equal_approx(3.5, 1e-5)
	assert_float(d.y).is_equal_approx(7.5, 1e-5)
	var i := MatchSim.payload_window(INK, 2.0, 1.5, c, cfg)
	assert_float(i.x).is_equal_approx(2.0, 1e-5)


func test_pick_warheads() -> void:
	var c := TestCharts.click_chart(120.0, 64, 1000)
	assert_array(MatchSim.pick_warheads(c, 2.0, 4)).is_equal([4, 5, 6, 7])
	assert_array(MatchSim.pick_warheads(c, 2.1, 2)).is_equal([5, 6])
	assert_array(MatchSim.pick_warheads(c, 2.0, 0)).is_empty()
	assert_array(MatchSim.pick_warheads(c, 31.0, 4)).is_empty()  # only 2 notes left


func test_pick_warheads_extends_whole_chord() -> void:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 1.0)
	c.add_note(1, 1.5)
	c.add_note(0, 2.0)
	c.add_note(2, 2.0)
	c.add_note(3, 2.0)
	c.add_note(1, 3.0)
	c.finalize()
	assert_array(MatchSim.pick_warheads(c, 1.0, 3)).is_equal([0, 1, 2, 3, 4])


func test_time_after_bars_respects_time_signature() -> void:
	var c := TestCharts.click_chart(120.0, 64, 1000)
	assert_float(MatchSim.time_after_bars(2.0, 1, c)).is_equal_approx(4.0, 1e-9)
	c.time_sigs.append({"time": 0.0, "num": 3, "den": 4})
	assert_float(MatchSim.bar_beats_at(1.0, c)).is_equal(3.0)
	assert_float(MatchSim.time_after_bars(2.0, 2, c)).is_equal_approx(5.0, 1e-9)


func test_tracks_last_attacker_on_launch() -> void:
	var sim := _sim()
	_give(3, INK)
	sim.set_target_mode(3, PlayerState.TargetMode.LOCKED, 0)
	sim.request_fire(3, 1.1)
	sim.update(1.5)
	assert_int(_players[0].last_attacker).is_equal(3)


func _depths(sim: MatchSim, d: Array) -> void:
	for s in range(d.size()):
		sim.report_status(s, 100.0, float(d[s]), 0.9, 10, 0.5)


func test_auto_targets_deepest_rival_or_second_when_leading() -> void:
	var sim := _sim()
	_depths(sim, [500, 900, 700, 300])
	assert_int(sim.resolve_target(0)).is_equal(1)
	assert_int(sim.resolve_target(1)).is_equal(2)
	assert_int(sim.resolve_target(3)).is_equal(1)


func test_auto_tie_goes_to_lower_seat() -> void:
	var sim := _sim()
	_depths(sim, [100, 500, 500, 0])
	assert_int(sim.resolve_target(0)).is_equal(1)
	assert_int(sim.resolve_target(3)).is_equal(1)


func test_cycle_target_order() -> void:
	var sim := _sim()
	_depths(sim, [500, 900, 700, 300])
	var modes: Array = []
	var targets: Array = []
	for k in range(5):
		targets.append(sim.cycle_target(0, 1.0))
		modes.append(_players[0].target_mode)
	var L := PlayerState.TargetMode.LOCKED
	assert_array(modes).is_equal([L, L, L, PlayerState.TargetMode.ATTACKERS,
		PlayerState.TargetMode.AUTO])
	assert_array(targets).is_equal([1, 2, 3, 1, 1])
	var te := _of(GameEvent.TARGET).filter(func(e: Dictionary) -> bool: return e["seat"] == 0)
	assert_int(te.size()).is_greater_equal(5)
	assert_int(te[te.size() - 1]["mode"]).is_equal(PlayerState.TargetMode.AUTO)


func test_attackers_without_attacker_is_auto_then_last_launcher() -> void:
	var sim := _sim()
	_depths(sim, [500, 900, 700, 300])
	sim.set_target_mode(0, PlayerState.TargetMode.ATTACKERS)
	assert_int(sim.resolve_target(0)).is_equal(1)
	_give(3, INK)
	sim.set_target_mode(3, PlayerState.TargetMode.LOCKED, 0)
	sim.request_fire(3, 1.1)
	sim.update(1.5)
	assert_int(sim.resolve_target(0)).is_equal(3)


func test_locked_target_that_dies_falls_back_to_auto() -> void:
	var sim := _sim()
	_depths(sim, [500, 900, 700, 300])
	sim.cycle_target(0, 1.0)
	sim.cycle_target(0, 1.0)
	assert_int(sim.resolve_target(0)).is_equal(2)
	sim.on_failed(2, 1.2)
	assert_int(sim.resolve_target(0)).is_equal(1)
	sim.update(2.0)
	assert_int(_players[0].target_mode).is_equal(PlayerState.TargetMode.AUTO)


func test_no_living_rival_is_no_target() -> void:
	var sim := _sim()
	for s in [1, 2, 3]:
		sim.on_failed(s, 1.0)
	_give(0, INK)
	assert_int(sim.request_fire(0, 1.1)).is_equal(MatchSim.FIRE_NO_TARGET)
	assert_str(_of(GameEvent.FIRE_REFUSED)[0]["reason"]).is_equal("no_target")
	assert_int(_players[0].meter.held).is_equal(INK)


func test_target_event_follows_auto_leader_at_beat() -> void:
	var sim := _sim()
	sim.update(0.1)
	_depths(sim, [0, 100, 50, 0])
	sim.update(1.0)
	var te := _of(GameEvent.TARGET).filter(func(e: Dictionary) -> bool: return e["seat"] == 0)
	assert_int(te[te.size() - 1]["target"]).is_equal(1)
	sim.report_status(2, 100.0, 300.0, 0.9, 5, 1.1)
	sim.update(1.5)
	te = _of(GameEvent.TARGET).filter(func(e: Dictionary) -> bool: return e["seat"] == 0)
	assert_int(te[te.size() - 1]["target"]).is_equal(2)


func test_wreck_fire_refused_nothing() -> void:
	var sim := _sim()
	sim.on_failed(1, 1.0)
	_give(1, INK)
	assert_int(sim.request_fire(1, 1.1)).is_equal(MatchSim.FIRE_NOTHING)
	assert_str(_of(GameEvent.FIRE_REFUSED)[0]["reason"]).is_equal("nothing")


func test_wreck_in_flight_torpedo_still_lands() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.update(1.6)
	sim.on_failed(1, 1.7)
	sim.update(2.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.IMPLODED).size()).is_equal(1)


func test_failed_shooter_pending_launch_is_cancelled() -> void:
	var sim := _sim()
	_give(1, INK)
	sim.request_fire(1, 1.1)
	sim.on_failed(1, 1.2)
	sim.update(3.0)
	assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(0)


func test_inject_fire_uses_no_meter() -> void:
	var sim := _sim()
	_players[1].is_drone = true
	assert_int(sim.inject_fire(1, 0, INK, 1.1)).is_equal(MatchSim.FIRE_OK)
	sim.update(2.0)
	assert_int(_of(GameEvent.LANDED).size()).is_equal(1)
	assert_int(_of(GameEvent.LANDED)[0]["reward"]).is_equal(INK)
	_give(2, INK)
	assert_int(sim.inject_fire(1, 0, INK, 2.1)).is_equal(MatchSim.FIRE_SHIELDED)
	assert_int(_players[2].meter.held).is_equal(INK)


func test_meter_events_follow_judgments() -> void:
	var sim := _sim()
	sim.on_judged(2, 0, P, 0.0)
	var m := _of(GameEvent.METER)
	assert_int(m.size()).is_equal(1)
	assert_int(m[0]["seat"]).is_equal(2)
	assert_int(m[0]["progress"]).is_equal(1)
	assert_int(m[0]["threshold"]).is_equal(31)
	assert_bool(m[0]["debris"]).is_false()
	for i in range(30):
		sim.on_judged(2, i + 1, P, 0.5 * (i + 1))
	var r := _of(GameEvent.REWARD_EARNED)
	assert_int(r.size()).is_equal(1)
	assert_str(r[0]["source"]).is_equal("meter")
	assert_int(r[0]["seat"]).is_equal(2)


func test_stray_does_not_touch_meter() -> void:
	var sim := _sim()
	sim.on_judged(0, 0, P, 0.0)
	sim.on_stray(0, 0.2)
	assert_int(_players[0].meter.progress).is_equal(1)
