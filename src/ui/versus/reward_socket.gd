class_name RewardSocket
extends Control
## Reward socket (03-UI-SPEC 5.1, S-1, S-2, S-4, D-33): the 270 degree reward meter arc, the
## held reward icon with its kind ring, the waiting-for-beat dashed state, launch / used / lost
## animations, the Solo Duel prize queue pip and the wreck debris variant. A sibling drawn over
## TorpedoSocket at the same rect. The name line under the socket is a child Label.
## Updates only from EventChannel events for the local seat (03-SPEC req 12); malformed events
## are read with defaults and ignored (T-03-23). Animation timers advance through step(dt).
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const RECT := Rect2(272.0, 928.0, 80.0, 80.0)
const CENTER := Vector2(40.0, 40.0)  # local; global (312, 968)
const R_ARC := 40.0
const BAND := 4.0
const ARC_FROM := 0.75 * PI  # 135 deg
const ARC_TO := 2.25 * PI  # 405 deg
const ARC_POINTS := 48
const TRACK_ALPHA := 0.70
const TICK_LEN := 6.0
const TICK_W := 2.0
const TICK_ALPHA := 0.60
const BREATH_SEC := 1.6
const BREATH_LO := 0.70
const ICON_RECT := Rect2(24.0, 24.0, 32.0, 32.0)  # global (296, 952, 32, 32)
const RING_R := 34.0
const RING_W := 2.0
const RING_DASHES := 8
const EARN_PEAK := 1.15
const EARN_FLASH_SEC := 0.12
const LOST_FLASH_SEC := 0.2
const LAUNCH_SCALE := 0.6
const WAIT_ALPHA := 0.5
const PIP_CENTER := Vector2(346.0, 934.0)  # global
const PIP_R := 5.0
const NAME_CX := 312.0
const NAME_BASE_Y := 1036.0
const NAME_W := 160.0
const GLOW_SCALE := 1.6  # Palette.GLOW_SM
const GLOW_ALPHA := 0.35

enum Anim { NONE, EARN, LAUNCH, USED, LOST }

var name_label: Label

var _channel: EventChannel
var _seat: int = 0
var _cfg: VersusConfig
var _progress: int = 0
var _threshold: int = 0
var _held: int = -1
var _queued: int = -1
var _debris: bool = false
var _debris_used: int = 0
var _waiting: bool = false
var _anim: Anim = Anim.NONE
var _anim_t: float = 0.0
var _anim_reward: int = -1
var _breath_t: float = 0.0
var _breath_q: int = -1  # last drawn breathing alpha step (WR-10)
var _arc_from: float = 0.0
var _arc_to: float = 0.0
var _arc_t: float = 1.0
var _low: bool = false
var _reduce: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label = Label.new()
	name_label.name = "NameLine"
	var f := UiKit.chip_font()  # Share Tech Mono +1 px letter spacing
	var fs := Palette.SIZE_LABEL
	name_label.add_theme_font_override("font", f)
	name_label.add_theme_font_size_override("font_size", fs)
	name_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	name_label.position = Vector2(NAME_CX - NAME_W * 0.5, NAME_BASE_Y - f.get_ascent(fs)) - RECT.position
	name_label.size = Vector2(NAME_W, f.get_height(fs))
	add_child(name_label)
	UiKit.register_fx(self)
	apply_effect_settings()
	_refresh()


## Listen to `channel` for `seat`. Safe to call again (rebinds).
func bind(channel: EventChannel, seat: int, cfg: VersusConfig) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_seat = seat
	_cfg = cfg if cfg != null else VersusConfig.new()
	if channel != null:
		channel.received.connect(on_event)
	_refresh()


func _cap() -> int:
	return (_cfg if _cfg != null else VersusConfig.new()).debris_max_per_wreck


