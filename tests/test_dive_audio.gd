extends GdUnitTestSuite
## DiveAudio (05-04, AV-03, D-02/D-03/D-04): downbeat sonar pings, hull creaks and the runtime
## low-pass filter on bus Music (added while a dive lives, removed by instance on exit).
## step() is driven directly with synthetic values; a real Conductor and HullScore are used only
## for the signal wiring (the test emits their signals; the pinned files are never edited).

const DT := 1.0 / 60.0
const SCENE := "res://scenes/gameplay.tscn"

var _saved_pings: bool
var _saved_hull: bool
var _saved_path: String
var _conductor: Conductor
var _score: HullScore
var _chart: ChartData


func before_test() -> void:
	_saved_pings = Settings.sonar_pings
	_saved_hull = Settings.hull_sounds
	_saved_path = Settings.save_path
	Settings.save_path = "user://test_dive_audio_settings.cfg"
	Settings.sonar_pings = true
	Settings.hull_sounds = true
	_strip_music_lpfs()
	_conductor = Conductor.new()
	_score = HullScore.new(JudgeConfig.new())
	if _chart == null:
		_chart = TestCharts.click_chart(120.0, 24)  # 4/4, bars every 2 s, ~14 s long


func after_test() -> void:
	Settings.sonar_pings = _saved_pings
	Settings.hull_sounds = _saved_hull
	Settings.save_path = _saved_path
	if _conductor != null and is_instance_valid(_conductor):
		_conductor.free()
	_conductor = null
	_score = null
	_strip_music_lpfs()


func _strip_music_lpfs() -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	if bus < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			AudioServer.remove_bus_effect(bus, i)


func _lpf_count(bus_name: StringName) -> int:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return 0
	var n := 0
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			n += 1
	return n


func _make(bound: bool = true) -> DiveAudio:
	var d := DiveAudio.new()
	add_child(d)
	d.set_process(false)  # the tests drive step() directly
	if bound:
		d.bind(_conductor, _chart, _score)
	return d


## Steps `secs` of frames at a fixed song time (muffle / creak tests do not need the clock).
func _steps(d: DiveAudio, secs: float, song_t: float = 1.0, paused: bool = false) -> float:
	var t := song_t
	var n := int(round(secs / DT))
	for i in range(n):
		d.step(DT, t, 0.0, 0.0, 0.0, paused)
		t += DT
	return t


# --- LPF lifetime -----------------------------------------------------------------------

func test_lpf_added_with_node_and_removed_on_free() -> void:
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)
	var d := _make()
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	assert_int(_lpf_count(&"SFX")).is_equal(0)
	assert_int(_lpf_count(&"Master")).is_equal(0)
	d.free()
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)


func test_two_nodes_in_a_row_leave_exactly_one() -> void:
	var a := _make()
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	remove_child(a)  # the retry path: the old run leaves the tree first
	a.free()
	var b := _make()
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	b.free()
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)


func test_stale_lpf_is_removed_on_start() -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	AudioServer.add_bus_effect(bus, AudioEffectLowPassFilter.new())  # a fake earlier run's leftover
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	var d := _make()
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	d.free()
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)


func test_removal_by_instance_survives_shifted_indices() -> void:
	var d := _make()
	var bus := AudioServer.get_bus_index(&"Music")
	var other := AudioEffectReverb.new()
	AudioServer.add_bus_effect(bus, other, 0)  # shifts the LPF index
	d.free()
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)
	var found := false
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == other:
			found = true
			AudioServer.remove_bus_effect(bus, i)
			break
	assert_bool(found).is_true()


func test_not_an_fx_group_node() -> void:
	var d := _make()
	await get_tree().process_frame
	assert_bool(d.is_in_group(UiKit.FX_GROUP)).is_false()
	d.free()


# --- Muffle -----------------------------------------------------------------------------

func test_hull_follow_and_heal() -> void:
	var d := _make()
	_steps(d, 0.2)
	assert_bool(d.lpf_enabled()).is_false()
	_score.hull_changed.emit(40.0, -60.0)
	_steps(d, 1.5)
	assert_bool(d.lpf_enabled()).is_true()
	var want := HullAudioCurve.cutoff_for_hull(40.0)
	assert_float(d.current_cutoff()).is_between(want * 0.97, want * 1.03)
	_score.hull_changed.emit(90.0, 50.0)  # a Ballast heal
	_steps(d, 1.5)
	assert_bool(d.lpf_enabled()).is_false()
	d.free()


