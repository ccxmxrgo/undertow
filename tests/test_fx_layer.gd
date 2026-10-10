extends GdUnitTestSuite
## 02.2-10: FxLayer juice on the board (UI-SPEC 7.5, 7.6 trail column, 11). Pooled
## CPUParticles2D bursts per judgment, shockwave rings, the Perfect flash, the Miss crack and
## the board-only shake, tier rail sparks, sustain sparks, clipping and prewarm.

const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

var _saved_low := false
var _saved_rm := false


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm
	Gameplay.pending_chart = null
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _fx(board: Control = null) -> FxLayer:
	var fx: FxLayer = auto_free(FxLayer.new())
	if board != null:
		board.add_child(fx)
		fx.bind(null, board)
	else:
		add_child(fx)
	return fx


func _board() -> Control:
	var b: Control = auto_free(Control.new())
	add_child(b)
	return b


func _emitting(list: Array) -> int:
	var n := 0
	for e in list:
		if (e as CPUParticles2D).emitting:
			n += 1
	return n


# ---- Pool and counts per mode ---------------------------------------------------------------

func test_pool_has_sixteen_one_shot_fixed_seed_emitters() -> void:
	var fx := _fx()
	assert_int(fx.perfect_emitters.size()).is_equal(8)
	assert_int(fx.good_emitters.size()).is_equal(4)
	assert_int(fx.miss_emitters.size()).is_equal(4)
	var all := fx.burst_emitters()
	assert_int(all.size()).is_equal(16)
	for e in all:
		var p := e as CPUParticles2D
		assert_bool(p.one_shot).is_true()
		assert_bool(p.use_fixed_seed).is_true()
		assert_bool(p.emitting).is_false()
	assert_int(fx.rail_emitters.size()).is_equal(2)
	assert_int(fx.sustain_emitters.size()).is_equal(4)


func test_full_effect_counts() -> void:
	var fx := _fx()
	var c := fx.effect_counts()
	assert_int(int(c["perfect_amount"])).is_equal(24)
	assert_int(int(c["good_amount"])).is_equal(10)
	assert_int(int(c["miss_amount"])).is_equal(6)
	assert_bool(bool(c["flash"])).is_true()
	assert_bool(bool(c["shake"])).is_true()
	assert_float(float(c["sustain_rate"])).is_equal(30.0)
	assert_float(float(c["rail_rate"])).is_equal(0.0)  # tier 1
	assert_bool(fx.is_in_group(UiKit.FX_GROUP)).is_true()


func test_low_effects_counts() -> void:
	var fx := _fx()
	Settings.low_effects = true
	fx.apply_effect_settings()
	var c := fx.effect_counts()
	assert_int(int(c["perfect_amount"])).is_equal(8)
	assert_int(int(c["good_amount"])).is_equal(4)
	assert_int(int(c["miss_amount"])).is_equal(0)
	assert_bool(bool(c["flash"])).is_false()
	assert_bool(bool(c["shake"])).is_true()
	assert_float(float(c["sustain_rate"])).is_equal(0.0)
	fx.set_tier(4)
	assert_float(float(fx.effect_counts()["rail_rate"])).is_equal(0.0)
	assert_int(fx.perfect_emitters[0].amount).is_equal(8)


func test_reduce_motion_counts_and_half_speed() -> void:
	var fx := _fx()
	var full_v := fx.perfect_emitters[0].initial_velocity_max
	Settings.reduce_motion = true
	fx.apply_effect_settings()
	var c := fx.effect_counts()
	assert_int(int(c["perfect_amount"])).is_equal(24)
	assert_int(int(c["good_amount"])).is_equal(10)
	assert_int(int(c["miss_amount"])).is_equal(0)
	assert_bool(bool(c["flash"])).is_false()
	assert_bool(bool(c["shake"])).is_false()
	assert_float(float(c["sustain_rate"])).is_equal(0.0)
	assert_float(fx.perfect_emitters[0].initial_velocity_max).is_equal_approx(full_v * 0.5, 0.01)
	assert_float(full_v).is_equal_approx(380.0, 0.01)


