extends GdUnitTestSuite
## Settings > LIBRARY (D-06) and SongLibrary <-> Settings wiring. Temp paths only; never opens a
## real dialog or file manager (folder_picker / shell_opener are injected).

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const SettingsScript := preload("res://src/autoload/settings.gd")
const TEST_PATH := "user://test_library_settings.cfg"
const D := "user://test_library_settings_dir"

var _old_path: String
var _old_folders: Array[String]
var _old_song: String
var _old_diff: String


class FakeLibrary extends Node:
	var extra_folders: Array[String] = []
	var entries: Array = []
	var rescans := 0
	var opened := 0
	var root := ""

	func rescan() -> void:
		rescans += 1
		extra_folders.assign(Settings.library_folders)

	func songs_dir() -> String:
		return root

	func open_songs_folder() -> bool:
		opened += 1
		return true


var _lib: FakeLibrary


func before_test() -> void:
	_old_path = Settings.save_path
	_old_folders = Settings.library_folders.duplicate()
	_old_song = Settings.last_song_id
	_old_diff = Settings.last_difficulty
	Settings.save_path = TEST_PATH
	Settings.library_folders = []
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D + "/songs"))
	_lib = FakeLibrary.new()
	_lib.root = ProjectSettings.globalize_path(D + "/songs")
	auto_free(_lib)


func after_test() -> void:
	Settings.save_path = _old_path
	Settings.library_folders = _old_folders
	Settings.last_song_id = _old_song
	Settings.last_difficulty = _old_diff
	_clean()


func _clean() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_rm(ProjectSettings.globalize_path(D))


func _rm(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for sub in DirAccess.get_directories_at(abs_dir):
		_rm(abs_dir.path_join(sub))
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)


func _mk(name: String) -> String:
	var p := ProjectSettings.globalize_path(D + "/" + name)
	DirAccess.make_dir_recursive_absolute(p)
	return p


func _screen() -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.library = _lib
	s.navigate = func(_p: String) -> void: pass
	add_child(s)
	auto_free(s)
	return s


func test_add_validation_and_persistence() -> void:
	var s := _screen()
	var a := _mk("a")
	assert_str(s.add_library_folder(a)).is_equal("")
	assert_str(s.add_library_folder(a + "/")).is_equal(SettingsScreen.ERR_DUPLICATE)
	assert_str(s.add_library_folder(a.replace("/", "\\"))).is_equal(SettingsScreen.ERR_DUPLICATE)
	assert_str(s.add_library_folder(ProjectSettings.globalize_path(D + "/nope"))).is_equal(SettingsScreen.ERR_MISSING)
	assert_str(s.add_library_folder("")).is_equal(SettingsScreen.ERR_MISSING)
	assert_str(s.add_library_folder(_lib.root)).is_equal(SettingsScreen.ERR_SONGS_DIR)
	assert_int(Settings.library_folders.size()).is_equal(1)
	var t: Node = auto_free(SettingsScript.new())
	t.load_from(TEST_PATH)
	assert_int(t.library_folders.size()).is_equal(1)
	assert_str(t.library_folders[0]).is_equal(a)


func test_a_file_is_not_a_folder() -> void:
	var s := _screen()
	var f := ProjectSettings.globalize_path(D + "/file.txt")
	var h := FileAccess.open(f, FileAccess.WRITE)
	h.store_string("x")
	h.close()
	assert_str(s.add_library_folder(f)).is_equal(SettingsScreen.ERR_MISSING)


func test_cap_of_eight() -> void:
	var s := _screen()
	for i in range(8):
		assert_str(s.add_library_folder(_mk("f%d" % i))).is_equal("")
	assert_str(s.add_library_folder(_mk("f8"))).is_equal(SettingsScreen.ERR_FULL)
	assert_int(Settings.library_folders.size()).is_equal(8)
	assert_bool(s.add_folder_button.disabled).is_true()


func test_remove_only_forgets_path() -> void:
	var s := _screen()
	var a := _mk("keep")
	s.add_library_folder(a)
	s.remove_library_folder(a)
	assert_array(Settings.library_folders).is_empty()
	assert_bool(DirAccess.dir_exists_absolute(a)).is_true()


