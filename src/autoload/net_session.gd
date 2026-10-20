extends Node
## Autoload "NetSession": the online session. Lobby half (04-06: D-01, D-06, D-11, D-12, D-17,
## D-20, D-21, D-22, D-23) and match half (04-10: D-04, D-05, D-07, D-16, D-17, D-19):
## start_match -> LOAD -> LOADED -> START (host_start_ticks; local_start = host_start - offset,
## used only through Conductor.begin's lead-in) -> pump_match per frame (INPUTS into the host
## queue, EVENTS into the client channel, 2 Hz HEARTBEAT for debug skew) -> DONE barrier ->
## RESULTS -> back to the lobby. A lost client is eliminated and the match continues; a lost
## host ends the match on every client (MATCH_ABORT, server_lost or the 4 s watchdog).
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

# --- Match half (04-10) ---
## Every peer, the host included: LOAD went out / arrived; pending_match() is filled.
signal match_loading
## Every peer: START went out / arrived. Call lead_in_for_start() once, then Conductor.begin.
signal start_scheduled
## Host only: every live client sent DONE and the host called report_done(end_t), or the
## barrier deadline (host_end + D + 3 s) passed. Emitted once per match.
signal results_due(end_t: float)
## Client: RESULTS from the host (local_seat already set to this client's seat).
signal results_received(data: Dictionary)
## Every peer: BACK_TO_LOBBY (state LOBBY, every Ready cleared, song/difficulty/flight kept).
signal returned_to_lobby
## Client in a match (LOADING/PLAYING/RESULTS): "host_left" (MATCH_ABORT) or
## "connection_lost" (server_lost or the 4 s watchdog). Emitted once; the session is OFFLINE.
signal host_left(kind: String)
## Every peer: a LOAD/START problem sent everyone back to the lobby. code = load_timeout,
## load_fail or start_late; name = the peer at fault ("" when unknown).
signal match_aborted_to_lobby(code: String, name: String)
## Client in a match: no host packet for more than NetProtocol.LINK_WEAK_S (true), or the
## link recovered (false).
signal link_weak_changed(weak: bool)

enum State { OFFLINE, CONNECTING, AUTHING, SYNCING, LOBBY, LOADING, PLAYING, RESULTS }

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
## In a match the host pings each client this often: it doubles as the clients' keep-alive, so
## seconds_since_host_packet() stays well under LINK_WEAK_S on a healthy link.
const MATCH_PING_PERIOD_S := 0.5
## 2 Hz HEARTBEAT {song_t, ticks} (client -> host; debug skew only, never corrects audio).
const HEARTBEAT_PERIOD_S := 0.5
## DONE barrier: results are due at host_end + D + this, even if a client never sent DONE.
const DONE_GRACE_S := 3.0
## START_LATE is honoured this long after the scheduled start (later ones are ignored).
const START_LATE_WINDOW_S := 5.0
## IN-05: the longest accepted lead beyond START_DELAY_S (more is reported as START_LATE).
const MAX_EXTRA_LEAD_S := 2.0
## WR-05: INPUTS bucket capacity (a 4 s burst at MAX_INPUTS_PER_S), so the backlog a lossy link
## releases after a stall fits. Refill stays MAX_INPUTS_PER_S.
const INPUT_BURST := NetProtocol.MAX_INPUTS_PER_S * 4
## WR-05: items past an empty bucket are still queued up to this much debt; only a batch beyond
## it (a sustained flood, 2x the burst with no refill) is cut and struck.
const INPUT_DEBT := INPUT_BURST
## WR-05: overflow strikes are at most one per this many seconds (sustained floods only).
const INPUT_STRIKE_GAP_S := 0.5
## WR-08: READY / SONG_STATUS (the messages that fan out as NOTICEs) per peer: a token bucket
## of CTL_BUCKET refilled at CTL_PER_S. Overflow is dropped silently; every CTL_DROPS_PER_STRIKE
## drops (a sustained flood) count as one strike.
const CTL_PER_S := 10.0
const CTL_BUCKET := 20
const CTL_DROPS_PER_STRIKE := 20
## WR-08: high_latency hysteresis. Notify above LobbyState.HIGH_LATENCY_S; re-arm below
## HIGH_REARM_S, or once the budget is back under the threshold HIGH_RENOTIFY_S after a notice.
const HIGH_REARM_S := 0.220
const HIGH_RENOTIFY_S := 10.0
## Undelivered EVENTS messages a client keeps before its channel is bound.
const MAX_EVENT_INBOX := 4096
## RESULTS keys that cross the wire (NetCodec._v_results).
const RESULT_KEYS: Array[String] = ["rows", "medals", "last_standing_seat", "local_seat",
	"title", "artist", "difficulty", "seed", "online", "is_host", "host_seat", "host_name"]

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
var _stats := {"pings_sent": 0, "ping_dropped": 0, "rejected_packets": 0, "strike_kicks": 0}

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
var _link_weak := false

