class_name SongScanner
extends RefCounted
## Finds and imports songs from library roots. Worker-thread safe: no scene tree, no
## autoloads, no engine resource loader on user files. Roots are only ever read; zips are
## unpacked into a hashed folder under zip_cache_root.
##
## Phase A enumerates candidates (so the total is known), Phase B imports each one, with a
## signature cache (path + mtime + size) that skips chart parsing and audio decoding.
##
## Candidate kinds: "folder" (a song folder), "bare" (one loose audio file), "zip".
## Zip entry ids are "<zip path>::<relative folder>".

static var max_depth := 6
static var max_candidates := 20000
static var zip_cache_root := "user://song_cache/zips"
## Test counters: how many charts were parsed and audio sets decoded.
static var parse_count := 0
static var decode_count := 0

const BATCH_SIZE := 16
const MAX_INI_BYTES := 1024 * 1024
const MAX_ID3_BYTES := 65536
const _TRAILING_PREFERRED := ["[y]", "[f]", "(y)", "(f)"]

var _cancel := Callable()


func _cancelled() -> bool:
	return _cancel.is_valid() and bool(_cancel.call())


## roots: Array of {path, source ("songs"|"library"|"test"), library_name}.
func scan_sync(roots: Array, cache: SongCache = null, cancel: Callable = Callable()) -> Array[SongEntry]:
	return scan(roots, cache, Callable(), Callable(), cancel)


## on_batch(entries: Array), on_progress(done: int, total: int, label: String).
func scan(roots: Array, cache: SongCache, on_batch: Callable, on_progress: Callable,
		cancel: Callable = Callable()) -> Array[SongEntry]:
	_cancel = cancel
	var results: Array[SongEntry] = []
	var cands: Array = []
	var visited := {}
	for r in roots:
		if _cancelled():
			return results
		var ctx := {"source": str(r.get("source", "songs")), "library_name": str(r.get("library_name", ""))}
		_discover(str(r["path"]), ctx, 0, true, cands, visited)
	var total := cands.size()
	var done := 0
	var batch: Array = []
	if on_progress.is_valid():
		on_progress.call(0, total, "")
	for c in cands:
		if _cancelled():
			break
		var label := String(c["path"]).get_file()
		var ents: Array[SongEntry]
		if c["kind"] == "zip":
			if on_progress.is_valid():
				on_progress.call(done, total, "Unpacking " + label)
			ents = _import_zip(c, cache)
		else:
			ents = _import_candidate(c, cache)
		total += maxi(ents.size() - 1, 0)
		for e in ents:
			results.append(e)
			batch.append(e)
		done += 1
		if on_batch.is_valid() and batch.size() >= BATCH_SIZE:
			on_batch.call(batch)
			batch = []
		if on_progress.is_valid():
			on_progress.call(done, total, label)
	if on_batch.is_valid() and not batch.is_empty():
		on_batch.call(batch)
	return results


# ---- Phase A: discovery ----

func _discover(dir: String, ctx: Dictionary, depth: int, is_root: bool, out: Array,
		visited: Dictionary) -> void:
	if out.size() >= max_candidates or depth > max_depth or _cancelled():
		return
	var key := norm(dir)
	if visited.has(key):
		return
	visited[key] = true
	var l := _list(dir)
	var has_chart := false
	var has_mid := false
	var audio: Array[String] = []
	for f in l["files"]:
		var ext := String(f).get_extension().to_lower()
		if ext == "chart":
			has_chart = true
		elif ext == "mid":
			has_mid = true
		elif AudioLoader.AUDIO_EXTS.has(ext):
			audio.append(f)
		elif ext == "zip" and not ctx.has("zip_path"):
			if out.size() < max_candidates:
				out.append({"kind": "zip", "path": dir.path_join(f), "ctx": ctx})
	if has_chart or has_mid:
		out.append({"kind": "folder", "path": dir, "ctx": ctx})
		return
	if not audio.is_empty():
		if is_root:
			for a in audio:
				if out.size() < max_candidates:
					out.append({"kind": "bare", "path": dir.path_join(a), "ctx": ctx})
		else:
			out.append({"kind": "folder", "path": dir, "ctx": ctx})
			return
	var da := DirAccess.open(dir)
	for d in l["dirs"]:
		if da != null and da.is_link(d):
			continue  # never follow symlinks or junctions
		_discover(dir.path_join(d), ctx, depth + 1, false, out, visited)


