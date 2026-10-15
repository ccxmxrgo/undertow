extends GdUnitTestSuite
## PackInstaller state machine with an injected fetcher and free-space probe (no network):
## not-available, network, hash/size mismatch, disk, happy path, marker-last, partial
## updates, install from folder, cancel mid-extract and before finalize, remove (D-03, D-04).

const D := "user://test_pack_installer"
const FX := D + "/fx"
const SRC := D + "/src"
const GB := 1024 * 1024 * 1024

var _inst: PackInstaller
var _states: Array = []
var _progress: Array = []
var _failed: Array = []
var _installed := 0
var _fetches: Array = []
## name -> [http_code, ok] scripted results; default 200/ok (copies the fixture).
var _script: Dictionary = {}


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(FX)
	AutochartPaths.root_override = D + "/root"
	_states = []
	_progress = []
	_failed = []
	_installed = 0
	_fetches = []
	_script = {}
	_inst = _new_installer()


func after_test() -> void:
	if is_instance_valid(_inst):
		_inst.cancel()
	SongFixture.rm_tree(D)
	AutochartPaths.root_override = ""


func _new_installer() -> PackInstaller:
	var inst: PackInstaller = auto_free(PackInstaller.new())
	add_child(inst)
	inst.fetcher = _fake_fetch
	inst.free_space = func(_p: String) -> int: return 10 * GB
	inst.state_changed.connect(func(s: String) -> void: _states.append(s))
	inst.progress_changed.connect(func(d: int, t: int, l: String) -> void: _progress.append([d, t, l]))
	inst.failed.connect(func(c: String, m: String) -> void: _failed.append([c, m]))
	inst.installed.connect(func() -> void: _installed += 1)
	return inst


func _fake_fetch(url: String, dest: String, _size: int, done: Callable) -> void:
	_fetches.append(url.get_file())
	var res: Array = _script.get(url.get_file(), [200, true])
	if res[1] and int(res[0]) == 200:
		SongFixture.mkdir(dest.get_base_dir())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FX.path_join(url.get_file())), dest)
	done.call(bool(res[1]), int(res[0]), "" if res[1] else "boom")


func _part(name: String, entries: Dictionary, roots: Array) -> Dictionary:
	var p := FX.path_join(name)
	SongFixture.make_zip(p, entries)
	var f := FileAccess.open(p, FileAccess.READ)
	var size := f.get_length()
	f.close()
	return {"name": name, "size": size, "sha256": FileAccess.get_sha256(p), "roots": roots}


func _spec(parts: Array, base: String = "https://example.invalid/rel/") -> Dictionary:
	return {"version": 1, "tag": "autocharter-pack-v1", "base_url": base, "parts": parts, "unpacked_bytes": 0}


func _three(app_text: String = "v1", rt_files: int = 0) -> Array:
	var rt := {"rt/python.exe": "MZ", "rt/Lib/x.py": "print(1)"}
	for i in rt_files:
		rt["rt/Lib/many/f%d.py" % i] = "x"
	return [
		_part("undertow-ac-v1-rt.zip", rt, ["rt"]),
		_part("undertow-ac-v1-app.zip", {"app/autochart.py": app_text, "NOTICES/LICENSE.txt": "lic"}, ["app", "NOTICES"]),
		_part("undertow-ac-v1-models.zip", {"models/m.bin": "weights"}, ["models"]),
	]


func _wait_end(max_frames: int = 1200) -> void:
	for i in max_frames:
		var s := _inst.state()
		if s == "done" or s == "failed" or s == "idle":
			return
		await get_tree().process_frame


func _vdir() -> String:
	return AutochartPaths.version_dir()


func _assert_nothing_installed() -> void:
	assert_bool(DirAccess.dir_exists_absolute(_vdir())).is_false()
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.staging_dir())).is_false()
	assert_bool(FileAccess.file_exists(AutochartPaths.marker_path())).is_false()


func _install_three() -> Array:
	var parts := _three()
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	return parts


