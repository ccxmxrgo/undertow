class_name EventBanner
extends Control
## Event banner: Solo Duel, Last Hull Standing and your Implosion (03-UI-SPEC 6.4, 03-SPEC
## req 11, D-22, D-24). Full-screen canvas (UiLayout.fill_rect) whose panel uses the section
## banner rect (640, 200, 640, 72) and look (U-4.9): glass ABYSS_700 at HUD_GLASS_ALPHA, CUT_SM.
## Caption Label 20 centred x 960 baseline 224, headline Heading 40 centred baseline 262, right
## caption Label 20 right-aligned x 1264 baseline 224, 2 px SONAR progress line y 270..272 in a
## live duel.
## Priority, highest first: IMPLOSION (yours) > LAST HULL STANDING > SOLO DUEL states > section.
## A higher or equal priority banner replaces the shown one (a replaced banner waits and comes
## back afterwards); a lower one waits until the shown one has faded out. While any event banner
## is visible, the bound SectionBanner.suppressed is true (the section name stays in the
## progress track); it goes back to false when the banner hides.
## Timing: slide down 24 px + fade over DUR_BASE (fade only under Reduce motion). Announce and
## live duel stay until the next duel event; duel result holds 1.6 s, Last Hull Standing and
## Implosion 2.4 s; then a 0.3 s fade. Implosion adds an 8 px horizontal shake over 120 ms (none
## under Reduce motion) and a full-screen WARNING_RED 22% corner vignette fading over 600 ms.
## Keep-out (W4): keepout_shapes() returns the panel rect only. The vignette is a transient
## full-screen tint drawn only for 600 ms after your implosion (like the U-9.2 vignette); it
## carries no information and is excluded from the keep-out contract.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().
## Online-only states (04-UI-SPEC 10.3, 11.7), activated only by start_countdown() and
## show_waiting(), so offline output is unchanged:
## - MATCH START countdown: "ALL SUBS LINKED" / "DIVE IN 3..1" then "DIVE" / "FLIGHT {n} BEATS",
##   a SONAR line draining right to left from the START receipt to song time 0. Highest priority
##   while song_time < 0; "DIVE" holds 600 ms then fades over DUR_SLOW (gone by song_time 0.9).
##   Digit changes cross-fade over DUR_FAST (swap under Reduce motion). Driven by song time.
## - MATCH COMPLETE / WAITING FOR RESULTS / "{n} SUBS STILL DIVING" until hide_waiting().

enum Kind { NONE, DUEL_ANNOUNCE, DUEL_LIVE, DUEL_RESULT, LAST_STANDING, IMPLOSION, COUNTDOWN, WAITING }
enum Phase { IDLE, IN, HOLD, OUT }

const TEXTS_REFRESH_S := 0.1  # live duel texts re-read at 10 Hz (WR-09)
const RECT := Rect2(640.0, 200.0, 640.0, 72.0)
const CAPTION_BASE_Y := 24.0  # 224
const HEADLINE_BASE_Y := 62.0  # 262
const RIGHT_X := 624.0  # 1264
const RIGHT_MAX := 240.0
const LINE_Y := 70.0  # 270..272
const LINE_H := 2.0
const SLIDE_PX := 24.0
const OUT_SEC := 0.3
const XFADE_SEC := 0.12
const HOLD_RESULT := 1.6
const HOLD_LONG := 2.4
const SHAKE_PX := 8.0
const SHAKE_SEC := 0.12
const VIGNETTE_ALPHA := 0.22
const VIGNETTE_SEC := 0.6
const BRACKET_ALPHA := 0.8
const DUEL_STALE_SEC := 1.0
const SEP := " · "
const DIVE_HOLD := 0.6  # "DIVE" holds 600 ms after song time 0 (10.3)
const COUNTDOWN_GONE := DIVE_HOLD + Palette.DUR_SLOW  # 0.9: never shown after song time 0 + 900 ms

var _channel: EventChannel
var _local_seat: int = 0
var _names: Array = []
var _cfg: VersusConfig
var _live_pct: Callable
var _section: SectionBanner
var _dead: Dictionary = {}
var _duel: Dictionary = {}  # {solo, start, end, note_count}
var _t: float = 0.0

