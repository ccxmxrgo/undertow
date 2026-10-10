extends GdUnitTestSuite
## 02.2-10: the redesigned judgment popup (one per chord, UI-SPEC 7.3 "Judgment popup",
## 11 "Judgment pop / rise") and the early/late text moved from Highway into Feedback.
## Hit sounds keep the same calls on the same events (T-02.2-19).

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

var _saved_rm := false
var _saved_el := true


class SfxSpy:
	extends SfxPool
	var calls: Array = []

	func _ready() -> void:
		pass

	func play_judgment(judgment: int) -> void:
		calls.append(judgment)


func before_test() -> void:
	_saved_rm = Settings.reduce_motion
	_saved_el = Settings.early_late_indicator
	Settings.reduce_motion = false
	Settings.early_late_indicator = true


func after_test() -> void:
	Settings.reduce_motion = _saved_rm
	Settings.early_late_indicator = _saved_el


## Chart: notes 0,1,2 are a chord at 1.0 s (lanes 0, 1, 3); note 3 at 1.5 s lane 2.
func _chart() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	c.add_note(0, 1.0)
	c.add_note(1, 1.0)
	c.add_note(3, 1.0)
	c.add_note(2, 1.5)
	c.finalize()
	return c


func _fb() -> Feedback:
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	fb.chart = _chart()
	fb.clock_usec = 1000000
	add_child(fb)
	return fb


func _idx(fb: Feedback, lane: int, t: float) -> int:
	for i in range(fb.chart.notes.size()):
		var n: Dictionary = fb.chart.notes[i]
		if int(n["lane"]) == lane and is_equal_approx(float(n["time"]), t):
			return i
	return -1


func test_chord_shares_one_popup_centred_on_mean_x() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), P, 0.0)
	fb.clock_usec = 1016000  # next frame
	fb.on_judged(1, _idx(fb, 1, 1.0), P, 0.0)
	fb.on_judged(3, _idx(fb, 3, 1.0), P, 0.0)
	assert_int(fb.floating_count()).is_equal(1)
	var pop := fb.popup(0)
	var mean := (Trench.hit_point(0).x + Trench.hit_point(1).x + Trench.hit_point(3).x) / 3.0
	assert_float(float(pop["x"])).is_equal_approx(mean, 0.01)
	assert_str(str(pop["text"])).is_equal("PERFECT")
	assert_int(int(pop["born"])).is_equal(1000000)  # the timeline did not restart


func test_chord_shows_worst_judgment_including_late_miss() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), P, 0.0)
	fb.on_judged(1, _idx(fb, 1, 1.0), G, 0.05)
	assert_str(str(fb.popup(0)["text"])).is_equal("GOOD")
	fb.on_judged(0, _idx(fb, 0, 1.0), P, 0.0)  # better never overrides worse
	assert_str(str(fb.popup(0)["text"])).is_equal("GOOD")
	fb.clock_usec = 1100000
	fb.on_judged(3, _idx(fb, 3, 1.0), M, 0.1)
	assert_int(fb.floating_count()).is_equal(1)
	assert_str(str(fb.popup(0)["text"])).is_equal("MISS")
	assert_object(fb.popup(0)["color"]).is_equal(Palette.WARNING_RED)


func test_different_times_make_separate_popups_and_cap() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), P, 0.0)
	fb.on_judged(2, _idx(fb, 2, 1.5), G, 0.0)
	assert_int(fb.floating_count()).is_equal(2)
	for i in range(20):
		fb.on_judged(i % 4, 100 + i, P, 0.0)  # unknown indices: each its own popup
		assert_int(fb.floating_count()).is_less_equal(Feedback.MAX_FLOATING)
	assert_int(fb.floating_count()).is_equal(Feedback.MAX_FLOATING)


func test_dead_popup_is_not_merged() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), P, 0.0)
	fb.clock_usec = 1000000 + 700000
	fb.expire()
	assert_int(fb.floating_count()).is_equal(0)
	fb.on_judged(1, _idx(fb, 1, 1.0), M, 0.2)
	assert_int(fb.floating_count()).is_equal(1)
	assert_int(int(fb.popup(0)["born"])).is_equal(1700000)


