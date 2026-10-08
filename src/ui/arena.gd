class_name Arena
extends Control
## Reactive neon abyss behind the board (D-08, D-09, D-13): depth glow, breathing trench walls,
## a bioluminescent crowd that tracks the combo, marine snow, a miss edge glitch and a static
## corner vignette. Everything is drawn in fixed 1920x1080 design coordinates; nothing here
## touches the lane region, and Low effects / reduce motion never change lane readability.

const W := 1920.0
const H := 1080.0
const BASE := Color("02040A")
const TEAL := Color("1E8CB4")
const VIOLET := Color("5A3CAA")
const GLITCH_RED := Color("FF4A3D")
const GLITCH_CYAN := Color("05D9E8")
const SNOW := Color(160.0 / 255.0, 230.0 / 255.0, 1.0)
const RINGS_FULL := 14
const RINGS_LOW := 6
const SNOW_FULL := 80
const SNOW_LOW := 24
const CROWD_FULL := 26
const CROWD_LOW := 13
const RING_PTS := 48
const WALL_SQUASH := 0.62
const WALL_SCROLL := 0.22
const GLOW_BASE_R := 840.0
const GLOW_PULSE_R := 72.0
const GLITCH_SEC := 0.12
const FAIL_DIM_SEC := 0.4
const RISE_TAU := 0.25
const FALL_TAU := 0.12
const EDGE_FADE_FROM := 880.0
const EDGE_FADE_TO := 1000.0

## 0..1 whole-arena alpha, driven by the intro (plan 04).
var reveal: float = 1.0

var _conductor: Conductor
var _tempo_map: Array = []
var _energy: float = 0.0
var _target: float = 0.0
var _t: float = 0.0
var _scroll: float = 0.0
var _glitch_left: float = 0.0
var _failed: bool = false
var _dim: float = 1.0
var _pulse: float = 0.0
var _unit_rings: Array[PackedVector2Array] = []
var _snow_pos := PackedVector2Array()
var _snow_z := PackedFloat32Array()
var _glow_tex: GradientTexture2D
var _vignette_tex: GradientTexture2D


static func energy_for(combo: int) -> float:
	if combo >= 100:
		return 1.0
	if combo >= 50:
		return 0.75
	if combo >= 10:
		return 0.5
	if combo >= 5:
		return 0.25
	return 0.0


static func ring_count(low: bool) -> int:
	return RINGS_LOW if low else RINGS_FULL


static func snow_count(low: bool) -> int:
	return SNOW_LOW if low else SNOW_FULL


static func crowd_max(low: bool) -> int:
	return CROWD_LOW if low else CROWD_FULL


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in RINGS_FULL:
		var pts := PackedVector2Array()
		pts.resize(RING_PTS + 1)
		for i in RING_PTS + 1:
			var a := TAU * float(i) / float(RING_PTS)
			var j := 1.0 + 0.08 * sin(7.0 * a + 1.7 * k) + 0.05 * sin(13.0 * a + k)
			pts[i] = Vector2(cos(a), sin(a)) * j
		_unit_rings.append(pts)
	_snow_pos.resize(SNOW_FULL)
	_snow_z.resize(SNOW_FULL)
	for i in SNOW_FULL:
		var z := fposmod(float(i) * 0.6180339, 1.0)
		_snow_z[i] = z
		_snow_pos[i] = Vector2(32.0 + fposmod(float(i) * 0.7548777, 1.0) * (W - 64.0),
			fposmod(float(i) * 0.5698403, 1.0) * H)
	_glow_tex = _radial([0.0, 0.35, 1.0], [Color("123A52"), Color(10.0 / 255.0, 20.0 / 255.0, 40.0 / 255.0, 0.6),
		Color(2.0 / 255.0, 4.0 / 255.0, 10.0 / 255.0, 0.0)], 0.5)
	_vignette_tex = _radial([0.0, 0.78, 1.0], [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35)],
		0.5 + 0.5 * sqrt(2.0))


