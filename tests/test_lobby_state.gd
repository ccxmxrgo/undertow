extends GdUnitTestSuite
## Plan 04-03 Task 2: LobbyState roster model and start gate (D-12, UI-SPEC 9.1 / 9.2).

const SONG_A := {"fp": "aaa", "sig": "s1", "diff": "expert", "title": "HRT", "artist": "X"}
const SONG_B := {"fp": "bbb", "sig": "s2", "diff": "hard", "title": "INVISIBLE", "artist": "Y"}


func _lobby_with(n_clients: int) -> LobbyState:
	var l := LobbyState.new("HOSTY")
	for i in n_clients:
		l.add_peer(100 + i, "C%d" % i)
	return l


## Makes every client synced, song OK and ready.
func _all_good(l: LobbyState) -> void:
	for r in l.rows():
		if not r.host:
			l.set_synced(r.seat, true)
			l.set_song_status(r.seat, "ok")
			l.set_ready(r.seat, true)


func test_host_seated_at_zero() -> void:
	var l := LobbyState.new("HOSTY")
	assert_int(l.seat_of(1)).is_equal(0)
	assert_int(l.peer_of(0)).is_equal(1)
	var r: Dictionary = l.row(0)
	assert_str(r.name).is_equal("HOSTY")
	assert_bool(r.host).is_true()
	assert_bool(r.ready).is_true()
	assert_bool(r.synced).is_true()
	assert_str(r.song_status).is_equal("none")
	assert_int(l.present_count()).is_equal(1)


func test_host_song_status_ok_once_song_set() -> void:
	var l := LobbyState.new("HOSTY")
	l.set_song(SONG_A)
	assert_str(l.row(0).song_status).is_equal("ok")


func test_add_peer_seats_in_join_order_and_full() -> void:
	var l := LobbyState.new("HOSTY")
	assert_int(l.add_peer(10, "A")).is_equal(1)
	assert_int(l.add_peer(11, "B")).is_equal(2)
	assert_int(l.add_peer(12, "C")).is_equal(3)
	assert_int(l.add_peer(13, "D")).is_equal(-1)
	assert_int(l.seat_of(12)).is_equal(3)
	assert_int(l.peer_of(2)).is_equal(11)
	assert_int(l.seat_of(99)).is_equal(-1)
	assert_int(l.peer_of(5)).is_equal(0)


func test_add_peer_rejects_duplicate_and_host_id() -> void:
	var l := LobbyState.new("HOSTY")
	assert_int(l.add_peer(10, "A")).is_equal(1)
	assert_int(l.add_peer(10, "A")).is_equal(-1)
	assert_int(l.add_peer(1, "Z")).is_equal(-1)
	assert_int(l.add_peer(0, "Z")).is_equal(-1)


func test_remove_frees_lowest_seat() -> void:
	var l := _lobby_with(3)
	assert_int(l.remove_peer(101)).is_equal(2)
	assert_int(l.seat_of(101)).is_equal(-1)
	assert_int(l.remove_peer(101)).is_equal(-1)
	assert_int(l.remove_peer(1)).is_equal(-1)
	assert_int(l.add_peer(200, "NEW")).is_equal(2)


func test_names_deduplicated() -> void:
	var l := LobbyState.new("DIVER")
	var s1 := l.add_peer(10, "DIVER")
	var s2 := l.add_peer(11, "DIVER")
	assert_str(l.row(s1).name).is_equal("DIVER2")
	assert_str(l.row(s2).name).is_equal("DIVER3")


func test_dedup_keeps_twelve_chars() -> void:
	var l := LobbyState.new("ABCDEFGHIJKL")
	var s := l.add_peer(10, "ABCDEFGHIJKL")
	assert_str(l.row(s).name).is_equal("ABCDEFGHIJK2")


func test_empty_name_gets_default() -> void:
	var l := LobbyState.new("")
	assert_str(l.row(0).name).is_equal("DIVER")


