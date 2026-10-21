extends GdUnitTestSuite
## CreakDirector (05-02, D-04): seeded, song-time driven hull creaks.


func test_no_damage_creak_on_heal_or_high_hull() -> void:
	var d := CreakDirector.new(7, 4)
	assert_dict(d.on_hull_changed(25.0, 0.0, 1.0)).is_empty()
	assert_dict(d.on_hull_changed(25.0, 5.0, 2.0)).is_empty()
	assert_dict(d.on_hull_changed(70.0, -5.0, 3.0)).is_empty()
	assert_dict(d.on_hull_changed(85.0, -5.0, 4.0)).is_empty()


func test_damage_creak_at_low_hull() -> void:
	var d := CreakDirector.new(7, 4)
	var t := 0.0
	for i in 50:
		var c := d.on_hull_changed(25.0, -5.0, t)
		assert_dict(c).is_not_empty()
		assert_int(int(c["variant"])).is_between(0, 3)
		assert_float(float(c["pitch"])).is_between(0.85, 1.15)
		assert_float(float(c["db"])).is_equal_approx(HullAudioCurve.creak_db_for_hull(25.0) + 3.0, 1e-6)
		t += 1.0


func test_variant_never_repeats_immediately() -> void:
	var d := CreakDirector.new(7, 4)
	var last := -1
	for i in 100:
		var c := d.on_hull_changed(10.0, -5.0, float(i))
		assert_int(int(c["variant"])).is_not_equal(last)
		last = int(c["variant"])


func test_single_variant() -> void:
	var d := CreakDirector.new(7, 1)
	for i in 10:
		assert_int(int(d.on_hull_changed(10.0, -5.0, float(i))["variant"])).is_equal(0)


func test_damage_cooldown() -> void:
	var d := CreakDirector.new(7, 4)
	assert_dict(d.on_hull_changed(25.0, -5.0, 10.0)).is_not_empty()
	assert_dict(d.on_hull_changed(25.0, -5.0, 10.5)).is_empty()
	assert_dict(d.on_hull_changed(25.0, -5.0, 10.79)).is_empty()
	assert_dict(d.on_hull_changed(25.0, -5.0, 10.8)).is_not_empty()


func test_damage_chance_partial() -> void:
	var d := CreakDirector.new(7, 4)
	var n := 0
	for i in 400:
		if not d.on_hull_changed(50.0, -5.0, float(i)).is_empty():
			n += 1
	assert_int(n).is_between(140, 260)  # chance 0.5


func test_ambient_never_at_high_hull() -> void:
	var d := CreakDirector.new(7, 4)
	var t := 0.0
	while t < 120.0:
		assert_dict(d.tick(80.0, t)).is_empty()
		assert_dict(d.tick(60.0, t)).is_empty()
		t += 1.0 / 60.0


func test_ambient_rate_and_gaps() -> void:
	var d := CreakDirector.new(7, 4)
	var times: Array = []
	var i := 0
	while i < 120 * 60:
		var t := float(i) / 60.0
		var c := d.tick(20.0, t)
		if not c.is_empty():
			times.append(t)
			assert_float(float(c["db"])).is_equal_approx(HullAudioCurve.creak_db_for_hull(20.0), 1e-6)
			assert_float(float(c["pitch"])).is_between(0.85, 1.15)
		i += 1
	var expected := 120.0 / HullAudioCurve.creak_interval_for_hull(20.0)
	assert_float(float(times.size())).is_between(expected * 0.6, expected * 1.4)
	for k in range(1, times.size()):
		assert_float(float(times[k]) - float(times[k - 1])).is_greater_equal(CreakDirector.COOLDOWN_SEC)


func test_ambient_and_damage_share_cooldown() -> void:
	var d := CreakDirector.new(7, 4)
	var times: Array = []
	var i := 0
	while i < 60 * 60:
		var t := float(i) / 60.0
		var c := d.tick(5.0, t)
		if c.is_empty() and i % 13 == 0:
			c = d.on_hull_changed(5.0, -2.0, t)
		if not c.is_empty():
			times.append(t)
		i += 1
	assert_int(times.size()).is_greater(10)
	for k in range(1, times.size()):
		assert_float(float(times[k]) - float(times[k - 1])).is_greater_equal(CreakDirector.COOLDOWN_SEC - 1e-9)


func _sequence(rng_seed: int) -> Array:
	var d := CreakDirector.new(rng_seed, 4)
	var out: Array = []
	var i := 0
	while i < 60 * 60:
		var t := float(i) / 60.0
		var hull := 60.0 - float(i) / 80.0
		if i % 97 == 0:
			out.append(d.on_hull_changed(hull, -3.0, t))
		out.append(d.tick(hull, t))
		i += 1
	return out


func test_deterministic_for_seed() -> void:
	var a := _sequence(7)
	var b := _sequence(7)
	assert_int(a.size()).is_equal(b.size())
	var non_empty := 0
	for k in a.size():
		assert_dict(a[k]).is_equal(b[k])
		if not (a[k] as Dictionary).is_empty():
			non_empty += 1
	assert_int(non_empty).is_greater(5)
	assert_bool(_sequence(8) == a).is_false()


func test_reset_restores_initial_state() -> void:
	var d := CreakDirector.new(7, 4)
	var first := d.on_hull_changed(20.0, -5.0, 1.0)
	d.tick(20.0, 5.0)
	d.reset()
	assert_dict(d.on_hull_changed(20.0, -5.0, 1.0)).is_equal(first)


func test_non_finite_inputs() -> void:
	var d := CreakDirector.new(7, 4)
	assert_dict(d.tick(20.0, NAN)).is_empty()
	assert_dict(d.tick(NAN, 1.0)).is_empty()
	assert_dict(d.on_hull_changed(20.0, -5.0, NAN)).is_empty()
	assert_float(CreakDirector.COOLDOWN_SEC).is_equal(0.8)
