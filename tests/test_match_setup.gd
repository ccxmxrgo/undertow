extends GdUnitTestSuite
## D-18, D-21, D-27: MatchSetup launch record, callsigns and Settings persistence.

const PATH := "user://test_match_setup_settings.cfg"

var _saved := {}
var _saved_path := ""


func before_test() -> void:
	_saved_path = Settings.save_path
	_saved = {
		"rivals": Settings.versus_rivals, "skill": Settings.versus_skill,
		"song": Settings.versus_song_id, "diff": Settings.versus_difficulty,
		"training": Settings.training_payload,
	}
	Settings.save_path = PATH
	MatchSetup.pending = null


func after_test() -> void:
	Settings.versus_rivals = _saved["rivals"]
	Settings.versus_skill = _saved["skill"]
	Settings.versus_song_id = _saved["song"]
	Settings.versus_difficulty = _saved["diff"]
	Settings.training_payload = _saved["training"]
	Settings.save_path = _saved_path
	MatchSetup.pending = null
	for p in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_defaults() -> void:
	var m := MatchSetup.new()
	assert_int(m.mode).is_equal(MatchSetup.MODE_VERSUS)
	assert_int(m.rivals).is_equal(3)
	assert_str(m.skill).is_equal("regular")
	assert_str(m.training).is_equal("off")


func test_clamped() -> void:
	var m := MatchSetup.new()
	m.rivals = 7
	m.skill = "boss"
	m.training = "lane_flip"
	var c := m.clamped()
	assert_int(c.rivals).is_equal(3)
	assert_str(c.skill).is_equal("regular")
	assert_str(c.training).is_equal("off")
	m.rivals = 0
	m.skill = "veteran"
	m.training = "sonar_jam"
	c = m.clamped()
	assert_int(c.rivals).is_equal(1)
	assert_str(c.skill).is_equal("veteran")
	assert_str(c.training).is_equal("sonar_jam")
	assert_int(m.rivals).is_equal(0)


func test_training_values_order() -> void:
	assert_array(MatchSetup.TRAINING_VALUES).is_equal(["off", "all", "crossed_wires", "ghost_notes",
		"ink_cloud", "pressure_crack", "sonar_jam", "depth_charge"])


func test_callsigns_distinct_from_list() -> void:
	var c := MatchSetup.callsigns(1234, 3)
	assert_int(c.size()).is_equal(3)
	var seen := {}
	for n in c:
		assert_bool(MatchSetup.CALLSIGNS.has(n)).is_true()
		seen[n] = true
	assert_int(seen.size()).is_equal(3)


func test_callsigns_same_seed_same_order() -> void:
	assert_array(MatchSetup.callsigns(99, 3)).is_equal(MatchSetup.callsigns(99, 3))


func test_callsigns_vary_with_seed() -> void:
	var orders := {}
	for s in range(1, 21):
		orders[",".join(MatchSetup.callsigns(s, 3))] = true
	assert_int(orders.size()).is_greater_equal(2)


func test_callsigns_clamps_count() -> void:
	assert_int(MatchSetup.callsigns(5, 0).size()).is_equal(0)
	assert_int(MatchSetup.callsigns(5, 99).size()).is_equal(MatchSetup.CALLSIGNS.size())


func test_rematch_copies_with_new_seed() -> void:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.song_id = "builtin:hrt"
	m.difficulty = "hard"
	m.rivals = 2
	m.skill = "rookie"
	m.seed = 42
	m.training = "off"
	var r := m.rematch()
	assert_int(r.mode).is_equal(m.mode)
	assert_str(r.song_id).is_equal("builtin:hrt")
	assert_str(r.difficulty).is_equal("hard")
	assert_int(r.rivals).is_equal(2)
	assert_str(r.skill).is_equal("rookie")
	assert_str(r.training).is_equal("off")
	assert_int(r.seed).is_not_equal(42)


func test_training_reward() -> void:
	assert_int(MatchSetup.training_reward("off")).is_equal(-1)
	assert_int(MatchSetup.training_reward("all")).is_equal(-2)
	assert_int(MatchSetup.training_reward("ink_cloud")).is_equal(Reward.Id.INK_CLOUD)
	assert_int(MatchSetup.training_reward("bogus")).is_equal(-1)


func test_settings_persistence() -> void:
	var m := MatchSetup.new()
	m.song_id = "builtin:invisible"
	m.difficulty = "expert"
	m.rivals = 1
	m.skill = "veteran"
	m.training = "depth_charge"
	m.save_to_settings()
	assert_int(Settings.versus_rivals).is_equal(1)
	assert_str(Settings.training_payload).is_equal("depth_charge")
	assert_bool(FileAccess.file_exists(PATH)).is_true()
	var f := MatchSetup.from_settings()
	assert_str(f.song_id).is_equal("builtin:invisible")
	assert_str(f.difficulty).is_equal("expert")
	assert_int(f.rivals).is_equal(1)
	assert_str(f.skill).is_equal("veteran")
	assert_str(f.training).is_equal("depth_charge")


func test_new_seed_varies() -> void:
	var seeds := {}
	for i in range(5):
		seeds[MatchSetup.new_seed()] = true
	assert_int(seeds.size()).is_greater(1)