func test_rescan_only_when_changed() -> void:
	var s := _screen()
	s.back_pressed()
	assert_int(_lib.rescans).is_equal(0)
	s.add_library_folder(_mk("x"))
	s.back_pressed()
	assert_int(_lib.rescans).is_equal(1)
	s.back_pressed()
	assert_int(_lib.rescans).is_equal(1)
	var s2 := _screen()
	s2.remove_library_folder(Settings.library_folders[0])
	s2.back_pressed()
	assert_int(_lib.rescans).is_equal(2)


func test_add_then_remove_same_session_does_not_rescan() -> void:
	var s := _screen()
	var a := _mk("tmp")
	s.add_library_folder(a)
	s.remove_library_folder(a)
	s.back_pressed()
	assert_int(_lib.rescans).is_equal(0)


func test_picker_seam_and_inline_error() -> void:
	var s := _screen()
	var a := _mk("p")
	s.folder_picker = func(cb: Callable) -> void: cb.call(a)
	s.request_add_folder()
	assert_int(Settings.library_folders.size()).is_equal(1)
	assert_str(s.library_message_text()).is_equal("")
	s.request_add_folder()
	assert_str(s.library_message_text()).is_equal("! " + SettingsScreen.ERR_DUPLICATE)
	s.clear_library_message()
	assert_str(s.library_message_text()).is_equal("")


func test_status_strings() -> void:
	var s := _screen()
	var a := _mk("st")
	s.add_library_folder(a)
	assert_str(s.folder_status(a)).is_equal("Not scanned yet")
	_lib.extra_folders.assign([a])
	var e := SongEntry.new()
	e.source = "library"
	e.path = a + "/Song One"
	_lib.entries = [e]
	assert_str(s.folder_status(a)).is_equal("1 song")
	_lib.entries = []
	assert_str(s.folder_status(a)).is_equal("0 songs")
	assert_str(s.folder_status(ProjectSettings.globalize_path(D + "/gone"))).is_equal("Folder not found")


func test_section_order_and_open_button() -> void:
	var s := _screen()
	var heads: Array[String] = []
	_collect_headings(s, heads)
	var order := ["SETTINGS", "CONTROLS", "GAMEPLAY", "DISPLAY", "AUDIO", "LIBRARY", "CALIBRATION"]
	assert_array(heads.filter(func(h: String) -> bool: return h in order)).is_equal(order)
	s.open_songs_button.pressed.emit()
	assert_int(_lib.opened).is_equal(1)


func _collect_headings(n: Node, out: Array[String]) -> void:
	if n is Label and (n as Label).theme_type_variation == &"HeadingLabel":
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_headings(c, out)


func test_middle_truncate() -> void:
	assert_str(SettingsScreen.middle_truncate("short", 20)).is_equal("short")
	var t := SettingsScreen.middle_truncate("C:/very/long/path/".repeat(10), 40)
	assert_int(t.length()).is_equal(40)
	assert_bool(t.contains("...")).is_true()
	assert_bool(t.begins_with("C:/")).is_true()


func test_song_library_reads_and_persists_via_settings() -> void:
	var st: Node = auto_free(SettingsScript.new())
	st.save_path = TEST_PATH
	var f := _mk("lf")
	st.library_folders = [f] as Array[String]
	st.last_song_id = "u1.abc.x"
	st.last_difficulty = "hard"
	var lib: Node = auto_free(load("res://src/autoload/song_library.gd").new())
	lib.auto_scan = false
	lib.settings_ref = st
	lib.songs_root_override = D + "/songs"
	lib.cache_path = D + "/cache.json"
	add_child(lib)
	assert_array(lib.extra_folders).is_equal([f])
	assert_str(lib.last_song_id).is_equal("u1.abc.x")
	assert_str(lib.last_difficulty).is_equal("hard")
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()  # loading never writes back
	lib.last_song_id = "u1.def.x"
	lib.last_difficulty = "easy"
	var reload: Node = auto_free(SettingsScript.new())
	reload.load_from(TEST_PATH)
	assert_str(reload.last_song_id).is_equal("u1.def.x")
	assert_str(reload.last_difficulty).is_equal("easy")
	st.library_folders = [] as Array[String]
	lib.rescan()
	assert_array(lib.extra_folders).is_empty()


func test_song_library_without_settings_is_plain() -> void:
	var lib: Node = auto_free(load("res://src/autoload/song_library.gd").new())
	lib.auto_scan = false
	add_child(lib)
	lib.last_song_id = "zzz"
	assert_str(lib.last_song_id).is_equal("zzz")
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()
