extends GdUnitTestSuite
## Trench projection: linear-in-time depth, hit-point invariant, reference points (IMM-02/IMM-05).


func _near(v: Vector2, x: float, y: float, tol: float) -> void:
	assert_float(v.x).is_equal_approx(x, tol)
	assert_float(v.y).is_equal_approx(y, tol)


func test_depth_is_linear_in_time() -> void:
	var a := 1.5
	var t0 := 3.0
	var h := 0.2
	var d0 := Trench.depth_for(t0, 0.0, a)
	var d1 := Trench.depth_for(t0 + h, 0.0, a)
	var d2 := Trench.depth_for(t0 + 2.0 * h, 0.0, a)
	assert_float(d2 - d1).is_equal_approx(d1 - d0, 1e-9)
	assert_float(Trench.depth_for(100.0, 0.0, 1.5)).is_greater(1.0)
	assert_float(Trench.depth_for(-100.0, 0.0, 1.5)).is_less(-1.0)


func test_note_centre_on_hit_point_at_judge_time() -> void:
	for offset in [0.0, 0.037, -0.05]:
		for lane in range(4):
			var note_time := 12.345
			var vt: float = note_time  # note.time == song_time + visual_offset
			var st: float = vt - offset
			assert_float(st + offset).is_equal_approx(note_time, 1e-9)
			var d := Trench.depth_for(note_time, vt, Trench.approach_for(1.0))
			assert_float(d).is_equal(0.0)
			var p: Vector2 = Trench.project(Trench.lane_f(lane), d)["pos"]
			var hp := Trench.hit_point(lane)
			assert_float(p.x).is_equal_approx(hp.x, 0.001)
			assert_float(p.y).is_equal_approx(hp.y, 0.001)


func test_hit_point_reference_values() -> void:
	_near(Trench.hit_point(0), 645.0, 879.0, 1.0)
	_near(Trench.hit_point(1), 855.0, 951.0, 1.0)
	_near(Trench.hit_point(2), 1065.0, 951.0, 1.0)
	_near(Trench.hit_point(3), 1275.0, 879.0, 1.0)


func test_sample_points_and_far_convergence() -> void:
	_near(Trench.point(1.5, 0.5), 1006.0, 496.0, 2.0)
	_near(Trench.point(1.5, 0.2), 1068.0, 636.0, 2.0)
	for lane in range(4):
		var p := Trench.point(Trench.lane_f(lane), 1.0)
		assert_float(p.x - Trench.VP.x).is_equal_approx(Trench.lane_f(lane) * 14.1, 0.2)  # cables converge on VP (outer lanes 21 px)
		assert_float(p.y).is_equal_approx(396.0, 1.0)
	_near(Trench.point(-2.6, 0.0), 414.0, 717.0, 1.0)
	_near(Trench.point(2.6, 0.0), 1506.0, 717.0, 1.0)


func test_monotonic_in_depth() -> void:
	for lane in range(4):
		var f := Trench.lane_f(lane)
		var prev_y := INF
		var prev_s := INF
		for i in range(0, 101):
			var d := float(i) / 100.0
			var pr := Trench.project(f, d)
			var y: float = (pr["pos"] as Vector2).y
			assert_float(y).is_less_equal(prev_y + 1e-6)
			assert_float(pr["s"]).is_less(prev_s)
			prev_y = y
			prev_s = pr["s"]


func test_project_finite_everywhere() -> void:
	var ds: Array[float] = [-5.0, Trench.D_MIN, -0.1, 0.0, 0.3, 1.0, 5.0]
	for i in range(0, 41):
		ds.append(Trench.D_MIN + (1.0 - Trench.D_MIN) * float(i) / 40.0)
	for d in ds:
		for lane in range(4):
			var pr := Trench.project(Trench.lane_f(lane), d)
			var p: Vector2 = pr["pos"]
			assert_bool(is_finite(p.x) and is_finite(p.y)).is_true()
			assert_bool(is_finite(pr["s"]) and is_finite(pr["n"])).is_true()


func test_approach_for() -> void:
	assert_float(Trench.approach_for(0.5)).is_equal_approx(3.0, 1e-9)
	assert_float(Trench.approach_for(1.0)).is_equal_approx(1.5, 1e-9)
	assert_float(Trench.approach_for(3.0)).is_equal_approx(0.5, 1e-9)
	for sp in [0.5, 1.0, 2.0, 3.0]:
		assert_float(Trench.approach_for(sp) * sp).is_equal_approx(1.5, 1e-9)
	assert_bool(is_finite(Trench.approach_for(0.0))).is_true()
	assert_bool(is_finite(Trench.approach_for(-2.0))).is_true()
	assert_float(Trench.approach_for(0.0)).is_greater(0.0)


func test_ring_points() -> void:
	var r := Trench.ring_points()
	assert_int(r.size()).is_equal(41)
	_near(r[0], 519.0, 801.0, 1.0)
	_near(r[40], 1401.0, 801.0, 1.0)


func test_note_radius() -> void:
	assert_float(Trench.note_radius(1.0)).is_equal_approx(41.0, 1e-9)
