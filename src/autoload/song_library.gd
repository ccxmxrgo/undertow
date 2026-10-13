extends Node
## Autoload "SongLibrary": the song list for song select and the entry point that turns a
## SongEntry + difficulty into a playable ChartData.
##
## The scan runs on one WorkerThreadPool task. The worker only touches SongScanner and
## friends (no tree, no autoloads); results cross threads through a Mutex-guarded queue
## that _process drains within a small per-frame budget.
##
## Signals: scan_started (consumers clear their lists; the calibration entry is re-sent via
## entries_added right after), entries_added(batch), progress(done, total, label),
## scan_finished(count, unplayable) where count excludes the calibration entry.

signal scan_started
signal entries_added(batch: Array)
signal progress(done: int, total: int, label: String)
signal scan_finished(count: int, unplayable: int)

const CACHE_PATH := "user://song_cache.json"
const DEFAULT_SONGS_DIR := "user://songs"
const DRAIN_BUDGET_USEC := 8000

var entries: Array[SongEntry] = []
var scanning: bool = false
## Absolute extra library folders. In the running game these mirror Settings.library_folders
## (refreshed at the start of every rescan); tests assign them directly.
var extra_folders: Array[String] = []
## Last played song/difficulty. Backed by Settings when settings_ref is bound (production),
## plain fields otherwise (tests). Same names and types as before plan 04.
var last_song_id: String = "":
	set(v):
		last_song_id = v
		_persist_last()
var last_difficulty: String = "":
	set(v):
		last_difficulty = v
		_persist_last()
## Non-empty when an extra folder is missing; never blocks the scan.
var folder_error: String = ""
var last_build_error: String = ""
var progress_done: int = 0
var progress_total: int = 0
var progress_label: String = ""

## Test hooks: point the library at temp paths, skip the boot scan, stub the file manager.
var songs_root_override: String = ""
var cache_path: String = CACHE_PATH
var auto_scan: bool = true
var shell_opener: Callable = Callable()
## Settings node that persists library folders and last played. Bound to the Settings autoload
## in _ready only when auto_scan is true (the real game); tests leave it null or inject a fake.
var settings_ref: Node = null
## Harness-only throttle (tools/playtest "songs" scenario): the scan worker sleeps this many ms
## after every progress step so a windowed run can photograph the mid-scan state. Always 0 in the game.
var test_scan_throttle_msec: int = 0
## True while the `--selftest-bundled` user argument runs (exported-build smoke test).
var selftest_bundled: bool = false

static var _calibration_cache: SongEntry

var _mutex := Mutex.new()
var _pending: Array = []
var _task_id: int = -1
var _cancel: bool = false
var _calibration: SongEntry
var _ids := {}
var _loading_last: bool = false


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	# `--no-boot-scan`: the windowed harness points the library at temp folders itself, so the boot
	# scan must not read the player's real Songs folder or write the real song cache.
	if user_args.has("--no-boot-scan"):
		auto_scan = false
	if user_args.has("--selftest-bundled"):
		_begin_selftest()
	if settings_ref == null and (auto_scan or selftest_bundled):
		settings_ref = Settings
	if settings_ref != null:
		extra_folders.assign(settings_ref.library_folders)
		_load_last(settings_ref.last_song_id, settings_ref.last_difficulty)
	_calibration = calibration_entry()
	entries = [_calibration]
	_ids = {_calibration.id: true}
	if selftest_bundled or (auto_scan and DisplayServer.get_name() != "headless"):
		rescan()


func _exit_tree() -> void:
	_cancel = true
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _load_last(sid: String, diff: String) -> void:
	# Loading must not write back to Settings.
	_loading_last = true
	last_song_id = sid
	last_difficulty = diff
	_loading_last = false


func _persist_last() -> void:
	if not _loading_last and settings_ref != null and settings_ref.has_method("set_last_played"):
		settings_ref.set_last_played(last_song_id, last_difficulty)


# ---- public API ----

## Absolute path of the Songs folder (created on demand).
func songs_dir() -> String:
	var p := songs_root_override if songs_root_override != "" else DEFAULT_SONGS_DIR
	var abs_path := ProjectSettings.globalize_path(p).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_path)
	return abs_path


## Opens the Songs folder in the OS file manager. Works with no scan having run.
func open_songs_folder() -> bool:
	var p := songs_dir()
	if not DirAccess.dir_exists_absolute(p):
		return false
	if shell_opener.is_valid():
		return bool(shell_opener.call(p))
	if DisplayServer.get_name() == "headless":
		return true
	return OS.shell_show_in_file_manager(p, true) == OK


