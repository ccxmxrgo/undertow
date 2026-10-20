class_name ENetTransport
extends NetTransport
## The real NetTransport: raw bytes over SceneMultiplayer + ENetMultiplayerPeer (D-01, D-02,
## D-17, D-21, D-22). NetSession sees only the NetTransport signals and methods.
##
## Engine facts (Godot 4.7):
## - 2 ENet channels: 0 reliable-ordered (lobby, inputs, events), 1 unreliable (pings,
##   heartbeats). Data goes through api.send_bytes / api.peer_packet only; there are no @rpc
##   calls, and allow_object_decoding stays at its default (off), so a peer can never make us
##   instantiate an object (T-04-18).
## - server_relay is off: star topology, clients can never address each other (D-22, T-04-17).
## - Auth: api.auth_callback(id, data) receives the other side's send_auth payloads while the
##   peer is authenticating. The host answers with an AUTH_REPLY via send_auth. A connection is
##   admitted (peer_connected on both sides) only once BOTH sides call complete_auth, so the
##   client calls complete_auth(1) when its session sees an accepting AUTH_REPLY. Once a side
##   has completed locally, further auth payloads from the other side are no longer delivered,
##   which is why the client must not complete before the reply arrives.
## - auth_timeout = 3.0 s: an authing peer that never finishes is dropped by the engine.
## - refuse_new_connections implements set_refuse_new (from LOAD until back in the lobby).
## - ENet peer timeouts are set per connected ENetPacketPeer to set_timeout(32, 4000, 10000)
##   (D-17); the session's own 4 s watchdog does not depend on them.
## - ENet disconnect resets the peer's queued outgoing packets, so refuse_auth sends the reply,
##   lets one poll flush it, and only then disconnects.
## - The SceneMultiplayer here is never attached to the SceneTree: it is polled by hand through
##   poll(), so several transports can live in one process (Pitfall 13, assumption A5).
## - Hostname resolution is asynchronous (IP.resolve_hostname_queue_item), so join() never
##   blocks; a failed lookup is reported as connect_failed("resolve") from poll().
## Never blocks, never throws: methods return Error codes or do nothing.

const CHANNELS := 2
const PEER_TIMEOUT_LIMIT := 32
const PEER_TIMEOUT_MIN_MS := 4000
const PEER_TIMEOUT_MAX_MS := 10000
## A node path that never exists (see _init).
const ROOT_PATH := NodePath("/root/__undertow_net_raw_only__")

var api := SceneMultiplayer.new()
var peer: ENetMultiplayerPeer

var _hosting := false
var _client_connected := false
var _closed := false
## Host: admitted member ids (peer_left is emitted exactly once per member).
var _members := {}
## Host: peers to disconnect on the next poll (after a refusal reply was flushed).
var _drop_next: Array[int] = []
var _drop_now: Array[int] = []
## Client: pending async hostname resolution.
var _resolve_id := -1
var _resolve_port := 0
var _resolve_failed := false


func _init() -> void:
	# SceneMultiplayer refuses to process even raw packets without a root path. Point it at a
	# node that never exists: raw bytes never touch the tree, and any RPC/spawn/sync packet a
	# hostile peer crafts resolves to nothing.
	api.root_path = ROOT_PATH
	api.server_relay = false
	api.auth_timeout = NetProtocol.AUTH_TIMEOUT_S
	api.auth_callback = _on_auth
	api.peer_packet.connect(_on_peer_packet)
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.server_disconnected.connect(_on_server_disconnected)
	api.connection_failed.connect(_on_connection_failed)


## Opens a UDP server. max_clients defaults to NetProtocol.MAX_CLIENTS (3).
func host(port: int, max_clients: int = NetProtocol.MAX_CLIENTS) -> Error:
	if peer != null:
		return ERR_ALREADY_IN_USE
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, max_clients, CHANNELS)
	if err != OK:
		return err
	peer = p
	api.multiplayer_peer = peer
	_hosting = true
	return OK


## Connects to address:port. IP literals connect at once; hostnames resolve asynchronously.
func join(address: String, port: int) -> Error:
	if peer != null or _resolve_id >= 0:
		return ERR_ALREADY_IN_USE
	var a := address.strip_edges().trim_prefix("[").trim_suffix("]")
	if a.is_empty():
		_resolve_failed = true
		return ERR_CANT_RESOLVE
	if a.is_valid_ip_address():
		return _create_client(a, port)
	_resolve_id = IP.resolve_hostname_queue_item(a)
	_resolve_port = port
	if _resolve_id < 0:
		_resolve_failed = true
		return ERR_CANT_RESOLVE
	return OK


func _create_client(ip: String, port: int) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port, CHANNELS)
	if err != OK:
		return err
	peer = p
	api.multiplayer_peer = peer
	var pp := peer.get_peer(HOST_ID)
	if pp != null:
		pp.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	return OK


