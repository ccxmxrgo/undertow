class_name ChartImporter
extends RefCounted
## ParsedChart (5-fret, ticks) -> ChartData (4 lanes, seconds) + solos + fingerprint.
##
## LANE MAPPING RULE (MAPPING_VERSION 1, SONG-02, D-01/D-02/D-04):
##   Green  -> lane 1 (index 0)      Red    -> lane 2 (index 1)
##   Yellow -> lane 3 (index 2)      Blue   -> lane 4 (index 3)
##   Orange -> lane 4 (index 3), merged with Blue: one note, the LONGEST sustain is kept.
##   Open   -> a chord on lanes 2 and 3 (indexes 1 and 2).
##   Forced / tap markers create no notes (HOPO and tap are ignored, plain notes).
##   Two gems landing on the same lane at one tick collapse to one note (longest sustain).
##   A sustain of at most a 16th note (len_ticks * SUSTAIN_TAP_DIVISOR <= resolution) is a tap.
## Changing any of this requires bumping MAPPING_VERSION (it is part of the fingerprint).
## `[Song] Offset` is ignored; only the song.ini delay (argument) shifts times.
## Solos are only stored (D-17); nothing is shown in gameplay.

const MAPPING_VERSION := 1
const IMPORTER_VERSION := 1
## Sustains with len_ticks * DIVISOR <= resolution (a 16th at DIVISOR 4) become taps.
## The judge ticks sustains every JudgeConfig.sustain_tick_interval (0.1 s), a 16th at
## 120 BPM is 0.125 s, so anything shorter could not even score one tick.
const SUSTAIN_TAP_DIVISOR := 4
const DIFFICULTIES: Array[String] = ["easy", "medium", "hard", "expert"]
const DEFAULT_BPM := 120.0
const MIN_BPM := 1.0
const MAX_BPM := 2000.0
## Untrusted [Events] / TS limits (T-02.2-05..07).
const MAX_SECTIONS := 256
const MAX_TIME_SIGS := 256
const MAX_SECTION_NAME := 64
const MAX_TS_NUM := 32
const MAX_TS_EXP := 5

const _TRACK_NAMES := {
	"easy": "EasySingle",
	"medium": "MediumSingle",
	"hard": "HardSingle",
	"expert": "ExpertSingle",
}
const _LETTERS := {"easy": "e", "medium": "m", "hard": "h", "expert": "x"}


## Difficulties that have at least one lane note after mapping.
static func difficulties(parsed: ParsedChart) -> Array[String]:
	var out: Array[String] = []
	if parsed == null or not parsed.ok:
		return out
	for d in DIFFICULTIES:
		if not _collect(parsed, d).is_empty():
			out.append(d)
	return out


static func build(parsed: ParsedChart, difficulty: String, delay_ms: int = 0) -> ChartData:
	var chart := ChartData.new()
	chart.difficulty = difficulty
	chart.title = SongIni.sanitize_text(str(parsed.song.get("name", "")))
	chart.artist = SongIni.sanitize_text(str(parsed.song.get("artist", "")))
	var warnings := parsed.warnings
	var delay := float(delay_ms) / 1000.0
	var res := maxi(parsed.resolution, 1)
	var segs := _segments(parsed)

	# tempo map in seconds, delay applied, times clamped to >= 0
	var tm: Array[Dictionary] = []
	for s in segs:
		tm.append({"time": s["sec"] + delay, "bpm": s["bpm"]})
	while tm.size() > 1 and tm[1]["time"] <= 0.0:
		tm.remove_at(0)
	if not tm.is_empty() and tm[0]["time"] < 0.0:
		tm[0]["time"] = 0.0
	chart.tempo_map = tm

	var gems := _collect(parsed, difficulty)
	for g in gems:
		var tick: int = g["tick"]
		var t := _tick_to_sec(segs, res, tick) + delay
		var dur := 0.0
		var len_ticks: int = g["len"]
		if len_ticks * SUSTAIN_TAP_DIVISOR > res:
			dur = _tick_to_sec(segs, res, tick + len_ticks) - _tick_to_sec(segs, res, tick)
		if not is_finite(t) or not is_finite(dur) or t < 0.0 or dur < 0.0:
			warnings += 1
			continue
		var lane: int = g["lane"]
		if lane < 0 or lane > 3:
			warnings += 1
			continue
		chart.add_note(lane, t, dur)
	chart.finalize()

	chart.solos = _solos(parsed, difficulty, chart, segs, res, delay)
	chart.sections = _sections(parsed, segs, res, delay)
	chart.time_sigs = _time_sigs(parsed, segs, res, delay)
	chart.meta = {
		"mapping_version": MAPPING_VERSION,
		"importer_version": IMPORTER_VERSION,
		"delay_ms": delay_ms,
		"warnings": warnings,
	}
	if parsed.song.has("offset"):
		chart.meta["ignored_offset"] = str(parsed.song["offset"])
	return chart


