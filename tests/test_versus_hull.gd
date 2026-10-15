extends GdUnitTestSuite
## VersusHull (03-SPEC req 6, D-08, D-12): heal without revive, Overclock score, capped ghost
## damage, overlay (Depth Charge) judgments scored like base notes.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS


func _make() -> VersusHull:
	return VersusHull.new(JudgeConfig.new())


func _hit(h: HullScore, j: int, n: int = 1) -> void:
	for i in range(n):
		h.on_judged(0, 0, j, 0.0)


func test_heal_caps_at_full() -> void:
	var h := _make()
	h._set_hull(90.0)
	h.heal(25.0)
	assert_float(h.hull).is_equal(100.0)
	h._set_hull(50.0)
	h.heal(25.0)
	assert_float(h.hull).is_equal(75.0)


func test_heal_does_not_revive() -> void:
	var h := _make()
	_hit(h, M, 13)
	assert_bool(h.is_failed).is_true()
	var before := h.hull
	h.heal(25.0)
	assert_float(h.hull).is_equal(before)


func test_overclock_good_at_x4_scores_perfect_value() -> void:
	var h := _make()
	_hit(h, P, 30)
	assert_int(h.multiplier()).is_equal(4)
	var before := h.score
	h.overclock_until = 10.0
	h.now = 5.0
	_hit(h, G)
	assert_int(h.score - before).is_equal(400)
	assert_int(h.good_count).is_equal(1)
	assert_int(h.perfect_streak).is_equal(0)  # raw judgment unchanged


func test_good_after_overclock_scores_good() -> void:
	var h := _make()
	_hit(h, P, 30)
	var before := h.score
	h.overclock_until = 10.0
	h.now = 10.0
	_hit(h, G)
	assert_int(h.score - before).is_equal(200)


func test_overclock_perfect_unchanged() -> void:
	var h := _make()
	_hit(h, P, 30)
	var before := h.score
	h.overclock_until = 10.0
	h.now = 1.0
	_hit(h, P)
	assert_int(h.score - before).is_equal(400)


func test_ghost_hit_costs_and_breaks_combo() -> void:
	var h := _make()
	_hit(h, P, 5)
	h.ghost_hit(7, 4.0, 12.0)
	assert_float(h.hull).is_equal(96.0)
	assert_int(h.combo).is_equal(0)
	assert_int(h.perfect_streak).is_equal(0)
	assert_int(h.stray_count).is_equal(1)


func test_ghost_damage_capped_per_payload() -> void:
	var h := _make()
	for i in range(4):
		h.ghost_hit(7, 4.0, 12.0)
	assert_float(h.hull).is_equal(88.0)
	assert_int(h.combo).is_equal(0)
	h.ghost_hit(8, 4.0, 12.0)
	assert_float(h.hull).is_equal(84.0)
	assert_float(h.ghost_damage_spent(7)).is_equal(12.0)
	assert_float(h.ghost_damage_spent(8)).is_equal(4.0)


func test_partial_cap_remainder() -> void:
	var h := _make()
	h.ghost_hit(1, 5.0, 12.0)
	h.ghost_hit(1, 5.0, 12.0)
	h.ghost_hit(1, 5.0, 12.0)
	assert_float(h.hull).is_equal(88.0)


func test_extra_judged_scored_like_base() -> void:
	var h := _make()
	_hit(h, M)
	h.on_extra_judged(VersusJudge.DEPTH, 2, P, 0.01)
	assert_float(h.hull).is_equal(92.25)
	assert_int(h.score).is_equal(100)
	assert_int(h.combo).is_equal(1)
	h.on_extra_judged(VersusJudge.DEPTH, 2, M, 0.2)
	assert_float(h.hull).is_equal(84.25)
	assert_int(h.combo).is_equal(0)


func test_connect_versus_routes_ghost_and_extra() -> void:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 1.0)
	c.finalize()
	var judge := VersusJudge.new(c, JudgeConfig.new())
	var h := _make()
	h.connect_versus(judge, VersusConfig.new())
	judge.add_overlay([
		{"time": 2.0, "lane": 1, "kind": VersusJudge.GHOST, "payload_id": 3},
		{"time": 3.0, "lane": 2, "kind": VersusJudge.DEPTH, "payload_id": 4},
	])
	judge.press(0, 1.0)
	judge.press(1, 2.0)
	assert_float(h.hull).is_equal(96.0)
	assert_int(h.combo).is_equal(0)
	judge.press(2, 3.0)
	assert_int(h.perfect_count).is_equal(2)
	assert_int(h.combo).is_equal(1)
