class_name PackInstaller
extends Node
## Installs the Autocharter pack (D-03, D-04, D-13): checking -> downloading -> verifying ->
## extracting -> finalizing -> done. This is the security gate in front of downloaded code:
## every part is size- and SHA-256-checked against the pins compiled into the game
## (PackSpec, never a downloaded manifest); a part that fails is deleted and never
## extracted. Extraction goes into staging, the staging folder is renamed into place and
## installed.json is written LAST. Hashing, extraction and finalize run on WorkerThreadPool;
## results come back through a Mutex-guarded queue drained in _process (workers never touch
## nodes). Tests inject fetcher / free_space and AutochartPaths.root_override.

signal state_changed(state: String)
signal progress_changed(done: int, total: int, label: String)
signal installed()
signal failed(code: String, message: String)

const NOT_AVAILABLE_TEXT := "The Autocharter pack is not available yet. Check for a newer UNDERTOW build."
const NETWORK_TEXT := "Download failed. Check your connection and try again."
const HASH_TEXT := "The download was damaged. Please try again."
const DISK_TEXT := "Not enough free disk space. The Autocharter pack needs about 2 GB."
const EXTRACT_TEXT := "The Autocharter pack could not be installed. Please try again."
const BUSY_TEXT := "The Autocharter pack is already being installed."
const DISK_UNKNOWN_TEXT := "Could not check free disk space. Installing anyway."
const REQUIRED_FREE_BYTES := 2147483648
const HASH_CHUNK := 1 << 20
const STALL_MS := 30000
## Roots that can be updated without a full reinstall.
const PARTIAL_ROOTS: Array[String] = ["app", "NOTICES", "models"]

var spec: Dictionary = PackSpec.as_dict()
## func(url: String, dest: String, expected_size: int, done: Callable); done.call(ok, http_code, err)
var fetcher: Callable = Callable()
## func(path: String) -> int; 0 = unknown
var free_space: Callable = Callable()
## "Install from Folder": parts are hashed and extracted directly from here (never modified).
var source_dir: String = ""
## Tests only: passed through to PackExtractor.extract_all (e.g. progress_every).
var extract_limits: Dictionary = {}
## WR-07: a staging rename that fails (antivirus scanning fresh DLLs, a brief sharing
## violation) is retried this many times, rename_retry_ms apart, before the install fails.
var rename_attempts := 10
var rename_retry_ms := 500
## Tests only: func(from: String, to: String) -> Error; default DirAccess.rename_absolute.
var rename_fn: Callable = Callable()

var _state := "idle"
var _gen := 0
var _cancel_flag := false
var _cancel_mutex := Mutex.new()
var _queue: Array = []
var _queue_mutex := Mutex.new()
var _task_id := -1

# Current run.
var _todo: Array = []
var _full := true
var _index := 0
var _paths: Array = []  # verified zip path per _todo entry
var _reused := false  # current part came from an earlier dl/ leftover

# Default HTTP fetcher.
var _http: HTTPRequest
var _http_args: Array = []
var _http_retries := 0
var _http_last_bytes := -1
var _http_last_change_ms := 0
var _dl_done_bytes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _exit_tree() -> void:
	_set_cancel(true)
	_http_stop()
	_wait_task()


func state() -> String:
	return _state


# ---- marker / plan ----

func _version() -> int:
	return int(spec.get("version", PackSpec.VERSION))


func _parts() -> Array:
	return spec.get("parts", [])


func _read_marker() -> Dictionary:
	var path := AutochartPaths.marker_path(_version())
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	var m: Dictionary = j.data
	if int(m.get("pack_version", -1)) != _version() or typeof(m.get("parts")) != TYPE_DICTIONARY:
		return {}
	return m


func is_installed() -> bool:
	if _parts().is_empty():
		return false
	return parts_to_fetch().is_empty()