## "u<importer>.<24 hex>.<e|m|h|x>". Integers only so every peer gets the same digest.
## versions (tests only): {"importer": int, "mapping": int} overrides the constants.
static func fingerprint(chart: ChartData, difficulty: String, duration_sec: float, versions: Dictionary = {}) -> String:
	var imp: int = versions.get("importer", IMPORTER_VERSION)
	var map: int = versions.get("mapping", MAPPING_VERSION)
	var sb := PackedStringArray()
	sb.append("u:%d:m:%d" % [imp, map])
	sb.append("d:%s" % difficulty)
	sb.append("len:%d" % int(round(duration_sec * 10.0)))
	for t in chart.tempo_map:
		sb.append("b:%d:%d" % [int(round(t["time"] * 1000.0)), int(round(t["bpm"] * 1000.0))])
	var rows: Array = []
	for n in chart.notes:
		rows.append([int(round(n["time"] * 1000.0)), int(n["lane"]), int(round(n["duration"] * 1000.0))])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	for r in rows:
		sb.append("n:%d:%d:%d" % [r[0], r[1], r[2]])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(sb).to_utf8_buffer())
	var hex := ctx.finish().hex_encode().substr(0, 24)
	return "u%d.%s.%s" % [imp, hex, _LETTERS.get(difficulty, "x")]


# ---- internals ----

## Mapped gems for a difficulty: Array of {tick, lane, len} sorted by tick then lane.
static func _collect(parsed: ParsedChart, difficulty: String) -> Array:
	var out: Array = []
	var track_name: String = _TRACK_NAMES.get(difficulty, "")
	if track_name == "" or not parsed.tracks.has(track_name):
		return out
	var track: Array = parsed.tracks[track_name]
	var cur_tick := -1
	var lanes := {}
	for e in track:
		if e["type"] != "N":
			continue
		var tick: int = e["tick"]
		if tick != cur_tick:
			_flush(out, cur_tick, lanes)
			lanes = {}
			cur_tick = tick
		var len_ticks: int = e["b"]
		match int(e["a"]):
			0, 1, 2, 3:
				_put(lanes, int(e["a"]), len_ticks)
			4:
				_put(lanes, 3, len_ticks)
			7:
				_put(lanes, 1, len_ticks)
				_put(lanes, 2, len_ticks)
			_:
				pass  # 5 forced, 6 tap: modifiers, no gem
	_flush(out, cur_tick, lanes)
	return out


static func _put(lanes: Dictionary, lane: int, len_ticks: int) -> void:
	lanes[lane] = maxi(lanes.get(lane, 0), len_ticks)


static func _flush(out: Array, tick: int, lanes: Dictionary) -> void:
	if tick < 0 or lanes.is_empty():
		return
	var keys := lanes.keys()
	keys.sort()
	for lane in keys:
		out.append({"tick": tick, "lane": lane, "len": lanes[lane]})


## Tempo segments [{tick, bpm, sec}], cumulative seconds computed once (double).
static func _segments(parsed: ParsedChart) -> Array:
	var raw: Array = []  # {tick, bpm}, last B at the same tick wins
	for t in parsed.tempo:
		var bpm := clampf(float(t["milli_bpm"]) / 1000.0, MIN_BPM, MAX_BPM)
		if not raw.is_empty() and raw[raw.size() - 1]["tick"] == t["tick"]:
			raw[raw.size() - 1]["bpm"] = bpm
		else:
			raw.append({"tick": t["tick"], "bpm": bpm})
	if raw.is_empty() or raw[0]["tick"] > 0:
		raw.push_front({"tick": 0, "bpm": DEFAULT_BPM})
	var res := float(maxi(parsed.resolution, 1))
	var sec := 0.0
	for i in raw.size():
		if i > 0:
			var p: Dictionary = raw[i - 1]
			sec += float(raw[i]["tick"] - p["tick"]) / res * 60.0 / p["bpm"]
		raw[i]["sec"] = sec
	return raw


static func _tick_to_sec(segs: Array, res: int, tick: int) -> float:
	var lo := 0
	var hi := segs.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if segs[mid]["tick"] <= tick:
			lo = mid
		else:
			hi = mid - 1
	var s: Dictionary = segs[lo]
	return s["sec"] + float(tick - s["tick"]) / float(res) * 60.0 / s["bpm"]


