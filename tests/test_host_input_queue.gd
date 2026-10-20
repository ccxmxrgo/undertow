extends GdUnitTestSuite
## 04-05 Task 1: HostInputQueue (D-04 horizon ordering, late clamp, D-16 drop_seat, D-09 approach
## margin, D-13 DUEL_LIVE). click_chart(120, beats): note i at i * 0.5 s, one beat = 0.5 s.

const PF := InputJudge.Judgment.PERFECT
const GD := InputJudge.Judgment.GOOD
const MS := InputJudge.Judgment.MISS
const D := 0.1
const END_T := 40.0
const FPS := 60.0


func _players(n: int) -> Array[PlayerState]:
	var ps: Array[PlayerState] = []
	for s in range(n):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	return ps


func _sim(chart: ChartData, n: int, ch: EventChannel = null) -> MatchSim:
	if ch == null:
		ch = LoopbackChannel.new()
	return MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), _players(n), ch, 77)


## Wire items per seat: {seat, item: [kind, t, seq, ...args]}, seq increasing per seat.
func _script(chart: ChartData) -> Array:
	var out: Array = []
	var seq := [0, 0, 0]
	var hull := [100.0, 100.0, 100.0]
	var depth := [0.0, 0.0, 0.0]
	var streak := [0, 0, 0]
	for i in range(chart.notes.size()):
		var nt: float = chart.notes[i]["time"]
		if nt > END_T - 3.0:
			break
		for s in range(3):
			var j := PF
			if (i + s) % 9 == 0:
				j = MS
			elif (i * 5 + s) % 7 == 0:
				j = GD
			# Seats 1 and 2 share some exact times with seat 0 (tie order by seat matters).
			var t := nt + (0.0 if s != 2 else 0.003 * float(i % 3 - 1))
			out.append({"seat": s, "item": [NetProtocol.IN_JUDGED, t, seq[s], i, j]})
			seq[s] += 1
			if j == MS:
				hull[s] = maxf(hull[s] - 6.0, 1.0)
				streak[s] = 0
			else:
				depth[s] += 100.0 if j == PF else 50.0
				streak[s] += 1
			out.append({"seat": s, "item": [NetProtocol.IN_STATUS, t, seq[s], hull[s], depth[s],
				0.9, streak[s]]})
			seq[s] += 1
		if i % 16 == 5:
			for s in range(3):
				out.append({"seat": s, "item": [NetProtocol.IN_FIRE, nt + 0.01 * s, seq[s]]})
				seq[s] += 1
		if i == 30:
			out.append({"seat": 1, "item": [NetProtocol.IN_CYCLE, nt + 0.02, seq[1]]})
			seq[1] += 1
			out.append({"seat": 2, "item": [NetProtocol.IN_TARGET_MODE, nt + 0.02, seq[2],
				PlayerState.TargetMode.LOCKED, 0]})
			seq[2] += 1
	out.append({"seat": 2, "item": [NetProtocol.IN_FAILED, 30.0, seq[2]]})
	seq[2] += 1
	return out


func _sorted(script: Array) -> Array:
	var s := script.duplicate()
	s.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = a["item"][1]
		var tb: float = b["item"][1]
		if ta != tb:
			return ta < tb
		if a["seat"] != b["seat"]:
			return a["seat"] < b["seat"]
		return int(a["item"][2]) < int(b["item"][2]))
	return s


## Offline reference: MatchSim fed directly in (t, seat, seq) order.
func _apply_direct(sim: MatchSim, seat: int, it: Array) -> void:
	var t: float = it[1]
	match int(it[0]):
		NetProtocol.IN_JUDGED: sim.on_judged(seat, it[3], it[4], t)
		NetProtocol.IN_STATUS: sim.report_status(seat, it[3], it[4], it[5], it[6], t)
		NetProtocol.IN_FIRE: sim.request_fire(seat, t)
		NetProtocol.IN_CYCLE: sim.cycle_target(seat, t)
		NetProtocol.IN_TARGET_MODE: sim.set_target_mode(seat, it[3], it[4], t)
		NetProtocol.IN_FAILED: sim.on_failed(seat, t)


