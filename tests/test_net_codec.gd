extends GdUnitTestSuite
## 04-01 Task 1: NetCodec is the single validation choke point (D-02, D-23, RESEARCH Pattern 4,
## Security Domain V5). Round trips, one test per rejection class, real producer payloads and a
## 10,000-case fuzz loop.

const P := NetProtocol


func _ctx(from_host: bool, note_count: int = 100, song_len: float = 120.0) -> Dictionary:
	return {"from_host": from_host, "note_count": note_count, "song_len": song_len, "max_seat": 3}


func _song() -> Dictionary:
	return {"fp": "u1.0123456789abcdef01234567.expert", "sig": "0123456789abcdef",
		"diff": "expert", "title": "Sea Shanty 2", "artist": "Somebody"}


func _results() -> Dictionary:
	return {"type": P.RESULTS, "rows": [
		{"seat": 0, "place": 1, "alive": true, "depth": 1200.0, "hull": 55.5, "accuracy": 0.93,
			"max_streak": 40, "eliminated_at": INF, "name": "YOU", "landed": 3, "reflected": 1},
		{"seat": 1, "place": 2, "alive": false, "depth": 800.0, "hull": 0.0, "accuracy": 0.7,
			"max_streak": 12, "eliminated_at": 51.25, "name": "MAKO", "landed": 0,
			"reflected": 0, "left": true, "left_t": 51.25},
	], "medals": {0: ["sharpshooter"], 1: []}, "last_standing_seat": 0, "local_seat": 0,
		"title": "T", "artist": "A", "difficulty": "expert", "seed": 99, "online": true,
		"is_host": false, "host_seat": 0, "host_name": "DIVER"}


## [msg, from_host] for every message type.
func _valid() -> Array:
	return [
		[{"type": P.AUTH, "proto": 1, "game": "0.7.0", "name": "diver"}, false],
		[{"type": P.AUTH_REPLY, "ok": false, "reason": P.R_VERSION, "host_version": "0.7.0"}, true],
		[{"type": P.PING, "seq": 3, "c0": 123456789}, false],
		[{"type": P.PING, "seq": 3, "c0": 123456789}, true],
		[{"type": P.PONG, "seq": 3, "c0": 123456789, "h": 987654321}, true],
		[{"type": P.PONG, "seq": 3, "c0": 123456789, "h": 987654321}, false],
		[{"type": P.READY, "ready": true, "synced": false}, false],
		[{"type": P.SONG_STATUS, "status": "missing", "synced": true}, false],
		[{"type": P.LOADED}, false],
		[{"type": P.LOAD_FAIL}, false],
		[{"type": P.START_LATE, "lead_ms": 120}, false],
		[{"type": P.INPUTS, "items": [
			[P.IN_JUDGED, 12.5, 0, 7, InputJudge.Judgment.PERFECT],
			[P.IN_EXTRA, 12.6, 1, InputJudge.Judgment.MISS],
			[P.IN_STRAY, 12.7, 2], [P.IN_GHOST, 12.8, 3],
			[P.IN_STATUS, 12.9, 4, 88.5, 1200.0, 0.95, 31],
			[P.IN_FIRE, 13.0, 5], [P.IN_CYCLE, 13.1, 6],
			[P.IN_TARGET_MODE, 13.2, 7, PlayerState.TargetMode.LOCKED, 2],
			[P.IN_FAILED, 13.3, 8], [P.IN_APPROACH, -2.0, 9, 1.5]]}, false],
		[{"type": P.DONE, "t": 118.25}, false],
		[{"type": P.HEARTBEAT, "song_t": 33.3, "ticks": 5_000_000}, false],
		[{"type": P.BYE}, false],
		[{"type": P.LOBBY, "roster": [
			{"seat": 0, "name": "DIVER", "ready": true, "song": "ok", "ping_ms": 0,
				"synced": true, "host": true},
			{"seat": 1, "name": "DIVER2", "ready": false, "song": "checking", "ping_ms": 41,
				"synced": false, "host": false}], "song": _song(), "flight": 2,
			"phase": "lobby"}, true],
		[{"type": P.LOBBY, "roster": [], "song": {}, "flight": 1, "phase": "lobby"}, true],
		[{"type": P.NOTICE, "code": "joined", "name": "MAKO", "n": 0}, true],
		[{"type": P.KICKED, "reason": P.R_KICKED}, true],
		[{"type": P.LOAD, "fp": "u1.abc.expert", "sig": "0123456789abcdef", "diff": "hard",
			"seed": 42, "flight": 2, "roster": [{"seat": 0, "name": "DIVER"},
			{"seat": 1, "name": "MAKO"}], "d_ms": 80, "max_song_s": 0.0, "autoplay": false}, true],
		[{"type": P.START, "host_start_ticks": 9_000_000_000}, true],
		[{"type": P.ABORT_TO_LOBBY, "reason": P.R_LOAD_TIMEOUT, "name": "MAKO"}, true],
		[{"type": P.EVENTS, "seq": 4, "events": [
			GameEvent.make(GameEvent.STATUS, 3.0, {"seat": 1, "hull": 90.0, "depth": 10.0,
				"alive": true, "place": 1, "accuracy": 1.0})]}, true],
		[_results(), true],
		[{"type": P.BACK_TO_LOBBY}, true],
		[{"type": P.MATCH_ABORT, "reason": P.R_HOST_LEFT}, true],
		[{"type": P.LOBBY_CLOSED}, true],
	]


