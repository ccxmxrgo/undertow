class_name Arena
extends Control
## The living trench behind the board (D-08, D-09, D-13; 02.2 UI-SPEC 7.7, AV-02): depth glow,
## breathing trench wall rings with layered rock band fills, bioluminescent colonies on the walls
## that pulse on the beat (stronger at higher streak tiers), a lantern-fish band that tracks the
## combo, marine snow, a rare distant creature, a miss edge glitch and a static corner vignette.
## Everything is drawn in fixed 1920x1080 design coordinates. Only the walls (and their band
## fills) pass behind the note path; colonies, fish, snow and the creature stay out of the
## expanded keep-out polygon (UI-SPEC 7.1). Low effects / reduce motion never change lanes.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const W := 1920.0
const H := 1080.0
const RINGS_FULL := 14
const RINGS_LOW := 6
const SNOW_FULL := 80
const SNOW_LOW := 24
const CROWD_FULL := 26
const CROWD_LOW := 13
const COLONIES_FULL := 36
const COLONIES_LOW := 12
const RING_PTS := 48
const HALF_PTS := RING_PTS / 2
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

## Note-path keep-out (UI-SPEC 7.1): the board trapezoid expanded by 48 px on every side.
const KEEP_OUT_PX := 48.0
const KEEP_OUT_NEAR_D := -0.043

## Band fills (7.7): ABYSS_600 between ring k and k+1 (spec alpha 0.03 + 0.05 n, raised below).
const BAND_MIN_PX := 1.5  # minimum band width where wavy rings would cross
## Visual review (02.2-11): at 0.03 + 0.05 n the bands were invisible on the abyss, so each band is
## a gradient: the lit rock lip at the nearer ring (0.06 + 0.16 n) fading to 30% toward the VP.
const BAND_LIP_BASE := 0.06
const BAND_LIP_N := 0.16
const BAND_INNER := 0.3
## Wall stroke glow (UI-SPEC 3.3 stroke glow, Full only): a wide faint stroke under each ring.
const WALL_GLOW_W := 6.0
const WALL_GLOW_A := 0.22

## Bio colonies (7.7): alpha 0.25 + 0.55 pulse x tier gain, radius 2 + 2 pulse.
const COLONY_ALPHA_BASE := 0.25
const COLONY_ALPHA_PULSE := 0.55
const COLONY_R_BASE := 2.0
const COLONY_R_PULSE := 2.0
const TIER_GAIN: Array[float] = [1.0, 1.1, 1.2, 1.3]
const COLONY_SPREAD := 11.0  # max dot offset from the cluster centre at depth scale 1
const COLONY_MARGIN := 18.0  # cluster extent (spread x max depth scale + dot radius)
const COLONY_FADE_PX := 40.0  # colonies fade in over this distance outside the keep-out
## Colony centres stay this far inside the screen (the outer 32 px band stays dark, D-06; the
## halo's bright core is ~25 px), fading over COLONY_FADE_PX.
const COLONY_EDGE_PX := 64.0
## Colonies also stay out of the cockpit console corners (UI-SPEC 7.2: x < 400 / x > 1520 below
## y 600, where the streak and depth readouts sit), with a 16 px margin, fading over COLONY_FADE_PX.
const CONSOLE_TOP := 584.0
const CONSOLE_LEFT_X := 416.0
const CONSOLE_RIGHT_X := 1504.0
## Colonies sit on wall vertices whose direction from the VP is at least this far from straight down,
## so they live on the side walls and the ceiling, not on the floor that holds the board.
const COLONY_MIN_ANGLE_DEG := 62.0
## Halo: glow_sm alpha; drawn at ~2x the glow_sm size (visual review: at 1.6 x the cluster the halo
## vanished into the dots and the walls did not read as bioluminescent).
const COLONY_GLOW_MUL := 1.6 * 2.2 * 2.0
## Halo floor so the walls still read as alive between beats (the dots keep the spec pulse).
const HALO_FLOOR := 0.5

## Lantern-fish band (7.7, 3.1 decoration exception): lane-1 / lane-3 hues at alpha <= 0.65.
const FISH_ALPHA_MAX := 0.65
const FISH_RX := 7.0
const FISH_RY := 3.0
const TIER4_MIN_ENERGY := 0.75
const FISH_X0 := 120.0
const FISH_X1 := 1800.0
const FISH_Y0 := 108.0
const FISH_Y1 := 192.0

