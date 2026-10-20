class_name NetCodec
extends RefCounted
## The single choke point for every peer message (D-02, D-23, RESEARCH Pattern 4, Security V5).
##
## Rules:
## - decode() checks the packet size first, then uses plain bytes_to_var. Object decoding is
##   never used, so a peer can never instantiate a script or resource.
## - validate() returns {} for anything malformed: wrong direction, unknown type, missing or
##   extra keys, wrong Variant types, NaN/INF or out-of-range times, bad seats, note indices,
##   judgments, over-long arrays/strings and control characters. On success it returns a deep
##   copy of the message, which by construction passes validate() again.
## - A seat is never trusted from a payload. Seat fields here are only range-checked; the
##   session binds the sender's seat from its peer id.
## - Never index into anything before checking its type.
##
## ctx (built by the receiver, trusted): {from_host: bool (the packet came from the host),
## note_count: int (0 = no chart loaded: every JUDGED item is rejected), song_len: float
## (<= 0 = unknown: NetProtocol.MAX_SONG_S is used), max_seat: int (highest seat, default 3)}.


## Event keys that carry a seat: an int in -1..3 at any nesting level.
const SEAT_KEYS: Array[String] = ["seat", "from", "to", "target", "sender", "winner"]
## Float keys that may also be +INF/-INF (MatchSim uses INF for "alive", -INF for "never").
## Any key ending in "_until" is allowed too. NaN is rejected everywhere.
const INF_KEYS: Array[String] = ["eliminated_at", "until_t", "immune_until"]
const MAX_EVENT_KEYS := 24
const MAX_NESTED_KEYS := 8
const MAX_MEDALS := 8
const MAX_ROW_KEYS := 16
const MAX_DIFF_STR := 16
const SIG_LEN := 16
const MAX_PING_MS := 99999
const MAX_LEAD_MS := 600000
const MAX_D_MS := 1000
const MAX_APPROACH_S := 10.0

## RESULTS row key -> type tag (MatchSim.standings + VersusController.finish + 04-10 online).
const ROW_KEYS := {
	"seat": "seat", "place": "place", "alive": "bool", "depth": "float_pos", "hull": "float",
	"accuracy": "float", "max_streak": "int_pos", "eliminated_at": "float_or_inf",
	"name": "name", "landed": "int_pos", "reflected": "int_pos", "left": "bool",
	"left_t": "float",
}


static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## Size check, plain Variant decode, then validate. {} for anything rejected.
static func decode(bytes: PackedByteArray, ctx: Dictionary) -> Dictionary:
	if bytes.size() > NetProtocol.MAX_PACKET or bytes.size() < 4:
		return {}
	var v: Variant = bytes_to_var(bytes)
	return validate(v, ctx)


static func validate(v: Variant, ctx: Dictionary) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var m: Dictionary = v
	var ty: Variant = m.get("type")
	if not (ty is String):
		return {}
	var from_host := bool(ctx.get("from_host", false))
	if from_host:
		if not NetProtocol.FROM_HOST.has(ty):
			return {}
	elif not NetProtocol.FROM_CLIENT.has(ty):
		return {}
	var ok := false
	match ty:
		NetProtocol.PING: ok = _v_ping(m)
		NetProtocol.PONG: ok = _v_pong(m)
		NetProtocol.AUTH: ok = _v_auth(m)
		NetProtocol.AUTH_REPLY: ok = _v_auth_reply(m)
		NetProtocol.READY: ok = _v_ready(m)
		NetProtocol.SONG_STATUS: ok = _v_song_status(m)
		NetProtocol.LOADED, NetProtocol.LOAD_FAIL, NetProtocol.BYE, NetProtocol.BACK_TO_LOBBY, \
				NetProtocol.LOBBY_CLOSED:
			ok = _keys(m, [])
		NetProtocol.START_LATE: ok = _v_start_late(m)
		NetProtocol.INPUTS: ok = _v_inputs(m, ctx)
		NetProtocol.DONE: ok = _keys(m, ["t"]) and _time_ok(m["t"], ctx)
		NetProtocol.HEARTBEAT: ok = _v_heartbeat(m, ctx)
		NetProtocol.LOBBY: ok = _v_lobby(m, ctx)
		NetProtocol.NOTICE: ok = _v_notice(m)
		NetProtocol.KICKED, NetProtocol.MATCH_ABORT:
			ok = _keys(m, ["reason"]) and _one_of(m["reason"], NetProtocol.REASONS)
		NetProtocol.LOAD: ok = _v_load(m, ctx)
		NetProtocol.START: ok = _keys(m, ["host_start_ticks"]) and m["host_start_ticks"] is int
		NetProtocol.ABORT_TO_LOBBY: ok = _v_abort_to_lobby(m)
		NetProtocol.EVENTS: ok = _v_events(m, ctx)
		NetProtocol.RESULTS: ok = _v_results(m, ctx)
	if not ok:
		return {}
	return m.duplicate(true)