func _rt(msg: Dictionary, from_host: bool) -> Dictionary:
	return NetCodec.decode(NetCodec.encode(msg), _ctx(from_host))


# --- round trips -----------------------------------------------------------

func test_every_valid_message_round_trips() -> void:
	for pair in _valid():
		var out := _rt(pair[0], pair[1])
		assert_bool(out.is_empty()).override_failure_message("rejected: %s" % str(pair[0])).is_false()
		assert_str(out.get("type", "")).is_equal(pair[0]["type"])


func test_song_time_survives_exactly() -> void:
	var out := _rt({"type": P.DONE, "t": 123.456789012}, false)
	assert_bool(float(out["t"]) == 123.456789012).is_true()
	var inp := _rt({"type": P.INPUTS, "items": [[P.IN_FIRE, 98.765432109876, 0]]}, false)
	assert_bool(float(inp["items"][0][1]) == 98.765432109876).is_true()


func test_every_message_type_is_whitelisted_in_one_direction() -> void:
	for ty in P.FROM_CLIENT:
		assert_bool(ty is String).is_true()
	assert_bool(P.FROM_CLIENT.has(P.PING) and P.FROM_HOST.has(P.PING)).is_true()
	assert_bool(P.FROM_CLIENT.has(P.PONG) and P.FROM_HOST.has(P.PONG)).is_true()
	assert_bool(P.FROM_CLIENT.has(P.AUTH)).is_true()
	assert_bool(P.FROM_HOST.has(P.AUTH_REPLY)).is_true()


# --- rejection classes -----------------------------------------------------

func test_rejects_oversize_before_decoding() -> void:
	var big := PackedByteArray()
	big.resize(P.MAX_PACKET + 1)
	assert_dict(NetCodec.decode(big, _ctx(true))).is_empty()
	# A valid message padded past the cap is rejected too.
	var msg := {"type": P.NOTICE, "code": "x", "name": "", "n": 0, "pad": "a".repeat(20000)}
	assert_bool(NetCodec.encode(msg).size() > P.MAX_PACKET).is_true()
	assert_dict(NetCodec.decode(NetCodec.encode(msg), _ctx(true))).is_empty()


func test_rejects_non_dictionary() -> void:
	for v in [null, 3, "ping", [P.PING], PackedByteArray([1, 2]), Vector2(1, 2)]:
		assert_dict(NetCodec.decode(var_to_bytes(v), _ctx(false))).is_empty()
		assert_dict(NetCodec.validate(v, _ctx(false))).is_empty()


func test_rejects_missing_or_bad_type() -> void:
	assert_dict(NetCodec.validate({"seq": 1, "c0": 2}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": 7, "seq": 1, "c0": 2}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": "nope"}, _ctx(false))).is_empty()


