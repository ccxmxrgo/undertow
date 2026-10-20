extends GdUnitTestSuite
## AutochartBundle: the Autocharter pack folder that ships next to UNDERTOW.exe. Found only when
## every pinned part is there at its pinned size; accepted folder names; no lookup next to the
## Godot binary in editor / test runs (base_dir_override stands in for the exe folder).

const D := "user://test_pack_bundle"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)
	AutochartBundle.base_dir_override = ""


func after_test() -> void:
	AutochartBundle.base_dir_override = ""
	SongFixture.rm_tree(D)


func _base() -> String:
	return ProjectSettings.globalize_path(D).simplify_path()


func _parts() -> Array:
	return [
		{"name": "undertow-ac-v1-app.zip", "size": 5, "sha256": "ab".repeat(32), "roots": ["app"]},
		{"name": "undertow-ac-v1-rt.zip", "size": 9, "sha256": "cd".repeat(32), "roots": ["rt"]},
	]


func _write_parts(folder: String, parts: Array, size_delta: int = 0, skip: String = "") -> String:
	var dir := D.path_join(folder)
	SongFixture.mkdir(dir)
	for p: Dictionary in parts:
		if String(p["name"]) == skip:
			continue
		var bytes := PackedByteArray()
		bytes.resize(maxi(0, int(p["size"]) + size_delta))
		SongFixture.write_bytes(dir.path_join(String(p["name"])), bytes)
	return ProjectSettings.globalize_path(dir).simplify_path()


func test_no_lookup_next_to_the_godot_binary_without_override() -> void:
	# Editor / headless test runs are not exported builds: nothing next to godot.exe is used.
	assert_str(AutochartBundle.base_dir()).is_equal("")
	assert_str(AutochartBundle.find(_parts())).is_equal("")


func test_found_in_autocharter_pack_folder() -> void:
	var dir := _write_parts("Autocharter Pack", _parts())
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.base_dir()).is_equal(_base())
	assert_str(AutochartBundle.find(_parts())).is_equal(dir)


func test_accepts_lowercase_autocharter_folder() -> void:
	var dir := _write_parts("autocharter", _parts())
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartPaths.path_key(AutochartBundle.find(_parts()))).is_equal(AutochartPaths.path_key(dir))


func test_wrong_size_is_not_found() -> void:
	_write_parts("Autocharter Pack", _parts(), 1)
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find(_parts())).is_equal("")


func test_missing_part_is_not_found() -> void:
	_write_parts("Autocharter Pack", _parts(), 0, "undertow-ac-v1-rt.zip")
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find(_parts())).is_equal("")


func test_no_folder_is_not_found() -> void:
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find(_parts())).is_equal("")


func test_empty_parts_is_not_found() -> void:
	_write_parts("Autocharter Pack", _parts())
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find([])).is_equal("")


func test_unsafe_part_name_is_not_found() -> void:
	var bad: Array = [{"name": "../evil.zip", "size": 1, "sha256": "ab".repeat(32), "roots": ["rt"]}]
	SongFixture.mkdir(D + "/Autocharter Pack")
	SongFixture.write_bytes(D + "/evil.zip", PackedByteArray([1]))
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find(bad)).is_equal("")


func test_default_parts_are_the_compiled_pins() -> void:
	# A folder holding only the fake parts is not the real pack.
	_write_parts("Autocharter Pack", _parts())
	AutochartBundle.base_dir_override = _base()
	assert_str(AutochartBundle.find()).is_equal("")
