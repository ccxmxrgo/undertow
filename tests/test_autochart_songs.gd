extends GdUnitTestSuite
## Audio-driven bundled songs made by tools/autochart (Phase 2.1, SPEC requirements 3-7 and 9).
## Generic checks over AUTOCHART_IDS that read the committed res:// files only: the chart
## (structure, density caps, grids, Expert-subset rule, sustains, solo), song.ini, the recorded
## sync-gate report (tools/autochart/reports/<id>.sync.json) and chart statistics
## (<id>.chart_stats.json), plus library listing, Autoplay and fingerprint stability.

const AUTOCHART_IDS: Array[String] = ["synth_wave_april", "space_synth_wave", "sea_shanty_2", "hrt", "invisible"]
## Ids allowed to ship at PASS_BASELINE (SPEC req 5, flagged in UAT).
const BASELINE_OK: Array[String] = []
## Minimum Expert melody direction match (SPEC req 4).
const MELODY_IDS := {"synth_wave_april": 0.70, "space_synth_wave": 0.70, "sea_shanty_2": 0.70, "hrt": 0.70, "invisible": 0.70}

const DIFFS: Array[String] = ["easy", "medium", "hard", "expert"]
const TRACKS := {"easy": "EasySingle", "medium": "MediumSingle", "hard": "HardSingle", "expert": "ExpertSingle"}
const CAPS := {"easy": 4, "medium": 5, "hard": 7, "expert": 8}
const RES := 192

## Neversoft bands (SPEC reference table) and the tolerance used for honest band flags.
const KEEP_BANDS := {"hard": [0.90, 1.00], "medium": [0.65, 0.75], "easy": [0.45, 0.55]}
const STEP_BANDS := {"repeat": [0.20, 0.30], "step1": [0.40, 0.60], "step2": [0.15, 0.30], "step3plus": [0.00, 0.05]}
const BAND_TOL := 0.05

## Fixed SPEC gate numbers and the professional baseline (tools/autochart/note_sync.py).
const FIXED := {"median_mix_abs_ms": 5.0, "stem_pct": 90.0, "mix_pct": 80.0,
		"tempo_median_ms": 10.0, "tempo_p90_ms": 20.0, "live_lag_abs_ms": 3.0}
const BASELINE := {"median_mix_abs_ms": 5.9, "stem_pct": 54.5, "mix_pct": 73.5, "mix_chance_max_pct": 45.0,
		"tempo_median_ms": 10.0, "tempo_p90_ms": 20.0, "live_lag_abs_ms": 3.0}


# ---- helpers ----

func _chart_path(id: String) -> String:
	return "res://songs/%s/notes.chart" % id


func _parsed(id: String) -> ParsedChart:
	return ChartParser.parse_bytes(FileAccess.get_file_as_bytes(_chart_path(id)))


func _ini(id: String) -> Dictionary:
	return SongIni.parse(FileAccess.get_file_as_string("res://songs/%s/song.ini" % id))


func _delay(id: String) -> int:
	return SongIni.get_int(_ini(id), "delay", 0)


func _report(id: String, kind: String) -> Dictionary:
	var p := "res://tools/autochart/reports/%s.%s.json" % [id, kind]
	if not FileAccess.file_exists(p):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


## Parsed chart or null (with a failed assertion) when the committed chart is missing / unreadable.
func _require(id: String) -> ParsedChart:
	assert_bool(FileAccess.file_exists(_chart_path(id))).override_failure_message(
			"%s: missing %s" % [id, _chart_path(id)]).is_true()
	if not FileAccess.file_exists(_chart_path(id)):
		return null
	var p := _parsed(id)
	assert_bool(p.ok).override_failure_message("%s: chart does not parse: %s" % [id, p.error]).is_true()
	return p if p.ok else null


