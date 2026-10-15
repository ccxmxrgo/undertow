extends GdUnitTestSuite
## 03-07 Task 1 (D-19, D-20, MATCH-01): BotProfile tiers and BotPlayer seeded timing + fire policy.
## Bots play through a SubRig, i.e. exactly the rules code the human uses.

const BEAT := 0.5  # 120 BPM click charts

var _ev: Array = []
var _players: Array[PlayerState] = []
var _chart: ChartData
var _ch: LoopbackChannel
var _sim: MatchSim
var _cfg: VersusConfig


## Notes every `spacing` s, lane = i % 4, tempo 120 BPM, no audio.
func _plain_chart(n: int, spacing: float = 0.25) -> ChartData:
	var c := ChartData.new()
	c.id = "test.bot.plain.%d" % n
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	for i in range(n):
		c.add_note(i % 4, 1.0 + i * spacing)
	c.finalize()
	return c


func _setup(chart: ChartData, seats: int = 2) -> void:
	_chart = chart
	_cfg = VersusConfig.new()
	_players = []
	for s in range(seats):
		_players.append(PlayerState.new(s, "B%d" % s, false))
	_ch = LoopbackChannel.new()
	_ev = []
	_ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	_sim = MatchSim.new(_chart, _cfg, JudgeConfig.new(), _players, _ch, 9)


func _bot(profile: BotProfile, seed: int = 5, seat: int = 0) -> BotPlayer:
	var rig := SubRig.new(seat, _chart, JudgeConfig.new(), _cfg, _sim, _ch, false)
	return BotPlayer.new(rig, profile, _sim, _cfg, _chart, seed)


func _idle() -> BotProfile:
	var p := BotProfile.veteran()
	p.lapse = 1.0  # never presses: fire policy in isolation
	return p


func _of(type: String, seat: int = -1) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool:
		return e["type"] == type and (seat == -1 or e.get("seat", -1) == seat))


func _run(bot: BotPlayer, from: float, to: float, dt: float = 1.0 / 60.0) -> void:
	var t := from
	while t < to:
		t = minf(t + dt, to)
		bot.update(t)
		_sim.update(t)


# --- profiles ---------------------------------------------------------------------------------

func test_profiles_match_d19() -> void:
	var v := BotProfile.veteran()
	assert_float(v.sigma_s).is_equal_approx(0.033, 1e-9)
	assert_float(v.lapse).is_equal_approx(0.015, 1e-9)
	assert_float(v.ghost_press_p).is_equal_approx(0.15, 1e-9)
	var r := BotProfile.regular()
	assert_float(r.sigma_s).is_equal_approx(0.042, 1e-9)
	assert_float(r.lapse).is_equal_approx(0.035, 1e-9)
	assert_float(r.ghost_press_p).is_equal_approx(0.30, 1e-9)
	var k := BotProfile.rookie()
	assert_float(k.sigma_s).is_equal_approx(0.055, 1e-9)
	assert_float(k.lapse).is_equal_approx(0.07, 1e-9)
	assert_float(k.ghost_press_p).is_equal_approx(0.45, 1e-9)
	var f := BotProfile.from_skill("veteran")
	assert_float(f.sigma_s).is_equal(v.sigma_s)
	assert_float(f.lapse).is_equal(v.lapse)
	assert_float(f.ghost_press_p).is_equal(v.ghost_press_p)
	assert_float(BotProfile.from_skill("rookie").sigma_s).is_equal(k.sigma_s)
	assert_float(BotProfile.from_skill("regular").sigma_s).is_equal(r.sigma_s)


func test_payload_penalties() -> void:
	var v := BotProfile.veteran()
	assert_float(v.effective_for(Reward.Id.INK_CLOUD).sigma_s).is_equal_approx(0.033 * 1.3, 1e-9)
	assert_float(v.effective_for(Reward.Id.PRESSURE_CRACK).sigma_s).is_equal_approx(0.033 * 1.2, 1e-9)
	assert_float(v.effective_for(Reward.Id.CROSSED_WIRES).lapse).is_equal_approx(0.075, 1e-9)
	assert_float(v.effective_for(Reward.Id.SONAR_JAM).lapse).is_equal_approx(0.055, 1e-9)
	assert_float(v.effective_for(Reward.Id.DEPTH_CHARGE).sigma_s).is_equal(v.sigma_s)
	assert_float(v.effective_for(-1).lapse).is_equal(v.lapse)


