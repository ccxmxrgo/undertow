class_name SectionBanner
extends Control
## Timed section banner (UI-SPEC 4.9, S-4, D-10) at x 640..1280, y 200..272, above the vanishing
## point and outside the note path. A CUT_SM glass panel with a "SECTION" caption (Label 20
## SONAR, baseline 224) flanked by two short SONAR rules, and the section name (Heading 40
## TEXT_HI UPPERCASE, baseline 262, 28 chars then "...").
## Timing: at a section start it slides down 24 px and fades in over DUR_BASE (cubic-out), holds
## 1.6 s and fades out over 0.3 s. A new section during the hold cross-fades the text in 0.12 s
## and restarts the hold. Not shown before song_time 0.5 s or within 2 s of the song end.
## A one-shot sonar sweep crosses the panel as it arrives (Full only).
## Reduce motion: fade only, no sweep. Low effects: no panel glow, no sweep.
## Read-only: polls Conductor.song_time() each frame; animation timers are delta driven so tests
## can step them. Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

enum Phase { IDLE, IN, HOLD, OUT }

const RECT := Rect2(640.0, 200.0, 640.0, 72.0)
const CAPTION := "SECTION"
const CAPTION_BASE_Y := 24.0  # 224 - 200
const NAME_BASE_Y := 62.0  # 262 - 200
const SLIDE_PX := 24.0
const HOLD_SEC := 1.6
const OUT_SEC := 0.3
const XFADE_SEC := 0.12
const MIN_START_SEC := 0.5
const END_GUARD_SEC := 2.0
const MAX_CHARS := 28
const ELLIPSIS := "..."
const BRACKET_ALPHA := 0.8
const RULE_GAP := 12.0
const RULE_LEN := 72.0
const RULE_ALPHA := 0.45
const SWEEP_SEC := 0.45
const SWEEP_ALPHA := 0.35
const SWEEP_W := 3.0

var _chart: ChartData
var _conductor: Conductor
var _len: float = 0.0
var _sections: Array[Dictionary] = []
var _idx: int = -1
var _phase: Phase = Phase.IDLE
var _phase_t: float = 0.0
var _text: String = ""
var _prev_text: String = ""
var _xfade_left: float = 0.0
var _sweep_t: float = -1.0
var _reduce: bool = false
var _low: bool = false
var _panel: StyleBoxFlat


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	UiKit.register_fx(self)
	apply_effect_settings()


func setup(chart: ChartData, conductor: Conductor) -> void:
	_chart = chart
	_conductor = conductor
	_len = ProgressTrack.song_length_of(chart)
	_sections.clear()
	if chart != null:
		for s in chart.sections:
			var st := float(s.get("time", 0.0))
			if is_finite(st):
				_sections.append({"time": st, "name": str(s.get("name", ""))})
		_sections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	_idx = -1
	_set_phase(Phase.IDLE)
	_text = ""
	_prev_text = ""
	_xfade_left = 0.0
	_sweep_t = -1.0


## False before 0.5 s and for a section starting within 2 s of the song end.
static func should_show(section_time: float, song_len: float) -> bool:
	if not is_finite(section_time) or section_time < MIN_START_SEC:
		return false
	if song_len > 0.0 and section_time > song_len - END_GUARD_SEC:
		return false
	return true


## UPPERCASE name, cut at 28 chars with "...", then cut further if it would overflow the panel.
static func display_name(raw: String) -> String:
	var s := raw.strip_edges().to_upper()
	if s.length() > MAX_CHARS:
		s = s.substr(0, MAX_CHARS).strip_edges(false, true) + ELLIPSIS
	var max_w := RECT.size.x - 2.0 * UiKit.PANEL_PAD
	return ProgressTrack.truncate_px(s, Palette.display_font(), Palette.SIZE_HEADING, max_w)


## Section-change detection for the time t (read-only). Only a forward change to a showable
## section starts the banner; going back (or the first section before 0.5 s) just re-syncs.
func observe(t: float) -> void:
	if not is_finite(t):
		return
	var i := ProgressTrack.section_index(_sections, t)
	if i == _idx:
		return
	var forward := i > _idx
	_idx = i
	if forward and i >= 0 and should_show(float(_sections[i]["time"]), _len):
		show_section(str(_sections[i]["name"]))


func show_section(raw_name: String) -> void:
	var n := display_name(raw_name)
	match _phase:
		Phase.HOLD:
			_cross_fade_to(n)
			_phase_t = 0.0  # the hold restarts with the new name
		Phase.IN:
			_cross_fade_to(n)
		Phase.OUT:
			_cross_fade_to(n)
			# Re-enter from the current opacity so nothing pops.
			var a := alpha()
			_set_phase(Phase.HOLD if a >= 0.999 else Phase.IN)
			_phase_t = 0.0 if _phase == Phase.HOLD else _in_time_for_alpha(a)
		_:
			_text = n
			_prev_text = ""
			_xfade_left = 0.0
			_set_phase(Phase.IN)
			_sweep_t = 0.0 if sweep_on() else -1.0
	_apply_visual()


func _cross_fade_to(n: String) -> void:
	if n == _text:
		return
	_prev_text = _text
	_text = n
	_xfade_left = XFADE_SEC


func _in_time_for_alpha(a: float) -> float:
	# Inverse of the cubic-out ease: a = 1 - (1 - k)^3.
	var k := 1.0 - pow(clampf(1.0 - a, 0.0, 1.0), 1.0 / 3.0)
	return k * Palette.DUR_BASE


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = 0.0