var _cur: Dictionary = {}  # {kind, data}
var _pending: Array[Dictionary] = []
var _phase: Phase = Phase.IDLE
var _phase_t: float = 0.0
var _hold: float = -1.0  # -1 = until replaced

var _caption: String = ""
var _caption_col: Color = Palette.REWARD_GOLD
var _headline: String = ""
var _headline_col: Color = Palette.TEXT_HI
var _right: String = ""
var _right_col: Color = Palette.TEXT_MID
var _prev: Dictionary = {}
var _xfade_left: float = 0.0
var _xfade_dur: float = XFADE_SEC
var _cd: Dictionary = {}  # countdown {receipt, beats}
var _shake_t: float = -1.0
var _vignette_t: float = -1.0
var _reduce: bool = false
var _low: bool = false
var _panel_node: Control
var _vignette_tex: GradientTexture2D
var _texts_next: float = -INF
var _style_cache: Dictionary = {}
var _fit_cache: Dictionary = {}


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_node = Control.new()
	_panel_node.name = "Panel"
	_panel_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_node.position = RECT.position
	_panel_node.size = RECT.size
	_panel_node.visible = false
	_panel_node.draw.connect(_draw_panel)
	add_child(_panel_node)
	UiKit.register_fx(self)
	apply_effect_settings()


## live_pct(seat) -> float: the seat's live solo Perfect % (0..100), or -1 before its first solo
## note (MatchSim.duel_live). section_banner may be null.
func bind(channel: EventChannel, local_seat: int, names: Array, cfg: VersusConfig, live_pct: Callable,
		section_banner: SectionBanner) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_local_seat = local_seat
	_names = names.duplicate()
	_cfg = cfg if cfg != null else VersusConfig.new()
	_live_pct = live_pct
	_section = section_banner
	if _channel != null:
		_channel.received.connect(on_event)
	_sync_suppress()


func _name(seat: int) -> String:
	if seat < 0 or seat >= _names.size():
		return "?"
	var s := str(_names[seat]).strip_edges().to_upper()
	return s if s != "" else "?"


func _min_pct() -> int:
	return roundi(_cfg.solo_duel_min_accuracy * 100.0)


static func priority_of(kind: Kind) -> int:
	match kind:
		Kind.COUNTDOWN:
			return 4
		Kind.IMPLOSION:
			return 3
		Kind.LAST_STANDING:
			return 2
		Kind.DUEL_ANNOUNCE, Kind.DUEL_LIVE, Kind.DUEL_RESULT, Kind.WAITING:
			return 1
	return 0


static func _is_duel(kind: int) -> bool:
	return kind == Kind.DUEL_ANNOUNCE or kind == Kind.DUEL_LIVE or kind == Kind.DUEL_RESULT


# ---- Events ------------------------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		GameEvent.DUEL_ANNOUNCE:
			_duel = {"solo": int(e.get("solo", -1)), "start": float(e.get("start", 0.0)),
				"end": float(e.get("end", 0.0)), "note_count": int(e.get("note_count", 0))}
			_request(Kind.DUEL_ANNOUNCE, {})
		GameEvent.DUEL_START:
			_request(Kind.DUEL_LIVE, {})
		GameEvent.DUEL_RESULT:
			_request(Kind.DUEL_RESULT, {"winner": int(e.get("winner", -1)), "pct": float(e.get("pct", 0.0)),
				"best_pct": float(e.get("best_pct", 0.0)), "tied": bool(e.get("tied", false))})
		GameEvent.LAST_STANDING:
			_request(Kind.LAST_STANDING, {"seat": int(e.get("seat", -1))})
		GameEvent.IMPLODED:
			var seat := int(e.get("seat", -1))
			_dead[seat] = true
			if seat == _local_seat:
				_request(Kind.IMPLOSION, {})
				_vignette_t = 0.0
				_shake_t = 0.0 if not _reduce else -1.0