## Parts whose pinned hash differs from installed.json. Anything that is not an app,
## NOTICES or models part, a missing marker or a missing interpreter means a full install.
func parts_to_fetch() -> Array:
	var parts := _parts()
	var m := _read_marker()
	if m.is_empty() or not FileAccess.file_exists(AutochartPaths.python_exe(_version())):
		return parts.duplicate()
	var have: Dictionary = m["parts"]
	var changed := {}  # part name -> true
	for p in parts:
		if String(have.get(p["name"], "")) != String(p["sha256"]):
			for r in p.get("roots", []):
				if not PARTIAL_ROOTS.has(String(r)):
					return parts.duplicate()
			changed[String(p["name"])] = true
	# WR-06: finalize replaces whole roots, so every part that shares a root with a changed part
	# is extracted again too (pack_build splits a big part into -a / -b with the same roots).
	var grew := true
	while grew:
		grew = false
		var roots := {}
		for p in parts:
			if changed.has(String(p["name"])):
				for r in p.get("roots", []):
					roots[String(r)] = true
		for p in parts:
			if changed.has(String(p["name"])):
				continue
			for r in p.get("roots", []):
				if roots.has(String(r)):
					changed[String(p["name"])] = true
					grew = true
					break
	var out: Array = []
	for p in parts:
		if changed.has(String(p["name"])):
			out.append(p)
	return out


# ---- control ----

func _busy() -> bool:
	return not (_state == "idle" or _state == "done" or _state == "failed")


func start() -> void:
	if _busy():
		return  # second call while running is ignored
	_gen += 1
	_set_cancel(false)
	_queue_mutex.lock()
	_queue.clear()
	_queue_mutex.unlock()
	_set_state("checking")
	if _parts().is_empty():
		_fail("not_available", NOT_AVAILABLE_TEXT)
		return
	_todo = parts_to_fetch()
	if _todo.is_empty():
		_set_state("done")
		installed.emit()
		return
	_full = _todo.size() == _parts().size() or _read_marker().is_empty()
	if _full:
		var free := _free_space(AutochartPaths.root())
		if free == 0:
			push_warning("PackInstaller: free disk space unknown")
			progress_changed.emit(0, 0, DISK_UNKNOWN_TEXT)
		elif free < REQUIRED_FREE_BYTES:
			_fail("disk", DISK_TEXT)
			return
	_index = 0
	_paths = []
	_dl_done_bytes = 0
	_next_part()


func cancel() -> void:
	if not _busy():
		return
	_set_cancel(true)
	_gen += 1
	_http_stop()
	_wait_task()  # never delete staging while the worker may still write
	_cleanup_run(true)
	set_process(false)
	_set_state("idle")


func remove_pack(job_running: bool) -> bool:
	if job_running or _busy():
		return false
	var v := _version()
	AutochartPaths.rm_tree(AutochartPaths.version_dir(v))
	AutochartPaths.rm_tree(AutochartPaths.staging_dir(v))
	AutochartPaths.rm_tree(AutochartPaths.dl_dir())
	# WR-11: the stem cache and the numba cache go with the pack; Clear Chart Cache is not
	# reachable once the pack is gone.
	AutochartWorkCache.clear(AutochartPaths.work_root())
	AutochartPaths.rm_tree(AutochartPaths.root().path_join("cache"))
	if _state == "done":
		_set_state("idle")
	return not DirAccess.dir_exists_absolute(AutochartPaths.version_dir(v))


func mark_selftest(ok: bool) -> void:
	var m := _read_marker()
	if m.is_empty():
		return
	m["selftest"] = ok
	var f := FileAccess.open(AutochartPaths.marker_path(_version()), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m, "\t"))
		f.close()


func selftest_ok() -> bool:
	return bool(_read_marker().get("selftest", false))


# ---- per part: fetch / locate, then verify on a worker ----