func test_hit_burst_configures_per_judgment() -> void:
	var p: CPUParticles2D = auto_free(CPUParticles2D.new())
	HitBurst.configure(p, P, 1, false, false)
	assert_int(p.amount).is_equal(24)
	assert_float(p.lifetime).is_equal_approx(0.35, 0.001)
	assert_float(p.initial_velocity_min).is_equal_approx(220.0, 0.01)
	assert_float(p.gravity.y).is_equal_approx(1400.0, 0.01)
	assert_object(p.material).is_same(UiKit.additive_material())
	HitBurst.configure(p, G, 1, false, false)
	assert_int(p.amount).is_equal(10)
	assert_float(p.lifetime).is_equal_approx(0.25, 0.001)
	HitBurst.configure(p, M, 1, false, false)
	assert_int(p.amount).is_equal(6)
	assert_float(p.gravity.y).is_equal_approx(200.0, 0.01)
	assert_float(p.initial_velocity_max).is_equal_approx(80.0, 0.01)
	assert_object(p.material).is_null()


# ---- Judgments ------------------------------------------------------------------------------

func test_perfect_restarts_a_lane_emitter_with_ring_and_flash() -> void:
	var fx := _fx()
	fx.on_judged(2, 0, P, 0.0)
	var lane2: Array = [fx.perfect_emitters[4], fx.perfect_emitters[5]]
	assert_int(_emitting(lane2)).is_equal(1)
	assert_int(_emitting(fx.perfect_emitters)).is_equal(1)
	var e := fx.perfect_emitters[4] as CPUParticles2D
	var hit := Trench.hit_point(2)
	assert_vector(e.get_global_transform().origin).is_equal_approx(hit, Vector2(0.5, 0.5))
	assert_int(fx.rings.count_kind(FxLayer.FX_RING_PERFECT)).is_equal(1)
	assert_int(fx.rings.count_kind(FxLayer.FX_FLASH)).is_equal(1)
	# Round robin: the second Perfect in the lane uses the other emitter.
	fx.on_judged(2, 1, P, 0.0)
	assert_int(_emitting(lane2)).is_equal(2)


func test_good_and_miss_entries() -> void:
	var fx := _fx()
	fx.on_judged(0, 0, G, 0.02)
	assert_bool(fx.good_emitters[0].emitting).is_true()
	assert_int(fx.rings.count_kind(FxLayer.FX_RING_GOOD)).is_equal(1)
	assert_int(fx.rings.count_kind(FxLayer.FX_FLASH)).is_equal(0)
	fx.on_judged(3, 1, M, 0.2)
	assert_bool(fx.miss_emitters[3].emitting).is_true()
	assert_int(fx.rings.count_kind(FxLayer.FX_CRACK)).is_equal(1)


func test_low_effects_perfect_has_ring_no_flash_and_miss_no_particles() -> void:
	var fx := _fx()
	Settings.low_effects = true
	fx.apply_effect_settings()
	fx.on_judged(1, 0, P, 0.0)
	assert_int(fx.rings.count_kind(FxLayer.FX_RING_PERFECT)).is_equal(1)
	assert_int(fx.rings.count_kind(FxLayer.FX_FLASH)).is_equal(0)
	fx.on_judged(1, 1, M, 0.2)
	assert_bool(fx.miss_emitters[1].emitting).is_false()
	assert_int(fx.rings.count_kind(FxLayer.FX_CRACK)).is_equal(1)


func test_reduce_motion_no_flash() -> void:
	var fx := _fx()
	Settings.reduce_motion = true
	fx.apply_effect_settings()
	fx.on_judged(1, 0, P, 0.0)
	assert_int(fx.rings.count_kind(FxLayer.FX_RING_PERFECT)).is_equal(1)
	assert_int(fx.rings.count_kind(FxLayer.FX_FLASH)).is_equal(0)
	assert_bool(_emitting(fx.perfect_emitters) == 1).is_true()


func test_ring_timelines() -> void:
	var a := HitBurst.ring_state(FxLayer.FX_RING_PERFECT, 0.0)
	assert_float(float(a["r"])).is_equal_approx(41.0, 0.01)
	assert_float(float(a["w"])).is_equal_approx(6.0, 0.01)
	assert_float(float(a["a"])).is_equal_approx(0.9, 0.01)
	var b := HitBurst.ring_state(FxLayer.FX_RING_PERFECT, 0.26)
	assert_float(float(b["r"])).is_equal_approx(120.0, 0.01)
	assert_float(float(b["w"])).is_equal_approx(1.0, 0.01)
	assert_float(float(b["a"])).is_equal_approx(0.0, 0.01)
	var g0 := HitBurst.ring_state(FxLayer.FX_RING_GOOD, 0.0)
	assert_float(float(g0["a"])).is_equal_approx(0.5, 0.01)
	var g1 := HitBurst.ring_state(FxLayer.FX_RING_GOOD, 0.2)
	assert_float(float(g1["r"])).is_equal_approx(80.0, 0.01)
	assert_float(HitBurst.life(FxLayer.FX_FLASH)).is_equal_approx(0.12, 0.001)
	assert_float(HitBurst.life(FxLayer.FX_CRACK)).is_equal_approx(0.30, 0.001)
	assert_float(HitBurst.flash_radius()).is_equal_approx(30.0, 0.01)


