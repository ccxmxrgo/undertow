class_name IncomingAlert
extends Control
## Alert slot for the local seat's incoming / active threat (03-UI-SPEC 6.3, TORP-04, D-04,
## D-05, D-17). Rect x 640..1280, y 120..192, directly above the section banner: a declared
## centre-band exception (UI-SPEC 6.1, above the vanishing point and outside the note path), so
## its keep-out is its fixed rect. CUT_SM glass (ABYSS_700 at HUD_GLASS_ALPHA), padding 16.
## States: INCOMING (launch -> arrival) -> ACTIVE (arrival -> payload end) -> ENDED (fade out),
## plus the 1.2 s result states REFLECTED / ABSORBED / COLLISION (then a 0.3 s fade).
## Telegraph lead: INCOMING becomes visible at the TORPEDO_LAUNCH time (first_visible_t), at
## least torpedo_travel_beats before arrive_t; the sonar ping (VersusSfx) is requested at the
## same moment and EdgeFlash pulses from the same event.
## Beat-locked parts (countdown ring, duration line, "{n} BARS LEFT") follow observe(song_time);
## fades / slide / cross-fade follow step(dt). Only events involving the local seat change it.
## Malformed events (T-03-28): .get() with defaults, fractions clamped 0..1, unknown seats "?".
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts()
## (Reduce motion: fade only, no slide, no burst growth; Low effects: no panel glow).

enum State { HIDDEN, INCOMING, ACTIVE, REFLECTED, ABSORBED, COLLISION, ENDED }

const RECT := Rect2(640.0, 120.0, 640.0, 72.0)
const PAD := 16.0
const RING_C := Vector2(40.0, 36.0)  # (680, 156) global
const RING_R := 24.0
const RING_W := 3.0
const GLYPH_RECT := Rect2(24.0, 20.0, 32.0, 32.0)  # (664, 140) global
const CAPTION_X := 80.0  # x 720
const CAPTION_BASE_Y := 26.0  # baseline 146
const CAPTION_MAX := 232.0
const HINT_RIGHT_X := 624.0  # x 1264
const HINT_MAX := 296.0
const HEADLINE_BASE_Y := 64.0  # baseline 184
const HEADLINE_MAX := 528.0
const LINE_Y := 70.0  # y 190..192
const LINE_H := 2.0
const SLIDE_PX := 16.0
const XFADE_SEC := 0.12
const RESULT_HOLD_SEC := 1.2
const OUT_SEC := 0.3
const BURST_SEC := 0.3
const BURST_GROW := 12.0
const ACTIVE_EDGE_ALPHA := 0.6
const BRACKET_ALPHA := 0.8
const SEP := " · "

var _channel: EventChannel
var _local_seat: int = 0
var _names: Array = []
var _chart: ChartData
var _cfg: VersusConfig
var _sfx: VersusSfx

var _state: State = State.HIDDEN
var _id: int = -1
var _from: int = -1
var _reward: int = -1
var _reflected: bool = false
var _debris: bool = false
var _launch_t: float = 0.0
var _arrive_t: float = 0.0
var _start_t: float = 0.0
var _end_t: float = 0.0
var _first_visible_t: float = -1.0
var _warheads_n: int = 0
var _k: int = 0
var _failed: bool = false
var _decoy_armed: bool = false
var _t: float = 0.0

var _caption: String = ""
var _caption_col: Color = Palette.WARNING_RED
var _hint: String = ""
var _hint_col: Color = Palette.TEXT_MID
var _headline: String = ""
var _prev: Dictionary = {}
var _xfade_left: float = 0.0
var _alpha: float = 0.0
var _in_t: float = 0.0
var _result_left: float = 0.0
var _burst_t: float = -1.0
var _reduce: bool = false
var _low: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	UiKit.register_fx(self)
	apply_effect_settings()


## chart / cfg may be null (bars-left then falls back to the payload's configured bars).
func bind(channel: EventChannel, local_seat: int, names: Array, chart: ChartData, cfg: VersusConfig,
		sfx: VersusSfx = null) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_local_seat = local_seat
	_names = names.duplicate()
	_chart = chart
	_cfg = cfg if cfg != null else VersusConfig.new()
	_sfx = sfx
	if _channel != null:
		_channel.received.connect(on_event)


