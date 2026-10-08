class_name VisorHud
extends Control
## Recording-frame instrument HUD (01.1-06; AV-01 visor portion; recording-editor art direction).
## Heading strip, edge rulers with a depth gauge, layer chips (VISUAL / AUDIO / SONAR), the
## "DIVE REC // UNDERTOW" tag, a REAL song timeline scrubber (playhead = song_time / length,
## tempo-change keyframes, mm:ss:ff timecode) and the bottom status strip (O2 / HULL / REC).
## Drawn above the lens shader, below the gameplay HUD. Nothing is drawn in the highway
## note-entry zone; only the thin timeline crosses the highway bottom (below the labels).
## Chrome: off-white text, hot red accents, teal data. Red text only for HULL while critical.
## Low effects / reduce motion: no REC blink, heading drift or AUDIO beat pulse.
## _draw allocates nothing: geometry is prebuilt, strings are rebuilt only when they change.

const W := 1920.0
const H := 1080.0
## Highway note-entry zone that visor text must never touch.
const ENTRY_RECT := Rect2(672.0, 0.0, 576.0, 120.0)
const CRITICAL_PCT := 30.0

const TAG_TEXT := "DIVE REC // UNDERTOW"
const TAG_POS := Vector2(54.0, 204.0)  # baseline, below the chips
## Layer chips (top-left frame area, below the hull bar and badges).
const CHIP_Y := 136.0
const CHIP_SIZE := Vector2(112.0, 30.0)
const CHIP_GAP := 8.0
const CHIP_X := 32.0
const CHIP_LABELS: Array[String] = ["VISUAL", "AUDIO", "SONAR"]
const CHIP_COLORS: Array[Color] = [Palette.CHIP_VISUAL, Palette.CHIP_AUDIO, Palette.CHIP_SONAR]
const AUDIO_CHIP := 1
## Heading strip: two flanks hugging the highway, ticks hang from the top edge.
const HDG_LEFT := Vector2(368.0, 600.0)  # x range
const HDG_RIGHT := Vector2(1320.0, 1552.0)
const HDG_TOP := 4.0
const HDG_TICK_STEP := 16.0
const HDG_TEXT_POS := Vector2(1336.0, 46.0)  # baseline
## Left ruler (trim) and right ruler (depth gauge) along the lens edge.
const LRULER_X := 168.0
const LRULER_Y := Vector2(300.0, 780.0)
const RRULER_X := 1776.0
const RRULER_Y := Vector2(470.0, 800.0)
const RULER_STEP := 16.0
const DEPTH_BAND := 250.0
## Timeline scrubber (frame band below the lens, clear of the y 840..960 gameplay band).
const TL_X := Vector2(240.0, 1680.0)
const TL_Y := 1018.0
const TL_TOP := 996.0
const TL_BOTTOM := 1040.0
const TL_MINOR := 48  # tick divisions
const TL_MAJOR_EVERY := 6
const TC_POS := Vector2(96.0, 1026.0)  # timecode baseline
const TC_FPS := 30
## Bottom status strip.
const STATUS_BASE_Y := 1066.0
const O2_X := 160.0
const HULL_X := 288.0
const REC_X := 1520.0
const SONAR_RIGHT := 1760.0
const SONAR_TEXT := "SONAR ACTIVE"
const O2_START := 98
const O2_FLOOR := 61
const O2_SEC_PER_PCT := 20.0
const BLINK_SEC := 0.6
const PULSE_DECAY := 4.0  # AUDIO chip pulse falloff over one beat

# _items index of the blinking "REC" text (fixed order, see _relayout).
const I_REC := 9

var _score: HullScore
var _conductor: Conductor
var _tempo_map: Array[Dictionary] = []
var _length: float = 0.0
var _hull_pct: int = 100
var _depth_m: int = 0
var _o2: int = O2_START
var _heading: int = 184
var _rec_on: bool = true
var _static: bool = false
var _elapsed: float = 0.0
var _song_t: float = 0.0
var _progress: float = 0.0
var _pulse: float = 0.0
var _tc_frame: int = -1

var _hull_text: String = "HULL 100%"
var _o2_text: String = "O2 98%"
var _hdg_text: String = "HDG 184"
var _depth_text: String = "0 M"
var _band_top_text: String = "0"
var _band_bot_text: String = "250"
var _tc_text: String = "00:00:00"
var _len_text: String = "00:00:00"
var _gauge_frac: float = 0.0