func test_entries_expire_and_pool_is_fixed() -> void:
	var fx := _fx()
	fx.clock_usec = 1000000
	for i in range(100):
		fx.on_judged(i % 4, i, [P, G, M][i % 3], 0.0)
	assert_int(fx.rings.live_count()).is_less_equal(FxLayer.RING_POOL)
	fx.clock_usec = 1000000 + 400000
	fx.rings.expire(fx.now())
	assert_int(fx.rings.live_count()).is_equal(0)


func test_cracks_are_deterministic_three_polylines() -> void:
	var a := FxLayer.crack_polylines(2)
	var b := FxLayer.crack_polylines(2)
	assert_int(a.size()).is_equal(3)
	for i in range(3):
		var pl: PackedVector2Array = a[i]
		assert_int(pl.size()).is_equal(4)
		assert_bool(pl == b[i]).is_true()
		var reach := pl[3].length()
		assert_float(reach).is_between(30.0, 60.0)


# ---- Clipping -------------------------------------------------------------------------------

func test_bursts_and_rings_are_clipped_sparks_are_not() -> void:
	var fx := _fx()
	var clip := fx.burst_clip
	assert_bool(clip.clip_contents).is_true()
	assert_vector(clip.position).is_equal(Vector2(0.0, 840.0))
	assert_vector(clip.size).is_equal(Vector2(1920.0, 240.0))
	assert_float(clip.position.y).is_equal(Trench.HIT_Y - 90.0)
	for e in fx.burst_emitters():
		assert_bool(clip.is_ancestor_of(e)).is_true()
	assert_bool(clip.is_ancestor_of(fx.rings)).is_true()
	for e in fx.rail_emitters + fx.sustain_emitters:
		assert_bool(clip.is_ancestor_of(e)).is_false()
		assert_bool(fx.is_ancestor_of(e)).is_true()


# ---- Shake ----------------------------------------------------------------------------------

func test_shake_moves_board_and_returns() -> void:
	var board := _board()
	var fx := _fx(board)
	fx.clock_usec = 1000000
	assert_bool(fx.request_shake()).is_true()
	fx.clock_usec = 1030000
	fx.advance_shake(fx.now())
	assert_float(board.position.length()).is_greater(0.0)
	assert_float(board.position.length()).is_less_equal(6.0)
	fx.clock_usec = 1100000
	assert_bool(fx.request_shake()).is_false()  # within 150 ms
	fx.clock_usec = 1130000
	fx.advance_shake(fx.now())
	assert_vector(board.position).is_equal(Vector2.ZERO)
	fx.clock_usec = 1200000
	assert_bool(fx.request_shake()).is_true()
	fx.clock_usec = 1400000
	fx.advance_shake(fx.now())
	assert_vector(board.position).is_equal(Vector2.ZERO)


func test_shake_off_under_reduce_motion() -> void:
	var board := _board()
	var fx := _fx(board)
	Settings.reduce_motion = true
	fx.apply_effect_settings()
	fx.clock_usec = 1000000
	assert_bool(fx.request_shake()).is_false()
	fx.on_judged(0, 0, M, 0.2)
	fx.clock_usec = 1030000
	fx.advance_shake(fx.now())
	assert_vector(board.position).is_equal(Vector2.ZERO)


func test_miss_requests_the_shake() -> void:
	var board := _board()
	var fx := _fx(board)
	fx.clock_usec = 1000000
	fx.on_judged(1, 0, M, 0.2)
	assert_bool(fx.shaking()).is_true()
	fx.clock_usec = 1040000
	fx.advance_shake(fx.now())
	assert_float(board.position.length()).is_greater(0.0)
	fx.clock_usec = 1300000
	fx.advance_shake(fx.now())
	assert_vector(board.position).is_equal(Vector2.ZERO)


# ---- Sparks ---------------------------------------------------------------------------------

