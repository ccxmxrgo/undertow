class_name MatchSetup
extends RefCounted
## Launch record for an offline versus match or a Solo Dive training run (D-18, D-21, D-27,
## MATCH-01). `pending` is a one-shot hand-off: the main menu (03-05) and the match setup screen
## (03-13) write it, Gameplay (03-14) reads and clears it. Seeds come only from new_seed() /
## rematch(); never the global randi/randomize.

const MODE_VERSUS := 0
const MODE_TRAINING := 1
const SKILLS: Array[String] = ["rookie", "regular", "veteran"]
## D-21 bot callsigns, shuffled per match seed.
const CALLSIGNS: Array[String] = ["MAKO", "ORCA", "BARRACUDA", "LAMPREY", "NARWHAL", "MORAY"]
## UI-SPEC 8.2 cycle order: off, all, then the 6 disruptor Reward keys.
const TRAINING_VALUES: Array[String] = [
	"off", "all", "crossed_wires", "ghost_notes", "ink_cloud", "pressure_crack", "sonar_jam",
	"depth_charge",
]
const MIN_RIVALS := 1
const MAX_RIVALS := 3

static var pending: MatchSetup = null
static var _seed_counter: int = 0

var mode: int = MODE_VERSUS
var song_id: String = ""
var difficulty: String = ""
var rivals: int = 3
var skill: String = "regular"
var seed: int = 0
var training: String = "off"


## A copy with rivals 1..3, a known skill and a known training value (T-03-02).
func clamped() -> MatchSetup:
	var c := _copy()
	c.mode = mode if mode == MODE_TRAINING else MODE_VERSUS
	c.rivals = clampi(rivals, MIN_RIVALS, MAX_RIVALS)
	c.skill = skill if SKILLS.has(skill) else "regular"
	c.training = training if TRAINING_VALUES.has(training) else "off"
	return c


## Last used versus/training choices (Settings validates them on load).
static func from_settings() -> MatchSetup:
	var m := MatchSetup.new()
	m.song_id = Settings.versus_song_id
	m.difficulty = Settings.versus_difficulty
	m.rivals = Settings.versus_rivals
	m.skill = Settings.versus_skill
	m.training = Settings.training_payload
	return m.clamped()


## Writes the choices to Settings and saves the settings file.
func save_to_settings() -> void:
	var c := clamped()
	Settings.versus_song_id = c.song_id.left(Settings.MAX_PATH_LEN)
	Settings.versus_difficulty = c.difficulty if Settings.DIFFICULTIES.has(c.difficulty) else ""
	Settings.versus_rivals = c.rivals
	Settings.versus_skill = c.skill
	Settings.training_payload = c.training
	Settings.save_to(Settings.save_path)


## Same match with a fresh seed.
func rematch() -> MatchSetup:
	var c := _copy()
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec() ^ seed
	c.seed = rng.randi()
	if c.seed == seed:
		c.seed = seed + 1
	return c


## A fresh match seed (not security material; shown in results for repro, T-03-04).
static func new_seed() -> int:
	var rng := RandomNumberGenerator.new()
	_seed_counter += 1
	rng.seed = hash([Time.get_ticks_usec(), _seed_counter])
	return rng.randi()


## The first n callsigns of a seeded shuffle of CALLSIGNS (D-21).
static func callsigns(seed_value: int, n: int) -> PackedStringArray:
	var names: Array[String] = CALLSIGNS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["callsigns", seed_value])
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := names[i]
		names[i] = names[j]
		names[j] = tmp
	var out := PackedStringArray()
	for i in range(clampi(n, 0, names.size())):
		out.append(names[i])
	return out


## -1 = off (or unknown), -2 = all disruptors in turn, else the Reward id.
static func training_reward(value: String) -> int:
	if value == "all":
		return -2
	if value == "off" or not TRAINING_VALUES.has(value):
		return -1
	return Reward.from_key(value)


func _copy() -> MatchSetup:
	var c := MatchSetup.new()
	c.mode = mode
	c.song_id = song_id
	c.difficulty = difficulty
	c.rivals = rivals
	c.skill = skill
	c.seed = seed
	c.training = training
	return c
