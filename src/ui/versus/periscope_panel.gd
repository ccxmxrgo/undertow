class_name PeriscopePanel
extends Control
## One rival readout in the periscope column (03-UI-SPEC 6.2; MATCH-04, S-10, S-11, D-26).
## A fixed 352 x 88 glass panel (CUT_SM, ABYSS_700 at HUD_GLASS_ALPHA) showing the rival's
## callsign, place, 10-segment hull bar (or WRECK / TRAINING), the tube meter arc with the held
## reward, decorative scope blips, the bounty marker, the status line (depth, SOLO p%, SITTING
## OUT, NEXT IN n BARS) and the threat block (what is happening TO this rival).
## Fed only by EventChannel events (on_event) plus a read-only live-percent callable for the
## Solo Duel. Song-time visuals (countdown rings, sweep) follow update(song_time); one-shot
## flashes and blips follow step(dt). PeriscopeColumn owns the rect, target flag and entrance.
## Rival Decoy and Overclock effects are never shown (UI-SPEC 16.6, hidden information).
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const SIZE := Vector2(352.0, 88.0)

# Scope disc + tube arc (same 270-degree geometry as RewardSocket, UI-SPEC 5.1).
const SCOPE_C := Vector2(52.0, 44.0)
const DISC_R := 24.0
const DISC_ALPHA := 0.9
const ARC_R := 30.0
const ARC_W := 4.0
const ARC_FROM := PI * 0.75  # 135 deg; the 90 deg gap faces down
const ARC_SPAN := PI * 1.5  # 270 deg
const ARC_POINTS := 48
const TRACK_ALPHA := 0.7
const HELD_SIZE := 24.0
const KIND_R := 22.0

# Scope blips (decorative, one per rival Perfect).
const BLIP_R_MIN := 8.0
const BLIP_R_MAX := 20.0
const BLIP_DOT := 1.5  # 3 px dot
const BLIP_SEC := 0.4
const BLIPS_FULL := 6
const BLIPS_LOW := 2
const SWEEP_ALPHA := 0.35

# Text and bars (offsets from the panel's top-left).
const BOUNTY_RECT := Rect2(96.0, 14.0, 16.0, 16.0)
const CALL_X := 96.0
const CALL_X_BOUNTY := 120.0
const CALL_BASE := 30.0
const CALL_MAX := 112.0
const CALL_SPACING := 2
const PLACE_RIGHT := 272.0
const PLACE_BOX := 64.0
const HULL_X := 96.0
const HULL_Y := 40.0
const HULL_W := 176.0
const HULL_H := 10.0
const HULL_SEGMENTS := 10
const HULL_GAP := 2.0
const UNLIT_ALPHA := 0.7
const DMG_SEC := 0.2
const WRECK_BASE := 52.0
const WRECK_GLYPH := Rect2(96.0, 38.0, 16.0, 16.0)
const WRECK_TEXT_X := 116.0
const STATUS_X := 96.0
const STATUS_BASE := 76.0
const STATUS_MAX := 176.0

# Threat block.
const THREAT_C := Vector2(316.0, 44.0)
const THREAT_R := 22.0
const THREAT_W := 3.0
const BURST_R := 34.0
const BURST_SEC := 0.3
const GLYPH_SEC := 0.6
const LAUNCH_FLASH_SEC := 0.3
const COLLIDE_FLASH_SEC := 0.2
const DASHES := 16

# Chrome.
const EDGE_ALPHA := 0.45
const BRACKET_ALPHA := 0.8
const WRECK_EDGE_ALPHA := 0.35
const WRECK_BRACKET_ALPHA := 0.5
const MAX_NAME_CHARS := 24

const PLACES: Array[String] = ["", "1ST", "2ND", "3RD", "4TH"]

static var _spaced: FontVariation

var seat: int = -1
var callsign: String = "?"
var drone: bool = false

var _chart: ChartData
var _min_pct: float = 85.0
var _live_pct: Callable = Callable()

var _hull: float = 100.0
var _depth: int = 0
var _place: int = 0
var _wreck: bool = false
var _duel: bool = false
var _drone_status: String = ""
var _progress: int = 0
var _threshold: int = 1
var _held: int = -1
var _bounty: bool = false
var _targeted: bool = false