func _request(kind: Kind, data: Dictionary) -> void:
	var r := {"kind": kind, "data": data}
	var cur_kind: int = _cur.get("kind", Kind.NONE)
	if _phase == Phase.IDLE or cur_kind == Kind.NONE:
		_show(r)
		return
	if _is_duel(kind) and _is_duel(cur_kind):
		_show(r)  # the duel moves on in place
		return
	if priority_of(kind) >= priority_of(cur_kind):
		if not (cur_kind == Kind.DUEL_RESULT and _phase == Phase.OUT):
			_queue(_cur)
		_show(r)
		return
	_queue(r)


# ---- Online states (04-UI-SPEC 10.3, 11.7) -----------------------------------------------

## MATCH START countdown from the START receipt (song time, < 0) to "DIVE" at song time 0.
## flight_beats is the lobby torpedo flight (right caption). Song-time driven via observe().
func start_countdown(start_receipt_song_t: float, flight_beats: int) -> void:
	var r := start_receipt_song_t if is_finite(start_receipt_song_t) else 0.0
	_cd = {"receipt": minf(r, 0.0), "beats": maxi(flight_beats, 1)}
	_t = r
	_drop_pending(Kind.COUNTDOWN)
	if r >= COUNTDOWN_GONE:
		return
	_request(Kind.COUNTDOWN, {})


## Headline for the countdown at song time t: "DIVE IN 3".."DIVE IN 1" (digit = ceil(-t)
## clamped 1..3), "DIVE" from t 0, "" once the state is gone (t >= 0.9).
static func countdown_text_at(song_time: float) -> String:
	if song_time >= COUNTDOWN_GONE:
		return ""
	if song_time >= 0.0:
		return "DIVE"
	return "DIVE IN %d" % clampi(ceili(-song_time), 1, 3)


## 1.0 at the START receipt, draining to 0.0 at song time 0 (the progress line width share).
func countdown_progress() -> float:
	if _cd.is_empty():
		return 0.0
	var r := float(_cd.get("receipt", 0.0))
	if r >= 0.0:
		return 0.0
	return clampf(_t / r, 0.0, 1.0)


## MATCH COMPLETE / WAITING FOR RESULTS (11.7). still_diving > 0 adds "{n} SUBS STILL DIVING"
## (host side); <= 0 leaves the right caption empty (clients). Calling it again updates in place.
func show_waiting(still_diving: int) -> void:
	var data := {"n": still_diving}
	if _phase != Phase.IDLE and int(_cur.get("kind", Kind.NONE)) == Kind.WAITING:
		_cur["data"] = data
		if _phase == Phase.OUT:
			_set_phase(Phase.HOLD)
		_refresh_texts()
		_apply_visual()
		return
	_request(Kind.WAITING, data)


func hide_waiting() -> void:
	_drop_pending(Kind.WAITING)
	if _phase != Phase.IDLE and int(_cur.get("kind", Kind.NONE)) == Kind.WAITING and _phase != Phase.OUT:
		_set_phase(Phase.OUT)
		_apply_visual()


func _drop_pending(kind: int) -> void:
	var keep: Array[Dictionary] = []
	for p in _pending:
		if int(p["kind"]) != kind:
			keep.append(p)
	_pending = keep


static func waiting_right_text(still_diving: int) -> String:
	if still_diving <= 0:
		return ""
	if still_diving == 1:
		return "1 SUB STILL DIVING"
	return "%d SUBS STILL DIVING" % still_diving


static func flight_text(beats: int) -> String:
	return "FLIGHT 1 BEAT" if beats == 1 else "FLIGHT %d BEATS" % beats


func _queue(r: Dictionary) -> void:
	var kind: int = r.get("kind", Kind.NONE)
	if kind == Kind.NONE:
		return
	var keep: Array[Dictionary] = []
	for p in _pending:
		var pk: int = p["kind"]
		if pk == kind or (_is_duel(pk) and _is_duel(kind)):
			continue  # latest state of a slot wins
		keep.append(p)
	keep.append(r)
	_pending = keep


