extends GdUnitTestSuite
## 04-13 (D-03, D-13, D-19): VersusController as an online host and an online client, wired to
## each other headlessly over a MemTransport hub with NetCodec on both ends. The test emulates
## NetSession.pump_match inline (push INPUTS items into the host queue, queue.pump(t), send the
## host channel batches, remote.flush()); it does not use NetMatchHarness.

const D_S := 0.08
const LAT_S := 0.03
const SEED := 21
const DT := 1.0 / 60.0
## Hub time = song time + HUB_OFFSET (the hub clock starts at 0 and only moves forward).
const HUB_OFFSET := 10.0


## A connected host/client pair: {hub, ht, ct, host, client, chart, peer, t}.
func _pair(autoplay: bool) -> Dictionary:
	var chart := TestCharts.hand_chart(1000)
	var hub := MemTransport.Hub.new(SEED)
	var ht := hub.make_host()
	var ct := hub.make_client()
	var peer := ct.unique_id()
	hub.set_link(peer, LAT_S)
	ht.auth_request.connect(func(id: int, _b: PackedByteArray) -> void: ht.complete_auth(id))
	ct.connect_to_host()
	hub.advance(1.0)
	ct.send_auth(NetTransport.HOST_ID, PackedByteArray([1, 2, 3, 4]))
	hub.advance(2.0)
	hub.advance(3.0)
	assert_int(ct.state).is_equal(MemTransport.State.CONNECTED)
	var names := PackedStringArray(["HOSTY", "CLIENTO"])
	var host := VersusController.new()
	host.setup_online(null, chart, JudgeConfig.new(), {"role": "host", "local_seat": 0,
		"names": names, "seed": SEED, "flight": 1, "d_s": D_S, "autoplay": autoplay,
		"margins": {0: 0.0, 1: LAT_S * 2.0}})
	host.human_rig.approach_s = 1.5
	host.host_channel.add_peer(peer)
	var client := VersusController.new()
	var song_len := ProgressTrack.song_length_of(chart)
	client.net_send = func(msg: Dictionary) -> void:
		ct.send(NetTransport.HOST_ID, NetCodec.encode(msg))
	client.setup_online(null, chart, JudgeConfig.new(), {"role": "client", "local_seat": 1,
		"names": names, "seed": SEED, "flight": 1, "d_s": D_S, "autoplay": autoplay})
	client.human_rig.approach_s = 1.5
	var host_ctx := {"from_host": false, "note_count": chart.notes.size(), "song_len": song_len,
		"max_seat": 1}
	var client_ctx := {"from_host": true, "note_count": chart.notes.size(),
		"song_len": song_len, "max_seat": 3}
	ht.packet.connect(func(src: int, bytes: PackedByteArray) -> void:
		var m := NetCodec.decode(bytes, host_ctx)
		if m.get("type", "") == NetProtocol.INPUTS and src == peer:
			for it in m["items"]:
				host.queue.push_item(1, it))
	ct.packet.connect(func(_src: int, bytes: PackedByteArray) -> void:
		var m := NetCodec.decode(bytes, client_ctx)
		if m.get("type", "") == NetProtocol.EVENTS:
			client.client_channel.receive(m))
	return {"hub": hub, "ht": ht, "ct": ct, "host": host, "client": client, "chart": chart,
		"peer": peer, "t": MatchHarness.START_T}


## One frame at song time t on both PCs (Gameplay order: pre_tick, update, net_tick, pump).
func _frame(p: Dictionary, t: float) -> void:
	var host: VersusController = p["host"]
	var client: VersusController = p["client"]
	host.pre_tick(t)
	host.update(t)
	host.net_tick(t)
	host.queue.pump(t)
	_send_batches(p)
	client.pre_tick(t)
	client.update(t)
	client.net_tick(t)
	client.remote.flush()
	(p["hub"] as MemTransport.Hub).advance(t + HUB_OFFSET)
	p["t"] = t


func _send_batches(p: Dictionary) -> void:
	var host: VersusController = p["host"]
	var ht: MemTransport = p["ht"]
	var batches := host.host_channel.take_batches()
	for id in batches:
		for msg in batches[id]:
			ht.send(id, NetCodec.encode(msg))


func _run_to(p: Dictionary, end_t: float) -> void:
	var t: float = p["t"]
	while t < end_t:
		t = minf(t + DT, end_t)
		_frame(p, t)


