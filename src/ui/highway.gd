class_name Highway
extends Control
## HighwaySurface (02.2 UI-SPEC 7.4 rows 1..8) and the board's state owner. A pure function of
## song_time + visual_offset + scroll speed (D-25): all geometry comes from Trench (depth is
## linear in time, only the projection is non-linear). Judgment uses raw song_time; only
## drawing adds the visual offset. Back to front: the lane-strip fill in the child Polygon2D
## "Surface" (show_behind_parent, carrying the sonar_surface CRT material in Full effects),
## then this node's own drawing: separators and teal outer rails (tier glow, x4 pale core and
## flowing MAX dashes), beat and bar lines from the tempo map and time signatures, the hit
## line with lane ticks, glowing sustain tubes, chord bars and the glass receptor pads. Gems,
## missed remnants and lane numbers are drawn by HighwayNotes (a layer above FxLayer and
## Feedback) through draw_notes_into() / draw_halos_into(), from the visible window this node
## computes once per frame in _process. Streak tiers follow set_tier (Gameplay connects
## HullScore.multiplier_changed). Colours from Palette only. The Phase 1 clock-smoothness
## spike readout is kept behind `show_spike_readout`.

## Emitted where a sustain hold starts or ends (FxLayer sustain sparks, 02.2-10).
signal hold_changed(lane: int, held: bool)

const LANES := 4
const RECEPTOR_PULSE_USEC := 120000
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const GRAPH_SAMPLES := 128
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
## Receptor light pool (lit glass): extra lane tint at the hit line, easing out by POOL_DEPTH.
## Peak strip tint stays <= 26% at x4, which keeps every gem/rim/receptor contrast pair.
const POOL_TINT := 0.12
const POOL_DEPTH := 0.40
## Surface rows (depths) for the per-vertex colour gradient; then y 950 and the strip end.
const STRIP_ROW_D: Array[float] = [1.0, 0.7, 0.5, 0.4, 0.3, 0.22, 0.15, 0.09, 0.04, 0.0]
## sonar_surface CRT pass (row 2).
const SURFACE_SHADER := "res://shaders/sonar_surface.gdshader"
const SCAN_ALPHA := 0.06
const SWEEP_GAIN := 0.05
const AFTERGLOW_SEC := 0.40
const PHOSPHOR := 0.015
const LANE_EDGE_GAIN := 0.16
const LANE_EDGE_PX := 9.0
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
## Beat and bar lines (row 4, D-18). At most MAX_BEAT_LINES per frame (T-02.2-16).
const MAX_BEAT_LINES := 64
const BEAT_MARGIN_SEC := 0.05
const BEAT_LINE_ALPHA := 0.07
const BAR_LINE_ALPHA := 0.20
const BAR_GLOW_ALPHA := 0.06
const BAR_GLOW_EXTRA_W := 8.0
## Sustain tube (row 6).
const TUBE_HALF_W := 0.42  # x note radius
const TUBE_GLOW_HALF_W := 0.80
const TUBE_GLOW_ALPHA := 0.10
const TUBE_FILL := 0.45
const TUBE_PULSE := 0.30
const TUBE_DEAD_FILL := 0.25
const TUBE_CORE_ALPHA := 0.90
const TUBE_EDGE_ALPHA := 0.70
## Streak tiers (UI-SPEC 7.6). Glow strength per tier; the rail glow strokes scale with it.
const RAIL_GLOW_BY_TIER: Array[float] = [0.0, 0.35, 0.55, 0.80]
const RAIL_GLOW_NEAR_W := 8.0
const RAIL_GLOW_NEAR_ALPHA := 0.35
const MAX_RAIL_W := 3.0
const MAX_DASH_LEN := 24.0
const MAX_DASH_ALPHA := 0.70
const MAX_DASH_W := 9.0
const MAX_DASH_GLOW_ALPHA := 0.22
const MAX_DASH_CAP := 64
const MAX_RECEPTOR_HALO := 0.20
const MAX_FLASH_SEC := 0.20
const RAIL_FLASH_W := 26.0

const S_PENDING := 0
const S_HIT := 1
const S_MISSED := 2
const S_HOLDING := 3
const S_EARLY_RELEASE := 4

