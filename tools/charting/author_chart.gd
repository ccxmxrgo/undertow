extends SceneTree
## Deterministic .chart generator for the bundled songs (dev tool, excluded from export).
##
##   godot --headless --path . --script res://tools/charting/author_chart.gd -- <song id|all> [--stats]
##
## Input: the hand-written per-bar plan in section_plans.gd. The audio is never analysed.
## Output: songs/<id>/notes.chart (Resolution 192, 120 BPM, 4/4). Same input -> same bytes
## (fixed seeds, no clock, no filesystem ordering).
##
## Expert is authored from the plan, then Hard/Medium/Easy are derived from Expert by
## thinning (keep on-beat gems, drop off-beat gems, collapse chords) and applying the
## difficulty's lane constraints, so all four feel like the same song.

const RES := 192
const BAR := 768
const STEP := 48  # a 16th note in ticks
const BPM_MILLI := 120000
const DIFFS := ["easy", "medium", "hard", "expert"]
const TRACKS := {"easy": "EasySingle", "medium": "MediumSingle", "hard": "HardSingle", "expert": "ExpertSingle"}
const TITLES := {
	"synth_wave_april": "Synth Wave April 3, 2022",
	"space_synth_wave": "Space Synth Wave",
}
const ARTIST := "Pro Sensory (Alex McCulloch)"
const FAMILIES := {
	"stairs": [0, 1, 2, 3, 2, 1],
	"zig": [0, 2, 1, 3, 1, 2],
	"trill": [1, 2],
	"pulse": [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1],
	"pad": [1, 2, 0, 2],
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var stats := args.has("--stats")
	var ids: Array[String] = []
	for a in args:
		if a == "--stats":
			continue
		if a == "all":
			ids = SectionPlans.ids()
		elif SectionPlans.SONGS.has(a):
			ids.append(a)
	if ids.is_empty():
		printerr("usage: -- <song id|all> [--stats]; ids: ", SectionPlans.ids())
		quit(2)
		return
	for id in ids:
		var text := generate(id)
		if stats:
			print(stats_text(id))
		else:
			var f := FileAccess.open("res://songs/%s/notes.chart" % id, FileAccess.WRITE)
			if f == null:
				printerr("cannot write chart for ", id)
				quit(1)
				return
			f.store_string(text)
			f.close()
			print("wrote songs/%s/notes.chart (%d bytes)" % [id, text.length()])
	quit(0)


# ---------------------------------------------------------------- generation

## The chart text for a song id (static so tests can regenerate and compare).
static func generate(id: String) -> String:
	var tracks := build_tracks(id)
	var plan: Dictionary = SectionPlans.SONGS[id]
	var out := PackedStringArray()
	out.append("[Song]\n{")
	out.append("  Name = \"%s\"" % TITLES[id])
	out.append("  Artist = \"%s\"" % ARTIST)
	out.append("  Charter = \"UNDERTOW\"")
	out.append("  Resolution = %d" % RES)
	out.append("  Genre = \"synthwave\"")
	out.append("}")
	out.append("[SyncTrack]\n{\n  0 = TS 4\n  0 = B %d\n}" % BPM_MILLI)
	out.append("[Events]\n{")
	for s in plan["sections"]:
		out.append("  %d = E \"section %s\"" % [int(s["from"]) * BAR, s["label"]])
	out.append("}")
	for d in DIFFS:
		out.append("[%s]\n{" % TRACKS[d])
		out.append_array(_track_lines(tracks[d], plan))
		out.append("}")
	return "\n".join(out) + "\n"


## {difficulty: Array of gems {tick, lane, len}} sorted by tick then lane.
static func build_tracks(id: String) -> Dictionary:
	var plan: Dictionary = SectionPlans.SONGS[id]
	var expert := _expert(plan)
	var out := {"expert": _clean(expert, 4)}
	out["hard"] = _clean(_derive(expert, plan, "hard"), 3)
	out["medium"] = _clean(_derive(expert, plan, "medium"), 2)
	out["easy"] = _clean(_derive(expert, plan, "easy"), 1)
	return out


static func _track_lines(gems: Array, plan: Dictionary) -> PackedStringArray:
	var rows: Array = []  # [tick, order, text]
	var solo: Dictionary = plan["solo"]
	rows.append([int(solo["from"]) * BAR, 0, "E solo"])
	rows.append([int(solo["to"]) * BAR - STEP, 2, "E soloend"])
	for g in gems:
		rows.append([g["tick"], 1, "N %d %d" % [g["lane"], g["len"]], g["lane"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		if a.size() > 3 and b.size() > 3:
			return a[3] < b[3]
		return false)
	var lines := PackedStringArray()
	for r in rows:
		lines.append("  %d = %s" % [r[0], r[2]])
	return lines


static func _section_at(plan: Dictionary, bar: int) -> Dictionary:
	for s in plan["sections"]:
		if bar >= int(s["from"]) and bar < int(s["to"]):
			return s
	return {"intensity": 0, "family": "pad"}


## Expert: authored straight from the plan on a 16th grid.
static func _expert(plan: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan["seed"]) + 4
	var gems: Array = []
	var counter := 0
	var solo: Dictionary = plan["solo"]
	for bar in int(plan["bars"]):
		if bar < 2:
			continue  # no notes before bar 2 (count-in)
		var sec := _section_at(plan, bar)
		var inten: int = sec["intensity"]
		var in_solo: bool = bar >= int(solo["from"]) and bar < int(solo["to"])
		if in_solo:
			inten = 4
		var seq: Array = FAMILIES[sec["family"]]
		var accent := bar % 4 == 3
		var steps: Array[int] = []
		match inten:
			1:
				match bar % 4:
					0: steps = [0]
					1: steps = []
					2: steps = [0, 8]
					3: steps = [0, 4, 8, 12]
			2:
				for s in [0, 4, 8, 12]:
					steps.append(s)
				for s in [2, 6, 10, 14]:
					if rng.randf() < 0.6:
						steps.append(s)
				if accent:
					steps.append(15)
			3:
				for s in range(0, 16, 2):
					steps.append(s)
				if rng.randf() < 0.5:
					steps.append(15)
				if accent:
					steps.append_array([13, 15])
			4:
				for s in range(0, 16, 2):
					steps.append(s)
				for s in [3, 7, 11, 15]:
					if rng.randf() < 0.45:
						steps.append(s)
				if accent:
					steps.append_array([13, 15])
		steps.sort()
		var uniq: Array[int] = []
		for s in steps:
			if not uniq.has(s):
				uniq.append(s)
		steps = uniq
		# a held pad note on phrase starts
		var sustain_steps := 0
		if bar % 8 == 0:
			sustain_steps = 8 if inten <= 1 else 12
		for s in steps:
			var tick := bar * BAR + s * STEP
			var lane: int = seq[counter % seq.size()]
			if rng.randf() < 0.15:
				lane = 3 - lane
			counter += 1
			var chord: Array[int] = [lane]
			if s == 0 and accent and inten >= 3:
				var base := mini(lane, 1)
				chord = [base, base + 1, base + 2]
			if s == 0 and bar % 8 == 7 and inten >= 4:
				chord = [0, 1, 2, 3]
			var len_ticks := 0
			if s == 0 and sustain_steps > 0:
				len_ticks = sustain_steps * STEP - STEP
			for l in chord:
				gems.append({"tick": tick, "lane": l, "len": len_ticks if chord.size() == 1 else 0})
	return gems


## Thinning rules per difficulty (see header comment).
static func _derive(expert: Array, plan: Dictionary, diff: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan["seed"]) + 100 * DIFFS.find(diff)
	var by_tick := {}
	var ticks: Array = []
	for g in expert:
		if not by_tick.has(g["tick"]):
			by_tick[g["tick"]] = []
			ticks.append(g["tick"])
		by_tick[g["tick"]].append(g)
	var out: Array = []
	var prev_lane := -1
	for t in ticks:
		var bar: int = t / BAR
		var step: int = (t % BAR) / STEP
		var inten: int = _section_at(plan, bar)["intensity"]
		var solo: Dictionary = plan["solo"]
		if bar >= int(solo["from"]) and bar < int(solo["to"]):
			inten = 4
		var accent := bar % 4 == 3
		var keep := false
		match diff:
			"hard":
				if step % 2 == 0:
					keep = step % 4 == 0 or rng.randf() < (0.6 if inten >= 3 else 0.4)
				else:
					keep = accent and step >= 13
			"medium":
				if step % 4 == 0:
					keep = true
				elif step % 2 == 0:
					keep = inten >= 3 and rng.randf() < 0.18
			"easy":
				keep = step % 8 == 0 or (step % 4 == 0 and inten >= 4 and rng.randf() < 0.25)
		if not keep:
			continue
		var gems: Array = by_tick[t]
		var picked: Array = gems.duplicate()
		if diff == "hard" and picked.size() > 3:
			picked = picked.slice(0, 3)
		elif diff == "medium":
			picked = picked.slice(0, 2) if (step == 0 and accent and inten >= 3) else picked.slice(0, 1)
		elif diff == "easy":
			picked = picked.slice(0, 1)
		if diff == "medium" or diff == "easy":
			var max_step := 2 if diff == "medium" else 1
			var lane: int = picked[0]["lane"]
			if prev_lane >= 0:
				lane = prev_lane + clampi(lane - prev_lane, -max_step, max_step)
			picked = [{"tick": t, "lane": lane, "len": picked[0]["len"]}] if picked.size() == 1 else [
				{"tick": t, "lane": lane, "len": 0}, {"tick": t, "lane": mini(lane + 1, 3) if lane < 3 else 2, "len": 0}]
			prev_lane = lane
		else:
			prev_lane = picked[0]["lane"]
		for g in picked:
			out.append({"tick": g["tick"], "lane": g["lane"], "len": g["len"]})
	return out


## Enforces: sorted, unique (tick, lane), no gem inside a same-lane sustain (and none within a
## 16th after it), chords limited to max_chord lanes and collapsed while any sustain is held.
static func _clean(gems: Array, max_chord: int) -> Array:
	var sorted := gems.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tick"] != b["tick"]:
			return a["tick"] < b["tick"]
		return a["lane"] < b["lane"])
	var out: Array = []
	var sustain_end := [-1000000, -1000000, -1000000, -1000000]  # per lane: tick when free again
	var holding_until := -1
	var i := 0
	while i < sorted.size():
		var t: int = sorted[i]["tick"]
		var group: Array = []
		while i < sorted.size() and sorted[i]["tick"] == t:
			group.append(sorted[i])
			i += 1
		var kept: Array = []
		var seen := {}
		for g in group:
			if seen.has(g["lane"]) or t < sustain_end[g["lane"]]:
				continue
			seen[g["lane"]] = true
			kept.append(g)
		if kept.size() > max_chord:
			kept = kept.slice(0, max_chord)
		if t < holding_until and kept.size() > 1:
			kept = kept.slice(0, 1)
		for g in kept:
			var len_ticks: int = g["len"] if kept.size() == 1 else 0
			out.append({"tick": t, "lane": g["lane"], "len": len_ticks})
			if len_ticks > 0:
				sustain_end[g["lane"]] = t + len_ticks + STEP
				holding_until = maxi(holding_until, t + len_ticks)
	return out


# ---------------------------------------------------------------- stats

static func stats_text(id: String) -> String:
	var tracks := build_tracks(id)
	var lines := PackedStringArray()
	lines.append(id)
	for d in DIFFS:
		var gems: Array = tracks[d]
		var first: int = gems[0]["tick"]
		var last: int = gems[gems.size() - 1]["tick"]
		var secs := float(last - first) / float(RES) * 0.5
		lines.append("  %-6s notes=%d  per_sec=%.2f" % [d, gems.size(), gems.size() / secs])
	return "\n".join(lines)