func _reference(chart: ChartData, script: Array) -> String:
	var sim := _sim(chart, 3)
	var s := _sorted(script)
	var next := 0
	var frame := 0
	while true:
		frame += 1
		var ft := frame / 37.0
		while next < s.size() and float(s[next]["item"][1]) <= ft:
			_apply_direct(sim, s[next]["seat"], s[next]["item"])
			next += 1
		sim.update(minf(ft, END_T))
		if ft >= END_T:
			break
	return var_to_str(sim.event_log)


## Host seat 0 goes through the local Referee methods (in order); seats 1 and 2 arrive over the
## "network" with a random delay < D and, when `shuffle`, in a random order per frame.
func _local_call(q: HostInputQueue, seat: int, it: Array) -> void:
	var t: float = it[1]
	match int(it[0]):
		NetProtocol.IN_JUDGED: q.on_judged(seat, it[3], it[4], t)
		NetProtocol.IN_STATUS: q.report_status(seat, it[3], it[4], it[5], it[6], t)
		NetProtocol.IN_FIRE: assert_int(q.request_fire(seat, t)).is_equal(Referee.FIRE_REMOTE)
		NetProtocol.IN_CYCLE: q.cycle_target(seat, t)
		NetProtocol.IN_TARGET_MODE: q.set_target_mode(seat, it[3], it[4], t)
		NetProtocol.IN_FAILED: q.on_failed(seat, t)


func _queued(chart: ChartData, script: Array, shuffle: bool) -> HostInputQueue:
	var sim := _sim(chart, 3)
	var q := HostInputQueue.new(sim, sim.channel, D)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var local: Array = []
	var remote: Array = []
	for e in _sorted(script):
		if e["seat"] == 0:
			local.append(e)
		else:
			remote.append({"seat": e["seat"], "item": e["item"],
				"arrive": float(e["item"][1]) + (rng.randf() * (D - 0.03) if shuffle else 0.0)})
	remote.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["arrive"] < b["arrive"])
	var li := 0
	var ri := 0
	var frame := 0
	while true:
		frame += 1
		var ft := frame / FPS
		while li < local.size() and float(local[li]["item"][1]) <= ft:
			_local_call(q, 0, local[li]["item"])
			li += 1
		var batch: Array = []
		while ri < remote.size() and float(remote[ri]["arrive"]) <= ft:
			batch.append(remote[ri])
			ri += 1
		if shuffle:
			for k in range(batch.size() - 1, 0, -1):
				var r := rng.randi_range(0, k)
				var tmp = batch[k]
				batch[k] = batch[r]
				batch[r] = tmp
		for e in batch:
			q.push_item(e["seat"], e["item"])
		q.pump(minf(ft, END_T + D))
		if ft >= END_T + D:
			break
	return q


func test_order_independent_and_matches_offline_reference() -> void:
	var chart := TestCharts.click_chart(120.0, 120, 1000)
	var script := _script(chart)
	var ref := _reference(chart, script)
	var q_in := _queued(chart, script, false)
	var q_sh := _queued(chart, script, true)
	assert_int(q_in.sim.event_log.size()).is_greater(50)
	assert_int(q_in.late_inputs).is_equal(0)
	assert_int(q_sh.late_inputs).is_equal(0)
	assert_str(var_to_str(q_in.sim.event_log)).is_equal(ref)
	assert_str(var_to_str(q_sh.sim.event_log)).is_equal(ref)
	assert_bool(q_in.sim.event_log.any(func(e: Dictionary) -> bool:
		return e["type"] == GameEvent.IMPLODED)).is_true()


func test_release_waits_for_horizon() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.push_item(1, [NetProtocol.IN_JUDGED, 1.0, 0, 2, PF])
	q.pump(1.05)  # horizon 0.95 < 1.0: still queued
	assert_int(int(q.debug_stats()["pending"])).is_equal(1)
	q.pump(1.1)  # horizon 1.0: released
	assert_int(int(q.debug_stats()["pending"])).is_equal(0)
	assert_float(float(q.debug_stats()["released_t"])).is_equal_approx(1.0, 1e-9)


func test_late_input_clamped_not_dropped() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.pump(2.0)
	assert_float(q.released_t).is_equal_approx(1.9, 1e-9)
	var before := sim.event_log.size()
	q.push_item(1, [NetProtocol.IN_JUDGED, 1.0, 0, 2, PF])
	q.push_item(1, [NetProtocol.IN_JUDGED, 1.5, 1, 3, PF])
	q.pump(2.1)
	assert_int(q.late_inputs).is_equal(2)
	assert_int(int(q.debug_stats()["late_inputs"])).is_equal(2)
	assert_int(sim.event_log.size()).is_greater(before)
	var last := -INF
	for e in sim.event_log:
		assert_float(float(e["t"])).is_greater_equal(last)
		last = float(e["t"])
	# The applied judgments landed at the clamped time, never before 1.9.
	for k in range(before, sim.event_log.size()):
		assert_float(float(sim.event_log[k]["t"])).is_greater_equal(1.9 - 1e-9)


