class_name PlayerState
extends RefCounted
## Per-seat rules state for one versus match, owned and mutated only by MatchSim (plus
## report_status values the seat's owner feeds in). Pure data: no nodes, no signals.
## Life is alive / eliminated_at only, never hull > 0 (RESEARCH Pitfall 5): the owner's hull
## reaching 0 becomes MatchSim.on_failed, which flips alive.

## D-01..D-03: AUTO = deepest living rival; LOCKED = locked_target; ATTACKERS = last_attacker.
enum TargetMode { AUTO, LOCKED, ATTACKERS }

var seat: int = 0
var callsign: String = ""
var is_human: bool = false
## Solo Dive training target (D-27): never fires through the meter, never dies, takes hits.
var is_drone: bool = false
var alive: bool = true
## Song time of elimination (INF while alive).
var eliminated_at: float = INF
var meter: RewardMeter
var bag: RewardBag

var target_mode: int = TargetMode.AUTO
var locked_target: int = -1
## Last seat that launched a disruptor at this seat (D-03), -1 for none.
var last_attacker: int = -1

## Torpedo id in flight to this seat, -1 for none (shield, D-06).
var incoming_id: int = -1
## The payload record currently active on this seat, or {} (shield, D-06).
var active: Dictionary = {}
## Shielded while t < immune_until (D-07).
var immune_until: float = -INF
## Decoy Flare armed while t < decoy_until (spec req 6).
var decoy_until: float = -INF
## Overclock active while t < overclock_until (spec req 6).
var overclock_until: float = -INF
## Seconds a gem travels from spawn to the strike line on this seat's highway (set by owner).
var approach_s: float = 1.5

## Values reported by the owner (MatchSim.report_status).
var hull: float = 100.0
var depth: float = 0.0
## 0..1, or -1 before any judgment.
var accuracy: float = -1.0
var max_streak: int = 0

## Match stats (results screen, medals).
var landed: int = 0
var reflected: int = 0
var absorbed: int = 0
var bounties: int = 0
var duels_won: int = 0
var collisions: int = 0
var debris_used: int = 0


func _init(p_seat: int = 0, p_callsign: String = "", p_is_human: bool = false,
		p_is_drone: bool = false) -> void:
	seat = p_seat
	callsign = p_callsign
	is_human = p_is_human
	is_drone = p_is_drone


## D-06: a disruptor is in flight to this seat, one is active on it, or it is immune.
func is_shielded(t: float) -> bool:
	return incoming_id != -1 or not active.is_empty() or t < immune_until
