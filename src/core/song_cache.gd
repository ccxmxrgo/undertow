class_name SongCache
extends RefCounted
## Scan cache at a JSON path: id -> SongEntry, valid only for the exact signature.
## The file is user-writable, so any problem (size, version, shape) yields an empty cache.
## It is only ever parsed as JSON, never handed to a resource loader.

const FORMAT := 1
const MAX_BYTES := 64 * 1024 * 1024

var path: String
var entries: Dictionary = {}


func _init(p_path: String = "") -> void:
	path = p_path


func load() -> void:
	entries = {}
	if path == "" or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		return
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.get("v") != FORMAT or data.get("importer") != ChartImporter.IMPORTER_VERSION \
			or data.get("mapping") != ChartImporter.MAPPING_VERSION:
		return
	var raw: Variant = data.get("entries")
	if typeof(raw) != TYPE_ARRAY:
		return
	var parsed := {}
	for item in raw:
		var e := SongEntry.from_dict(item)
		if e == null or e.id == "":
			return  # one bad entry poisons the file: start over
		parsed[e.id] = e
	entries = parsed


func lookup(id: String, signature: String) -> SongEntry:
	var e: SongEntry = entries.get(id)
	if e != null and signature != "" and e.signature == signature:
		return e
	return null


func put(e: SongEntry) -> void:
	entries[e.id] = e


## Atomic: write a temp file, then rename over the real one.
func save() -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var arr: Array = []
	for id in entries:
		arr.append((entries[id] as SongEntry).to_dict())
	var json := JSON.stringify({
		"v": FORMAT, "importer": ChartImporter.IMPORTER_VERSION,
		"mapping": ChartImporter.MAPPING_VERSION, "entries": arr,
	})
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(json)
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK and FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return err
