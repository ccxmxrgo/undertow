class_name GameEvent
extends RefCounted
## The versus event vocabulary (RESEARCH Pattern 2, 03-SPEC req 12, D-28). Every rules outcome
## MatchSim decides is one of these records, sent through an EventChannel. Views (HUD, killfeed,
## periscopes, SFX) and the Phase 4 network host read only these. Each record is a Dictionary
## with "type" (one of the constants below) and "t" (song time in seconds, never frame time:
## spec constraint "host-decidable"), plus the fields documented per type.
## Seats are ints (0 = first player). Rewards are Reward.Id ints. Never rename or remove a type:
## wave-3 view plans and Phase 4 code against these names and fields.

## {seat, reward, source: "meter"|"bounty"|"duel"|"debris"} - a reward entered the slot.
const REWARD_EARNED := "reward_earned"
## {seat, reward} - a duel prize waits in the one-item queue.
const REWARD_QUEUED := "reward_queued"
## {seat, progress, threshold, held, queued, debris: bool} - meter state changed.
const METER := "meter"
## {seat, reward, to, launch_beat} - a fire press was accepted; launch waits for launch_beat.
const FIRE_QUEUED := "fire_queued"
## {seat, reason: "shielded"|"no_target"|"race"|"nothing"} - a fire was refused; reward kept.
const FIRE_REFUSED := "fire_refused"
## {id, from, to, reward, launch_beat, launch_t, arrive_t, warheads: Array[int], reflected: bool,
## debris: bool} - a torpedo left the tube. Warheads are base-chart note indices (D-05, D-16).
const TORPEDO_LAUNCH := "torpedo_launch"
## {a, b, ids: [id_a, id_b], reward_a, reward_b} - two opposite disruptors cancelled (spec req 9).
const COLLISION := "collision"
## {id, from, to, reward} - a Decoy Flare on `to` absorbed the torpedo (spec req 6).
const ABSORBED := "absorbed"
## {id, from, to, reward, arrive_t, active_start, end_t, seed, reflected, debris} - a payload
## took effect on `to`; its board effect runs over [active_start, end_t).
const LANDED := "landed"
## {id, seat, reward, reason: "expired"|"reflected", immune_until} - a payload ended on `seat`.
const PAYLOAD_END := "payload_end"
## {id, seat, note, k, n, ok} - a warhead note of torpedo `id` was judged on `seat` (D-16).
const WARHEAD := "warhead"
## {id, by, to, reward} - `by` cleared every warhead; the payload returns to `to` (D-16).
const REFLECTED := "reflected"
## {id, from, to, reward} - a reflected torpedo found no valid target and fizzled.
const FIZZLED := "fizzled"
## {seat, reward, until_t, amount} - a buff took effect (Ballast: amount = hull restored).
const BUFF_APPLIED := "buff_applied"
## {seat, reward, reason: "expired"|"used"|"lost"} - a timed buff ended.
const BUFF_ENDED := "buff_ended"
## {seat, mode: PlayerState.TargetMode, target: seat or -1} - targeting changed (D-01..D-03).
const TARGET := "target"
## {from_seat, to_seat} - the bounty moved to the new alive leader (-1 = nobody).
const BOUNTY_MOVED := "bounty_moved"
## {from, to, refund} - shooter `from` claimed the bounty on `to` (spec req 10).
const BOUNTY_CLAIMED := "bounty_claimed"
## {seat, hull, depth, alive, place, accuracy} - periodic per-seat status (bounded per beat).
const STATUS := "status"
## {solo, start, end, note_count} - a Solo Duel starts in one bar (spec req 11).
const DUEL_ANNOUNCE := "duel_announce"
## {solo} - the Solo Duel section began.
const DUEL_START := "duel_start"
## {solo, winner, pct, best_pct, tied} - the Solo Duel result (winner -1 = nobody).
const DUEL_RESULT := "duel_result"
## {seat} - the sub imploded (hull reached 0); it keeps playing as a wreck (D-24).
const IMPLODED := "imploded"
## {seat} - only this sub is left alive (D-22); emitted once, at a beat boundary.
const LAST_STANDING := "last_standing"
## {standings: Array[Dictionary]} - the song ended; rows as MatchSim.standings().
const MATCH_END := "match_end"
## {seat, reason: "disconnected"|"left"} - an online player's link dropped; emitted by the host
## right after that seat's IMPLODED (D-16). Host-only, never offline.
const PLAYER_LEFT := "player_left"
## {solo: int, pct: Dictionary seat->float} - live Solo Duel Perfect % per participant, at most
## once per beat while a duel runs; host-only, read by clients' RemoteReferee.duel_live (D-13).
const DUEL_LIVE := "duel_live"

const ALL_TYPES: Array[String] = [
	REWARD_EARNED, REWARD_QUEUED, METER, FIRE_QUEUED, FIRE_REFUSED, TORPEDO_LAUNCH, COLLISION,
	ABSORBED, LANDED, PAYLOAD_END, WARHEAD, REFLECTED, FIZZLED, BUFF_APPLIED, BUFF_ENDED, TARGET,
	BOUNTY_MOVED, BOUNTY_CLAIMED, STATUS, DUEL_ANNOUNCE, DUEL_START, DUEL_RESULT, IMPLODED,
	LAST_STANDING, MATCH_END, PLAYER_LEFT, DUEL_LIVE,
]


## {"type": type, "t": t} plus fields (fields never override type or t).
static func make(type: String, t: float, fields: Dictionary = {}) -> Dictionary:
	var e := {"type": type, "t": t}
	for k in fields:
		if k != "type" and k != "t":
			e[k] = fields[k]
	return e
