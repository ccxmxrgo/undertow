class_name VersusController
extends Node
## Match wiring under Gameplay's run root (MATCH-01, MATCH-06, D-18, D-27, D-28). Mirrors the
## MatchHarness construction for a live scene: PlayerStates (the human "YOU" at seat 0, bots
## at seats 1..rivals with MatchSetup.callsigns, or the training "DRONE"), a LoopbackChannel,
## the MatchSim referee, the human SubRig (VersusJudge / VersusHull / PayloadStack), bot SubRigs
## driven by BotPlayers, and the TrainingDrone. bind_views() creates and binds every versus view.
##
## Per frame (Gameplay._process): pre_tick(t) = advance_to(t), then update(t) for the views.
## Determinism (WR-01, Pitfall 6): advance_to runs every due action in global song-time order
## exactly like MatchHarness: a fixed TICK_S judge-tick grid for every rig (then the referee and
## the channel), the autoplay human, the bots by seat and the drone. The human's real presses,
## releases, fire and target input first advance everything due before their own song time
## (human_press / human_release / fire / cycle_target), so the referee never sees time run
## backwards by a frame. The same event log comes out at any frame rate. Everything is stamped
## with the audio clock song time, never the frame time. Versus rigs never read
## Settings.no_fail: versus forces no_fail false, Solo Dive training forces it true (T-03-33).
##
## Modes: versus (a MatchSetup with rivals 1..3); training (practice, drone_mode != -1: one drone
## seat); training OFF (practice, no rivals: the meter, bag and buffs run, no periscope column
## and no killfeed, UI-SPEC 8.3).
##
## Online (Phase 4, D-03, D-13, D-19): setup_online() builds one of two network backends next
## to the unchanged offline one. Host: MatchSim behind a HostInputQueue, events through a
## NetHostChannel. Client: a RemoteReferee proxy, events from a NetClientChannel. The views
## bind to `channel` and `local_seat` exactly as offline. There are no bots and no drone online.
## NetSession.pump_match owns the network pump (queue.pump / take_batches / remote.flush); the
## controller never pumps, except the final drain in finish() on the host.

## Test seam: drive the human with VersusAutoplay in a versus match (a versus launch with
## pending_autoplay is discarded by design). Reset by the tests.
static var test_autoplay_human: bool = false

## Offline seat of the human (kept for compatibility); online the seat is local_seat.
const HUMAN_SEAT := 0
## Judge tick grid, shared with MatchHarness so live and headless matches tick identically.
const TICK_S := MatchHarness.TICK_S
## FIRE_REFUSED reasons (MatchSim._refuse) that play the error blip online: the same cases as
## FIRE_SHIELDED / FIRE_NO_TARGET offline. "nothing" and "race" stay silent.
const REFUSAL_BLIP_REASONS := ["shielded", "no_target"]

var match_setup: MatchSetup
var versus: bool = false
var training: bool = false
## -1 off, -2 all disruptors in turn, else the drone's Reward id.
var drone_mode: int = -1
var chart: ChartData
var jcfg: JudgeConfig
var cfg: VersusConfig
var match_seed: int = 0
## The seat this PC drives (HUMAN_SEAT offline, the session's seat online).
var local_seat: int = HUMAN_SEAT
## Offline: a LoopbackChannel. Online: host_channel or client_channel.
var channel: EventChannel
## The rig-facing referee: the MatchSim offline, the HostInputQueue on the host, the
## RemoteReferee on a client.
var sim: Referee
## The real rules (offline and host). Null on clients (D-19: clients never call MatchSim).
var match_sim: MatchSim

## Online state (all null / false offline).
var online: bool = false
var is_host: bool = false
## Input delay D in seconds (online).
var d_s: float = 0.0
var queue: HostInputQueue
var host_channel: NetHostChannel
var remote: RemoteReferee
var client_channel: NetClientChannel
## Client only: receives each INPUTS message RemoteReferee.flush() produces. Set it before
## setup_online; the default (an invalid Callable) drops the message.
var net_send: Callable = Callable()
var players: Array[PlayerState] = []
## Callsigns indexed by seat ("YOU" first).
var names := PackedStringArray()
var human_rig: SubRig
var human_judge: VersusJudge
var human_hull: VersusHull
var human_stack: PayloadStack
## seat -> SubRig for the bots.
var bot_rigs := {}
var bots: Array[BotPlayer] = []
var drone: TrainingDrone
var drone_seat: int = -1
## The autoplay human (tests, playtest): VersusAutoplay stepped at its own event times.
var autoplay_human: MatchHarness._AutoActor
## Song time everything has been advanced to (advance_to).
var now: float = -INF