# Match (both roles; cleared by _clear_match).
var _match := {}  # pending_match() spec
var _d_s := 0.0
var _note_count := 0
var _song_len := 0.0
var _start_set := false
var _local_start := 0  # local ticks of song_time 0 (host_start - offset)
var _lead_checked := false
var _lead_late := false
var _late_sent := false
var _skew_ms := 0.0
var _next_heartbeat := 0.0
# Host match.
var _queue: HostInputQueue
var _hchan: NetHostChannel
var _host_loaded := false
var _load_deadline := 0  # ticks
var _host_start := 0  # host ticks
var _inbox: Array = []  # [seat, items] of validated INPUTS waiting for pump_match
var _left_seats := {}  # seats in LOAD that left before bind_host_match
var _host_done := false
var _host_end_t := 0.0
var _done_deadline := 0  # ticks
var _results_due_sent := false
var _host_song_t := NAN
var _host_song_ticks := 0
var _event_seq := 0
var _heartbeats := 0
# Client match.
var _remote: RemoteReferee
var _cchan: NetClientChannel
var _ev_inbox: Array = []
var _done_sent := false
# Both: wall-clock instant of song_time 0 (04-17 smoke) and this match's RESULTS data.
var _start_unix_ms := 0.0
var _last_results := {}


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
	var high_t := -INF
	# WR-08: control-message bucket (READY / SONG_STATUS).
	var ctl_tokens := float(CTL_BUCKET)
	var ctl_refill_t := 0.0
	var ctl_drops := 0
	# Match: INPUTS bucket (INPUT_BURST, refill MAX_INPUTS_PER_S), LOADED/DONE, skew.
	var in_tokens := float(INPUT_BURST)
	var in_refill_t := 0.0
	## WR-05: last INPUTS overflow strike (at most one per INPUT_STRIKE_GAP_S).
	var in_struck_t := -INF
	var loaded := false
	var done := false
	var skew_ms := 0.0


func _init() -> void:
	transport_factory = _default_factory
	ticks_fn = Time.get_ticks_usec


## 04-17: the command-line autotest driver exists only when `--net-autotest=` is passed
## (T-04-51); a normal game never adds it.
func _ready() -> void:
	if NetAutotest.has_arg(OS.get_cmdline_user_args()):
		var a := NetAutotest.new()
		a.name = "NetAutotest"
		add_child(a)


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


## Host: in LOADING/PLAYING broadcasts MATCH_ABORT {reason host_left}, otherwise (LOBBY,
## RESULTS) LOBBY_CLOSED, then closes after a short flush (CLOSE_GRACE_S of polling). Client:
## says BYE and leaves. No return message (the player chose to leave), no signal.
func leave() -> void:
	if state == State.OFFLINE:
		return
	if transport != null:
		if _is_host:
			if state == State.LOADING or state == State.PLAYING:
				transport.send(0, NetCodec.encode({"type": NetProtocol.MATCH_ABORT,
					"reason": NetProtocol.R_HOST_LEFT}))
			else:
				transport.send(0, NetCodec.encode({"type": NetProtocol.LOBBY_CLOSED}))
			_retire(CLOSE_GRACE_S)
		else:
			if state >= State.SYNCING:
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


## Host in LOBBY: tells every client the host opened Song Select (UI-SPEC 9.4, WR-07). Clients
## log "choosing"; the host itself gets no log line for its own action.
func host_choosing() -> void:
	if _host_lobby():
		transport.send(0, NetCodec.encode({"type": NetProtocol.NOTICE, "code": "choosing",
			"name": "", "n": 0}))


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
		# LOADING / PLAYING / RESULTS. The transport keeps accepting connections (refuse_new
		# stays off) so the joiner reads this reason instead of an ENet timeout.
		return NetProtocol.R_IN_MATCH
	if _lobby.present_count() + _accepted.size() >= NetProtocol.MAX_SEATS:
		return NetProtocol.R_FULL
	if NetCodec.clean_name(msg.name).is_empty():
		return NetProtocol.R_BAD_NAME
	return ""


## Counters for the F3 overlay (04-16). Every key is present with a numeric default offline:
## role, seat, state, peers, pings_sent, ping_dropped, rejected_packets, rtt_p50_ms, rtt_p90_ms
## (host: worst client), per_peer [{seat, name, p90_ms, skew_ms}] (host), offset_us,
## horizon_ms (D), late_inputs (host queue), skew_ms (debug only: host = the client skew with
## the largest magnitude from HEARTBEATs; client = own song_time against the scheduled start),
## landed_late_last_ms, landed_late_max_ms (client channel), event_seq (host: highest EVENTS
## seq sent; client: last applied), link_weak, start_unix_ms (04-17: wall-clock ms of song_time 0
## from the first lead_in_for_start call; 0 before), strike_kicks (host: peers disconnected for
## strikes this session).
func debug_stats() -> Dictionary:
	var d := _stats.duplicate()
	d["role"] = "offline" if state == State.OFFLINE else ("host" if _is_host else "client")
	d["seat"] = local_seat()
	d["state"] = State.keys()[state].to_lower()
	d["peers"] = _peers.size() if _is_host else (1 if transport != null else 0)
	d["rtt_p50_ms"] = ping_ms()
	d["rtt_p90_ms"] = 0 if _is_host else int(round(clock.rtt_p90_us() / 1000.0))
	d["offset_us"] = clock_offset_us()
	var per: Array = []
	var skew := _skew_ms
	if _is_host and _lobby != null:
		var p50 := 0
		var p90 := 0
		for peer in _peers:
			var p: PeerLink = _peers[peer]
			var seat := _lobby.seat_of(peer)
			var r := _lobby.row(seat)
			var ms90 := int(round(p.clock.rtt_p90_us() / 1000.0))
			p50 = maxi(p50, int(round(p.clock.rtt_p50_us() / 1000.0)))
			p90 = maxi(p90, ms90)
			per.append({"seat": seat, "name": str(r.get("name", "")), "p90_ms": ms90,
				"skew_ms": p.skew_ms})
			if absf(p.skew_ms) > absf(skew):
				skew = p.skew_ms
		d["rtt_p50_ms"] = p50
		d["rtt_p90_ms"] = p90
	d["per_peer"] = per
	d["horizon_ms"] = int(round(_d_s * 1000.0)) if not _match.is_empty() else 0
	d["late_inputs"] = _queue.late_inputs if _queue != null else 0
	d["skew_ms"] = skew
	d["landed_late_last_ms"] = _cchan.landed_late_last_ms if _cchan != null else 0.0
	d["landed_late_max_ms"] = _cchan.landed_late_max_ms if _cchan != null else 0.0
	d["event_seq"] = _cchan.last_seq if _cchan != null else _event_seq
	d["link_weak"] = _link_weak
	d["start_unix_ms"] = _start_unix_ms
	return d


