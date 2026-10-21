class_name TorpedoJuice
extends Control
## Torpedo juice (05-05, AV-04, D-05): makes torpedoes physical for the local player.
##   LANDED on the local seat  -> impact boom, board shake 10 px / 160 ms, WARNING_RED edge flash
##                               (96 px gradient bands left / right / top, alpha 0.35 -> 0, 120 ms)
##   TORPEDO_LAUNCH by local   -> launch thump + whoosh, board kick 3 px / 80 ms, SONAR_PALE 2 px
##                               ring on the torpedo socket (radius 40 -> 72, alpha 0.8 -> 0, 200 ms)
##   IMPLODED local seat       -> implosion (the IMPLOSION banner shake / vignette stay as they are)
##   IMPLODED rival seat       -> distant implosion (baked about -14 dB) + that rival's periscope
##                               panel edge flashes WARNING_RED for 300 ms
## Effect table (05-05 addendum to 02.2 UI-SPEC 11 / 03-UI-SPEC 11.6, D-13):
##   impact shake  Full on / Low on / Reduce off      impact edge flash  on / on / on (opacity)
##   launch ring   Full on / Low off / Reduce fade only (radius fixed at 56)
##   launch kick   Full on / Low on / Reduce off      rival panel flash  on / on / on
##   sounds (SFX bus) always on.
## Photosensitivity (03-UI-SPEC 11.6, T-05-12): every juice flash (impact bands, socket ring,
## panel flash) goes through one FlashLimiter on event song time: <= 3 per second, >= 1/3 s
## apart. Sounds are not flashes and are not rate capped.
## Events only, no protocol change: reacts to the existing EventChannel records (no new events
## or fields), so offline, host and client behave the same; the sim and channel are untouched
## (T-05-15). Dedupe (Pitfall 7, T-05-13): launches and landings are remembered per torpedo id
## (bounded, like VersusSfx) and implosions per seat, so online echoes never double-fire.
## Fields are read with typed defaults; negative or out-of-range seats are ignored (T-05-14).
## It registers with UiKit.register_fx because its visual parts change with Low effects (ring)
## and Reduce motion (shake / kick); its sounds need no registration (Pitfall 3).
## Full-screen canvas (UiLayout.fill_rect), so it implements keepout_shapes() with the bands.

const IMPACT_SHAKE_PX := 10.0
const IMPACT_SHAKE_USEC := 160000
const IMPACT_FLASH_SEC := 0.12
const IMPACT_PEAK := 0.35
const BAND_PX := 96.0
const KICK_PX := 3.0
const KICK_USEC := 80000
const RING_SEC := 0.2
const RING_R0 := 40.0
const RING_R1 := 72.0
const RING_R_REDUCE := 56.0
const RING_PEAK := 0.8
const RING_W := 2.0
const RING_POINTS := 48
const POOL_SIZE := 4
const MAX_REMEMBERED_IDS := 64
const MAX_SEAT := 15
const SCREEN := Vector2(1920.0, 1080.0)

var impact_count: int = 0
var launch_count: int = 0
var near_implosion_count: int = 0
var distant_implosion_count: int = 0
var flash_count: int = 0
## Every board shake / kick this node asked FxLayer for: [px, usec].
var shake_requests: Array = []

var _channel: EventChannel
var _local_seat: int = 0
var _fx_layer: FxLayer
var _socket: Control
var _column: PeriscopeColumn
var _limiter := FlashLimiter.new()
var _landed_ids: Array[int] = []
var _launch_ids: Array[int] = []
var _imploded_seats: Array[int] = []
var _impact_left: float = 0.0
var _ring_left: float = 0.0
var _low: bool = false
var _reduce: bool = false
var _shown: bool = false
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _bank: Dictionary = {}
var _sfx_counts := {}
var _tex_left: GradientTexture2D
var _tex_right: GradientTexture2D
var _tex_top: GradientTexture2D


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_textures()
	_ensure_audio()
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(channel: EventChannel, local_seat: int, fx_layer: FxLayer, socket: Control,
		column: PeriscopeColumn) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_local_seat = local_seat
	_fx_layer = fx_layer
	_socket = socket
	_column = column
	if _channel != null:
		_channel.received.connect(on_event)


func on_event(e: Dictionary) -> void:
	var t := float(e.get("t", 0.0))
	match str(e.get("type", "")):
		GameEvent.LANDED:
			if int(e.get("to", -1)) == _local_seat and _remember(_landed_ids, int(e.get("id", -1))):
				_on_impact(t)
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("from", -1)) == _local_seat and _remember(_launch_ids, int(e.get("id", -1))):
				_on_launch(t)
		GameEvent.IMPLODED:
			var seat := int(e.get("seat", -1))
			if seat < 0 or seat > MAX_SEAT or _imploded_seats.has(seat):
				return
			_imploded_seats.append(seat)
			_on_implosion(seat, t)


## True the first time an id is seen (ids < 0 always pass: nothing to dedupe on).
func _remember(list: Array[int], id: int) -> bool:
	if id < 0:
		return true
	if list.has(id):
		return false
	list.append(id)
	if list.size() > MAX_REMEMBERED_IDS:
		list.pop_front()
	return true


func _on_impact(t: float) -> void:
	impact_count += 1
	_play("impact")
	if not _reduce:
		_shake(IMPACT_SHAKE_PX, IMPACT_SHAKE_USEC)
	if _limiter.try_flash(t):
		flash_count += 1
		_impact_left = IMPACT_FLASH_SEC
		_redraw_now()


func _on_launch(t: float) -> void:
	launch_count += 1
	_play("launch")
	if not _reduce:
		_shake(KICK_PX, KICK_USEC)
	if not _low and _limiter.try_flash(t):
		flash_count += 1
		_ring_left = RING_SEC
		_redraw_now()