func test_row_setters() -> void:
	var l := _lobby_with(1)
	l.set_ready(1, true)
	l.set_song_status(1, "missing")
	l.set_ping(1, 42)
	l.set_synced(1, true)
	var r: Dictionary = l.row(1)
	assert_bool(r.ready).is_true()
	assert_str(r.song_status).is_equal("missing")
	assert_int(r.ping_ms).is_equal(42)
	assert_bool(r.synced).is_true()
	l.set_song_status(1, "bogus")
	assert_str(l.row(1).song_status).is_equal("missing")
	l.set_ready(0, false)
	assert_bool(l.row(0).ready).is_true()


func test_revision_bumps_only_on_change() -> void:
	var l := _lobby_with(1)
	var r0 := l.revision
	l.set_ready(1, true)
	var r1 := l.revision
	assert_int(r1).is_greater(r0)
	l.set_ready(1, true)
	assert_int(l.revision).is_equal(r1)
	l.set_ping(1, 30)
	assert_int(l.revision).is_greater(r1)


func test_song_change_clears_ready_and_sets_checking() -> void:
	var l := _lobby_with(2)
	l.set_song(SONG_A)
	_all_good(l)
	assert_bool(l.set_song(SONG_B)).is_true()
	for seat in [1, 2]:
		assert_bool(l.row(seat).ready).is_false()
		assert_str(l.row(seat).song_status).is_equal("checking")
	assert_bool(l.row(0).ready).is_true()
	assert_str(l.song.title).is_equal("INVISIBLE")


func test_same_song_changes_nothing() -> void:
	var l := _lobby_with(1)
	l.set_song(SONG_A)
	_all_good(l)
	var rev := l.revision
	assert_bool(l.set_song(SONG_A.duplicate())).is_false()
	assert_bool(l.row(1).ready).is_true()
	assert_int(l.revision).is_equal(rev)


func test_difficulty_change_is_a_song_change() -> void:
	var l := _lobby_with(1)
	l.set_song(SONG_A)
	_all_good(l)
	var harder := SONG_A.duplicate()
	harder.diff = "hard"
	assert_bool(l.set_song(harder)).is_true()
	assert_bool(l.row(1).ready).is_false()


func test_flight_does_not_clear_ready() -> void:
	var l := _lobby_with(1)
	l.set_song(SONG_A)
	_all_good(l)
	assert_int(l.flight_beats).is_equal(2)
	assert_bool(l.set_flight(1)).is_true()
	assert_int(l.flight_beats).is_equal(1)
	assert_bool(l.row(1).ready).is_true()
	assert_bool(l.set_flight(3)).is_false()
	assert_int(l.flight_beats).is_equal(1)


func test_late_joiner_gets_checking() -> void:
	var l := LobbyState.new("HOSTY")
	l.set_song(SONG_A)
	var s := l.add_peer(10, "A")
	assert_str(l.row(s).song_status).is_equal("checking")
	assert_bool(l.row(s).ready).is_false()


func test_gate_need_players() -> void:
	var l := LobbyState.new("HOSTY")
	l.set_song(SONG_A)
	var g := l.start_gate()
	assert_bool(g.ok).is_false()
	assert_str(g.code).is_equal("need_players")


func test_gate_need_song() -> void:
	var l := _lobby_with(1)
	_all_good(l)
	assert_str(l.start_gate().code).is_equal("need_song")


func test_gate_syncing_before_song_status() -> void:
	var l := _lobby_with(2)
	l.set_song(SONG_A)
	_all_good(l)
	l.set_synced(2, false)
	l.set_song_status(1, "missing")
	var g := l.start_gate()
	assert_str(g.code).is_equal("syncing")
	assert_str(g.name).is_equal("C1")
	assert_int(g.n).is_equal(1)


func test_gate_missing_single_and_many() -> void:
	var l := _lobby_with(3)
	l.set_song(SONG_A)
	_all_good(l)
	l.set_song_status(2, "missing")
	l.set_ready(3, false)
	var g := l.start_gate()
	assert_str(g.code).is_equal("missing")
	assert_str(g.name).is_equal("C1")
	assert_int(g.n).is_equal(1)
	l.set_song_status(3, "missing")
	g = l.start_gate()
	assert_str(g.code).is_equal("missing")
	assert_str(g.name).is_equal("")
	assert_int(g.n).is_equal(2)


