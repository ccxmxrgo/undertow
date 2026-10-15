extends GdUnitTestSuite
## Phase 3 code review (03-REVIEW.md) view-level regressions: WR-04 .. WR-12 and the cheap info
## items. Rules-engine fixes live next to their own suites (bounty, sub rig, controller).


func _crossed_highway() -> Highway:
	var hw: Highway = auto_free(Highway.new())
	# Lanes 1 and 2 settled in each other's column (Crossed Wires).
	hw._lane_x = PackedFloat32Array([-1.5, 0.5, -0.5, 1.5])
	return hw


# ---- WR-04 (V-3): bursts, sparks and popups follow the judged lane's drawn column ----------

func test_fx_layer_bursts_use_the_swapped_receptor() -> void:
	var hw := _crossed_highway()
	var fx: FxLayer = auto_free(FxLayer.new())
	fx.bind(hw, null)
	assert_vector(fx.lane_point(1)).is_equal(hw.receptor_center(1))
	assert_vector(fx.lane_point(1)).is_equal(Trench.hit_point(2))
	assert_vector(fx.lane_point(0)).is_equal(Trench.hit_point(0))
	fx.on_judged(1, 0, InputJudge.Judgment.GOOD, 0.0)
	assert_vector(fx.good_emitters[1].position).is_equal(Trench.hit_point(2))


func test_fx_layer_without_highway_uses_static_column() -> void:
	var fx: FxLayer = auto_free(FxLayer.new())
	assert_vector(fx.lane_point(1)).is_equal(Trench.hit_point(1))


func test_feedback_popup_sits_over_the_swapped_receptor() -> void:
	var hw := _crossed_highway()
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	fb.highway = hw
	fb.on_judged(2, 0, InputJudge.Judgment.PERFECT, 0.0)
	assert_float(float(fb.popup(0)["x"])).is_equal_approx(Trench.hit_point(1).x, 1e-3)
	fb.on_ghost_hit(1)
	assert_float(float(fb.popup(1)["x"])).is_equal_approx(Trench.hit_point(2).x, 1e-3)
