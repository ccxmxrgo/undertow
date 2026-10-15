extends GdUnitTestSuite
## AutochartRunner with a scripted fake process: per-frame drain, event dispatch, exit mapping,
## cancel, quit/free kill (D-05, D-01).


class FakeAdapter extends ProcessAdapter:
	var pid := 4242
	## One entry is returned per read_stdout() call; empty once exhausted.
	var chunks: Array = []
	var stderr_chunks: Array = []
	var running := true
	var code := 0
	var kill_count := 0
	var stderr_reads := 0
	var close_count := 0
	var started_exe := ""
	var started_args := PackedStringArray()

	func start(exe: String, args: PackedStringArray) -> int:
		started_exe = exe
		started_args = args
		return pid

	func read_stdout() -> PackedByteArray:
		if chunks.is_empty():
			return PackedByteArray()
		return (chunks.pop_front() as String).to_utf8_buffer()

	func read_stderr() -> PackedByteArray:
		stderr_reads += 1
		if stderr_chunks.is_empty():
			return PackedByteArray()
		return (stderr_chunks.pop_front() as String).to_utf8_buffer()

	func is_running() -> bool:
		return running

	func exit_code() -> int:
		return code

	func kill() -> void:
		kill_count += 1

	func close() -> void:
		close_count += 1


var _runner: AutochartRunner
var _fake: FakeAdapter
var _stages: Array = []
var _progress: Array = []
var _warns: Array = []
var _events: Array = []
var _finished: Array = []
var _failed: Array = []
var _cancelled := 0


func before_test() -> void:
	_stages = []
	_progress = []
	_warns = []
	_events = []
	_finished = []
	_failed = []
	_cancelled = 0
	_fake = FakeAdapter.new()
	_runner = auto_free(AutochartRunner.new())
	_runner.adapter = _fake
	_runner.stage_changed.connect(func(k: int, n: int, s: String) -> void: _stages.append([k, n, s]))
	_runner.progress_changed.connect(func(f: float) -> void: _progress.append(f))
	_runner.warned.connect(func(m: String) -> void: _warns.append(m))
	_runner.event_received.connect(func(ev: Dictionary) -> void: _events.append(ev))
	_runner.finished.connect(func(r: Dictionary) -> void: _finished.append(r))
	_runner.failed.connect(func(c: String, m: String, l: String) -> void: _failed.append([c, m, l]))
	_runner.cancelled.connect(func() -> void: _cancelled += 1)


func _python() -> String:
	# Any file that exists stands in for the interpreter.
	return OS.get_executable_path()


func _start() -> void:
	var args := AutochartJob.build_args("C:/ac/v1/app", "job", "C:/ac/work/jobs/1/job.json")
	assert_bool(_runner.start(_python(), args)).is_true()


func _frame() -> void:
	_runner._process(0.016)


func test_start_passes_argv_to_adapter() -> void:
	_start()
	assert_bool(_runner.is_running()).is_true()
	assert_str(_fake.started_exe).is_equal(_python())
	assert_int(_fake.started_args.size()).is_equal(7)


func test_stage_and_progress_split_across_frames() -> void:
	_start()
	_fake.chunks = ["{\"ev\":\"stage\",\"k\":2,\"n\":8,\"na", "me\":\"separate\"}\n{\"ev\":\"progress\",\"frac\":0.37}\n"]
	_frame()
	assert_array(_stages).is_empty()
	_frame()
	assert_array(_stages).is_equal([[2, 8, "separate"]])
	assert_int(_progress.size()).is_equal(1)
	assert_float(_progress[0]).is_equal_approx(0.37, 0.0001)
	_frame()
	assert_int(_stages.size()).is_equal(1)
	assert_int(_progress.size()).is_equal(1)
	assert_int(_events.size()).is_equal(2)


func test_progress_clamped_and_monotonic() -> void:
	_start()
	_fake.chunks = ["{\"ev\":\"progress\",\"frac\":0.5}\n{\"ev\":\"progress\",\"frac\":0.2}\n{\"ev\":\"progress\",\"frac\":7}\n{\"ev\":\"progress\",\"frac\":\"x\"}\n"]
	_frame()
	assert_array(_progress).is_equal([0.5, 1.0])


