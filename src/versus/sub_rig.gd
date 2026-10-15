class_name SubRig
extends RefCounted
## One seat's playing kit (D-28): VersusJudge + VersusHull + PayloadStack wired to the MatchSim
## referee. The human and every bot use this same rig, so they follow the same rules code
## (MATCH-01). Inputs (press/release/tick) carry song time; judgments reach the referee stamped
## with note time + error (never frame time). Payload and buff outcomes arrive as GameEvents
## through the EventChannel and are applied here (MatchSim never changes a hull).
## Pure RefCounted: no nodes, no Time, no Settings (versus never uses Settings.no_fail).

## A base-chart judgment was forwarded to the referee (t = note time + error).
signal judgment_reported(note_index: int, judgment: int, t: float)
## Overlay notes ({time, lane, kind, payload_id}) were added to the judge for payload `payload_id`.
signal overlay_added(payload_id: int, notes: Array)

var seat: int
var chart: ChartData
var jcfg: JudgeConfig
var cfg: VersusConfig
var sim: MatchSim
var channel: EventChannel
var judge: VersusJudge
var hull: VersusHull
var stack: PayloadStack
## Song time of the input being processed (stamps referee calls).
var now: float = 0.0

## Base-chart judgment counts (accuracy, tests).
var perfect: int = 0
var good: int = 0
var miss: int = 0
## Depth Charge overlay judgments.
var depth_perfect: int = 0
var depth_other: int = 0
var ghost_hits: int = 0

## Seconds a gem travels on this seat's highway; decides the Ghost/Depth window (Pitfall 1).
var approach_s: float = 1.5:
	set(v):
		approach_s = v
		if _player != null:
			_player.approach_s = v

var _player: PlayerState


func _init(p_seat: int, p_chart: ChartData, p_jcfg: JudgeConfig, p_cfg: VersusConfig,
		p_sim: MatchSim, p_channel: EventChannel, no_fail: bool) -> void:
	seat = p_seat
	chart = p_chart
	jcfg = p_jcfg
	cfg = p_cfg
	sim = p_sim
	channel = p_channel
	for p in sim.players:
		if p.seat == seat:
			_player = p
	if _player != null:
		approach_s = _player.approach_s
	judge = VersusJudge.new(chart, jcfg)
	hull = VersusHull.new(jcfg)
	hull.no_fail = no_fail
	stack = PayloadStack.new(chart, cfg)
	# Dispatch order equals connection order: the rig's handlers set hull.now and reach the
	# referee BEFORE VersusHull scores the judgment (Overclock needs the right time).
	judge.judged.connect(_on_judged)
	judge.extra_judged.connect(_on_extra_judged)
	judge.stray.connect(_on_stray)
	judge.ghost_hit.connect(_on_ghost_hit)
	hull.connect_versus(judge, cfg)
	# Method callables, not lambdas (CR-02): a lambda captures self strongly, so hull -> signal ->
	# lambda -> rig formed a reference cycle that leaked the whole match after every game.
	hull.hull_changed.connect(_on_hull_changed)
	hull.score_changed.connect(_on_score_changed)
	hull.failed.connect(_on_failed)
	channel.received.connect(_on_event)


## Sets the input time for anything that presses the judge directly (VersusAutoplay).
func begin(t: float) -> void:
	now = t
	hull.now = t


func press(lane: int, t: float) -> void:
	begin(t)
	judge.press(lane, t)


func release(lane: int, t: float) -> void:
	begin(t)
	judge.release(lane, t)


func tick(t: float) -> void:
	begin(t)
	judge.tick(t)
	stack.prune(t)


## 0..1 like PlayerState.accuracy (RunStats.accuracy is a percentage), -1 before any judgment.
func accuracy() -> float:
	var a := RunStats.accuracy(perfect, good, miss)
	return a / 100.0 if a >= 0.0 else -1.0


# --- judge -> referee --------------------------------------------------------------------------