var _now: float = 0.0
var _threat: String = "none"  # none | incoming | active | immune
var _t0: float = 0.0
var _t1: float = 0.0
var _threat_reward: int = -1
var _threat_id: int = -1

var _glyph_kind: String = ""  # collision | absorbed | reflected
var _glyph_left: float = 0.0
var _burst_left: float = 0.0
var _edge_flash_left: float = 0.0
var _edge_flash_sec: float = 0.0
var _edge_flash_color: Color = Palette.WARNING_RED
var _dmg_left: float = 0.0
var _dmg_from: float = 100.0

var _blips: Array[Dictionary] = []  # {a, r, age}
var _rng := RandomNumberGenerator.new()

var _low: bool = false
var _reduce: bool = false
var _box: StyleBoxFlat


func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


## One-time setup by the column (or a test). names are clamped to UPPERCASE and to
## MAX_NAME_CHARS; pixel truncation happens at draw time (T-03-25).
func setup(p_seat: int, p_callsign: String, p_drone: bool = false, p_chart: ChartData = null,
		cfg: VersusConfig = null, live_pct: Callable = Callable()) -> void:
	seat = p_seat
	callsign = clamp_name(p_callsign)
	drone = p_drone
	_chart = p_chart
	_live_pct = live_pct
	if cfg != null:
		_min_pct = cfg.solo_duel_min_accuracy * 100.0
	_rng.seed = hash("periscope:%d" % p_seat)  # private RNG, never the global one
	queue_redraw()


static func clamp_name(s: String) -> String:
	var n := s.strip_edges().to_upper().left(MAX_NAME_CHARS)
	return "?" if n.is_empty() else n


static func spaced_font() -> Font:
	if _spaced == null:
		_spaced = FontVariation.new()
		_spaced.base_font = Palette.font()
		_spaced.spacing_glyph = CALL_SPACING
	return _spaced


# ---- Events -----------------------------------------------------------------------------

## Applies one GameEvent; events about other seats are ignored. O(1) per event (T-03-26).
func on_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		GameEvent.STATUS:
			if int(e.get("seat", -1)) == seat:
				_on_status(e)
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == seat:
				_wreck = true
				_held = -1
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("to", -1)) == seat:
				_threat = "incoming"
				_threat_id = int(e.get("id", -1))
				_threat_reward = int(e.get("reward", -1))
				_t0 = float(e.get("launch_t", e.get("t", 0.0)))
				_t1 = float(e.get("arrive_t", _t0))
				_flash_edge(Palette.WARNING_RED, LAUNCH_FLASH_SEC)
		GameEvent.LANDED:
			if int(e.get("to", -1)) == seat:
				_threat = "active"
				_threat_id = int(e.get("id", -1))
				_threat_reward = int(e.get("reward", -1))
				_t0 = float(e.get("arrive_t", e.get("t", 0.0)))
				_t1 = float(e.get("end_t", _t0))
		GameEvent.PAYLOAD_END:
			if int(e.get("seat", -1)) == seat:
				_threat = "immune"
				_t0 = float(e.get("t", _now))
				_t1 = float(e.get("immune_until", _t0))
				_threat_reward = -1
		GameEvent.COLLISION:
			if int(e.get("a", -1)) == seat or int(e.get("b", -1)) == seat:
				_clear_incoming()
				_show_glyph("collision")
				_burst_left = BURST_SEC
				_flash_edge(Palette.TEXT_HI, COLLIDE_FLASH_SEC)
		GameEvent.ABSORBED:
			if int(e.get("to", -1)) == seat:
				_clear_incoming()
				_show_glyph("absorbed")
		GameEvent.REFLECTED:
			if int(e.get("by", -1)) == seat:
				if _threat == "active" or _threat == "incoming":
					_threat = "none"
					_threat_reward = -1
				_show_glyph("reflected")
		GameEvent.FIZZLED:
			if int(e.get("to", -1)) == seat and _threat == "incoming" and int(e.get("id", -2)) == _threat_id:
				_clear_incoming()
		GameEvent.BOUNTY_MOVED:
			_bounty = int(e.get("to_seat", -1)) == seat
		GameEvent.DUEL_START:
			_duel = not drone
		GameEvent.DUEL_RESULT:
			_duel = false
		GameEvent.REWARD_EARNED:
			if int(e.get("seat", -1)) == seat:
				_held = int(e.get("reward", -1))
		GameEvent.METER:
			if int(e.get("seat", -1)) == seat:
				_on_meter(e)
		_:
			return
	queue_redraw()


