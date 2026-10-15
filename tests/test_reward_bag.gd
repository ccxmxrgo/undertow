extends GdUnitTestSuite
## 03-SPEC reqs 3 and 7: the seeded reward bag and the reward table.


func _draws(seed_value: int, n: int) -> Array[int]:
	var b := RewardBag.new(seed_value)
	var out: Array[int] = []
	for i in range(n):
		out.append(b.draw())
	return out


func _sorted(a: Array) -> Array:
	var c := a.duplicate()
	c.sort()
	return c


func test_nine_draws_give_each_reward_once() -> void:
	var d := _draws(77, 9)
	assert_array(_sorted(d)).is_equal(_sorted(Reward.ALL))


func test_second_bag_is_again_a_permutation() -> void:
	var d := _draws(77, 18)
	assert_array(_sorted(d.slice(9, 18))).is_equal(_sorted(Reward.ALL))


func test_same_seed_same_sequence() -> void:
	assert_array(_draws(77, 18)).is_equal(_draws(77, 18))


func test_different_seed_differs() -> void:
	assert_array(_draws(77, 18)).is_not_equal(_draws(78, 18))


func test_remaining_is_a_copy() -> void:
	var b := RewardBag.new(5)
	b.draw()
	var r := b.remaining()
	assert_int(r.size()).is_equal(8)
	r.clear()
	assert_int(b.remaining().size()).is_equal(8)


func test_seed_for_is_stable_per_seat() -> void:
	assert_int(RewardBag.seed_for(42, 1)).is_equal(RewardBag.seed_for(42, 1))
	assert_int(RewardBag.seed_for(42, 1)).is_not_equal(RewardBag.seed_for(42, 2))


func test_reward_all_has_nine_and_no_lane_flip() -> void:
	assert_int(Reward.ALL.size()).is_equal(9)
	assert_bool(Reward.Id.has("LANE_FLIP")).is_false()
	assert_bool(Reward.ALL.has(Reward.Id.CROSSED_WIRES)).is_true()


func test_six_disruptors_three_buffs() -> void:
	var dis := 0
	var buff := 0
	for id in Reward.ALL:
		if Reward.is_disruptor(id):
			dis += 1
		elif Reward.is_buff(id):
			buff += 1
	assert_int(dis).is_equal(6)
	assert_int(buff).is_equal(3)


func test_debris_kinds_not_in_bag() -> void:
	for id in [Reward.Id.SILT, Reward.Id.GROAN]:
		assert_int(Reward.kind_of(id)).is_equal(Reward.Kind.DEBRIS)
		assert_bool(Reward.is_debris(id)).is_true()
		assert_bool(Reward.ALL.has(id)).is_false()
		assert_str(Reward.glyph(id)).is_equal("debris")


func test_keys_round_trip() -> void:
	for id in Reward.Id.values():
		assert_int(Reward.from_key(Reward.key_of(id))).is_equal(id)
	assert_int(Reward.from_key("lane_flip")).is_equal(-1)
	assert_str(Reward.key_of(Reward.Id.INK_CLOUD)).is_equal("ink_cloud")
	assert_str(Reward.hud_name(Reward.Id.INK_CLOUD)).is_equal("INK CLOUD")
	assert_str(Reward.feed_name(Reward.Id.INK_CLOUD)).is_equal("Ink Cloud")


func test_descriptions_read_config() -> void:
	var cfg := VersusConfig.new()
	assert_str(Reward.description(Reward.Id.CROSSED_WIRES, cfg)).is_equal("Two lanes trade places for 4 bars.")
	assert_str(Reward.description(Reward.Id.SONAR_JAM, cfg)).is_equal("Notes lose colour and shape for 3 bars.")
	assert_str(Reward.description(Reward.Id.BALLAST_PATCH, cfg)).is_equal("Repairs 25% of your hull.")
	cfg.bars_ink_cloud = 6
	assert_str(Reward.description(Reward.Id.INK_CLOUD, cfg)).is_equal("Ink hides the bottom of the highway for 6 bars.")
	cfg.ballast_restore_ratio = 0.5
	assert_str(Reward.description(Reward.Id.BALLAST_PATCH, cfg)).is_equal("Repairs 50% of your hull.")


func test_config_validated_clamps() -> void:
	var cfg := VersusConfig.new()
	cfg.reward_threshold_ratio = 3.0
	cfg.bars_ink_cloud = 0
	cfg.warhead_count = 50
	cfg.torpedo_travel_beats = 0
	var v := cfg.validated()
	assert_float(v.reward_threshold_ratio).is_equal(1.0)
	assert_int(v.bars_ink_cloud).is_equal(1)
	assert_int(v.warhead_count).is_equal(8)
	assert_int(v.torpedo_travel_beats).is_equal(1)
	assert_float(cfg.reward_threshold_ratio).is_equal(3.0)
	cfg.warhead_count = 0
	assert_int(cfg.validated().warhead_count).is_equal(0)


func test_bars_for() -> void:
	var cfg := VersusConfig.new()
	assert_int(cfg.bars_for(Reward.Id.DEPTH_CHARGE)).is_equal(2)
	assert_int(cfg.bars_for(Reward.Id.SONAR_JAM)).is_equal(3)
	assert_int(cfg.bars_for(Reward.Id.DECOY_FLARE)).is_equal(8)
	assert_int(cfg.bars_for(Reward.Id.OVERCLOCK)).is_equal(4)
	assert_int(cfg.bars_for(Reward.Id.BALLAST_PATCH)).is_equal(0)
	assert_int(cfg.bars_for(Reward.Id.SILT)).is_equal(1)
