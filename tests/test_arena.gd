extends GdUnitTestSuite
## Arena reactivity logic: energy tiers, counts per effects mode, miss dim, glitch gating.

var _low: bool
var _rm: bool
var _style: String


func before_test() -> void:
	_low = Settings.low_effects
	_rm = Settings.reduce_motion
	_style = Settings.background_style
	Settings.low_effects = false
	Settings.reduce_motion = false
	# 02.2-27: Calm is the default background; the tests below assert Living behaviour.
	Settings.background_style = Settings.BACKGROUND_LIVING


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _rm
	Settings.background_style = _style


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


# Regression: the wavy rings of large radius overlap, which made the half-annulus band polygons
# self-intersect ("Invalid polygon data, triangulation failed") and spammed errors every frame.
func test_band_polygons_always_triangulate() -> void:
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var drawn := 0
	for step in 200:
		a.set_scroll(float(step) / 200.0)
		var polys := a.band_polygons()
		drawn = maxi(drawn, polys.size())
		for poly in polys:
			assert_bool(Geometry2D.triangulate_polygon(poly).is_empty()).override_failure_message(
				"band polygon failed to triangulate at scroll step %d" % step).is_false()
	assert_int(drawn).is_greater_equal(10)


# Visual review / songs harness: the outer 32 px band stays dark (D-06), also on Song Select.
func test_colonies_keep_clear_of_the_screen_edges() -> void:
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	for step in 120:
		a.set_scroll(float(step) / 120.0)
		for p in a.colony_dots():
			var edge := minf(minf(p.x, Arena.W - p.x), minf(p.y, Arena.H - p.y))
			assert_float(edge).override_failure_message("colony dot %s too close to the edge" % p).is_greater_equal(40.0)


# Visual review: no colony behind the console readouts (streak left, depth right, below y 600).
func test_colonies_stay_out_of_the_console_corners() -> void:
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	for step in 120:
		a.set_scroll(float(step) / 120.0)
		for p in a.colony_dots():
			var in_console := p.y > 600.0 and (p.x < 400.0 or p.x > 1520.0)
			assert_bool(in_console).override_failure_message("colony dot %s in a console corner" % p).is_false()


# ---- 02.2-27: Calm background (gap G2) ---------------------------------------------------

func _calm_arena() -> Arena:
	Settings.background_style = Settings.BACKGROUND_CALM
	var a: Arena = auto_free(Arena.new())
	a.bind(null, [], "sea_shanty_2")  # empty tempo map = 120 BPM
	a.apply_effect_settings()
	return a


## First scheduled creature crossing midpoint (song time) for this arena's key.
func _creature_mid(a: Arena) -> float:
	var t := 0.0
	while t < 400.0:
		if a.creature_rect(t).has_area():
			return t + 2.0
		t += 0.25
	return -1.0


func test_calm_walls_and_glow_radius_are_still() -> void:
	var a := _calm_arena()
	assert_str(a.background_style()).is_equal(Arena.STYLE_CALM)
	var r0 := a.ring_radii()
	var s0 := a.scroll_phase()
	var g0 := a.depth_glow_radius()
	for i in 240:  # 4 s at 60 fps, 120 BPM
		a.advance(1.0 / 60.0)
		assert_array(Array(a.ring_radii())).is_equal(Array(r0))
		assert_float(a.scroll_phase()).is_equal(s0)
		assert_float(a.depth_glow_radius()).is_equal(g0)


func test_living_walls_move_for_contrast() -> void:
	Settings.background_style = Settings.BACKGROUND_LIVING
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var r0 := a.ring_radii()
	a.advance(0.5)
	assert_array(Array(a.ring_radii())).is_not_equal(Array(r0))


func test_calm_has_no_creature_or_miss_glitch() -> void:
	var a := _calm_arena()
	var mid := _creature_mid(a)
	assert_float(mid).is_greater(0.0)
	a._update_creature(mid)
	assert_bool(a.creature_active()).is_false()
	a.on_miss()
	assert_bool(a.glitch_active()).is_false()
	var c := a.effect_counts()
	assert_bool(c["creature"]).is_false()
	assert_bool(c["glitch"]).is_false()
	assert_bool(c["wall_scroll"]).is_false()
	assert_bool(c["wall_breathe"]).is_false()
	assert_str(c["style"]).is_equal("calm")


func test_calm_snow_fewer_slower_and_straight() -> void:
	var a := _calm_arena()
	assert_int(a.effect_counts()["snow"]).is_equal(Arena.SNOW_LOW)
	Settings.background_style = Settings.BACKGROUND_LIVING
	var b: Arena = auto_free(Arena.new())
	b.apply_effect_settings()
	var pa: PackedVector2Array = a._snow_pos.duplicate()
	var pb: PackedVector2Array = b._snow_pos.duplicate()
	a.advance(0.1)
	b.advance(0.1)
	var fast_a := 0.0
	var fast_b := 0.0
	for i in Arena.SNOW_LOW:
		var da: Vector2 = a._snow_pos[i] - pa[i]
		var db: Vector2 = b._snow_pos[i] - pb[i]
		assert_float(da.x).is_equal(0.0)  # no sideways wobble
		fast_a = maxf(fast_a, da.y)
		fast_b = maxf(fast_b, db.y)
	assert_float(fast_a).is_greater(0.0)
	assert_float(fast_a).is_less_equal(0.4 * fast_b + 0.0001)