func test_rail_sparks_follow_tier() -> void:
	var fx := _fx()
	fx.set_tier(1)
	assert_int(_emitting(fx.rail_emitters)).is_equal(0)
	fx.set_tier(2)
	assert_int(_emitting(fx.rail_emitters)).is_equal(0)
	fx.set_tier(3)
	assert_int(_emitting(fx.rail_emitters)).is_equal(2)
	assert_float(float(fx.effect_counts()["rail_rate"])).is_equal(20.0)
	var r := fx.rail_emitters[0] as CPUParticles2D
	assert_float(r.amount / r.lifetime).is_equal_approx(20.0, 0.5)
	fx.set_tier(4)
	assert_float(float(fx.effect_counts()["rail_rate"])).is_equal(40.0)
	assert_float(r.amount / r.lifetime).is_equal_approx(40.0, 0.5)
	fx.set_tier(1)
	assert_int(_emitting(fx.rail_emitters)).is_equal(0)
	fx.set_tier(4)
	Settings.reduce_motion = true
	fx.apply_effect_settings()
	assert_int(_emitting(fx.rail_emitters)).is_equal(0)


func test_sustain_sparks_while_held() -> void:
	var fx := _fx()
	fx.on_sustain_state(1, true)
	assert_bool(fx.sustain_emitters[1].emitting).is_true()
	assert_bool(fx.sustain_emitters[0].emitting).is_false()
	var s := fx.sustain_emitters[1] as CPUParticles2D
	assert_float(s.amount / s.lifetime).is_equal_approx(30.0, 0.5)
	assert_vector(s.get_global_transform().origin).is_equal_approx(Trench.hit_point(1), Vector2(0.5, 0.5))
	fx.on_sustain_state(1, false)
	assert_bool(fx.sustain_emitters[1].emitting).is_false()
	Settings.low_effects = true
	fx.apply_effect_settings()
	fx.on_sustain_state(2, true)
	assert_bool(fx.sustain_emitters[2].emitting).is_false()
	Settings.low_effects = false
	fx.apply_effect_settings()
	assert_bool(fx.sustain_emitters[2].emitting).is_true()  # still held: resumes


func test_live_particle_budget() -> void:
	var fx := _fx()
	assert_int(fx.max_live_particles()).is_less_equal(450)


# ---- Prewarm --------------------------------------------------------------------------------

func test_prewarm_leaves_nothing_visible() -> void:
	var fx := _fx()
	fx.prewarm()
	for e in fx.burst_emitters():
		var p := e as CPUParticles2D
		assert_bool(p.emitting).is_true()
		var o := p.get_global_transform().origin
		assert_bool(fx.burst_clip.get_global_rect().has_point(o)).is_false()
	await get_tree().create_timer(0.6).timeout
	assert_int(_emitting(fx.burst_emitters())).is_equal(0)
	# The next hit emits at the hit point again.
	fx.on_judged(0, 0, P, 0.0)
	var hit := Trench.hit_point(0)
	var any := false
	for i in [0, 1]:
		var p := fx.perfect_emitters[i] as CPUParticles2D
		if p.emitting:
			any = p.get_global_transform().origin.distance_to(hit) < 0.5
	assert_bool(any).is_true()


# ---- Gameplay wiring ------------------------------------------------------------------------

func test_gameplay_inserts_fx_layer_and_connects() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/gameplay.gd")
	assert_bool(src.contains("judge.judged.connect(fx_layer.on_judged)")).is_true()
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = TestCharts.short_chart()
	var gp: Gameplay = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	await get_tree().process_frame
	assert_object(gp.fx_layer).is_not_null()
	assert_object(gp.fx_layer.get_parent()).is_same(gp.board_root)
	assert_int(gp.fx_layer.get_index()).is_greater(gp.highway.get_index())
	assert_int(gp.fx_layer.get_index()).is_less(gp.feedback.get_index())
	assert_bool(gp.judge.judged.is_connected(gp.fx_layer.on_judged)).is_true()
	assert_bool(gp.score.multiplier_changed.is_connected(gp.fx_layer.set_tier)).is_true()
	assert_bool(gp.highway.hold_changed.is_connected(gp.fx_layer.on_sustain_state)).is_true()
	# Highway emits hold_changed where _holding changes.
	var got: Array = []
	gp.highway.hold_changed.connect(func(l: int, h: bool) -> void: got.append([l, h]))
	var idx := -1
	for i in range(gp.chart.notes.size()):
		if float(gp.chart.notes[i]["duration"]) > 0.0:
			idx = i
			break
	if idx >= 0:
		var lane := int(gp.chart.notes[idx]["lane"])
		gp.highway.on_judged(lane, idx, P, 0.0)
		gp.highway.on_sustain_end(lane, true)
		assert_array(got).is_equal([[lane, true], [lane, false]])
