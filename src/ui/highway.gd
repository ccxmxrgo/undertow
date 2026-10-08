class_name Highway
extends Control
## Single _draw() Trench Descent board: four cables descending from a glowing depth to a curved
## hit line. A pure function of song_time + visual_offset + scroll speed (D-25): all geometry
## comes from Trench (depth is linear in time, only the projection is non-linear). Judgment
## uses raw song_time; only drawing adds the visual offset. Colors come from Palette only.
## Lane flashes and floating text live in Feedback. The Phase 1 clock-smoothness spike
## readout is kept behind `show_spike_readout`.

const LANES := 4
const RECEPTOR_PULSE_USEC := 120000
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const GRAPH_SAMPLES := 128
const INDICATOR_FADE_USEC := 400000
const INDICATOR_BASE_Y := 1004.0
const CABLE_SAMPLES := 41
const RIBBON_SAMPLES := 10
const RECEPTOR_R := 41.0
const GHOST_FADE_SEC := 0.25
const CABLE_CORE := Color("0D1424")
const RING_COLOR := Color("A0FFF0")
const RING_GLOW := Color("05D9E8")

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
var _cable := PackedVector2Array()
var _quad := PackedVector2Array()
var _edge_l := PackedVector2Array()
var _edge_r := PackedVector2Array()
var _vis := PackedInt32Array()

## Intro tuning (plan 04 drives these; defaults reproduce normal play).
var cable_grow: float = 1.0  # fraction of the cable samples drawn, from the far end inward
var cable_bright: float = 0.0  # 0 = dim x0.50 line, 1 = full lane colour 3.6 px with glow
var receptor_alpha: float = 1.0  # multiplies receptor and lane-number alpha
## False until the conductor lead-in starts: before that the idle clock reads song_time 0 and
## early notes would sit on the cables, then jump away when the lead-in begins (WR-03).
var notes_enabled: bool = true


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


func setup(p_chart: ChartData, p_conductor: Conductor, p_cfg: JudgeConfig = null) -> void:
	chart = p_chart
	conductor = p_conductor
	_good_window = (p_cfg if p_cfg != null else JudgeConfig.new()).good_window
	_press_ticks = [-1, -1, -1, -1]
	_state.resize(chart.notes.size())
	_state.fill(S_PENDING)
	_holding = [-1, -1, -1, -1]
	_first_visible = 0
	_cable.resize(CABLE_SAMPLES)
	_quad.resize(4)
	_edge_l.resize(RIBBON_SAMPLES + 1)
	_edge_r.resize(RIBBON_SAMPLES + 1)
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
	var st := conductor.song_time()
	var vt := st + Settings.visual_offset
	var approach := Trench.approach_for(Settings.scroll_speed)
	var phase := BeatClock.phase(st, chart.tempo_map)
	var calm: bool = Settings.low_effects or Settings.reduce_motion

	_draw_cables(phase, calm)
	_draw_ring(phase)
	if notes_enabled:
		_draw_notes(st, vt, approach)
	_draw_receptors()
	_draw_indicator()
	if show_spike_readout:
		_draw_spike_readout()


func _draw_cables(phase: float, calm: bool) -> void:
	var count := clampi(int(ceil(float(CABLE_SAMPLES) * cable_grow)), 0, CABLE_SAMPLES)
	if count < 2:
		return
	var bright := clampf(cable_bright, 0.0, 1.0)
	var mult := lerpf(0.5, 1.0, bright)
	var width := lerpf(2.5, 3.6, bright)
	var pulse_d := 1.0 - phase
	for lane in range(LANES):
		var f := Trench.lane_f(lane)
		for i in range(CABLE_SAMPLES):
			_cable[i] = Trench.point(f, 1.0 - float(i) / float(CABLE_SAMPLES - 1))
		var col := Palette.lane_color(lane)
		var line := Color(col.r * mult, col.g * mult, col.b * mult, 1.0)
		var pts := _cable if count == CABLE_SAMPLES else _cable.slice(0, count)
		draw_polyline(pts, CABLE_CORE, 11.0, true)
		if bright > 0.0 and not Settings.low_effects:
			draw_polyline(pts, Palette.alpha(col, 0.25 * bright), 10.0, true)
		draw_polyline(pts, line, width, true)
		if not calm and cable_grow >= 1.0:
			var s := Trench.scale_at(pulse_d)
			draw_circle(Trench.point(f, pulse_d), (3.0 + 3.0 * s) * 1.2, Palette.alpha(col, 0.5 * phase))


