class_name Referee
extends RefCounted
## The seam between the seat rigs and the rules (D-03). SubRig and VersusController only talk
## to a Referee, so the object behind it can change without them knowing:
## - MatchSim: the real rules, used offline and by the online host.
## - HostInputQueue (04-05): orders remote inputs by song time on the host before they reach
##   MatchSim (horizon ordering).
## - RemoteReferee (04-05): the client proxy. It forwards inputs to the host and answers
##   queries from the host's events. Clients run no rules.
##
## Every method mirrors MatchSim's signature exactly; the bodies here are safe no-ops. Inputs
## carry song time (never frame time). The FIRE_OK..FIRE_PENDING results (0..4) live on
## MatchSim; this base only adds FIRE_REMOTE.

## request_fire on a proxy: the result is unknown until FIRE_QUEUED / FIRE_REFUSED arrives.
const FIRE_REMOTE := 5

## Seat states the rules read and write. SubRig looks up its own seat here (it tolerates none).
var players: Array[PlayerState] = []


## A base-chart judgment on `seat` (raw judgment, before any Overclock upgrade).
func on_judged(_seat: int, _note_index: int, _judgment: int, _t: float) -> void:
	pass


## A Depth Charge overlay note judgment.
func on_extra_judged(_seat: int, _judgment: int, _t: float) -> void:
	pass


## A press with no note.
func on_stray(_seat: int, _t: float) -> void:
	pass


## A Ghost Note was hit.
func on_ghost_hit(_seat: int, _t: float) -> void:
	pass


## The owner's current hull/score values.
func report_status(_seat: int, _hull: float, _depth: float, _accuracy: float, _max_streak: int,
		_t: float = NAN) -> void:
	pass


## Fire the held reward. The base cannot know the outcome: FIRE_REMOTE.
func request_fire(_seat: int, _t: float) -> int:
	return FIRE_REMOTE


## Queue a launch without touching any meter (training drone, host).
func inject_fire(_seat: int, _to: int, _reward: int, _t: float) -> int:
	return FIRE_REMOTE


## Cycle the target mode; returns the resolved target, -1 when unknown.
func cycle_target(_seat: int, _t: float = NAN) -> int:
	return -1


## Set the target mode directly (bots); LOCKED needs `locked`.
func set_target_mode(_seat: int, _mode: int, _locked: int = -1, _t: float = NAN) -> void:
	pass


## The sub's hull reached 0.
func on_failed(_seat: int, _t: float) -> void:
	pass


## Live Perfect % (0..100) of `seat` in the running Solo Duel; -1.0 when unknown.
func duel_live(_seat: int) -> float:
	return -1.0


## chart.solos index of the running Solo Duel, or -1.
func duel_active() -> int:
	return -1


## Process everything due up to song time t.
func update(_t: float) -> void:
	pass


## The seconds a gem travels on `seat`'s highway (D-09): decides that seat's payload windows.
## SubRig reports it whenever its approach_s changes, so a remote host learns each scroll speed.
func set_approach(_seat: int, _approach_s: float) -> void:
	pass