# --- Match API (04-10) -----------------------------------------------------------------------

## Host, in LOBBY: fixes D from the lobby RTT (D-05), locks the lobby and sends LOAD to every
## client; every peer then emits match_loading. opts (autotest switches, all optional): seed
## (int, default random), max_song_s (float, 0 = full song), autoplay (bool).
## Returns "" when the match is loading, "gate" when start_gate() is not ok, "not_host" else.
func start_match(opts := {}) -> String:
	if not _host_lobby():
		return "not_host"
	if not start_gate().ok:
		return "gate"
	var worst_us := 0
	var margins := {0: 0.0}
	var p90 := peer_rtt_p90_us()
	for seat in p90:
		worst_us = maxi(worst_us, int(p90[seat]))
		margins[seat] = int(p90[seat]) / 1_000_000.0
	var d_ms := int(round(clampf(worst_us / 2_000_000.0 + 0.053, NetProtocol.D_MIN_S,
		NetProtocol.D_MAX_S) * 1000.0))
	var seed_v: Variant = opts.get("seed")
	var seed_i: int = seed_v if seed_v is int else int(randi())
	var max_s := clampf(float(opts.get("max_song_s", 0.0)), 0.0, NetProtocol.MAX_SONG_S)
	if not is_finite(max_s):
		max_s = 0.0
	var roster: Array = []
	for r in _lobby.rows():
		roster.append({"seat": r.seat, "name": r.name})
		# IN-10: a seat with no host-side RTT samples still gets D cover (margin_for(D, 0)).
		if not margins.has(r.seat):
			margins[r.seat] = 0.0
	var song := _lobby.song
	var load_msg := {"type": NetProtocol.LOAD, "fp": song.fp, "sig": song.sig, "diff": song.diff,
		"seed": seed_i, "flight": _lobby.flight_beats, "roster": roster, "d_ms": d_ms,
		"max_song_s": max_s, "autoplay": bool(opts.get("autoplay", false))}
	_clear_match()
	_accepted.clear()
	_set_state(State.LOADING)
	_match = _spec_from_load(load_msg, "host", 0, margins)
	_d_s = float(_match.d_s)
	_load_deadline = _ticks() + int(NetProtocol.LOAD_TIMEOUT_S * 1_000_000.0)
	for peer in _peers:
		var p: PeerLink = _peers[peer]
		p.loaded = false
		p.done = false
		p.skew_ms = 0.0
		p.in_tokens = float(INPUT_BURST)
		p.in_refill_t = _now
		p.in_struck_t = -INF
	transport.send(0, NetCodec.encode(load_msg))
	match_loading.emit()
	return ""


## The LOAD spec while in a match ({} otherwise): role ("host"|"client"), local_seat, names
## (PackedStringArray by seat; a seat missing from the roster is ""), seats (Array of roster
## seats), fp, sig, diff, title, artist, seed, flight, d_s, max_song_s, autoplay, margins
## ({seat: rtt_p90_s} on the host with 0.0 for seat 0; {} on clients).
func pending_match() -> Dictionary:
	if state < State.LOADING:
		return {}
	return _match.duplicate(true)


## This peer built its chart and scene: client sends LOADED; host counts itself loaded. START
## goes out once the host and every live client are loaded.
func report_loaded() -> void:
	if state != State.LOADING:
		return
	if _is_host:
		_host_loaded = true
		_maybe_start()
	else:
		_send(NetTransport.HOST_ID, {"type": NetProtocol.LOADED})


## This peer could not load the match: everyone goes back to the lobby with load_fail.
func report_load_failed() -> void:
	if state != State.LOADING:
		return
	if _is_host:
		_abort_to_lobby(NetProtocol.R_LOAD_FAIL, _lobby.row(0).name)
	else:
		_send(NetTransport.HOST_ID, {"type": NetProtocol.LOAD_FAIL})


