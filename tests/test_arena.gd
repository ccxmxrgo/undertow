extends GdUnitTestSuite
## Arena reactivity logic: energy tiers, counts per effects mode, miss dim, glitch gating.

var _low: bool
var _rm: bool


func before_test() -> void:
	_low = Settings.low_effects
	_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _rm


func test_energy_tiers() -> void:
	var expected := {0: 0.0, 4: 0.0, 5: 0.25, 9: 0.25, 10: 0.5, 49: 0.5, 50: 0.75, 99: 0.75, 100: 1.0, 1000: 1.0}
	for c in expected:
		assert_float(Arena.energy_for(c)).is_equal(expected[c])


func test_counts_per_mode() -> void:
	assert_int(Arena.ring_count(false)).is_equal(14)
	assert_int(Arena.ring_count(true)).is_equal(6)
	assert_int(Arena.snow_count(false)).is_equal(80)
	assert_int(Arena.snow_count(true)).is_equal(24)
	assert_int(Arena.crowd_max(false)).is_equal(26)
	assert_int(Arena.crowd_max(true)).is_equal(13)


func _settled(combo: int) -> Arena:
	var a: Arena = auto_free(Arena.new())
	a.on_combo(combo)
	for i in 120:
		a.advance(0.05)
	return a


func test_miss_drops_energy_to_40_percent() -> void:
	var a := _settled(100)
	assert_float(a.energy()).is_equal_approx(1.0, 0.001)
	a.on_miss()
	assert_float(a.energy()).is_equal_approx(0.4, 0.001)


func test_glitch_on_miss_then_expires() -> void:
	var a := _settled(10)
	a.on_miss()
	assert_bool(a.glitch_active()).is_true()
	a.advance(0.06)
	assert_bool(a.glitch_active()).is_true()
	a.advance(0.07)
	assert_bool(a.glitch_active()).is_false()


func test_glitch_gated_by_low_effects_and_reduce_motion() -> void:
	Settings.low_effects = true
	var a := _settled(10)
	a.on_miss()
	assert_bool(a.glitch_active()).is_false()
	Settings.low_effects = false
	Settings.reduce_motion = true
	var b := _settled(10)
	b.on_miss()
	assert_bool(b.glitch_active()).is_false()


func test_energy_eases_and_is_bounded() -> void:
	var a: Arena = auto_free(Arena.new())
	a.on_combo(100)
	a.advance(0.25)
	assert_float(a.energy()).is_equal_approx(1.0 - exp(-1.0), 0.001)
	for i in 200:
		a.advance(0.1)
	assert_float(a.energy()).is_less_equal(1.0)
	a.on_combo(0)
	a.advance(0.12)
	assert_float(a.energy()).is_equal_approx(exp(-1.0), 0.001)
	for i in 200:
		a.advance(0.1)
	assert_float(a.energy()).is_greater_equal(0.0)


func test_rise_slower_than_fall() -> void:
	var up: Arena = auto_free(Arena.new())
	up.on_combo(100)
	up.advance(0.1)
	var down := _settled(100)
	down.on_combo(0)
	down.advance(0.1)
	assert_float(up.energy()).is_less(1.0 - down.energy())


func test_visible_crowd() -> void:
	var a: Arena = auto_free(Arena.new())
	assert_int(a.visible_crowd()).is_equal(10)
	var full := _settled(100)
	assert_int(full.visible_crowd()).is_equal(26)
	Settings.low_effects = true
	assert_int(full.visible_crowd()).is_equal(13)


func test_fail_zeroes_energy_and_dims() -> void:
	var a := _settled(100)
	a.fail()
	assert_float(a.energy()).is_equal(0.0)
	a.on_combo(100)
	a.advance(1.0)
	assert_float(a.energy()).is_equal(0.0)