func test_far_future_items_dropped_on_push() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.pump(5.0)
	q.push_item(1, [NetProtocol.IN_STRAY, 5.0 + NetProtocol.FUTURE_INPUT_S + 0.5, 0])
	q.push_item(1, [NetProtocol.IN_STRAY, 6.0, 1])
	assert_int(q.rejected_future).is_equal(1)
	var st := q.debug_stats()
	assert_int(int(st["rejected_future"])).is_equal(1)
	assert_int(int(st["pending"])).is_equal(1)
	assert_bool(st.has("released_t")).is_true()


func test_seat_comes_from_caller_and_bad_items_ignored() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.push_item(9, [NetProtocol.IN_STRAY, 0.5, 0])  # unknown seat
	q.push_item(1, [NetProtocol.IN_JUDGED, 0.5, 0])  # wrong arity
	q.push_item(1, [99, 0.5, 0])  # unknown kind
	q.push_item(1, [NetProtocol.IN_STRAY, NAN, 0])  # non-finite time
	assert_int(int(q.debug_stats()["pending"])).is_equal(0)


func test_status_sanity_clamps() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.push_item(1, [NetProtocol.IN_STATUS, 0.5, 0, 9999.0, -50.0, 7.0, 3])
	q.pump(1.0)
	assert_float(sim.players[1].hull).is_equal(JudgeConfig.new().hull_start)
	assert_float(sim.players[1].depth).is_equal(0.0)
	assert_float(sim.players[1].accuracy).is_equal(1.0)
	q.push_item(1, [NetProtocol.IN_STATUS, 1.0, 1, -3.0, 10.0, -7.0, 3])
	q.pump(1.5)
	assert_float(sim.players[1].hull).is_equal(0.0)
	assert_float(sim.players[1].accuracy).is_equal(-1.0)


func test_update_is_a_noop_only_pump_advances() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.push_item(1, [NetProtocol.IN_JUDGED, 1.0, 0, 2, PF])
	var log_before := var_to_str(sim.event_log)
	var rel := q.released_t
	q.update(50.0)
	assert_str(var_to_str(sim.event_log)).is_equal(log_before)
	assert_float(q.released_t).is_equal(rel)
	assert_int(int(q.debug_stats()["pending"])).is_equal(1)
	q.pump(2.0)
	assert_int(int(q.debug_stats()["pending"])).is_equal(0)


func test_drop_seat_implodes_then_player_left() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var ch := LoopbackChannel.new()
	var got: Array = []
	ch.received.connect(func(e: Dictionary) -> void: got.append(e))
	var sim := _sim(chart, 3, ch)
	var q := HostInputQueue.new(sim, ch, D)
	q.pump(5.0)
	q.push_item(2, [NetProtocol.IN_STRAY, 5.05, 0])
	q.push_item(1, [NetProtocol.IN_STRAY, 5.05, 0])
	got.clear()
	q.drop_seat(2, "disconnected")
	assert_int(int(q.debug_stats()["pending"])).is_equal(1)  # seat 1's item stays
	var types: Array = got.map(func(e: Dictionary) -> String: return e["type"])
	var ii := types.find(GameEvent.IMPLODED)
	var li := types.find(GameEvent.PLAYER_LEFT)
	assert_int(ii).is_greater_equal(0)
	assert_int(li).is_greater(ii)
	assert_int(got[ii]["seat"]).is_equal(2)
	assert_float(float(got[ii]["t"])).is_equal_approx(4.9, 1e-9)
	assert_int(got[li]["seat"]).is_equal(2)
	assert_str(got[li]["reason"]).is_equal("disconnected")
	assert_float(float(got[li]["t"])).is_equal_approx(4.9, 1e-9)
	assert_bool(NetCodec.validate_event(got[li])).is_true()
	assert_bool(sim.players[2].alive).is_false()
	assert_int(q.extra_log.size()).is_equal(1)
	assert_str(q.extra_log[0]["type"]).is_equal(GameEvent.PLAYER_LEFT)
	# Second drop: no-op. Later items for the dropped seat are ignored.
	var n := got.size()
	q.drop_seat(2, "disconnected")
	q.push_item(2, [NetProtocol.IN_STRAY, 5.2, 1])
	assert_int(got.size()).is_equal(n)
	assert_int(q.extra_log.size()).is_equal(1)
	assert_int(int(q.debug_stats()["pending"])).is_equal(1)


