extends Node
## Autoload "NetSession": the online session, lobby half (D-01, D-06, D-11, D-12, D-17, D-20,
## D-21, D-22, D-23). Plan 04-10 adds the match half (LOAD/START/inputs/events/results).
##
## Rules:
## - Every packet from any peer goes through NetCodec.decode (ctx.from_host set for the
##   receiving side). Anything it rejects is dropped; on the host it is a strike, and
##   NetProtocol.STRIKES_TO_KICK strikes disconnect the peer.
## - A seat always comes from the sender's peer id (LobbyState binds it at join), never from a
##   payload. Clients accept host messages only from peer 1 (NetTransport.HOST_ID).
## - Song matching is by fingerprint + VersusSig only (D-11): no path ever crosses the wire.
## - PING is rate limited per peer by a token bucket (capacity NetProtocol.PING_BUCKET, refill
##   NetProtocol.MAX_PINGS_PER_S); overflow is dropped silently and is never a strike.
##
## Roles:
## - Host: seat 0, owns the LobbyState, answers auth (proto/game version, lobby phase, room,
##   name), sends LOBBY when LobbyState.revision changes (at most every 0.1 s) and once per
##   second, pings each client (8-ping burst on join, then 1 Hz) for the roster PING column.
## - Client: connect stages "connecting" -> "auth" -> "sync" -> "lobby". Bursts 16 pings at
##   50 ms on join and when Ready turns on (skipped while a burst runs), then 1 Hz, and keeps a
##   ClockSync of the host clock. It reports its own ClockSync.is_synced() in READY and
##   SONG_STATUS (again when it flips to true); the start gate uses that value. It checks the
##   host's song against its own library and answers SONG_STATUS ok / missing / changed. Its
##   seat arrives in NOTICE {code "welcome", name, n = seat} right after the host admits it.
##
## Testability: transport_factory (role -> NetTransport), ticks_fn (microseconds), library and
## settings are injectable; tests set auto_process = false and drive step(now_s) with virtual
## time over MemTransport.

signal connect_stage(stage: String)
## Codes: timeout, resolve, version (info.host_version), full, in_match, bad_name, lost.
signal connect_error(code: String, info: Dictionary)
signal lobby_changed
## Codes: choosing, joined, left, kicked_other, song_picked, flight_set (n = beats), ready,
## missing (n = 0 missing, 1 changed), high_latency (n = ping ms). info = {name, n}.
signal log_line(code: String, info: Dictionary)
## A client left the lobby involuntarily. Codes: kicked, closed, lost.
signal left_lobby(code: String)

## 04-10 appends LOADING, PLAYING and RESULTS after LOBBY.
enum State { OFFLINE, CONNECTING, AUTHING, SYNCING, LOBBY }

const BURST_PINGS := 16
const BURST_GAP_S := 0.05
const PING_PERIOD_S := 1.0
const HOST_BURST_PINGS := 8
const LOBBY_RESEND_S := 1.0
const LOBBY_MIN_GAP_S := 0.1
## A joining client enters the lobby once synced, or after this long in "sync" regardless
## (its row then shows unsynced and the start gate waits).
const SYNC_CAP_S := 3.0
## Host leave(): LOBBY_CLOSED gets this long to flush before the transport closes (D-17).
const CLOSE_GRACE_S := 0.1
## kick(): the kicked client normally leaves on KICKED itself; the host disconnects it after
## this long anyway. ENet drops a peer's queued and unprocessed packets on disconnect, so an
## immediate disconnect would swallow the KICKED reason.
const KICK_GRACE_S := 0.5
## Accepted-but-not-admitted peers hold a seat reservation this long.
const ACCEPT_TTL_S := 5.0
const MAX_OUTSTANDING := 64
## ENet server slots: one more than the seats so a 4th joiner can be told "full".
const ENET_SLOTS := NetProtocol.MAX_CLIENTS + 1
const NOTICE_WELCOME := "welcome"
const PHASE_LOBBY := "lobby"
const SONG_KEYS: Array[String] = ["fp", "sig", "diff", "title", "artist"]

# --- Injection ---------------------------------------------------------------------------------
## role ("host" | "client") -> NetTransport. Default: ENetTransport.new().
var transport_factory: Callable
## -> int microseconds. Default: Time.get_ticks_usec.
var ticks_fn: Callable
## Duck-typed SongLibrary (entries[].difficulty(diff).fingerprint, build_chart(entry, diff)).
## Null resolves /root/SongLibrary.
var library: Object
## Anything with player_name. Null resolves /root/Settings.
var settings: Object
## False in tests: step() is driven by hand.
var auto_process := true
## Test seams for the handshake.
var game_version_override := ""
var proto_override := -1

