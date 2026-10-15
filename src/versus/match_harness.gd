class_name MatchHarness
extends RefCounted
## Headless whole-match runner (tests, the reward-frequency report, 03-14 reuse). Builds the
## seats (an optional autoplay or bot human, bots, an optional training drone), one SubRig per
## playing seat, and the MatchSim referee on a LoopbackChannel, then plays the song in sim time.
##
## Determinism (Pitfall 6): nothing is driven by frame time. Every actor (bots, the autoplay
## human, the drone, and a fixed TICK_S judge-tick grid) exposes next_time()/step(), and
## advance_to(t) runs every due action in global song-time order (ties: tick grid, human, bots
## by seat, drone). The fps option only decides how the song is chunked, so the event log is the
## same at any fps. Never reads Settings or Time; versus seats never use Settings.no_fail.
##
## opts: human "autoplay" | "none" | "bot" (default "autoplay"); human_skill (bot human);
## bots: Array of skill names or BotProfiles; seed (int); fps (10..2000, default 60);
## cfg: VersusConfig; jcfg: JudgeConfig; training: -1 off, -2 all, else a disruptor id
## (adds a TrainingDrone seat named "DRONE"; the human is a no-fail autoplay and there are no bots).

const TICK_S := 0.005
const MAX_SONG_S := 1800.0
const MIN_FPS := 10.0
const MAX_FPS := 2000.0
const START_T := -1.0

var chart: ChartData
var cfg: VersusConfig
var jcfg: JudgeConfig
var channel: LoopbackChannel
var sim: MatchSim
var players: Array[PlayerState] = []
## seat -> SubRig (playing seats only; the drone has none).
var rigs := {}
var bots: Array[BotPlayer] = []
var drone: RefCounted  # TrainingDrone (Task 3)
var human_seat: int = -1
var drone_seat: int = -1
var seed: int = 0
var fps: float = 60.0
var end_t: float = 0.0
var now: float = START_T

var _actors: Array = []
var _autoplay: _AutoActor
var _finished := false


## Judge tick grid: every rig ticks at k x TICK_S (expiry misses and sustain ticks at
## frame-rate independent times), then the referee and the channel catch up.
class _TickActor:
	var h: MatchHarness
	var k: int

	func _init(p_h: MatchHarness) -> void:
		h = p_h
		k = int(ceil(START_T / TICK_S))

	func next_time() -> float:
		return float(k) * TICK_S

	func step() -> void:
		var t := next_time()
		k += 1
		for s in h._rig_seats():
			h.rigs[s].tick(t)
		h.sim.update(t)
		h.channel.update(t)


## The autoplay human: VersusAutoplay stepped at each of its own event times.
class _AutoActor:
	var rig: SubRig
	var ap: VersusAutoplay
	var times: Array[float] = []
	var idx: int = 0

	func _init(p_chart: ChartData, p_rig: SubRig) -> void:
		rig = p_rig
		ap = VersusAutoplay.new(p_chart, rig.judge)
		for n in p_chart.notes:
			times.append(float(n["time"]))
			if float(n["duration"]) > 0.0:
				times.append(float(n["time"]) + float(n["duration"]))
		times.sort()
		rig.overlay_added.connect(_on_overlay)

	func _on_overlay(_id: int, notes: Array) -> void:
		ap.refresh(rig.judge)
		var tail: Array[float] = times.slice(idx)
		for n in notes:
			if int(n["kind"]) == VersusJudge.DEPTH:
				tail.append(float(n["time"]))
		tail.sort()
		times = times.slice(0, idx)
		times.append_array(tail)

	func next_time() -> float:
		return times[idx] if idx < times.size() else INF

	func step() -> void:
		var t := times[idx]
		idx += 1
		rig.begin(t)
		ap.update(t)


