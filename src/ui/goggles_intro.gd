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
var _frame_sb: StyleBoxFlat
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
	_frame_sb = StyleBoxFlat.new()
	_frame_sb.bg_color = Color("10131D")
	_frame_sb.set_corner_radius_all(110)
	_frame_sb.set_border_width_all(8)
	_frame_sb.border_color = Color("2F3550")
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
		IntroTimeline.Phase.ROOM_GOGGLES:
			_draw_room(t)
			if rm:
				_draw_goggles(IntroTimeline.FULL_GOGGLES_END, clampf((t - 0.4) / 0.4, 0.0, 1.0))
			else:
				_draw_goggles(t, 1.0)
		IntroTimeline.Phase.BLACK:
			draw_rect(Rect2(0, 0, W, H), Color.BLACK)
		IntroTimeline.Phase.CRT:
			if rm:
				draw_rect(Rect2(0, 0, W, H), Color.BLACK)
			else:
				_draw_crt(p)
		IntroTimeline.Phase.ARENA:
			if rm:
				pass  # cross-fade is the board reveal itself
	if mode == IntroTimeline.Mode.FULL and not rm:
		_draw_link_text(t)
	if _hint_visible(t, phase):
		var txt := "A TO SKIP" if _pad_last else "SPACE TO SKIP"
		_draw_spaced(txt, 960.0, 1040.0, Palette.SIZE_LABEL, Palette.alpha(HINT_COL, 0.7), 2.0)


func _hint_visible(t: float, phase: int) -> bool:
	if mode != IntroTimeline.Mode.FULL:
		return false
	if phase == IntroTimeline.Phase.ROOM_GOGGLES:
		return t >= 0.3
	return phase == IntroTimeline.Phase.ARENA


func _draw_room(t: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color("07070B"))
	var glow_c := Vector2(1380, 504)
	for i in range(12):
		var r := 624.0 * (1.0 - float(i) / 12.0)
		draw_circle(glow_c, r, Color(60.0 / 255.0, 90.0 / 255.0, 140.0 / 255.0, 0.35 / 12.0))
	draw_rect(Rect2(0, 768, 1920, 312), Color("0F1118"))
	draw_rect(Rect2(1200, 360, 360, 228), Color("161A26"))
	draw_rect(Rect2(1214, 374, 331, 199), Color(80.0 / 255.0, 140.0 / 255.0, 200.0 / 255.0, 0.25))
	draw_rect(Rect2(216, 192, 192, 276), Color("12141C"))
	draw_rect(Rect2(456, 240, 144, 192), Color("12141C"))
	var font := Palette.font()
	draw_string(font, Vector2(1236, 480), "NEURAL DIVE RIG · READY", HORIZONTAL_ALIGNMENT_LEFT,
		-1, Palette.SIZE_LABEL, Color(0.91, 0.90, 0.94, 0.35))
	var rec_on := Settings.reduce_motion or fmod(t, 1.0) < 0.5
	if rec_on:
		draw_circle(Vector2(1216, 474), 5.0, HOT_RED)


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_goggles(t: float, alpha: float) -> void:
	var s := IntroTimeline.goggles_scale(t)
	var y := IntroTimeline.goggles_y(t)
	draw_set_transform(Vector2(960.0, y), 0.0, Vector2(s, s))
	var strap := PackedVector2Array()
	for i in range(21):
		var u := float(i) / 20.0
		var a := Vector2(-420, -10)
		var b := Vector2(0, -120)
		var c := Vector2(420, -10)
		strap.append(a.lerp(b, u).lerp(b.lerp(c, u), u))
	draw_polyline(strap, Color(0.102, 0.114, 0.157, alpha), 26.0, true)
	_frame_sb.bg_color.a = alpha
	_frame_sb.border_color.a = alpha
	draw_style_box(_frame_sb, Rect2(-330, -110, 660, 220))
	for x in [-150.0, 150.0]:
		for i in range(8):
			var u := float(i) / 7.0
			var col := Color(2.0 / 255.0, 4.0 / 255.0, 10.0 / 255.0, 0.95).lerp(
				Color(5.0 / 255.0, 217.0 / 255.0, 232.0 / 255.0, 0.35), u)
			col.a *= alpha
			var k := 1.0 - u * 0.85
			draw_colored_polygon(_ellipse(Vector2(x - 30.0 * u, -30.0 * u), 130.0 * k, 88.0 * k), col)
		var rim := _ellipse(Vector2(x, 0.0), 130.0, 88.0)
		rim.append(rim[0])
		draw_polyline(rim, Color(1.0, 31.0 / 255.0, 75.0 / 255.0, 0.55 * alpha), 6.0, true)
	var led := HOT_RED if t / IntroTimeline.FULL_GOGGLES_END > 0.6 else Color("552030")
	led.a = alpha
	draw_circle(Vector2(0, -70), 7.0, led)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