## Time-ordered actors (WR-01): tick grid, autoplay human, bots by seat, drone.
var _actors: Array = []
var _bot_seats: Array = []

# Views (null when the mode has none).
var ink_cloud: InkCloudLayer
var ink_top: InkTopLayer
var reward_socket: RewardSocket
var target_readout: TargetReadout
var status_chips: StatusChips
var versus_hud: VersusHud
var periscope_column: PeriscopeColumn
var killfeed: Killfeed
var incoming_alert: IncomingAlert
var event_banner: EventBanner
var edge_flash: EdgeFlash
var torpedo_juice: TorpedoJuice
var reward_popup: RewardPopup
var versus_sfx: VersusSfx
## Refusal blips played (SHIELDED / NO TARGET). Tests read it; nothing plays on FIRE_NOTHING.
var error_blips: int = 0

var _hud: Hud
var _feedback: Feedback
var _error_player: AudioStreamPlayer
var _finish_data: Dictionary = {}


## setup: the versus launch record (MODE_VERSUS) or null for a Solo Dive; p_drone_mode is
## MatchSetup.training_reward(Settings.training_payload) for a Solo Dive (ignored in versus).
func setup(gp: Gameplay, p_chart: ChartData, p_jcfg: JudgeConfig, p_setup: MatchSetup,
		p_drone_mode: int, autoplay: bool = false) -> void:
	name = "VersusController"
	chart = p_chart
	jcfg = p_jcfg
	match_setup = p_setup
	versus = p_setup != null and p_setup.mode == MatchSetup.MODE_VERSUS
	training = not versus
	drone_mode = -1 if versus else p_drone_mode
	cfg = VersusConfig.new().validated()
	var rivals := clampi(p_setup.rivals, MatchSetup.MIN_RIVALS, MatchSetup.MAX_RIVALS) if versus else 0
	match_seed = p_setup.seed if versus else MatchSetup.new_seed()
	players.clear()
	names = PackedStringArray()
	players.append(PlayerState.new(HUMAN_SEAT, "YOU", true))
	names.append("YOU")
	var calls := MatchSetup.callsigns(match_seed, rivals)
	for i in range(rivals):
		var nm := calls[i] if i < calls.size() else "BOT%d" % (i + 1)
		players.append(PlayerState.new(i + 1, nm))
		names.append(nm)
	if training and drone_mode != -1:
		drone_seat = players.size()
		players.append(PlayerState.new(drone_seat, "DRONE", false, true))
		names.append("DRONE")
	channel = LoopbackChannel.new()
	match_sim = MatchSim.new(chart, cfg, jcfg, players, channel, match_seed)
	sim = match_sim
	_make_human_rig(training)
	var profile := BotProfile.from_skill(p_setup.skill if versus else "regular")
	for i in range(rivals):
		var s := i + 1
		var rig := SubRig.new(s, chart, jcfg, cfg, match_sim, channel, false)
		bot_rigs[s] = rig
		bots.append(BotPlayer.new(rig, profile, match_sim, cfg, chart, hash([match_seed, "bot", s])))
	if drone_seat != -1:
		drone = TrainingDrone.new(match_sim, chart, cfg, drone_seat, HUMAN_SEAT, drone_mode)
	_actors.append(_TickActor.new(self))
	if autoplay or (versus and test_autoplay_human):
		autoplay_human = MatchHarness._AutoActor.new(chart, human_rig)
		_actors.append(autoplay_human)
	_bot_seats = bot_rigs.keys()
	_bot_seats.sort()
	for b in bots:
		_actors.append(b)
	if drone != null:
		_actors.append(drone)
	_finish_wiring(gp)


