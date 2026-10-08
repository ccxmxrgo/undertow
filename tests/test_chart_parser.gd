extends GdUnitTestSuite
## ChartParser + SongIni: grammar, encodings, tolerance, hostile input, caps (SONG-01, SONG-06).

const DIR := "res://tests/fixtures/charts/"


func _fx(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(DIR + name)


func _parse(name: String) -> ParsedChart:
	return ChartParser.parse_bytes(_fx(name))


func _ticks(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		out.append(e["tick"])
	return out


func test_minimal() -> void:
	var pc := _parse("minimal.chart")
	assert_bool(pc.ok).is_true()
	assert_str(pc.error).is_equal("")
	assert_int(pc.resolution).is_equal(192)
	assert_int(pc.tempo.size()).is_equal(1)
	assert_int(pc.tempo[0]["tick"]).is_equal(0)
	assert_int(pc.tempo[0]["milli_bpm"]).is_equal(120000)
	assert_bool(pc.tracks.has("ExpertSingle")).is_true()
	assert_int(pc.tracks["ExpertSingle"].size()).is_equal(3)
	assert_str(pc.song["name"]).is_equal("Minimal")
	assert_int(pc.events.size()).is_equal(1)
	assert_str(pc.events[0]["text"]).is_equal("section Intro")
	assert_int(pc.warnings).is_equal(0)


func test_crlf_and_boms_parse_identically() -> void:
	var text := _fx("minimal.chart").get_string_from_utf8()
	var base := ChartParser.parse_bytes(text.to_utf8_buffer())
	var crlf := ChartParser.parse_bytes(text.replace("\n", "\r\n").to_utf8_buffer())
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	bom.append_array(text.to_utf8_buffer())
	var u8 := ChartParser.parse_bytes(bom)
	var le := PackedByteArray([0xFF, 0xFE])
	le.append_array(text.to_utf16_buffer())
	var u16le := ChartParser.parse_bytes(le)
	var be := PackedByteArray([0xFE, 0xFF])
	var raw := text.to_utf16_buffer()
	var j := 0
	while j + 1 < raw.size():
		be.append(raw[j + 1])
		be.append(raw[j])
		j += 2
	var u16be := ChartParser.parse_bytes(be)
	for pc in [crlf, u8, u16le, u16be]:
		assert_bool(pc.ok).is_true()
		assert_int(pc.resolution).is_equal(base.resolution)
		assert_array(pc.tempo).is_equal(base.tempo)
		assert_int(pc.tracks["ExpertSingle"].size()).is_equal(3)
		assert_str(pc.song["name"]).is_equal("Minimal")


func test_out_of_order_is_stably_sorted() -> void:
	var pc := _parse("out_of_order.chart")
	assert_bool(pc.ok).is_true()
	var t: Array = pc.tracks["ExpertSingle"]
	assert_array(_ticks(t)).is_equal([0, 192, 192, 192, 384])
	# file order kept for equal ticks: N 1, N 3, N 0
	assert_int(t[1]["a"]).is_equal(1)
	assert_int(t[2]["a"]).is_equal(3)
	assert_int(t[3]["a"]).is_equal(0)
	assert_array(_ticks(pc.tempo)).is_equal([0, 768])
	assert_int(pc.tempo[1]["milli_bpm"]).is_equal(180000)


func test_quotes_and_keys() -> void:
	var txt := "[Song]\n{\n  NAME = \"He said \"hi\" there\"\n  Artist=Plain\n  Resolution = 96\n}\n"
	var pc := ChartParser.parse_bytes(txt.to_utf8_buffer())
	assert_bool(pc.ok).is_true()
	assert_str(pc.song["name"]).is_equal("He said \"hi\" there")
	assert_str(pc.song["artist"]).is_equal("Plain")
	assert_int(pc.resolution).is_equal(96)


func test_garbage_reports_line() -> void:
	var pc := _parse("garbage.chart")
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).is_equal("Unreadable .chart (line 1)")
	assert_int(pc.error_line).is_equal(1)
	var late := ChartParser.parse_bytes("// c\n\nnot a header\n".to_utf8_buffer())
	assert_str(late.error).is_equal("Unreadable .chart (line 3)")


func test_header_without_brace() -> void:
	var pc := ChartParser.parse_bytes("[Song]\n  Resolution = 192\n".to_utf8_buffer())
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).is_equal("Unreadable .chart (line 1)")
	var pc2 := ChartParser.parse_bytes("[Song]\n{\n}\n[Events]\nE x\n".to_utf8_buffer())
	assert_str(pc2.error).is_equal("Unreadable .chart (line 4)")


