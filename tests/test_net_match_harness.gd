extends GdUnitTestSuite
## 04-09 (NET-04, NET-05, TORP-04 online, D-08, D-09, D-16, D-24 layer 2): whole online matches
## over MemTransport through the real codec, HostInputQueue, RemoteReferee and net channels.
## hand_chart: ~59 s, 100 BPM then 140 BPM at bar 16 (beats 0.6 s / 0.4286 s).

const PIN_RTT := 0.1

static var _hand: ChartData


static func _chart() -> ChartData:
	if _hand == null:
		_hand = TestCharts.hand_chart(1000)
	return _hand


static func _opts(extra: Dictionary) -> Dictionary:
	var o := {"clients": 3, "seed": 7, "flight_beats": 2, "d_s": 0.10, "fire_every_beats": 8,
		"fire_from_beat": 16, "margin_rtt_p90_s": PIN_RTT}
	o.merge(extra, true)
	return o


## The four NET-04 link profiles (worst one-way 0.07 s + frames < D 0.10).
static func _profiles() -> Array:
	return [
		{"latency_s": 0.0},
		{"latency_s": 0.05},
		{"latency_s": 0.04, "jitter_s": 0.03},
		{"latency_s": 0.04, "jitter_s": 0.03, "loss": 0.02},
	]


static func _types(log: Array, type: String) -> Array:
	return log.filter(func(e: Dictionary) -> bool: return e["type"] == type)


static func _beat_len_at(t: float) -> float:
	var tm: Array = _chart().tempo_map
	var b := BeatClock.beat_at(t, tm)
	return BeatClock.time_at_beat(b + 1.0, tm) - BeatClock.time_at_beat(b, tm)


## Minimum warning in beats over the telegraph rows: (arrive_t - receipt) / beat at arrive.
static func _min_warning_beats(rows: Array) -> float:
	var m := INF
	for r in rows:
		m = minf(m, (float(r["arrive_t"]) - float(r["target_receipt_t"]))
			/ _beat_len_at(float(r["arrive_t"])))
	return m


# --- 1 + 2: determinism across links, fan-out ---------------------------------------------------

func test_host_log_identical_across_link_profiles_and_fan_out_exact() -> void:
	for sd in [7, 2]:
		_assert_identical_across_profiles(sd)


## The match seed also seeds the MemTransport jitter/loss RNG.
func _assert_identical_across_profiles(sd: int) -> void:
	var base: Array = []
	var i := 0
	for p in _profiles():
		var r := NetMatchHarness.run(_chart(), _opts(p.merged({"seed": sd})))
		var log: Array = r["host_log"]
		assert_int(int(r["late_inputs"])).override_failure_message(
			"late inputs in profile %d" % i).is_equal(0)
		if i == 0:
			base = log
			assert_int(log.size()).is_greater(200)
			assert_int(_types(log, GameEvent.TORPEDO_LAUNCH).size()).is_greater(0)
			assert_int(_types(log, GameEvent.LANDED).size()).is_greater(0)
			assert_str(log[-1]["type"]).is_equal(GameEvent.MATCH_END)
		else:
			assert_bool(log == base).override_failure_message(
				"host log differs in profile %d (%s)" % [i, _first_diff(base, log)]).is_true()
		# Fan-out: every client got every host event exactly once, in order.
		var logs: Dictionary = r["client_logs"]
		assert_int(logs.size()).is_equal(3)
		for s in logs:
			assert_bool(logs[s] == log).override_failure_message(
				"client %d log != host log in profile %d" % [s, i]).is_true()
		i += 1


func test_client_batches_seq_contiguous() -> void:
	var h := NetMatchHarness.new(_chart(), _opts(_profiles()[3]))
	h.run_to(h.end_t)
	h.finish()
	for s in h.client_channels:
		var ch: NetClientChannel = h.client_channels[s]
		# Every batch applied exactly once and in order: last_seq equals the batches sent and
		# nothing is left buffered or rejected.
		assert_int(ch.rejected_events).is_equal(0)
		assert_int(ch.received_log.size()).is_equal(h.host_channel.broadcast_log.size())
		assert_int(ch.last_seq).is_greater(0)
		assert_int(ch._buffer.size()).is_equal(0)


func _first_diff(a: Array, b: Array) -> String:
	for k in range(mini(a.size(), b.size())):
		if a[k] != b[k]:
			return "index %d: %s vs %s" % [k, str(a[k]), str(b[k])]
	return "sizes %d vs %d" % [a.size(), b.size()]


