extends GdUnitTestSuite
## PayloadStack (D-09, D-10, D-13, D-15, D-17, D-25, UI-SPEC 7.4-7.7): beat-locked modifier
## queries a board view and LaneInput read for one player's highway.

const SAMPLE_RATE := 8000

var _chart: ChartData


func before() -> void:
	_chart = TestCharts.click_chart(120.0, 256, SAMPLE_RATE)  # 0.5 s beats


func _stack() -> PayloadStack:
	return PayloadStack.new(_chart, VersusConfig.new())


func _rec(id: int, reward: int, arrive: float, end: float, seed: int = 1) -> Dictionary:
	return {"id": id, "reward": reward, "from": 1, "to": 0, "arrive_t": arrive,
		"active_start": arrive, "end_t": end, "seed": seed, "reflected": false, "debris": false}


func test_pressure_crack_scroll_ease() -> void:
	var s := _stack()
	s.install(_rec(1, Reward.Id.PRESSURE_CRACK, 10.0, 18.0))
	assert_float(s.scroll_mult(9.9)).is_equal(1.0)
	assert_float(s.scroll_mult(10.0)).is_equal(1.0)
	var mid := s.scroll_mult(10.25)
	assert_float(mid).is_greater(1.0)
	assert_float(mid).is_less(1.5)
	assert_float(mid).is_equal_approx(1.25, 1e-6)  # smoothstep(0.5) = 0.5
	assert_float(s.scroll_mult(10.1)).is_less(1.0 + 0.5 * 0.2)  # eases in (slow start)
	for t in [10.5, 12.0, 15.0, 17.5, 18.0]:
		assert_float(s.scroll_mult(t)).is_equal_approx(1.5, 1e-6)
	assert_float(s.scroll_mult(18.25)).is_equal_approx(1.25, 1e-6)
	assert_float(s.scroll_mult(18.5)).is_equal_approx(1.0, 1e-6)
	assert_float(s.scroll_mult(20.0)).is_equal(1.0)
	assert_float(s.rail_tint(9.0)).is_equal(0.0)
	assert_float(s.rail_tint(10.25)).is_equal_approx(0.5, 1e-6)
	assert_float(s.rail_tint(14.0)).is_equal_approx(1.0, 1e-6)
	assert_float(s.rail_tint(18.5)).is_equal_approx(0.0, 1e-6)
	assert_int(s.active_reward(14.0)).is_equal(Reward.Id.PRESSURE_CRACK)
	assert_int(s.active_reward(9.0)).is_equal(-1)
	assert_int(s.active_reward(19.0)).is_equal(-1)


func test_effective_speed_cap() -> void:
	assert_float(PayloadStack.effective_speed(3.0, 1.5, 3.5)).is_equal(3.5)
	assert_float(PayloadStack.effective_speed(1.0, 1.5, 3.5)).is_equal(1.5)
	assert_float(PayloadStack.effective_speed(4.0, 1.0, 3.5)).is_equal(4.0)
	assert_float(PayloadStack.effective_speed(4.0, 1.5, 3.5)).is_equal(4.0)  # never slower


func test_groan_debris() -> void:
	var s := _stack()
	var r := _rec(2, Reward.Id.GROAN, 4.0, 6.0)
	r["debris"] = true
	s.install(r)
	assert_float(s.scroll_mult(5.0)).is_equal_approx(1.25, 1e-6)
	assert_float(s.rail_tint(5.0)).is_equal_approx(0.5, 1e-6)


