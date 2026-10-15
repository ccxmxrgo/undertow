extends GdUnitTestSuite
## PayloadNotes (D-11, D-14, Pitfall 2, T-03-10), the D-08 / TORP-06 worst cases on every
## bundled chart, and VersusAutoplay (spec req 5 acceptance: all-Perfect with Depth Charge
## overlay notes, ghosts skipped).

const SAMPLE_RATE := 8000
const IDS: Array[String] = ["synth_wave_april", "space_synth_wave", "sea_shanty_2", "hrt", "invisible"]
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]
const WINDOWS := 10
const P := InputJudge.Judgment.PERFECT

static var _charts: Dictionary = {}


func _parsed(id: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes("res://songs/%s/notes.chart" % id))


func _bundled() -> Array:
	if _charts.is_empty():
		for id in IDS:
			var parsed := _parsed(id)
			for diff in DIFFS:
				_charts["%s/%s" % [id, diff]] = ChartImporter.build(parsed, diff)
	var out: Array = []
	for k in _charts:
		out.append([k, _charts[k]])
	return out


func _cfg() -> VersusConfig:
	return VersusConfig.new()


func _jcfg() -> JudgeConfig:
	return JudgeConfig.new()


## Window of `bars` 4/4 bars starting at the first beat at or after t.
func _window(chart: ChartData, t: float, bars: int) -> Vector2:
	var b0 := ceilf(BeatClock.beat_at(t, chart.tempo_map) - 1e-6)
	return Vector2(BeatClock.time_at_beat(b0, chart.tempo_map),
			BeatClock.time_at_beat(b0 + 4.0 * bars, chart.tempo_map))


func _starts(chart: ChartData) -> Array[float]:
	var last: float = chart.notes[chart.notes.size() - 1]["time"]
	var out: Array[float] = []
	for i in range(WINDOWS):
		out.append(last * float(i) / float(WINDOWS))
	return out


func _on_grid(chart: ChartData, t: float) -> bool:
	var e := BeatClock.beat_at(t, chart.tempo_map) * 2.0
	return absf(e - roundf(e)) < 1e-4


func _base_in(chart: ChartData, s: float, e: float) -> int:
	var n := 0
	for note in chart.notes:
		if note["time"] >= s and note["time"] < e:
			n += 1
	return n


## Pitfall 2 invariant, checked independently of PayloadNotes.is_free.
func _assert_spacing(key: String, chart: ChartData, ov: Array) -> void:
	var sp := _cfg().overlay_spacing_s
	var forgive := _jcfg().release_forgive_window
	for i in range(ov.size()):
		var o: Dictionary = ov[i]
		var t: float = o["time"]
		for n in chart.notes:
			if n["lane"] != o["lane"]:
				continue
			var nt: float = n["time"]
			if nt > t + sp + 1.0:
				break
			assert_bool(absf(nt - t) >= sp - 1e-6).override_failure_message(
					"%s: overlay %.3f lane %d within %.2f s of base %.3f" % [key, t, o["lane"], sp, nt]).is_true()
			if n["duration"] > 0.0:
				var inside: bool = t >= nt - 1e-6 and t <= nt + n["duration"] + forgive + 1e-6
				assert_bool(inside).override_failure_message(
						"%s: overlay %.3f inside sustain %.3f" % [key, t, nt]).is_false()
		for j in range(i + 1, ov.size()):
			assert_bool(absf(float(ov[j]["time"]) - t) >= sp - 1e-6).override_failure_message(
					"%s: overlays %.3f and %.3f too close" % [key, t, ov[j]["time"]]).is_true()


# ---- generators ----

func test_ghosts_count_kind_sort_and_determinism() -> void:
	var chart := TestCharts.click_chart(120.0, 64, SAMPLE_RATE)
	var w := Vector2(2.0, 10.0)  # 4 bars = 16 beats
	var g := PayloadNotes.ghosts(chart, w.x, w.y, _cfg(), _jcfg(), 42)
	assert_int(g.size()).is_less_equal(16)
	assert_int(g.size()).is_greater_equal(8)
	for i in range(g.size()):
		assert_int(g[i]["kind"]).is_equal(VersusJudge.GHOST)
		assert_float(g[i]["time"]).is_greater_equal(w.x - 1e-6)
		assert_float(g[i]["time"]).is_less(w.y)
		assert_bool(_on_grid(chart, g[i]["time"])).is_true()
		if i > 0:
			assert_float(g[i]["time"]).is_greater_equal(g[i - 1]["time"])
	assert_array(PayloadNotes.ghosts(chart, w.x, w.y, _cfg(), _jcfg(), 42)).is_equal(g)
	assert_array(PayloadNotes.ghosts(chart, w.x, w.y, _cfg(), _jcfg(), 43)).is_not_equal(g)
	_assert_spacing("click", chart, g)


