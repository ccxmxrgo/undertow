class_name PeriscopeColumn
extends Control
## The left-column stack of rival periscope panels plus the target reticle and caret
## (03-UI-SPEC 6.2; MATCH-04, TORP-03, D-26). Full-screen, mouse-transparent canvas
## (UiLayout.fill_rect) that reports its drawn parts through keepout_shapes().
## Panels fill top-down in seat order; the training drone uses P1; unused panels do not exist.
## Fed only by EventChannel events (bind); gameplay wiring is plan 03-14, which calls
## update(song_time) every frame. step(dt) drives the glide, entrance and panel flashes.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const PANEL_RECTS: Array[Rect2] = [
	Rect2(24.0, 216.0, 352.0, 88.0), Rect2(24.0, 312.0, 352.0, 88.0), Rect2(24.0, 408.0, 352.0, 88.0),
]
const MAX_PANELS := 3

const RETICLE_OUT := 4.0
const RETICLE_ARM := 16.0
const RETICLE_W := 2.0
const CARET_X := 384.0
const CARET_W := 12.0
const CARET_H := 16.0

const ENTER_SLIDE := 16.0
const ENTER_STAGGER := 0.06

var local_seat: int = 0
var training: bool = false

var _channel: EventChannel
var _panels: Array[PeriscopePanel] = []
var _seat_idx: Dictionary = {}  # seat -> panel index

var _target_seat: int = -1
var _has_reticle: bool = false
var _from: Rect2 = Rect2()
var _to: Rect2 = Rect2()
var _glide: float = 1.0  # 0..1 progress of the current glide

var _enter_t: float = -1.0  # < 0: no entrance running

var _reduce: bool = false
var _low: bool = false


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


## Builds one panel per rival (max 3) and subscribes to the channel. rival_seats are in seat
## order; names are indexed by seat (unknown seats show "?"). live_pct(seat) -> int is the
## read-only Solo Duel Perfect % (-1 before the first solo note).
func bind(channel: EventChannel, p_local_seat: int, rival_seats: Array[int], names: PackedStringArray,
		chart: ChartData, cfg: VersusConfig, live_pct: Callable, p_training: bool) -> void:
	if _channel != null and _channel.received.is_connected(_on_event):
		_channel.received.disconnect(_on_event)
	for p in _panels:
		p.queue_free()
	_panels.clear()
	_seat_idx.clear()
	local_seat = p_local_seat
	training = p_training
	_channel = channel
	var seats := rival_seats.duplicate()
	seats.sort()
	for i in mini(seats.size(), MAX_PANELS):
		var s: int = seats[i]
		var p := PeriscopePanel.new()
		p.name = "Periscope%d" % (i + 1)
		var nm := names[s] if s >= 0 and s < names.size() else "?"
		p.setup(s, nm, training, chart, cfg, live_pct)
		p.position = PANEL_RECTS[i].position
		add_child(p)
		_panels.append(p)
		_seat_idx[s] = i
	_target_seat = -1
	_has_reticle = false
	_glide = 1.0
	if _channel != null:
		_channel.received.connect(_on_event)
	play_entrance()
	queue_redraw()


func panels() -> Array[PeriscopePanel]:
	return _panels


func panel_for(seat: int) -> PeriscopePanel:
	var i: int = _seat_idx.get(seat, -1)
	return _panels[i] if i >= 0 else null


func _on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) == GameEvent.TARGET:
		if int(e.get("seat", -1)) == local_seat:
			set_target(int(e.get("target", -1)))
		return
	for p in _panels:
		p.on_event(e)


## Moves the reticle to `seat`'s panel (-1 or a seat without a panel = no reticle).
func set_target(seat: int) -> void:
	var i: int = _seat_idx.get(seat, -1)
	_target_seat = seat if i >= 0 else -1
	for k in _panels.size():
		_panels[k].set_targeted(k == i)
	if i < 0:
		_has_reticle = false
		queue_redraw()
		return
	var dest := PANEL_RECTS[i].grow(RETICLE_OUT)
	if not _has_reticle or _reduce:
		_from = dest
		_glide = 1.0
	else:
		_from = reticle_rect()
		_glide = 0.0
	_to = dest
	_has_reticle = true
	queue_redraw()