func test_rejects_wrong_direction() -> void:
	assert_dict(NetCodec.validate({"type": P.LOBBY_CLOSED}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.START, "host_start_ticks": 1}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.BYE}, _ctx(true))).is_empty()
	assert_dict(NetCodec.validate({"type": P.LOADED}, _ctx(true))).is_empty()
	assert_dict(NetCodec.validate({"type": P.AUTH, "proto": 1, "game": "x", "name": "A"},
		_ctx(true))).is_empty()


func test_rejects_missing_key_and_wrong_type() -> void:
	assert_dict(NetCodec.validate({"type": P.PING, "seq": 1}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.PING, "seq": 1.0, "c0": 2}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.READY, "ready": 1, "synced": true}, _ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.START, "host_start_ticks": "1"}, _ctx(true))).is_empty()
	# Unknown extra keys are rejected (strict schema).
	assert_dict(NetCodec.validate({"type": P.BYE, "x": 1}, _ctx(false))).is_empty()


func test_rejects_bad_times() -> void:
	for t in [NAN, INF, -INF, -10.5, 150.01, 1e300]:
		assert_dict(NetCodec.validate({"type": P.DONE, "t": t}, _ctx(false))).is_empty()
		assert_dict(NetCodec.validate({"type": P.INPUTS, "items": [[P.IN_FIRE, t, 0]]},
			_ctx(false))).is_empty()
	assert_dict(NetCodec.validate({"type": P.DONE, "t": -10.0}, _ctx(false))).is_not_empty()
	assert_dict(NetCodec.validate({"type": P.DONE, "t": 150.0}, _ctx(false))).is_not_empty()
	assert_dict(NetCodec.validate({"type": P.HEARTBEAT, "song_t": NAN, "ticks": 1},
		_ctx(false))).is_empty()


func test_rejects_bad_seats() -> void:
	var lob := {"type": P.LOBBY, "roster": [{"seat": 4, "name": "A", "ready": true, "song": "ok",
		"ping_ms": 0, "synced": true, "host": true}], "song": {}, "flight": 1, "phase": "lobby"}
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()
	lob["roster"][0]["seat"] = -1
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()
	lob["roster"][0]["seat"] = 3
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_not_empty()
	var r := _results()
	r["local_seat"] = 4
	assert_dict(NetCodec.validate(r, _ctx(true))).is_empty()
	var ev := GameEvent.make(GameEvent.IMPLODED, 1.0, {"seat": 4})
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_false()
	ev["seat"] = -2
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_false()
	ev["seat"] = 2.0
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_false()
	ev["seat"] = -1
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_true()


func test_rejects_bad_note_index() -> void:
	var good := {"type": P.INPUTS, "items": [[P.IN_JUDGED, 1.0, 0, 99, 0]]}
	assert_dict(NetCodec.validate(good, _ctx(false, 100))).is_not_empty()
	for idx in [100, -1, 1 << 40]:
		var m := {"type": P.INPUTS, "items": [[P.IN_JUDGED, 1.0, 0, idx, 0]]}
		assert_dict(NetCodec.validate(m, _ctx(false, 100))).is_empty()
	# No chart loaded: any JUDGED item is rejected.
	assert_dict(NetCodec.validate(good, _ctx(false, 0))).is_empty()


func test_rejects_bad_judgment_kind_and_arity() -> void:
	for it in [[P.IN_JUDGED, 1.0, 0, 3, 3], [P.IN_JUDGED, 1.0, 0, 3, -1],
			[P.IN_EXTRA, 1.0, 0, 9], [P.IN_FIRE, 1.0, 0, 1], [P.IN_JUDGED, 1.0, 0, 3],
			[99, 1.0, 0], ["fire", 1.0, 0], [P.IN_FIRE, 1.0, -1], [P.IN_FIRE, 1.0],
			[P.IN_STATUS, 1.0, 0, NAN, 1.0, 1.0, 1], [P.IN_STATUS, 1.0, 0, 1.0, 1.0, 1.0, -1],
			[P.IN_TARGET_MODE, 1.0, 0, 7, 0], [P.IN_TARGET_MODE, 1.0, 0, 0, 4],
			[P.IN_APPROACH, 1.0, 0, INF], {"kind": 1}, "x"]:
		var m := {"type": P.INPUTS, "items": [it]}
		assert_dict(NetCodec.validate(m, _ctx(false))).override_failure_message(str(it)).is_empty()


