class_name PackExtractor
extends RefCounted
## Fail-closed extraction of hashed Autocharter pack parts (D-04). Same two-pass approach
## as ZipExtractor: central-directory sizes are checked against caps BEFORE any data is
## decompressed (Zip64 refused). Unlike songs, every extension is allowed (the hash pins
## the content) but ANY unsafe name fails the whole part: a hashed part with a bad name is
## a broken build, never something to skip silently. Safe to call from a worker thread.

const MAX_ENTRIES := 60000
const MAX_ENTRY_BYTES := 600 * 1024 * 1024
const MAX_TOTAL_BYTES := 1717986918
const PROGRESS_EVERY := 200


static func _abs(p: String) -> String:
	var g := ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
	return g.replace("\\", "/").simplify_path()


## limits (tests): max_entries, max_total, max_entry. progress(written, total).
## should_cancel() -> bool is checked before every file. Returns {ok, error, written}.
static func extract_all(zip_path: String, dest_dir: String, progress: Callable = Callable(),
		limits: Dictionary = {}, should_cancel: Callable = Callable()) -> Dictionary:
	var max_entries: int = limits.get("max_entries", MAX_ENTRIES)
	var max_total: int = limits.get("max_total", MAX_TOTAL_BYTES)
	var max_entry: int = limits.get("max_entry", MAX_ENTRY_BYTES)
	var sizes: Variant = ZipExtractor._central_sizes(zip_path)
	if sizes == null:
		return _fail("zip_unreadable")
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return _fail("zip_unreadable")
	var files := zr.get_files()
	if files.size() > max_entries:
		zr.close()
		return _fail("too_many")
	var dest := _abs(dest_dir)
	var prefix := dest + "/"
	# Pass 1: every name and every claimed size, before touching any data.
	var plan: Array = []  # [entry name, absolute target, is_dir]
	var total := 0
	for name_s in files:
		var rel := ZipExtractor.safe_rel(name_s)
		if rel == "":
			zr.close()
			return _fail("unsafe_path")
		var target := dest.path_join(rel).simplify_path()
		if not target.begins_with(prefix):
			zr.close()
			return _fail("unsafe_path")
		var is_dir := name_s.ends_with("/") or name_s.ends_with("\\")
		if not is_dir:
			var sz: int = sizes.get(name_s, -1)
			if sz < 0 or sz > max_entry:
				zr.close()
				return _fail("too_large")
			total += sz
			if total > max_total:
				zr.close()
				return _fail("too_large")
		plan.append([name_s, target, is_dir])
	var file_count := 0
	for p in plan:
		if not p[2]:
			file_count += 1
	DirAccess.make_dir_recursive_absolute(dest)
	# Pass 2: write.
	var written := 0
	for p in plan:
		if p[2]:
			DirAccess.make_dir_recursive_absolute(p[1])
			continue
		if should_cancel.is_valid() and bool(should_cancel.call()):
			zr.close()
			return {"ok": false, "error": "cancelled", "written": written}
		DirAccess.make_dir_recursive_absolute(String(p[1]).get_base_dir())
		var f := FileAccess.open(p[1], FileAccess.WRITE)
		if f == null:
			zr.close()
			return {"ok": false, "error": "write_failed", "written": written}
		f.store_buffer(zr.read_file(p[0]))
		f.close()
		written += 1
		if progress.is_valid() and written % PROGRESS_EVERY == 0 and written < file_count:
			progress.call(written, file_count)
	zr.close()
	if progress.is_valid():
		progress.call(written, file_count)
	return {"ok": true, "error": "", "written": written}


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code, "written": 0}
