extends GdUnitTestSuite
## VIS-10 / AV-01 / VIS-03 readability guardrail: every UI-SPEC section 13 contrast pair
## (C1..C19) computed from Palette tokens, composited with Wcag.over exactly as listed.
## Only the strip-hex sanity check names hex values (to prove the compositing matches the
## UI-SPEC numbers); every pair below reads Palette tokens.

const LANES := 4


## Highway surface: HIGHWAY_BASE at 90% over the arena VP glow (#050F1C).
func _surface() -> Color:
	return Wcag.over(Palette.HIGHWAY_BASE, Palette.HIGHWAY_ALPHA, Palette.VP_GLOW)


## Lane strip at the x4 tier tint (14%) over the highway surface.
func _strip(lane: int) -> Color:
	return Wcag.over(Palette.lane_color(lane), Palette.TIER_TINT[3], _surface())


## Glass panel: ABYSS_700 at 82% over ABYSS_900 (#091628).
func _panel() -> Color:
	return Wcag.over(Palette.ABYSS_700, Palette.PANEL_ALPHA, Palette.ABYSS_900)


func _keyline() -> Color:
	return Color(Palette.KEYLINE, 1.0)


func _check(label: String, fg: Color, bg: Color, minimum: float) -> void:
	var r := Wcag.ratio(fg, bg)
	assert_float(r).override_failure_message(
		"%s: contrast %.2f < %.1f (fg #%s on bg #%s)" % [label, r, minimum, fg.to_html(false), bg.to_html(false)]
	).is_greater_equal(minimum)


func _near(label: String, got: Color, want: Color) -> void:
	var tol := 2.0 / 255.0 + 0.0001
	var ok := absf(got.r - want.r) <= tol and absf(got.g - want.g) <= tol and absf(got.b - want.b) <= tol
	assert_bool(ok).override_failure_message(
		"%s: composite #%s, expected #%s (+/-2 per channel)" % [label, got.to_html(false), want.to_html(false)]
	).is_true()


# ---- Wcag helper ----

func test_wcag_luminance_and_ratio_extremes() -> void:
	assert_float(Wcag.luminance(Color(1, 1, 1))).is_equal_approx(1.0, 0.0001)
	assert_float(Wcag.luminance(Color(0, 0, 0))).is_equal_approx(0.0, 0.0001)
	assert_float(Wcag.ratio(Color(1, 1, 1), Color(0, 0, 0))).is_equal_approx(21.0, 0.01)
	assert_float(Wcag.ratio(Color(0, 0, 0), Color(1, 1, 1))).is_equal_approx(21.0, 0.01)


func test_wcag_over_composites_in_srgb() -> void:
	var c := Wcag.over(Color(1, 1, 1), 0.5, Color(0, 0, 0))
	assert_float(c.r).is_equal_approx(0.5, 0.0001)
	assert_float(c.a).is_equal_approx(1.0, 0.0001)
	_near("panel composite", _panel(), Color("091628"))
	_near("highway surface", _surface(), Color("050F1C"))


func test_strip_composites_match_ui_spec_hexes() -> void:
	var want := [Color("092A39"), Color("28271D"), Color("271D32"), Color("1B2D20")]
	for lane in LANES:
		_near("lane %d strip" % (lane + 1), _strip(lane), want[lane])


# ---- C1..C19 ----

func test_c1_c4_gem_cores_on_x4_strip() -> void:
	for lane in LANES:
		_check("C%d gem core lane %d" % [lane + 1, lane + 1], Palette.lane_color(lane), _strip(lane), 4.5)


func test_c5_ready_rims_on_strip() -> void:
	for lane in LANES:
		_check("C5 ready rim lane %d" % (lane + 1), Palette.rim_ready(lane), _strip(lane), 4.5)


func test_c6_ready_rims_on_bar_line() -> void:
	for lane in LANES:
		var bar := Wcag.over(Palette.SONAR, 0.22, _strip(lane))
		_check("C6 ready rim on bar line lane %d" % (lane + 1), Palette.rim_ready(lane), bar, 4.5)


func test_c7_gem_rims_on_keyline() -> void:
	for lane in LANES:
		_check("C7 ready rim lane %d" % (lane + 1), Palette.rim_ready(lane), _keyline(), 4.5)
		_check("C7 far rim lane %d" % (lane + 1), Palette.rim_far(lane), _keyline(), 4.5)
		_check("C7 core lane %d" % (lane + 1), Palette.lane_color(lane), _keyline(), 4.5)


func test_c8_receptor_outline_on_strip() -> void:
	for lane in LANES:
		var outline := Wcag.over(Palette.lane_color(lane), 0.75, _strip(lane))
		_check("C8 receptor outline lane %d" % (lane + 1), outline, _strip(lane), 3.0)


func test_c9_text_on_glass_panel() -> void:
	for t in [Palette.TEXT_HI, Palette.TEXT_MID, Palette.TEXT_LO]:
		_check("C9 text on panel", t, _panel(), 4.5)


func test_c10_text_on_focused_row() -> void:
	for t in [Palette.TEXT_HI, Palette.TEXT_MID, Palette.TEXT_LO]:
		_check("C10 text on ABYSS_600", t, Palette.ABYSS_600, 4.5)


func test_c11_accents_on_glass_panel() -> void:
	for t in [Palette.SONAR, Palette.SONAR_PALE, Palette.REWARD_GOLD]:
		_check("C11 accent on panel", t, _panel(), 4.5)


func test_c12_warning_red_on_panel_and_abyss() -> void:
	_check("C12 red on panel", Palette.WARNING_RED, _panel(), 4.5)
	_check("C12 red on ABYSS_900", Palette.WARNING_RED, Palette.ABYSS_900, 4.5)


func test_c13_judgments_on_highway_surface() -> void:
	_check("C13 PERFECT on surface", Palette.SONAR_PALE, _surface(), 4.5)
	_check("C13 GOOD on surface", Palette.TEXT_MID, _surface(), 4.5)


func test_c14_c18_keylined_text() -> void:
	_check("C14/C18 red on keyline", Palette.WARNING_RED, _keyline(), 4.5)
	_check("C18 TEXT_MID on keyline", Palette.TEXT_MID, _keyline(), 4.5)


func test_c15_panel_edge_on_panel() -> void:
	var edge := Wcag.over(Palette.SONAR, 0.45, _panel())
	_check("C15 panel edge", edge, _panel(), 3.0)


func test_c16_focus_edge_on_abyss() -> void:
	_check("C16 focus edge", Palette.SONAR, Palette.ABYSS_900, 3.0)


func test_c17_implosion_backdrop() -> void:
	var backdrop := Wcag.over(Palette.WARNING_RED, 0.18, Palette.ABYSS_900)
	_check("C17 TEXT_HI on IMPLOSION backdrop", Palette.TEXT_HI, backdrop, 4.5)
	_check("C17 red on IMPLOSION backdrop", Palette.WARNING_RED, backdrop, 4.5)


func test_c19_progress_text_on_top_scrim() -> void:
	var typical := Wcag.over(Palette.ABYSS_900, 0.8, Wcag.over(Palette.WALL_TEAL, 0.45, Palette.ABYSS_900))
	var worst := Wcag.over(Palette.ABYSS_900, 0.8, Palette.WALL_TEAL)
	for bg in [typical, worst]:
		_check("C19 title TEXT_MID", Palette.TEXT_MID, bg, 4.5)
		_check("C19 section SONAR_PALE", Palette.SONAR_PALE, bg, 4.5)
		_check("C19 time TEXT_LO", Palette.TEXT_LO, bg, 4.5)
