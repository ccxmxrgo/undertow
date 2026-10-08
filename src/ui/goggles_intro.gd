class_name GogglesIntro
extends Control
## Goggles-on intro overlay (D-10..D-12). Pure presentation: pre-count runs on the wall clock
## before the Conductor starts (IntroTimeline drives what is shown); Gameplay then begins the
## conductor lead-in and calls on_count_started(), after which the 3-2-1 numerals derive from
## Conductor.song_time(). While it plays it also drives the board reveal (arena, cables,
## receptors, HUD) and restores the board defaults when it ends or leaves the tree (T-1.2-12).
## Hot red (#FF1F4B) is used only here, never in gameplay.

signal pre_count_finished
signal skip_requested

enum State { PRE, COUNT, DONE }

const W := 1920.0
const H := 1080.0
const INK := Color("02040A")
const TEAL := Color("05D9E8")
const HOT_RED := Color("FF1F4B")
const TEXT_COL := Color("E8E6F0")
const HINT_COL := Color("8A93AD")
const NUMERAL_SIZE := 180
const NUMERAL_BASELINE := 624.0
const SKIP_DIP_SEC := 0.12
const HUD_FADE_SEC := 0.3
const MASK_W := 480
const MASK_H := 270
const MASK_FAR_SCALE := 7.5
const ROOM_GLOW_R := 624.0

static var _room_glow_tex: GradientTexture2D

var mode: int = IntroTimeline.Mode.FULL
var _state: State = State.PRE
var _conductor: Conductor
var _arena: Arena
var _highway: Highway
var _hud: Control
var _streak: Control
var _spb: float = 0.5
var _beats: int = 3
var _origin_usec: int = 0
var _emitted: bool = false
var _skipped: bool = false
var _skip_usec: int = 0
var _last_phase: int = -1
var _last_number: int = 0
var _dive_played: bool = false
var _pad_last: bool = false
var _mask_tex: ImageTexture
var _sfx: AudioStreamPlayer
var _tick: AudioStreamWAV
var _tick_hi: AudioStreamWAV
var _clunk: AudioStreamWAV


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_mode: int, p_conductor: Conductor, chart: ChartData, p_arena: Arena,
		p_highway: Highway, p_hud: Control, p_streak: Control) -> void:
	mode = p_mode
	_conductor = p_conductor
	_arena = p_arena
	_highway = p_highway
	_hud = p_hud
	_streak = p_streak
	var bpm := 120.0
	if chart != null and not chart.tempo_map.is_empty():
		bpm = float(chart.tempo_map[0]["bpm"])
	_spb = IntroTimeline.seconds_per_beat(bpm)
	_build_sfx()
	_set_board(0.0, 0.0, 1.0, 0.0, 0.0)
	_origin_usec = Time.get_ticks_usec()


func _build_sfx() -> void:
	_tick = AudioSynth.make_tick(1.0)
	_tick_hi = AudioSynth.make_tick(2.0)
	_clunk = AudioSynth.make_clunk()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(_sfx)


func _play(stream: AudioStreamWAV) -> void:
	if _sfx != null and stream != null:
		_sfx.stream = stream
		_sfx.play()


func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _origin_usec) / 1000000.0


## Test hook: move the wall-clock origin earlier by `sec`.
func advance(sec: float) -> void:
	_origin_usec -= int(sec * 1000000.0)
	if _state == State.PRE:
		_update_pre()


func is_counting() -> bool:
	return _state == State.COUNT


## Request a skip straight to the 3-beat count-in. Only the first call while pre-count acts.
func skip() -> void:
	if _state != State.PRE or _skipped:
		return
	_skipped = true
	_skip_usec = Time.get_ticks_usec()
	_set_board(1.0, 1.0, 1.0, 1.0, 0.0)
	skip_requested.emit()


## Called by Gameplay when the conductor lead-in has begun.
func on_count_started(skipped: bool) -> void:
	_skipped = _skipped or skipped
	if skipped and _skip_usec == 0:
		_skip_usec = Time.get_ticks_usec()
	_beats = IntroTimeline.lead_in_beats(mode, skipped)
	_state = State.COUNT
	_last_number = 0
	_dive_played = false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_last = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad_last = false


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.PRE or event.is_echo():
		return
	if event.is_action_pressed(&"fire") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		skip()


