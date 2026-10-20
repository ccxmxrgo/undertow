extends GdUnitTestSuite
## 04-17: NetAutotest pure helpers (arg parsing, canonical log digest, report comparison).


func _args(a: Array) -> PackedStringArray:
	return PackedStringArray(a)


func test_parse_args_valid() -> void:
	var c := NetAutotest.parse_args(_args(["--net-autotest=client", "--net-address=127.0.0.1",
		"--net-port=47591", "--net-players=3", "--net-seconds=12", "--net-diff=hard",
		"--net-report=build/net_smoke/full/c1.json", "--net-name=C1", "--net-timeout=90",
		"--net-seed=5", "--mute", "--net-profile=2", "--no-boot-scan"]))
	assert_bool(c.ok).is_true()
	assert_str(c.role).is_equal("client")
	assert_str(c.address).is_equal("127.0.0.1")
	assert_int(c.port).is_equal(47591)
	assert_int(c.players).is_equal(3)
	assert_float(c.seconds).is_equal(12.0)
	assert_str(c.diff).is_equal("hard")
	assert_str(c.name).is_equal("C1")
	assert_float(c.timeout).is_equal(90.0)
	assert_int(c.seed).is_equal(5)
	assert_bool(c.mute).is_true()
	assert_str(c.report).is_equal(
		ProjectSettings.globalize_path("res://build/net_smoke/full/c1.json"))


func test_parse_args_defaults() -> void:
	var h := NetAutotest.parse_args(_args(["--net-autotest=host"]))
	assert_bool(h.ok).is_true()
	assert_str(h.name).is_equal("HOST")
	assert_int(h.port).is_equal(47474)
	assert_int(h.players).is_equal(4)
	assert_float(h.seconds).is_equal(30.0)
	assert_str(h.diff).is_equal("easy")
	assert_float(h.timeout).is_equal(120.0)
	assert_bool(h.mute).is_false()
	assert_str(h.address).is_equal("127.0.0.1")
	assert_str(h.report).is_equal(ProjectSettings.globalize_path("res://build/net_smoke/host.json"))
	var c := NetAutotest.parse_args(_args(["--net-autotest=client", "--net-profile=4"]))
	assert_bool(c.ok).is_true()
	assert_str(c.name).is_equal("C3")
	var c2 := NetAutotest.parse_args(_args(["--net-autotest=client"]))
	assert_str(c2.name).is_equal("CLIENT")


func test_parse_args_rejects_report_paths() -> void:
	for p in ["../x.json", "C:/Windows/x.txt", "build/net_smoke/../../x.json", "user://x.json",
			"res://x.json", "src/x.json", "build/net_smoke/x.cfg", "C:/a/../b.json", ""]:
		var r := NetAutotest.parse_args(_args(["--net-autotest=host", "--net-report=" + p]))
		assert_bool(r.ok).override_failure_message("accepted %s" % p).is_false()
		assert_str(r.error).is_equal("report")
	# An explicit absolute .json path is allowed.
	var ok := NetAutotest.parse_args(_args(["--net-autotest=host",
		"--net-report=C:/tmp/smoke/host.json"]))
	assert_bool(ok.ok).is_true()
	assert_str(ok.report).is_equal("C:/tmp/smoke/host.json")


func test_parse_args_rejects_bad_values() -> void:
	var cases := [["--net-autotest=host", "--net-players=5"], ["--net-autotest=host",
		"--net-players=1"], ["--net-autotest=host", "--net-players=x"],
		["--net-autotest=boss"], ["--net-port=47474"],
		["--net-autotest=host", "--net-port=80"], ["--net-autotest=host", "--net-diff=insane"],
		["--net-autotest=client", "--net-address=1.2.3.4;rm"],
		["--net-autotest=host", "--net-seconds=0"], ["--net-autotest=host", "--net-timeout=1"]]
	for a: Array in cases:
		var r := NetAutotest.parse_args(_args(a))
		assert_bool(r.ok).override_failure_message("accepted %s" % str(a)).is_false()
	assert_str(NetAutotest.parse_args(_args(["--net-autotest=host", "--net-players=5"])).error) \
		.is_equal("players")
	assert_bool(NetAutotest.has_arg(_args(["--net-autotest=host"]))).is_true()
	assert_bool(NetAutotest.has_arg(_args(["--net-profile=1"]))).is_false()


func _event() -> Dictionary:
	return {"type": GameEvent.STATUS, "t": 12.345678901, "seat": 2, "hull": 87.5,
		"depth": 1234.0, "alive": true, "place": 1, "accuracy": 0.9375}