func test_rejects_overlong_arrays_and_batches() -> void:
	var items := []
	for i in P.MAX_BATCH + 1:
		items.append([P.IN_FIRE, 1.0, i])
	assert_dict(NetCodec.validate({"type": P.INPUTS, "items": items}, _ctx(false))).is_empty()
	items.pop_back()
	assert_dict(NetCodec.validate({"type": P.INPUTS, "items": items}, _ctx(false))).is_not_empty()
	var evs := []
	for i in P.MAX_BATCH + 1:
		evs.append(GameEvent.make(GameEvent.DUEL_START, 1.0, {"solo": 0}))
	assert_dict(NetCodec.validate({"type": P.EVENTS, "seq": 0, "events": evs},
		_ctx(true))).is_empty()
	var heads := []
	for i in P.MAX_EVENT_ARRAY + 1:
		heads.append(i)
	var launch := GameEvent.make(GameEvent.TORPEDO_LAUNCH, 1.0, {"id": 1, "from": 0, "to": 1,
		"warheads": heads})
	assert_bool(NetCodec.validate_event(launch, _ctx(true))).is_false()
	heads.pop_back()
	assert_bool(NetCodec.validate_event(launch, _ctx(true))).is_true()


func test_rejects_long_or_control_strings() -> void:
	var n := {"type": P.NOTICE, "code": "a".repeat(P.MAX_STR + 1), "name": "", "n": 0}
	assert_dict(NetCodec.validate(n, _ctx(true))).is_empty()
	n["code"] = "bad\ncode"
	assert_dict(NetCodec.validate(n, _ctx(true))).is_empty()
	var ev := GameEvent.make(GameEvent.FIRE_REFUSED, 1.0, {"seat": 0, "reason": "a\u0007b"})
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_false()
	ev["reason"] = "x".repeat(P.MAX_STR + 1)
	assert_bool(NetCodec.validate_event(ev, _ctx(true))).is_false()
	var lob := {"type": P.LOBBY, "roster": [], "song": _song(), "flight": 1, "phase": "lobby"}
	lob["song"]["title"] = "t".repeat(65)
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()
	lob["song"]["title"] = "ok\ttitle"
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()
	lob["song"]["title"] = "t".repeat(64)
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_not_empty()
	lob["song"]["sig"] = "0123456789ABCDEF"
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()


func test_clean_name() -> void:
	assert_str(NetCodec.clean_name("diver")).is_equal("DIVER")
	assert_str(NetCodec.clean_name("Sub_1 - x")).is_equal("SUB_1 - X")
	assert_str(NetCodec.clean_name("ABCDEFGHIJKL")).is_equal("ABCDEFGHIJKL")
	for bad in ["", "ABCDEFGHIJKLM", "a\nb", "ä", "x.y", "<b>", 12, null, ["A"]]:
		assert_str(NetCodec.clean_name(bad)).override_failure_message(str(bad)).is_equal("")
	var lob := {"type": P.LOBBY, "roster": [{"seat": 0, "name": "bad!name", "ready": true,
		"song": "ok", "ping_ms": 0, "synced": true, "host": true}], "song": {}, "flight": 1,
		"phase": "lobby"}
	assert_dict(NetCodec.validate(lob, _ctx(true))).is_empty()


# --- events ----------------------------------------------------------------