func _pop_next() -> Dictionary:
	# A waiting announce / live duel the song has already left behind is dropped.
	if not _duel.is_empty() and _t > float(_duel.get("end", 0.0)) + DUEL_STALE_SEC:
		var keep: Array[Dictionary] = []
		for p in _pending:
			if int(p["kind"]) != Kind.DUEL_ANNOUNCE and int(p["kind"]) != Kind.DUEL_LIVE:
				keep.append(p)
		_pending = keep
	if _t >= COUNTDOWN_GONE:
		_drop_pending(Kind.COUNTDOWN)
	var best := -1
	for i in range(_pending.size()):
		if best < 0 or priority_of(_pending[i]["kind"]) > priority_of(_pending[best]["kind"]):
			best = i
	if best < 0:
		return {}
	var r: Dictionary = _pending[best]
	_pending.remove_at(best)
	return r


func _show(r: Dictionary) -> void:
	var was_showing := _phase != Phase.IDLE
	if was_showing:
		_prev = {"caption": _caption, "caption_col": _caption_col, "headline": _headline,
			"headline_col": _headline_col, "right": _right, "right_col": _right_col}
		_xfade_left = XFADE_SEC
		_xfade_dur = XFADE_SEC
	else:
		_prev = {}
		_xfade_left = 0.0
	_cur = r
	var kind: int = r["kind"]
	match kind:
		Kind.DUEL_RESULT:
			_hold = HOLD_RESULT
		Kind.LAST_STANDING, Kind.IMPLOSION:
			_hold = HOLD_LONG
		_:
			_hold = -1.0
	match _phase:
		Phase.IDLE:
			_set_phase(Phase.IN)
		Phase.HOLD:
			_phase_t = 0.0
		Phase.OUT:
			var a := alpha()
			_set_phase(Phase.HOLD if a >= 0.999 else Phase.IN)
			if _phase == Phase.IN:
				var k := 1.0 - pow(clampf(1.0 - a, 0.0, 1.0), 1.0 / 3.0)
				_phase_t = k * Palette.DUR_BASE
	_refresh_texts()
	_apply_visual()


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = 0.0


# ---- Texts -------------------------------------------------------------------------------

func _refresh_texts() -> void:
	var kind: int = _cur.get("kind", Kind.NONE)
	var d: Dictionary = _cur.get("data", {})
	var mn := _min_pct()
	match kind:
		Kind.DUEL_ANNOUNCE:
			_caption = "SOLO DUEL"
			_caption_col = Palette.REWARD_GOLD
			_headline = "%d%% PERFECT WINS A REWARD" % mn
			_headline_col = Palette.TEXT_HI
			_right = "%d NOTES" % int(_duel.get("note_count", 0))
			_right_col = Palette.TEXT_MID
		Kind.DUEL_LIVE:
			_caption = "SOLO DUEL"
			_caption_col = Palette.REWARD_GOLD
			if _dead.get(_local_seat, false):
				_headline = "WRECKS SIT THIS ONE OUT"
				_headline_col = Palette.TEXT_MID
			else:
				var p := _pct(_local_seat)
				if p < 0.0:
					_headline = "YOU --%"
					_headline_col = Palette.TEXT_HI
				else:
					_headline = "YOU %d%%" % roundi(p)
					_headline_col = Palette.SONAR_PALE if roundi(p) >= mn else Palette.TEXT_HI
			_right = _leader_text()
			_right_col = Palette.TEXT_MID
		Kind.DUEL_RESULT:
			_caption = "SOLO DUEL"
			var w := int(d.get("winner", -1))
			_right_col = Palette.TEXT_MID
			if w == _local_seat:
				_caption_col = Palette.REWARD_GOLD
				_headline = "YOU WIN THE SOLO"
				_headline_col = Palette.REWARD_GOLD
				_right = "%d%% PERFECT" % roundi(float(d.get("pct", 0.0)))
			elif w >= 0:
				_caption_col = Palette.REWARD_GOLD
				_headline = _name(w) + " WINS THE SOLO"
				_headline_col = Palette.TEXT_HI
				_right = "%d%% PERFECT" % roundi(float(d.get("pct", 0.0)))
			else:
				_caption_col = Palette.REWARD_GOLD
				_headline = "NO WINNER"
				_headline_col = Palette.TEXT_HI
				if bool(d.get("tied", false)):
					_right = "TIED"
				else:
					_right = "BEST %d%%%sNEEDED %d%%" % [roundi(float(d.get("best_pct", 0.0))), SEP, mn]
		Kind.LAST_STANDING:
			_caption = "LAST HULL STANDING"
			var s := int(d.get("seat", -1))
			if s == _local_seat:
				_caption_col = Palette.REWARD_GOLD
				_headline = "YOU WIN"
				_headline_col = Palette.REWARD_GOLD
			else:
				_caption_col = Palette.TEXT_HI
				_headline = _name(s) + " WINS"
				_headline_col = Palette.TEXT_HI
			_right = "SONG PLAYS ON"
			_right_col = Palette.TEXT_LO
		Kind.IMPLOSION:
			_caption = "HULL BREACHED"
			_caption_col = Palette.WARNING_RED
			_headline = "IMPLOSION"
			_headline_col = Palette.WARNING_RED
			_right = "YOU ARE A WRECK"
			_right_col = Palette.TEXT_MID
		Kind.COUNTDOWN:
			_caption = "ALL SUBS LINKED"
			_caption_col = Palette.SONAR
			var hl := countdown_text_at(minf(_t, 0.0))  # "DIVE" stays through its fade
			_headline = hl
			_headline_col = Palette.SONAR_PALE if _t >= 0.0 else Palette.TEXT_HI
			_right = flight_text(int(_cd.get("beats", 2)))
			_right_col = Palette.TEXT_MID
		Kind.WAITING:
			_caption = "MATCH COMPLETE"
			_caption_col = Palette.SONAR
			_headline = "WAITING FOR RESULTS"
			_headline_col = Palette.TEXT_HI
			_right = waiting_right_text(int(d.get("n", 0)))
			_right_col = Palette.TEXT_MID
	if _panel_node != null:
		_panel_node.queue_redraw()


