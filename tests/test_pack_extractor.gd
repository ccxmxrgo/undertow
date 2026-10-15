extends GdUnitTestSuite
## PackSpec format, AutochartPaths resolution and PackExtractor (fail-closed safe extraction
## of hashed pack parts: zip-slip, central-directory caps, progress, cancel). D-04, D-13.

const D := "user://test_pack_extractor"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)


func after_test() -> void:
	SongFixture.rm_tree(D)
	AutochartPaths.env_getter = Callable()
	AutochartPaths.root_override = ""


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


# ---- PackSpec ----

func test_spec_contract() -> void:
	# Plan 06 pins the real parts; the pinned values are checked in test_pack_spec.gd.
	assert_str(PackSpec.TAG).is_equal("autocharter-pack-v1")
	assert_str(PackSpec.url({"name": "undertow-ac-v1-app.zip"})).is_equal(
		"https://github.com/ccxmxrgo/undertow/releases/download/autocharter-pack-v1/undertow-ac-v1-app.zip")
	var d := PackSpec.as_dict()
	assert_int(d["version"]).is_equal(1)
	assert_str(d["tag"]).is_equal(PackSpec.TAG)
	assert_str(d["base_url"]).is_equal(PackSpec.BASE_URL)
	assert_int((d["parts"] as Array).size()).is_equal(PackSpec.PARTS.size())
	assert_int(d["unpacked_bytes"]).is_equal(PackSpec.UNPACKED_BYTES)


# ---- AutochartPaths ----

func test_paths_localappdata() -> void:
	var fake := _abs(D + "/lad").replace("\\", "/")
	AutochartPaths.env_getter = func(k: String) -> String: return fake if k == "LOCALAPPDATA" else ""
	var r := AutochartPaths.root()
	assert_str(r).is_equal(fake + "/UNDERTOW/ac")
	assert_bool(DirAccess.dir_exists_absolute(r)).is_true()
	assert_str(AutochartPaths.version_dir()).is_equal(r + "/v1")
	assert_str(AutochartPaths.staging_dir()).is_equal(r + "/staging_v1")
	assert_str(AutochartPaths.dl_dir()).is_equal(r + "/dl")
	assert_str(AutochartPaths.work_root()).is_equal(r + "/work")
	assert_str(AutochartPaths.python_exe()).is_equal(r + "/v1/rt/python.exe")
	assert_str(AutochartPaths.app_dir()).is_equal(r + "/v1/app")
	assert_str(AutochartPaths.models_dir()).is_equal(r + "/v1/models")
	assert_str(AutochartPaths.marker_path()).is_equal(r + "/v1/installed.json")
	assert_str(AutochartPaths.version_dir(2)).is_equal(r + "/v2")


func test_paths_fallback_user() -> void:
	AutochartPaths.env_getter = func(_k: String) -> String: return ""
	var r := AutochartPaths.root()
	assert_str(r).is_equal(_abs("user://autocharter").replace("\\", "/").simplify_path())
	assert_bool(DirAccess.dir_exists_absolute(r)).is_true()


func test_paths_override() -> void:
	AutochartPaths.root_override = D + "/root"
	assert_str(AutochartPaths.root()).is_equal(_abs(D + "/root").replace("\\", "/").simplify_path())


# ---- PackExtractor ----

func test_extract_any_extension() -> void:
	var z := D + "/p.zip"
	SongFixture.make_zip(z, {"rt/python.exe": "MZ", "rt/Lib/x.py": "print(1)", "rt/Lib/": "", "app/autochart.py": "x"})
	var dest := D + "/out"
	var r := PackExtractor.extract_all(z, dest)
	assert_bool(r["ok"]).is_true()
	assert_int(r["written"]).is_equal(3)
	assert_str(FileAccess.get_file_as_string(dest + "/rt/python.exe")).is_equal("MZ")
	assert_str(FileAccess.get_file_as_string(dest + "/rt/Lib/x.py")).is_equal("print(1)")
	assert_bool(FileAccess.file_exists(dest + "/app/autochart.py")).is_true()


func test_extract_absolute_dest() -> void:
	var z := D + "/p.zip"
	SongFixture.make_zip(z, {"app/a.txt": "a"})
	var dest := _abs(D + "/absout")
	assert_bool(PackExtractor.extract_all(z, dest)["ok"]).is_true()
	assert_bool(FileAccess.file_exists(dest.path_join("app/a.txt"))).is_true()


