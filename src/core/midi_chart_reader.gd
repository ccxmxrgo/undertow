class_name MidiChartReader
extends RefCounted
## Clone Hero / GH .mid -> ParsedChart (CONT-01, SONG-07). Same output contract as ChartParser (D-02);
## bytes in, chart out; never reads song.ini; never asserts or prints.
##
## SmfReader supplies the raw tracks (grammar). This layer applies the Clone Hero meaning:
## track choice (D-03), pitch to fret per difficulty and open notes (D-04), tempo / time signature
## from track 0 (D-05), EVENTS sections and note 103 solos (D-06). Lane mapping stays in ChartImporter.

const MAX_BYTES := SmfReader.MAX_BYTES
## D-03 order: the first one that has at least one gem is used whole.
const TRACK_CANDIDATES: Array[String] = ["PART GUITAR", "T1 GEMS", "PART GUITAR COOP", "PART RHYTHM", "PART BASS"]
## D-04: pitch of the green gem per difficulty; red..orange follow at +1..+4.
const DIFF_BASES := {"EasySingle": 60, "MediumSingle": 72, "HardSingle": 84, "ExpertSingle": 96}
const DIFF_ORDER: Array[String] = ["EasySingle", "MediumSingle", "HardSingle", "ExpertSingle"]
## Open note pitch is green - 1 (59 / 71 / 83 / 95), only with [ENHANCED_OPENS].
const OPEN_OFFSET := -1
const SOLO_NOTE := 103
const SP_NOTE := 116
const EVENTS_TRACK := "EVENTS"
const OPEN_FRET := 7
## Open-note SysEx ranges kept per difficulty; extras are ignored (review H-01).
const MAX_OPEN_RANGES := 4096


## limits (optional, tests): {max_bytes, max_tracks, max_entries}. max_entries caps gems per difficulty here.
static func parse_bytes(bytes: PackedByteArray, limits: Dictionary = {}) -> ParsedChart:
	var max_bytes: int = limits.get("max_bytes", MAX_BYTES)
	var max_entries: int = limits.get("max_entries", ChartParser.MAX_ENTRIES)
	var pc := ParsedChart.new()
	if bytes.size() > max_bytes:
		pc.error = SongEntry.ERR_TOO_LARGE
		return pc

	# max_entries is NOT forwarded: SmfReader would cap raw note on/off events with it.
	var smf_limits := {}
	for k in ["max_bytes", "max_tracks", "max_events"]:
		if limits.has(k):
			smf_limits[k] = limits[k]
	var keep := PackedStringArray()
	for n in TRACK_CANDIDATES:
		keep.append(n)
	keep.append(EVENTS_TRACK)
	var smf := SmfReader.read(bytes, smf_limits, keep)
	if not smf["ok"]:
		pc.error = str(smf["error"])
		return pc

	var warnings: int = int(smf["warnings"])
	var res := clampi(int(smf["division"]), 1, ChartParser.MAX_RESOLUTION)
	pc.resolution = res
	var tracks: Array = smf["tracks"]
	var seq := 0

	# Tempo and time signatures: track 0 only (D-05).
	if not tracks.is_empty():
		var t0: Dictionary = tracks[0]
		for t in t0["tempos"]:
			var us: int = t["uspqn"]
			if us <= 0:
				warnings += 1
				continue
			pc.tempo.append({"tick": t["tick"], "milli_bpm": 60000000000.0 / float(us), "seq": seq})
			seq += 1
		for s in t0["time_sigs"]:
			pc.time_sigs.append({"tick": s["tick"], "num": s["num"], "exp": s["exp"], "seq": seq})
			seq += 1

	# Sections from the first EVENTS track (D-06).
	for tr in tracks:
		if int(tr["index"]) > 0 and not tr["skipped"] and str(tr["name"]).to_upper() == EVENTS_TRACK:
			for tx in tr["texts"]:
				var sec := _section_text(str(tx["text"]))
				if sec != "":
					pc.events.append({"tick": tx["tick"], "text": sec, "seq": seq})
					seq += 1
			break

	# Track choice (D-03): first candidate with a gem, taken whole.
	var chosen: Dictionary = {}
	var gems: Dictionary = {}
	var closed: Array = []
	var has_sp := false
	var ctx := {"warnings": 0}
	for cand in TRACK_CANDIDATES:
		for tr in tracks:
			if int(tr["index"]) < 1 or tr["skipped"] or str(tr["name"]).to_upper() != cand:
				continue
			ctx["warnings"] = 0
			var c := _pair(tr["notes"], ctx)
			var g := _gems(tr, c, res)
			var has_gem := false
			for k in g.keys():
				if not (g[k] as Array).is_empty():
					has_gem = true
			if has_gem:
				chosen = tr
				gems = g
				closed = c
				break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		pc.error = SongEntry.ERR_MIDI_NO_GUITAR
		return pc
	warnings += int(ctx["warnings"])

	for n in chosen["notes"]:
		if n["on"] and n["pitch"] == SP_NOTE:
			has_sp = true
			break

	for dname in DIFF_ORDER:
		var list: Array = gems[dname]
		if list.is_empty():
			continue
		if list.size() > max_entries:
			list.resize(max_entries)
			warnings += 1
		var out: Array = []
		for gm in list:
			out.append({"tick": gm["tick"], "type": "N", "a": gm["a"], "b": gm["b"], "text": "", "seq": seq})
			seq += 1
		pc.tracks[dname] = out

	# Solos (SONG-07): 103 is a solo only when the track also uses 116 for Star Power (GH1/GH2 differ).
	if has_sp:
		var solo_notes: Array = []
		for c in closed:
			if c["pitch"] == SOLO_NOTE:
				solo_notes.append(c)
		solo_notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["tick"] == b["tick"]:
				return a["seq"] < b["seq"]
			return a["tick"] < b["tick"])
		for dname in pc.tracks.keys():
			var arr: Array = pc.tracks[dname]
			for sn in solo_notes:
				var st: int = sn["tick"]
				var en: int = maxi(st, st + int(sn["len"]) - 1)
				arr.append({"tick": st, "type": "E", "a": 0, "b": 0, "text": "solo", "seq": seq})
				seq += 1
				arr.append({"tick": en, "type": "E", "a": 0, "b": 0, "text": "soloend", "seq": seq})
				seq += 1

	pc.warnings = warnings
	pc.tempo.sort_custom(_by_tick)
	pc.time_sigs.sort_custom(_by_tick)
	pc.events.sort_custom(_by_tick)
	for k in pc.tracks.keys():
		var t: Array = pc.tracks[k]
		t.sort_custom(_by_tick)
	pc.ok = true
	return pc


