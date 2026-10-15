class_name AutochartRunner
extends Node
## Runs the autocharter child process, streams its JSON-line events, cancels it and kills it on
## quit (D-05). Polls both pipes every frame without blocking; maps failures to the player-facing
## error table (D-01).
##
## Result rule (W1): a done event without an error event -> finished(done), when the exit code
## is 0 or a cancel raced the end of the job (the song is installed; WR-01). Otherwise a
## cancelled run emits only cancelled(). Any other outcome is a failure: the last error event's code/log win;
## without one, the exit code decides (0 -> internal, 3 -> memory, 4 -> internal, other -> crash).

signal stage_changed(k: int, n: int, stage_name: String)
signal progress_changed(frac: float)
signal warned(msg: String)
signal event_received(ev: Dictionary)
signal finished(result: Dictionary)
signal failed(code: String, message: String, log_path: String)
signal cancelled()

## Kept for the failure details when the child never wrote a log.
const STDERR_CAP := 65536
## A partial line longer than this is junk (the protocol lines are small); drop it.
const LINE_CAP := 1048576

var adapter: ProcessAdapter = ProcessAdapter.new()

var _running := false
var _cancelled := false
var _out := PackedByteArray()
var _err_tail := PackedByteArray()
var _work_dir := ""
var _error_ev: Dictionary = {}
var _done_ev: Dictionary = {}
var _last_error: Dictionary = {}
var _progress := -1.0


func _init() -> void:
	# Keep draining while the game is paused; a full pipe would stall the child.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start(python_exe: String, args: PackedStringArray) -> bool:
	if _running:
		return false
	_reset()
	if python_exe.is_empty() or not FileAccess.file_exists(python_exe):
		_fail("start", "", "interpreter not found: " + python_exe)
		return false
	for a in args:
		var ext := a.get_extension().to_lower()
		if (ext == "py" or ext == "json") and not AutochartJob.safe_path_arg(a):
			_fail("start", "", "unsafe path argument")
			return false
	var pid := adapter.start(python_exe, args)
	if pid <= 0:
		_fail("start", "", "process could not be started")
		return false
	_running = true
	set_process(true)
	return true


## Only a live child is cancelled: once it has exited (a done event may already be buffered)
## the run finishes normally on the next frame (WR-01).
func cancel() -> void:
	if not _running or _cancelled or not adapter.is_running():
		return
	_cancelled = true
	adapter.kill()


func is_running() -> bool:
	return _running


func work_dir() -> String:
	return _work_dir


func last_error() -> Dictionary:
	return _last_error


func _process(_delta: float) -> void:
	if not _running:
		return
	_drain()
	_dispatch(false)
	if not adapter.is_running():
		_drain()
		_dispatch(true)
		_finish(adapter.exit_code())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _running and adapter != null and adapter.is_running():
			adapter.kill()


func _reset() -> void:
	_cancelled = false
	_out = PackedByteArray()
	_err_tail = PackedByteArray()
	_work_dir = ""
	_error_ev = {}
	_done_ev = {}
	_last_error = {}
	_progress = -1.0


func _drain() -> void:
	_out.append_array(adapter.read_stdout())
	var err := adapter.read_stderr()
	if not err.is_empty():
		_err_tail.append_array(err)
		if _err_tail.size() > STDERR_CAP:
			_err_tail = _err_tail.slice(_err_tail.size() - STDERR_CAP)


func _dispatch(final: bool) -> void:
	var r: Array = AutochartJob.take_lines(_out)
	_out = r[1]
	var lines: PackedStringArray = r[0]
	if final and not _out.is_empty():
		# An event written without a newline right before exit.
		var tail := _out.get_string_from_utf8().strip_edges()
		if not tail.is_empty():
			lines.append(tail)
		_out = PackedByteArray()
	elif _out.size() > LINE_CAP:
		_out = PackedByteArray()
	for line in lines:
		var ev := AutochartJob.parse_event(line)
		if not ev.is_empty():
			_on_event(ev)


func _on_event(ev: Dictionary) -> void:
	match ev["ev"]:
		"stage":
			stage_changed.emit(_int(ev.get("k")), _int(ev.get("n")), _str(ev.get("name")))
		"progress":
			var f = ev.get("frac")
			if f is int or f is float:
				var frac := clampf(float(f), 0.0, 1.0)
				if frac > _progress:
					_progress = frac
					progress_changed.emit(frac)
		"warn":
			warned.emit(_str(ev.get("msg")))
		"work":
			_work_dir = _str(ev.get("dir"))
		"error":
			_error_ev = ev
		"done":
			_done_ev = ev
	event_received.emit(ev)


func _finish(code: int) -> void:
	_running = false
	set_process(false)
	adapter.close()
	# WR-01: a done event means the song was installed; it wins over a cancel that raced it
	# (the kill may land after done was printed, so the exit code is not checked then).
	var done := not _done_ev.is_empty() and _error_ev.is_empty()
	if done and (code == AutochartJob.EXIT_OK or _cancelled):
		finished.emit(_done_ev)
		return
	if _cancelled:
		cancelled.emit()
		return
	if not _error_ev.is_empty():
		_fail(_str(_error_ev.get("code"), "internal"), _str(_error_ev.get("log")),
			_str(_error_ev.get("msg")), code)
		return
	var mapped := "crash"
	match code:
		AutochartJob.EXIT_OK, AutochartJob.EXIT_PARENT_GONE, AutochartJob.EXIT_ERROR:
			mapped = "internal"
		AutochartJob.EXIT_MEMORY:
			mapped = "memory"
	_fail(mapped, "", "exit code %d" % code, code)


func _fail(code: String, log_path: String, detail: String, exit: int = -1) -> void:
	if code.is_empty():
		code = "internal"
	var message := AutochartJob.error_text(code)
	_last_error = {
		"code": code,
		"message": message,
		"log": log_path,
		"detail": detail,
		"exit_code": exit,
		"stderr": _err_tail.get_string_from_utf8(),
	}
	failed.emit(code, message, log_path)


static func _int(v: Variant) -> int:
	return int(v) if (v is int or v is float) else 0


static func _str(v: Variant, fallback: String = "") -> String:
	return v if v is String else fallback
