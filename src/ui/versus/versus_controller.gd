class_name VersusController
extends Node
## Match wiring under Gameplay's run root (MATCH-01, MATCH-06, D-18, D-27, D-28). Mirrors the
## MatchHarness construction for a live scene: PlayerStates (the human "YOU" at seat 0, bots
## at seats 1..rivals with MatchSetup.callsigns, or the training "DRONE"), a LoopbackChannel,
## the MatchSim referee, the human SubRig (VersusJudge / VersusHull / PayloadStack), bot SubRigs
## driven by BotPlayers, and the TrainingDrone. bind_views() creates and binds every versus view.
##
## Per frame (Gameplay._process): pre_tick(t) (rig input time + autoplay) -> judge.tick(t) ->
## update(t): bots, drone, sim, channel, then the views. Everything is stamped with the audio
## clock song time, never the frame time. Versus rigs never read Settings.no_fail: versus forces
## no_fail false, Solo Dive training forces it true (T-03-33).
##
## Modes: versus (a MatchSetup with rivals 1..3); training (practice, drone_mode != -1: one drone
## seat); training OFF (practice, no rivals: the meter, bag and buffs run, no periscope column
## and no killfeed, UI-SPEC 8.3).

## Test seam: drive the human with VersusAutoplay in a versus match (a versus launch with
## pending_autoplay is discarded by design). Reset by the tests.
static var test_autoplay_human: bool = false

const HUMAN_SEAT := 0

var match_setup: MatchSetup
var versus: bool = false
var training: bool = false
## -1 off, -2 all disruptors in turn, else the drone's Reward id.
var drone_mode: int = -1
var chart: ChartData
var jcfg: JudgeConfig
var cfg: VersusConfig
var match_seed: int = 0
var channel: LoopbackChannel
var sim: MatchSim
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
var autoplay_human: VersusAutoplay

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
	sim = MatchSim.new(chart, cfg, jcfg, players, channel, match_seed)
	human_rig = SubRig.new(HUMAN_SEAT, chart, jcfg, cfg, sim, channel, training)
	human_rig.approach_s = Trench.approach_for(Settings.scroll_speed)
	human_judge = human_rig.judge
	human_hull = human_rig.hull
	human_stack = human_rig.stack
	var profile := BotProfile.from_skill(p_setup.skill if versus else "regular")
	for i in range(rivals):
		var s := i + 1
		var rig := SubRig.new(s, chart, jcfg, cfg, sim, channel, false)
		bot_rigs[s] = rig
		bots.append(BotPlayer.new(rig, profile, sim, cfg, chart, hash([match_seed, "bot", s])))
	if drone_seat != -1:
		drone = TrainingDrone.new(sim, chart, cfg, drone_seat, HUMAN_SEAT, drone_mode)
	if autoplay or (versus and test_autoplay_human):
		autoplay_human = VersusAutoplay.new(chart, human_judge)
		human_rig.overlay_added.connect(func(_id: int, _notes: Array) -> void:
			autoplay_human.refresh(human_judge))
	channel.received.connect(_on_event)
	_error_player = AudioStreamPlayer.new()
	_error_player.name = "ErrorBlip"
	_error_player.stream = AudioSynth.make_ui_blip("error")
	var ui := get_node_or_null("/root/UiSounds") if gp != null and gp.is_inside_tree() else null
	_error_player.bus = ui.call("bus_name") if ui != null else &"Master"
	add_child(_error_player)


## True when the run shows rival views (versus, or training with a drone).
func has_rivals() -> bool:
	return versus or drone_seat != -1


## Rival seats shown in the periscope column (bots, or the drone).
func rival_seats() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if p.seat != HUMAN_SEAT:
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
	reward_socket.bind(channel, HUMAN_SEAT, cfg)
	target_readout = TargetReadout.new()
	target_readout.name = "TargetReadout"
	_hud.add_child(target_readout)
	target_readout.bind(channel, HUMAN_SEAT, names, drone_seat != -1)
	status_chips = StatusChips.new()
	status_chips.name = "StatusChips"
	add_child(status_chips)
	status_chips.bind(channel, HUMAN_SEAT, _hud, cfg, chart, players.size() if versus else 1, training)
	if training:
		_hud.set_solo_dive(true)
	versus_sfx = VersusSfx.new()
	versus_sfx.name = "VersusSfx"
	add_child(versus_sfx)
	versus_sfx.bind(channel, HUMAN_SEAT)
	# VersusHud: after Hud, before StreakCounter.
	versus_hud = VersusHud.new()
	gp.hud.get_parent().add_child(versus_hud)
	gp.hud.get_parent().move_child(versus_hud, gp.hud.get_index() + 1)
	if has_rivals():
		periscope_column = PeriscopeColumn.new()
		periscope_column.name = "PeriscopeColumn"
		versus_hud.add_child(periscope_column)
		periscope_column.bind(channel, HUMAN_SEAT, rival_seats(), names, chart, cfg,
			Callable(sim, "duel_live"), training)
		killfeed = Killfeed.new()
		killfeed.name = "Killfeed"
		versus_hud.add_child(killfeed)
		killfeed.bind(channel, HUMAN_SEAT, names, cfg)
	incoming_alert = IncomingAlert.new()
	incoming_alert.name = "IncomingAlert"
	versus_hud.add_child(incoming_alert)
	incoming_alert.bind(channel, HUMAN_SEAT, Array(names), chart, cfg, versus_sfx)
	event_banner = EventBanner.new()
	event_banner.name = "EventBanner"
	versus_hud.add_child(event_banner)
	event_banner.bind(channel, HUMAN_SEAT, Array(names), cfg, Callable(sim, "duel_live"),
		_hud.section_banner)
	edge_flash = EdgeFlash.new()
	edge_flash.name = "EdgeFlash"
	versus_hud.add_child(edge_flash)
	edge_flash.bind(channel, HUMAN_SEAT)
	reward_popup = RewardPopup.new()
	reward_popup.name = "RewardPopup"
	versus_hud.add_child(reward_popup)
	reward_popup.bind(channel, HUMAN_SEAT, func() -> bool:
		return gp.streak_counter != null and is_instance_valid(gp.streak_counter) \
			and gp.streak_counter.popup_text() != "")