var transport: NetTransport
var state: State = State.OFFLINE
## Error of the last host() call (OK on success).
var last_error_code: int = OK
## Client: the host clock estimate (host_ticks = client_ticks + offset).
var clock := ClockSync.new()

var _is_host := false
var _now := 0.0
var _step_i := 0
var _times_pending := false
var _return_message := ""
var _retired: Array = []  # [NetTransport, close_at_s]
var _stats := {"pings_sent": 0, "ping_dropped": 0, "rejected_packets": 0}

# Host.
var _lobby: LobbyState
var _peers := {}  # peer id -> PeerLink
var _accepted := {}  # peer id -> {name, t}
var _kicks: Array = []  # [peer id, disconnect_at_s]
var _kicked := {}
var _sent_rev := -1
var _last_lobby_sent := -INF
var _known_rev := -1

# Client.
var _seat := -1
var _rows: Array = []
var _song := {}
var _flight := 2
var _got_lobby := false
var _ping_seq := 0
var _out := {}  # seq -> c0
var _burst_left := 0
var _next_ping_at := 0.0
var _connect_deadline := 0.0
var _sync_started := 0.0
var _last_host_packet := 0.0
var _refusal := ""
var _my_ready := false
var _my_status := "none"
var _checked_key := ""
var _check_at_step := -1
var _reported_synced := false


## Host-side state of one admitted client.
class PeerLink:
	extends RefCounted
	var strikes := 0
	var tokens := float(NetProtocol.PING_BUCKET)
	var refill_t := 0.0
	var clock := ClockSync.new()
	var out := {}  # seq -> c0
	var seq := 0
	var burst_left := 0
	var next_ping := 0.0
	var high := false


func _init() -> void:
	transport_factory = _default_factory
	ticks_fn = Time.get_ticks_usec


func _process(_delta: float) -> void:
	if auto_process:
		step(Time.get_ticks_usec() / 1_000_000.0)


func _exit_tree() -> void:
	for r in _retired:
		(r[0] as NetTransport).close()
	_retired.clear()
	if transport != null:
		_unwire(transport)
		transport.close()
		transport = null


static func _default_factory(_role: String) -> NetTransport:
	return ENetTransport.new()


# --- Public API ----------------------------------------------------------------------------------

## Opens a lobby on `port` with this player at seat 0. Returns an Error (also last_error_code).
func host(port: int) -> int:
	if state != State.OFFLINE:
		last_error_code = ERR_ALREADY_IN_USE
		return last_error_code
	_reset()
	var t: NetTransport = transport_factory.call("host")
	if t == null:
		last_error_code = ERR_CANT_CREATE
		return last_error_code
	if t is ENetTransport:
		var err: int = (t as ENetTransport).host(port, ENET_SLOTS)
		if err != OK:
			t.close()
			last_error_code = err
			return err
	transport = t
	_is_host = true
	_wire(t)
	_lobby = LobbyState.new(_my_name())
	var fl: Variant = _settings_value("net_flight_beats")
	if fl is int:
		_lobby.set_flight(fl)
	_known_rev = _lobby.revision
	_set_state(State.LOBBY)
	last_error_code = OK
	log_line.emit("choosing", {"name": "", "n": 0})
	lobby_changed.emit()
	return OK


## Starts joining address:port. Progress comes through connect_stage / connect_error.
func join(address: String, port: int) -> int:
	if state != State.OFFLINE:
		return ERR_ALREADY_IN_USE
	_reset()
	var t: NetTransport = transport_factory.call("client")
	if t == null:
		connect_error.emit("lost", {})
		return ERR_CANT_CREATE
	transport = t
	_is_host = false
	_wire(t)
	_set_state(State.CONNECTING)
	_times_pending = true
	_connect_deadline = _now + NetProtocol.CONNECT_TIMEOUT_S
	_last_host_packet = _now
	connect_stage.emit("connecting")
	var err := OK
	if t is ENetTransport:
		err = (t as ENetTransport).join(address, port)
	elif t is MemTransport:
		(t as MemTransport).connect_to_host()
	if err != OK:
		_fail_connect("resolve" if err == ERR_CANT_RESOLVE else "lost", {})
		return err
	t.send_auth(NetTransport.HOST_ID, NetCodec.encode({
		"type": NetProtocol.AUTH,
		"proto": proto_override if proto_override >= 0 else NetProtocol.PROTO,
		"game": game_version_override if game_version_override != "" \
			else NetProtocol.game_version(),
		"name": _raw_name(),
	}))
	if t.has_signal("authing"):
		t.connect("authing", _on_authing)
	else:
		_on_authing()
	return OK