static func _by_tick(a: Dictionary, b: Dictionary) -> bool:
	if a["tick"] == b["tick"]:
		return a["seq"] < b["seq"]
	return a["tick"] < b["tick"]


## "[section Verse 1]" / "[prc_chorus_2]" / "section_bridge" -> "section <name>"; anything else -> "".
static func _section_text(raw: String) -> String:
	var s := raw.strip_edges()
	if s.begins_with("["):
		s = s.substr(1)
	if s.ends_with("]"):
		s = s.substr(0, s.length() - 1)
	s = s.strip_edges()
	var low := s.to_lower()
	var name := ""
	for prefix in ["section", "prc"]:
		if low.begins_with(prefix) and low.length() > prefix.length():
			var sep := low[prefix.length()]
			if sep == " " or sep == "_":
				name = s.substr(prefix.length() + 1)
				break
	name = name.strip_edges()
	if name == "":
		return ""
	if not name.contains(" "):
		name = name.replace("_", " ")
	return "section " + name.strip_edges()


## Pairs note-on / note-off per pitch (channel and velocity ignored) into closed notes
## [{pitch, tick, len, seq}]. Within one tick: offs closing earlier notes, then ons, then
## leftover offs (zero-length notes). Orphan offs are counted in ctx.warnings.
static func _pair(notes: Array, ctx: Dictionary) -> Array:
	var out: Array = []
	var open := {}
	var i := 0
	var n := notes.size()
	while i < n:
		var tick: int = notes[i]["tick"]
		var j := i
		while j < n and int(notes[j]["tick"]) == tick:
			j += 1
		var done := {}
		for k in range(i, j):
			var e: Dictionary = notes[k]
			var p: int = e["pitch"]
			if not e["on"] and open.has(p) and int(open[p]["tick"]) < tick:
				_close(out, open, p, tick)
				done[k] = true
		for k in range(i, j):
			var e: Dictionary = notes[k]
			if e["on"]:
				var p: int = e["pitch"]
				if open.has(p):
					_close(out, open, p, tick)
				open[p] = {"tick": tick, "seq": e["seq"]}
		for k in range(i, j):
			var e: Dictionary = notes[k]
			if not e["on"] and not done.has(k):
				var p: int = e["pitch"]
				if open.has(p):
					_close(out, open, p, tick)
				else:
					ctx["warnings"] = int(ctx["warnings"]) + 1
		i = j
	for p in open.keys():
		var o: Dictionary = open[p]
		out.append({"pitch": p, "tick": o["tick"], "len": 0, "seq": o["seq"]})
	return out


