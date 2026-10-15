extends GdUnitTestSuite
## 03-08 Task 2: overlay gems (ghost / depth charge), warhead rings, ghost shatter and the Ink
## Cloud board layers (03-UI-SPEC 7.1-7.4, 12). The board reads a PayloadStack and a
## VersusJudge; frames are stepped by resetting the idle conductor's clock.

## 120 bpm (beat 0.5 s). Base notes: lane 0 and lane 1 at 10.0 (a chord), lane 3 at 14.0.
const BPM := 120.0


class NotesProbe extends Control:
	var hw: Highway
	var draws := 0

	func _draw() -> void:
		if hw != null:
			hw.draw_halos_into(self)
			hw.draw_notes_into(self)
			draws += 1


var _saved_low: bool
var _saved_reduce: bool
var _saved_speed: float
var _saved_offset: float


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_reduce = Settings.reduce_motion
	_saved_speed = Settings.scroll_speed
	_saved_offset = Settings.visual_offset
	Settings.low_effects = false
	Settings.reduce_motion = false
	Settings.scroll_speed = 1.0
	Settings.visual_offset = 0.0


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_reduce
	Settings.scroll_speed = _saved_speed
	Settings.visual_offset = _saved_offset


func _chart() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": BPM})
	c.add_note(0, 10.0)
	c.add_note(1, 10.0)
	c.add_note(3, 14.0)
	c.finalize()
	return c


## [hw, stack, judge, probe]
func _board(t: float) -> Array:
	var chart := _chart()
	var conductor: Conductor = auto_free(Conductor.new())
	add_child(conductor)
	var hw: Highway = auto_free(Highway.new())
	add_child(hw)
	hw.setup(chart, conductor)
	var cfg := VersusConfig.new()
	var stack := PayloadStack.new(chart, cfg)
	var judge := VersusJudge.new(chart, JudgeConfig.new())
	judge.judged.connect(hw.on_judged)
	hw.bind_versus(stack, judge, cfg)
	var probe: NotesProbe = auto_free(NotesProbe.new())
	probe.hw = hw
	probe.size = Vector2(1920, 1080)
	add_child(probe)
	_at(hw, t)
	return [hw, stack, judge, probe]


func _at(hw: Highway, t: float) -> void:
	hw.conductor.clock.reset(0, t)
	hw._update_window()


func _frame(probe: NotesProbe) -> void:
	probe.queue_redraw()
	await await_idle_frame()


func _ghost(judge: VersusJudge, t: float, lane: int) -> void:
	judge.add_overlay([{"time": t, "lane": lane, "kind": VersusJudge.GHOST, "payload_id": 1}])


func _depth(judge: VersusJudge, t: float, lane: int) -> void:
	judge.add_overlay([{"time": t, "lane": lane, "kind": VersusJudge.DEPTH, "payload_id": 2}])


# ---- PAY-03 ghosts (UI-SPEC 7.2) ---------------------------------------------------------

func test_ghost_draws_as_ghost_at_its_depth_in_every_mode() -> void:
	for mode in [[false, false], [true, false], [false, true]]:
		Settings.low_effects = mode[0]
		Settings.reduce_motion = mode[1]
		var b := _board(10.5)
		var hw: Highway = b[0]
		_ghost(b[2], 11.0, 2)
		_at(hw, 10.5)
		await _frame(b[3])
		var st := hw.debug_payload_state()
		assert_int(int(st["overlay_drawn"])).is_equal(1)
		var last: Dictionary = st["overlay_last"]
		assert_int(int(last["type"])).is_equal(NotePainter.NOTE_GHOST)
		var expect := Trench.point(hw.lane_x_f(2), Trench.depth_for(11.0, 10.5, hw._approach))
		assert_float((last["center"] as Vector2).distance_to(expect)).is_less_equal(0.5)
		assert_int(int(st["warheads_drawn"])).is_equal(0)