func _exit_tree() -> void:
	_restore_board()


func _restore_board() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.reveal = 1.0
	if _highway != null and is_instance_valid(_highway):
		_highway.cable_grow = 1.0
		_highway.cable_bright = 0.0
		_highway.receptor_alpha = 1.0
	for c in [_hud, _streak]:
		if c != null and is_instance_valid(c):
			(c as Control).modulate.a = 1.0


func _set_board(reveal: float, grow: float, bright: float, receptors: float, hud_a: float) -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.reveal = reveal
	if _highway != null and is_instance_valid(_highway):
		_highway.cable_grow = grow
		_highway.cable_bright = bright
		_highway.receptor_alpha = receptors
	for c in [_hud, _streak]:
		if c != null and is_instance_valid(c):
			(c as Control).modulate.a = hud_a


func _process(_delta: float) -> void:
	if _state == State.DONE:
		return
	if _state == State.PRE:
		_update_pre()
	else:
		_update_count()
	queue_redraw()


func _update_pre() -> void:
	if _skipped:
		return
	var t := _elapsed()
	var ph := IntroTimeline.phase_at(t, mode, Settings.reduce_motion)
	var phase: int = ph["phase"]
	if phase != _last_phase:
		if phase == IntroTimeline.Phase.CRT:
			_play(_clunk)
		_last_phase = phase
	var a := 0.0
	var receptors := 0.0
	if phase == IntroTimeline.Phase.ARENA or phase == IntroTimeline.Phase.COUNT:
		a = IntroTimeline.ease_out(float(ph["progress"]))
		var total := IntroTimeline.pre_count_seconds(mode, Settings.reduce_motion)
		receptors = clampf((t - (total - 0.3)) / 0.3, 0.0, 1.0)
	_set_board(a, a, 1.0, receptors, 0.0)
	if phase == IntroTimeline.Phase.COUNT and not _emitted:
		_emitted = true
		pre_count_finished.emit()


func _update_count() -> void:
	var st := _conductor.song_time()
	var ct := st + float(_beats) * _spb
	var bright := 1.0 - clampf(ct / _spb, 0.0, 1.0)
	_set_board(1.0, 1.0, bright, 1.0, clampf(ct / HUD_FADE_SEC, 0.0, 1.0))
	var n := IntroTimeline.count_number(st, _spb, _beats)
	if n != 0 and n != _last_number:
		_play(_tick)
	if n != 0:
		_last_number = n
	if st >= 0.0:
		var dp := IntroTimeline.dive_progress(st, _is_quick())
		if dp < 0.0:
			_finish()
			return
		if not _dive_played:
			_dive_played = true
			_play(_tick_hi)


func _is_quick() -> bool:
	return mode == IntroTimeline.Mode.QUICK and not _skipped


func _finish() -> void:
	_state = State.DONE
	_restore_board()
	queue_free()


# ---------------------------------------------------------------------------------- drawing

func _draw() -> void:
	if _state == State.DONE:
		return
	if _state == State.PRE and not _skipped:
		_draw_pre()
	else:
		_draw_count()


func _draw_pre() -> void:
	var t := _elapsed()
	var rm := Settings.reduce_motion
	var ph := IntroTimeline.phase_at(t, mode, rm)
	var phase: int = ph["phase"]
	var p: float = ph["progress"]
	match phase:
		IntroTimeline.Phase.ROOM_LENS:
			var focus := IntroTimeline.lens_focus(t, mode, rm)
			_draw_room(t)
			if not rm:
				_draw_room_blur(t, focus)
			_draw_lens_mask(IntroTimeline.lens_close(t, mode, rm), 0.0, rm)
		IntroTimeline.Phase.BLACK:
			draw_rect(Rect2(0, 0, W, H), Color.BLACK)
		IntroTimeline.Phase.CRT:
			if rm:
				draw_rect(Rect2(0, 0, W, H), Color.BLACK)
			else:
				_draw_crt(p)
		IntroTimeline.Phase.ARENA:
			_draw_lens_mask(1.0, IntroTimeline.lens_open(t, mode, rm), rm)
	if mode == IntroTimeline.Mode.FULL and not rm:
		_draw_link_text(t)
	if _hint_visible(t, phase):
		var txt := "A TO SKIP" if _pad_last else "SPACE TO SKIP"
		_draw_spaced(txt, 960.0, 1040.0, Palette.SIZE_LABEL, Palette.alpha(HINT_COL, 0.7), 2.0)


