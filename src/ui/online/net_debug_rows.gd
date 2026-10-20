class_name NetDebugRows
extends RefCounted
## F3 net rows (04-UI-SPEC 11.8, D-10 measure-first): formats NetSession.debug_stats() as exactly
## five lines for the DebugOverlay. Debug builds only (the overlay's existing gate). Any missing
## or non-numeric value prints "--"; ints print as ints and floats with one decimal.

const MISSING := "--"
const MAX_PEERS := 3


## Five lines joined with "\n" (no trailing newline).
static func format(stats: Dictionary) -> String:
	var role := str(stats.get("role", "")).to_upper()
	if role.is_empty():
		role = MISSING
	var lines: PackedStringArray = []
	lines.append("NET %s  SEAT %s  PEERS %s" % [role, num(stats, "seat"), num(stats, "peers")])
	lines.append(_rtt_line(stats, role == "HOST"))
	lines.append("HORIZON D %s MS  LATE INPUTS %s" % [num(stats, "horizon_ms"), num(stats, "late_inputs")])
	lines.append("SKEW %s MS  LANDED LATE LAST %s / MAX %s MS" % [num(stats, "skew_ms"),
		num(stats, "landed_late_last_ms"), num(stats, "landed_late_max_ms")])
	lines.append("REJECTED PACKETS %s  EVENT SEQ %s" % [num(stats, "rejected_packets"),
		num(stats, "event_seq")])
	return "\n".join(lines)


## Client: p50 / p90 and the clock offset. Host: per-peer p90 by name, up to 3, two spaces apart
## (falls back to the client form when there is no per-peer list).
static func _rtt_line(stats: Dictionary, host: bool) -> String:
	var per: Variant = stats.get("per_peer")
	if host and per is Array and not (per as Array).is_empty():
		var parts: PackedStringArray = []
		for p: Variant in per:
			if parts.size() >= MAX_PEERS:
				break
			if not (p is Dictionary):
				continue
			var nm := str((p as Dictionary).get("name", "")).strip_edges()
			parts.append("RTT %s %s MS" % [nm if nm != "" else MISSING, num(p, "p90_ms")])
		if not parts.is_empty():
			return "  ".join(parts)
	return "RTT P50 %s MS  P90 %s MS  OFFSET %s US" % [num(stats, "rtt_p50_ms"),
		num(stats, "rtt_p90_ms"), num(stats, "offset_us")]


## One value: int as "%d", finite float as "%.1f", anything else (missing, NaN, text) as "--".
static func num(d: Dictionary, key: String) -> String:
	var v: Variant = d.get(key)
	if v is int:
		return "%d" % v
	if v is float and is_finite(v):
		return "%.1f" % v
	return MISSING