# ---- Phase B: import ----

func _id_for(path: String, ctx: Dictionary) -> String:
	if ctx.has("zip_path"):
		var rel := norm(path).trim_prefix(norm(String(ctx["zip_dir"]))).trim_prefix("/")
		return norm(String(ctx["zip_path"])) + "::" + rel
	return norm(path)


func _import_candidate(c: Dictionary, cache: SongCache) -> Array[SongEntry]:
	var out: Array[SongEntry] = []
	var path: String = c["path"]
	var ctx: Dictionary = c["ctx"]
	var source: String = ctx["source"]
	var lib: String = ctx["library_name"]
	if c["kind"] == "bare":
		var sig := file_signature(path)
		var id := _id_for(path, ctx)
		var hit := _cached(cache, id, sig, source, lib)
		if hit != null:
			out.append(hit)
			return out
		var e := import_bare(path, source, lib)
		e.id = id
		e.signature = sig
		out.append(e)
		return out
	# folder: loose multi-audio folders with no chart split into one entry per file
	var files: Array[String] = _list(path)["files"]
	var has_chart := false
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext == "chart" or ext == "mid":
			has_chart = true
	if not has_chart and AudioLoader.classify_stems(files)["core"].is_empty():
		for f in files:
			if AudioLoader.is_audio_name(f) and f.get_basename().to_lower() != "preview":
				out.append_array(_import_candidate(
						{"kind": "bare", "path": path.path_join(f), "ctx": ctx}, cache))
		return out
	var fsig := folder_signature(path)
	var fid := _id_for(path, ctx)
	var fhit := _cached(cache, fid, fsig, source, lib)
	if fhit != null:
		out.append(fhit)
		return out
	var fe := import_folder(path, source, lib)
	fe.id = fid
	fe.signature = fsig
	out.append(fe)
	return out


static func _cached(cache: SongCache, id: String, sig: String, source: String, lib: String) -> SongEntry:
	if cache == null:
		return null
	var hit := cache.lookup(id, sig)
	if hit != null:
		hit.source = source
		hit.library_name = lib
	return hit


func _import_zip(c: Dictionary, cache: SongCache) -> Array[SongEntry]:
	var zp: String = c["path"]
	var ctx: Dictionary = c["ctx"]
	var out: Array[SongEntry] = []
	var ctx_hash := HashingContext.new()
	ctx_hash.start(HashingContext.HASH_SHA1)
	ctx_hash.update(("%s|%d|%d" % [norm(zp), FileAccess.get_modified_time(zp), _file_len(zp)]).to_utf8_buffer())
	var dest := zip_cache_root.path_join(ctx_hash.finish().hex_encode())
	var marker := dest.path_join(".done")
	if not FileAccess.file_exists(marker):
		_rm_tree(dest)
		var r := ZipExtractor.extract(zp, dest)
		if not r["ok"]:
			_rm_tree(dest)
			out.append(_broken_zip(zp, ctx, SongEntry.ERR_ZIP))
			return out
		var mf := FileAccess.open(marker, FileAccess.WRITE)
		if mf != null:
			mf.store_string("ok")
			mf.close()
	var zctx := {"source": ctx["source"], "library_name": ctx["library_name"],
			"zip_path": zp, "zip_dir": dest}
	var sub: Array = []
	_discover(dest, zctx, 0, false, sub, {})
	if sub.is_empty():
		out.append(_broken_zip(zp, ctx, SongEntry.ERR_ZIP))
		return out
	for s in sub:
		if _cancelled():
			break
		out.append_array(_import_candidate(s, cache))
	return out


