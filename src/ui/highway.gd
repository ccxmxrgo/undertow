class_name Highway
extends Control
## Single _draw() highway: a pure function of song_time + visual_offset + scroll speed
## (D-25). Geometry from UI-SPEC: 4 lanes x 128 px centered, hull line at y = 880.
## Colors come from Palette only. Lane flashes and floating text live in Feedback.
## The Phase 1 clock-smoothness spike readout is kept behind `show_spike_readout`.

const LANE_W := 128.0
const LANES := 4
const HULL_Y := 880.0
const LABEL_Y := 936.0
const RECEPTOR_PULSE_USEC := 120000
const INDICATOR_Y := 780.0
const PX_PER_SEC := 700.0
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const GRAPH_SAMPLES := 128
const SUSTAIN_W := 32.0
const INDICATOR_FADE_USEC := 400000
const PREROLL_BEATS := 2

const S_PENDING := 0
const S_HIT := 1
const S_MISSED := 2
const S_HOLDING := 3
const S_EARLY_RELEASE := 4

var chart: ChartData
var conductor: Conductor
var show_spike_readout: bool = false

var _first_visible: int = 0
var _state := PackedByteArray()
var _holding: Array[int] = [-1, -1, -1, -1]
var _last_error_ms: float = 0.0
var _last_ticks: int = -INDICATOR_FADE_USEC
var _show_indicator: bool = false
var _graph := PackedFloat32Array()  # song_time delta per frame, ms
var _prev_song_time: float = 0.0
var _good_window: float = 0.070
var _press_ticks: Array[int] = [-1, -1, -1, -1]


## True while a note is inside the Good window (inclusive); NaN/inf are never ready.
static func note_is_ready(dt: float, good_window: float) -> bool:
	return is_finite(dt) and absf(dt) <= good_window


## Receptor pulse on lane press: 120 ms ease-out, scale 1.0 -> 1.2 -> 1.0.
static func receptor_pulse(age_usec: int, reduce_motion: bool) -> Dictionary:
	var pulsing := age_usec >= 0 and age_usec < RECEPTOR_PULSE_USEC
	var scale := 1.0
	if pulsing and not reduce_motion:
		var t := float(age_usec) / RECEPTOR_PULSE_USEC
		scale = 1.0 + 0.2 * sin(PI * pow(t, 0.5))
	return {"scale": scale, "fill_alpha": 0.40 if pulsing else 0.0, "outline_alpha": 1.0 if pulsing else 0.70}


## X of the highway's left edge in screen space.
static func lane_left() -> float:
	return (SCREEN_W - LANE_W * LANES) * 0.5


static func lane_center_x(lane: int) -> float:
	return lane_left() + (lane + 0.5) * LANE_W


func setup(p_chart: ChartData, p_conductor: Conductor, p_cfg: JudgeConfig = null) -> void:
	chart = p_chart
	conductor = p_conductor
	_good_window = (p_cfg if p_cfg != null else JudgeConfig.new()).good_window
	_press_ticks = [-1, -1, -1, -1]
	_state.resize(chart.notes.size())
	_state.fill(S_PENDING)
	_holding = [-1, -1, -1, -1]
	_first_visible = 0
	_graph.resize(GRAPH_SAMPLES)
	_graph.fill(0.0)


func on_judged(lane: int, note_index: int, judgment: int, error_s: float) -> void:
	if note_index < 0 or note_index >= _state.size():
		return
	if judgment == InputJudge.Judgment.MISS:
		_state[note_index] = S_MISSED
		_show_indicator = false
		return
	if float(chart.notes[note_index]["duration"]) > 0.0:
		_state[note_index] = S_HOLDING
		_holding[lane] = note_index
	else:
		_state[note_index] = S_HIT
	_last_error_ms = error_s * 1000.0
	_last_ticks = Time.get_ticks_usec()
	_show_indicator = true


func on_stray(_lane: int) -> void:
	pass


## Connect to LaneInput.lane_pressed; starts the receptor pulse for that lane.
func on_lane_pressed(lane: int, _ticks: int) -> void:
	if lane < 0 or lane >= LANES:
		return
	_press_ticks[lane] = Time.get_ticks_usec()


## Connect to InputJudge.sustain_end. Early release dims the tail; completion consumes it.
func on_sustain_end(lane: int, completed: bool) -> void:
	var idx := _holding[lane]
	if idx < 0:
		return
	_state[idx] = S_HIT if completed else S_EARLY_RELEASE
	_holding[lane] = -1


func _process(_delta: float) -> void:
	if conductor == null:
		return
	if show_spike_readout:
		var st := conductor.song_time()
		for i in range(GRAPH_SAMPLES - 1):
			_graph[i] = _graph[i + 1]
		_graph[GRAPH_SAMPLES - 1] = (st - _prev_song_time) * 1000.0
		_prev_song_time = st
	queue_redraw()


