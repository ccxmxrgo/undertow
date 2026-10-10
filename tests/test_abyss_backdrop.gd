extends GdUnitTestSuite
## AbyssBackdrop (02.2 plan 06, UI-SPEC 5 / 6 / 8 / 11): the three variants, Low effects
## counts (menu particles 160 -> 40), Reduce motion freezing and the effect contract.

const TITLE_FULL := {"snow": 120, "specks": 40, "shafts": 5, "kelp": 9, "sub": 1}
const TITLE_LOW := {"snow": 30, "specks": 10, "shafts": 3, "kelp": 5, "sub": 1}

var _low := false
var _reduce := false


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce


func _backdrop(variant: String = "title") -> AbyssBackdrop:
	var b := AbyssBackdrop.new()
	b.variant = variant
	add_child(b)
	auto_free(b)
	return b


func _particles(c: Dictionary) -> int:
	return int(c.get("snow", 0)) + int(c.get("specks", 0))


func test_title_full_counts() -> void:
	var b := _backdrop()
	assert_dict(b.effect_counts()).is_equal(TITLE_FULL)
	assert_int(_particles(b.effect_counts())).is_equal(160)


func test_title_low_counts_drop_particles_75_percent() -> void:
	Settings.low_effects = true
	var b := _backdrop()
	assert_dict(b.effect_counts()).is_equal(TITLE_LOW)
	assert_int(_particles(b.effect_counts())).is_equal(40)


func test_settings_changed_updates_counts_on_the_same_node() -> void:
	var b := _backdrop()
	var id := b.get_instance_id()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(b.effect_counts()).is_equal(TITLE_LOW)
	Settings.low_effects = false
	Settings.settings_changed.emit()
	assert_dict(b.effect_counts()).is_equal(TITLE_FULL)
	assert_int(b.get_instance_id()).is_equal(id)
	assert_bool(is_instance_valid(b)).is_true()


func test_reduce_motion_freezes_parallax_sub_and_snow() -> void:
	Settings.reduce_motion = true
	var b := _backdrop()
	b.advance(0.25)
	var ridge := b.ridge_offset()
	var rocks := b.rocks_offset()
	var kelp := b.kelp_phase()
	var drift := b.kelp_drift()
	var sub := b.sub_transform()
	var shafts := b.shaft_sway()
	var snow: Array[Vector2] = []
	for i in 10:
		snow.append(b.snow_position(i))
	for i in 60:
		b._process(1.0 / 60.0)
	assert_float(b.ridge_offset()).is_equal(ridge)
	assert_float(b.rocks_offset()).is_equal(rocks)
	assert_float(b.kelp_phase()).is_equal(kelp)
	assert_float(b.kelp_drift()).is_equal(drift)
	assert_bool(b.sub_transform().is_equal_approx(sub)).is_true()
	assert_float(b.shaft_sway()).is_equal(shafts)
	for i in 10:
		assert_vector(b.snow_position(i)).is_equal(snow[i])


func test_reduce_motion_keeps_speck_pulse() -> void:
	Settings.reduce_motion = true
	var b := _backdrop()
	var seen := {}
	for i in 40:
		b.advance(0.05)
		seen[snappedf(b.speck_alpha(0), 0.01)] = true
	assert_int(seen.size()).is_greater(3)
	for i in 40:
		b.advance(0.05)
		var a := b.speck_alpha(0)
		assert_float(a).is_between(0.3, 0.85)


func test_full_motion_moves_layers() -> void:
	var b := _backdrop()
	var ridge := b.ridge_offset()
	var sub := b.sub_transform()
	var snow := b.snow_position(0)
	var kelp := b.kelp_phase()
	b.advance(1.0)
	assert_float(b.ridge_offset()).is_not_equal(ridge)
	assert_bool(b.sub_transform().is_equal_approx(sub)).is_false()
	assert_vector(b.snow_position(0)).is_not_equal(snow)
	assert_float(b.kelp_phase()).is_not_equal(kelp)


func test_low_effects_static_ridge_and_shafts_but_kelp_sways_and_sub_bobs() -> void:
	Settings.low_effects = true
	var b := _backdrop()
	var ridge := b.ridge_offset()
	var rocks := b.rocks_offset()
	var shafts := b.shaft_sway()
	var kelp := b.kelp_phase()
	var sub := b.sub_transform()
	b.advance(1.0)
	assert_float(b.ridge_offset()).is_equal(ridge)
	assert_float(b.rocks_offset()).is_equal(rocks)
	assert_float(b.shaft_sway()).is_equal(shafts)
	assert_float(b.kelp_phase()).is_not_equal(kelp)
	assert_bool(b.sub_transform().is_equal_approx(sub)).is_false()
	assert_bool(b.searchlight_glow()).is_false()


func test_table_variant_has_no_sub_and_dims_layers() -> void:
	var b := _backdrop("table")
	assert_int(int(b.effect_counts()["sub"])).is_equal(0)
	assert_int(int(b.effect_counts()["snow"])).is_equal(120)
	assert_float(b.layer_alpha()).is_equal_approx(0.6, 0.0001)
	var t := _backdrop("title")
	assert_float(t.layer_alpha()).is_equal_approx(1.0, 0.0001)


func test_calm_variant_counts() -> void:
	var b := _backdrop("calm")
	assert_dict(b.effect_counts()).is_equal({"snow": 40})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	assert_dict(b.effect_counts()).is_equal({"snow": 12})


func test_fx_group_mouse_ignore_and_pulse_default() -> void:
	var b := _backdrop()
	assert_bool(b.is_in_group(UiKit.FX_GROUP)).is_true()
	assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for c in b.get_children():
		assert_int((c as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(b.pulse_hz).is_equal(0.5)


func test_layer_children_draw_order() -> void:
	var b := _backdrop()
	var g := b.get_node("Gradient") as CanvasItem
	var s := b.get_node("Shafts") as CanvasItem
	var l := b.get_node("Searchlight") as CanvasItem
	assert_bool(g.show_behind_parent).is_true()
	assert_bool(s.show_behind_parent).is_true()
	assert_bool(l.show_behind_parent).is_false()
	assert_int(g.get_index()).is_less(s.get_index())
	assert_object(s.material).is_same(UiKit.additive_material())


func test_draws_every_variant_and_mode_without_error() -> void:
	for v in ["title", "table", "calm"]:
		for low in [false, true]:
			for rm in [false, true]:
				Settings.low_effects = low
				Settings.reduce_motion = rm
				var b := _backdrop(v)
				b.advance(0.5)
				b.queue_redraw()
				await get_tree().process_frame
				assert_bool(is_instance_valid(b)).is_true()