func test_approach_margin_applied_and_capped() -> void:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var sim := _sim(chart, 2)
	var q := HostInputQueue.new(sim, sim.channel, D)
	q.set_net_margin(1, 0.12)
	q.set_approach(1, 1.2)
	assert_float(sim.players[1].approach_s).is_equal_approx(1.32, 1e-9)
	q.set_net_margin(1, 0.5)  # capped at 0.3, re-applied to the last reported s
	assert_float(sim.players[1].approach_s).is_equal_approx(1.5, 1e-9)
	q.set_net_margin(1, 0.05)
	assert_float(sim.players[1].approach_s).is_equal_approx(1.25, 1e-9)
	# The host's own seat gets the margin path too; network APPROACH items as well.
	q.set_net_margin(0, 0.2)
	q.set_approach(0, 1.0)
	assert_float(sim.players[0].approach_s).is_equal_approx(1.2, 1e-9)
	q.push_item(1, [NetProtocol.IN_APPROACH, 0.5, 0, 2.0])
	q.pump(1.0)
	assert_float(sim.players[1].approach_s).is_equal_approx(2.05, 1e-9)
	assert_float(HostInputQueue.margin_for(0.1, 0.06)).is_equal_approx(0.163, 1e-9)
	assert_float(HostInputQueue.margin_for(0.2, 0.4)).is_equal_approx(0.3, 1e-9)


func test_duel_live_once_per_beat_only_during_duel() -> void:
	var chart := TestCharts.click_chart(120.0, 200, 1000)
	chart.solos.append({"start": 20.0, "end": 29.5, "note_count": 20})
	var ch := LoopbackChannel.new()
	var got: Array = []
	ch.received.connect(func(e: Dictionary) -> void: got.append(e))
	var sim := _sim(chart, 2, ch)
	var q := HostInputQueue.new(sim, ch, D)
	var remote: Array = []
	for n in range(40, 60):
		remote.append([NetProtocol.IN_JUDGED, n * 0.5, n - 40, n, PF if n % 4 != 0 else GD])
		q.on_judged(0, n, PF, n * 0.5)
	var last_live := {}
	var frame := 0
	var checked := false
	while true:
		frame += 1
		var ft := frame / FPS
		while not remote.is_empty() and float(remote[0][1]) <= ft + 0.02:
			q.push_item(1, remote.pop_front())
		q.pump(ft)
		var lives := got.filter(func(e: Dictionary) -> bool: return e["type"] == GameEvent.DUEL_LIVE)
		if not lives.is_empty():
			last_live = lives[-1]
		if ft > 25.0 and not checked and not last_live.is_empty():
			checked = true
			assert_float(q.duel_live(1)).is_equal(float(last_live["pct"][1]))
			assert_float(q.duel_live(0)).is_equal(100.0)
			assert_int(q.duel_active()).is_equal(0)
		if ft >= 31.0:
			break
	assert_bool(checked).is_true()
	var lives := got.filter(func(e: Dictionary) -> bool: return e["type"] == GameEvent.DUEL_LIVE)
	assert_int(lives.size()).is_greater(5)
	var beats := {}
	for e in lives:
		var t: float = e["t"]
		assert_float(t).is_greater_equal(20.0)
		assert_float(t).is_less_equal(29.61)
		var b := int(floor(BeatClock.beat_at(t, chart.tempo_map) + 1e-6))
		assert_bool(beats.has(b)).is_false()
		beats[b] = true
		assert_int(int(e["solo"])).is_equal(0)
		assert_bool(NetCodec.validate_event(e)).is_true()
		for s in e["pct"]:
			assert_float(float(e["pct"][s])).is_greater_equal(0.0)
	assert_int(q.extra_log.size()).is_equal(lives.size())
	# After the duel resolved: no live value.
	assert_float(q.duel_live(0)).is_equal(-1.0)
	assert_int(q.duel_active()).is_equal(-1)