# --- 3: late inputs ------------------------------------------------------------------------------

func test_latency_above_horizon_clamps_late_inputs_and_time_never_decreases() -> void:
	var r := NetMatchHarness.run(_chart(), _opts({"latency_s": 0.15, "d_s": 0.06,
		"margin_rtt_p90_s": -1.0}))
	assert_int(int(r["late_inputs"])).is_greater(0)
	var log: Array = r["host_log"]
	var prev := -INF
	for e in log:
		assert_float(float(e["t"])).is_greater_equal(prev)
		prev = float(e["t"])
	assert_str(log[-1]["type"]).is_equal(GameEvent.MATCH_END)


# --- 4: telegraph (TORP-04 online, D-08) ----------------------------------------------------------

func test_two_beat_flight_warns_at_least_one_beat_one_beat_flight_does_not() -> void:
	var link := {"d_s": 0.2, "latency_s": 0.15, "margin_rtt_p90_s": -1.0}
	var r2 := NetMatchHarness.run(_chart(), _opts(link.merged({"flight_beats": 2})))
	var rows: Array = r2["telegraph"]
	assert_int(rows.size()).is_greater(0)
	for row in rows:
		var bound: float = float(row["arrive_t"]) - _beat_len_at(float(row["arrive_t"])) + 1e-6
		assert_float(float(row["target_receipt_t"])).override_failure_message(
			"telegraph < 1 beat: %s" % str(row)).is_less_equal(bound)
	var r1 := NetMatchHarness.run(_chart(), _opts(link.merged({"flight_beats": 1})))
	var rows1: Array = r1["telegraph"]
	assert_int(rows1.size()).is_greater(0)
	var fails := 0
	for row in rows1:
		if float(row["target_receipt_t"]) > float(row["arrive_t"]) \
				- _beat_len_at(float(row["arrive_t"])) + 1e-6:
			fails += 1
	assert_int(fails).is_greater(0)
	print("TELEGRAPH flight2 rows=%d min_warning_beats=%.3f | flight1 rows=%d fails=%d min=%.3f"
		% [rows.size(), _min_warning_beats(rows), rows1.size(), fails, _min_warning_beats(rows1)])


# --- 5: overlay margin (D-09: no pop-in) --------------------------------------------------------

## Link-derived margin (margin_rtt_p90_s -1). The link is the RESEARCH "DERP relay" class with
## jitter (L 0.07 +- 0.02) and D from the D-05 formula (L_p90 + 53 ms = 0.143 s), so the D-09
## margin D + L_p90 + 50 ms = 0.283 s stays under its cap. The D-05 cap link (D 0.2, L 0.15) is
## covered by the WR-01 test below (the old 0.3 s cap measured a 50 ms pop-in there).
func test_overlay_notes_never_start_before_landed_receipt_plus_approach() -> void:
	var total := 0
	var slack := INF
	for sd in [1, 2, 3, 7]:
		var r := NetMatchHarness.run(_chart(), _opts({"seed": sd, "d_s": 0.143,
			"latency_s": 0.07, "jitter_s": 0.02, "margin_rtt_p90_s": -1.0}))
		var rows: Array = r["overlay"]
		total += rows.size()
		for row in rows:
			var visible: float = float(row["active_start"]) - float(row["approach_local"])
			slack = minf(slack, visible - float(row["receipt_t"]))
			assert_float(visible).override_failure_message("overlay pop-in: %s" % str(row)) \
				.is_greater_equal(float(row["receipt_t"]) - 1e-6)
	assert_int(total).is_greater(5)
	print("OVERLAY rows=%d min_slack_s=%.4f" % [total, slack])


## WR-01 (F-1): RTT p90 300 ms at the D-05 cap (D 0.2, L 0.15, 60 fps clients). The margin
## D + L + 50 ms = 0.4 s (cap 0.5 s) covers D + L + 2 frames, so no overlay note starts before
## its LANDED reached the target.
func test_overlay_no_pop_in_at_rtt_p90_300ms() -> void:
	var total := 0
	var slack := INF
	for sd in [1, 2, 3, 7]:
		var r := NetMatchHarness.run(_chart(), _opts({"seed": sd, "d_s": NetProtocol.D_MAX_S,
			"latency_s": 0.15, "fps": 60.0, "margin_rtt_p90_s": 0.3}))
		var rows: Array = r["overlay"]
		total += rows.size()
		for row in rows:
			var visible: float = float(row["active_start"]) - float(row["approach_local"])
			slack = minf(slack, visible - float(row["receipt_t"]))
			assert_float(visible).override_failure_message("overlay pop-in: %s" % str(row)) \
				.is_greater_equal(float(row["receipt_t"]) - 1e-6)
	assert_int(total).is_greater(5)
	print("OVERLAY300 rows=%d min_slack_s=%.4f" % [total, slack])