## Distant creature (7.7).
const CREATURE_Y_MIN := 120.0
const CREATURE_Y_MAX := 340.0
const CREATURE_GAP_MIN := 45.0
const CREATURE_GAP_MAX := 75.0
const CREATURE_SPEED_MIN := 60.0
const CREATURE_SPEED_MAX := 120.0
## First crossing: one gap measured from 30 s before the song start (so it lands at 15..45 s).
const CREATURE_FIRST_ORIGIN := -30.0
const CREATURE_HORIZON := 1500.0  # schedule length, seconds
const CREATURE_BOB := 6.0
const CREATURE_ALPHA := 0.5
const CREATURE_RIM_ALPHA := 0.10
const LEVIATHAN := 0
const JELLYFISH := 1
const LEVIATHAN_SIZE := Vector2(420.0, 120.0)
const JELLY_SIZE := Vector2(90.0, 140.0)
const JELLY_TENDRILS := 5
const JELLY_TENDRIL_PTS := 8
const LEVIATHAN_LIGHTS := 7
const CREATURE_LIGHT_A := 0.35
const JELLY_GLOW_A := 0.16

## 0..1 whole-arena alpha, driven by the intro (plan 04).
var reveal: float = 1.0
## False until the conductor lead-in starts: the idle clock reads song_time 0, which would pin
## the beat pulse at maximum for the whole pre-count (WR-03). Gameplay flips it on.
var beat_live: bool = true
## Menu mode (Song Select): no Conductor, no crowd, no creature, no miss glitch, walls at x0.25.
## Set before adding to the tree.
var menu_mode: bool = false
## Seed of the creature schedule (the chart id; bind() sets it).
var creature_key: String = ""

var _conductor: Conductor
var _tempo_map: Array = []
var _energy: float = 0.0
var _target: float = 0.0
var _t: float = 0.0
var _song_t: float = 0.0
var _scroll: float = 0.0
var _glitch_left: float = 0.0
var _failed: bool = false
var _dim: float = 1.0
## Motion pulse (wall breathing, VP glow, fish height): 0 under reduce motion.
var _pulse: float = 0.0
## Raw beat pulse (colony brightness): kept under reduce motion.
var _beat: float = 0.0
var _tier: int = 1
var _low: bool = false
var _reduce: bool = false
var _unit_rings: Array[PackedVector2Array] = []
var _snow_pos := PackedVector2Array()
var _snow_z := PackedFloat32Array()
var _glow_tex: GradientTexture2D
var _vignette_tex: GradientTexture2D
var _dot_tex: GradientTexture2D
var _glow_layer: Node2D

# Wall state per frame (filled by _update_rings, read by walls, bands and colonies).
var _ring_r := PackedFloat32Array()
var _ring_n := PackedFloat32Array()
var _ring_fade := PackedFloat32Array()
var _band_pts := PackedVector2Array()
var _band_cols := PackedColorArray()

# Colonies: static layout plus per-frame screen state.
var _colony_vertex := PackedInt32Array()
var _colony_dot_count := PackedInt32Array()
var _colony_offsets: Array[PackedVector2Array] = []
var _colony_center := PackedVector2Array()
var _colony_scale := PackedFloat32Array()
var _colony_vis := PackedFloat32Array()  # 0 = hidden, else fade 0..1

# Creature.
var _schedule: Array[Dictionary] = []
var _cr_active: bool = false
var _cr_kind: int = LEVIATHAN
var _cr_pos := Vector2.ZERO
var _cr_dir: float = 1.0
var _leviathan := PackedVector2Array()
var _leviathan_rim := PackedVector2Array()
var _jelly_bell := PackedVector2Array()
var _jelly_rim := PackedVector2Array()
var _tendril := PackedVector2Array()
var _fish_tail := PackedVector2Array([Vector2(-0.9, 0.0), Vector2(-1.85, -0.85), Vector2(-1.85, 0.85)])

static var _keep_out_cache := PackedVector2Array()
static var _edge_p := PackedVector2Array()
static var _edge_n := PackedVector2Array()


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


static func colony_count(low: bool) -> int:
	return COLONIES_LOW if low else COLONIES_FULL


static func band_count(low: bool) -> int:
	return 0 if low else RINGS_FULL - 1


static func tier_gain_for(tier: int) -> float:
	return TIER_GAIN[clampi(tier, 1, TIER_GAIN.size()) - 1]


## Colony alpha (UI-SPEC 7.7): 0.25 + 0.55 x pulse x tier gain (1.0 / 1.1 / 1.2 / 1.3).
static func colony_alpha(pulse: float, tier: int) -> float:
	return COLONY_ALPHA_BASE + COLONY_ALPHA_PULSE * pulse * tier_gain_for(tier)


## Colony dot radius: 2 + 2 x pulse px; constant 2 under reduce motion (brightness pulse only).
static func colony_radius(pulse: float, reduce: bool) -> float:
	return COLONY_R_BASE if reduce else COLONY_R_BASE + COLONY_R_PULSE * pulse


