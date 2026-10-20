class_name RawGatePeer
extends MultiplayerPeerExtension
## WR-09: a MultiplayerPeer wrapper between SceneMultiplayer and the real ENetMultiplayerPeer
## that lets only the two SceneMultiplayer packet kinds UNDERTOW uses reach the API:
## - NETWORK_COMMAND_RAW (api.send_bytes / peer_packet: every NetCodec message), and
## - NETWORK_COMMAND_SYS + SYS_COMMAND_AUTH (api.send_auth / complete_auth).
## RPC, path-cache, spawn, sync and the other SYS commands never reach SceneMultiplayer, so a
## peer can no longer make it print an engine error per packet without ever being counted.
## On the host, every dropped packet is a strike against its sender; GATE_STRIKES strikes
## disconnect it (the session sees an ordinary peer_left). The host is trusted on clients: a
## dropped packet from it is only counted.
##
## Engine fact (Godot 4.7 SceneMultiplayer, pinned): byte 0 & CMD_MASK is the command
## (RAW = 3, SYS = 7), byte 1 of a SYS packet is the sys command (AUTH = 0).

const CMD_MASK := 7
const CMD_RAW := 3
const CMD_SYS := 7
const SYS_AUTH := 0
const GATE_STRIKES := 3

var inner: ENetMultiplayerPeer
## Packets dropped by the gate (tests / debug).
var rejected := 0
## Peers disconnected by the gate.
var gate_kicks := 0

var _queue: Array = []  # [peer, channel, mode, bytes]
var _strikes := {}  # peer -> gate strikes
var _target := 0
var _channel := 0
var _mode: TransferMode = TRANSFER_MODE_RELIABLE


func _init(p_inner: ENetMultiplayerPeer = null) -> void:
	inner = p_inner
	if inner != null:
		inner.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
		inner.peer_disconnected.connect(func(id: int) -> void:
			_strikes.erase(id)
			peer_disconnected.emit(id))


## True for the packet kinds SceneMultiplayer may see (RAW, or SYS AUTH).
static func allowed(bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	var cmd := bytes[0] & CMD_MASK
	if cmd == CMD_RAW:
		return true
	return cmd == CMD_SYS and bytes.size() >= 2 and bytes[1] == SYS_AUTH


func _poll() -> void:
	if inner == null:
		return
	inner.poll()
	while inner.get_available_packet_count() > 0:
		var from := inner.get_packet_peer()
		var ch := inner.get_packet_channel()
		var md := inner.get_packet_mode()
		var bytes := inner.get_packet()
		if allowed(bytes):
			_queue.append([from, ch, md, bytes])
			continue
		rejected += 1
		if inner.get_unique_id() == 1 and from > 1:
			var n: int = int(_strikes.get(from, 0)) + 1
			_strikes[from] = n
			if n == GATE_STRIKES:
				gate_kicks += 1
				inner.disconnect_peer(from)


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	var e: Array = _queue.pop_front()
	return e[3]


func _get_packet_peer() -> int:
	return int(_queue[0][0]) if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_queue[0][1]) if not _queue.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _queue[0][2] if not _queue.is_empty() else TRANSFER_MODE_RELIABLE


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if inner == null:
		return ERR_UNCONFIGURED
	inner.set_target_peer(_target)
	inner.set_transfer_channel(_channel)
	inner.set_transfer_mode(_mode)
	return inner.put_packet(p_buffer)


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(p_mode: TransferMode) -> void:
	_mode = p_mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(p_peer: int) -> void:
	_target = p_peer


func _is_server() -> bool:
	return inner != null and inner.get_unique_id() == 1


func _close() -> void:
	_queue.clear()
	if inner != null:
		inner.close()


func _disconnect_peer(p_peer: int, p_force: bool) -> void:
	if inner != null:
		inner.disconnect_peer(p_peer, p_force)


func _get_unique_id() -> int:
	return inner.get_unique_id() if inner != null else 0


func _set_refuse_new_connections(p_enable: bool) -> void:
	if inner != null:
		inner.refuse_new_connections = p_enable


func _is_refusing_new_connections() -> bool:
	return inner != null and inner.refuse_new_connections


func _is_server_relay_supported() -> bool:
	return inner != null and inner.is_server_relay_supported()


func _get_connection_status() -> ConnectionStatus:
	if inner == null:
		return CONNECTION_DISCONNECTED
	return inner.get_connection_status()
