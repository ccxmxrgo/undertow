extends GdUnitTestSuite
## VersusJudge (D-11, D-12, D-14, T-03-11): ghost and depth-charge overlay notes on top of the
## pinned InputJudge; with no overlay notes it must behave exactly like InputJudge.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const SAMPLE_RATE := 8000


func _chart() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 1.0)
	c.add_note(0, 6.0)
	c.add_note(3, 6.0)
	c.finalize()
	return c


func _rec(judge: VersusJudge) -> Dictionary:
	var r := {"judged": [], "stray": [], "extra": [], "ghost": []}
	judge.judged.connect(func(l: int, i: int, j: int, e: float) -> void: r["judged"].append([l, i, j, e]))
	judge.stray.connect(func(l: int) -> void: r["stray"].append(l))
	judge.extra_judged.connect(func(k: int, l: int, j: int, e: float) -> void: r["extra"].append([k, l, j, e]))
	judge.ghost_hit.connect(func(l: int, pid: int) -> void: r["ghost"].append([l, pid]))
	return r


func test_ghost_press_costs_hull_and_breaks_combo() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_versus(judge, VersusConfig.new())
	var r := _rec(judge)
	judge.press(0, 1.0)
	assert_int(hull.combo).is_equal(1)
	judge.add_overlay([{"time": 2.0, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 7}])
	judge.press(1, 2.03)
	assert_array(r["ghost"]).is_equal([[1, 7]])
	assert_int(r["judged"].size()).is_equal(1)  # only the base note at 1.0
	assert_int(r["stray"].size()).is_equal(0)
	assert_float(hull.hull).is_equal(96.0)
	assert_int(hull.combo).is_equal(0)
	assert_int(hull.perfect_streak).is_equal(0)
	assert_str(judge.overlay_notes()[0]["state"]).is_equal("hit")


func test_ghost_cap_per_payload() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_versus(judge, VersusConfig.new())
	var notes: Array = []
	for i in range(4):
		notes.append({"time": 2.0 + 0.5 * i, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 7})
	notes.append({"time": 4.5, "lane": 2, "kind": VersusJudge.GHOST, "payload_id": 8})
	judge.add_overlay(notes)
	for i in range(4):
		judge.press(1, 2.0 + 0.5 * i)
	assert_float(hull.hull).is_equal(88.0)
	judge.press(2, 4.5)
	assert_float(hull.hull).is_equal(84.0)


func test_ignored_ghost_does_nothing() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_versus(judge, VersusConfig.new())
	var r := _rec(judge)
	judge.add_overlay([{"time": 2.0, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 7}])
	judge.tick(2.0 + 0.1 + 0.01)
	assert_int(r["extra"].size()).is_equal(0)
	assert_int(r["ghost"].size()).is_equal(0)
	assert_float(hull.hull).is_equal(100.0)
	assert_str(judge.overlay_notes()[0]["state"]).is_equal("passed")
	# A later press in that lane is a normal stray, not a ghost hit
	judge.press(1, 2.5)
	assert_int(r["ghost"].size()).is_equal(0)
	assert_int(r["stray"].size()).is_equal(1)


func test_ghost_outside_good_window_is_stray() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var r := _rec(judge)
	judge.add_overlay([{"time": 2.0, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 7}])
	judge.press(1, 1.85)
	assert_int(r["ghost"].size()).is_equal(0)
	assert_int(r["stray"].size()).is_equal(1)
	assert_str(judge.overlay_notes()[0]["state"]).is_equal("open")


func test_depth_note_perfect() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_versus(judge, VersusConfig.new())
	var r := _rec(judge)
	judge.add_overlay([{"time": 4.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1}])
	judge.press(2, 4.01)
	assert_int(r["extra"].size()).is_equal(1)
	var e: Array = r["extra"][0]
	assert_int(e[0]).is_equal(VersusJudge.DEPTH)
	assert_int(e[1]).is_equal(2)
	assert_int(e[2]).is_equal(P)
	assert_float(e[3]).is_equal_approx(0.01, 1e-9)
	assert_int(hull.perfect_count).is_equal(1)
	assert_int(hull.score).is_equal(100)
	assert_str(judge.overlay_notes()[0]["state"]).is_equal("judged")
	assert_int(judge.overlay_notes()[0]["judgment"]).is_equal(P)


func test_depth_note_good_and_early_miss() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var r := _rec(judge)
	judge.add_overlay([
		{"time": 2.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1},
		{"time": 3.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1},
	])
	judge.press(2, 2.08)
	judge.press(2, 2.88)  # 120 ms early -> early miss
	assert_int(r["extra"][0][2]).is_equal(G)
	assert_int(r["extra"][1][2]).is_equal(M)
	assert_int(r["stray"].size()).is_equal(0)


func test_depth_note_unpressed_misses_on_tick() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_versus(judge, VersusConfig.new())
	var r := _rec(judge)
	judge.add_overlay([{"time": 4.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1}])
	judge.tick(4.05)
	assert_int(r["extra"].size()).is_equal(0)
	judge.tick(4.2)
	assert_int(r["extra"].size()).is_equal(1)
	assert_int(r["extra"][0][2]).is_equal(M)
	assert_float(hull.hull).is_equal(92.0)
	assert_str(judge.overlay_notes()[0]["state"]).is_equal("missed")