## Advance the animation by dt seconds.
func step(dt: float) -> void:
	if dt <= 0.0 or _phase == Phase.IDLE:
		return
	if _xfade_left > 0.0:
		_xfade_left = maxf(_xfade_left - dt, 0.0)
	if _sweep_t >= 0.0:
		_sweep_t += dt
		if _sweep_t >= SWEEP_SEC:
			_sweep_t = -1.0
	_phase_t += dt
	match _phase:
		Phase.IN:
			if _phase_t >= Palette.DUR_BASE:
				var over := _phase_t - Palette.DUR_BASE
				_set_phase(Phase.HOLD)
				_phase_t = over
		Phase.HOLD:
			if _phase_t >= HOLD_SEC:
				var over2 := _phase_t - HOLD_SEC
				_set_phase(Phase.OUT)
				_phase_t = over2
		Phase.OUT:
			if _phase_t >= OUT_SEC:
				_set_phase(Phase.IDLE)
				_prev_text = ""
				_xfade_left = 0.0
	_apply_visual()


func _apply_visual() -> void:
	modulate.a = alpha()
	visible = _phase != Phase.IDLE
	queue_redraw()


static func _ease_out_cubic(k: float) -> float:
	var u := 1.0 - clampf(k, 0.0, 1.0)
	return 1.0 - u * u * u


func alpha() -> float:
	match _phase:
		Phase.IN:
			return _ease_out_cubic(_phase_t / Palette.DUR_BASE)
		Phase.HOLD:
			return 1.0
		Phase.OUT:
			return clampf(1.0 - _phase_t / OUT_SEC, 0.0, 1.0)
	return 0.0


## Vertical draw offset: -24 px at the start of the slide, 0 when settled (always 0 under Reduce motion).
func slide_offset() -> float:
	if _reduce or _phase != Phase.IN:
		return 0.0
	return -SLIDE_PX * (1.0 - _ease_out_cubic(_phase_t / Palette.DUR_BASE))


func is_showing() -> bool:
	return _phase != Phase.IDLE


func shown_text() -> String:
	return _text


func is_cross_fading() -> bool:
	return _xfade_left > 0.0


func phase() -> Phase:
	return _phase


func sweep_on() -> bool:
	return not _low and not _reduce


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	_panel = UiKit.style_panel("default", _low)
	_panel.corner_radius_top_left = Palette.CUT_SM
	_panel.corner_radius_bottom_right = Palette.CUT_SM
	if not sweep_on():
		_sweep_t = -1.0
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"slide": not _reduce, "glow": not _low, "sweep": sweep_on()}


func _process(delta: float) -> void:
	if _conductor != null and is_instance_valid(_conductor):
		observe(_conductor.song_time())
	step(delta)


## W4 keep-out contract: the panel at its current slide offset (global space).
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var r := Rect2(Vector2(0.0, slide_offset()), RECT.size)
	return [PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
		xf * Vector2(r.position.x, r.end.y)])]


func _draw() -> void:
	if _phase == Phase.IDLE:
		return
	var oy := slide_offset()
	var r := Rect2(Vector2(0.0, oy), RECT.size)
	draw_style_box(_panel, r)
	UiKit.draw_brackets(self, r, Palette.alpha(Palette.SONAR, BRACKET_ALPHA))
	# "SECTION" caption with a short rule on each side.
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var cw := f.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cx := RECT.size.x * 0.5
	var cby := oy + CAPTION_BASE_Y
	draw_string(f, Vector2(cx - cw * 0.5, cby), CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SONAR)
	var ry := cby - f.get_ascent(fs) * 0.35
	var rule := Palette.alpha(Palette.SONAR, RULE_ALPHA)
	var l0 := cx - cw * 0.5 - RULE_GAP
	var r0 := cx + cw * 0.5 + RULE_GAP
	draw_line(Vector2(l0 - RULE_LEN, ry), Vector2(l0, ry), rule, 1.0, true)
	draw_line(Vector2(r0, ry), Vector2(r0 + RULE_LEN, ry), rule, 1.0, true)
	draw_rect(Rect2(l0 - RULE_LEN - 3.0, ry - 1.5, 3.0, 3.0), rule)
	draw_rect(Rect2(r0 + RULE_LEN, ry - 1.5, 3.0, 3.0), rule)
	# Name, cross-fading from the previous one.
	var k := 1.0 - _xfade_left / XFADE_SEC if _xfade_left > 0.0 else 1.0
	if _xfade_left > 0.0 and _prev_text != "":
		_draw_name(_prev_text, oy, 1.0 - k)
	_draw_name(_text, oy, k)
	# Arrival sweep: a thin SONAR_PALE line crossing the panel once.
	if _sweep_t >= 0.0:
		var s := clampf(_sweep_t / SWEEP_SEC, 0.0, 1.0)
		var sx := lerpf(Palette.CUT_SM, RECT.size.x - Palette.CUT_SM, _ease_out_cubic(s))
		var sa := SWEEP_ALPHA * (1.0 - s)
		draw_line(Vector2(sx, oy + 4.0), Vector2(sx, oy + RECT.size.y - 4.0), Palette.alpha(Palette.SONAR_PALE, sa), SWEEP_W)
		draw_line(Vector2(sx, oy + 4.0), Vector2(sx, oy + RECT.size.y - 4.0), Palette.alpha(Palette.SONAR_PALE, sa * 0.3), SWEEP_W * 4.0)


func _draw_name(text: String, oy: float, a: float) -> void:
	if text == "" or a <= 0.0:
		return
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2((RECT.size.x - w) * 0.5, oy + NAME_BASE_Y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Palette.alpha(Palette.TEXT_HI, a))
