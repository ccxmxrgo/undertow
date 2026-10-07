class_name Highway
extends Control
## Single _draw() highway: a pure function of song_time + visual_offset + scroll speed
## (D-25). Geometry from UI-SPEC: 4 lanes x 128 px centered, hull line at y = 880.
## Also draws the Phase 1 clock-smoothness spike readout (song_time, raw position, graph).

const LANE_W := 128.0
const LANES := 4
const HULL_Y := 880.0
const PX_PER_SEC := 700.0
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const GRAPH_SAMPLES := 128
const JUDGMENT_SHOW_USEC := 600000

const GREEN := Color("39FF14")
const DIM_GREEN := Color("1F8F0C")
const TEXT_GREEN := Color("8FD98A")
const RED := Color("FF4A3D")
const FONT: Font = preload("res://assets/fonts/ShareTechMono-Regular.ttf")

var chart: ChartData
var conductor: Conductor

var _first_visible: int = 0
var _state := PackedByteArray()  # per note: 0 unjudged, 1 hit, 2 missed
var _last_word: String = ""
var _last_word_color: Color = GREEN
var _last_error_ms: float = 0.0
var _last_ticks: int = -JUDGMENT_SHOW_USEC
var _flash_lane: int = -1
var _flash_ticks: int = 0
var _graph := PackedFloat32Array()  # song_time delta per frame, ms
var _prev_song_time: float = 0.0


func setup(p_chart: ChartData, p_conductor: Conductor) -> void:
	chart = p_chart
	conductor = p_conductor
	_state.resize(chart.notes.size())
	_state.fill(0)
	_graph.resize(GRAPH_SAMPLES)
	_graph.fill(0.0)


func on_judged(lane: int, note_index: int, judgment: int, error_s: float) -> void:
	_state[note_index] = 2 if judgment == InputJudge.Judgment.MISS else 1
	match judgment:
		InputJudge.Judgment.PERFECT:
			_last_word = "PERFECT"
			_last_word_color = GREEN
		InputJudge.Judgment.GOOD:
			_last_word = "GOOD"
			_last_word_color = TEXT_GREEN
		_:
			_last_word = "MISS"
			_last_word_color = RED
	_last_error_ms = error_s * 1000.0
	_last_ticks = Time.get_ticks_usec()
	_flash_lane = lane
	_flash_ticks = _last_ticks


func on_stray(lane: int) -> void:
	_flash_lane = lane
	_flash_ticks = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if conductor == null:
		return
	var st := conductor.song_time()
	# Ring buffer of per-frame song_time delta: a smooth clock draws a flat line.
	for i in range(GRAPH_SAMPLES - 1):
		_graph[i] = _graph[i + 1]
	_graph[GRAPH_SAMPLES - 1] = (st - _prev_song_time) * 1000.0
	_prev_song_time = st
	queue_redraw()


func _draw() -> void:
	if chart == null or conductor == null:
		return
	var left := (SCREEN_W - LANE_W * LANES) * 0.5
	var width := LANE_W * LANES
	var vt := conductor.song_time() + Settings.visual_offset
	var pps := PX_PER_SEC * Settings.scroll_speed

	_draw_lanes(left, width)
	_draw_notes(left, vt, pps)
	_draw_hull_line(left, width)
	_draw_judgment(left)
	_draw_spike_readout()


