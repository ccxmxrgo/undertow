extends GdUnitTestSuite
## StreakMilestones pure logic (D-08).


func test_is_milestone_true() -> void:
	for n in [10, 25, 50, 100, 200, 300, 1000]:
		assert_bool(StreakMilestones.is_milestone(n)).is_true()


func test_is_milestone_false() -> void:
	for n in [0, 5, 11, 24, 26, 49, 75, 99, 101, 150, -3]:
		assert_bool(StreakMilestones.is_milestone(n)).is_false()


func test_reached_crossing() -> void:
	assert_int(StreakMilestones.reached(9, 10)).is_equal(10)
	assert_int(StreakMilestones.reached(24, 25)).is_equal(25)
	assert_int(StreakMilestones.reached(99, 100)).is_equal(100)
	assert_int(StreakMilestones.reached(199, 200)).is_equal(200)


func test_reached_none_and_reset() -> void:
	assert_int(StreakMilestones.reached(10, 11)).is_equal(0)
	assert_int(StreakMilestones.reached(30, 0)).is_equal(0)
	assert_int(StreakMilestones.reached(25, 25)).is_equal(0)


func test_reached_highest_when_skipped() -> void:
	assert_int(StreakMilestones.reached(5, 30)).is_equal(25)
	assert_int(StreakMilestones.reached(0, 120)).is_equal(100)
