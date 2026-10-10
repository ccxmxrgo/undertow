class_name AbyssBackdrop
extends Control
## The living abyss behind the menus (02.2 UI-SPEC 5, 6, 8, 11). Variants:
##   "title": the main menu scene, layers L0..L8 (gradient, light shafts, far ridge, kelp,
##            submarine with searchlight, near rocks, marine snow, bio specks, vignette).
##   "table": song select / settings / calibration. Same scene without the submarine, with
##            every layer above the gradient at 60% alpha.
##   "calm":  results. Static gradient + 40 marine snow + vignette only.
## Set `variant` before adding the node to the tree. Everything is drawn in fixed 1920x1080
## design coordinates; all colours come from Palette (VIS-01).
##
## Draw order. Godot draws a node's children after the node itself unless the child sets
## show_behind_parent, so the layers are split across three canvases:
##   1. child "Gradient"    (show_behind_parent): L0 gradient + surface glow.
##   2. child "Shafts"      (show_behind_parent, additive): L1 light shafts and the faint halo
##                          behind the submarine. Above the gradient, behind everything else.
##   3. this node itself:   L2 ridge, L3 kelp, L4 submarine, L5 near rocks, L6 snow,
##                          L7 bio specks, L8 vignette.
##   4. child "Searchlight" (normal order, additive): the searchlight cone and porthole glows,
##                          on top of the scene.
## Geometry (ridge, rocks, submarine, shaft quads, cone triangles) is built once; per frame
## only transforms and a reused kelp scratch buffer change.
##
## Effect node (UiKit contract): Low effects = 3 static shafts, static ridge/rocks/kelp drift,
## 5 kelp strands (sway kept), 30 snow + 10 specks (160 -> 40 particles, -75%), searchlight
## cone without additive glow, no soft glows. Reduce motion = every drift, sway, bob and
## particle frozen; only the speck brightness pulse keeps running.

const W := 1920.0
const H := 1080.0

const SNOW_FULL := 120
const SNOW_LOW := 30
const SPECKS_FULL := 40
const SPECKS_LOW := 10
const SHAFTS_FULL := 5
const SHAFTS_LOW := 3
const KELP_FULL := 9
const KELP_LOW := 5
const CALM_SNOW_FULL := 40
const CALM_SNOW_LOW := 12
const TABLE_ALPHA := 0.6

## L1 light shafts.
const SHAFT_X: Array[float] = [980.0, 1150.0, 1320.0, 1490.0, 1660.0]
const SHAFT_W: Array[float] = [80.0, 100.0, 76.0, 120.0, 84.0]
const SHAFT_LOW_IDX: Array[int] = [0, 2, 4]
const SHAFT_LEAN := deg_to_rad(12.0)
const SHAFT_END_Y := 760.0
const SHAFT_SPREAD := 1.8
const SHAFT_ALPHA := 0.07
const SHAFT_SWAY := deg_to_rad(1.5)
const SHAFT_SWAY_SEC := 9.0

## L2 / L5 parallax speeds (px/s).
const RIDGE_SPEED := 4.0
const ROCKS_SPEED := 14.0

## L3 kelp.
const KELP_X: Array[float] = [180.0, 410.0, 640.0, 860.0, 1080.0, 1290.0, 1500.0, 1700.0, 1880.0]
const KELP_LOW_IDX: Array[int] = [0, 2, 4, 6, 8]
const KELP_SEGMENTS := 10
const KELP_W_ROOT := 10.0
const KELP_W_TIP := 3.0
const KELP_SWAY := 14.0
const KELP_DRIFT := 8.0
const KELP_WRAP := 200.0

## L4 submarine.
const SUB_CENTER := Vector2(1400.0, 560.0)
const SUB_BOB := 8.0
const SUB_PERIOD := 6.0
const SUB_PITCH := deg_to_rad(1.0)
const CONE_APEX := Vector2(-268.0, 14.0)  # the nose, (1132, 574) at rest
const CONE_LEN := 700.0
## Cone axis below the horizontal, pointing left (matches the 02.2 mockup composition).
const CONE_ANGLE := deg_to_rad(57.0)
const CONE_HALF_OUTER := deg_to_rad(14.0)
const CONE_HALF_INNER := deg_to_rad(7.0)
const CONE_ALPHA_OUTER := 0.06
const CONE_ALPHA_INNER := 0.05
const CONE_STEPS := 8
## Lit pool on the far ridge where the beam lands (sub-local, along the cone axis). Full only.
const POOL_DIST := 300.0
const POOL_SIZE := Vector2(380.0, 96.0)
const POOL_ALPHA := 0.16
const POOL_CORE_ALPHA := 0.12
const PORTHOLES: Array[Vector2] = [Vector2(-140.0, -6.0), Vector2(-80.0, -6.0), Vector2(-20.0, -6.0)]

## L6 snow / L7 specks.
const SNOW_SWAY := 6.0
const SPECK_MIN_A := 0.3
const SPECK_MAX_A := 0.85

## Animation variant; set before adding to the tree ("title", "table", "calm").
var variant := "title"
## Bio-speck pulse rate in Hz (menu music beat; 0.5 Hz when there is no tempo, plan 07).
var pulse_hz := 0.5

var _low := false
var _reduce := false
var _layer_a := 1.0
var _snow_n := 0
var _speck_n := 0
var _shaft_idx: Array[int] = []
var _kelp_idx: Array[int] = []

var _pulse_t := 0.0
var _motion_t := 0.0
var _kelp_t := 0.0
var _sub_t := 0.0
var _shaft_t := 0.0
var _ridge_off := 0.0
var _rocks_off := 0.0
var _kelp_drift := 0.0
var _sub_xform := Transform2D.IDENTITY

var _grad_tex: GradientTexture2D
var _surface_tex: GradientTexture2D
var _vignette_tex: GradientTexture2D

var _ridge_poly := PackedVector2Array()
var _ridge_crest := PackedVector2Array()
var _rock_polys: Array[PackedVector2Array] = []
var _hull := PackedVector2Array()
var _sail := PackedVector2Array()
var _rudders: Array[PackedVector2Array] = []
var _hull_rim := PackedVector2Array()
var _sail_rim := PackedVector2Array()
var _rudder_rim := PackedVector2Array()
var _shaft_quads: Array[PackedVector2Array] = []
var _shaft_colors := PackedColorArray()
var _cone_tris: Array[PackedVector2Array] = []
var _cone_cols: Array[PackedColorArray] = []

var _kelp_h := PackedFloat32Array()
var _kelp_period := PackedFloat32Array()
var _kelp_phase0 := PackedFloat32Array()
var _kelp_bend := PackedFloat32Array()
var _kelp_buf := PackedVector2Array()
var _kelp_ctr := PackedVector2Array()
var _leaf_buf := PackedVector2Array()

var _snow_pos := PackedVector2Array()
var _snow_speed := PackedFloat32Array()
var _snow_size := PackedFloat32Array()
var _snow_phase := PackedFloat32Array()

var _speck_pos := PackedVector2Array()
var _speck_rise := PackedFloat32Array()
var _speck_size := PackedFloat32Array()
var _speck_phase := PackedFloat32Array()

var _gradient_layer: LayerCanvas
var _shafts_layer: LayerCanvas
var _light_layer: LayerCanvas


## A full-rect canvas that forwards _draw to a painter Callable(ci).
class LayerCanvas:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_build_textures()
	_build_ridge()
	_build_rocks()
	_build_sub()
	_build_shafts()
	_build_cone()
	_build_kelp()
	_build_particles()


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gradient_layer = _make_layer("Gradient", _draw_gradient, true)
	_shafts_layer = _make_layer("Shafts", _draw_shafts, true)
	_shafts_layer.material = UiKit.additive_material()
	_light_layer = _make_layer("Searchlight", _draw_searchlight, false)
	_update_sub()
	apply_effect_settings()
	UiKit.register_fx(self)


func _make_layer(layer_name: String, painter: Callable, behind: bool) -> LayerCanvas:
	var c := LayerCanvas.new()
	c.name = layer_name
	c.painter = painter
	c.show_behind_parent = behind
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.focus_mode = Control.FOCUS_NONE
	UiLayout.fill_rect(c)
	add_child(c)
	return c


# ---- effect contract ------------------------------------------------------------------

## Effect contract: re-read Low effects / Reduce motion and reconfigure in place.
func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	_reduce = UiKit.reduce_motion()
	_layer_a = TABLE_ALPHA if variant == "table" else 1.0
	if variant == "calm":
		_snow_n = CALM_SNOW_LOW if _low else CALM_SNOW_FULL
		_speck_n = 0
		_shaft_idx = []
		_kelp_idx = []
	else:
		_snow_n = SNOW_LOW if _low else SNOW_FULL
		_speck_n = SPECKS_LOW if _low else SPECKS_FULL
		if _low:
			_shaft_idx = SHAFT_LOW_IDX.duplicate()
			_kelp_idx = KELP_LOW_IDX.duplicate()
		else:
			_shaft_idx = [0, 1, 2, 3, 4]
			_kelp_idx = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	if _shafts_layer != null:
		_shafts_layer.visible = variant != "calm"
	if _light_layer != null:
		_light_layer.visible = variant == "title"
		_light_layer.material = null if _low else UiKit.additive_material()
	_redraw_all()


## Effect contract: what is active right now.
func effect_counts() -> Dictionary:
	if variant == "calm":
		return {"snow": _snow_n, "frozen": _reduce}
	return {
		"snow": _snow_n,
		"frozen": _reduce,
		"specks": _speck_n,
		"shafts": _shaft_idx.size(),
		"kelp": _kelp_idx.size(),
		"sub": 1 if variant == "title" else 0,
	}


# ---- state accessors (tests, harness) -------------------------------------------------

func layer_alpha() -> float:
	return _layer_a


func ridge_offset() -> float:
	return _ridge_off


func rocks_offset() -> float:
	return _rocks_off


func kelp_phase() -> float:
	return _kelp_t


func kelp_drift() -> float:
	return _kelp_drift


func shaft_sway() -> float:
	return SHAFT_SWAY * sin(_shaft_t * TAU / SHAFT_SWAY_SEC)


func sub_transform() -> Transform2D:
	return _sub_xform


## True when the searchlight cone is drawn additively (Full effects, title variant).
func searchlight_glow() -> bool:
	return variant == "title" and not _low


## Drawn position of snow particle i (sink + sway).
func snow_position(i: int) -> Vector2:
	var p := _snow_pos[i]
	return Vector2(p.x + SNOW_SWAY * sin(_motion_t * 0.7 + _snow_phase[i]), p.y)


## Current alpha of bio speck i, 0.3..0.85, pulsed at pulse_hz (kept under Reduce motion).
func speck_alpha(i: int) -> float:
	var beat := pow(1.0 - fposmod(_pulse_t * pulse_hz, 1.0), 3.0)
	var twinkle := 0.5 + 0.5 * sin(_pulse_t * 1.3 + _speck_phase[i])
	var k := clampf(0.65 * beat + 0.35 * twinkle, 0.0, 1.0)
	return lerpf(SPECK_MIN_A, SPECK_MAX_A, k)


# ---- time -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)
	_redraw_all()


## Step every animation clock. Public so tests can drive time without frames.
func advance(delta: float) -> void:
	_pulse_t += delta
	if _reduce:
		return
	_motion_t += delta
	_kelp_t += delta
	_sub_t += delta
	if not _low:
		_shaft_t += delta
		_ridge_off = fposmod(_ridge_off + RIDGE_SPEED * delta, W)
		_rocks_off = fposmod(_rocks_off + ROCKS_SPEED * delta, W)
		_kelp_drift = fposmod(_kelp_drift + KELP_DRIFT * delta, W + KELP_WRAP)
	for i in _snow_n:
		var p := _snow_pos[i]
		p.y += _snow_speed[i] * delta
		if p.y > H + 8.0:
			p.y -= H + 16.0
		_snow_pos[i] = p
	for i in _speck_n:
		var q := _speck_pos[i]
		q.y -= _speck_rise[i] * delta
		q.x += 3.0 * sin(_motion_t * 0.4 + _speck_phase[i]) * delta
		if q.y < -8.0:
			q.y += H + 16.0
		_speck_pos[i] = q
	_update_sub()


func _update_sub() -> void:
	var w := _sub_t * TAU / SUB_PERIOD
	_sub_xform = Transform2D(SUB_PITCH * sin(w + 1.3), SUB_CENTER + Vector2(0.0, SUB_BOB * sin(w)))


func _redraw_all() -> void:
	queue_redraw()
	if _gradient_layer != null:
		_gradient_layer.queue_redraw()
	if _shafts_layer != null:
		_shafts_layer.queue_redraw()
	if _light_layer != null:
		_light_layer.queue_redraw()


# ---- drawing --------------------------------------------------------------------------

func _draw_gradient(ci: CanvasItem) -> void:
	ci.draw_texture_rect(_grad_tex, Rect2(0.0, 0.0, W, H), false)
	ci.draw_texture_rect(_surface_tex, Rect2(1300.0 - 900.0, -200.0 - 900.0, 1800.0, 1800.0), false)


func _draw_shafts(ci: CanvasItem) -> void:
	var sway := shaft_sway()
	var mod := Color(Palette.WHITE, _layer_a)
	for k in _shaft_idx.size():
		var i: int = _shaft_idx[k]
		ci.draw_set_transform(Vector2(SHAFT_X[i], -10.0), sway * (1.0 if i % 2 == 0 else -0.8))
		ci.draw_primitive(_shaft_quads[i], _tint(_shaft_colors, mod), PackedVector2Array())
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if variant == "title" and not _low:
		# Faint halo behind the submarine so its silhouette reads against the water.
		var g := Vector2(1100.0, 520.0)
		ci.draw_texture_rect(UiKit.glow_texture(), Rect2(_sub_xform.origin - g * 0.5, g), false,
			Color(Palette.SONAR, 0.07))


func _tint(cols: PackedColorArray, mod: Color) -> PackedColorArray:
	if mod.a >= 1.0:
		return cols
	var out := cols.duplicate()
	for i in out.size():
		out[i] = Color(out[i], out[i].a * mod.a)
	return out


func _draw() -> void:
	if variant != "calm":
		_draw_ridge()
		_draw_kelp()
		if variant == "title":
			_draw_sub()
		_draw_rocks()
	_draw_snow()
	if variant != "calm":
		_draw_specks()
	draw_texture_rect(_vignette_tex, Rect2(0.0, 0.0, W, H), false)


func _draw_ridge() -> void:
	draw_set_transform(Vector2(-_ridge_off, 0.0))
	draw_colored_polygon(_ridge_poly, Color(Palette.SILHOUETTE_FAR, _layer_a))
	draw_polyline(_ridge_crest, Color(Palette.SONAR, 0.07 * _layer_a), 2.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_rocks() -> void:
	var col := Color(Palette.SILHOUETTE_NEAR, _layer_a)
	for shift in [-W, 0.0, W]:
		draw_set_transform(Vector2(shift - _rocks_off, 0.0))
		for poly in _rock_polys:
			draw_colored_polygon(poly, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_kelp() -> void:
	var col := Color(Palette.SILHOUETTE_MID, _layer_a)
	var tip_col := Color(Palette.BIO_VIOLET, 0.5 * _layer_a)
	var glow := UiKit.glow_texture()
	var n := KELP_SEGMENTS + 1
	for k in _kelp_idx.size():
		var i: int = _kelp_idx[k]
		var root_x := fposmod(KELP_X[i] - _kelp_drift + KELP_WRAP * 0.5, W + KELP_WRAP) - KELP_WRAP * 0.5
		var h := _kelp_h[i]
		var w_t := _kelp_t * TAU / _kelp_period[i] + _kelp_phase0[i]
		var tip := Vector2.ZERO
		for j in n:
			var s := float(j) / float(KELP_SEGMENTS)
			var y := H + 6.0 - h * s
			var cx := root_x + _kelp_bend[i] * sin(s * PI * 1.2) \
				+ KELP_SWAY * pow(s, 1.5) * sin(w_t - s * 1.4)
			var half := lerpf(KELP_W_ROOT, KELP_W_TIP, s) * 0.5
			_kelp_buf[j] = Vector2(cx - half, y)
			_kelp_buf[2 * n - 1 - j] = Vector2(cx + half, y)
			_kelp_ctr[j] = Vector2(cx, y)
			tip = Vector2(cx, y)
		draw_colored_polygon(_kelp_buf, col)
		# Blades: alternating leaves on every second joint, swaying with the stem.
		for j in range(2, KELP_SEGMENTS, 2):
			var side := 1.0 if (j / 2 + i) % 2 == 0 else -1.0
			var b := _kelp_ctr[j]
			var up := _kelp_ctr[j + 1] - b
			var size := lerpf(1.0, 0.55, float(j) / float(KELP_SEGMENTS))
			_leaf_buf[0] = b
			_leaf_buf[1] = b + Vector2(side * 20.0 * size, -10.0 * size) + up * 0.3
			_leaf_buf[2] = b + Vector2(side * 9.0 * size, 0.0) + up * 0.95
			draw_colored_polygon(_leaf_buf, col)
		draw_polyline(_kelp_ctr, Color(Palette.SONAR, 0.05 * _layer_a), 1.0, true)
		if not _low:
			var g := Vector2(28.0, 28.0)
			draw_texture_rect(glow, Rect2(tip - g * 0.5, g), false, Color(Palette.BIO_VIOLET, 0.3 * _layer_a))
		draw_circle(tip, 3.0, tip_col)


func _draw_sub() -> void:
	draw_set_transform_matrix(_sub_xform)
	for r in _rudders:
		draw_colored_polygon(r, Palette.ABYSS_800)
	draw_colored_polygon(_sail, Palette.ABYSS_800)
	draw_colored_polygon(_hull, Palette.ABYSS_800)
	var rim := Color(Palette.SONAR, 0.3)
	draw_polyline(_hull_rim, rim, 2.0, true)
	draw_polyline(_sail_rim, rim, 2.0, true)
	draw_polyline(_rudder_rim, rim, 2.0, true)
	# Periscope mast and a hull seam.
	draw_line(Vector2(36.0, -98.0), Vector2(36.0, -124.0), rim, 2.0, true)
	draw_line(Vector2(36.0, -124.0), Vector2(48.0, -124.0), rim, 2.0, true)
	draw_line(Vector2(-200.0, 26.0), Vector2(150.0, 26.0), Color(Palette.SONAR, 0.08), 1.0, true)
	for p in PORTHOLES:
		draw_circle(p, 6.0, Color(Palette.SONAR_PALE, 0.7))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_snow() -> void:
	for i in _snow_n:
		var s := _snow_size[i]
		var p := snow_position(i)
		var a := (0.16 + 0.09 * (s - 2.0)) * _layer_a
		draw_rect(Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s), Color(Palette.SONAR_PALE, a))


func _draw_specks() -> void:
	var glow := UiKit.glow_texture()
	for i in _speck_n:
		var c: Color = Palette.SONAR if i % 2 == 0 else Palette.BIO_VIOLET
		var a := speck_alpha(i) * _layer_a
		var p := _speck_pos[i]
		var r := _speck_size[i] * 0.5
		if not _low:
			var g := Vector2.ONE * _speck_size[i] * 7.0
			draw_texture_rect(glow, Rect2(p - g * 0.5, g), false, Color(c, a * 0.4))
		draw_circle(p, r, Color(c, a))


func _draw_searchlight(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_sub_xform)
	for t in _cone_tris.size():
		ci.draw_primitive(_cone_tris[t], _cone_cols[t], PackedVector2Array())
	if not _low:
		var glow := UiKit.glow_texture()
		var g := Vector2(56.0, 56.0)
		ci.draw_texture_rect(glow, Rect2(CONE_APEX - g * 0.5, g), false, Color(Palette.SONAR_PALE, 0.55))
		var pg := Vector2(30.0, 30.0)
		for p in PORTHOLES:
			ci.draw_texture_rect(glow, Rect2(p - pg * 0.5, pg), false, Color(Palette.SONAR_PALE, 0.35))
		# Lit pool where the beam lands on the far ridge (02.2-07 visual review): a wide soft
		# ellipse plus a tighter core, so the cone ends on something instead of fading out.
		var axis := PI - CONE_ANGLE
		var hit := CONE_APEX + Vector2(cos(axis), sin(axis)) * POOL_DIST
		ci.draw_texture_rect(glow, Rect2(hit - POOL_SIZE * 0.5, POOL_SIZE), false,
			Color(Palette.SONAR_PALE, POOL_ALPHA))
		var core := POOL_SIZE * 0.45
		ci.draw_texture_rect(glow, Rect2(hit - core * 0.5, core), false, Color(Palette.SONAR_PALE, POOL_CORE_ALPHA))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---- one-time geometry ----------------------------------------------------------------

func _build_textures() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Palette.ABYSS_700, Palette.ABYSS_850, Palette.ABYSS_900])
	_grad_tex = GradientTexture2D.new()
	_grad_tex.gradient = g
	_grad_tex.fill_from = Vector2(0.0, 0.0)
	_grad_tex.fill_to = Vector2(0.0, 1.0)
	_grad_tex.width = 4
	_grad_tex.height = 512
	_surface_tex = _radial([0.0, 1.0], [Color(Palette.SONAR, 0.10), Color(Palette.SONAR, 0.0)], 1.0)
	_vignette_tex = _radial([0.0, 0.78, 1.0],
		[Color(Palette.SHADOW, 0.0), Color(Palette.SHADOW, 0.0), Palette.SHADOW], 0.5 + 0.5 * sqrt(2.0))


## `reach` is fill_to.x in UV: 1.0 puts the last stop at the texture edge.
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


## Periodic far ridge (tile width 1920, crest y 700..820), built as one 2-tile polygon so
## scrolling never shows a seam.
func _build_ridge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 610_201
	var xs: Array[float] = []
	var ys: Array[float] = []
	var x := 0.0
	while x < W - 60.0:
		xs.append(x)
		ys.append(rng.randf_range(712.0, 812.0))
		x += rng.randf_range(100.0, 180.0)
	var mids: Array[float] = []
	for k in xs.size():
		mids.append(rng.randf_range(-16.0, 10.0))
	var crest := PackedVector2Array()
	for tile in 2:
		for k in xs.size():
			var x0 := xs[k]
			var y0 := ys[k]
			var x1 := W if k + 1 >= xs.size() else xs[k + 1]
			var y1 := ys[0] if k + 1 >= xs.size() else ys[k + 1]
			crest.append(Vector2(x0 + tile * W, y0))
			crest.append(Vector2((x0 + x1) * 0.5 + tile * W, clampf((y0 + y1) * 0.5 + mids[k], 700.0, 820.0)))
	crest.append(Vector2(2.0 * W, ys[0]))
	_ridge_crest = crest
	_ridge_poly = crest.duplicate()
	_ridge_poly.append(Vector2(2.0 * W, H + 10.0))
	_ridge_poly.append(Vector2(0.0, H + 10.0))


## Near-rock clusters (y 900..1080), drawn at three horizontal shifts: the big mass spans
## the tile seam, so at rest it reads as a bottom-left and a bottom-right rock.
func _build_rocks() -> void:
	_rock_polys = [
		PackedVector2Array([
			Vector2(1560, 1090), Vector2(1604, 1032), Vector2(1652, 998), Vector2(1702, 986),
			Vector2(1758, 952), Vector2(1828, 942), Vector2(1880, 926), Vector2(1920, 921),
			Vector2(1990, 914), Vector2(2062, 908), Vector2(2124, 930), Vector2(2182, 962),
			Vector2(2232, 1012), Vector2(2268, 1090)]),
		PackedVector2Array([
			Vector2(800, 1090), Vector2(846, 1052), Vector2(904, 1034), Vector2(962, 1040),
			Vector2(1004, 1062), Vector2(1040, 1090)]),
	]


## Submarine silhouette in local coordinates around SUB_CENTER (560 x ~150).
func _build_sub() -> void:
	var hull := PackedVector2Array()
	var rim := PackedVector2Array()
	var ry := 50.0
	# Nose: left half-ellipse centred (-190, 0), rx 80, from the top round to the bottom.
	for k in 13:
		var a := PI * 0.5 + PI * float(k) / 12.0
		hull.append(Vector2(-190.0 + 80.0 * cos(-a), ry * sin(-a)))
	# hull now runs top (-190,-50) -> nose (-270,0) -> bottom (-190,50).
	# Bottom run and tail (quadratic taper to the stern at x 262).
	var bottom_tail := PackedVector2Array()
	for k in 11:
		var t := float(k) / 10.0
		var p0 := Vector2(120.0, ry)
		var p1 := Vector2(226.0, ry - 2.0)
		var p2 := Vector2(262.0, 8.0)
		bottom_tail.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	var top_tail := PackedVector2Array()
	for k in 11:
		var t := 1.0 - float(k) / 10.0
		var p0 := Vector2(120.0, -ry)
		var p1 := Vector2(226.0, -ry + 2.0)
		var p2 := Vector2(262.0, -8.0)
		top_tail.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	# Polygon order: top -> nose -> bottom -> tail -> stern -> back along the top.
	var poly := PackedVector2Array()
	for p in hull:
		poly.append(p)
	poly.append_array(bottom_tail)
	poly.append(Vector2(268.0, 0.0))
	poly.append_array(top_tail)
	_hull = poly
	# Rim light along the upper edge: from the upper nose to the tail top.
	for k in 9:
		var a := PI * 0.8 - PI * 0.3 * float(k) / 8.0
		rim.append(Vector2(-190.0 + 80.0 * cos(a), -ry * sin(a)))
	for k in range(top_tail.size() - 1, -1, -1):
		rim.append(top_tail[k])
	_hull_rim = rim
	_sail = PackedVector2Array([
		Vector2(-44, -48), Vector2(-24, -98), Vector2(76, -98), Vector2(100, -48)])
	_sail_rim = PackedVector2Array([Vector2(-44, -50), Vector2(-24, -98), Vector2(76, -98), Vector2(100, -50)])
	_rudders = [
		PackedVector2Array([Vector2(214, -34), Vector2(252, -72), Vector2(274, -72), Vector2(264, -10)]),
		PackedVector2Array([Vector2(214, 34), Vector2(264, 10), Vector2(274, 72), Vector2(252, 72)]),
		PackedVector2Array([Vector2(-6, -76), Vector2(-36, -70), Vector2(-36, -64), Vector2(-4, -66)]),
	]
	_rudder_rim = _rudders[0].slice(0, 3)


## Shaft quads in local coordinates (top centre at the origin), leaning 12 degrees left,
## SONAR_PALE 7% at the top fading to 0 at y 760.
func _build_shafts() -> void:
	_shaft_quads.clear()
	var dir := Vector2(-sin(SHAFT_LEAN), cos(SHAFT_LEAN))
	var length := (SHAFT_END_Y + 10.0) / cos(SHAFT_LEAN)
	for i in SHAFT_X.size():
		var w := SHAFT_W[i]
		var bottom := dir * length
		var bw := w * SHAFT_SPREAD
		_shaft_quads.append(PackedVector2Array([
			Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, 0.0),
			bottom + Vector2(bw * 0.5, 0.0), bottom - Vector2(bw * 0.5, 0.0)]))
	var top := Color(Palette.SONAR_PALE, SHAFT_ALPHA)
	var end := Color(Palette.SONAR_PALE, 0.0)
	_shaft_colors = PackedColorArray([top, top, end, end])


## Searchlight cone triangles (local to the submarine): an outer and an inner fan.
func _build_cone() -> void:
	_cone_tris.clear()
	_cone_cols.clear()
	var axis := PI - CONE_ANGLE  # pointing left and down (y grows downward)
	for spec in [[CONE_HALF_OUTER, CONE_ALPHA_OUTER], [CONE_HALF_INNER, CONE_ALPHA_INNER]]:
		var half: float = spec[0]
		var a0 := Color(Palette.SONAR_PALE, float(spec[1]))
		var a1 := Color(Palette.SONAR_PALE, 0.0)
		for k in CONE_STEPS:
			var t0 := axis - half + 2.0 * half * float(k) / float(CONE_STEPS)
			var t1 := axis - half + 2.0 * half * float(k + 1) / float(CONE_STEPS)
			var e0 := CONE_APEX + Vector2(cos(t0), sin(t0)) * CONE_LEN
			var e1 := CONE_APEX + Vector2(cos(t1), sin(t1)) * CONE_LEN
			_cone_tris.append(PackedVector2Array([CONE_APEX, e0, e1]))
			_cone_cols.append(PackedColorArray([a0, a1, a1]))


func _build_kelp() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 610_303
	var n := KELP_X.size()
	_kelp_h.resize(n)
	_kelp_period.resize(n)
	_kelp_phase0.resize(n)
	_kelp_bend.resize(n)
	for i in n:
		_kelp_h[i] = rng.randf_range(260.0, 520.0)
		_kelp_period[i] = rng.randf_range(5.0, 8.0)
		_kelp_phase0[i] = rng.randf_range(0.0, TAU)
		_kelp_bend[i] = rng.randf_range(-22.0, 22.0)
	_kelp_buf.resize(2 * (KELP_SEGMENTS + 1))
	_kelp_ctr.resize(KELP_SEGMENTS + 1)
	_leaf_buf.resize(3)


## Snow and specks: low-discrepancy positions (any prefix covers the screen evenly, so the
## Low counts are just the first N), fixed-seed sizes and speeds.
func _build_particles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 610_404
	_snow_pos.resize(SNOW_FULL)
	_snow_speed.resize(SNOW_FULL)
	_snow_size.resize(SNOW_FULL)
	_snow_phase.resize(SNOW_FULL)
	for i in SNOW_FULL:
		_snow_pos[i] = Vector2(fposmod(float(i) * 0.7548777 + 0.13, 1.0) * W,
			fposmod(float(i) * 0.5698403 + 0.31, 1.0) * H)
		_snow_speed[i] = rng.randf_range(20.0, 50.0)
		_snow_size[i] = rng.randf_range(2.0, 4.0)
		_snow_phase[i] = rng.randf_range(0.0, TAU)
	rng.seed = 610_505
	_speck_pos.resize(SPECKS_FULL)
	_speck_rise.resize(SPECKS_FULL)
	_speck_size.resize(SPECKS_FULL)
	_speck_phase.resize(SPECKS_FULL)
	for i in SPECKS_FULL:
		_speck_pos[i] = Vector2(fposmod(float(i) * 0.6180339 + 0.41, 1.0) * W,
			120.0 + fposmod(float(i) * 0.4142135 + 0.07, 1.0) * (H - 200.0))
		_speck_rise[i] = rng.randf_range(3.0, 9.0)
		_speck_size[i] = rng.randf_range(2.0, 4.0)
		_speck_phase[i] = rng.randf_range(0.0, TAU)