func _draw_lanes(left: float, width: float) -> void:
	if _flash_lane >= 0:
		var age := Time.get_ticks_usec() - _flash_ticks
		if age < 120000:
			var a := 0.4 * (1.0 - age / 120000.0)
			draw_rect(Rect2(left + _flash_lane * LANE_W, HULL_Y - 160.0, LANE_W, 160.0), Color(GREEN.r, GREEN.g, GREEN.b, a))
	for i in range(LANES + 1):
		var x := left + i * LANE_W
		var edge := i == 0 or i == LANES
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_H), GREEN if edge else DIM_GREEN, 2.0)
	for lane in range(LANES):
		var label := _lane_label(lane)
		draw_string(FONT, Vector2(left + lane * LANE_W, 904.0 + 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, LANE_W, 20, TEXT_GREEN)


func _lane_label(lane: int) -> String:
	for ev in InputMap.action_get_events(LaneInput.ACTIONS[lane]):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return str(lane + 1)


func _draw_notes(left: float, vt: float, pps: float) -> void:
	var notes := chart.notes
	# Moving window: skip notes already far below the screen.
	var below_time := vt - (SCREEN_H + NoteShape.SIZE - HULL_Y) / pps
	while _first_visible < notes.size() and float(notes[_first_visible]["time"]) < below_time:
		_first_visible += 1
	var i := _first_visible
	while i < notes.size():
		var n: Dictionary = notes[i]
		var y := HULL_Y - (float(n["time"]) - vt) * pps
		if y < -NoteShape.SIZE:
			break
		if _state[i] != 1:
			var lane: int = n["lane"]
			var col := GREEN if _state[i] == 0 else Color(GREEN.r, GREEN.g, GREEN.b, 0.25)
			NoteShape.draw(self, NoteShape.kind_for_lane(lane), Vector2(left + (lane + 0.5) * LANE_W, y), col)
		i += 1


func _draw_hull_line(left: float, width: float) -> void:
	draw_line(Vector2(left - 32.0, HULL_Y), Vector2(left + width + 32.0, HULL_Y), GREEN, 4.0)


func _draw_judgment(left: float) -> void:
	var age := Time.get_ticks_usec() - _last_ticks
	if age >= JUDGMENT_SHOW_USEC or _last_word == "":
		return
	var a := 1.0 - float(age) / JUDGMENT_SHOW_USEC
	var col := Color(_last_word_color.r, _last_word_color.g, _last_word_color.b, a)
	var cx := left
	draw_string(FONT, Vector2(cx, HULL_Y - 200.0), _last_word, HORIZONTAL_ALIGNMENT_CENTER, LANE_W * LANES, 40, col)
	var arrow := "<" if _last_error_ms < 0.0 else ">"
	var side := "EARLY" if _last_error_ms < 0.0 else "LATE"
	var txt := "%s %s %d MS" % [arrow, side, int(round(absf(_last_error_ms)))]
	draw_string(FONT, Vector2(cx, HULL_Y - 160.0), txt, HORIZONTAL_ALIGNMENT_CENTER, LANE_W * LANES, 28, Color(TEXT_GREEN.r, TEXT_GREEN.g, TEXT_GREEN.b, a))


func _draw_spike_readout() -> void:
	var x := 1568.0
	var y := 32.0
	var st := conductor.song_time()
	draw_string(FONT, Vector2(x, y + 20.0), "song_time %.3f" % st, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_GREEN)
	draw_string(FONT, Vector2(x, y + 44.0), "raw_pos   %.3f" % conductor.raw_position(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_GREEN)
	draw_string(FONT, Vector2(x, y + 68.0), "latency   %.1f ms  audio_valid %s" % [conductor.output_latency() * 1000.0, str(conductor.audio_valid())], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_GREEN)
	draw_string(FONT, Vector2(x, y + 92.0), "dt/frame (ms), 0-40", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_GREEN)
	var gx := x
	var gy := y + 104.0
	var gw := 320.0
	var gh := 96.0
	draw_rect(Rect2(gx, gy, gw, gh), DIM_GREEN, false, 2.0)
	var pts := PackedVector2Array()
	for i in range(GRAPH_SAMPLES):
		var v := clampf(_graph[i], 0.0, 40.0) / 40.0
		pts.append(Vector2(gx + gw * i / (GRAPH_SAMPLES - 1), gy + gh - v * gh))
	draw_polyline(pts, GREEN, 2.0)