## Host: broadcasts LOBBY_CLOSED and closes after a short flush. Client: says BYE and leaves.
## No return message (the player chose to leave).
func leave() -> void:
	if state == State.OFFLINE:
		return
	if transport != null:
		if _is_host:
			transport.send(0, NetCodec.encode({"type": NetProtocol.LOBBY_CLOSED}))
			_retire(CLOSE_GRACE_S)
		else:
			if state == State.SYNCING or state == State.LOBBY:
				transport.send(NetTransport.HOST_ID, NetCodec.encode({"type": NetProtocol.BYE}))
			_retire(0.0)
	_reset()


## Host: removes the player at `seat` (1..3) with KICKED {reason kicked}.
func kick(seat: int) -> void:
	if not _host_lobby() or seat <= 0:
		return
	var peer := _lobby.peer_of(seat)
	if peer == 0 or _kicked.has(peer):
		return
	var who: String = _lobby.row(seat).name
	_send(peer, {"type": NetProtocol.KICKED, "reason": NetProtocol.R_KICKED})
	_kicked[peer] = true
	_kicks.append([peer, _now + KICK_GRACE_S])
	_notice("kicked_other", who, seat)


## Client: toggles Ready. Turning it on starts a 16-ping burst unless one is running.
func set_ready(on: bool) -> void:
	if _is_host or state != State.LOBBY or transport == null:
		return
	_my_ready = on
	_send(NetTransport.HOST_ID, {"type": NetProtocol.READY, "ready": on,
		"synced": clock.is_synced()})
	if on and _burst_left == 0:
		_start_burst()


## Host: picks the song {fp, sig, diff, title, artist} ({} clears it). A song change clears
## every client's Ready (D-12). Returns false when the song is rejected (not host, bad fields).
func host_set_song(song: Dictionary) -> bool:
	if not _host_lobby():
		return false
	var clean := _clean_song(song)
	if clean.is_empty() and not song.is_empty():
		return false
	if _lobby.set_song(clean) and not clean.is_empty():
		_notice("song_picked", "", 0)
	return true


## Host: torpedo flight 2 (default, internet) or 1 (LAN). Does not clear Ready.
func host_set_flight(n: int) -> void:
	if not _host_lobby():
		return
	if _lobby.set_flight(n):
		_notice("flight_set", "", n)


## UI-SPEC 9.1 start gate {ok, code, name, n}. Host: LobbyState.start_gate(). Client: the same
## rule over its mirror of the last LOBBY.
func start_gate() -> Dictionary:
	if _is_host and _lobby != null:
		return _lobby.start_gate()
	var ls := _mirror_state()
	if ls == null:
		return {"ok": false, "code": "need_players", "name": "", "n": 0}
	return ls.start_gate()


func local_seat() -> int:
	if state == State.OFFLINE:
		return -1
	return 0 if _is_host else _seat


func is_host() -> bool:
	return _is_host and state != State.OFFLINE


func is_offline() -> bool:
	return state == State.OFFLINE


func is_in_lobby() -> bool:
	return state == State.LOBBY


## Roster rows in seat order, wire shape {seat, name, ready, song, ping_ms, synced, host}. song is
## ok / missing / changed / checking ("checking" also while no song is picked); ping_ms is 0
## until measured.
func lobby_rows() -> Array:
	if _is_host and _lobby != null:
		return _wire_rows()
	return _rows.duplicate(true)


## {fp, sig, diff, title, artist} or {} while the host is choosing.
func lobby_song() -> Dictionary:
	if _is_host and _lobby != null:
		return _lobby.song.duplicate()
	return _song.duplicate()


func flight() -> int:
	if _is_host and _lobby != null:
		return _lobby.flight_beats
	return _flight


## Client: round trip to the host, p50 in ms (0 on the host or before any sample).
func ping_ms() -> int:
	if _is_host:
		return 0
	return int(round(clock.rtt_p50_us() / 1000.0))


## Client: host_ticks - client_ticks in microseconds (0 on the host).
func clock_offset_us() -> int:
	return 0 if _is_host else clock.offset_us()


func is_synced() -> bool:
	return true if _is_host else clock.is_synced()


## The last involuntary exit code (kicked, closed, lost), consumed once.
func take_return_message() -> String:
	var m := _return_message
	_return_message = ""
	return m


## Client: seconds since the last valid packet from the host (0 on the host / offline).
func seconds_since_host_packet() -> float:
	if _is_host or state == State.OFFLINE:
		return 0.0
	return maxf(_now - _last_host_packet, 0.0)


## Client: this PC's status for the host's song: none, checking, ok, missing, changed.
func my_song_status() -> String:
	return _my_status


func is_bursting() -> bool:
	return _burst_left > 0


## Host: the authoritative LobbyState (null on clients).
func lobby_state() -> LobbyState:
	return _lobby if _is_host else null


