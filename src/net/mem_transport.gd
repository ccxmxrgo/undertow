class_name MemTransport
extends NetTransport
## In-memory NetTransport endpoint on a virtual-time Hub (D-02, D-24), the test and
## NetMatchHarness counterpart of ENetTransport (04-06), like LoopbackChannel is for
## EventChannel.
##
## Usage: var hub := MemTransport.Hub.new(seed); var host := hub.make_host() (id 1);
## var c := hub.make_client() (ids 2, 3, 4, ...); hub.set_link(c.unique_id(), 0.08, 0.04, 0.02);
## c.connect_to_host(); c.send_auth(1, bytes); ... hub.advance(now_s) delivers everything due.
## The hub holds endpoints weakly: the caller must keep a reference to every endpoint it makes,
## or the endpoint is freed and silently stops receiving.
##
## Every signal is emitted from Hub.advance (or synchronously from the host's own call for
## complete_auth / disconnect_peer, matching what the host itself observes at once).
##
## Delivery model (per client link; the host side of a packet uses the client's link):
## - delay = latency + uniform[-jitter, +jitter] from the seeded RNG, clamped at >= 0.
## - Reliable packets (and all control packets) are FIFO per (src, dst):
##   due = max(send_time + delay, last due on that pair). They are never lost.
## - Unreliable packets are dropped with probability `loss`, and may reorder.
## - Due packets are delivered in (due, enqueue index) order.
## - drop_peer(id): queued packets to/from id vanish; after the link latency the host sees
##   peer_left(id) and the client sees server_lost.
## - stall(id): nothing reaches or leaves id, and nothing is signalled (silent host loss for the
##   4 s watchdog, D-17). unstall(id) resumes new traffic.
## - Auth: a client's send_auth reaches the host as auth_request; complete_auth emits peer_joined
##   on the host and `connected` on the client; refuse_auth delivers auth_reply and then
##   connect_failed("refused"). Data from/to a peer that is not authenticated is discarded.

enum State { IDLE, CONNECTING, CONNECTED, HOSTING, CLOSED }

var hub: Hub
var state: State = State.IDLE
var _id := 0
## Host side: authing ids (peer -> true) and members (sorted by join).
var _pending := {}
var _members: Array[int] = []
var _refuse_new := false


func _init(p_hub: Hub = null, p_id: int = 0) -> void:
	hub = p_hub
	_id = p_id


# --- NetTransport ----------------------------------------------------------------------------

func send(peer: int, bytes: PackedByteArray, reliable: bool = true) -> void:
	if hub == null:
		return
	if state == State.HOSTING:
		if peer == 0:
			for m in _members:
				hub._enqueue(_id, m, "data", bytes, reliable)
		elif _members.has(peer):
			hub._enqueue(_id, peer, "data", bytes, reliable)
	elif state == State.CONNECTED and peer == HOST_ID:
		hub._enqueue(_id, HOST_ID, "data", bytes, reliable)


func send_auth(peer: int, bytes: PackedByteArray) -> void:
	if hub == null:
		return
	if state == State.CONNECTING and peer == HOST_ID:
		hub._enqueue(_id, HOST_ID, "auth", bytes, true)
	elif state == State.HOSTING and _pending.has(peer):
		hub._enqueue(_id, peer, "auth_reply", bytes, true)


func complete_auth(peer: int) -> void:
	if state != State.HOSTING or not _pending.has(peer):
		return
	_pending.erase(peer)
	_members.append(peer)
	hub._enqueue(_id, peer, "accept", PackedByteArray(), true)
	peer_joined.emit(peer)


func refuse_auth(peer: int, reply: PackedByteArray) -> void:
	if state != State.HOSTING or not _pending.has(peer):
		return
	_pending.erase(peer)
	hub._enqueue(_id, peer, "auth_reply", reply, true)
	hub._enqueue(_id, peer, "kick", PackedByteArray(), true)


