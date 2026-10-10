class_name Highway
extends Control
## HighwaySurface (02.2 UI-SPEC 7.4 rows 1..8) and the board's state owner. A pure function of
## song_time + visual_offset + scroll speed (D-25): all geometry comes from Trench (depth is
## linear in time, only the projection is non-linear). Judgment uses raw song_time; only
## drawing adds the visual offset. Draws, back to front: four filled translucent lane strips,
## separators and teal outer rails, the hit line with lane ticks, sustains, chord bars and the
## glass receptor pads. Gems, missed remnants and lane numbers are drawn by HighwayNotes (a
## layer above FxLayer and Feedback) through draw_notes_into() / draw_halos_into(), from the
## visible window this node computes once per frame in _process. Colours from Palette only.
## The Phase 1 clock-smoothness spike readout is kept behind `show_spike_readout`.

const LANES := 4
const RECEPTOR_PULSE_USEC := 120000
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const GRAPH_SAMPLES := 128
const INDICATOR_FADE_USEC := 400000
const INDICATOR_BASE_Y := 1004.0
const RIBBON_SAMPLES := 10
const RECEPTOR_R := 41.0
const RECEPTOR_INNER_R := 30.0
const GHOST_FADE_SEC := 0.25

## Surface (row 1): strips run from the far end (d = 1) to y 1000; the last 50 px fade out.
const STRIP_FADE_Y := 950.0
const STRIP_END_Y := 1000.0
## Extra strip tint / rail glow at full intro brightness (cable_bright = 1).
const BRIGHT_TINT := 0.06
const BRIGHT_RAIL_GLOW := 0.35
## Separators and rails (row 3).
const SEPARATOR_W := 1.5
const SEPARATOR_ALPHA := 0.10
const RAIL_W := 2.0
const RAIL_ALPHA := 0.60
const RAIL_GLOW_W := 18.0
const RAIL_GLOW_ALPHA := 0.20
## Hit line (row 5).
const HIT_LINE_W := 4.0
const HIT_GLOW_W := 12.0
const HIT_GLOW_ALPHA := 0.12
const HIT_TICK_H := 12.0
const HIT_TICK_W := 2.0
const HIT_TICK_ALPHA := 0.60
## Receptors (row 8, UI-SPEC 4.16).
const RECEPTOR_GLASS_ALPHA := 0.70
const RECEPTOR_OUTLINE_ALPHA := 0.75
const RECEPTOR_INNER_ALPHA := 0.35
const RECEPTOR_PRESS_FILL := 0.40
const RECEPTOR_HELD_FILL := 0.25
const RECEPTOR_SQUASH := Vector2(1.12, 0.88)
const LANE_LABEL_ALPHA := 0.90

const S_PENDING := 0
const S_HIT := 1
const S_MISSED := 2
const S_HOLDING := 3
const S_EARLY_RELEASE := 4

var chart: ChartData
var conductor: Conductor
var show_spike_readout: bool = false
## Streak tier multiplier 1..4 (plan 09 wires it); picks the lane tint from Palette.TIER_TINT.
var tier_multiplier: int = 1

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
var _quad := PackedVector2Array()
var _edge_l := PackedVector2Array()
var _edge_r := PackedVector2Array()
var _vis := PackedInt32Array()
var _ring := PackedVector2Array()
var _lane_labels := PackedStringArray(["", "", "", ""])
## Frame snapshot shared by both layers (set in _process by _update_window).
var _st: float = 0.0
var _vt: float = 0.0
var _approach: float = 1.5
## Strip geometry cache, rebuilt only when the reveal, tint or brightness changes.
var _strip_polys: Array[PackedVector2Array] = []
var _strip_cols: Array[PackedColorArray] = []
var _strip_key := Vector3(-1.0, -1.0, -1.0)

