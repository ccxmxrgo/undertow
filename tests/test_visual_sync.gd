extends GdUnitTestSuite
## Gap G1 (02.2-26): the gem is drawn exactly where the judge says the note is. At judge offset 0
## (song_time == note time) every lane's gem centre sits on its receptor centre and on the hit
## line, for every scroll speed and visual offset (applied by the documented convention
## vt = song_time + visual_offset, the same one the calibration wizard previews).

const NOTE_T := 10.0
const SPEEDS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0]
const OFFSETS: Array[float] = [-0.1, 0.0, 0.05]
const EPS_PX := 0.5

var _saved_offset: float
var _saved_speed: float
var _saved_reduce: bool


func before_test() -> void:
	_saved_offset = Settings.visual_offset
	_saved_speed = Settings.scroll_speed
	_saved_reduce = Settings.reduce_motion


func after_test() -> void:
	Settings.visual_offset = _saved_offset
	Settings.scroll_speed = _saved_speed
	Settings.reduce_motion = _saved_reduce


## One note per lane, all at NOTE_T (lane order 0..3 = note index 0..3).
func _chart() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})
	for lane in range(4):
		c.add_note(lane, NOTE_T)
	return c


func _board(song_time: float) -> Highway:
	var conductor: Conductor = auto_free(Conductor.new())
	add_child(conductor)
	var hw: Highway = auto_free(Highway.new())
	add_child(hw)
	hw.setup(_chart(), conductor)
	_set_time(hw, song_time)
	return hw


func _set_time(hw: Highway, song_time: float) -> void:
	hw.conductor.clock.reset(0, song_time)
	hw._update_window()


func _lane_of(hw: Highway, idx: int) -> int:
	return int(hw.chart.notes[idx]["lane"])


## A: 4 lanes x 5 scroll speeds x 3 visual offsets = 60 positions, gem on hit point and line.
func test_gem_on_hit_line_every_lane_speed_and_visual_offset() -> void:
	var line_y := Trench.line_points()[0].y
	var checked := 0
	for speed in SPEEDS:
		for vo in OFFSETS:
			Settings.scroll_speed = speed
			Settings.visual_offset = vo
			var hw := _board(NOTE_T - vo)
			for idx in range(4):
				var lane := _lane_of(hw, idx)
				var c := hw.gem_center(idx)
				var hp := Trench.hit_point(lane)
				assert_float(c.distance_to(hp)).override_failure_message(
					"lane %d speed %.1f vo %.2f: gem %s vs hit point %s" % [lane, speed, vo, c, hp]).is_less_equal(EPS_PX)
				assert_float(absf(c.y - line_y)).is_less_equal(EPS_PX)
				checked += 1
	assert_int(checked).is_equal(60)


## B: at judge offset 0 with no visual offset, gem centre == the pad centre _draw_receptors uses.
func test_gem_on_receptor_at_judge_offset_zero() -> void:
	Settings.visual_offset = 0.0
	for speed in SPEEDS:
		Settings.scroll_speed = speed
		var hw := _board(NOTE_T)
		for idx in range(4):
			var lane := _lane_of(hw, idx)
			assert_float(hw.gem_center(idx).distance_to(hw.receptor_center(lane))).is_less_equal(EPS_PX)
		# The ready window is judged on raw song_time (judge clock), not on the visual time.
		assert_float(hw._st).is_equal(NOTE_T)


## C: visual_offset +0.05 draws the gem early: it reaches the line 50 ms of song_time BEFORE the
## note time. The calibration wizard's visual step uses the same sign (vt = st + pending_visual).
func test_visual_offset_sign_matches_calibration_wizard() -> void:
	Settings.scroll_speed = 1.0
	Settings.visual_offset = 0.05
	var hw := _board(NOTE_T - 0.05)
	assert_float(hw.gem_center(0).distance_to(hw.receptor_center(0))).is_less_equal(EPS_PX)
	# At the note time itself the gem is already past (below) the line.
	_set_time(hw, NOTE_T)
	assert_float(hw.gem_center(0).y).is_greater(Trench.HIT_Y + 10.0)
	var src := FileAccess.get_file_as_string("res://src/ui/calibration_wizard.gd")
	assert_bool(src.contains("var vt := st + pending_visual")).is_true()
	var hsrc := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	assert_bool(hsrc.contains("_vt = _st + Settings.visual_offset")).is_true()


