extends GdUnitTestSuite
## AutochartJob: job.json contract, argv, line splitter, event parser, error text (D-05, D-01).

const D := "user://test_job_protocol"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(D))


func after_test() -> void:
	var p := ProjectSettings.globalize_path(D)
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func _valid_job() -> Dictionary:
	return AutochartJob.make_job("C:/music/song.mp3", "My Song", "Me", "auto", "drums",
		"C:/ac/songs", "C:/ac/work", "C:/ac/models", 4)


func _bytes(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()


# --- take_lines ------------------------------------------------------------

func test_take_lines_keeps_partial_rest() -> void:
	var r: Array = AutochartJob.take_lines(_bytes("{\"ev\":\"a\"}\n{\"ev\":"))
	var lines: PackedStringArray = r[0]
	var rest: PackedByteArray = r[1]
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal("{\"ev\":\"a\"}")
	assert_str(rest.get_string_from_utf8()).is_equal("{\"ev\":")


func test_take_lines_strips_cr_and_drops_empty() -> void:
	var r: Array = AutochartJob.take_lines(_bytes("a\r\n\r\n\nb\r\n"))
	var lines: PackedStringArray = r[0]
	assert_array(Array(lines)).is_equal(["a", "b"])
	assert_int((r[1] as PackedByteArray).size()).is_equal(0)


# --- parse_event -----------------------------------------------------------

func test_parse_event_rejects_junk() -> void:
	assert_dict(AutochartJob.parse_event("garbage")).is_empty()
	assert_dict(AutochartJob.parse_event("[1,2]")).is_empty()
	assert_dict(AutochartJob.parse_event("{}")).is_empty()
	assert_dict(AutochartJob.parse_event("{\"ev\":3}")).is_empty()
	assert_dict(AutochartJob.parse_event("")).is_empty()


func test_parse_event_accepts_valid() -> void:
	var ev := AutochartJob.parse_event("{\"ev\":\"progress\",\"frac\":0.5}")
	assert_str(ev.get("ev")).is_equal("progress")
	assert_float(float(ev.get("frac"))).is_equal(0.5)


# --- write_job -------------------------------------------------------------

func test_write_job_round_trips_hostile_name() -> void:
	var job := _valid_job()
	var hostile := "Evil\" --force\nline2"
	job["name"] = hostile
	var path := ProjectSettings.globalize_path(D).path_join("job.json")
	assert_int(AutochartJob.write_job(path, job)).is_equal(OK)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).is_true()
	assert_str(parsed["name"]).is_equal(hostile)
	assert_int(int(parsed["version"])).is_equal(AutochartJob.VERSION)


# --- build_args ------------------------------------------------------------

func test_build_args_job() -> void:
	var args := AutochartJob.build_args("C:/ac/v1/app", "job", "C:/ac/work/jobs/1/job.json")
	assert_array(Array(args)).is_equal(["-I", "-X", "utf8", "-u", "C:/ac/v1/app/autochart.py",
		"job", "C:/ac/work/jobs/1/job.json"])
	for a in args:
		assert_bool(a.contains("My Song")).is_false()
		assert_str(a).is_not_equal("-B")


func test_build_args_selftest() -> void:
	var args := AutochartJob.build_args("C:/ac/v1/app", "selftest")
	assert_array(Array(args)).is_equal(["-I", "-X", "utf8", "-u", "C:/ac/v1/app/autochart.py",
		"selftest"])


# --- make_job / validate ---------------------------------------------------

func test_make_job_defaults() -> void:
	var job := AutochartJob.make_job("C:/a.mp3", "  N  ", "", "AUTO", "DRUMS",
		"C:/s", "C:/w", "C:/m", 2)
	assert_str(job["name"]).is_equal("N")
	assert_str(job["artist"]).is_equal("Unknown")
	assert_str(job["mode"]).is_equal("auto")
	assert_str(job["stem"]).is_equal("other")
	assert_str(job["genre"]).is_equal("Autochart")
	assert_float(float(job["target_nps"])).is_equal(3.5)
	assert_bool(job["replace"]).is_false()
	var single := AutochartJob.make_job("C:/a.mp3", "N", "A", "single", "Bass",
		"C:/s", "C:/w", "C:/m", 2, true)
	assert_str(single["stem"]).is_equal("bass")
	assert_bool(single["replace"]).is_true()


func test_validate_accepts_valid_job() -> void:
	assert_str(AutochartJob.validate(_valid_job())).is_equal("")
	for ext in AutochartJob.AUDIO_EXTS:
		var j := _valid_job()
		j["src"] = "C:/music/song." + ext.to_upper()
		assert_str(AutochartJob.validate(j)).is_equal("")


func test_validate_rejects_bad_type() -> void:
	for ext in ["opus", "m4a"]:
		var j := _valid_job()
		j["src"] = "C:/music/song." + ext
		assert_str(AutochartJob.validate(j)).is_equal("bad_type")


func test_validate_rejects_bad_fields() -> void:
	var cases := [
		["name", ""], ["name", "   "], ["mode", "chaos"], ["stem", "piano"], ["threads", 0],
		["threads", 65], ["target_nps", 20.0], ["songs_root", "rel/songs"],
		["work_root", "C:/a\"b"], ["models_root", "C:/m/"], ["src", "song.mp3"],
		["replace", "yes"], ["version", 2], ["artist", "x".repeat(121)], ["name", "x".repeat(121)],
	]
	for c in cases:
		var j := _valid_job()
		j[c[0]] = c[1]
		assert_str(AutochartJob.validate(j)).override_failure_message(str(c)).is_equal("bad_job")
	var missing := _valid_job()
	missing.erase("mode")
	assert_str(AutochartJob.validate(missing)).is_equal("bad_job")


# --- safe_path_arg ---------------------------------------------------------

func test_safe_path_arg() -> void:
	for bad in ["C:/a/", "C:\\a\\", "C:/a\"b", "rel/path", "", "C:/a\nb", "C:/a\tb"]:
		assert_bool(AutochartJob.safe_path_arg(bad)).override_failure_message(bad).is_false()
	for good in ["C:/a", "C:\\a\\b.json", "C:/Users/Some One/x.py"]:
		assert_bool(AutochartJob.safe_path_arg(good)).override_failure_message(good).is_true()


# --- error text ------------------------------------------------------------

func test_error_text_table() -> void:
	var codes := ["bad_job", "bad_type", "not_found", "too_big", "too_short", "too_long",
		"bad_rate", "decode", "no_beats", "no_notes", "exists", "disk", "memory", "selftest",
		"internal", "crash", "vcredist", "start"]
	assert_int(AutochartJob.ERROR_TEXT.size()).is_equal(18)
	for c in codes:
		assert_bool(AutochartJob.ERROR_TEXT.has(c)).override_failure_message(c).is_true()
	assert_str(AutochartJob.error_text("too_long")).is_equal(
		"Songs longer than 10 minutes are not supported.")
	assert_str(AutochartJob.error_text("vcredist")).is_equal(
		"Install the Microsoft Visual C++ Redistributable (x64), then try again.")
	assert_str(AutochartJob.error_text("nope")).is_equal(AutochartJob.error_text("internal"))