func target_seat() -> int:
	return _target_seat


func has_reticle() -> bool:
	return _has_reticle


## Current (possibly gliding) reticle rect, Rect2() when there is no target.
func reticle_rect() -> Rect2:
	if not _has_reticle:
		return Rect2()
	var k := 1.0 - pow(1.0 - clampf(_glide, 0.0, 1.0), 3.0)  # cubic-out
	return Rect2(_from.position.lerp(_to.position, k), _from.size.lerp(_to.size, k))


## 12 x 16 caret at x 384..396, vertically centred on the reticle's panel.
func caret_rect() -> Rect2:
	if not _has_reticle:
		return Rect2()
	var cy := reticle_rect().get_center().y
	return Rect2(CARET_X, cy - CARET_H * 0.5, CARET_W, CARET_H)


func is_gliding() -> bool:
	return _has_reticle and _glide < 1.0


## Training: the drone's status line ("NEXT IN 3 BARS").
func set_drone_status(text: String) -> void:
	for p in _panels:
		if p.drone:
			p.set_drone_status(text)


## Song-time pump (countdown rings, sweep line).
func update(song_time: float) -> void:
	for p in _panels:
		p.update(song_time)


## Entrance: panels fade in and slide 16 px from the left, 60 ms stagger (Reduce: fade only).
func play_entrance() -> void:
	_enter_t = 0.0
	_apply_entrance()


func step(dt: float) -> void:
	if _glide < 1.0:
		_glide = minf(_glide + dt / Palette.DUR_FAST, 1.0)
		queue_redraw()
	if _enter_t >= 0.0:
		_enter_t += dt
		_apply_entrance()
	for p in _panels:
		p.step(dt)


func _apply_entrance() -> void:
	var done := true
	for i in _panels.size():
		var k := 1.0
		if _enter_t >= 0.0:
			k = clampf((_enter_t - ENTER_STAGGER * i) / Palette.DUR_BASE, 0.0, 1.0)
		if k < 1.0:
			done = false
		var e := 1.0 - pow(1.0 - k, 3.0)
		var slide := 0.0 if _reduce else -ENTER_SLIDE * (1.0 - e)
		_panels[i].position = PANEL_RECTS[i].position + Vector2(slide, 0.0)
		_panels[i].modulate.a = k
	if done:
		_enter_t = -1.0


func _process(delta: float) -> void:
	step(delta)


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	if _reduce and _glide < 1.0:
		_glide = 1.0
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"glide": not _reduce, "slide": not _reduce, "glow": not _low}


func keepout_shapes() -> Array[PackedVector2Array]:
	var xf := get_global_transform()
	var rects: Array[Rect2] = []
	for i in _panels.size():
		rects.append(Rect2(_panels[i].position, PeriscopePanel.SIZE))
	if _has_reticle:
		rects.append(reticle_rect())
		rects.append(caret_rect())
	var out: Array[PackedVector2Array] = []
	for r in rects:
		out.append(PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
			xf * Vector2(r.position.x, r.end.y)]))
	return out


func _draw() -> void:
	if not _has_reticle:
		return
	var r := reticle_rect()
	var c := Palette.SONAR_PALE
	var a := RETICLE_ARM
	var p := r.position
	var e := r.end
	for corner: Array in [
		[Vector2(p.x, p.y + a), p, Vector2(p.x + a, p.y)],
		[Vector2(e.x - a, p.y), Vector2(e.x, p.y), Vector2(e.x, p.y + a)],
		[Vector2(e.x, e.y - a), e, Vector2(e.x - a, e.y)],
		[Vector2(p.x + a, e.y), Vector2(p.x, e.y), Vector2(p.x, e.y - a)],
	]:
		draw_polyline(PackedVector2Array(corner), c, RETICLE_W, true)
	var cr := caret_rect()
	draw_colored_polygon(PackedVector2Array([
		Vector2(cr.position.x, cr.get_center().y), Vector2(cr.end.x, cr.position.y), cr.end]), c)