func _draw_ring(phase: float) -> void:
	var ring := Trench.line_points()
	var a := 0.75 if Settings.reduce_motion else 0.55 + 0.4 * BeatClock.pulse(phase)
	if not Settings.low_effects:
		draw_polyline(ring, Palette.alpha(RING_GLOW, 0.12), 12.0, true)
	draw_polyline(ring, Palette.alpha(RING_COLOR, a), 4.0, true)


func _draw_notes(st: float, vt: float, approach: float) -> void:
	var notes := chart.notes
	# Moving window: skip notes whose head AND tail are well past the line (and the ghost fade).
	var past_time := vt - 0.06 * approach - GHOST_FADE_SEC - 0.1
	while _first_visible < notes.size() and float(notes[_first_visible]["time"]) + float(notes[_first_visible]["duration"]) < past_time:
		_first_visible += 1
	_vis.clear()
	var i := _first_visible
	while i < notes.size():
		var n: Dictionary = notes[i]
		var d := Trench.depth_for(float(n["time"]), vt, approach)
		if d > Trench.D_FAR:
			break
		if _state[i] != S_HIT:
			_vis.append(i)
		i += 1
	# Sustains first (they sit behind note heads), then heads far to near.
	for k in range(_vis.size()):
		var idx := _vis[k]
		var n: Dictionary = notes[idx]
		var dur: float = n["duration"]
		if dur > 0.0:
			var lane: int = n["lane"]
			var ready := _state[idx] == S_PENDING and note_is_ready(float(n["time"]) - st, _good_window)
			var d_head := Trench.depth_for(float(n["time"]), vt, approach)
			var d_tail := Trench.depth_for(float(n["time"]) + dur, vt, approach)
			_draw_sustain(lane, d_head, d_tail, _state[idx], ready)
	for k in range(_vis.size() - 1, -1, -1):
		var idx := _vis[k]
		var n: Dictionary = notes[idx]
		var state := _state[idx]
		if state != S_PENDING and state != S_MISSED:
			continue
		var lane: int = n["lane"]
		var lane_col := Palette.lane_color(lane)
		var d := Trench.depth_for(float(n["time"]), vt, approach)
		var kind := NoteShape.kind_for_lane(lane)
		var col := lane_col
		var ghost := 1.0
		if state == S_MISSED:
			var held := maxf(d, -0.06)
			var past := (vt - float(n["time"])) - 0.06 * approach
			ghost = 1.0 - clampf(past / GHOST_FADE_SEC, 0.0, 1.0)
			if ghost <= 0.0:
				continue
			d = held
			col = Palette.alpha(lane_col, 0.25 * ghost)
		var s := Trench.scale_at(d)
		var c := Trench.point(Trench.lane_f(lane), d)
		var r := Trench.note_radius(s)
		var outline := 2.0 + 2.0 * s
		var ready := state == S_PENDING and note_is_ready(float(n["time"]) - st, _good_window)
		if state == S_PENDING:
			if ready:
				NoteShape.draw_outline(self, kind, c, 2.0 * r + 12.0, Palette.alpha(lane_col, 0.35), 6.0)
				if not Settings.low_effects:
					NoteShape.draw_outline(self, kind, c, 2.0 * r + 16.0, Palette.alpha(lane_col, 0.12), 8.0)
					NoteShape.draw_outline(self, kind, c, 2.0 * r + 32.0, Palette.alpha(lane_col, 0.06), 8.0)
			else:
				col = Palette.dim(lane_col)
		NoteShape.draw(self, kind, c, 2.0 * r, col, outline)
		if state == S_MISSED:
			_draw_x(c, r * 0.5, Palette.alpha(Palette.DESTRUCTIVE, ghost))


## Drawable depth range (x = start, y = end) of a sustain ribbon. The start is clamped to the
## projection's drawable range so a long-past head cannot yield zero-area quads (WR-01).
## Empty when y <= x + 0.001.
static func ribbon_span(d_head: float, d_tail: float, holding: bool) -> Vector2:
	var d0 := maxf(d_head, 0.0) if holding else maxf(d_head, Trench.D_MIN)  # held: consumed at the ring
	return Vector2(d0, minf(d_tail, Trench.D_FAR))