func test_popup_timeline() -> void:
	var s0 := Feedback.popup_state(0.0, false)
	assert_float(float(s0["scale"])).is_equal_approx(1.4, 0.01)
	assert_float(float(s0["alpha"])).is_equal(1.0)
	var s1 := Feedback.popup_state(0.12, false)
	assert_float(float(s1["scale"])).is_equal_approx(1.0, 0.01)
	var s2 := Feedback.popup_state(0.39, false)
	assert_float(float(s2["alpha"])).is_equal(1.0)
	assert_float(float(s2["rise"])).is_equal_approx(0.0, 0.01)
	var s3 := Feedback.popup_state(0.41, false)
	assert_float(float(s3["alpha"])).is_less_equal(0.61)
	assert_float(float(s3["alpha"])).is_greater(0.5)
	var s4 := Feedback.popup_state(0.62, false)
	assert_float(float(s4["alpha"])).is_equal_approx(0.0, 0.001)
	assert_float(float(s4["rise"])).is_equal_approx(24.0, 0.01)
	var r0 := Feedback.popup_state(0.0, true)
	assert_float(float(r0["scale"])).is_equal(1.0)
	var r1 := Feedback.popup_state(0.5, true)
	assert_float(float(r1["rise"])).is_equal(0.0)
	assert_float(float(r1["alpha"])).is_equal_approx(float(Feedback.popup_state(0.5, false)["alpha"]), 0.001)
	assert_float(Feedback.POP_LIFE).is_equal_approx(0.62, 0.001)


func test_popup_style_tokens() -> void:
	assert_object(Feedback.judgment_color(P)).is_equal(Palette.SONAR_PALE)
	assert_object(Feedback.judgment_color(G)).is_equal(Palette.TEXT_MID)
	assert_object(Feedback.judgment_color(M)).is_equal(Palette.WARNING_RED)
	assert_int(Feedback.POP_SIZE).is_equal(Palette.SIZE_HEADING)
	assert_object(Feedback.popup_font()).is_same(Palette.display_font())
	assert_float(Feedback.POP_Y).is_equal(846.0)
	assert_int(Feedback.OUTLINE_PX).is_equal(6)  # 3 px each side


func test_early_late_text() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), G, -0.012)
	assert_str(fb.indicator_text()).is_equal("EARLY 12 MS")
	assert_bool(fb.indicator_early()).is_true()
	assert_float(fb.indicator_alpha()).is_equal(1.0)
	fb.on_judged(2, _idx(fb, 2, 1.5), P, 0.008)
	assert_str(fb.indicator_text()).is_equal("LATE 8 MS")
	assert_bool(fb.indicator_early()).is_false()
	fb.clock_usec += 390000
	assert_float(fb.indicator_alpha()).is_equal(1.0)
	fb.clock_usec += 200000
	assert_float(fb.indicator_alpha()).is_equal(0.0)
	assert_vector(Feedback.INDICATOR_POS).is_equal(Vector2(960.0, 1004.0))
	assert_vector(Feedback.ARROW_SIZE).is_equal(Vector2(10.0, 12.0))


func test_early_late_hidden_by_setting_and_on_miss() -> void:
	var fb := _fb()
	fb.on_judged(0, _idx(fb, 0, 1.0), G, -0.02)
	assert_bool(fb.indicator_visible()).is_true()
	fb.on_judged(1, _idx(fb, 1, 1.0), M, 0.2)
	assert_bool(fb.indicator_visible()).is_false()
	fb.on_judged(2, _idx(fb, 2, 1.5), G, 0.02)
	Settings.early_late_indicator = false
	assert_bool(fb.indicator_visible()).is_false()


func test_highway_no_longer_draws_the_indicator() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	assert_bool(src.contains("_draw_indicator")).is_false()
	var fsrc := FileAccess.get_file_as_string("res://src/ui/feedback.gd")
	assert_bool(fsrc.contains("_draw_flash")).is_false()
	assert_bool(fsrc.contains("nudge")).is_false()


func test_sfx_calls_unchanged() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	var spy := SfxSpy.new()
	fb.sfx = spy
	fb.add_child(spy)
	add_child(fb)
	fb.on_judged(0, 0, P, 0.0)
	fb.on_judged(1, 1, G, 0.04)
	fb.on_judged(2, 2, M, 0.2)
	fb.on_stray(3)
	assert_array(spy.calls).is_equal([P, G, M])


func test_feedback_connect_judge_reads_chart() -> void:
	var chart := _chart()
	var judge := InputJudge.new(chart, JudgeConfig.new())
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	add_child(fb)
	fb.connect_judge(judge)
	judge.press(0, 1.0)
	judge.press(1, 1.0)
	judge.press(3, 1.01)
	assert_int(fb.floating_count()).is_equal(1)
	judge.tick(5.0)  # note 3 (1.5 s) expires as a miss
	assert_int(fb.floating_count()).is_equal(2)
