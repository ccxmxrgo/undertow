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
