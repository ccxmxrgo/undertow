extends GdUnitTestSuite
## 04-01 Task 2: ClockSync, the min-RTT median offset estimator (D-06, RESEARCH Pattern 3).
## host_ticks = client_ticks + offset. All ticks are passed in (no Time reads).

const TRUE_OFFSET := 2_000_000
const ONE_WAY := 20_000


## One NTP-style exchange: client sends at c0, the host stamps h on arrival (out leg = ONE_WAY),
## the reply takes ONE_WAY + extra (asymmetric: the jitter is on the return leg only).
func _exchange(cs: ClockSync, c0: int, extra: int) -> void:
	var h := c0 + ONE_WAY + TRUE_OFFSET
	var c1 := c0 + ONE_WAY + ONE_WAY + extra
	cs.add(c0, h, c1)


## Realistic queueing: about a quarter of packets see (almost) no queue, the rest 0-60 ms.
func _mixed_extra(rng: RandomNumberGenerator) -> int:
	if rng.randf() < 0.25:
		return rng.randi_range(0, 2_000)
	return rng.randi_range(0, 60_000)


func test_empty_estimator() -> void:
	var cs := ClockSync.new()
	assert_int(cs.offset_us()).is_equal(0)
	assert_bool(cs.is_synced()).is_false()
	assert_int(cs.sample_count()).is_equal(0)
	assert_int(cs.rtt_p50_us()).is_equal(0)
	assert_int(cs.rtt_p90_us()).is_equal(0)


func test_rejects_negative_and_huge_rtt() -> void:
	var cs := ClockSync.new()
	cs.add(1000, 5000, 999)
	cs.add(0, 5000, 2_000_001)
	assert_int(cs.sample_count()).is_equal(0)
	cs.add(0, 5000, 2_000_000)
	assert_int(cs.sample_count()).is_equal(1)


func test_keeps_last_32_and_syncs_at_5() -> void:
	var cs := ClockSync.new()
	for i in 4:
		_exchange(cs, i * 50_000, 0)
	assert_bool(cs.is_synced()).is_false()
	_exchange(cs, 4 * 50_000, 0)
	assert_bool(cs.is_synced()).is_true()
	for i in 40:
		_exchange(cs, (5 + i) * 50_000, 1000)
	assert_int(cs.sample_count()).is_equal(ClockSync.MAX_SAMPLES)


func test_exact_without_jitter() -> void:
	var cs := ClockSync.new()
	for i in 8:
		_exchange(cs, 1_000_000 + i * 50_000, 0)
	assert_int(cs.offset_us()).is_equal(TRUE_OFFSET)
	assert_int(cs.rtt_p50_us()).is_equal(2 * ONE_WAY)


func test_recovers_offset_within_2ms_with_asymmetric_jitter() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var cs := ClockSync.new()
		for i in 32:
			_exchange(cs, 5_000_000 + i * 50_000, _mixed_extra(rng))
		assert_int(absi(cs.offset_us() - TRUE_OFFSET)).override_failure_message(
			"seed %d: offset %d" % [seed_value, cs.offset_us()]).is_less_equal(2_000)
		# A naive mean over all samples is far worse (the bias is extra/2 on average).
		assert_bool(cs.is_synced()).is_true()


## Pure uniform 0-60 ms return-leg jitter: the estimator error is half the queueing of the
## middle of the 5 fastest samples (about 2.7 ms expected); it stays well bounded.
func test_uniform_return_jitter_is_bounded() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cs := ClockSync.new()
	for i in 32:
		_exchange(cs, i * 50_000, rng.randi_range(0, 60_000))
	assert_int(absi(cs.offset_us() - TRUE_OFFSET)).is_less_equal(8_000)
	# The estimate is biased low (host appears behind), never above the truth.
	assert_int(cs.offset_us()).is_less_equal(TRUE_OFFSET)


func test_rtt_percentiles() -> void:
	var cs := ClockSync.new()
	for i in 10:
		cs.add(0, 0, (i + 1) * 10_000)  # rtts 10..100 ms
	assert_int(cs.rtt_p50_us()).is_equal(50_000)
	assert_int(cs.rtt_p90_us()).is_equal(90_000)


func test_reset() -> void:
	var cs := ClockSync.new()
	for i in 6:
		_exchange(cs, i * 1000, 0)
	cs.reset()
	assert_int(cs.sample_count()).is_equal(0)
	assert_bool(cs.is_synced()).is_false()
	assert_int(cs.offset_us()).is_equal(0)
