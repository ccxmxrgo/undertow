extends GdUnitTestSuite
## SmfReader: Standard MIDI File grammar, hardened against hostile bytes (D-05, D-08, D-09, D-10).

const BAD := "Unreadable .mid"


func _e(tick: int, bytes: PackedByteArray) -> Dictionary:
	return MidiWriter.ev(tick, bytes)


func _tempo_track() -> PackedByteArray:
	return MidiWriter.track([
		_e(0, MidiWriter.tempo(500000)),
		_e(0, MidiWriter.ts(4, 2)),
		_e(1920, MidiWriter.tempo(400000)),
		_e(3840, MidiWriter.ts(3, 2)),
	])


func _guitar_events() -> Array:
	return [
		_e(0, MidiWriter.name("PART GUITAR")),
		_e(0, MidiWriter.on(96)),
		_e(240, MidiWriter.off(96)),
		_e(480, MidiWriter.on(97)),
		_e(720, MidiWriter.off(97)),
		_e(960, MidiWriter.on(98)),
		_e(1200, MidiWriter.off(98)),
	]


func _valid() -> PackedByteArray:
	return MidiWriter.file([_tempo_track(), MidiWriter.track(_guitar_events())])


func test_vlq_encoding() -> void:
	assert_array(Array(MidiWriter.vlq(0))).is_equal([0x00])
	assert_array(Array(MidiWriter.vlq(127))).is_equal([0x7F])
	assert_array(Array(MidiWriter.vlq(128))).is_equal([0x81, 0x00])
	assert_array(Array(MidiWriter.vlq(0x0FFFFFFF))).is_equal([0xFF, 0xFF, 0xFF, 0x7F])


func test_valid_type1_file() -> void:
	var r := SmfReader.read(_valid())
	assert_bool(r["ok"]).is_true()
	assert_str(r["error"]).is_equal("")
	assert_int(r["format"]).is_equal(1)
	assert_int(r["division"]).is_equal(480)
	var tr: Array = r["tracks"]
	assert_int(tr.size()).is_equal(2)
	var t0: Dictionary = tr[0]
	assert_int(t0["tempos"].size()).is_equal(2)
	assert_int(t0["tempos"][0]["uspqn"]).is_equal(500000)
	assert_int(t0["tempos"][0]["tick"]).is_equal(0)
	assert_int(t0["tempos"][1]["uspqn"]).is_equal(400000)
	assert_int(t0["tempos"][1]["tick"]).is_equal(1920)
	assert_int(t0["time_sigs"].size()).is_equal(2)
	assert_int(t0["time_sigs"][0]["num"]).is_equal(4)
	assert_int(t0["time_sigs"][0]["exp"]).is_equal(2)
	assert_int(t0["time_sigs"][1]["num"]).is_equal(3)
	assert_int(t0["time_sigs"][1]["tick"]).is_equal(3840)
	var t1: Dictionary = tr[1]
	assert_str(t1["name"]).is_equal("PART GUITAR")
	var notes: Array = t1["notes"]
	assert_int(notes.size()).is_equal(6)
	var pitches: Array = []
	var ticks: Array = []
	var ons: Array = []
	for n in notes:
		pitches.append(n["pitch"])
		ticks.append(n["tick"])
		ons.append(n["on"])
	assert_array(pitches).is_equal([96, 96, 97, 97, 98, 98])
	assert_array(ticks).is_equal([0, 240, 480, 720, 960, 1200])
	assert_array(ons).is_equal([true, false, true, false, true, false])


func test_velocity_zero_is_note_off() -> void:
	var ev: Array = [_e(0, MidiWriter.on(96)), _e(100, MidiWriter.on(96, 0))]
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev)]))
	assert_bool(r["ok"]).is_true()
	var notes: Array = r["tracks"][1]["notes"]
	assert_bool(notes[0]["on"]).is_true()
	assert_bool(notes[1]["on"]).is_false()


func test_running_status_matches_explicit() -> void:
	var ev: Array = []
	for i in 6:
		ev.append(_e(i * 10, MidiWriter.on(96 + i % 5)))
		ev.append(_e(i * 10 + 5, MidiWriter.on(96 + i % 5, 0)))
	var a := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev, false)]))
	var b := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev, true)]))
	assert_bool(a["ok"]).is_true()
	assert_bool(b["ok"]).is_true()
	assert_int(b["tracks"][1]["notes"].size()).is_equal(12)
	assert_array(b["tracks"][1]["notes"]).is_equal(a["tracks"][1]["notes"])


