class_name ScoreStore
extends RefCounted
## Saved best score per chart id in user://scores.cfg (D-07).
## The file is untrusted: parsed from text (never ResourceLoader), type/finite/clamp checked,
## section count capped, ids sanitized. Saves are atomic (tmp then rename). Local file by design,
## no anti-cheat.

## 8192: one record per song+difficulty fingerprint, 4 difficulties x large Clone Hero libraries
## (RESEARCH Pitfall 9). Still a hard cap so a hostile file cannot exhaust memory (T-02-20).
const MAX_SECTIONS := 8192
const MAX_ID_LEN := 64
const MAX_DEPTH := 1.0e7
const MAX_COMBO := 1.0e6
const PREFIX := "chart:"
## D-16: the only grade letters that may be stored or loaded (anything else reads as "").
const GRADES: Array[String] = ["S", "A", "B", "C", "D"]

static var default_path := "user://scores.cfg"

var path: String
var load_error := false
## id -> {depth: float, accuracy: float, max_combo: int, date: String, grade: String, misses: int}.
## grade is "" and misses -1 for records saved before D-16 (legacy files load unchanged).
var _entries: Dictionary = {}


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path


static func sanitize_id(id: String) -> String:
	var out := ""
	for ch in id.to_lower():
		var c: int = ch.unicode_at(0)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or ch in ["_", ".", ":", "-"]
		if ok:
			out += ch
		if out.length() >= MAX_ID_LEN:
			break
	return out


static func is_eligible(autoplay_used: bool, no_fail: bool, practice: bool) -> bool:
	return not autoplay_used and not no_fail and not practice


## Legacy hit rate (Perfect + Good) / judged x 100. Gameplay now submits the weighted D-08
## accuracy from RunStats.accuracy; this stays for older callers (records before 02.2-15 hold it).
static func accuracy(perfect: int, good: int, miss: int) -> float:
	var total := perfect + good + miss
	if total <= 0:
		return 0.0
	return float(perfect + good) / float(total) * 100.0


func load() -> void:
	_entries = {}
	load_error = false
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var cfg := ConfigFile.new()
	if cfg.parse(text) != OK:
		_back_up_bad_file()
		load_error = true
		return
	var count := 0
	for section in cfg.get_sections():
		if count >= MAX_SECTIONS:
			break
		count += 1
		if not section.begins_with(PREFIX):
			continue
		var id := sanitize_id(section.substr(PREFIX.length()))
		if id == "":
			continue
		_entries[id] = {
			"depth": _num(cfg, section, "best_depth", MAX_DEPTH),
			"accuracy": _num(cfg, section, "best_accuracy", 100.0),
			"max_combo": int(_num(cfg, section, "max_combo", MAX_COMBO)),
			"date": _date(cfg, section),
			"grade": _grade(cfg.get_value(section, "grade", "")),
			"misses": _misses(cfg.get_value(section, "misses", -1)),
		}


## Empty dictionary when there is no saved best.
func best(id: String) -> Dictionary:
	var key := sanitize_id(id)
	if key != "" and _entries.has(key):
		return (_entries[key] as Dictionary).duplicate()
	return {}


## Returns {recorded, new_record, previous}. new_record is strictly greater depth.
## grade/misses (D-16) are stored together when the grade ranks above the stored one (or none is
## stored); an unknown grade is ignored. Depth, accuracy and combo improve independently.
func submit(id: String, depth: float, acc: float, max_combo: int, eligible: bool,
		date_text: String = "", grade: String = "", misses: int = -1) -> Dictionary:
	var key := sanitize_id(id)
	if not eligible or key == "":
		return {"recorded": false, "new_record": false, "previous": {}}
	var d := clampf(depth if is_finite(depth) else 0.0, 0.0, MAX_DEPTH)
	var a := clampf(acc if is_finite(acc) else 0.0, 0.0, 100.0)
	var c := clampi(max_combo, 0, int(MAX_COMBO))
	var previous := best(key)
	var new_record := previous.is_empty() or d > float(previous["depth"])
	var entry: Dictionary = previous.duplicate() if not previous.is_empty() \
		else {"depth": 0.0, "accuracy": 0.0, "max_combo": 0, "date": "", "grade": "", "misses": -1}
	var changed := previous.is_empty()
	var g := _grade(grade)
	if g != "" and RunStats.grade_rank(g) > RunStats.grade_rank(str(entry.get("grade", ""))):
		entry["grade"] = g
		entry["misses"] = clampi(misses, 0, int(MAX_COMBO))
		changed = true
	if d > float(entry["depth"]):
		entry["depth"] = d
		changed = true
	if a > float(entry["accuracy"]):
		entry["accuracy"] = a
		changed = true
	if c > int(entry["max_combo"]):
		entry["max_combo"] = c
		changed = true
	if new_record:
		entry["date"] = _clean_date(date_text)
	if changed:
		_entries[key] = entry
		save()
	return {"recorded": true, "new_record": new_record, "previous": previous}


func save() -> int:
	var cfg := ConfigFile.new()
	for id in _entries:
		var e: Dictionary = _entries[id]
		var section: String = PREFIX + String(id)
		cfg.set_value(section, "best_depth", e["depth"])
		cfg.set_value(section, "best_accuracy", e["accuracy"])
		cfg.set_value(section, "max_combo", e["max_combo"])
		cfg.set_value(section, "date", e["date"])
		var g: String = str(e.get("grade", ""))
		if g != "":  # ungraded (legacy) records keep their original key set
			cfg.set_value(section, "grade", g)
			cfg.set_value(section, "misses", int(e.get("misses", -1)))
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("ScoreStore: could not save %s (error %d)" % [path, err])
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
	return err


## Whitelist (T-02.2-27): only S/A/B/C/D strings survive; everything else is "".
static func _grade(v: Variant) -> String:
	if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
		return ""
	var s := str(v)
	return s if s in GRADES else ""


## Miss count of the best-grade run: -1 when absent or invalid, else clamped 0..MAX_COMBO.
static func _misses(v: Variant) -> int:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return -1
	var f := float(v)
	if not is_finite(f) or f < 0.0:
		return -1
	return int(minf(f, MAX_COMBO))


static func _clean_date(text: String) -> String:
	var out := ""
	for ch in text:
		if (ch >= "0" and ch <= "9") or ch == "-":
			out += ch
	return out.left(10)


func _date(cfg: ConfigFile, section: String) -> String:
	var v: Variant = cfg.get_value(section, "date", "")
	return _clean_date(v) if typeof(v) == TYPE_STRING else ""


func _num(cfg: ConfigFile, section: String, key: String, hi: float) -> float:
	var v: Variant = cfg.get_value(section, key, 0.0)
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0.0
	var f := float(v)
	if not is_finite(f):
		return 0.0
	return clampf(f, 0.0, hi)


func _back_up_bad_file() -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.rename_absolute(abs_path, abs_path + ".bak")
