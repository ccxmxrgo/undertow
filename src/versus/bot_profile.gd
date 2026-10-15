class_name BotProfile
extends Resource
## Bot timing skill (D-19). A bot presses each note at note time + N(bias_s, sigma_s) or lapses
## (no press) with probability `lapse`. While a payload is active on the bot's own highway the
## penalties below apply (effective_for). Veteran is the "strong" bot of 03-SPEC req 8.

@export var name: String = "veteran"
## Timing error standard deviation (seconds).
@export var sigma_s: float = 0.033
## Chance of not pressing a note at all.
@export var lapse: float = 0.015
## Mean timing error (seconds, positive = late).
@export var bias_s: float = 0.0
## D-19 payload penalties.
@export var crossed_lapse_add: float = 0.06
@export var ink_sigma_mult: float = 1.3
@export var pressure_sigma_mult: float = 1.2
@export var jam_lapse_add: float = 0.04
## Chance of pressing each Ghost Note (D-19: 0.15 / 0.30 / 0.45).
@export var ghost_press_p: float = 0.15


static func make(p_name: String, sigma: float, p_lapse: float, ghost_p: float) -> BotProfile:
	var p := BotProfile.new()
	p.name = p_name
	p.sigma_s = sigma
	p.lapse = p_lapse
	p.ghost_press_p = ghost_p
	return p


## Strong bot (RESEARCH "Bot skill model": 33 ms / 1.5%).
static func veteran() -> BotProfile:
	return make("veteran", 0.033, 0.015, 0.15)


static func regular() -> BotProfile:
	return make("regular", 0.042, 0.035, 0.30)


static func rookie() -> BotProfile:
	return make("rookie", 0.055, 0.07, 0.45)


## MatchSetup.SKILLS name -> profile; unknown names give regular().
static func from_skill(skill: String) -> BotProfile:
	match skill:
		"veteran":
			return veteran()
		"rookie":
			return rookie()
	return regular()


## A copy with the D-19 penalty for `reward` active on the bot's highway applied (debris: Silt
## counts as ink, Groan as a scroll-speed change).
func effective_for(reward: int) -> BotProfile:
	var p: BotProfile = duplicate()
	match reward:
		Reward.Id.CROSSED_WIRES:
			p.lapse = minf(1.0, lapse + crossed_lapse_add)
		Reward.Id.INK_CLOUD, Reward.Id.SILT:
			p.sigma_s = sigma_s * ink_sigma_mult
		Reward.Id.PRESSURE_CRACK, Reward.Id.GROAN:
			p.sigma_s = sigma_s * pressure_sigma_mult
		Reward.Id.SONAR_JAM:
			p.lapse = minf(1.0, lapse + jam_lapse_add)
	return p