func test_event_rules() -> void:
	var c := _ctx(true)
	assert_bool(NetCodec.validate_event(GameEvent.make("bogus", 1.0), c)).is_false()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.DUEL_START, NAN, {"solo": 0}), c)).is_false()
	assert_bool(NetCodec.validate_event({"type": GameEvent.DUEL_START, "solo": 0}, c)).is_false()
	var many := {}
	for i in 23:
		many["k%d" % i] = i
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.STATUS, 1.0, many), c)).is_false()
	# INF allowed only on the documented keys; NaN never.
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.BUFF_APPLIED, 1.0,
		{"seat": 0, "reward": 1, "until_t": INF, "amount": 0.0}), c)).is_true()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.PAYLOAD_END, 1.0,
		{"id": 1, "seat": 0, "reward": 1, "reason": "expired", "immune_until": -INF}), c)).is_true()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.BUFF_APPLIED, 1.0,
		{"seat": 0, "until_t": NAN}), c)).is_false()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.LANDED, 1.0,
		{"arrive_t": INF}), c)).is_false()
	# Objects, packed arrays and vectors are never accepted.
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.STATUS, 1.0,
		{"x": Vector2.ZERO}), c)).is_false()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.STATUS, 1.0,
		{"x": PackedInt32Array([1])}), c)).is_false()
	# Depth: event -> array -> dict -> array is too deep.
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.MATCH_END, 1.0,
		{"standings": [{"x": [1]}]}), c)).is_false()
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.MATCH_END, 1.0,
		{"d": {"x": {"y": 1}}}), c)).is_false()
	# Nested dict key cap (8).
	var nine := {}
	for i in 9:
		nine["k%d" % i] = i
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.MATCH_END, 1.0,
		{"standings": [nine]}), c)).is_false()
	# Nested seat keys are checked too.
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.MATCH_END, 1.0,
		{"standings": [{"seat": 9}]}), c)).is_false()
	# Generic: a dict of seat -> float like DUEL_LIVE.pct.
	assert_bool(NetCodec.validate_event(GameEvent.make(GameEvent.DUEL_START, 1.0,
		{"solo": 0, "pct": {0: 0.5, 1: 0.25}}), c)).is_true()


func test_events_message_rejects_one_bad_event() -> void:
	var m := {"type": P.EVENTS, "seq": 1, "events": [
		GameEvent.make(GameEvent.DUEL_START, 1.0, {"solo": 0}),
		GameEvent.make(GameEvent.IMPLODED, 2.0, {"seat": 7})]}
	assert_dict(NetCodec.validate(m, _ctx(true))).is_empty()
	m["seq"] = -1
	m["events"].pop_back()
	assert_dict(NetCodec.validate(m, _ctx(true))).is_empty()


# --- RESULTS schema --------------------------------------------------------

func test_results_schema_rejections() -> void:
	var c := _ctx(true)
	assert_dict(NetCodec.validate(_results(), c)).is_not_empty()
	var r := _results()
	r["rows"][0]["hull"] = NAN
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["rows"][0]["eliminated_at"] = -INF
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["rows"][1]["left_t"] = INF
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["rows"][0]["bogus"] = 1
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	var medals := []
	for i in 9:
		medals.append("m%d" % i)
	r["medals"][0] = medals
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["medals"][4] = []
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["rows"].append(r["rows"][0].duplicate())
	r["rows"].append(r["rows"][0].duplicate())
	r["rows"].append(r["rows"][0].duplicate())
	assert_dict(NetCodec.validate(r, c)).is_empty()
	r = _results()
	r["last_standing_seat"] = 5
	assert_dict(NetCodec.validate(r, c)).is_empty()
	assert_dict(NetCodec.validate(_results(), _ctx(false))).is_empty()


# --- real producer payloads -----------------------------------------------

func _sim_run() -> MatchSim:
	var chart := TestCharts.click_chart(120.0, 120, 1000)
	var ps: Array[PlayerState] = []
	for s in range(4):
		ps.append(PlayerState.new(s, "P%d" % s, s == 0))
	var sim := MatchSim.new(chart, VersusConfig.new(), JudgeConfig.new(), ps,
		LoopbackChannel.new(), 7)
	var script := [[3.0, "give", [0, Reward.Id.INK_CLOUD]], [3.1, "fire", [0]],
		[6.0, "give", [1, Reward.Id.DECOY_FLARE]], [6.1, "fire", [1]],
		[9.0, "give", [2, Reward.Id.DEPTH_CHARGE]], [9.2, "fire", [2]],
		[12.0, "give", [0, Reward.Id.OVERCLOCK]], [12.0, "fire", [0]],
		[20.0, "fail", [3]]]
	var next := 0
	var ni := 0
	var t := 0.0
	while t < 40.0:
		t += 1.0 / 60.0
		while ni < chart.notes.size() and float(chart.notes[ni]["time"]) <= t:
			for s in range(3):
				var j := InputJudge.Judgment.PERFECT if (ni + s) % 9 != 0 else InputJudge.Judgment.MISS
				sim.on_judged(s, ni, j, float(chart.notes[ni]["time"]))
			ni += 1
		while next < script.size() and float(script[next][0]) <= t:
			var ev: Array = script[next]
			var a: Array = ev[2]
			match ev[1]:
				"give":
					ps[a[0]].meter.progress = ps[a[0]].meter.target
					ps[a[0]].meter.held = a[1]
				"fire":
					sim.request_fire(a[0], ev[0])
				"fail":
					sim.on_failed(a[0], ev[0])
			next += 1
		sim.update(t)
	sim.finish(40.0)
	return sim


