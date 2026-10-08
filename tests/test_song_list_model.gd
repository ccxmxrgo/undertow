extends GdUnitTestSuite
## SongListModel: pure filter / sort / order / navigation / preview rules for Song Select.


func _e(id: String, title: String, artist: String = "", status: String = "ok", source: String = "songs",
		fps: Array = []) -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.artist = artist
	e.status = status
	e.source = source
	for fp in fps:
		e.difficulties.append({"name": "expert", "note_count": 10, "fingerprint": fp})
	return e


func _ids(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append(e.id)
	return out


func test_filter_empty_returns_all_including_broken() -> void:
	var l := [_e("a", "Alpha"), _e("b", "Beta", "", "broken"), _e("c", "Gamma", "", "needs_chart")]
	assert_array(_ids(SongListModel.filter(l, ""))).is_equal(["a", "b", "c"])
	assert_array(_ids(SongListModel.filter(l, "   "))).is_equal(["a", "b", "c"])


func test_filter_all_terms_case_insensitive_title_or_artist() -> void:
	var l := [_e("a", "Deep Blue", "The Divers"), _e("b", "Deep Red", "Other"), _e("c", "Shallow", "Divers Deep")]
	assert_array(_ids(SongListModel.filter(l, "deep DIVERS"))).is_equal(["a", "c"])
	assert_array(_ids(SongListModel.filter(l, "red"))).is_equal(["b"])
	assert_array(_ids(SongListModel.filter(l, "zzz"))).is_empty()


func test_filter_text_capped_at_40() -> void:
	var long_text := "x".repeat(60)
	assert_int(SongListModel.clamp_filter(long_text).length()).is_equal(40)
	var l := [_e("a", "x".repeat(45))]
	# 60 x's would not be a substring of 45; the 40-char cap makes it match.
	assert_int(SongListModel.filter(l, long_text).size()).is_equal(1)


func test_order_title_calibration_then_needs_chart_then_broken() -> void:
	var cal := _e("test.hand", "Calibration Track", "", "ok", "test")
	var l := [
		_e("br2", "Zed broken", "", "broken"), _e("b", "beta"), cal,
		_e("nc", "Mid audio", "", "needs_chart"), _e("a", "Alpha"), _e("br1", "Aaa broken", "", "broken"),
		_e("c", "Charlie"),
	]
	var o := SongListModel.order(l, SongListModel.SortMode.TITLE, {})
	assert_array(_ids(o)).is_equal(["a", "b", "c", "test.hand", "nc", "br1", "br2"])


func test_order_artist_then_title() -> void:
	var l := [_e("1", "B", "zeta"), _e("2", "A", "Zeta"), _e("3", "C", "alpha")]
	var o := SongListModel.order(l, SongListModel.SortMode.ARTIST, {})
	assert_array(_ids(o)).is_equal(["3", "2", "1"])


func test_order_best_desc_then_no_record_by_title() -> void:
	var l := [_e("a", "Alpha", "", "ok", "songs", ["fa1", "fa2"]), _e("b", "Beta", "", "ok", "songs", ["fb"]),
		_e("c", "Cee", "", "ok", "songs", ["fc"]), _e("d", "Dee", "", "ok", "songs", ["fd"])]
	var best := {"fa1": 100.0, "fa2": 900.0, "fb": 500.0}
	var o := SongListModel.order(l, SongListModel.SortMode.BEST, best)
	assert_array(_ids(o)).is_equal(["a", "b", "c", "d"])
	assert_float(SongListModel.best_depth(l[0], best)).is_equal(900.0)
	assert_float(SongListModel.best_depth(l[2], best)).is_equal(-1.0)


func test_order_is_stable_for_equal_keys() -> void:
	var l := [_e("1", "Same"), _e("2", "same"), _e("3", "SAME")]
	var o := SongListModel.order(l, SongListModel.SortMode.TITLE, {})
	assert_array(_ids(o)).is_equal(["1", "2", "3"])


func test_next_sort_cycles() -> void:
	assert_int(SongListModel.next_sort(SongListModel.SortMode.TITLE)).is_equal(SongListModel.SortMode.ARTIST)
	assert_int(SongListModel.next_sort(SongListModel.SortMode.ARTIST)).is_equal(SongListModel.SortMode.BEST)
	assert_int(SongListModel.next_sort(SongListModel.SortMode.BEST)).is_equal(SongListModel.SortMode.TITLE)
	assert_str(SongListModel.sort_label(SongListModel.SortMode.BEST)).is_equal("SORT: BEST SCORE")


func test_digits_only_when_filter_empty_and_not_typing() -> void:
	assert_bool(SongListModel.nav_digits_active("", false)).is_true()
	assert_bool(SongListModel.nav_digits_active("a", false)).is_false()
	assert_bool(SongListModel.nav_digits_active("", true)).is_false()
	assert_int(SongListModel.digit_delta(KEY_1)).is_equal(-1)
	assert_int(SongListModel.digit_delta(KEY_2)).is_equal(1)
	assert_int(SongListModel.digit_delta(KEY_3)).is_equal(-9)
	assert_int(SongListModel.digit_delta(KEY_4)).is_equal(9)
	assert_int(SongListModel.digit_delta(KEY_5)).is_equal(0)


func test_esc_clears_filter_first_then_back() -> void:
	assert_str(SongListModel.esc_action("abc")).is_equal("clear_filter")
	assert_str(SongListModel.esc_action("")).is_equal("back")


func test_typing_mode_ends_when_backspace_empties() -> void:
	assert_bool(SongListModel.typing_after_backspace("ab")).is_true()
	assert_bool(SongListModel.typing_after_backspace("")).is_false()


func test_snap_difficulty_exact_nearest_and_tie_prefers_lower() -> void:
	assert_str(SongListModel.snap_difficulty(["easy", "expert"], "expert")).is_equal("expert")
	# wanted medium, available easy + hard: tie -> lower (easy)
	assert_str(SongListModel.snap_difficulty(["easy", "hard"], "medium")).is_equal("easy")
	assert_str(SongListModel.snap_difficulty(["easy", "medium"], "expert")).is_equal("medium")
	assert_str(SongListModel.snap_difficulty(["hard", "expert"], "easy")).is_equal("hard")
	assert_str(SongListModel.snap_difficulty([], "easy")).is_equal("")


func test_next_difficulty_skips_unavailable_and_clamps() -> void:
	var av := ["easy", "hard", "expert"]
	assert_str(SongListModel.next_difficulty(av, "easy", 1)).is_equal("hard")
	assert_str(SongListModel.next_difficulty(av, "hard", 1)).is_equal("expert")
	assert_str(SongListModel.next_difficulty(av, "expert", 1)).is_equal("expert")
	assert_str(SongListModel.next_difficulty(av, "easy", -1)).is_equal("easy")
	assert_str(SongListModel.next_difficulty(av, "expert", -1)).is_equal("hard")
	assert_str(SongListModel.next_difficulty([], "easy", 1)).is_equal("")


func test_preview_start_uses_ini_value_or_30_percent() -> void:
	assert_float(SongListModel.preview_start_sec(45000, 180.0)).is_equal_approx(45.0, 0.0001)
	assert_float(SongListModel.preview_start_sec(-1, 100.0)).is_equal_approx(30.0, 0.0001)
	# Too close to the end (needs >= 5 s of audio left): fall back to 30%.
	assert_float(SongListModel.preview_start_sec(98000, 100.0)).is_equal_approx(30.0, 0.0001)
	assert_float(SongListModel.preview_start_sec(0, 100.0)).is_equal_approx(0.0, 0.0001)


func test_preview_gate_and_stale_guard() -> void:
	assert_bool(SongListModel.preview_gate(1000, 1399)).is_false()
	assert_bool(SongListModel.preview_gate(1000, 1400)).is_true()
	assert_bool(SongListModel.accept_result(5, 5)).is_true()
	assert_bool(SongListModel.accept_result(4, 5)).is_false()


func test_insert_stable_keeps_selected_row_at_same_visible_y() -> void:
	var old_ids := ["a", "c", "e", "g", "i", "k", "m", "o", "q", "s", "u"]
	var new_ids := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "m", "o", "q", "s", "u"]
	# selected "g": old index 3, offset 1 -> visible row 2. After: index 6 -> offset 4.
	assert_int(SongListModel.insert_stable(old_ids, new_ids, "g", 1)).is_equal(4)
	# Rows inserted below the selection do not move the offset.
	assert_int(SongListModel.insert_stable(["a", "b"], ["a", "b", "c"], "a", 0)).is_equal(0)
	# Unknown selection: unchanged.
	assert_int(SongListModel.insert_stable(["a"], ["x", "a"], "zz", 3)).is_equal(3)