# --- NetTransport ----------------------------------------------------------------------------

func send(p_peer: int, bytes: PackedByteArray, reliable: bool = true) -> void:
	if peer == null or _closed:
		return
	if not _hosting and (p_peer != HOST_ID or not _client_connected):
		return
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable \
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	var ch := NetProtocol.CH_RELIABLE if reliable else NetProtocol.CH_UNRELIABLE
	api.send_bytes(bytes, p_peer, mode, ch)


func send_auth(p_peer: int, bytes: PackedByteArray) -> void:
	if peer == null or _closed or bytes.is_empty():
		return
	if not api.get_authenticating_peers().has(p_peer):
		return
	api.send_auth(p_peer, bytes)


## Host: accept an authing peer. Client: complete_auth(1) once the host accepted.
func complete_auth(p_peer: int) -> void:
	if peer == null or _closed:
		return
	if not api.get_authenticating_peers().has(p_peer):
		return
	api.complete_auth(p_peer)


func refuse_auth(p_peer: int, reply: PackedByteArray) -> void:
	if not _hosting or peer == null or _closed:
		return
	if not api.get_authenticating_peers().has(p_peer):
		return
	api.send_auth(p_peer, reply)
	if not _drop_next.has(p_peer):
		_drop_next.append(p_peer)


func disconnect_peer(p_peer: int) -> void:
	if not _hosting or peer == null or _closed:
		return
	var known := api.get_peers().has(p_peer) or api.get_authenticating_peers().has(p_peer)
	if not known:
		return
	api.disconnect_peer(p_peer)
	# A deliberate kick of a member is reported like any other departure (once).
	_member_left(p_peer)


func set_refuse_new(on: bool) -> void:
	api.refuse_new_connections = on


func poll(_now_s: float) -> void:
	if _closed:
		return
	if _resolve_failed:
		_resolve_failed = false
		connect_failed.emit("resolve")
		return
	if _resolve_id >= 0:
		_poll_resolve()
		return
	if peer == null:
		return
	# Refusals sent on the previous poll have been flushed by now.
	for id in _drop_now:
		if api.get_authenticating_peers().has(id) or api.get_peers().has(id):
			api.disconnect_peer(id)
	_drop_now = _drop_next
	_drop_next = []
	api.poll()


func _poll_resolve() -> void:
	var st := IP.get_resolve_item_status(_resolve_id)
	if st == IP.RESOLVER_STATUS_WAITING:
		return
	var ip := ""
	if st == IP.RESOLVER_STATUS_DONE:
		ip = IP.get_resolve_item_address(_resolve_id)
	IP.erase_resolve_item(_resolve_id)
	_resolve_id = -1
	if ip.is_empty() or _create_client(ip, _resolve_port) != OK:
		connect_failed.emit("resolve")


func close() -> void:
	if _closed:
		return
	_closed = true
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1
	if peer != null:
		peer.close()
	api.multiplayer_peer = null


func unique_id() -> int:
	if peer == null:
		return 0
	return peer.get_unique_id()


func is_host() -> bool:
	return _hosting


func peers() -> PackedInt32Array:
	if peer == null or not _hosting:
		return PackedInt32Array()
	return api.get_peers()


## Debug only: ENet's smoothed round trip to `p_peer` in ms, or -1.
func rtt_ms(p_peer: int) -> int:
	if peer == null or _closed:
		return -1
	var pp := peer.get_peer(p_peer)
	if pp == null:
		return -1
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


# --- Engine signal mapping -------------------------------------------------------------------

func _on_auth(id: int, data: PackedByteArray) -> void:
	if _hosting:
		auth_request.emit(id, data)
	elif id == HOST_ID:
		auth_reply.emit(data)


func _on_peer_authenticating(id: int) -> void:
	if peer == null:
		return
	var pp := peer.get_peer(id)
	if pp != null:
		pp.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_packet(id: int, bytes: PackedByteArray) -> void:
	packet.emit(id, bytes)


func _on_peer_connected(id: int) -> void:
	if _hosting:
		_members[id] = true
		peer_joined.emit(id)
	elif id == HOST_ID and not _client_connected:
		_client_connected = true
		connected.emit()


func _on_peer_disconnected(id: int) -> void:
	if _hosting:
		_member_left(id)


func _member_left(id: int) -> void:
	if _members.has(id):
		_members.erase(id)
		peer_left.emit(id)


func _on_server_disconnected() -> void:
	if _hosting or _closed:
		return
	var was := _client_connected
	_client_connected = false
	_closed = true
	if was:
		server_lost.emit()
	else:
		connect_failed.emit("refused")


func _on_connection_failed() -> void:
	if _hosting or _closed:
		return
	_closed = true
	connect_failed.emit("timeout")