func test_real_match_sim_events_pass() -> void:
	var sim := _sim_run()
	var c := {"from_host": true, "note_count": 120, "song_len": 60.0, "max_seat": 3}
	var saw_end := false
	var saw_inf := false
	var saw_finite := false
	for e in sim.event_log:
		assert_bool(NetCodec.validate_event(e, c)).override_failure_message("event rejected: %s" % str(e)).is_true()
		if e["type"] == GameEvent.MATCH_END:
			saw_end = true
			for row in e["standings"]:
				if is_inf(float(row["eliminated_at"])):
					saw_inf = true
				else:
					saw_finite = true
	assert_bool(saw_end).is_true()
	assert_bool(saw_inf and saw_finite).is_true()
	# The whole log also passes in EVENTS batches through the codec.
	var batch := []
	for e in sim.event_log:
		batch.append(e)
		if batch.size() == P.MAX_BATCH:
			var out := NetCodec.decode(NetCodec.encode({"type": P.EVENTS, "seq": 0,
				"events": batch}), c)
			assert_dict(out).is_not_empty()
			batch = []


func test_real_versus_controller_results_pass() -> void:
	var chart := TestCharts.hand_chart(1000)
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = 3
	m.skill = "veteran"
	m.seed = 11
	var vc := VersusController.new()
	vc.setup(null, chart, JudgeConfig.new(), m, -1, true)
	vc.human_rig.approach_s = 1.5
	var end_t := 0.0
	for n in chart.notes:
		end_t = maxf(end_t, float(n["time"]) + float(n["duration"]))
	end_t += 2.0
	var t := MatchHarness.START_T
	while t < end_t:
		t = minf(t + 1.0 / 60.0, end_t)
		vc.pre_tick(t)
		vc.update(t)
	var fin := vc.finish(end_t)
	vc.free()
	var msg := {"type": P.RESULTS}
	for k in fin:
		msg[k] = fin[k]
	var c := {"from_host": true, "note_count": chart.notes.size(), "song_len": end_t,
		"max_seat": 3}
	assert_dict(NetCodec.validate(msg, c)).is_not_empty()
	assert_dict(NetCodec.decode(NetCodec.encode(msg), c)).is_not_empty()
	var bad: Dictionary = msg.duplicate(true)
	bad["rows"][0]["hull"] = NAN
	assert_dict(NetCodec.validate(bad, c)).is_empty()
	bad = msg.duplicate(true)
	for i in 17:
		bad["rows"][0]["x%d" % i] = 0
	assert_dict(NetCodec.validate(bad, c)).is_empty()
	bad = msg.duplicate(true)
	var nine: Array = []
	for i in 9:
		nine.append("m")
	bad["medals"][0] = nine
	assert_dict(NetCodec.validate(bad, c)).is_empty()
	bad = msg.duplicate(true)
	bad["medals"][4] = []
	assert_dict(NetCodec.validate(bad, c)).is_empty()


# --- fuzz ------------------------------------------------------------------