## The note path (UI-SPEC 7.1) built from Trench.point(+-2, d) at d = 1.0 and d = -0.043,
## expanded by 48 px (mitred). Cached.
static func note_path_polygon() -> PackedVector2Array:
	if _keep_out_cache.is_empty():
		var base := PackedVector2Array([Trench.point(-2.0, 1.0), Trench.point(2.0, 1.0),
			Trench.point(2.0, KEEP_OUT_NEAR_D), Trench.point(-2.0, KEEP_OUT_NEAR_D)])
		var grown := Geometry2D.offset_polygon(base, KEEP_OUT_PX, Geometry2D.JOIN_MITER)
		_keep_out_cache = grown[0] if not grown.is_empty() else base
	return _keep_out_cache


## Largest signed distance of p outside the four edges of the unexpanded board trapezoid. For a
## convex polygon this is < 48 exactly when p is inside the mitred 48 px expansion (allocation free).
static func path_clearance(p: Vector2) -> float:
	if _edge_n.is_empty():
		var tl := Trench.point(-2.0, 1.0)
		var tr := Trench.point(2.0, 1.0)
		var br := Trench.point(2.0, KEEP_OUT_NEAR_D)
		var bl := Trench.point(-2.0, KEEP_OUT_NEAR_D)
		_edge_p = PackedVector2Array([tl, bl, tl, br])
		# Outward normals: top (up), bottom (down), left edge (left/up), right edge (right/up).
		_edge_n = PackedVector2Array([Vector2.UP, Vector2.DOWN, (tl - bl).orthogonal().normalized(),
			(br - tr).orthogonal().normalized()])
	var d := -INF
	for i in 4:
		d = maxf(d, (p - _edge_p[i]).dot(_edge_n[i]))
	return d - KEEP_OUT_PX


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
	_ring_r.resize(RINGS_FULL)
	_ring_n.resize(RINGS_FULL)
	_ring_fade.resize(RINGS_FULL)
	_band_pts.resize(2 * (HALF_PTS + 1))
	_band_cols.resize(2 * (HALF_PTS + 1))
	_snow_pos.resize(SNOW_FULL)
	_snow_z.resize(SNOW_FULL)
	for i in SNOW_FULL:
		var z := fposmod(float(i) * 0.6180339, 1.0)
		_snow_z[i] = z
		_snow_pos[i] = Vector2(32.0 + fposmod(float(i) * 0.7548777, 1.0) * (W - 64.0),
			fposmod(float(i) * 0.5698403, 1.0) * H)
	_glow_tex = _radial([0.0, 0.35, 1.0], [Palette.VP_GLOW, Color(Palette.VP_GLOW_MID, 0.6),
		Color(Palette.ABYSS_900, 0.0)], 1.0)
	var clear := Color(Palette.SHADOW, 0.0)
	_vignette_tex = _radial([0.0, 0.78, 1.0], [clear, clear, Palette.SHADOW], 0.5 + 0.5 * sqrt(2.0))
	_dot_tex = UiKit.glow_texture()
	_build_colonies()
	_build_creature_shapes()
	_glow_layer = Node2D.new()
	_glow_layer.name = "TrenchGlow"
	_glow_layer.material = UiKit.additive_material()
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)
	_build_schedule()
	apply_effect_settings()
	_update_rings()
	_update_colonies()


## `reach` is fill_to.x in UV: 1.0 puts the last stop at the texture edge (radius = half width).
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


func _build_colonies() -> void:
	# Allowed wall vertices: direction from the VP at least COLONY_MIN_ANGLE_DEG from straight down.
	var allowed: Array[int] = []
	var min_a := deg_to_rad(COLONY_MIN_ANGLE_DEG)
	for i in RING_PTS:
		var a := TAU * float(i) / float(RING_PTS)
		var dir := Vector2(cos(a), sin(a) * WALL_SQUASH)
		if dir.y <= 0.0 or atan2(absf(dir.x), dir.y) >= min_a:
			allowed.append(i)
	for c in COLONIES_FULL:
		var k := c % RINGS_FULL
		# Golden-ratio walk over the allowed vertices, offset per ring: deterministic, well spread.
		var idx := int(floor(fposmod(float(c) * 0.6180339 + float(k) * 0.1372, 1.0) * allowed.size()))
		_colony_vertex.append(allowed[idx])
		var n := 3 + (c * 5 + k) % 3
		_colony_dot_count.append(n)
		var offs := PackedVector2Array()
		for j in n:
			if j == 0:
				offs.append(Vector2.ZERO)
				continue
			var ang := float(c) * 2.4 + float(j) * 2.1
			var rad := COLONY_SPREAD * (0.45 + 0.55 * fposmod(float(c * 3 + j) * 0.618, 1.0))
			offs.append(Vector2(cos(ang), sin(ang)) * rad)
		_colony_offsets.append(offs)
	_colony_center.resize(COLONIES_FULL)
	_colony_scale.resize(COLONIES_FULL)
	_colony_vis.resize(COLONIES_FULL)


