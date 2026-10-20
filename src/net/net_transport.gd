class_name NetTransport
extends RefCounted
## The seam between the online session and whatever moves bytes (D-01, D-02, D-21, D-22), like
## EventChannel is for the referee. Implementations:
## - ENetTransport (04-06): SceneMultiplayer.send_bytes / peer_packet over ENetMultiplayerPeer,
##   channel 0 reliable-ordered, channel 1 unreliable, auth_callback for the handshake.
## - MemTransport (this plan): in-memory, virtual time, latency/jitter/loss, for tests and the
##   NetMatchHarness.
## The session never sees anything but these signals and methods. Every packet it receives goes
## through NetCodec.decode; the sender id is the only source of a peer's seat.
##
## Peer ids follow Godot: the host is always 1, clients get other ids. Star topology: clients
## only ever talk to the host (peer 1). The base class is a safe no-op.

## A data packet arrived from `peer` (host side: an authenticated client; client side: 1).
signal packet(peer: int, bytes: PackedByteArray)
## Host side: `peer` finished auth (complete_auth) and is now a member.
signal peer_joined(peer: int)
## Host side: an authenticated `peer` left (disconnect, drop, kick).
signal peer_left(peer: int)
## Host side: `peer` sent its auth payload (NetProtocol.AUTH bytes).
signal auth_request(peer: int, bytes: PackedByteArray)
## Client side: the host sent an auth payload (NetProtocol.AUTH_REPLY bytes).
signal auth_reply(bytes: PackedByteArray)
## Client side: the host accepted the auth; data may flow.
signal connected
## Client side: the connection never got established. code: "timeout", "resolve", "refused".
signal connect_failed(code: String)
## Client side: an established (or authing) connection to the host was lost.
signal server_lost

const HOST_ID := 1


## Sends bytes. reliable = channel 0 (ordered), else channel 1 (may drop). Host: peer 0 sends
## to every member.
func send(_peer: int, _bytes: PackedByteArray, _reliable: bool = true) -> void:
	pass


## Auth-phase payload (before complete_auth). Client -> host or host -> client.
func send_auth(_peer: int, _bytes: PackedByteArray) -> void:
	pass


## Host: accept an authing peer.
func complete_auth(_peer: int) -> void:
	pass


## Host: send `reply` (AUTH_REPLY) to an authing peer, then disconnect it.
func refuse_auth(_peer: int, _reply: PackedByteArray) -> void:
	pass


## Host: kick a peer.
func disconnect_peer(_peer: int) -> void:
	pass


## Host: refuse new connections (true from LOAD until back in the lobby, D-12).
func set_refuse_new(_on: bool) -> void:
	pass


## Pumps the transport; called once per frame with the current time in seconds.
func poll(_now_s: float) -> void:
	pass


## Leaves (client) or shuts the server down (host).
func close() -> void:
	pass


func unique_id() -> int:
	return 0


func is_host() -> bool:
	return false


## Host: the authenticated member ids.
func peers() -> PackedInt32Array:
	return PackedInt32Array()