var chart: ChartData
var conductor: Conductor
var show_spike_readout: bool = false
## Streak tier 1..4 = the score multiplier (Gameplay connects HullScore.multiplier_changed to
## set_tier). Picks the lane tint, rail glow, MAX dashes and the receptor halo (UI-SPEC 7.6).
var tier: int = 1

var _first_visible: int = 0
var _state := PackedByteArray()
var _holding: Array[int] = [-1, -1, -1, -1]
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
## Row 1 + 2: the lane-strip fill lives in this child Polygon2D (show_behind_parent, so it is
## drawn before everything Highway draws itself and far below HighwayNotes). It carries the
## sonar_surface CRT material in Full effects and the plain vertex-coloured strips in Low.
var surface: Polygon2D
var _surface_mat: ShaderMaterial
var _rows := PackedFloat32Array()
## Bar phase snapshot for the sweep (set by _update_sweep).
var _bar_len_beats: float = 4.0
var _bar_start_beat: float = 0.0
## Strip geometry cache key, rebuilt only when the reveal, tint or brightness changes.
var _strip_key := Vector3(-1.0, -1.0, -1.0)
## Visible beat/bar lines this frame (preallocated, filled in place by _fill_beat_lines).
var _beat_d := PackedFloat32Array()
var _beat_t := PackedFloat32Array()
var _beat_bar := PackedByteArray()
var _beat_count: int = 0
## Tier drop fade (extras of _drop_from_tier fade over DUR_BASE) and the rail flash.
var _drop_ticks: int = -1
var _drop_from_tier: int = 1
var _flash_ticks: int = -1
var _flash_alpha: float = 0.0
var _flash_dur: float = MAX_FLASH_SEC

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
	return strip_tint() + BRIGHT_TINT * clampf(cable_bright, 0.0, 1.0)


## Lane tint of the current tier: Palette.TIER_TINT[tier - 1].
func strip_tint() -> float:
	return Palette.TIER_TINT[clampi(tier - 1, 0, Palette.TIER_TINT.size() - 1)]


## Sets the streak tier from the score multiplier (clamped 1..4). Rising is instant; entering
## x4 flashes the rails for 200 ms; dropping fades the old tier's extras over DUR_BASE.
func set_tier(m: int) -> void:
	var t := clampi(m, 1, 4)
	if t == tier:
		return
	if t < tier:
		_drop_from_tier = tier
		_drop_ticks = Time.get_ticks_usec()
	elif t == 4:
		flash_rails(1.0, MAX_FLASH_SEC)
	tier = t
	queue_redraw()


## Outer-rail glow strength of the current tier; 0 in Low effects (kept under Reduce motion).
func rail_glow_alpha() -> float:
	if Settings.low_effects:
		return 0.0
	return RAIL_GLOW_BY_TIER[clampi(tier - 1, 0, 3)]


## MAX rail dashes are drawn at x4 in every mode (static under Reduce motion).
func max_dashes_enabled() -> bool:
	return tier == 4


## Multiplier for the tier extras: 1 at a steady tier above x1, 1 -> 0 over DUR_BASE after a
## drop, 0 at a steady x1. now_usec < 0 reads the clock.
func extras_alpha(now_usec: int = -1) -> float:
	var fade := _fade_part(now_usec)
	if fade > 0.0:
		return fade
	return 1.0 if tier > 1 else 0.0


## Remaining fraction of the drop fade (0 when not fading).
func _fade_part(now_usec: int = -1) -> float:
	if _drop_ticks < 0:
		return 0.0
	var now := Time.get_ticks_usec() if now_usec < 0 else now_usec
	var age := float(now - _drop_ticks) / (Palette.DUR_BASE * 1000000.0)
	return clampf(1.0 - age, 0.0, 1.0)


## A short pale rail flash: x4 entry (200 ms) and streak milestones (plan 12).
func flash_rails(alpha: float, dur: float) -> void:
	_flash_alpha = clampf(alpha, 0.0, 1.0)
	_flash_dur = maxf(dur, 0.001)
	_flash_ticks = Time.get_ticks_usec()