static func _radial(offsets: Array, colors: Array, reach: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(reach, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Settings.settings_changed.is_connected(_on_settings_changed):
		Settings.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	if Settings.settings_changed.is_connected(_on_settings_changed):
		Settings.settings_changed.disconnect(_on_settings_changed)


func _on_settings_changed() -> void:
	if _calm():
		_glitch_left = 0.0
	queue_redraw()


func bind(conductor: Conductor, tempo_map: Array) -> void:
	_conductor = conductor
	_tempo_map = tempo_map


func _calm() -> bool:
	return Settings.low_effects or Settings.reduce_motion


func energy() -> float:
	return _energy


func glitch_active() -> bool:
	return _glitch_left > 0.0


## Number of crowd glows currently lit.
func visible_crowd() -> int:
	var n := 10 + int(round(16.0 * _energy))
	return mini(n, crowd_max(Settings.low_effects))


func on_combo(value: int) -> void:
	if _failed:
		return
	_target = energy_for(value)


func on_miss() -> void:
	_energy *= 0.4
	if not _calm():
		_glitch_left = GLITCH_SEC


func fail() -> void:
	_failed = true
	_energy = 0.0
	_target = 0.0
	_dim = 1.0
	_glitch_left = 0.0


func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Step the arena clock. Public so tests can drive time without a scene tree.
func advance(delta: float) -> void:
	_t += delta
	var rm := Settings.reduce_motion
	_scroll += delta * WALL_SCROLL * (0.25 if rm else 1.0)
	var tau := RISE_TAU if _target > _energy else FALL_TAU
	_energy = clampf(_energy + (_target - _energy) * (1.0 - exp(-delta / tau)), 0.0, 1.0)
	if _glitch_left > 0.0:
		_glitch_left = maxf(_glitch_left - delta, 0.0)
	if _failed:
		_dim = maxf(_dim - delta / FAIL_DIM_SEC * 0.5, 0.5)
	if not rm:
		var st := _conductor.song_time() if _conductor != null else _t
		_pulse = BeatClock.pulse(BeatClock.phase(st, _tempo_map))
		for i in SNOW_FULL:
			var z := _snow_z[i]
			var p := _snow_pos[i]
			p.y += (30.0 + 60.0 * z) * delta
			p.x += 12.0 * sin(_t + 10.0 * z) * delta
			if p.y > H:
				p.y -= H
			if p.x < 32.0:
				p.x += W - 64.0
			elif p.x > W - 32.0:
				p.x -= W - 64.0
			_snow_pos[i] = p
	else:
		_pulse = 0.0


func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(alpha, 0.0, 1.0) * reveal * _dim)


func _draw() -> void:
	var low := Settings.low_effects
	var glitch := clampf(_glitch_left / GLITCH_SEC, 0.0, 1.0)
	draw_rect(Rect2(0.0, 0.0, W, H), _a(BASE, 1.0))
	# Depth glow at the vanishing point.
	var gr := (GLOW_BASE_R + GLOW_PULSE_R * _pulse) * (1.0 - 0.1 * glitch)
	draw_texture_rect(_glow_tex, Rect2(Trench.VP.x - gr, Trench.VP.y - gr, gr * 2.0, gr * 2.0), false,
		Color(1, 1, 1, reveal * _dim))
	_draw_walls(ring_count(low))
	_draw_crowd(low)
	_draw_snow(snow_count(low))
	if glitch > 0.0:
		for x in [0.0, W - 24.0]:
			draw_rect(Rect2(x, 0.0, 24.0, H), _a(GLITCH_RED, 0.35 * glitch))
		draw_rect(Rect2(30.0, 0.0, 6.0, H), _a(GLITCH_CYAN, 0.25 * glitch))
		draw_rect(Rect2(W - 36.0, 0.0, 6.0, H), _a(GLITCH_CYAN, 0.25 * glitch))
	# Static corner vignette, always on, drawn last.
	draw_texture_rect(_vignette_tex, Rect2(0.0, 0.0, W, H), false, Color(1, 1, 1, reveal))


func _draw_walls(count: int) -> void:
	for k in count:
		var d := 1.0 - fposmod(float(k) / float(count) + _scroll, 1.0)
		var n := 1.0 - d
		var r := (72.0 + 1080.0 * n) * (1.0 + 0.035 * _pulse)
		var fade := clampf((EDGE_FADE_TO - r) / (EDGE_FADE_TO - EDGE_FADE_FROM), 0.0, 1.0)
		if fade <= 0.0:
			continue
		var lw := 1.2 + 3.6 * n
		var col := TEAL if k % 2 == 0 else VIOLET
		draw_set_transform(Trench.VP, 0.0, Vector2(r, r * WALL_SQUASH))
		draw_polyline(_unit_rings[k], _a(col, (0.08 + 0.35 * n) * fade), lw / r, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_crowd(low: bool) -> void:
	var lit := visible_crowd()
	var pulse := 0.0 if (low or Settings.reduce_motion) else _pulse
	var energy_alpha := 0.6 + 0.4 * _energy
	for i in CROWD_FULL:
		if (i * 7) % CROWD_FULL >= lit:
			continue
		var pos := Vector2(192.0 + 62.4 * i + 14.0 * sin(7.1 * i), 144.0 + 19.0 * sin(3.3 * i))
		var h := 7.2 + 4.8 * pulse * (1.0 + 0.5 * _energy)
		var col := Palette.lane_color(3) if i % 2 == 0 else Palette.lane_color(1)
		var alpha := (0.15 + pulse * 0.5 * (float(i % 3) / 2.0 + 0.3)) * energy_alpha
		draw_set_transform(pos, 0.0, Vector2(3.6, h))
		draw_circle(Vector2.ZERO, 1.8, _a(col, alpha * 0.35))
		draw_circle(Vector2.ZERO, 1.0, _a(col, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_snow(count: int) -> void:
	for i in count:
		var z := _snow_z[i]
		var s := 2.0 + 2.0 * z
		draw_rect(Rect2(_snow_pos[i], Vector2(s, s)), _a(SNOW, 0.08 + 0.25 * z))