## Seconds until this peer's song_time 0 (local_start = host_start - offset; the host uses
## offset 0), for Conductor.begin(stream, lead). Call it once after start_scheduled: the first
## call decides. -1 when there is no START yet, when this client's clock was not synced at
## START, or when the lead is below NetProtocol.MIN_LEAD_S; the latter two report START_LATE
## (the host aborts to the lobby with start_late). Later calls return the current raw lead
## (or -1 if the first call was late) and never send anything.
func lead_in_for_start() -> float:
	if not _start_set or (state != State.PLAYING):
		return -1.0
	if _lead_late:
		return -1.0
	var lead := (_local_start - _ticks()) / 1_000_000.0
	if _lead_checked:
		return lead
	_lead_checked = true
	# IN-05: a start further away than START_DELAY + MAX_EXTRA_LEAD_S means a broken clock or
	# offset; treat it like a late start (back to the lobby), not a long silent wait.
	if lead < NetProtocol.MIN_LEAD_S or lead > NetProtocol.START_DELAY_S + MAX_EXTRA_LEAD_S:
		_lead_late = true
		_report_late(lead)
		return -1.0
	_start_unix_ms = _unix_ms_at_lead(lead)
	return lead


## 04-17 smoke: the wall-clock instant (unix ms) that is `lead_s` from now. All smoke processes
## share one OS clock on localhost, so comparing it across them measures the offset math.
static func _unix_ms_at_lead(lead_s: float) -> float:
	return Time.get_unix_time_from_system() * 1000.0 + lead_s * 1000.0


## Host: binds the match objects (04-13 VersusController.queue / host_channel). Every live
## client is added to the channel; seats that left during LOADING are dropped at once.
func bind_host_match(queue: HostInputQueue, channel: NetHostChannel, note_count: int,
		song_len: float) -> void:
	if not _is_host or state < State.LOADING:
		return
	_queue = queue
	_hchan = channel
	_note_count = maxi(note_count, 0)
	_song_len = song_len if is_finite(song_len) else 0.0
	for peer in _peers:
		channel.add_peer(peer)
	for seat in _left_seats:
		queue.drop_seat(seat, "disconnected")
	_left_seats.clear()


## Client: binds RemoteReferee + NetClientChannel (04-13 VersusController.remote /
## client_channel). The referee's send Callable should end in send_to_host.
func bind_client_match(remote: RemoteReferee, channel: NetClientChannel, note_count: int,
		song_len: float) -> void:
	if _is_host or state < State.LOADING:
		return
	_remote = remote
	_cchan = channel
	_note_count = maxi(note_count, 0)
	_song_len = song_len if is_finite(song_len) else 0.0


## Client: encodes msg and sends it to the host on the reliable channel (the controller's
## net_send / RemoteReferee send_fn).
func send_to_host(msg: Dictionary) -> void:
	if _is_host or transport == null or state < State.SYNCING:
		return
	_send(NetTransport.HOST_ID, msg)


## Once per frame, after controller.net_tick(t). song_time may be NAN before START: then only
## the bound channel traffic moves. Host: received INPUTS -> queue.push_item(seat, item),
## queue.pump(t) (capped at end_t + D after report_done), then the EVENTS batches go out.
## Client: remote.flush(), then EVENTS -> channel.receive in arrival order. Both: 2 Hz skew.
func pump_match(song_time: float) -> void:
	if transport == null or state < State.LOADING:
		return
	if _is_host:
		_host_pump(song_time)
	else:
		_client_pump(song_time)
	if is_finite(song_time) and _start_set and _now >= _next_heartbeat:
		_next_heartbeat = _now + HEARTBEAT_PERIOD_S
		_skew_ms = (song_time - (_ticks() - _local_start) / 1_000_000.0) * 1000.0
		if not _is_host and state == State.PLAYING:
			_send(NetTransport.HOST_ID, {"type": NetProtocol.HEARTBEAT,
				"song_t": clampf(song_time, NetProtocol.TIME_MIN_S, NetProtocol.MAX_SONG_S),
				"ticks": _ticks()}, false)


## Host: live clients that have not sent DONE yet (0 on clients and outside PLAYING).
func still_diving() -> int:
	if not _is_host or state != State.PLAYING:
		return 0
	var n := 0
	for peer in _peers:
		if not (_peers[peer] as PeerLink).done:
			n += 1
	return n


## This peer's song ended at song time t. Client: DONE {t} (once). Host: starts the DONE
## barrier (results_due at the latest at now + D + 3 s).
func report_done(t: float) -> void:
	if state != State.PLAYING or not is_finite(t):
		return
	if _is_host:
		if _host_done:
			return
		_host_done = true
		_host_end_t = t
		_done_deadline = _ticks() + int((_d_s + DONE_GRACE_S) * 1_000_000.0)
		_check_results_due()
	elif not _done_sent:
		_done_sent = true
		_send(NetTransport.HOST_ID, {"type": NetProtocol.DONE,
			"t": clampf(t, NetProtocol.TIME_MIN_S, NetProtocol.MAX_SONG_S)})


