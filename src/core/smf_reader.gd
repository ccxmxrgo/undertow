class_name SmfReader
extends RefCounted
## Bounded Standard MIDI File reader (CONT-01, D-08, D-09).
##
## Pure and deterministic: bytes in, track/event lists out. Never asserts, never throws, never prints.
## Untrusted input (D-08): size / track / entry / tick caps apply, every read is bounds-checked
## against the chunk end, and every loop iteration advances the cursor.
## Clone Hero semantics (pitches, difficulties, SysEx meaning) live in MidiChartReader, not here.

## Real Clone Hero / GH .mid files are well under 1 MB; 4 MB leaves generous headroom (review M-02).
const MAX_BYTES := 4 * 1024 * 1024
## Events scanned across ALL tracks of one file (review M-01 / M-02). Bounds parse time and memory
## however the bytes are split over tracks. A real chart has well under 200k events.
const MAX_EVENTS := 1500000
const MAX_TRACKS := 256
## Per list per track (notes / texts / tempos / time_sigs / sysex); extras dropped, warnings += 1.
const MAX_ENTRIES := 300000
## Bytes kept from one text / name event; the rest is skipped by length.
const MAX_TEXT := 256
## Same cap as ChartParser.MAX_TICK; an absolute tick above it fails the file.
const MAX_TICK := 2147483647


## Cursor over one chunk body. Reads return -1 on overrun.
class _Cur extends RefCounted:
	var b: PackedByteArray
	var pos: int = 0
	var end: int = 0
	var warnings: int = 0
	var events: int = 0
	var max_events: int = 0
	var over: bool = false

	## Variable-length quantity, at most 4 bytes (a 5th continuation byte fails).
	func vlq() -> int:
		var v := 0
		for i in 4:
			if pos >= end:
				return -1
			var c: int = b[pos]
			pos += 1
			v = (v << 7) | (c & 0x7F)
			if c & 0x80 == 0:
				return v
		return -1


## keep_names (optional): upper-cased track names to parse fully. Track index 0 is always parsed fully.
## When keep_names is non-empty, any other track whose name is not in it gets {name, index, skipped=true}
## with empty lists and the rest of its chunk is skipped by length.
## limits (optional, tests): {max_bytes, max_tracks, max_entries, max_events}.
static func read(bytes: PackedByteArray, limits: Dictionary = {}, keep_names: PackedStringArray = PackedStringArray()) -> Dictionary:
	var max_bytes: int = limits.get("max_bytes", MAX_BYTES)
	var max_tracks: int = limits.get("max_tracks", MAX_TRACKS)
	var max_entries: int = limits.get("max_entries", MAX_ENTRIES)
	var max_events: int = limits.get("max_events", MAX_EVENTS)
	var res := {"ok": false, "error": "", "format": 0, "division": 0, "warnings": 0, "tracks": []}
	var size := bytes.size()
	if size > max_bytes:
		res["error"] = SongEntry.ERR_TOO_LARGE
		return res
	if size < 14 or not _is_tag(bytes, 0, "MThd"):
		return _bad(res)
	var hlen := _u32(bytes, 4)
	if hlen < 6 or 8 + hlen > size:
		return _bad(res)
	var format := _u16(bytes, 8)
	var division := _u16(bytes, 12)
	if format > 1 or division == 0 or (division & 0x8000) != 0:
		return _bad(res)
	res["format"] = format
	res["division"] = division

	var cur := _Cur.new()
	cur.b = bytes
	cur.max_events = max_events
	var tracks: Array[Dictionary] = []
	var warnings := 0
	var pos := 8 + hlen
	while pos + 8 <= size:
		var is_trk := _is_tag(bytes, pos, "MTrk")
		var clen := _u32(bytes, pos + 4)
		var body := pos + 8
		if body + clen > size:
			if not is_trk and not tracks.is_empty():
				# Junk after the last track (review L-03): keep what was read.
				warnings += 1
				break
			return _bad(res)
		if is_trk:
			if tracks.size() >= max_tracks:
				warnings += 1
			else:
				var t = _parse_track(cur, body, body + clen, tracks.size(), max_entries, keep_names)
				if t == null:
					if cur.over:
						res["error"] = SongEntry.ERR_TOO_LARGE
						res["tracks"] = []
						return res
					return _bad(res)
				tracks.append(t)
		pos = body + clen
	res["warnings"] = warnings + cur.warnings
	res["tracks"] = tracks
	res["ok"] = true
	return res


static func _bad(res: Dictionary) -> Dictionary:
	res["ok"] = false
	res["error"] = SongEntry.ERR_MIDI_BAD
	res["tracks"] = []
	return res


static func _empty_track(index: int, track_name: String, skipped: bool) -> Dictionary:
	return {"index": index, "name": track_name, "skipped": skipped, "notes": [], "texts": [],
			"tempos": [], "time_sigs": [], "sysex": []}


