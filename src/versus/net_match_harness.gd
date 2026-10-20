class_name NetMatchHarness
extends RefCounted
## Headless whole ONLINE match runner (04-09, D-24 layer 2): virtual song time; no nodes;
## NetCodec on every hop; same construction as the online VersusController backends.
##
## The host is SubRig(0) on a HostInputQueue in front of MatchSim, with a NetHostChannel. Each
## client k (seats 1..clients) is SubRig(k) on a RemoteReferee bound to its own NetClientChannel,
## with its own PlayerState copies (clients run no rules). Every seat is an autoplay human
## (MatchHarness._AutoActor). Peers talk over a MemTransport.Hub whose clock IS the shared song
## time (the start sync is NetSession's job, not modelled here). Every message is encoded with
## NetCodec.encode and decoded with NetCodec.decode on the receiving side, like the real session.
##
## Determinism: actors (one judge-tick grid for every live rig, the autoplay humans, the scripted
## fires) run in global song-time order exactly like MatchHarness.advance_to (ties: tick grid,
## then autoplay by seat, then fires by seat). The fixed frame step (1/fps) only decides when
## messages are flushed, carried, pumped and received.
##
## opts (each read with opts.get(key, default) and clamped):
## - clients 1..3 (default 3); seed (int, default 0)
## - flight_beats 1..2 (cfg.torpedo_travel_beats, default 2)
## - d_s: host input horizon D in seconds (default 0.08, 0..1)
## - latency_s, jitter_s, loss: defaults for every client link (uniform +-jitter)
## - links: {seat: {latency_s, jitter_s, loss}} per-seat overrides
## - margin_rtt_p90_s: -1 (default) derives each client seat's RTT p90 as
##   2 x (latency + jitter) of its link; >= 0 pins it for every client seat, so the D-09
##   approach margin (and therefore payload spans) do not change with the link profile.
##   The host seat always uses margin 0.
## - fire_every_beats (0 = off, default 8), fire_from_beat (default 16): every seat calls
##   request_fire on its referee at those whole beats (refusals are fine).
## - drop_seat (-1 = none) and drop_at_s: that client's link dies at drop_at_s.
## - end_t: default min(chart end + 2 s, 60 s); fps (default 120, 10..2000); tick_s (default
##   MatchHarness.TICK_S); cfg (VersusConfig), jcfg (JudgeConfig).
##
## Frame step (step(t)):
## 1. every actor due up to t runs in global order;
## 2. each live client's RemoteReferee.set_now(t) + flush() -> encode -> hub (reliable);
## 3. hub.advance(t) (host decodes INPUTS, push_item with the sender's seat);
## 4. queue.pump(t);
## 5. host_channel.take_batches() -> encode -> hub (reliable);
## 6. hub.advance(t) again (clients decode EVENTS, NetClientChannel.receive);
## 7. the scripted drop when due: hub.drop_peer(client); the host drops the seat
##    (queue.drop_seat(seat, "disconnected"), host_channel.remove_peer) when peer_left fires.

const START_T := -1.0
const HANDSHAKE_T := -5.0
const MAX_END_S := 60.0
const APPROACH_S := 1.5
const FINISH_SLACK_S := 1.0

var chart: ChartData
var cfg: VersusConfig
var jcfg: JudgeConfig
var seed: int = 0
var clients: int = 3
var d_s: float = 0.08
var fps: float = 120.0
var tick_s: float = MatchHarness.TICK_S
var end_t: float = 0.0
var now: float = START_T
var fire_every_beats: int = 8
var fire_from_beat: int = 16
var drop_seat: int = -1
var drop_at_s: float = INF

## Host side.
var host_players: Array[PlayerState] = []
var host_channel: NetHostChannel
var sim: MatchSim
var queue: HostInputQueue
var host_transport: MemTransport

## seat -> SubRig (host seat 0 and every client seat).
var rigs := {}
## Client seat -> RemoteReferee / NetClientChannel / MemTransport / players copy.
var referees := {}
var client_channels := {}
var client_transports := {}
var client_players := {}
## The shared virtual-time medium. Keep every endpoint referenced (the hub holds them weakly).
var hub: MemTransport.Hub

## seat -> peer id and back.
var peer_of := {}
var seat_of := {}
## Seats whose link was dropped (by the script) and seats the host already removed.
var dropped := {}
var host_left := {}

## Telegraph / overlay measurements.
var telegraph: Array[Dictionary] = []
var overlay: Array[Dictionary] = []
## seat -> {torpedo id -> client song time the TORPEDO_LAUNCH was emitted}.
var _launch_receipt := {}
## torpedo id -> TORPEDO_LAUNCH event (host log).
var _launches := {}

var _ctx_host := {}
var _ctx_client := {}
var _actors: Array = []
var _finished := false
var _drop_done := false