## Current rail flash alpha, decaying linearly over its duration. now_usec < 0 reads the clock.
func rail_flash_alpha(now_usec: int = -1) -> float:
	if _flash_ticks < 0:
		return 0.0
	var now := Time.get_ticks_usec() if now_usec < 0 else now_usec
	var t := float(now - _flash_ticks) / (_flash_dur * 1000000.0)
	if t < 0.0 or t >= 1.0:
		return 0.0
	return _flash_alpha * (1.0 - t)


## Phase 0..1 of the half-beat dash cycle at visual time vt; frozen at 0 under Reduce motion.
func dash_phase(vt: float) -> float:
	if Settings.reduce_motion:
		return 0.0
	var tempo: Array = chart.tempo_map if chart != null else []
	return fposmod(BeatClock.beat_at(vt, tempo) * 2.0, 1.0)


## Sustain tube fill alpha: held pulses 0.45 -> 0.75 with the beat, early release / missed tails
## are TEXT_LO 25%.
static func sustain_fill_alpha(state: int, phase: float) -> float:
	if state == S_HOLDING:
		return TUBE_FILL + TUBE_PULSE * BeatClock.pulse(phase)
	if state == S_MISSED or state == S_EARLY_RELEASE:
		return TUBE_DEAD_FILL
	return TUBE_FILL


## Early release and missed tails lose the bright core line.
static func sustain_has_core(state: int) -> bool:
	return state != S_MISSED and state != S_EARLY_RELEASE


## Beat and bar lines with d in [0, 1] at visual time vt (tests and tools; allocates).
## Each entry {time, d, bar}.
func visible_beat_lines(vt: float, approach: float) -> Array:
	var out: Array = []
	var n := _fill_beat_lines(vt, approach)
	for i in range(n):
		out.append({"time": _beat_t[i], "d": _beat_d[i], "bar": _beat_bar[i] == 1})
	return out


## Fills the preallocated beat-line arrays from the chart's tempo map and time signatures
## (D-18); returns the count (at most MAX_BEAT_LINES).
func _fill_beat_lines(vt: float, approach: float) -> int:
	if _beat_d.size() != MAX_BEAT_LINES:
		_beat_d.resize(MAX_BEAT_LINES)
		_beat_t.resize(MAX_BEAT_LINES)
		_beat_bar.resize(MAX_BEAT_LINES)
	_beat_count = 0
	if chart == null:
		return 0
	var beats := BeatClock.beats_between(vt - BEAT_MARGIN_SEC, vt + approach, chart.tempo_map, chart.time_sigs)
	for b in beats:
		var t := float(b["time"])
		var d := Trench.depth_for(t, vt, approach)
		if d < 0.0 or d > 1.0:
			continue
		_beat_d[_beat_count] = d
		_beat_t[_beat_count] = t
		_beat_bar[_beat_count] = 1 if bool(b["bar"]) else 0
		_beat_count += 1
		if _beat_count >= MAX_BEAT_LINES:
			break
	return _beat_count


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


func _init() -> void:
	surface = Polygon2D.new()
	surface.name = "Surface"
	surface.show_behind_parent = true
	add_child(surface)


func _ready() -> void:
	UiKit.register_fx(self)
	_refresh_labels()
	_apply_surface_material()
	_rebuild_strips()


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
	_rebuild_strips()


## Effect contract: re-read settings (lane labels follow rebinds; strips are re-tinted).
func apply_effect_settings() -> void:
	_refresh_labels()
	_apply_surface_material()
	_strip_key = Vector3(-1.0, -1.0, -1.0)
	_rebuild_strips()
	queue_redraw()


func effect_counts() -> Dictionary:
	var low: bool = Settings.low_effects
	return {
		"hit_line_glow": not low,
		"note_halos": not low,
		"receptor_glow": not low,
		"receptor_squash": not Settings.reduce_motion,
		"crt": surface.material != null,
		"rail_glow": rail_glow_alpha(),
	}


func _refresh_labels() -> void:
	for lane in range(LANES):
		_lane_labels[lane] = Settings.bindings.display_name(LaneInput.ACTIONS[lane], &"keyboard")


func on_judged(lane: int, note_index: int, judgment: int, _error_s: float) -> void:
	if note_index < 0 or note_index >= _state.size():
		return
	if judgment == InputJudge.Judgment.MISS:
		_state[note_index] = S_MISSED
		return
	if float(chart.notes[note_index]["duration"]) > 0.0:
		_state[note_index] = S_HOLDING
		_holding[lane] = note_index
		hold_changed.emit(lane, true)
	else:
		_state[note_index] = S_HIT


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
	hold_changed.emit(lane, false)