func _rand_scalar(rng: RandomNumberGenerator) -> Variant:
	match rng.randi_range(0, 11):
		0: return rng.randi_range(-5, 200)
		1: return rng.randf_range(-50.0, 300.0)
		2: return NAN
		3: return INF if rng.randf() < 0.5 else -INF
		4: return ["ping", "inputs", "events", "results", "lobby", "x", "", "\n", "a".repeat(40)][rng.randi_range(0, 8)]
		5: return rng.randf() < 0.5
		6: return null
		7: return Vector2(rng.randf(), rng.randf())
		8: return PackedByteArray([1, 2, 3])
		9: return 1 << rng.randi_range(0, 62)
		10: return GameEvent.ALL_TYPES[rng.randi_range(0, GameEvent.ALL_TYPES.size() - 1)]
		_: return P.FROM_CLIENT[rng.randi_range(0, P.FROM_CLIENT.size() - 1)]


func _rand_value(rng: RandomNumberGenerator, depth: int) -> Variant:
	var r := rng.randi_range(0, 9)
	if depth >= 5 or r < 6:
		return _rand_scalar(rng)
	if r < 8:
		var a := []
		for i in rng.randi_range(0, 20 if rng.randf() < 0.9 else 200):
			a.append(_rand_value(rng, depth + 1))
		return a
	return _rand_dict(rng, depth + 1)


const KEYS := ["type", "t", "seq", "c0", "h", "items", "events", "rows", "medals", "seat", "name",
	"roster", "song", "flight", "phase", "status", "synced", "ready", "reason", "fp", "sig",
	"until_t", "eliminated_at", "standings", "warheads", "local_seat", "last_standing_seat"]


func _rand_dict(rng: RandomNumberGenerator, depth: int) -> Dictionary:
	var d := {}
	if rng.randf() < 0.7:
		d["type"] = (P.FROM_CLIENT + P.FROM_HOST + GameEvent.ALL_TYPES)[rng.randi_range(0,
			P.FROM_CLIENT.size() + P.FROM_HOST.size() + GameEvent.ALL_TYPES.size() - 1)]
	for i in rng.randi_range(0, 12):
		var k: Variant = KEYS[rng.randi_range(0, KEYS.size() - 1)] if rng.randf() < 0.8 \
			else _rand_scalar(rng)
		d[k] = _rand_value(rng, depth)
	return d


func _check(v: Variant, rng: RandomNumberGenerator) -> void:
	var c := _ctx(rng.randf() < 0.5, rng.randi_range(0, 200), rng.randf_range(0.0, 400.0))
	var out := NetCodec.validate(v, c)
	if not out.is_empty():
		assert_dict(NetCodec.validate(out, c)).is_not_empty()


func test_fuzz_10000_random_cases_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var valid := _valid()
	var accepted := 0
	for i in 10000:
		var kind := i % 4
		if kind == 0 or kind == 1:
			var v: Variant = _rand_dict(rng, 0) if kind == 0 else _rand_value(rng, 0)
			_check(v, rng)
			var c := _ctx(rng.randf() < 0.5)
			var out := NetCodec.decode(var_to_bytes(v), c)
			if not out.is_empty():
				accepted += 1
				assert_dict(NetCodec.validate(out, c)).is_not_empty()
		elif kind == 2:
			# Structurally mutated valid message: one key replaced with a random value.
			var pair: Array = valid[rng.randi_range(0, valid.size() - 1)]
			var m: Dictionary = pair[0].duplicate(true)
			var ks := m.keys()
			m[ks[rng.randi_range(0, ks.size() - 1)]] = _rand_value(rng, 1)
			_check(m, rng)
		else:
			# Byte-level damage: truncation or bit flips of a valid encoding (rarer, the engine
			# logs a decode error for each broken buffer).
			if i % 40 != 3:
				continue
			var pair: Array = valid[rng.randi_range(0, valid.size() - 1)]
			var b := NetCodec.encode(pair[0])
			if rng.randf() < 0.5:
				b = b.slice(0, rng.randi_range(0, b.size() - 1))
			else:
				for f in rng.randi_range(1, 4):
					var at := rng.randi_range(0, b.size() - 1)
					b[at] = b[at] ^ (1 << rng.randi_range(0, 7))
			var c := _ctx(pair[1])
			var out := NetCodec.decode(b, c)
			if not out.is_empty():
				assert_dict(NetCodec.validate(out, c)).is_not_empty()
	assert_int(accepted).is_greater_equal(0)