func disconnect_peer(peer: int) -> void:
	if state != State.HOSTING:
		return
	if _pending.has(peer):
		_pending.erase(peer)
		hub._enqueue(_id, peer, "kick", PackedByteArray(), true)
	elif _members.has(peer):
		_members.erase(peer)
		hub._enqueue(_id, peer, "kick", PackedByteArray(), true)
		peer_left.emit(peer)


func set_refuse_new(on: bool) -> void:
	_refuse_new = on


## Advances the shared hub to now_s (idempotent; any endpoint may pump).
func poll(now_s: float) -> void:
	if hub != null:
		hub.advance(now_s)


func close() -> void:
	if hub == null:
		return
	match state:
		State.HOSTING:
			var all: Array[int] = _members.duplicate()
			for p in _pending:
				all.append(p)
			hub._purge(_id)
			for p in all:
				hub._enqueue(_id, p, "lost", PackedByteArray(), true)
			_members.clear()
			_pending.clear()
		State.CONNECTING, State.CONNECTED:
			hub._enqueue(_id, HOST_ID, "left", PackedByteArray(), true)
	state = State.CLOSED


func unique_id() -> int:
	return _id


func is_host() -> bool:
	return _id == HOST_ID


func peers() -> PackedInt32Array:
	return PackedInt32Array(_members)


# --- Client ----------------------------------------------------------------------------------

## Starts connecting to the hub's host. connect_failed("timeout") after CONNECT_TIMEOUT_S when
## nothing answers (no host, or a stalled one).
func connect_to_host() -> void:
	if hub == null or is_host() or state != State.IDLE:
		return
	state = State.CONNECTING
	hub._schedule_self(_id, "timeout", NetProtocol.CONNECT_TIMEOUT_S)
	hub._enqueue(_id, HOST_ID, "hello", PackedByteArray(), true)


# --- Delivery (called by Hub.advance) ----------------------------------------------------------

func _deliver(src: int, kind: String, bytes: PackedByteArray) -> void:
	if state == State.CLOSED or state == State.IDLE:
		return
	if state == State.HOSTING:
		_host_deliver(src, kind, bytes)
	else:
		_client_deliver(kind, bytes)


func _host_deliver(src: int, kind: String, bytes: PackedByteArray) -> void:
	match kind:
		"hello":
			if _refuse_new or _members.size() + _pending.size() >= NetProtocol.MAX_CLIENTS:
				hub._enqueue(_id, src, "refused", PackedByteArray(), true)
			else:
				_pending[src] = true
		"auth":
			if _pending.has(src):
				auth_request.emit(src, bytes)
		"data":
			if _members.has(src):
				packet.emit(src, bytes)
		"left":
			_pending.erase(src)
			if _members.has(src):
				_members.erase(src)
				peer_left.emit(src)


func _client_deliver(kind: String, bytes: PackedByteArray) -> void:
	match kind:
		"accept":
			if state == State.CONNECTING:
				state = State.CONNECTED
				connected.emit()
		"auth_reply":
			auth_reply.emit(bytes)
		"data":
			if state == State.CONNECTED:
				packet.emit(HOST_ID, bytes)
		"refused", "kick", "lost":
			var was := state
			state = State.CLOSED
			if was == State.CONNECTED:
				server_lost.emit()
			else:
				connect_failed.emit("refused")
		"timeout":
			if state == State.CONNECTING:
				state = State.CLOSED
				connect_failed.emit("timeout")


