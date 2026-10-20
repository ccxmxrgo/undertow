extends GdUnitTestSuite
## 04-06 Task 1: ENetTransport on 127.0.0.1, host and clients as separate manually polled
## SceneMultiplayer instances in one process (Pitfall 13, assumption A5). Ports are random in
## 49000-49900 so a running game on 47474 can never collide.

const CAP_S := 5.0


## Records every signal of one endpoint as [name, args...].
class Spy:
	extends RefCounted
	var log: Array = []

	func watch(t: NetTransport) -> void:
		t.packet.connect(func(p: int, b: PackedByteArray) -> void: log.append(["packet", p, b]))
		t.peer_joined.connect(func(p: int) -> void: log.append(["peer_joined", p]))
		t.peer_left.connect(func(p: int) -> void: log.append(["peer_left", p]))
		t.auth_request.connect(
			func(p: int, b: PackedByteArray) -> void: log.append(["auth_request", p, b]))
		t.auth_reply.connect(func(b: PackedByteArray) -> void: log.append(["auth_reply", b]))
		t.connected.connect(func() -> void: log.append(["connected"]))
		t.connect_failed.connect(func(c: String) -> void: log.append(["connect_failed", c]))
		t.server_lost.connect(func() -> void: log.append(["server_lost"]))

	func has(name: String) -> bool:
		for e in log:
			if e[0] == name:
				return true
		return false

	func first(name: String) -> Array:
		for e in log:
			if e[0] == name:
				return e
		return []

	func all(name: String) -> Array:
		var out := []
		for e in log:
			if e[0] == name:
				out.append(e)
		return out


var _eps: Array = []


func after_test() -> void:
	for t in _eps:
		(t as ENetTransport).close()
	_eps.clear()


func _port() -> int:
	return 49000 + randi() % 901


func _host(max_clients: int = 3) -> Array:
	for _attempt in 5:
		var h := ENetTransport.new()
		var port := _port()
		if h.host(port, max_clients) == OK:
			_eps.append(h)
			var spy := Spy.new()
			spy.watch(h)
			return [h, spy, port]
	return []


func _client(port: int) -> Array:
	var c := ENetTransport.new()
	assert_int(c.join("127.0.0.1", port)).is_equal(OK)
	_eps.append(c)
	var spy := Spy.new()
	spy.watch(c)
	return [c, spy]