func _process(_delta: float) -> void:
	_rebuild_strips()
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
	_fill_beat_lines(_vt, _approach)
	_update_sweep()


func _draw() -> void:
	if chart == null or conductor == null:
		return
	var phase := BeatClock.phase(_st, chart.tempo_map)
	_draw_rails()
	if notes_enabled:
		_draw_beat_lines()
	_draw_hit_line(phase)
	if notes_enabled:
		_draw_sustains(phase)
		_draw_chord_bars()
	_draw_receptors()
	if show_spike_readout:
		_draw_spike_readout()


# ---- Row 1 + 2: lane strips (Surface Polygon2D) and the sonar CRT pass ---------------------

func _strip_end_y() -> float:
	return lerpf(Trench.VP.y, STRIP_END_Y, clampf(cable_grow, 0.0, 1.0))


## Linear depth d at screen y on the board (inverse of the Trench projection).
static func depth_at_y(y: float) -> float:
	var smin := 1.0 / (1.0 + Trench.PERSPECTIVE)
	var n := (y - Trench.VP.y) / Trench.TRAVEL
	var s := smin + n * (1.0 - smin)
	return (1.0 / maxf(s, 0.001) - 1.0) / Trench.PERSPECTIVE


## Strip fill at screen y: HIGHWAY_BASE at 90% with the lane tint composited over it (tier tint,
## plus the receptor light pool rising toward the hit line), and the bottom 50 px fade.
func strip_color(lane: int, y: float, tint: float) -> Color:
	var d := depth_at_y(y)
	var pool := clampf(1.0 - d / POOL_DEPTH, 0.0, 1.0)
	var t := clampf(tint + POOL_TINT * pool * pool, 0.0, 1.0)
	var base_a := Palette.HIGHWAY_ALPHA
	var a := t + base_a * (1.0 - t)
	var col := Palette.alpha(Palette.HIGHWAY_BASE.lerp(Palette.lane_color(lane), t / maxf(a, 0.001)), a)
	if y > STRIP_FADE_Y:
		col.a *= clampf(1.0 - (y - STRIP_FADE_Y) / (STRIP_END_Y - STRIP_FADE_Y), 0.0, 1.0)
	return col


## Rebuilds the Surface polygons (4 strips x N row quads, per-vertex colours) when the reveal,
## tint or base alpha changed. Rows follow STRIP_ROW_D so the light pool gradient is smooth.
func _rebuild_strips() -> void:
	var tint := strip_tint_alpha()
	var key := Vector3(clampf(cable_grow, 0.0, 1.0), tint, Palette.HIGHWAY_ALPHA)
	if key == _strip_key:
		return
	_strip_key = key
	surface.visible = key.x > 0.0
	if key.x <= 0.0:
		surface.polygons = []
		surface.polygon = PackedVector2Array()
		surface.vertex_colors = PackedColorArray()
		return
	var y_end := _strip_end_y()
	_rows.clear()
	for d in STRIP_ROW_D:
		var y := Trench.point(0.0, d).y
		if y >= y_end - 0.5:
			break
		_rows.append(y)
	if STRIP_FADE_Y < y_end - 0.5 and STRIP_FADE_Y > _rows[_rows.size() - 1]:
		_rows.append(STRIP_FADE_Y)
	_rows.append(y_end)
	var nr := _rows.size()
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var polys: Array = []
	for lane in range(LANES):
		var f := Trench.lane_f(lane)
		var base := verts.size()
		for r in range(nr):
			var y := _rows[r]
			var col := strip_color(lane, y, tint)
			verts.append(Vector2(edge_x(f - 0.5, y), y))
			verts.append(Vector2(edge_x(f + 0.5, y), y))
			cols.append(col)
			cols.append(col)
		for r in range(nr - 1):
			var i := base + 2 * r
			polys.append(PackedInt32Array([i, i + 1, i + 3, i + 2]))
	surface.polygon = verts
	surface.vertex_colors = cols
	surface.polygons = polys