func _pct(seat: int) -> float:
	if not _live_pct.is_valid():
		return -1.0
	var v: Variant = _live_pct.call(seat)
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return -1.0
	var f := float(v)
	return clampf(f, 0.0, 100.0) if is_finite(f) and f >= 0.0 else -1.0


## "LEADER {NAME} {q}%" for the best living rival with a live %, "" if none.
func _leader_text() -> String:
	var best := -1
	var best_p := -1.0
	for seat in range(_names.size()):
		if seat == _local_seat or _dead.get(seat, false):
			continue
		var p := _pct(seat)
		if p > best_p:
			best_p = p
			best = seat
	if best < 0 or best_p < 0.0:
		return ""
	return "LEADER %s %d%%" % [_name(best), roundi(best_p)]


# ---- Time --------------------------------------------------------------------------------

## Song-clock update: live duel numbers and progress line; drops a duel state the song has
## left behind (no DUEL_START / DUEL_RESULT came).
func observe(song_time: float) -> void:
	if not is_finite(song_time):
		return
	_t = song_time
	var kind: int = _cur.get("kind", Kind.NONE)
	if _phase != Phase.IDLE and (kind == Kind.DUEL_ANNOUNCE or kind == Kind.DUEL_LIVE):
		if not _duel.is_empty() and _t > float(_duel.get("end", 0.0)) + DUEL_STALE_SEC:
			if _phase != Phase.OUT:
				_set_phase(Phase.OUT)
		# Live percentages are re-read at 10 Hz, not every frame (WR-09); only the DUEL_LIVE
		# progress line needs a per-frame redraw.
		if _t >= _texts_next or _t < _texts_next - 1.0:
			_texts_next = _t + TEXTS_REFRESH_S
			_refresh_texts()
	if _phase != Phase.IDLE and kind == Kind.COUNTDOWN:
		_observe_countdown()
		return
	if _panel_node != null and _phase != Phase.IDLE and kind == Kind.DUEL_LIVE:
		_panel_node.queue_redraw()