## Host finish, then everything still in flight reaches the client.
func _finish_and_drain(p: Dictionary, end_t: float) -> Dictionary:
	var host: VersusController = p["host"]
	var data := host.finish(end_t)
	_send_batches(p)
	(p["hub"] as MemTransport.Hub).advance(end_t + HUB_OFFSET + 1.0)
	return data


func _free(p: Dictionary) -> void:
	(p["host"] as VersusController).free()
	(p["client"] as VersusController).free()


static func _seat_events(log: Array, type: String, seat: int) -> Array:
	return log.filter(func(e: Dictionary) -> bool:
		return e.get("type", "") == type and int(e.get("seat", -1)) == seat)


# --- 1, 2, 6: the full loop ----------------------------------------------------------------

func test_client_log_equals_host_broadcast_and_host_judges_seat_1() -> void:
	var p := _pair(true)
	var host: VersusController = p["host"]
	var client: VersusController = p["client"]
	assert_int(host.host_channel.broadcast_log.size()).is_equal(0)
	_run_to(p, 40.0)
	_finish_and_drain(p, 40.0)
	var sent := host.host_channel.broadcast_log
	var got := client.client_channel.received_log
	assert_int(sent.size()).is_greater(50)
	assert_int(client.client_channel.rejected_events).is_equal(0)
	assert_int(got.size()).is_equal(sent.size())
	assert_str(JSON.stringify(got)).is_equal(JSON.stringify(sent))
	# 2: the host's MatchSim judged seat 1 from the client's inputs.
	var st := _seat_events(host.match_sim.event_log, GameEvent.STATUS, 1)
	assert_int(st.size()).is_greater(0)
	assert_bool(st.any(func(e: Dictionary) -> bool:
		return float(e.get("accuracy", -1.0)) > 0.0)).is_true()
	assert_int(host.queue.late_inputs).is_equal(0)
	# 6: the client drives seat 1.
	assert_int(client.local_seat).is_equal(1)
	assert_int(client.human_rig.seat).is_equal(1)
	assert_int(host.local_seat).is_equal(0)
	assert_object(client.match_sim).is_null()
	assert_str(client.names[1]).is_equal("YOU")
	assert_str(client.names[0]).is_equal("HOSTY")
	assert_str(host.names[0]).is_equal("YOU")
	assert_dict(client.debug_net()).contains_keys(["last_seq", "rejected_events", "online"])
	assert_dict(host.debug_net()).contains_keys(["late_inputs", "pending", "released_t"])
	_free(p)


# --- 3: the online refusal blip --------------------------------------------------------------

func test_client_blips_once_on_fire_refused_and_host_does_not() -> void:
	var p := _pair(false)
	var host: VersusController = p["host"]
	var client: VersusController = p["client"]
	_run_to(p, 4.0)
	# Nothing held: refused with "nothing", no blip.
	assert_int(client.fire(4.0)).is_equal(Referee.FIRE_REMOTE)
	assert_int(client.error_blips).is_equal(0)
	_run_to(p, 5.0)
	assert_int(_seat_events(client.client_channel.received_log, GameEvent.FIRE_REFUSED, 1).size()) \
		.is_equal(1)
	assert_int(client.error_blips).is_equal(0)
	# Scripted host state: seat 1 holds a disruptor and its only rival (seat 0) is immune.
	var p1: PlayerState = host.match_sim.players[1]
	p1.meter.held = Reward.Id.INK_CLOUD
	(host.match_sim.players[0] as PlayerState).immune_until = 1e9
	client.fire(5.0)
	assert_int(client.error_blips).is_equal(0)  # no synchronous blip online
	_run_to(p, 6.0)
	var refused := _seat_events(client.client_channel.received_log, GameEvent.FIRE_REFUSED, 1)
	assert_int(refused.size()).is_equal(2)
	assert_str(str(refused[1]["reason"])).is_equal("shielded")
	assert_int(client.error_blips).is_equal(1)
	assert_int(host.error_blips).is_equal(0)
	_free(p)


## The host's own refusal blips once through the event (its fire returns FIRE_REMOTE too).
func test_host_blips_from_its_own_fire_refused() -> void:
	var p := _pair(false)
	var host: VersusController = p["host"]
	var client: VersusController = p["client"]
	_run_to(p, 4.0)
	(host.match_sim.players[0] as PlayerState).meter.held = Reward.Id.INK_CLOUD
	(host.match_sim.players[1] as PlayerState).immune_until = 1e9
	assert_int(host.fire(4.0)).is_equal(Referee.FIRE_REMOTE)
	assert_int(host.error_blips).is_equal(0)
	_run_to(p, 4.5)
	assert_int(host.error_blips).is_equal(1)
	assert_int(client.error_blips).is_equal(0)
	_free(p)