## Full effects: the sonar_surface material with every colour from Palette. Low effects: no
## material (plain strips). Reduce motion: scanlines kept, sweep off.
func _apply_surface_material() -> void:
	if Settings.low_effects:
		surface.material = null
		return
	if _surface_mat == null:
		_surface_mat = ShaderMaterial.new()
		_surface_mat.shader = load(SURFACE_SHADER) as Shader
	var m := _surface_mat
	m.set_shader_parameter("scan_color", Palette.alpha(Palette.ABYSS_900, SCAN_ALPHA))
	m.set_shader_parameter("sweep_color", Palette.SONAR)
	for lane in range(LANES):
		m.set_shader_parameter("lane_color_%d" % lane, Palette.lane_color(lane))
	m.set_shader_parameter("sweep_gain", SWEEP_GAIN)
	m.set_shader_parameter("phosphor", PHOSPHOR)
	m.set_shader_parameter("lane_edge_gain", LANE_EDGE_GAIN)
	m.set_shader_parameter("lane_edge_px", LANE_EDGE_PX)
	m.set_shader_parameter("vp_x", Trench.VP.x)
	m.set_shader_parameter("vp_y", Trench.VP.y)
	m.set_shader_parameter("travel", Trench.TRAVEL)
	m.set_shader_parameter("perspective", Trench.PERSPECTIVE)
	m.set_shader_parameter("lane_spread", Trench.LANE_SPREAD)
	m.set_shader_parameter("far_spread", Trench.FAR_SPREAD)
	m.set_shader_parameter("scanlines_on", true)
	m.set_shader_parameter("sweep_on", not Settings.reduce_motion)
	surface.material = m


## Fraction 0..1 through the current bar at song time t, honouring time signatures (D-18).
## Also caches the bar length (in quarter beats) for bar_seconds.
func bar_phase(t: float) -> float:
	var tempo: Array = chart.tempo_map if chart != null else []
	_bar_len_beats = 4.0
	_bar_start_beat = 0.0
	if chart != null:
		for ts in chart.time_sigs:
			if float(ts.get("time", 0.0)) > t:
				break
			_bar_start_beat = BeatClock.beat_at(float(ts.get("time", 0.0)), tempo)
			_bar_len_beats = float(clampi(int(ts.get("num", 4)), 1, 32)) * 4.0 / float(clampi(int(ts.get("den", 4)), 1, 32))
	return fposmod((BeatClock.beat_at(t, tempo) - _bar_start_beat) / _bar_len_beats, 1.0)


## Sweep: once per bar from the hit line (0) to the far end (1); the afterglow is 400 ms
## expressed in the same units (a fraction of the bar).
func _update_sweep() -> void:
	if surface.material == null or Settings.reduce_motion:
		return
	var ph := bar_phase(_vt)
	var bar_sec := _bar_len_beats * 60.0 / _bpm_at(_vt)
	_surface_mat.set_shader_parameter("sweep_pos", ph)
	_surface_mat.set_shader_parameter("afterglow", AFTERGLOW_SEC / maxf(bar_sec, 0.05))


# ---- Row 3: separators and outer rails ---------------------------------------------------