## Intro tuning (GogglesIntro drives these; defaults reproduce normal play).
var cable_grow: float = 1.0  # fraction of the strip length revealed, from the far end inward
var cable_bright: float = 0.0  # extra strip/rail brightness 0..1 (0 = normal play look)
var receptor_alpha: float = 1.0  # multiplies receptor and lane-number alpha
## False until the conductor lead-in starts: before that the idle clock reads song_time 0 and
## early notes would sit on the board, then jump away when the lead-in begins (WR-03).
var notes_enabled: bool = true


## True while a note is inside the Good window (inclusive); NaN/inf are never ready.
static func note_is_ready(dt: float, good_window: float) -> bool:
	return is_finite(dt) and absf(dt) <= good_window


## Receptor pulse on lane press: 120 ms ease-out, scale 1.0 -> 1.2 -> 1.0 (legacy scalar; the
## pad itself uses receptor_squash). Fill/outline alphas drive the press brightness.
static func receptor_pulse(age_usec: int, reduce_motion: bool) -> Dictionary:
	var pulsing := age_usec >= 0 and age_usec < RECEPTOR_PULSE_USEC
	var scale := 1.0
	if pulsing and not reduce_motion:
		var t := float(age_usec) / RECEPTOR_PULSE_USEC
		scale = 1.0 + 0.2 * sin(PI * pow(t, 0.5))
	return {"scale": scale, "fill_alpha": 0.40 if pulsing else 0.0, "outline_alpha": 1.0 if pulsing else 0.70}


## Receptor squash (UI-SPEC 4.16): (1.12, 0.88) at press, back to (1, 1) over DUR_FAST with a
## cubic ease-out. Reduce motion: always (1, 1) (brightness change only).
static func receptor_squash(age_usec: int, reduce_motion: bool) -> Vector2:
	var dur := Palette.DUR_FAST * 1000000.0
	if reduce_motion or age_usec < 0 or float(age_usec) >= dur:
		return Vector2.ONE
	var t := float(age_usec) / dur
	return RECEPTOR_SQUASH.lerp(Vector2.ONE, 1.0 - pow(1.0 - t, 3.0))


## Current squash of a lane's pad. now_usec < 0 reads the clock.
func receptor_scale(lane: int, now_usec: int = -1) -> Vector2:
	if lane < 0 or lane >= LANES or _press_ticks[lane] < 0:
		return Vector2.ONE
	var now := Time.get_ticks_usec() if now_usec < 0 else now_usec
	return receptor_squash(now - _press_ticks[lane], Settings.reduce_motion)


## Lane strip tint alpha for the current tier (x1 = 7%), plus the intro brightness boost.
func strip_tint_alpha() -> float:
	return Palette.TIER_TINT[clampi(tier_multiplier - 1, 0, Palette.TIER_TINT.size() - 1)] \
		+ BRIGHT_TINT * clampf(cable_bright, 0.0, 1.0)


## Drawable depth range (x = start, y = end) of a sustain ribbon. The start is clamped to the
## projection's drawable range so a long-past head cannot yield zero-area quads (WR-01).
## Empty when y <= x + 0.001.
static func ribbon_span(d_head: float, d_tail: float, holding: bool) -> Vector2:
	var d0 := maxf(d_head, 0.0) if holding else maxf(d_head, Trench.D_MIN)  # held: consumed at the ring
	return Vector2(d0, minf(d_tail, Trench.D_FAR))


## Screen x of lane offset f at screen y (lane edges are straight lines in the projection).
static func edge_x(f: float, y: float) -> float:
	var n := (y - Trench.VP.y) / Trench.TRAVEL
	return Trench.VP.x + f * Trench.LANE_SPREAD * (Trench.FAR_SPREAD + (1.0 - Trench.FAR_SPREAD) * n)


func _ready() -> void:
	UiKit.register_fx(self)
	_refresh_labels()