func test_depth_charges_count_rule_and_grid() -> void:
	var chart := TestCharts.click_chart(120.0, 64, SAMPLE_RATE)
	var w := Vector2(2.0, 6.0)  # 2 bars, 8 base notes, 8 free off-beats
	var d := PayloadNotes.depth_charges(chart, w.x, w.y, _cfg(), _jcfg(), 7)
	assert_int(d.size()).is_equal(4)
	for n in d:
		assert_int(n["kind"]).is_equal(VersusJudge.DEPTH)
		assert_bool(_on_grid(chart, n["time"])).is_true()
		for b in chart.notes:
			assert_bool(absf(float(b["time"]) - float(n["time"])) < 1e-3).is_false()
	assert_float(d[0]["time"]).is_greater_equal(w.x)
	assert_array(PayloadNotes.depth_charges(chart, w.x, w.y, _cfg(), _jcfg(), 7)).is_equal(d)
	_assert_spacing("click", chart, d)


func test_depth_charges_at_least_min_notes() -> void:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	for i in range(8):
		c.add_note(i % 4, 2.0 * i)
	c.finalize()
	var d := PayloadNotes.depth_charges(c, 2.0, 6.0, _cfg(), _jcfg(), 1)  # 2 base notes
	assert_int(d.size()).is_equal(2)


func test_free_points_limit_count() -> void:
	# Every 8th-note grid point carries a base note: nothing is free.
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	for i in range(40):
		c.add_note(i % 4, 0.25 * i)
	c.finalize()
	assert_int(PayloadNotes.depth_charges(c, 2.0, 6.0, _cfg(), _jcfg(), 1).size()).is_equal(0)


func test_empty_and_hostile_windows() -> void:
	var chart := TestCharts.click_chart(120.0, 64, SAMPLE_RATE)
	assert_int(PayloadNotes.ghosts(chart, 5.0, 5.0, _cfg(), _jcfg(), 1).size()).is_equal(0)
	assert_int(PayloadNotes.depth_charges(chart, 6.0, 2.0, _cfg(), _jcfg(), 1).size()).is_equal(0)
	assert_int(PayloadNotes.ghosts(chart, NAN, 5.0, _cfg(), _jcfg(), 1).size()).is_equal(0)
	assert_int(PayloadNotes.grid_points(chart, 0.0, INF).size()).is_equal(0)
	var huge := PayloadNotes.ghosts(chart, 0.0, 1.0e6, _cfg(), _jcfg(), 1)
	assert_int(huge.size()).is_less_equal(PayloadNotes.MAX_NOTES)
	var dense := ChartData.new()
	dense.tempo_map.append({"time": 0.0, "bpm": 1.0e7})
	dense.add_note(0, 0.0)
	dense.finalize()
	assert_int(PayloadNotes.grid_points(dense, 0.0, 100.0).size()).is_less_equal(BeatClock.MAX_BEATS)
	assert_int(PayloadNotes.ghosts(dense, 0.0, 100.0, _cfg(), _jcfg(), 1).size()).is_less_equal(PayloadNotes.MAX_NOTES)
	assert_int(PayloadNotes.depth_charges(dense, 0.0, 100.0, _cfg(), _jcfg(), 1).size()).is_less_equal(PayloadNotes.MAX_NOTES)


func test_is_free_rules() -> void:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(1, 2.0, 1.0)
	c.add_note(2, 2.0)
	c.finalize()
	var cfg := _cfg()
	var j := _jcfg()
	assert_bool(PayloadNotes.is_free(c, 2.2, 2, [], cfg, j)).is_false()  # near base, same lane
	assert_bool(PayloadNotes.is_free(c, 2.25, 2, [], cfg, j)).is_true()
	assert_bool(PayloadNotes.is_free(c, 2.2, 0, [], cfg, j)).is_true()  # other lane
	assert_bool(PayloadNotes.is_free(c, 3.05, 1, [], cfg, j)).is_false()  # inside sustain + forgive
	assert_bool(PayloadNotes.is_free(c, 3.25, 1, [], cfg, j)).is_true()
	var taken := [{"time": 5.0, "lane": 3}]
	assert_bool(PayloadNotes.is_free(c, 5.1, 0, taken, cfg, j)).is_false()  # near another overlay
	assert_bool(PayloadNotes.is_free(c, 5.25, 0, taken, cfg, j)).is_true()