## Host: sends RESULTS (the VersusController.finish data) to every client with local_seat set
## to that client's seat and is_host false, after flushing pending EVENTS (MATCH_END first).
## State becomes RESULTS.
func host_send_results(data: Dictionary) -> void:
	if not _is_host or state != State.PLAYING or transport == null:
		return
	if _hchan != null:
		_send_batches()
	var base := {}
	for k in RESULT_KEYS:
		if data.has(k):
			base[k] = data[k]
	# CR-03: chart title / artist come straight from song.ini (up to 120 chars, C1 kept); the
	# codec caps display text at MAX_TEXT, so clip and clean them like the LOBBY song fields.
	for k in ["title", "artist"]:
		if base.has(k):
			base[k] = _text(base[k])
	if base.has("host_name"):
		var hn := NetCodec.clean_name(base["host_name"])
		if hn.is_empty():
			base.erase("host_name")
		else:
			base["host_name"] = hn
	_last_results = base.duplicate(true)
	_last_results["local_seat"] = 0
	for peer in _peers:
		var msg: Dictionary = base.duplicate(true)
		msg["type"] = NetProtocol.RESULTS
		msg["local_seat"] = _lobby.seat_of(peer)
		if msg.has("is_host"):
			msg["is_host"] = false
		_send(peer, msg)
	_set_state(State.RESULTS)


## Host, in a match: everyone back to the lobby (BACK_TO_LOBBY), Ready cleared, song,
## difficulty and flight kept. Emits returned_to_lobby locally too.
func host_back_to_lobby() -> void:
	if not _is_host or state < State.LOADING or transport == null:
		return
	transport.send(0, NetCodec.encode({"type": NetProtocol.BACK_TO_LOBBY}))
	_to_lobby()
	returned_to_lobby.emit()


## The bound match event channel: NetHostChannel on the host (broadcast_log), NetClientChannel
## on a client (received_log), null outside a bound match. Read-only use (04-17 autotest).
func match_channel() -> EventChannel:
	if _is_host:
		return _hchan
	return _cchan


## This match's RESULTS data (host: what host_send_results sent, with local_seat 0; client: the
## received RESULTS), {} before results. Cleared with the match.
func last_results() -> Dictionary:
	return _last_results.duplicate(true)


## Client: true while no host packet arrived for more than NetProtocol.LINK_WEAK_S.
func is_link_weak() -> bool:
	return _link_weak


## Host: HEARTBEATs received this match (tests / overlay).
func heartbeats_received() -> int:
	return _heartbeats


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
	if _lobby == null or transport == null:
		return
	if state == State.LOADING and _ticks() >= _load_deadline:
		_abort_to_lobby(NetProtocol.R_LOAD_TIMEOUT, _first_not_loaded())
		return
	if state == State.PLAYING:
		_check_results_due()
	var rev := _lobby.revision
	if state == State.LOBBY and ((rev != _sent_rev and _now - _last_lobby_sent >= LOBBY_MIN_GAP_S) \
			or _now - _last_lobby_sent >= LOBBY_RESEND_S):
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
	var period := PING_PERIOD_S if state <= State.LOBBY else MATCH_PING_PERIOD_S
	p.next_ping = _now + (BURST_GAP_S if p.burst_left > 0 else period)


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
	if info == null or state != State.LOBBY:
		transport.disconnect_peer(peer)
		return
	var seat := _lobby.add_peer(peer, info.name)
	if seat < 0:
		transport.disconnect_peer(peer)
		return
	var p := PeerLink.new()
	p.refill_t = _now
	p.ctl_refill_t = _now
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
	# D-16: in a match a lost client is eliminated and the match continues.
	if state >= State.LOADING:
		if _hchan != null:
			_hchan.remove_peer(peer)
		# CR-02: a leave in LOADING after bind_host_match is dropped at once (sim time is still
		# TIME_MIN_S, harmless); before the bind it waits in _left_seats for the bind.
		if _queue != null:
			if state == State.PLAYING or state == State.LOADING:
				_queue.drop_seat(seat, "disconnected")
		elif state == State.LOADING:
			_left_seats[seat] = true
		var keep: Array = []
		for e in _inbox:
			if int(e[0]) != seat:
				keep.append(e)
		_inbox = keep
	_lobby.remove_peer(peer)
	if _kicked.has(peer):
		_kicked.erase(peer)
	else:
		_notice("left", who, seat)
	if state == State.LOADING:
		_maybe_start()
	elif state == State.PLAYING:
		_check_results_due()