func _next_part() -> void:
	if _index >= _todo.size():
		_begin_extract()
		return
	var part: Dictionary = _todo[_index]
	var pname := String(part["name"])
	if not _safe_part_name(pname):
		_fail("not_available", NOT_AVAILABLE_TEXT)
		return
	var dest := AutochartPaths.dl_dir().path_join(pname)
	if source_dir != "":
		var src := AutochartPaths.norm(source_dir).path_join(pname)
		if not FileAccess.file_exists(src):
			_fail("not_available", "Part %s was not found in the chosen folder." % pname)
			return
		# CR-01: never extract from the chosen folder. The worker copies the part into dl/ and
		# hashes exactly the bytes it writes, so extraction reads only the pinned copy.
		_reused = false
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		_begin_verify(dest, src)
		return
	if FileAccess.file_exists(dest):
		_reused = true  # complete leftover from an earlier failed run: verify before refetching
		_begin_verify(dest)
		return
	_fetch(part, dest)


func _fetch(part: Dictionary, dest: String) -> void:
	_reused = false
	var url := String(spec.get("base_url", "")) + String(part["name"])
	if not url.begins_with("https://"):
		push_error("PackInstaller: refusing non-HTTPS url " + url)
		_fail("network", NETWORK_TEXT)
		return
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	_set_state("downloading")
	var done := _on_fetched.bind(_gen, _index)
	if fetcher.is_valid():
		fetcher.call(url, dest, int(part["size"]), done)
	else:
		_http_fetch(url, dest, int(part["size"]), done)


func _on_fetched(ok: bool, http_code: int, err: String, gen: int, index: int) -> void:
	if gen != _gen or index != _index or _state != "downloading":
		return
	var part: Dictionary = _todo[_index]
	var dest := AutochartPaths.dl_dir().path_join(String(part["name"]))
	if http_code == 404:
		_delete_file(dest)
		_fail("not_available", NOT_AVAILABLE_TEXT)
		return
	if not ok or http_code != 200 or not FileAccess.file_exists(dest):
		push_warning("PackInstaller: download failed (%d) %s" % [http_code, err])
		_delete_file(dest)
		_fail("network", NETWORK_TEXT)
		return
	_dl_done_bytes += int(part["size"])
	_begin_verify(dest)


## copy_from != "": the part is copied from there into path while it is hashed (CR-01).
func _begin_verify(path: String, copy_from: String = "") -> void:
	_set_state("verifying")
	var part: Dictionary = _todo[_index]
	progress_changed.emit(_index, _todo.size(), "Checking part %d / %d" % [_index + 1, _todo.size()])
	_run_task(_verify_task.bind(_gen, path, int(part["size"]), String(part["sha256"]).to_lower(),
		copy_from), "PackInstaller verify")


func _on_verified(msg: Dictionary) -> void:
	var path := String(msg["path"])
	match String(msg["result"]):
		"ok":
			_paths.append(path)
			_index += 1
			_next_part()
		"cancelled":
			pass
		_:
			# Every verified path is under dl/ (folder installs verify their dl/ copy); the
			# player's own folder is never touched.
			var in_dl := AutochartPaths.norm(path).begins_with(AutochartPaths.dl_dir() + "/")
			if in_dl:
				_delete_file(path)  # never extract a part that fails its pin
			if _reused and in_dl:
				_fetch(_todo[_index], path)  # stale leftover: download it fresh
				return
			_fail("hash_mismatch", HASH_TEXT)


# ---- extract and finalize on workers ----

func _begin_extract() -> void:
	var gen := _gen
	_set_state("extracting")
	if gen != _gen:
		return  # cancelled from a state handler
	_run_task(_extract_task.bind(_gen, _paths.duplicate(), AutochartPaths.staging_dir(_version())),
		"PackInstaller extract")