# ---- invariants on every bundled chart ----

func test_spacing_invariant_on_all_bundled_charts() -> void:
	var cfg := _cfg()
	var j := _jcfg()
	for kc in _bundled():
		var key: String = kc[0]
		var chart: ChartData = kc[1]
		var seed := 1
		for s in _starts(chart):
			seed += 1
			var wg := _window(chart, s, cfg.bars_ghost_notes)
			var g := PayloadNotes.ghosts(chart, wg.x, wg.y, cfg, j, seed)
			_assert_spacing(key, chart, g)
			var beats := BeatClock.beat_at(wg.y, chart.tempo_map) - BeatClock.beat_at(wg.x, chart.tempo_map)
			assert_int(g.size()).is_less_equal(int(ceilf(cfg.ghost_per_beat * beats - 1e-6)))
			var wd := _window(chart, s, cfg.bars_depth_charge)
			var d := PayloadNotes.depth_charges(chart, wd.x, wd.y, cfg, j, seed)
			_assert_spacing(key, chart, d)
			var cap := maxi(cfg.depth_charge_min_notes, int(floor(cfg.depth_charge_density * _base_in(chart, wd.x, wd.y))))
			assert_int(d.size()).is_less_equal(cap)
			assert_int(d.size()).is_less_equal(PayloadNotes.depth_cap(j))
			for n in d:
				assert_bool(_on_grid(chart, n["time"])).override_failure_message("%s off grid" % key).is_true()
				assert_float(n["time"]).is_greater_equal(wd.x - 1e-6)
				assert_float(n["time"]).is_less(wd.y)


## Runs a chart all-Perfect through VersusJudge/VersusHull with overlay notes; ghosts are hit
## (worst case) when hit_ghosts, depth notes are pressed only when press_depth. Returns the
## lowest hull seen.
func _worst_case(chart: ChartData, overlay: Array, hit_ghosts: bool, press_depth: bool) -> float:
	var judge := VersusJudge.new(chart, _jcfg())
	var hull := VersusHull.new(_jcfg())
	hull.connect_versus(judge, _cfg())
	var low := [hull.hull]
	hull.hull_changed.connect(func(v: float, _d: float) -> void: low[0] = minf(low[0], v))
	judge.add_overlay(overlay)
	var ap := Autoplay.new(chart, judge)
	var times: Array[float] = []
	for n in chart.notes:
		times.append(n["time"])
		if n["duration"] > 0.0:
			times.append(n["time"] + n["duration"])
	var extra: Array = []
	for o in overlay:
		times.append(o["time"])
		if (o["kind"] == VersusJudge.GHOST and hit_ghosts) or (o["kind"] == VersusJudge.DEPTH and press_depth):
			extra.append(o)
	times.sort()
	var k := 0
	for t in times:
		ap.update(t)
		while k < extra.size() and extra[k]["time"] <= t:
			judge.press(extra[k]["lane"], extra[k]["time"])
			k += 1
		judge.tick(t)
	judge.tick(times[times.size() - 1] + 1.0)
	assert_int(hull.perfect_count + hull.miss_count).is_greater_equal(chart.notes.size())
	return low[0]


func test_worst_case_hull_per_payload_on_all_bundled_charts() -> void:
	var cfg := _cfg()
	var j := _jcfg()
	for kc in _bundled():
		var key: String = kc[0]
		var chart: ChartData = kc[1]
		# Crossed Wires, Ink Cloud, Pressure Crack, Sonar Jam: no judge-side damage at all.
		assert_float(_worst_case(chart, [], false, false)).override_failure_message(key).is_equal(100.0)
		var seed := 100
		for s in _starts(chart):
			seed += 1
			var wg := _window(chart, s, cfg.bars_ghost_notes)
			var g := PayloadNotes.ghosts(chart, wg.x, wg.y, cfg, j, seed, 1)
			var lg := _worst_case(chart, g, true, false)
			assert_float(lg).override_failure_message("%s ghost hull %.2f" % [key, lg]).is_greater_equal(100.0 - cfg.ghost_damage_cap - 1e-6)
			var wd := _window(chart, s, cfg.bars_depth_charge)
			var d := PayloadNotes.depth_charges(chart, wd.x, wd.y, cfg, j, seed, 2)
			var ld := _worst_case(chart, d, false, false)
			assert_float(ld).override_failure_message("%s depth hull %.2f" % [key, ld]).is_greater(0.0)