# --- 4: offline never blips from events -------------------------------------------------------

func test_offline_blips_only_from_the_return_code() -> void:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = 1
	m.skill = "veteran"
	m.seed = SEED
	var vc := VersusController.new()
	vc.setup(null, TestCharts.hand_chart(1000), JudgeConfig.new(), m, -1, false)
	assert_bool(vc.online).is_false()
	assert_int(vc.local_seat).is_equal(VersusController.HUMAN_SEAT)
	vc.pre_tick(3.0)
	vc.channel.send(GameEvent.make(GameEvent.FIRE_REFUSED, 3.0, {"seat": 0, "reason": "shielded"}))
	assert_int(vc.error_blips).is_equal(0)
	(vc.match_sim.players[0] as PlayerState).meter.held = Reward.Id.INK_CLOUD
	(vc.match_sim.players[1] as PlayerState).immune_until = 1e9
	assert_int(vc.fire(3.5)).is_equal(MatchSim.FIRE_SHIELDED)
	# MatchSim also emitted FIRE_REFUSED on the loopback: still exactly one blip.
	assert_int(_seat_events(vc.match_sim.event_log, GameEvent.FIRE_REFUSED, 0).size()).is_equal(1)
	assert_int(vc.error_blips).is_equal(1)
	vc.free()


# --- 5, 7: host finish data -------------------------------------------------------------------

func _host_only(names: PackedStringArray) -> VersusController:
	var host := VersusController.new()
	host.setup_online(null, TestCharts.hand_chart(1000), JudgeConfig.new(), {"role": "host",
		"local_seat": 0, "names": names, "seed": SEED, "flight": 1, "d_s": D_S,
		"autoplay": false, "margins": {0: 0.0, 1: 0.05}})
	return host


func _host_run(host: VersusController, from_t: float, end_t: float) -> void:
	var t := from_t
	while t < end_t:
		t = minf(t + DT, end_t)
		host.pre_tick(t)
		host.update(t)
		host.net_tick(t)
		host.queue.pump(t)


func test_host_finish_data_has_names_and_left_flags() -> void:
	var host := _host_only(PackedStringArray(["HOSTY", "CLIENTO"]))
	_host_run(host, MatchHarness.START_T, 6.0)
	host.queue.drop_seat(1, "lost")
	var left_t := host.queue.released_t
	_host_run(host, 6.0, 7.0)
	var data := host.finish(8.0)
	assert_bool(data["online"]).is_true()
	assert_bool(data["is_host"]).is_true()
	assert_int(data["host_seat"]).is_equal(0)
	assert_str(data["host_name"]).is_equal("HOSTY")
	assert_int(data["local_seat"]).is_equal(0)
	var rows: Array = data["rows"]
	assert_int(rows.size()).is_equal(2)
	var by_seat := {}
	for r in rows:
		by_seat[int(r["seat"])] = r
	assert_str(by_seat[0]["name"]).is_equal("HOSTY")
	assert_str(by_seat[1]["name"]).is_equal("CLIENTO")
	assert_bool(by_seat[1].get("left", false)).is_true()
	assert_float(float(by_seat[1]["left_t"])).is_equal_approx(left_t, 1e-9)
	assert_bool(by_seat[0].has("left")).is_false()
	host.free()


func test_host_finish_drains_inputs_stamped_before_the_end() -> void:
	var host := _host_only(PackedStringArray(["HOSTY", "CLIENTO"]))
	var end_t := 8.0
	_host_run(host, MatchHarness.START_T, end_t)
	host.queue.push_item(1, [NetProtocol.IN_STATUS, end_t - 0.05, 0, 37.5, 123.0, 0.5, 9])
	assert_int(int(host.queue.debug_stats()["pending"])).is_greater(0)
	var data := host.finish(end_t)
	var row: Dictionary = {}
	for r in data["rows"]:
		if int(r["seat"]) == 1:
			row = r
	assert_float(float(row["hull"])).is_equal_approx(37.5, 1e-9)
	assert_float(float(row["depth"])).is_equal_approx(123.0, 1e-9)
	assert_int(int(row["max_streak"])).is_equal(9)
	assert_int(int(host.queue.debug_stats()["pending"])).is_equal(0)
	host.free()


## Clients never finish (D-19): results come from NetSession.
func test_client_finish_returns_empty() -> void:
	var p := _pair(false)
	var client: VersusController = p["client"]
	assert_dict(client.finish(2.0)).is_empty()
	_free(p)
