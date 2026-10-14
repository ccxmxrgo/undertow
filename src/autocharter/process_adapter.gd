class_name ProcessAdapter
extends RefCounted
## Thin wrapper over OS.execute_with_pipe / OS.kill so AutochartRunner can be tested with a fake.
##
## Godot 4.7 on Windows: execute_with_pipe uses CREATE_NO_WINDOW; in non-blocking mode the pipes
## are PIPE_NOWAIT and get_length() is PeekNamedPipe, so reads never block. OS.kill is
## TerminateProcess on this one PID. The stdio FileAccess must stay referenced for the whole
## run: dropping it closes the child's stdin, and the child's stdin-EOF watchdog then exits.

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess


## Returns the child's pid, or -1 when the process could not be started.
func start(exe: String, args: PackedStringArray) -> int:
	close()
	var info: Dictionary = OS.execute_with_pipe(exe, args, false)
	if info.is_empty():
		_pid = -1
		return -1
	_pid = int(info.get("pid", -1))
	_stdio = info.get("stdio")
	_stderr = info.get("stderr")
	return _pid


func read_stdout() -> PackedByteArray:
	return _drain(_stdio)


func read_stderr() -> PackedByteArray:
	return _drain(_stderr)


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func exit_code() -> int:
	if _pid <= 0:
		return -1
	return OS.get_process_exit_code(_pid)


func kill() -> void:
	if is_running():
		OS.kill(_pid)


## Drops the pipe references. Only once the process is gone (closing stdio early would end
## the child through its stdin watchdog, and Windows keeps handles until the process exits).
func close() -> void:
	if is_running():
		return
	_stdio = null
	_stderr = null


## Reads only what is available right now; never blocks.
static func _drain(pipe: FileAccess) -> PackedByteArray:
	if pipe == null:
		return PackedByteArray()
	var n := pipe.get_length()
	if n <= 0:
		return PackedByteArray()
	return pipe.get_buffer(n)
