extends GdUnitTestSuite
## F3 net rows (04-16, 04-UI-SPEC 11.8): NetDebugRows.format exact strings for client, host and
## empty stats, and DebugOverlay showing the five rows only while a session reports an active match.


class FakeSession extends Node:
	var match_spec: Dictionary = {}
	var stats: Dictionary = {}
	var stats_calls := 0

	func pending_match() -> Dictionary:
		return match_spec

	func debug_stats() -> Dictionary:
		stats_calls += 1
		return stats


const CLIENT_STATS := {
	"role": "client", "seat": 2, "state": "playing", "peers": 1, "rtt_p50_ms": 38, "rtt_p90_ms": 52,
	"per_peer": [], "offset_us": -1250, "horizon_ms": 120, "late_inputs": 0, "skew_ms": 1.5,
	"landed_late_last_ms": 0.0, "landed_late_max_ms": 14.5, "rejected_packets": 3, "event_seq": 41,
	"link_weak": false,
}

const HOST_STATS := {
	"role": "host", "seat": 0, "state": "playing", "peers": 3, "rtt_p50_ms": 30, "rtt_p90_ms": 61,
	"per_peer": [
		{"seat": 1, "name": "NEMO", "p90_ms": 44, "skew_ms": 0.5},
		{"seat": 2, "name": "ORCA", "p90_ms": 61, "skew_ms": -2.0},
		{"seat": 3, "name": "KRAKEN", "p90_ms": 12, "skew_ms": 0.0},
	],
	"offset_us": 0, "horizon_ms": 95, "late_inputs": 7, "skew_ms": -2.0, "landed_late_last_ms": 0.0,
	"landed_late_max_ms": 0.0, "rejected_packets": 0, "event_seq": 118,
}


func test_format_client() -> void:
	assert_str(NetDebugRows.format(CLIENT_STATS)).is_equal("\n".join([
		"NET CLIENT  SEAT 2  PEERS 1",
		"RTT P50 38 MS  P90 52 MS  OFFSET -1250 US",
		"HORIZON D 120 MS  LATE INPUTS 0",
		"SKEW 1.5 MS  LANDED LATE LAST 0.0 / MAX 14.5 MS",
		"REJECTED PACKETS 3  EVENT SEQ 41",
	]))


func test_format_host_lists_up_to_three_peers() -> void:
	assert_str(NetDebugRows.format(HOST_STATS)).is_equal("\n".join([
		"NET HOST  SEAT 0  PEERS 3",
		"RTT NEMO 44 MS  RTT ORCA 61 MS  RTT KRAKEN 12 MS",
		"HORIZON D 95 MS  LATE INPUTS 7",
		"SKEW -2.0 MS  LANDED LATE LAST 0.0 / MAX 0.0 MS",
		"REJECTED PACKETS 0  EVENT SEQ 118",
	]))
	var four := HOST_STATS.duplicate(true)
	(four["per_peer"] as Array).append({"seat": 4, "name": "EXTRA", "p90_ms": 9})
	var line2 := NetDebugRows.format(four).split("\n")[1]
	assert_str(line2).is_equal("RTT NEMO 44 MS  RTT ORCA 61 MS  RTT KRAKEN 12 MS")


func test_format_empty_prints_dashes() -> void:
	var out := NetDebugRows.format({})
	assert_int(out.split("\n").size()).is_equal(5)
	assert_str(out).is_equal("\n".join([
		"NET --  SEAT --  PEERS --",
		"RTT P50 -- MS  P90 -- MS  OFFSET -- US",
		"HORIZON D -- MS  LATE INPUTS --",
		"SKEW -- MS  LANDED LATE LAST -- / MAX -- MS",
		"REJECTED PACKETS --  EVENT SEQ --",
	]))
	assert_str(NetDebugRows.num({"x": NAN}, "x")).is_equal("--")
	assert_str(NetDebugRows.num({"x": "12"}, "x")).is_equal("--")


func _overlay(session: Node) -> DebugOverlay:
	var c: Conductor = auto_free(Conductor.new())
	add_child(c)
	var o := DebugOverlay.new()
	o.net_session = session
	add_child(o)
	auto_free(o)
	o.conductor = c
	return o


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_panel_grew_to_580() -> void:
	assert_float(DebugOverlay.PANEL_SIZE.y).is_equal(580.0)
	assert_float(DebugOverlay.PANEL_SIZE.x).is_equal(360.0)


func test_overlay_shows_five_net_rows_during_a_match() -> void:
	var s: FakeSession = auto_free(FakeSession.new())
	s.match_spec = {"role": "client", "local_seat": 2}
	s.stats = CLIENT_STATS
	var o := _overlay(s)
	o.visible = true
	await _frames(2)
	assert_str(o.net_text()).is_equal(NetDebugRows.format(CLIENT_STATS))
	assert_int(o.net_text().split("\n").size()).is_equal(5)
	assert_str(o.timing_text()).starts_with("song_time")
	assert_int(o.timing_text().split("\n").size()).is_equal(6)


func test_overlay_hidden_does_not_poll_the_session() -> void:
	var s: FakeSession = auto_free(FakeSession.new())
	s.match_spec = {"role": "host"}
	s.stats = HOST_STATS
	var o := _overlay(s)
	await _frames(2)
	assert_bool(o.visible).is_false()
	assert_int(s.stats_calls).is_equal(0)


func test_overlay_offline_text_is_unchanged() -> void:
	var s: FakeSession = auto_free(FakeSession.new())  # lobby only: no pending match
	s.stats = CLIENT_STATS
	for session: Node in [s, null]:
		var o := _overlay(session)
		if session == null:
			o.net_session = auto_free(Node.new())  # a node without the session API
		o.visible = true
		await _frames(2)
		assert_str(o.net_text()).is_equal("")
		var lines := o.timing_text().split("\n")
		assert_int(lines.size()).is_equal(6)
		assert_str(lines[0]).starts_with("song_time")
		assert_str(lines[5]).starts_with("fps")
	assert_int(s.stats_calls).is_equal(0)


func test_match_ending_hides_the_rows() -> void:
	var s: FakeSession = auto_free(FakeSession.new())
	s.match_spec = {"role": "host"}
	s.stats = HOST_STATS
	var o := _overlay(s)
	o.visible = true
	await _frames(2)
	assert_str(o.net_text()).is_not_empty()
	s.match_spec = {}
	await _frames(2)
	assert_str(o.net_text()).is_equal("")
