extends GdUnitTestSuite
## WR-01 (03-REVIEW): the live VersusController path is frame-rate independent. The controller
## steps the judge-tick grid, the autoplay human, the bots and the drone in global song-time
## order (the MatchHarness ordering), and late misses are stamped at their deadline, so the same
## seeded match gives the same event log at 30, 144 and 1000 fps, and the same log as the
## headless MatchHarness.

const SEED := 11


static func _setup(seed: int) -> MatchSetup:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = 3
	m.skill = "veteran"
	m.seed = seed
	return m


static func _end_t(chart: ChartData) -> float:
	var last := 0.0
	for n in chart.notes:
		last = maxf(last, float(n["time"]) + float(n["duration"]))
	return last + 2.0


## Drives a real VersusController like Gameplay._process does (pre_tick, then update) at `fps`.
func _run_controller(fps: float, seed: int = SEED) -> Array:
	var chart := TestCharts.hand_chart(1000)
	var vc := VersusController.new()
	vc.setup(null, chart, JudgeConfig.new(), _setup(seed), -1, true)
	vc.human_rig.approach_s = 1.5  # MatchHarness default (Settings.scroll_speed independent)
	var end_t := _end_t(chart)
	var dt := 1.0 / fps
	var k := 0
	var t := MatchHarness.START_T
	while t < end_t:
		k += 1
		t = minf(MatchHarness.START_T + float(k) * dt, end_t)
		vc.pre_tick(t)
		vc.update(t)
	vc.finish(end_t)
	var log: Array = vc.sim.event_log.duplicate(true)
	vc.free()
	return log


func test_controller_logs_identical_at_30_144_1000_fps() -> void:
	var a := _run_controller(30.0)
	var b := _run_controller(144.0)
	var c := _run_controller(1000.0)
	var sa := var_to_str(a)
	assert_int(a.size()).is_greater(100)
	assert_str(var_to_str(b)).is_equal(sa)
	assert_str(var_to_str(c)).is_equal(sa)


func test_controller_matches_the_headless_harness() -> void:
	var live := _run_controller(60.0)
	var h := MatchHarness.run(TestCharts.hand_chart(1000), {"human": "autoplay",
		"bots": ["veteran", "veteran", "veteran"], "seed": SEED, "fps": 60.0,
		"cfg": VersusConfig.new().validated()})
	assert_str(var_to_str(live)).is_equal(var_to_str(h["event_log"]))


## Event timestamps never run backwards by more than one tick-grid step (bots used to be
## stepped one after another, each advancing the referee to frame time).
func test_controller_log_is_time_ordered() -> void:
	var log := _run_controller(30.0)
	var last := -INF
	var worst := 0.0
	for e in log:
		var t := float(e.get("t", 0.0))
		worst = maxf(worst, last - t)
		last = maxf(last, t)
	assert_float(worst).is_less_equal(VersusController.TICK_S + 1e-6)


## Real presses advance every rival to the press time before judging (human_press).
func test_human_press_advances_rivals_first() -> void:
	var chart := TestCharts.hand_chart(1000)
	var vc := VersusController.new()
	vc.setup(null, chart, JudgeConfig.new(), _setup(SEED), -1, false)
	vc.pre_tick(2.0)
	var first: Dictionary = chart.notes[0]
	vc.human_press(int(first["lane"]), 5.0)
	assert_float(vc.now).is_equal_approx(5.0, 1e-9)
	assert_float(vc.human_rig.now).is_equal_approx(5.0, 1e-9)
	for b in vc.bots:
		assert_float(b.next_time()).is_greater(5.0)
	vc.free()


## IN-03: a scroll-speed change mid-match refreshes the human's approach time (Ghost / Depth
## Charge window, Pitfall 1).
func test_scroll_speed_change_refreshes_approach() -> void:
	var saved := Settings.scroll_speed
	var vc := VersusController.new()
	vc.setup(null, TestCharts.hand_chart(1000), JudgeConfig.new(), _setup(SEED), -1, false)
	Settings.scroll_speed = 2.0  # direct + emit: never writes the real settings file
	Settings.settings_changed.emit()
	assert_float(vc.human_rig.approach_s).is_equal_approx(Trench.approach_for(Settings.scroll_speed), 1e-9)
	assert_float(vc.players[0].approach_s).is_equal_approx(vc.human_rig.approach_s, 1e-9)
	Settings.scroll_speed = saved
	Settings.settings_changed.emit()
	vc.free()