static func _solos(parsed: ParsedChart, difficulty: String, chart: ChartData, segs: Array, res: int, delay: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events: Array = []
	var track_name: String = _TRACK_NAMES.get(difficulty, "")
	if track_name != "" and parsed.tracks.has(track_name):
		for e in parsed.tracks[track_name]:
			if e["type"] == "E" and _solo_kind(e["text"]) != 0:
				events.append(e)
	if events.is_empty():
		for e in parsed.events:
			if _solo_kind(e["text"]) != 0:
				events.append(e)
	if events.is_empty():
		return out

	var last_note_tick := 0
	for g in _collect(parsed, difficulty):
		last_note_tick = maxi(last_note_tick, g["tick"])
	var open := -1
	var pairs: Array = []
	for e in events:
		var kind := _solo_kind(e["text"])
		if kind == 1:
			if open < 0:
				open = e["tick"]
		elif open >= 0:
			pairs.append([open, e["tick"]])
			open = -1
	if open >= 0:
		pairs.append([open, maxi(open, last_note_tick)])

	for p in pairs:
		var st := maxf(_tick_to_sec(segs, res, p[0]) + delay, 0.0)
		var en := maxf(_tick_to_sec(segs, res, p[1]) + delay, 0.0)
		var count := 0
		for n in chart.notes:
			if n["time"] >= st and n["time"] <= en:
				count += 1
		out.append({"start": st, "end": en, "note_count": count})
	return out


## [Events] "section <name>" -> [{time, name}] sorted, deduplicated, sanitized, capped.
static func _sections(parsed: ParsedChart, segs: Array, res: int, delay: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for e in parsed.events:
		var text: String = str(e.get("text", ""))
		var stripped := text.strip_edges(true, false)
		if not stripped.to_lower().begins_with("section "):
			continue
		var name := _clean_section_name(stripped.substr(8))
		if name == "":
			continue
		var t := maxf(_tick_to_sec(segs, res, int(e["tick"])) + delay, 0.0)
		if not is_finite(t):
			continue
		var key := "%d|%s" % [int(round(t * 1000000.0)), name]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"time": t, "name": name})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	if out.size() > MAX_SECTIONS:
		out.resize(MAX_SECTIONS)
	return out


## Control characters removed, whitespace runs collapsed to one space, trimmed, capped.
static func _clean_section_name(raw: String) -> String:
	var out := ""
	var pending_space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c == 9 or c == 10 or c == 13 or c == 32:
			pending_space = out != ""
			continue
		if c < 32 or c == 127:
			continue
		if pending_space:
			out += " "
			pending_space = false
		out += raw[i]
		if out.length() >= MAX_SECTION_NAME:
			break
	return out.substr(0, MAX_SECTION_NAME).strip_edges()


## TS events -> [{time, num, den}] (den = 2^exp), clamped, last at a tick wins, default
## 4/4 at the chart start when the first TS is missing or later.
static func _time_sigs(parsed: ParsedChart, segs: Array, res: int, delay: float) -> Array[Dictionary]:
	var raw: Array = []  # {tick, num, den}
	for ts in parsed.time_sigs:
		var num := clampi(int(ts.get("num", 4)), 1, MAX_TS_NUM)
		var ts_exp := clampi(int(ts.get("exp", 2)), 0, MAX_TS_EXP)
		var tick := int(ts.get("tick", 0))
		if tick < 0:
			continue
		var entry := {"tick": tick, "num": num, "den": 1 << ts_exp}
		if not raw.is_empty() and raw[raw.size() - 1]["tick"] == tick:
			raw[raw.size() - 1] = entry
		else:
			raw.append(entry)
		if raw.size() >= MAX_TIME_SIGS:
			break
	if raw.is_empty() or raw[0]["tick"] > 0:
		raw.push_front({"tick": 0, "num": 4, "den": 4})
		if raw.size() > MAX_TIME_SIGS:
			raw.resize(MAX_TIME_SIGS)
	var out: Array[Dictionary] = []
	for r in raw:
		var t := _tick_to_sec(segs, res, int(r["tick"])) + delay
		if not is_finite(t):
			continue
		out.append({"time": t, "num": r["num"], "den": r["den"]})
	# negative delay: keep the last signature at or before 0 and start it at 0
	while out.size() > 1 and out[1]["time"] <= 0.0:
		out.remove_at(0)
	if not out.is_empty() and out[0]["time"] < 0.0:
		out[0]["time"] = 0.0
	return out


## 1 = solo, 2 = soloend, 0 = other.
static func _solo_kind(text: String) -> int:
	var t := text.strip_edges().to_lower()
	if t == "solo":
		return 1
	if t == "soloend":
		return 2
	return 0