func _on_status(e: Dictionary) -> void:
	var h := clampf(float(e.get("hull", _hull)), 0.0, 100.0)
	if h < _hull and not _reduce:
		if _dmg_left <= 0.0:
			_dmg_from = _hull
		_dmg_left = DMG_SEC
	_hull = h
	_depth = int(e.get("depth", _depth))
	_place = int(e.get("place", _place))
	if e.has("alive") and not bool(e["alive"]):
		_wreck = true


func _on_meter(e: Dictionary) -> void:
	var p := int(e.get("progress", _progress))
	var th := maxi(int(e.get("threshold", _threshold)), 1)
	var held := int(e.get("held", -1))
	if p > _progress and held == _held:
		add_blip()
	_progress = p
	_threshold = th
	_held = held


func _clear_incoming() -> void:
	if _threat == "incoming":
		_threat = "none"
		_threat_reward = -1


func _show_glyph(kind: String) -> void:
	_glyph_kind = kind
	_glyph_left = GLYPH_SEC


func _flash_edge(c: Color, sec: float) -> void:
	_edge_flash_color = c
	_edge_flash_sec = sec
	_edge_flash_left = sec


## One decorative scope blip (seeded angle and radius). Capped at 6 (Full) / 2 (Low); the
## oldest drops first (T-03-26).
func add_blip() -> void:
	_blips.append({"a": _rng.randf() * TAU, "r": _rng.randf_range(BLIP_R_MIN, BLIP_R_MAX), "age": 0.0})
	var cap := blips_max()
	while _blips.size() > cap:
		_blips.pop_front()


# ---- Column / training hooks ------------------------------------------------------------

func set_targeted(on: bool) -> void:
	if _targeted != on:
		_targeted = on
		queue_redraw()


func is_targeted() -> bool:
	return _targeted


## Training drone status line, e.g. "NEXT IN 3 BARS".
func set_drone_status(text: String) -> void:
	_drone_status = text.to_upper()
	queue_redraw()


func set_live_pct(cb: Callable) -> void:
	_live_pct = cb


## Song-time pump: countdown rings and the sweep line.
func update(song_time: float) -> void:
	_now = song_time
	if (_threat == "immune" or _threat == "active") and _now >= _t1:
		_threat = "none"
		_threat_reward = -1
	queue_redraw()


## Wall-clock pump for one-shot flashes and blips (tests call it directly).
func step(dt: float) -> void:
	var dirty := false
	for v in ["_glyph_left", "_burst_left", "_edge_flash_left", "_dmg_left"]:
		var left: float = get(v)
		if left > 0.0:
			set(v, maxf(left - dt, 0.0))
			dirty = true
	if not _blips.is_empty():
		for b in _blips:
			b["age"] = float(b["age"]) + dt
		_blips = _blips.filter(func(b: Dictionary) -> bool: return float(b["age"]) < BLIP_SEC)
		dirty = true
	if dirty or sweep_on():
		queue_redraw()


# ---- Read-only state (tests) ------------------------------------------------------------

## none | incoming | active | immune | collision | absorbed | reflected
func threat_state() -> String:
	return _glyph_kind if _glyph_left > 0.0 else _threat


## Remaining fraction of the countdown ring (1 = full, 0 = drained).
func threat_fraction() -> float:
	if _threat == "none" or _t1 <= _t0:
		return 0.0
	return clampf((_t1 - _now) / (_t1 - _t0), 0.0, 1.0)