## Countdown from song time: digit swaps (cross-fade DUR_FAST, swap under Reduce motion),
## "DIVE" hold, the DUR_SLOW fade from 0.6 s and the end at 0.9 s, all on the song clock.
func _observe_countdown() -> void:
	if _t >= COUNTDOWN_GONE:
		_finish_current()
		return
	if _t >= DIVE_HOLD:
		if _phase != Phase.OUT:
			_set_phase(Phase.OUT)
		_phase_t = maxf(_phase_t, _t - DIVE_HOLD)
	var hl := countdown_text_at(minf(_t, 0.0))
	if hl != _headline:
		if _reduce:
			_prev = {}
			_xfade_left = 0.0
		else:
			_prev = {"caption": _caption, "caption_col": _caption_col, "headline": _headline,
				"headline_col": _headline_col, "right": _right, "right_col": _right_col}
			_xfade_dur = Palette.DUR_FAST
			_xfade_left = Palette.DUR_FAST
		_refresh_texts()
	_apply_visual()


## Ends the shown banner now and shows the next waiting one (if any).
func _finish_current() -> void:
	_set_phase(Phase.IDLE)
	_cur = {}
	_prev = {}
	_xfade_left = 0.0
	var nxt := _pop_next()
	if not nxt.is_empty():
		_show(nxt)
		return
	_apply_visual()


## Fade-out length of the shown banner: DUR_SLOW for the countdown "DIVE", else 0.3 s.
func _out_sec() -> float:
	return Palette.DUR_SLOW if int(_cur.get("kind", Kind.NONE)) == Kind.COUNTDOWN else OUT_SEC


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	if _vignette_t >= 0.0:
		_vignette_t += dt
		if _vignette_t >= VIGNETTE_SEC:
			_vignette_t = -1.0
		queue_redraw()
	if _shake_t >= 0.0:
		_shake_t += dt
		if _shake_t >= SHAKE_SEC:
			_shake_t = -1.0
	if _phase == Phase.IDLE:
		return
	var phase0 := _phase
	if _xfade_left > 0.0:
		_xfade_left = maxf(_xfade_left - dt, 0.0)
	_phase_t += dt
	# A long step may cross several phases (IN -> HOLD -> OUT -> IDLE); carry the overshoot.
	var moved := true
	while moved:
		moved = false
		match _phase:
			Phase.IN:
				if _phase_t >= Palette.DUR_BASE:
					var over := _phase_t - Palette.DUR_BASE
					_set_phase(Phase.HOLD)
					_phase_t = over
					moved = true
			Phase.HOLD:
				if _hold >= 0.0 and _phase_t >= _hold:
					var over2 := _phase_t - _hold
					_set_phase(Phase.OUT)
					_phase_t = over2
					moved = true
			Phase.OUT:
				if _phase_t >= _out_sec():
					_set_phase(Phase.IDLE)
					_cur = {}
					_prev = {}
					_xfade_left = 0.0
					var nxt := _pop_next()
					if not nxt.is_empty():
						_show(nxt)  # the next banner starts fresh; overshoot is dropped
						return
	_apply_visual(_xfade_left > 0.0 or _phase != phase0 or int(_cur.get("kind", Kind.NONE)) == Kind.DUEL_LIVE)


func _process(delta: float) -> void:
	step(delta)


## Alpha / slide / shake are node properties; the panel is only re-recorded when its content
## changes (cross-fade, phase change, live duel line) and the vignette layer only while it
## runs (WR-09 / WR-10).
func _apply_visual(redraw_panel: bool = true) -> void:
	if _panel_node != null:
		_panel_node.visible = _phase != Phase.IDLE
		_panel_node.modulate.a = alpha()
		_panel_node.position = RECT.position + Vector2(shake_offset(), slide_offset())
		if redraw_panel:
			_panel_node.queue_redraw()
	_sync_suppress()
	if _vignette_t >= 0.0:
		queue_redraw()


func _sync_suppress() -> void:
	if _section != null and is_instance_valid(_section):
		_section.suppressed = _phase != Phase.IDLE


static func _ease_out_cubic(k: float) -> float:
	var u := 1.0 - clampf(k, 0.0, 1.0)
	return 1.0 - u * u * u


# ---- Getters -----------------------------------------------------------------------------

func current_kind() -> Kind:
	return _cur.get("kind", Kind.NONE) if _phase != Phase.IDLE else Kind.NONE


func pending_kinds() -> Array[int]:
	var out: Array[int] = []
	for p in _pending:
		out.append(int(p["kind"]))
	return out


func caption_text() -> String:
	return _caption if _phase != Phase.IDLE else ""