func on_event(e: Dictionary) -> void:
	var type: String = str(e.get("type", ""))
	match type:
		GameEvent.METER:
			if int(e.get("seat", -1)) != _seat:
				return
			var was := _arc_target()
			_progress = maxi(int(e.get("progress", _progress)), 0)
			_threshold = maxi(int(e.get("threshold", _threshold)), 0)
			var held := int(e.get("held", _held))
			if held == -1 or Reward.is_valid(held):
				if held == -1 and _held != -1 and _anim != Anim.LAUNCH:
					_start_anim(Anim.USED, _held)
				_held = held
			if _held == -1:
				_waiting = false
			var q := int(e.get("queued", _queued))
			_queued = q if Reward.is_valid(q) else -1
			if bool(e.get("debris", false)):
				_debris = true
			if e.has("debris_used"):
				_debris_used = clampi(int(e["debris_used"]), 0, 1000)
			_retarget_arc(was)
		GameEvent.REWARD_EARNED:
			if int(e.get("seat", -1)) != _seat:
				return
			var id := int(e.get("reward", -1))
			if not Reward.is_valid(id):
				return
			_held = id
			_waiting = false
			_start_anim(Anim.EARN, id)
		GameEvent.REWARD_QUEUED:
			if int(e.get("seat", -1)) != _seat:
				return
			var qid := int(e.get("reward", -1))
			if Reward.is_valid(qid):
				_queued = qid
		GameEvent.FIRE_QUEUED:
			if int(e.get("seat", -1)) == _seat and _held != -1:
				_waiting = true
		GameEvent.FIRE_REFUSED:
			if int(e.get("seat", -1)) == _seat:
				_waiting = false
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("from", -1)) != _seat:
				return
			_waiting = false
			if bool(e.get("debris", false)):
				_debris_used += 1
			var was2 := _arc_target()
			var r := _held if _held != -1 else int(e.get("reward", -1))
			_held = -1
			_start_anim(Anim.LAUNCH, r)
			_retarget_arc(was2)
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == _seat and _held != -1 and _held == int(e.get("reward", -2)):
				_start_anim(Anim.USED, _held)
				_held = -1
				_waiting = false
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) != _seat:
				return
			_start_anim(Anim.LOST, _held)
			_held = -1
			_queued = -1
			_waiting = false
			_debris = true
			_progress = 0
			_retarget_arc(0.0)
		_:
			return
	_refresh()


func _start_anim(a: Anim, reward: int) -> void:
	_anim = a
	_anim_t = 0.0
	_anim_reward = reward


func _anim_len() -> float:
	match _anim:
		Anim.EARN:
			return Palette.DUR_BASE
		Anim.LAUNCH, Anim.USED:
			return Palette.DUR_FAST
		Anim.LOST:
			return LOST_FLASH_SEC
	return 0.0


func _arc_target() -> float:
	if _held != -1:
		return 1.0
	if _threshold <= 0:
		return 0.0
	return clampf(float(_progress) / float(_threshold), 0.0, 1.0)


func _retarget_arc(from: float) -> void:
	var to := _arc_target()
	if _reduce or is_equal_approx(from, to):
		_arc_from = to
		_arc_to = to
		_arc_t = 1.0
		return
	_arc_from = arc_shown() if _arc_t < 1.0 else from
	_arc_to = to
	_arc_t = 0.0


## Advance animations by dt seconds.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_breath_t = fmod(_breath_t + dt, BREATH_SEC)
	# Redraw only while something animates (WR-10): breathing held arc, a pop / launch / lost
	# animation, or the arc easing to its target (checked before advancing so the last frame
	# of an animation still redraws). Events redraw through _refresh().
	var animating := _anim != Anim.NONE or _arc_t < 1.0
	if breathing():
		# The 1.6 s breath moves alpha by < 0.4 / s: redraw only when it changes by 1/64
		# (about 24 redraws / s instead of every frame; the step is invisible).
		var q := int(full_alpha() * 64.0)
		if q != _breath_q:
			_breath_q = q
			animating = true
	if _anim != Anim.NONE:
		_anim_t += dt
		if _anim_t >= _anim_len():
			_anim = Anim.NONE
			_anim_t = 0.0
	if _arc_t < 1.0:
		_arc_t = minf(_arc_t + dt / Palette.DUR_BASE, 1.0)
	if animating:
		queue_redraw()