func setup(p_chart: ChartData, p_conductor: Conductor, p_cfg: JudgeConfig = null) -> void:
	chart = p_chart
	conductor = p_conductor
	_good_window = (p_cfg if p_cfg != null else JudgeConfig.new()).good_window
	_press_ticks = [-1, -1, -1, -1]
	_state.resize(chart.notes.size())
	_state.fill(S_PENDING)
	_holding = [-1, -1, -1, -1]
	_first_visible = 0
	_vis.clear()
	_quad.resize(4)
	_edge_l.resize(RIBBON_SAMPLES + 1)
	_edge_r.resize(RIBBON_SAMPLES + 1)
	_graph.resize(GRAPH_SAMPLES)
	_graph.fill(0.0)
	_refresh_labels()


## Effect contract: re-read settings (lane labels follow rebinds; strips are re-tinted).
func apply_effect_settings() -> void:
	_refresh_labels()
	_strip_key = Vector3(-1.0, -1.0, -1.0)
	queue_redraw()


func effect_counts() -> Dictionary:
	var low: bool = Settings.low_effects
	return {
		"hit_line_glow": not low,
		"note_halos": not low,
		"receptor_glow": not low,
		"receptor_squash": not Settings.reduce_motion,
	}


func _refresh_labels() -> void:
	for lane in range(LANES):
		_lane_labels[lane] = Settings.bindings.display_name(LaneInput.ACTIONS[lane], &"keyboard")


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


## Connect to LaneInput.lane_pressed; any press (hit or not) lights and squashes the pad.
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
	_update_window()
	queue_redraw()


## Snapshot the clock and the visible note window (shared with HighwayNotes this frame).
func _update_window() -> void:
	if chart == null or conductor == null:
		return
	_st = conductor.song_time()
	_vt = _st + Settings.visual_offset
	_approach = Trench.approach_for(Settings.scroll_speed)
	var notes := chart.notes
	# Moving window: skip notes whose head AND tail are well past the line (and the ghost fade).
	var past_time := _vt - 0.06 * _approach - GHOST_FADE_SEC - 0.1
	while _first_visible < notes.size() and float(notes[_first_visible]["time"]) + float(notes[_first_visible]["duration"]) < past_time:
		_first_visible += 1
	_vis.clear()
	var i := _first_visible
	while i < notes.size():
		var n: Dictionary = notes[i]
		if Trench.depth_for(float(n["time"]), _vt, _approach) > Trench.D_FAR:
			break
		if _state[i] != S_HIT:
			_vis.append(i)
		i += 1


func _draw() -> void:
	if chart == null or conductor == null:
		return
	var phase := BeatClock.phase(_st, chart.tempo_map)
	_draw_surface()
	_draw_rails()
	_draw_hit_line(phase)
	if notes_enabled:
		_draw_sustains()
		_draw_chord_bars()
	_draw_receptors()
	_draw_indicator()
	if show_spike_readout:
		_draw_spike_readout()


# ---- Row 1: lane strips ------------------------------------------------------------------

func _strip_end_y() -> float:
	return lerpf(Trench.VP.y, STRIP_END_Y, clampf(cable_grow, 0.0, 1.0))


func _rebuild_strips() -> void:
	var tint := strip_tint_alpha()
	var key := Vector3(clampf(cable_grow, 0.0, 1.0), tint, Palette.HIGHWAY_ALPHA)
	if key == _strip_key:
		return
	_strip_key = key
	_strip_polys.clear()
	_strip_cols.clear()
	if key.x <= 0.0:
		return
	_add_strip(-2.0, 2.0, Palette.alpha(Palette.HIGHWAY_BASE, Palette.HIGHWAY_ALPHA))
	for lane in range(LANES):
		var f := Trench.lane_f(lane)
		_add_strip(f - 0.5, f + 0.5, Palette.alpha(Palette.lane_color(lane), tint))