func test_is_finished_waits_for_open_depth_notes() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	judge.add_overlay([
		{"time": 8.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1},
		{"time": 9.0, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 2},
	])
	judge.tick(7.0)
	assert_bool(judge.is_finished()).is_false()
	judge.tick(8.5)
	assert_bool(judge.is_finished()).is_true()  # an open ghost never blocks the end


func test_add_overlay_sorts_and_clear_payload() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	judge.add_overlay([
		{"time": 5.0, "lane": 1, "kind": VersusJudge.DEPTH, "payload_id": 1},
		{"time": 3.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 1},
	])
	judge.add_overlay([{"time": 3.0, "lane": 0, "kind": VersusJudge.GHOST, "payload_id": 2}])
	var ov := judge.overlay_notes()
	assert_int(ov.size()).is_equal(3)
	assert_float(ov[0]["time"]).is_equal(3.0)
	assert_int(ov[0]["lane"]).is_equal(0)
	assert_int(ov[1]["lane"]).is_equal(2)
	assert_float(ov[2]["time"]).is_equal(5.0)
	judge.clear_payload(1, 4.0)
	ov = judge.overlay_notes()
	assert_int(ov.size()).is_equal(2)
	for n in ov:
		assert_float(n["time"]).is_less(4.0)


func test_bad_overlay_entries_ignored() -> void:
	var judge := VersusJudge.new(_chart(), JudgeConfig.new())
	judge.add_overlay([
		{"time": 3.0, "lane": 7, "kind": VersusJudge.DEPTH, "payload_id": 1},
		{"time": NAN, "lane": 1, "kind": VersusJudge.DEPTH, "payload_id": 1},
		{"time": 3.0, "lane": 1, "kind": 99, "payload_id": 1},
		{"lane": 1},
	])
	assert_int(judge.overlay_notes().size()).is_equal(0)


# ---- equivalence with the pinned InputJudge (T-03-11) ----

func _schedule(fps: float, length: float, jitter: bool) -> Array[float]:
	var out: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var t := 0.0
	while t < length:
		var dt := 1.0 / fps
		if jitter:
			dt *= rng.randf_range(0.4, 1.8)
			if rng.randf() < 0.01:
				dt += 0.1
		t += dt
		out.append(t)
	return out


func _log_judge(judge: InputJudge) -> Array:
	var log: Array = []
	judge.judged.connect(func(l: int, i: int, j: int, e: float) -> void: log.append(["j", l, i, j, e]))
	judge.stray.connect(func(l: int) -> void: log.append(["s", l]))
	judge.sustain_tick.connect(func(l: int) -> void: log.append(["t", l]))
	judge.sustain_end.connect(func(l: int, c: bool) -> void: log.append(["e", l, c]))
	return log


func _autoplay_log(chart: ChartData, judge: InputJudge, times: Array[float]) -> Array:
	var log := _log_judge(judge)
	var ap := Autoplay.new(chart, judge)
	for t in times:
		ap.update(t)
		judge.tick(t)
	return log


## Sloppy human: every note pressed at time + N(0, 70 ms) (some lapses), random strays, early
## releases; presses at frame times like LaneInput.
func _sloppy_log(chart: ChartData, judge: InputJudge, times: Array[float]) -> Array:
	var log := _log_judge(judge)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ev: Array = []
	for n in chart.notes:
		if rng.randf() < 0.05:
			continue
		var pt: float = n["time"] + rng.randfn(0.0, 0.07)
		ev.append([pt, 1, n["lane"]])
		var rel: float = pt + maxf(n["duration"] * rng.randf_range(0.5, 1.1), 0.05)
		ev.append([rel, 0, n["lane"]])
		if rng.randf() < 0.1:
			ev.append([pt + 0.3, 1, rng.randi_range(0, 3)])
	ev.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var k := 0
	for t in times:
		while k < ev.size() and ev[k][0] <= t:
			if ev[k][1] == 1:
				judge.press(ev[k][2], t)
			else:
				judge.release(ev[k][2], t)
			k += 1
		judge.tick(t)
	return log


func test_no_overlay_equivalent_to_input_judge() -> void:
	for chart in [TestCharts.short_chart(SAMPLE_RATE), TestCharts.hand_chart(SAMPLE_RATE)]:
		var last: float = chart.notes[chart.notes.size() - 1]["time"] + 3.0
		for jitter in [false, true]:
			var times := _schedule(60.0, last, jitter)
			var a := _autoplay_log(chart, InputJudge.new(chart, JudgeConfig.new()), times)
			var b := _autoplay_log(chart, VersusJudge.new(chart, JudgeConfig.new()), times)
			assert_int(a.size()).is_greater(0)
			assert_array(b).is_equal(a)
			var c := _sloppy_log(chart, InputJudge.new(chart, JudgeConfig.new()), times)
			var d := _sloppy_log(chart, VersusJudge.new(chart, JudgeConfig.new()), times)
			assert_array(d).is_equal(c)
