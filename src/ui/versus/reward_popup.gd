class_name RewardPopup
extends Control
## Reward-ready popup (03-UI-SPEC 5.4, S-4) at the streak milestone popup anchor (centre x 208):
## caption "REWARD READY · {FIRE}" / "SOLO PRIZE · {FIRE}" / "PRIZE QUEUED" (Label 20 TEXT_HI,
## 3 px KEYLINE, baseline 548) and the reward HUD name (Heading 40, 3 px KEYLINE, baseline 590,
## WARNING_RED for a disruptor, SONAR_PALE for a buff). Pop 1.3 -> 1.0 over DUR_FAST (back-out),
## hold 1.2 s, fade 0.22 s, no rise. Popups queue FIFO and wait while `blocker` returns true
## (a streak milestone popup is showing). {FIRE} is the current fire binding: the keyboard label,
## or the pad label once the last input came from a gamepad.
## Full-screen canvas (UiLayout.fill_rect); keepout_shapes() returns the text rect.
## Updates only from EventChannel events for the local seat (03-SPEC req 12).
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const CX := 208.0
const CAPTION_BASE_Y := 548.0
const NAME_BASE_Y := 590.0
const TEXT_RECT := Rect2(0.0, 516.0, 416.0, 82.0)  # y 516..598
const OUTLINE_PX := 6  # 3 px KEYLINE each side
const POP_FROM := 1.3
const HOLD_SEC := 1.2
const FADE_SEC := 0.22
const LIFE := Palette.DUR_FAST + HOLD_SEC + FADE_SEC
const FIRE_TOKEN := "{FIRE}"

## True once the last input event came from a gamepad (chooses the {FIRE} label).
var last_pad: bool = false

var _channel: EventChannel
var _seat: int = 0
var _blocker: Callable = Callable()
var _queue: Array[Dictionary] = []  # {caption, name, color}
var _cur: Dictionary = {}
var _age: float = 0.0
var _reduce: bool = false


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(channel: EventChannel, seat: int, blocker: Callable = Callable()) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_seat = seat
	_blocker = blocker
	if channel != null:
		channel.received.connect(on_event)


func on_event(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	if type != GameEvent.REWARD_EARNED and type != GameEvent.REWARD_QUEUED:
		return
	if int(e.get("seat", -1)) != _seat:
		return
	var id := int(e.get("reward", -1))
	if not Reward.is_valid(id):
		return
	var caption := "REWARD READY · " + FIRE_TOKEN
	if type == GameEvent.REWARD_QUEUED:
		caption = "PRIZE QUEUED"
	elif str(e.get("source", "")) == "duel":
		caption = "SOLO PRIZE · " + FIRE_TOKEN
	_queue.append({"caption": caption, "name": Reward.hud_name(id), "color": name_color_for(id)})
	_try_start()


static func name_color_for(id: int) -> Color:
	if Reward.is_disruptor(id):
		return Palette.WARNING_RED
	if Reward.is_buff(id):
		return Palette.SONAR_PALE
	return Palette.TEXT_MID


func _blocked() -> bool:
	return _blocker.is_valid() and bool(_blocker.call())


func _try_start() -> void:
	if not _cur.is_empty() or _queue.is_empty() or _blocked():
		return
	_cur = _queue.pop_front()
	_age = 0.0
	queue_redraw()


## Advance the popup by dt seconds.
func step(dt: float) -> void:
	if dt > 0.0 and not _cur.is_empty():
		_age += dt
		if _age >= LIFE - 1e-6:
			_cur = {}
			_age = 0.0
	_try_start()
	queue_redraw()


func _process(delta: float) -> void:
	if not _cur.is_empty() or not _queue.is_empty():
		step(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.5:
			return
		last_pad = true
	elif event is InputEventKey:
		last_pad = false


func fire_label() -> String:
	var device := &"gamepad" if last_pad else &"keyboard"
	return Settings.bindings.display_name(&"fire", device).to_upper()


func showing() -> bool:
	return not _cur.is_empty()


func queued_count() -> int:
	return _queue.size()


func caption_text() -> String:
	if _cur.is_empty():
		return ""
	return str(_cur["caption"]).replace(FIRE_TOKEN, fire_label())


func name_text() -> String:
	return "" if _cur.is_empty() else str(_cur["name"])


func name_color() -> Color:
	return Palette.TEXT_HI if _cur.is_empty() else (_cur["color"] as Color)


func pop_scale() -> float:
	if _reduce or _cur.is_empty():
		return 1.0
	var k := clampf(_age / Palette.DUR_FAST, 0.0, 1.0)
	return lerpf(POP_FROM, 1.0, _ease_out_back(k))


func alpha() -> float:
	if _cur.is_empty():
		return 0.0
	var fade_at := Palette.DUR_FAST + HOLD_SEC
	if _age <= fade_at:
		return 1.0
	return clampf(1.0 - (_age - fade_at) / FADE_SEC, 0.0, 1.0)


static func _ease_out_back(k: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"pop": not _reduce}


## W4 keep-out contract: the popup text area (global space).
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var r := TEXT_RECT
	return [PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
		xf * Vector2(r.position.x, r.end.y)])]


func _draw() -> void:
	if _cur.is_empty():
		return
	var a := alpha()
	if a <= 0.0:
		return
	var s := pop_scale()
	var key := Palette.alpha(Palette.KEYLINE, Palette.KEYLINE.a * a)
	var mid := Vector2(CX, (CAPTION_BASE_Y + NAME_BASE_Y) * 0.5)
	draw_set_transform(mid - mid * s, 0.0, Vector2(s, s))
	_centred(Palette.font(), Palette.SIZE_LABEL, caption_text(), CAPTION_BASE_Y, Palette.alpha(Palette.TEXT_HI, a), key)
	_centred(Palette.display_font(), Palette.SIZE_HEADING, name_text(), NAME_BASE_Y, Palette.alpha(name_color(), a), key)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _centred(f: Font, fs: int, text: String, base_y: float, col: Color, key: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(CX - w * 0.5, base_y)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE_PX, key)
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
