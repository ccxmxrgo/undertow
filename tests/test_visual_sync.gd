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


func before_test() -> void:
	_saved_offset = Settings.visual_offset
	_saved_speed = Settings.scroll_speed


func after_test() -> void:
	Settings.visual_offset = _saved_offset
	Settings.scroll_speed = _saved_speed


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