func _name(seat: int) -> String:
	if seat < 0 or seat >= _names.size():
		return "?"
	var s := str(_names[seat]).strip_edges().to_upper()
	return s if s != "" else "?"


# ---- Events ------------------------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("to", -1)) == _local_seat:
				_on_launch(e)
		GameEvent.LANDED:
			if int(e.get("to", -1)) == _local_seat:
				_on_landed(e)
		GameEvent.WARHEAD:
			if int(e.get("seat", -1)) == _local_seat and int(e.get("id", -2)) == _id:
				_on_warhead(e)
		GameEvent.REFLECTED:
			if int(e.get("by", -1)) == _local_seat:
				_on_result(State.REFLECTED, e)
		GameEvent.ABSORBED:
			if int(e.get("to", -1)) == _local_seat:
				_on_result(State.ABSORBED, e)
		GameEvent.COLLISION:
			if int(e.get("a", -1)) == _local_seat or int(e.get("b", -1)) == _local_seat:
				_on_result(State.COLLISION, e)
		GameEvent.PAYLOAD_END:
			if int(e.get("seat", -1)) == _local_seat and int(e.get("id", -2)) == _id \
					and (_state == State.ACTIVE or _state == State.INCOMING):
				_end()
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == _local_seat and int(e.get("reward", -1)) == Reward.Id.DECOY_FLARE:
				_decoy_armed = true
				_refresh_texts()
		GameEvent.BUFF_ENDED:
			if int(e.get("seat", -1)) == _local_seat and int(e.get("reward", -1)) == Reward.Id.DECOY_FLARE:
				_decoy_armed = false
				_refresh_texts()


func _on_launch(e: Dictionary) -> void:
	_id = int(e.get("id", -1))
	_from = int(e.get("from", -1))
	_reward = int(e.get("reward", -1))
	_reflected = bool(e.get("reflected", false))
	_debris = bool(e.get("debris", false))
	_launch_t = float(e.get("launch_t", e.get("t", 0.0)))
	_arrive_t = float(e.get("arrive_t", _launch_t))
	if not is_finite(_launch_t):
		_launch_t = 0.0
	if not is_finite(_arrive_t) or _arrive_t < _launch_t:
		_arrive_t = _launch_t
	var wh: Variant = e.get("warheads", [])
	_warheads_n = (wh as Array).size() if wh is Array else 0
	_k = 0
	_failed = false
	_first_visible_t = _launch_t
	_t = maxf(_t, _launch_t)
	_burst_t = -1.0
	_set_state(State.INCOMING)
	if _sfx != null and is_instance_valid(_sfx):
		_sfx.ping(_id)


func _on_landed(e: Dictionary) -> void:
	var id := int(e.get("id", -1))
	if id != _id:
		# Landed without a launch we saw (bound late): show it with what LANDED carries.
		_id = id
		_warheads_n = 0
		_k = 0
		_failed = false
		_reflected = bool(e.get("reflected", false))
		_debris = bool(e.get("debris", false))
	_from = int(e.get("from", _from))
	_reward = int(e.get("reward", _reward))
	_arrive_t = float(e.get("arrive_t", e.get("t", _arrive_t)))
	_start_t = float(e.get("active_start", _arrive_t))
	_end_t = float(e.get("end_t", _start_t))
	if not is_finite(_start_t):
		_start_t = _arrive_t
	if not is_finite(_end_t) or _end_t < _start_t:
		_end_t = _start_t
	if _reflected or _debris:
		_warheads_n = 0
	_set_state(State.ACTIVE)


func _on_warhead(e: Dictionary) -> void:
	var n := int(e.get("n", _warheads_n))
	if n > 0:
		_warheads_n = n
	if bool(e.get("ok", false)):
		_k = clampi(int(e.get("k", _k)), 0, maxi(_warheads_n, 0))
	else:
		_failed = true
	_refresh_texts()


func _on_result(s: State, e: Dictionary) -> void:
	match s:
		State.REFLECTED:
			_id = int(e.get("id", _id))
			_from = int(e.get("to", _from))  # the original shooter
			_reward = int(e.get("reward", _reward))
		State.ABSORBED:
			_id = int(e.get("id", _id))
			_from = int(e.get("from", _from))
			_reward = int(e.get("reward", _reward))
		State.COLLISION:
			_burst_t = 0.0
	_result_left = RESULT_HOLD_SEC
	_set_state(s)


