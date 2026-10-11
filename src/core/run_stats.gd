class_name RunStats
extends RefCounted
## Pure run statistics for the HUD and results (D-08, D-09). Outside the timing core.
## Not ScoreStore.accuracy (that one is a hit rate); this is the weighted D-08 accuracy.

## Histogram bin width, count and half-range in ms: 40 bins of 5 ms covering -100..+100. The range
## follows the Good window (D-09, adapted in 02.2-26 to the user-approved G1 windows 50/100 ms).
const BIN_MS := 5
const BIN_COUNT := 40
const RANGE_MS := 100
## |mean| below this many ms reads as "Right on time".
const ON_TIME_MS := 3

const _GRADE_RANKS := {"S": 5, "A": 4, "B": 3, "C": 2, "D": 1}


## (Perfect x 100 + Good x 50) / judged notes. -1.0 when nothing was judged.
static func accuracy(p: int, g: int, m: int) -> float:
	var n := p + g + m
	if n <= 0:
		return -1.0
	return (float(p) * 100.0 + float(g) * 50.0) / float(n)


## "98.4%" with one decimal; "--.-%" when nothing was judged (acc < 0).
static func accuracy_text(acc: float) -> String:
	if acc < 0.0 or not is_finite(acc):
		return "--.-%"
	return "%.1f%%" % acc


## S >= 98 with no miss, A >= 93, B >= 85, C >= 75, else D; "-" when nothing was judged.
static func grade(acc: float, misses: int) -> String:
	if acc < 0.0 or not is_finite(acc):
		return "-"
	if acc >= 98.0 and misses == 0:
		return "S"
	if acc >= 93.0:
		return "A"
	if acc >= 85.0:
		return "B"
	if acc >= 75.0:
		return "C"
	return "D"


## S 5 .. D 1; "-", "" or anything unknown 0 (for best-grade comparisons).
static func grade_rank(g: String) -> int:
	return int(_GRADE_RANKS.get(g, 0))


## BIN_COUNT bins of 5 ms from -RANGE_MS to +RANGE_MS (early left). Bin i covers
## [-RANGE_MS + 5i, -RANGE_MS + 5 + 5i); exactly +RANGE_MS and anything beyond the range clamp into the end bins. Computed in integer
## microseconds so float noise cannot move a value across a bin edge.
static func histogram(offsets_s: PackedFloat32Array) -> PackedInt32Array:
	var bins := PackedInt32Array()
	bins.resize(BIN_COUNT)
	bins.fill(0)
	var range_us := RANGE_MS * 1000
	var bin_us := BIN_MS * 1000
	for e in offsets_s:
		if not is_finite(e):
			continue
		var us := int(clampf(roundf(e * 1000000.0), -1.0e9, 1.0e9))
		var shifted := us + range_us
		var i := 0 if shifted < 0 else shifted / bin_us
		bins[clampi(i, 0, BIN_COUNT - 1)] += 1
	return bins


## Rounded mean offset in ms (negative = early); 0 when empty.
static func mean_offset_ms(offsets_s: PackedFloat32Array) -> int:
	var n := 0
	var sum := 0.0
	for e in offsets_s:
		if is_finite(e):
			sum += e
			n += 1
	if n == 0:
		return 0
	return int(roundf(sum / float(n) * 1000.0))


## "Average 12 ms early" / "Average 8 ms late" / "Right on time (average 2 ms)".
static func summary_text(mean_ms: int) -> String:
	if absi(mean_ms) < ON_TIME_MS:
		return "Right on time (average %d ms)" % mean_ms
	if mean_ms < 0:
		return "Average %d ms early" % -mean_ms
	return "Average %d ms late" % mean_ms
