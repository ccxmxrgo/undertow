extends GdUnitTestSuite
## 03-06 Task 2: Solo Duel (spec req 11, Pitfall 9). click_chart(120, beats): note i at i * 0.5 s,
## one 4/4 bar = 2 s. Solo [20.0, 29.5] holds notes 40..59 (20 base notes).

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS
const RESOLVE := 29.5 + 0.1 + 0.001

var _ev: Array = []
var _players: Array[PlayerState] = []
var _chart: ChartData


func _sim(solos: Array, beats: int = 200, seats: int = 2) -> MatchSim:
	_chart = TestCharts.click_chart(120.0, beats, 1000)
	for s in solos:
		_chart.solos.append(s)
	_players = []
	for s in range(seats):
		_players.append(PlayerState.new(s, "P%d" % s, s == 0))
	var ch := LoopbackChannel.new()
	_ev = []
	ch.received.connect(func(e: Dictionary) -> void: _ev.append(e))
	return MatchSim.new(_chart, VersusConfig.new(), JudgeConfig.new(), _players, ch, 3)


func _solo20() -> Dictionary:
	return {"start": 20.0, "end": 29.5, "note_count": 20}


func _of(type: String) -> Array:
	return _ev.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Judge notes first..first+pattern.size()-1 on seat with the given judgments.
func _play(sim: MatchSim, seat: int, first: int, pattern: Array) -> void:
	for i in range(pattern.size()):
		var n := first + i
		sim.on_judged(seat, n, pattern[i], n * 0.5)


## `perfects` Perfects then Goods, `count` notes from note `first`.
func _pattern(count: int, perfects: int) -> Array:
	var out := []
	for i in range(count):
		out.append(P if i < perfects else G)
	return out


func test_announce_start_and_resolution_times() -> void:
	var sim := _sim([_solo20()])
	sim.update(17.99)
	assert_int(_of(GameEvent.DUEL_ANNOUNCE).size()).is_equal(0)
	sim.update(18.0)
	var a := _of(GameEvent.DUEL_ANNOUNCE)
	assert_int(a.size()).is_equal(1)
	assert_float(a[0]["t"]).is_equal_approx(18.0, 1e-9)
	assert_int(a[0]["solo"]).is_equal(0)
	assert_float(a[0]["start"]).is_equal_approx(20.0, 1e-9)
	assert_float(a[0]["end"]).is_equal_approx(29.5, 1e-9)
	assert_int(a[0]["note_count"]).is_equal(20)
	assert_int(sim.duel_active()).is_equal(-1)
	sim.update(20.0)
	var s := _of(GameEvent.DUEL_START)
	assert_int(s.size()).is_equal(1)
	assert_int(s[0]["solo"]).is_equal(0)
	assert_float(s[0]["t"]).is_equal_approx(20.0, 1e-9)
	assert_int(sim.duel_active()).is_equal(0)
	sim.update(RESOLVE - 0.0005)
	assert_int(_of(GameEvent.DUEL_RESULT).size()).is_equal(0)
	sim.update(RESOLVE)
	assert_int(_of(GameEvent.DUEL_RESULT).size()).is_equal(1)
	assert_int(sim.duel_active()).is_equal(-1)


func test_best_pct_at_or_above_85_wins_bag_item() -> void:
	var sim := _sim([_solo20()])
	_play(sim, 0, 40, _pattern(20, 18))
	_play(sim, 1, 40, _pattern(20, 17))
	sim.update(RESOLVE)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r.size()).is_equal(1)
	assert_int(r[0]["winner"]).is_equal(0)
	assert_float(r[0]["pct"]).is_equal_approx(90.0, 1e-6)
	assert_float(r[0]["best_pct"]).is_equal_approx(90.0, 1e-6)
	assert_bool(r[0]["tied"]).is_false()
	assert_float(r[0]["t"]).is_equal_approx(RESOLVE, 1e-9)
	assert_int(_players[0].duels_won).is_equal(1)
	assert_int(_players[1].duels_won).is_equal(0)
	var earned := _of(GameEvent.REWARD_EARNED).filter(
		func(e: Dictionary) -> bool: return e["source"] == "duel")
	assert_int(earned.size()).is_equal(1)
	assert_int(earned[0]["seat"]).is_equal(0)
	assert_int(_players[0].meter.held).is_equal(earned[0]["reward"])


func test_spec_90_vs_86_on_50_notes() -> void:
	var sim := _sim([{"start": 20.0, "end": 44.5, "note_count": 50}])
	_play(sim, 0, 40, _pattern(50, 45))
	_play(sim, 1, 40, _pattern(50, 43))
	sim.update(44.5 + 0.101)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r.size()).is_equal(1)
	assert_int(r[0]["winner"]).is_equal(0)
	assert_float(r[0]["pct"]).is_equal_approx(90.0, 1e-6)


func test_everyone_below_85_no_winner() -> void:
	var sim := _sim([_solo20()])
	_play(sim, 0, 40, _pattern(20, 16))
	_play(sim, 1, 40, _pattern(20, 10))
	sim.update(RESOLVE)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r[0]["winner"]).is_equal(-1)
	assert_bool(r[0]["tied"]).is_false()
	assert_float(r[0]["best_pct"]).is_equal_approx(80.0, 1e-6)
	assert_int(_players[0].duels_won).is_equal(0)


