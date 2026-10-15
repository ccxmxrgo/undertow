extends GdUnitTestSuite
## RESEARCH Pitfall 4 regression guard (D-28): VersusJudge/VersusHull extend the pinned
## InputJudge/HullScore. A signal connection made inside the pinned connect_judge must dispatch
## to the subclass override, super.<method>() must run the parent body, and parent underscore
## methods must be callable from the subclass. If a Godot bump changes any of this, Phase 3
## payload logic silently stops running, so these tests fail loudly instead.

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD


class _Probe:
	extends VersusHull
	var calls := 0

	func _init(cfg: JudgeConfig) -> void:
		super(cfg)

	func on_judged(lane: int, idx: int, judgment: int, err: float) -> void:
		calls += 1
		super.on_judged(lane, idx, judgment, err)


func _one_note() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 1.0)
	c.add_note(1, 2.0)
	c.finalize()
	return c


func test_parent_connection_dispatches_to_subclass_override() -> void:
	var chart := _one_note()
	var judge := VersusJudge.new(chart, JudgeConfig.new())
	var hull := _Probe.new(JudgeConfig.new())
	hull.connect_judge(judge)
	judge.press(0, 1.0)
	assert_int(hull.calls).is_equal(1)
	# super.on_judged still ran the pinned body
	assert_int(hull.perfect_count).is_equal(1)
	assert_int(hull.combo).is_equal(1)
	assert_int(hull.score).is_equal(100)


func test_versus_hull_override_runs_through_signal() -> void:
	# The overclock top-up only exists in VersusHull.on_judged: seeing it through the judge's
	# signal proves the override (not the parent) is the connected callable.
	var chart := _one_note()
	var judge := VersusJudge.new(chart, JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	hull.connect_judge(judge)
	hull.overclock_until = 100.0
	hull.now = 1.07
	judge.press(0, 1.07)  # GOOD (70 ms late)
	assert_int(hull.good_count).is_equal(1)
	assert_int(hull.score).is_equal(100)


func test_parent_private_methods_callable_from_subclass() -> void:
	var hull := VersusHull.new(JudgeConfig.new())
	hull.on_judged(0, 0, InputJudge.Judgment.MISS, 0.0)
	assert_float(hull.hull).is_equal(92.0)
	hull.heal(5.0)  # uses the parent's _set_hull
	assert_float(hull.hull).is_equal(97.0)


func test_subclass_is_still_the_pinned_type() -> void:
	var chart := _one_note()
	var judge := VersusJudge.new(chart, JudgeConfig.new())
	var hull := VersusHull.new(JudgeConfig.new())
	assert_bool(judge is InputJudge).is_true()
	assert_bool(hull is HullScore).is_true()
	# Autoplay is typed InputJudge and must accept the subclass unchanged
	var ap := Autoplay.new(chart, judge)
	hull.connect_judge(judge)
	ap.update(5.0)
	judge.tick(5.0)
	assert_int(hull.perfect_count).is_equal(2)


func test_sources_extend_never_edit() -> void:
	var vj := FileAccess.get_file_as_string("res://src/core/versus_judge.gd")
	var vh := FileAccess.get_file_as_string("res://src/core/versus_hull.gd")
	assert_bool(vj.contains("extends InputJudge")).is_true()
	assert_bool(vh.contains("extends HullScore")).is_true()
	assert_bool(vj.contains("super.press")).is_true()
	assert_bool(vh.contains("super.on_judged")).is_true()
