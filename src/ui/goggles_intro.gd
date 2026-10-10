class_name GogglesIntro
extends Control
## Goggles-on intro overlay (D-10..D-12). Pure presentation: pre-count runs on the wall clock
## before the Conductor starts (IntroTimeline drives what is shown); Gameplay then begins the
## conductor lead-in and calls on_count_started(), after which the 3-2-1 numerals derive from
## Conductor.song_time(). While it plays it also drives the board reveal (arena, cables,
## receptors, HUD) and restores the board defaults when it ends or leaves the tree (T-1.2-12).
## 02.2-20 (UI-SPEC 9.5, D-12): the room segment is replaced by the rig-boot stage (sonar ping
## rings and "NEURAL DIVE RIG · READY" typed in, under the closing lens mask). The stage
## boundaries come from IntroTimeline and are unchanged. Colours are Palette tokens only.
## Effect node (UiKit contract): rig rings static under Reduce motion, numeral glow off on Low.

signal pre_count_finished
signal skip_requested

enum State { PRE, COUNT, DONE }

const W := 1920.0
const H := 1080.0
## Count numerals: the Cinematic 176 Oxanium exception (UI-SPEC 3.2), animated 211 -> 176.
const NUMERAL_SIZE := 176
const NUMERAL_FROM := 1.2
const NUMERAL_BASELINE := 624.0
const NUMERAL_GLOW_ALPHA := 0.3
const NUMERAL_GLOW_SIZE := 12
## Rig boot (UI-SPEC 9.5): two SONAR ping rings and the typed rig line.
const RIG_CENTER := Vector2(960, 540)
const RING_STARTS: Array[float] = [0.05, 0.45]
const RING_SEC := 0.7
const RING_MAX_R := 420.0
const RING_ALPHA := 0.35
const RING_W := 2.0
const RING_STATIC_R := 300.0
const RING_STATIC_ALPHA := 0.2
const RIG_TEXT := "NEURAL DIVE RIG · READY"
const RIG_TEXT_AT := Vector2(960, 548)
const RIG_TEXT_FROM := 0.10
const RIG_CHARS_PER_SEC := 40.0
## Soft SONAR-tinted backlight behind the rig line (cached gradient, see room_glow_texture).
const BACKLIGHT_R := 560.0
## Static scope under the pings: faint range rings and a crosshair with a gap for the text.
const SCOPE_RINGS: Array[float] = [140.0, 280.0, 420.0]
const SCOPE_RING_ALPHA := 0.07
const SCOPE_CROSS_ALPHA := 0.05
const SCOPE_CROSS_GAP := 180.0
const SCOPE_CROSS_REACH := 470.0
const HINT_ALPHA := 0.7
const SKIP_DIP_SEC := 0.12
const HUD_FADE_SEC := 0.3
const MASK_W := 480
const MASK_H := 270
const MASK_FAR_SCALE := 7.5

static var _room_glow_tex: GradientTexture2D
static var _mask_tex: ImageTexture

var mode: int = IntroTimeline.Mode.FULL
var _state: State = State.PRE
var _conductor: Conductor
var _arena: Arena
var _highway: Highway
var _hud: Control
var _streak: Control
var _spb: float = 0.5
var _bpm: float = 120.0
var _beats: int = 3
var _origin_usec: int = 0
var _emitted: bool = false
var _skipped: bool = false
var _skip_usec: int = 0
var _last_phase: int = -1
var _last_number: int = 0
var _dive_played: bool = false
var _pad_last: bool = false
var _sfx: AudioStreamPlayer
var _tick: AudioStreamWAV
var _tick_hi: AudioStreamWAV
var _clunk: AudioStreamWAV
var _reduce := false
var _low := false


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_effect_settings()
	UiKit.register_fx(self)


## Effect contract: re-read Reduce motion / Low effects (rig rings, numeral glow).
func apply_effect_settings() -> void:
	_reduce = UiKit.reduce_motion()
	_low = UiKit.low_effects()
	queue_redraw()