static func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## D: every gem kind's visual centre is its anchor, and the gem and pad share it.
func test_gem_visual_centre_is_anchor() -> void:
	var r := Trench.note_radius(Trench.scale_at(0.0))
	assert_float(r).is_equal_approx(41.0, 0.001)
	for kind in range(4):
		var u := NotePainter.unit_shape(kind)
		var gem_box := _bbox(u["poly"])
		var pad_box := _bbox(NotePainter.outline_ring(kind))
		var gc := gem_box.get_center()
		var pc := pad_box.get_center()
		assert_float(gc.length()).override_failure_message("kind %d gem bbox centre %s" % [kind, gc]).is_less_equal(0.02)
		assert_float(gc.distance_to(pc)).is_less_equal(0.001)
		var top := Trench.HIT_Y + gem_box.position.y * r
		var bottom := Trench.HIT_Y + gem_box.end.y * r
		assert_float(absf((top + bottom) * 0.5 - Trench.HIT_Y)).override_failure_message(
			"kind %d drawn extent %.2f..%.2f not centred on the hit line" % [kind, top, bottom]).is_less_equal(1.0)
		# Top-light and specular stay inside the gem's bounding box after any recentring.
		assert_bool(gem_box.grow(0.001).encloses(_bbox(u["top"]))).is_true()
		assert_bool(gem_box.grow(0.001).encloses(_bbox(u["spec"]))).is_true()


## E: the board reads the same-frame clock: Conductor processes first, the snapshot is exact.
func test_board_uses_same_frame_clock() -> void:
	var conductor: Conductor = auto_free(Conductor.new())
	var hw: Highway = auto_free(Highway.new())
	var notes: HighwayNotes = auto_free(HighwayNotes.new())
	assert_int(conductor.process_priority).is_less(hw.process_priority)
	assert_int(conductor.process_priority).is_less(notes.process_priority)
	Settings.visual_offset = 0.037
	var board := _board(9.8765)
	assert_float(board._st).is_equal(board.conductor.song_time())
	assert_float(board._vt).is_equal(board._st + Settings.visual_offset)
	_set_time(board, 9.9)
	assert_float(board._st).is_equal(9.9)
	assert_float(board._vt).is_equal(9.9 + 0.037)
	var src := FileAccess.get_file_as_string("res://src/ui/highway.gd")
	assert_bool(src.contains("_st = conductor.song_time()")).is_true()
	assert_bool(src.contains("lerp(_st")).is_false()


## F: a pending note just past the line (late but inside Good) keeps moving below the line on its
## lane axis; it does not snap back to the line or vanish.
func test_pending_note_past_line_keeps_moving() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	var approach := Trench.approach_for(1.0)
	for idx in range(4):
		var lane := _lane_of(hw, idx)
		var prev_y := Trench.HIT_Y
		for step in range(1, 7):
			var d := -0.01 * step
			_set_time(hw, NOTE_T - d * approach)
			assert_int(hw._vis.has(idx) as int).is_equal(1)
			var c := hw.gem_center(idx)
			var expect := Trench.point(Trench.lane_f(lane), d)
			assert_float(c.distance_to(expect)).is_less_equal(EPS_PX)
			assert_float(c.y).is_greater(prev_y)
			prev_y = c.y


## G: the fade helper is fully opaque at the line and the gem y at d = 0 is the hit line y.
func test_gem_at_line_is_unfaded() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	assert_float(Trench.note_fade(0.0)).is_equal(1.0)
	assert_float(hw.gem_center(0).y).is_equal_approx(Trench.line_points()[0].y, EPS_PX)