func test_ghost_stays_a_ghost_under_sonar_jam() -> void:
	var b := _board(10.5)
	var hw: Highway = b[0]
	(b[1] as PayloadStack).install({"id": 3, "reward": Reward.Id.SONAR_JAM, "arrive_t": 2.0, "end_t": 20.0})
	_ghost(b[2], 11.0, 2)
	_depth(b[2], 11.5, 1)
	_at(hw, 10.5)
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["overlay_drawn"])).is_equal(2)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_GHOST)).is_equal(NotePainter.NOTE_GHOST)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_DISRUPTOR)).is_equal(NotePainter.NOTE_JAM)
	var types: Array = hw.debug_payload_state()["overlay_types"]
	assert_bool(types.has(NotePainter.NOTE_GHOST)).is_true()
	assert_bool(types.has(NotePainter.NOTE_JAM)).is_true()


func test_hit_ghost_shatters_then_is_gone() -> void:
	var b := _board(11.0)
	var hw: Highway = b[0]
	var judge: VersusJudge = b[2]
	_ghost(judge, 11.0, 2)
	judge.press(2, 11.0)
	_at(hw, 11.0)
	assert_int(int(hw.debug_payload_state()["fragments"])).is_equal(1)
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["overlay_drawn"])).is_equal(0)  # the gem is gone
	_at(hw, 11.125)
	assert_float(float(hw.debug_payload_state()["fragment_drift"])).is_equal_approx(6.0, 0.01)
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["fragments_drawn"])).is_equal(1)
	_at(hw, 11.3)
	assert_int(int(hw.debug_payload_state()["fragments"])).is_equal(0)
	# Re-scanning the same hit ghost never shatters it twice.
	_at(hw, 11.31)
	assert_int(int(hw.debug_payload_state()["fragments"])).is_equal(0)


func test_hit_ghost_reduce_motion_fades_without_drift() -> void:
	Settings.reduce_motion = true
	var b := _board(11.0)
	var hw: Highway = b[0]
	_ghost(b[2], 11.0, 2)
	(b[2] as VersusJudge).press(2, 11.0)
	_at(hw, 11.0)
	_at(hw, 11.125)
	assert_int(int(hw.debug_payload_state()["fragments"])).is_equal(1)
	assert_float(float(hw.debug_payload_state()["fragment_drift"])).is_equal(0.0)


func test_ignored_ghost_fades_below_line_with_no_x() -> void:
	var b := _board(11.05)
	var hw: Highway = b[0]
	var judge: VersusJudge = b[2]
	_ghost(judge, 11.0, 2)
	judge.tick(11.2)
	assert_str(String(judge.overlay_notes()[0]["state"])).is_equal("passed")
	_at(hw, 11.075)
	await _frame(b[3])
	var last: Dictionary = hw.debug_payload_state()["overlay_last"]
	assert_int(int(last["type"])).is_equal(NotePainter.NOTE_GHOST)
	assert_int(int(last["paint"])).is_not_equal(NotePainter.STATE_MISSED)
	assert_float(float(last["alpha"])).is_between(0.3, 0.7)
	assert_float((last["center"] as Vector2).y).is_greater(Trench.HIT_Y)
	_at(hw, 11.16)
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["overlay_drawn"])).is_equal(0)


# ---- PAY-05 depth charges (UI-SPEC 7.3, Pitfall 1) ----------------------------------------

func test_depth_charge_draws_as_disruptor() -> void:
	var b := _board(11.0)
	var hw: Highway = b[0]
	_depth(b[2], 11.5, 1)
	_at(hw, 11.0)
	await _frame(b[3])
	var last: Dictionary = hw.debug_payload_state()["overlay_last"]
	assert_int(int(last["type"])).is_equal(NotePainter.NOTE_DISRUPTOR)
	assert_float((last["center"] as Vector2).x).is_equal_approx(Trench.point(Trench.lane_f(1), 1.0 / 3.0).x, 0.5)


