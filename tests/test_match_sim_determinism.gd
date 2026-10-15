extends GdUnitTestSuite
## 03-03 Task 3 (RESEARCH Pitfall 6, T-03-08): the same scripted, song-time-stamped inputs give
## byte-identical event logs whatever the frame rate the referee is stepped at.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const END_T := 70.0


## [t, kind, args] sorted by t (stable: equal times keep script order).
func _script(chart: ChartData) -> Array:
	var out: Array = []
	var depth := [0.0, 0.0, 0.0, 0.0]
	var streak := [0, 0, 0, 0]
	var hull := [100.0, 100.0, 100.0, 100.0]
	for i in range(chart.notes.size()):
		var nt: float = chart.notes[i]["time"]
		if nt > END_T - 2.0:
			break
		for s in range(4):
			if s == 3 and nt >= 50.0:
				continue  # seat 3 is a wreck from 50 s (it would keep playing; skip for brevity)
			var j := P
			if (i + s) % 11 == 0:
				j = M
			elif (i * 3 + s) % 7 == 0:
				j = G
			var t := nt + 0.004 * (s - 1.5)
			out.append([t, "judge", [s, i, j]])
			if j == M:
				hull[s] -= 8.0
				streak[s] = 0
			else:
				depth[s] += 100.0 if j == P else 50.0
				streak[s] += 1
			out.append([t, "status", [s, hull[s], depth[s], 0.9, streak[s]]])
	# Forced rewards and fires: a head-on pair (0 <-> 1 locked), a race (2 and 3 at seat 1),
	# buffs, and plain shots.
	out.append([3.0, "lock", [0, 1]])
	out.append([3.0, "lock", [1, 0]])
	out.append([3.05, "give", [0, Reward.Id.INK_CLOUD]])
	out.append([3.05, "give", [1, Reward.Id.SONAR_JAM]])
	out.append([3.1, "fire", [0]])
	out.append([3.3, "fire", [1]])
	out.append([9.0, "lock", [2, 1]])
	out.append([9.0, "lock", [3, 1]])
	out.append([9.0, "give", [2, Reward.Id.GHOST_NOTES]])
	out.append([9.0, "give", [3, Reward.Id.DEPTH_CHARGE]])
	out.append([9.2, "fire", [3]])
	out.append([9.4, "fire", [2]])
	out.append([12.0, "give", [1, Reward.Id.DECOY_FLARE]])
	out.append([12.1, "fire", [1]])
	out.append([20.0, "give", [3, Reward.Id.CROSSED_WIRES]])
	out.append([20.13, "fire", [3]])
	out.append([22.0, "give", [0, Reward.Id.OVERCLOCK]])
	out.append([22.0, "fire", [0]])
	out.append([30.0, "cycle", [0]])
	out.append([30.0, "cycle", [0]])
	out.append([31.0, "give", [0, Reward.Id.PRESSURE_CRACK]])
	out.append([31.37, "fire", [0]])
	out.append([40.0, "give", [2, Reward.Id.BALLAST_PATCH]])
	out.append([40.0, "fire", [2]])
	out.append([45.0, "give", [1, Reward.Id.INK_CLOUD]])
	out.append([45.25, "fire", [1]])
	out.append([50.0, "fail", [3]])
	out.append([55.5, "fail", [2]])
	for k in range(out.size()):
		out[k].append(k)
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] == b[0]:
			return a[3] < b[3]
		return a[0] < b[0])
	return out


func _apply(sim: MatchSim, ps: Array[PlayerState], ev: Array) -> void:
	var t: float = ev[0]
	var a: Array = ev[2]
	match ev[1]:
		"judge":
			sim.on_judged(a[0], a[1], a[2], t)
		"status":
			sim.report_status(a[0], a[1], a[2], a[3], a[4], t)
		"give":
			ps[a[0]].meter.progress = ps[a[0]].meter.target
			ps[a[0]].meter.held = a[1]
		"fire":
			sim.request_fire(a[0], t)
		"lock":
			sim.set_target_mode(a[0], PlayerState.TargetMode.LOCKED, a[1], t)
		"cycle":
			sim.cycle_target(a[0], t)
		"fail":
			sim.on_failed(a[0], t)


func _run(fps: float) -> String:
	var chart := TestCharts.click_chart(120.0, 256, 1000)
	var ps: Array[PlayerState] = []
	for s in range(4):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps,
		LoopbackChannel.new(), 99)
	var script := _script(chart)
	var next := 0
	var frame := 0
	while true:
		frame += 1
		var ft := frame / fps
		while next < script.size() and float(script[next][0]) <= ft:
			_apply(sim, ps, script[next])
			next += 1
		sim.update(ft)
		if ft >= END_T:
			break
	sim.finish(END_T)
	return var_to_str(sim.event_log)


func test_event_log_identical_at_30_144_1000_fps() -> void:
	var a := _run(30.0)
	var b := _run(144.0)
	var c := _run(1000.0)
	assert_int(a.length()).is_greater(1000)
	assert_bool(a == b).is_true()
	assert_bool(a == c).is_true()


func test_script_exercises_collision_race_and_landing() -> void:
	var chart := TestCharts.click_chart(120.0, 256, 1000)
	var ps: Array[PlayerState] = []
	for s in range(4):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps,
		LoopbackChannel.new(), 99)
	for ev in _script(chart):
		_apply(sim, ps, ev)
	sim.finish(END_T)
	var types := {}
	for e in sim.event_log:
		types[e["type"]] = int(types.get(e["type"], 0)) + 1
	assert_int(types.get(GameEvent.COLLISION, 0)).is_equal(1)
	assert_int(types.get(GameEvent.LANDED, 0)).is_greater_equal(2)
	assert_int(types.get(GameEvent.BUFF_APPLIED, 0)).is_equal(3)
	assert_int(types.get(GameEvent.IMPLODED, 0)).is_equal(2)
	assert_int(types.get(GameEvent.MATCH_END, 0)).is_equal(1)
	var race := sim.event_log.filter(func(e: Dictionary) -> bool:
		return e["type"] == GameEvent.FIRE_REFUSED and e["reason"] == "race")
	assert_int(race.size()).is_equal(1)
