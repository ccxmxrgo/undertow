extends GdUnitTestSuite
## 05-06: the slow-frame results hint (D-06, AV-05). LowEffectsHint helper; the results-screen and
## gameplay tests follow below.

const SETTINGS_TMP := "user://test_low_effects_hint_settings.cfg"

var _low: bool
var _reduce: bool
var _save_path: String
var _changed: int = 0


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	_save_path = Settings.save_path
	Settings.save_path = SETTINGS_TMP
	Settings.low_effects = false
	Settings.reduce_motion = false
	_changed = 0
	_rm()


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce
	Settings.save_path = _save_path
	_rm()


func _rm() -> void:
	for p in [SETTINGS_TMP, SETTINGS_TMP + ".tmp", SETTINGS_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _count_changed() -> void:
	_changed += 1


# ---- LowEffectsHint ---------------------------------------------------------------------

func test_wanted_only_for_a_real_true_with_low_effects_off() -> void:
	assert_bool(LowEffectsHint.wanted({"slow_frames": true})).is_true()
	assert_bool(LowEffectsHint.wanted({"slow_frames": false})).is_false()
	assert_bool(LowEffectsHint.wanted({})).is_false()
	assert_bool(LowEffectsHint.wanted({"slow_frames": 1})).is_false()
	assert_bool(LowEffectsHint.wanted({"slow_frames": "true"})).is_false()
	Settings.low_effects = true
	assert_bool(LowEffectsHint.wanted({"slow_frames": true})).is_false()


func test_enable_low_effects_sets_saves_and_signals_once() -> void:
	Settings.settings_changed.connect(_count_changed)
	LowEffectsHint.enable_low_effects()
	Settings.settings_changed.disconnect(_count_changed)
	assert_bool(Settings.low_effects).is_true()
	assert_int(_changed).is_equal(1)
	assert_bool(FileAccess.file_exists(SETTINGS_TMP)).is_true()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SETTINGS_TMP)).is_equal(OK)
	assert_bool(cfg.get_value("display", "low_effects", false)).is_true()


func test_copy_and_rect() -> void:
	assert_str(LowEffectsHint.TEXT).is_equal("Some frames came late on this PC. Low effects can help.")
	assert_str(LowEffectsHint.DONE_TEXT).is_equal("Low effects is on. Change it in Settings > Display.")
	assert_str(LowEffectsHint.BUTTON_TEXT).is_equal("Turn on Low effects")
	assert_str(LowEffectsHint.DONE_BUTTON_TEXT).is_equal("Low effects on")
	assert_object(LowEffectsHint.BUTTON_RECT).is_equal(Rect2(1368.0, 752.0, 400.0, 64.0))
	assert_bool(LowEffectsHint.BUTTON_RECT.end.x <= ResultsScreen.RIGHT_X).is_true()