# --- Per-message validators ----------------------------------------------------------------------

static func _v_ping(m: Dictionary) -> bool:
	return _keys(m, ["seq", "c0"]) and _int_ge(m["seq"], 0) and m["c0"] is int


static func _v_pong(m: Dictionary) -> bool:
	return _keys(m, ["seq", "c0", "h"]) and _int_ge(m["seq"], 0) and m["c0"] is int \
		and m["h"] is int


## The name is only charset-checked loosely here (String <= MAX_STR, no control chars) so the
## host can answer a bad name with AUTH_REPLY reason "bad_name": it must run clean_name itself.
static func _v_auth(m: Dictionary) -> bool:
	return _keys(m, ["proto", "game", "name"]) and m["proto"] is int \
		and _str_ok(m["game"], NetProtocol.MAX_STR) and _str_ok(m["name"], NetProtocol.MAX_STR)


static func _v_auth_reply(m: Dictionary) -> bool:
	if not _keys(m, ["ok", "reason", "host_version"]):
		return false
	if not (m["ok"] is bool) or not _str_ok(m["host_version"], NetProtocol.MAX_STR):
		return false
	return m["reason"] is String and (m["reason"] == "" or _one_of(m["reason"], NetProtocol.REASONS))


static func _v_ready(m: Dictionary) -> bool:
	return _keys(m, ["ready", "synced"]) and m["ready"] is bool and m["synced"] is bool


static func _v_song_status(m: Dictionary) -> bool:
	return _keys(m, ["status", "synced"]) and _one_of(m["status"], NetProtocol.SONG_STATES) \
		and m["synced"] is bool


static func _v_start_late(m: Dictionary) -> bool:
	return _keys(m, ["lead_ms"]) and _int_in(m["lead_ms"], -MAX_LEAD_MS, MAX_LEAD_MS)


static func _v_inputs(m: Dictionary, ctx: Dictionary) -> bool:
	if not _keys(m, ["items"]) or not (m["items"] is Array):
		return false
	var items: Array = m["items"]
	if items.size() > NetProtocol.MAX_BATCH:
		return false
	for it in items:
		if not _item_ok(it, ctx):
			return false
	return true


static func _v_heartbeat(m: Dictionary, ctx: Dictionary) -> bool:
	return _keys(m, ["song_t", "ticks"]) and _time_ok(m["song_t"], ctx) and m["ticks"] is int


static func _v_lobby(m: Dictionary, ctx: Dictionary) -> bool:
	if not _keys(m, ["roster", "song", "flight", "phase"]):
		return false
	if not _int_in(m["flight"], 1, 2) or not _token_ok(m["phase"]):
		return false
	if not (m["song"] is Dictionary) or not _song_ok(m["song"]):
		return false
	if not (m["roster"] is Array):
		return false
	var roster: Array = m["roster"]
	if roster.size() > NetProtocol.MAX_ROWS:
		return false
	var seen := {}
	for r in roster:
		if not (r is Dictionary):
			return false
		var row: Dictionary = r
		if not _keys(row, ["seat", "name", "ready", "song", "ping_ms", "synced", "host"]):
			return false
		if not _seat_ok(row["seat"], ctx) or seen.has(row["seat"]):
			return false
		seen[row["seat"]] = true
		if not _name_ok(row["name"]) or not (row["ready"] is bool) \
				or not _one_of(row["song"], NetProtocol.SONG_STATES) or not (row["synced"] is bool) \
				or not (row["host"] is bool) or not _int_in(row["ping_ms"], 0, MAX_PING_MS):
			return false
	return true