func _broken_zip(zp: String, ctx: Dictionary, err: String) -> SongEntry:
	var e := SongEntry.new()
	e.id = norm(zp)
	e.path = zp
	e.source = ctx["source"]
	e.library_name = ctx["library_name"]
	e.title = SongIni.sanitize_text(zp.get_file().get_basename())
	e.status = "broken"
	e.error = err
	e.fix_hint = SongEntry.hint_for(err)
	e.signature = file_signature(zp)
	return e


## Imports one song folder (works for user paths and res:// bundled folders).
## audio_override: full audio paths that replace folder discovery (bundled songs).
static func import_folder(path: String, source: String, library_name: String,
		audio_override: Array = []) -> SongEntry:
	var e := SongEntry.new()
	e.path = path
	e.id = norm(path)
	e.source = source
	e.library_name = library_name
	var files: Array[String] = _list(path)["files"]
	var chart_name := _pick_chart(files)
	var has_mid := false
	var ini_name := ""
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext == "mid":
			has_mid = true
		if f.to_lower() == "song.ini":
			ini_name = f
	var ini := {}
	if ini_name != "":
		e.ini_path = path.path_join(ini_name)
		ini = SongIni.parse(_read_text(e.ini_path, MAX_INI_BYTES))
	var folder_title := path.get_file()
	if folder_title.to_lower().ends_with(".zip"):
		folder_title = folder_title.get_basename()
	e.title = SongIni.sanitize_text(str(ini.get("name", ""))) if str(ini.get("name", "")) != "" \
			else SongIni.sanitize_text(folder_title)
	e.artist = SongIni.sanitize_text(str(ini.get("artist", "")))
	e.charter = SongIni.sanitize_text(str(ini.get("charter", ini.get("frets", ""))))
	e.delay_ms = clampi(SongIni.get_int(ini, "delay", 0), -30000, 30000)
	var pv := SongIni.get_int(ini, "preview_start_time", -1)
	e.preview_start_ms = pv if pv >= 0 else -1
	var audio_paths: Array[String] = []
	if audio_override.is_empty():
		for n in _song_audio(files):
			audio_paths.append(path.path_join(n))
	else:
		for p in audio_override:
			audio_paths.append(String(p))
	e.audio_files = audio_paths
	e.signature = folder_signature(path, audio_override)

	if chart_name == "":
		if has_mid:
			return _fail(e, SongEntry.ERR_MIDI)
		e.status = "needs_chart"
		e.error = SongEntry.ERR_NEEDS_CHART
		e.fix_hint = SongEntry.hint_for(e.error)
		return e
	e.chart_path = path.path_join(chart_name)
	if _file_len(e.chart_path) > ChartParser.MAX_BYTES:
		return _fail(e, SongEntry.ERR_TOO_LARGE)
	parse_count += 1
	var parsed := ChartParser.parse_bytes(FileAccess.get_file_as_bytes(e.chart_path))
	if not parsed.ok:
		return _fail(e, parsed.error)
	e.warnings = parsed.warnings
	if str(ini.get("name", "")) == "" and str(parsed.song.get("name", "")) != "":
		e.title = SongIni.sanitize_text(str(parsed.song["name"]))
	if e.artist == "":
		e.artist = SongIni.sanitize_text(str(parsed.song.get("artist", "")))
	if e.charter == "":
		e.charter = SongIni.sanitize_text(str(parsed.song.get("charter", "")))
	var diffs := ChartImporter.difficulties(parsed)
	if diffs.is_empty():
		return _fail(e, SongEntry.ERR_NO_GUITAR)
	if audio_paths.is_empty():
		return _fail(e, SongEntry.ERR_AUDIO_MISSING)
	decode_count += 1
	var au := AudioLoader.load_song_audio(audio_paths)
	if au["error"] != "":
		return _fail(e, au["error"])
	e.length_sec = au["length"]
	var lo := INF
	var hi := 0.0
	for d in diffs:
		var chart := ChartImporter.build(parsed, d, e.delay_ms)
		e.difficulties.append({"name": d, "note_count": chart.notes.size(),
				"fingerprint": ChartImporter.fingerprint(chart, d, e.length_sec)})
		if not chart.solos.is_empty():
			e.has_solos = true
		for t in chart.tempo_map:
			lo = minf(lo, float(t["bpm"]))
			hi = maxf(hi, float(t["bpm"]))
	e.bpm_min = lo if lo != INF else 0.0
	e.bpm_max = hi
	e.status = "ok"
	return e