func test_empty_and_random_bytes_never_throw() -> void:
	assert_bool(ChartParser.parse_bytes(PackedByteArray()).ok).is_false()
	var rnd := PackedByteArray()
	for i in 4096:
		rnd.append((i * 131 + 7) % 256)
	var pc := ChartParser.parse_bytes(rnd)
	assert_bool(pc.ok).is_false()
	assert_str(pc.error).starts_with("Unreadable .chart (line ")


func test_truncated_is_ok_with_warning() -> void:
	var pc := _parse("truncated.chart")
	assert_bool(pc.ok).is_true()
	assert_bool(pc.warnings >= 1).is_true()
	assert_int(pc.tracks["ExpertSingle"].size()).is_equal(2)


func test_hostile_numbers_skipped() -> void:
	var pc := _parse("hostile.chart")
	assert_bool(pc.ok).is_true()
	assert_int(pc.resolution).is_equal(192)
	assert_bool(pc.warnings >= 1).is_true()
	assert_int(pc.tempo.size()).is_equal(1)
	assert_int(pc.tempo[0]["milli_bpm"]).is_equal(120000)
	var t: Array = pc.tracks["ExpertSingle"]
	assert_int(t.size()).is_equal(1)
	assert_int(t[0]["tick"]).is_equal(384)
	assert_int(t[0]["a"]).is_equal(3)


func test_resolution_clamped() -> void:
	var pc := ChartParser.parse_bytes("[Song]\n{\n Resolution = 999999\n}\n".to_utf8_buffer())
	assert_int(pc.resolution).is_equal(65535)


func test_caps_via_limits() -> void:
	var minimal := _fx("minimal.chart")
	var big := ChartParser.parse_bytes(minimal, {"max_bytes": 10})
	assert_bool(big.ok).is_false()
	assert_str(big.error).is_equal("Chart too large")
	var many := ChartParser.parse_bytes(minimal, {"max_lines": 3})
	assert_str(many.error).is_equal("Chart too large")
	var capped := ChartParser.parse_bytes(minimal, {"max_entries": 2})
	assert_bool(capped.ok).is_true()
	assert_int(capped.tracks["ExpertSingle"].size()).is_equal(2)
	assert_bool(capped.warnings >= 1).is_true()


func test_ignores_other_sections() -> void:
	var pc := _parse("community_style.chart")
	assert_bool(pc.ok).is_true()
	assert_bool(pc.tracks.has("ExpertSingle")).is_true()
	assert_bool(pc.tracks.has("HardSingle")).is_true()
	assert_int(pc.tracks.size()).is_equal(2)
	assert_int(pc.time_sigs.size()).is_equal(4)
	assert_int(pc.tempo.size()).is_equal(4)


func test_no_guitar_parses_without_tracks() -> void:
	var pc := _parse("no_guitar.chart")
	assert_bool(pc.ok).is_true()
	assert_int(pc.tracks.size()).is_equal(0)


# ---- SongIni ----

func test_song_ini_tolerance() -> void:
	var txt := "﻿; comment\n# other\nName = My Song\nARTIST=A=B\nbad line\n[Song]\nDelay = 120\n[Other]\nx = y\n"
	var d := SongIni.parse(txt)
	assert_str(d["name"]).is_equal("My Song")
	assert_str(d["artist"]).is_equal("A=B")
	assert_int(SongIni.get_int(d, "delay", 0)).is_equal(120)
	assert_bool(d.has("x")).is_false()
	var d2 := SongIni.parse("[song]\nname = z\n")
	assert_str(d2["name"]).is_equal("z")
	var d3 := SongIni.parse("[Song]\nname = a\n[Other]\nname = b\n")
	assert_str(d3["name"]).is_equal("a")


func test_song_ini_sanitize_and_get_int() -> void:
	assert_str(SongIni.sanitize_text("<color=#00FF00>Hi</color>\u0007there")).is_equal("Hithere")
	assert_int(SongIni.sanitize_text("x".repeat(300)).length()).is_equal(120)
	assert_int(SongIni.sanitize_text("x".repeat(300), 10).length()).is_equal(10)
	var d := {"a": "12abc", "b": " 42 ", "c": "-7"}
	assert_int(SongIni.get_int(d, "a", 5)).is_equal(5)
	assert_int(SongIni.get_int(d, "b", 5)).is_equal(42)
	assert_int(SongIni.get_int(d, "c", 5)).is_equal(-7)
	assert_int(SongIni.get_int(d, "missing", 9)).is_equal(9)
