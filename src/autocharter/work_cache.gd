class_name AutochartWorkCache
extends RefCounted
## The autocharter's on-disk cache (02.2.2 D-12 / D-05). Under AutochartPaths.work_root():
##   w_<sha16>/   one per source song (written by the Python job): decoded audio, stems and the
##                analysis. analyze_done.json is written LAST when analysis finished;
##                last_used.json {"t": unix} is refreshed on every job that uses the dir.
##   jobs/<id>/   one per run: job.json + log.txt (the error screen points at log.txt).
## prune keeps the stems of the last `keep` songs (instant "Chart Another Instrument"), drops
## unfinished dirs and job dirs older than a week; clear empties the cache. Every delete is
## confined to AutochartPaths.root() (same rule as PackInstaller).

const MARKER := "analyze_done.json"
const LAST_USED := "last_used.json"
const JOBS := "jobs"
const KEEP := 3
const JOB_MAX_AGE_S := 7 * 86400

static var _seq := 0


## Creates work_root/jobs/<unique id>/ and returns its absolute path ("" on failure). The id is
## j_<unix ms>_<n>, so the age of a job dir is readable from its name.
static func new_job_dir(work_root: String) -> String:
	var jobs := AutochartPaths.norm(work_root).path_join(JOBS)
	var ms := int(Time.get_unix_time_from_system() * 1000.0)
	for _i in 1000:
		_seq += 1
		var dir := jobs.path_join("j_%d_%d" % [ms, _seq])
		if DirAccess.dir_exists_absolute(dir):
			continue
		if DirAccess.make_dir_recursive_absolute(dir) == OK:
			return dir
		return ""
	return ""


## True when the Python job finished analysing this work dir (its stems can be reused).
static func is_analyzed(work_dir: String) -> bool:
	return work_dir != "" and FileAccess.file_exists(AutochartPaths.norm(work_dir).path_join(MARKER))


## Keeps the `keep` most recently used finished w_* dirs (the protected one always stays and
## counts toward `keep`), deletes unfinished unprotected w_* dirs and job dirs older than
## JOB_MAX_AGE_S. Returns the bytes freed, or -1 when work_root is outside the pack root.
static func prune(work_root: String, keep: int = KEEP, protect: String = "") -> int:
	var wr := AutochartPaths.norm(work_root)
	if not AutochartPaths.is_under_root(wr):
		return -1
	if not DirAccess.dir_exists_absolute(wr):
		return 0
	var prot := AutochartPaths.norm(protect) if protect != "" else ""
	var freed := 0
	var finished: Array = []  # [t, path]
	for n in DirAccess.get_directories_at(wr):
		if not n.begins_with("w_"):
			continue
		var p := wr.path_join(n)
		if prot != "" and AutochartPaths.same_path(p, prot):
			continue
		if is_analyzed(p):
			finished.append([_last_used(p), p])
		else:
			freed += _remove(p)
	finished.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var room := maxi(0, keep - (1 if prot != "" and DirAccess.dir_exists_absolute(prot) else 0))
	for i in finished.size():
		if i >= room:
			freed += _remove(String(finished[i][1]))
	var jobs := wr.path_join(JOBS)
	if DirAccess.dir_exists_absolute(jobs):
		var now := Time.get_unix_time_from_system()
		for n in DirAccess.get_directories_at(jobs):
			var p := jobs.path_join(n)
			var t := _job_time(p)
			if t > 0.0 and now - t > JOB_MAX_AGE_S:
				freed += _remove(p)
	return freed


## After a cancel (process gone): deletes work_dir when its analysis never finished. Returns
## true when it was removed (or was already gone), false when it is kept (finished, empty
## path, or outside the pack root).
static func remove_unfinished(work_dir: String) -> bool:
	if work_dir.strip_edges() == "":
		return false
	var p := AutochartPaths.norm(work_dir)
	if not AutochartPaths.is_under_root(p):
		return false
	if is_analyzed(p):
		return false
	if not DirAccess.dir_exists_absolute(p):
		return true
	return AutochartPaths.rm_tree(p)


## Clear Chart Cache: deletes every w_* dir and every job dir. Returns the bytes freed, or -1
## when work_root is not under AutochartPaths.root() (nothing is touched).
static func clear(work_root: String) -> int:
	var wr := AutochartPaths.norm(work_root)
	if not AutochartPaths.is_under_root(wr):
		return -1
	if not DirAccess.dir_exists_absolute(wr):
		return 0
	var freed := 0
	for n in DirAccess.get_directories_at(wr):
		if n.begins_with("w_"):
			freed += _remove(wr.path_join(n))
	var jobs := wr.path_join(JOBS)
	if DirAccess.dir_exists_absolute(jobs):
		for n in DirAccess.get_directories_at(jobs):
			freed += _remove(jobs.path_join(n))
		for f in DirAccess.get_files_at(jobs):
			freed += _remove(jobs.path_join(f))
	return freed


## Sum of every file size under path (0 when missing). A file path gives its own size.
static func size_bytes(path: String) -> int:
	var p := AutochartPaths.norm(path)
	if FileAccess.file_exists(p):
		return _file_size(p)
	# rm_tree removes a junction / symlink, never its target, so it frees nothing (WR-04).
	if not DirAccess.dir_exists_absolute(p) or AutochartPaths.is_link(p):
		return 0
	var total := 0
	for f in DirAccess.get_files_at(p):
		total += _file_size(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		total += size_bytes(p.path_join(d))
	return total


# ---- helpers ---------------------------------------------------------------------------------


static func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


## last_used.json {"t": unix}; else the analyze_done.json mtime; else 0.
static func _last_used(dir: String) -> float:
	var lu := dir.path_join(LAST_USED)
	if FileAccess.file_exists(lu):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(lu)) == OK and json.data is Dictionary:
			var t = (json.data as Dictionary).get("t")
			if (t is float or t is int) and float(t) > 0.0:
				return float(t)
	var m := dir.path_join(MARKER)
	if FileAccess.file_exists(m):
		return float(FileAccess.get_modified_time(m))
	return 0.0


## Job dir age from its j_<unix ms>_<n> name, else from job.json / log.txt mtimes; 0 = unknown.
static func _job_time(dir: String) -> float:
	var parts := dir.get_file().split("_")
	if parts.size() == 3 and parts[0] == "j" and parts[1].is_valid_int():
		return float(parts[1].to_int()) / 1000.0
	for f in ["job.json", "log.txt"]:
		var p := dir.path_join(f)
		if FileAccess.file_exists(p):
			return float(FileAccess.get_modified_time(p))
	return 0.0


## Deletes path (file or tree) and returns the bytes it held when it is gone, else 0.
static func _remove(path: String) -> int:
	var n := size_bytes(path)
	return n if AutochartPaths.rm_tree(path) else 0