func _build_creature_shapes() -> void:
	# Leviathan, facing +x, 420 x 120 around the origin.
	var lev: Array[Vector2] = [Vector2(210, 4), Vector2(198, -20), Vector2(170, -38), Vector2(120, -52),
		Vector2(50, -60), Vector2(-30, -54), Vector2(-100, -38), Vector2(-150, -22), Vector2(-180, -12),
		Vector2(-205, -48), Vector2(-210, -40), Vector2(-196, -2), Vector2(-210, 40), Vector2(-204, 46),
		Vector2(-180, 12), Vector2(-150, 20), Vector2(-100, 30), Vector2(-40, 42), Vector2(10, 46),
		Vector2(30, 60), Vector2(48, 58), Vector2(50, 44), Vector2(100, 38), Vector2(150, 30),
		Vector2(185, 20), Vector2(205, 12)]
	_leviathan = PackedVector2Array(lev)
	_leviathan_rim = PackedVector2Array(lev)
	_leviathan_rim.append(lev[0])
	# Jellyfish bell: top half-ellipse 90 x 52 (y -70..-18) with a scalloped rim.
	var bell := PackedVector2Array()
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		bell.append(Vector2(cos(a) * 45.0, -18.0 + sin(a) * 52.0))
	for i in range(1, 8):
		var x := 45.0 - 90.0 * float(i) / 8.0
		bell.append(Vector2(x, -18.0 + (6.0 if i % 2 == 1 else 0.0)))
	_jelly_bell = bell
	_jelly_rim = bell.duplicate()
	_jelly_rim.append(bell[0])
	_tendril.resize(JELLY_TENDRIL_PTS)


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


## Effect contract (UI-SPEC 11): re-read Low effects / Reduce motion and reconfigure in place.
func apply_effect_settings() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	if _calm():
		_glitch_left = 0.0
	if _glow_layer != null:
		_glow_layer.visible = not _low
		_glow_layer.queue_redraw()
	queue_redraw()


func effect_counts() -> Dictionary:
	var creature_on := not (_low or _reduce or menu_mode)
	return {
		"rings": ring_count(_low),
		"band_fills": band_count(_low),
		"colonies": colony_count(_low),
		"colony_glow": not _low,
		"colony_radius_pulse": not _reduce,
		"fish": 0 if menu_mode else crowd_max(_low),
		"snow": snow_count(_low),
		"snow_frozen": _reduce,
		"creature": creature_on,
	}


func glow_layer() -> Node2D:
	return _glow_layer


## `key` seeds the distant creature (the chart id).
func bind(conductor: Conductor, tempo_map: Array, key: String = "") -> void:
	_conductor = conductor
	_tempo_map = tempo_map
	if key != creature_key or _schedule.is_empty():
		creature_key = key
		_build_schedule()


## Streak tier 1..4 = the score multiplier (Gameplay connects HullScore.multiplier_changed).
func set_tier(m: int) -> void:
	_tier = clampi(m, 1, TIER_GAIN.size())


func tier() -> int:
	return _tier


func tier_gain() -> float:
	return tier_gain_for(_tier)


func _calm() -> bool:
	return Settings.low_effects or Settings.reduce_motion


## Fish energy; at tier 4 (MAX) it is held at 0.75 or more (UI-SPEC 7.6).
func energy() -> float:
	if _tier >= 4 and not _failed:
		return maxf(_energy, TIER4_MIN_ENERGY)
	return _energy


func glitch_active() -> bool:
	return _glitch_left > 0.0


func beat_pulse() -> float:
	return _beat


func motion_pulse() -> float:
	return _pulse


## Number of lantern fish currently lit.
func visible_crowd() -> int:
	var n := 10 + int(round(16.0 * energy()))
	return mini(n, crowd_max(Settings.low_effects))


func on_combo(value: int) -> void:
	if _failed:
		return
	_target = energy_for(value)


func on_miss() -> void:
	_energy *= 0.4
	if not _calm() and not menu_mode:
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
	if _glow_layer.visible:
		_glow_layer.queue_redraw()


## Step the arena clock. Public so tests can drive time without a scene tree.
func advance(delta: float) -> void:
	_t += delta
	var rm := Settings.reduce_motion
	_scroll += delta * WALL_SCROLL * (0.25 if (rm or menu_mode) else 1.0)
	var tau := RISE_TAU if _target > _energy else FALL_TAU
	_energy = clampf(_energy + (_target - _energy) * (1.0 - exp(-delta / tau)), 0.0, 1.0)
	if _glitch_left > 0.0:
		_glitch_left = maxf(_glitch_left - delta, 0.0)
	if _failed:
		_dim = maxf(_dim - delta / FAIL_DIM_SEC * 0.5, 0.5)
	_song_t = _conductor.song_time() if _conductor != null else _t
	_beat = BeatClock.pulse(BeatClock.phase(_song_t, _tempo_map)) if beat_live else 0.0
	if not rm:
		_pulse = _beat
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
	_update_rings()
	_update_colonies()
	_update_creature(_song_t)