func test_crossed_wires_slide_and_input_map() -> void:
	for seed in [1, 2, 3, 99, 12345]:
		var s := _stack()
		s.install(_rec(3, Reward.Id.CROSSED_WIRES, 10.0, 18.0, seed))
		var pair := s.crossed_pair()
		var a := pair.x
		var b := pair.y
		assert_bool(a >= 0 and a < 4 and b >= 0 and b < 4 and a != b).is_true()
		# same seed, same pair
		var s2 := _stack()
		s2.install(_rec(3, Reward.Id.CROSSED_WIRES, 10.0, 18.0, seed))
		assert_that(s2.crossed_pair()).is_equal(pair)
		assert_float(s.lane_pos(a, 10.0)).is_equal(Trench.lane_f(a))
		assert_float(s.lane_pos(a, 10.5)).is_equal_approx(Trench.lane_f(b), 1e-6)
		assert_float(s.lane_pos(b, 10.5)).is_equal_approx(Trench.lane_f(a), 1e-6)
		var mid := s.lane_pos(a, 10.25)
		assert_float(mid).is_equal_approx((Trench.lane_f(a) + Trench.lane_f(b)) * 0.5, 1e-6)
		var q := s.lane_pos(a, 10.125)  # cubic in-out: 4 x^3 at x = 0.25 -> 0.0625
		assert_float(q).is_equal_approx(lerpf(Trench.lane_f(a), Trench.lane_f(b), 0.0625), 1e-6)
		for other in range(4):
			if other != a and other != b:
				assert_float(s.lane_pos(other, 10.25)).is_equal(Trench.lane_f(other))
		assert_array(Array(s.input_map(10.49))).is_equal([0, 1, 2, 3])
		var swapped := [0, 1, 2, 3]
		swapped[a] = b
		swapped[b] = a
		assert_array(Array(s.input_map(10.5))).is_equal(swapped)
		assert_array(Array(s.input_map(18.25))).is_equal(swapped)  # return slide still running
		assert_array(Array(s.input_map(18.5))).is_equal([0, 1, 2, 3])
		assert_float(s.lane_pos(a, 18.5)).is_equal_approx(Trench.lane_f(a), 1e-6)
		assert_float(s.lane_pos(a, 19.0)).is_equal(Trench.lane_f(a))
		assert_float(s.slide_k(10.25)).is_equal_approx(0.5, 1e-6)
		assert_bool(s.sliding(10.25)).is_true()
		assert_bool(s.sliding(14.0)).is_false()
		assert_float(s.slide_k(18.25)).is_equal_approx(0.5, 1e-6)
		assert_that(s.crossed_pair(30.0)).is_equal(Vector2i(-1, -1))
		assert_that(s.crossed_pair(14.0)).is_equal(pair)


func test_no_crossed_wires() -> void:
	var s := _stack()
	assert_that(s.crossed_pair()).is_equal(Vector2i(-1, -1))
	assert_array(Array(s.input_map(5.0))).is_equal([0, 1, 2, 3])
	for lane in range(4):
		assert_float(s.lane_pos(lane, 5.0)).is_equal(Trench.lane_f(lane))


func test_jam_and_ink_fades() -> void:
	var s := _stack()
	s.install(_rec(4, Reward.Id.SONAR_JAM, 10.0, 16.0))
	assert_float(s.jam_amount(9.0)).is_equal(0.0)
	assert_float(s.jam_amount(10.25)).is_equal_approx(0.5, 1e-6)
	assert_float(s.jam_amount(12.0)).is_equal_approx(1.0, 1e-6)
	assert_float(s.jam_amount(16.25)).is_equal_approx(0.5, 1e-6)
	assert_float(s.jam_amount(16.5)).is_equal_approx(0.0, 1e-6)
	assert_float(s.ink_amount(12.0)).is_equal(0.0)
	s.install(_rec(5, Reward.Id.INK_CLOUD, 20.0, 28.0))
	assert_float(s.ink_amount(20.5)).is_equal_approx(1.0, 1e-6)
	assert_float(s.ink_amount(28.5)).is_equal_approx(0.0, 1e-6)
	assert_float(s.ink_top_depth(24.0)).is_equal(0.35)
	var silt := _rec(6, Reward.Id.SILT, 40.0, 42.0)
	silt["debris"] = true
	s.install(silt)
	assert_float(s.ink_amount(41.0)).is_equal_approx(1.0, 1e-6)
	assert_float(s.ink_top_depth(41.0)).is_equal(0.20)
	assert_float(s.ink_top_depth()).is_equal(0.20)  # latest ink payload


