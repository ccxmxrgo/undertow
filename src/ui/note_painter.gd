class_name NotePainter
extends RefCounted
## Solid gem notes (02.2 UI-SPEC 4.15). One draw function keyed by note type: NOTE_NORMAL
## now; Phase 3 adds NOTE_GHOST and NOTE_DISRUPTOR as new match entries in draw_note and
## layers, nothing else changes. Gem layers, back to front: halo (ready only), keyline,
## core (always the FULL lane colour, never darkened), top-light, specular, rim.
## The Full-effects halo is additive, so it is drawn by HighwayNotes' "Halos" child (which
## has the shared additive material) through draw_halo(), never by the gem pass itself.
## Unit geometry is cached per lane kind; fills are drawn through draw_set_transform from
## the cached arrays, outlines through two small preallocated ring buffers.
## Colours come from Palette only (VIS-01).

const NOTE_NORMAL := 0

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

## Specular chevron centre per lane kind (unit space, y down): inside every shape's top half.
const _SPEC_CENTRE: Array[Vector2] = [Vector2(0.0, -0.5), Vector2(-0.3, -0.5), Vector2(0.0, -0.3), Vector2(-0.4, -0.6)]

static var _cache: Dictionary = {}
static var _ring_tri := PackedVector2Array()
static var _ring_quad := PackedVector2Array()


## Unknown types fall back to NOTE_NORMAL (Phase 3 extends this match).
static func resolve_type(type: int) -> int:
	match type:
		NOTE_NORMAL:
			return NOTE_NORMAL
		_:
			return NOTE_NORMAL


## Ordered layer names drawn for a gem (tests and docs; draw_note follows the same order).
static func layers(type: int, _lane: int, state: int, low_effects: bool) -> Array[String]:
	var out: Array[String] = []
	match resolve_type(type):
		_:
			if state == STATE_MISSED:
				out.assign(["core", "x"])
				return out
			if state == STATE_READY:
				out.append("halo_ring" if low_effects else "halo")
			out.append_array(["keyline", "core", "toplight", "specular", "rim"])
	return out


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
	var clip := PackedVector2Array([Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(2.0, TOPLIGHT_CLIP), Vector2(-2.0, TOPLIGHT_CLIP)])
	var parts := Geometry2D.intersect_polygons(poly, clip)
	var top: PackedVector2Array = parts[0] if not parts.is_empty() else PackedVector2Array()
	# Chevron "^" 0.35 wide: outer edge, apex, outer edge, then the inner edge back.
	var c := _SPEC_CENTRE[k]
	var w := SPEC_W * 0.5
	var spec := PackedVector2Array([
		c + Vector2(-w, 0.06), c + Vector2(0.0, -0.10), c + Vector2(w, 0.06),
		c + Vector2(w, 0.13), c + Vector2(0.0, -0.03), c + Vector2(-w, 0.13)])
	# Closed outline starting mid-edge, so the polyline's unjoined seam never sits on a corner.
	var ring := PackedVector2Array()
	if k != NoteShape.Kind.CIRCLE:
		var mid := (poly[poly.size() - 1] + poly[0]) * 0.5
		ring.append(mid)
		ring.append_array(poly)
		ring.append(mid)
	var entry := {"poly": poly, "top": top, "spec": spec, "ring": ring}
	_cache[k] = entry
	return entry


## Draw one gem. `t` is the song time (reserved for animated Phase 3 types); `fade` scales a
## missed remnant (1 = fresh). Ready Full halos are NOT drawn here (see draw_halo).
static func draw_note(ci: CanvasItem, type: int, lane: int, center: Vector2, r: float, state: int, t: float, fade: float = 1.0) -> void:
	match resolve_type(type):
		_:
			_draw_normal(ci, lane, center, r, state, t, fade)


## Additive halo sprite for a ready gem (Full effects); call on the additive Halos layer.
static func draw_halo(ci: CanvasItem, lane: int, center: Vector2, r: float) -> void:
	var reach := HALO_REACH * r
	ci.draw_texture_rect(UiKit.glow_texture(), Rect2(center - Vector2(reach, reach), Vector2(2.0 * reach, 2.0 * reach)),
		false, Palette.alpha(Palette.lane_color(lane), HALO_ALPHA))


## Chord bar between two chord gem centres (drawn behind the gems).
static func draw_chord_bar(ci: CanvasItem, a: Vector2, b: Vector2, s: float) -> void:
	var col := Palette.alpha(Palette.SONAR_PALE, CHORD_ALPHA)
	ci.draw_line(a, b, col, 3.0 + 3.0 * s, true)
	ci.draw_circle(a, CHORD_DOT_R, col, true, -1.0, true)
	ci.draw_circle(b, CHORD_DOT_R, col, true, -1.0, true)


static func _draw_normal(ci: CanvasItem, lane: int, center: Vector2, r: float, state: int, _t: float, fade: float) -> void:
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
		_outline(ci, kind, u, center, r + HALO_RING_GAP, HALO_RING_W, Palette.alpha(lane_col, HALO_RING_ALPHA))
	var rw := rim_width(scale_for_radius(r))
	_outline(ci, kind, u, center, r + KEYLINE_W * 0.5, KEYLINE_W, Palette.KEYLINE)
	_fill(ci, poly, center, r, core_color(lane))
	_fill(ci, u["top"], center, r, toplight_color(lane))
	_fill(ci, u["spec"], center, r, Palette.alpha(Palette.WHITE, SPEC_ALPHA))
	_outline(ci, kind, u, center, r - rw * 0.5, rw, rim_color(lane, ready))


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