## Judge tick grid for every live rig (host and clients), then each referee's song time.
class _TickActor:
	var h: NetMatchHarness
	var k: int

	func _init(p_h: NetMatchHarness) -> void:
		h = p_h
		k = int(ceil(START_T / h.tick_s))

	func next_time() -> float:
		return float(k) * h.tick_s

	func step() -> void:
		var t := next_time()
		k += 1
		for s in h.live_seats():
			var rig: SubRig = h.rigs[s]
			rig.tick(t)
			rig.sim.update(t)


## Scripted fires: one seat requests a fire at every fire_every_beats whole beats.
class _FireActor:
	var h: NetMatchHarness
	var seat: int
	var beat: int

	func _init(p_h: NetMatchHarness, p_seat: int) -> void:
		h = p_h
		seat = p_seat
		beat = h.fire_from_beat

	func next_time() -> float:
		if h.fire_every_beats <= 0 or not h.is_live(seat):
			return INF
		return BeatClock.time_at_beat(float(beat), h.chart.tempo_map)

	func step() -> void:
		var t := next_time()
		beat += h.fire_every_beats
		var rig: SubRig = h.rigs[seat]
		rig.begin(t)
		rig.sim.request_fire(seat, t)


## Wraps an autoplay human so a dropped client's machine stops playing.
class _SeatAuto:
	var h: NetMatchHarness
	var seat: int
	var a: MatchHarness._AutoActor

	func _init(p_h: NetMatchHarness, p_seat: int, p_a: MatchHarness._AutoActor) -> void:
		h = p_h
		seat = p_seat
		a = p_a

	func next_time() -> float:
		return a.next_time() if h.is_live(seat) else INF

	func step() -> void:
		a.step()


func _init(p_chart: ChartData, opts: Dictionary = {}) -> void:
	chart = p_chart
	seed = int(opts.get("seed", 0))
	clients = clampi(int(opts.get("clients", 3)), 1, NetProtocol.MAX_CLIENTS)
	d_s = clampf(float(opts.get("d_s", 0.08)), 0.0, 1.0)
	fps = clampf(float(opts.get("fps", 120.0)), MatchHarness.MIN_FPS, MatchHarness.MAX_FPS)
	tick_s = clampf(float(opts.get("tick_s", MatchHarness.TICK_S)), 0.001, 0.05)
	fire_every_beats = maxi(int(opts.get("fire_every_beats", 8)), 0)
	fire_from_beat = maxi(int(opts.get("fire_from_beat", 16)), 0)
	drop_seat = int(opts.get("drop_seat", -1))
	if drop_seat < 1 or drop_seat > clients:
		drop_seat = -1
	drop_at_s = float(opts.get("drop_at_s", INF))
	var base_cfg: VersusConfig = opts.get("cfg", null)
	cfg = (base_cfg if base_cfg != null else VersusConfig.new()).validated()
	cfg.torpedo_travel_beats = clampi(int(opts.get("flight_beats", 2)), 1, 2)
	jcfg = opts.get("jcfg", null)
	if jcfg == null:
		jcfg = JudgeConfig.new()
	var last := 0.0
	for n in chart.notes:
		last = maxf(last, float(n["time"]) + float(n["duration"]))
	end_t = clampf(float(opts.get("end_t", minf(last + 2.0, MAX_END_S))), 1.0,
		MatchHarness.MAX_SONG_S)
	var song_len := end_t + d_s + FINISH_SLACK_S + 2.0
	_ctx_host = {"from_host": false, "note_count": chart.notes.size(), "song_len": song_len,
		"max_seat": clients}
	_ctx_client = {"from_host": true, "note_count": chart.notes.size(), "song_len": song_len,
		"max_seat": clients}

	# Roster: seat 0 "HOST", then "C1".."C3".
	var names: Array[String] = ["HOST"]
	for k in range(1, clients + 1):
		names.append("C%d" % k)
	for s in range(clients + 1):
		host_players.append(PlayerState.new(s, names[s], true))

	# Host: MatchSim + NetHostChannel + HostInputQueue, SubRig(0) on the queue.
	host_channel = NetHostChannel.new()
	sim = MatchSim.new(chart, cfg, jcfg, host_players, host_channel, seed)
	queue = HostInputQueue.new(sim, host_channel, d_s)
	var host_rig := SubRig.new(0, chart, jcfg, cfg, queue, host_channel, false)
	rigs[0] = host_rig

	# Transport: the hub clock is the shared song time.
	hub = MemTransport.Hub.new(seed)
	hub.now = HANDSHAKE_T
	host_transport = hub.make_host()
	host_transport.auth_request.connect(_on_auth_request)
	host_transport.peer_left.connect(_on_peer_left)
	host_transport.packet.connect(_on_host_packet)
	var links: Dictionary = opts.get("links", {})
	var pin := float(opts.get("margin_rtt_p90_s", -1.0))
	for s in range(1, clients + 1):
		var c := hub.make_client()
		var id := c.unique_id()
		peer_of[s] = id
		seat_of[id] = s
		client_transports[s] = c
		var l: Dictionary = links.get(s, {})
		var lat := clampf(float(l.get("latency_s", opts.get("latency_s", 0.0))), 0.0, 2.0)
		var jit := clampf(float(l.get("jitter_s", opts.get("jitter_s", 0.0))), 0.0, 2.0)
		var loss := clampf(float(l.get("loss", opts.get("loss", 0.0))), 0.0, 1.0)
		hub.set_link(id, lat, jit, loss)
		c.packet.connect(_on_client_packet.bind(s))
		# Client: own PlayerState copies, NetClientChannel, RemoteReferee, SubRig(s).
		var ps: Array[PlayerState] = []
		for k in range(clients + 1):
			ps.append(PlayerState.new(k, names[k], true))
		client_players[s] = ps
		var ch := NetClientChannel.new(s, _song_now, _ctx_client)
		client_channels[s] = ch
		var ref := RemoteReferee.new(s, ps, _on_client_send.bind(s))
		ref.bind(ch)
		referees[s] = ref
		ch.received.connect(_on_client_event.bind(s))
		rigs[s] = SubRig.new(s, chart, jcfg, cfg, ref, ch, false)
		var rtt := pin if pin >= 0.0 else 2.0 * (lat + jit)
		queue.set_net_margin(s, HostInputQueue.margin_for(d_s, rtt))
	queue.set_net_margin(0, 0.0)
	_handshake()

	# Every rig: approach 1.5 s (the setter reports APPROACH through its referee).
	for s in rigs:
		rigs[s].approach_s = APPROACH_S

	# Actors: tick grid, autoplay humans by seat, fires by seat.
	_actors.append(_TickActor.new(self))
	for s in range(clients + 1):
		_actors.append(_SeatAuto.new(self, s, MatchHarness._AutoActor.new(chart, rigs[s])))
	for s in range(clients + 1):
		_actors.append(_FireActor.new(self, s))
	host_channel.received.connect(_on_host_event)