func _host_packet(peer: int, bytes: PackedByteArray) -> void:
	var p: PeerLink = _peers.get(peer)
	if p == null or _kicked.has(peer):
		return
	var msg := NetCodec.decode(bytes, _ctx(false))
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
			if not _take_ctl(peer, p):
				return
			var was: bool = _lobby.row(seat).ready
			_lobby.set_ready(seat, msg.ready)
			_lobby.set_synced(seat, msg.synced)
			if msg.ready and not was:
				_notice("ready", _lobby.row(seat).name, seat)
		NetProtocol.SONG_STATUS:
			if not _take_ctl(peer, p):
				return
			_lobby.set_synced(seat, msg.synced)
			if _lobby.song.is_empty():
				return
			var prev: String = _lobby.row(seat).song_status
			_lobby.set_song_status(seat, msg.status)
			if msg.status != prev and (msg.status == "missing" or msg.status == "changed"):
				_notice("missing", _lobby.row(seat).name, 1 if msg.status == "changed" else 0)
		NetProtocol.BYE:
			transport.disconnect_peer(peer)
		NetProtocol.LOADED:
			if state == State.LOADING:
				p.loaded = true
				_maybe_start()
		NetProtocol.LOAD_FAIL:
			if state == State.LOADING:
				_abort_to_lobby(NetProtocol.R_LOAD_FAIL, _lobby.row(seat).name)
		NetProtocol.START_LATE:
			if state == State.PLAYING and _ticks() < _host_start \
					+ int(START_LATE_WINDOW_S * 1_000_000.0):
				_abort_to_lobby(NetProtocol.R_START_LATE, _lobby.row(seat).name)
		NetProtocol.INPUTS:
			if state == State.PLAYING:
				_take_inputs(peer, p, seat, msg.items)
		NetProtocol.DONE:
			if state == State.PLAYING:
				p.done = true
				_check_results_due()
		NetProtocol.HEARTBEAT:
			if state == State.PLAYING:
				_heartbeats += 1
				_host_heartbeat(p, msg)
		_:
			pass


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
	# WR-08: hysteresis, so a p90 jittering around 250 ms does not re-fire the notice.
	var hi := high_latency_next(p.high, _now - p.high_t, d_est, float(ms))
	if hi and not p.high:
		p.high_t = _now
		_notice("high_latency", _lobby.row(seat).name, ms)
	p.high = hi


## WR-08: the next high-latency flag. Rises above LobbyState.HIGH_LATENCY_S (the caller then
## notifies); once up it falls only below HIGH_REARM_S, or when back under the threshold at
## least HIGH_RENOTIFY_S after the notice (since_s).
static func high_latency_next(was_high: bool, since_s: float, d_s: float, rtt_ms: float) -> bool:
	if LobbyState.is_high_latency(d_s, rtt_ms):
		return true
	if not was_high:
		return false
	var budget := d_s + rtt_ms / 2000.0 + LobbyState.FRAME_S
	return not (budget < HIGH_REARM_S or since_s >= HIGH_RENOTIFY_S)


## WR-08: one READY / SONG_STATUS from `peer` against its control bucket. False = drop it.
func _take_ctl(peer: int, p: PeerLink) -> bool:
	p.ctl_tokens = minf(float(CTL_BUCKET),
		p.ctl_tokens + maxf(_now - p.ctl_refill_t, 0.0) * CTL_PER_S)
	p.ctl_refill_t = _now
	if p.ctl_tokens >= 1.0:
		p.ctl_tokens -= 1.0
		return true
	p.ctl_drops += 1
	if p.ctl_drops % CTL_DROPS_PER_STRIKE == 0:
		_strike(peer, p)
	return false


# --- Host match ----------------------------------------------------------------------------------

## START {host_start_ticks = now + 3 s} once the host and every live client are loaded.
func _maybe_start() -> void:
	if state != State.LOADING or not _host_loaded:
		return
	for peer in _peers:
		if not (_peers[peer] as PeerLink).loaded:
			return
	_host_start = _ticks() + int(NetProtocol.START_DELAY_S * 1_000_000.0)
	_send_all({"type": NetProtocol.START, "host_start_ticks": _host_start})
	_set_state(State.PLAYING)
	_local_start = _host_start
	_start_set = true
	_next_heartbeat = _now
	start_scheduled.emit()


## The name of the first seat (host included) that has not reported LOADED.
func _first_not_loaded() -> String:
	if not _host_loaded:
		return _lobby.row(0).name
	for r in _lobby.rows():
		var p: PeerLink = _peers.get(_lobby.peer_of(r.seat))
		if p != null and not p.loaded:
			return r.name
	return ""


## Host: ABORT_TO_LOBBY {reason, name} to everyone, then back to the lobby here too.
func _abort_to_lobby(reason: String, who: String) -> void:
	if not _is_host or transport == null:
		return
	var n := who if NetCodec.clean_name(who) != "" else ""
	_send_all({"type": NetProtocol.ABORT_TO_LOBBY, "reason": reason, "name": n})
	_to_lobby()
	match_aborted_to_lobby.emit(reason, n)


## Match -> LOBBY on this peer: match state cleared, Ready cleared (host: every client row;
## client: its own flag), a fresh LOBBY broadcast from the host.
func _to_lobby() -> void:
	_clear_match()
	_set_state(State.LOBBY)
	if _is_host:
		if _lobby != null:
			for r in _lobby.rows():
				if not r.host:
					_lobby.set_ready(r.seat, false)
			_send_lobby()
	else:
		_my_ready = false
	lobby_changed.emit()