# ---- VersusAutoplay ----

func _schedule(fps: float, length: float) -> Array[float]:
	var out: Array[float] = []
	var t := 0.0
	while t < length:
		t += 1.0 / fps
		out.append(t)
	return out


func _autoplay_run(chart: ChartData, fps: float) -> Dictionary:
	var cfg := _cfg()
	var j := _jcfg()
	var judge := VersusJudge.new(chart, j)
	var hull := VersusHull.new(j)
	hull.connect_versus(judge, cfg)
	var r := {"base": [], "extra": [], "ghost": 0}
	judge.judged.connect(func(_l: int, _i: int, jj: int, e: float) -> void: r["base"].append([jj, e]))
	judge.extra_judged.connect(func(_k: int, _l: int, jj: int, e: float) -> void: r["extra"].append([jj, e]))
	judge.ghost_hit.connect(func(_l: int, _p: int) -> void: r["ghost"] += 1)
	var last: float = chart.notes[chart.notes.size() - 1]["time"]
	var w1 := _window(chart, 0.5, cfg.bars_depth_charge)
	var w2 := _window(chart, last * 0.6, cfg.bars_depth_charge)
	var wg := _window(chart, last * 0.25, cfg.bars_ghost_notes)
	var d1 := PayloadNotes.depth_charges(chart, w1.x, w1.y, cfg, j, 11, 1)
	var d2 := PayloadNotes.depth_charges(chart, w2.x, w2.y, cfg, j, 12, 2)
	# MatchSim never overlaps two disruptors on one sub (immunity, D-07); keep ghosts clear
	# of the depth notes the same way.
	var g: Array = PayloadNotes.ghosts(chart, wg.x, wg.y, cfg, j, 13, 3).filter(func(o: Dictionary) -> bool:
		for dn in d1 + d2:
			if absf(float(dn["time"]) - float(o["time"])) < cfg.overlay_spacing_s:
				return false
		return true)
	judge.add_overlay(d1)
	judge.add_overlay(g)
	var ap := VersusAutoplay.new(chart, judge)
	var injected := false
	for t in _schedule(fps, last + 3.0):
		if not injected and t >= w2.x - 2.0:
			judge.add_overlay(d2)  # mid-run injection (a payload landing)
			ap.refresh(judge)
			injected = true
		ap.update(t)
		judge.tick(t)
	r["hull"] = hull
	r["judge"] = judge
	r["n_extra"] = d1.size() + d2.size()
	r["n_ghost"] = g.size()
	return r


func test_versus_autoplay_all_perfect_with_overlay() -> void:
	for chart in [TestCharts.short_chart(SAMPLE_RATE), TestCharts.hand_chart(SAMPLE_RATE)]:
		for fps in [30.0, 60.0, 144.0, 1000.0]:
			var r := _autoplay_run(chart, fps)
			assert_int(r["n_extra"]).is_greater_equal(4)
			assert_int(r["n_ghost"]).is_greater(0)
			assert_int(r["base"].size()).is_equal(chart.notes.size())
			for b in r["base"]:
				assert_int(b[0]).is_equal(P)
				assert_float(b[1]).is_equal(0.0)
			assert_int(r["extra"].size()).is_equal(r["n_extra"])
			for e in r["extra"]:
				assert_int(e[0]).is_equal(P)
				assert_float(e[1]).is_equal(0.0)
			assert_int(r["ghost"]).is_equal(0)
			var hull: VersusHull = r["hull"]
			assert_int(hull.stray_count).is_equal(0)
			assert_float(hull.hull).is_equal(100.0)
			assert_bool((r["judge"] as VersusJudge).is_finished()).is_true()


func test_versus_autoplay_ignores_past_overlay() -> void:
	var chart := TestCharts.short_chart(SAMPLE_RATE)
	var judge := VersusJudge.new(chart, _jcfg())
	var ap := VersusAutoplay.new(chart, judge)
	ap.update(3.0)
	judge.add_overlay([{"time": 2.75, "lane": 0, "kind": VersusJudge.DEPTH, "payload_id": 1}])
	ap.refresh(judge)
	var before := ap.pending()
	ap.refresh(judge)  # idempotent
	assert_int(ap.pending()).is_equal(before)
	judge.add_overlay([{"time": 3.75, "lane": 0, "kind": VersusJudge.DEPTH, "payload_id": 1}])
	ap.refresh(judge)
	ap.refresh(judge)
	assert_int(ap.pending()).is_equal(before + 1)