func test_gate_changed_when_first_bad_is_changed() -> void:
	var l := _lobby_with(2)
	l.set_song(SONG_A)
	_all_good(l)
	l.set_song_status(1, "changed")
	l.set_song_status(2, "missing")
	assert_str(l.start_gate().code).is_equal("changed")


func test_gate_checking_counts_as_not_ok() -> void:
	var l := _lobby_with(1)
	l.set_song(SONG_A)
	l.set_synced(1, true)
	assert_str(l.start_gate().code).is_equal("missing")


func test_gate_not_ready() -> void:
	var l := _lobby_with(2)
	l.set_song(SONG_A)
	_all_good(l)
	l.set_ready(1, false)
	l.set_ready(2, false)
	var g := l.start_gate()
	assert_str(g.code).is_equal("not_ready")
	assert_int(g.n).is_equal(2)
	assert_str(g.name).is_equal("")
	l.set_ready(2, true)
	g = l.start_gate()
	assert_str(g.name).is_equal("C0")


func test_gate_ok() -> void:
	var l := _lobby_with(3)
	l.set_song(SONG_A)
	_all_good(l)
	var g := l.start_gate()
	assert_bool(g.ok).is_true()
	assert_str(g.code).is_equal("ok")


func test_gate_order_walks_every_code() -> void:
	var l := LobbyState.new("HOSTY")
	var codes: Array[String] = []
	codes.append(l.start_gate().code)
	l.add_peer(10, "A")
	codes.append(l.start_gate().code)
	l.set_song(SONG_A)
	codes.append(l.start_gate().code)
	l.set_synced(1, true)
	codes.append(l.start_gate().code)
	l.set_song_status(1, "ok")
	codes.append(l.start_gate().code)
	l.set_ready(1, true)
	codes.append(l.start_gate().code)
	assert_array(codes).is_equal(["need_players", "need_song", "syncing", "missing", "not_ready", "ok"])


func test_wire_roundtrip() -> void:
	var l := _lobby_with(2)
	l.set_song(SONG_A)
	l.set_flight(1)
	l.set_ping(1, 77)
	l.set_ready(2, true)
	var c := LobbyState.new()
	assert_bool(c.apply_wire(l.to_wire())).is_true()
	assert_dict(c.to_wire()).is_equal(l.to_wire())
	assert_int(c.seat_of(101)).is_equal(2)
	assert_int(c.flight_beats).is_equal(1)
	assert_str(c.song.fp).is_equal("aaa")
	assert_int(c.revision).is_equal(l.revision)


func test_apply_wire_rejects_junk() -> void:
	var c := LobbyState.new("ME")
	assert_bool(c.apply_wire({})).is_false()
	assert_bool(c.apply_wire({"rows": "x", "rev": 1, "flight": 2, "song": {}})).is_false()
	var bad := {"rev": 1, "flight": 2, "song": {}, "rows": [{"seat": 9, "peer_id": 5, "name": "X"}]}
	assert_bool(c.apply_wire(bad)).is_false()
	assert_str(c.row(0).name).is_equal("ME")


func test_ping_bars() -> void:
	assert_int(LobbyState.ping_bars(-1)).is_equal(0)
	assert_int(LobbyState.ping_bars(0)).is_equal(4)
	assert_int(LobbyState.ping_bars(60)).is_equal(4)
	assert_int(LobbyState.ping_bars(61)).is_equal(3)
	assert_int(LobbyState.ping_bars(120)).is_equal(3)
	assert_int(LobbyState.ping_bars(200)).is_equal(2)
	assert_int(LobbyState.ping_bars(201)).is_equal(1)


func test_high_latency() -> void:
	# d 0.2 s + 60 ms RTT/2 (0.03) + 0.0167 = 0.2467 -> fine
	assert_bool(LobbyState.is_high_latency(0.2, 60)).is_false()
	# d 0.2 s + 80 ms RTT/2 (0.04) + 0.0167 = 0.2567 -> high
	assert_bool(LobbyState.is_high_latency(0.2, 80)).is_true()