func _process(delta: float) -> void:
	step(delta)


# ---- getters (tests) -----------------------------------------------------------------------

func name_text() -> String:
	if _debris:
		if _debris_used >= _cap():
			return "NO DEBRIS LEFT"
		if _held != -1:
			return Reward.hud_name(_held)
		var s := "DEBRIS %d/%d" % [_progress, _threshold]
		var f := UiKit.chip_font()
		if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x > NAME_W:
			s = "%d/%d" % [_progress, _threshold]
		return s
	if _held != -1:
		return Reward.hud_name(_held)
	return "%d/%d" % [_progress, _threshold]


func name_color() -> Color:
	if _debris:
		if _debris_used >= _cap():
			return Palette.TEXT_LO
		return Palette.TEXT_MID if _held != -1 else Palette.TEXT_LO
	return Palette.TEXT_HI if _held != -1 else Palette.TEXT_LO


## Fill fraction of the meter arc (1.0 while a reward is held).
func arc_fraction() -> float:
	return _arc_target()


## Animated fill fraction currently drawn.
func arc_shown() -> float:
	return lerpf(_arc_from, _arc_to, clampf(_arc_t, 0.0, 1.0)) if _arc_t < 1.0 else _arc_target()


func arc_visible() -> bool:
	return not (_debris and _debris_used >= _cap())


func arc_color() -> Color:
	return Palette.TEXT_MID if _debris else Palette.SONAR


## Kind ring colour of the held reward (TEXT_MID for debris).
func ring_color() -> Color:
	return _kind_color(_held)


static func _kind_color(id: int) -> Color:
	if Reward.is_disruptor(id):
		return Palette.WARNING_RED
	if Reward.is_buff(id):
		return Palette.SONAR
	return Palette.TEXT_MID


func breathing() -> bool:
	return _held != -1 and not _reduce


## Alpha of the full (held) arc: 0.70..1.00 sine over 1.6 s; 1.0 under Reduce motion.
func full_alpha() -> float:
	if not breathing():
		return 1.0
	var k := 0.5 - 0.5 * cos(_breath_t / BREATH_SEC * TAU)
	return lerpf(BREATH_LO, 1.0, 1.0 - k)


func waiting() -> bool:
	return _waiting


func launching() -> bool:
	return _anim == Anim.LAUNCH


func lost_flashing() -> bool:
	return _anim == Anim.LOST


func queue_pip_visible() -> bool:
	return _queued != -1


func pip_color() -> Color:
	return Palette.REWARD_GOLD


func is_debris() -> bool:
	return _debris


func held() -> int:
	return _held


## Held icon scale: earn pop 0 -> 1.15 -> 1.0 (none under Reduce motion).
func icon_scale() -> float:
	if _anim == Anim.EARN and not _reduce:
		var k := clampf(_anim_t / Palette.DUR_BASE, 0.0, 1.0)
		if k < 0.6:
			return EARN_PEAK * _ease_out(k / 0.6)
		return lerpf(EARN_PEAK, 1.0, (k - 0.6) / 0.4)
	return 1.0


func icon_alpha() -> float:
	if _anim == Anim.EARN and _reduce:
		return clampf(_anim_t / Palette.DUR_BASE, 0.0, 1.0)
	if _waiting:
		return WAIT_ALPHA
	return 1.0


static func _ease_out(k: float) -> float:
	var u := 1.0 - clampf(k, 0.0, 1.0)
	return 1.0 - u * u * u


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"breathing": not _reduce, "glow": not _low, "pop": not _reduce}


func _refresh() -> void:
	if name_label != null:
		name_label.text = ProgressTrack.truncate_px(name_text(), UiKit.chip_font(), Palette.SIZE_LABEL, NAME_W)
		name_label.add_theme_color_override("font_color", name_color())
	queue_redraw()