## Effect contract: what is active right now.
func effect_counts() -> Dictionary:
	return {"rings_animated": not _reduce, "numeral_glow": not _low}


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
	_bpm = bpm
	_spb = IntroTimeline.seconds_per_beat(bpm)
	_build_sfx()
	_set_board(0.0, 0.0, 1.0, 0.0, 0.0)
	# Build the (cached) lens mask BEFORE the wall clock starts so a first-time generation
	# hitch cannot eat the lens-close animation (WR-02).
	if arena_draws_lens(mode):
		lens_mask_texture()
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
	_spb = IntroTimeline.count_beat_seconds(_beats, _bpm)  # matches the bounded lead-in
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
			_draw_rig_boot(t, rm)
			_draw_lens_mask(IntroTimeline.lens_close(t, mode, rm), 0.0, rm)
			_draw_rig_text(t, rm)  # the rig readout sits in the goggles, above the lens bridge
		IntroTimeline.Phase.BLACK:
			draw_rect(Rect2(0, 0, W, H), Palette.ABYSS_900)
		IntroTimeline.Phase.CRT:
			if rm:
				draw_rect(Rect2(0, 0, W, H), Palette.ABYSS_900)
			else:
				_draw_crt(p)
		IntroTimeline.Phase.ARENA:
			if arena_draws_lens(mode):
				_draw_lens_mask(1.0, IntroTimeline.lens_open(t, mode, rm), rm)
	if mode == IntroTimeline.Mode.FULL and not rm:
		_draw_link_text(t)
	if _hint_visible(t, phase):
		var txt := "A TO SKIP" if _pad_last else "SPACE TO SKIP"
		_draw_spaced(txt, 960.0, 1040.0, Palette.SIZE_LABEL, Color(Palette.TEXT_LO, HINT_ALPHA), 2.0)


## Only the FULL intro has a lens mask; the QUICK intro is a CRT blink plus one count (D-11),
## so its ARENA phase must show the board, not a closed mask (CR-01).
static func arena_draws_lens(p_mode: int) -> bool:
	return p_mode == IntroTimeline.Mode.FULL


func _hint_visible(t: float, phase: int) -> bool:
	if mode != IntroTimeline.Mode.FULL:
		return false
	if phase == IntroTimeline.Phase.ROOM_LENS:
		return t >= 0.3
	return phase == IntroTimeline.Phase.ARENA


## Rig boot (0.00..1.10 s of the FULL intro; the Reduce-motion variant uses the same stage):
## ABYSS_900, a soft SONAR backlight, two expanding ping rings and the typed rig line.
func _draw_rig_boot(t: float, rm: bool) -> void:
	draw_rect(Rect2(0, 0, W, H), Palette.ABYSS_900)
	draw_texture_rect(room_glow_texture(), Rect2(RIG_CENTER - Vector2(BACKLIGHT_R, BACKLIGHT_R),
		Vector2(BACKLIGHT_R, BACKLIGHT_R) * 2.0), false)
	for r: float in SCOPE_RINGS:
		draw_arc(RIG_CENTER, r, 0.0, TAU, 96, Color(Palette.SONAR, SCOPE_RING_ALPHA), Palette.EDGE_HAIR, true)
	var cross := Color(Palette.SONAR, SCOPE_CROSS_ALPHA)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT]:
		draw_line(RIG_CENTER + d * SCOPE_CROSS_GAP, RIG_CENTER + d * SCOPE_CROSS_REACH, cross, Palette.EDGE_HAIR)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN]:
		draw_line(RIG_CENTER + d * 40.0, RIG_CENTER + d * SCOPE_CROSS_REACH, cross, Palette.EDGE_HAIR)
	for i in RING_STARTS.size():
		var ring := rig_ring(t, i, rm)
		var a: float = ring["a"]
		var r: float = ring["r"]
		if a > 0.0 and r > 0.5:
			draw_arc(RIG_CENTER, r, 0.0, TAU, 96, Color(Palette.SONAR, a), RING_W, true)


func _draw_rig_text(t: float, rm: bool) -> void:
	var n := rig_text_chars(t, rm)
	if n > 0:
		# Typed text keeps its final centred position: draw the visible prefix from the full start x.
		_draw_spaced(RIG_TEXT, RIG_TEXT_AT.x, RIG_TEXT_AT.y, Palette.SIZE_LABEL, Palette.SONAR, 2.0, n)


## Ring `i` at intro time `t`: {r, a}. r 0 -> 420 over 0.7 s from its start, alpha 0.35 -> 0.
## Reduce motion: static r 300 at alpha 0.2.
static func rig_ring(t: float, i: int, rm: bool) -> Dictionary:
	if rm:
		return {"r": RING_STATIC_R, "a": RING_STATIC_ALPHA}
	var k := (t - RING_STARTS[i]) / RING_SEC
	if k < 0.0 or k > 1.0:
		return {"r": 0.0, "a": 0.0}
	return {"r": RING_MAX_R * k, "a": RING_ALPHA * (1.0 - k)}


## Characters of RIG_TEXT shown at intro time `t` (40 chars/s from 0.10 s; all at once under
## Reduce motion).
static func rig_text_chars(t: float, rm: bool) -> int:
	if rm:
		return RIG_TEXT.length()
	return clampi(int(floor((t - RIG_TEXT_FROM) * RIG_CHARS_PER_SEC + 1e-6)), 0, RIG_TEXT.length())