## Online setup (D-03). spec = NetSession.pending_match() plus `margins`:
##   role "host" | "client", local_seat, names (PackedStringArray by seat), seed, flight
##   (torpedo_travel_beats), d_s, autoplay, margins {seat: rtt_p90_s} (host; 0 for the host),
##   optional song_len (client event-validation context; default the chart length).
## Host: MatchSim behind a HostInputQueue, a NetHostChannel; the human at local_seat (0).
## Client: a RemoteReferee (its INPUTS go to net_send) and a NetClientChannel.
## No bots and no drone. Set net_send (client) before calling.
func setup_online(gp: Gameplay, p_chart: ChartData, p_jcfg: JudgeConfig, spec: Dictionary) -> void:
	name = "VersusController"
	chart = p_chart
	jcfg = p_jcfg
	match_setup = null
	online = true
	versus = true
	training = false
	drone_mode = -1
	is_host = str(spec.get("role", "")) == "host"
	local_seat = int(spec.get("local_seat", HUMAN_SEAT))
	d_s = maxf(float(spec.get("d_s", 0.0)), 0.0)
	match_seed = int(spec.get("seed", 0))
	cfg = VersusConfig.new()
	cfg.torpedo_travel_beats = int(spec.get("flight", cfg.torpedo_travel_beats))
	cfg = cfg.validated()
	players.clear()
	names = PackedStringArray()
	var spec_names := PackedStringArray(spec.get("names", PackedStringArray()))
	# CR-01: players come from the roster seats, never from the name indices. A seat gap (seat 1
	# left the lobby, seat 2 stayed) keeps `names` indexable by seat with "" in the gap but
	# builds no PlayerState there (a phantom would never die and would break RESULTS).
	var roster := roster_seats(spec, spec_names, local_seat)
	for s in range(mini(spec_names.size(), NetProtocol.MAX_SEATS)):
		if not roster.has(s):
			names.append("")
			continue
		var nm := spec_names[s]
		players.append(PlayerState.new(s, nm, s == local_seat))
		names.append("YOU" if s == local_seat else nm)
	if is_host:
		host_channel = NetHostChannel.new()
		channel = host_channel
		match_sim = MatchSim.new(chart, cfg, jcfg, players, channel, match_seed)
		queue = HostInputQueue.new(match_sim, channel, d_s)
		sim = queue
	else:
		var ctx := {"from_host": true, "note_count": chart.notes.size(),
			"song_len": float(spec.get("song_len", ProgressTrack.song_length_of(chart))),
			"max_seat": NetProtocol.MAX_SEATS - 1}
		client_channel = NetClientChannel.new(local_seat, Callable(self, "_song_now"), ctx)
		channel = client_channel
		match_sim = null
		remote = RemoteReferee.new(local_seat, players, Callable(self, "_send_net"))
		remote.bind(channel)
		sim = remote
	_make_human_rig(false)
	if is_host:
		var margins: Variant = spec.get("margins", {})
		if margins is Dictionary:
			for s in margins:
				var rtt: Variant = margins[s]
				if (s is int) and (rtt is float or rtt is int):
					queue.set_net_margin(s, HostInputQueue.margin_for(d_s, float(rtt)))
	_actors.append(_TickActor.new(self))
	if bool(spec.get("autoplay", false)) or test_autoplay_human:
		autoplay_human = MatchHarness._AutoActor.new(chart, human_rig)
		_actors.append(autoplay_human)
	_bot_seats = []
	_finish_wiring(gp)


## CR-01: the seats that hold a player online. spec.seats when present (the LOAD roster), else
## every seat with a non-empty name; the local seat always counts.
static func roster_seats(spec: Dictionary, spec_names: PackedStringArray, p_local: int) -> Array:
	var out: Array = []
	var v: Variant = spec.get("seats", [])
	if v is Array and not (v as Array).is_empty():
		for s: Variant in v:
			if (s is int or s is float) and not out.has(int(s)):
				out.append(int(s))
	else:
		for s in spec_names.size():
			if spec_names[s] != "":
				out.append(s)
	if p_local >= 0 and not out.has(p_local):
		out.append(p_local)
	out.sort()
	return out


## The human rig at local_seat on `sim` / `channel` (shared by setup and setup_online).
func _make_human_rig(no_fail: bool) -> void:
	human_rig = SubRig.new(local_seat, chart, jcfg, cfg, sim, channel, no_fail)
	human_rig.approach_s = Trench.approach_for(Settings.scroll_speed)
	# IN-03: the pause-menu settings can change the scroll speed mid-match; the Ghost Notes /
	# Depth Charge window (Pitfall 1) must follow it.
	if not Settings.settings_changed.is_connected(_on_settings_changed):
		Settings.settings_changed.connect(_on_settings_changed)
	human_judge = human_rig.judge
	human_hull = human_rig.hull
	human_stack = human_rig.stack