# ---- drawing --------------------------------------------------------------------------------

func _draw() -> void:
	if arc_visible():
		_draw_arc()
		_draw_icon()
	if _anim == Anim.LOST:
		draw_arc(CENTER, RING_R, 0.0, TAU, 48, Palette.alpha(Palette.WARNING_RED,
			1.0 - _anim_t / LOST_FLASH_SEC), RING_W, true)
		_draw_fading_icon(1.0 - clampf(_anim_t / Palette.DUR_FAST, 0.0, 1.0), 1.0)
	if queue_pip_visible():
		draw_circle(PIP_CENTER - RECT.position, PIP_R, pip_color(), true, -1.0, true)


func _draw_arc() -> void:
	var r_mid := R_ARC - BAND * 0.5
	draw_arc(CENTER, r_mid, ARC_FROM, ARC_TO, ARC_POINTS, Palette.alpha(Palette.ABYSS_500, TRACK_ALPHA), BAND, true)
	if _held != -1:
		var a := full_alpha()
		if not _low:
			var g := RECT.size.x * GLOW_SCALE
			draw_texture_rect(UiKit.glow_texture(), Rect2(CENTER - Vector2(g, g) * 0.5, Vector2(g, g)), false,
				Palette.alpha(Palette.SONAR_PALE, GLOW_ALPHA * a))
		var col := Palette.TEXT_MID if _debris else Palette.SONAR_PALE
		draw_arc(CENTER, r_mid, ARC_FROM, ARC_TO, ARC_POINTS, Palette.alpha(col, a), BAND, true)
	else:
		var k := arc_shown()
		if k > 0.0:
			draw_arc(CENTER, r_mid, ARC_FROM, lerpf(ARC_FROM, ARC_TO, k), maxi(4, int(ARC_POINTS * k)),
				arc_color(), BAND, true)
	var tick := Palette.alpha(Palette.TEXT_LO, TICK_ALPHA)
	for i in [1, 2, 3]:
		var ang := lerpf(ARC_FROM, ARC_TO, i * 0.25)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(CENTER + dir * (R_ARC - TICK_LEN), CENTER + dir * R_ARC, tick, TICK_W, true)


func _draw_icon() -> void:
	if _held == -1:
		if _anim == Anim.LAUNCH:
			var k := clampf(_anim_t / Palette.DUR_FAST, 0.0, 1.0)
			_draw_fading_icon(1.0 - k, 1.0 if _reduce else lerpf(1.0, LAUNCH_SCALE, k))
		elif _anim == Anim.USED:
			_draw_fading_icon(1.0 - clampf(_anim_t / Palette.DUR_FAST, 0.0, 1.0), 1.0)
		return
	var s := icon_scale()
	var a := icon_alpha()
	var ring := ring_color()
	if _anim == Anim.EARN and _anim_t < EARN_FLASH_SEC:
		ring = Palette.SONAR_PALE
	if _waiting:
		var step_a := TAU / RING_DASHES
		for i in RING_DASHES:
			draw_arc(CENTER, RING_R, step_a * i, step_a * i + step_a * 0.5, 6, ring, RING_W, true)
	else:
		draw_arc(CENTER, RING_R, 0.0, TAU, 48, Palette.alpha(ring, a), RING_W, true)
	var r := Rect2(CENTER - ICON_RECT.size * 0.5 * s, ICON_RECT.size * s)
	if s > 0.01:
		UiIcons.draw(self, Reward.glyph(_held), r, Palette.alpha(Palette.TEXT_HI, a))


func _draw_fading_icon(a: float, s: float) -> void:
	if a <= 0.0 or not Reward.is_valid(_anim_reward):
		return
	var r := Rect2(CENTER - ICON_RECT.size * 0.5 * s, ICON_RECT.size * s)
	UiIcons.draw(self, Reward.glyph(_anim_reward), r, Palette.alpha(Palette.TEXT_HI, a))