## Empty, or {fp, sig, diff, title, artist}.
static func _song_ok(s: Dictionary) -> bool:
	if s.is_empty():
		return true
	if not _keys(s, ["fp", "sig", "diff", "title", "artist"]):
		return false
	return _str_ok(s["fp"], NetProtocol.MAX_TEXT) and _sig_ok(s["sig"]) \
		and _one_of(s["diff"], NetProtocol.DIFFICULTIES) \
		and _str_ok(s["title"], NetProtocol.MAX_TEXT) and _str_ok(s["artist"], NetProtocol.MAX_TEXT)


static func _v_notice(m: Dictionary) -> bool:
	return _keys(m, ["code", "name", "n"]) and _token_ok(m["code"]) \
		and _name_or_empty(m["name"]) and m["n"] is int


static func _v_load(m: Dictionary, ctx: Dictionary) -> bool:
	if not _keys(m, ["fp", "sig", "diff", "seed", "flight", "roster", "d_ms", "max_song_s",
			"autoplay"]):
		return false
	if not _str_ok(m["fp"], NetProtocol.MAX_TEXT) or (m["fp"] as String).is_empty():
		return false
	if not _sig_ok(m["sig"]) or not _one_of(m["diff"], NetProtocol.DIFFICULTIES) \
			or not (m["seed"] is int):
		return false
	if not _int_in(m["flight"], 1, 2) or not _int_in(m["d_ms"], 0, MAX_D_MS):
		return false
	if not _finite(m["max_song_s"]) or float(m["max_song_s"]) < 0.0 \
			or float(m["max_song_s"]) > NetProtocol.MAX_SONG_S:
		return false
	if not (m["autoplay"] is bool) or not (m["roster"] is Array):
		return false
	var roster: Array = m["roster"]
	if roster.is_empty() or roster.size() > NetProtocol.MAX_ROWS:
		return false
	var seen := {}
	for r in roster:
		if not (r is Dictionary) or not _keys(r, ["seat", "name"]):
			return false
		if not _seat_ok(r["seat"], ctx) or seen.has(r["seat"]) or not _name_ok(r["name"]):
			return false
		seen[r["seat"]] = true
	return true


static func _v_abort_to_lobby(m: Dictionary) -> bool:
	return _keys(m, ["reason", "name"]) and _one_of(m["reason"], NetProtocol.REASONS) \
		and _name_or_empty(m["name"])


static func _v_events(m: Dictionary, ctx: Dictionary) -> bool:
	if not _keys(m, ["seq", "events"]) or not _int_ge(m["seq"], 0) or not (m["events"] is Array):
		return false
	var evs: Array = m["events"]
	if evs.size() > NetProtocol.MAX_BATCH:
		return false
	for e in evs:
		if not validate_event(e, ctx):
			return false
	return true


## RESULTS has its own schema (D-19): rows, medals, last_standing_seat, local_seat, plus the
## optional display fields VersusController.finish and the online host add.
static func _v_results(m: Dictionary, ctx: Dictionary) -> bool:
	if not _keys(m, ["rows", "medals", "last_standing_seat", "local_seat"],
			["title", "artist", "difficulty", "seed", "online", "is_host", "host_seat",
			"host_name"]):
		return false
	if not _int_in(m["last_standing_seat"], -1, NetProtocol.MAX_SEATS - 1):
		return false
	if not _seat_ok(m["local_seat"], ctx):
		return false
	if m.has("title") and not _str_ok(m["title"], NetProtocol.MAX_TEXT):
		return false
	if m.has("artist") and not _str_ok(m["artist"], NetProtocol.MAX_TEXT):
		return false
	if m.has("difficulty") and not _str_ok(m["difficulty"], MAX_DIFF_STR):
		return false
	if m.has("seed") and not (m["seed"] is int):
		return false
	for k in ["online", "is_host"]:
		if m.has(k) and not (m[k] is bool):
			return false
	if m.has("host_seat") and not _seat_ok(m["host_seat"], ctx):
		return false
	if m.has("host_name") and not _name_ok(m["host_name"]):
		return false
	if not (m["rows"] is Array):
		return false
	var rows: Array = m["rows"]
	if rows.size() > NetProtocol.MAX_ROWS:
		return false
	for r in rows:
		if not _row_ok(r, ctx):
			return false
	if not (m["medals"] is Dictionary):
		return false
	var medals: Dictionary = m["medals"]
	if medals.size() > NetProtocol.MAX_SEATS:
		return false
	for s in medals:
		if not _int_in(s, 0, NetProtocol.MAX_SEATS - 1) or not (medals[s] is Array):
			return false
		var list: Array = medals[s]
		if list.size() > MAX_MEDALS:
			return false
		for id in list:
			if not _str_ok(id, NetProtocol.MAX_STR):
				return false
	return true


