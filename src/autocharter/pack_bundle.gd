class_name AutochartBundle
extends RefCounted
## Finds the Autocharter pack that ships with the game: a folder named "Autocharter Pack" (also
## "autocharter" / "Autocharter") next to UNDERTOW.exe holding every pinned part (PackSpec.PARTS)
## at its pinned size. Only exported builds look next to the executable (in the editor and in
## tests that is the Godot binary); tests inject base_dir_override instead. A folder that is
## "found" here is still only a source: PackInstaller copies every part into dl/ while it hashes
## it and refuses anything that does not match the pinned SHA-256 (CR-01). Hashing is never
## skipped; this check is just the cheap size gate that decides whether to try it at all.

const FOLDER_NAMES: Array[String] = ["Autocharter Pack", "autocharter", "Autocharter"]

## Tests: the folder that stands in for "next to the executable". "" = the default lookup.
static var base_dir_override: String = ""


## The folder the bundled pack folder is looked for in; "" when there is none to look in
## (editor / headless test runs without an override).
static func base_dir() -> String:
	if base_dir_override != "":
		return AutochartPaths.norm(base_dir_override)
	if not OS.has_feature("template"):
		return ""
	return AutochartPaths.norm(OS.get_executable_path()).get_base_dir()


## Absolute path of the bundled pack folder, or "" when none holds every part of `parts` at
## its pinned size. parts default to the compiled pins.
static func find(parts: Array = PackSpec.PARTS) -> String:
	var base := base_dir()
	if base == "" or parts.is_empty():
		return ""
	for n in FOLDER_NAMES:
		var d := base.path_join(n)
		if DirAccess.dir_exists_absolute(d) and has_parts(d, parts):
			return d
	return ""


## True when dir holds every part of `parts` with exactly its pinned size.
static func has_parts(dir: String, parts: Array) -> bool:
	if parts.is_empty():
		return false
	for p: Dictionary in parts:
		var pname := String(p.get("name", ""))
		if not PackInstaller._safe_part_name(pname):
			return false
		var f := FileAccess.open(dir.path_join(pname), FileAccess.READ)
		if f == null:
			return false
		var size := f.get_length()
		f.close()
		if size != int(p.get("size", -1)):
			return false
	return true