func test_running_status_survives_meta_and_sysex() -> void:
	# Explicit status once, then meta + SysEx + running-status data bytes.
	var body := PackedByteArray()
	body.append_array(PackedByteArray([0x00, 0x90, 96, 100]))
	body.append_array(PackedByteArray([0x00]))
	body.append_array(MidiWriter.text("hi"))
	body.append_array(PackedByteArray([0x0A, 97, 100]))  # running status after FF 01
	body.append_array(PackedByteArray([0x00]))
	body.append_array(MidiWriter.sysex(PackedByteArray([1, 2, 3, 0xF7])))
	body.append_array(PackedByteArray([0x0A, 98, 100]))  # running status after F0
	body.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"][1]["notes"].size()).is_equal(3)
	assert_int(r["tracks"][1]["texts"].size()).is_equal(1)


func test_data_byte_without_status_fails() -> void:
	var body := PackedByteArray([0x00, 96, 100, 0x00, 0xFF, 0x2F, 0x00])
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(BAD)


func test_five_byte_vlq_fails() -> void:
	var body := PackedByteArray([0x81, 0x81, 0x81, 0x81, 0x01, 0x90, 96, 100])
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(BAD)


func test_header_rejections() -> void:
	var good := _valid()
	assert_str(SmfReader.read(good.slice(0, 13))["error"]).is_equal(BAD)
	assert_str(SmfReader.read(PackedByteArray())["error"]).is_equal(BAD)
	var magic := good.duplicate()
	magic[0] = 0x58
	assert_str(SmfReader.read(magic)["error"]).is_equal(BAD)
	var short_len := good.duplicate()
	short_len[7] = 4
	assert_str(SmfReader.read(short_len)["error"]).is_equal(BAD)
	# SMPTE division (bit 15 set)
	assert_str(SmfReader.read(MidiWriter.file([_tempo_track()], 0xE728))["error"]).is_equal(BAD)
	# division 0
	assert_str(SmfReader.read(MidiWriter.file([_tempo_track()], 0))["error"]).is_equal(BAD)
	# format 2
	assert_str(SmfReader.read(MidiWriter.file([_tempo_track()], 480, 2))["error"]).is_equal(BAD)


func test_format0_is_readable() -> void:
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track(_guitar_events())], 480, 0))
	assert_bool(r["ok"]).is_true()
	assert_int(r["format"]).is_equal(0)


func test_long_header_is_honoured() -> void:
	var head := PackedByteArray([0, 1, 0, 2, 1, 0xE0, 0xAA, 0xBB])
	var out := MidiWriter.chunk("MThd", head)
	out.append_array(MidiWriter.chunk("MTrk", _tempo_track()))
	out.append_array(MidiWriter.chunk("MTrk", MidiWriter.track(_guitar_events())))
	var r := SmfReader.read(out)
	assert_bool(r["ok"]).is_true()
	assert_int(r["division"]).is_equal(480)
	assert_int(r["tracks"].size()).is_equal(2)


func test_unknown_chunk_skipped_and_overrun_chunk_fails() -> void:
	var out := MidiWriter.chunk("MThd", PackedByteArray([0, 1, 0, 2, 1, 0xE0]))
	out.append_array(MidiWriter.chunk("MTrk", _tempo_track()))
	out.append_array(MidiWriter.chunk("XFIH", PackedByteArray([1, 2, 3])))
	out.append_array(MidiWriter.chunk("MTrk", MidiWriter.track(_guitar_events())))
	var r := SmfReader.read(out)
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"].size()).is_equal(2)
	var bad := MidiWriter.chunk("MThd", PackedByteArray([0, 1, 0, 1, 1, 0xE0]))
	bad.append_array(PackedByteArray([0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, 200, 1, 2]))
	assert_str(SmfReader.read(bad)["error"]).is_equal(BAD)


func test_sysex_skipped_by_length_and_ps_stored() -> void:
	var ev: Array = [
		_e(0, MidiWriter.sysex(PackedByteArray([0xFF, 0xF7, 0xFF, 0xF7, 0x01]))),
		_e(0, PackedByteArray([0xF7, 0x03, 0xFF, 0xF7, 0xFF])),
		_e(100, MidiWriter.ps_open(3, true)),
		_e(200, MidiWriter.on(96)),
		_e(300, MidiWriter.off(96)),
	]
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev)]))
	assert_bool(r["ok"]).is_true()
	var t: Dictionary = r["tracks"][1]
	assert_int(t["notes"].size()).is_equal(2)
	assert_int(t["sysex"].size()).is_equal(1)
	assert_int(t["sysex"][0]["tick"]).is_equal(100)
	assert_array(Array(t["sysex"][0]["data"])).is_equal([0x50, 0x53, 0x00, 0x00, 3, 0x01, 1, 0xF7])


func test_meta_overrun_fails_and_missing_eot_tolerated() -> void:
	var body := PackedByteArray([0x00, 0xFF, 0x01, 0x20, 65, 66])
	assert_str(SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))["error"]).is_equal(BAD)
	var ok_body := MidiWriter.track(_guitar_events(), false, false)
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), ok_body]))
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"][1]["notes"].size()).is_equal(6)


