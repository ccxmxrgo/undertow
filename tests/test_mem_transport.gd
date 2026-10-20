extends GdUnitTestSuite
## 04-01 Task 2: MemTransport, the in-memory virtual-time NetTransport (D-02, D-24).
## Latency/jitter/loss per client link, reliable FIFO, drop/stall/close and the auth flow.

const EPS := 1e-9


## Records every signal of one endpoint as [name, args...].
class Spy:
	extends RefCounted
	var log: Array = []

	func watch(t: NetTransport) -> void:
		t.packet.connect(_on_packet)
		t.peer_joined.connect(_on.bind("peer_joined"))
		t.peer_left.connect(_on.bind("peer_left"))
		t.auth_request.connect(_on_auth_request)
		t.auth_reply.connect(_on_auth_reply)
		t.connected.connect(_on0.bind("connected"))
		t.connect_failed.connect(_on_str.bind("connect_failed"))
		t.server_lost.connect(_on0.bind("server_lost"))

	func _on_packet(peer: int, bytes: PackedByteArray) -> void:
		log.append(["packet", peer, bytes])

	func _on(peer: int, name: String) -> void:
		log.append([name, peer])

	func _on0(name: String) -> void:
		log.append([name])

	func _on_str(code: String, name: String) -> void:
		log.append([name, code])

	func _on_auth_request(peer: int, bytes: PackedByteArray) -> void:
		log.append(["auth_request", peer, bytes])

	func _on_auth_reply(bytes: PackedByteArray) -> void:
		log.append(["auth_reply", bytes])

	func names() -> Array:
		var out := []
		for e in log:
			out.append(e[0])
		return out

	func packets() -> Array:
		var out := []
		for e in log:
			if e[0] == "packet":
				out.append(e)
		return out


func _b(n: int) -> PackedByteArray:
	return var_to_bytes(n)


## A hub with a host and one joined client (id 2).
func _joined(hub: MemTransport.Hub) -> Array:
	var host := hub.make_host()
	var cl := hub.make_client()
	cl.connect_to_host()
	cl.send_auth(1, _b(0))
	hub.advance(hub.now + 1.0)
	host.complete_auth(cl.unique_id())
	hub.advance(hub.now + 1.0)
	return [host, cl]


func test_ids() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	assert_int(host.unique_id()).is_equal(1)
	assert_bool(host.is_host()).is_true()
	var ids := []
	for i in 3:
		var c := hub.make_client()
		ids.append(c.unique_id())
		assert_bool(c.is_host()).is_false()
	assert_array(ids).is_equal([2, 3, 4])


func test_auth_flow_accept() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	var cl := hub.make_client()
	hub.set_link(cl.unique_id(), 0.05)
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	cl.connect_to_host()
	cl.send_auth(1, _b(42))
	hub.advance(0.049)
	assert_array(hs.log).is_empty()
	hub.advance(0.05)
	assert_array(hs.names()).is_equal(["auth_request"])
	assert_int(hs.log[0][1]).is_equal(2)
	assert_int(bytes_to_var(hs.log[0][2])).is_equal(42)
	# Data before the auth completes is never delivered.
	cl.send(1, _b(1))
	host.complete_auth(2)
	assert_array(hs.names()).is_equal(["auth_request", "peer_joined"])
	assert_array(Array(host.peers())).is_equal([2])
	hub.advance(0.2)
	assert_array(cs.names()).is_equal(["connected"])
	assert_array(hs.packets()).is_empty()
	cl.send(1, _b(7))
	host.send(2, _b(8))
	hub.advance(0.3)
	assert_int(bytes_to_var(hs.packets()[0][2])).is_equal(7)
	assert_int(bytes_to_var(cs.packets()[0][2])).is_equal(8)


