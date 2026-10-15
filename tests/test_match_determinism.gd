extends GdUnitTestSuite
## 03-07 Task 2 (RESEARCH Pitfall 6, T-03-19): a seeded match with bots gives identical event logs
## whether the harness is stepped at 30, 144 or 1000 fps.


func _run(fps: float, seed: int = 11) -> Dictionary:
	return MatchHarness.run(TestCharts.hand_chart(1000), {"human": "autoplay",
		"bots": ["veteran", "veteran", "veteran"], "seed": seed, "fps": fps})


func test_logs_identical_at_30_144_1000_fps() -> void:
	var a := _run(30.0)
	var b := _run(144.0)
	var c := _run(1000.0)
	var sa := var_to_str(a["event_log"])
	assert_int(a["event_log"].size()).is_greater(100)
	assert_str(var_to_str(b["event_log"])).is_equal(sa)
	assert_str(var_to_str(c["event_log"])).is_equal(sa)


func test_match_ends_with_match_end_and_has_real_traffic() -> void:
	var r := _run(60.0)
	var log: Array = r["event_log"]
	assert_str(log[-1]["type"]).is_equal(GameEvent.MATCH_END)
	assert_int(r["standings"].size()).is_equal(4)
	var types := {}
	for e in log:
		types[e["type"]] = true
	assert_bool(types.has(GameEvent.REWARD_EARNED)).is_true()
	assert_bool(types.has(GameEvent.STATUS)).is_true()
	assert_float(r["duration_s"]).is_greater(50.0)
	for k in ["event_log", "standings", "meter_rewards", "fired", "landed", "reflected",
			"duration_s", "threshold", "stats"]:
		assert_bool(r.has(k)).override_failure_message("missing " + k).is_true()
	# The autoplay human never misses a base note.
	assert_int(r["stats"][0]["miss"]).is_equal(0)


func test_different_seed_changes_the_match() -> void:
	var a := _run(60.0, 11)
	var b := _run(60.0, 12)
	assert_str(var_to_str(a["event_log"])).is_not_equal(var_to_str(b["event_log"]))


func test_fps_is_clamped() -> void:
	var r := MatchHarness.run(TestCharts.short_chart(1000), {"human": "autoplay", "bots": ["rookie"],
		"seed": 3, "fps": 1.0e9})
	assert_str(r["event_log"][-1]["type"]).is_equal(GameEvent.MATCH_END)