# ---- availability / network ----

func test_empty_parts_not_available() -> void:
	_inst.spec = _spec([])
	_inst.start()
	assert_array(_failed).is_equal([["not_available", PackInstaller.NOT_AVAILABLE_TEXT]])
	assert_array(_fetches).is_empty()
	assert_str(_inst.state()).is_equal("failed")


func test_default_spec_is_compiled_pack_spec() -> void:
	var inst: PackInstaller = auto_free(PackInstaller.new())
	assert_dict(inst.spec).is_equal(PackSpec.as_dict())


func test_http_404_not_available() -> void:
	var parts := _three()
	_script["undertow-ac-v1-rt.zip"] = [404, false]
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["not_available", PackInstaller.NOT_AVAILABLE_TEXT]])
	_assert_nothing_installed()


func test_http_500_and_error_network() -> void:
	var parts := _three()
	_script["undertow-ac-v1-rt.zip"] = [500, false]
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["network", "Download failed. Check your connection and try again."]])
	_failed.clear()
	_script["undertow-ac-v1-rt.zip"] = [0, false]
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["network", "Download failed. Check your connection and try again."]])
	_assert_nothing_installed()


func test_http_url_refused() -> void:
	_inst.spec = _spec(_three(), "http://example.invalid/rel/")
	_inst.start()
	await _wait_end()
	assert_array(_fetches).is_empty()
	assert_str(_failed[0][0]).is_equal("network")
	_assert_nothing_installed()


# ---- verification ----

func test_hash_mismatch_deletes_and_never_extracts() -> void:
	var parts := _three()
	parts[1]["sha256"] = "0".repeat(64)
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["hash_mismatch", "The download was damaged. Please try again."]])
	assert_bool(FileAccess.file_exists(AutochartPaths.dl_dir().path_join("undertow-ac-v1-app.zip"))).is_false()
	assert_bool(_states.has("extracting")).is_false()
	_assert_nothing_installed()


func test_size_mismatch_deletes() -> void:
	var parts := _three()
	parts[0]["size"] = int(parts[0]["size"]) + 1
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_str(_failed[0][0]).is_equal("hash_mismatch")
	assert_bool(FileAccess.file_exists(AutochartPaths.dl_dir().path_join("undertow-ac-v1-rt.zip"))).is_false()
	_assert_nothing_installed()


# ---- disk ----

func test_disk_too_small() -> void:
	_inst.free_space = func(_p: String) -> int: return 1024 * 1024
	_inst.spec = _spec(_three())
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["disk", "Not enough free disk space. The Autocharter pack needs about 2 GB."]])
	assert_array(_fetches).is_empty()
	_assert_nothing_installed()


func test_disk_unknown_warns_and_continues() -> void:
	_inst.free_space = func(_p: String) -> int: return 0
	_inst.spec = _spec(_three())
	_inst.start()
	await _wait_end()
	assert_int(_installed).is_equal(1)
	var warned := false
	for p in _progress:
		if String(p[2]).contains("disk space"):
			warned = true
	assert_bool(warned).is_true()


# ---- happy path ----

func test_happy_path() -> void:
	var parts: Array = await _install_three()
	assert_array(_failed).is_empty()
	assert_int(_installed).is_equal(1)
	assert_str(_inst.state()).is_equal("done")
	var v := _vdir()
	assert_str(FileAccess.get_file_as_string(v + "/rt/python.exe")).is_equal("MZ")
	assert_bool(FileAccess.file_exists(v + "/rt/Lib/x.py")).is_true()
	assert_str(FileAccess.get_file_as_string(v + "/app/autochart.py")).is_equal("v1")
	assert_bool(FileAccess.file_exists(v + "/NOTICES/LICENSE.txt")).is_true()
	assert_bool(FileAccess.file_exists(v + "/models/m.bin")).is_true()
	var marker: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AutochartPaths.marker_path()))
	assert_int(int(marker["pack_version"])).is_equal(1)
	assert_str(marker["tag"]).is_equal("autocharter-pack-v1")
	assert_bool(marker["selftest"]).is_false()
	for p in parts:
		assert_str(marker["parts"][p["name"]]).is_equal(p["sha256"])
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.dl_dir())).is_false()
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.staging_dir())).is_false()
	# State order (first occurrences).
	var order := ["checking", "downloading", "verifying", "extracting", "finalizing", "done"]
	var last := -1
	for s in order:
		var i := _states.find(s)
		assert_bool(i > last).override_failure_message("state order %s" % [_states]).is_true()
		last = i
	assert_bool(_inst.is_installed()).is_true()
	# Second start: nothing fetched, installed emitted again.
	_fetches.clear()
	_inst.start()
	await _wait_end()
	assert_array(_fetches).is_empty()
	assert_int(_installed).is_equal(2)


