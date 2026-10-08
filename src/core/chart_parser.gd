class_name ChartParser
extends RefCounted
## Tolerant Clone Hero .chart text parser (SONG-01, SONG-06).
##
## Pure and deterministic: bytes in, ParsedChart (ticks) out. Never asserts, never throws,
## never prints per line. Untrusted input: size / line / entry / tick caps apply (T-01),
## all numbers go through a strict integer check (T-02, garbage is skipped, never tick 0).
## Fatal errors: no section header where one is expected, a header with no "{", or caps.
## Everything else is a counted warning and the line is skipped.

const MAX_BYTES := 64 * 1024 * 1024
const MAX_LINES := 1000000
const MAX_ENTRIES := 300000
const MAX_TICK := 2147483647
const DEFAULT_RESOLUTION := 192
const MAX_RESOLUTION := 65535
const BAD := -9223372036854775807

const ERR_TOO_LARGE := "Chart too large"


## limits (optional, tests): {max_bytes, max_lines, max_entries} override the caps.
static func parse_bytes(bytes: PackedByteArray, limits: Dictionary = {}) -> ParsedChart:
	var max_bytes: int = limits.get("max_bytes", MAX_BYTES)
	var max_lines: int = limits.get("max_lines", MAX_LINES)
	var max_entries: int = limits.get("max_entries", MAX_ENTRIES)
	var pc := ParsedChart.new()
	if bytes.size() > max_bytes:
		pc.error = ERR_TOO_LARGE
		return pc
	var text := _decode(bytes)
	var lines := text.split("\n")
	if lines.size() > max_lines:
		pc.error = ERR_TOO_LARGE
		return pc

	var re_track := RegEx.new()
	re_track.compile("^(Easy|Medium|Hard|Expert)Single$")

	var section := ""  # "" = outside any section
	var pending := ""  # header seen, waiting for "{"
	var pending_line := 0
	var seen_header := false
	var seq := 0
	var res_raw := ""

	var i := 0
	while i < lines.size():
		i += 1
		var line: String = lines[i - 1].strip_edges()
		if line == "" or line.begins_with("//"):
			continue

		if pending != "":
			if line == "{":
				section = pending
				pending = ""
				if not pc.tracks.has(section) and re_track.search(section) != null:
					pc.tracks[section] = []
				continue
			return _fail(pc, pending_line)

		if section == "":
			if _is_header(line):
				seen_header = true
				pending = line.substr(1, line.length() - 2).strip_edges()
				pending_line = i
				if pending == "":
					pending = " "  # empty name: still needs a brace
				continue
			if not seen_header:
				return _fail(pc, i)
			_warn(pc, i)
			continue

		# inside a section
		if line == "}":
			section = ""
			continue
		if _is_header(line):
			# missing "}" before the next header: tolerate
			_warn(pc, i)
			section = ""
			pending = line.substr(1, line.length() - 2).strip_edges()
			pending_line = i
			if pending == "":
				pending = " "
			continue

		var eq := line.find("=")
		if eq < 0:
			_warn(pc, i)
			continue
		var left := line.substr(0, eq).strip_edges()
		var right := line.substr(eq + 1).strip_edges()

		if section == "Song":
			var key := left.to_lower()
			pc.song[key] = _unquote(right)
			if key == "resolution":
				res_raw = right
			continue

		var is_track := re_track.search(section) != null
		if section != "SyncTrack" and section != "Events" and not is_track:
			continue  # unknown / unsupported section: ignored silently

		var tick := _to_int(left)
		if tick == BAD or tick < 0 or tick > MAX_TICK:
			_warn(pc, i)
			continue
		var toks := right.split(" ", false)
		if toks.is_empty():
			_warn(pc, i)
			continue
		var typ: String = toks[0]

		if section == "SyncTrack":
			if typ == "B":
				var v := _to_int(toks[1]) if toks.size() > 1 else BAD
				if v == BAD or v <= 0 or v > MAX_TICK:
					_warn(pc, i)
				else:
					pc.tempo.append({"tick": tick, "milli_bpm": v, "seq": seq})
					seq += 1
			elif typ == "TS":
				var n := _to_int(toks[1]) if toks.size() > 1 else BAD
				var e := _to_int(toks[2]) if toks.size() > 2 else 2
				if n == BAD or n <= 0 or n > 1024 or e == BAD or e < 0 or e > 16:
					_warn(pc, i)
				else:
					pc.time_sigs.append({"tick": tick, "num": n, "exp": e, "seq": seq})
					seq += 1
			# "A" anchors and unknown types: ignored
			continue

		if section == "Events":
			if typ == "E":
				if pc.events.size() >= max_entries:
					_warn(pc, i)
					continue
				pc.events.append({"tick": tick, "text": _unquote(right.substr(1).strip_edges()), "seq": seq})
				seq += 1
			continue

		# guitar track
		var arr: Array = pc.tracks[section]
		if typ == "N" or typ == "S":
			var a := _to_int(toks[1]) if toks.size() > 1 else BAD
			var b := _to_int(toks[2]) if toks.size() > 2 else BAD
			if a == BAD or b == BAD or b < 0 or b > MAX_TICK:
				_warn(pc, i)
				continue
			if typ == "N" and (a < 0 or a > 7):
				_warn(pc, i)
				continue
			if arr.size() >= max_entries:
				_warn(pc, i)
				continue
			arr.append({"tick": tick, "type": typ, "a": a, "b": b, "text": "", "seq": seq})
			seq += 1
		elif typ == "E":
			if arr.size() >= max_entries:
				_warn(pc, i)
				continue
			arr.append({"tick": tick, "type": "E", "a": 0, "b": 0, "text": _unquote(right.substr(1).strip_edges()), "seq": seq})
			seq += 1
		# other types ignored

	if pending != "":
		return _fail(pc, pending_line)
	if not seen_header:
		return _fail(pc, 1)
	if section != "":
		_warn(pc, lines.size())  # truncated: missing final "}"

	# Resolution
	var res := _to_int(res_raw) if res_raw != "" else BAD
	if res == BAD or res <= 0:
		pc.resolution = DEFAULT_RESOLUTION
		_warn(pc, 0)
	else:
		pc.resolution = clampi(res, 1, MAX_RESOLUTION)

	# Stable sort by tick (seq keeps file order for equal ticks).
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


