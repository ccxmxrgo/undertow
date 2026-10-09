extends GdUnitTestSuite
## Bundled songs (SONG-04, SONG-07, D-14): committed charts are the generator's exact output,
## import cleanly for all four difficulties, hit the density bands, carry a solo and never
## overlap sustains. Reads the committed res://songs files only; no user:// access.

const IDS: Array[String] = ["synth_wave_april", "space_synth_wave"]
## Measured in 02-06 against the game's own decoded audio (tools/charting/README.txt).
const DELAYS := {"synth_wave_april": 48, "space_synth_wave": 525}
const BARS := {"synth_wave_april": 64, "space_synth_wave": 96}
const BANDS := {
	"easy": [0.6, 1.4], "medium": [1.2, 2.2], "hard": [2.0, 3.2], "expert": [3.0, 4.6],
}
const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]
const BAR_SEC := 2.0

var _author: Script = load("res://tools/charting/author_chart.gd")


func _text(id: String) -> String:
	return FileAccess.get_file_as_string("res://songs/%s/notes.chart" % id).replace("\r\n", "\n")


func _parsed(id: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes("res://songs/%s/notes.chart" % id))


func _chart(id: String, diff: String) -> ChartData:
	return ChartImporter.build(_parsed(id), diff, int(DELAYS[id]))


func test_generator_output_is_deterministic_and_matches_committed_files() -> void:
	for id in IDS:
		var a: String = _author.generate(id)
		var b: String = _author.generate(id)
		assert_str(a).is_equal(b)
		assert_str(a).is_equal(_text(id))


func test_chart_structure() -> void:
	for id in IDS:
		var p := _parsed(id)
		assert_bool(p.ok).is_true()
		assert_int(p.resolution).is_equal(192)
		assert_int(p.tempo.size()).is_equal(1)
		assert_int(p.tempo[0]["tick"]).is_equal(0)
		assert_int(p.tempo[0]["milli_bpm"]).is_equal(120000)
		assert_str(str(p.song["charter"])).is_equal("UNDERTOW")
		var names := p.tracks.keys()
		names.sort()
		assert_array(names).is_equal(["EasySingle", "ExpertSingle", "HardSingle", "MediumSingle"])
		assert_array(ChartImporter.difficulties(p)).contains_exactly(DIFFS)
		var sections: Array = []
		for e in p.events:
			sections.append(e["text"])
			assert_int(int(e["tick"]) % (768 * 8)).is_equal(0)
		assert_str(sections[0]).is_equal("section Intro")
		assert_bool(sections.has("section Drop")).is_true()
		assert_bool(sections.has("section Break")).is_true()
		assert_bool(sections.has("section Outro")).is_true()


func test_density_bands_and_monotone_counts() -> void:
	for id in IDS:
		var prev := 0
		for d in DIFFS:
			var c := _chart(id, d)
			var n := c.notes.size()
			assert_int(n).is_greater(prev)
			prev = n
			var span: float = c.notes[n - 1]["time"] - c.notes[0]["time"]
			var rate := n / span
			var band: Array = BANDS[d]
			assert_bool(rate >= band[0] and rate <= band[1]).override_failure_message(
					"%s %s density %.2f outside %s" % [id, d, rate, band]).is_true()


func test_first_note_not_before_bar_two_and_breaks_have_rest_bars() -> void:
	for id in IDS:
		var plan: Dictionary = SectionPlans.SONGS[id]
		for d in DIFFS:
			var c := _chart(id, d)
			var delay: float = float(DELAYS[id]) / 1000.0
			assert_float(c.notes[0]["time"]).is_greater_equal(2.0 * BAR_SEC + delay - 0.001)
			var bars_with_notes := {}
			for n in c.notes:
				bars_with_notes[int(floor((n["time"] - delay + 0.001) / BAR_SEC))] = true
			var rest_in_break := 0
			for s in plan["sections"]:
				if s["label"] == "Break":
					for b in range(int(s["from"]), int(s["to"])):
						if not bars_with_notes.has(b):
							rest_in_break += 1
			assert_int(rest_in_break).is_greater(0)