func test_scroll_keeps_selection_in_rows_3_to_7() -> void:
	# 40 rows, offset 0, selection index 8 (visible row 9 of 9) -> offset so it sits on row 7 (index off+6).
	assert_int(SongListModel.scroll_for_selection(8, 0, 40)).is_equal(2)
	assert_int(SongListModel.scroll_for_selection(3, 0, 40)).is_equal(0)
	assert_int(SongListModel.scroll_for_selection(10, 10, 40)).is_equal(8)
	assert_int(SongListModel.scroll_for_selection(39, 0, 40)).is_equal(31)
	assert_int(SongListModel.scroll_for_selection(2, 0, 5)).is_equal(0)


func test_text_formatting() -> void:
	assert_str(SongListModel.fmt_length(192.0)).is_equal("3:12")
	assert_str(SongListModel.fmt_length(5.0)).is_equal("0:05")
	assert_str(SongListModel.fmt_count(1204)).is_equal("1,204")
	assert_str(SongListModel.fmt_count(7)).is_equal("7")
	assert_str(SongListModel.truncate_middle("short", 20)).is_equal("short")
	var t := SongListModel.truncate_middle("C:/Users/someone/Documents/Songs/Folder", 20)
	assert_int(t.length()).is_equal(20)
	assert_bool(t.contains("...")).is_true()
	assert_bool(t.begins_with("C:/")).is_true()
	assert_bool(t.ends_with("Folder")).is_true()


func test_scan_status_text() -> void:
	assert_str(SongListModel.scan_status_text(false, 0, 0, "", 12, 0)).is_equal("12 songs")
	assert_str(SongListModel.scan_status_text(false, 0, 0, "", 1, 0)).is_equal("1 song")
	assert_str(SongListModel.scan_status_text(false, 0, 0, "", 12, 3)).is_equal("12 songs  ·  3 unplayable")
	assert_str(SongListModel.scan_status_text(true, 0, 0, "", 0, 0)).is_equal("Looking for songs...")
	assert_str(SongListModel.scan_status_text(true, 4, 10, "x", 0, 0)).is_equal("Scanning 4 / 10")
	assert_str(SongListModel.scan_status_text(true, 4, 10, "Unpacking pack.zip", 0, 0)).is_equal("Unpacking pack.zip")
	var long_name := "Unpacking " + "n".repeat(40) + ".zip"
	var s := SongListModel.scan_status_text(true, 4, 10, long_name, 0, 0)
	assert_str(s).is_equal("Unpacking " + "n".repeat(28) + "...")