func test_equal_pct_longest_streak_wins() -> void:
	var sim := _sim([_solo20()])
	# Both 18/20. Seat 0: one run of 18. Seat 1: Goods at 5 and 15 -> best streak 9.
	_play(sim, 0, 40, _pattern(20, 18))
	var b := _pattern(20, 20)
	b[5] = G
	b[15] = G
	_play(sim, 1, 40, b)
	sim.update(RESOLVE)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r[0]["winner"]).is_equal(0)
	assert_bool(r[0]["tied"]).is_false()


func test_equal_pct_and_streak_is_tied_no_winner() -> void:
	var sim := _sim([_solo20()])
	_play(sim, 0, 40, _pattern(20, 18))
	_play(sim, 1, 40, _pattern(20, 18))
	sim.update(RESOLVE)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r[0]["winner"]).is_equal(-1)
	assert_bool(r[0]["tied"]).is_true()
	assert_int(_players[0].duels_won + _players[1].duels_won).is_equal(0)


func test_ten_note_solo_runs_no_duel() -> void:
	var sim := _sim([{"start": 20.0, "end": 24.5, "note_count": 10}])
	sim.update(60.0)
	assert_int(_of(GameEvent.DUEL_ANNOUNCE).size()).is_equal(0)
	assert_int(_of(GameEvent.DUEL_RESULT).size()).is_equal(0)


func test_note_count_is_recounted_not_trusted() -> void:
	var sim := _sim([{"start": 20.0, "end": 24.5, "note_count": 30}])
	sim.update(60.0)
	assert_int(_of(GameEvent.DUEL_ANNOUNCE).size()).is_equal(0)


func test_malformed_solos_ignored() -> void:
	var sim := _sim([
		{"start": 30.0, "end": 20.0, "note_count": 20},
		{"start": 20.0, "end": 20.0, "note_count": 20},
		{"start": 500.0, "end": 600.0, "note_count": 20},
		{"start": 40.0, "end": 49.5, "note_count": 20},
	])
	sim.update(60.0)
	var a := _of(GameEvent.DUEL_ANNOUNCE)
	assert_int(a.size()).is_equal(1)
	assert_int(a[0]["solo"]).is_equal(3)


func test_wreck_and_mid_solo_elimination_do_not_take_part() -> void:
	var sim := _sim([_solo20()], 200, 3)
	sim.on_failed(2, 5.0)
	sim.update(20.0)
	assert_float(sim.duel_live(0)).is_equal(-1.0)
	_play(sim, 0, 40, _pattern(4, 4))
	_play(sim, 1, 40, _pattern(4, 4))
	_play(sim, 2, 40, _pattern(4, 4))
	assert_float(sim.duel_live(0)).is_equal_approx(100.0, 1e-6)
	assert_float(sim.duel_live(2)).is_equal(-1.0)
	sim.on_failed(1, 22.1)
	assert_float(sim.duel_live(1)).is_equal(-1.0)
	_play(sim, 0, 44, _pattern(16, 15))
	_play(sim, 1, 44, _pattern(16, 16))
	_play(sim, 2, 44, _pattern(16, 16))
	sim.update(RESOLVE)
	var r := _of(GameEvent.DUEL_RESULT)
	assert_int(r[0]["winner"]).is_equal(0)
	assert_float(r[0]["pct"]).is_equal_approx(95.0, 1e-6)


func test_live_pct_tracks_judged_notes() -> void:
	var sim := _sim([_solo20()])
	sim.update(20.0)
	_play(sim, 0, 40, [P, P, G, P])
	assert_float(sim.duel_live(0)).is_equal_approx(75.0, 1e-6)
	assert_float(sim.duel_live(1)).is_equal(-1.0)


func test_winner_holding_reward_gets_it_queued() -> void:
	var sim := _sim([_solo20()])
	_players[0].meter.progress = _players[0].meter.target
	_players[0].meter.held = Reward.Id.INK_CLOUD
	_play(sim, 0, 40, _pattern(20, 20))
	_play(sim, 1, 40, _pattern(20, 10))
	sim.update(RESOLVE)
	var q := _of(GameEvent.REWARD_QUEUED)
	assert_int(q.size()).is_equal(1)
	assert_int(q[0]["seat"]).is_equal(0)
	var prize: int = q[0]["reward"]
	assert_int(_players[0].meter.queued).is_equal(prize)
	assert_int(_players[0].duels_won).is_equal(1)
	# Using the held reward drops the prize into the slot.
	_players[0].meter.use()
	assert_int(_players[0].meter.held).is_equal(prize)


func test_depth_charge_overlay_never_counts() -> void:
	var sim := _sim([_solo20()])
	sim.update(20.0)
	_play(sim, 0, 40, [P, P])
	for i in range(6):
		sim.on_extra_judged(0, M, 21.0 + i * 0.1)
	assert_float(sim.duel_live(0)).is_equal_approx(100.0, 1e-6)


func test_duel_events_ordered_in_log() -> void:
	var sim := _sim([_solo20()])
	_play(sim, 0, 40, _pattern(20, 20))
	sim.update(40.0)
	var types := []
	for e in sim.event_log:
		if e["type"] in [GameEvent.DUEL_ANNOUNCE, GameEvent.DUEL_START, GameEvent.DUEL_RESULT]:
			types.append(e["type"])
	assert_array(types).is_equal(
		[GameEvent.DUEL_ANNOUNCE, GameEvent.DUEL_START, GameEvent.DUEL_RESULT])
