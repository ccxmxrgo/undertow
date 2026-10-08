class_name Trench
extends RefCounted
## Pure static projection for the Trench Descent board (D-02..D-05). Depth is LINEAR in time
## (depth_for, never clamped); every non-linearity lives in scale_at / norm_at / point, so a
## note whose time equals the visual time sits exactly on hit_point(lane).

const VP := Vector2(960.0, 396.0)
const HIT_Y := 960.0
const LANE_SPREAD := 210.0
const SAG := 21.6
const RING_CURVE := 36.0
const Z_SCALE := 0.42
const APPROACH_BASE := 1.5
const D_MIN := -0.15
const D_FAR := 1.0
const PERSPECTIVE := 4.2
const TRAVEL := 564.0  # HIT_Y - VP.y


static func lane_f(lane: int) -> float:
	return float(lane) - 1.5


## Seconds from the far end of the cable to the hit ring. Speed is clamped (no divide by zero).
static func approach_for(scroll_speed: float) -> float:
	return APPROACH_BASE / maxf(scroll_speed, 0.1)


## Linear depth: 0 at the ring, 1 at the far end, negative once past the ring. Never clamped.
static func depth_for(note_time: float, vt: float, approach: float) -> float:
	return (note_time - vt) / maxf(approach, 0.001)


static func scale_at(d: float) -> float:
	return 1.0 / (1.0 + PERSPECTIVE * clampf(d, D_MIN, D_FAR))


static func norm_at(d: float) -> float:
	var smin := 1.0 / (1.0 + PERSPECTIVE)
	return (scale_at(d) - smin) / (1.0 - smin)


## Allocation-free screen position for lane offset f at depth d (hot path).
static func point(f: float, d: float) -> Vector2:
	var dd := clampf(d, D_MIN, D_FAR)
	var s := 1.0 / (1.0 + PERSPECTIVE * dd)
	var smin := 1.0 / (1.0 + PERSPECTIVE)
	var n := (s - smin) / (1.0 - smin)
	var x := VP.x + f * LANE_SPREAD * s * (0.35 + 0.65 * n)
	var y := VP.y + TRAVEL * n + sin(dd * PI) * SAG * (1.0 - dd) - f * f * RING_CURVE * n * n
	return Vector2(x, y)


## Dictionary form for tests and tools: {pos, s, n}.
static func project(f: float, d: float) -> Dictionary:
	return {"pos": point(f, d), "s": scale_at(d), "n": norm_at(d)}


static func hit_point(lane: int) -> Vector2:
	return point(lane_f(lane), 0.0)


## The curved hit ring polyline, f in [-2.1, 2.1] at d = 0.
static func ring_points(samples: int = 41) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := maxi(samples, 2)
	out.resize(count)
	for i in range(count):
		var f := lerpf(-2.1, 2.1, float(i) / float(count - 1))
		out[i] = point(f, 0.0)
	return out


static func note_radius(s: float) -> float:
	return 36.0 * s + 5.0
