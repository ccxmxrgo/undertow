extends SceneTree
## Dumps a chart's note and beat times exactly as the game computes them (02.1-01, sync gate).
## One source of truth for chart time: ChartParser + ChartImporter.build (tick -> seconds + song.ini delay).
## Usage (repo root):
##   GODOT_BIN --headless --path . --script res://tools/autochart/dump_chart_times.gd -- \
##       <notes.chart (res:// or absolute)> <song.ini> <difficulty> <out.json>
## Output JSON: {"delay_ms", "resolution", "difficulty", "notes": [[time_s, lane, duration_s], ...],
##               "beats": [time_s of every tick multiple of resolution from 0 to the last note tick],
##               "solos": [{start, end, note_count}]}
## Prints DUMP_OK <notes> <beats> or DUMP_FAIL <reason> (exit 1).


func _initialize() -> void:
	var code := _run()
	quit(code)


func _fail(reason: String) -> int:
	print("DUMP_FAIL %s" % reason)
	return 1


func _run() -> int:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		return _fail("usage: -- <chart> <ini> <difficulty> <out.json>")
	var chart_path := String(args[0])
	var ini_path := String(args[1])
	var diff := String(args[2]).to_lower()
	var out_path := String(args[3])
	if not ChartImporter.DIFFICULTIES.has(diff):
		return _fail("unknown difficulty %s" % diff)
	if not FileAccess.file_exists(chart_path):
		return _fail("chart not found %s" % chart_path)
	var parsed := ChartParser.parse_bytes(FileAccess.get_file_as_bytes(chart_path))
	if parsed == null or not parsed.ok:
		return _fail("chart parse error %s" % ("" if parsed == null else parsed.error))
	var delay_ms := 0
	if ini_path != "" and FileAccess.file_exists(ini_path):
		delay_ms = SongIni.get_int(SongIni.parse(FileAccess.get_file_as_string(ini_path)), "delay", 0)
	elif ini_path != "":
		return _fail("ini not found %s" % ini_path)
	var chart := ChartImporter.build(parsed, diff, delay_ms)
	if chart == null or chart.notes.is_empty():
		return _fail("no %s notes" % diff)

	var notes: Array = []
	for n in chart.notes:
		notes.append([float(n["time"]), int(n["lane"]), float(n["duration"])])

	var res := maxi(parsed.resolution, 1)
	var segs := ChartImporter._segments(parsed)
	var last_tick := 0
	for g in ChartImporter._collect(parsed, diff):
		last_tick = maxi(last_tick, int(g["tick"]))
	var delay := float(delay_ms) / 1000.0
	var beats: Array = []
	var tick := 0
	while tick <= last_tick:
		beats.append(ChartImporter._tick_to_sec(segs, res, tick) + delay)
		tick += res

	var solos: Array = []
	for s in chart.solos:
		solos.append({"start": s["start"], "end": s["end"], "note_count": s["note_count"]})

	var doc := {"delay_ms": delay_ms, "resolution": res, "difficulty": diff, "notes": notes,
		"beats": beats, "solos": solos}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return _fail("cannot write %s" % out_path)
	f.store_string(JSON.stringify(doc, "", false, true))
	f.close()
	print("DUMP_OK %d %d" % [notes.size(), beats.size()])
	return 0