# ---- Phase 3 (03-08): payload modifiers keep the gem on the hit line (UI-SPEC 7.5-7.7) ----

## 120 bpm: one beat = 0.5 s. Payload arrives at 2.0 (ease/slide done at 2.5), ends at 20.0.
const P_ARRIVE := 2.0
const P_END := 20.0


func _stack(hw: Highway, reward: int, seed: int = 0) -> PayloadStack:
	var s := PayloadStack.new(hw.chart, VersusConfig.new())
	s.install({"id": 1, "reward": reward, "arrive_t": P_ARRIVE, "end_t": P_END, "seed": seed})
	hw.bind_versus(s, null, VersusConfig.new())
	return s


## A Crossed Wires stack whose seeded pair is exactly lanes {a, b}.
func _crossed(hw: Highway, a: int, b: int) -> PayloadStack:
	for seed in range(1000):
		var s := PayloadStack.new(hw.chart, VersusConfig.new())
		s.install({"id": 1, "reward": Reward.Id.CROSSED_WIRES, "arrive_t": P_ARRIVE, "end_t": P_END, "seed": seed})
		var p := s.crossed_pair()
		if (p.x == a and p.y == b) or (p.x == b and p.y == a):
			hw.bind_versus(s, null, VersusConfig.new())
			return s
	return null


func test_null_payloads_keep_solo_approach() -> void:
	Settings.visual_offset = 0.0
	for speed in SPEEDS:
		Settings.scroll_speed = speed
		var hw := _board(NOTE_T - 0.4)
		assert_object(hw.payloads).is_null()
		assert_float(float(hw.debug_payload_state()["approach"])).is_equal(Trench.approach_for(speed))
		for lane in range(4):
			assert_float(hw.receptor_center(lane).distance_to(Trench.hit_point(lane))).is_equal(0.0)


func test_pressure_crack_speeds_up_and_gem_still_on_line() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	_stack(hw, Reward.Id.PRESSURE_CRACK)
	_set_time(hw, NOTE_T)
	assert_float(hw._approach).is_equal_approx(Trench.approach_for(1.5), 1e-9)
	for idx in range(4):
		var lane := _lane_of(hw, idx)
		assert_float(hw.gem_center(idx).distance_to(Trench.hit_point(lane))).is_less_equal(EPS_PX)
	# Before the note the gem is nearer than at normal speed (faster scroll).
	_set_time(hw, NOTE_T - 0.6)
	assert_float(hw.gem_depth(0)).is_equal_approx(0.6 / Trench.approach_for(1.5), 1e-6)
	# Cap: base 3.0 x 1.5 is capped at pressure_crack_max_speed (3.5).
	Settings.scroll_speed = 3.0
	_set_time(hw, NOTE_T)
	assert_float(hw._approach).is_equal_approx(Trench.approach_for(3.5), 1e-9)
	assert_float(PayloadStack.effective_speed(3.0, 1.5, 3.5)).is_equal(3.5)


func test_pressure_crack_rail_colour_blends_toward_warning_red() -> void:
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	assert_that(_rgb(hw.rail_color())).is_equal(_rgb(Palette.SONAR))
	_stack(hw, Reward.Id.PRESSURE_CRACK)
	_set_time(hw, NOTE_T)
	assert_that(_rgb(hw.rail_color())).is_equal(_rgb(Palette.SONAR.lerp(Palette.WARNING_RED, 0.6)))
	assert_that(_rgb(hw.debug_payload_state()["rail_color"])).is_equal(_rgb(Palette.SONAR.lerp(Palette.WARNING_RED, 0.6)))


static func _rgb(c: Color) -> Vector3:
	return Vector3(snappedf(c.r, 1e-5), snappedf(c.g, 1e-5), snappedf(c.b, 1e-5))