## Ribbon along the cable between head and tail depth.
func _draw_sustain(lane: int, d_head: float, d_tail: float, state: int, ready: bool) -> void:
	var span := ribbon_span(d_head, d_tail, state == S_HOLDING)
	var d0 := span.x
	var d1 := span.y
	if d1 <= d0 + 0.001:
		return
	var lane_col := Palette.lane_color(lane)
	var base := lane_col if (ready or state == S_HOLDING) else Palette.dim(lane_col)
	var fill_a := 0.5
	var edge_a := 1.0
	if state == S_HOLDING:
		fill_a = 0.8
	elif state == S_MISSED or state == S_EARLY_RELEASE:
		fill_a = 0.25
		edge_a = 0.25
	var f := Trench.lane_f(lane)
	for k in range(RIBBON_SAMPLES + 1):
		var d := lerpf(d0, d1, float(k) / float(RIBBON_SAMPLES))
		var c := Trench.point(f, d)
		var hw := 0.4 * Trench.note_radius(Trench.scale_at(d))
		_edge_l[k] = Vector2(c.x - hw, c.y)
		_edge_r[k] = Vector2(c.x + hw, c.y)
	var fill := Palette.alpha(base, fill_a)
	for k in range(RIBBON_SAMPLES):
		_quad[0] = _edge_l[k]
		_quad[1] = _edge_r[k]
		_quad[2] = _edge_r[k + 1]
		_quad[3] = _edge_l[k + 1]
		draw_colored_polygon(_quad, fill)
	var edge := Palette.alpha(base, edge_a)
	draw_polyline(_edge_l, edge, 2.0, true)
	draw_polyline(_edge_r, edge, 2.0, true)
	if state == S_HOLDING and not Settings.low_effects:
		draw_circle(Trench.hit_point(lane), RECEPTOR_R * 0.9, Palette.alpha(lane_col, 0.18))


func _draw_x(c: Vector2, h: float, col: Color) -> void:
	draw_line(c + Vector2(-h, -h), c + Vector2(h, h), col, 4.0)
	draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, 4.0)


## Outline-only receptor per lane at the exact hit point; pulses on key press.
func _draw_receptors() -> void:
	var now := Time.get_ticks_usec()
	var ra := clampf(receptor_alpha, 0.0, 1.0)
	if ra <= 0.0:
		return
	for lane in range(LANES):
		var col := Palette.lane_color(lane)
		var kind := NoteShape.kind_for_lane(lane)
		var center := Trench.hit_point(lane)
		var tick := _press_ticks[lane]
		var p := receptor_pulse(now - tick if tick >= 0 else RECEPTOR_PULSE_USEC, Settings.reduce_motion)
		var size := 2.0 * RECEPTOR_R * float(p["scale"])
		var pulse_fill: float = p["fill_alpha"]
		var fill_a := pulse_fill
		if _holding[lane] >= 0:
			fill_a = maxf(fill_a, 0.25)
		if fill_a > 0.0:
			# NoteShape.draw fills at 25% of the color alpha, so scale up to reach fill_a.
			NoteShape.draw(self, kind, center, size, Palette.alpha(col, minf(fill_a * 4.0, 1.0) * ra))
		if pulse_fill > 0.0:
			NoteShape.draw_outline(self, kind, center, size + 12.0, Palette.alpha(col, 0.35 * ra), 6.0)
		NoteShape.draw_outline(self, kind, center, size, Palette.alpha(col, float(p["outline_alpha"]) * ra), 4.0)
		var label := Settings.bindings.display_name(LaneInput.ACTIONS[lane], &"keyboard")
		draw_string(Palette.font(), Vector2(center.x - 50.0, center.y + 60.0), label, HORIZONTAL_ALIGNMENT_CENTER, 100.0, Palette.SIZE_LABEL, Palette.alpha(col, 0.9 * ra))


## "EARLY 12 MS" / "LATE 8 MS" with a left/right arrow glyph, fading over 400 ms.
func _draw_indicator() -> void:
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
	var cx := Trench.VP.x
	var base_y := INDICATOR_BASE_Y
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