## Connect + auth every client before the song (virtual time HANDSHAKE_T .. START_T).
func _handshake() -> void:
	for s in client_transports:
		client_transports[s].connect_to_host()
	var t := HANDSHAKE_T
	var auth_sent := {}
	while t < START_T - 0.01:
		t += 0.01
		hub.advance(t)
		for s in client_transports:
			var c: MemTransport = client_transports[s]
			if c.state == MemTransport.State.CONNECTING and not auth_sent.has(s):
				auth_sent[s] = true
				c.send_auth(NetTransport.HOST_ID, NetCodec.encode({"type": NetProtocol.AUTH,
					"proto": NetProtocol.PROTO, "game": "undertow", "name": "C%d" % s}))
	hub.advance(START_T - 0.01)


func _on_auth_request(peer: int, bytes: PackedByteArray) -> void:
	var m := NetCodec.decode(bytes, _ctx_host)
	if m.get("type", "") != NetProtocol.AUTH or not seat_of.has(peer):
		host_transport.refuse_auth(peer, PackedByteArray())
		return
	host_transport.complete_auth(peer)
	host_channel.add_peer(peer)


func _on_peer_left(peer: int) -> void:
	var s: int = seat_of.get(peer, -1)
	if s < 0 or host_left.has(s):
		return
	host_left[s] = true
	queue.drop_seat(s, "disconnected")
	host_channel.remove_peer(peer)


func _on_host_packet(peer: int, bytes: PackedByteArray) -> void:
	var s: int = seat_of.get(peer, -1)
	if s < 0:
		return
	var m := NetCodec.decode(bytes, _ctx_host)
	if m.get("type", "") != NetProtocol.INPUTS:
		return
	for item in m["items"]:
		queue.push_item(s, item)


func _on_client_send(msg: Dictionary, s: int) -> void:
	var c: MemTransport = client_transports[s]
	c.send(NetTransport.HOST_ID, NetCodec.encode(msg), true)


func _on_client_packet(_peer: int, bytes: PackedByteArray, s: int) -> void:
	var m := NetCodec.decode(bytes, _ctx_client)
	if m.get("type", "") != NetProtocol.EVENTS:
		return
	client_channels[s].receive(m)


func _song_now() -> float:
	return now