## The shared virtual-time medium. Holds endpoints weakly (endpoints hold the hub), so the hub
## lives exactly as long as some endpoint or test reference does.
class Hub:
	extends RefCounted

	## Virtual time in seconds (only moves forward).
	var now := 0.0
	var rng := RandomNumberGenerator.new()
	## Delivered packets: [due, src, dst, size, kind] in delivery order (reproducibility checks).
	var log: Array = []
	## Unreliable packets lost to `loss`.
	var dropped := 0

	var _eps := {}  # id -> WeakRef(MemTransport)
	var _links := {}  # client id -> [latency_s, jitter_s, loss]
	var _stalled := {}
	var _queue: Array = []  # [due, idx, src, dst, kind, bytes]
	var _last_due := {}  # Vector2i(src, dst) -> float
	var _idx := 0
	var _next_client := 2

	func _init(seed_value: int = 0) -> void:
		rng.seed = hash([seed_value, "mem"])

	func make_host() -> MemTransport:
		var t := MemTransport.new(self, NetTransport.HOST_ID)
		t.state = MemTransport.State.HOSTING
		_eps[NetTransport.HOST_ID] = weakref(t)
		return t

	func make_client() -> MemTransport:
		var t := MemTransport.new(self, _next_client)
		_eps[_next_client] = weakref(t)
		_next_client += 1
		return t

	## Link settings for one client id (both directions of its link to the host).
	func set_link(id: int, latency_s: float, jitter_s: float = 0.0, loss: float = 0.0) -> void:
		_links[id] = [maxf(latency_s, 0.0), maxf(jitter_s, 0.0), clampf(loss, 0.0, 1.0)]

	## The client's link dies: queued traffic vanishes, both ends learn after the latency.
	func drop_peer(id: int) -> void:
		_purge(id)
		var ep := _ep(id)
		if ep != null and ep.state != MemTransport.State.CLOSED:
			_enqueue(id, NetTransport.HOST_ID, "left", PackedByteArray(), true)
			_enqueue(NetTransport.HOST_ID, id, "lost", PackedByteArray(), true)

	## Silently stops all delivery to and from id.
	func stall(id: int) -> void:
		_stalled[id] = true
		var keep: Array = []
		for q in _queue:
			if not _stalled.has(q[2]) and not _stalled.has(q[3]):
				keep.append(q)
		_queue = keep

	func unstall(id: int) -> void:
		_stalled.erase(id)

	func pending_count() -> int:
		return _queue.size()

	## Delivers every packet with due <= now_s in (due, enqueue index) order, including packets
	## sent by handlers during delivery that are already due.
	func advance(now_s: float) -> void:
		now = maxf(now, now_s)
		while true:
			var due: Array = []
			var keep: Array = []
			for q in _queue:
				if q[0] <= now:
					due.append(q)
				else:
					keep.append(q)
			if due.is_empty():
				return
			_queue = keep
			due.sort_custom(_by_due)
			for q in due:
				if _stalled.has(q[2]) or _stalled.has(q[3]):
					continue
				var ep := _ep(q[3])
				if ep == null:
					continue
				log.append([q[0], q[2], q[3], (q[5] as PackedByteArray).size(), q[4]])
				ep._deliver(q[2], q[4], q[5])

	static func _by_due(a: Array, b: Array) -> bool:
		if a[0] == b[0]:
			return a[1] < b[1]
		return a[0] < b[0]

	func _ep(id: int) -> MemTransport:
		var w: WeakRef = _eps.get(id)
		if w == null:
			return null
		return w.get_ref() as MemTransport

	func _enqueue(src: int, dst: int, kind: String, bytes: PackedByteArray,
			reliable: bool) -> void:
		if _stalled.has(src) or _stalled.has(dst):
			return
		var link: Array = _links.get(dst if src == NetTransport.HOST_ID else src, [0.0, 0.0, 0.0])
		var delay: float = link[0]
		if link[1] > 0.0:
			delay += rng.randf_range(-link[1], link[1])
		delay = maxf(delay, 0.0)
		var due := now + delay
		if reliable:
			var key := Vector2i(src, dst)
			due = maxf(due, _last_due.get(key, -INF))
			_last_due[key] = due
		elif link[2] > 0.0 and rng.randf() < link[2]:
			dropped += 1
			return
		_queue.append([due, _idx, src, dst, kind, bytes])
		_idx += 1

	## A control event to one endpoint itself after delay_s (connect timeout).
	func _schedule_self(id: int, kind: String, delay_s: float) -> void:
		_queue.append([now + delay_s, _idx, id, id, kind, PackedByteArray()])
		_idx += 1

	## Drops queued packets to or from id (timers to self included).
	func _purge(id: int) -> void:
		var keep: Array = []
		for q in _queue:
			if q[2] != id and q[3] != id:
				keep.append(q)
		_queue = keep