## The controller's own event handler and the error blip player (after every rig connected).
func _finish_wiring(gp: Gameplay) -> void:
	channel.received.connect(_on_event)
	_error_player = AudioStreamPlayer.new()
	_error_player.name = "ErrorBlip"
	_error_player.stream = AudioSynth.make_ui_blip("error")
	var ui := get_node_or_null("/root/UiSounds") if gp != null and gp.is_inside_tree() else null
	_error_player.bus = ui.call("bus_name") if ui != null else &"Master"
	add_child(_error_player)


## Client: the song time the controller has advanced to (NetClientChannel landed probe).
func _song_now() -> float:
	return now


## Client: RemoteReferee's send_fn; forwards each INPUTS message to net_send.
func _send_net(msg: Dictionary) -> void:
	if net_send.is_valid():
		net_send.call(msg)


## Per frame online, after pre_tick and update and before NetSession.pump_match(t): a client
## stamps non-finite input times with t (RemoteReferee.set_now). No-op on the host / offline.
func net_tick(t: float) -> void:
	if remote != null:
		remote.set_now(t)


## F3 overlay rows: HostInputQueue.debug_stats (host) or NetClientChannel.debug_stats (client)
## plus {online, is_host, local_seat, d_s}. {} offline.
func debug_net() -> Dictionary:
	if not online:
		return {}
	var out := {"online": true, "is_host": is_host, "local_seat": local_seat, "d_s": d_s}
	if queue != null:
		out.merge(queue.debug_stats())
	if client_channel != null:
		out.merge(client_channel.debug_stats())
	if remote != null:
		out["pending_inputs"] = remote.pending_count()
		out["ignored_foreign"] = remote.ignored_foreign
	return out


## True when the run shows rival views (versus, or training with a drone).
func has_rivals() -> bool:
	return versus or drone_seat != -1


## Rival seats shown in the periscope column (bots, or the drone).
func rival_seats() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if p.seat != local_seat:
			out.append(p.seat)
	return out


## Creates and binds the versus views. Call after Gameplay built board_root (with HighwayNotes)
## and the Hud, and before the StreakCounter (VersusHud sits between them, UI-SPEC 1).
func bind_views(gp: Gameplay) -> void:
	_hud = gp.hud
	_feedback = gp.feedback
	var highway := gp.highway
	highway.bind_versus(human_stack, human_judge, cfg)
	gp.lane_input.payloads = human_stack
	# WR-01: real presses advance the rivals to the press time first (global time order).
	gp.lane_input.press_fn = human_press
	gp.lane_input.release_fn = human_release
	gp.lane_input.lane_released.connect(highway.on_lane_released)
	human_judge.ghost_hit.connect(_on_ghost_hit)
	# Board layers above Feedback / FxLayer / HighwayNotes.
	ink_cloud = InkCloudLayer.new()
	ink_cloud.name = "InkCloudLayer"
	gp.board_root.add_child(ink_cloud)
	ink_cloud.bind(highway)
	ink_top = InkTopLayer.new()
	ink_top.name = "InkTopLayer"
	gp.board_root.add_child(ink_top)
	ink_top.bind(highway)
	# Hud children: RewardSocket over TorpedoSocket, then TargetReadout.
	reward_socket = RewardSocket.new()
	reward_socket.name = "RewardSocket"
	_hud.add_child(reward_socket)
	reward_socket.bind(channel, local_seat, cfg)
	target_readout = TargetReadout.new()
	target_readout.name = "TargetReadout"
	_hud.add_child(target_readout)
	target_readout.bind(channel, local_seat, names, drone_seat != -1)
	status_chips = StatusChips.new()
	status_chips.name = "StatusChips"
	add_child(status_chips)
	status_chips.bind(channel, local_seat, _hud, cfg, chart, players.size() if versus else 1, training)
	if training:
		_hud.set_solo_dive(true)
	versus_sfx = VersusSfx.new()
	versus_sfx.name = "VersusSfx"
	add_child(versus_sfx)
	versus_sfx.bind(channel, local_seat)
	# VersusHud: after Hud, before StreakCounter.
	versus_hud = VersusHud.new()
	gp.hud.get_parent().add_child(versus_hud)
	gp.hud.get_parent().move_child(versus_hud, gp.hud.get_index() + 1)
	if has_rivals():
		periscope_column = PeriscopeColumn.new()
		periscope_column.name = "PeriscopeColumn"
		versus_hud.add_child(periscope_column)
		periscope_column.bind(channel, local_seat, rival_seats(), names, chart, cfg,
			Callable(sim, "duel_live"), training)
		killfeed = Killfeed.new()
		killfeed.name = "Killfeed"
		versus_hud.add_child(killfeed)
		killfeed.bind(channel, local_seat, names, cfg)
	incoming_alert = IncomingAlert.new()
	incoming_alert.name = "IncomingAlert"
	versus_hud.add_child(incoming_alert)
	incoming_alert.bind(channel, local_seat, Array(names), chart, cfg, versus_sfx)
	event_banner = EventBanner.new()
	event_banner.name = "EventBanner"
	versus_hud.add_child(event_banner)
	event_banner.bind(channel, local_seat, Array(names), cfg, Callable(sim, "duel_live"),
		_hud.section_banner)
	edge_flash = EdgeFlash.new()
	edge_flash.name = "EdgeFlash"
	versus_hud.add_child(edge_flash)
	edge_flash.bind(channel, local_seat)
	# 05-05 (D-05): impact / launch / implosion juice, view-only on the same channel.
	torpedo_juice = TorpedoJuice.new()
	torpedo_juice.name = "TorpedoJuice"
	versus_hud.add_child(torpedo_juice)
	torpedo_juice.bind(channel, local_seat, gp.fx_layer, reward_socket, periscope_column)
	reward_popup = RewardPopup.new()
	reward_popup.name = "RewardPopup"
	versus_hud.add_child(reward_popup)
	reward_popup.bind(channel, local_seat, func() -> bool:
		return gp.streak_counter != null and is_instance_valid(gp.streak_counter) \
			and gp.streak_counter.popup_text() != "")