## Soft backlight behind the rig line: one smooth radial gradient (01.2-09 regression: never
## stacked discs). The name is kept from the old room light.
static func room_glow_texture() -> GradientTexture2D:
	if _room_glow_tex != null:
		return _room_glow_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(Palette.VP_GLOW, 0.42), Color(Palette.VP_GLOW, 0.16), Color(Palette.VP_GLOW, 0.0)])
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
## vignette inside each opening. Generated once per process (static), only scaled per frame.
static func lens_mask_texture() -> ImageTexture:
	if _mask_tex != null:
		return _mask_tex
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
			img.set_pixel(x, y, Color(Palette.ABYSS_900, a))
	_mask_tex = ImageTexture.create_from_image(img)
	return _mask_tex


## close: 0..1 closing scale; open: 0..1 opening/dissolve. Reduce motion: no scaling, alpha only.
func _draw_lens_mask(close: float, open: float, rm: bool) -> void:
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
	draw_texture_rect(lens_mask_texture(), Rect2(960.0 - 960.0 * scale_f, 540.0 - 540.0 * scale_f,
		W * scale_f, H * scale_f), false, Color(Palette.WHITE, alpha))


func _draw_crt(q: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Palette.ABYSS_900)
	var pa := minf(q / 0.35, 1.0)
	var pb := maxf((q - 0.35) / 0.65, 0.0)
	var bar_w := maxf(8.0, W * IntroTimeline.ease_out(pa))
	var bar_h := 4.0 + (H - 4.0) * IntroTimeline.ease_out(pb)
	draw_rect(Rect2(960.0 - bar_w * 0.5, 540.0 - bar_h * 0.5, bar_w, bar_h),
		Color(Palette.mix(Palette.SONAR_PALE, Palette.WHITE, 0.6), 1.0 - pb * 0.85))
	if pb > 0.0:
		var peak := 0.9 if mode == IntroTimeline.Mode.FULL else 0.6
		if Settings.reduce_motion:
			peak = 0.0
		draw_rect(Rect2(0, 0, W, H), Color(Palette.WHITE, peak * (1.0 - pb)))


func _draw_link_text(t: float) -> void:
	var q := (t - IntroTimeline.FULL_BLACK_END) / (IntroTimeline.FULL_CRT_END - IntroTimeline.FULL_BLACK_END)
	if q < 0.2 or t >= 2.15:
		return
	var pb := maxf((q - 0.35) / 0.65, 0.0)
	var col := Palette.ABYSS_900 if pb < 0.56 else Palette.SONAR
	var a := 1.0
	if t > IntroTimeline.FULL_CRT_END:
		a = 1.0 - clampf((t - IntroTimeline.FULL_CRT_END) / (2.15 - IntroTimeline.FULL_CRT_END), 0.0, 1.0)
	_draw_spaced("LINK ESTABLISHED", 960.0, 547.0, Palette.SIZE_LABEL, Palette.alpha(col, a), 2.0)


## Letter-spaced text centred on `cx`; only the first `count` characters are drawn (-1 = all),
## at the positions they have in the full string.
func _draw_spaced(text: String, cx: float, y: float, size: int, col: Color, spacing: float,
		count: int = -1) -> void:
	var font := Palette.font()
	var total := 0.0
	for ch in text:
		total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	total -= spacing
	var x := cx - total * 0.5
	var shown := text.length() if count < 0 else mini(count, text.length())
	for i in shown:
		var ch := text[i]
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
		draw_rect(Rect2(0, 0, W, H), Color(Palette.ABYSS_900, a))


## Numeral size for beat progress `p`: 211 -> 176 (Reduce motion: 176).
static func numeral_size(p: float, rm: bool) -> int:
	if rm:
		return NUMERAL_SIZE
	return int(round(float(NUMERAL_SIZE) * (NUMERAL_FROM - (NUMERAL_FROM - 1.0) * clampf(p, 0.0, 1.0))))


static func numeral_font() -> Font:
	return Palette.display_font()


func _draw_numeral(text: String, p: float) -> void:
	var size := numeral_size(p, Settings.reduce_motion)
	var alpha := 1.0 - clampf(p, 0.0, 1.0)
	var font := numeral_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(960.0 - w * 0.5, NUMERAL_BASELINE)
	if not Settings.low_effects:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, NUMERAL_GLOW_SIZE,
			Color(Palette.SONAR, NUMERAL_GLOW_ALPHA * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Palette.TEXT_HI, alpha))