## One strip between lane offsets f0..f1: a solid quad to y 950, then a quad fading to 0 at 1000.
func _add_strip(f0: float, f1: float, col: Color) -> void:
	var y_top := Trench.VP.y
	var y_end := _strip_end_y()
	var y_solid := minf(y_end, STRIP_FADE_Y)
	_strip_polys.append(PackedVector2Array([
		Vector2(edge_x(f0, y_top), y_top), Vector2(edge_x(f1, y_top), y_top),
		Vector2(edge_x(f1, y_solid), y_solid), Vector2(edge_x(f0, y_solid), y_solid)]))
	_strip_cols.append(PackedColorArray([col, col, col, col]))
	if y_end > STRIP_FADE_Y:
		var a_end := col.a * (1.0 - (y_end - STRIP_FADE_Y) / (STRIP_END_Y - STRIP_FADE_Y))
		var c_end := Palette.alpha(col, a_end)
		_strip_polys.append(PackedVector2Array([
			Vector2(edge_x(f0, STRIP_FADE_Y), STRIP_FADE_Y), Vector2(edge_x(f1, STRIP_FADE_Y), STRIP_FADE_Y),
			Vector2(edge_x(f1, y_end), y_end), Vector2(edge_x(f0, y_end), y_end)]))
		_strip_cols.append(PackedColorArray([col, col, c_end, c_end]))


func _draw_surface() -> void:
	_rebuild_strips()
	for k in range(_strip_polys.size()):
		draw_polygon(_strip_polys[k], _strip_cols[k])


# ---- Row 3: separators and outer rails ---------------------------------------------------

func _draw_rails() -> void:
	if cable_grow <= 0.0:
		return
	var y0 := Trench.VP.y
	var y1 := _strip_end_y()
	var sep := Palette.alpha(Palette.TEXT_HI, SEPARATOR_ALPHA)
	for f in [-1.0, 0.0, 1.0]:
		draw_line(Vector2(edge_x(f, y0), y0), Vector2(edge_x(f, y1), y1), sep, SEPARATOR_W, true)
	var glow_a := RAIL_GLOW_ALPHA * BRIGHT_RAIL_GLOW * clampf(cable_bright, 0.0, 1.0)
	for f in [-2.0, 2.0]:
		var a := Vector2(edge_x(f, y0), y0)
		var b := Vector2(edge_x(f, y1), y1)
		if glow_a > 0.0 and not Settings.low_effects:
			draw_line(a, b, Palette.alpha(Palette.SONAR, glow_a), RAIL_GLOW_W, true)
		draw_line(a, b, Palette.alpha(Palette.SONAR, RAIL_ALPHA), RAIL_W, true)


# ---- Row 5: hit line ---------------------------------------------------------------------

func _draw_hit_line(phase: float) -> void:
	var ring := Trench.line_points()
	var a := 0.75 if Settings.reduce_motion else 0.55 + 0.4 * BeatClock.pulse(phase)
	if not Settings.low_effects:
		draw_line(ring[0], ring[1], Palette.alpha(Palette.SONAR, HIT_GLOW_ALPHA), HIT_GLOW_W, true)
	draw_line(ring[0], ring[1], Palette.alpha(Palette.SONAR_PALE, a), HIT_LINE_W, true)
	var tick := Palette.alpha(Palette.SONAR_PALE, HIT_TICK_ALPHA)
	var hh := HIT_TICK_H * 0.5
	for f in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		var p := Trench.point(f, 0.0)
		draw_line(Vector2(p.x, p.y - hh), Vector2(p.x, p.y + hh), tick, HIT_TICK_W)


# ---- Row 6: sustains ---------------------------------------------------------------------

func _draw_sustains() -> void:
	var notes := chart.notes
	for k in range(_vis.size()):
		var idx := _vis[k]
		var n: Dictionary = notes[idx]
		var dur: float = n["duration"]
		if dur <= 0.0:
			continue
		var d_head := Trench.depth_for(float(n["time"]), _vt, _approach)
		var d_tail := Trench.depth_for(float(n["time"]) + dur, _vt, _approach)
		_draw_sustain(int(n["lane"]), d_head, d_tail, _state[idx])