## The glyph shown in the threat block ("" when none).
func threat_glyph() -> String:
	if _glyph_left > 0.0:
		match _glyph_kind:
			"collision":
				return "cross"
			"absorbed":
				return "decoy_flare"
			"reflected":
				return "reflect"
	match _threat:
		"incoming", "active":
			return Reward.glyph(_threat_reward)
		"immune":
			return "shield"
	return ""


func edge_flashing() -> bool:
	return _edge_flash_left > 0.0


func burst_radius() -> float:
	if _burst_left <= 0.0:
		return THREAT_R
	if _reduce:
		return THREAT_R
	return lerpf(BURST_R, THREAT_R, _burst_left / BURST_SEC)


func is_wreck() -> bool:
	return _wreck


func status_text() -> String:
	if drone:
		return _drone_status if _drone_status != "" else depth_text()
	if _duel:
		if _wreck:
			return "SITTING OUT"
		var p := live_pct()
		return "SOLO --%" if p < 0 else "SOLO %d%%" % p
	return depth_text()


func status_color() -> Color:
	if drone:
		return Palette.TEXT_MID
	if _duel:
		if _wreck:
			return Palette.TEXT_LO
		var p := live_pct()
		return Palette.SONAR_PALE if p >= 0 and float(p) >= _min_pct - 1e-6 else Palette.TEXT_MID
	return Palette.TEXT_MID


func depth_text() -> String:
	return "%s M" % Palette.fmt_depth(_depth)


## Live Solo Duel Perfect % for this seat (integer), -1 before the first solo note.
func live_pct() -> int:
	if not _live_pct.is_valid():
		return -1
	var v: Variant = _live_pct.call(seat)
	if v == null:
		return -1
	var f := float(v)
	return -1 if f < 0.0 else int(floor(f))


func place_text() -> String:
	return PLACES[_place] if _place >= 0 and _place < PLACES.size() else ""


func place_color() -> Color:
	return Palette.REWARD_GOLD if _place == 1 else Palette.TEXT_MID


## Lit hull segments (0..10, fractional at the boundary), shared rule with HullArc.
func lit_segments() -> float:
	return HullArc.segments_lit(_hull) * float(HULL_SEGMENTS) / float(HullArc.SEGMENTS)


func hull_color() -> Color:
	return HullArc.color_for(_hull)


func hull() -> float:
	return _hull


## Held reward glyph ("" when nothing is held).
func held_glyph() -> String:
	return Reward.glyph(_held) if _held >= 0 else ""


func held_reward() -> int:
	return _held


func meter_fraction() -> float:
	if _held >= 0:
		return 1.0
	return clampf(float(_progress) / float(maxi(_threshold, 1)), 0.0, 1.0)


func bounty() -> bool:
	return _bounty


func blip_count() -> int:
	return _blips.size()


func callsign_x() -> float:
	return CALL_X_BOUNTY if _bounty else CALL_X


func shown_callsign() -> String:
	return ProgressTrack.truncate_px(callsign, spaced_font(), Palette.SIZE_LABEL, CALL_MAX)


func edge_color() -> Color:
	var base := Palette.alpha(Palette.SONAR, EDGE_ALPHA)
	if _targeted:
		base = Palette.SONAR
	elif _wreck:
		base = Palette.alpha(Palette.TEXT_LO, WRECK_EDGE_ALPHA)
	if _edge_flash_left > 0.0 and _edge_flash_sec > 0.0:
		var k := _edge_flash_left / _edge_flash_sec
		return base.lerp(_edge_flash_color, k)
	return base


func bracket_color() -> Color:
	if _wreck:
		return Palette.alpha(Palette.TEXT_LO, WRECK_BRACKET_ALPHA)
	if _bounty:
		return Palette.REWARD_GOLD
	return Palette.alpha(Palette.SONAR, BRACKET_ALPHA)


func sweep_on() -> bool:
	return not _low and not _reduce


func blips_max() -> int:
	return BLIPS_LOW if _low else BLIPS_FULL