## Before the human judge ticks: stamp the rig's input time, then the autoplay presses.
func pre_tick(t: float) -> void:
	human_rig.begin(t)
	if autoplay_human != null:
		autoplay_human.update(t)
		human_rig.begin(t)


## After the human judge ticked: bots, drone, referee, channel, then the views.
func update(t: float) -> void:
	human_stack.prune(t)
	for b in bots:
		b.update(t)
	if drone != null:
		drone.update(t)
	sim.update(t)
	channel.update(t)
	status_chips.update(t)
	if periscope_column != null:
		periscope_column.update(t)
		if drone != null:
			periscope_column.set_drone_status(drone_status_text(drone.bars_until_next(t)))
	incoming_alert.observe(t)
	event_banner.observe(t)
	edge_flash.observe(t)


static func drone_status_text(bars: int) -> String:
	var n := maxi(bars, 1)
	return "NEXT IN 1 BAR" if n == 1 else "NEXT IN %d BARS" % n


## Fire (TORP-02). A refused shot (shielded / no target) plays the error blip; nothing held
## plays nothing (UI-SPEC 10).
func fire(t: float) -> int:
	var r := sim.request_fire(HUMAN_SEAT, t)
	if r == MatchSim.FIRE_SHIELDED or r == MatchSim.FIRE_NO_TARGET:
		error_blips += 1
		if _error_player != null and _error_player.is_inside_tree():
			_error_player.play()
	channel.update(t)
	return r


## Target cycle (TORP-03, D-01); works without a reward so players can pre-aim.
func cycle_target(t: float = NAN) -> int:
	var r := sim.cycle_target(HUMAN_SEAT, t)
	if is_finite(t):
		channel.update(t)
	return r


## Ends the match (MATCH_END once) and returns the VersusResultsScreen data.
func finish(t: float) -> Dictionary:
	sim.update(t)
	sim.finish(t)
	channel.update(t)
	var rows: Array[Dictionary] = []
	for r in sim.standings():
		var row := r.duplicate()
		var p := _player(int(r["seat"]))
		row["name"] = p.callsign if p != null else "?"
		row["landed"] = p.landed if p != null else 0
		row["reflected"] = p.reflected if p != null else 0
		rows.append(row)
	var seats: Array[int] = []
	var drones: Array[int] = []
	for p in players:
		if p.is_drone:
			drones.append(p.seat)
		else:
			seats.append(p.seat)
	var last := -1
	for e in sim.event_log:
		if e.get("type", "") == GameEvent.LAST_STANDING:
			last = int(e.get("seat", -1))
	_finish_data = {"rows": rows, "local_seat": HUMAN_SEAT,
		"medals": MedalRules.medals(sim.event_log, seats, drones),
		"title": chart.title, "artist": chart.artist, "difficulty": chart.difficulty,
		"seed": match_seed, "last_standing_seat": last}
	return _finish_data


func _player(seat: int) -> PlayerState:
	for p in players:
		if p.seat == seat:
			return p
	return null


func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == HUMAN_SEAT and _hud != null and is_instance_valid(_hud):
				_hud.set_wreck(true)
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == HUMAN_SEAT and int(e.get("reward", -1)) == Reward.Id.OVERCLOCK:
				_set_overclock(true)
		GameEvent.BUFF_ENDED:
			if int(e.get("seat", -1)) == HUMAN_SEAT and int(e.get("reward", -1)) == Reward.Id.OVERCLOCK:
				_set_overclock(false)


func _set_overclock(on: bool) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.overclock = on


func _on_ghost_hit(lane: int, payload_id: int) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.on_ghost_hit(lane, payload_id)
