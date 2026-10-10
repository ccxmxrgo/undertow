extends GdUnitTestSuite
## MenuMusic autoload (02.2 plan 07, D-07): a random bundled song preview on the Preview bus,
## -12 dB, 600 ms fade-in, stop(fade), settings toggle, pulse_hz. Fades are stepped manually.

const MenuMusicScript := preload("res://src/autoload/menu_music.gd")

var _old_menu_music: bool
var _old_path: String


func before_test() -> void:
	_old_menu_music = Settings.menu_music
	_old_path = Settings.save_path
	Settings.save_path = "user://test_menu_music.cfg"
	Settings.menu_music = true


func after_test() -> void:
	Settings.menu_music = _old_menu_music
	Settings.save_path = _old_path
	for p in ["user://test_menu_music.cfg", "user://test_menu_music.cfg.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _music() -> Node:
	var m: Node = MenuMusicScript.new()
	m.auto_process = false
	add_child(m)
	auto_free(m)
	return m


func _stream() -> AudioStream:
	return AudioSynth.make_song([{"time": 0.0, "bpm": 120.0}], 40.0, 11025)


func test_preview_bus_sends_to_music_with_spectrum_analyzer() -> void:
	var idx := AudioServer.get_bus_index("Preview")
	assert_int(idx).is_greater(0)
	assert_str(String(AudioServer.get_bus_send(idx))).is_equal("Music")
	assert_int(AudioServer.get_bus_effect_count(idx)).is_greater_equal(1)
	assert_bool(AudioServer.get_bus_effect(idx, 0) is AudioEffectSpectrumAnalyzer).is_true()
	assert_int(idx).is_greater(AudioServer.get_bus_index("Music"))


func test_menu_music_is_an_autoload() -> void:
	var n := get_tree().root.get_node_or_null("MenuMusic")
	assert_object(n).is_not_null()
	assert_bool(n.has_method("start") and n.has_method("stop") and n.has_method("pulse_hz")).is_true()


func test_start_does_nothing_when_disabled() -> void:
	Settings.menu_music = false
	var m := _music()
	m.start()
	assert_bool(m.is_playing()).is_false()
	assert_str(m.state()).is_equal("idle")
	m.start_with_stream(_stream(), 1.0, 120.0)
	assert_bool(m.is_playing()).is_false()


func test_start_with_stream_plays_on_preview_and_fades_in_to_minus_12() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 1.0, 120.0)
	assert_bool(m.is_playing()).is_true()
	var p: AudioStreamPlayer = m.active_player()
	assert_str(String(p.bus)).is_equal("Preview")
	assert_bool(p.playing).is_true()
	assert_float(m.loop_start).is_equal_approx(1.0, 0.001)
	assert_float(p.volume_db).is_less(-40.0)
	m.step(0.3)
	assert_float(m.gain()).is_equal_approx(0.5, 0.02)
	m.step(0.31)
	assert_float(m.gain()).is_equal(1.0)
	assert_float(p.volume_db).is_equal_approx(-12.0, 0.01)


func test_stop_fades_out_within_the_fade_time() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.0, 120.0)
	m.step(1.0)
	m.stop(0.4)
	m.step(0.2)
	assert_bool(m.is_playing()).is_true()
	assert_float(m.gain()).is_equal_approx(0.5, 0.02)
	m.step(0.21)
	assert_bool(m.is_playing()).is_false()
	assert_str(m.state()).is_equal("idle")
	assert_bool(m.active_player().playing).is_false()


func test_stop_zero_stops_at_once() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.0, 120.0)
	m.stop(0.0)
	assert_bool(m.is_playing()).is_false()
	assert_bool(m.active_player().playing).is_false()


func test_start_while_stopping_fades_back_in() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.0, 120.0)
	m.step(1.0)
	m.stop(0.4)
	m.step(0.2)
	m.start()
	assert_str(m.state()).is_equal("playing")
	m.step(1.0)
	assert_float(m.gain()).is_equal(1.0)


func test_turning_the_setting_off_stops_playback() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.0, 120.0)
	m.step(1.0)
	Settings.menu_music = false
	Settings.settings_changed.emit()
	m.step(0.5)
	assert_bool(m.is_playing()).is_false()


func test_pulse_hz_follows_constant_bpm_else_half_hertz() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.0, 120.0)
	assert_float(m.pulse_hz()).is_equal_approx(2.0, 0.001)
	m.stop(0.0)
	m.start_with_stream(_stream(), 0.0, 0.0)
	assert_float(m.pulse_hz()).is_equal_approx(0.5, 0.001)
	assert_float(MenuMusicScript.pulse_for(100.0, 140.0)).is_equal_approx(0.5, 0.001)
	assert_float(MenuMusicScript.pulse_for(90.0, 90.0)).is_equal_approx(1.5, 0.001)


func test_only_bundled_res_entries_are_candidates() -> void:
	var a := SongEntry.new()
	a.source = "bundled"
	a.status = "ok"
	a.audio_files = ["res://songs/hrt/song.mp3"] as Array[String]
	var b := SongEntry.new()
	b.source = "songs"
	b.status = "ok"
	b.audio_files = ["C:/Users/x/song.ogg"] as Array[String]
	var c := SongEntry.new()
	c.source = "bundled"
	c.status = "ok"
	c.audio_files = ["C:/evil/song.ogg"] as Array[String]
	var d := SongEntry.new()
	d.source = "bundled"
	d.status = "broken"
	d.audio_files = ["res://songs/x/song.mp3"] as Array[String]
	var out: Array = MenuMusicScript.bundled_candidates([a, b, c, d, null])
	assert_int(out.size()).is_equal(1)
	assert_object(out[0]).is_same(a)


func test_loop_window_is_30_s_from_the_preview_start_clamped_to_the_stream() -> void:
	var w: Vector2 = MenuMusicScript.loop_window(20.0, 200.0)
	assert_float(w.x).is_equal_approx(20.0, 0.001)
	assert_float(w.y).is_equal_approx(50.0, 0.001)
	w = MenuMusicScript.loop_window(190.0, 200.0)
	assert_float(w.y).is_equal_approx(200.0, 0.001)
	assert_float(w.x).is_less(190.0)


func test_loop_crossfades_back_to_the_window_start() -> void:
	var m := _music()
	m.start_with_stream(_stream(), 0.5, 120.0)
	m.step(1.0)
	var first: AudioStreamPlayer = m.active_player()
	m.debug_position = m.loop_end - 0.2
	m.step(0.01)
	assert_bool(m.crossfading()).is_true()
	m.debug_position = -1.0
	m.step(0.45)
	assert_bool(m.crossfading()).is_false()
	assert_object(m.active_player()).is_not_same(first)
	assert_bool(first.playing).is_false()
	assert_bool(m.active_player().playing).is_true()