## Test hook: put the wall scroll at a known phase and refresh the derived state.
func set_scroll(s: float) -> void:
	_scroll = s
	_update_rings()
	_update_colonies()


# ---- Walls -------------------------------------------------------------------------------

func _update_rings() -> void:
	var count := ring_count(_low)
	for k in count:
		var d := 1.0 - fposmod(float(k) / float(count) + _scroll, 1.0)
		var n := 1.0 - d
		var r := (72.0 + 1080.0 * n) * (1.0 + 0.035 * _pulse)
		_ring_r[k] = r
		_ring_n[k] = n
		_ring_fade[k] = clampf((EDGE_FADE_TO - r) / (EDGE_FADE_TO - EDGE_FADE_FROM), 0.0, 1.0)


func _ring_point(k: int, i: int) -> Vector2:
	var u := _unit_rings[k][i]
	var r := _ring_r[k]
	return Trench.VP + Vector2(u.x * r, u.y * r * WALL_SQUASH)


# ---- Colonies ----------------------------------------------------------------------------

func colony_ring(c: int) -> int:
	return c % ring_count(_low)


func _update_colonies() -> void:
	var count := colony_count(_low)
	for c in COLONIES_FULL:
		_colony_vis[c] = 0.0
		if c >= count:
			continue
		var k := colony_ring(c)
		var fade := _ring_fade[k]
		if fade <= 0.0:
			continue
		var p := _ring_point(k, _colony_vertex[c])
		var edge := minf(minf(p.x, W - p.x), minf(p.y, H - p.y)) - COLONY_EDGE_PX
		if edge <= 0.0:
			continue
		var console := minf(maxf(p.x - CONSOLE_LEFT_X, CONSOLE_TOP - p.y),
			maxf(CONSOLE_RIGHT_X - p.x, CONSOLE_TOP - p.y)) - COLONY_MARGIN
		if console <= 0.0:
			continue
		edge = minf(edge, console)
		var clear := path_clearance(p) - COLONY_MARGIN
		if clear <= 0.0:
			continue
		_colony_center[c] = p
		_colony_scale[c] = 0.7 + 0.6 * _ring_n[k]
		_colony_vis[c] = fade * clampf(clear / COLONY_FADE_PX, 0.0, 1.0) * clampf(edge / COLONY_FADE_PX, 0.0, 1.0)


## Screen positions of every colony dot drawn this frame (tests: keep-out and determinism).
func colony_dots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in COLONIES_FULL:
		if _colony_vis[c] <= 0.0:
			continue
		var offs := _colony_offsets[c]
		for j in _colony_dot_count[c]:
			out.append(_colony_center[c] + offs[j] * _colony_scale[c])
	return out


# ---- Creature ----------------------------------------------------------------------------

func _build_schedule() -> void:
	_schedule.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = creature_key.hash()
	var t := CREATURE_FIRST_ORIGIN
	while true:
		t += rng.randf_range(CREATURE_GAP_MIN, CREATURE_GAP_MAX)
		if t > CREATURE_HORIZON:
			break
		var kind := LEVIATHAN if rng.randf() < 0.5 else JELLYFISH
		var half_h := (LEVIATHAN_SIZE.y if kind == LEVIATHAN else JELLY_SIZE.y) * 0.5 + CREATURE_BOB
		_schedule.append({
			"start": t,
			"kind": kind,
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"y": rng.randf_range(CREATURE_Y_MIN + half_h, CREATURE_Y_MAX - half_h),
			"speed": rng.randf_range(CREATURE_SPEED_MIN, CREATURE_SPEED_MAX),
			"phase": rng.randf() * TAU,
		})


func creature_schedule() -> Array[Dictionary]:
	return _schedule


static func _creature_size(kind: int) -> Vector2:
	return LEVIATHAN_SIZE if kind == LEVIATHAN else JELLY_SIZE


## Bounding box of the creature at song time t (empty Rect2 when none is crossing).
func creature_rect(t: float) -> Rect2:
	var e := _creature_at(t)
	if e.is_empty():
		return Rect2()
	var sz := _creature_size(int(e["kind"]))
	var pos := _creature_pos(e, t)
	return Rect2(pos - sz * 0.5, sz)


func _creature_at(t: float) -> Dictionary:
	for e in _schedule:
		var st: float = e["start"]
		if t < st:
			return {}
		var sz := _creature_size(int(e["kind"]))
		var dist := W + sz.x + 80.0
		if t < st + dist / float(e["speed"]):
			return e
	return {}