# Regression (01.2-06 windowed run): the glow radial used fill_to == fill_from, so the whole
# 1680 px glow quad rendered as flat #123A52 and the screen edges were not near-black.
func test_depth_glow_is_radial_and_fades_to_transparent() -> void:
	var a: Arena = auto_free(Arena.new())
	var img: Image = a._glow_tex.get_image()
	var c := img.get_pixel(128, 128)
	assert_float(c.a).is_greater(0.9)
	assert_float(c.b).is_equal_approx(Color("123A52").b, 0.03)
	assert_float(img.get_pixel(255, 128).a).is_less(0.05)
	assert_float(img.get_pixel(0, 0).a).is_less(0.05)
	var mid := img.get_pixel(128 + 45, 128)
	assert_float(mid.a).is_less(0.95)


func test_vignette_is_clear_in_the_middle_and_dark_in_corners() -> void:
	var a: Arena = auto_free(Arena.new())
	var img: Image = a._vignette_tex.get_image()
	assert_float(img.get_pixel(128, 128).a).is_less(0.01)
	assert_float(img.get_pixel(0, 0).a).is_greater(0.25)


# ---- 02.2-11: living trench (UI-SPEC 7.7, 11) ------------------------------------------

func test_effect_counts_full() -> void:
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var c := a.effect_counts()
	assert_int(c["rings"]).is_equal(14)
	assert_int(c["band_fills"]).is_equal(13)
	assert_int(c["colonies"]).is_equal(36)
	assert_int(c["fish"]).is_equal(26)
	assert_int(c["snow"]).is_equal(80)
	assert_bool(c["creature"]).is_true()
	assert_bool(c["colony_glow"]).is_true()
	assert_bool(c["snow_frozen"]).is_false()
	assert_bool(c["colony_radius_pulse"]).is_true()


func test_effect_counts_low() -> void:
	Settings.low_effects = true
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var c := a.effect_counts()
	assert_int(c["rings"]).is_equal(6)
	assert_int(c["band_fills"]).is_equal(0)
	assert_int(c["colonies"]).is_equal(12)
	assert_int(c["fish"]).is_equal(13)
	assert_int(c["snow"]).is_equal(24)
	assert_bool(c["creature"]).is_false()
	assert_bool(c["colony_glow"]).is_false()


func test_effect_counts_reduce_motion() -> void:
	Settings.reduce_motion = true
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var c := a.effect_counts()
	assert_bool(c["creature"]).is_false()
	assert_bool(c["snow_frozen"]).is_true()
	assert_bool(c["colony_radius_pulse"]).is_false()
	assert_int(c["band_fills"]).is_equal(13)
	assert_int(c["colonies"]).is_equal(36)


func test_colony_alpha_and_radius() -> void:
	var gains := [1.0, 1.1, 1.2, 1.3]
	for tier in range(1, 5):
		for p in [0.0, 0.3, 1.0]:
			assert_float(Arena.colony_alpha(p, tier)).is_equal_approx(0.25 + 0.55 * p * gains[tier - 1], 0.0001)
	assert_float(Arena.colony_alpha(1.0, 9)).is_equal_approx(0.25 + 0.55 * 1.3, 0.0001)
	assert_float(Arena.colony_radius(0.0, false)).is_equal_approx(2.0, 0.0001)
	assert_float(Arena.colony_radius(1.0, false)).is_equal_approx(4.0, 0.0001)
	assert_float(Arena.colony_radius(0.5, false)).is_equal_approx(3.0, 0.0001)
	assert_float(Arena.colony_radius(1.0, true)).is_equal_approx(2.0, 0.0001)


func test_note_path_polygon_is_the_expanded_keep_out() -> void:
	var poly := Arena.note_path_polygon()
	assert_int(poly.size()).is_greater_equal(4)
	assert_bool(Geometry2D.is_point_in_polygon(Trench.VP, poly)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Trench.VP + Vector2(0, -40), poly)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(960, 1040), poly)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(960, 300), poly)).is_false()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(300, 900), poly)).is_false()


func _colonies_outside(low: bool) -> void:
	Settings.low_effects = low
	var poly := Arena.note_path_polygon()
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var most := 0
	for step in 120:
		a.set_scroll(float(step) / 120.0)
		var dots := a.colony_dots()
		most = maxi(most, dots.size())
		for p in dots:
			assert_bool(Geometry2D.is_point_in_polygon(p, poly)).override_failure_message(
				"colony dot %s inside the note path (scroll %d)" % [p, step]).is_false()
	# Filtering must not hide everything: most colonies are visible at some point.
	assert_int(most).is_greater_equal((12 if low else 36) * 3 / 2)


