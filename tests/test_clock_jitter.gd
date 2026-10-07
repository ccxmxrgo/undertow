extends GdUnitTestSuite
## Frame-rate independence of the ClockModel filter (playtest gap 4, D-30). The measured audio
## target is truth + 10.67 ms mix-chunk noise (std 3.19 ms, max 15.6 ms); song_time must stay within
## 2 ms (p99) of truth at 30/60/144/240 fps, never decrease, and absorb the 13 ms handoff offset.

const RATES := [30, 60, 144, 240]
const CHUNK_S := 0.010667
const NOISE_STD := 0.0032
const OUTLIER_S := 0.012
const LIMIT := 0.002
const WARMUP_S := 1.0
const DURATION_S := 60.0


## Returns {errors: Array[float] (abs, post warm-up), backwards: int, max_advance_excess: float}.
func _simulate(fps: int, seed_value: int, start_offset_s: float, noise: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var clock := ClockModel.new()
	clock.reset(0, start_offset_s)
	var now := 0
	var prev_song := start_offset_s
	var chunk_noise := 0.0
	var next_chunk := 0.0
	var errors: Array[float] = []
	var backwards := 0
	var worst_excess := 0.0
	var nominal := 1.0 / fps
	while now < int(DURATION_S * 1000000.0):
		var dt := nominal * rng.randf_range(0.8, 1.2)
		now += int(round(dt * 1000000.0))
		var truth := now / 1000000.0
		var target := truth
		if noise:
			while truth >= next_chunk:
				chunk_noise = rng.randfn(0.0, NOISE_STD)
				next_chunk += CHUNK_S
			target += chunk_noise
			if rng.randi_range(0, 499) == 0:
				target += OUTLIER_S if rng.randf() < 0.5 else -OUTLIER_S
		var st := clock.update(now, target, true)
		if st < prev_song:
			backwards += 1
		worst_excess = maxf(worst_excess, (st - prev_song) - dt)
		prev_song = st
		if truth >= WARMUP_S:
			errors.append(absf(st - truth))
	return {"errors": errors, "backwards": backwards, "excess": worst_excess}


func _p99(values: Array[float]) -> float:
	var s := values.duplicate()
	s.sort()
	return s[int(floor(0.99 * s.size()))]


func test_p99_error_within_2ms_at_all_frame_rates() -> void:
	for fps in RATES:
		var r := _simulate(fps, 1000 + fps, 0.0, true)
		var p99 := _p99(r["errors"])
		assert_float(p99).override_failure_message("fps %d p99 %.3f ms" % [fps, p99 * 1000.0]).is_less_equal(0.002)
		assert_int(r["backwards"]).is_equal(0)


func test_song_time_advance_per_frame_is_bounded() -> void:
	for fps in RATES:
		var r := _simulate(fps, 2000 + fps, 0.0, true)
		assert_float(r["excess"]).override_failure_message(
			"fps %d max advance beyond dt %.3f ms" % [fps, r["excess"] * 1000.0]).is_less_equal(0.002)


func test_handoff_offset_of_13ms_absorbed_within_1s_without_snap() -> void:
	for fps in RATES:
		# song_time 13 ms ahead of an otherwise exact audio target.
		var clock := ClockModel.new()
		clock.reset(0, 0.013)
		var now := 0
		var prev := 0.013
		for k in range(1, fps + 1):
			now = int(round(k * 1000000.0 / fps))
			var st := clock.update(now, now / 1000000.0, true)
			assert_float(st).is_greater_equal(prev)
			assert_float(st - prev).override_failure_message("snap/jump at fps %d" % fps).is_less(
				1.0 / fps + 0.001)
			prev = st
		assert_float(absf(prev - now / 1000000.0)).override_failure_message(
			"fps %d residual %.3f ms" % [fps, absf(prev - now / 1000000.0) * 1000.0]).is_less(LIMIT)


func test_constant_error_decay_is_frame_rate_independent() -> void:
	var residuals: Array[float] = []
	for fps in RATES:
		var clock := ClockModel.new()
		clock.reset(0, -0.005)  # 5 ms behind a perfect target
		var now := 0
		var st := 0.0
		for k in range(1, fps + 1):
			now = int(round(k * 1000000.0 / fps))
			st = clock.update(now, now / 1000000.0, true)
		residuals.append(absf(st - now / 1000000.0))
	for r in residuals:
		assert_float(r * 1000.0).is_equal_approx(residuals[0] * 1000.0, 0.01)