func caption_color() -> Color:
	return _caption_col


func headline_text() -> String:
	return _headline if _phase != Phase.IDLE else ""


func headline_color() -> Color:
	return _headline_col


func right_text() -> String:
	return _right if _phase != Phase.IDLE else ""


func right_color() -> Color:
	return _right_col


func is_showing() -> bool:
	return _phase != Phase.IDLE


func phase() -> Phase:
	return _phase


func alpha() -> float:
	match _phase:
		Phase.IN:
			return _ease_out_cubic(_phase_t / Palette.DUR_BASE)
		Phase.HOLD:
			return 1.0
		Phase.OUT:
			return clampf(1.0 - _phase_t / _out_sec(), 0.0, 1.0)
	return 0.0


## -24 px at the start of the slide, 0 when settled (always 0 under Reduce motion).
func slide_offset() -> float:
	if _reduce or _phase != Phase.IN or not _prev.is_empty():
		return 0.0
	return -SLIDE_PX * (1.0 - _ease_out_cubic(_phase_t / Palette.DUR_BASE))


## Horizontal shake after your implosion: 8 px decaying over 120 ms (0 under Reduce motion).
func shake_offset() -> float:
	if _reduce or _shake_t < 0.0:
		return 0.0
	var k := clampf(_shake_t / SHAKE_SEC, 0.0, 1.0)
	return SHAKE_PX * sin(k * TAU * 3.0) * (1.0 - k)


func is_shaking() -> bool:
	return shake_offset() != 0.0 or (_shake_t >= 0.0 and not _reduce)


## Opacity factor of the implosion vignette (1 at the implosion, 0 after 600 ms).
func vignette_alpha() -> float:
	if _vignette_t < 0.0:
		return 0.0
	return clampf(1.0 - _vignette_t / VIGNETTE_SEC, 0.0, 1.0)


## 0..1 share of the solo elapsed (live duel progress line).
func duel_progress() -> float:
	if _duel.is_empty():
		return 0.0
	var s := float(_duel.get("start", 0.0))
	var e := float(_duel.get("end", 0.0))
	if e <= s:
		return 0.0
	return clampf((_t - s) / (e - s), 0.0, 1.0)


# ---- Effects -----------------------------------------------------------------------------

func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	if _reduce:
		_shake_t = -1.0
	_apply_visual()


func effect_counts() -> Dictionary:
	return {"slide": not _reduce, "shake": not _reduce, "glow": not _low}


## W4 keep-out: the panel rect (global). The implosion vignette is a transient tint (see header).
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var r := RECT
	return [PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
		xf * Vector2(r.position.x, r.end.y)])]


# ---- Drawing -----------------------------------------------------------------------------

func _draw() -> void:
	var va := vignette_alpha()
	if va <= 0.0:
		return
	if _vignette_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Palette.alpha(Palette.WARNING_RED, 0.0), Palette.alpha(Palette.WARNING_RED, 0.0),
			Palette.alpha(Palette.WARNING_RED, VIGNETTE_ALPHA)])
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient = g
		_vignette_tex.width = 128
		_vignette_tex.height = 72
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to = Vector2(1.0, 1.0)
	var sz := size if size.x > 0.0 and size.y > 0.0 else Vector2(1920.0, 1080.0)
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, sz), false, Palette.alpha(Palette.WHITE, va))


## Cached per (danger, gold win, Low effects) (WR-09): no StyleBoxFlat per draw.
func _panel_style() -> StyleBoxFlat:
	var kind: int = _cur.get("kind", Kind.NONE)
	var danger := kind == Kind.IMPLOSION
	var gold := _gold_win()
	var key := int(danger) * 4 + int(gold) * 2 + int(_low)
	var cached = _style_cache.get(key)
	if cached != null:
		return cached
	var sb := UiKit.style_panel("danger" if danger else "default", _low)
	sb.bg_color = Color(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA)
	sb.corner_radius_top_left = Palette.CUT_SM
	sb.corner_radius_bottom_right = Palette.CUT_SM
	if gold:
		sb.shadow_color = Palette.alpha(Palette.REWARD_GOLD, Palette.PANEL_GLOW_ALPHA)
	_style_cache[key] = sb
	return sb