## Judge tick grid (WR-01): every rig ticks at k x TICK_S (expiry misses and sustain ticks at
## frame-rate independent times), then the referee and the channel catch up. Same as
## MatchHarness._TickActor.
class _TickActor:
	var vc: VersusController
	var k: int

	func _init(p_vc: VersusController) -> void:
		vc = p_vc
		k = int(ceil(MatchHarness.START_T / TICK_S))

	func next_time() -> float:
		return float(k) * TICK_S

	func step() -> void:
		var t := next_time()
		k += 1
		vc._tick_rigs(t)


func _tick_rigs(t: float) -> void:
	human_rig.tick(t)
	for s in _bot_seats:
		bot_rigs[s].tick(t)
	sim.update(t)
	channel.update(t)


## Runs every action due up to song time t in global time order (ties: tick grid, autoplay
## human, bots by seat, drone), as MatchHarness.advance_to does.
func advance_to(t: float) -> void:
	if not is_finite(t):
		return
	var guard := 0
	while guard < 1000000:
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
	now = maxf(now, t)


## Per frame, before the views: everything due by t (the human's judge ticks on the grid).
func pre_tick(t: float) -> void:
	advance_to(t)


## A real lane press of the human at song time t (LaneInput routes here in versus): rivals and
## ticks due before t run first, then the press reaches the judge with the rig stamped at t.
func human_press(lane: int, t: float) -> void:
	advance_to(t)
	human_rig.press(lane, t)


func human_release(lane: int, t: float) -> void:
	advance_to(t)
	human_rig.release(lane, t)


## After pre_tick: the human's payload stack and the views.
func update(t: float) -> void:
	human_stack.prune(t)
	if status_chips != null:
		status_chips.update(t)
	if periscope_column != null:
		periscope_column.update(t)
		if drone != null:
			periscope_column.set_drone_status(drone_status_text(drone.bars_until_next(t)))
	if incoming_alert != null:
		incoming_alert.observe(t)
	if event_banner != null:
		event_banner.observe(t)
	if edge_flash != null:
		edge_flash.observe(t)


static func drone_status_text(bars: int) -> String:
	var n := maxi(bars, 1)
	return "NEXT IN 1 BAR" if n == 1 else "NEXT IN %d BARS" % n