func test_system_status_bytes_fail() -> void:
	for st in [0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF8, 0xFA, 0xFE]:
		var body := PackedByteArray([0x00, st, 0x00, 0xFF, 0x2F, 0x00])
		var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))
		assert_bool(r["ok"]).is_false()
		assert_str(r["error"]).is_equal(BAD)


func test_text_latin1_and_truncation() -> void:
	var latin := PackedByteArray([0xFF, 0x01, 0x03, 0x41, 0xE9, 0x42])
	var long_text := "x".repeat(SmfReader.MAX_TEXT + 100)
	var ev: Array = [
		_e(0, latin),
		_e(0, MidiWriter.text(long_text)),
		_e(10, MidiWriter.on(96)),
		_e(20, MidiWriter.off(96)),
	]
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev)]))
	assert_bool(r["ok"]).is_true()
	var t: Dictionary = r["tracks"][1]
	assert_int(t["texts"].size()).is_equal(2)
	assert_int(String(t["texts"][1]["text"]).length()).is_equal(SmfReader.MAX_TEXT)
	assert_int(t["notes"].size()).is_equal(2)


func test_track_name_is_first_at_tick_zero() -> void:
	var ev: Array = [
		_e(0, MidiWriter.name("PART GUITAR")),
		_e(960, MidiWriter.name("OTHER")),
		_e(960, MidiWriter.on(96)),
	]
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev)]))
	assert_str(r["tracks"][1]["name"]).is_equal("PART GUITAR")


func test_keep_names_skips_other_tracks() -> void:
	var drums: PackedByteArray = MidiWriter.track([_e(0, MidiWriter.name("PART DRUMS"))], false, false)
	drums.append_array(PackedByteArray([0x00, 0xF1, 0x00, 0xF2]))  # corrupt body, never walked
	var r := SmfReader.read(
			MidiWriter.file([_tempo_track(), MidiWriter.track(_guitar_events()), drums]),
			{}, PackedStringArray(["PART GUITAR"]))
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"].size()).is_equal(3)
	assert_int(r["tracks"][0]["tempos"].size()).is_equal(2)
	assert_int(r["tracks"][1]["notes"].size()).is_equal(6)
	assert_bool(r["tracks"][2]["skipped"]).is_true()
	assert_int(r["tracks"][2]["notes"].size()).is_equal(0)


func test_caps_via_limits() -> void:
	var r := SmfReader.read(_valid(), {"max_bytes": 10})
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(SongEntry.ERR_TOO_LARGE)
	var three := MidiWriter.file([_tempo_track(), MidiWriter.track(_guitar_events()), MidiWriter.track(_guitar_events())])
	r = SmfReader.read(three, {"max_tracks": 1})
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"].size()).is_equal(1)
	assert_int(r["warnings"]).is_greater_equal(1)
	var ev: Array = []
	for i in 5:
		ev.append(_e(i * 10, MidiWriter.on(96 + i)))
	r = SmfReader.read(MidiWriter.file([MidiWriter.track([]), MidiWriter.track(ev)]), {"max_entries": 2})
	assert_bool(r["ok"]).is_true()
	assert_int(r["tracks"][1]["notes"].size()).is_equal(2)
	assert_int(r["warnings"]).is_greater_equal(1)


func test_tick_overflow_fails() -> void:
	var big := MidiWriter.vlq(0x0FFFFFFF)
	var body := PackedByteArray()
	for i in 9:
		body.append_array(big)
		body.append_array(PackedByteArray([0x90, 96, 100]))
	var r := SmfReader.read(MidiWriter.file([MidiWriter.track([]), body]))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(BAD)


func test_truncation_sweep_never_raises() -> void:
	var good := _valid()
	for n in good.size():
		var r := SmfReader.read(good.slice(0, n))
		assert_bool(r.has("ok")).is_true()
		if not r["ok"]:
			assert_str(r["error"]).is_equal(BAD)


func test_fuzz_terminates_quickly() -> void:
	var good := _valid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var t0 := Time.get_ticks_msec()
	for it in 300:
		var m := good.duplicate()
		for k in rng.randi_range(1, 8):
			m[rng.randi() % m.size()] = rng.randi() % 256
		var r := SmfReader.read(m)
		assert_bool(r.has("ok")).is_true()
	assert_int(Time.get_ticks_msec() - t0).is_less(5000)


func test_random_bytes_never_throw() -> void:
	var rnd := PackedByteArray()
	for i in 4096:
		rnd.append((i * 131 + 7) % 256)
	var r := SmfReader.read(rnd)
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(BAD)