## tick -> Array of {a, b} raw N gems of one difficulty (ticks ascending in the returned keys()).
func _gems(p: ParsedChart, diff: String) -> Dictionary:
	var out := {}
	var name: String = TRACKS[diff]
	if not p.tracks.has(name):
		return out
	for e in p.tracks[name]:
		if e["type"] != "N":
			continue
		if not out.has(e["tick"]):
			out[e["tick"]] = []
		(out[e["tick"]] as Array).append({"a": int(e["a"]), "b": int(e["b"])})
	return out


func _ticks(g: Dictionary) -> Array:
	var t := g.keys()
	t.sort()
	return t


func _unique_times(c: ChartData) -> Array:
	var seen := {}
	var out: Array = []
	for n in c.notes:
		var k := int(round(float(n["time"]) * 1000000.0))
		if not seen.has(k):
			seen[k] = true
			out.append(float(n["time"]))
	out.sort()
	return out


func _max_per_window(times: Array, span: float = 1.0) -> int:
	var best := 0
	var j := 0
	for i in times.size():
		while j < times.size() and float(times[j]) < float(times[i]) + span - 1e-9:
			j += 1
		best = maxi(best, j - i)
	return best


func _chord_ticks(g: Dictionary) -> int:
	var n := 0
	for t in g:
		if (g[t] as Array).size() >= 2:
			n += 1
	return n


# ---- chart structure (SPEC req 2, 7, 9) ----

func test_chart_structure() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		assert_int(p.resolution).is_equal(RES)
		assert_str(str(p.song.get("charter", ""))).is_equal("UNDERTOW autochart")
		var names := p.tracks.keys()
		names.sort()
		assert_array(names).is_equal(["EasySingle", "ExpertSingle", "HardSingle", "MediumSingle"])
		for d in DIFFS:
			for e in p.tracks[TRACKS[d]]:
				if e["type"] == "N":
					assert_int(int(e["a"])).override_failure_message(
							"%s %s gem %d at %d (only 0..3 allowed)" % [id, d, e["a"], e["tick"]]).is_between(0, 3)
		assert_int(p.tempo.size()).is_greater_equal(1)
		for b in p.tempo:
			assert_int(int(b["milli_bpm"])).is_between(1000, 2000000)
		var sections := 0
		for e in p.events:
			if str(e["text"]).begins_with("section "):
				sections += 1
		assert_int(sections).override_failure_message("%s: %d sections" % [id, sections]).is_greater_equal(2)


# ---- density caps (SPEC req 3, 6) ----

func test_density_caps_and_expert_average() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		for d in DIFFS:
			var c := ChartImporter.build(p, d, _delay(id))
			var times := _unique_times(c)
			assert_int(times.size()).override_failure_message("%s %s has no notes" % [id, d]).is_greater(16)
			if times.size() < 2:
				continue
			var most := _max_per_window(times)
			assert_int(most).override_failure_message("%s %s: %d notes in 1 s (cap %d)" % [id, d, most, CAPS[d]]).is_less_equal(CAPS[d])
			if d == "expert":
				var rate: float = times.size() / (float(times[times.size() - 1]) - float(times[0]))
				assert_bool(rate >= 2.0 and rate <= 5.0).override_failure_message(
						"%s expert average %.2f n/s outside 2..5" % [id, rate]).is_true()


# ---- reductions are Expert subsets on their grids (SPEC req 6) ----

func test_reductions_keep_expert_ticks_and_grids() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		var ex := _gems(p, "expert")
		for d in ["hard", "medium", "easy"]:
			var g := _gems(p, d)
			for t in g:
				assert_bool(ex.has(t)).override_failure_message("%s %s tick %d not in Expert" % [id, d, t]).is_true()
				if d != "hard":
					assert_int(int(t) % 96).override_failure_message("%s %s tick %d off the 1/8 grid" % [id, d, t]).is_equal(0)
		# Easy: >= 1 beat apart, lanes 0..2, no chords
		var easy := _gems(p, "easy")
		var et := _ticks(easy)
		for i in et.size():
			assert_int((easy[et[i]] as Array).size()).is_equal(1)
			assert_int(int((easy[et[i]] as Array)[0]["a"])).is_less_equal(2)
			if i > 0:
				assert_int(int(et[i]) - int(et[i - 1])).override_failure_message(
						"%s easy gap %d ticks at %d" % [id, int(et[i]) - int(et[i - 1]), et[i]]).is_greater_equal(RES)
		# Medium: <= 3% chords, 2-note only
		var med := _gems(p, "medium")
		var mchords := 0
		for t in med:
			var k := (med[t] as Array).size()
			assert_int(k).is_less_equal(2)
			if k == 2:
				mchords += 1
		assert_float(float(mchords) / maxf(1.0, float(med.size()))).is_less_equal(0.03)
		# Hard / Expert: <= 2-note chords
		for d in ["hard", "expert"]:
			var g := _gems(p, d)
			for t in g:
				assert_int((g[t] as Array).size()).override_failure_message("%s %s chord of %d at %d" % [id, d, (g[t] as Array).size(), t]).is_less_equal(2)