func _draw() -> void:
	if chart == null or conductor == null:
		return
	var left := lane_left()
	var width := LANE_W * LANES
	var st := conductor.song_time()
	var vt := st + Settings.visual_offset
	var pps := PX_PER_SEC * Settings.scroll_speed

	_draw_lanes(left)
	_draw_preroll(st)
	_draw_notes(left, vt, pps, st)
	_draw_hull_line(left, width)
	_draw_receptors(left)
	_draw_indicator(left)
	if show_spike_readout:
		_draw_spike_readout()


func _draw_lanes(left: float) -> void:
	for i in range(LANES + 1):
		var x := left + i * LANE_W
		var edge := i == 0 or i == LANES
		draw_line(Vector2(x, 0), Vector2(x, SCREEN_H), Palette.ACCENT if edge else Palette.DIM, 2.0)
	for lane in range(LANES):
		var label := Settings.bindings.display_name(LaneInput.ACTIONS[lane], &"keyboard")
		draw_string(Palette.font(), Vector2(left + lane * LANE_W, LABEL_Y + 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, LANE_W, Palette.SIZE_LABEL, Palette.lane_color(lane))


## Two beat pips above the highway center during the lead-in (no numerals).
func _draw_preroll(st: float) -> void:
	if st >= 0.0 or chart.tempo_map.is_empty():
		return
	var spb := 60.0 / float(chart.tempo_map[0]["bpm"])
	var cx := lane_left() + LANE_W * LANES * 0.5
	for k in range(PREROLL_BEATS):
		var p := Vector2(cx + (k - 0.5) * 48.0, 64.0)
		var beat_time := -float(PREROLL_BEATS - k) * spb
		if st >= beat_time:
			draw_circle(p, 12.0, Palette.ACCENT)
		else:
			draw_arc(p, 11.0, 0.0, TAU, 24, Palette.DIM, 2.0, true)


func _draw_notes(left: float, vt: float, pps: float, st: float) -> void:
	var notes := chart.notes
	# Moving window: skip notes whose head AND tail are already below the screen.
	var below_time := vt - (SCREEN_H + NoteShape.SIZE - HULL_Y) / pps
	while _first_visible < notes.size() and float(notes[_first_visible]["time"]) + float(notes[_first_visible]["duration"]) < below_time:
		_first_visible += 1
	var i := _first_visible
	while i < notes.size():
		var n: Dictionary = notes[i]
		var y := HULL_Y - (float(n["time"]) - vt) * pps
		if y < -NoteShape.SIZE:
			break
		var state := _state[i]
		if state != S_HIT:
			var lane: int = n["lane"]
			var cx := left + (lane + 0.5) * LANE_W
			var dur: float = n["duration"]
			var lane_col := Palette.lane_color(lane)
			var ready := state == S_PENDING and note_is_ready(float(n["time"]) - st, _good_window)
			if dur > 0.0:
				_draw_sustain(cx, y, y - dur * pps, state, lane_col, ready)
			if state == S_PENDING or state == S_MISSED:
				var kind := NoteShape.kind_for_lane(lane)
				var col := lane_col
				if state == S_MISSED:
					col = Palette.alpha(lane_col, 0.25)
				elif not ready:
					col = Palette.dim(lane_col)
				else:
					NoteShape.draw_outline(self, kind, Vector2(cx, y), NoteShape.SIZE + 12.0, Palette.alpha(lane_col, 0.35), 6.0)
				NoteShape.draw(self, kind, Vector2(cx, y), NoteShape.SIZE, col)
				if state == S_MISSED:
					_draw_x(Vector2(cx, y), Palette.DESTRUCTIVE)
		i += 1


func _draw_sustain(cx: float, head_y: float, tail_y: float, state: int, lane_col: Color, ready: bool) -> void:
	var bottom := head_y
	if state == S_HOLDING:
		bottom = minf(head_y, HULL_Y)  # consumed below the hull line
	var top := maxf(tail_y, -NoteShape.SIZE)
	if bottom <= top:
		return
	var base := lane_col if (ready or state == S_HOLDING) else Palette.dim(lane_col)
	var fill_a := 0.5
	var edge_a := 1.0
	if state == S_HOLDING:
		fill_a = 1.0
	elif state == S_MISSED or state == S_EARLY_RELEASE:
		fill_a = 0.25
		edge_a = 0.25
	var r := Rect2(cx - SUSTAIN_W * 0.5, top, SUSTAIN_W, bottom - top)
	draw_rect(r, Palette.alpha(base, fill_a))
	draw_rect(r, Palette.alpha(base, edge_a), false, 2.0)  # flat cap = top edge


func _draw_x(c: Vector2, col: Color) -> void:
	var h := 20.0
	draw_line(c + Vector2(-h, -h), c + Vector2(h, h), col, 4.0)
	draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, 4.0)


