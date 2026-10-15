class_name MedalRules
extends RefCounted
## End-of-match medals (03-SPEC req 13, 03-UI-SPEC 9.4 / 14). Pure rules over a MatchSim
## event_log: no nodes, no settings. Each seat gets up to MAX_PER_SEAT medals, picked in ORDER.
## A tie for a "most" medal (Uno Reverse, Bounty Hunter) goes to every tied seat. Drones never
## earn medals and never count as rivals. Malformed or unknown-seat events are ignored (T-03-29):
## every field is read with .get() and a default.
##
## Definitions used (from the GameEvent schema, 03-03):
##   fired at seat s  = TORPEDO_LAUNCH to s (not debris), or the half of a COLLISION aimed at s
##                      whose torpedo id has no TORPEDO_LAUNCH (a pending launch that collided)
##   took effect on s = LANDED to s (not debris) whose id has no REFLECTED event
##   targeted s       = a rival launched at s (not debris, not a reflected relaunch) or collided
##                      with a torpedo aimed at s

const ORDER: Array[String] = [
	"untouchable", "uno_reverse", "bounty_hunter", "shredder", "head_on", "grudge", "dogpiled",
]
const NAMES := {
	"untouchable": "UNTOUCHABLE",
	"uno_reverse": "UNO REVERSE",
	"bounty_hunter": "BOUNTY HUNTER",
	"shredder": "SHREDDER",
	"head_on": "HEAD-ON",
	"grudge": "GRUDGE",
	"dogpiled": "DOGPILED",
}
const GLYPHS := {
	"untouchable": "medal_untouchable",
	"uno_reverse": "medal_uno_reverse",
	"bounty_hunter": "medal_bounty_hunter",
	"shredder": "medal_shredder",
	"head_on": "medal_head_on",
	"grudge": "medal_grudge",
	"dogpiled": "medal_dogpiled",
}
## UI-SPEC 14 legend sentences (shown after "{NAME}: ").
const LEGEND := {
	"untouchable": "2 or more disruptors were fired at you and none took effect.",
	"uno_reverse": "most reflections in the match.",
	"bounty_hunter": "most bounties claimed.",
	"shredder": "won a Solo Duel.",
	"head_on": "your torpedo collided with a rival's.",
	"grudge": "landed 3 or more disruptors on the same rival.",
	"dogpiled": "every rival targeted you at least once.",
}
const MAX_PER_SEAT := 3
const UNTOUCHABLE_MIN := 2
const GRUDGE_MIN := 3
const DOGPILE_MIN_PLAYERS := 3


## "{NAME}: {rule text}" for one medal key (legend line).
static func legend_line(key: String) -> String:
	return "%s: %s" % [NAMES.get(key, key.to_upper()), LEGEND.get(key, "")]


## seat -> Array[String] of medal keys (at most MAX_PER_SEAT, in ORDER) for every seat in
## `seats` that is not in `drone_seats`; drones map to [].
static func medals(event_log: Array, seats: Array[int], drone_seats: Array[int] = []) -> Dictionary:
	var players: Array[int] = []
	for s in seats:
		if not drone_seats.has(s):
			players.append(s)
	var out := {}
	for s in seats:
		out[s] = [] as Array[String]
	if players.is_empty():
		return out

	# Pass 1: torpedo ids that were reflected, and ids that had a launch record.
	var reflected_ids := {}
	var launch_ids := {}
	for e in event_log:
		if not (e is Dictionary):
			continue
		var ty: String = str(e.get("type", ""))
		if ty == GameEvent.REFLECTED:
			reflected_ids[e.get("id", -1)] = true
		elif ty == GameEvent.TORPEDO_LAUNCH:
			launch_ids[e.get("id", -1)] = true

	var fired_at := {}  # seat -> int
	var took_effect := {}  # seat -> int
	var reflections := {}  # seat -> int
	var bounties := {}  # seat -> int
	var duel_wins := {}  # seat -> true
	var collided := {}  # seat -> true
	var grudge := {}  # seat -> {rival: int}
	var targeted_by := {}  # seat -> {rival: true}
	for s in players:
		fired_at[s] = 0
		took_effect[s] = 0
		reflections[s] = 0
		bounties[s] = 0
		grudge[s] = {}
		targeted_by[s] = {}

	for e in event_log:
		if not (e is Dictionary):
			continue
		match str(e.get("type", "")):
			GameEvent.TORPEDO_LAUNCH:
				if e.get("debris", false):
					continue
				var from: int = int(e.get("from", -1))
				var to: int = int(e.get("to", -1))
				if fired_at.has(to):
					fired_at[to] += 1
					if not e.get("reflected", false) and from != to and players.has(from):
						targeted_by[to][from] = true
			GameEvent.COLLISION:
				var a: int = int(e.get("a", -1))
				var b: int = int(e.get("b", -1))
				var ids: Array = e.get("ids", []) if e.get("ids", []) is Array else []
				var id_a: Variant = ids[0] if ids.size() > 0 else null
				var id_b: Variant = ids[1] if ids.size() > 1 else null
				if players.has(a):
					collided[a] = true
				if players.has(b):
					collided[b] = true
				# a fired at b, b fired at a; a torpedo already counted at launch is not recounted.
				if fired_at.has(b) and not launch_ids.has(id_a):
					fired_at[b] += 1
				if fired_at.has(a) and not launch_ids.has(id_b):
					fired_at[a] += 1
				if targeted_by.has(b) and players.has(a) and a != b:
					targeted_by[b][a] = true
				if targeted_by.has(a) and players.has(b) and a != b:
					targeted_by[a][b] = true
			GameEvent.LANDED:
				if e.get("debris", false) or reflected_ids.has(e.get("id", -1)):
					continue
				var from: int = int(e.get("from", -1))
				var to: int = int(e.get("to", -1))
				if took_effect.has(to):
					took_effect[to] += 1
				if not e.get("reflected", false) and grudge.has(from) and players.has(to) and to != from:
					grudge[from][to] = int(grudge[from].get(to, 0)) + 1
			GameEvent.REFLECTED:
				var by: int = int(e.get("by", -1))
				if reflections.has(by):
					reflections[by] += 1
			GameEvent.BOUNTY_CLAIMED:
				var from: int = int(e.get("from", -1))
				if bounties.has(from):
					bounties[from] += 1
			GameEvent.DUEL_RESULT:
				var w: int = int(e.get("winner", -1))
				if players.has(w):
					duel_wins[w] = true

	var top_reflect := _max_value(reflections)
	var top_bounty := _max_value(bounties)
	for s in players:
		var earned: Array[String] = []
		for key in ORDER:
			var ok := false
			match key:
				"untouchable":
					ok = fired_at[s] >= UNTOUCHABLE_MIN and took_effect[s] == 0
				"uno_reverse":
					ok = top_reflect >= 1 and reflections[s] == top_reflect
				"bounty_hunter":
					ok = top_bounty >= 1 and bounties[s] == top_bounty
				"shredder":
					ok = duel_wins.has(s)
				"head_on":
					ok = collided.has(s)
				"grudge":
					for r in grudge[s]:
						if int(grudge[s][r]) >= GRUDGE_MIN:
							ok = true
				"dogpiled":
					if players.size() >= DOGPILE_MIN_PLAYERS:
						ok = true
						for r in players:
							if r != s and not targeted_by[s].has(r):
								ok = false
			if ok:
				earned.append(key)
				if earned.size() >= MAX_PER_SEAT:
					break
		out[s] = earned
	return out


static func _max_value(d: Dictionary) -> int:
	var best := 0
	for k in d:
		best = maxi(best, int(d[k]))
	return best