## Host: strikes recorded against `peer_id` (0 when unknown).
func peer_strikes(peer_id: int) -> int:
	var p: PeerLink = _peers.get(peer_id)
	return p.strikes if p != null else 0


## Host: {seat: rtt p90 in us} for every client with samples (input for D, 04-10).
func peer_rtt_p90_us() -> Dictionary:
	var out := {}
	if not _is_host or _lobby == null:
		return out
	for peer in _peers:
		var p: PeerLink = _peers[peer]
		if p.clock.sample_count() > 0:
			out[_lobby.seat_of(peer)] = p.clock.rtt_p90_us()
	return out


## Host: why an AUTH payload would be refused right now ("" = accept).
func auth_refusal_for(msg: Dictionary) -> String:
	if msg.is_empty() or msg.get("type") != NetProtocol.AUTH:
		return NetProtocol.R_VERSION
	if msg.proto != NetProtocol.PROTO:
		return NetProtocol.R_PROTO
	if msg.game != NetProtocol.game_version():
		return NetProtocol.R_VERSION
	if state != State.LOBBY or _lobby == null:
		return NetProtocol.R_IN_MATCH
	if _lobby.present_count() + _accepted.size() >= NetProtocol.MAX_SEATS:
		return NetProtocol.R_FULL
	if NetCodec.clean_name(msg.name).is_empty():
		return NetProtocol.R_BAD_NAME
	return ""


## Counters for the debug overlay (04-10/04-16 extend this).
func debug_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["role"] = "offline" if state == State.OFFLINE else ("host" if _is_host else "client")
	d["seat"] = local_seat()
	d["peers"] = _peers.size() if _is_host else (1 if transport != null else 0)
	d["rtt_p50_ms"] = ping_ms()
	d["rtt_p90_ms"] = 0 if _is_host else int(round(clock.rtt_p90_us() / 1000.0))
	d["offset_us"] = clock_offset_us()
	return d


# --- Frame step ------------------------------------------------------------------------------------

## Pumps the transport and every timer. now_s is the session clock in seconds (virtual in tests).
func step(now_s: float) -> void:
	_now = now_s
	_step_i += 1
	if _times_pending:
		_times_pending = false
		_connect_deadline = now_s + NetProtocol.CONNECT_TIMEOUT_S
		_last_host_packet = now_s
	_poll_retired()
	if transport == null:
		return
	transport.poll(now_s)
	if transport == null:
		return
	if _is_host:
		_host_tick()
	else:
		_client_tick()


func _poll_retired() -> void:
	if _retired.is_empty():
		return
	var keep: Array = []
	for r in _retired:
		var t: NetTransport = r[0]
		t.poll(_now)
		if _now >= float(r[1]):
			t.close()
		else:
			keep.append(r)
	_retired = keep


# --- Host ----------------------------------------------------------------------------------------

func _host_tick() -> void:
	var due: Array = []
	var later: Array = []
	for k in _kicks:
		if _now >= float(k[1]):
			due.append(k)
		else:
			later.append(k)
	_kicks = later
	for k in due:
		transport.disconnect_peer(int(k[0]))
	for peer in _accepted.keys():
		if _now - float(_accepted[peer].t) > ACCEPT_TTL_S:
			_accepted.erase(peer)
			transport.disconnect_peer(peer)
	for peer in _peers.keys():
		_host_ping(peer)
	if _lobby == null:
		return
	var rev := _lobby.revision
	if (rev != _sent_rev and _now - _last_lobby_sent >= LOBBY_MIN_GAP_S) \
			or _now - _last_lobby_sent >= LOBBY_RESEND_S:
		_send_lobby()
	if rev != _known_rev:
		_known_rev = rev
		lobby_changed.emit()


func _host_ping(peer: int) -> void:
	var p: PeerLink = _peers.get(peer)
	if p == null or _now < p.next_ping:
		return
	var c0 := _ticks()
	p.out[p.seq] = c0
	_trim(p.out)
	_send(peer, {"type": NetProtocol.PING, "seq": p.seq, "c0": c0}, false)
	p.seq += 1
	if p.burst_left > 0:
		p.burst_left -= 1
	p.next_ping = _now + (BURST_GAP_S if p.burst_left > 0 else PING_PERIOD_S)


func _send_lobby() -> void:
	_sent_rev = _lobby.revision
	_last_lobby_sent = _now
	transport.send(0, NetCodec.encode({
		"type": NetProtocol.LOBBY,
		"roster": _wire_rows(),
		"song": _lobby.song.duplicate(),
		"flight": _lobby.flight_beats,
		"phase": PHASE_LOBBY,
	}))