# --- timing -----------------------------------------------------------------------------------

func _press_log(seed: int) -> Array:
	_setup(TestCharts.hand_chart(1000))
	var bot := _bot(BotProfile.veteran(), seed)
	_run(bot, -1.0, 62.0)
	return bot.press_log.duplicate()


func test_same_seed_presses_at_identical_times() -> void:
	var a := _press_log(5)
	var b := _press_log(5)
	assert_int(a.size()).is_greater(100)
	assert_str(var_to_str(a)).is_equal(var_to_str(b))
	var c := _press_log(6)
	assert_str(var_to_str(a)).is_not_equal(var_to_str(c))


func test_veteran_statistics_on_1000_notes() -> void:
	_setup(_plain_chart(1000), 1)
	var bot := _bot(BotProfile.veteran(), 5)
	_run(bot, -1.0, 1.0 + 1000 * 0.25 + 2.0, 0.05)
	var rig := bot.rig
	var total := rig.perfect + rig.good + rig.miss
	assert_int(total).is_equal(1000)
	var pf := float(rig.perfect) / total
	var mf := float(rig.miss) / total
	assert_float(pf).override_failure_message("perfect %.3f" % pf).is_between(0.80, 0.92)
	assert_float(mf).override_failure_message("miss %.3f" % mf).is_less_equal(0.04)
	assert_int(rig.hull.stray_count).is_equal(0)  # D-19: no stray presses


func test_ink_cloud_raises_effective_sigma() -> void:
	_setup(_plain_chart(100))
	var bot := _bot(BotProfile.veteran())
	bot.rig.stack.install({"id": 99, "reward": Reward.Id.INK_CLOUD, "arrive_t": 2.0,
		"end_t": 6.0, "seed": 1})
	assert_float(bot.effective_profile(3.0).sigma_s).is_equal_approx(0.033 * 1.3, 1e-9)
	assert_float(bot.effective_profile(20.0).sigma_s).is_equal_approx(0.033, 1e-9)


# --- fire policy (D-20) -----------------------------------------------------------------------

func _give_at(seat: int, id: int, t: float) -> void:
	_sim.update(t)
	_sim.report_status(seat, 100.0, 0.0, -1.0, 0, t)  # stamps _now = t
	_players[seat].meter.queue_prize(id)


func test_disruptor_fired_1_to_8_beats_after_earning() -> void:
	for seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		_setup(_plain_chart(400))
		var bot := _bot(_idle(), seed)
		_run(bot, -1.0, 2.0)
		_give_at(0, Reward.Id.INK_CLOUD, 2.0)
		_run(bot, 2.0, 8.0)
		var q := _of(GameEvent.FIRE_QUEUED, 0)
		assert_int(q.size()).is_equal(1)
		var dt: float = q[0]["t"] - 2.0
		assert_float(dt).is_between(1.0 * BEAT - 1e-6, 8.0 * BEAT + 1e-6)
		assert_float(fmod(q[0]["t"], BEAT)).is_equal_approx(0.0, 1e-6)  # on a beat
		assert_int(_of(GameEvent.TORPEDO_LAUNCH).size()).is_equal(1)


func test_shielded_target_retried_every_beat() -> void:
	_setup(_plain_chart(400))
	var bot := _bot(_idle(), 3)
	_players[1].immune_until = 7.0
	_run(bot, -1.0, 2.0)
	_give_at(0, Reward.Id.INK_CLOUD, 2.0)
	_run(bot, 2.0, 10.0)
	var refused := _of(GameEvent.FIRE_REFUSED, 0)
	var queued := _of(GameEvent.FIRE_QUEUED, 0)
	assert_int(queued.size()).is_equal(1)
	assert_float(queued[0]["t"]).is_greater_equal(7.0)
	if not refused.is_empty():
		for i in range(1, refused.size()):
			assert_float(refused[i]["t"] - refused[i - 1]["t"]).is_equal_approx(BEAT, 1e-6)
		assert_float(queued[0]["t"] - refused[-1]["t"]).is_equal_approx(BEAT, 1e-6)
		assert_str(refused[0]["reason"]).is_equal("shielded")