# ---- Effect contract --------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	_box = UiKit.chamfer_box(Palette.alpha(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA),
		Palette.alpha(Palette.ABYSS_700, 0.0), 0, Palette.CUT_SM)
	_box.shadow_color = Palette.alpha(Palette.SONAR, Palette.PANEL_GLOW_ALPHA)
	_box.shadow_size = 0 if _low else Palette.PANEL_GLOW_SIZE
	_box.shadow_offset = Vector2.ZERO
	if _reduce:
		_dmg_left = 0.0
	var cap := blips_max()
	while _blips.size() > cap:
		_blips.pop_front()
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"sweep": sweep_on(), "blips_max": blips_max(), "glow": not _low,
		"burst_radius": not _reduce, "damage_flash": not _reduce}


# ---- Drawing ----------------------------------------------------------------------------

func _sweep_angle() -> float:
	var turn := 0.0
	if _chart != null and not _chart.tempo_map.is_empty():
		var bar := MatchSim.bar_beats_at(_now, _chart)
		turn = BeatClock.beat_at(_now, _chart.tempo_map) / maxf(bar, 1.0)
	else:
		turn = _now / 2.0  # 4/4 at 120 BPM
	return -PI * 0.5 + TAU * fposmod(turn, 1.0)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	if _box == null:
		apply_effect_settings()
	draw_style_box(_box, r)
	var outline := UiKit.chamfer_points(r.grow(-Palette.EDGE * 0.5), Palette.CUT_SM)
	outline.append(outline[0])
	draw_polyline(outline, edge_color(), Palette.EDGE, true)
	UiKit.draw_brackets(self, r, bracket_color())
	_draw_scope()
	_draw_text()
	_draw_hull()
	_draw_threat()


func _draw_scope() -> void:
	draw_circle(SCOPE_C, DISC_R, Palette.alpha(Palette.ABYSS_900, DISC_ALPHA))
	draw_arc(SCOPE_C, ARC_R, ARC_FROM, ARC_FROM + ARC_SPAN, ARC_POINTS,
		Palette.alpha(Palette.ABYSS_500, TRACK_ALPHA), ARC_W, true)
	var frac := meter_fraction()
	var fill := Palette.SONAR
	if _wreck:
		fill = Palette.TEXT_MID
	elif _held >= 0:
		fill = Palette.SONAR_PALE
	if frac > 0.0:
		draw_arc(SCOPE_C, ARC_R, ARC_FROM, ARC_FROM + ARC_SPAN * frac, maxi(4, int(ARC_POINTS * frac)),
			fill, ARC_W, true)
	var g := held_glyph()
	if g != "":
		var ring := Palette.TEXT_MID
		if Reward.is_disruptor(_held):
			ring = Palette.WARNING_RED
		elif Reward.is_buff(_held):
			ring = Palette.SONAR
		draw_arc(SCOPE_C, KIND_R, 0.0, TAU, 40, ring, Palette.EDGE, true)
		UiIcons.draw(self, g, Rect2(SCOPE_C - Vector2.ONE * HELD_SIZE * 0.5, Vector2.ONE * HELD_SIZE), Palette.TEXT_HI)
		return
	if sweep_on():
		var a := _sweep_angle()
		draw_line(SCOPE_C, SCOPE_C + Vector2(cos(a), sin(a)) * DISC_R, Palette.alpha(Palette.SONAR, SWEEP_ALPHA), 1.0, true)
	for b in _blips:
		var k := 1.0 - float(b["age"]) / BLIP_SEC
		var p := SCOPE_C + Vector2(cos(float(b["a"])), sin(float(b["a"]))) * float(b["r"])
		draw_circle(p, BLIP_DOT, Palette.alpha(Palette.SONAR, clampf(k, 0.0, 1.0)))


func _draw_text() -> void:
	var fs := Palette.SIZE_LABEL
	if _bounty:
		UiIcons.draw(self, "bounty", BOUNTY_RECT, Palette.REWARD_GOLD)
	var call_col := Palette.TEXT_LO if _wreck else Palette.TEXT_HI
	draw_string(spaced_font(), Vector2(callsign_x(), CALL_BASE), shown_callsign(), HORIZONTAL_ALIGNMENT_LEFT,
		CALL_MAX, fs, call_col)
	var place := place_text()
	if place != "":
		draw_string(Palette.font(), Vector2(PLACE_RIGHT - PLACE_BOX, CALL_BASE), place, HORIZONTAL_ALIGNMENT_RIGHT,
			PLACE_BOX, fs, place_color())
	var st := ProgressTrack.truncate_px(status_text(), Palette.font(), fs, STATUS_MAX)
	draw_string(Palette.font(), Vector2(STATUS_X, STATUS_BASE), st, HORIZONTAL_ALIGNMENT_LEFT, STATUS_MAX, fs,
		status_color())