func _hint_visible(t: float, phase: int) -> bool:
	if mode != IntroTimeline.Mode.FULL:
		return false
	if phase == IntroTimeline.Phase.ROOM_LENS:
		return t >= 0.3
	return phase == IntroTimeline.Phase.ARENA


func _draw_room(t: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color("07070B"))
	_draw_room_props(t, 1.0)


## Cheap blur approximation: faint offset copies of the bright props, shrinking as focus
## returns, plus a dim toward black while unfocused.
func _draw_room_blur(t: float, focus: float) -> void:
	var off := 14.0 * (1.0 - focus)
	if off > 0.5:
		for d in [Vector2(off, 0), Vector2(-off, 0), Vector2(0, off), Vector2(0, -off)]:
			draw_set_transform(d, 0.0, Vector2.ONE)
			_draw_room_props(t, 0.2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var dim := (1.0 - focus) * 0.35
	if dim > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, dim))


func _draw_room_props(t: float, am: float) -> void:
	var glow_c := Vector2(1380, 504)
	draw_texture_rect(room_glow_texture(), Rect2(glow_c - Vector2(ROOM_GLOW_R, ROOM_GLOW_R),
		Vector2(2.0 * ROOM_GLOW_R, 2.0 * ROOM_GLOW_R)), false, Color(1, 1, 1, am))
	draw_rect(Rect2(0, 768, 1920, 312), Color(Color("0F1118"), am))
	draw_rect(Rect2(1200, 360, 360, 228), Color(Color("161A26"), am))
	draw_rect(Rect2(1214, 374, 331, 199), Color(80.0 / 255.0, 140.0 / 255.0, 200.0 / 255.0, 0.25 * am))
	draw_rect(Rect2(216, 192, 192, 276), Color(Color("12141C"), am))
	draw_rect(Rect2(456, 240, 144, 192), Color(Color("12141C"), am))
	var font := Palette.font()
	draw_string(font, Vector2(1236, 480), "NEURAL DIVE RIG · READY", HORIZONTAL_ALIGNMENT_LEFT,
		-1, Palette.SIZE_LABEL, Color(0.91, 0.90, 0.94, 0.35 * am))
	var rec_on := Settings.reduce_motion or fmod(t, 1.0) < 0.5
	if rec_on:
		draw_circle(Vector2(1216, 474), 5.0, Color(HOT_RED, am))