func test_slam_reaches_floor_and_holds() -> void:
	var d := _make()
	_steps(d, 0.1)
	_score.failed.emit()
	assert_bool(d.slammed()).is_true()
	_steps(d, 0.35)
	assert_float(d.current_cutoff()).is_less_equal(HullAudioCurve.FLOOR_HZ * 1.05)
	assert_bool(d.lpf_enabled()).is_true()
	_steps(d, 2.0)
	assert_float(d.current_cutoff()).is_less_equal(HullAudioCurve.FLOOR_HZ * 1.05)
	d.free()


func test_hull_sounds_off_opens_filter_and_no_creaks() -> void:
	Settings.hull_sounds = false
	var d := _make()
	d.set_live(true)
	_score.hull_changed.emit(20.0, -80.0)
	_steps(d, 60.0)
	assert_bool(d.lpf_enabled()).is_false()
	assert_float(d.current_cutoff()).is_equal(HullAudioCurve.OPEN_HZ)
	assert_int(d.creak_count()).is_equal(0)
	d.free()


# --- Pings ------------------------------------------------------------------------------

func _ping_run(d: DiveAudio, t0: float, t1: float, pause_from: float = INF, pause_to: float = INF) -> void:
	var t := t0
	while t < t1:
		if t >= pause_from and t < pause_to:
			# Paused: song time is held; several frames pass.
			for i in range(30):
				d.step(DT, t, 0.0, 0.0, 0.0, true)
			pause_from = INF
			continue
		d.step(DT, t, 0.0, 0.0, 0.0, false)
		t += DT


func test_pings_on_every_bar() -> void:
	assert_float(ProgressTrack.song_length_of(_chart)).is_greater_equal(12.0)
	var d := _make()
	d.set_live(true)
	_ping_run(d, -1.0, 9.0)
	assert_int(d.ping_count()).is_equal(5)  # bars 0, 2, 4, 6, 8
	d.free()


func test_pause_adds_no_pings_and_no_double_after_resume() -> void:
	var d := _make()
	d.set_live(true)
	_ping_run(d, -1.0, 9.0, 3.0, 3.5)
	assert_int(d.ping_count()).is_equal(5)
	d.free()


func test_resumed_signal_resets_without_double_ping() -> void:
	var d := _make()
	d.set_live(true)
	_ping_run(d, -1.0, 4.0)
	var before := d.ping_count()  # bars 0, 2 and 4 (4 is within the lead at 3.9 s)
	_conductor.resumed.emit()
	_ping_run(d, 3.9, 9.0)
	assert_int(d.ping_count()).is_equal(5)
	assert_int(before).is_equal(3)
	d.free()


func test_pings_off_setting() -> void:
	Settings.sonar_pings = false
	var d := _make()
	d.set_live(true)
	_ping_run(d, -1.0, 9.0)
	assert_int(d.ping_count()).is_equal(0)
	d.free()


func test_no_pings_when_not_live() -> void:
	var d := _make()
	_ping_run(d, -1.0, 9.0)
	assert_int(d.ping_count()).is_equal(0)
	d.free()


func test_no_pings_past_song_end() -> void:
	var d := _make()
	d.set_live(true)
	var end := ProgressTrack.song_length_of(_chart)
	_ping_run(d, end + 0.01, end + 6.0)
	assert_int(d.ping_count()).is_equal(0)
	d.free()


func test_unbound_node_is_inert() -> void:
	var d := _make(false)
	d.set_live(true)
	_ping_run(d, -1.0, 3.0)
	assert_int(d.ping_count()).is_equal(0)
	d.free()


# --- Creaks -----------------------------------------------------------------------------

func test_low_hull_creaks() -> void:
	var d := _make()
	d.set_live(true)
	_score.hull_changed.emit(20.0, -80.0)
	_steps(d, 60.0)
	assert_int(d.creak_count()).is_greater(0)
	d.free()


func test_high_hull_no_creaks() -> void:
	var d := _make()
	d.set_live(true)
	_score.hull_changed.emit(90.0, -10.0)
	_steps(d, 60.0)
	assert_int(d.creak_count()).is_equal(0)
	d.free()


# --- Scene level ------------------------------------------------------------------------

func test_gameplay_scene_lpf_lifetime() -> void:
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	await get_tree().process_frame
	assert_object(gp.dive_audio).is_not_null()
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	gp.restart(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(DiveAudio.music_lpf_count()).is_equal(1)
	gp.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(DiveAudio.music_lpf_count()).is_equal(0)
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL
