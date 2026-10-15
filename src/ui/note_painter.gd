class_name NotePainter
extends RefCounted
## Solid gem notes (02.2 UI-SPEC 4.15). One draw function keyed by note type: NOTE_NORMAL,
## plus the Phase 3 types (03-UI-SPEC 7.2, 7.3, 7.6): NOTE_GHOST (hollow dashed rim),
## NOTE_DISRUPTOR (depth charge: normal gem + charge mark) and NOTE_JAM (plain grey circle),
## and the warhead ring overlay (7.1, draw_warhead_ring). Normal gem layers, back to front:
## halo (ready only), keyline, core (always the FULL lane colour, never darkened), top-light,
## specular, rim.
## The Full-effects halo is additive, so it is drawn by HighwayNotes' "Halos" child (which
## has the shared additive material) through draw_halo(), never by the gem pass itself.
## Unit geometry is cached per lane kind; fills are drawn through draw_set_transform from
## the cached arrays, outlines through two small preallocated ring buffers.
## Colours come from Palette only (VIS-01).

const NOTE_NORMAL := 0
## Phase 3 (D-11, D-14, D-15).
const NOTE_GHOST := 1
const NOTE_DISRUPTOR := 2
const NOTE_JAM := 3

## Warhead ring states (D-16, 03-UI-SPEC 7.1).
const WARHEAD_OPEN := 0
const WARHEAD_CONFIRMED := 1
const WARHEAD_DEAD := 2

const STATE_FAR := 0
const STATE_READY := 1
const STATE_MISSED := 2

## Halo: additive glow sprite reaching HALO_REACH * r from the centre, lane colour.
const HALO_REACH := 2.6
const HALO_ALPHA := 0.35
## Low effects halo: a plain ring at r + 6, 6 px, lane colour 35%.
const HALO_RING_GAP := 6.0
const HALO_RING_W := 6.0
const HALO_RING_ALPHA := 0.35
## Keyline: 2 px outline sitting at r + 2 (its inner edge meets the rim's outer edge).
const KEYLINE_W := 2.0
## Top-light: shape part above centre.y - 0.2 r, mix(lane, white, 0.35) at 70%.
const TOPLIGHT_CLIP := -0.2
const TOPLIGHT_MIX := 0.35
const TOPLIGHT_ALPHA := 0.70
## Specular chevron, 0.35 r wide, white 55%.
const SPEC_W := 0.35
const SPEC_ALPHA := 0.55
const MISSED_ALPHA := 0.25
const MISSED_X_W := 4.0
const CIRCLE_SEGMENTS := 40
## Chord bar: width 3 + 3 s, SONAR_PALE 50%, round dots at the gem centres.
const CHORD_ALPHA := 0.5
const CHORD_DOT_R := 4.0
## Ghost rim (03-UI-SPEC 7.2): 3 px, 8 dashes per perimeter, 60% dash / 40% gap.
const GHOST_RIM_W := 3.0
const GHOST_DASHES := 8
const GHOST_DASH_FRAC := 0.6
## Depth-charge mark (7.3): filled ABYSS_900 circle of 0.22 r with a 1 px light ring.
const CHARGE_R := 0.22
const CHARGE_RING_MIX := 0.55
const CHARGE_RING_W := 1.0
## Jam gem rim (7.6).
const JAM_RIM_W := 2.0
## Warhead ring (7.1): ring at r + 8, 3 px; keyline 2 px just outside; 10 x 6 chevron
## centred 6 px above the ring top; Perfect flash grows to r + 20; dead = TEXT_LO 50%.
const WARHEAD_GAP := 8.0
const WARHEAD_W := 3.0
const WARHEAD_FLASH_GAP := 20.0
const WARHEAD_CHEVRON := Vector2(10.0, 6.0)
const WARHEAD_CHEVRON_LIFT := 6.0
const WARHEAD_DEAD_ALPHA := 0.5

## Specular chevron centre per lane kind (unit space, y down): inside every shape's top half.
const _SPEC_CENTRE: Array[Vector2] = [Vector2(0.0, -0.5), Vector2(-0.3, -0.5), Vector2(0.0, -0.3), Vector2(-0.4, -0.6)]

static var _cache: Dictionary = {}
static var _ring_tri := PackedVector2Array()
static var _ring_quad := PackedVector2Array()
static var _dash_cache: Dictionary = {}
static var _dash_buf := PackedVector2Array()


## Known types resolve to themselves; unknown types fall back to NOTE_NORMAL.
static func resolve_type(type: int) -> int:
	match type:
		NOTE_NORMAL, NOTE_GHOST, NOTE_DISRUPTOR, NOTE_JAM:
			return type
		_:
			return NOTE_NORMAL


## Ordered layer names drawn for a gem (tests and docs; draw_note follows the same order).
static func layers(type: int, _lane: int, state: int, low_effects: bool) -> Array[String]:
	var out: Array[String] = []
	match resolve_type(type):
		NOTE_GHOST:
			# Hollow and identical in every effect mode and state (no halo, core, mark or X).
			out.assign(["keyline", "rim_dashed"])
		NOTE_JAM:
			if state == STATE_MISSED:
				out.assign(["core", "x"])
			else:
				out.assign(["keyline", "core", "rim"])
		NOTE_DISRUPTOR:
			out = _normal_layers(state, low_effects)
			out.append("charge_mark")
		_:
			out = _normal_layers(state, low_effects)
	return out


static func _normal_layers(state: int, low_effects: bool) -> Array[String]:
	var out: Array[String] = []
	if state == STATE_MISSED:
		out.assign(["core", "x"])
		return out
	if state == STATE_READY:
		out.append("halo_ring" if low_effects else "halo")
	out.append_array(["keyline", "core", "toplight", "specular", "rim"])
	return out


## Sonar Jam cross-fade core colour (7.6): lane core at k = 0, JAM_GREY at k = 1. Highway
## draws the normal gem with this core while 0 < k < 1 and switches to NOTE_JAM at k = 1.
static func jam_mix(lane: int, k: float) -> Color:
	return core_color(lane).lerp(Palette.JAM_GREY, clampf(k, 0.0, 1.0))


static func core_color(lane: int) -> Color:
	return Palette.lane_color(lane)


static func rim_color(lane: int, ready: bool) -> Color:
	return Palette.rim_ready(lane) if ready else Palette.rim_far(lane)


static func rim_width(s: float) -> float:
	return 2.0 + 2.0 * s


static func toplight_color(lane: int) -> Color:
	return Palette.alpha(Palette.mix(Palette.lane_color(lane), Palette.WHITE, TOPLIGHT_MIX), TOPLIGHT_ALPHA)


static func missed_core_color(lane: int, fade: float) -> Color:
	return Palette.alpha(Palette.lane_color(lane), MISSED_ALPHA * clampf(fade, 0.0, 1.0))


static func missed_x_color(fade: float) -> Color:
	return Palette.alpha(Palette.WARNING_RED, clampf(fade, 0.0, 1.0))


## Inverse of Trench.note_radius (r = 36 s + 5).
static func scale_for_radius(r: float) -> float:
	return maxf((r - 5.0) / 36.0, 0.0)


static func cache_size() -> int:
	return _cache.size()


static func clear_cache() -> void:
	_cache.clear()
	_dash_cache.clear()


## Cached unit geometry for a lane kind: {poly, top, spec, ring}. Built once per kind.
static func unit_shape(kind: int) -> Dictionary:
	var k := posmod(kind, 4)
	if _cache.has(k):
		return _cache[k]
	var poly: PackedVector2Array
	if k == NoteShape.Kind.CIRCLE:
		poly = PackedVector2Array()
		poly.resize(CIRCLE_SEGMENTS)
		for i in range(CIRCLE_SEGMENTS):
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			poly[i] = Vector2(cos(a), sin(a))
	else:
		poly = NoteShape._polygon(k, Vector2.ZERO, 1.0)
	# Recentre on the bounding box (02.2-26, G1): the triangle spans y -1..0.9, so its visual
	# centre sat 0.05 r (2 px at the hit line) above the anchor that the judge's on-time moment
	# puts on the hit line. The specular moves with the shape and the shared pad ring is built
	# from this poly, so gem and pad stay identical; the top-light is clipped at centre - 0.2 r.
	var shift := -_bbox_center(poly)
	poly = _translated(poly, shift)
	var clip := PackedVector2Array([Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(2.0, TOPLIGHT_CLIP), Vector2(-2.0, TOPLIGHT_CLIP)])
	var parts := Geometry2D.intersect_polygons(poly, clip)
	var top: PackedVector2Array = parts[0] if not parts.is_empty() else PackedVector2Array()
	# Chevron "^" 0.35 wide: outer edge, apex, outer edge, then the inner edge back.
	var c := _SPEC_CENTRE[k] + shift
	var w := SPEC_W * 0.5
	var spec := PackedVector2Array([
		c + Vector2(-w, 0.06), c + Vector2(0.0, -0.10), c + Vector2(w, 0.06),
		c + Vector2(w, 0.13), c + Vector2(0.0, -0.03), c + Vector2(-w, 0.13)])
	# Closed outline starting mid-edge, so the polyline's unjoined seam never sits on a corner.
	# (The circle's ring is the closed 40-gon; gems draw circles with draw_arc instead.)
	var ring := PackedVector2Array()
	if k == NoteShape.Kind.CIRCLE:
		ring.append_array(poly)
		ring.append(poly[0])
	else:
		var mid := (poly[poly.size() - 1] + poly[0]) * 0.5
		ring.append(mid)
		ring.append_array(poly)
		ring.append(mid)
	var entry := {"poly": poly, "top": top, "spec": spec, "ring": ring}
	_cache[k] = entry
	return entry


static func _bbox_center(poly: PackedVector2Array) -> Vector2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r.get_center()


static func _translated(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = poly[i] + by
	return out


## Closed unit outline of a lane kind (receptor pads scale it non-uniformly for the squash).
static func outline_ring(kind: int) -> PackedVector2Array:
	return unit_shape(kind)["ring"]


## Draw one gem. `t` is the song time (reserved for animated Phase 3 types); `fade` scales a
## missed remnant (1 = fresh). Ready Full halos are NOT drawn here (see draw_halo).
static func draw_note(ci: CanvasItem, type: int, lane: int, center: Vector2, r: float, state: int, t: float, fade: float = 1.0, alpha: float = 1.0) -> void:
	match resolve_type(type):
		NOTE_GHOST:
			_draw_ghost(ci, lane, center, r, state, fade, alpha)
		NOTE_DISRUPTOR:
			_draw_normal(ci, lane, center, r, state, t, fade, alpha)
			_draw_charge_mark(ci, lane, center, r, fade if state == STATE_MISSED else alpha)
		NOTE_JAM:
			_draw_jam(ci, center, r, state, fade, alpha)
		_:
			_draw_normal(ci, lane, center, r, state, t, fade, alpha)


## Sonar Jam cross-fade frame (7.6, 0 < k < 1): the normal gem with core jam_mix(lane, k).
## Depth charges keep their charge mark through the fade (pass disruptor = true).
static func draw_jam_fade(ci: CanvasItem, lane: int, center: Vector2, r: float, state: int, t: float, k: float, fade: float = 1.0, alpha: float = 1.0, disruptor: bool = false) -> void:
	_draw_normal(ci, lane, center, r, state, t, fade, alpha, jam_mix(lane, k))
	if disruptor:
		_draw_charge_mark(ci, lane, center, r, fade if state == STATE_MISSED else alpha)


## Warhead ring overlay (D-16, 03-UI-SPEC 7.1), drawn over the gem in every effect mode and
## under Sonar Jam. OPEN: WARNING_RED ring at r + 8 (3 px) with a 2 px KEYLINE just outside
## and a filled 10 x 6 up-chevron centred 6 px above the ring top. CONFIRMED (Perfect): a
## SONAR_PALE ring whose alpha goes 1 -> 0 with flash_k; with `grow` the radius also goes
## r + 8 -> r + 20. Under Reduce motion Highway passes grow = false, so the flash is
## alpha-only (03-UI-SPEC 12); flash_k still runs 0 -> 1 over the 200 ms flash. DEAD (Good
## or Miss on the payload): ring and chevron in TEXT_LO at 50%.
static func draw_warhead_ring(ci: CanvasItem, center: Vector2, r: float, state: int, flash_k: float = 0.0, grow: bool = true, alpha: float = 1.0) -> void:
	var rr := r + WARHEAD_GAP
	if state == WARHEAD_CONFIRMED:
		var k := clampf(flash_k, 0.0, 1.0)
		var fr := lerpf(rr, r + WARHEAD_FLASH_GAP, k) if grow else rr
		var a := (1.0 - k) * alpha
		if a <= 0.0:
			return
		ci.draw_arc(center, fr, 0.0, TAU, CIRCLE_SEGMENTS, Palette.alpha(Palette.SONAR_PALE, a), WARHEAD_W, true)
		return
	var col := Palette.WARNING_RED
	var key := Palette.KEYLINE
	if state == WARHEAD_DEAD:
		col = Palette.alpha(Palette.TEXT_LO, WARHEAD_DEAD_ALPHA)
		key = faded(key, WARHEAD_DEAD_ALPHA)
	col = faded(col, alpha)
	key = faded(key, alpha)
	ci.draw_arc(center, rr + WARHEAD_W * 0.5 + KEYLINE_W * 0.5, 0.0, TAU, CIRCLE_SEGMENTS, key, KEYLINE_W, true)
	ci.draw_arc(center, rr, 0.0, TAU, CIRCLE_SEGMENTS, col, WARHEAD_W, true)
	var cc := center + Vector2(0.0, -(rr + WARHEAD_W * 0.5 + WARHEAD_CHEVRON_LIFT))
	var hw := WARHEAD_CHEVRON.x * 0.5
	var hh := WARHEAD_CHEVRON.y * 0.5
	ci.draw_colored_polygon(PackedVector2Array([cc + Vector2(-hw, hh), cc + Vector2(0.0, -hh), cc + Vector2(hw, hh)]), col)


## Additive halo sprite for a ready gem (Full effects); call on the additive Halos layer.
static func draw_halo(ci: CanvasItem, lane: int, center: Vector2, r: float, alpha: float = 1.0) -> void:
	var reach := HALO_REACH * r
	ci.draw_texture_rect(UiKit.glow_texture(), Rect2(center - Vector2(reach, reach), Vector2(2.0 * reach, 2.0 * reach)),
		false, Palette.alpha(Palette.lane_color(lane), HALO_ALPHA * alpha))


## Chord bar between two chord gem centres (drawn behind the gems).
static func draw_chord_bar(ci: CanvasItem, a: Vector2, b: Vector2, s: float, alpha: float = 1.0) -> void:
	var col := Palette.alpha(Palette.SONAR_PALE, CHORD_ALPHA * alpha)
	ci.draw_line(a, b, col, 3.0 + 3.0 * s, true)
	ci.draw_circle(a, CHORD_DOT_R, col, true, -1.0, true)
	ci.draw_circle(b, CHORD_DOT_R, col, true, -1.0, true)


static func _draw_normal(ci: CanvasItem, lane: int, center: Vector2, r: float, state: int, _t: float, fade: float, alpha: float = 1.0, core: Variant = null) -> void:
	var kind := NoteShape.kind_for_lane(lane)
	var u := unit_shape(kind)
	var poly: PackedVector2Array = u["poly"]
	if state == STATE_MISSED:
		_fill(ci, poly, center, r, missed_core_color(lane, fade))
		var h := r * 0.5
		var xc := missed_x_color(fade)
		ci.draw_line(center + Vector2(-h, -h), center + Vector2(h, h), xc, MISSED_X_W, true)
		ci.draw_line(center + Vector2(-h, h), center + Vector2(h, -h), xc, MISSED_X_W, true)
		return
	var lane_col := Palette.lane_color(lane)
	var ready := state == STATE_READY
	if ready and UiKit.low_effects():
		_outline(ci, kind, u, center, r + HALO_RING_GAP, HALO_RING_W, Palette.alpha(lane_col, HALO_RING_ALPHA * alpha))
	var rw := rim_width(scale_for_radius(r))
	_outline(ci, kind, u, center, r + KEYLINE_W * 0.5, KEYLINE_W, faded(Palette.KEYLINE, alpha))
	_fill(ci, poly, center, r, faded(core_color(lane) if core == null else (core as Color), alpha))
	_fill(ci, u["top"], center, r, faded(toplight_color(lane), alpha))
	_fill(ci, u["spec"], center, r, Palette.alpha(Palette.WHITE, SPEC_ALPHA * alpha))
	_outline(ci, kind, u, center, r - rw * 0.5, rw, faded(rim_color(lane, ready), alpha))


## Ghost gem (D-11, 03-UI-SPEC 7.2): solid KEYLINE outline under a dashed lane-shape rim.
## No core, halo, centre mark or missed X; the same in Full, Low effects and Reduce motion.
## A missed (ignored) ghost only fades: `fade` scales it, Highway owns the 150 ms fade-out.
static func _draw_ghost(ci: CanvasItem, lane: int, center: Vector2, r: float, state: int, fade: float, alpha: float) -> void:
	var a := alpha * (clampf(fade, 0.0, 1.0) if state == STATE_MISSED else 1.0)
	if a <= 0.0:
		return
	var kind := NoteShape.kind_for_lane(lane)
	var u := unit_shape(kind)
	_outline(ci, kind, u, center, r + KEYLINE_W * 0.5, KEYLINE_W, faded(Palette.KEYLINE, a))
	var col := faded(rim_color(lane, state == STATE_READY), a)
	var k := r - GHOST_RIM_W * 0.5
	for dash: PackedVector2Array in ghost_dashes(kind):
		if _dash_buf.size() != dash.size():
			_dash_buf.resize(dash.size())
		for i in range(dash.size()):
			_dash_buf[i] = center + dash[i] * k
		ci.draw_polyline(_dash_buf, col, GHOST_RIM_W, true)


## The 8 unit-space dash polylines of a lane kind's outline (cached; T-03-05 bounded walk):
## dash i covers arc length [i, i + 0.6] * perimeter / 8 along outline_ring(kind).
static func ghost_dashes(kind: int) -> Array:
	var kk := posmod(kind, 4)
	if _dash_cache.has(kk):
		return _dash_cache[kk]
	var ring := outline_ring(kk)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, ring.size()):
		cum.append(cum[i - 1] + ring[i - 1].distance_to(ring[i]))
	var total := cum[cum.size() - 1]
	var step := total / float(GHOST_DASHES)
	var out: Array = []
	for d in range(GHOST_DASHES):
		var s0 := step * d
		var s1 := s0 + step * GHOST_DASH_FRAC
		var pts := PackedVector2Array([_ring_at(ring, cum, s0)])
		for i in range(1, ring.size() - 1):
			if cum[i] > s0 and cum[i] < s1:
				pts.append(ring[i])
		pts.append(_ring_at(ring, cum, s1))
		out.append(pts)
	_dash_cache[kk] = out
	return out


## Point at arc length s along a polyline with cumulative lengths cum.
static func _ring_at(ring: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(1, ring.size()):
		if s <= cum[i]:
			var seg := cum[i] - cum[i - 1]
			var f := 0.0 if seg <= 0.0 else (s - cum[i - 1]) / seg
			return ring[i - 1].lerp(ring[i], f)
	return ring[ring.size() - 1]


## Depth-charge mark (D-14, 7.3): ABYSS_900 disc of 0.22 r with a 1 px ring of the lane
## colour mixed 0.55 toward TEXT_HI, at the gem centre.
static func _draw_charge_mark(ci: CanvasItem, lane: int, center: Vector2, r: float, alpha: float) -> void:
	var cr := CHARGE_R * r
	ci.draw_circle(center, cr, faded(Palette.ABYSS_900, alpha), true, -1.0, true)
	var ring_col := Palette.mix(Palette.lane_color(lane), Palette.TEXT_HI, CHARGE_RING_MIX)
	ci.draw_arc(center, cr, 0.0, TAU, 20, faded(ring_col, alpha), CHARGE_RING_W, true)


## Jammed gem (D-15, 7.6): plain circle of radius r, KEYLINE outline, JAM_GREY core, 2 px
## rim TEXT_HI (ready) / TEXT_MID (far). No lane shape or colour, top-light or halo.
static func _draw_jam(ci: CanvasItem, center: Vector2, r: float, state: int, fade: float, alpha: float) -> void:
	if state == STATE_MISSED:
		var f := clampf(fade, 0.0, 1.0)
		ci.draw_circle(center, r, Palette.alpha(Palette.JAM_GREY, MISSED_ALPHA * f), true, -1.0, true)
		var h := r * 0.5
		var xc := missed_x_color(fade)
		ci.draw_line(center + Vector2(-h, -h), center + Vector2(h, h), xc, MISSED_X_W, true)
		ci.draw_line(center + Vector2(-h, h), center + Vector2(h, -h), xc, MISSED_X_W, true)
		return
	ci.draw_arc(center, r + KEYLINE_W * 0.5, 0.0, TAU, CIRCLE_SEGMENTS, faded(Palette.KEYLINE, alpha), KEYLINE_W, true)
	ci.draw_circle(center, r, faded(Palette.JAM_GREY, alpha), true, -1.0, true)
	var rim := Palette.TEXT_HI if state == STATE_READY else Palette.TEXT_MID
	ci.draw_arc(center, r - JAM_RIM_W * 0.5, 0.0, TAU, CIRCLE_SEGMENTS, faded(rim, alpha), JAM_RIM_W, true)


## Filled unit polygon scaled by k about center (no per-call point arrays).
static func _fill(ci: CanvasItem, unit: PackedVector2Array, center: Vector2, k: float, col: Color) -> void:
	if unit.size() < 3:
		return
	ci.draw_set_transform(center, 0.0, Vector2(k, k))
	ci.draw_colored_polygon(unit, col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Antialiased outline of the lane shape whose centre line sits at radius k.
static func _outline(ci: CanvasItem, kind: int, u: Dictionary, center: Vector2, k: float, width: float, col: Color) -> void:
	if kind == NoteShape.Kind.CIRCLE:
		ci.draw_arc(center, k, 0.0, TAU, CIRCLE_SEGMENTS, col, width, true)
		return
	var ring: PackedVector2Array = u["ring"]
	var n := ring.size()
	if n == 5:
		if _ring_tri.size() != 5:
			_ring_tri.resize(5)
		for i in range(5):
			_ring_tri[i] = center + ring[i] * k
		ci.draw_polyline(_ring_tri, col, width, true)
	else:
		if _ring_quad.size() != n:
			_ring_quad.resize(n)
		for i in range(n):
			_ring_quad[i] = center + ring[i] * k
		ci.draw_polyline(_ring_quad, col, width, true)


## Colour with its alpha scaled by the depth fade (alpha 1.0 returns it untouched).
static func faded(col: Color, alpha: float) -> Color:
	if alpha >= 1.0:
		return col
	col.a *= alpha
	return col