## Validated INPUTS from `peer` (seat from the sender id only, T-04-30). A token bucket of
## INPUT_BURST items refilled at MAX_INPUTS_PER_S. WR-05: past an empty bucket items are still
## queued (the bucket goes into debt, down to -INPUT_DEBT); only the part of a batch beyond
## that is cut and counts as a strike, so a post-stall backlog is never dropped.
func _take_inputs(peer: int, p: PeerLink, seat: int, items: Array) -> void:
	p.in_tokens = minf(float(INPUT_BURST),
		p.in_tokens + maxf(_now - p.in_refill_t, 0.0) * NetProtocol.MAX_INPUTS_PER_S)
	p.in_refill_t = _now
	var n := clampi(items.size(), 0, maxi(int(floor(p.in_tokens + INPUT_DEBT)), 0))
	p.in_tokens -= n
	if n > 0:
		_inbox.append([seat, items.slice(0, n)])
	if n < items.size() and _now - p.in_struck_t >= INPUT_STRIKE_GAP_S:
		# One strike per overflow second: the chunks of one burst count once, a flood that
		# keeps going reaches STRIKES_TO_KICK.
		p.in_struck_t = _now
		_strike(peer, p)


## HEARTBEAT {song_t, ticks}: the client's song time against the host's song time at the
## same instant (client ticks mapped through the host's ping clock). Debug only.
func _host_heartbeat(p: PeerLink, msg: Dictionary) -> void:
	if not is_finite(_host_song_t) or p.clock.sample_count() == 0:
		return
	var host_ticks: int = int(msg.ticks) - p.clock.offset_us()
	var host_song := _host_song_t + (host_ticks - _host_song_ticks) / 1_000_000.0
	p.skew_ms = (float(msg.song_t) - host_song) * 1000.0


func _host_pump(song_time: float) -> void:
	if _queue != null and is_finite(song_time) and state == State.PLAYING:
		_drain_inbox()
		var t := song_time
		if _host_done:
			t = minf(t, _host_end_t + _d_s)
		_queue.pump(t)
		_host_song_t = song_time
		_host_song_ticks = _ticks()
	if _hchan != null:
		_send_batches()


func _send_batches() -> void:
	var batches := _hchan.take_batches()
	for peer in batches:
		if not _peers.has(peer):
			continue
		for m in batches[peer]:
			_event_seq = maxi(_event_seq, int(m.seq))
			_send(peer, m)


func _check_results_due() -> void:
	if state != State.PLAYING or not _host_done or _results_due_sent:
		return
	if still_diving() > 0 and _ticks() < _done_deadline:
		return
	_results_due_sent = true
	# WR-04: a client's final INPUTS flush arrives in the same poll as its DONE; queue it now so
	# VersusController.finish (pump(t + D)) applies it before the standings are taken.
	_drain_inbox()
	results_due.emit(_host_end_t)


## Validated INPUTS waiting in _inbox -> the host queue (seat from the sender, T-04-30).
func _drain_inbox() -> void:
	if _queue == null:
		return
	for e in _inbox:
		for it in e[1]:
			_queue.push_item(int(e[0]), it)
	_inbox.clear()


## The first lead_in_for_start() call found the start too close (or the clock unsynced).
func _report_late(lead_s: float) -> void:
	if _late_sent:
		return
	_late_sent = true
	if _is_host:
		_abort_to_lobby(NetProtocol.R_START_LATE, _lobby.row(0).name)
	else:
		var ms := clampi(int(round(lead_s * 1000.0)), -NetCodec.MAX_LEAD_MS, NetCodec.MAX_LEAD_MS)
		_send(NetTransport.HOST_ID, {"type": NetProtocol.START_LATE, "lead_ms": ms})


func _strike(peer: int, p: PeerLink) -> void:
	_stats.rejected_packets += 1
	p.strikes += 1
	if p.strikes >= NetProtocol.STRIKES_TO_KICK:
		if p.strikes == NetProtocol.STRIKES_TO_KICK:
			_stats.strike_kicks += 1  # 04-17: the smoke fails on any strike disconnect
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
	var silent := _now - _last_host_packet
	# WR-06: in LOADING the host builds its chart and swaps scenes on its main thread (no pings);
	# allow the whole load window there and rely on server_lost for real drops.
	var limit := NetProtocol.WATCHDOG_S
	if state == State.LOADING:
		limit = NetProtocol.LOAD_TIMEOUT_S + NetProtocol.START_DELAY_S
	if silent > limit:
		if state >= State.LOADING:
			_host_lost("connection_lost")
		elif state == State.LOBBY:
			_leave_with("lost")
		else:
			_fail_connect("lost", {})
		return
	if state >= State.LOADING:
		var weak := silent > NetProtocol.LINK_WEAK_S
		if weak != _link_weak:
			_link_weak = weak
			link_weak_changed.emit(weak)
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
	if state >= State.LOADING:
		_host_lost("connection_lost")
	elif state == State.LOBBY:
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
	var msg := NetCodec.decode(bytes, _ctx(true))
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
		NetProtocol.LOAD:
			if state == State.LOBBY and _seat > 0:
				_clear_match()
				_match = _spec_from_load(msg, "client", _seat, {})
				_d_s = float(_match.d_s)
				_set_state(State.LOADING)
				match_loading.emit()
		NetProtocol.START:
			if state == State.LOADING:
				_on_start(int(msg.host_start_ticks))
		NetProtocol.ABORT_TO_LOBBY:
			if state >= State.LOADING:
				_to_lobby()
				match_aborted_to_lobby.emit(msg.reason, msg.name)
		NetProtocol.EVENTS:
			if state == State.PLAYING or state == State.RESULTS:
				if _ev_inbox.size() < MAX_EVENT_INBOX:
					_ev_inbox.append(msg)
		NetProtocol.RESULTS:
			if state == State.PLAYING:
				if msg.local_seat != _seat:
					_stats.rejected_packets += 1
					return
				_set_state(State.RESULTS)
				var data: Dictionary = msg.duplicate(true)
				data.erase("type")
				_last_results = data.duplicate(true)
				results_received.emit(data)
		NetProtocol.BACK_TO_LOBBY:
			if state >= State.LOADING:
				_to_lobby()
				returned_to_lobby.emit()
		NetProtocol.MATCH_ABORT:
			if state >= State.LOADING:
				_host_lost("host_left")
			else:
				_leave_with("closed")
		_:
			pass


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


