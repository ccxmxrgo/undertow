class_name LobbyState
extends RefCounted
## Lobby roster model and start gate (D-12, D-20, UI-SPEC 9.1 / 9.2). Pure data: no nodes,
## no Time, no Settings, no NetProtocol. The host owns the authoritative copy; clients rebuild a
## read-only copy from to_wire() snapshots with apply_wire().
##
## Rows are Dictionaries {seat, peer_id, name, ready, song_status, ping_ms, synced, host}.
## Seat 0 is the host (peer id 1, implicitly ready and synced). Clients take the lowest free
## seat 1..3. Seats bind to peer ids, never to names (T-04-10); names are de-duplicated with
## numeric suffixes ("DIVER", "DIVER2", "DIVER3").
##
## start_gate() codes in UI-SPEC 9.1 order: need_players, need_song, syncing,
## missing | changed, not_ready, ok.

const MAX_SEATS := 4
const HOST_PEER_ID := 1
const NAME_MAX := 12
const DEFAULT_NAME := "DIVER"
const SONG_STATUSES: Array[String] = ["none", "ok", "missing", "changed", "checking"]
const FLIGHTS: Array[int] = [2, 1]
const SONG_KEYS: Array[String] = ["fp", "sig", "diff", "title", "artist"]
const FRAME_S := 0.0167
const HIGH_LATENCY_S := 0.250

## Bumps on every real change so the session sends LOBBY only when something changed.
var revision: int = 0
## {fp, sig, diff, title, artist} or {} when the host has not picked.
var song: Dictionary = {}
## Torpedo flight in beats (2 internet, 1 same-room LAN).
var flight_beats: int = 2
## Index = seat. {} = open seat.
var _seats: Array[Dictionary] = []


func _init(p_host_name: String = DEFAULT_NAME) -> void:
	_clear_seats()
	_seats[0] = _make_row(0, HOST_PEER_ID, _base_name(p_host_name), true)


func _clear_seats() -> void:
	_seats.clear()
	for i in MAX_SEATS:
		_seats.append({})


func _make_row(p_seat: int, p_peer: int, p_name: String, p_host: bool) -> Dictionary:
	return {
		"seat": p_seat,
		"peer_id": p_peer,
		"name": p_name,
		"ready": p_host,
		"song_status": _status_for_new(p_host),
		"ping_ms": -1,
		"synced": p_host,
		"host": p_host,
	}


func _status_for_new(p_host: bool) -> String:
	if song.is_empty():
		return "none"
	return "ok" if p_host else "checking"


static func _base_name(n: String) -> String:
	var s := n.strip_edges().left(NAME_MAX).strip_edges()
	return s if s != "" else DEFAULT_NAME


func _name_taken(n: String, except_seat: int) -> bool:
	for r in _seats:
		if not r.is_empty() and r.seat != except_seat and r.name == n:
			return true
	return false


func _unique_name(n: String, seat: int) -> String:
	var base := _base_name(n)
	if not _name_taken(base, seat):
		return base
	for k in range(2, 100):
		var suffix := str(k)
		var cand := base.left(NAME_MAX - suffix.length()).strip_edges() + suffix
		if not _name_taken(cand, seat):
			return cand
	return base


func _bump() -> void:
	revision += 1


# --- roster ---


## Seats a client in the lowest free seat 1..3. Returns the seat, or -1 when full, when the
## peer id is already seated or is the host's id.
func add_peer(peer_id: int, p_name: String) -> int:
	if peer_id <= 0 or peer_id == HOST_PEER_ID or seat_of(peer_id) >= 0:
		return -1
	for seat in range(1, MAX_SEATS):
		if _seats[seat].is_empty():
			_seats[seat] = _make_row(seat, peer_id, _unique_name(p_name, seat), false)
			_bump()
			return seat
	return -1


## Frees the peer's seat and returns it (-1 when absent or the host).
func remove_peer(peer_id: int) -> int:
	var seat := seat_of(peer_id)
	if seat <= 0:
		return -1
	_seats[seat] = {}
	_bump()
	return seat