func test_marker_absent_on_extract_failure() -> void:
	var parts := _three()
	# A hashed part with an unsafe name: verify passes, extraction fails closed.
	parts[2] = _part("undertow-ac-v1-models.zip", {"../evil.bin": "x"}, ["models"])
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_str(_failed[0][0]).is_equal("extract")
	_assert_nothing_installed()
	assert_bool(FileAccess.file_exists(AutochartPaths.root().get_base_dir().path_join("evil.bin"))).is_false()


# ---- partial updates ----

func test_update_app_only() -> void:
	await _install_three()
	var parts := _three("v2")
	_fetches.clear()
	_inst.spec = _spec(parts)
	assert_bool(_inst.is_installed()).is_false()
	assert_int(_inst.parts_to_fetch().size()).is_equal(1)
	_inst.start()
	await _wait_end()
	assert_array(_fetches).is_equal(["undertow-ac-v1-app.zip"])
	assert_str(FileAccess.get_file_as_string(_vdir() + "/app/autochart.py")).is_equal("v2")
	assert_bool(FileAccess.file_exists(_vdir() + "/rt/python.exe")).is_true()
	assert_bool(FileAccess.file_exists(_vdir() + "/NOTICES/LICENSE.txt")).is_true()
	assert_bool(_inst.is_installed()).is_true()
	var marker: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AutochartPaths.marker_path()))
	assert_str(marker["parts"]["undertow-ac-v1-app.zip"]).is_equal(parts[1]["sha256"])


func test_update_rt_full_reinstall() -> void:
	await _install_three()
	var parts := _three("v1", 2)
	_fetches.clear()
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_int(_fetches.size()).is_equal(3)
	assert_bool(FileAccess.file_exists(_vdir() + "/rt/Lib/many/f1.py")).is_true()
	assert_bool(_inst.is_installed()).is_true()


# ---- install from folder ----

func test_install_from_folder() -> void:
	var parts := _three()
	SongFixture.mkdir(SRC)
	for p in parts:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FX.path_join(p["name"])),
			ProjectSettings.globalize_path(SRC.path_join(p["name"])))
	_inst.source_dir = ProjectSettings.globalize_path(SRC)
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_fetches).is_empty()
	assert_int(_installed).is_equal(1)
	assert_bool(_inst.is_installed()).is_true()
	assert_bool(_states.has("downloading")).is_false()
	for p in parts:
		assert_bool(FileAccess.file_exists(SRC.path_join(p["name"]))).is_true()


func test_install_from_folder_hash_checked() -> void:
	var parts := _three()
	SongFixture.mkdir(SRC)
	for p in parts:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FX.path_join(p["name"])),
			ProjectSettings.globalize_path(SRC.path_join(p["name"])))
	parts[0]["sha256"] = "f".repeat(64)
	_inst.source_dir = SRC
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_str(_failed[0][0]).is_equal("hash_mismatch")
	_assert_nothing_installed()
	# Never deletes anything in the player's folder.
	assert_bool(FileAccess.file_exists(SRC.path_join(parts[0]["name"]))).is_true()


