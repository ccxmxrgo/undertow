extends GdUnitTestSuite
## RunStats (D-08 accuracy and grade, D-09 histogram) and HitOffsetRecorder.


class FakeJudge:
	extends RefCounted
	signal judged(lane: int, note_index: int, judgment: int, error_s: float)


func test_accuracy() -> void:
	assert_float(RunStats.accuracy(0, 0, 0)).is_equal(-1.0)
	assert_float(RunStats.accuracy(10, 0, 0)).is_equal_approx(100.0, 1e-9)
	assert_float(RunStats.accuracy(1, 1, 0)).is_equal_approx(75.0, 1e-9)
	assert_float(RunStats.accuracy(0, 0, 5)).is_equal_approx(0.0, 1e-9)
	assert_float(RunStats.accuracy(1, 0, 1)).is_equal_approx(50.0, 1e-9)


func test_accuracy_text() -> void:
	assert_str(RunStats.accuracy_text(98.4)).is_equal("98.4%")
	assert_str(RunStats.accuracy_text(100.0)).is_equal("100.0%")
	assert_str(RunStats.accuracy_text(75.0)).is_equal("75.0%")
	assert_str(RunStats.accuracy_text(-1.0)).is_equal("--.-%")


func test_grade() -> void:
	assert_str(RunStats.grade(98.0, 0)).is_equal("S")
	assert_str(RunStats.grade(100.0, 0)).is_equal("S")
	assert_str(RunStats.grade(98.0, 1)).is_equal("A")
	assert_str(RunStats.grade(93.0, 0)).is_equal("A")
	assert_str(RunStats.grade(92.99, 0)).is_equal("B")
	assert_str(RunStats.grade(85.0, 3)).is_equal("B")
	assert_str(RunStats.grade(75.0, 3)).is_equal("C")
	assert_str(RunStats.grade(74.9, 3)).is_equal("D")
	assert_str(RunStats.grade(0.0, 9)).is_equal("D")
	assert_str(RunStats.grade(-1.0, 0)).is_equal("-")


func test_grade_rank() -> void:
	assert_int(RunStats.grade_rank("S")).is_equal(5)
	assert_int(RunStats.grade_rank("A")).is_equal(4)
	assert_int(RunStats.grade_rank("B")).is_equal(3)
	assert_int(RunStats.grade_rank("C")).is_equal(2)
	assert_int(RunStats.grade_rank("D")).is_equal(1)
	assert_int(RunStats.grade_rank("-")).is_equal(0)
	assert_int(RunStats.grade_rank("")).is_equal(0)
	assert_int(RunStats.grade_rank("Z")).is_equal(0)


func _bin_of(offset_s: float) -> int:
	var h := RunStats.histogram(PackedFloat32Array([offset_s]))
	for i in h.size():
		if h[i] == 1:
			return i
	return -1


func test_histogram_shape_and_edges() -> void:
	var h := RunStats.histogram(PackedFloat32Array())
	assert_int(h.size()).is_equal(RunStats.BIN_COUNT)
	assert_int(RunStats.BIN_COUNT).is_equal(28)
	for c in h:
		assert_int(c).is_equal(0)
	assert_int(_bin_of(-0.070)).is_equal(0)
	assert_int(_bin_of(0.070)).is_equal(27)
	assert_int(_bin_of(-0.0651)).is_equal(0)
	assert_int(_bin_of(-0.065)).is_equal(1)
	assert_int(_bin_of(0.0)).is_equal(14)
	assert_int(_bin_of(-0.2)).is_equal(0)
	assert_int(_bin_of(0.2)).is_equal(27)
	assert_int(_bin_of(0.004999)).is_equal(14)
	assert_int(_bin_of(0.005)).is_equal(15)


func test_histogram_counts_known_run() -> void:
	var h := RunStats.histogram(PackedFloat32Array([-0.010, -0.010, 0.0, 0.002, 0.040, 0.3]))
	assert_int(h[12]).is_equal(2)
	assert_int(h[14]).is_equal(2)
	assert_int(h[22]).is_equal(1)
	assert_int(h[27]).is_equal(1)
	var total := 0
	for c in h:
		total += c
	assert_int(total).is_equal(6)


func test_mean_offset_ms() -> void:
	assert_int(RunStats.mean_offset_ms(PackedFloat32Array())).is_equal(0)
	assert_int(RunStats.mean_offset_ms(PackedFloat32Array([-0.010, -0.014]))).is_equal(-12)
	assert_int(RunStats.mean_offset_ms(PackedFloat32Array([0.008]))).is_equal(8)


func test_summary_text() -> void:
	assert_str(RunStats.summary_text(-12)).is_equal("Average 12 ms early")
	assert_str(RunStats.summary_text(8)).is_equal("Average 8 ms late")
	assert_str(RunStats.summary_text(2)).is_equal("Right on time (average 2 ms)")
	assert_str(RunStats.summary_text(0)).is_equal("Right on time (average 0 ms)")
	assert_str(RunStats.summary_text(3)).is_equal("Average 3 ms late")
	assert_str(RunStats.summary_text(-3)).is_equal("Average 3 ms early")


func test_recorder_collects_offsets_and_counts() -> void:
	var judge := FakeJudge.new()
	var rec := HitOffsetRecorder.new()
	rec.attach(judge)
	judge.judged.emit(0, 0, InputJudge.Judgment.PERFECT, -0.010)
	judge.judged.emit(1, 1, InputJudge.Judgment.GOOD, 0.040)
	judge.judged.emit(2, 2, InputJudge.Judgment.MISS, 0.12)
	var offs := rec.offsets()
	assert_int(offs.size()).is_equal(2)
	assert_float(offs[0]).is_equal_approx(-0.010, 1e-6)
	assert_float(offs[1]).is_equal_approx(0.040, 1e-6)
	assert_dict(rec.counts()).is_equal({"perfect": 1, "good": 1, "miss": 1})


func test_recorder_reset_and_detach() -> void:
	var judge := FakeJudge.new()
	var rec := HitOffsetRecorder.new()
	rec.attach(judge)
	judge.judged.emit(0, 0, InputJudge.Judgment.PERFECT, 0.001)
	rec.reset()
	assert_int(rec.offsets().size()).is_equal(0)
	assert_dict(rec.counts()).is_equal({"perfect": 0, "good": 0, "miss": 0})
	rec.detach()
	judge.judged.emit(0, 1, InputJudge.Judgment.PERFECT, 0.001)
	assert_int(rec.offsets().size()).is_equal(0)
	assert_int(judge.judged.get_connections().size()).is_equal(0)
	# attaching twice does not double-count
	rec.attach(judge)
	rec.attach(judge)
	judge.judged.emit(0, 2, InputJudge.Judgment.GOOD, -0.02)
	assert_int(rec.offsets().size()).is_equal(1)
	rec.detach()