func seat_of(peer_id: int) -> int:
	for r in _seats:
		if not r.is_empty() and r.peer_id == peer_id:
			return r.seat
	return -1


## Peer id seated at `seat`, or 0 when the seat is open or out of range.
func peer_of(seat: int) -> int:
	if seat < 0 or seat >= MAX_SEATS or _seats[seat].is_empty():
		return 0
	return _seats[seat].peer_id


## Copy of the row at `seat`, or {} for an open / out-of-range seat.
func row(seat: int) -> Dictionary:
	if seat < 0 or seat >= MAX_SEATS:
		return {}
	return _seats[seat].duplicate()


## Copies of the occupied rows in seat order.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _seats:
		if not r.is_empty():
			out.append(r.duplicate())
	return out


func present_count() -> int:
	var n := 0
	for r in _seats:
		if not r.is_empty():
			n += 1
	return n


func is_full() -> bool:
	return present_count() >= MAX_SEATS


func _set_field(seat: int, key: String, value: Variant) -> void:
	if seat < 0 or seat >= MAX_SEATS or _seats[seat].is_empty():
		return
	if _seats[seat][key] == value:
		return
	_seats[seat][key] = value
	_bump()


## The host is implicitly ready; set_ready on seat 0 is ignored.
func set_ready(seat: int, v: bool) -> void:
	if seat == 0:
		return
	_set_field(seat, "ready", v)


## status is one of SONG_STATUSES; anything else is ignored.
func set_song_status(seat: int, status: String) -> void:
	if not SONG_STATUSES.has(status):
		return
	_set_field(seat, "song_status", status)


## Round-trip ms (-1 = no samples yet).
func set_ping(seat: int, ms: int) -> void:
	_set_field(seat, "ping_ms", maxi(ms, -1))


## True once the clock sync has 5 or more samples (D-06).
func set_synced(seat: int, v: bool) -> void:
	_set_field(seat, "synced", v)


# --- match settings ---


## Sets the song {fp, sig, diff, title, artist}. A change (fingerprint, signature or difficulty)
## clears every client's Ready and marks their SONG "checking" (D-12). Returns true on change.
## {} clears the song.
func set_song(p_song: Dictionary) -> bool:
	var next := {}
	if not p_song.is_empty():
		for k in SONG_KEYS:
			next[k] = str(p_song.get(k, ""))
	if _same_song(song, next):
		if next != song:
			song = next  # title/artist cosmetic refresh, no Ready reset
			_bump()
		return false
	song = next
	for r in _seats:
		if r.is_empty():
			continue
		if r.host:
			r.song_status = "none" if song.is_empty() else "ok"
		else:
			r.ready = false
			r.song_status = "none" if song.is_empty() else "checking"
	_bump()
	return true


