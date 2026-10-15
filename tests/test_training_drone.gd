extends GdUnitTestSuite
## 03-07 Task 3 (MATCH-06, D-27, 03-SPEC req 5 acceptance): the Solo Dive TrainingDrone fires
## the chosen payload (or all six in turn) every training_interval_bars at the human; with an
## autoplay human each disruptor lands, ends after its configured duration, and autoplay stays
## all-Perfect (ghosts skipped).

const DISRUPTORS: Array[int] = [Reward.Id.CROSSED_WIRES, Reward.Id.GHOST_NOTES,
	Reward.Id.INK_CLOUD, Reward.Id.PRESSURE_CRACK, Reward.Id.SONAR_JAM, Reward.Id.DEPTH_CHARGE]

var _ev: Array = []


func _bundled() -> ChartData:
	var id := "synth_wave_april"
	var parsed := ChartParser.parse_bytes(
		FileAccess.get_file_as_bytes("res://songs/%s/notes.chart" % id))
	var ini := SongIni.parse(FileAccess.get_file_as_string("res://songs/%s/song.ini" % id))
	return ChartImporter.build(parsed, "expert", SongIni.get_int(ini, "delay", 0))


## Two seats (human 0, drone 1) on a 120 BPM click chart (2 s bars), drone driven directly.
func _small(mode: int) -> Array:
	var chart := TestCharts.click_chart(120.0, 240, 1000)
	var players: Array[PlayerState] = [PlayerState.new(0, "YOU", true),
		PlayerState.new(1, "DRONE", false, true)]
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	var cfg := VersusConfig.new()
	cfg.warhead_count = 0
	var sim := MatchSim.new(chart, cfg, JudgeConfig.new(), players, ch, 1)
	var drone := TrainingDrone.new(sim, chart, cfg, 1, 0, mode)
	return [sim, drone, players]


func _drive(sim: MatchSim, drone: TrainingDrone, from: float, to: float) -> void:
	var t := from
	while t < to:
		t = minf(t + 1.0 / 60.0, to)
		drone.update(t)
		sim.update(t)


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_fires_every_8_bars_from_bar_4() -> void:
	var a := _small(Reward.Id.INK_CLOUD)
	var sim: MatchSim = a[0]
	var drone: TrainingDrone = a[1]
	_drive(sim, drone, -1.0, 60.0)
	var q := _of(GameEvent.FIRE_QUEUED)
	assert_int(q.size()).is_equal(4)  # 8 s, 24 s, 40 s, 56 s
	for i in range(q.size()):
		assert_float(q[i]["t"]).is_equal_approx(8.0 + 16.0 * i, 1e-6)
		assert_int(q[i]["reward"]).is_equal(Reward.Id.INK_CLOUD)
		assert_int(q[i]["to"]).is_equal(0)


func test_bars_until_next_counts_down() -> void:
	var a := _small(Reward.Id.INK_CLOUD)
	var drone: TrainingDrone = a[1]
	assert_int(drone.bars_until_next(0.0)).is_equal(4)
	assert_int(drone.bars_until_next(5.0)).is_equal(2)
	assert_int(drone.bars_until_next(8.0)).is_equal(0)


func test_all_mode_cycles_disruptors_in_reward_order() -> void:
	var a := _small(-2)
	_drive(a[0], a[1], -1.0, 8.0 + 16.0 * 6 + 1.0)
	var launched := _of(GameEvent.TORPEDO_LAUNCH)
	assert_int(launched.size()).is_greater_equal(6)
	for i in range(6):
		assert_int(launched[i]["reward"]).is_equal(DISRUPTORS[i])


func test_off_mode_never_fires() -> void:
	var a := _small(-1)
	_drive(a[0], a[1], -1.0, 40.0)
	assert_int(_of(GameEvent.FIRE_QUEUED).size()).is_equal(0)


