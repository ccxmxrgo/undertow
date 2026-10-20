class_name VersusSig
extends RefCounted
## The versus song signature (D-11): first 16 lowercase hex chars of SHA-256 over the chart's
## time_sigs and solos, the two inputs MatchSim uses that the SONG-05 fingerprint (chart.id)
## leaves out. The lobby compares fingerprint + this signature, so peers only start when their
## built charts agree on bars and Solo Duels. Notes, tempo, title and artist are ignored here
## (the fingerprint covers notes and tempo).
##
## Runtime only; chart_importer.gd is never edited. Canonical form: one line per entry,
## "<list>:<k>=<v>,..." with keys sorted, every number as "%.6f" (so 4 and 4.0 agree).


static func of(chart: ChartData) -> String:
	var sb := PackedStringArray()
	sb.append("vsig:1")
	sb.append("ts:%d" % chart.time_sigs.size())
	for d in chart.time_sigs:
		sb.append("t:" + _canon(d))
	sb.append("solos:%d" % chart.solos.size())
	for d in chart.solos:
		sb.append("s:" + _canon(d))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(sb).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


static func _canon(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [str(k), _val(d[k])])
	return ",".join(parts)


static func _val(v: Variant) -> String:
	if v is int or v is float:
		return "%.6f" % float(v)
	if v is bool:
		return "true" if v else "false"
	return str(v).c_escape()