## START {host_start_ticks}: local_start = host_start - offset (frozen now; Pitfall 2). A client
## whose ClockSync is not synced cannot trust its offset and replies START_LATE at once.
func _on_start(host_start: int) -> void:
	_set_state(State.PLAYING)
	_local_start = host_start - clock.offset_us()
	_start_set = true
	_next_heartbeat = _now
	if not clock.is_synced():
		_lead_checked = true
		_lead_late = true
		_report_late((_local_start - _ticks()) / 1_000_000.0)
	start_scheduled.emit()


func _client_pump(_song_time: float) -> void:
	if _remote != null and state == State.PLAYING:
		_remote.flush()
	if _cchan != null and not _ev_inbox.is_empty():
		var msgs := _ev_inbox
		_ev_inbox = []
		for m in msgs:
			_cchan.receive(m)


## The host is gone during a match (D-17): offline, return message closed / lost, host_left.
func _host_lost(kind: String) -> void:
	_retire(0.0)
	_reset()
	_return_message = "closed" if kind == "host_left" else "lost"
	host_left.emit(kind)


func _fail_connect(code: String, info: Dictionary) -> void:
	_retire(0.0)
	_reset()
	connect_error.emit(code, info)


# --- Plumbing ------------------------------------------------------------------------------------

## The transport never refuses new connections: joiners during LOADING / PLAYING / RESULTS
## are refused by auth_refusal_for with reason in_match (an ENet refuse_new drop would only
## show them a timeout). The ENet slot cap and auth_timeout still bound the cost.
func _set_state(s: State) -> void:
	state = s
	if _is_host and transport != null:
		transport.set_refuse_new(false)


## NetCodec ctx for packets this side receives (note_count / song_len once a match is bound).
func _ctx(from_host: bool) -> Dictionary:
	return {"from_host": from_host, "note_count": _note_count, "song_len": _song_len}


func _send_all(msg: Dictionary, reliable: bool = true) -> void:
	if transport != null:
		transport.send(0, NetCodec.encode(msg), reliable)


## pending_match() from a (validated) LOAD message.
func _spec_from_load(m: Dictionary, role: String, seat: int, margins: Dictionary) -> Dictionary:
	var top := 0
	var seats: Array = []
	for r in m.roster:
		top = maxi(top, int(r.seat))
		seats.append(int(r.seat))
	seats.sort()
	var names := PackedStringArray()
	names.resize(top + 1)
	for r in m.roster:
		names[int(r.seat)] = str(r.name)
	var song := lobby_song()
	return {"role": role, "local_seat": seat, "names": names, "seats": seats, "fp": m.fp,
		"sig": m.sig, "diff": m.diff, "title": str(song.get("title", "")),
		"artist": str(song.get("artist", "")), "seed": m.seed, "flight": m.flight,
		"d_s": int(m.d_ms) / 1000.0, "max_song_s": float(m.max_song_s), "autoplay": m.autoplay,
		"margins": margins}


## Clears every per-match field (both roles). Lobby state is untouched.
func _clear_match() -> void:
	_match = {}
	_d_s = 0.0
	_note_count = 0
	_song_len = 0.0
	_start_set = false
	_local_start = 0
	_lead_checked = false
	_lead_late = false
	_late_sent = false
	_skew_ms = 0.0
	_next_heartbeat = 0.0
	_queue = null
	_hchan = null
	_host_loaded = false
	_load_deadline = 0
	_host_start = 0
	_inbox = []
	_left_seats.clear()
	_host_done = false
	_host_end_t = 0.0
	_done_deadline = 0
	_results_due_sent = false
	_host_song_t = NAN
	_host_song_ticks = 0
	_event_seq = 0
	_heartbeats = 0
	_remote = null
	_cchan = null
	_ev_inbox = []
	_done_sent = false
	_link_weak = false
	_start_unix_ms = 0.0
	_last_results = {}
	for peer in _peers:
		var p: PeerLink = _peers[peer]
		p.loaded = false
		p.done = false
		p.skew_ms = 0.0
		# WR-05: strikes and token buckets are per match (three stalls over a whole session
		# never add up to a kick).
		p.strikes = 0
		p.tokens = float(NetProtocol.PING_BUCKET)
		p.refill_t = _now
		p.in_tokens = float(INPUT_BURST)
		p.in_refill_t = _now
		p.in_struck_t = -INF


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
	_clear_match()
	clock = ClockSync.new()
	_stats = {"pings_sent": 0, "ping_dropped": 0, "rejected_packets": 0, "strike_kicks": 0}


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