var _items: Array = []  # [text, baseline pos, color]; rebuilt only when a value changes
var _ticks_minor := PackedVector2Array()
var _ticks_major := PackedVector2Array()
var _tl_minor := PackedVector2Array()
var _tl_major := PackedVector2Array()
var _caret_l := PackedVector2Array()
var _caret_r := PackedVector2Array()
var _keyframes: Array[PackedVector2Array] = []
var _ph_tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _gauge_tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ticks()
	_relayout()
	if not Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.connect(apply_low_effects)
	apply_low_effects()


func _exit_tree() -> void:
	if Settings.settings_changed.is_connected(apply_low_effects):
		Settings.settings_changed.disconnect(apply_low_effects)


## Subscribe to a HullScore (real hull and depth values).
func bind(score: HullScore) -> void:
	_score = score
	score.hull_changed.connect(_on_hull_changed)
	score.score_changed.connect(_on_score_changed)
	_set_hull(score.hull)
	_set_depth(score.depth())


## Real song progress source: playhead = song_time / length, keyframes at tempo changes.
func setup_timeline(conductor: Conductor, tempo_map: Array[Dictionary], length: float) -> void:
	_conductor = conductor
	_tempo_map = tempo_map
	_length = maxf(length, 0.0)
	_len_text = timecode(_length)
	_keyframes.clear()
	if _length > 0.0:
		for seg in tempo_map:
			var x := _tl_x(progress_for(float(seg["time"]), _length))
			_keyframes.append(PackedVector2Array([Vector2(x, TL_Y - 6.0), Vector2(x + 6.0, TL_Y),
				Vector2(x, TL_Y + 6.0), Vector2(x - 6.0, TL_Y)]))
	_relayout()


## Playhead position 0..1 for song time t (clamped; 0 when the length is unknown).
static func progress_for(t: float, length: float) -> float:
	if length <= 0.0:
		return 0.0
	return clampf(t / length, 0.0, 1.0)


## "mm:ss:ff" (ff = frames at TC_FPS). Negative times read 00:00:00.
static func timecode(t: float) -> String:
	var total := int(floor(maxf(t, 0.0) * TC_FPS))
	@warning_ignore("integer_division")
	var secs := total / TC_FPS
	@warning_ignore("integer_division")
	var mins := secs / 60
	return "%02d:%02d:%02d" % [mins, secs % 60, total % TC_FPS]


## Fraction 0..1 through the current beat at song time t, from the tempo map.
static func beat_phase(t: float, tempo_map: Array[Dictionary]) -> float:
	if tempo_map.is_empty() or t < 0.0:
		return 0.0
	var seg: Dictionary = tempo_map[0]
	for s in tempo_map:
		if float(s["time"]) <= t:
			seg = s
		else:
			break
	var bpm := maxf(float(seg["bpm"]), 1.0)
	return fposmod((t - float(seg["time"])) * bpm / 60.0, 1.0)


func apply_low_effects() -> void:
	_static = Settings.low_effects or Settings.reduce_motion
	if _static:
		_rec_on = true
		_pulse = 0.0
	_relayout()


## True while decorative animation (REC blink, heading drift, AUDIO pulse) runs.
func animated() -> bool:
	return not _static


func is_hull_critical() -> bool:
	return float(_hull_pct) <= CRITICAL_PCT


func hull_text() -> String:
	return _hull_text


func depth_text() -> String:
	return _depth_text


func gauge_fraction() -> float:
	return _gauge_frac


func progress() -> float:
	return _progress


func timecode_text() -> String:
	return _tc_text


func playhead_x() -> float:
	return _tl_x(_progress)


func audio_pulse() -> float:
	return _pulse


func keyframe_count() -> int:
	return _keyframes.size()


## Every text item this node draws (and the chips), as screen rects for layout tests.
func text_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var f := Palette.font()
	var s := Palette.SIZE_LABEL
	for item in _items:
		var text: String = item[0]
		var pos: Vector2 = item[1]
		var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s)
		out.append(Rect2(pos.x, pos.y - f.get_ascent(s), sz.x, sz.y))
	for i in CHIP_LABELS.size():
		out.append(_chip_rect(i))
	return out


func _chip_rect(i: int) -> Rect2:
	return Rect2(Vector2(CHIP_X + i * (CHIP_SIZE.x + CHIP_GAP), CHIP_Y), CHIP_SIZE)


func _tl_x(p: float) -> float:
	return lerpf(TL_X.x, TL_X.y, p)