## Returns the track Dictionary, or null on any grammar failure.
static func _parse_track(c: _Cur, start: int, end: int, index: int, max_entries: int, keep_names: PackedStringArray) -> Variant:
	var b := c.b
	c.pos = start
	c.end = end
	var t := _empty_track(index, "", false)
	var notes: Array = t["notes"]
	var texts: Array = t["texts"]
	var tempos: Array = t["tempos"]
	var sigs: Array = t["time_sigs"]
	var sysex: Array = t["sysex"]
	var filtering := index > 0 and not keep_names.is_empty()
	var tick := 0
	var running := -1
	var seq := 0
	var has_name := false
	var name_known := false
	while c.pos < end:
		c.events += 1
		if c.events > c.max_events:
			c.over = true
			return null
		var delta := c.vlq()
		if delta < 0:
			return null
		tick += delta
		if tick > MAX_TICK:
			return null
		if tick > 0 and not name_known:
			name_known = true
			if filtering and not _is_kept(t["name"], keep_names):
				return _skip(c, index, t["name"])
		if c.pos >= end:
			return null
		var status: int = b[c.pos]
		if status >= 0x80:
			c.pos += 1
			if status < 0xF0:
				running = status
			elif status == 0xF0 or status == 0xF7:
				var slen := c.vlq()
				if slen < 0 or c.pos + slen > end:
					return null
				if slen == 8:
					if sysex.size() >= max_entries:
						c.warnings += 1
					else:
						sysex.append({"tick": tick, "data": b.slice(c.pos, c.pos + slen), "seq": seq})
						seq += 1
				c.pos += slen
				continue
			elif status == 0xFF:
				if c.pos >= end:
					return null
				var mtype: int = b[c.pos]
				c.pos += 1
				var mlen := c.vlq()
				if mlen < 0 or c.pos + mlen > end:
					return null
				var mstart := c.pos
				c.pos += mlen
				if mtype == 0x2F:
					c.pos = end
					break
				elif mtype == 0x03:
					if tick == 0 and not has_name:
						has_name = true
						name_known = true
						t["name"] = _decode(b, mstart, mlen).strip_edges()
						if filtering and not _is_kept(t["name"], keep_names):
							return _skip(c, index, t["name"])
				elif mtype >= 0x01 and mtype <= 0x0F:
					if texts.size() >= max_entries:
						c.warnings += 1
					else:
						texts.append({"tick": tick, "text": _decode(b, mstart, mlen), "seq": seq})
						seq += 1
				elif mtype == 0x51 and mlen >= 3:
					if tempos.size() >= max_entries:
						c.warnings += 1
					else:
						var us := (int(b[mstart]) << 16) | (int(b[mstart + 1]) << 8) | int(b[mstart + 2])
						tempos.append({"tick": tick, "uspqn": us, "seq": seq})
						seq += 1
				elif mtype == 0x58 and mlen >= 2:
					if sigs.size() >= max_entries:
						c.warnings += 1
					else:
						sigs.append({"tick": tick, "num": int(b[mstart]), "exp": int(b[mstart + 1]), "seq": seq})
						seq += 1
				continue
			else:
				return null
		else:
			if running < 0:
				return null
			status = running
		var kind := status & 0xF0
		var need := 1 if (kind == 0xC0 or kind == 0xD0) else 2
		if c.pos + need > end:
			return null
		var d1 := int(b[c.pos]) & 0x7F
		var d2 := (int(b[c.pos + 1]) & 0x7F) if need == 2 else 0
		c.pos += need
		if kind == 0x80 or kind == 0x90:
			if notes.size() >= max_entries:
				c.warnings += 1
			else:
				notes.append({"tick": tick, "pitch": d1, "on": kind == 0x90 and d2 > 0, "seq": seq})
				seq += 1
	if filtering and not _is_kept(t["name"], keep_names):
		return _skip(c, index, t["name"])
	return t


static func _skip(c: _Cur, index: int, track_name: String) -> Dictionary:
	c.pos = c.end
	return _empty_track(index, track_name, true)


static func _is_kept(track_name: String, keep_names: PackedStringArray) -> bool:
	return keep_names.has(track_name.to_upper())


## ASCII fast path; valid UTF-8 as UTF-8; anything else as Latin-1. Capped at MAX_TEXT bytes.
static func _decode(b: PackedByteArray, start: int, length: int) -> String:
	var n := mini(length, MAX_TEXT)
	var s := PackedByteArray()
	var high := false
	for i in n:
		var x: int = b[start + i]
		if x == 0:
			continue  # NUL would make the engine print a Unicode error
		if x >= 0x80:
			high = true
		s.append(x)
	if not high:
		return s.get_string_from_ascii()
	if _valid_utf8(s):
		return s.get_string_from_utf8()
	var out := ""
	for x in s:
		out += String.chr(x)
	return out


static func _valid_utf8(s: PackedByteArray) -> bool:
	var i := 0
	var n := s.size()
	while i < n:
		var x: int = s[i]
		var extra := 0
		if x < 0x80:
			extra = 0
		elif x >= 0xC2 and x <= 0xDF:
			extra = 1
		elif x >= 0xE0 and x <= 0xEF:
			extra = 2
		elif x >= 0xF0 and x <= 0xF4:
			extra = 3
		else:
			return false
		if extra > 0 and i + extra >= n:
			return false
		for k in extra:
			if (int(s[i + 1 + k]) & 0xC0) != 0x80:
				return false
		i += 1 + extra
	return true


static func _is_tag(b: PackedByteArray, p: int, tag: String) -> bool:
	for i in 4:
		if b[p + i] != tag.unicode_at(i):
			return false
	return true


static func _u16(b: PackedByteArray, p: int) -> int:
	return (int(b[p]) << 8) | int(b[p + 1])


static func _u32(b: PackedByteArray, p: int) -> int:
	return (int(b[p]) << 24) | (int(b[p + 1]) << 16) | (int(b[p + 2]) << 8) | int(b[p + 3])