func _draw_rails() -> void:
	if cable_grow <= 0.0:
		return
	var y0 := Trench.VP.y
	var y1 := _strip_end_y()
	var sep := Palette.alpha(Palette.TEXT_HI, SEPARATOR_ALPHA)
	for f in [-1.0, 0.0, 1.0]:
		draw_line(Vector2(edge_x(f, y0), y0), Vector2(edge_x(f, y1), y1), sep, SEPARATOR_W, true)
	var now := Time.get_ticks_usec()
	var low: bool = Settings.low_effects
	var fade := _fade_part(now)
	# Glow strength: the tier's, the fading old tier's, or the intro boost, whichever is larger.
	var glow := rail_glow_alpha()
	if not low and fade > 0.0:
		glow = maxf(glow, RAIL_GLOW_BY_TIER[clampi(_drop_from_tier - 1, 0, 3)] * fade)
	glow = maxf(glow, BRIGHT_RAIL_GLOW * clampf(cable_bright, 0.0, 1.0))
	var max_a := 1.0 if tier == 4 else (fade if _drop_from_tier == 4 else 0.0)
	var flash := rail_flash_alpha(now)
	for f in [-2.0, 2.0]:
		var a := Vector2(edge_x(f, y0), y0)
		var b := Vector2(edge_x(f, y1), y1)
		if glow > 0.0 and not low:
			draw_line(a, b, Palette.alpha(Palette.SONAR, RAIL_GLOW_ALPHA * glow), RAIL_GLOW_W, true)
			draw_line(a, b, Palette.alpha(Palette.SONAR, RAIL_GLOW_NEAR_ALPHA * glow), RAIL_GLOW_NEAR_W, true)
		if flash > 0.0 and not low:
			draw_line(a, b, Palette.alpha(Palette.SONAR_PALE, 0.35 * flash), RAIL_FLASH_W, true)
		draw_line(a, b, Palette.alpha(Palette.SONAR, RAIL_ALPHA), RAIL_W, true)
		if max_a > 0.0:
			draw_line(a, b, Palette.alpha(Palette.SONAR_PALE, max_a), MAX_RAIL_W, true)
			_draw_max_dashes(f, max_a)
		if flash > 0.0:
			draw_line(a, b, Palette.alpha(Palette.SONAR_PALE, flash), MAX_RAIL_W + 1.0, true)


## MAX rail dashes: 24 px SONAR_PALE 70% strokes, one every half beat, flowing toward the
## player with the board (static under Reduce motion).
func _draw_max_dashes(f: float, alpha: float) -> void:
	var hb := 30.0 / _bpm_at(_vt)
	var sp := hb / maxf(_approach, 0.001)
	if sp <= 0.0:
		return
	var d := (1.0 - dash_phase(_vt)) * sp
	var dir := (Trench.point(f, 1.0) - Trench.point(f, 0.0)).normalized()
	var col := Palette.alpha(Palette.SONAR_PALE, MAX_DASH_ALPHA * alpha)
	var glow := Palette.alpha(Palette.SONAR_PALE, MAX_DASH_GLOW_ALPHA * alpha)
	var low: bool = Settings.low_effects
	var n := 0
	while d <= 1.0 and n < MAX_DASH_CAP:
		var s := Trench.scale_at(d)
		var p := Trench.point(f, d)
		var q := p + dir * MAX_DASH_LEN * s
		# Wider than the 3 px core so the beads read as light flowing down the rail.
		var w := MAX_DASH_W * (0.5 + 0.5 * s)
		if not low:
			draw_line(p, q, glow, w * 2.6, true)
		draw_line(p, q, col, w, true)
		d += sp
		n += 1


## Tempo at song time t (the last segment starting at or before t; 120 bpm without a map).
func _bpm_at(t: float) -> float:
	if chart == null or chart.tempo_map.is_empty():
		return 120.0
	var bpm := float(chart.tempo_map[0]["bpm"])
	for seg in chart.tempo_map:
		if float(seg["time"]) <= t:
			bpm = float(seg["bpm"])
		else:
			break
	return maxf(bpm, 1.0)


# ---- Row 4: beat and bar lines -------------------------------------------------------------

## Lines across the highway (f = -2..+2) at each visible beat; bars are wider, SONAR, with a
## soft glow in Full effects. Uses the arrays _update_window filled this frame.
func _draw_beat_lines() -> void:
	var y_end := _strip_end_y()
	var low: bool = Settings.low_effects
	var beat_col := Palette.alpha(Palette.TEXT_HI, BEAT_LINE_ALPHA)
	var bar_col := Palette.alpha(Palette.SONAR, BAR_LINE_ALPHA)
	var bar_glow := Palette.alpha(Palette.SONAR, BAR_GLOW_ALPHA)
	for i in range(_beat_count):
		var d := _beat_d[i]
		var y := Trench.point(0.0, d).y
		if y > y_end:
			continue
		var s := Trench.scale_at(d)
		var a := Vector2(edge_x(-2.0, y), y)
		var b := Vector2(edge_x(2.0, y), y)
		if _beat_bar[i] == 1:
			var w := 2.0 + 2.0 * s
			if not low:
				draw_line(a, b, bar_glow, w + BAR_GLOW_EXTRA_W, true)
			draw_line(a, b, bar_col, w, true)
		else:
			draw_line(a, b, beat_col, 1.0 + s, true)


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