func _assert_unsafe(entry: String) -> void:
	var z := D + "/evil.zip"
	SongFixture.rm_tree(D + "/sub")
	SongFixture.make_zip(z, {"fine/ok.txt": "ok", entry: "x"})
	var r := PackExtractor.extract_all(z, D + "/sub/out")
	assert_bool(r["ok"]).override_failure_message("accepted " + entry).is_false()
	assert_str(r["error"]).is_equal("unsafe_path")
	# Nothing written at all (fail closed before pass 2), nothing outside dest.
	assert_bool(FileAccess.file_exists(D + "/sub/out/fine/ok.txt")).is_false()
	assert_bool(FileAccess.file_exists(D + "/sub/evil.txt")).is_false()
	assert_bool(FileAccess.file_exists(D + "/evil.txt")).is_false()
	assert_bool(FileAccess.file_exists(D + "/b.txt")).is_false()
	assert_bool(FileAccess.file_exists(D + "/sub/b.txt")).is_false()
	assert_bool(FileAccess.file_exists("user://abs.txt")).is_false()
	assert_int(DirAccess.get_files_at(_abs(D + "/sub")).size()).is_equal(0)


func test_extract_unsafe_names_fail_closed() -> void:
	_assert_unsafe("../evil.txt")
	_assert_unsafe("a/../../b.txt")
	_assert_unsafe("C:/x.txt")
	_assert_unsafe("/abs.txt")
	_assert_unsafe("bad\u0001name.txt")
	_assert_unsafe("..\\evil.txt")


func test_extract_caps_before_write() -> void:
	var big := D + "/big.zip"
	SongFixture.make_zip(big, {"a.txt": "0123456789", "b.txt": "0123456789"})
	var r1 := PackExtractor.extract_all(big, D + "/o1", Callable(), {"max_entry": 5})
	assert_bool(r1["ok"]).is_false()
	assert_str(r1["error"]).is_equal("too_large")
	assert_bool(FileAccess.file_exists(D + "/o1/a.txt")).is_false()
	var r2 := PackExtractor.extract_all(big, D + "/o2", Callable(), {"max_total": 15})
	assert_bool(r2["ok"]).is_false()
	assert_bool(FileAccess.file_exists(D + "/o2/a.txt")).is_false()
	var r3 := PackExtractor.extract_all(big, D + "/o3", Callable(), {"max_entries": 1})
	assert_bool(r3["ok"]).is_false()
	assert_str(r3["error"]).is_equal("too_many")
	assert_bool(FileAccess.file_exists(D + "/o3/a.txt")).is_false()
	assert_bool(PackExtractor.extract_all(big, D + "/o4")["ok"]).is_true()


func test_extract_unreadable() -> void:
	SongFixture.write_bytes(D + "/bad.zip", SongFixture.garbage_bytes())
	var r := PackExtractor.extract_all(D + "/bad.zip", D + "/o")
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal("zip_unreadable")
	assert_str(PackExtractor.extract_all(D + "/missing.zip", D + "/o")["error"]).is_equal("zip_unreadable")


func test_extract_progress() -> void:
	var z := D + "/many.zip"
	var entries := {}
	for i in 450:
		entries["d/f%d.txt" % i] = "x"
	SongFixture.make_zip(z, entries)
	var calls: Array = []
	var r := PackExtractor.extract_all(z, D + "/o", func(w: int, t: int) -> void: calls.append([w, t]))
	assert_bool(r["ok"]).is_true()
	assert_int(r["written"]).is_equal(450)
	assert_array(calls.back()).is_equal([450, 450])
	var last := 0
	for c in calls:
		assert_int(c[1]).is_equal(450)
		assert_bool(int(c[0]) - last <= 200).is_true()
		last = int(c[0])


func test_extract_cancel() -> void:
	var z := D + "/many.zip"
	var entries := {}
	for i in 20:
		entries["f%d.txt" % i] = "x"
	SongFixture.make_zip(z, entries)
	var count := [0]
	var cancel := func() -> bool:
		count[0] += 1
		return count[0] > 3
	var r := PackExtractor.extract_all(z, D + "/o", Callable(), {}, cancel)
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal("cancelled")
	assert_int(DirAccess.get_files_at(_abs(D + "/o")).size()).is_equal(3)


## WR-03: an entry whose bytes do not match its central-directory size fails the part instead
## of leaving a truncated (here: empty) file behind while extraction reports ok.
func test_extract_short_entry_fails_closed() -> void:
	var z := D + "/short.zip"
	SongFixture.make_zip(z, {"a.bin": "0123456789", "b.bin": "abc"})
	var bytes := FileAccess.get_file_as_bytes(z)
	var patched := false
	for i in range(bytes.size() - 46, -1, -1):
		if bytes.decode_u32(i) == 0x02014B50:
			var nlen := bytes.decode_u16(i + 28)
			if bytes.slice(i + 46, i + 46 + nlen).get_string_from_utf8() == "a.bin":
				bytes.encode_u32(i + 24, 20)  # central record claims 20 bytes, the data holds 10
				patched = true
	assert_bool(patched).is_true()
	SongFixture.write_bytes(z, bytes)
	var r := PackExtractor.extract_all(z, D + "/o")
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal("read_failed")
	assert_bool(FileAccess.file_exists(D + "/o/a.bin")).is_false()