## Polls every endpoint until cond() is true or CAP_S passes. Returns cond().
func _pump(cond: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(CAP_S * 1000.0):
		for t in _eps:
			(t as ENetTransport).poll(0.0)
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


## Polls every endpoint for `secs` seconds.
func _pump_for(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		for t in _eps:
			(t as ENetTransport).poll(0.0)
		await get_tree().process_frame


## Host accepts every auth request at once.
func _host_accepts(h: ENetTransport) -> void:
	h.auth_request.connect(func(p: int, _b: PackedByteArray) -> void:
		h.send_auth(p, "ok".to_utf8_buffer())
		h.complete_auth(p))


## The client completes its side when the host's reply arrives.
func _client_completes(c: ENetTransport) -> void:
	c.auth_reply.connect(func(_b: PackedByteArray) -> void: c.complete_auth(1))


func _start_auth(c: ENetTransport) -> void:
	c.api.peer_authenticating.connect(func(_id: int) -> void:
		c.send_auth(1, "hello".to_utf8_buffer()))


func test_engine_flags() -> void:
	var t := ENetTransport.new()
	assert_bool(t.api.server_relay).is_false()
	assert_bool(t.api.allow_object_decoding).is_false()
	assert_float(t.api.auth_timeout).is_equal_approx(3.0, 0.001)
	t.set_refuse_new(true)
	assert_bool(t.api.refuse_new_connections).is_true()
	t.close()


func test_a_auth_handshake_accepted() -> void:
	var hs := _host()
	assert_array(hs).is_not_empty()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var cs := _client(hs[2])
	var c: ENetTransport = cs[0]
	var cspy: Spy = cs[1]
	_start_auth(c)
	_client_completes(c)
	var ok: bool = await _pump(func() -> bool: return cspy.has("connected") and hspy.has("peer_joined"))
	assert_bool(ok).is_true()
	var req := hspy.first("auth_request")
	assert_array(req).is_not_empty()
	assert_str((req[2] as PackedByteArray).get_string_from_utf8()).is_equal("hello")
	assert_str((cspy.first("auth_reply")[1] as PackedByteArray).get_string_from_utf8()) \
		.is_equal("ok")
	assert_int(hspy.first("peer_joined")[1]).is_equal(c.unique_id())
	assert_bool(h.peers().has(c.unique_id())).is_true()
	assert_bool(h.is_host()).is_true()
	assert_bool(c.is_host()).is_false()
	assert_int(h.unique_id()).is_equal(1)


func test_b_refusal_reply_then_disconnect() -> void:
	var hs := _host()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	var cs := _client(hs[2])
	var c: ENetTransport = cs[0]
	var cspy: Spy = cs[1]
	_start_auth(c)
	h.auth_request.connect(func(p: int, _b: PackedByteArray) -> void:
		h.refuse_auth(p, "nope".to_utf8_buffer()))
	var ok: bool = await _pump(func() -> bool: return cspy.has("connect_failed"))
	assert_bool(ok).is_true()
	var reply := cspy.first("auth_reply")
	assert_array(reply).is_not_empty()
	assert_str((reply[1] as PackedByteArray).get_string_from_utf8()).is_equal("nope")
	# The reply arrived before the drop.
	assert_int(cspy.log.find(reply)).is_less(cspy.log.find(cspy.first("connect_failed")))
	assert_bool(cspy.has("connected")).is_false()
	assert_bool(hspy.has("peer_joined")).is_false()


func test_c_bytes_both_ways_both_channels() -> void:
	var hs := _host()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var c1s := _client(hs[2])
	var c2s := _client(hs[2])
	for cs in [c1s, c2s]:
		_start_auth(cs[0])
		_client_completes(cs[0])
	var ok: bool = await _pump(func() -> bool:
		return (c1s[1] as Spy).has("connected") and (c2s[1] as Spy).has("connected") \
			and hspy.all("peer_joined").size() == 2)
	assert_bool(ok).is_true()
	var big := PackedByteArray()
	big.resize(3000)
	for i in big.size():
		big[i] = i % 251
	var c1: ENetTransport = c1s[0]
	var c2: ENetTransport = c2s[0]
	c1.send(1, var_to_bytes({"a": 1}), true)
	c1.send(1, var_to_bytes({"u": 1}), false)
	c2.send(1, big, true)
	h.send(c1.unique_id(), var_to_bytes("to1"), true)
	h.send(0, var_to_bytes("all"), false)
	ok = await _pump(func() -> bool:
		return hspy.all("packet").size() >= 3 and (c1s[1] as Spy).all("packet").size() >= 2 \
			and (c2s[1] as Spy).all("packet").size() >= 1)
	assert_bool(ok).is_true()
	var got_host := {}
	for e in hspy.all("packet"):
		got_host[e[1]] = got_host.get(e[1], []) + [e[2]]
	assert_bool((got_host[c1.unique_id()] as Array).has(var_to_bytes({"a": 1}))).is_true()
	assert_bool((got_host[c1.unique_id()] as Array).has(var_to_bytes({"u": 1}))).is_true()
	assert_bool((got_host[c2.unique_id()] as Array).has(big)).is_true()
	var c1_got := []
	for e in (c1s[1] as Spy).all("packet"):
		assert_int(e[1]).is_equal(1)
		c1_got.append(bytes_to_var(e[2]))
	assert_bool(c1_got.has("to1")).is_true()
	assert_bool(c1_got.has("all")).is_true()
	var c2_got := []
	for e in (c2s[1] as Spy).all("packet"):
		c2_got.append(bytes_to_var(e[2]))
	assert_array(c2_got).contains(["all"])
	assert_bool(c2_got.has("to1")).is_false()
	assert_int(h.rtt_ms(c1.unique_id())).is_greater_equal(0)


func test_d_client_beyond_max_is_not_accepted() -> void:
	var hs := _host(1)
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var c1s := _client(hs[2])
	_start_auth(c1s[0])
	_client_completes(c1s[0])
	var ok: bool = await _pump(func() -> bool: return (c1s[1] as Spy).has("connected"))
	assert_bool(ok).is_true()
	var c2s := _client(hs[2])
	_start_auth(c2s[0])
	_client_completes(c2s[0])
	# ENet has no free peer slot: the connect is never answered (the client would time out on
	# its own after ENet's connect timeout). Within 1.5 s it is not accepted and never authed.
	await _pump_for(1.5)
	assert_bool((c2s[1] as Spy).has("connected")).is_false()
	assert_bool((c2s[1] as Spy).has("auth_reply")).is_false()
	assert_int(hspy.all("peer_joined").size()).is_equal(1)
	assert_int(hspy.all("auth_request").size()).is_equal(1)
	assert_int(h.peers().size()).is_equal(1)


func test_e_close_seen_as_left_and_lost() -> void:
	var hs := _host()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var c1s := _client(hs[2])
	var c2s := _client(hs[2])
	for cs in [c1s, c2s]:
		_start_auth(cs[0])
		_client_completes(cs[0])
	var ok: bool = await _pump(func() -> bool:
		return (c1s[1] as Spy).has("connected") and (c2s[1] as Spy).has("connected") \
			and hspy.all("peer_joined").size() == 2)
	assert_bool(ok).is_true()
	var c1: ENetTransport = c1s[0]
	var id1 := c1.unique_id()
	c1.close()
	ok = await _pump(func() -> bool: return hspy.has("peer_left"))
	assert_bool(ok).is_true()
	assert_int(hspy.first("peer_left")[1]).is_equal(id1)
	h.close()
	ok = await _pump(func() -> bool: return (c2s[1] as Spy).has("server_lost"))
	assert_bool(ok).is_true()


func test_kick_member_reports_left_once() -> void:
	var hs := _host()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var cs := _client(hs[2])
	_start_auth(cs[0])
	_client_completes(cs[0])
	var ok: bool = await _pump(func() -> bool:
		return (cs[1] as Spy).has("connected") and hspy.has("peer_joined"))
	assert_bool(ok).is_true()
	var id := (cs[0] as ENetTransport).unique_id()
	h.disconnect_peer(id)
	ok = await _pump(func() -> bool: return (cs[1] as Spy).has("server_lost"))
	assert_bool(ok).is_true()
	assert_int(hspy.all("peer_left").size()).is_equal(1)


func test_resolve_failure_reports_resolve() -> void:
	var c := ENetTransport.new()
	_eps.append(c)
	var spy := Spy.new()
	spy.watch(c)
	c.join("no-such-host.invalid", 49999)
	var ok: bool = await _pump(func() -> bool: return spy.has("connect_failed"))
	assert_bool(ok).is_true()
	assert_str(spy.first("connect_failed")[1]).is_equal("resolve")


# --- Review fix WR-09: only RAW and SYS AUTH packets reach SceneMultiplayer -----------------------

func test_gate_allows_only_raw_and_auth() -> void:
	assert_bool(RawGatePeer.allowed(PackedByteArray([3, 1, 2]))).is_true()  # RAW
	assert_bool(RawGatePeer.allowed(PackedByteArray([7, 0, 9]))).is_true()  # SYS AUTH
	assert_bool(RawGatePeer.allowed(PackedByteArray([7, 0]))).is_true()  # auth complete
	assert_bool(RawGatePeer.allowed(PackedByteArray([7, 3, 0]))).is_false()  # SYS RELAY
	for cmd in [0, 1, 2, 4, 5, 6]:  # RPC, path cache, spawn, despawn, sync
		assert_bool(RawGatePeer.allowed(PackedByteArray([cmd, 0, 0, 0]))).is_false()
	assert_bool(RawGatePeer.allowed(PackedByteArray())).is_false()


func test_member_sending_non_raw_commands_is_disconnected() -> void:
	var hs := _host()
	var h: ENetTransport = hs[0]
	var hspy: Spy = hs[1]
	_host_accepts(h)
	var cs := _client(hs[2])
	var c: ENetTransport = cs[0]
	_start_auth(c)
	_client_completes(c)
	var ok: bool = await _pump(func() -> bool:
		return (cs[1] as Spy).has("connected") and hspy.has("peer_joined"))
	assert_bool(ok).is_true()
	# Raw bytes still flow.
	c.send(1, "fine".to_utf8_buffer())
	ok = await _pump(func() -> bool: return hspy.has("packet"))
	assert_bool(ok).is_true()
	# Crafted SceneMultiplayer RPC / path-cache packets, straight on the ENet peer.
	for i in 3:
		c.peer.set_target_peer(1)
		c.peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
		c.peer.put_packet(PackedByteArray([1 if i % 2 == 0 else 0, 0, 0, 0, 0, 0]))
	ok = await _pump(func() -> bool: return hspy.has("peer_left"))
	assert_bool(ok).is_true()
	assert_int(h.gate.rejected).is_equal(3)
	assert_int(h.gate.gate_kicks).is_equal(1)
	assert_int(hspy.all("peer_left").size()).is_equal(1)