func _end() -> void:
	_set_state(State.ENDED)


func _set_state(s: State) -> void:
	var was_visible := _state != State.HIDDEN and _alpha > 0.0
	if was_visible and s != State.ENDED:
		_prev = {"caption": _caption, "caption_col": _caption_col, "hint": _hint, "hint_col": _hint_col,
			"headline": _headline}
		_xfade_left = XFADE_SEC
	elif not was_visible:
		_prev = {}
		_xfade_left = 0.0
		_in_t = 0.0
	_state = s
	_refresh_texts()
	_apply_visual()


# ---- Texts -------------------------------------------------------------------------------

func _refresh_texts() -> void:
	var from_name := _name(_from)
	var hud := Reward.hud_name(_reward)
	match _state:
		State.INCOMING:
			_caption_col = Palette.WARNING_RED
			if _debris:
				_caption = "WRECK DEBRIS" + SEP + from_name
			elif _reflected:
				_caption = "REFLECTED BY " + from_name
			else:
				_caption = "INCOMING" + SEP + from_name
			if _decoy_armed and not _debris:
				_hint = "DECOY WILL ABSORB"
				_hint_col = Palette.SONAR
			elif _warheads_n <= 0 or _reflected or _debris:
				_hint = "CANNOT BE REFLECTED"
				_hint_col = Palette.TEXT_LO
			else:
				_hint = "HIT RINGED NOTES PERFECT"
				_hint_col = Palette.TEXT_MID
			_headline = hud
		State.ACTIVE:
			_caption = "ACTIVE" + SEP + from_name
			_caption_col = Palette.WARNING_RED
			if _warheads_n > 0 and not _failed and _k < _warheads_n:
				_hint = "REFLECT %d/%d" % [_k, _warheads_n]
				_hint_col = Palette.SONAR_PALE
			else:
				var n := bars_left()
				_hint = ("%d BAR LEFT" if n == 1 else "%d BARS LEFT") % n
				_hint_col = Palette.TEXT_MID
			_headline = hud
		State.REFLECTED:
			_caption = "REFLECTED"
			_caption_col = Palette.SONAR_PALE
			_hint = ""
			_headline = "BACK TO " + from_name
		State.ABSORBED:
			_caption = "DECOY ABSORBED"
			_caption_col = Palette.SONAR
			_hint = ""
			_headline = hud
		State.COLLISION:
			_caption = "HEAD-ON COLLISION"
			_caption_col = Palette.TEXT_HI
			_hint = ""
			_headline = "BOTH TORPEDOES DESTROYED"
	queue_redraw()


## Whole bars left in the active payload at the observed song time (rounded up, >= 0).
func bars_left() -> int:
	var t := maxf(_t, _start_t)
	if t >= _end_t:
		return 0
	if _chart != null and not _chart.tempo_map.is_empty():
		var tm: Array = _chart.tempo_map
		var beats := BeatClock.beat_at(_end_t, tm) - BeatClock.beat_at(t, tm)
		var per_bar := MatchSim.bar_beats_at(t, _chart)
		return maxi(ceili(beats / maxf(per_bar, 1e-6) - 1e-6), 0)
	var bars := _cfg.bars_for(_reward) if _cfg != null else 1
	var frac := (_end_t - t) / maxf(_end_t - _start_t, 1e-6)
	return maxi(ceili(float(bars) * frac - 1e-6), 0)


# ---- Time --------------------------------------------------------------------------------

## Beat-locked update from the song clock (ring, duration line, bars left).
func observe(song_time: float) -> void:
	if not is_finite(song_time):
		return
	_t = song_time
	if _state == State.ACTIVE:
		if _t > _end_t + 0.5:
			_end()  # safety net if PAYLOAD_END never arrives
			return
		var before := _hint
		_refresh_texts()
		if before != _hint:
			queue_redraw()
	queue_redraw()