func test_depth_charge_first_depth_is_far_end_when_window_starts_after_approach() -> void:
	var b := _board(9.0)
	var hw: Highway = b[0]
	var judge: VersusJudge = b[2]
	var arrive := 9.0
	# 03-04 window rule: the overlay window starts at the first beat >= arrive + approach.
	var tempo: Array = hw.chart.tempo_map
	var start := BeatClock.time_at_beat(ceilf(BeatClock.beat_at(arrive + hw._approach, tempo) - 1e-9), tempo)
	_depth(judge, start, 2)
	_depth(judge, start + 0.5, 3)
	var t := arrive
	while t <= start:
		_at(hw, t)
		t += 1.0 / 60.0
	var first: Dictionary = hw.debug_payload_state()["first_depth_by_overlay"]
	assert_int(first.size()).is_greater_equal(2)
	for uid in first:
		assert_float(float(first[uid])).is_greater_equal(Trench.D_FAR - 1e-6)
	# Negative control: a note injected mid-board would be caught.
	_depth(judge, t + 0.5, 0)
	_at(hw, t)
	var later: Dictionary = hw.debug_payload_state()["first_depth_by_overlay"]
	var low := INF
	for uid in later:
		low = minf(low, float(later[uid]))
	assert_float(low).is_less(Trench.D_FAR)


func test_judged_depth_charge_disappears_and_missed_one_pins() -> void:
	var b := _board(11.0)
	var hw: Highway = b[0]
	var judge: VersusJudge = b[2]
	_depth(judge, 11.0, 1)
	_depth(judge, 11.5, 2)
	judge.press(1, 11.0)
	judge.tick(11.7)
	_at(hw, 11.7)
	await _frame(b[3])
	var st := hw.debug_payload_state()
	assert_int(int(st["overlay_drawn"])).is_equal(1)  # only the missed remnant
	assert_int(int((st["overlay_last"] as Dictionary)["paint"])).is_equal(NotePainter.STATE_MISSED)


# ---- PAY-06 warheads (UI-SPEC 7.1) ----------------------------------------------------------

func test_warhead_open_ring_drawn_from_mark() -> void:
	var b := _board(9.5)
	var hw: Highway = b[0]
	var stack: PayloadStack = b[1]
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["warheads_drawn"])).is_equal(0)
	stack.mark_warheads(7, [0, 1])
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["warheads_drawn"])).is_equal(2)
	stack.kill(7)
	await _frame(b[3])
	assert_int(int(hw.debug_payload_state()["warheads_drawn"])).is_equal(2)  # DEAD style, still drawn


func test_warhead_confirm_flashes_once_for_200ms() -> void:
	for reduce in [false, true]:
		Settings.reduce_motion = reduce
		var b := _board(9.9)
		var hw: Highway = b[0]
		var stack: PayloadStack = b[1]
		var judge: VersusJudge = b[2]
		stack.mark_warheads(7, [0])
		judge.press(0, 10.0)
		stack.confirm(0)
		_at(hw, 10.0)
		var st := hw.debug_payload_state()
		assert_int(int(st["warhead_flashes"])).is_equal(1)
		assert_bool(bool(st["flash_grow"])).is_equal(not reduce)
		_at(hw, 10.1)
		assert_float(float(hw.debug_payload_state()["flash_k"])).is_equal_approx(0.5, 0.01)
		await _frame(b[3])
		assert_int(int(hw.debug_payload_state()["flashes_drawn"])).is_equal(1)
		_at(hw, 10.25)
		assert_int(int(hw.debug_payload_state()["warhead_flashes"])).is_equal(0)
		_at(hw, 10.3)
		assert_int(int(hw.debug_payload_state()["warhead_flashes"])).is_equal(0)  # once only


# ---- PAY-04 Ink Cloud layers (UI-SPEC 7.4) --------------------------------------------------

func _ink_board(t: float) -> Array:
	var b := _board(t)
	(b[1] as PayloadStack).install({"id": 4, "reward": Reward.Id.INK_CLOUD, "arrive_t": 2.0, "end_t": 20.0})
	_at(b[0], t)
	return b