func rescan() -> void:
	if scanning:
		return
	if _calibration == null:
		_calibration = calibration_entry()
	folder_error = ""
	if settings_ref != null:
		extra_folders.assign(settings_ref.library_folders)
	var roots: Array = [{"path": songs_dir(), "source": "songs", "library_name": ""}]
	for f in extra_folders:
		if f == "":
			continue
		if not DirAccess.dir_exists_absolute(f):
			folder_error = "Folder not found: " + f
			continue
		roots.append({"path": f, "source": "library", "library_name": f.trim_suffix("/").get_file()})
	_mutex.lock()
	_pending.clear()
	_mutex.unlock()
	entries = [_calibration]
	_ids = {_calibration.id: true}
	scanning = true
	_cancel = false
	progress_done = 0
	progress_total = 0
	progress_label = ""
	scan_started.emit()
	entries_added.emit([_calibration])
	_task_id = WorkerThreadPool.add_task(_scan_task.bind(roots), false, "SongLibrary scan")
	set_process(true)


func find(id: String) -> SongEntry:
	for e in entries:
		if e.id == id:
			return e
	return null


## The built-in hand chart, always listed (D-13). Its record id stays test.hand_chart.v1.
func calibration_entry() -> SongEntry:
	if _calibration_cache == null:
		var hc := TestCharts.hand_chart(8000)
		var e := SongEntry.new()
		e.id = TestCharts.HAND_CHART_ID
		e.source = "test"
		e.title = "Calibration Track"
		e.artist = "Built-in test chart"
		e.status = "ok"
		e.length_sec = hc.audio_stream.get_length() if hc.audio_stream != null else 0.0
		var lo := INF
		var hi := 0.0
		for t in hc.tempo_map:
			lo = minf(lo, float(t["bpm"]))
			hi = maxf(hi, float(t["bpm"]))
		e.bpm_min = lo if lo != INF else 0.0
		e.bpm_max = hi
		e.difficulties = [{"name": "expert", "note_count": hc.notes.size(),
				"fingerprint": TestCharts.HAND_CHART_ID}]
		_calibration_cache = e
	return _calibration_cache


## Re-parses the chart and loads the audio fresh; null with last_build_error on failure.
func build_chart(entry: SongEntry, difficulty: String) -> ChartData:
	last_build_error = ""
	if entry == null:
		last_build_error = "Song not found"
		return null
	if entry.source == "test" and entry.id == TestCharts.HAND_CHART_ID:
		return TestCharts.hand_chart()
	if entry.status != "ok":
		last_build_error = entry.error
		return null
	var stored := entry.difficulty(difficulty)
	if stored.is_empty():
		last_build_error = "Difficulty not available"
		return null
	var parsed := ChartFile.parse(entry.chart_path)
	if not parsed.ok:
		last_build_error = parsed.error
		return null
	if not ChartImporter.difficulties(parsed).has(difficulty):
		last_build_error = SongEntry.ERR_NO_GUITAR
		return null
	var au := AudioLoader.load_song_audio(entry.audio_files)
	if au["error"] != "":
		last_build_error = au["error"]
		return null
	var chart := ChartImporter.build(parsed, difficulty, entry.delay_ms)
	var fp := ChartImporter.fingerprint(chart, difficulty, au["length"])
	if fp != stored["fingerprint"]:
		last_build_error = "Song changed since the last scan. Press Rescan."
		return null
	chart.id = fp
	chart.title = entry.title
	chart.artist = entry.artist
	chart.difficulty = difficulty
	chart.audio_stream = au["stream"]
	return chart


## Audio for the preview player. Thread-safe (no tree access).
func load_audio(entry: SongEntry) -> AudioStream:
	if entry == null or entry.audio_files.is_empty():
		return null
	return AudioLoader.load_song_audio(entry.audio_files)["stream"]


# ---- worker side (no tree, no autoload access) ----

func _scan_task(roots: Array) -> void:
	var cache := SongCache.new(cache_path)
	cache.load()
	var scanner := SongScanner.new()
	var all: Array[SongEntry] = []
	var cancel := func() -> bool: return _cancel
	var bundled: Array = []
	for b in BundledSongs.SONGS:
		if _cancel:
			break
		var e := _import_bundled(b, cache)
		if e != null:
			bundled.append(e)
			all.append(e)
	if not bundled.is_empty():
		_push({"t": "batch", "v": bundled})
	var throttle := test_scan_throttle_msec
	var on_progress := func(done: int, total: int, label: String) -> void:
		_push({"t": "progress", "done": done, "total": total, "label": label})
		if throttle > 0:
			OS.delay_msec(throttle)
	var found := scanner.scan(roots, cache,
			func(batch: Array) -> void: _push({"t": "batch", "v": batch}),
			on_progress,
			cancel)
	all.append_array(found)
	if not _cancel:
		var fresh := SongCache.new(cache_path)
		for e in all:
			fresh.put(e)
		fresh.save()
	_push({"t": "done"})


