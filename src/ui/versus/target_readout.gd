class_name TargetReadout
extends Control
## Target readout (03-UI-SPEC 5.2, S-4, D-01..D-03) in the left console, x 248..392,
## y 752..840: caption (Label 20 TEXT_LO) "AUTO TARGET" / "TARGET" / "ATTACKERS" /
## "DEBRIS TARGET", the resolved callsign (Body 28 TEXT_HI, max 136 px, "..." truncation;
## "NONE" in TEXT_LO, "DRONE" in training) and a 16 px target glyph that pulses once on change.
## Refused fire flashes "SHIELDED" / "NO TARGET" in WARNING_RED for 800 ms; a bounty you claim
## flashes "BOUNTY +n" in REWARD_GOLD for 1200 ms. Updates only from EventChannel events for
## the local seat (03-SPEC req 12). Timers advance through step(dt).
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const RECT := Rect2(248.0, 752.0, 144.0, 88.0)
const CAPTION_POS := Vector2(8.0, 24.0)  # global (256, 776) baseline
const VALUE_POS := Vector2(8.0, 60.0)  # global (256, 812) baseline
const VALUE_MAX_W := 136.0
const GLYPH_RECT := Rect2(124.0, 12.0, 16.0, 16.0)  # global (372, 764)
const PULSE_PEAK := 1.2
const REFUSE_SEC := 0.8
const BOUNTY_SEC := 1.2

var _channel: EventChannel
var _seat: int = 0
var _names: PackedStringArray = PackedStringArray()
var _training: bool = false
var _mode: int = PlayerState.TargetMode.AUTO
var _target: int = -1
var _wreck: bool = false
var _flash_text: String = ""
var _flash_color: Color = Palette.TEXT_LO
var _flash_left: float = 0.0
var _pulse_t: float = -1.0
var _xfade_left: float = 0.0
var _prev_value: String = ""
var _reduce: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(channel: EventChannel, seat: int, names: PackedStringArray, training: bool) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_seat = seat
	_names = names
	_training = training
	if channel != null:
		channel.received.connect(on_event)
	queue_redraw()


func on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		GameEvent.TARGET:
			if int(e.get("seat", -1)) != _seat:
				return
			var mode := clampi(int(e.get("mode", _mode)), PlayerState.TargetMode.AUTO,
				PlayerState.TargetMode.ATTACKERS)
			var target := int(e.get("target", -1))
			if mode == _mode and target == _target:
				return
			var old := value_text()
			_mode = mode
			_target = target
			if value_text() != old:
				_prev_value = old
				_xfade_left = Palette.DUR_FAST
			_pulse_t = 0.0 if not _reduce else -1.0
		GameEvent.FIRE_REFUSED:
			if int(e.get("seat", -1)) != _seat:
				return
			match str(e.get("reason", "")):
				"shielded":
					_flash("SHIELDED", Palette.WARNING_RED, REFUSE_SEC)
				"no_target":
					_flash("NO TARGET", Palette.WARNING_RED, REFUSE_SEC)
		GameEvent.BOUNTY_CLAIMED:
			if int(e.get("from", -1)) != _seat:
				return
			_flash("BOUNTY +%d" % maxi(int(e.get("refund", 0)), 0), Palette.REWARD_GOLD, BOUNTY_SEC)
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == _seat:
				_wreck = true
		_:
			return
	queue_redraw()


func _flash(text: String, col: Color, sec: float) -> void:
	_flash_text = text
	_flash_color = col
	_flash_left = sec


## Advance timers by dt seconds.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	if _flash_left > 0.0:
		_flash_left -= dt
		if _flash_left <= 1e-6:
			_flash_left = 0.0
			_flash_text = ""
	if _pulse_t >= 0.0:
		_pulse_t += dt
		if _pulse_t >= Palette.DUR_FAST:
			_pulse_t = -1.0
	if _xfade_left > 0.0:
		_xfade_left = maxf(_xfade_left - dt, 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_left > 0.0 or _pulse_t >= 0.0 or _xfade_left > 0.0:
		step(delta)


func caption_text() -> String:
	if _flash_left > 0.0:
		return _flash_text
	if _wreck:
		return "DEBRIS TARGET"
	match _mode:
		PlayerState.TargetMode.LOCKED:
			return "TARGET"
		PlayerState.TargetMode.ATTACKERS:
			return "ATTACKERS"
	return "AUTO TARGET"


func caption_color() -> Color:
	return _flash_color if _flash_left > 0.0 else Palette.TEXT_LO


func value_text() -> String:
	if _target < 0:
		return "NONE"
	var raw := "DRONE"
	if not _training:
		raw = _names[_target] if _target < _names.size() else ""
		if raw == "":
			return "NONE"
	return ProgressTrack.truncate_px(raw.to_upper(), Palette.font(), Palette.SIZE_BODY, VALUE_MAX_W)


func value_color() -> Color:
	return Palette.TEXT_LO if value_text() == "NONE" else Palette.TEXT_HI


## Target glyph scale: 1.0 -> 1.2 -> 1.0 over DUR_FAST after a change (never under Reduce motion).
func glyph_scale() -> float:
	if _pulse_t < 0.0 or _reduce:
		return 1.0
	return 1.0 + (PULSE_PEAK - 1.0) * sin(PI * clampf(_pulse_t / Palette.DUR_FAST, 0.0, 1.0))


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	if _reduce:
		_pulse_t = -1.0
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"pulse": not _reduce}


func keepout_rect() -> Rect2:
	return RECT


func _draw() -> void:
	var f := Palette.font()
	draw_string(f, CAPTION_POS, caption_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL, caption_color())
	var k := 1.0
	if _xfade_left > 0.0:
		k = 1.0 - _xfade_left / Palette.DUR_FAST
		if _prev_value != "":
			var pc := Palette.TEXT_LO if _prev_value == "NONE" else Palette.TEXT_HI
			draw_string(f, VALUE_POS, _prev_value, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_BODY,
				Palette.alpha(pc, 1.0 - k))
	draw_string(f, VALUE_POS, value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_BODY,
		Palette.alpha(value_color(), k))
	var s := glyph_scale()
	var c := GLYPH_RECT.get_center()
	UiIcons.draw(self, "target", Rect2(c - GLYPH_RECT.size * 0.5 * s, GLYPH_RECT.size * s), Palette.SONAR_PALE)