## Ribbon along the lane centre between head and tail depth (restyled into a tube in plan 09).
func _draw_sustain(lane: int, d_head: float, d_tail: float, state: int) -> void:
	var span := ribbon_span(d_head, d_tail, state == S_HOLDING)
	var d0 := span.x
	var d1 := span.y
	if d1 <= d0 + 0.001:
		return
	var lane_col := Palette.lane_color(lane)
	var base := lane_col
	var fill_a := 0.45
	var edge_a := 0.9
	if state == S_HOLDING:
		fill_a = 0.8
		edge_a = 1.0
	elif state == S_MISSED or state == S_EARLY_RELEASE:
		base = Palette.TEXT_LO
		fill_a = 0.25
		edge_a = 0.25
	var f := Trench.lane_f(lane)
	for k in range(RIBBON_SAMPLES + 1):
		var d := lerpf(d0, d1, float(k) / float(RIBBON_SAMPLES))
		var c := Trench.point(f, d)
		var hw := 0.42 * Trench.note_radius(Trench.scale_at(d))
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


# ---- Row 7: chord bars -------------------------------------------------------------------

## Pending notes with equal time are joined behind the gems. Bars link consecutive chord
## members, so together they always span the leftmost to the rightmost gem.
func _draw_chord_bars() -> void:
	var notes := chart.notes
	var prev := -1
	for k in range(_vis.size()):
		var idx := _vis[k]
		if _state[idx] != S_PENDING:
			continue
		if prev >= 0 and absf(float(notes[idx]["time"]) - float(notes[prev]["time"])) < 0.001:
			var d := Trench.depth_for(float(notes[idx]["time"]), _vt, _approach)
			var a := Trench.point(Trench.lane_f(int(notes[prev]["lane"])), d)
			var b := Trench.point(Trench.lane_f(int(notes[idx]["lane"])), d)
			NotePainter.draw_chord_bar(self, a, b, Trench.scale_at(d))
		prev = idx


# ---- Row 8: receptor pads ----------------------------------------------------------------

func _draw_receptors() -> void:
	var ra := clampf(receptor_alpha, 0.0, 1.0)
	if ra <= 0.0:
		return
	var now := Time.get_ticks_usec()
	var low: bool = Settings.low_effects
	for lane in range(LANES):
		var col := Palette.lane_color(lane)
		var kind := NoteShape.kind_for_lane(lane)
		var center := Trench.hit_point(lane)
		var tick := _press_ticks[lane]
		var age := now - tick if tick >= 0 else RECEPTOR_PULSE_USEC
		var pressed := age >= 0 and age < RECEPTOR_PULSE_USEC
		var held := _holding[lane] >= 0
		var sq := receptor_scale(lane, now)
		var kx := RECEPTOR_R * sq.x
		var ky := RECEPTOR_R * sq.y
		if pressed and not low:
			var reach := Palette.GLOW_SM[0] * RECEPTOR_R
			draw_texture_rect(UiKit.glow_texture(), Rect2(center - Vector2(reach, reach), Vector2(2.0 * reach, 2.0 * reach)),
				false, Palette.alpha(col, Palette.GLOW_SM[1] * ra))
		var unit: PackedVector2Array = NotePainter.unit_shape(kind)["poly"]
		draw_set_transform(center, 0.0, Vector2(kx, ky))
		draw_colored_polygon(unit, Palette.alpha(Palette.ABYSS_900, RECEPTOR_GLASS_ALPHA * ra))
		var fill_a := RECEPTOR_PRESS_FILL if pressed else (RECEPTOR_HELD_FILL if held else 0.0)
		if fill_a > 0.0:
			draw_colored_polygon(unit, Palette.alpha(col, fill_a * ra))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var out_a := 1.0 if (pressed or held) else RECEPTOR_OUTLINE_ALPHA
		_pad_outline(kind, center, kx - 2.0, ky - 2.0, 4.0, Palette.alpha(col, out_a * ra))
		var inner := RECEPTOR_INNER_R / RECEPTOR_R
		_pad_outline(kind, center, kx * inner, ky * inner, 2.0, Palette.alpha(col, RECEPTOR_INNER_ALPHA * ra))