static func _row_ok(r: Variant, ctx: Dictionary) -> bool:
	if not (r is Dictionary):
		return false
	var row: Dictionary = r
	if row.size() > MAX_ROW_KEYS or not row.has("seat"):
		return false
	for k in row:
		if not (k is String) or not ROW_KEYS.has(k):
			return false
		var v: Variant = row[k]
		var ok := false
		match ROW_KEYS[k]:
			"seat": ok = _seat_ok(v, ctx)
			"place": ok = _int_in(v, 1, NetProtocol.MAX_SEATS)
			"bool": ok = v is bool
			"float": ok = _finite(v)
			"float_pos": ok = _finite(v) and float(v) >= 0.0
			"float_or_inf": ok = _is_num(v) and not is_nan(float(v)) and float(v) != -INF
			"int_pos": ok = _int_ge(v, 0)
			"name": ok = _name_ok(v)
		if not ok:
			return false
	return true


# --- INPUTS items --------------------------------------------------------------------------------

## [kind, t, seq, ...args] with the arity and arg types from NetProtocol.IN_ARITY.
static func _item_ok(it: Variant, ctx: Dictionary) -> bool:
	if not (it is Array):
		return false
	var a: Array = it
	if a.size() < NetProtocol.ITEM_HEAD or not (a[0] is int) or not NetProtocol.IN_ARITY.has(a[0]):
		return false
	var kind: int = a[0]
	if a.size() != NetProtocol.ITEM_HEAD + int(NetProtocol.IN_ARITY[kind]):
		return false
	if not _time_ok(a[1], ctx) or not _int_ge(a[2], 0):
		return false
	match kind:
		NetProtocol.IN_JUDGED:
			var nc := int(ctx.get("note_count", 0))
			return _int_in(a[3], 0, nc - 1) and _judgment_ok(a[4])
		NetProtocol.IN_EXTRA:
			return _judgment_ok(a[3])
		NetProtocol.IN_STATUS:
			return _finite(a[3]) and _finite(a[4]) and _finite(a[5]) and _int_ge(a[6], 0)
		NetProtocol.IN_TARGET_MODE:
			return a[3] is int and PlayerState.TargetMode.values().has(a[3]) \
				and _int_in(a[4], -1, NetProtocol.MAX_SEATS - 1)
		NetProtocol.IN_APPROACH:
			return _finite(a[3]) and float(a[3]) >= 0.0 and float(a[3]) <= MAX_APPROACH_S
	return true


static func _judgment_ok(v: Variant) -> bool:
	return v is int and InputJudge.Judgment.values().has(v)


# --- Events (generic rule set; reads GameEvent.ALL_TYPES at runtime) -----------------------------

## An event: type in GameEvent.ALL_TYPES, finite t, <= 24 keys. Values are scalars, Arrays
## (<= MAX_EVENT_ARRAY) of scalars or flat Dictionaries, or flat Dictionaries (<= 8 keys of
## scalars): nesting depth at most 3. Seat keys hold an int -1..3 at every level.
static func validate_event(e: Variant, _ctx: Dictionary = {}) -> bool:
	if not (e is Dictionary):
		return false
	var d: Dictionary = e
	if d.size() > MAX_EVENT_KEYS:
		return false
	var ty: Variant = d.get("type")
	if not (ty is String) or not GameEvent.ALL_TYPES.has(ty):
		return false
	if not d.has("t") or not _finite(d["t"]):
		return false
	for k in d:
		if not (k is String) or (k as String).length() > NetProtocol.MAX_STR:
			return false
		if k == "type" or k == "t":
			continue
		if not _ev_value(k, d[k]):
			return false
	return true


static func _ev_value(key: String, v: Variant) -> bool:
	if v is Array:
		var a: Array = v
		if a.size() > NetProtocol.MAX_EVENT_ARRAY:
			return false
		for x in a:
			if x is Dictionary:
				if not _ev_flat_dict(x):
					return false
			elif not _ev_scalar(key, x):
				return false
		return true
	if v is Dictionary:
		return _ev_flat_dict(v)
	return _ev_scalar(key, v)


