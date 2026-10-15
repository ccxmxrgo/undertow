extends SceneTree
## DEV-ONLY (tools/* is not exported): end-to-end run of the real Autocharter pack through the
## game's own classes (02.2.2-07). PackInstaller installs the part zips from a folder ("Install
## from Folder": same size + SHA-256 checks against PackSpec), AutochartRunner with the real
## ProcessAdapter runs the selftest and real jobs, one job is cancelled, and SongScanner checks
## the generated song folders.
##
## Usage (repo root; relative paths are resolved against the project folder):
##   & $env:GODOT_BIN --headless --path . -s res://tools/autochart/pack_e2e.gd -- `
##       --source build/pack/out --root build/pack/e2e_ac --songs build/pack/e2e_songs --threads 8 `
##       [--only install|selftest|job|rechart|lanes|cancel|scan|probe]
## --only probe (02.2.2-10) is not part of the full run: it starts a real download through
## PackInstaller's default HTTP fetcher and the compiled PackSpec URLs into a scratch root
## (default build/pack/probe_ac) and prints PROBE_NOT_AVAILABLE (the pinned URL answers 404: the
## release is not published yet), PROBE_DOWNLOAD_STARTED (bytes arrived; the download is
## cancelled at once) or PROBE_FAIL <code>. The scratch root is deleted afterwards.
## The pack root is always --root (AutochartPaths.root_override); the player's real
## %LOCALAPPDATA%\UNDERTOW\ac is never used. Each step prints one result line; a failing step
## prints E2E_FAIL <step> <reason> and exits 1. The last line of a full run is E2E_OK.

const STEPS: Array[String] = ["install", "selftest", "job", "rechart", "lanes", "cancel", "scan"]
const SONG_SRC := "res://songs/synth_wave_april/song.mp3"
const CANCEL_SRC := "res://songs/space_synth_wave/song.wav"
const CANCEL_COPY := "build/pack/e2e_src/space.wav"
const INSTALL_TIMEOUT_S := 1800.0
const SELFTEST_TIMEOUT_S := 300.0
const JOB_TIMEOUT_S := 900.0
const RECHART_MAX_S := 20.0
const CANCEL_DELAY_S := 3.0
const CANCEL_GONE_MAX_S := 15.0
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]
const PROBE_ROOT := "build/pack/probe_ac"
const PROBE_TIMEOUT_S := 60.0

var _source := "build/pack/out"
var _root := "build/pack/e2e_ac"
var _songs := "build/pack/e2e_songs"
var _threads := 8
var _only := ""
var _root_given := false

var _installer: PackInstaller
var _ranking: Array = []


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var code: int = await _run()
	quit(code)


func _run() -> int:
	var err := _parse_args(OS.get_cmdline_user_args())
	if err != "":
		return _fail("args", err)
	if _only == "probe":
		return await _probe()
	AutochartPaths.root_override = _root
	DirAccess.make_dir_recursive_absolute(_songs)
	print("E2E_CONFIG root=%s songs=%s threads=%d only=%s" % [_rel(AutochartPaths.root()), _rel(_songs),
		_threads, _only if _only != "" else "all"])
	_installer = PackInstaller.new()
	root.add_child(_installer)
	await process_frame
	for step in STEPS:
		if _only != "" and step != _only:
			continue
		var code: int = await call("_step_" + step)
		if code != 0:
			return code
	if _only == "":
		print("E2E_OK")
	return 0