func test_hard_keeps_at_most_60_percent_of_expert_chords() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		var hc := _chord_ticks(_gems(p, "hard"))
		var ec := _chord_ticks(_gems(p, "expert"))
		assert_float(float(hc)).override_failure_message("%s: hard chords %d vs expert %d" % [id, hc, ec]).is_less_equal(0.6 * float(ec))


# ---- sustains (SPEC req 4) ----

func test_sustains_never_reach_the_next_note() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		for d in DIFFS:
			var g := _gems(p, d)
			var ts := _ticks(g)
			for i in range(ts.size() - 1):
				for gem in g[ts[i]]:
					if int(gem["b"]) > 0:
						assert_int(int(ts[i]) + int(gem["b"])).override_failure_message(
								"%s %s sustain at %d reaches %d" % [id, d, ts[i], ts[i + 1]]).is_less(int(ts[i + 1]))


# ---- solo (SPEC req 7) ----

func test_one_solo_per_difficulty_with_16_notes_on_hard_and_expert() -> void:
	for id in AUTOCHART_IDS:
		var p := _require(id)
		if p == null:
			continue
		for d in DIFFS:
			var c := ChartImporter.build(p, d, _delay(id))
			assert_int(c.solos.size()).override_failure_message("%s %s solos %d" % [id, d, c.solos.size()]).is_equal(1)
			if c.solos.size() == 1 and (d == "hard" or d == "expert"):
				assert_int(int(c.solos[0]["note_count"])).is_greater_equal(16)


# ---- song.ini (SPEC req 7) ----

func test_song_ini_metadata_matches_the_report() -> void:
	for id in AUTOCHART_IDS:
		var p := "res://songs/%s/song.ini" % id
		assert_bool(FileAccess.file_exists(p)).override_failure_message("%s: missing song.ini" % id).is_true()
		var ini := _ini(id)
		var rep := _report(id, "sync")
		assert_bool(rep.is_empty()).override_failure_message("%s: missing sync report" % id).is_false()
		assert_str(str(ini.get("charter", ""))).is_equal("UNDERTOW autochart")
		assert_str(str(ini.get("name", ""))).is_not_empty()
		assert_bool(ini.has("diff_guitar")).is_true()
		var length := SongIni.get_int(ini, "song_length", 0)
		var preview := SongIni.get_int(ini, "preview_start_time", -1)
		assert_int(preview).is_greater(0)
		assert_int(preview).is_less(length)
		if rep.is_empty():
			continue
		assert_int(SongIni.get_int(ini, "delay", -99999)).is_equal(int(rep["suggested_delay_ms"]))
		assert_int(absi(length - int(rep["decoded_length_ms"]))).is_less_equal(50)


# ---- recorded sync gate (SPEC req 5) ----

func _tempo(rep: Dictionary, key: String) -> float:
	var t: Variant = rep.get("tempo")
	if not (t is Dictionary) or not (t as Dictionary).has("refined"):
		return INF
	var v: Variant = t["refined"].get(key)
	return INF if v == null else float(v)