func _wire_rows() -> Array:
	var out: Array = []
	for r in _lobby.rows():
		out.append({
			"seat": r.seat,
			"name": r.name,
			"ready": r.ready,
			"song": "checking" if r.song_status == "none" else r.song_status,
			"ping_ms": clampi(int(r.ping_ms), 0, NetCodec.MAX_PING_MS),
			"synced": r.synced,
			"host": r.host,
		})
	return out


func _on_auth_request(peer: int, bytes: PackedByteArray) -> void:
	if not _is_host:
		return
	var msg := NetCodec.decode(bytes, {"from_host": false})
	var reason := auth_refusal_for(msg)
	var reply := {"type": NetProtocol.AUTH_REPLY, "ok": reason == "", "reason": reason,
		"host_version": NetProtocol.game_version()}
	if reason != "":
		transport.refuse_auth(peer, NetCodec.encode(reply))
		return
	_accepted[peer] = {"name": NetCodec.clean_name(msg.name), "t": _now}
	transport.send_auth(peer, NetCodec.encode(reply))
	transport.complete_auth(peer)


func _on_peer_joined(peer: int) -> void:
	if not _is_host or _lobby == null:
		return
	var info: Variant = _accepted.get(peer)
	_accepted.erase(peer)
	if info == null:
		transport.disconnect_peer(peer)
		return
	var seat := _lobby.add_peer(peer, info.name)
	if seat < 0:
		transport.disconnect_peer(peer)
		return
	var p := PeerLink.new()
	p.refill_t = _now
	p.burst_left = HOST_BURST_PINGS
	p.next_ping = _now
	_peers[peer] = p
	var who: String = _lobby.row(seat).name
	_send(peer, {"type": NetProtocol.NOTICE, "code": NOTICE_WELCOME, "name": who, "n": seat})
	_notice("joined", who, seat)
	_send_lobby()


func _on_peer_left(peer: int) -> void:
	if not _is_host:
		return
	_accepted.erase(peer)
	_peers.erase(peer)
	if _lobby == null:
		return
	var seat := _lobby.seat_of(peer)
	if seat < 0:
		return
	var who: String = _lobby.row(seat).name
	_lobby.remove_peer(peer)
	if _kicked.has(peer):
		_kicked.erase(peer)
	else:
		_notice("left", who, seat)


func _host_packet(peer: int, bytes: PackedByteArray) -> void:
	var p: PeerLink = _peers.get(peer)
	if p == null or _kicked.has(peer):
		return
	var msg := NetCodec.decode(bytes, {"from_host": false})
	if msg.is_empty():
		_strike(peer, p)
		return
	var seat := _lobby.seat_of(peer)
	if seat < 0:
		return
	match msg.type:
		NetProtocol.PING:
			p.tokens = minf(float(NetProtocol.PING_BUCKET),
				p.tokens + maxf(_now - p.refill_t, 0.0) * NetProtocol.MAX_PINGS_PER_S)
			p.refill_t = _now
			if p.tokens < 1.0:
				_stats.ping_dropped += 1
				return
			p.tokens -= 1.0
			_send(peer, {"type": NetProtocol.PONG, "seq": msg.seq, "c0": msg.c0, "h": _ticks()},
				false)
		NetProtocol.PONG:
			_host_pong(peer, p, seat, msg)
		NetProtocol.READY:
			var was: bool = _lobby.row(seat).ready
			_lobby.set_ready(seat, msg.ready)
			_lobby.set_synced(seat, msg.synced)
			if msg.ready and not was:
				_notice("ready", _lobby.row(seat).name, seat)
		NetProtocol.SONG_STATUS:
			_lobby.set_synced(seat, msg.synced)
			if _lobby.song.is_empty():
				return
			var prev: String = _lobby.row(seat).song_status
			_lobby.set_song_status(seat, msg.status)
			if msg.status != prev and (msg.status == "missing" or msg.status == "changed"):
				_notice("missing", _lobby.row(seat).name, 1 if msg.status == "changed" else 0)
		NetProtocol.BYE:
			transport.disconnect_peer(peer)
		_:
			pass  # Valid client messages of the match half (04-10) are ignored in the lobby.


func _host_pong(peer: int, p: PeerLink, seat: int, msg: Dictionary) -> void:
	if not p.out.has(msg.seq):
		return
	var c0: int = p.out[msg.seq]
	p.out.erase(msg.seq)
	p.clock.add(c0, msg.h, _ticks())
	var ms := int(round(p.clock.rtt_p50_us() / 1000.0))
	_lobby.set_ping(seat, ms)
	if p.clock.sample_count() < ClockSync.MIN_SAMPLES:
		return
	var d_est := clampf(p.clock.rtt_p90_us() / 2_000_000.0 + 0.053, NetProtocol.D_MIN_S,
		NetProtocol.D_MAX_S)
	var hi := LobbyState.is_high_latency(d_est, float(ms))
	if hi and not p.high:
		_notice("high_latency", _lobby.row(seat).name, ms)
	p.high = hi


