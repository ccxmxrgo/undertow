class_name EdgeFlash
extends Control
## Screen-edge threat flash (03-UI-SPEC 6.5, D-04, TORP-04): one of the four telegraph cues that
## start on the launch beat of a threat aimed at the local seat.
## - Two vertical strips, x 0..16 and x 1904..1920, full height. Each is a horizontal gradient
##   from WARNING_RED at the screen edge to 0 alpha 16 px inward.
## - Launch pulse: alpha 0 -> 0.50 over 60 ms, then a linear decay to 0 at the arrival time.
## - Arrival pulse: 0.30, decaying to 0 over 300 ms.
## - Photosensitivity (UI-SPEC 11.6, T-03-27): at most 2 pulses per torpedo (launch + arrival)
##   and never more than 3 pulses per second: a pulse within 333 ms of an accepted pulse, or one
##   that would be the 4th inside any 1 s window, is skipped.
## Same in every effect mode (opacity only, already Reduce-motion safe; UI-SPEC 12 lists it as
## on/on/on), so it deliberately does NOT call UiKit.register_fx: test_effect_settings requires
## every registered node to change its effect_counts() under Low effects or Reduce motion.
## Beat-locked: alpha is a pure function of song time (observe(t)), never of frame time.
## Full-screen canvas (UiLayout.fill_rect), so it implements keepout_shapes() with the strips.

const STRIP_W := 16.0
const SCREEN := Vector2(1920.0, 1080.0)
const LAUNCH_PEAK := 0.5
const RISE_SEC := 0.06
const ARRIVAL_PEAK := 0.3
const ARRIVAL_SEC := 0.3
const MIN_GAP_SEC := 1.0 / 3.0
const MAX_PER_SEC := 3
const KIND_LAUNCH := 0
const KIND_ARRIVAL := 1

var _channel: EventChannel
var _local_seat: int = 0
## Accepted pulses: {kind, t, end} (launch: t = launch, end = arrival; arrival: t = arrival).
var _pulses: Array[Dictionary] = []
var _t: float = 0.0
var _tex_left: GradientTexture2D
var _tex_right: GradientTexture2D


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_textures()


func bind(channel: EventChannel, local_seat: int) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_local_seat = local_seat
	if _channel != null:
		_channel.received.connect(on_event)


func on_event(e: Dictionary) -> void:
	if str(e.get("type", "")) != GameEvent.TORPEDO_LAUNCH:
		return
	if int(e.get("to", -1)) != _local_seat:
		return
	var launch := float(e.get("launch_t", e.get("t", 0.0)))
	var arrive := float(e.get("arrive_t", launch))
	add_threat(launch, arrive)


## Schedules the launch and arrival pulses of one threat (each subject to the rate cap).
## Returns how many of the two were accepted.
func add_threat(launch_t: float, arrive_t: float) -> int:
	if not is_finite(launch_t) or not is_finite(arrive_t):
		return 0
	arrive_t = maxf(arrive_t, launch_t + RISE_SEC)
	_prune(launch_t)
	var n := 0
	if _try_add({"kind": KIND_LAUNCH, "t": launch_t, "end": arrive_t}):
		n += 1
	if _try_add({"kind": KIND_ARRIVAL, "t": arrive_t, "end": arrive_t + ARRIVAL_SEC}):
		n += 1
	queue_redraw()
	return n


func _try_add(p: Dictionary) -> bool:
	if not can_pulse_at(float(p["t"])):
		return false
	_pulses.append(p)
	return true


## True when a pulse starting at t keeps the photosensitivity cap: no accepted pulse within
## 333 ms and fewer than 3 accepted pulses in any 1 s window containing t.
func can_pulse_at(t: float) -> bool:
	var times: Array[float] = []
	for q in _pulses:
		var qt := float(q["t"])
		if absf(qt - t) < MIN_GAP_SEC - 1e-6:
			return false
		if absf(qt - t) < 1.0:
			times.append(qt)
	times.append(t)
	times.sort()
	for i in range(times.size()):
		var c := 0
		for j in range(i, times.size()):
			if times[j] - times[i] <= 1.0 + 1e-9:
				c += 1
		if c > MAX_PER_SEC:
			return false
	return true


func _prune(now: float) -> void:
	var keep: Array[Dictionary] = []
	for p in _pulses:
		if float(p["end"]) + 1.0 >= now:
			keep.append(p)
	_pulses = keep


## Accepted pulse start times (tests).
func pulse_times() -> Array[float]:
	var out: Array[float] = []
	for p in _pulses:
		out.append(float(p["t"]))
	return out


## Strip opacity at song time t: the strongest envelope of all accepted pulses.
func alpha_at(t: float) -> float:
	var a := 0.0
	for p in _pulses:
		a = maxf(a, _envelope(p, t))
	return clampf(a, 0.0, 1.0)


static func _envelope(p: Dictionary, t: float) -> float:
	var t0 := float(p["t"])
	var t1 := float(p["end"])
	if t < t0 or t >= t1:
		return 0.0
	if int(p["kind"]) == KIND_ARRIVAL:
		return ARRIVAL_PEAK * (1.0 - (t - t0) / ARRIVAL_SEC)
	var peak_t := t0 + RISE_SEC
	if t < peak_t:
		return LAUNCH_PEAK * (t - t0) / RISE_SEC
	return LAUNCH_PEAK * (t1 - t) / maxf(t1 - peak_t, 1e-6)


func observe(song_time: float) -> void:
	if not is_finite(song_time):
		return
	_t = song_time
	queue_redraw()


func current_alpha() -> float:
	return alpha_at(_t)


## W4 keep-out contract (global space): the two 16 px strips, full height.
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var out: Array[PackedVector2Array] = []
	for r in strip_rects():
		out.append(PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
			xf * Vector2(r.position.x, r.end.y)]))
	return out


func strip_rects() -> Array[Rect2]:
	var w := _screen_size()
	var out: Array[Rect2] = [Rect2(0.0, 0.0, STRIP_W, w.y), Rect2(w.x - STRIP_W, 0.0, STRIP_W, w.y)]
	return out


func _screen_size() -> Vector2:
	if size.x >= STRIP_W * 2.0 and size.y > 0.0:
		return size
	return SCREEN


func _build_textures() -> void:
	var g := Gradient.new()
	g.set_color(0, Palette.WARNING_RED)
	g.set_color(1, Palette.alpha(Palette.WARNING_RED, 0.0))
	_tex_left = GradientTexture2D.new()
	_tex_left.gradient = g
	_tex_left.width = int(STRIP_W)
	_tex_left.height = 4
	_tex_left.fill_from = Vector2(0.0, 0.0)
	_tex_left.fill_to = Vector2(1.0, 0.0)
	_tex_right = GradientTexture2D.new()
	_tex_right.gradient = g
	_tex_right.width = int(STRIP_W)
	_tex_right.height = 4
	_tex_right.fill_from = Vector2(1.0, 0.0)
	_tex_right.fill_to = Vector2(0.0, 0.0)


func _draw() -> void:
	var a := current_alpha()
	if a <= 0.001:
		return
	if _tex_left == null:
		_build_textures()
	var rects := strip_rects()
	var m := Palette.alpha(Palette.WHITE, a)
	draw_texture_rect(_tex_left, rects[0], false, m)
	draw_texture_rect(_tex_right, rects[1], false, m)