func test_log_digest_round_trip_and_change() -> void:
	var host_log: Array = [_event(), {"type": GameEvent.PLAYER_LEFT, "t": 3.0, "seat": 3,
		"reason": "disconnected"}]
	var wire: Array = []
	for e: Dictionary in host_log:
		wire.append(bytes_to_var(var_to_bytes(e)))
	var a := NetAutotest.log_digest(host_log)
	assert_str(a).has_length(64)
	assert_str(NetAutotest.log_digest(wire)).is_equal(a)
	var changed: Array = [_event(), host_log[1].duplicate()]
	changed[1]["seat"] = 2
	assert_str(NetAutotest.log_digest(changed)).is_not_equal(a)
	var flt: Array = [_event(), host_log[1]]
	flt[0]["hull"] = 87.25
	assert_str(NetAutotest.log_digest(flt)).is_not_equal(a)
	assert_str(NetAutotest.log_digest([])).is_not_equal(a)


func _rows(n: int, left_seat: int = -1, left := true) -> Array:
	var out: Array = []
	for s in n:
		out.append({"seat": s, "name": "HOST" if s == 0 else "C%d" % s,
			"left": left and s == left_seat})
	return out


func _reports(sha := "abc", spread := 3.0, late := 0) -> Array:
	var out: Array = [{"role": "host", "seat": 0, "name": "HOST", "version": "0.7.0",
		"host_log_sha": sha, "start_unix_ms": 1000.0, "late_inputs": late,
		"results_rows": _rows(4), "error": "", "strike_kicks": 0}]
	for s in [1, 2, 3]:
		out.append({"role": "client", "seat": s, "name": "C%d" % s, "version": "0.7.0",
			"received_sha": sha, "start_unix_ms": 1000.0 + spread * (s / 3.0), "late_inputs": 0,
			"results_rows": _rows(4), "error": ""})
	return out


func test_compare_reports_all_match_passes() -> void:
	var r := NetAutotest.compare_reports(_reports(), {"players": 4})
	assert_bool(r.ok).is_true()
	assert_bool((r.lines as Array).has("[PASS] late inputs 0")).is_true()
	assert_bool((r.lines as Array).has("[PASS] start spread 3.00 ms <= 20")).is_true()


func test_compare_reports_digest_mismatch_fails() -> void:
	var reps := _reports()
	reps[2]["received_sha"] = "abd"
	var r := NetAutotest.compare_reports(reps, {"players": 4})
	assert_bool(r.ok).is_false()


func test_compare_reports_start_spread_fails() -> void:
	assert_bool(NetAutotest.compare_reports(_reports("abc", 35.0), {"players": 4}).ok).is_false()


func test_compare_reports_late_inputs_fail() -> void:
	assert_bool(NetAutotest.compare_reports(_reports("abc", 3.0, 2), {"players": 4}).ok).is_false()


func test_compare_reports_error_strike_and_rows_fail() -> void:
	var reps := _reports()
	reps[1]["error"] = "timeout"
	assert_bool(NetAutotest.compare_reports(reps, {"players": 4}).ok).is_false()
	reps = _reports()
	reps[0]["strike_kicks"] = 1
	assert_bool(NetAutotest.compare_reports(reps, {"players": 4}).ok).is_false()
	reps = _reports()
	reps[3]["results_rows"] = _rows(3)
	assert_bool(NetAutotest.compare_reports(reps, {"players": 4}).ok).is_false()
	reps = _reports()
	reps.remove_at(2)
	assert_bool(NetAutotest.compare_reports(reps, {"players": 4}).ok).is_false()


func test_compare_reports_drop_scenario() -> void:
	var reps := _reports()
	reps.remove_at(3)  # the killed client never wrote a report
	for d: Dictionary in reps:
		d["results_rows"] = _rows(4, 3, true)
	var r := NetAutotest.compare_reports(reps, {"players": 4, "dropped_seat": 3})
	assert_bool(r.ok).override_failure_message(str(r.lines)).is_true()
	assert_bool((r.lines as Array).has("[PASS] seat 3 LEFT")).is_true()
	# By name, with a partial report from the dropped client that must be ignored.
	var partial := reps.duplicate(true)
	partial.append({"role": "client", "seat": 3, "name": "C3", "error": "timeout"})
	assert_bool(NetAutotest.compare_reports(partial, {"players": 4, "dropped_name": "C3"}).ok) \
		.is_true()
	# The seat is not marked LEFT: FAIL.
	for d: Dictionary in reps:
		d["results_rows"] = _rows(4, 3, false)
	assert_bool(NetAutotest.compare_reports(reps, {"players": 4, "dropped_seat": 3}).ok).is_false()