func _strike(peer: int, p: PeerLink) -> void:
	_stats.rejected_packets += 1
	p.strikes += 1
	if p.strikes >= NetProtocol.STRIKES_TO_KICK:
		transport.disconnect_peer(peer)


## Host log line locally plus a NOTICE to every client.
func _notice(code: String, who: String, n: int) -> void:
	log_line.emit(code, {"name": who, "n": n})
	if transport != null:
		transport.send(0, NetCodec.encode({"type": NetProtocol.NOTICE, "code": code,
			"name": who, "n": n}))


func _host_lobby() -> bool:
	return _is_host and state == State.LOBBY and _lobby != null and transport != null


static func _clean_song(s: Dictionary) -> Dictionary:
	if s.is_empty():
		return {}
	var fp: Variant = s.get("fp")
	var sig: Variant = s.get("sig")
	var diff: Variant = s.get("diff")
	if not (fp is String) or (fp as String).is_empty() \
			or (fp as String).length() > NetProtocol.MAX_TEXT or not _printable(fp):
		return {}
	if not (sig is String) or not _is_sig(sig):
		return {}
	if not (diff is String) or not NetProtocol.DIFFICULTIES.has(diff):
		return {}
	return {"fp": fp, "sig": sig, "diff": diff, "title": _text(s.get("title", "")),
		"artist": _text(s.get("artist", ""))}