func test_warn_and_work_events() -> void:
	_start()
	_fake.chunks = ["junk line\n{\"ev\":\"work\",\"dir\":\"C:/ac/work/jobs/1\"}\n{\"ev\":\"warn\",\"msg\":\"low\"}\n"]
	_frame()
	assert_str(_runner.work_dir()).is_equal("C:/ac/work/jobs/1")
	assert_array(_warns).is_equal(["low"])


func test_stderr_drained_every_frame() -> void:
	_start()
	_fake.stderr_chunks = ["noise\n"]
	for i in 5:
		_frame()
	assert_int(_fake.stderr_reads).is_greater_equal(5)


func test_exit_zero_with_done_finishes() -> void:
	_start()
	_fake.chunks = ["{\"ev\":\"done\",\"folder\":\"C:/songs/x\",\"slug\":\"x\",\"stem\":\"other\"}\n"]
	_frame()
	_fake.running = false
	_fake.code = 0
	_frame()
	assert_int(_finished.size()).is_equal(1)
	assert_str(_finished[0]["folder"]).is_equal("C:/songs/x")
	assert_array(_failed).is_empty()
	assert_bool(_runner.is_running()).is_false()
	assert_int(_fake.close_count).is_equal(1)
	_frame()
	assert_int(_finished.size()).is_equal(1)


func test_exit_zero_without_done_is_internal() -> void:
	_start()
	_fake.running = false
	_fake.code = 0
	_frame()
	assert_array(_finished).is_empty()
	assert_int(_failed.size()).is_equal(1)
	assert_str(_failed[0][0]).is_equal("internal")


func test_exit_two_with_error_event() -> void:
	_start()
	_fake.chunks = ["{\"ev\":\"error\",\"code\":\"too_long\",\"stage\":\"decode\",\"msg\":\"712 s\",\"log\":\"C:/w/1/log.txt\"}\n"]
	_frame()
	_fake.running = false
	_fake.code = 2
	_frame()
	assert_array(_failed).is_equal([["too_long", AutochartJob.ERROR_TEXT["too_long"], "C:/w/1/log.txt"]])
	assert_str(_runner.last_error()["code"]).is_equal("too_long")


func test_exit_code_mapping_without_error_event() -> void:
	for pair in [[3, "memory"], [7, "crash"], [4, "internal"], [1, "crash"]]:
		before_test()
		_start()
		_fake.running = false
		_fake.code = pair[0]
		_frame()
		assert_int(_failed.size()).override_failure_message(str(pair)).is_equal(1)
		assert_str(_failed[0][0]).override_failure_message(str(pair)).is_equal(pair[1])
		assert_str(_failed[0][1]).is_equal(AutochartJob.error_text(pair[1]))


func test_error_event_wins_over_any_nonzero_exit() -> void:
	for exit in [1, 7, 3]:
		before_test()
		_start()
		_fake.chunks = ["{\"ev\":\"error\",\"code\":\"decode\",\"log\":\"C:/w/a.txt\"}\n{\"ev\":\"error\",\"code\":\"internal\",\"log\":\"C:/w/log.txt\"}\n"]
		_frame()
		_fake.running = false
		_fake.code = exit
		_frame()
		assert_array(_failed).override_failure_message(str(exit)).is_equal(
			[["internal", AutochartJob.ERROR_TEXT["internal"], "C:/w/log.txt"]])


func test_cancel_kills_once_and_emits_cancelled_only() -> void:
	_start()
	_frame()
	_runner.cancel()
	_runner.cancel()
	assert_int(_fake.kill_count).is_equal(1)
	assert_int(_cancelled).is_equal(0)
	_frame()
	assert_int(_cancelled).is_equal(0)
	_fake.running = false
	_fake.code = 1
	_frame()
	assert_int(_cancelled).is_equal(1)
	assert_array(_failed).is_empty()
	assert_array(_finished).is_empty()


