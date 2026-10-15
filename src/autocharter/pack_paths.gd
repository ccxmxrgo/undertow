class_name AutochartPaths
extends RefCounted
## Where the Autocharter pack lives (D-13): %LOCALAPPDATA%/UNDERTOW/ac (user:// is the
## ROAMING profile, too big for a 1 GB runtime), fallback user://autocharter. Never next to
## the exe or in the Songs folder. The root is kept short (MAX_PATH).

## Tests inject; default OS.get_environment.
static var env_getter: Callable = Callable()
## Tests inject a user:// path.
static var root_override: String = ""


static func _norm(p: String) -> String:
	var g := ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
	return g.replace("\\", "/").simplify_path()


static func root() -> String:
	var r := ""
	if root_override != "":
		r = _norm(root_override)
	else:
		var lad := ""
		if env_getter.is_valid():
			lad = String(env_getter.call("LOCALAPPDATA"))
		else:
			lad = OS.get_environment("LOCALAPPDATA")
		if lad.strip_edges() != "":
			r = _norm(lad.strip_edges().replace("\\", "/").path_join("UNDERTOW/ac"))
		else:
			r = _norm("user://autocharter")
	DirAccess.make_dir_recursive_absolute(r)
	return r


static func version_dir(v: int = PackSpec.VERSION) -> String:
	return root().path_join("v%d" % v)


static func staging_dir(v: int = PackSpec.VERSION) -> String:
	return root().path_join("staging_v%d" % v)


static func dl_dir() -> String:
	return root().path_join("dl")


static func work_root() -> String:
	return root().path_join("work")


static func python_exe(v: int = PackSpec.VERSION) -> String:
	return version_dir(v).path_join("rt/python.exe")


static func app_dir(v: int = PackSpec.VERSION) -> String:
	return version_dir(v).path_join("app")


static func models_dir(v: int = PackSpec.VERSION) -> String:
	return version_dir(v).path_join("models")


static func marker_path(v: int = PackSpec.VERSION) -> String:
	return version_dir(v).path_join("installed.json")


## True when path is root() itself or inside it (defence in depth for recursive deletes).
static func is_under_root(path: String) -> bool:
	var r := root()
	var p := _norm(path)
	return p.begins_with(r + "/")