func test_colonies_never_inside_note_path_full() -> void:
	_colonies_outside(false)


func test_colonies_never_inside_note_path_low() -> void:
	_colonies_outside(true)


func test_colony_positions_are_deterministic() -> void:
	var a: Arena = auto_free(Arena.new())
	var b: Arena = auto_free(Arena.new())
	a.set_scroll(0.37)
	b.set_scroll(0.37)
	assert_array(Array(a.colony_dots())).is_equal(Array(b.colony_dots()))
	assert_int(a.colony_ring(5)).is_equal(5 % 14)


func test_creature_schedule_and_path() -> void:
	var poly := Arena.note_path_polygon()
	for key in ["sea_shanty_2", "april", ""]:
		var a: Arena = auto_free(Arena.new())
		a.bind(null, [], key)
		var sched := a.creature_schedule()
		assert_int(sched.size()).is_greater(3)
		for i in sched.size():
			var e: Dictionary = sched[i]
			assert_float(e["speed"]).is_between(60.0, 120.0)
			if i > 0:
				assert_float(e["start"] - sched[i - 1]["start"]).is_between(45.0, 75.0)
		var seen := 0
		var t := 0.0
		while t < 400.0:
			var r := a.creature_rect(t)
			if r.has_area():
				seen += 1
				assert_float(r.position.y).is_greater_equal(120.0)
				assert_float(r.end.y).is_less_equal(340.0)
				var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
					Vector2(r.position.x, r.end.y)])
				assert_array(Geometry2D.intersect_polygons(box, poly)).is_empty()
			t += 0.25
		assert_int(seen).is_greater(0)
	var x: Arena = auto_free(Arena.new())
	var y: Arena = auto_free(Arena.new())
	x.bind(null, [], "same")
	y.bind(null, [], "same")
	assert_array(x.creature_schedule()).is_equal(y.creature_schedule())


func test_tier_four_keeps_fish_energy_high() -> void:
	var a: Arena = auto_free(Arena.new())
	a.set_tier(4)
	assert_float(a.energy()).is_greater_equal(0.75)
	assert_int(a.visible_crowd()).is_greater_equal(10 + int(round(16.0 * 0.75)))
	a.set_tier(1)
	assert_float(a.energy()).is_equal(0.0)
	assert_float(a.tier_gain()).is_equal_approx(1.0, 0.0001)
	a.set_tier(3)
	assert_float(a.tier_gain()).is_equal_approx(1.2, 0.0001)


func test_reduce_motion_freezes_snow_but_keeps_brightness_pulse() -> void:
	Settings.reduce_motion = true
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var before: PackedVector2Array = a._snow_pos.duplicate()
	var pulses := []
	for i in 40:
		a.advance(0.05)
		pulses.append(a.beat_pulse())
	assert_array(Array(a._snow_pos)).is_equal(Array(before))
	assert_float(pulses.max() - pulses.min()).is_greater(0.3)
	assert_float(a.motion_pulse()).is_equal(0.0)


func test_registered_fx_reacts_without_rebuild() -> void:
	var a: Arena = auto_free(Arena.new())
	add_child(a)
	assert_bool(a.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_int(a.effect_counts()["colonies"]).is_equal(36)
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_int(a.effect_counts()["colonies"]).is_equal(12)
	assert_bool(a.glow_layer().visible).is_false()
	Settings.low_effects = false
	Settings.settings_changed.emit()
	assert_int(a.effect_counts()["colonies"]).is_equal(36)
	assert_bool(a.glow_layer().visible).is_true()
	assert_object(a.glow_layer().material).is_same(UiKit.additive_material())
	remove_child(a)


func test_menu_mode_has_no_fish_or_creature() -> void:
	var a: Arena = auto_free(Arena.new())
	a.menu_mode = true
	a.apply_effect_settings()
	var c := a.effect_counts()
	assert_int(c["fish"]).is_equal(0)
	assert_bool(c["creature"]).is_false()