## Soft light behind the rig monitor: one smooth radial gradient (was 12 stacked discs, which
## banded visibly). Same peak (~0.30 alpha at the centre) and 624 px reach as before.
static func room_glow_texture() -> GradientTexture2D:
	if _room_glow_tex != null:
		return _room_glow_tex
	var g := Gradient.new()
	var c := Color(60.0 / 255.0, 90.0 / 255.0, 140.0 / 255.0)
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(c, 0.30), Color(c, 0.16), Color(c, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_room_glow_tex = tex
	return tex


## Soft round-lens mask: two overlapping circular openings, a dark bridge between them and a
## vignette inside each opening. Generated once, only scaled per frame.
func _ensure_mask() -> void:
	if _mask_tex != null:
		return
	var img := Image.create(MASK_W, MASK_H, false, Image.FORMAT_RGBA8)
	var r := 82.5
	var c1 := Vector2(195.0, 135.0)
	var c2 := Vector2(285.0, 135.0)
	for y in range(MASK_H):
		for x in range(MASK_W):
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := minf(pt.distance_to(c1), pt.distance_to(c2)) / r
			var a := smoothstep(0.80, 1.0, d)
			a = maxf(a, 0.40 * smoothstep(0.45, 0.80, d))
			var bx := 1.0 - smoothstep(0.0, 9.0, absf(pt.x - 240.0))
			var by := 1.0 - smoothstep(35.0, 75.0, absf(pt.y - 135.0))
			a = maxf(a, 0.92 * bx * by)
			img.set_pixel(x, y, Color(0.008, 0.016, 0.04, a))
	_mask_tex = ImageTexture.create_from_image(img)


## close: 0..1 closing scale; open: 0..1 opening/dissolve. Reduce motion: no scaling, alpha only.
func _draw_lens_mask(close: float, open: float, rm: bool) -> void:
	_ensure_mask()
	var scale_f := 1.0
	var alpha := 1.0
	if rm:
		alpha = close * (1.0 - open)
	elif open > 0.0:
		scale_f = lerpf(1.0, MASK_FAR_SCALE, open)
		alpha = 1.0 - open
	else:
		scale_f = lerpf(MASK_FAR_SCALE, 1.0, close)
	if alpha <= 0.0:
		return
	draw_texture_rect(_mask_tex, Rect2(960.0 - 960.0 * scale_f, 540.0 - 540.0 * scale_f,
		W * scale_f, H * scale_f), false, Color(1, 1, 1, alpha))


func _draw_crt(q: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	var pa := minf(q / 0.35, 1.0)
	var pb := maxf((q - 0.35) / 0.65, 0.0)
	var bar_w := maxf(8.0, W * IntroTimeline.ease_out(pa))
	var bar_h := 4.0 + (H - 4.0) * IntroTimeline.ease_out(pb)
	draw_rect(Rect2(960.0 - bar_w * 0.5, 540.0 - bar_h * 0.5, bar_w, bar_h),
		Color(235.0 / 255.0, 250.0 / 255.0, 1.0, 1.0 - pb * 0.85))
	if pb > 0.0:
		var peak := 0.9 if mode == IntroTimeline.Mode.FULL else 0.6
		if Settings.reduce_motion:
			peak = 0.0
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, peak * (1.0 - pb)))


func _draw_link_text(t: float) -> void:
	var q := (t - IntroTimeline.FULL_BLACK_END) / (IntroTimeline.FULL_CRT_END - IntroTimeline.FULL_BLACK_END)
	if q < 0.2 or t >= 2.15:
		return
	var pb := maxf((q - 0.35) / 0.65, 0.0)
	var col := INK if pb < 0.56 else TEAL
	var a := 1.0
	if t > IntroTimeline.FULL_CRT_END:
		a = 1.0 - clampf((t - IntroTimeline.FULL_CRT_END) / (2.15 - IntroTimeline.FULL_CRT_END), 0.0, 1.0)
	_draw_spaced("LINK ESTABLISHED", 960.0, 547.0, Palette.SIZE_LABEL, Palette.alpha(col, a), 2.0)


func _draw_spaced(text: String, cx: float, y: float, size: int, col: Color, spacing: float) -> void:
	var font := Palette.font()
	var total := 0.0
	for ch in text:
		total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	total -= spacing
	var x := cx - total * 0.5
	for ch in text:
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing


func _draw_count() -> void:
	if _state != State.COUNT:
		# Skipped but Gameplay has not begun the conductor yet: just the dip.
		_draw_dip()
		return
	var st := _conductor.song_time()
	var n := IntroTimeline.count_number(st, _spb, _beats)
	if n > 0:
		_draw_numeral(str(n), IntroTimeline.beat_fraction(st, _spb))
	elif st >= 0.0:
		var dp := IntroTimeline.dive_progress(st, _is_quick())
		if dp >= 0.0:
			_draw_numeral("DIVE", dp)
	_draw_dip()


func _draw_dip() -> void:
	if not _skipped or Settings.reduce_motion or _skip_usec == 0:
		return
	var d := float(Time.get_ticks_usec() - _skip_usec) / 1000000.0
	var a := 1.0 - clampf(d / SKIP_DIP_SEC, 0.0, 1.0)
	if a > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, a))


func _draw_numeral(text: String, p: float) -> void:
	var size := NUMERAL_SIZE
	if not Settings.reduce_motion:
		size = int(round(float(NUMERAL_SIZE) * (1.2 - 0.2 * p)))
	var alpha := 1.0 - clampf(p, 0.0, 1.0)
	var font := Palette.bold()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(960.0 - w * 0.5, NUMERAL_BASELINE)
	if not Settings.low_effects:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 12,
			Palette.alpha(TEAL, 0.3 * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.alpha(TEXT_COL, alpha))
