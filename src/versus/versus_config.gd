class_name VersusConfig
extends Resource
## Every Phase 3 (offline versus) tunable. Each value cites its source (03-SPEC requirement or
## CONTEXT/RESEARCH decision D-nn). Durations are in bars unless noted. Rules never hard-code
## these numbers; call validated() before using a config that came from outside the code.

## Reward threshold = ceil(ratio x base chart note count) (03-SPEC req 1, D-30).
@export var reward_threshold_ratio: float = 0.12
## Torpedo flight time in beats (03-SPEC req 9).
@export var torpedo_travel_beats: int = 1
## Bounty refund = ratio x threshold, credited to the shooter's meter (03-SPEC req 10, D-31).
@export var bounty_refund_ratio: float = 0.25
## Solo Duel needs at least this many notes in the solo section (03-SPEC req 11).
@export var solo_duel_min_notes: int = 16
## Solo Duel needs at least this hit accuracy to win the prize (03-SPEC req 11).
@export var solo_duel_min_accuracy: float = 0.85

## After a disruptor resolves on a sub, it is immune for this many bars (D-07).
@export var immunity_bars: int = 1
## Hull damage for hitting a Ghost Note (D-08).
@export var ghost_hull_damage: float = 4.0
## Maximum total Ghost Note damage per Ghost Notes payload (D-08).
@export var ghost_damage_cap: float = 12.0
## Ghost notes spawned per beat while active (D-11).
@export var ghost_per_beat: float = 1.0
## Whether hitting a Ghost Note empties the reward meter (CONTEXT open question; off by default).
@export var ghost_resets_meter: bool = false
## Warhead notes for Return to Sender (D-16). 0 disables warheads (tests and tuning).
@export var warhead_count: int = 4
## Pressure Crack scroll multiplier (D-09).
@export var pressure_crack_mult: float = 1.5
## Pressure Crack never pushes the scroll speed above this (D-09).
@export var pressure_crack_max_speed: float = 3.5
## Wreck debris Groan scroll multiplier (D-25).
@export var groan_mult: float = 1.25
## Ink Cloud covers the highway from this depth (strike-line relative, D-13).
@export var ink_depth_bottom: float = -0.15
## Ink Cloud top edge (D-13).
@export var ink_depth_top: float = 0.35
## Wreck debris Silt top edge (D-25).
@export var silt_depth_top: float = 0.20
## Depth Charge extra notes = density x base notes in its window (D-14).
@export var depth_charge_density: float = 0.5
## Depth Charge minimum extra notes (D-14).
@export var depth_charge_min_notes: int = 2
## Minimum spacing (seconds) between overlay notes and base notes in a lane (RESEARCH Pitfall 2).
@export var overlay_spacing_s: float = 0.25

## Decoy Flare stays armed this many bars (03-SPEC req 6).
@export var decoy_bars: int = 8
## Overclock lasts this many bars (03-SPEC req 6).
@export var overclock_bars: int = 4
## Ballast Patch restores this share of the full hull (03-SPEC req 6).
@export var ballast_restore_ratio: float = 0.25

## Disruptor durations (03-SPEC req 5).
@export var bars_crossed_wires: int = 4
@export var bars_ghost_notes: int = 4
@export var bars_ink_cloud: int = 4
@export var bars_pressure_crack: int = 4
@export var bars_sonar_jam: int = 3
@export var bars_depth_charge: int = 2

## Wreck debris duration and how many debris shots one wreck may fire (D-25).
@export var debris_bars: int = 1
@export var debris_max_per_wreck: int = 2

## Solo Dive training drone fires every this many bars (D-27).
@export var training_interval_bars: int = 8

## Killfeed shows at most this many lines, each living this many seconds (03-SPEC req 12).
@export var killfeed_max_lines: int = 4
@export var killfeed_life_s: float = 4.0

## Bot fire behaviour (D-20).
@export var bot_fire_delay_min_beats: int = 1
@export var bot_fire_delay_max_beats: int = 8
## Chance a bot aims at the attacker instead of the leader (D-20).
@export var bot_attackers_p: float = 0.3
## Bots use Ballast Patch at or below this hull (D-20).
@export var bot_ballast_hull: float = 75.0
## Bots use Ballast Patch anyway after holding it this many bars (D-20).
@export var bot_ballast_wait_bars: int = 16