func _import_bundled(b: Dictionary, cache: SongCache) -> SongEntry:
	var dir := str(b.get("dir", ""))
	var audio := str(b.get("audio", ""))
	if not dir.begins_with("res://") or audio == "" or audio.contains("/") or audio.contains(".."):
		return null
	var audio_path := dir.path_join(audio)
	var sig := bundled_signature(dir, audio_path)
	var id := SongScanner.norm(dir)
	var hit := cache.lookup(id, sig)
	if hit != null:
		hit.source = "bundled"
		return hit
	var e := SongScanner.import_folder(dir, "bundled", "", [audio_path])
	e.id = id
	e.signature = sig
	return e


## Inside an exported .pck the modified time of res:// files is 0, so a game update that changes a
## bundled song.ini or chart without changing its size (e.g. delay 17 -> 48) would keep a stale cache
## entry whose fingerprint no longer matches ("Song changed since the last scan" forever). The MD5 of
## the small chart / ini files makes the signature follow the content.
static func bundled_signature(dir: String, audio_path: String) -> String:
	var parts: Array[String] = [SongScanner.folder_signature(dir, [audio_path])]
	for f in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if ext == "chart" or ext == "ini":
			parts.append("%s=%s" % [f, FileAccess.get_md5(dir.path_join(f))])
	return "|".join(parts)


func _push(item: Dictionary) -> void:
	_mutex.lock()
	_pending.append(item)
	_mutex.unlock()


# ---- main thread drain ----

func _process(_delta: float) -> void:
	if _pending.is_empty() and not scanning:
		set_process(false)
		return
	var start := Time.get_ticks_usec()
	while true:
		_mutex.lock()
		var item: Variant = _pending.pop_front() if not _pending.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		_apply(item)
		if Time.get_ticks_usec() - start > DRAIN_BUDGET_USEC:
			break


func _apply(item: Dictionary) -> void:
	match item["t"]:
		"batch":
			var fresh: Array = []
			for e in item["v"]:
				var se: SongEntry = e
				if _ids.has(se.id):
					continue
				_ids[se.id] = true
				entries.append(se)
				fresh.append(se)
			if not fresh.is_empty():
				entries_added.emit(fresh)
		"progress":
			progress_done = item["done"]
			progress_total = item["total"]
			progress_label = item["label"]
			progress.emit(progress_done, progress_total, progress_label)
		"done":
			if _task_id != -1:
				WorkerThreadPool.wait_for_task_completion(_task_id)
				_task_id = -1
			scanning = false
			var unplayable := 0
			for e in entries:
				if e.source != "test" and e.status != "ok":
					unplayable += 1
			scan_finished.emit(entries.size() - 1, unplayable)


# ---- exported-build self test (`--selftest-bundled`) ----

const SELFTEST_SONGS_DIR := "user://selftest_songs"
const SELFTEST_CACHE := "user://selftest_song_cache.json"


## Uses throwaway paths so the player's Songs folder and song cache are never read or written.
func _begin_selftest() -> void:
	selftest_bundled = true
	songs_root_override = SELFTEST_SONGS_DIR
	cache_path = SELFTEST_CACHE
	scan_finished.connect(_run_selftest, CONNECT_ONE_SHOT)


## Every bundled song and difficulty must build with real audio longer than 1 s.
## Prints `BUNDLED_OK <n>` or `BUNDLED_FAIL <reason>` and quits with 0 / 1.
func _run_selftest(_count: int, _unplayable: int) -> void:
	var fails: Array[String] = []
	var ok_count := 0
	var listed := 0
	for e in entries:
		if e.source != "bundled":
			continue
		listed += 1
		if e.status != "ok":
			fails.append("%s: %s" % [e.title, e.error])
			continue
		for d in e.difficulties:
			var diff: String = d["name"]
			var chart := build_chart(e, diff)
			if chart == null:
				fails.append("%s %s: %s" % [e.title, diff, last_build_error])
			elif chart.audio_stream == null or chart.audio_stream.get_length() <= 1.0:
				fails.append("%s %s: audio missing or too short" % [e.title, diff])
			elif chart.notes.is_empty():
				fails.append("%s %s: no notes" % [e.title, diff])
			else:
				ok_count += 1
	if listed != BundledSongs.SONGS.size():
		fails.append("bundled songs listed %d of %d" % [listed, BundledSongs.SONGS.size()])
	if ok_count == 0 and fails.is_empty():
		fails.append("no bundled difficulties found")
	var abs_cache := ProjectSettings.globalize_path(SELFTEST_CACHE)
	if FileAccess.file_exists(abs_cache):
		DirAccess.remove_absolute(abs_cache)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELFTEST_SONGS_DIR))
	if fails.is_empty():
		print("BUNDLED_OK %d" % ok_count)
	else:
		print("BUNDLED_FAIL %s" % "; ".join(fails))
	if is_inside_tree():
		get_tree().quit(0 if fails.is_empty() else 1)