func test_end_early_eases_out_at_next_beat() -> void:
	var s := _stack()
	s.install(_rec(7, Reward.Id.PRESSURE_CRACK, 10.0, 18.0))
	s.end_early(7, 12.2)  # next beat 12.5, eased out by 13.0
	assert_float(s.scroll_mult(12.4)).is_equal_approx(1.5, 1e-6)
	assert_float(s.scroll_mult(12.75)).is_equal_approx(1.25, 1e-6)
	assert_float(s.scroll_mult(13.0)).is_equal_approx(1.0, 1e-6)
	assert_float(s.scroll_mult(15.0)).is_equal(1.0)
	s.end_early(7, 12.9)  # never extends an end that is already earlier
	assert_float(s.scroll_mult(13.0)).is_equal_approx(1.0, 1e-6)
	assert_float(s.scroll_mult(13.2)).is_equal(1.0)
	s.end_early(999, 11.0)  # unknown id: no-op


func test_end_early_exactly_on_beat() -> void:
	var s := _stack()
	s.install(_rec(7, Reward.Id.SONAR_JAM, 10.0, 18.0))
	s.end_early(7, 12.0)
	assert_float(s.jam_amount(12.25)).is_equal_approx(1.0, 1e-6)
	assert_float(s.jam_amount(13.0)).is_equal_approx(0.0, 1e-6)


func test_clear_and_invalid_records() -> void:
	var s := _stack()
	s.install(_rec(1, Reward.Id.PRESSURE_CRACK, 10.0, 18.0))
	s.mark_warheads(1, [3, 4])
	s.clear()
	assert_float(s.scroll_mult(14.0)).is_equal(1.0)
	assert_int(s.warhead_state(3)).is_equal(-1)
	s.install({"id": 2, "reward": 77, "arrive_t": 1.0, "end_t": 2.0, "seed": 0})
	s.install({"id": 3, "reward": Reward.Id.SONAR_JAM, "arrive_t": NAN, "end_t": 2.0, "seed": 0})
	s.install({"id": 4})
	assert_int(s.active_reward(1.5)).is_equal(-1)
	assert_int(s.payload_count()).is_equal(0)


func test_prune_drops_finished() -> void:
	var s := _stack()
	s.install(_rec(1, Reward.Id.PRESSURE_CRACK, 10.0, 12.0))
	s.install(_rec(2, Reward.Id.SONAR_JAM, 20.0, 22.0))
	s.prune(15.0)
	assert_int(s.payload_count()).is_equal(1)
	assert_float(s.jam_amount(21.0)).is_equal_approx(1.0, 1e-6)


func test_warheads() -> void:
	var s := _stack()
	assert_int(PayloadStack.OPEN).is_equal(NotePainter.WARHEAD_OPEN)
	assert_int(PayloadStack.CONFIRMED).is_equal(NotePainter.WARHEAD_CONFIRMED)
	assert_int(PayloadStack.DEAD).is_equal(NotePainter.WARHEAD_DEAD)
	s.mark_warheads(9, [3, 4, 5, 6])
	assert_int(s.warhead_state(4)).is_equal(PayloadStack.OPEN)
	s.confirm(4)
	assert_int(s.warhead_state(4)).is_equal(PayloadStack.CONFIRMED)
	assert_that(s.warhead_progress(9)).is_equal(Vector2i(1, 4))
	s.kill(9)
	assert_int(s.warhead_state(3)).is_equal(PayloadStack.DEAD)
	assert_int(s.warhead_state(4)).is_equal(PayloadStack.CONFIRMED)
	assert_int(s.warhead_state(6)).is_equal(PayloadStack.DEAD)
	s.confirm(5)  # dead stays dead
	assert_int(s.warhead_state(5)).is_equal(PayloadStack.DEAD)
	assert_int(s.warhead_state(42)).is_equal(-1)
	assert_that(s.warhead_progress(1234)).is_equal(Vector2i(0, 0))
	s.clear_warheads(9)
	assert_int(s.warhead_state(4)).is_equal(-1)