static func _same_song(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return a.fp == b.fp and a.sig == b.sig and a.diff == b.diff


## 2 or 1 beats. Does not clear Ready (not a song change). Returns true on change.
func set_flight(beats: int) -> bool:
	if not FLIGHTS.has(beats) or beats == flight_beats:
		return false
	flight_beats = beats
	_bump()
	return true


# --- start gate ---


## First failing rule of UI-SPEC 9.1: {ok, code, name, n}. `name` is the single offender's name
## ("" when several fail; `n` is then their count). A SONG status of checking counts as missing.
func start_gate() -> Dictionary:
	var present := rows()
	if present.size() < 2:
		return _gate("need_players", [], present.size())
	if song.is_empty():
		return _gate("need_song", [], 0)
	var clients: Array[Dictionary] = []
	for r in present:
		if not r.host:
			clients.append(r)
	var bad: Array[Dictionary] = []
	for r in clients:
		if not r.synced:
			bad.append(r)
	if not bad.is_empty():
		return _gate("syncing", bad, bad.size())
	for r in clients:
		if r.song_status != "ok":
			bad.append(r)
	if not bad.is_empty():
		var code := "changed" if bad[0].song_status == "changed" else "missing"
		return _gate(code, bad, bad.size())
	for r in clients:
		if not r.ready:
			bad.append(r)
	if not bad.is_empty():
		return _gate("not_ready", bad, bad.size())
	return {"ok": true, "code": "ok", "name": "", "n": present.size()}


static func _gate(code: String, bad: Array[Dictionary], n: int) -> Dictionary:
	var who: String = bad[0].name if bad.size() == 1 else ""
	return {"ok": false, "code": code, "name": who, "n": n}


# --- wire snapshot ---


func to_wire() -> Dictionary:
	return {"rev": revision, "flight": flight_beats, "song": song.duplicate(), "rows": rows()}


## Rebuilds this copy from a host snapshot. The snapshot is untrusted (network): every field is
## type- and range-checked; on any failure nothing changes and false is returned.
func apply_wire(d: Dictionary) -> bool:
	var rev: Variant = d.get("rev")
	var fl: Variant = d.get("flight")
	var sg: Variant = d.get("song")
	var rs: Variant = d.get("rows")
	if typeof(rev) != TYPE_INT or typeof(fl) != TYPE_INT or not FLIGHTS.has(fl):
		return false
	if typeof(sg) != TYPE_DICTIONARY or typeof(rs) != TYPE_ARRAY or rs.size() > MAX_SEATS:
		return false
	var new_song := {}
	if not sg.is_empty():
		for k in SONG_KEYS:
			var v: Variant = sg.get(k)
			if typeof(v) != TYPE_STRING or v.length() > 1024:
				return false
			new_song[k] = v
	var new_seats: Array[Dictionary] = []
	for i in MAX_SEATS:
		new_seats.append({})
	for item in rs:
		var r := _row_from_wire(item)
		if r.is_empty() or not new_seats[r.seat].is_empty():
			return false
		new_seats[r.seat] = r
	if new_seats[0].is_empty() or not new_seats[0].host:
		return false
	revision = rev
	flight_beats = fl
	song = new_song
	_seats = new_seats
	return true


static func _row_from_wire(item: Variant) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return {}
	var seat: Variant = item.get("seat")
	var peer: Variant = item.get("peer_id")
	var nm: Variant = item.get("name")
	var rd: Variant = item.get("ready")
	var st: Variant = item.get("song_status")
	var pg: Variant = item.get("ping_ms")
	var sy: Variant = item.get("synced")
	var hs: Variant = item.get("host")
	if typeof(seat) != TYPE_INT or seat < 0 or seat >= MAX_SEATS:
		return {}
	if typeof(peer) != TYPE_INT or peer <= 0:
		return {}
	if typeof(nm) != TYPE_STRING or nm.length() < 1 or nm.length() > NAME_MAX:
		return {}
	if typeof(rd) != TYPE_BOOL or typeof(sy) != TYPE_BOOL or typeof(hs) != TYPE_BOOL:
		return {}
	if typeof(st) != TYPE_STRING or not SONG_STATUSES.has(st):
		return {}
	if typeof(pg) != TYPE_INT or pg < -1:
		return {}
	if hs != (seat == 0):
		return {}
	return {"seat": seat, "peer_id": peer, "name": nm, "ready": rd, "song_status": st,
		"ping_ms": pg, "synced": sy, "host": hs}


# --- display helpers (UI-SPEC 9.2) ---


## Lit signal bars: <= 60 ms 4, <= 120 ms 3, <= 200 ms 2, else 1; no samples (< 0) 0.
static func ping_bars(ms: int) -> int:
	if ms < 0:
		return 0
	if ms <= 60:
		return 4
	if ms <= 120:
		return 3
	if ms <= 200:
		return 2
	return 1


## D + L + F > 250 ms, with L = RTT / 2 and F = one 60 Hz frame (research Latency Budget).
static func is_high_latency(d_s: float, rtt_ms: float) -> bool:
	return d_s + rtt_ms / 2000.0 + FRAME_S > HIGH_LATENCY_S