## A loose audio file: listed as "Needs a chart" with ID3 or filename title/artist.
static func import_bare(path: String, source: String, library_name: String) -> SongEntry:
	var e := SongEntry.new()
	e.path = path
	e.id = norm(path)
	e.source = source
	e.library_name = library_name
	e.status = "needs_chart"
	e.error = SongEntry.ERR_NEEDS_CHART
	e.fix_hint = SongEntry.hint_for(e.error)
	e.audio_files = [path]
	e.signature = file_signature(path)
	var title := ""
	var artist := ""
	if AudioLoader.detect(path) == "mp3":
		var tags := read_id3(path)
		title = str(tags.get("title", ""))
		artist = str(tags.get("artist", ""))
	if title == "":
		var base := path.get_file().get_basename().replace("_", " ").strip_edges()
		var dash := base.find(" - ")
		if dash > 0:
			if artist == "":
				artist = base.substr(0, dash)
			title = base.substr(dash + 3)
		else:
			title = base
	e.title = SongIni.sanitize_text(title)
	e.artist = SongIni.sanitize_text(artist)
	return e


static func _fail(e: SongEntry, err: String) -> SongEntry:
	e.status = "broken"
	e.error = err
	e.fix_hint = SongEntry.hint_for(err)
	return e


# ---- ID3v2 (bounded) ----