func _passes(rep: Dictionary, th: Dictionary, baseline: bool) -> bool:
	if rep.get("median_mix_ms") == null or rep.get("stem_pct") == null or rep.get("live_lag_ms") == null:
		return false
	var ok := absf(float(rep["median_mix_ms"])) <= float(th["median_mix_abs_ms"])
	ok = ok and float(rep["mix_pct"]) >= float(th["mix_pct"])
	ok = ok and float(rep["stem_pct"]) >= float(th["stem_pct"])
	ok = ok and _tempo(rep, "median_abs_ms") <= float(th["tempo_median_ms"])
	ok = ok and _tempo(rep, "p90_abs_ms") <= float(th["tempo_p90_ms"])
	ok = ok and absf(float(rep["live_lag_ms"])) <= float(th["live_lag_abs_ms"])
	if baseline:
		ok = ok and float(rep["mix_chance_pct"]) <= float(th["mix_chance_max_pct"])
	return ok


func test_sync_gate_report_passes_and_belongs_to_the_committed_chart() -> void:
	for id in AUTOCHART_IDS:
		var rep := _report(id, "sync")
		assert_bool(rep.is_empty()).override_failure_message("%s: missing tools/autochart/reports/%s.sync.json" % [id, id]).is_false()
		if rep.is_empty():
			continue
		var verdict := str(rep.get("verdict", ""))
		var allowed := ["PASS"]
		if BASELINE_OK.has(id):
			allowed.append("PASS_BASELINE")
		assert_bool(allowed.has(verdict)).override_failure_message("%s verdict %s" % [id, verdict]).is_true()
		assert_bool(rep.has("mix_chance_pct") and rep.has("stem_chance_pct")).is_true()
		assert_bool(rep.get("stem_chance_pct") != null).is_true()
		if verdict == "PASS":
			assert_bool(_passes(rep, FIXED, false)).override_failure_message("%s numbers do not meet the fixed gate" % id).is_true()
		else:
			assert_bool(_passes(rep, BASELINE, true)).override_failure_message("%s numbers do not meet the baseline" % id).is_true()
		var sha := FileAccess.get_sha256(_chart_path(id))
		assert_str(str(rep.get("chart_sha256", "")).to_lower()).is_equal(sha.to_lower())
		assert_int(int(rep.get("ini_delay_ms", -99999))).is_equal(_delay(id))


## A filled chart (chart_stats fill_stem set) is gated against every charted stem: the report's
## stems list holds both the primary and the fill stem WAV (plan 02.1-06).
func test_filled_chart_gated_against_all_charted_stems() -> void:
	for id in AUTOCHART_IDS:
		var st := _report(id, "chart_stats")
		var rep := _report(id, "sync")
		if st.is_empty() or rep.is_empty():
			continue
		var names: Array[String] = []
		for p in rep.get("stems", []):
			names.append(str(p).replace("\\", "/").get_file().get_basename())
		assert_bool(names.has(str(st.get("stem", "")))).override_failure_message(
				"%s: primary stem %s not in sync stems %s" % [id, st.get("stem"), names]).is_true()
		var fill: Variant = st.get("fill_stem")
		if fill != null and str(fill) != "":
			assert_bool(names.has(str(fill))).override_failure_message(
					"%s: fill stem %s not in sync stems %s" % [id, fill, names]).is_true()


# ---- chart statistics: melody and honest band flags (SPEC req 4, 6) ----

func test_melody_direction_match() -> void:
	for id in MELODY_IDS:
		var st := _report(id, "chart_stats")
		assert_bool(st.is_empty()).override_failure_message("%s: missing chart_stats.json" % id).is_false()
		if st.is_empty():
			continue
		assert_float(float(st.get("direction_match", 0.0))).is_greater_equal(float(MELODY_IDS[id]))


func _outside(v: float, band: Array) -> bool:
	return v < float(band[0]) - BAND_TOL - 1e-9 or v > float(band[1]) + BAND_TOL + 1e-9


func _has_flag(flags: Array, diff: String, metric: String) -> bool:
	for f in flags:
		if f is Dictionary and str(f.get("difficulty", "")) == diff and str(f.get("metric", "")) == metric:
			return true
	return false