func test_auth_flow_refuse() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	var cl := hub.make_client()
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	cl.connect_to_host()
	cl.send_auth(1, _b(1))
	hub.advance(0.1)
	host.refuse_auth(2, _b(99))
	hub.advance(0.2)
	assert_array(cs.names()).is_equal(["auth_reply", "connect_failed"])
	assert_int(bytes_to_var(cs.log[0][1])).is_equal(99)
	assert_str(cs.log[1][1]).is_equal("refused")
	assert_array(Array(host.peers())).is_empty()
	assert_bool(hs.names().has("peer_joined")).is_false()
	cl.send(1, _b(5))
	hub.advance(0.5)
	assert_array(hs.packets()).is_empty()


func test_refuse_new_connections() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	host.set_refuse_new(true)
	var cl := hub.make_client()
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	cl.connect_to_host()
	cl.send_auth(1, _b(1))
	hub.advance(0.5)
	assert_array(hs.log).is_empty()
	assert_array(cs.names()).is_equal(["connect_failed"])


func test_connect_without_host_times_out() -> void:
	var hub := MemTransport.Hub.new(1)
	var cl := hub.make_client()
	var cs := Spy.new()
	cs.watch(cl)
	cl.connect_to_host()
	hub.advance(NetProtocol.CONNECT_TIMEOUT_S - 0.1)
	assert_array(cs.log).is_empty()
	hub.advance(NetProtocol.CONNECT_TIMEOUT_S + 0.1)
	assert_array(cs.log).is_equal([["connect_failed", "timeout"]])


func test_latency_exact() -> void:
	var hub := MemTransport.Hub.new(1)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	hub.set_link(2, 0.08)
	var hs := Spy.new()
	hs.watch(host)
	var t0 := hub.now
	cl.send(1, _b(1))
	hub.advance(t0 + 0.0799)
	assert_array(hs.packets()).is_empty()
	hub.advance(t0 + 0.08)
	assert_int(hs.packets().size()).is_equal(1)


func test_reliable_fifo_under_jitter_and_unreliable_reorders() -> void:
	var hub := MemTransport.Hub.new(5)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	hub.set_link(2, 0.08, 0.04)
	var hs := Spy.new()
	hs.watch(host)
	var t0 := hub.now
	for i in 500:
		hub.advance(t0 + i * 0.001)
		cl.send(1, _b(i), true)
	hub.advance(t0 + 2.0)
	var got := []
	for p in hs.packets():
		got.append(bytes_to_var(p[2]))
	var want := []
	for i in 500:
		want.append(i)
	assert_array(got).is_equal(want)
	# Unreliable: each delay is in [40, 120] ms and order is not preserved.
	hs.log.clear()
	var t1 := hub.now
	var sent_at := {}
	var arrivals := []
	for step in 2000:
		var t := t1 + step * 0.0005
		var before := hs.packets().size()
		hub.advance(t)
		var pk := hs.packets()
		for k in range(before, pk.size()):
			arrivals.append([bytes_to_var(pk[k][2]), t])
		if step % 2 == 0 and step / 2 < 500:
			sent_at[step / 2] = t
			cl.send(1, _b(step / 2), false)
	assert_int(arrivals.size()).is_equal(500)
	var reordered := false
	for k in arrivals.size():
		var d: float = arrivals[k][1] - sent_at[arrivals[k][0]]
		assert_float(d).is_greater_equal(0.04 - 0.001)
		assert_float(d).is_less_equal(0.12 + 0.001)
		if k > 0 and arrivals[k][0] < arrivals[k - 1][0]:
			reordered = true
	assert_bool(reordered).is_true()


func test_loss_only_on_unreliable() -> void:
	var hub := MemTransport.Hub.new(9)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	hub.set_link(2, 0.01, 0.0, 0.02)
	var hs := Spy.new()
	hs.watch(host)
	for i in 5000:
		cl.send(1, _b(i), false)
	hub.advance(hub.now + 1.0)
	var lost := 5000 - hs.packets().size()
	assert_float(lost / 5000.0).is_between(0.01, 0.03)
	hs.log.clear()
	for i in 5000:
		cl.send(1, _b(i), true)
	hub.advance(hub.now + 1.0)
	assert_int(hs.packets().size()).is_equal(5000)


