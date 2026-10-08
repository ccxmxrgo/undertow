extends GdUnitTestSuite
## AudioLoader: header detection, Opus never reaches the engine, stems, classification.

const D := "user://test_audio_loader"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)


func after_test() -> void:
	SongFixture.rm_tree(D)


func test_detect_formats() -> void:
	SongFixture.make_wav(D + "/a.wav")
	assert_str(AudioLoader.detect(D + "/a.wav")).is_equal("wav")
	SongFixture.write_bytes(D + "/o.ogg", SongFixture.opus_bytes())
	assert_str(AudioLoader.detect(D + "/o.ogg")).is_equal("opus")
	SongFixture.write_bytes(D + "/x.opus", SongFixture.garbage_bytes())
	assert_str(AudioLoader.detect(D + "/x.opus")).is_equal("opus")
	var vorbis := "OggS".to_ascii_buffer()
	vorbis.append_array(PackedByteArray([0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1]))
	vorbis.append_array("vorbis".to_ascii_buffer())
	SongFixture.write_bytes(D + "/v.ogg", vorbis)
	assert_str(AudioLoader.detect(D + "/v.ogg")).is_equal("ogg")
	SongFixture.write_bytes(D + "/t.mp3", SongFixture.mp3_bytes("T", "A"))
	assert_str(AudioLoader.detect(D + "/t.mp3")).is_equal("mp3")
	SongFixture.write_bytes(D + "/s.bin", PackedByteArray([0xFF, 0xFB, 0x90, 0x00]))
	assert_str(AudioLoader.detect(D + "/s.bin")).is_equal("mp3")
	SongFixture.write_bytes(D + "/g.bin", SongFixture.garbage_bytes())
	assert_str(AudioLoader.detect(D + "/g.bin")).is_equal("unknown")
	assert_str(AudioLoader.detect(D + "/nope.wav")).is_equal("missing")


func test_load_wav_and_refuse_opus() -> void:
	SongFixture.make_wav(D + "/a.wav", 1.5)
	var s := AudioLoader.load_file(D + "/a.wav")
	assert_object(s).is_not_null()
	assert_bool(s is AudioStreamWAV).is_true()
	assert_float(s.get_length()).is_greater(1.0)
	SongFixture.write_bytes(D + "/o.ogg", SongFixture.opus_bytes())
	assert_object(AudioLoader.load_file(D + "/o.ogg")).is_null()
	SongFixture.write_bytes(D + "/g.wav", SongFixture.garbage_bytes())
	assert_object(AudioLoader.load_file(D + "/g.wav")).is_null()
	assert_object(AudioLoader.load_file(D + "/missing.wav")).is_null()


func test_single_and_stems() -> void:
	SongFixture.make_wav(D + "/song.wav", 2.0)
	var one := AudioLoader.load_song_audio([D + "/song.wav"])
	assert_str(one["error"]).is_equal("")
	assert_float(one["length"]).is_greater(1.0)
	SongFixture.make_wav(D + "/guitar.wav", 3.0)
	var two := AudioLoader.load_song_audio([D + "/guitar.wav", D + "/song.wav"])
	assert_str(two["error"]).is_equal("")
	assert_bool(two["stream"] is AudioStreamSynchronized).is_true()
	assert_float(two["stream"].get_length()).is_equal_approx(3.0, 0.1)
	assert_float(two["length"]).is_equal_approx(3.0, 0.1)


func test_optional_stem_failure_skipped_core_failure_reported() -> void:
	SongFixture.make_wav(D + "/song.wav")
	SongFixture.write_bytes(D + "/crowd.wav", SongFixture.garbage_bytes())
	var r := AudioLoader.load_song_audio([D + "/song.wav", D + "/crowd.wav"])
	assert_str(r["error"]).is_equal("")
	assert_object(r["stream"]).is_not_null()
	SongFixture.write_bytes(D + "/guitar.ogg", SongFixture.opus_bytes())
	var o := AudioLoader.load_song_audio([D + "/guitar.ogg", D + "/song.wav"])
	assert_str(o["error"]).is_equal(SongEntry.ERR_OPUS)
	assert_object(o["stream"]).is_null()
	SongFixture.write_bytes(D + "/drums.wav", SongFixture.garbage_bytes())
	var b := AudioLoader.load_song_audio([D + "/drums.wav", D + "/song.wav"])
	assert_bool(b["error"] != "").is_true()
	var m := AudioLoader.load_song_audio([D + "/gone.wav"])
	assert_str(m["error"]).is_equal(SongEntry.ERR_AUDIO_MISSING)


func test_classify_stems() -> void:
	var c := AudioLoader.classify_stems(["Guitar.OGG", "rhythm.mp3", "DRUMS_2.wav", "crowd.ogg",
			"preview.ogg", "album.png", "notes.chart"])
	assert_array(c["core"]).contains_exactly(["Guitar.OGG", "rhythm.mp3", "DRUMS_2.wav"])
	assert_array(c["optional"]).contains_exactly(["crowd.ogg"])
	assert_str(c["preview"]).is_equal("preview.ogg")
	var single := AudioLoader.classify_stems(["Artist - Title.mp3", "cover.jpg"])
	assert_array(single["core"]).contains_exactly(["Artist - Title.mp3"])
	var multi := AudioLoader.classify_stems(["a.mp3", "b.mp3"])
	assert_array(multi["core"]).is_empty()
	var only_preview := AudioLoader.classify_stems(["song.ogg", "preview.ogg"])
	assert_array(only_preview["core"]).contains_exactly(["song.ogg"])