## Client-side measurements: telegraph receipt and overlay receipt (D-08, D-09).
func _on_client_event(e: Dictionary, s: int) -> void:
	match e.get("type", ""):
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("to", -1)) == s:
				if not _launch_receipt.has(s):
					_launch_receipt[s] = {}
				_launch_receipt[s][int(e["id"])] = now
		GameEvent.LANDED:
			if int(e.get("to", -1)) != s:
				return
			var id := int(e["id"])
			var rec: Dictionary = _launch_receipt.get(s, {})
			if rec.has(id):
				telegraph.append({"target": s, "id": id,
					"launch_t": float(_launches[id]["launch_t"]) if _launches.has(id) else NAN,
					"arrive_t": float(e["arrive_t"]), "target_receipt_t": float(rec[id])})
			var reward := int(e.get("reward", -1))
			if reward == Reward.Id.GHOST_NOTES or reward == Reward.Id.DEPTH_CHARGE:
				overlay.append({"target": s, "id": id, "reward": reward, "receipt_t": now,
					"arrive_t": float(e["arrive_t"]), "active_start": float(e["active_start"]),
					"approach_local": float(rigs[s].approach_s)})


func _on_host_event(e: Dictionary) -> void:
	if e.get("type", "") == GameEvent.TORPEDO_LAUNCH:
		_launches[int(e["id"])] = e


## A seat whose machine is still playing (the host, or a client whose link is up).
func is_live(s: int) -> bool:
	return not dropped.has(s)


func live_seats() -> Array:
	var out: Array = []
	for s in range(clients + 1):
		if is_live(s):
			out.append(s)
	return out


## Runs every due actor up to song time t in global time order (never past end_t).
func advance_to(t: float) -> void:
	t = minf(t, end_t)
	var guard := 0
	while guard < 10000000:
		guard += 1
		var best = null
		var best_t := INF
		for a in _actors:
			var at: float = a.next_time()
			if at < best_t:
				best_t = at
				best = a
		if best == null or best_t > t:
			break
		best.step()


## One frame at song time t (see the header for the order).
func step(t: float) -> void:
	advance_to(t)
	now = maxf(now, t)
	_net_frame(now)
	if drop_seat != -1 and not _drop_done and now >= drop_at_s:
		_drop_done = true
		dropped[drop_seat] = true
		hub.drop_peer(peer_of[drop_seat])


func _net_frame(t: float) -> void:
	for s in referees:
		if is_live(s):
			var ref: RemoteReferee = referees[s]
			ref.set_now(t)
			ref.flush()
	hub.advance(t)
	queue.pump(t)
	_send_batches()
	hub.advance(t)


func _send_batches() -> void:
	var batches := host_channel.take_batches()
	for peer in batches:
		for msg in batches[peer]:
			host_transport.send(peer, NetCodec.encode(msg), true)


## Releases everything, ends the match (MATCH_END once) and delivers the last batches.
func finish() -> void:
	if _finished:
		return
	_finished = true
	step(end_t)
	# Every input in flight lands first (latency + jitter well below FINISH_SLACK_S), then the
	# horizon is released exactly to end_t so MATCH_END (at end_t) stays the last event and the
	# host log's times never decrease.
	now = end_t + FINISH_SLACK_S
	hub.advance(now)
	queue.pump(end_t + d_s)
	sim.finish(end_t)
	_send_batches()
	now += FINISH_SLACK_S
	hub.advance(now)
	# Actors hold the harness: cut the cycle so a finished harness is freed (CR-02 style).
	_actors.clear()


func result() -> Dictionary:
	var host_log: Array = host_channel.broadcast_log.duplicate(true)
	var client_logs := {}
	for s in client_channels:
		client_logs[s] = client_channels[s].received_log.duplicate(true)
	var standings: Array = []
	var duel_live: Array = []
	for e in host_log:
		match e["type"]:
			GameEvent.MATCH_END:
				standings = e["standings"]
			GameEvent.DUEL_LIVE:
				duel_live.append(e)
	return {"host_log": host_log, "client_logs": client_logs, "late_inputs": queue.late_inputs,
		"rejected_future": queue.rejected_future, "standings": standings,
		"telegraph": telegraph.duplicate(true), "overlay": overlay.duplicate(true),
		"duel_live_events": duel_live, "end_t": end_t, "hub_dropped": hub.dropped}


## Whole online match: steps from START_T to end_t in 1/fps frames, then finish().
static func run(p_chart: ChartData, opts: Dictionary = {}) -> Dictionary:
	var h := NetMatchHarness.new(p_chart, opts)
	h.run_to(h.end_t)
	h.finish()
	return h.result()


## Fixed-step frames from the current time up to t.
func run_to(t: float) -> void:
	var dt := 1.0 / fps
	var k := int(round((now - START_T) * fps))
	while now < minf(t, end_t) - 1e-9:
		k += 1
		step(minf(START_T + float(k) * dt, end_t))