func _init(p_chart: ChartData, opts: Dictionary = {}) -> void:
	chart = p_chart
	cfg = opts.get("cfg", null)
	if cfg == null:
		cfg = VersusConfig.new()
	jcfg = opts.get("jcfg", null)
	if jcfg == null:
		jcfg = JudgeConfig.new()
	seed = int(opts.get("seed", 0))
	fps = clampf(float(opts.get("fps", 60.0)), MIN_FPS, MAX_FPS)
	var training := int(opts.get("training", -1))
	var human: String = opts.get("human", "autoplay")
	var bot_list: Array = opts.get("bots", [])
	if training != -1:
		human = "autoplay"
		bot_list = []
	if human != "autoplay" and human != "bot" and human != "none":
		human = "autoplay"
	var n_bots := clampi(bot_list.size(), 0, 3 if human != "none" else 4)
	var names := MatchSetup.callsigns(seed, n_bots)
	var seat := 0
	if human != "none":
		human_seat = seat
		players.append(PlayerState.new(seat, "YOU", true))
		seat += 1
	for i in range(n_bots):
		players.append(PlayerState.new(seat, names[i] if i < names.size() else "BOT%d" % seat))
		seat += 1
	if training != -1:
		drone_seat = seat
		players.append(PlayerState.new(seat, "DRONE", false, true))
	channel = LoopbackChannel.new()
	sim = MatchSim.new(chart, cfg, jcfg, players, channel, seed)
	_actors.append(_TickActor.new(self))
	if human_seat != -1:
		var rig := SubRig.new(human_seat, chart, jcfg, cfg, sim, channel, training != -1)
		rigs[human_seat] = rig
		if human == "autoplay":
			_autoplay = _AutoActor.new(chart, rig)
			_actors.append(_autoplay)
		else:
			var hb := BotPlayer.new(rig, _profile(opts.get("human_skill", "veteran")), sim, cfg,
				chart, _bot_seed(human_seat))
			bots.append(hb)
			_actors.append(hb)
	for i in range(n_bots):
		var s := i + (1 if human_seat != -1 else 0)
		var rig := SubRig.new(s, chart, jcfg, cfg, sim, channel, false)
		rigs[s] = rig
		var b := BotPlayer.new(rig, _profile(bot_list[i]), sim, cfg, chart, _bot_seed(s))
		bots.append(b)
		_actors.append(b)
	if training != -1:
		pass  # TrainingDrone added in Task 3
	var last := 0.0
	for n in chart.notes:
		last = maxf(last, float(n["time"]) + float(n["duration"]))
	end_t = minf(last + 2.0, MAX_SONG_S)


static func _profile(v) -> BotProfile:
	if v is BotProfile:
		return v
	return BotProfile.from_skill(str(v))


func _bot_seed(s: int) -> int:
	return hash([seed, "bot", s])


func _rig_seats() -> Array:
	var out := rigs.keys()
	out.sort()
	return out


## Runs every due action up to song time t in global time order (never past end_t).
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
	now = maxf(now, t)


## Plays to the end of the song and emits MATCH_END (once).
func finish() -> void:
	if _finished:
		return
	advance_to(end_t)
	_finished = true
	sim.finish(end_t)


func result() -> Dictionary:
	var log: Array[Dictionary] = sim.event_log
	var rewards := {}
	for p in players:
		if not p.is_drone:
			rewards[p.seat] = 0
	var fired := 0
	var landed := 0
	var reflected := 0
	var standings: Array = []
	for e in log:
		match e["type"]:
			GameEvent.REWARD_EARNED:
				if e.get("source", "") == "meter":
					rewards[e["seat"]] = int(rewards.get(e["seat"], 0)) + 1
			GameEvent.TORPEDO_LAUNCH:
				if not e.get("reflected", false):
					fired += 1
			GameEvent.LANDED:
				landed += 1
			GameEvent.REFLECTED:
				reflected += 1
			GameEvent.MATCH_END:
				standings = e["standings"]
	var stats := {}
	for s in rigs:
		var r: SubRig = rigs[s]
		stats[s] = {"perfect": r.perfect, "good": r.good, "miss": r.miss,
			"depth_perfect": r.depth_perfect, "depth_other": r.depth_other,
			"ghost_hits": r.ghost_hits, "hull": r.hull.hull, "depth": r.hull.depth(),
			"strays": r.hull.stray_count}
	return {"event_log": log, "standings": standings, "meter_rewards": rewards, "fired": fired,
		"landed": landed, "reflected": reflected, "duration_s": end_t, "threshold": sim.threshold,
		"note_count": chart.notes.size(), "stats": stats}


## Whole match in sim time: steps from START_T to the end in 1/fps chunks, then MATCH_END.
static func run(p_chart: ChartData, opts: Dictionary = {}) -> Dictionary:
	var h := MatchHarness.new(p_chart, opts)
	var dt := 1.0 / h.fps
	var k := 0
	var t := START_T
	while t < h.end_t:
		k += 1
		t = minf(START_T + float(k) * dt, h.end_t)
		h.advance_to(t)
	h.finish()
	return h.result()