func _on_judged(_lane: int, idx: int, j: int, err: float) -> void:
	# A late miss comes from InputJudge._expire with err = tick time - note time, i.e. frame /
	# tick time. Stamp it at the deterministic deadline instead (WR-01): the meter reset, warhead
	# kill, debris and elimination times must not depend on when the judge happened to tick.
	var e := err
	if j == InputJudge.Judgment.MISS and err > 0.0:
		e = minf(err, jcfg.good_window + InputJudge.EPS)
	var t: float = float(chart.notes[idx]["time"]) + e
	begin(t)
	match j:
		InputJudge.Judgment.PERFECT:
			perfect += 1
		InputJudge.Judgment.GOOD:
			good += 1
		_:
			miss += 1
	sim.on_judged(seat, idx, j, t)
	judgment_reported.emit(idx, j, t)


func _on_extra_judged(_kind: int, _lane: int, j: int, err: float) -> void:
	# err = now - note time. A late Depth Charge miss is stamped at its deadline, like base
	# notes (WR-01); a press is stamped at the press time (now).
	var t := now
	if j == InputJudge.Judgment.MISS and err > jcfg.good_window + InputJudge.EPS:
		t = now - err + jcfg.good_window + InputJudge.EPS
	hull.now = t
	if j == InputJudge.Judgment.PERFECT:
		depth_perfect += 1
	else:
		depth_other += 1
	sim.on_extra_judged(seat, j, t)


func _on_stray(_lane: int) -> void:
	sim.on_stray(seat, now)


func _on_ghost_hit(_lane: int, _payload_id: int) -> void:
	ghost_hits += 1  # hull damage via connect_versus; never the meter (D-12)


func _on_hull_changed(_v: float, _d: float) -> void:
	_report()


func _on_score_changed(_v: int) -> void:
	_report()


func _report() -> void:
	sim.report_status(seat, hull.hull, hull.depth(), accuracy(), hull.max_combo, now)


func _on_failed() -> void:
	sim.on_failed(seat, now)


# --- referee events -> this seat -----------------------------------------------------------------

func _on_event(e: Dictionary) -> void:
	match e.get("type", ""):
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("to", -1)) == seat:
				var heads: Array = e.get("warheads", [])
				if not heads.is_empty():
					stack.mark_warheads(int(e["id"]), heads)
		GameEvent.LANDED:
			if int(e.get("to", -1)) == seat:
				_on_landed(e)
		GameEvent.WARHEAD:
			if int(e.get("seat", -1)) == seat:
				if e.get("ok", false):
					stack.confirm(int(e["note"]))
				else:
					stack.kill(int(e["id"]))
		GameEvent.PAYLOAD_END:
			if int(e.get("seat", -1)) == seat and e.get("reason", "") == "reflected":
				var t := float(e["t"])
				stack.end_early(int(e["id"]), t)
				judge.clear_payload(int(e["id"]), t)
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) == seat:
				match int(e.get("reward", -1)):
					Reward.Id.OVERCLOCK:
						hull.overclock_until = float(e["until_t"])
					Reward.Id.BALLAST_PATCH:
						begin(maxf(now, float(e["t"])))
						hull.heal(float(e.get("amount", 0.0)))
		GameEvent.BUFF_ENDED:
			if int(e.get("seat", -1)) == seat and int(e.get("reward", -1)) == Reward.Id.OVERCLOCK:
				hull.overclock_until = minf(hull.overclock_until, float(e["t"]))


func _on_landed(e: Dictionary) -> void:
	stack.install(e)
	var reward := int(e.get("reward", -1))
	if reward != Reward.Id.GHOST_NOTES and reward != Reward.Id.DEPTH_CHARGE:
		return
	var id := int(e["id"])
	var start := float(e["active_start"])
	var end := float(e["end_t"])
	var notes: Array[Dictionary]
	if reward == Reward.Id.GHOST_NOTES:
		notes = PayloadNotes.ghosts(chart, start, end, cfg, jcfg, int(e["seed"]), id)
	else:
		notes = PayloadNotes.depth_charges(chart, start, end, cfg, jcfg, int(e["seed"]), id)
	if notes.is_empty():
		return
	judge.add_overlay(notes)
	overlay_added.emit(id, notes)