static func _is_sig(s: String) -> bool:
	if s.length() != NetCodec.SIG_LEN:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _printable(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or (c >= 127 and c < 160):
			return false
	return true


## Display text for the wire: control characters dropped, capped at NetProtocol.MAX_TEXT.
static func _text(v: Variant) -> String:
	var s := str(v) if v != null else ""
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 32 and not (c >= 127 and c < 160):
			out += s[i]
	return out.left(NetProtocol.MAX_TEXT)


# --- Client --------------------------------------------------------------------------------------

func _client_tick() -> void:
	if state == State.CONNECTING or state == State.AUTHING:
		if _now >= _connect_deadline:
			_fail_connect("timeout", {})
		return
	if _now - _last_host_packet > NetProtocol.WATCHDOG_S:
		if state == State.LOBBY:
			_leave_with("lost")
		else:
			_fail_connect("lost", {})
		return
	_client_ping()
	if _check_at_step >= 0 and _step_i >= _check_at_step:
		_check_at_step = -1
		_check_song()
	if state == State.SYNCING and _got_lobby and _seat > 0 \
			and (clock.is_synced() or _now - _sync_started >= SYNC_CAP_S):
		_set_state(State.LOBBY)
		connect_stage.emit("lobby")
		lobby_changed.emit()
		if _song.is_empty():
			log_line.emit("choosing", {"name": "", "n": 0})


func _client_ping() -> void:
	if transport == null or _now < _next_ping_at:
		return
	var c0 := _ticks()
	_out[_ping_seq] = c0
	_trim(_out)
	_send(NetTransport.HOST_ID, {"type": NetProtocol.PING, "seq": _ping_seq, "c0": c0}, false)
	_ping_seq += 1
	_stats.pings_sent += 1
	if _burst_left > 0:
		_burst_left -= 1
	_next_ping_at = _now + (BURST_GAP_S if _burst_left > 0 else PING_PERIOD_S)


func _start_burst() -> void:
	_burst_left = BURST_PINGS
	_next_ping_at = _now


func _on_authing() -> void:
	if state == State.CONNECTING:
		_set_state(State.AUTHING)
		connect_stage.emit("auth")


func _on_auth_reply(bytes: PackedByteArray) -> void:
	if _is_host or (state != State.CONNECTING and state != State.AUTHING):
		return
	var msg := NetCodec.decode(bytes, {"from_host": true})
	if msg.get("type") != NetProtocol.AUTH_REPLY:
		_stats.rejected_packets += 1
		return
	if msg.ok:
		transport.complete_auth(NetTransport.HOST_ID)
		return
	_refusal = msg.reason
	var code := _refusal_code(msg.reason)
	_fail_connect(code, {"host_version": msg.host_version} if code == "version" else {})


static func _refusal_code(reason: String) -> String:
	match reason:
		NetProtocol.R_VERSION, NetProtocol.R_PROTO:
			return "version"
		NetProtocol.R_FULL:
			return "full"
		NetProtocol.R_IN_MATCH:
			return "in_match"
		NetProtocol.R_BAD_NAME:
			return "bad_name"
	return "lost"


func _on_connected() -> void:
	if _is_host or (state != State.CONNECTING and state != State.AUTHING):
		return
	if state == State.CONNECTING:
		_on_authing()
	_set_state(State.SYNCING)
	connect_stage.emit("sync")
	_sync_started = _now
	_last_host_packet = _now
	_start_burst()


func _on_connect_failed(code: String) -> void:
	if _is_host or state == State.OFFLINE:
		return
	match code:
		"resolve":
			_fail_connect("resolve", {})
		"refused":
			# A refusal without an AUTH_REPLY reason: the transport itself turned us away
			# (MemTransport caps at 3 peers; ENet only when refusing new connections).
			_fail_connect(_refusal_code(_refusal) if _refusal != "" else "full", {})
		_:
			_fail_connect("timeout", {})


func _on_server_lost() -> void:
	if _is_host:
		return
	if state == State.LOBBY:
		_leave_with("lost")
	elif state != State.OFFLINE:
		_fail_connect("lost", {})


func _on_packet(peer: int, bytes: PackedByteArray) -> void:
	if _is_host:
		_host_packet(peer, bytes)
		return
	if peer != NetTransport.HOST_ID:
		_stats.rejected_packets += 1
		return
	var msg := NetCodec.decode(bytes, {"from_host": true})
	if msg.is_empty():
		_stats.rejected_packets += 1
		return
	_last_host_packet = _now
	match msg.type:
		NetProtocol.PING:
			_send(NetTransport.HOST_ID, {"type": NetProtocol.PONG, "seq": msg.seq, "c0": msg.c0,
				"h": _ticks()}, false)
		NetProtocol.PONG:
			_client_pong(msg)
		NetProtocol.LOBBY:
			_apply_lobby(msg)
		NetProtocol.NOTICE:
			if msg.code == NOTICE_WELCOME:
				if _seat < 0 and msg.n >= 1 and msg.n < NetProtocol.MAX_SEATS:
					_seat = msg.n
			else:
				log_line.emit(msg.code, {"name": msg.name, "n": msg.n})
		NetProtocol.KICKED:
			_leave_with("kicked")
		NetProtocol.LOBBY_CLOSED:
			_leave_with("closed")
		_:
			pass  # The match half (04-10).


func _client_pong(msg: Dictionary) -> void:
	if not _out.has(msg.seq):
		return
	var c0: int = _out[msg.seq]
	_out.erase(msg.seq)
	clock.add(c0, msg.h, _ticks())
	if clock.is_synced() and not _reported_synced:
		_reported_synced = true
		if _checked_key != "" and _my_status != "checking" and _my_status != "none":
			_send(NetTransport.HOST_ID, {"type": NetProtocol.SONG_STATUS, "status": _my_status,
				"synced": true})
		elif _checked_key == "":
			_send(NetTransport.HOST_ID, {"type": NetProtocol.READY, "ready": _my_ready,
				"synced": true})
		# else: the pending song check reports synced itself.


func _apply_lobby(msg: Dictionary) -> void:
	var rows: Array = msg.roster
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.seat < b.seat)
	var song: Dictionary = msg.song
	var changed: bool = not _got_lobby or rows != _rows or song != _song or msg.flight != _flight
	_rows = rows
	_song = song
	_flight = msg.flight
	_got_lobby = true
	var key := "" if song.is_empty() else "%s|%s|%s" % [song.fp, song.sig, song.diff]
	if key != _checked_key:
		_checked_key = key
		if key == "":
			_my_status = "none"
			_check_at_step = -1
		else:
			_my_status = "checking"
			_check_at_step = _step_i + 1  # next frame: the lobby stays responsive
	for r in rows:
		if r.seat == _seat:
			_my_ready = r.ready
	if changed and state == State.LOBBY:
		lobby_changed.emit()


## Looks the host's song up by fingerprint for its difficulty, builds the chart and compares
## VersusSig (D-11). Never a path: only fp / sig / diff come from the wire.
func _check_song() -> void:
	if _checked_key == "" or transport == null:
		return
	var status := "missing"
	var entry: Variant = _find_entry(_song.fp, _song.diff)
	if entry != null:
		var lib := _lib()
		var chart: Variant = lib.call("build_chart", entry, _song.diff) if lib != null else null
		if chart is ChartData:
			status = "ok" if VersusSig.of(chart) == _song.sig else "changed"
	_my_status = status
	_send(NetTransport.HOST_ID, {"type": NetProtocol.SONG_STATUS, "status": status,
		"synced": clock.is_synced()})


