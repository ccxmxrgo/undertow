class_name ChartFile
extends RefCounted
## Single chart-parse choke point (CONT-01). Scan, play, Song Select sections and the playtest
## harness all parse through here, so the scan fingerprint equals the play fingerprint.


static func is_chart_ext(ext: String) -> bool:
	var e := ext.to_lower()
	return e == "chart" or e == "mid"


static func max_bytes_for(path: String) -> int:
	if path.get_extension().to_lower() == "mid":
		return MidiChartReader.MAX_BYTES
	return ChartParser.MAX_BYTES


static func parse(path: String) -> ParsedChart:
	var ext := path.get_extension().to_lower()
	if ext != "chart" and ext != "mid":
		return _fail(SongEntry.err_unreadable(0))
	var unreadable := SongEntry.ERR_MIDI_BAD if ext == "mid" else SongEntry.err_unreadable(0)
	if not FileAccess.file_exists(path):
		return _fail(unreadable)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail(unreadable)
	var nbytes := f.get_length()
	if nbytes > max_bytes_for(path):
		f.close()
		return _fail(SongEntry.ERR_TOO_LARGE)
	var bytes := f.get_buffer(nbytes)
	f.close()
	var parsed: ParsedChart
	if ext == "mid":
		parsed = MidiChartReader.parse_bytes(bytes)
	else:
		parsed = ChartParser.parse_bytes(bytes)
	if not parsed.ok and parsed.error == "":
		parsed.error = unreadable
	return parsed


static func _fail(err: String) -> ParsedChart:
	var pc := ParsedChart.new()
	pc.ok = false
	pc.error = err
	return pc