func test_band_flags_are_honest() -> void:
	for id in AUTOCHART_IDS:
		var st := _report(id, "chart_stats")
		assert_bool(st.is_empty()).override_failure_message("%s: missing chart_stats.json" % id).is_false()
		if st.is_empty():
			continue
		assert_bool(st.get("band_flags") is Array).is_true()
		var flags: Array = st.get("band_flags", [])
		var per: Dictionary = st.get("difficulties", {})
		for d in DIFFS:
			assert_bool(per.has(d)).is_true()
			if not per.has(d):
				continue
			var s: Dictionary = per[d]
			if KEEP_BANDS.has(d):
				var v := float(s["keep_share"])
				assert_bool(_has_flag(flags, d, "keep_share") == _outside(v, KEEP_BANDS[d])).override_failure_message(
						"%s %s keep_share %.3f flag mismatch" % [id, d, v]).is_true()
			var hist: Dictionary = s["lane_step_hist"]
			for m in STEP_BANDS:
				var hv := float(hist[m])
				assert_bool(_has_flag(flags, d, m) == _outside(hv, STEP_BANDS[m])).override_failure_message(
						"%s %s %s %.3f flag mismatch" % [id, d, m, hv]).is_true()
		for f in flags:
			assert_float(float(f.get("tolerance", -1.0))).is_equal_approx(BAND_TOL, 1e-6)


# ---- manifest, library, Autoplay, fingerprints (SPEC req 7, 9; SONG-05) ----

func test_manifest_lists_autochart_songs() -> void:
	for id in AUTOCHART_IDS:
		var found := {}
		for b in BundledSongs.SONGS:
			if b["id"] == id:
				found = b
		assert_bool(found.is_empty()).override_failure_message("%s not in BundledSongs.SONGS" % id).is_false()
		if found.is_empty():
			continue
		assert_str(found["dir"]).is_equal("res://songs/" + id)
		assert_bool(ResourceLoader.exists(found["dir"] + "/" + found["audio"])).is_true()
	var credits := FileAccess.get_file_as_string("res://songs/CREDITS.txt")
	assert_bool(credits.contains("Sea Shanty 2") and credits.contains("Jagex")).is_true()


const LIB_D := "user://test_autochart_songs"


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


func test_library_lists_and_autoplay_is_all_perfect() -> void:
	var lib := await _lib()
	assert_bool(lib.scanning).is_false()
	for id in AUTOCHART_IDS:
		var e: SongEntry = null
		for x in lib.entries:
			if x.source == "bundled" and str(x.id).ends_with(id):
				e = x
		assert_object(e).override_failure_message("%s not listed by SongLibrary" % id).is_not_null()
		if e == null:
			continue
		assert_str(e.status).is_equal("ok")
		assert_array(e.difficulties.map(func(d: Dictionary) -> String: return d["name"])).contains_exactly(DIFFS)
		for d in DIFFS:
			var chart: ChartData = lib.build_chart(e, d)
			assert_object(chart).override_failure_message("%s %s: %s" % [id, d, lib.last_build_error]).is_not_null()
			if chart == null:
				continue
			assert_object(chart.audio_stream).is_not_null()
			var r := _autoplay_all_perfect(chart)
			var hs: HullScore = r["hs"]
			assert_int(hs.miss_count).is_equal(0)
			assert_int(hs.good_count).is_equal(0)
			assert_int(hs.perfect_count).is_equal(chart.notes.size())
	lib.queue_free()


func test_fingerprints_are_stable() -> void:
	for id in AUTOCHART_IDS:
		var p1 := _require(id)
		if p1 == null:
			continue
		var p2 := _parsed(id)
		var dur := float(SongIni.get_int(_ini(id), "song_length", 0)) / 1000.0
		for d in DIFFS:
			var a := ChartImporter.fingerprint(ChartImporter.build(p1, d, _delay(id)), d, dur)
			var b := ChartImporter.fingerprint(ChartImporter.build(p2, d, _delay(id)), d, dur)
			assert_str(a).is_equal(b)