## Fire (TORP-02). A refused shot (shielded / no target) plays the error blip; nothing held
## plays nothing (UI-SPEC 10). Online the result is unknown (FIRE_REMOTE): the blip comes from
## FIRE_REFUSED for local_seat one round trip later (_on_event, D-13), never from the return.
func fire(t: float) -> int:
	advance_to(t)
	var r := sim.request_fire(local_seat, t)
	if not online and (r == MatchSim.FIRE_SHIELDED or r == MatchSim.FIRE_NO_TARGET):
		_error_blip()
	channel.update(t)
	return r


func _error_blip() -> void:
	error_blips += 1
	if _error_player != null and _error_player.is_inside_tree():
		_error_player.play()


## Target cycle (TORP-03, D-01); works without a reward so players can pre-aim.
func cycle_target(t: float = NAN) -> int:
	advance_to(t)
	var r := sim.cycle_target(local_seat, t)
	if is_finite(t):
		channel.update(t)
	return r


## Ends the match (MATCH_END once) and returns the VersusResultsScreen data. Offline and on
## the online host (D-19); clients never call it (their results come from NetSession) and get {}.
## Host: the input queue is drained first (pump(t + d_s) moves the horizon to t), so every input
## stamped up to t reaches MatchSim before the standings are taken.
func finish(t: float) -> Dictionary:
	if match_sim == null:
		return _finish_data
	advance_to(t)
	if queue != null:
		queue.pump(t + d_s)
	match_sim.update(t)
	match_sim.finish(t)
	channel.update(t)
	var rows: Array[Dictionary] = []
	var left := _left_times()
	for r in match_sim.standings():
		var row := r.duplicate()
		var p := _player(int(r["seat"]))
		row["name"] = p.callsign if p != null else "?"
		row["landed"] = p.landed if p != null else 0
		row["reflected"] = p.reflected if p != null else 0
		if left.has(row["seat"]):
			row["left"] = true
			row["left_t"] = left[row["seat"]]
		rows.append(row)
	var seats: Array[int] = []
	var drones: Array[int] = []
	for p in players:
		if p.is_drone:
			drones.append(p.seat)
		else:
			seats.append(p.seat)
	var last := -1
	for e in match_sim.event_log:
		if e.get("type", "") == GameEvent.LAST_STANDING:
			last = int(e.get("seat", -1))
	_finish_data = {"rows": rows, "local_seat": local_seat,
		"medals": MedalRules.medals(match_sim.event_log, seats, drones),
		"title": chart.title, "artist": chart.artist, "difficulty": chart.difficulty,
		"seed": match_seed, "last_standing_seat": last}
	if online:
		var host := _player(0)
		_finish_data["online"] = true
		_finish_data["is_host"] = is_host
		_finish_data["host_seat"] = 0
		_finish_data["host_name"] = host.callsign if host != null else ""
	return _finish_data


## Host: seat -> song time of its first PLAYER_LEFT in the broadcast log ({} offline).
func _left_times() -> Dictionary:
	var out := {}
	if host_channel == null:
		return out
	for e in host_channel.broadcast_log:
		if e.get("type", "") == GameEvent.PLAYER_LEFT:
			var s := int(e.get("seat", -1))
			if not out.has(s):
				out[s] = float(e.get("t", 0.0))
	return out


func _player(seat: int) -> PlayerState:
	for p in players:
		if p.seat == seat:
			return p
	return null


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == local_seat and _hud != null and is_instance_valid(_hud):
				_hud.set_wreck(true)
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == local_seat and int(e.get("reward", -1)) == Reward.Id.OVERCLOCK:
				_set_overclock(true)
		GameEvent.BUFF_ENDED:
			if int(e.get("seat", -1)) == local_seat and int(e.get("reward", -1)) == Reward.Id.OVERCLOCK:
				_set_overclock(false)
		GameEvent.FIRE_REFUSED:
			# D-13: online only (offline blips from fire()'s return code, never twice).
			if online and int(e.get("seat", -1)) == local_seat \
					and REFUSAL_BLIP_REASONS.has(str(e.get("reason", ""))):
				_error_blip()


func _on_settings_changed() -> void:
	if human_rig == null:
		return
	var a := Trench.approach_for(Settings.scroll_speed)
	if not is_equal_approx(human_rig.approach_s, a):
		human_rig.approach_s = a


func _set_overclock(on: bool) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.overclock = on


func _on_ghost_hit(lane: int, payload_id: int) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.on_ghost_hit(lane, payload_id)