func test_ink_cloud_band_covers_lane_area_and_fades() -> void:
	var b := _ink_board(10.0)
	var hw: Highway = b[0]
	var ink: InkCloudLayer = auto_free(InkCloudLayer.new())
	ink.bind(hw)
	add_child(ink)
	var poly := ink.band_polygon()
	var cfg := VersusConfig.new()
	assert_int(poly.size()).is_equal(4)
	assert_that(poly[0]).is_equal(Trench.point(-2.0, cfg.ink_depth_bottom))
	assert_that(poly[1]).is_equal(Trench.point(2.0, cfg.ink_depth_bottom))
	assert_that(poly[2]).is_equal(Trench.point(2.0, cfg.ink_depth_top))
	assert_that(poly[3]).is_equal(Trench.point(-2.0, cfg.ink_depth_top))
	assert_float(ink.band_alpha()).is_equal(1.0)
	ink.queue_redraw()
	await await_idle_frame()
	assert_bool(bool(ink.debug_state()["band_drawn"])).is_true()
	_at(hw, 2.25)
	assert_float(ink.band_alpha()).is_between(0.01, 0.99)
	_at(hw, 1.0)
	assert_float(ink.band_alpha()).is_equal(0.0)


func test_ink_cloud_effect_modes() -> void:
	var b := _ink_board(10.0)
	var ink: InkCloudLayer = auto_free(InkCloudLayer.new())
	ink.bind(b[0])
	add_child(ink)
	assert_bool(ink.is_in_group(UiKit.FX_GROUP)).is_true()
	Settings.low_effects = false
	Settings.reduce_motion = false
	ink.apply_effect_settings()
	assert_that(ink.effect_counts()).is_equal({"feather": true, "edge_line": false, "drift": true})
	ink.queue_redraw()
	await await_idle_frame()
	assert_int(int(ink.debug_state()["feathers_drawn"])).is_equal(6)
	Settings.low_effects = true
	ink.apply_effect_settings()
	assert_that(ink.effect_counts()).is_equal({"feather": false, "edge_line": true, "drift": false})
	ink.queue_redraw()
	await await_idle_frame()
	assert_int(int(ink.debug_state()["feathers_drawn"])).is_equal(0)
	assert_bool(bool(ink.debug_state()["edge_line_drawn"])).is_true()
	Settings.low_effects = false
	Settings.reduce_motion = true
	ink.apply_effect_settings()
	assert_that(ink.effect_counts()).is_equal({"feather": true, "edge_line": false, "drift": false})
	assert_float(ink.feather_offset(1.234, 2)).is_equal(0.0)


func test_ink_top_layer_draws_only_with_ink() -> void:
	var b := _board(10.0)
	var hw: Highway = b[0]
	var top: InkTopLayer = auto_free(InkTopLayer.new())
	top.bind(hw)
	add_child(top)
	assert_bool(top.is_in_group(UiKit.FX_GROUP)).is_false()
	assert_that(top.effect_counts()).is_equal({"ink_top": true})
	top.queue_redraw()
	await await_idle_frame()
	assert_bool(bool(top.debug_state()["drawn"])).is_false()
	(b[1] as PayloadStack).install({"id": 4, "reward": Reward.Id.INK_CLOUD, "arrive_t": 2.0, "end_t": 20.0})
	_at(hw, 10.0)
	hw.on_lane_pressed(1, Time.get_ticks_usec())
	top.queue_redraw()
	await await_idle_frame()
	var st := top.debug_state()
	assert_bool(bool(st["drawn"])).is_true()
	assert_int(int(st["ticks"])).is_equal(5)
	assert_int(int(st["outlines"])).is_equal(4)
	assert_int(int(st["fills"])).is_equal(1)
	hw.on_lane_released(1, Time.get_ticks_usec())
	hw._press_ticks[1] = -1
	top.queue_redraw()
	await await_idle_frame()
	assert_int(int(top.debug_state()["fills"])).is_equal(0)