func test_chord_size_limits_and_no_sustain_overlap() -> void:
	var limits := {"easy": 1, "medium": 2, "hard": 3, "expert": 4}
	for id in IDS:
		for d in DIFFS:
			var c := _chart(id, d)
			var by_time := {}
			var free_at := [-1.0, -1.0, -1.0, -1.0]  # lane free again after sustain end + a 16th
			for n in c.notes:
				var key := int(round(n["time"] * 1000.0))
				by_time[key] = int(by_time.get(key, 0)) + 1
				var lane: int = n["lane"]
				assert_float(n["time"]).is_greater_equal(free_at[lane] - 0.0005)
				if n["duration"] > 0.0:
					free_at[lane] = n["time"] + n["duration"] + 0.125
			var most := 0
			for k in by_time:
				most = maxi(most, by_time[k])
			assert_int(most).is_less_equal(limits[d])
			if d == "easy":
				assert_int(most).is_equal(1)
	# expert accent chords exist, but hard stays at 3 at most
	assert_int(_chart("synth_wave_april", "expert").notes.size()).is_greater(100)


func test_lane_steps_on_lower_difficulties() -> void:
	for id in IDS:
		for d in ["easy", "medium"]:
			var c := _chart(id, d)
			var max_step := 1 if d == "easy" else 2
			var prev := -1
			for n in c.notes:
				if prev >= 0:
					assert_int(absi(int(n["lane"]) - prev)).is_less_equal(max_step if d == "easy" else max_step + 1)
				prev = n["lane"]


func test_solos_in_hard_and_expert_have_at_least_16_notes() -> void:
	for id in IDS:
		for d in ["hard", "expert"]:
			var c := _chart(id, d)
			assert_int(c.solos.size()).is_equal(1)
			assert_int(c.solos[0]["note_count"]).is_greater_equal(16)
		# easy and medium carry the same solo span (documented choice)
		for d in ["easy", "medium"]:
			assert_int(_chart(id, d).solos.size()).is_equal(1)


func test_song_ini_metadata() -> void:
	for id in IDS:
		var ini := SongIni.parse(FileAccess.get_file_as_string("res://songs/%s/song.ini" % id))
		assert_str(str(ini["artist"])).is_equal("Pro Sensory (Alex McCulloch)")
		assert_str(str(ini["charter"])).is_equal("UNDERTOW")
		assert_int(SongIni.get_int(ini, "delay", -1)).is_equal(int(DELAYS[id]))
		assert_int(SongIni.get_int(ini, "preview_start_time", -1)).is_greater(0)
		assert_int(SongIni.get_int(ini, "song_length", 0)).is_greater(100000)
		assert_str(str(ini["name"])).is_not_empty()


func test_manifest_lists_both_songs_with_existing_files() -> void:
	assert_int(BundledSongs.SONGS.size()).is_equal(2)
	for i in IDS.size():
		var b: Dictionary = BundledSongs.SONGS[i]
		assert_str(b["id"]).is_equal(IDS[i])
		assert_str(b["dir"]).is_equal("res://songs/" + IDS[i])
		assert_bool(FileAccess.file_exists(b["dir"] + "/notes.chart")).is_true()
		assert_bool(ResourceLoader.exists(b["dir"] + "/" + b["audio"])).is_true()
	assert_bool(FileAccess.file_exists("res://songs/CREDITS.txt")).is_true()
	var credits := FileAccess.get_file_as_string("res://songs/CREDITS.txt")
	assert_bool(credits.contains("Pro Sensory") and credits.contains("CC0")).is_true()


# ---- library listing, audio length and Autoplay (plan 02-05 task 3) ----

const LIB_D := "user://test_bundled_songs"
const AUDIO_LEN := {"synth_wave_april": 128.0, "space_synth_wave": 192.0}


func _lib() -> Node:
	SongFixture.rm_tree(LIB_D)
	SongFixture.mkdir(LIB_D + "/songs")
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = LIB_D + "/songs"
	lib.cache_path = LIB_D + "/cache.json"
	lib.auto_scan = false
	add_child(lib)
	lib.rescan()
	var t0 := Time.get_ticks_msec()
	while lib.scanning and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	return lib