static func _close(out: Array, open: Dictionary, pitch: int, tick: int) -> void:
	var o: Dictionary = open[pitch]
	out.append({"pitch": pitch, "tick": o["tick"], "len": tick - int(o["tick"]), "seq": o["seq"]})
	open.erase(pitch)


static func _is_enhanced_opens(tr: Dictionary) -> bool:
	for tx in tr["texts"]:
		var s := str(tx["text"]).strip_edges()
		if s.begins_with("["):
			s = s.substr(1)
		if s.ends_with("]"):
			s = s.substr(0, s.length() - 1)
		if s.strip_edges().to_upper() == "ENHANCED_OPENS":
			return true
	return false


## difficulty track name -> Array of {tick, a, b} sorted by (tick, seq).
static func _gems(tr: Dictionary, closed: Array, res: int) -> Dictionary:
	var enhanced := _is_enhanced_opens(tr)
	var cutoff := res / 3
	var sorted := closed.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tick"] == b["tick"]:
			return a["seq"] < b["seq"]
		return a["tick"] < b["tick"])
	var out := {}
	for dname in DIFF_ORDER:
		out[dname] = []
	for c in sorted:
		var pitch: int = c["pitch"]
		var length: int = c["len"]
		var b := 0 if length < cutoff else length
		for dname in DIFF_ORDER:
			var base: int = DIFF_BASES[dname]
			var d := pitch - base
			if d >= 0 and d <= 4:
				(out[dname] as Array).append({"tick": c["tick"], "a": d, "b": b})
				break
			if enhanced and pitch == base + OPEN_OFFSET:
				(out[dname] as Array).append({"tick": c["tick"], "a": OPEN_FRET, "b": b})
				break
	var ranges := _open_ranges(tr["sysex"])
	for di in DIFF_ORDER.size():
		var list: Array = out[DIFF_ORDER[di]]
		var rs: Array = ranges[di]
		if rs.is_empty():
			continue
		# Gems are sorted by tick; ranges are ordered and disjoint: one linear sweep (review H-01).
		var ri := 0
		for gm in list:
			var gt: int = gm["tick"]
			while ri < rs.size() and gt >= int(rs[ri][1]):
				ri += 1
			if ri >= rs.size():
				break
			if gt >= int(rs[ri][0]):
				gm["a"] = OPEN_FRET
	return out


## Phase Shift open-note SysEx -> per difficulty (Easy..Expert) Array of [start, end) tick ranges.
## Payload: 50 53 00 00 diff 01 value F7; diff 0..3 or 0xFF (all); value 1 start, 0 end.
static func _open_ranges(sysex: Array) -> Array:
	var ranges := [[], [], [], []]
	var starts := [-1, -1, -1, -1]
	for s in sysex:
		var d: PackedByteArray = s["data"]
		if d.size() != 8 or d[0] != 0x50 or d[1] != 0x53 or d[2] != 0 or d[3] != 0 or d[5] != 1 or d[7] != 0xF7:
			continue
		var diff: int = d[4]
		var val: int = d[6]
		if val > 1:
			continue
		var targets: Array = []
		if diff == 0xFF:
			targets = [0, 1, 2, 3]
		elif diff <= 3:
			targets = [diff]
		else:
			continue
		for t in targets:
			if val == 1:
				if starts[t] < 0:
					starts[t] = s["tick"]
			elif starts[t] >= 0:
				if (ranges[t] as Array).size() < MAX_OPEN_RANGES:
					(ranges[t] as Array).append([starts[t], s["tick"]])
				starts[t] = -1
	for t in 4:
		if starts[t] >= 0:
			(ranges[t] as Array).append([starts[t], SmfReader.MAX_TICK + 1])
	return ranges