func test_drop_peer() -> void:
	var hub := MemTransport.Hub.new(1)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	hub.set_link(2, 0.05)
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	var t0 := hub.now
	hub.drop_peer(2)
	hub.advance(t0 + 0.049)
	assert_array(hs.log).is_empty()
	hub.advance(t0 + 0.05)
	assert_array(hs.log).is_equal([["peer_left", 2]])
	assert_array(cs.names()).is_equal(["server_lost"])
	assert_array(Array(host.peers())).is_empty()


func test_disconnect_peer_kicks() -> void:
	var hub := MemTransport.Hub.new(1)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	host.disconnect_peer(2)
	assert_array(hs.log).is_equal([["peer_left", 2]])
	hub.advance(hub.now + 0.1)
	assert_array(cs.names()).is_equal(["server_lost"])
	cl.send(1, _b(1))
	hub.advance(hub.now + 0.1)
	assert_array(hs.packets()).is_empty()


func test_client_close_is_seen_by_host() -> void:
	var hub := MemTransport.Hub.new(1)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	var hs := Spy.new()
	hs.watch(host)
	cl.close()
	hub.advance(hub.now + 0.1)
	assert_array(hs.log).is_equal([["peer_left", 2]])


func test_stall_is_silent() -> void:
	var hub := MemTransport.Hub.new(1)
	var pair := _joined(hub)
	var host: MemTransport = pair[0]
	var cl: MemTransport = pair[1]
	var hs := Spy.new()
	var cs := Spy.new()
	hs.watch(host)
	cs.watch(cl)
	hub.stall(1)
	host.send(2, _b(1))
	cl.send(1, _b(2))
	hub.advance(hub.now + 10.0)
	assert_array(hs.log).is_empty()
	assert_array(cs.log).is_empty()
	assert_int(hub.pending_count()).is_equal(0)


func test_host_close_loses_every_client() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	var spies := []
	var keep := []
	for i in 3:
		var c := hub.make_client()
		c.connect_to_host()
		c.send_auth(1, _b(0))
		var s := Spy.new()
		keep.append(c)
		s.watch(c)
		spies.append(s)
	hub.advance(0.1)
	for id in [2, 3, 4]:
		host.complete_auth(id)
	hub.advance(0.2)
	host.close()
	hub.advance(0.3)
	for s in spies:
		assert_array(s.names()).is_equal(["connected", "server_lost"])
	assert_array(Array(host.peers())).is_empty()


func test_broadcast_peer_zero() -> void:
	var hub := MemTransport.Hub.new(1)
	var host := hub.make_host()
	var spies := []
	var keep := []
	for i in 2:
		var c := hub.make_client()
		c.connect_to_host()
		c.send_auth(1, _b(0))
		var s := Spy.new()
		keep.append(c)
		s.watch(c)
		spies.append(s)
	hub.advance(0.1)
	host.complete_auth(2)
	host.complete_auth(3)
	host.send(0, _b(5))
	hub.advance(0.2)
	for s in spies:
		assert_int(s.packets().size()).is_equal(1)


func _scenario(seed_value: int) -> Array:
	var hub := MemTransport.Hub.new(seed_value)
	var host := hub.make_host()
	var cls := []
	for i in 3:
		var c := hub.make_client()
		c.connect_to_host()
		c.send_auth(1, _b(i))
		hub.set_link(c.unique_id(), 0.03 + 0.02 * i, 0.015, 0.05)
		cls.append(c)
	hub.advance(0.5)
	for id in [2, 3, 4]:
		host.complete_auth(id)
	hub.advance(1.0)
	for k in 300:
		var t := 1.0 + k * 0.004
		hub.advance(t)
		var c: MemTransport = cls[k % 3]
		c.send(1, _b(k), k % 2 == 0)
		host.send(c.unique_id(), _b(k), k % 3 == 0)
	hub.advance(5.0)
	return hub.log.duplicate(true)


func test_seeded_runs_are_reproducible() -> void:
	var a := _scenario(123)
	var b := _scenario(123)
	var c := _scenario(124)
	assert_int(a.size()).is_greater(400)
	assert_str(var_to_str(b)).is_equal(var_to_str(a))
	assert_str(var_to_str(c)).is_not_equal(var_to_str(a))