## Closed lane-shape outline scaled by (kx, ky) about center, into a reused buffer.
func _pad_outline(kind: int, center: Vector2, kx: float, ky: float, width: float, col: Color) -> void:
	var ring := NotePainter.outline_ring(kind)
	var n := ring.size()
	if _ring.size() != n:
		_ring.resize(n)
	for i in range(n):
		_ring[i] = center + Vector2(ring[i].x * kx, ring[i].y * ky)
	draw_polyline(_ring, col, width, true)


# ---- HighwayNotes layer (rows 9..11) -----------------------------------------------------

## Gems far to near, missed remnants and lane numbers, drawn into the HighwayNotes layer.
func draw_notes_into(ci: CanvasItem) -> void:
	if chart == null or conductor == null:
		return
	if notes_enabled:
		var notes := chart.notes
		for k in range(_vis.size() - 1, -1, -1):
			var idx := _vis[k]
			var state := _state[idx]
			if state != S_PENDING and state != S_MISSED:
				continue
			var n: Dictionary = notes[idx]
			var lane: int = n["lane"]
			var d := Trench.depth_for(float(n["time"]), _vt, _approach)
			var paint := NotePainter.STATE_FAR
			var fade := 1.0
			if state == S_MISSED:
				var past := (_vt - float(n["time"])) - 0.06 * _approach
				fade = 1.0 - clampf(past / GHOST_FADE_SEC, 0.0, 1.0)
				if fade <= 0.0:
					continue
				d = maxf(d, -0.06)
				paint = NotePainter.STATE_MISSED
			elif note_is_ready(float(n["time"]) - _st, _good_window):
				paint = NotePainter.STATE_READY
			var c := Trench.point(Trench.lane_f(lane), d)
			var r := Trench.note_radius(Trench.scale_at(d))
			NotePainter.draw_note(ci, int(n.get("type", NotePainter.NOTE_NORMAL)), lane, c, r, paint, _st, fade)
	_draw_lane_numbers(ci)


## Additive halos of ready gems (Full effects); drawn into HighwayNotes' Halos child.
func draw_halos_into(ci: CanvasItem) -> void:
	if chart == null or conductor == null or not notes_enabled or Settings.low_effects:
		return
	var notes := chart.notes
	for k in range(_vis.size() - 1, -1, -1):
		var idx := _vis[k]
		if _state[idx] != S_PENDING:
			continue
		var n: Dictionary = notes[idx]
		if not note_is_ready(float(n["time"]) - _st, _good_window):
			continue
		var lane: int = n["lane"]
		var d := Trench.depth_for(float(n["time"]), _vt, _approach)
		NotePainter.draw_halo(ci, lane, Trench.point(Trench.lane_f(lane), d), Trench.note_radius(Trench.scale_at(d)))


## Bound key under each receptor (Label 20, lane colour 90%), cached per settings change.
func _draw_lane_numbers(ci: CanvasItem) -> void:
	var ra := clampf(receptor_alpha, 0.0, 1.0)
	if ra <= 0.0:
		return
	var font := Palette.font()
	for lane in range(LANES):
		var center := Trench.hit_point(lane)
		ci.draw_string(font, Vector2(center.x - 50.0, center.y + 60.0), _lane_labels[lane], HORIZONTAL_ALIGNMENT_CENTER,
			100.0, Palette.SIZE_LABEL, Palette.alpha(Palette.lane_color(lane), LANE_LABEL_ALPHA * ra))


# ---- Early/late indicator and spike readout -------------------------------------------------

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