static func _is_header(line: String) -> bool:
	return line.length() >= 2 and line.begins_with("[") and line.ends_with("]")


static func _fail(pc: ParsedChart, line: int) -> ParsedChart:
	pc.ok = false
	pc.error_line = line
	pc.error = "Unreadable .chart (line %d)" % line
	return pc


static func _warn(pc: ParsedChart, line: int) -> void:
	pc.warnings += 1
	if pc.first_warning_line == 0 and line > 0:
		pc.first_warning_line = line


## Strict base-10 integer: rejects garbage instead of returning 0.
static func _to_int(s: String) -> int:
	var t := s.strip_edges()
	if t.length() == 0 or t.length() > 12 or not t.is_valid_int():
		return BAD
	return t.to_int()


## Drops only the first and last quote; stray inner quotes stay.
static func _unquote(s: String) -> String:
	var t := s
	if t.begins_with("\""):
		t = t.substr(1)
	if t.ends_with("\""):
		t = t.substr(0, t.length() - 1)
	return t


static func _decode(bytes: PackedByteArray) -> String:
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		return bytes.slice(2).get_string_from_utf16().lstrip("﻿")
	if bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF:
		var swapped := bytes.slice(2)
		var n := swapped.size() - (swapped.size() % 2)
		var j := 0
		while j < n:
			var tmp := swapped[j]
			swapped[j] = swapped[j + 1]
			swapped[j + 1] = tmp
			j += 2
		return swapped.get_string_from_utf16().lstrip("﻿")
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return bytes.slice(3).get_string_from_utf8()
	return bytes.get_string_from_utf8().lstrip("﻿")
