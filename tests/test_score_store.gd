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
	var total := ScoreStore.MAX_SECTIONS + 50
	for i in range(total):
		text += "[chart:c%d]
best_depth=%d.0

" % [i, i + 1]
	_write(text)
	var s := ScoreStore.new(P)
	s.load()
	assert_bool(s.best("c0").is_empty()).is_false()
	assert_bool(s.best("c%d" % (ScoreStore.MAX_SECTIONS - 1)).is_empty()).is_false()
	assert_bool(s.best("c%d" % (total - 1)).is_empty()).is_true()


func test_thousand_fingerprint_records_survive_reload() -> void:
	var s := ScoreStore.new(P)
	for i in range(1200):
		var fid := "u1.%024x.x" % (i * 7919 + 1)
		s.submit(fid, float(i + 1), 90.0, 10, true, "2026-10-09")
	var t := ScoreStore.new(P)
	t.load()
	var lost := 0
	for i in range(1200):
		var b := t.best("u1.%024x.x" % (i * 7919 + 1))
		if b.is_empty() or absf(b.depth - float(i + 1)) > 0.01:
			lost += 1
	assert_int(lost).is_equal(0)


func test_difficulties_of_one_song_are_independent() -> void:
	var c := TestCharts.click_chart(120.0, 16)
	var fx := ChartImporter.fingerprint(c, "expert", 30.0)
	var fe := ChartImporter.fingerprint(c, "easy", 30.0)
	assert_str(fx).is_not_equal(fe)
	var s := ScoreStore.new(P)
	s.submit(fx, 300.0, 95.0, 50, true)
	s.submit(fe, 100.0, 99.0, 20, true)
	s.submit(TestCharts.HAND_CHART_ID, 10.0, 80.0, 5, true)
	var t := ScoreStore.new(P)
	t.load()
	assert_float(t.best(fx).depth).is_equal_approx(300.0, 0.01)
	assert_float(t.best(fe).depth).is_equal_approx(100.0, 0.01)
	assert_float(t.best("test.hand_chart.v1").depth).is_equal_approx(10.0, 0.01)


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


# --- D-16: best grade and miss count per record ---------------------------------------------------


func test_grade_and_misses_round_trip() -> void:
	var s := ScoreStore.new(P)
	s.submit("g", 100.0, 95.0, 30, true, "2026-10-10", "A", 2)
	var t := ScoreStore.new(P)
	t.load()
	var b := t.best("g")
	assert_str(b.grade).is_equal("A")
	assert_int(b.misses).is_equal(2)


func test_better_grade_replaces_worse_grade_keeps() -> void:
	var s := ScoreStore.new(P)
	s.submit("g", 100.0, 80.0, 30, true, "", "C", 9)
	s.submit("g", 50.0, 99.0, 10, true, "", "S", 0)  # shallower but a better grade
	assert_str(s.best("g").grade).is_equal("S")
	assert_int(s.best("g").misses).is_equal(0)
	assert_float(s.best("g").depth).is_equal_approx(100.0, 0.001)
	var before := FileAccess.get_file_as_string(P)
	s.submit("g", 10.0, 50.0, 5, true, "", "D", 30)  # worse in every way: file unchanged
	assert_str(s.best("g").grade).is_equal("S")
	assert_int(s.best("g").misses).is_equal(0)
	assert_str(FileAccess.get_file_as_string(P)).is_equal(before)
	s.submit("g", 10.0, 50.0, 5, true, "", "S", 0)  # equal grade: kept
	assert_str(s.best("g").grade).is_equal("S")


func test_ungraded_submit_and_legacy_defaults() -> void:
	var s := ScoreStore.new(P)
	s.submit("u", 100.0, 90.0, 10, true)
	assert_str(s.best("u").grade).is_equal("")
	assert_int(s.best("u").misses).is_equal(-1)


func test_legacy_file_loads_unchanged_with_no_grade() -> void:
	_write("[chart:old.song]\nbest_depth=1240.5\nbest_accuracy=96.25\nmax_combo=321\ndate=\"2026-10-01\"\n")
	var s := ScoreStore.new(P)
	s.load()
	var b := s.best("old.song")
	assert_float(b.depth).is_equal_approx(1240.5, 0.001)
	assert_float(b.accuracy).is_equal_approx(96.25, 0.001)
	assert_int(b.max_combo).is_equal(321)
	assert_str(b.date).is_equal("2026-10-01")
	assert_str(b.grade).is_equal("")
	assert_int(b.misses).is_equal(-1)
	# A first graded submit on a legacy record stores the grade; the id is unchanged.
	s.submit("old.song", 10.0, 50.0, 5, true, "", "B", 4)
	var t := ScoreStore.new(P)
	t.load()
	assert_str(t.best("old.song").grade).is_equal("B")
	assert_float(t.best("old.song").depth).is_equal_approx(1240.5, 0.001)
	assert_str(FileAccess.get_file_as_string(P)).contains("[chart:old.song]")


func test_hostile_grade_and_misses_sanitized() -> void:
	_write("[chart:h1]\nbest_depth=5.0\ngrade=\"SSS\"\nmisses=-7\n\n"
		+ "[chart:h2]\nbest_depth=5.0\ngrade=5\nmisses=1e30\n\n"
		+ "[chart:h3]\nbest_depth=5.0\ngrade=\"a\"\nmisses=\"lots\"\n\n"
		+ "[chart:h4]\nbest_depth=5.0\ngrade=\"S\"\nmisses=nan\n\n"
		+ "[chart:h5]\nbest_depth=5.0\ngrade=\"D\"\nmisses=12\n")
	var s := ScoreStore.new(P)
	s.load()
	assert_str(s.best("h1").grade).is_equal("")
	assert_int(s.best("h1").misses).is_equal(-1)
	assert_str(s.best("h2").grade).is_equal("")
	assert_int(s.best("h2").misses).is_equal(int(ScoreStore.MAX_COMBO))
	assert_str(s.best("h3").grade).is_equal("")
	assert_int(s.best("h3").misses).is_equal(-1)
	assert_str(s.best("h4").grade).is_equal("S")
	assert_int(s.best("h4").misses).is_equal(-1)
	assert_str(s.best("h5").grade).is_equal("D")
	assert_int(s.best("h5").misses).is_equal(12)


func test_submit_rejects_unknown_grade_and_clamps_misses() -> void:
	var s := ScoreStore.new(P)
	s.submit("z", 10.0, 10.0, 1, true, "", "X", 5)
	assert_str(s.best("z").grade).is_equal("")
	assert_int(s.best("z").misses).is_equal(-1)
	s.submit("z", 10.0, 10.0, 1, true, "", "D", -3)
	assert_str(s.best("z").grade).is_equal("D")
	assert_int(s.best("z").misses).is_equal(0)
