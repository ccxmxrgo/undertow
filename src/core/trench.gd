class_name Trench
extends RefCounted
## Pure static projection for the Trench Descent board (D-02..D-05). Depth is LINEAR in time
## (depth_for, never clamped); every non-linearity lives in scale_at / norm_at / point, so a
## note whose time equals the visual time sits exactly on hit_point(lane).

const VP := Vector2(960.0, 396.0)
const HIT_Y := 930.0
const LANE_SPREAD := 210.0
const FAR_SPREAD := 0.35  # lane spread at the far end, as a fraction of LANE_SPREAD
const Z_SCALE := 0.42
const APPROACH_BASE := 1.5
const D_MIN := -0.15
const D_FAR := 1.0
const PERSPECTIVE := 0.70
const NOTE_FADE_START := 0.85  # depth where gems start fading out toward the far end
const LINE_FADE_START := 0.45  # depth where lane lines start fading out
const TRAVEL := HIT_Y - VP.y


static func lane_f(lane: int) -> float:
	return float(lane) - 1.5


## Seconds from the far end of the cable to the hit line. Speed is clamped (no divide by zero).
static func approach_for(scroll_speed: float) -> float:
	return APPROACH_BASE / maxf(scroll_speed, 0.1)


## Linear depth: 0 at the line, 1 at the far end, negative once past the line. Never clamped.
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
	var x := VP.x + f * LANE_SPREAD * (FAR_SPREAD + (1.0 - FAR_SPREAD) * n)
	var y := VP.y + TRAVEL * n
	return Vector2(x, y)


## Dictionary form for tests and tools: {pos, s, n}.
static func project(f: float, d: float) -> Dictionary:
	return {"pos": point(f, d), "s": scale_at(d), "n": norm_at(d)}


static func hit_point(lane: int) -> Vector2:
	return point(lane_f(lane), 0.0)


## End points of the flat hit line, f = -2.1 and +2.1 at d = 0 (same y).
static func line_points() -> PackedVector2Array:
	return PackedVector2Array([point(-2.1, 0.0), point(2.1, 0.0)])


static func note_radius(s: float) -> float:
	return 36.0 * s + 5.0


## Gem opacity multiplier: 1.0 near the line, 0.0 at the far end (D-02).
static func note_fade(d: float) -> float:
	return 1.0 - smoothstep(NOTE_FADE_START, D_FAR, d)


## Lane-line opacity multiplier: 1.0 near the line, 0.0 at the far end (D-04).
static func line_fade(d: float) -> float:
	return 1.0 - smoothstep(LINE_FADE_START, D_FAR, d)