func _draw_hull_line(left: float, width: float) -> void:
	draw_line(Vector2(left - 32.0, HULL_Y), Vector2(left + width + 32.0, HULL_Y), Palette.ACCENT, 4.0)
	# Thin glow on the hull line segment of every held lane.
	for lane in range(LANES):
		if _holding[lane] >= 0:
			draw_rect(Rect2(left + lane * LANE_W, HULL_Y - 6.0, LANE_W, 12.0), Palette.alpha(Palette.ACCENT, 0.5))


## Outline-only receptor per lane at the exact hit position; pulses on key press.
func _draw_receptors(left: float) -> void:
	var now := Time.get_ticks_usec()
	for lane in range(LANES):
		var col := Palette.lane_color(lane)
		var cx := left + (lane + 0.5) * LANE_W
		var kind := NoteShape.kind_for_lane(lane)
		var center := Vector2(cx, HULL_Y)
		var tick := _press_ticks[lane]
		var p := receptor_pulse(now - tick if tick >= 0 else RECEPTOR_PULSE_USEC, Settings.reduce_motion)
		var size := NoteShape.SIZE * float(p["scale"])
		var pulse_fill: float = p["fill_alpha"]
		var fill_a := pulse_fill
		if _holding[lane] >= 0:
			fill_a = maxf(fill_a, 0.25)
		if fill_a > 0.0:
			# NoteShape.draw fills at 25% of the color alpha, so scale up to reach fill_a.
			NoteShape.draw(self, kind, center, size, Palette.alpha(col, fill_a * 4.0))
		if pulse_fill > 0.0:
			NoteShape.draw_outline(self, kind, center, size + 12.0, Palette.alpha(col, 0.35), 6.0)
		NoteShape.draw_outline(self, kind, center, size, Palette.alpha(col, float(p["outline_alpha"])))


## "EARLY 12 MS" / "LATE 8 MS" with a left/right arrow glyph, fading over 400 ms.
func _draw_indicator(left: float) -> void:
	if not Settings.early_late_indicator or not _show_indicator:
		return
	var age := Time.get_ticks_usec() - _last_ticks
	if age >= INDICATOR_FADE_USEC:
		return
	var a := 1.0 - float(age) / INDICATOR_FADE_USEC
	var col := Palette.alpha(Palette.TEXT, a)
	var early := _last_error_ms < 0.0
	var txt := "%s %d MS" % ["EARLY" if early else "LATE", int(round(absf(_last_error_ms)))]
	var font := Palette.font()
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL)
	var cx := left + LANE_W * LANES * 0.5
	var base_y := INDICATOR_Y
	var gap := 12.0
	var arrow_w := 14.0
	var x0 := cx - (arrow_w + gap + sz.x) * 0.5
	var ay := base_y - 7.0
	var tri: PackedVector2Array
	if early:
		tri = PackedVector2Array([Vector2(x0, ay), Vector2(x0 + arrow_w, ay - 8.0), Vector2(x0 + arrow_w, ay + 8.0)])
	else:
		tri = PackedVector2Array([Vector2(x0 + arrow_w, ay), Vector2(x0, ay - 8.0), Vector2(x0, ay + 8.0)])
	draw_colored_polygon(tri, col)
	draw_string(font, Vector2(x0 + arrow_w + gap, base_y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, col)


func _draw_spike_readout() -> void:
	var font := Palette.font()
	var x := 1568.0
	var y := 120.0
	var st := conductor.song_time()
	draw_string(font, Vector2(x, y + 20.0), "song_time %.3f" % st, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT)
	draw_string(font, Vector2(x, y + 44.0), "raw_pos   %.3f" % conductor.raw_position(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT)
	draw_string(font, Vector2(x, y + 68.0), "latency   %.1f ms  audio_valid %s" % [conductor.output_latency() * 1000.0, str(conductor.audio_valid())], HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT)
	draw_string(font, Vector2(x, y + 92.0), "dt/frame (ms), 0-40", HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT)
	var gx := x
	var gy := y + 104.0
	var gw := 320.0
	var gh := 96.0
	draw_rect(Rect2(gx, gy, gw, gh), Palette.DIM, false, 2.0)
	var pts := PackedVector2Array()
	for i in range(GRAPH_SAMPLES):
		var v := clampf(_graph[i], 0.0, 40.0) / 40.0
		pts.append(Vector2(gx + gw * i / (GRAPH_SAMPLES - 1), gy + gh - v * gh))
	draw_polyline(pts, Palette.ACCENT, 2.0)