func _on_extracted(msg: Dictionary) -> void:
	var r := String(msg["result"])
	if r == "cancelled":
		return
	if r != "ok":
		push_warning("PackInstaller: extraction failed: " + r)
		_fail("extract", EXTRACT_TEXT)
		return
	var gen := _gen
	_set_state("finalizing")
	if gen != _gen or _is_cancelled():
		return  # cancel() between verify and finalize: finalize never runs
	var roots: Array = []
	for p in _todo:
		for root in p.get("roots", []):
			roots.append(String(root))
	var pins := {}
	for p in _parts():
		pins[String(p["name"])] = String(p["sha256"]).to_lower()
	_run_task(_finalize_task.bind(_gen, _full, roots, pins), "PackInstaller finalize")


func _on_finalized(msg: Dictionary) -> void:
	var r := String(msg["result"])
	if r == "cancelled":
		return
	if r != "ok":
		push_warning("PackInstaller: finalize failed: " + r)
		_fail("extract", EXTRACT_TEXT)
		return
	AutochartPaths.rm_tree(AutochartPaths.dl_dir())
	set_process(false)
	_set_state("done")
	installed.emit()


# ---- worker bodies (no nodes, no signals) ----

## Hashes path. With copy_from, reads copy_from instead, writes every hashed chunk to
## path + ".part" and renames it to path only when size and hash match, so the bytes that
## get extracted are the bytes that were hashed (CR-01).
func _verify_task(gen: int, path: String, size: int, sha: String, copy_from: String = "") -> void:
	var result := "ok"
	var src_path := copy_from if copy_from != "" else path
	var tmp := path + ".part"
	var out: FileAccess = null
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		result = "mismatch"
	elif f.get_length() != size:
		result = "mismatch"
		f.close()
	else:
		if copy_from != "":
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			out = FileAccess.open(tmp, FileAccess.WRITE)
			if out == null:
				result = "mismatch"
		if result == "ok":
			result = hash_stream(f, size, sha, out, _is_cancelled)
		f.close()
		if out != null:
			out.close()
		if copy_from != "":
			if result == "ok" and DirAccess.rename_absolute(tmp, path) != OK:
				result = "mismatch"
			if FileAccess.file_exists(tmp):
				DirAccess.remove_absolute(tmp)
	_push({"t": "verified", "gen": gen, "path": path, "result": result})


## Reads `size` bytes from f in HASH_CHUNK steps, hashes them (and copies them to out when
## given). Returns "ok", "mismatch" or "cancelled". A read that returns nothing or reports an
## error (unplugged stick, dropped share) fails instead of spinning (WR-02).
static func hash_stream(f: FileAccess, size: int, sha: String, out: FileAccess = null,
		should_cancel: Callable = Callable()) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var read := 0
	while read < size:
		if should_cancel.is_valid() and bool(should_cancel.call()):
			return "cancelled"
		var buf := f.get_buffer(mini(HASH_CHUNK, size - read))
		if buf.is_empty() or f.get_error() not in [OK, ERR_FILE_EOF]:
			return "mismatch"
		read += buf.size()
		ctx.update(buf)
		if out != null and (not out.store_buffer(buf) or out.get_error() != OK):
			return "mismatch"
	return "ok" if ctx.finish().hex_encode() == sha else "mismatch"


func _extract_task(gen: int, zips: Array, staging: String) -> void:
	if DirAccess.dir_exists_absolute(staging):
		AutochartPaths.rm_tree(staging)
	var total := 0
	for z in zips:
		var sizes: Variant = ZipExtractor._central_sizes(z)
		if sizes != null:
			for n in sizes:
				if not String(n).ends_with("/"):
					total += 1
	var base := [0]
	var progress := func(w: int, _t: int) -> void:
		_push({"t": "progress", "gen": gen, "done": base[0] + w, "total": total})
	var result := "ok"
	for z in zips:
		var r := PackExtractor.extract_all(z, staging, progress, extract_limits, _is_cancelled)
		if not r["ok"]:
			result = String(r["error"])
			break
		base[0] += int(r["written"])
	if result == "ok" and _is_cancelled():
		result = "cancelled"
	_push({"t": "extracted", "gen": gen, "result": result})