func test_crossed_wires_moves_gems_and_receptors_not_labels() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	assert_object(_crossed(hw, 1, 2)).is_not_null()
	_set_time(hw, NOTE_T)
	# Lane 1's gem reaches the hit line at its time, at lane 2's screen x (and vice versa).
	assert_float(hw.gem_center(1).distance_to(Trench.hit_point(2))).is_less_equal(EPS_PX)
	assert_float(hw.gem_center(2).distance_to(Trench.hit_point(1))).is_less_equal(EPS_PX)
	assert_float(hw.receptor_center(1).distance_to(Trench.hit_point(2))).is_less_equal(EPS_PX)
	assert_float(hw.receptor_center(2).distance_to(Trench.hit_point(1))).is_less_equal(EPS_PX)
	for lane in [0, 3]:
		assert_float(hw.gem_center(lane).distance_to(Trench.hit_point(lane))).is_less_equal(EPS_PX)
		assert_float(hw.receptor_center(lane).distance_to(Trench.hit_point(lane))).is_less_equal(EPS_PX)
	# Key labels stay at their screen positions.
	for lane in range(4):
		assert_float(hw.lane_label_center(lane).distance_to(Trench.hit_point(lane))).is_equal(0.0)
	var xs: PackedFloat32Array = hw.debug_payload_state()["lane_x"]
	assert_float(xs[1]).is_equal_approx(Trench.lane_f(2), 1e-6)
	assert_float(xs[2]).is_equal_approx(Trench.lane_f(1), 1e-6)


func test_crossed_wires_slide_is_between_positions_mid_beat() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	Settings.reduce_motion = false
	var hw := _board(P_ARRIVE + 0.25)
	assert_object(_crossed(hw, 1, 2)).is_not_null()
	_set_time(hw, P_ARRIVE + 0.25)
	var x := float((hw.debug_payload_state()["lane_x"] as PackedFloat32Array)[1])
	assert_float(x).is_between(Trench.lane_f(1) + 0.01, Trench.lane_f(2) - 0.01)
	assert_bool(bool(hw.debug_payload_state()["sliding"])).is_true()


func test_crossed_wires_reduce_motion_cross_fades_columns() -> void:
	Settings.visual_offset = 0.0
	Settings.scroll_speed = 1.0
	Settings.reduce_motion = true
	var hw := _board(P_ARRIVE + 0.25)
	assert_object(_crossed(hw, 1, 2)).is_not_null()
	_set_time(hw, P_ARRIVE + 0.25)
	var cols: Array = hw.lane_columns(1)
	assert_int(cols.size()).is_equal(2)
	assert_float(float(cols[0].x)).is_equal_approx(Trench.lane_f(1), 1e-6)
	assert_float(float(cols[1].x)).is_equal_approx(Trench.lane_f(2), 1e-6)
	assert_float(float(cols[0].y) + float(cols[1].y)).is_equal_approx(1.0, 1e-6)
	# Lanes outside the pair always have a single opaque column.
	assert_int(hw.lane_columns(0).size()).is_equal(1)


func test_sonar_jam_switches_gems_to_jam_type() -> void:
	Settings.scroll_speed = 1.0
	var hw := _board(NOTE_T)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_NORMAL)).is_equal(NotePainter.NOTE_NORMAL)
	_stack(hw, Reward.Id.SONAR_JAM)
	_set_time(hw, P_ARRIVE + 0.25)
	var k := float(hw.debug_payload_state()["jam_k"])
	assert_float(k).is_between(0.01, 0.99)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_NORMAL)).is_equal(NotePainter.NOTE_NORMAL)
	_set_time(hw, NOTE_T)
	assert_float(float(hw.debug_payload_state()["jam_k"])).is_equal(1.0)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_NORMAL)).is_equal(NotePainter.NOTE_JAM)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_DISRUPTOR)).is_equal(NotePainter.NOTE_JAM)
	assert_int(hw.gem_paint_type(NotePainter.NOTE_GHOST)).is_equal(NotePainter.NOTE_GHOST)
	# Jam never moves a gem: it still sits on the hit line at its time.
	assert_float(hw.gem_center(0).distance_to(Trench.hit_point(0))).is_less_equal(EPS_PX)
