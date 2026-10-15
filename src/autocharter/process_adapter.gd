class_name ProcessAdapter
extends RefCounted
## Thin wrapper over OS.execute_with_pipe / OS.kill so AutochartRunner can be tested with a fake.
##
## Godot 4.7 on Windows: execute_with_pipe uses CREATE_NO_WINDOW; in non-blocking mode the pipes
## are PIPE_NOWAIT, so get_buffer() returns at once with what is there. OS.kill is
## TerminateProcess on this one PID. The stdio FileAccess must stay referenced for the whole
## run: dropping it closes the child's stdin, and the child's stdin-EOF watchdog then exits.

const READ_CHUNK := 65536
## Per call and pipe; the rest is read on the next frame.
const MAX_DRAIN := 4194304

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


## Reads only what is available right now; never blocks (PIPE_NOWAIT: ReadFile returns the
## bytes that are there, or none). No get_length(): PeekNamedPipe fails on a pipe whose write end
## is closed, and Godot logs an engine error for every call. The job redirects its fd 2 into the
## log at startup and every child closes both pipes at exit, so polling get_length() flooded the
## game log every frame for the whole job (02.2.2-07). get_buffer() on a broken or empty pipe
## just returns nothing.
static func _drain(pipe: FileAccess) -> PackedByteArray:
	var out := PackedByteArray()
	if pipe == null:
		return out
	while out.size() < MAX_DRAIN:
		var b := pipe.get_buffer(READ_CHUNK)
		if b.is_empty():
			break
		out.append_array(b)
		if b.size() < READ_CHUNK:
			break
	return out