## Advance fades / slide / cross-fade / result holds by dt seconds.
func step(dt: float) -> void:
	if dt <= 0.0 or _state == State.HIDDEN:
		return
	_in_t += dt
	if _xfade_left > 0.0:
		_xfade_left = maxf(_xfade_left - dt, 0.0)
	if _burst_t >= 0.0:
		_burst_t += dt
		if _burst_t >= BURST_SEC:
			_burst_t = -1.0
	match _state:
		State.ENDED:
			_alpha = maxf(_alpha - dt / OUT_SEC, 0.0)
			if _alpha <= 0.0:
				_state = State.HIDDEN
				_prev = {}
		State.REFLECTED, State.ABSORBED, State.COLLISION:
			_alpha = minf(_alpha + dt / Palette.DUR_FAST, 1.0)
			_result_left -= dt
			if _result_left <= 0.0:
				_state = State.ENDED
		_:
			_alpha = minf(_alpha + dt / Palette.DUR_FAST, 1.0)
	_apply_visual()


func _apply_visual() -> void:
	visible = _state != State.HIDDEN
	modulate.a = _alpha
	queue_redraw()


func _process(delta: float) -> void:
	step(delta)


# ---- Getters -----------------------------------------------------------------------------

func state() -> State:
	return _state


func caption_text() -> String:
	return _caption if _state != State.HIDDEN else ""


func caption_color() -> Color:
	return _caption_col


func hint_text() -> String:
	return _hint if _state != State.HIDDEN else ""


func hint_color() -> Color:
	return _hint_col


func headline_text() -> String:
	return _headline if _state != State.HIDDEN else ""


## Song time the current threat's alert became visible (its TORPEDO_LAUNCH time), -1 if none.
func first_visible_t() -> float:
	return _first_visible_t


func arrive_t() -> float:
	return _arrive_t


func alpha() -> float:
	return _alpha


func is_showing() -> bool:
	return _state != State.HIDDEN


## Remaining share of the countdown ring (1 = full, 0 = drained), clamped 0..1.
func ring_fraction() -> float:
	match _state:
		State.INCOMING:
			if _arrive_t <= _launch_t:
				return 0.0
			return clampf((_arrive_t - _t) / (_arrive_t - _launch_t), 0.0, 1.0)
		State.ACTIVE, State.ENDED:
			if _end_t <= _start_t:
				return 0.0
			return clampf((_end_t - maxf(_t, _start_t)) / (_end_t - _start_t), 0.0, 1.0)
		State.REFLECTED:
			return 1.0
	return 0.0


## Vertical draw offset of the appear slide: -16 px -> 0 over DUR_FAST (0 under Reduce motion).
func slide_offset() -> float:
	if _reduce or _state != State.INCOMING or _in_t >= Palette.DUR_FAST or _prev.size() > 0:
		return 0.0
	var k := clampf(_in_t / Palette.DUR_FAST, 0.0, 1.0)
	var u := 1.0 - k
	return -SLIDE_PX * u * u * u


func is_cross_fading() -> bool:
	return _xfade_left > 0.0


# ---- Effects -----------------------------------------------------------------------------

func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"slide": not _reduce, "glow": not _low, "burst_grow": not _reduce}


## W4 keep-out: the fixed slot rect (declared centre-band exception, UI-SPEC 6.1), global space.
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var r := Rect2(Vector2.ZERO, RECT.size)
	return [PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
		xf * Vector2(r.position.x, r.end.y)])]


# ---- Drawing -----------------------------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var edge := Palette.alpha(Palette.SONAR, 0.45)
	match _state:
		State.INCOMING:
			edge = Palette.WARNING_RED
		State.ACTIVE:
			edge = Palette.alpha(Palette.WARNING_RED, ACTIVE_EDGE_ALPHA)
	var sb := UiKit.chamfer_box(Color(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA), edge, Palette.EDGE, Palette.CUT_SM)
	sb.shadow_color = Palette.alpha(Palette.SONAR, Palette.PANEL_GLOW_ALPHA)
	sb.shadow_size = 0 if _low else Palette.PANEL_GLOW_SIZE
	sb.shadow_offset = Vector2.ZERO
	sb.set_content_margin_all(PAD)
	return sb