func _draw_sustains(phase: float) -> void:
	var notes := chart.notes
	for k in range(_vis.size()):
		var idx := _vis[k]
		var n: Dictionary = notes[idx]
		var dur: float = n["duration"]
		if dur <= 0.0:
			continue
		var d_head := Trench.depth_for(float(n["time"]), _vt, _approach)
		var d_tail := Trench.depth_for(float(n["time"]) + dur, _vt, _approach)
		_draw_sustain(int(n["lane"]), d_head, d_tail, _state[idx], phase)


## Glowing tube along the lane centre between head and tail depth (UI-SPEC 7.4 row 6): a soft
## lane-colour glow (Full), the 45% fill (held: pulsing to 75% with the beat), thin edges and a
## bright core line. Early release / missed tails: TEXT_LO 25%, no core.
func _draw_sustain(lane: int, d_head: float, d_tail: float, state: int, phase: float) -> void:
	var span := ribbon_span(d_head, d_tail, state == S_HOLDING)
	var d0 := span.x
	var d1 := span.y
	if d1 <= d0 + 0.001:
		return
	var lane_col := Palette.lane_color(lane)
	var core := sustain_has_core(state)
	var base := lane_col if core else Palette.TEXT_LO
	var fill_a := sustain_fill_alpha(state, phase)
	var f := Trench.lane_f(lane)
	var low: bool = Settings.low_effects
	if core and not low:
		_tube_edges(f, d0, d1, TUBE_GLOW_HALF_W)
		_fill_ribbon(Palette.alpha(lane_col, TUBE_GLOW_ALPHA * (fill_a / TUBE_FILL)))
	_tube_edges(f, d0, d1, TUBE_HALF_W)
	_fill_ribbon(Palette.alpha(base, fill_a))
	var edge := Palette.alpha(base, TUBE_EDGE_ALPHA if core else TUBE_DEAD_FILL)
	draw_polyline(_edge_l, edge, 1.5, true)
	draw_polyline(_edge_r, edge, 1.5, true)
	if core:
		for k in range(RIBBON_SAMPLES + 1):
			_edge_l[k] = Trench.point(f, lerpf(d0, d1, float(k) / float(RIBBON_SAMPLES)))
		var w := 3.0 * Trench.scale_at(d0)
		draw_polyline(_edge_l, Palette.alpha(Palette.mix(lane_col, Palette.WHITE, 0.5), TUBE_CORE_ALPHA), maxf(w, 1.0), true)
	if state == S_HOLDING and not low:
		draw_circle(Trench.hit_point(lane), RECEPTOR_R * 0.9, Palette.alpha(lane_col, 0.18 + 0.12 * BeatClock.pulse(phase)))


## Fills _edge_l / _edge_r with the ribbon edges at half-width k * note radius.
func _tube_edges(f: float, d0: float, d1: float, k: float) -> void:
	for i in range(RIBBON_SAMPLES + 1):
		var d := lerpf(d0, d1, float(i) / float(RIBBON_SAMPLES))
		var c := Trench.point(f, d)
		var hw := k * Trench.note_radius(Trench.scale_at(d))
		_edge_l[i] = Vector2(c.x - hw, c.y)
		_edge_r[i] = Vector2(c.x + hw, c.y)


func _fill_ribbon(col: Color) -> void:
	for i in range(RIBBON_SAMPLES):
		_quad[0] = _edge_l[i]
		_quad[1] = _edge_r[i]
		_quad[2] = _edge_r[i + 1]
		_quad[3] = _edge_l[i + 1]
		draw_colored_polygon(_quad, col)


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
	# x4 constant receptor halo (kept in Low effects, UI-SPEC 7.6); fades with the extras.
	var max_halo := MAX_RECEPTOR_HALO * (1.0 if tier == 4 else (_fade_part(now) if _drop_from_tier == 4 else 0.0))
	for lane in range(LANES):
		var col := Palette.lane_color(lane)
		var kind := NoteShape.kind_for_lane(lane)
		var center := receptor_center(lane)
		var tick := _press_ticks[lane]
		var age := now - tick if tick >= 0 else RECEPTOR_PULSE_USEC
		var pressed := age >= 0 and age < RECEPTOR_PULSE_USEC
		var held := _holding[lane] >= 0
		var sq := receptor_scale(lane, now)
		var kx := RECEPTOR_R * sq.x
		var ky := RECEPTOR_R * sq.y
		if max_halo > 0.0:
			var hr := Palette.GLOW_MD[0] * RECEPTOR_R
			draw_texture_rect(UiKit.glow_texture(), Rect2(center - Vector2(hr, hr), Vector2(2.0 * hr, 2.0 * hr)),
				false, Palette.alpha(col, max_halo * ra))
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