func after_test() -> void:
	SongFixture.rm_tree(LIB_D)


func test_library_lists_both_bundled_songs_playable() -> void:
	var lib := await _lib()
	assert_bool(lib.scanning).is_false()
	for id in IDS:
		var e: SongEntry = null
		for x in lib.entries:
			if x.source == "bundled" and str(x.id).ends_with(id):
				e = x
		assert_object(e).is_not_null()
		assert_str(e.status).is_equal("ok")
		assert_str(e.artist).is_equal("Pro Sensory (Alex McCulloch)")
		assert_array(e.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(DIFFS)
		assert_bool(e.has_solos).is_true()
		assert_float(e.length_sec).is_equal_approx(AUDIO_LEN[id], 0.15)
	lib.queue_free()


func _autoplay_all_perfect(chart: ChartData) -> Dictionary:
	var cfg := JudgeConfig.new()
	var judge := InputJudge.new(chart, cfg)
	var hs := HullScore.new(cfg)
	hs.connect_judge(judge)
	var ap := Autoplay.new(chart, judge)
	var last: float = chart.notes[chart.notes.size() - 1]["time"] + chart.notes[chart.notes.size() - 1]["duration"] + 3.0
	var t := 0.0
	while t < last:
		t += 1.0 / 60.0
		ap.update(t)
		judge.tick(t)
	return {"hs": hs, "judge": judge}


func test_autoplay_all_perfect_every_difficulty_of_both_songs() -> void:
	var lib := await _lib()
	for id in IDS:
		var e: SongEntry = null
		for x in lib.entries:
			if x.source == "bundled" and str(x.id).ends_with(id):
				e = x
		assert_object(e).is_not_null()
		for d in DIFFS:
			var chart: ChartData = lib.build_chart(e, d)
			assert_object(chart).override_failure_message("%s %s: %s" % [id, d, lib.last_build_error]).is_not_null()
			assert_object(chart.audio_stream).is_not_null()
			assert_float(chart.audio_stream.get_length()).is_equal_approx(AUDIO_LEN[id], 0.15)
			var r := _autoplay_all_perfect(chart)
			var hs: HullScore = r["hs"]
			assert_int(hs.miss_count).is_equal(0)
			assert_int(hs.good_count).is_equal(0)
			assert_int(hs.perfect_count).is_equal(chart.notes.size())
			assert_bool((r["judge"] as InputJudge).is_finished()).is_true()
			assert_int(chart.solos.size()).is_equal(1)
			if d == "hard" or d == "expert":
				assert_int(chart.solos[0]["note_count"]).is_greater_equal(16)
	lib.queue_free()


## 02-06: bundled signatures follow chart / ini content, so a same-size delay change in a game
## update (exported res:// files report mtime 0) cannot leave a stale cache entry behind.
func test_bundled_signature_follows_ini_content() -> void:
	for id in IDS:
		var dir := "res://songs/%s" % id
		var sig: String = load("res://src/autoload/song_library.gd").bundled_signature(dir, dir.path_join("song.ini"))
		assert_str(sig).contains("song.ini=" + FileAccess.get_md5(dir.path_join("song.ini")))
		assert_str(sig).contains("notes.chart=" + FileAccess.get_md5(dir.path_join("notes.chart")))
	var d := LIB_D + "_sig"
	SongFixture.rm_tree(d)
	SongFixture.write_text(d + "/song.ini", "[song]\ndelay = 17\n")
	SongFixture.write_text(d + "/notes.chart", SongFixture.CHART)
	var lib_script: GDScript = load("res://src/autoload/song_library.gd")
	var s1: String = lib_script.bundled_signature(d, d + "/song.ini")
	SongFixture.write_text(d + "/song.ini", "[song]\ndelay = 48\n")
	var s2: String = lib_script.bundled_signature(d, d + "/song.ini")
	assert_str(s2).is_not_equal(s1)
	SongFixture.rm_tree(d)
