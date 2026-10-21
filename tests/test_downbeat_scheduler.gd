extends GdUnitTestSuite
## DownbeatScheduler (05-02, D-02): one ping per bar, started early with a lead-silence offset
## so the audible onset lands on the downbeat.

const DT := 1.0 / 60.0
const LAT := 0.02
const OFF := 0.01
const MIX := 0.005
const LEAD := 0.15


func _head(t: float) -> float:
	return t + LAT + OFF + MIX


## Expected bars at time >= 0 whose ping window opens before the last simulated head.
func _expected_bars(tm: Array, ts: Array, last_head: float, n: int = 1) -> Array:
	var out: Array = []
	var ordinal := 0
	for e in BeatClock.beats_between(0.0, last_head + LEAD + 1.0, tm, ts):
		if not e["bar"] or float(e["time"]) < 0.0:
			continue
		if float(e["time"]) - last_head < LEAD:
			if ordinal % n == 0:
				out.append(float(e["time"]))
		ordinal += 1
	return out


## Runs frames from t0 to t1 (exclusive). Returns the reconstructed onset of every ping.
func _run(s: DownbeatScheduler, t0: float, t1: float, onsets: Array) -> float:
	var t := t0
	while t < t1:
		var fp := s.tick(t, LAT, OFF, MIX)
		if fp >= 0.0:
			assert_float(fp).is_between(0.0, LEAD)
			onsets.append(_head(t) + (LEAD - fp))
		t += DT
	return t - DT


func _assert_onsets(onsets: Array, expected: Array) -> void:
	assert_int(onsets.size()).is_equal(expected.size())
	for i in mini(onsets.size(), expected.size()):
		assert_float(float(onsets[i])).is_equal_approx(float(expected[i]), 0.001)


func test_four_four_120_bpm() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var ts: Array = [{"time": 0.0, "num": 4, "den": 4}]
	var s := DownbeatScheduler.new(tm, ts, LEAD)
	var onsets: Array = []
	_run(s, -1.0, 19.5, onsets)
	assert_int(s.fired_count()).is_equal(10)
	_assert_onsets(onsets, [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0])


func test_seven_eight() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var ts: Array = [{"time": 0.0, "num": 7, "den": 8}]
	var s := DownbeatScheduler.new(tm, ts, LEAD)
	var onsets: Array = []
	var last := _run(s, -1.0, 20.0, onsets)
	var expected := _expected_bars(tm, ts, _head(last))
	assert_int(expected.size()).is_equal(12)
	assert_float(float(expected[1])).is_equal_approx(1.75, 1e-6)
	_assert_onsets(onsets, expected)
	assert_int(s.fired_count()).is_equal(12)


func test_tempo_change() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}, {"time": 8.0, "bpm": 90.0}]
	var ts: Array = []
	var s := DownbeatScheduler.new(tm, ts, LEAD)
	var onsets: Array = []
	var last := _run(s, -1.0, 20.0, onsets)
	var expected := _expected_bars(tm, ts, _head(last))
	# 0, 2, 4, 6, 8, then 90 bpm bars of 8/3 s.
	assert_float(float(expected[4])).is_equal_approx(8.0, 1e-6)
	assert_float(float(expected[5])).is_equal_approx(8.0 + 8.0 / 3.0, 1e-6)
	_assert_onsets(onsets, expected)
	for i in range(1, onsets.size()):
		assert_float(float(onsets[i]) - float(onsets[i - 1])).is_greater(1.9)


func test_count_in_never_pings_negative_bars() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var s := DownbeatScheduler.new(tm, [], LEAD)
	var onsets: Array = []
	_run(s, -3.0, 0.5, onsets)
	_assert_onsets(onsets, [0.0])
	assert_int(s.fired_count()).is_equal(1)


func test_late_frame_skips_bar() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var s := DownbeatScheduler.new(tm, [], LEAD)
	var onsets: Array = []
	_run(s, -1.0, 1.0, onsets)  # bar 0 pinged
	_assert_onsets(onsets, [0.0])
	# Park just before the bar-2 ping window opens, then jump 0.2 s past it.
	var before := 2.0 - LEAD - (LAT + OFF + MIX) - 0.01
	assert_float(s.tick(before, LAT, OFF, MIX)).is_equal(-1.0)
	var after := before + 0.2
	assert_float(2.0 - _head(after)).is_less(-DownbeatScheduler.LATE_SKIP_SEC)
	assert_float(s.tick(after, LAT, OFF, MIX)).is_equal(-1.0)
	assert_float(s.next_bar_time()).is_equal_approx(4.0, 1e-6)
	_run(s, after + DT, 4.5, onsets)
	_assert_onsets(onsets, [0.0, 4.0])
	assert_int(s.fired_count()).is_equal(2)


