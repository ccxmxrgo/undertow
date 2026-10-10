extends GdUnitTestSuite
## VIS-01 / D-21: the Oxanium display face renders at weight 700 via the integer
## OpenType tag, has tabular digits, and falls back to Share Tech Mono.


func _wght_tag() -> int:
	return TextServerManager.get_primary_interface().name_to_tag("wght")


func test_display_font_uses_integer_wght_tag_700() -> void:
	var f := Palette.display_font() as FontVariation
	assert_object(f).is_not_null()
	var vo: Dictionary = f.variation_opentype
	assert_bool(vo.has(_wght_tag())).is_true()
	assert_int(int(vo[_wght_tag()])).is_equal(700)
	assert_bool(vo.has("wght")).is_false()


func test_display_font_renders_heavier_than_axis_default() -> void:
	var f := Palette.display_font() as FontVariation
	var plain := FontVariation.new()
	plain.base_font = f.base_font
	var bold_w := f.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var default_w := plain.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	assert_float(bold_w).is_greater(default_w)


func test_display_font_digits_are_tabular() -> void:
	var f := Palette.display_font()
	var first := f.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
	assert_float(first).is_greater(0.0)
	for d in range(1, 10):
		var w := f.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
		assert_float(w).is_equal_approx(first, 0.01)


func test_display_font_falls_back_to_share_tech_mono() -> void:
	var f := Palette.display_font()
	assert_bool(f.fallbacks.has(Palette.font())).is_true()
	assert_bool(f.base_font != Palette.font()).is_true()