func _draw() -> void:
	if _state == State.HIDDEN:
		return
	var oy := slide_offset()
	var r := Rect2(Vector2(0.0, oy), RECT.size)
	draw_style_box(_panel_style(), r)
	var bracket := Palette.alpha(Palette.SONAR, BRACKET_ALPHA)
	if _state == State.INCOMING:
		bracket = Palette.WARNING_RED
	elif _state == State.ACTIVE:
		bracket = Palette.alpha(Palette.WARNING_RED, ACTIVE_EDGE_ALPHA)
	UiKit.draw_brackets(self, r, bracket)
	var off := Vector2(0.0, oy)
	_draw_ring(off)
	if _reward >= 0 and _state != State.COLLISION:
		UiIcons.draw(self, Reward.glyph(_reward), Rect2(GLYPH_RECT.position + off, GLYPH_RECT.size), Palette.TEXT_HI)
	var k := 1.0 - _xfade_left / XFADE_SEC if _xfade_left > 0.0 else 1.0
	if _xfade_left > 0.0 and not _prev.is_empty():
		_draw_texts(off, str(_prev["caption"]), _prev["caption_col"], str(_prev["hint"]), _prev["hint_col"],
			str(_prev["headline"]), 1.0 - k)
	_draw_texts(off, _caption, _caption_col, _hint, _hint_col, _headline, k)
	if _state == State.ACTIVE or (_state == State.ENDED and _end_t > _start_t):
		var f := ring_fraction()
		var x0 := (1.0 - f) * RECT.size.x
		draw_rect(Rect2(x0, LINE_Y + oy, RECT.size.x - x0, LINE_H), Palette.alpha(Palette.WARNING_RED, ACTIVE_EDGE_ALPHA))


func _draw_ring(off: Vector2) -> void:
	var c := RING_C + off
	match _state:
		State.INCOMING, State.ACTIVE, State.ENDED:
			var col := Palette.WARNING_RED if _state == State.INCOMING else Palette.alpha(Palette.WARNING_RED, ACTIVE_EDGE_ALPHA)
			draw_arc(c, RING_R, 0.0, TAU, 48, Palette.alpha(col, 0.2), 1.0, true)
			var f := ring_fraction()
			if f > 0.0:
				draw_arc(c, RING_R, -PI * 0.5, -PI * 0.5 + TAU * f, 48, col, RING_W, true)
		State.REFLECTED:
			var a := clampf(_result_left / RESULT_HOLD_SEC, 0.0, 1.0)
			draw_arc(c, RING_R, 0.0, TAU, 48, Palette.alpha(Palette.SONAR_PALE, 0.4 + 0.6 * a), RING_W, true)
		State.COLLISION:
			if _burst_t >= 0.0:
				var s := clampf(_burst_t / BURST_SEC, 0.0, 1.0)
				var rr := RING_R + (BURST_GROW * s if not _reduce else 0.0)
				draw_arc(c, rr, 0.0, TAU, 48, Palette.alpha(Palette.TEXT_HI, 1.0 - s), RING_W, true)
				for i in range(6):
					var ang := TAU * float(i) / 6.0
					var d := Vector2(cos(ang), sin(ang))
					draw_line(c + d * (RING_R * 0.4), c + d * rr * 0.8, Palette.alpha(Palette.WARNING_RED, 1.0 - s), 2.0, true)


func _draw_texts(off: Vector2, caption: String, caption_col: Color, hint: String, hint_col: Color,
		headline: String, a: float) -> void:
	if a <= 0.0:
		return
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	if caption != "":
		var c := ProgressTrack.truncate_px(caption, f, fs, CAPTION_MAX)
		draw_string(f, Vector2(CAPTION_X, CAPTION_BASE_Y) + off, c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.alpha(caption_col, caption_col.a * a))
	if hint != "":
		var h := ProgressTrack.truncate_px(hint, f, fs, HINT_MAX)
		var w := f.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(HINT_RIGHT_X - w, CAPTION_BASE_Y) + off, h, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.alpha(hint_col, hint_col.a * a))
	if headline != "":
		var df := Palette.display_font()
		var hs := Palette.SIZE_HEADING
		var hl := ProgressTrack.truncate_px(headline, df, hs, HEADLINE_MAX)
		draw_string(df, Vector2(CAPTION_X, HEADLINE_BASE_Y) + off, hl, HORIZONTAL_ALIGNMENT_LEFT, -1, hs,
			Palette.alpha(Palette.TEXT_HI, a))
