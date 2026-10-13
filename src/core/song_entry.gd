class_name SongEntry
extends RefCounted
## One row of the song library (playable, needs a chart, or broken with a readable reason).
## Plain data with a type-validating from_dict, because the scan cache file is untrusted.

const ERR_OPUS := "Opus audio not supported"
const ERR_NO_GUITAR := "No guitar chart"
const ERR_AUDIO_MISSING := "Audio file missing"
const ERR_MIDI := "MIDI charts not supported yet"
const ERR_UNSUPPORTED_AUDIO := "Unsupported audio format"
const ERR_AUDIO_BAD := "Audio could not be read"
const ERR_ZIP := "Zip could not be unpacked"
const ERR_TOO_LARGE := "Chart too large"
const ERR_NEEDS_CHART := "Needs a chart"
const ERR_MIDI_BAD := "Unreadable .mid"
const ERR_MIDI_NO_GUITAR := "No guitar part in .mid"

const STATUSES: Array[String] = ["ok", "needs_chart", "broken"]
const SOURCES: Array[String] = ["bundled", "songs", "library", "test"]
const MAX_STR := 1024
const MAX_PATH := 2048

var id: String = ""
var path: String = ""
var source: String = "songs"
var library_name: String = ""
var title: String = ""
var artist: String = ""
var charter: String = ""
var length_sec: float = 0.0
var bpm_min: float = 0.0
var bpm_max: float = 0.0
## -1 = unset.
var preview_start_ms: int = -1
## Array of {name: String, note_count: int, fingerprint: String}.
var difficulties: Array[Dictionary] = []
var has_solos: bool = false
var status: String = "ok"
var error: String = ""
var fix_hint: String = ""
var warnings: int = 0
var chart_path: String = ""
var ini_path: String = ""
var audio_files: Array[String] = []
var delay_ms: int = 0
## Cheap change detector (names, mtimes, sizes of the files that matter).
var signature: String = ""


static func err_unreadable(line: int) -> String:
	return "Unreadable .chart (line %d)" % line


static func hint_for(err: String) -> String:
	if err.begins_with("Unreadable .chart (line "):
		var n := err.trim_prefix("Unreadable .chart (line ").trim_suffix(")")
		return "The chart file looks damaged near line %s. Download the song again." % n
	match err:
		ERR_OPUS:
			return "Convert the audio to OGG Vorbis, MP3 or WAV, then press Rescan."
		ERR_NO_GUITAR:
			return "This chart has no lead guitar notes. Only guitar charts work."
		ERR_AUDIO_MISSING:
			return "No song audio found next to the chart. Add song.ogg, song.mp3 or song.wav, then press Rescan."
		ERR_MIDI:
			return "This song only has a .mid chart. Only .chart files work for now."
		ERR_UNSUPPORTED_AUDIO:
			return "Use OGG Vorbis, MP3 or WAV audio."
		ERR_AUDIO_BAD:
			return "The audio file looks damaged. Replace it, then press Rescan."
		ERR_ZIP:
			return "The zip is damaged or has unsafe paths. Unzip it into the Songs folder yourself."
		ERR_TOO_LARGE:
			return "This chart file is far larger than any normal song. It was skipped."
		ERR_MIDI_BAD:
			return "The .mid chart looks damaged. Download the song again."
		ERR_MIDI_NO_GUITAR:
			return "This .mid has no guitar or bass part. Only guitar charts work."
		ERR_NEEDS_CHART:
			return "Only audio was found. Add a notes.chart next to it, then press Rescan."
	return ""


func difficulty(diff_name: String) -> Dictionary:
	for d in difficulties:
		if d["name"] == diff_name:
			return d
	return {}


func is_playable() -> bool:
	return status == "ok"


func to_dict() -> Dictionary:
	return {
		"id": id, "path": path, "source": source, "library_name": library_name,
		"title": title, "artist": artist, "charter": charter,
		"length_sec": length_sec, "bpm_min": bpm_min, "bpm_max": bpm_max,
		"preview_start_ms": preview_start_ms, "difficulties": difficulties.duplicate(true),
		"has_solos": has_solos, "status": status, "error": error, "fix_hint": fix_hint,
		"warnings": warnings, "chart_path": chart_path, "ini_path": ini_path,
		"audio_files": audio_files.duplicate(), "delay_ms": delay_ms, "signature": signature,
	}


static func _num_ok(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## Returns null on any wrong type, non-finite or negative number, or over-long string.
static func from_dict(d: Variant) -> SongEntry:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var e := SongEntry.new()
	for k in ["id", "path", "chart_path", "ini_path", "signature"]:
		var v: Variant = d.get(k)
		if typeof(v) != TYPE_STRING or (v as String).length() > MAX_PATH:
			return null
		e.set(k, v)
	for k in ["library_name", "title", "artist", "charter", "error", "fix_hint"]:
		var v: Variant = d.get(k)
		if typeof(v) != TYPE_STRING or (v as String).length() > MAX_STR:
			return null
		e.set(k, v)
	if typeof(d.get("source")) != TYPE_STRING or not SOURCES.has(d["source"]):
		return null
	e.source = d["source"]
	if typeof(d.get("status")) != TYPE_STRING or not STATUSES.has(d["status"]):
		return null
	e.status = d["status"]
	for k in ["length_sec", "bpm_min", "bpm_max"]:
		var f: Variant = d.get(k)
		if not _num_ok(f):
			return null
		var ff := float(f)
		if not is_finite(ff) or ff < 0.0 or ff > 1.0e7:
			return null
		e.set(k, ff)
	for k in ["preview_start_ms", "warnings", "delay_ms"]:
		var n: Variant = d.get(k)
		if not _num_ok(n):
			return null
		var nf := float(n)
		if not is_finite(nf) or absf(nf) > 2.0e9 or nf != floorf(nf):
			return null
		if k == "warnings" and nf < 0.0:
			return null
		e.set(k, int(nf))
	if typeof(d.get("has_solos")) != TYPE_BOOL:
		return null
	e.has_solos = d["has_solos"]
	var diffs: Variant = d.get("difficulties")
	if typeof(diffs) != TYPE_ARRAY or (diffs as Array).size() > 8:
		return null
	for x in diffs:
		if typeof(x) != TYPE_DICTIONARY:
			return null
		var nm: Variant = x.get("name")
		var fp: Variant = x.get("fingerprint")
		var nc: Variant = x.get("note_count")
		if typeof(nm) != TYPE_STRING or typeof(fp) != TYPE_STRING:
			return null
		if (nm as String).length() > 16 or (fp as String).length() > 64:
			return null
		if not _num_ok(nc) or not is_finite(float(nc)) or float(nc) < 0.0 or float(nc) > 1.0e7:
			return null
		e.difficulties.append({"name": nm, "note_count": int(nc), "fingerprint": fp})
	var af: Variant = d.get("audio_files")
	if typeof(af) != TYPE_ARRAY or (af as Array).size() > 32:
		return null
	for a in af:
		if typeof(a) != TYPE_STRING or (a as String).length() > MAX_PATH:
			return null
		e.audio_files.append(a)
	return e
