class_name AutochartJob
extends RefCounted
## Godot half of the autocharter job protocol (D-05).
##
## The game never puts free text on the child's argv: Godot's Windows argument quoting does not
## escape '"' or a trailing backslash. The argv is a fixed token list plus paths checked by
## safe_path_arg; the song name, artist and every other field live only in job.json.
##
## Event protocol (child stdout, one ASCII JSON object per line):
##   start, work, stage, progress, warn, rank, error, selftest, done (see the plan 02 interfaces).
## Exit codes: 0 ok, 2 an error event was printed, 3 MemoryError, 4 parent gone, other = crash.

const VERSION := 1
const MODES: Array[String] = ["auto", "single", "lanes"]
const STEMS: Array[String] = ["other", "drums", "bass", "vocals"]
const AUDIO_EXTS: Array[String] = ["mp3", "ogg", "wav", "flac"]

const EXIT_OK := 0
const EXIT_ERROR := 2
const EXIT_MEMORY := 3
const EXIT_PARENT_GONE := 4

const MAX_TEXT := 120
const DEFAULT_GENRE := "Autochart"
const DEFAULT_TARGET_NPS := 3.5

## Error code -> player-facing text (D-01). Shared with the Python job (plan 05).
const ERROR_TEXT := {
	"bad_job": "The chart request was invalid. Please try again.",
	"bad_type": "This file type is not supported. Use MP3, OGG, WAV or FLAC.",
	"not_found": "The audio file could not be found.",
	"too_big": "The file is larger than 200 MB.",
	"too_short": "The song is shorter than 5 seconds.",
	"too_long": "Songs longer than 10 minutes are not supported.",
	"bad_rate": "Only 44.1 kHz and 48 kHz audio is supported.",
	"decode": "This file could not be read. It may be damaged or copy-protected.",
	"no_beats": "No steady beat was found in this song.",
	"no_notes": "The chosen instrument has too few notes. Try another instrument.",
	"exists": "A song with this name already exists.",
	"disk": "Not enough free disk space.",
	"memory": "Not enough memory for a song this long.",
	"selftest": "The autocharter failed its self-test. Remove the pack and install it again.",
	"internal": "The autocharter stopped unexpectedly.",
	"crash": "The autocharter crashed.",
	"vcredist": "Install the Microsoft Visual C++ Redistributable (x64), then try again.",
	"start": "The autocharter could not be started.",
}


static func make_job(src: String, name: String, artist: String, mode: String, stem: String,
		songs_root: String, work_root: String, models_root: String, threads: int,
		replace: bool = false) -> Dictionary:
	var m := mode.strip_edges().to_lower()
	var s := stem.strip_edges().to_lower()
	if m == "auto" or m == "lanes":
		s = "other"
	var a := artist.strip_edges()
	if a.is_empty():
		a = "Unknown"
	return {
		"version": VERSION,
		"src": src,
		"name": name.strip_edges(),
		"artist": a,
		"genre": DEFAULT_GENRE,
		"mode": m,
		"stem": s,
		"target_nps": DEFAULT_TARGET_NPS,
		"songs_root": songs_root,
		"work_root": work_root,
		"models_root": models_root,
		"threads": threads,
		"replace": replace,
	}


## Returns "" when the job is valid, else an error code from ERROR_TEXT.
static func validate(job: Dictionary) -> String:
	for key in ["version", "src", "name", "artist", "mode", "stem", "target_nps", "songs_root",
			"work_root", "models_root", "threads", "replace"]:
		if not job.has(key):
			return "bad_job"
	# IN-05: version and threads must be real ints, as stages/job.py requires.
	if not (job["version"] is int) or int(job["version"]) != VERSION:
		return "bad_job"
	if not (job["src"] is String):
		return "bad_job"
	var src: String = job["src"]
	if not AUDIO_EXTS.has(src.get_extension().to_lower()):
		return "bad_type"
	if not (job["name"] is String) or not (job["artist"] is String):
		return "bad_job"
	var nm: String = (job["name"] as String).strip_edges()
	if nm.is_empty() or nm.length() > MAX_TEXT:
		return "bad_job"
	if (job["artist"] as String).strip_edges().length() > MAX_TEXT:
		return "bad_job"
	if not (job["mode"] is String) or not MODES.has(job["mode"]):
		return "bad_job"
	if not (job["stem"] is String) or not STEMS.has(job["stem"]):
		return "bad_job"
	if not _is_number(job["target_nps"]):
		return "bad_job"
	var nps := float(job["target_nps"])
	if nps < 0.5 or nps > 8.0:
		return "bad_job"
	if not (job["threads"] is int):
		return "bad_job"
	var th := int(job["threads"])
	if th < 1 or th > 64:
		return "bad_job"
	for key in ["src", "songs_root", "work_root", "models_root"]:
		if not (job[key] is String) or not safe_path_arg(job[key]):
			return "bad_job"
	if not (job["replace"] is bool):
		return "bad_job"
	return ""


static func write_job(path: String, job: Dictionary) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		return err if err != OK else FAILED
	f.store_string(JSON.stringify(job, "\t"))
	var werr := f.get_error()
	f.close()
	return werr


## Fixed argv for the child interpreter. No -B: pack mode keeps pyc in LOCALAPPDATA.
static func build_args(app_dir: String, command: String, job_path: String = "") -> PackedStringArray:
	var args := PackedStringArray(["-I", "-X", "utf8", "-u", app_dir.path_join("autochart.py"),
		command])
	if command == "job":
		args.append(job_path)
	return args


## True when p is safe to pass on a Windows argv: absolute, no '"', no trailing separator,
## no control characters, not a Godot virtual path.
static func safe_path_arg(p: String) -> bool:
	if p.is_empty() or not p.is_absolute_path() or p.contains("://"):
		return false
	if p.contains("\"") or p.ends_with("\\") or p.ends_with("/"):
		return false
	for i in p.length():
		var c := p.unicode_at(i)
		if c < 32 or c == 127:
			return false
	return true


## Splits complete '\n'-terminated lines off buf. Returns [PackedStringArray lines,
## PackedByteArray rest]. CR and surrounding whitespace are stripped; empty lines are dropped.
static func take_lines(buf: PackedByteArray) -> Array:
	var lines := PackedStringArray()
	var start := 0
	for i in buf.size():
		if buf[i] == 10:
			var line := buf.slice(start, i).get_string_from_utf8().strip_edges()
			if not line.is_empty():
				lines.append(line)
			start = i + 1
	return [lines, buf.slice(start)]


## One protocol event, or {} for junk, non-objects and objects without a String "ev".
static func parse_event(line: String) -> Dictionary:
	if not line.begins_with("{"):
		return {}
	# A JSON instance reports failure silently; JSON.parse_string logs an engine error per junk line.
	var json := JSON.new()
	if json.parse(line) != OK:
		return {}
	var v = json.data
	if v is Dictionary and (v as Dictionary).get("ev") is String:
		return v
	return {}


static func error_text(code: String) -> String:
	return ERROR_TEXT.get(code, ERROR_TEXT["internal"])


static func _is_number(v: Variant) -> bool:
	return v is int or v is float