static func _ev_flat_dict(d: Dictionary) -> bool:
	if d.size() > MAX_NESTED_KEYS:
		return false
	for k in d:
		var key := ""
		if k is String:
			if (k as String).length() > NetProtocol.MAX_STR:
				return false
			key = k
		elif not (k is int):
			return false
		if not _ev_scalar(key, d[k]):
			return false
	return true


static func _ev_scalar(key: String, v: Variant) -> bool:
	if SEAT_KEYS.has(key):
		return _int_in(v, -1, NetProtocol.MAX_SEATS - 1)
	if v is bool or v is int:
		return true
	if v is float:
		var f: float = v
		if is_nan(f):
			return false
		return is_finite(f) or _inf_key(key)
	if v is String:
		return _str_ok(v, NetProtocol.MAX_STR)
	return false


static func _inf_key(key: String) -> bool:
	return INF_KEYS.has(key) or key.ends_with("_until")


# --- Names ---------------------------------------------------------------------------------------

## The upper-cased name when it is 1-12 chars of [A-Z0-9 _-] (after strip_edges), else "".
static func clean_name(s: Variant) -> String:
	if not (s is String):
		return ""
	var n := (s as String).strip_edges().to_upper()
	if n.is_empty() or n.length() > NetProtocol.MAX_NAME:
		return ""
	for i in n.length():
		var c := n.unicode_at(i)
		var ok := (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 32 or c == 95 \
			or c == 45
		if not ok:
			return ""
	return n


static func _name_ok(v: Variant) -> bool:
	return not clean_name(v).is_empty()


static func _name_or_empty(v: Variant) -> bool:
	return (v is String and (v as String).is_empty()) or _name_ok(v)


# --- Primitive checks ----------------------------------------------------------------------------

## Every required key present, and no key outside required + optional.
static func _keys(m: Variant, required: Array, optional: Array = []) -> bool:
	if not (m is Dictionary):
		return false
	var d: Dictionary = m
	for k in required:
		if not d.has(k):
			return false
	var n := 1 if d.has("type") else 0
	for k in d:
		if not (k is String):
			return false
		if k == "type":
			continue
		if not required.has(k) and not optional.has(k):
			return false
	return d.size() <= required.size() + optional.size() + n


static func _is_num(v: Variant) -> bool:
	return v is int or v is float


static func _finite(v: Variant) -> bool:
	return _is_num(v) and is_finite(float(v))


static func _int_ge(v: Variant, lo: int) -> bool:
	return v is int and int(v) >= lo


static func _int_in(v: Variant, lo: int, hi: int) -> bool:
	return v is int and int(v) >= lo and int(v) <= hi


static func _seat_ok(v: Variant, ctx: Dictionary) -> bool:
	var hi := clampi(int(ctx.get("max_seat", NetProtocol.MAX_SEATS - 1)), 0, NetProtocol.MAX_SEATS - 1)
	return _int_in(v, 0, hi)


## A finite song time in [TIME_MIN_S, song_len + TIME_SLACK_S].
static func _time_ok(v: Variant, ctx: Dictionary) -> bool:
	if not _finite(v):
		return false
	var len_v: Variant = ctx.get("song_len", 0.0)
	var song_len := float(len_v) if _finite(len_v) and float(len_v) > 0.0 else NetProtocol.MAX_SONG_S
	var t := float(v)
	return t >= NetProtocol.TIME_MIN_S and t <= song_len + NetProtocol.TIME_SLACK_S


## A String of at most max_len chars with no control characters (C0, DEL, C1).
static func _str_ok(v: Variant, max_len: int) -> bool:
	if not (v is String):
		return false
	var s: String = v
	if s.length() > max_len:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or (c >= 127 and c < 160):
			return false
	return true


## A lowercase identifier token: 1..MAX_STR chars of [a-z0-9_].
static func _token_ok(v: Variant) -> bool:
	if not (v is String):
		return false
	var s: String = v
	if s.is_empty() or s.length() > NetProtocol.MAX_STR:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


## VersusSig: exactly 16 lowercase hex chars.
static func _sig_ok(v: Variant) -> bool:
	if not (v is String):
		return false
	var s: String = v
	if s.length() != SIG_LEN:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## v is a String in list (typed-array has() would log an error for a non-String).
static func _one_of(v: Variant, list: Array[String]) -> bool:
	return v is String and list.has(v)