## WR-01: the child already exited after printing done; a cancel pressed now does nothing and
## the run finishes with the installed song.
func test_cancel_after_exit_with_done_still_finishes() -> void:
	_start()
	_fake.chunks.append('{"ev":"done","folder":"C:/s/x","slug":"x"}\n')
	_fake.running = false
	_fake.code = 0
	_runner.cancel()
	assert_int(_fake.kill_count).is_equal(0)
	_frame()
	assert_int(_cancelled).is_equal(0)
	assert_int(_finished.size()).is_equal(1)


## WR-01: the kill lands after done was printed (install finished): done wins over the cancel.
func test_done_wins_over_a_cancel_that_raced_it() -> void:
	_start()
	_fake.chunks.append('{"ev":"done","folder":"C:/s/x","slug":"x"}\n')
	_frame()
	_runner.cancel()
	assert_int(_fake.kill_count).is_equal(1)
	_fake.running = false
	_fake.code = 1
	_frame()
	assert_int(_cancelled).is_equal(0)
	assert_array(_failed).is_empty()
	assert_int(_finished.size()).is_equal(1)
	assert_str(_finished[0]["slug"]).is_equal("x")


func test_cancel_with_exit_four_is_not_failure() -> void:
	_start()
	_runner.cancel()
	_fake.running = false
	_fake.code = 4
	_frame()
	assert_int(_cancelled).is_equal(1)
	assert_array(_failed).is_empty()


func test_close_request_kills_running_child() -> void:
	_start()
	_runner.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_fake.kill_count).is_equal(1)


func test_predelete_kills_running_child() -> void:
	var fake := FakeAdapter.new()
	var r := AutochartRunner.new()
	r.adapter = fake
	assert_bool(r.start(_python(), AutochartJob.build_args("C:/ac/app", "selftest"))).is_true()
	r.free()
	assert_int(fake.kill_count).is_equal(1)


func test_no_kill_when_not_running() -> void:
	_runner.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_runner.cancel()
	assert_int(_fake.kill_count).is_equal(0)


func test_start_failure_emits_start() -> void:
	_fake.pid = -1
	var ok := _runner.start(_python(), AutochartJob.build_args("C:/ac/app", "selftest"))
	assert_bool(ok).is_false()
	assert_bool(_runner.is_running()).is_false()
	assert_array(_failed).is_equal([["start", AutochartJob.ERROR_TEXT["start"], ""]])


func test_start_rejects_missing_interpreter_and_unsafe_paths() -> void:
	assert_bool(_runner.start("C:/definitely/not/here/python.exe",
		AutochartJob.build_args("C:/ac/app", "selftest"))).is_false()
	assert_bool(_runner.start(_python(),
		PackedStringArray(["-I", "-u", "C:/ac/app/autochart.py", "job", "C:/a\"b/job.json"]))).is_false()
	assert_bool(_runner.start(_python(),
		PackedStringArray(["-I", "-u", "rel/autochart.py", "selftest"]))).is_false()
	assert_str(_fake.started_exe).is_empty()
	assert_int(_failed.size()).is_equal(3)
	assert_str(_failed[0][0]).is_equal("start")


func test_final_drain_delivers_event_written_at_exit() -> void:
	_start()
	# Frame read returns nothing; the process is already gone; the final drain gets the done line.
	_fake.chunks = ["", "{\"ev\":\"done\",\"folder\":\"C:/songs/y\"}\n"]
	_fake.running = false
	_fake.code = 0
	_frame()
	assert_int(_finished.size()).is_equal(1)
	assert_str(_finished[0]["folder"]).is_equal("C:/songs/y")


func test_final_unterminated_line_is_parsed() -> void:
	_start()
	_fake.chunks = ["{\"ev\":\"done\",\"folder\":\"C:/songs/z\"}"]
	_fake.running = false
	_frame()
	assert_int(_finished.size()).is_equal(1)


func test_stderr_tail_capped() -> void:
	_start()
	var big := "e".repeat(40000)
	_fake.stderr_chunks = [big, big, big]
	for i in 3:
		_frame()
	_fake.running = false
	_fake.code = 9
	_frame()
	var tail: String = _runner.last_error()["stderr"]
	assert_int(tail.length()).is_less_equal(AutochartRunner.STDERR_CAP)
	assert_int(tail.length()).is_greater(0)