func _find_entry(fp: String, diff: String) -> Variant:
	var lib := _lib()
	if lib == null:
		return null
	var entries: Variant = lib.get("entries")
	if not (entries is Array):
		return null
	for e in entries:
		if not (e is Object) or not (e as Object).has_method("difficulty"):
			continue
		var d: Variant = e.difficulty(diff)
		if d is Dictionary and str(d.get("fingerprint", "")) == fp:
			return e
	return null


func _mirror_state() -> LobbyState:
	if not _got_lobby:
		return null
	var rows: Array = []
	for r in _rows:
		rows.append({"seat": r.seat, "peer_id": int(r.seat) + 1, "name": r.name,
			"ready": r.ready, "song_status": "none" if _song.is_empty() else r.song,
			"ping_ms": r.ping_ms, "synced": r.synced, "host": r.host})
	var ls := LobbyState.new()
	if not ls.apply_wire({"rev": 0, "flight": _flight, "song": _song, "rows": rows}):
		return null
	return ls


func _leave_with(code: String) -> void:
	_retire(0.0)
	_reset()
	_return_message = code
	left_lobby.emit(code)


func _fail_connect(code: String, info: Dictionary) -> void:
	_retire(0.0)
	_reset()
	connect_error.emit(code, info)


# --- Plumbing ------------------------------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	if _is_host and transport != null:
		transport.set_refuse_new(s != State.LOBBY)


func _send(peer: int, msg: Dictionary, reliable: bool = true) -> void:
	if transport != null:
		transport.send(peer, NetCodec.encode(msg), reliable)


func _ticks() -> int:
	return int(ticks_fn.call())


static func _trim(d: Dictionary) -> void:
	while d.size() > MAX_OUTSTANDING:
		d.erase(d.keys()[0])


## Moves the transport to the retired list (signals cut at once, closed after grace_s, polled
## until then so queued messages flush).
func _retire(grace_s: float) -> void:
	if transport == null:
		return
	_unwire(transport)
	_retired.append([transport, _now + grace_s])
	transport = null


func _wire(t: NetTransport) -> void:
	t.packet.connect(_on_packet)
	t.peer_joined.connect(_on_peer_joined)
	t.peer_left.connect(_on_peer_left)
	t.auth_request.connect(_on_auth_request)
	t.auth_reply.connect(_on_auth_reply)
	t.connected.connect(_on_connected)
	t.connect_failed.connect(_on_connect_failed)
	t.server_lost.connect(_on_server_lost)


func _unwire(t: NetTransport) -> void:
	for pair in [[t.packet, _on_packet], [t.peer_joined, _on_peer_joined],
			[t.peer_left, _on_peer_left], [t.auth_request, _on_auth_request],
			[t.auth_reply, _on_auth_reply], [t.connected, _on_connected],
			[t.connect_failed, _on_connect_failed], [t.server_lost, _on_server_lost]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	if t.has_signal("authing") and t.is_connected("authing", _on_authing):
		t.disconnect("authing", _on_authing)


## Back to OFFLINE with every per-session field cleared (the return message survives).
func _reset() -> void:
	state = State.OFFLINE
	_is_host = false
	_times_pending = false
	_lobby = null
	_peers.clear()
	_accepted.clear()
	_kicks.clear()
	_kicked.clear()
	_sent_rev = -1
	_last_lobby_sent = -INF
	_known_rev = -1
	_seat = -1
	_rows = []
	_song = {}
	_flight = 2
	_got_lobby = false
	_ping_seq = 0
	_out.clear()
	_burst_left = 0
	_next_ping_at = 0.0
	_refusal = ""
	_my_ready = false
	_my_status = "none"
	_checked_key = ""
	_check_at_step = -1
	_reported_synced = false
	clock = ClockSync.new()
	_stats = {"pings_sent": 0, "ping_dropped": 0, "rejected_packets": 0}


func _lib() -> Object:
	if library == null and is_inside_tree():
		library = get_node_or_null("/root/SongLibrary")
	return library


func _settings_obj() -> Object:
	if settings == null and is_inside_tree():
		settings = get_node_or_null("/root/Settings")
	return settings


func _settings_value(key: String) -> Variant:
	var s := _settings_obj()
	return s.get(key) if s != null else null


## The cleaned display name for this player (host seat 0), DIVER when unusable.
func _my_name() -> String:
	var n := NetCodec.clean_name(_settings_value("player_name"))
	return n if n != "" else LobbyState.DEFAULT_NAME


## The name as typed, for AUTH: the host validates it (bad_name). Control characters are
## dropped and the length capped so the codec's loose AUTH check still passes.
func _raw_name() -> String:
	var v: Variant = _settings_value("player_name")
	var s := _text(v if v != null else LobbyState.DEFAULT_NAME).strip_edges()
	return s.left(NetProtocol.MAX_STR)
