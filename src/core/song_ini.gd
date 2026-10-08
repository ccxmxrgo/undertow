class_name SongIni
extends RefCounted
## Tolerant song.ini reader (ConfigFile is too strict for community files).
## Only the [song] section is read; keys before any header count as [song].

const MAX_KEYS := 512


static func parse(text: String) -> Dictionary:
	var d := {}
	var in_song := true
	for raw in text.lstrip("﻿").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("["):
			in_song = line.to_lower() == "[song]"
			continue
		var eq := line.find("=")
		if not in_song or eq < 0:
			continue
		if d.size() >= MAX_KEYS:
			break
		d[line.substr(0, eq).strip_edges().to_lower()] = line.substr(eq + 1).strip_edges()
	return d


## Strips <...> rich-text tags and control characters, caps the length (T-04).
static func sanitize_text(s: String, max_len: int = 120) -> String:
	var re := RegEx.new()
	re.compile("<[^>]*>")
	var t := re.sub(s, "", true)
	var out := ""
	for i in t.length():
		var c := t.unicode_at(i)
		if c < 32 or c == 127:
			continue
		out += t[i]
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len)
	return out


## Strict integer read: "12abc" or a missing key returns default.
static func get_int(d: Dictionary, key: String, default: int = 0) -> int:
	if not d.has(key):
		return default
	var t := str(d[key]).strip_edges()
	if t.length() == 0 or t.length() > 12 or not t.is_valid_int():
		return default
	return t.to_int()
