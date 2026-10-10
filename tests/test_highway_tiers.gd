extends GdUnitTestSuite
## 02.2-09: the living surface. Beat and bar lines from the tempo map and time signatures
## (D-18), streak intensity tiers (UI-SPEC 7.6), the sustain tube alpha, the effect contract,
## and the sonar_surface CRT pass under the notes (UI-SPEC 7.4 row 2, section 11).

const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"

var _saved_low := false
var _saved_rm := false


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm
	Gameplay.pending_chart = null
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _chart(bpm: float, num: int = 0, den: int = 4) -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": bpm})
	if num > 0:
		c.time_sigs.append({"time": 0.0, "num": num, "den": den})
	c.add_note(0, 1.0)
	c.add_note(1, 2.0, 1.0)
	c.finalize()
	return c


func _highway(chart: ChartData) -> Highway:
	var conductor: Conductor = auto_free(Conductor.new())
	add_child(conductor)
	var hw: Highway = auto_free(Highway.new())
	add_child(hw)
	hw.setup(chart, conductor)
	return hw


func _bars(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		if bool(l["bar"]):
			out.append(l)
	return out


# ---- Beat and bar lines ----------------------------------------------------------------

func test_beat_lines_120_bpm_four_four() -> void:
	var hw := _highway(_chart(120.0))
	var lines := hw.visible_beat_lines(0.6, 1.5)
	assert_int(lines.size()).is_equal(3)
	assert_int(_bars(lines).size()).is_equal(1)
	assert_float(float(_bars(lines)[0]["time"])).is_equal_approx(2.0, 0.0001)
	for l in lines:
		assert_bool(float(l["d"]) >= 0.0 and float(l["d"]) <= 1.0).is_true()
	var none := hw.visible_beat_lines(0.25, 1.5)
	assert_int(none.size()).is_equal(3)
	assert_int(_bars(none).size()).is_equal(0)


func test_beat_lines_follow_three_four() -> void:
	var hw := _highway(_chart(120.0, 3, 4))
	var lines := hw.visible_beat_lines(0.1, 3.0)
	var bar_times: Array = []
	for b in _bars(lines):
		bar_times.append(snappedf(float(b["time"]), 0.001))
	assert_array(bar_times).is_equal([1.5, 3.0])
	assert_int(lines.size()).is_equal(6)


func test_beat_lines_are_capped() -> void:
	var hw := _highway(_chart(6000.0))
	var lines := hw.visible_beat_lines(1.0, 1.5)
	assert_int(lines.size()).is_less_equal(Highway.MAX_BEAT_LINES)
	assert_int(Highway.MAX_BEAT_LINES).is_equal(64)


func test_highway_uses_beats_between() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	assert_bool(src.contains("BeatClock.beats_between(")).is_true()
	assert_bool(src.contains("chart.time_sigs")).is_true()


# ---- Streak tiers -----------------------------------------------------------------------

func test_set_tier_clamps_and_picks_the_tint() -> void:
	var hw: Highway = auto_free(Highway.new())
	var want := {0: 1, 1: 1, 2: 2, 3: 3, 4: 4, 9: 4}
	for m in want:
		hw.set_tier(m)
		assert_int(hw.tier).is_equal(want[m])
		assert_float(hw.strip_tint()).is_equal(Palette.TIER_TINT[hw.tier - 1])


func test_rail_glow_alpha_per_tier_and_low_effects() -> void:
	var hw: Highway = auto_free(Highway.new())
	var want := [0.0, 0.35, 0.55, 0.80]
	for t in range(1, 5):
		hw.set_tier(t)
		assert_float(hw.rail_glow_alpha()).is_equal_approx(want[t - 1], 0.0001)
	Settings.low_effects = true
	for t in range(1, 5):
		hw.set_tier(t)
		assert_float(hw.rail_glow_alpha()).is_equal(0.0)


func test_max_dashes_in_every_mode_flowing_unless_reduce_motion() -> void:
	var hw := _highway(_chart(120.0))
	hw.set_tier(3)
	assert_bool(hw.max_dashes_enabled()).is_false()
	hw.set_tier(4)
	for low in [false, true]:
		for rm in [false, true]:
			Settings.low_effects = low
			Settings.reduce_motion = rm
			assert_bool(hw.max_dashes_enabled()).is_true()
	Settings.low_effects = false
	Settings.reduce_motion = false
	assert_bool(absf(hw.dash_phase(1.10) - hw.dash_phase(1.20)) > 0.01).is_true()
	Settings.reduce_motion = true
	assert_float(hw.dash_phase(1.10)).is_equal(hw.dash_phase(1.20))


func test_drop_from_max_fades_extras() -> void:
	var hw: Highway = auto_free(Highway.new())
	hw.set_tier(4)
	assert_float(hw.extras_alpha()).is_equal(1.0)
	hw.set_tier(1)
	var t0: int = hw._drop_ticks
	assert_float(hw.extras_alpha(t0)).is_greater(0.99)
	var mid := hw.extras_alpha(t0 + 90000)
	assert_bool(mid > 0.2 and mid < 0.8).is_true()
	assert_float(hw.extras_alpha(t0 + 200000)).is_equal(0.0)


func test_entering_max_flashes_the_rails() -> void:
	var hw: Highway = auto_free(Highway.new())
	hw.set_tier(3)
	assert_float(hw.rail_flash_alpha()).is_equal(0.0)
	hw.set_tier(4)
	assert_float(hw.rail_flash_alpha()).is_greater(0.5)
	hw.flash_rails(0.6, 0.2)
	assert_float(hw.rail_flash_alpha(hw._flash_ticks + 250000)).is_equal(0.0)


# ---- Sustain tube -----------------------------------------------------------------------

func test_sustain_tube_alpha() -> void:
	assert_float(Highway.sustain_fill_alpha(Highway.S_HOLDING, 0.0)).is_equal_approx(0.75, 0.0001)
	assert_float(Highway.sustain_fill_alpha(Highway.S_HOLDING, 0.5)).is_equal_approx(0.45 + 0.30 * BeatClock.pulse(0.5), 0.0001)
	assert_float(Highway.sustain_fill_alpha(Highway.S_PENDING, 0.0)).is_equal_approx(0.45, 0.0001)
	assert_float(Highway.sustain_fill_alpha(Highway.S_EARLY_RELEASE, 0.0)).is_equal_approx(0.25, 0.0001)
	assert_bool(Highway.sustain_has_core(Highway.S_EARLY_RELEASE)).is_false()
	assert_bool(Highway.sustain_has_core(Highway.S_MISSED)).is_false()
	assert_bool(Highway.sustain_has_core(Highway.S_PENDING)).is_true()
	assert_bool(Highway.sustain_has_core(Highway.S_HOLDING)).is_true()


# ---- Effect contract --------------------------------------------------------------------

func test_highway_is_an_fx_node_with_crt_and_rail_glow_counts() -> void:
	var hw := _highway(_chart(120.0))
	assert_bool(hw.is_in_group(UiKit.FX_GROUP)).is_true()
	hw.set_tier(3)
	var counts := hw.effect_counts()
	assert_bool(counts.has("crt")).is_true()
	assert_float(float(counts["rail_glow"])).is_equal_approx(0.55, 0.0001)


func test_gameplay_wires_multiplier_to_set_tier() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/gameplay.gd")
	assert_bool(src.contains("multiplier_changed.connect(highway.set_tier)")).is_true()
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = TestCharts.short_chart()
	var gp: Gameplay = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	assert_int(gp.highway.tier).is_equal(1)
	gp.score.multiplier_changed.emit(3)
	assert_int(gp.highway.tier).is_equal(3)
