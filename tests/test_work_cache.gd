extends GdUnitTestSuite
## AutochartWorkCache (02.2.2 plan 09, D-12 / D-05): job dirs, keep-3 prune of the stem cache,
## unfinished-dir cleanup after a cancel, Clear Chart Cache, and the root-confined delete.

const D := "user://test_work_cache"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)
	AutochartPaths.root_override = D + "/root"


func after_test() -> void:
	SongFixture.rm_tree(D)
	AutochartPaths.root_override = ""


func _wr() -> String:
	return AutochartPaths.work_root()


## A finished stem-cache dir: analyze_done.json + last_used.json {"t": t} + one stem of `bytes`.
func _work(name: String, t: float, bytes: int = 100, finished: bool = true) -> String:
	var dir := _wr().path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	if finished:
		SongFixture.write_text(dir.path_join("analyze_done.json"), JSON.stringify({"source_sha256": "ab", "t": t}))
	SongFixture.write_text(dir.path_join("last_used.json"), JSON.stringify({"t": t}))
	var data := PackedByteArray()
	data.resize(bytes)
	SongFixture.write_bytes(dir.path_join("stems/other.wav"), data)
	return dir


func _exists(p: String) -> bool:
	return DirAccess.dir_exists_absolute(p)


func test_new_job_dir_is_unique_and_under_jobs() -> void:
	var a := AutochartWorkCache.new_job_dir(_wr())
	var b := AutochartWorkCache.new_job_dir(_wr())
	assert_str(a).is_not_equal(b)
	assert_bool(_exists(a)).is_true()
	assert_bool(_exists(b)).is_true()
	assert_str(a.get_base_dir()).is_equal(_wr().path_join("jobs"))
	assert_bool(AutochartJob.safe_path_arg(a.path_join("job.json"))).is_true()


func test_prune_keeps_three_newest_and_returns_freed_bytes() -> void:
	var now := Time.get_unix_time_from_system()
	var dirs: Array = []
	for i in 5:
		dirs.append(_work("w_%016d" % i, now - 1000.0 + i * 10.0, 100))
	var freed := AutochartWorkCache.prune(_wr(), 3, "")
	assert_bool(_exists(dirs[0])).is_false()
	assert_bool(_exists(dirs[1])).is_false()
	for i in [2, 3, 4]:
		assert_bool(_exists(dirs[i])).override_failure_message("w %d" % i).is_true()
	assert_int(freed).is_greater_equal(200)


func test_prune_never_deletes_the_protected_dir() -> void:
	var now := Time.get_unix_time_from_system()
	var dirs: Array = []
	for i in 5:
		dirs.append(_work("w_%016d" % i, now - 1000.0 + i * 10.0))
	AutochartWorkCache.prune(_wr(), 3, dirs[0])
	assert_bool(_exists(dirs[0])).is_true()
	assert_bool(_exists(dirs[4])).is_true()
	assert_bool(_exists(dirs[3])).is_true()
	assert_bool(_exists(dirs[2])).is_false()
	assert_bool(_exists(dirs[1])).is_false()


func test_prune_deletes_unfinished_unprotected_dirs() -> void:
	var now := Time.get_unix_time_from_system()
	var done := _work("w_done", now)
	var half := _work("w_half", now, 100, false)
	var running := _work("w_running", now, 100, false)
	AutochartWorkCache.prune(_wr(), 3, running)
	assert_bool(_exists(done)).is_true()
	assert_bool(_exists(half)).is_false()
	assert_bool(_exists(running)).is_true()


func test_prune_deletes_job_dirs_older_than_seven_days() -> void:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var jobs := _wr().path_join("jobs")
	var old := jobs.path_join("j_%d_0" % (now_ms - 8 * 86400 * 1000))
	var fresh := jobs.path_join("j_%d_0" % (now_ms - 86400 * 1000))
	SongFixture.write_text(old.path_join("log.txt"), "old")
	SongFixture.write_text(fresh.path_join("log.txt"), "fresh")
	var made := AutochartWorkCache.new_job_dir(_wr())
	AutochartWorkCache.prune(_wr(), 3, "")
	assert_bool(_exists(old)).is_false()
	assert_bool(_exists(fresh)).is_true()
	assert_bool(_exists(made)).is_true()


func test_last_used_falls_back_to_marker_mtime() -> void:
	var now := Time.get_unix_time_from_system()
	var a := _work("w_a", now - 50.0)
	var b := _work("w_b", now - 40.0)
	var c := _work("w_c", now - 30.0)
	var d := _work("w_d", 0.0)
	DirAccess.remove_absolute(d.path_join("last_used.json"))  # marker written just now -> newest
	AutochartWorkCache.prune(_wr(), 3, "")
	assert_bool(_exists(a)).is_false()
	for p in [b, c, d]:
		assert_bool(_exists(p)).is_true()


func test_remove_unfinished_only_without_marker() -> void:
	var now := Time.get_unix_time_from_system()
	var done := _work("w_done", now)
	var half := _work("w_half", now, 100, false)
	assert_bool(AutochartWorkCache.remove_unfinished(done)).is_false()
	assert_bool(_exists(done)).is_true()
	assert_bool(AutochartWorkCache.remove_unfinished(half)).is_true()
	assert_bool(_exists(half)).is_false()
	assert_bool(AutochartWorkCache.is_analyzed(done)).is_true()
	assert_bool(AutochartWorkCache.is_analyzed(half)).is_false()


func test_remove_unfinished_refuses_outside_root() -> void:
	var outside := ProjectSettings.globalize_path(D + "/outside")
	SongFixture.write_text(outside.path_join("x.txt"), "keep")
	assert_bool(AutochartWorkCache.remove_unfinished(outside)).is_false()
	assert_bool(_exists(outside)).is_true()
	assert_bool(AutochartWorkCache.remove_unfinished("")).is_false()


func test_clear_removes_everything_and_reports_bytes() -> void:
	var now := Time.get_unix_time_from_system()
	_work("w_a", now, 1000)
	_work("w_b", now, 2000, false)
	var job := AutochartWorkCache.new_job_dir(_wr())
	SongFixture.write_text(job.path_join("log.txt"), "12345")
	var before := AutochartWorkCache.size_bytes(_wr())
	assert_int(before).is_greater_equal(3005)
	var freed := AutochartWorkCache.clear(_wr())
	assert_int(freed).is_equal(before)
	assert_array(Array(DirAccess.get_directories_at(_wr())).filter(
		func(n: String) -> bool: return n.begins_with("w_"))).is_empty()
	assert_array(Array(DirAccess.get_directories_at(_wr().path_join("jobs")))).is_empty()
	assert_int(AutochartWorkCache.size_bytes(_wr())).is_equal(0)


func test_clear_refuses_outside_root() -> void:
	var outside := ProjectSettings.globalize_path(D + "/elsewhere")
	SongFixture.write_text(outside.path_join("w_x/a.txt"), "keep")
	assert_int(AutochartWorkCache.clear(outside)).is_equal(-1)
	assert_bool(FileAccess.file_exists(outside.path_join("w_x/a.txt"))).is_true()


func test_size_bytes_sums_nested_files() -> void:
	var dir := _wr().path_join("w_size")
	SongFixture.write_bytes(dir.path_join("a.bin"), PackedByteArray([1, 2, 3]))
	SongFixture.write_bytes(dir.path_join("x/y/b.bin"), PackedByteArray([1, 2, 3, 4, 5]))
	assert_int(AutochartWorkCache.size_bytes(dir)).is_equal(8)
	assert_int(AutochartWorkCache.size_bytes(_wr().path_join("missing"))).is_equal(0)