func _on_implosion(seat: int, t: float) -> void:
	if seat == _local_seat:
		near_implosion_count += 1
		_play("implosion")
		return
	distant_implosion_count += 1
	_play("implosion_distant")
	if _column == null or not is_instance_valid(_column):
		return
	var panel := _column.panel_for(seat)
	if panel != null and _limiter.try_flash(t):
		flash_count += 1
		panel.flash_implosion()


func _shake(px: float, usec: int) -> void:
	if _fx_layer == null or not is_instance_valid(_fx_layer):
		return
	shake_requests.append([px, usec])
	_fx_layer.request_shake(px, usec)


# ---- Audio -----------------------------------------------------------------------------------

func _ensure_audio() -> void:
	if _bank.is_empty():
		_bank = AudioSynth.sfx_bank()  # cached; built at load (bind_views), never mid-song
	if _players.is_empty():
		var bus: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		for i in range(POOL_SIZE):
			var p := AudioStreamPlayer.new()
			p.bus = bus
			add_child(p)
			_players.append(p)


func _play(key: String) -> bool:
	if not is_inside_tree():
		return false
	_ensure_audio()
	var s: Variant = _bank.get(key)
	if not (s is AudioStream) or _players.is_empty():
		return false
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.play()
	_sfx_counts[key] = int(_sfx_counts.get(key, 0)) + 1
	return true


## How many times the sound `key` was started (tests).
func sfx_count(key: String) -> int:
	return int(_sfx_counts.get(key, 0))


func players() -> Array[AudioStreamPlayer]:
	return _players


# ---- Visuals ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## Wall-clock decay of the impact bands and the socket ring (tests call it directly).
func step(dt: float) -> void:
	if _impact_left > 0.0:
		_impact_left = maxf(_impact_left - dt, 0.0)
	if _ring_left > 0.0:
		_ring_left = maxf(_ring_left - dt, 0.0)
	# Redraw only while something is visible, plus one frame to clear it (no idle cost).
	var on := impact_active() or ring_active()
	if on or _shown:
		queue_redraw()
	_shown = on


func _redraw_now() -> void:
	_shown = true
	queue_redraw()


func impact_active() -> bool:
	return _impact_left > 0.0


func ring_active() -> bool:
	return _ring_left > 0.0


func impact_alpha() -> float:
	return IMPACT_PEAK * clampf(_impact_left / IMPACT_FLASH_SEC, 0.0, 1.0)


## 0 at the start of the ring, 1 at its end.
func ring_progress() -> float:
	return 1.0 - clampf(_ring_left / RING_SEC, 0.0, 1.0)


func ring_radius() -> float:
	if _reduce:
		return RING_R_REDUCE
	return lerpf(RING_R0, RING_R1, ring_progress())


func ring_alpha() -> float:
	if not ring_active():
		return 0.0
	return RING_PEAK * (1.0 - ring_progress())


func _ring_center() -> Vector2:
	if _socket == null or not is_instance_valid(_socket):
		return Vector2(-10000.0, -10000.0)
	return _socket.get_global_rect().get_center() - global_position


func _draw() -> void:
	if _tex_left == null:
		_build_textures()
	var a := impact_alpha() if impact_active() else 0.0
	if a > 0.001:
		var m := Palette.alpha(Palette.WHITE, a)
		var r := band_rects()
		draw_texture_rect(_tex_left, r[0], false, m)
		draw_texture_rect(_tex_right, r[1], false, m)
		draw_texture_rect(_tex_top, r[2], false, m)
	var ra := ring_alpha()
	if ra > 0.001 and _socket != null and is_instance_valid(_socket):
		draw_arc(_ring_center(), ring_radius(), 0.0, TAU, RING_POINTS,
			Palette.alpha(Palette.SONAR_PALE, ra), RING_W, true)


func _build_textures() -> void:
	var g := Gradient.new()
	g.set_color(0, Palette.WARNING_RED)
	g.set_color(1, Palette.alpha(Palette.WARNING_RED, 0.0))
	_tex_left = _gradient(g, Vector2(0.0, 0.0), Vector2(1.0, 0.0), true)
	_tex_right = _gradient(g, Vector2(1.0, 0.0), Vector2(0.0, 0.0), true)
	_tex_top = _gradient(g, Vector2(0.0, 0.0), Vector2(0.0, 1.0), false)


static func _gradient(g: Gradient, from: Vector2, to: Vector2, horizontal: bool) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = int(BAND_PX) if horizontal else 4
	tex.height = 4 if horizontal else int(BAND_PX)
	tex.fill_from = from
	tex.fill_to = to
	return tex


## Impact bands in local space: left, right, top.
func band_rects() -> Array[Rect2]:
	var w := _screen_size()
	var out: Array[Rect2] = [Rect2(0.0, 0.0, BAND_PX, w.y), Rect2(w.x - BAND_PX, 0.0, BAND_PX, w.y),
		Rect2(0.0, 0.0, w.x, BAND_PX)]
	return out


func _screen_size() -> Vector2:
	if size.x >= BAND_PX * 2.0 and size.y >= BAND_PX:
		return size
	return SCREEN


## W4 keep-out contract (global space): the three impact bands.
func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var out: Array[PackedVector2Array] = []
	for r in band_rects():
		out.append(PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
			xf * Vector2(r.position.x, r.end.y)]))
	return out


# ---- Effect contract -------------------------------------------------------------------------

func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_reduce = UiKit.reduce_motion()
	if _low and _ring_left > 0.0:
		_ring_left = 0.0
		queue_redraw()


func effect_counts() -> Dictionary:
	return {
		"launch_ring": not _low,
		"kick": not _reduce,
		"impact_shake": not _reduce,
		"edge_flash": true,
	}
