extends GdUnitTestSuite
## ProcessAdapter with a real child process (cmd.exe): non-blocking partial reads, and reads after
## the child exited (both pipes closed on the child side) return nothing at once. Regression for
## 02.2.2-07: _drain used get_length() (PeekNamedPipe), which logs an engine error on every call
## once the child closed a pipe; the job closes its stderr pipe at startup.


func _cmd() -> String:
	var c := OS.get_environment("ComSpec")
	return c if c != "" else "C:/Windows/System32/cmd.exe"


func test_reads_child_output_and_drains_closed_pipes_without_blocking() -> void:
	if OS.get_name() != "Windows":
		return
	var a := ProcessAdapter.new()
	var pid := a.start(_cmd(), PackedStringArray(["/c", "echo adapter-out& echo adapter-err 1>&2"]))
	assert_int(pid).is_greater(0)
	var out := PackedByteArray()
	var err := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while a.is_running() and Time.get_ticks_msec() - t0 < 10000:
		out.append_array(a.read_stdout())
		err.append_array(a.read_stderr())
		await get_tree().process_frame
	assert_bool(a.is_running()).is_false()
	out.append_array(a.read_stdout())
	err.append_array(a.read_stderr())
	assert_str(out.get_string_from_utf8()).contains("adapter-out")
	assert_str(err.get_string_from_utf8()).contains("adapter-err")
	# The child is gone: both pipes are broken. Reads return empty immediately, many times over.
	var t1 := Time.get_ticks_msec()
	for i in 200:
		assert_int(a.read_stdout().size()).is_equal(0)
		assert_int(a.read_stderr().size()).is_equal(0)
	assert_int(Time.get_ticks_msec() - t1).is_less(1000)
	assert_int(a.exit_code()).is_equal(0)
	a.close()


func test_large_output_is_read_across_chunks() -> void:
	if OS.get_name() != "Windows":
		return
	var a := ProcessAdapter.new()
	# About 200 KB on stdout (more than one READ_CHUNK and more than the pipe buffer).
	var pid := a.start(_cmd(), PackedStringArray(["/c",
		"for /L %i in (1,1,4000) do @echo line-%i-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]))
	assert_int(pid).is_greater(0)
	var out := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while a.is_running() and Time.get_ticks_msec() - t0 < 20000:
		out.append_array(a.read_stdout())
		await get_tree().process_frame
	out.append_array(a.read_stdout())
	var text := out.get_string_from_utf8()
	assert_str(text).contains("line-1-")
	assert_str(text).contains("line-4000-")
	assert_int(text.count("\n")).is_equal(4000)
	a.close()