# --- 6: disconnect (NET-05, D-16) ---------------------------------------------------------------

func test_dropped_client_imploded_then_left_match_runs_to_end() -> void:
	var r := NetMatchHarness.run(_chart(), _opts({"latency_s": 0.03, "drop_seat": 2,
		"drop_at_s": 20.0}))
	var log: Array = r["host_log"]
	var imp := -1
	var left := -1
	for k in range(log.size()):
		var e: Dictionary = log[k]
		if e["type"] == GameEvent.IMPLODED and int(e["seat"]) == 2 and imp == -1:
			imp = k
		if e["type"] == GameEvent.PLAYER_LEFT and int(e["seat"]) == 2:
			left = k
	assert_int(imp).is_greater_equal(0)
	assert_int(left).is_greater(imp)
	assert_float(float(log[left]["t"])).is_equal(float(log[imp]["t"]))
	assert_float(float(log[left]["t"])).is_greater_equal(20.0 - 0.10)
	assert_str(log[left]["reason"]).is_equal("disconnected")
	assert_str(log[-1]["type"]).is_equal(GameEvent.MATCH_END)
	assert_int(r["standings"].size()).is_equal(4)
	var logs: Dictionary = r["client_logs"]
	assert_bool(logs[1] == log).is_true()
	assert_bool(logs[3] == log).is_true()
	var c2: Array = logs[2]
	assert_int(c2.size()).is_less(log.size())
	assert_bool(c2 == log.slice(0, c2.size())).is_true()


# --- 7: DUEL_LIVE ---------------------------------------------------------------------------------

func test_duel_live_only_inside_the_duel_and_mirrored_on_clients() -> void:
	var c := TestCharts.click_chart(120.0, 80, 1000)
	c.solos.append({"start": 20.0, "end": 29.5, "note_count": 20})
	var h := NetMatchHarness.new(c, {"clients": 2, "seed": 3, "d_s": 0.08, "latency_s": 0.02,
		"fire_every_beats": 0})
	h.run_to(25.0)
	var mid_checked := 0
	for s in h.referees:
		var ref: RemoteReferee = h.referees[s]
		var got: Array = _types(h.client_channels[s].received_log, GameEvent.DUEL_LIVE)
		assert_int(got.size()).is_greater(0)
		var pct: Dictionary = got[-1]["pct"]
		for seat in pct:
			assert_float(ref.duel_live(seat)).is_equal(float(pct[seat]))
			mid_checked += 1
		assert_int(ref.duel_active()).is_equal(0)
	assert_int(mid_checked).is_greater(0)
	h.run_to(h.end_t)
	h.finish()
	var r := h.result()
	var log: Array = r["host_log"]
	var start := -1
	var result := -1
	for k in range(log.size()):
		if log[k]["type"] == GameEvent.DUEL_START:
			start = k
		elif log[k]["type"] == GameEvent.DUEL_RESULT:
			result = k
	assert_int(start).is_greater_equal(0)
	assert_int(result).is_greater(start)
	var beats := {}
	var live: Array = r["duel_live_events"]
	assert_int(live.size()).is_greater(0)
	for k in range(log.size()):
		var e: Dictionary = log[k]
		if e["type"] != GameEvent.DUEL_LIVE:
			continue
		assert_int(k).is_greater(start)
		assert_int(k).is_less(result)
		var b := int(floor(BeatClock.beat_at(float(e["t"]), c.tempo_map) + 1e-6))
		assert_bool(beats.has(b)).override_failure_message("two DUEL_LIVE in beat %d" % b) \
			.is_false()
		beats[b] = true
	for s in r["client_logs"]:
		assert_bool(r["client_logs"][s] == log).is_true()
	# After DUEL_RESULT the clients clear their live view.
	for s in h.referees:
		assert_int(h.referees[s].duel_active()).is_equal(-1)