func _finalize_task(gen: int, full: bool, roots: Array, pins: Dictionary) -> void:
	var v := _version()
	var vdir := AutochartPaths.version_dir(v)
	var staging := AutochartPaths.staging_dir(v)
	var marker := AutochartPaths.marker_path(v)
	if _is_cancelled():
		_push({"t": "finalized", "gen": gen, "result": "cancelled"})
		return
	# The marker goes first so a crash mid-swap never looks installed.
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)
	var result := "ok"
	if full:
		if DirAccess.dir_exists_absolute(vdir) and not AutochartPaths.rm_tree(vdir):
			result = "remove_failed"
		elif _is_cancelled():
			result = "cancelled"
		else:
			result = _rename_with_retry(staging, vdir)
	else:
		for root in roots:
			var src := staging.path_join(root)
			var dst := vdir.path_join(root)
			if not (DirAccess.dir_exists_absolute(src) or FileAccess.file_exists(src)):
				continue
			if DirAccess.dir_exists_absolute(dst):
				AutochartPaths.rm_tree(dst)
			elif FileAccess.file_exists(dst):
				DirAccess.remove_absolute(dst)
			if _is_cancelled():
				result = "cancelled"
				break
			result = _rename_with_retry(src, dst)
			if result != "ok":
				break
		if DirAccess.dir_exists_absolute(staging):
			AutochartPaths.rm_tree(staging)
	if result == "ok" and _is_cancelled():
		result = "cancelled"
	if result == "ok":
		# installed.json LAST, after the rename.
		var data := {
			"pack_version": v,
			"tag": String(spec.get("tag", PackSpec.TAG)),
			"parts": pins,
			"installed_unix": Time.get_unix_time_from_system(),
			"selftest": false,
		}
		var f := FileAccess.open(marker, FileAccess.WRITE)
		if f == null:
			result = "marker_failed"
		else:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()
	_push({"t": "finalized", "gen": gen, "result": result})


## Worker thread. "ok", "cancelled" (cancel seen between tries) or "rename_failed" (WR-07).
func _rename_with_retry(from: String, to: String) -> String:
	var tries := maxi(1, rename_attempts)
	for i in tries:
		var err: int = rename_fn.call(from, to) if rename_fn.is_valid() else DirAccess.rename_absolute(from, to)
		if err == OK:
			return "ok"
		if i + 1 < tries:
			if _is_cancelled():
				return "cancelled"
			OS.delay_msec(maxi(0, rename_retry_ms))
	return "rename_failed"


# ---- main-thread drain ----

func _process(_delta: float) -> void:
	_http_watch()
	_queue_mutex.lock()
	var items := _queue.duplicate()
	_queue.clear()
	_queue_mutex.unlock()
	for item in items:
		if int(item["gen"]) != _gen:
			continue
		var t := String(item["t"])
		if t == "progress":
			progress_changed.emit(int(item["done"]), int(item["total"]),
				"Installing %d / %d files" % [int(item["done"]), int(item["total"])])
			continue
		_wait_task()
		match t:
			"verified":
				_on_verified(item)
			"extracted":
				_on_extracted(item)
			"finalized":
				_on_finalized(item)


func _push(item: Dictionary) -> void:
	_queue_mutex.lock()
	_queue.append(item)
	_queue_mutex.unlock()


func _run_task(c: Callable, desc: String) -> void:
	_wait_task()
	_task_id = WorkerThreadPool.add_task(c, false, desc)
	set_process(true)


func _wait_task() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _set_cancel(v: bool) -> void:
	_cancel_mutex.lock()
	_cancel_flag = v
	_cancel_mutex.unlock()


func _is_cancelled() -> bool:
	_cancel_mutex.lock()
	var v := _cancel_flag
	_cancel_mutex.unlock()
	return v


# ---- helpers ----

func _set_state(s: String) -> void:
	if s == _state:
		return
	_state = s
	state_changed.emit(s)