func _relayout() -> void:
	var f := Palette.font()
	var s := Palette.SIZE_LABEL
	var sonar_w := f.get_string_size(SONAR_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var depth_w := f.get_string_size(_depth_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var top_w := f.get_string_size(_band_top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var bot_w := f.get_string_size(_band_bot_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var gy := _gauge_y()
	var txt := Palette.REC_TEXT
	var dim := Palette.alpha(Palette.REC_TEXT, 0.6)
	var data := Palette.REC_TEAL
	var hull_c := Palette.DESTRUCTIVE if is_hull_critical() else data
	_items = [
		[TAG_TEXT, TAG_POS, txt],
		[_hdg_text, HDG_TEXT_POS, data],
		["TRIM", Vector2(LRULER_X - 8.0, LRULER_Y.x - 12.0), dim],
		["BATHY", Vector2(RRULER_X - 56.0, RRULER_Y.x - 12.0), dim],
		[_band_top_text, Vector2(RRULER_X - 24.0 - top_w, RRULER_Y.x + 6.0), dim],
		[_band_bot_text, Vector2(RRULER_X - 24.0 - bot_w, RRULER_Y.y + 6.0), dim],
		[_depth_text, Vector2(RRULER_X - 32.0 - depth_w, gy + 7.0), data],
		[_o2_text, Vector2(O2_X, STATUS_BASE_Y), data],
		[_hull_text, Vector2(HULL_X, STATUS_BASE_Y), hull_c],
		["REC", Vector2(REC_X + 16.0, STATUS_BASE_Y), txt],
		[SONAR_TEXT, Vector2(SONAR_RIGHT - sonar_w, STATUS_BASE_Y), dim],
		[_tc_text, TC_POS, txt],
		[_len_text, Vector2(TL_X.y + 16.0, TC_POS.y), dim],
	]
	queue_redraw()


func _build_ticks() -> void:
	_ticks_minor.clear()
	_ticks_major.clear()
	# Heading flanks: minor 6px, major (every 5th) 14px, hanging from HDG_TOP.
	for flank in [HDG_LEFT, HDG_RIGHT]:
		var i := 0
		var x: float = flank.x
		while x <= flank.y + 0.5:
			var major := i % 5 == 0
			var arr := _ticks_major if major else _ticks_minor
			arr.append(Vector2(x, HDG_TOP))
			arr.append(Vector2(x, HDG_TOP + (14.0 if major else 6.0)))
			x += HDG_TICK_STEP
			i += 1
	_add_ruler(LRULER_X, LRULER_Y, 1.0)
	_add_ruler(RRULER_X, RRULER_Y, -1.0)
	_caret_l = PackedVector2Array([Vector2(HDG_LEFT.y + 8.0, HDG_TOP),
		Vector2(HDG_LEFT.y + 20.0, HDG_TOP + 7.0), Vector2(HDG_LEFT.y + 8.0, HDG_TOP + 14.0)])
	_caret_r = PackedVector2Array([Vector2(HDG_RIGHT.x - 8.0, HDG_TOP),
		Vector2(HDG_RIGHT.x - 20.0, HDG_TOP + 7.0), Vector2(HDG_RIGHT.x - 8.0, HDG_TOP + 14.0)])
	# Timeline ticks above the track.
	_tl_minor.clear()
	_tl_major.clear()
	for k in range(TL_MINOR + 1):
		var x := _tl_x(float(k) / TL_MINOR)
		var major := k % TL_MAJOR_EVERY == 0
		var arr := _tl_major if major else _tl_minor
		arr.append(Vector2(x, TL_Y - (14.0 if major else 6.0)))
		arr.append(Vector2(x, TL_Y))


func _add_ruler(x: float, span: Vector2, dir: float) -> void:
	var j := 0
	var y := span.x
	while y <= span.y + 0.5:
		var major := j % 5 == 0
		var arr := _ticks_major if major else _ticks_minor
		arr.append(Vector2(x, y))
		arr.append(Vector2(x + dir * (16.0 if major else 8.0), y))
		y += RULER_STEP
		j += 1
	_ticks_minor.append(Vector2(x, span.x))
	_ticks_minor.append(Vector2(x, span.y))


func _process(delta: float) -> void:
	_elapsed += delta
	var relayout := false
	var redraw := false
	var o2 := maxi(O2_START - int(_elapsed / O2_SEC_PER_PCT), O2_FLOOR)
	if o2 != _o2:
		_o2 = o2
		_o2_text = "O2 %d%%" % _o2
		relayout = true
	if not _static:
		var rec := fmod(_elapsed, BLINK_SEC * 2.0) < BLINK_SEC
		if rec != _rec_on:
			_rec_on = rec
			redraw = true
		var hdg := posmod(184 + int(round(6.0 * sin(_elapsed * 0.15))), 360)
		if hdg != _heading:
			_heading = hdg
			_hdg_text = "HDG %03d" % _heading
			relayout = true
	if _conductor != null and is_instance_valid(_conductor):
		_song_t = _conductor.song_time()
		var p := progress_for(_song_t, _length)
		if absf(p - _progress) * (TL_X.y - TL_X.x) >= 0.25:
			_progress = p
			redraw = true
		var frame := int(floor(maxf(_song_t, 0.0) * TC_FPS))
		if frame != _tc_frame:
			_tc_frame = frame
			_tc_text = timecode(_song_t)
			relayout = true
		if not _static:
			var pulse := exp(-beat_phase(_song_t, _tempo_map) * PULSE_DECAY) if _song_t >= 0.0 else 0.0
			if absf(pulse - _pulse) > 0.01:
				_pulse = pulse
				redraw = true
	if relayout:
		_relayout()
	elif redraw:
		queue_redraw()


func _on_hull_changed(value: float, _delta: float) -> void:
	_set_hull(value)


func _on_score_changed(_value: int) -> void:
	if _score != null:
		_set_depth(_score.depth())


func _set_hull(value: float) -> void:
	var pct := int(round(clampf(value, 0.0, 100.0)))
	if pct == _hull_pct:
		return
	_hull_pct = pct
	_hull_text = "HULL %d%%" % pct
	_relayout()


func _set_depth(meters: float) -> void:
	var m := maxi(int(meters), 0)
	if m == _depth_m and m != 0:
		return
	_depth_m = m
	_depth_text = "%s M" % Palette.fmt_depth(m)
	var band := floorf(float(m) / DEPTH_BAND) * DEPTH_BAND
	_band_top_text = Palette.fmt_depth(int(band))
	_band_bot_text = Palette.fmt_depth(int(band + DEPTH_BAND))
	_gauge_frac = (float(m) - band) / DEPTH_BAND
	_relayout()


func _gauge_y() -> float:
	return lerpf(RRULER_Y.x, RRULER_Y.y, _gauge_frac)


func _draw() -> void:
	var txt := Palette.REC_TEXT
	var dim := Palette.alpha(Palette.REC_TEXT, 0.45)
	var red := Palette.REC_RED
	var data := Palette.REC_TEAL
	var f := Palette.font()
	var s := Palette.SIZE_LABEL
	# Frame ticks: dim off-white minors, hot red majors.
	draw_multiline(_ticks_minor, dim, 2.0)
	draw_multiline(_ticks_major, red, 2.0)
	draw_colored_polygon(_caret_l, red)
	draw_colored_polygon(_caret_r, red)
	# Depth gauge marker (moves with depth inside the current 250 m band).
	var gy := _gauge_y()
	_gauge_tri.set(0, Vector2(RRULER_X - 28.0, gy - 7.0))
	_gauge_tri.set(1, Vector2(RRULER_X - 16.0, gy))
	_gauge_tri.set(2, Vector2(RRULER_X - 28.0, gy + 7.0))
	draw_colored_polygon(_gauge_tri, data)
	# Layer chips (AUDIO pulses on beats).
	for i in CHIP_LABELS.size():
		var r := _chip_rect(i)
		var c := CHIP_COLORS[i]
		var fill := 0.12 + (0.45 * _pulse if i == AUDIO_CHIP else 0.0)
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.85))
		draw_rect(r, Palette.alpha(c, fill))
		draw_rect(r, c, false, 2.0)
		draw_string(f, Vector2(r.position.x, r.position.y + 22.0), CHIP_LABELS[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, s, c)
	# Solid red dot in front of "DIVE REC // UNDERTOW".
	draw_circle(Vector2(TAG_POS.x - 14.0, TAG_POS.y - 7.0), 5.0, red)
	# Timeline: track, played portion, ticks, keyframes, playhead.
	var px := _tl_x(_progress)
	draw_line(Vector2(TL_X.x, TL_Y), Vector2(TL_X.y, TL_Y), dim, 2.0)
	draw_line(Vector2(TL_X.x, TL_Y), Vector2(px, TL_Y), txt, 2.0)
	draw_multiline(_tl_minor, dim, 1.0)
	draw_multiline(_tl_major, txt, 2.0)
	for kf in _keyframes:
		draw_colored_polygon(kf, data)
	draw_line(Vector2(px, TL_TOP), Vector2(px, TL_BOTTOM), red, 2.0)
	_ph_tri.set(0, Vector2(px - 7.0, TL_TOP - 6.0))
	_ph_tri.set(1, Vector2(px + 7.0, TL_TOP - 6.0))
	_ph_tri.set(2, Vector2(px, TL_TOP + 2.0))
	draw_colored_polygon(_ph_tri, red)
	# Text.
	for i in _items.size():
		var item: Array = _items[i]
		if i == I_REC and not _rec_on:
			continue
		draw_string(f, item[1], item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, s, item[2])
	if _rec_on:
		draw_circle(Vector2(REC_X + 6.0, STATUS_BASE_Y - 7.0), 5.0, red)
