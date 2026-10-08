extends GdUnitTestSuite
## ScoreStore: round trip, strict record semantics, eligibility, hostile files. Temp paths only.

const P := "user://test_score_store.cfg"


func before_test() -> void:
	_clean()


func after_test() -> void:
	_clean()


func _clean() -> void:
	for p in [P, P + ".bak", P + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write(text: String) -> void:
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_round_trip() -> void:
	var s := ScoreStore.new(P)
	var r := s.submit("a.b", 120.5, 96.5, 42, true, "2026-10-08")
	assert_bool(r.recorded).is_true()
	assert_bool(r.new_record).is_true()
	assert_bool(r.previous.is_empty()).is_true()
	var t := ScoreStore.new(P)
	t.load()
	var b := t.best("a.b")
	assert_float(b.depth).is_equal_approx(120.5, 0.001)
	assert_float(b.accuracy).is_equal_approx(96.5, 0.001)
	assert_int(b.max_combo).is_equal(42)
	assert_str(b.date).is_equal("2026-10-08")
	assert_bool(b.date.length() <= 10).is_true()


func test_record_semantics() -> void:
	var s := ScoreStore.new(P)
	s.submit("x", 100.0, 90.0, 10, true)
	var r2 := s.submit("x", 150.0, 90.0, 10, true)
	assert_bool(r2.new_record).is_true()
	assert_float(r2.previous.depth).is_equal_approx(100.0, 0.001)
	assert_bool(s.submit("x", 150.0, 90.0, 10, true).new_record).is_false()
	var r4 := s.submit("x", 50.0, 99.0, 99, true)
	assert_bool(r4.new_record).is_false()
	var b := s.best("x")
	assert_float(b.depth).is_equal_approx(150.0, 0.001)
	assert_float(b.accuracy).is_equal_approx(99.0, 0.001)
	assert_int(b.max_combo).is_equal(99)


func test_ineligible_writes_nothing() -> void:
	var s := ScoreStore.new(P)
	var r := s.submit("x", 100.0, 90.0, 10, false)
	assert_bool(r.recorded).is_false()
	assert_bool(r.new_record).is_false()
	assert_bool(FileAccess.file_exists(P)).is_false()
	s.submit("x", 100.0, 90.0, 10, true)
	var before := FileAccess.get_file_as_string(P)
	s.submit("x", 900.0, 100.0, 90, false)
	assert_str(FileAccess.get_file_as_string(P)).is_equal(before)


func test_eligibility_and_accuracy() -> void:
	assert_bool(ScoreStore.is_eligible(false, false, false)).is_true()
	assert_bool(ScoreStore.is_eligible(true, false, false)).is_false()
	assert_bool(ScoreStore.is_eligible(false, true, false)).is_false()
	assert_bool(ScoreStore.is_eligible(false, false, true)).is_false()
	assert_float(ScoreStore.accuracy(8, 1, 1)).is_equal_approx(90.0, 0.001)
	assert_float(ScoreStore.accuracy(0, 0, 0)).is_equal(0.0)


func test_corrupt_file_backed_up() -> void:
	_write("this is [[ not a config = = \n[unclosed")
	var s := ScoreStore.new(P)
	s.load()
	assert_bool(s.load_error).is_true()
	assert_bool(s.best("x").is_empty()).is_true()
	assert_bool(FileAccess.file_exists(P + ".bak")).is_true()
	assert_bool(FileAccess.file_exists(P)).is_false()
	assert_bool(s.submit("x", 5.0, 5.0, 5, true).recorded).is_true()


func test_hostile_values() -> void:
	_write("[chart:wrongtype]\nbest_depth=\"lots\"\nbest_accuracy=1e30\nmax_combo=-5\n\n"
		+ "[chart:huge]\nbest_depth=1e30\nbest_accuracy=500.0\nmax_combo=99999999999\n\n"
		+ "[chart:nan]\nbest_depth=nan\nbest_accuracy=inf\n\n"
		+ "[chart:Bad ID!]\nbest_depth=5.0\n\n"
		+ "[chart:!!!]\nbest_depth=5.0\n\n"
		+ "[chart:missing]\n")
	var s := ScoreStore.new(P)
	s.load()
	assert_bool(s.load_error).is_false()
	assert_float(s.best("wrongtype").depth).is_equal(0.0)
	assert_float(s.best("wrongtype").accuracy).is_equal(100.0)
	assert_int(s.best("wrongtype").max_combo).is_equal(0)
	assert_float(s.best("huge").depth).is_equal(1.0e7)
	assert_float(s.best("huge").accuracy).is_equal(100.0)
	assert_int(s.best("huge").max_combo).is_equal(1000000)
	assert_float(s.best("nan").depth).is_equal(0.0)
	assert_float(s.best("nan").accuracy).is_equal(0.0)
	assert_float(s.best("badid").depth).is_equal_approx(5.0, 0.001)
	assert_bool(s.best("missing").is_empty()).is_true()


func test_section_cap() -> void:
	var text := ""
	for i in range(1000):
		text += "[chart:c%d]\nbest_depth=%d.0\n\n" % [i, i + 1]
	_write(text)
	var s := ScoreStore.new(P)
	s.load()
	assert_bool(s.best("c0").is_empty()).is_false()
	assert_bool(s.best("c255").is_empty()).is_false()
	assert_bool(s.best("c256").is_empty()).is_true()
	assert_bool(s.best("c999").is_empty()).is_true()


func test_sanitize_id() -> void:
	assert_str(ScoreStore.sanitize_id("A]b\nc dé:1.x-_")).is_equal("abcd:1.x-_")
	assert_int(ScoreStore.sanitize_id("a".repeat(200)).length()).is_equal(64)
	assert_str(ScoreStore.sanitize_id("]\n é")).is_equal("")
	var s := ScoreStore.new(P)
	assert_bool(s.submit("]\n", 5.0, 5.0, 5, true).recorded).is_false()
	assert_bool(FileAccess.file_exists(P)).is_false()


func test_atomic_save_no_tmp() -> void:
	var s := ScoreStore.new(P)
	assert_int(s.save()).is_equal(OK)
	assert_int(s.save()).is_equal(OK)
	assert_bool(FileAccess.file_exists(P + ".tmp")).is_false()
	s.submit("x", 1.0, 1.0, 1, true)
	s.submit("x", 2.0, 1.0, 1, true)
	assert_bool(FileAccess.file_exists(P + ".tmp")).is_false()


func test_chart_ids() -> void:
	assert_str(TestCharts.hand_chart().id).is_equal("test.hand_chart.v1")
	var ids := [TestCharts.hand_chart().id, TestCharts.short_chart().id,
		TestCharts.click_chart(120.0, 16).id]
	for i in ids:
		assert_bool(i != "").is_true()
	assert_int(ids.size()).is_equal(3)
	assert_bool(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]).is_true()
