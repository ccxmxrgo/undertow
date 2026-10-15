class_name Reward
extends RefCounted
## Reward ids, kinds and display data (03-SPEC reqs 3-7, UI-SPEC 4.1). Pure data, no colours.
## Spec req 7: Crossed Wires replaces Lane Flip (PAY-02 superseded); the bag holds 9 rewards:
## 6 disruptors and 3 buffs. SILT and GROAN are wreck debris (D-25) and never in the bag.
## Descriptions read bar counts and percentages from VersusConfig, never hard-coded numbers.

enum Id {
	CROSSED_WIRES,
	GHOST_NOTES,
	INK_CLOUD,
	PRESSURE_CRACK,
	SONAR_JAM,
	DEPTH_CHARGE,
	DECOY_FLARE,
	BALLAST_PATCH,
	OVERCLOCK,
	SILT,
	GROAN,
}

enum Kind { DISRUPTOR, BUFF, DEBRIS }

## The bag contents (spec req 3, req 7).
const ALL: Array[int] = [
	Id.CROSSED_WIRES,
	Id.GHOST_NOTES,
	Id.INK_CLOUD,
	Id.PRESSURE_CRACK,
	Id.SONAR_JAM,
	Id.DEPTH_CHARGE,
	Id.DECOY_FLARE,
	Id.BALLAST_PATCH,
	Id.OVERCLOCK,
]

## UI-SPEC 4.1. glyph = UiIcons name. desc tokens: {bars} (VersusConfig.bars_for), {pct}.
const TABLE := {
	Id.CROSSED_WIRES: {
		"key": "crossed_wires", "hud_name": "CROSSED WIRES", "feed_name": "Crossed Wires",
		"glyph": "crossed_wires", "kind": Kind.DISRUPTOR,
		"desc": "Two lanes trade places for {bars} bars.",
	},
	Id.GHOST_NOTES: {
		"key": "ghost_notes", "hud_name": "GHOST NOTES", "feed_name": "Ghost Notes",
		"glyph": "ghost_notes", "kind": Kind.DISRUPTOR,
		"desc": "Hollow fake notes for {bars} bars. Hitting one costs hull.",
	},
	Id.INK_CLOUD: {
		"key": "ink_cloud", "hud_name": "INK CLOUD", "feed_name": "Ink Cloud",
		"glyph": "ink_cloud", "kind": Kind.DISRUPTOR,
		"desc": "Ink hides the bottom of the highway for {bars} bars.",
	},
	Id.PRESSURE_CRACK: {
		"key": "pressure_crack", "hud_name": "PRESSURE CRACK", "feed_name": "Pressure Crack",
		"glyph": "pressure_crack", "kind": Kind.DISRUPTOR,
		"desc": "Notes scroll {mult}x faster for {bars} bars.",
	},
	Id.SONAR_JAM: {
		"key": "sonar_jam", "hud_name": "SONAR JAM", "feed_name": "Sonar Jam",
		"glyph": "sonar_jam", "kind": Kind.DISRUPTOR,
		"desc": "Notes lose colour and shape for {bars} bars.",
	},
	Id.DEPTH_CHARGE: {
		"key": "depth_charge", "hud_name": "DEPTH CHARGE", "feed_name": "Depth Charge",
		"glyph": "depth_charge", "kind": Kind.DISRUPTOR,
		"desc": "Extra notes on the beat for {bars} bars.",
	},
	Id.DECOY_FLARE: {
		"key": "decoy_flare", "hud_name": "DECOY FLARE", "feed_name": "Decoy Flare",
		"glyph": "decoy_flare", "kind": Kind.BUFF,
		"desc": "Absorbs the next torpedo aimed at you.",
	},
	Id.BALLAST_PATCH: {
		"key": "ballast_patch", "hud_name": "BALLAST PATCH", "feed_name": "Ballast Patch",
		"glyph": "ballast_patch", "kind": Kind.BUFF,
		"desc": "Repairs {pct}% of your hull.",
	},
	Id.OVERCLOCK: {
		"key": "overclock", "hud_name": "OVERCLOCK", "feed_name": "Overclock",
		"glyph": "overclock", "kind": Kind.BUFF,
		"desc": "Goods count as Perfect for {bars} bars.",
	},
	Id.SILT: {
		"key": "silt", "hud_name": "SILT", "feed_name": "Silt",
		"glyph": "debris", "kind": Kind.DEBRIS,
		"desc": "",
	},
	Id.GROAN: {
		"key": "groan", "hud_name": "GROAN", "feed_name": "Groan",
		"glyph": "debris", "kind": Kind.DEBRIS,
		"desc": "",
	},
}


static func _row(id: int) -> Dictionary:
	return TABLE.get(id, {})


static func is_valid(id: int) -> bool:
	return TABLE.has(id)


## -1 for an unknown id.
static func kind_of(id: int) -> int:
	return _row(id).get("kind", -1)


static func is_disruptor(id: int) -> bool:
	return kind_of(id) == Kind.DISRUPTOR


static func is_buff(id: int) -> bool:
	return kind_of(id) == Kind.BUFF


static func is_debris(id: int) -> bool:
	return kind_of(id) == Kind.DEBRIS


static func key_of(id: int) -> String:
	return _row(id).get("key", "")


## -1 for an unknown key (e.g. "lane_flip").
static func from_key(key: String) -> int:
	for id in TABLE:
		if TABLE[id]["key"] == key:
			return id
	return -1


static func hud_name(id: int) -> String:
	return _row(id).get("hud_name", "")


static func feed_name(id: int) -> String:
	return _row(id).get("feed_name", "")


static func glyph(id: int) -> String:
	return _row(id).get("glyph", "")


## One-line description (UI-SPEC 4.1) with {bars}, {pct} and {mult} filled from cfg.
static func description(id: int, cfg: VersusConfig) -> String:
	var text: String = _row(id).get("desc", "")
	return text.format({
		"bars": str(cfg.bars_for(id)),
		"pct": str(roundi(cfg.ballast_restore_ratio * 100.0)),
		"mult": _num(cfg.pressure_crack_mult),
	})


static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(roundi(x))
	return String.num(x, 2).trim_suffix("0")