## {title, artist} from an ID3v2.2/2.3/2.4 tag; reads at most 64 KB. {} if none.
static func read_id3(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(10)
	if head.size() < 10 or head.slice(0, 3).get_string_from_ascii() != "ID3":
		f.close()
		return out
	var ver := int(head[3])
	var size := (int(head[6]) & 0x7F) << 21 | (int(head[7]) & 0x7F) << 14 \
			| (int(head[8]) & 0x7F) << 7 | (int(head[9]) & 0x7F)
	size = mini(size, MAX_ID3_BYTES)
	var body := f.get_buffer(size)
	f.close()
	var idlen := 3 if ver == 2 else 4
	var hlen := 6 if ver == 2 else 10
	var pos := 0
	while pos + hlen <= body.size():
		var fid := body.slice(pos, pos + idlen).get_string_from_ascii()
		if fid == "" or body[pos] == 0:
			break
		var fsize := 0
		if ver == 2:
			fsize = int(body[pos + 3]) << 16 | int(body[pos + 4]) << 8 | int(body[pos + 5])
		elif ver == 4:
			fsize = (int(body[pos + 4]) & 0x7F) << 21 | (int(body[pos + 5]) & 0x7F) << 14 \
					| (int(body[pos + 6]) & 0x7F) << 7 | (int(body[pos + 7]) & 0x7F)
		else:
			fsize = int(body[pos + 4]) << 24 | int(body[pos + 5]) << 16 \
					| int(body[pos + 6]) << 8 | int(body[pos + 7])
		if fsize <= 0 or pos + hlen + fsize > body.size():
			break
		var data := body.slice(pos + hlen, pos + hlen + fsize)
		if fid == "TIT2" or fid == "TT2":
			out["title"] = _id3_text(data)
		elif fid == "TPE1" or fid == "TP1":
			out["artist"] = _id3_text(data)
		pos += hlen + fsize
	return out


static func _id3_text(data: PackedByteArray) -> String:
	if data.size() < 2:
		return ""
	var enc := int(data[0])
	var rest := data.slice(1)
	var s := ""
	match enc:
		0:
			for b in rest:
				if b == 0:
					break
				s += char(b)
		3:
			s = rest.get_string_from_utf8()
		1, 2:
			var le := true
			if enc == 1 and rest.size() >= 2:
				if rest[0] == 0xFE and rest[1] == 0xFF:
					le = false
					rest = rest.slice(2)
				elif rest[0] == 0xFF and rest[1] == 0xFE:
					rest = rest.slice(2)
			elif enc == 2:
				le = false
			if not le:
				var swapped := rest.duplicate()
				for i in range(0, swapped.size() - 1, 2):
					swapped[i] = rest[i + 1]
					swapped[i + 1] = rest[i]
				rest = swapped
			s = rest.get_string_from_utf16()
		_:
			return ""
	return s.replace("\u0000", "").strip_edges()


# ---- helpers ----

## Absolute, forward-slash, simplified path; res:// paths are kept as they are.
static func norm(p: String) -> String:
	if p.begins_with("res://"):
		return p
	return ProjectSettings.globalize_path(p).simplify_path().replace("\\", "/")


static func _list(dir: String) -> Dictionary:
	var files: Array[String] = []
	var dirs: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		files.append(f)
	for d in DirAccess.get_directories_at(dir):
		dirs.append(d)
	files.sort()
	dirs.sort()
	return {"files": files, "dirs": dirs}


static func _file_len(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


static func _read_text(path: String, cap: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var b := f.get_buffer(mini(f.get_length(), cap))
	f.close()
	return b.get_string_from_utf8()


static func file_signature(path: String) -> String:
	return "%s:%d:%d" % [path.get_file(), FileAccess.get_modified_time(path), _file_len(path)]


## Names, mtimes and sizes of the chart, ini, midi and audio files, plus any override paths.
static func folder_signature(path: String, audio_override: Array = []) -> String:
	var parts: Array[String] = []
	for f in _list(path)["files"]:
		var ext := String(f).get_extension().to_lower()
		if ext == "chart" or ext == "ini" or ext == "mid" or AudioLoader.AUDIO_EXTS.has(ext):
			parts.append(file_signature(path.path_join(f)))
	for p in audio_override:
		parts.append(file_signature(String(p)))
	return "|".join(parts)


## notes.chart first; else prefer names ending [Y]/[F]/(Y) over [N]; else the first by name.
static func _pick_chart(files: Array[String]) -> String:
	var charts: Array[String] = []
	for f in files:
		if f.get_extension().to_lower() == "chart":
			charts.append(f)
	if charts.is_empty():
		return ""
	for c in charts:
		if c.to_lower() == "notes.chart":
			return c
	for c in charts:
		var base := c.get_basename().to_lower()
		for suf in _TRAILING_PREFERRED:
			if base.ends_with(suf):
				return c
	for c in charts:
		var base2 := c.get_basename().to_lower()
		if not (base2.ends_with("[n]") or base2.ends_with("(n)")):
			return c
	return charts[0]


## Core + optional stems; with no reserved names the first non-preview audio file.
static func _song_audio(files: Array[String]) -> Array[String]:
	var cls := AudioLoader.classify_stems(files)
	var out: Array[String] = []
	for n in cls["core"]:
		out.append(n)
	for n in cls["optional"]:
		out.append(n)
	if out.is_empty():
		for f in files:
			if AudioLoader.is_audio_name(f) and f != cls["preview"]:
				out.append(f)
				break
	return out


static func _rm_tree(dir: String) -> void:
	var d := ProjectSettings.globalize_path(dir) if dir.begins_with("user://") else dir
	if not DirAccess.dir_exists_absolute(d):
		return
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	for sub in DirAccess.get_directories_at(d):
		_rm_tree(d.path_join(sub))
	DirAccess.remove_absolute(d)