func test_calm_fish_fewer_slower_and_no_pulse() -> void:
	var a := _calm_arena()
	assert_int(a.effect_counts()["fish"]).is_less_equal(Arena.CROWD_LOW)
	a.set_tier(4)
	assert_int(a.visible_crowd()).is_less_equal(Arena.CROWD_LOW)
	Settings.background_style = Settings.BACKGROUND_LIVING
	var b: Arena = auto_free(Arena.new())
	b.apply_effect_settings()
	Settings.background_style = Settings.BACKGROUND_CALM
	for i in [1, 2, 4, 5]:
		var a0 := a._fish_pos(i)
		var b0 := b._fish_pos(i)
		a._t += 1.0
		b._t += 1.0
		var da := absf(a._fish_pos(i).x - a0.x)
		var db := absf(b._fish_pos(i).x - b0.x)
		a._t -= 1.0
		b._t -= 1.0
		assert_float(da).is_less_equal(0.25 * db + 0.0001)
	for i in 30:
		a.advance(1.0 / 30.0)
		assert_float(a.fish_scale_pulse()).is_equal(1.0)


func test_calm_colonies_and_glow_breathe_gently() -> void:
	var a := _calm_arena()
	a.set_tier(4)
	var lo := 1.0
	var hi := 0.0
	var glo := 1.0
	var ghi := 0.0
	var prev := a.depth_glow_alpha()
	var max_step := 0.0
	for i in 240:
		a.advance(1.0 / 60.0)
		var ca := a.colony_alpha_now()
		lo = minf(lo, ca)
		hi = maxf(hi, ca)
		var ga := a.depth_glow_alpha()
		glo = minf(glo, ga)
		ghi = maxf(ghi, ga)
		max_step = maxf(max_step, absf(ga - prev))
		prev = ga
	assert_float(lo).is_greater_equal(0.35)
	assert_float(hi).is_less_equal(0.50)
	assert_float(hi - lo).is_greater(0.02)  # it does breathe
	assert_float(ghi - glo).is_less_equal(0.08)
	assert_float(ghi - glo).is_greater(0.0)
	assert_float(max_step).is_less_equal(0.02)
	assert_bool(a.effect_counts()["colony_radius_pulse"]).is_false()


func test_living_colony_alpha_spans_the_spec_range() -> void:
	Settings.background_style = Settings.BACKGROUND_LIVING
	var a: Arena = auto_free(Arena.new())
	a.apply_effect_settings()
	var lo := 1.0
	var hi := 0.0
	for i in 120:
		a.advance(1.0 / 60.0)
		lo = minf(lo, a.colony_alpha_now())
		hi = maxf(hi, a.colony_alpha_now())
	assert_float(lo).is_less_equal(0.26)
	assert_float(hi).is_greater_equal(0.75)


func test_calm_with_low_effects_uses_low_counts() -> void:
	Settings.low_effects = true
	var a := _calm_arena()
	var c := a.effect_counts()
	assert_int(c["rings"]).is_equal(6)
	assert_int(c["colonies"]).is_equal(12)
	assert_bool(c["colony_glow"]).is_false()
	assert_int(c["snow"]).is_equal(Arena.SNOW_LOW)
	assert_int(c["fish"]).is_less_equal(Arena.CROWD_LOW)
	assert_bool(a.glow_layer().visible).is_false()


func test_calm_with_reduce_motion_freezes_snow_and_fish_but_breathes() -> void:
	Settings.reduce_motion = true
	var a := _calm_arena()
	var snow: PackedVector2Array = a._snow_pos.duplicate()
	var f0 := a._fish_pos(3)
	var lo := 1.0
	var hi := 0.0
	for i in 120:
		a.advance(1.0 / 60.0)
		lo = minf(lo, a.colony_alpha_now())
		hi = maxf(hi, a.colony_alpha_now())
	assert_array(Array(a._snow_pos)).is_equal(Array(snow))
	assert_that(a._fish_pos(3)).is_equal(f0)
	assert_float(hi - lo).is_greater(0.0)
	assert_bool(a.effect_counts()["snow_frozen"]).is_true()


func test_style_switches_live_through_the_effect_contract() -> void:
	Settings.background_style = Settings.BACKGROUND_LIVING
	var a: Arena = auto_free(Arena.new())
	add_child(a)
	assert_str(a.effect_counts()["style"]).is_equal("living")
	assert_bool(a.effect_counts()["creature"]).is_true()
	Settings.background_style = Settings.BACKGROUND_CALM
	Settings.settings_changed.emit()
	assert_str(a.effect_counts()["style"]).is_equal("calm")
	assert_bool(a.effect_counts()["creature"]).is_false()
	var r0 := a.ring_radii()
	a.advance(0.5)
	assert_array(Array(a.ring_radii())).is_equal(Array(r0))
	Settings.background_style = Settings.BACKGROUND_LIVING
	Settings.settings_changed.emit()
	assert_str(a.effect_counts()["style"]).is_equal("living")
	remove_child(a)


func test_menu_mode_ignores_background_style() -> void:
	var out := []
	for style in [Settings.BACKGROUND_LIVING, Settings.BACKGROUND_CALM]:
		Settings.background_style = style
		var a: Arena = auto_free(Arena.new())
		a.menu_mode = true
		a.apply_effect_settings()
		var radii := []
		var alphas := []
		for i in 60:
			a.advance(1.0 / 30.0)
			radii.append(Array(a.ring_radii()))
			alphas.append(a.colony_alpha_now())
		var c := a.effect_counts()
		c.erase("style")
		out.append([radii, alphas, c, Array(a._snow_pos), a.depth_glow_radius(), a.depth_glow_alpha()])
	assert_array(out[0]).is_equal(out[1])