func test_pause_resume_never_double_pings() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var s := DownbeatScheduler.new(tm, [], LEAD)
	var onsets: Array = []
	var last := _run(s, -1.0, 5.9, onsets)
	# Paused: the node does not tick. 60 frames later it resets at the held song time.
	s.reset(last, LAT, OFF, MIX)
	s.reset(last, LAT, OFF, MIX)
	_run(s, last + DT, 11.5, onsets)
	_assert_onsets(onsets, [0.0, 2.0, 4.0, 6.0, 8.0, 10.0])
	# Seek back: bars already fired are never re-pinged.
	s.reset(3.0, LAT, OFF, MIX)
	_run(s, 3.0, 11.5, onsets)
	assert_int(onsets.size()).is_equal(6)
	# Seek forward: later bars still ping exactly once.
	s.reset(15.0, LAT, OFF, MIX)
	_run(s, 15.0, 18.5, onsets)
	_assert_onsets(onsets, [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 16.0, 18.0])


func test_reset_at_bar_keeps_slightly_late_bar() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var s := DownbeatScheduler.new(tm, [], LEAD)
	s.reset(2.0 - (LAT + OFF + MIX) + 0.01, LAT, OFF, MIX)  # head 10 ms past bar 2
	assert_float(s.next_bar_time()).is_equal_approx(2.0, 1e-6)
	s.reset(2.0 - (LAT + OFF + MIX) + 0.05, LAT, OFF, MIX)  # head 50 ms past: skipped
	assert_float(s.next_bar_time()).is_equal_approx(4.0, 1e-6)


func test_every_second_bar_stable_across_reset() -> void:
	var tm: Array = [{"time": 0.0, "bpm": 120.0}]
	var s := DownbeatScheduler.new(tm, [], LEAD)
	s.every_n_bars = 2
	var onsets: Array = []
	var last := _run(s, -1.0, 5.0, onsets)
	s.reset(last, LAT, OFF, MIX)
	_run(s, last + DT, 13.0, onsets)
	s.reset(13.0, LAT, OFF, MIX)
	_run(s, 13.0, 17.0, onsets)
	_assert_onsets(onsets, [0.0, 4.0, 8.0, 12.0, 16.0])


func test_empty_tempo_map_defaults_to_120_four_four() -> void:
	var s := DownbeatScheduler.new([], [], LEAD)
	var onsets: Array = []
	_run(s, -1.0, 7.5, onsets)
	_assert_onsets(onsets, [0.0, 2.0, 4.0, 6.0])


func test_non_finite_song_time() -> void:
	var s := DownbeatScheduler.new([], [], LEAD)
	assert_float(s.tick(NAN, LAT, OFF, MIX)).is_equal(-1.0)
	assert_float(s.tick(INF, LAT, OFF, MIX)).is_equal(-1.0)
	assert_float(s.tick(-0.1, NAN, OFF, MIX)).is_equal(-1.0)
	assert_int(s.fired_count()).is_equal(0)
	assert_float(s.next_bar_time()).is_equal_approx(0.0, 1e-9)
	s.reset(NAN)
	assert_float(s.next_bar_time()).is_equal_approx(0.0, 1e-9)


func test_contract_constants() -> void:
	assert_float(DownbeatScheduler.LATE_SKIP_SEC).is_equal_approx(0.03, 1e-9)
	assert_float(DownbeatScheduler.WINDOW_SEC).is_equal_approx(4.0, 1e-9)
	var s := DownbeatScheduler.new([], [])
	assert_int(s.every_n_bars).is_equal(1)
	# Default lead 0.15: a ping started at r = 0.1 begins 50 ms into the sample.
	var t := 2.0 - 0.1 - (LAT + OFF + MIX)
	s.reset(t - 0.5, LAT, OFF, MIX)
	assert_float(s.tick(t, LAT, OFF, MIX)).is_equal_approx(0.05, 1e-6)