func test_refused_fire_retries_next_beat() -> void:
	var a := _small(Reward.Id.SONAR_JAM)
	var players: Array = a[2]
	players[0].immune_until = 9.2
	_drive(a[0], a[1], -1.0, 12.0)
	var refused := _of(GameEvent.FIRE_REFUSED)
	assert_int(refused.size()).is_equal(3)  # 8.0, 8.5, 9.0
	for i in range(refused.size()):
		assert_float(refused[i]["t"]).is_equal_approx(8.0 + 0.5 * i, 1e-6)
	var q := _of(GameEvent.FIRE_QUEUED)
	assert_float(q[0]["t"]).is_equal_approx(9.5, 1e-6)


func test_each_disruptor_lands_expires_and_autoplay_stays_perfect() -> void:
	var chart := _bundled()
	var cfg := VersusConfig.new()
	cfg.warhead_count = 0
	for reward in DISRUPTORS:
		var r := MatchHarness.run(chart, {"training": reward, "seed": 21, "fps": 60.0, "cfg": cfg})
		var log: Array = r["event_log"]
		var landed := log.filter(func(e: Dictionary) -> bool:
			return e["type"] == GameEvent.LANDED and e["to"] == 0)
		assert_int(landed.size()).override_failure_message(
			"%s never landed" % Reward.key_of(reward)).is_greater(0)
		for l in landed:
			assert_int(l["reward"]).is_equal(reward)
			var ends := log.filter(func(e: Dictionary) -> bool:
				return e["type"] == GameEvent.PAYLOAD_END and e["id"] == l["id"])
			if float(l["end_t"]) > r["duration_s"]:
				continue  # still running when the song ended
			assert_int(ends.size()).is_equal(1)
			assert_str(ends[0]["reason"]).is_equal("expired")
			assert_float(ends[0]["t"]).is_equal(l["end_t"])
			var want := MatchSim.time_after_bars(l["active_start"], cfg.bars_for(reward), chart)
			assert_float(l["end_t"]).is_equal_approx(want, 1e-9)
		var st: Dictionary = r["stats"][0]
		var msg := "%s: %s" % [Reward.key_of(reward), str(st)]
		assert_int(st["perfect"]).override_failure_message(msg).is_equal(chart.notes.size())
		assert_int(st["good"]).override_failure_message(msg).is_equal(0)
		assert_int(st["miss"]).override_failure_message(msg).is_equal(0)
		assert_int(st["depth_other"]).override_failure_message(msg).is_equal(0)
		assert_int(st["ghost_hits"]).override_failure_message(msg).is_equal(0)
		if reward == Reward.Id.DEPTH_CHARGE:
			assert_int(st["depth_perfect"]).override_failure_message(msg).is_greater(0)
		# The drone is never ranked and never fails.
		assert_int(r["standings"].size()).is_equal(1)


func test_human_fire_lands_on_the_drone_which_never_fails() -> void:
	var cfg := VersusConfig.new()
	cfg.warhead_count = 0
	var h := MatchHarness.new(TestCharts.hand_chart(1000),
		{"training": Reward.Id.INK_CLOUD, "seed": 4, "cfg": cfg})
	assert_int(h.drone_seat).is_equal(1)
	assert_bool(h.players[1].is_drone).is_true()
	h.advance_to(0.2)
	h.sim.report_status(0, 100.0, 0.0, -1.0, 0, 0.2)
	h.players[0].meter.queue_prize(Reward.Id.GHOST_NOTES)
	assert_int(h.sim.request_fire(0, 0.2)).is_equal(MatchSim.FIRE_OK)
	h.finish()
	var log: Array = h.sim.event_log
	var on_drone := log.filter(func(e: Dictionary) -> bool:
		return e["type"] == GameEvent.LANDED and e["to"] == 1)
	assert_int(on_drone.size()).is_equal(1)
	assert_int(on_drone[0]["from"]).is_equal(0)
	assert_bool(h.players[1].alive).is_true()
	assert_int(log.filter(func(e: Dictionary) -> bool:
		return e["type"] == GameEvent.IMPLODED).size()).is_equal(0)