## Duration in bars of a reward or debris. Buffs return their armed/active bars; Ballast 0.
func bars_for(reward_id: int) -> int:
	match reward_id:
		Reward.Id.CROSSED_WIRES:
			return bars_crossed_wires
		Reward.Id.GHOST_NOTES:
			return bars_ghost_notes
		Reward.Id.INK_CLOUD:
			return bars_ink_cloud
		Reward.Id.PRESSURE_CRACK:
			return bars_pressure_crack
		Reward.Id.SONAR_JAM:
			return bars_sonar_jam
		Reward.Id.DEPTH_CHARGE:
			return bars_depth_charge
		Reward.Id.DECOY_FLARE:
			return decoy_bars
		Reward.Id.OVERCLOCK:
			return overclock_bars
		Reward.Id.SILT, Reward.Id.GROAN:
			return debris_bars
	return 0


## A copy with every value clamped to a safe range (RESEARCH Security V5, T-03-03): ratios 0..1,
## bar counts >= 1, warhead_count 0..8, travel beats >= 1, non-finite floats back to defaults.
func validated() -> VersusConfig:
	var d := VersusConfig.new()
	var v: VersusConfig = duplicate()
	v.reward_threshold_ratio = _ratio(reward_threshold_ratio, d.reward_threshold_ratio)
	v.bounty_refund_ratio = _ratio(bounty_refund_ratio, d.bounty_refund_ratio)
	v.solo_duel_min_accuracy = _ratio(solo_duel_min_accuracy, d.solo_duel_min_accuracy)
	v.ballast_restore_ratio = _ratio(ballast_restore_ratio, d.ballast_restore_ratio)
	v.depth_charge_density = _ratio(depth_charge_density, d.depth_charge_density)
	v.bot_attackers_p = _ratio(bot_attackers_p, d.bot_attackers_p)
	v.torpedo_travel_beats = maxi(1, torpedo_travel_beats)
	v.warhead_count = clampi(warhead_count, 0, 8)
	v.solo_duel_min_notes = maxi(1, solo_duel_min_notes)
	v.immunity_bars = maxi(1, immunity_bars)
	v.decoy_bars = maxi(1, decoy_bars)
	v.overclock_bars = maxi(1, overclock_bars)
	v.bars_crossed_wires = maxi(1, bars_crossed_wires)
	v.bars_ghost_notes = maxi(1, bars_ghost_notes)
	v.bars_ink_cloud = maxi(1, bars_ink_cloud)
	v.bars_pressure_crack = maxi(1, bars_pressure_crack)
	v.bars_sonar_jam = maxi(1, bars_sonar_jam)
	v.bars_depth_charge = maxi(1, bars_depth_charge)
	v.debris_bars = maxi(1, debris_bars)
	v.debris_max_per_wreck = maxi(0, debris_max_per_wreck)
	v.training_interval_bars = maxi(1, training_interval_bars)
	v.killfeed_max_lines = maxi(1, killfeed_max_lines)
	v.bot_ballast_wait_bars = maxi(1, bot_ballast_wait_bars)
	v.depth_charge_min_notes = maxi(0, depth_charge_min_notes)
	v.bot_fire_delay_min_beats = maxi(0, bot_fire_delay_min_beats)
	v.bot_fire_delay_max_beats = maxi(v.bot_fire_delay_min_beats, bot_fire_delay_max_beats)
	v.ghost_per_beat = _pos(ghost_per_beat, d.ghost_per_beat)
	v.ghost_hull_damage = _pos(ghost_hull_damage, d.ghost_hull_damage)
	v.ghost_damage_cap = _pos(ghost_damage_cap, d.ghost_damage_cap)
	v.pressure_crack_mult = maxf(1.0, _pos(pressure_crack_mult, d.pressure_crack_mult))
	v.pressure_crack_max_speed = maxf(0.1, _pos(pressure_crack_max_speed, d.pressure_crack_max_speed))
	v.groan_mult = maxf(1.0, _pos(groan_mult, d.groan_mult))
	v.overlay_spacing_s = _pos(overlay_spacing_s, d.overlay_spacing_s)
	v.killfeed_life_s = maxf(0.1, _pos(killfeed_life_s, d.killfeed_life_s))
	v.bot_ballast_hull = clampf(_pos(bot_ballast_hull, d.bot_ballast_hull), 0.0, 100.0)
	return v


static func _ratio(x: float, def: float) -> float:
	return clampf(x, 0.0, 1.0) if is_finite(x) else def


static func _pos(x: float, def: float) -> float:
	return maxf(0.0, x) if is_finite(x) else def