# ---- Shared positions (02.2-26, G1): drawing and tests use these, so they cannot drift ------

## Depth of a gem this frame from the visual time snapshot (missed remnants are pinned just
## past the line at d = -0.06; pending gems keep moving).
func gem_depth(note_index: int) -> float:
	var d := Trench.depth_for(float(chart.notes[note_index]["time"]), _vt, _approach)
	if _state[note_index] == S_MISSED:
		d = maxf(d, -0.06)
	return d


## The exact centre draw_notes_into / draw_halos_into pass to NotePainter for this note.
func gem_center(note_index: int) -> Vector2:
	return Trench.point(Trench.lane_f(int(chart.notes[note_index]["lane"])), gem_depth(note_index))


## Un-squashed receptor pad centre (on the hit line); _draw_receptors and the lane numbers use it.
func receptor_center(lane: int) -> Vector2:
	return Trench.hit_point(lane)


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
			var paint := NotePainter.STATE_FAR
			var fade := 1.0
			if state == S_MISSED:
				var past := (_vt - float(n["time"])) - 0.06 * _approach
				fade = 1.0 - clampf(past / GHOST_FADE_SEC, 0.0, 1.0)
				if fade <= 0.0:
					continue
				paint = NotePainter.STATE_MISSED
			elif note_is_ready(float(n["time"]) - _st, _good_window):
				paint = NotePainter.STATE_READY
			var d := gem_depth(idx)
			var c := gem_center(idx)
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
		var d := gem_depth(idx)
		NotePainter.draw_halo(ci, lane, gem_center(idx), Trench.note_radius(Trench.scale_at(d)))


## Bound key under each receptor (Label 20, lane colour 90%), cached per settings change.
func _draw_lane_numbers(ci: CanvasItem) -> void:
	var ra := clampf(receptor_alpha, 0.0, 1.0)
	if ra <= 0.0:
		return
	var font := Palette.font()
	for lane in range(LANES):
		var center := receptor_center(lane)
		ci.draw_string(font, Vector2(center.x - 50.0, center.y + 60.0), _lane_labels[lane], HORIZONTAL_ALIGNMENT_CENTER,
			100.0, Palette.SIZE_LABEL, Palette.alpha(Palette.lane_color(lane), LANE_LABEL_ALPHA * ra))


# ---- Spike readout (early/late moved to Feedback, 02.2-10) -------------------------------------------------

func _draw_spike_readout() -> void:
	var font := Palette.font()
	var x := 1568.0
	var y := 120.0
	var st := conductor.song_time()
	draw_string(font, Vector2(x, y + 20.0), "song_time %.3f" % st, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT_MID)
	draw_string(font, Vector2(x, y + 44.0), "raw_pos   %.3f" % conductor.raw_position(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT_MID)
	draw_string(font, Vector2(x, y + 68.0), "latency   %.1f ms  audio_valid %s" % [conductor.output_latency() * 1000.0, str(conductor.audio_valid())], HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT_MID)
	draw_string(font, Vector2(x, y + 92.0), "dt/frame (ms), 0-40", HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, Palette.TEXT_MID)
	var gx := x
	var gy := y + 104.0
	var gw := 320.0
	var gh := 96.0
	draw_rect(Rect2(gx, gy, gw, gh), Palette.ABYSS_500, false, 2.0)
	var pts := PackedVector2Array()
	for i in range(GRAPH_SAMPLES):
		var v := clampf(_graph[i], 0.0, 40.0) / 40.0
		pts.append(Vector2(gx + gw * i / (GRAPH_SAMPLES - 1), gy + gh - v * gh))
	draw_polyline(pts, Palette.SONAR, 2.0)