func _creature_pos(e: Dictionary, t: float) -> Vector2:
	var sz := _creature_size(int(e["kind"]))
	var travelled := (t - float(e["start"])) * float(e["speed"])
	var x0 := -sz.x * 0.5 - 40.0
	var x := x0 + travelled
	if float(e["dir"]) < 0.0:
		x = W - x
	var y := float(e["y"]) + CREATURE_BOB * sin(t * 0.6 + float(e["phase"]))
	return Vector2(x, y)


func _update_creature(t: float) -> void:
	_cr_active = false
	if _low or _reduce or menu_mode:
		return
	var e := _creature_at(t)
	if e.is_empty():
		return
	_cr_active = true
	_cr_kind = int(e["kind"])
	_cr_dir = float(e["dir"])
	_cr_pos = _creature_pos(e, t)


## Screen position of photophore i on the leviathan (same layout as _draw_creature).
func _leviathan_light(i: int) -> Vector2:
	var f := float(i) / float(LEVIATHAN_LIGHTS - 1)
	var lp := Vector2(150.0 - 290.0 * f, 14.0 + 10.0 * sin(f * PI))
	return _cr_pos + Vector2(lp.x * _cr_dir, lp.y)


func creature_active() -> bool:
	return _cr_active


# ---- Drawing -----------------------------------------------------------------------------

func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(alpha, 0.0, 1.0) * reveal * _dim)


func _draw() -> void:
	var low := _low
	var glitch := clampf(_glitch_left / GLITCH_SEC, 0.0, 1.0)
	draw_rect(Rect2(0.0, 0.0, W, H), _a(Palette.ABYSS_900, 1.0))
	# Depth glow at the vanishing point.
	var gr := (GLOW_BASE_R + GLOW_PULSE_R * _pulse) * (1.0 - 0.1 * glitch)
	draw_texture_rect(_glow_tex, Rect2(Trench.VP.x - gr, Trench.VP.y - gr, gr * 2.0, gr * 2.0), false,
		Color(Palette.WHITE, reveal * _dim))
	if _cr_active:
		_draw_creature()
	if not low:
		_draw_bands()
	_draw_walls(ring_count(low))
	_draw_colonies()
	if not menu_mode:
		_draw_fish(low)
	_draw_snow(snow_count(low))
	if glitch > 0.0:
		for x in [0.0, W - 24.0]:
			draw_rect(Rect2(x, 0.0, 24.0, H), _a(Palette.WARNING_RED, 0.35 * glitch))
		draw_rect(Rect2(30.0, 0.0, 6.0, H), _a(Palette.SONAR, 0.25 * glitch))
		draw_rect(Rect2(W - 36.0, 0.0, 6.0, H), _a(Palette.SONAR, 0.25 * glitch))
	# Static corner vignette, always on, drawn last.
	draw_texture_rect(_vignette_tex, Rect2(0.0, 0.0, W, H), false, Color(Palette.WHITE, reveal))