## CR-01: the bytes that are extracted are the bytes that were hashed. Swapping the files in
## the chosen folder after they were checked must not change what gets installed.
func test_install_from_folder_extracts_the_hashed_copy() -> void:
	var parts := _three("genuine")
	SongFixture.mkdir(SRC)
	for p in parts:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FX.path_join(p["name"])),
			ProjectSettings.globalize_path(SRC.path_join(p["name"])))
	var evil := D + "/evil.zip"
	SongFixture.make_zip(evil, {"app/autochart.py": "EVIL", "NOTICES/LICENSE.txt": "lic"})
	_inst.state_changed.connect(func(s: String) -> void:
		if s == "extracting":
			var dst := ProjectSettings.globalize_path(SRC.path_join("undertow-ac-v1-app.zip"))
			DirAccess.remove_absolute(dst)
			DirAccess.copy_absolute(ProjectSettings.globalize_path(evil), dst))
	_inst.source_dir = ProjectSettings.globalize_path(SRC)
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_empty()
	assert_int(_installed).is_equal(1)
	assert_str(FileAccess.get_file_as_string(_vdir() + "/app/autochart.py")).is_equal("genuine")
	# The verified copies lived in dl/ and are gone after the install.
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.dl_dir())).is_false()


func test_install_from_folder_missing_part() -> void:
	var parts := _three()
	SongFixture.mkdir(SRC)
	_inst.source_dir = SRC
	_inst.spec = _spec(parts)
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_equal([["not_available", "Part undertow-ac-v1-rt.zip was not found in the chosen folder."]])
	assert_array(_fetches).is_empty()
	_assert_nothing_installed()


# ---- cancel ----

func test_cancel_mid_extract() -> void:
	_inst.spec = _spec(_three("v1", 1500))
	_inst.extract_limits = {"progress_every": 1}
	var seen := [false]
	_inst.progress_changed.connect(func(_d: int, _t: int, l: String) -> void:
		if l.begins_with("Installing") and not seen[0]:
			seen[0] = true
			_inst.cancel())
	_inst.start()
	await _wait_end()
	assert_bool(seen[0]).is_true()
	assert_str(_inst.state()).is_equal("idle")
	assert_array(_failed).is_empty()
	assert_int(_installed).is_equal(0)
	_assert_nothing_installed()
	assert_bool(DirAccess.dir_exists_absolute(AutochartPaths.dl_dir())).is_false()
	# Nothing arrives later from the stopped worker.
	for i in 10:
		await get_tree().process_frame
	_assert_nothing_installed()
	assert_str(_inst.state()).is_equal("idle")


func test_cancel_before_finalize() -> void:
	_inst.spec = _spec(_three())
	_inst.state_changed.connect(func(s: String) -> void:
		if s == "finalizing":
			_inst.cancel())
	_inst.start()
	await _wait_end()
	for i in 10:
		await get_tree().process_frame
	assert_str(_inst.state()).is_equal("idle")
	assert_int(_installed).is_equal(0)
	_assert_nothing_installed()


# ---- remove / busy / selftest ----

func test_remove_pack() -> void:
	await _install_three()
	assert_bool(_inst.remove_pack(true)).is_false()
	assert_bool(_inst.is_installed()).is_true()
	assert_bool(_inst.remove_pack(false)).is_true()
	assert_bool(_inst.is_installed()).is_false()
	_assert_nothing_installed()


func test_start_twice_ignored() -> void:
	var parts := _three()
	_inst.spec = _spec(parts)
	_inst.start()
	_inst.start()
	await _wait_end()
	assert_array(_failed).is_empty()
	assert_int(_installed).is_equal(1)
	assert_int(_fetches.size()).is_equal(3)


func test_selftest_marker() -> void:
	await _install_three()
	assert_bool(_inst.selftest_ok()).is_false()
	_inst.mark_selftest(true)
	assert_bool(_inst.selftest_ok()).is_true()
	assert_bool(_inst.is_installed()).is_true()
	_inst.mark_selftest(false)
	assert_bool(_inst.selftest_ok()).is_false()