func test_decoy_and_overclock_fired_when_earned() -> void:
	for id in [Reward.Id.DECOY_FLARE, Reward.Id.OVERCLOCK]:
		_setup(_plain_chart(400))
		var bot := _bot(_idle(), 4)
		_run(bot, -1.0, 2.0)
		_give_at(0, id, 2.0)
		bot.update(2.0)
		var b := _of(GameEvent.BUFF_APPLIED, 0)
		assert_int(b.size()).is_equal(1)
		assert_float(b[0]["t"]).is_equal(2.0)
		assert_int(b[0]["reward"]).is_equal(id)
	assert_float(_players[0].overclock_until).is_greater(2.0)


func test_ballast_waits_16_bars_at_full_hull() -> void:
	# One note at 1.0 s (missed: hull 92 > 75), then no notes, so the hull stays above 75.
	_setup(_plain_chart(1))
	var bot := _bot(_idle(), 4)
	_run(bot, -1.0, 2.0)
	_give_at(0, Reward.Id.BALLAST_PATCH, 2.0)
	var due := MatchSim.time_after_bars(2.0, 16, _chart)  # 34.0
	_run(bot, 2.0, due - 0.01)
	assert_int(_of(GameEvent.BUFF_APPLIED, 0).size()).is_equal(0)
	_run(bot, due - 0.01, due + 0.5)
	var b := _of(GameEvent.BUFF_APPLIED, 0)
	assert_int(b.size()).is_equal(1)
	assert_float(b[0]["t"]).is_equal_approx(due, 1e-9)


func test_ballast_fired_when_hull_drops_to_75() -> void:
	_setup(_plain_chart(1))
	var bot := _bot(_idle(), 4)
	_run(bot, -1.0, 2.0)
	_give_at(0, Reward.Id.BALLAST_PATCH, 2.0)
	_run(bot, 2.0, 3.0)
	assert_int(_of(GameEvent.BUFF_APPLIED, 0).size()).is_equal(0)
	bot.rig.begin(3.0)
	bot.rig.hull.ghost_hit(7, 30.0, 30.0)  # hull 92 -> 62 (the missed note at 1.0 cost 8)
	bot.update(3.0)
	var b := _of(GameEvent.BUFF_APPLIED, 0)
	assert_int(b.size()).is_equal(1)
	assert_float(b[0]["t"]).is_equal(3.0)
	assert_float(bot.rig.hull.hull).is_equal(87.0)  # 62 + 25


func test_wreck_fires_debris_as_soon_as_held() -> void:
	_setup(_plain_chart(1))
	var bot := _bot(_idle(), 4)
	_run(bot, -1.0, 2.0)
	_ch.send(GameEvent.make(GameEvent.REWARD_EARNED, 2.0,
		{"seat": 0, "reward": Reward.Id.SILT, "source": "debris"}))
	bot.update(2.0)
	assert_int(bot.fire_log.size()).is_greater_equal(1)
	assert_float(bot.fire_log[0]["t"]).is_equal(2.0)
	assert_int(bot.fire_log[0]["reward"]).is_equal(Reward.Id.SILT)


func test_ghost_notes_pressed_with_profile_probability() -> void:
	_setup(_plain_chart(1))
	var p := _idle()
	p.ghost_press_p = 1.0
	p.sigma_s = 0.0
	var bot := _bot(p, 4)
	_run(bot, -1.0, 2.0)
	_ch.send(GameEvent.make(GameEvent.LANDED, 2.0, {"id": 3, "from": 1, "to": 0,
		"reward": Reward.Id.GHOST_NOTES, "arrive_t": 2.0, "active_start": 4.0, "end_t": 12.0,
		"seed": 5, "reflected": false, "debris": false}))
	var n := bot.rig.judge.overlay_notes().size()
	assert_int(n).is_greater(0)
	_run(bot, 2.0, 13.0)
	assert_int(bot.rig.ghost_hits).is_equal(n)
	# p = 0: never pressed.
	_setup(_plain_chart(1))
	p = _idle()
	p.ghost_press_p = 0.0
	bot = _bot(p, 4)
	_run(bot, -1.0, 2.0)
	_ch.send(GameEvent.make(GameEvent.LANDED, 2.0, {"id": 3, "from": 1, "to": 0,
		"reward": Reward.Id.GHOST_NOTES, "arrive_t": 2.0, "active_start": 4.0, "end_t": 12.0,
		"seed": 5, "reflected": false, "debris": false}))
	_run(bot, 2.0, 13.0)
	assert_int(bot.rig.ghost_hits).is_equal(0)