func _draw_walls(count: int) -> void:
	for k in count:
		var fade := _ring_fade[k]
		if fade <= 0.0:
			continue
		var n := _ring_n[k]
		var r := _ring_r[k]
		var lw := 1.2 + 3.6 * n
		var col := Palette.WALL_TEAL if k % 2 == 0 else Palette.WALL_VIOLET
		var line_a := (0.08 + 0.35 * n) * fade
		draw_set_transform(Trench.VP, 0.0, Vector2(r, r * WALL_SQUASH))
		if not _low and not menu_mode:  # Song Select keeps its 01.2 walls (outer band stays dark)
			draw_polyline(_unit_rings[k], _a(col, line_a * WALL_GLOW_A), (lw + WALL_GLOW_W * (0.4 + n)) / r, false)
		draw_polyline(_unit_rings[k], _a(col, line_a), lw / r, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Layered rock: a filled band between each ring and the next nearer one (two simple half-annulus
## polygons per band). The pair that wraps (next ring is the far one) has no band: 13 of 14.
func _draw_bands() -> void:
	var count := RINGS_FULL
	for k in count:
		var j := (k + 1) % count
		if _ring_r[j] <= _ring_r[k]:
			continue
		var fade := _ring_fade[k]
		if fade <= 0.0:
			continue
		var lip := _a(Palette.ABYSS_600, band_alpha(_ring_n[j]) * fade)
		var deep := Color(lip, lip.a * BAND_INNER)
		for i in HALF_PTS + 1:
			_band_cols[i] = lip
			_band_cols[2 * HALF_PTS + 1 - i] = deep
		for half in 2:
			_fill_band(k, j, half)
			draw_polygon(_band_pts, _band_cols)


## Alpha of a band's lit lip at the nearer ring's depth n (see BAND_LIP_*).
static func band_alpha(n: float) -> float:
	return BAND_LIP_BASE + BAND_LIP_N * n


## Half band k (inner ring) -> j (outer ring) into _band_pts. Both edges follow their wavy wall
## ring; where the inner wall bulges past the outer one (large rings) the inner edge is pulled in
## along the same ray, so the polygon stays simple (star-shaped from the VP) and triangulates.
func _fill_band(k: int, j: int, half: int) -> void:
	var i0 := half * HALF_PTS
	var rk := _ring_r[k]
	var rj := _ring_r[j]
	var sq := Vector2(1.0, WALL_SQUASH)
	for i in HALF_PTS + 1:
		var uk := _unit_rings[k][i0 + i]
		var uj := _unit_rings[j][i0 + i]
		var outer_len := rj * uj.length()
		var inner_len := minf(rk * uk.length(), outer_len - BAND_MIN_PX)
		var dir := uk.normalized()
		_band_pts[i] = Trench.VP + dir * outer_len * sq
		_band_pts[2 * HALF_PTS + 1 - i] = Trench.VP + dir * inner_len * sq


## Test hook: every band polygon drawn at the current scroll (copies).
func band_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if _low:
		return out
	for k in RINGS_FULL:
		var j := (k + 1) % RINGS_FULL
		if _ring_r[j] <= _ring_r[k] or _ring_fade[k] <= 0.0:
			continue
		for half in 2:
			_fill_band(k, j, half)
			out.append(_band_pts.duplicate())
	return out


func _draw_colonies() -> void:
	var alpha := colony_alpha(_beat, _tier)
	var rad := colony_radius(_beat, _reduce)
	for c in COLONIES_FULL:
		var vis := _colony_vis[c]
		if vis <= 0.0:
			continue
		var col := Palette.SONAR if c % 2 == 0 else Palette.BIO_VIOLET
		var s := _colony_scale[c]
		var offs := _colony_offsets[c]
		var ctr := _colony_center[c]
		for j in _colony_dot_count[c]:
			var dot_r := rad * s * (1.0 - 0.18 * float(j))
			draw_circle(ctr + offs[j] * s, dot_r, _a(col, alpha * vis * (1.0 - 0.12 * float(j))))


## Lantern fish: a loose school of small elongated glows swimming at y 100..200 (crowd energy
## logic). Lane-1 / lane-3 hues (cyan, pink) at alpha <= 0.65 (UI-SPEC 3.1 decoration exception).
func _draw_fish(low: bool) -> void:
	var lit := visible_crowd()
	var pulse := 0.0 if low else _pulse
	var e := energy()
	var energy_alpha := 0.6 + 0.4 * e
	for i in CROWD_FULL:
		if (i * 7) % CROWD_FULL >= lit:
			continue
		var pos := _fish_pos(i)
		var edge := _fish_edge_fade(pos.x)
		if edge <= 0.0:
			continue
		var face := _fish_face(i)
		var size := _fish_size(i)
		var sc := size * (1.0 + 0.35 * pulse * (1.0 + 0.5 * e))
		var col := _fish_color(i)
		var alpha := minf((0.3 + pulse * 0.5 * (float(i % 3) / 2.0 + 0.3)) * energy_alpha, FISH_ALPHA_MAX) * edge
		draw_set_transform(pos, 0.0, Vector2(FISH_RX * sc * face, FISH_RY * sc))
		draw_circle(Vector2.ZERO, 1.0, _a(col, alpha * 0.8))
		draw_colored_polygon(_fish_tail, _a(col, alpha * 0.45))
		draw_circle(Vector2(0.45, -0.1), 0.32, _a(Palette.SONAR_PALE, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fish_color(i: int) -> Color:
	return Palette.lane_color(0) if i % 2 == 0 else Palette.lane_color(2)


func _fish_face(i: int) -> float:
	return -1.0 if i % 3 == 0 else 1.0


func _fish_size(i: int) -> float:
	return 0.75 + 0.5 * fposmod(float(i) * 0.4142, 1.0)


## School layout: fish swim slowly in their facing direction across x 120..1800 and wrap; each
## fades out over the last 80 px of the span so the wrap never pops. Static under reduce motion.
func _fish_pos(i: int) -> Vector2:
	var span := FISH_X1 - FISH_X0
	var x0 := FISH_X0 + fposmod(float(i) * 0.6180339 + 0.05 * sin(7.1 * i), 1.0) * span
	var y := FISH_Y0 + (FISH_Y1 - FISH_Y0) * fposmod(float(i) * 0.3819660 + 0.11 * sin(3.3 * i), 1.0)
	if _reduce:
		return Vector2(x0, y)
	var speed := 6.0 + 10.0 * fposmod(float(i) * 0.7548777, 1.0)
	var x := FISH_X0 + fposmod(x0 - FISH_X0 + _fish_face(i) * speed * _t, span)
	return Vector2(x, y + 5.0 * sin(0.8 * _t + 2.1 * i))


func _fish_edge_fade(x: float) -> float:
	return clampf(minf(x - FISH_X0, FISH_X1 - x) / 80.0, 0.0, 1.0)


func _draw_snow(count: int) -> void:
	for i in count:
		var p := _snow_pos[i]
		if path_clearance(p) < 0.0:
			continue
		var z := _snow_z[i]
		var s := 2.0 + 2.0 * z
		draw_rect(Rect2(p, Vector2(s, s)), _a(Palette.MARINE_SNOW, 0.08 + 0.25 * z))


func _draw_creature() -> void:
	var fill := _a(Palette.ABYSS_800, CREATURE_ALPHA)
	var rim := _a(Palette.SONAR, CREATURE_RIM_ALPHA)
	if _cr_kind == LEVIATHAN:
		draw_set_transform(_cr_pos, 0.0, Vector2(_cr_dir, 1.0))
		draw_colored_polygon(_leviathan, fill)
		draw_polyline(_leviathan_rim, rim, 1.0, true)
		# A faint row of photophores along the flank (visual review: alive, still distant).
		for i in LEVIATHAN_LIGHTS:
			var f := float(i) / float(LEVIATHAN_LIGHTS - 1)
			var lp := Vector2(150.0 - 290.0 * f, 14.0 + 10.0 * sin(f * PI))  # local (see _leviathan_light)
			var tw := 0.5 + 0.5 * sin(_t * 1.3 + float(i) * 0.9)
			draw_circle(lp, 2.0, _a(Palette.SONAR_PALE, CREATURE_LIGHT_A * (0.5 + 0.5 * tw)))
	else:
		var squeeze := 1.0 + 0.06 * sin(_t * 2.2)
		draw_set_transform(_cr_pos, 0.0, Vector2(squeeze, 2.0 - squeeze))
		draw_colored_polygon(_jelly_bell, fill)
		draw_polyline(_jelly_rim, rim, 1.0, true)
		draw_set_transform(_cr_pos, 0.0, Vector2.ONE)
		for t in JELLY_TENDRILS:
			var x0 := -32.0 + 16.0 * float(t)
			for i in JELLY_TENDRIL_PTS:
				var f := float(i) / float(JELLY_TENDRIL_PTS - 1)
				_tendril[i] = Vector2(x0 + 6.0 * f * sin(_t * 1.7 + float(t) * 1.3 + f * 4.0) - _cr_dir * 10.0 * f,
					-16.0 + 84.0 * f)
			draw_polyline(_tendril, _a(Palette.SONAR, CREATURE_RIM_ALPHA * 0.8), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Additive glows (TrenchGlow child, one material switch): colony halos (glow_sm) and fish glows.
## Full effects only (the layer is hidden in Low).
func _draw_glow() -> void:
	var gl := _glow_layer
	var alpha := colony_alpha(_beat, _tier)
	var glow_a: float = Palette.GLOW_SM[1]
	for c in COLONIES_FULL:
		var vis := _colony_vis[c]
		if vis <= 0.0:
			continue
		var col := Palette.SONAR if c % 2 == 0 else Palette.BIO_VIOLET
		var sz := COLONY_SPREAD * COLONY_GLOW_MUL * _colony_scale[c] * (1.0 + 0.25 * _pulse)
		gl.draw_texture_rect(_dot_tex, Rect2(_colony_center[c] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false,
			_a(col, glow_a * maxf(alpha, HALO_FLOOR) * vis))
	if _cr_active and _cr_kind == LEVIATHAN:
		for i in LEVIATHAN_LIGHTS:
			var lp := _leviathan_light(i)
			var tw := 0.5 + 0.5 * sin(_t * 1.3 + float(i) * 0.9)
			gl.draw_texture_rect(_dot_tex, Rect2(lp - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), false,
				_a(Palette.SONAR, CREATURE_LIGHT_A * 0.6 * (0.5 + 0.5 * tw)))
	if _cr_active and _cr_kind == JELLYFISH:
		var jg := Vector2(150.0, 130.0) * (1.0 + 0.08 * sin(_t * 2.2))
		gl.draw_texture_rect(_dot_tex, Rect2(_cr_pos + Vector2(0.0, -40.0) - jg * 0.5, jg), false,
			_a(Palette.BIO_VIOLET, JELLY_GLOW_A))
	if menu_mode:
		return
	var lit := visible_crowd()
	var e := energy()
	for i in CROWD_FULL:
		if (i * 7) % CROWD_FULL >= lit:
			continue
		var fp := _fish_pos(i)
		var edge := _fish_edge_fade(fp.x)
		if edge <= 0.0:
			continue
		var size := Vector2(46.0, 18.0) * _fish_size(i) * (1.0 + 0.3 * _pulse)
		gl.draw_texture_rect(_dot_tex, Rect2(fp - size * 0.5, size), false,
			_a(_fish_color(i), glow_a * (0.5 + 0.5 * e) * (0.6 + 0.4 * _pulse) * edge))