## Fitted text and its width, cached (WR-09): no glyph measuring per frame.
func _fit(text: String, font: Font, fs: int, max_w: float) -> Array:
	var key := "%s|%d|%d" % [text, fs, int(max_w)]
	var hit = _fit_cache.get(key)
	if hit != null:
		return hit
	if _fit_cache.size() > 48:
		_fit_cache.clear()
	var t := text if max_w <= 0.0 else ProgressTrack.truncate_px(text, font, fs, max_w)
	var out := [t, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x]
	_fit_cache[key] = out
	return out


func _gold_win() -> bool:
	var kind: int = _cur.get("kind", Kind.NONE)
	var d: Dictionary = _cur.get("data", {})
	return (kind == Kind.DUEL_RESULT and int(d.get("winner", -1)) == _local_seat) \
		or (kind == Kind.LAST_STANDING and int(d.get("seat", -1)) == _local_seat)


func _bracket_color() -> Color:
	var kind: int = _cur.get("kind", Kind.NONE)
	match kind:
		Kind.IMPLOSION:
			return Palette.alpha(Palette.WARNING_RED, BRACKET_ALPHA)
		Kind.DUEL_ANNOUNCE, Kind.DUEL_LIVE:
			return Palette.REWARD_GOLD
	if _gold_win():
		return Palette.REWARD_GOLD
	return Palette.alpha(Palette.SONAR, BRACKET_ALPHA)


func _draw_panel() -> void:
	if _phase == Phase.IDLE or _panel_node == null:
		return
	var ci := _panel_node
	var r := Rect2(Vector2.ZERO, RECT.size)
	ci.draw_style_box(_panel_style(), r)
	UiKit.draw_brackets(ci, r, _bracket_color())
	var k := 1.0 - _xfade_left / _xfade_dur if _xfade_left > 0.0 else 1.0
	if _xfade_left > 0.0 and not _prev.is_empty():
		_draw_texts(ci, str(_prev["caption"]), _prev["caption_col"], str(_prev["headline"]), _prev["headline_col"],
			str(_prev["right"]), _prev["right_col"], 1.0 - k)
	_draw_texts(ci, _caption, _caption_col, _headline, _headline_col, _right, _right_col, k)
	if int(_cur.get("kind", Kind.NONE)) == Kind.DUEL_LIVE:
		ci.draw_rect(Rect2(0.0, LINE_Y, RECT.size.x * duel_progress(), LINE_H), Palette.SONAR)
	elif int(_cur.get("kind", Kind.NONE)) == Kind.COUNTDOWN:
		var w := RECT.size.x * countdown_progress()  # drains right to left
		if w > 0.0:
			ci.draw_rect(Rect2(0.0, LINE_Y, w, LINE_H), Palette.SONAR)


func _draw_texts(ci: CanvasItem, caption: String, caption_col: Color, headline: String, headline_col: Color,
		right: String, right_col: Color, a: float) -> void:
	if a <= 0.0:
		return
	var f := Palette.font()
	var fs := Palette.SIZE_LABEL
	var cx := RECT.size.x * 0.5
	if caption != "":
		var cw: float = _fit(caption, f, fs, 0.0)[1]
		ci.draw_string(f, Vector2(cx - cw * 0.5, CAPTION_BASE_Y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.alpha(caption_col, caption_col.a * a))
	if right != "":
		var rf := _fit(right, f, fs, RIGHT_MAX)
		var rt: String = rf[0]
		var rw: float = rf[1]
		ci.draw_string(f, Vector2(RIGHT_X - rw, CAPTION_BASE_Y), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.alpha(right_col, right_col.a * a))
	if headline != "":
		var df := Palette.display_font()
		var hs := Palette.SIZE_HEADING
		var hf := _fit(headline, df, hs, RECT.size.x - 2.0 * UiKit.PANEL_PAD)
		var hl: String = hf[0]
		var hw: float = hf[1]
		ci.draw_string(df, Vector2(cx - hw * 0.5, HEADLINE_BASE_Y), hl, HORIZONTAL_ALIGNMENT_LEFT, -1, hs,
			Palette.alpha(headline_col, headline_col.a * a))
