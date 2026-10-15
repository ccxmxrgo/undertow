class_name AutochartPaths
extends RefCounted
## Where the Autocharter pack lives (D-13): %LOCALAPPDATA%/UNDERTOW/ac (user:// is the
## ROAMING profile, too big for a 1 GB runtime), fallback user://autocharter. Never next to
## the exe or in the Songs folder. The root is kept short (MAX_PATH).

## Tests inject; default OS.get_environment.
static var env_getter: Callable = Callable()
## Tests inject a user:// path.
static var root_override: String = ""


## Absolute, forward-slash, simplified form of a path (user:// and res:// are globalized). The
## one path normaliser of the autocharter code (IN-08).
static func norm(p: String) -> String:
	var g := ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
	return g.replace("\\", "/").simplify_path()


static func root() -> String:
	var r := ""
	if root_override != "":
		r = norm(root_override)
	else:
		var lad := ""
		if env_getter.is_valid():
			lad = String(env_getter.call("LOCALAPPDATA"))
		else:
			lad = OS.get_environment("LOCALAPPDATA")
		if lad.strip_edges() != "":
			r = norm(lad.strip_edges().replace("\\", "/").path_join("UNDERTOW/ac"))
		else:
			r = norm("user://autocharter")
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
## Comparisons are case-insensitive on Windows (WR-05): the Python side resolves its paths, so
## the casing it reports can differ from the LOCALAPPDATA / user:// strings built here.
static func is_under_root(path: String) -> bool:
	return path_key(path).begins_with(path_key(root()) + "/")


## Comparison key of a path: norm(), lowercased on Windows (case-insensitive file system).
static func path_key(p: String) -> String:
	var n := norm(p)
	return n.to_lower() if OS.get_name() == "Windows" else n


## True when a and b name the same path (case-insensitive on Windows).
static func same_path(a: String, b: String) -> bool:
	return path_key(a) == path_key(b)


## Recursive delete that refuses anything outside root() (defence in depth) and never follows a
## directory junction or symlink: a link is removed itself, its target is left alone (WR-04).
## Safe on worker threads. Returns true when the path no longer exists. The one delete helper
## of the autocharter code (IN-08).
static func rm_tree(path: String) -> bool:
	var p := norm(path)
	if not is_under_root(p):
		push_error("AutochartPaths: refusing to delete outside the pack root: " + p)
		return false
	if is_link(p):
		return DirAccess.remove_absolute(p) == OK
	if FileAccess.file_exists(p):
		return DirAccess.remove_absolute(p) == OK
	if not DirAccess.dir_exists_absolute(p):
		return true
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		rm_tree(p.path_join(d))
	return DirAccess.remove_absolute(p) == OK


## True for a symlink or (Windows) a directory junction / other reparse point.
static func is_link(p: String) -> bool:
	var da := DirAccess.open(p.get_base_dir())
	return da != null and da.is_link(p)