func _fail(code: String, message: String) -> void:
	_http_stop()
	_wait_task()
	_cleanup_run(false)
	set_process(false)
	_set_state("failed")
	failed.emit(code, message)


## Staging always goes; dl/ goes on cancel (failed runs keep complete, hash-checked-later
## leftovers so a retry does not redownload everything). Nothing in source_dir is touched.
func _cleanup_run(remove_dl: bool) -> void:
	AutochartPaths.rm_tree(AutochartPaths.staging_dir(_version()))
	if remove_dl:
		AutochartPaths.rm_tree(AutochartPaths.dl_dir())
	else:
		var dl := AutochartPaths.dl_dir()
		if DirAccess.dir_exists_absolute(dl):
			for f in DirAccess.get_files_at(dl):
				if f.ends_with(".part"):
					DirAccess.remove_absolute(dl.path_join(f))


func _free_space(path: String) -> int:
	if free_space.is_valid():
		return int(free_space.call(path))
	var d := DirAccess.open(path)
	return d.get_space_left() if d != null else 0


static func _safe_part_name(n: String) -> bool:
	return n != "" and ZipExtractor.safe_rel(n) == n and not n.contains("/")


func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path) and AutochartPaths.is_under_root(path):
		DirAccess.remove_absolute(path)




# ---- default fetcher: HTTPRequest, 1 MiB chunks, own stall timer, one retry ----

func _http_fetch(url: String, dest: String, expected_size: int, done: Callable) -> void:
	if not url.begins_with("https://"):
		done.call(false, 0, "insecure_url")
		return
	_http_args = [url, dest, expected_size, done]
	_http_retries = 0
	_http_begin()


func _http_begin() -> void:
	_http_stop()
	var dest := String(_http_args[1])
	var http := HTTPRequest.new()
	http.download_file = dest + ".part"
	http.download_chunk_size = 1 << 20
	http.max_redirects = 8
	http.body_size_limit = int(_http_args[2]) + 1024
	http.accept_gzip = false
	http.timeout = 0.0
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_http_completed.bind(http))
	_http = http
	_http_last_bytes = -1
	_http_last_change_ms = Time.get_ticks_msec()
	set_process(true)
	if http.request(String(_http_args[0])) != OK:
		_http_finish(false, 0, "request_failed")


func _on_http_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	if http != _http:
		return
	var dest := String(_http_args[1])
	_http_stop(false)
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(dest + ".part"):
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		if DirAccess.rename_absolute(dest + ".part", dest) == OK:
			(_http_args[3] as Callable).call(true, 200, "")
			return
	DirAccess.remove_absolute(dest + ".part")
	(_http_args[3] as Callable).call(false, code, "http result %d" % result)


func _http_finish(ok: bool, code: int, err: String) -> void:
	var dest := String(_http_args[1])
	_http_stop()
	if FileAccess.file_exists(dest + ".part"):
		DirAccess.remove_absolute(dest + ".part")
	(_http_args[3] as Callable).call(ok, code, err)


func _http_watch() -> void:
	if _http == null:
		return
	var bytes := _http.get_downloaded_bytes()
	var total := 0
	for p in _todo:
		total += int(p["size"])
	progress_changed.emit(_dl_done_bytes + bytes, total,
		"Downloading %d / %d MB" % [(_dl_done_bytes + bytes) >> 20, total >> 20])
	var now := Time.get_ticks_msec()
	if bytes != _http_last_bytes:
		_http_last_bytes = bytes
		_http_last_change_ms = now
	elif now - _http_last_change_ms > STALL_MS:
		if _http_retries < 1:
			_http_retries += 1
			_http_begin()
		else:
			_http_finish(false, 0, "stalled")


func _http_stop(delete_part: bool = true) -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
		_http = null
		if delete_part and not _http_args.is_empty():
			var part := String(_http_args[1]) + ".part"
			if FileAccess.file_exists(part):
				DirAccess.remove_absolute(part)