func _parse_args(args: PackedStringArray) -> String:
	var i := 0
	while i < args.size():
		var a := String(args[i])
		var v := String(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--source":
				_source = v
			"--root":
				_root = v
				_root_given = true
			"--songs":
				_songs = v
			"--threads":
				_threads = int(v)
			"--only":
				_only = v
			_:
				return "unknown argument " + a
		i += 2
	if _only == "probe" and not _root_given:
		_root = PROBE_ROOT
	if _only != "" and _only != "probe" and not STEPS.has(_only):
		return "unknown step " + _only
	if _threads < 1 or _threads > 64:
		return "threads out of range"
	_source = _abs(_source)
	_root = _abs(_root)
	_songs = _abs(_songs)
	var lad := OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()
	if lad != "" and _root.to_lower().begins_with(lad):
		return "refusing a pack root under LOCALAPPDATA"
	return ""


# ---- steps ----

func _step_install() -> int:
	var t0 := Time.get_ticks_msec()
	var st := {"result": "", "code": "", "msg": "", "files": 0}
	_installer.source_dir = _source
	var on_ok := func() -> void:
		st["result"] = "ok"
	var on_fail := func(code: String, msg: String) -> void:
		st["result"] = "failed"
		st["code"] = code
		st["msg"] = msg
	var on_progress := func(_done: int, total: int, label: String) -> void:
		if label.begins_with("Installing"):
			st["files"] = total
	var on_state := func(s: String) -> void:
		print("E2E_INSTALL_STATE %s +%.1f" % [s, _since(t0)])
	_installer.installed.connect(on_ok)
	_installer.failed.connect(on_fail)
	_installer.progress_changed.connect(on_progress)
	_installer.state_changed.connect(on_state)
	_installer.start()
	while st["result"] == "" and _since(t0) < INSTALL_TIMEOUT_S:
		await process_frame
	_installer.installed.disconnect(on_ok)
	_installer.failed.disconnect(on_fail)
	_installer.progress_changed.disconnect(on_progress)
	_installer.state_changed.disconnect(on_state)
	if st["result"] != "ok":
		return _fail("install", "%s %s" % [st["code"], st["msg"]] if st["result"] != "" else "timeout")
	if not _installer.is_installed():
		return _fail("install", "is_installed() false after install")
	if not FileAccess.file_exists(AutochartPaths.python_exe()):
		return _fail("install", "interpreter missing")
	print("E2E_INSTALL_OK %.1f %d" % [_since(t0), int(st["files"])])
	return 0


func _step_selftest() -> int:
	if not _installer.is_installed():
		return _fail("selftest", "pack not installed")
	var args := AutochartJob.build_args(AutochartPaths.app_dir(), "selftest")
	var r: Dictionary = await _run_child(args, "", SELFTEST_TIMEOUT_S)
	if r["state"] != "finished_selftest":
		return _fail("selftest", _why(r))
	_installer.mark_selftest(true)
	if not _installer.selftest_ok():
		return _fail("selftest", "marker not updated")
	print("E2E_SELFTEST_OK %.1f (child reported %s s)" % [r["seconds"], str(r["selftest"].get("seconds", "?"))])
	return 0


func _step_job() -> int:
	var src := _abs(SONG_SRC)
	var r: Dictionary = await _run_job("job", src, "Synth Wave April", "auto", "other", "")
	if r["state"] != "finished":
		return _fail("job", _why(r))
	var d: Dictionary = r["done"]
	_ranking = d.get("ranking", [])
	print("E2E_JOB_OK %s %s %s %.1f threads=%d reused=%s ranking=%s" % [_rel(str(d.get("folder"))),
		str(d.get("stem")), str(d.get("expert_nps")), r["seconds"], _threads, str(d.get("reused")),
		",".join(PackedStringArray(_ranking))])
	print("E2E_WORK %s" % _rel(str(r["work"])))
	return 0


func _step_rechart() -> int:
	var stem := "bass"
	if _ranking.size() > 1:
		stem = str(_ranking[1])
	var r: Dictionary = await _run_job("rechart", _abs(SONG_SRC), "Synth Wave April", "single", stem, "")
	if r["state"] != "finished":
		return _fail("rechart", _why(r))
	var d: Dictionary = r["done"]
	if not bool(d.get("reused", false)):
		return _fail("rechart", "stems were not reused")
	if float(r["seconds"]) >= RECHART_MAX_S:
		return _fail("rechart", "took %.1f s (limit %.0f s)" % [r["seconds"], RECHART_MAX_S])
	print("E2E_RECHART_OK %s %.1f folder=%s expert_nps=%s" % [str(d.get("stem")), r["seconds"],
		_rel(str(d.get("folder"))), str(d.get("expert_nps"))])
	return 0


func _step_lanes() -> int:
	var r: Dictionary = await _run_job("lanes", _abs(SONG_SRC), "Synth Wave April", "lanes", "other", "")
	if r["state"] != "finished":
		return _fail("lanes", _why(r))
	var d: Dictionary = r["done"]
	print("E2E_LANES_OK %.1f folder=%s stem=%s reused=%s expert_nps=%s" % [r["seconds"],
		_rel(str(d.get("folder"))), str(d.get("stem")), str(d.get("reused")), str(d.get("expert_nps"))])
	return 0


func _step_cancel() -> int:
	var copy := _abs(CANCEL_COPY)
	DirAccess.make_dir_recursive_absolute(copy.get_base_dir())
	if DirAccess.copy_absolute(_abs(CANCEL_SRC), copy) != OK:
		return _fail("cancel", "could not copy the cancel source")
	var r: Dictionary = await _run_job("cancel", copy, "Space Synth Wave", "auto", "other", "separate")
	if r["state"] != "cancelled":
		return _fail("cancel", "expected cancelled, got " + _why(r))
	var pid := int(r["pid"])
	if pid <= 0:
		return _fail("cancel", "no start event pid")
	if int(r["spawned_pid"]) != pid:
		return _fail("cancel", "start pid %d != spawned pid %d" % [pid, int(r["spawned_pid"])])
	# TerminateProcess is asynchronous: the exit code is set at once (the runner reports cancelled)
	# while Windows still frees the process memory. The PID must leave the process table shortly.
	var re := RegEx.create_from_string("\\s%d\\s" % pid)
	var t_gone := Time.get_ticks_msec()
	var text := ""
	var seen_after_cancelled := 0
	while true:
		var out: Array = []
		OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH"], out)
		text = "".join(PackedStringArray(out))
		if re.search(text) == null:
			break
		seen_after_cancelled += 1
		if _since(t_gone) > CANCEL_GONE_MAX_S:
			return _fail("cancel", "process %d still in the process table %.0f s after cancelled: %s" % [pid,
				CANCEL_GONE_MAX_S, text.strip_edges()])
		await create_timer(0.1).timeout
	print("E2E_CANCEL_OK pid=%d cancel_requested=+%.1f cancelled=+%.1f gone_after=%.1f s (polls %d; tasklist: %s)" % [
		pid, r["seconds"], float(r.get("cancelled_s", -1.0)), _since(t_gone), seen_after_cancelled,
		text.strip_edges().replace("\r", " ").replace("\n", " ")])
	return 0


func _step_scan() -> int:
	var scanner := SongScanner.new()
	var entries: Array[SongEntry] = scanner.scan_sync([{"path": _songs, "source": "songs", "library_name": ""}])
	if entries.is_empty():
		return _fail("scan", "no songs found in " + _rel(_songs))
	for e in entries:
		var name := e.path.trim_suffix("/").get_file()
		if e.status != "ok":
			return _fail("scan", "%s status %s: %s" % [name, e.status, e.error])
		var names: Array[String] = []
		for dd in e.difficulties:
			names.append(str(dd["name"]))
		for d in DIFFS:
			if not names.has(d):
				return _fail("scan", "%s missing difficulty %s" % [name, d])
		var parsed := ChartFile.parse(e.chart_path)
		if not parsed.ok:
			return _fail("scan", "%s chart parse: %s" % [name, parsed.error])
		var lanes_used := {}
		for d in DIFFS:
			var chart := ChartImporter.build(parsed, d, e.delay_ms)
			for n in chart.notes:
				var lane := int(n["lane"])
				if lane < 0 or lane > 3:
					return _fail("scan", "%s %s lane %d outside 0..3" % [name, d, lane])
				lanes_used[lane] = true
		var counts := PackedStringArray()
		for dd in e.difficulties:
			counts.append("%s=%d" % [dd["name"], int(dd["note_count"])])
		print("E2E_SCAN_SONG %s status=ok delay=%d length=%.1f lanes=%d %s" % [name, e.delay_ms,
			e.length_sec, lanes_used.size(), " ".join(counts)])
	print("E2E_SCAN_OK %d" % entries.size())
	return 0


# ---- child runs ----

func _run_job(tag: String, src: String, name: String, mode: String, stem: String, cancel_at: String) -> Dictionary:
	var job := AutochartJob.make_job(src, name, "UNDERTOW e2e", mode, stem, _songs,
		AutochartPaths.work_root(), AutochartPaths.models_dir(), _threads)
	var v := AutochartJob.validate(job)
	if v != "":
		return {"state": "invalid", "code": v, "msg": "job did not validate"}
	var dir := AutochartWorkCache.new_job_dir(AutochartPaths.work_root())
	if dir == "":
		return {"state": "invalid", "code": "disk", "msg": "no job dir"}
	var job_path := dir.path_join("job.json")
	if AutochartJob.write_job(job_path, job) != OK:
		return {"state": "invalid", "code": "disk", "msg": "job.json not written"}
	print("E2E_RUN %s mode=%s stem=%s threads=%d" % [tag, mode, stem, _threads])
	return await _run_child(AutochartJob.build_args(AutochartPaths.app_dir(), "job", job_path), cancel_at,
		JOB_TIMEOUT_S)


## Runs one child through AutochartRunner + the real ProcessAdapter. cancel_at: runner.cancel()
## is called CANCEL_DELAY_S after this stage starts ("" = never).
func _run_child(args: PackedStringArray, cancel_at: String, timeout_s: float) -> Dictionary:
	var runner := AutochartRunner.new()
	root.add_child(runner)
	var t0 := Time.get_ticks_msec()
	var r := {"state": "", "done": {}, "code": "", "msg": "", "log": "", "pid": -1, "spawned_pid": -1,
		"selftest": {}, "work": "", "seconds": 0.0, "stderr": "", "cancel_t": -1, "cancel_sent": false}
	runner.finished.connect(func(res: Dictionary) -> void:
		r["state"] = "finished"
		r["done"] = res)
	runner.failed.connect(func(code: String, msg: String, log_path: String) -> void:
		r["state"] = "failed"
		r["code"] = code
		r["msg"] = msg
		r["log"] = log_path)
	runner.cancelled.connect(func() -> void:
		r["cancelled_s"] = _since(t0)
		r["state"] = "cancelled")
	runner.stage_changed.connect(func(k: int, n: int, stage_name: String) -> void:
		print("E2E_STAGE %d/%d %s +%.1f" % [k, n, stage_name, _since(t0)])
		if cancel_at != "" and stage_name == cancel_at and int(r["cancel_t"]) < 0:
			r["cancel_t"] = Time.get_ticks_msec())
	runner.warned.connect(func(msg: String) -> void:
		print("E2E_WARN %s" % msg))
	runner.event_received.connect(_on_event.bind(r, runner))
	var ok := runner.start(AutochartPaths.python_exe(), args)
	if not ok and r["state"] == "":
		r["state"] = "failed"
		r["msg"] = "start returned false"
	while r["state"] == "" and _since(t0) < timeout_s:
		# Cancel CANCEL_DELAY_S into the cancel stage, while the separator is busy (torch threads up).
		if int(r["cancel_t"]) >= 0 and not r["cancel_sent"] and _since(int(r["cancel_t"])) >= CANCEL_DELAY_S:
			r["cancel_sent"] = true
			r["seconds"] = _since(t0)
			print("E2E_CANCEL_REQUEST in %s +%.1f" % [cancel_at, _since(t0)])
			runner.cancel()
		await process_frame
	if r["state"] == "":
		runner.cancel()
		while runner.is_running():
			await process_frame
		r["state"] = "timeout"
	if r["state"] != "cancelled":
		r["seconds"] = _since(t0)
	if r["state"] == "failed":
		r["stderr"] = str(runner.last_error().get("stderr", ""))
	# The selftest exits 0 with a selftest event and no done event, which the runner reports as
	# failed("internal", exit 0). An ok selftest event + exit 0 is the selftest's success.
	var st_ok := bool((r["selftest"] as Dictionary).get("ok", false))
	if st_ok and (r["state"] == "finished" or (r["state"] == "failed"
			and int(runner.last_error().get("exit_code", -1)) == AutochartJob.EXIT_OK)):
		r["state"] = "finished_selftest"
	runner.queue_free()
	await process_frame
	return r


func _on_event(ev: Dictionary, r: Dictionary, runner: AutochartRunner) -> void:
	match str(ev.get("ev")):
		"start":
			r["pid"] = int(ev.get("pid", -1))
			r["spawned_pid"] = runner.adapter._pid
		"work":
			r["work"] = str(ev.get("dir"))
		"rank":
			print("E2E_RANK recommended=%s ranking=%s" % [str(ev.get("recommended")),
				",".join(PackedStringArray(ev.get("ranking", [])))])
		"selftest":
			r["selftest"] = ev


# ---- probe (02.2.2-10): the real download path against the pinned release URLs ----

func _probe() -> int:
	AutochartPaths.root_override = _root
	print("PROBE_CONFIG root=%s url=%s" % [_rel(AutochartPaths.root()), PackSpec.url(PackSpec.PARTS[0])])
	var inst := PackInstaller.new()  # default HTTP fetcher, compiled PackSpec
	root.add_child(inst)
	await process_frame
	var st := {"result": "", "code": "", "msg": "", "bytes": 0}
	var on_ok := func() -> void:
		st["result"] = "installed"
	var on_fail := func(code: String, msg: String) -> void:
		st["result"] = "failed"
		st["code"] = code
		st["msg"] = msg
	var on_progress := func(done: int, _total: int, label: String) -> void:
		if label.begins_with("Downloading") and done > 0 and st["result"] == "":
			st["result"] = "bytes"
			st["bytes"] = done
	inst.installed.connect(on_ok)
	inst.failed.connect(on_fail)
	inst.progress_changed.connect(on_progress)
	var t0 := Time.get_ticks_msec()
	inst.start()
	while st["result"] == "" and _since(t0) < PROBE_TIMEOUT_S:
		await process_frame
	var code := 0
	match str(st["result"]):
		"bytes":
			inst.cancel()
			print("PROBE_DOWNLOAD_STARTED %d bytes after %.1f s (cancelled)" % [int(st["bytes"]), _since(t0)])
		"failed":
			if st["code"] == "not_available":
				print("PROBE_NOT_AVAILABLE %.1f s: %s" % [_since(t0), str(st["msg"])])
			else:
				print("PROBE_FAIL %s %s" % [str(st["code"]), str(st["msg"])])
				code = 1
		"installed":
			print("PROBE_FAIL installed (the scratch root already held the pack)")
			code = 1
		_:
			inst.cancel()
			print("PROBE_FAIL timeout %.0f s" % PROBE_TIMEOUT_S)
			code = 1
	inst.queue_free()
	await process_frame
	_rm_tree(_root)
	return code


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ---- helpers ----

func _fail(step: String, reason: String) -> int:
	print("E2E_FAIL %s %s" % [step, reason])
	return 1


func _why(r: Dictionary) -> String:
	var s := "%s %s %s" % [str(r.get("state")), str(r.get("code", "")), str(r.get("msg", ""))]
	if str(r.get("log", "")) != "":
		s += " log=" + _rel(str(r["log"]))
	var err := str(r.get("stderr", "")).strip_edges()
	if err != "":
		s += " stderr_tail=" + err.right(600).replace("\n", " | ")
	return s


func _since(t0: int) -> float:
	return float(Time.get_ticks_msec() - t0) / 1000.0


static func _abs(p: String) -> String:
	var g := p
	if p.begins_with("res://") or p.begins_with("user://"):
		g = ProjectSettings.globalize_path(p)
	elif not p.is_absolute_path():
		g = ProjectSettings.globalize_path("res://").path_join(p)
	return g.replace("\\", "/").simplify_path()


## Repo-relative path for the printout (no user profile paths in the committed report).
static func _rel(p: String) -> String:
	var repo := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path()
	var q := p.replace("\\", "/")
	if q.to_lower().begins_with(repo.to_lower() + "/"):
		return "<repo>/" + q.substr(repo.length() + 1)
	return q