func _segment_rect(k: int) -> Rect2:
	var pitch := (HULL_W + HULL_GAP) / float(HULL_SEGMENTS)
	return Rect2(HULL_X + pitch * k, HULL_Y, pitch - HULL_GAP, HULL_H)


func _draw_hull() -> void:
	var fs := Palette.SIZE_LABEL
	if drone:
		draw_string(Palette.font(), Vector2(HULL_X, WRECK_BASE), "TRAINING", HORIZONTAL_ALIGNMENT_LEFT, HULL_W, fs,
			Palette.TEXT_LO)
		return
	if _wreck:
		UiIcons.draw(self, "skull", WRECK_GLYPH, Palette.WARNING_RED)
		draw_string(Palette.font(), Vector2(WRECK_TEXT_X, WRECK_BASE), "WRECK", HORIZONTAL_ALIGNMENT_LEFT,
			HULL_W - (WRECK_TEXT_X - HULL_X), fs, Palette.WARNING_RED)
		return
	var n := lit_segments()
	var lit := hull_color()
	var unlit := Palette.alpha(Palette.ABYSS_500, UNLIT_ALPHA)
	var n_old := HullArc.segments_lit(_dmg_from) * float(HULL_SEGMENTS) / float(HullArc.SEGMENTS)
	for k in HULL_SEGMENTS:
		var sr := _segment_rect(k)
		var f := clampf(n - k, 0.0, 1.0)
		if f < 1.0:
			draw_rect(sr, unlit)
		if f > 0.0:
			draw_rect(sr, Palette.alpha(lit, f))
		if _dmg_left > 0.0:
			var lost := clampf(n_old - k, 0.0, 1.0) - f
			if lost > 0.0:
				draw_rect(sr, Palette.alpha(Palette.WARNING_RED, _dmg_left / DMG_SEC * maxf(lost, 0.5)))


func _draw_threat() -> void:
	var state := threat_state()
	var top := -PI * 0.5
	match state:
		"none":
			var step_a := TAU / DASHES
			for i in DASHES:
				draw_arc(THREAT_C, THREAT_R, top + step_a * i, top + step_a * (i + 0.5), 4,
					Palette.alpha(Palette.TEXT_LO, 0.2), 1.0, true)
		"incoming", "active", "immune":
			var col := Palette.WARNING_RED
			if state == "active":
				col = Palette.alpha(Palette.WARNING_RED, 0.6)
			elif state == "immune":
				col = Palette.alpha(Palette.TEXT_LO, WRECK_EDGE_ALPHA)
			var f := threat_fraction()
			if f > 0.0:
				# Drains clockwise: the remaining arc ends at 12 o'clock.
				draw_arc(THREAT_C, THREAT_R, top + TAU * (1.0 - f), top + TAU, maxi(4, int(40 * f)), col, THREAT_W, true)
		"collision":
			if _burst_left > 0.0:
				draw_arc(THREAT_C, burst_radius(), 0.0, TAU, 40,
					Palette.alpha(Palette.TEXT_HI, _burst_left / BURST_SEC), THREAT_W, true)
		"reflected":
			draw_arc(THREAT_C, THREAT_R, 0.0, TAU, 40,
				Palette.alpha(Palette.SONAR_PALE, _glyph_left / GLYPH_SEC), THREAT_W, true)
	var g := threat_glyph()
	if g == "":
		return
	var gc := Palette.TEXT_HI
	if state == "immune":
		gc = Palette.TEXT_LO
	elif state == "absorbed":
		gc = Palette.SONAR
	UiIcons.draw(self, g, Rect2(THREAT_C - Vector2.ONE * HELD_SIZE * 0.5, Vector2.ONE * HELD_SIZE), gc)
