extends GdUnitTestSuite


func test_fake_time_starts_at_zero() -> void:
	var t := FakeTime.new()
	assert_int(t.now()).is_equal(0)


func test_fake_time_advance_usec() -> void:
	var t := FakeTime.new()
	t.advance_usec(1500)
	assert_int(t.now()).is_equal(1500)


func test_fake_time_advance_sec() -> void:
	var t := FakeTime.new()
	t.advance_sec(0.25)
	assert_int(t.now()).is_equal(250000)
