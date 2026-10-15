extends GdUnitTestSuite
## 03-12 Task 1: MedalRules over a scripted match event_log (03-SPEC req 13).

const R := 1  # any disruptor reward id; MedalRules does not look at the reward
var _next_id: int = 100


func before_test() -> void:
	_next_id = 100


func _seats(n: int) -> Array[int]:
	var out: Array[int] = []
	for s in range(n):
		out.append(s)
	return out


func _launch(ev: Array, from: int, to: int, debris: bool = false, reflected: bool = false) -> int:
	var id := _next_id
	_next_id += 1
	ev.append(GameEvent.make(GameEvent.TORPEDO_LAUNCH, 1.0, {"id": id, "from": from, "to": to,
		"reward": R, "reflected": reflected, "debris": debris}))
	return id


func _land(ev: Array, id: int, from: int, to: int, debris: bool = false, reflected: bool = false) -> void:
	ev.append(GameEvent.make(GameEvent.LANDED, 2.0, {"id": id, "from": from, "to": to, "reward": R,
		"reflected": reflected, "debris": debris}))


func _shot(ev: Array, from: int, to: int) -> int:
	var id := _launch(ev, from, to)
	_land(ev, id, from, to)
	return id


func _reflect(ev: Array, id: int, by: int, to: int) -> void:
	ev.append(GameEvent.make(GameEvent.REFLECTED, 3.0, {"id": id, "by": by, "to": to, "reward": R}))


func _collide(ev: Array, a: int, b: int) -> void:
	var ia := _next_id
	var ib := _next_id + 1
	_next_id += 2
	ev.append(GameEvent.make(GameEvent.COLLISION, 1.0, {"a": a, "b": b, "ids": [ia, ib],
		"reward_a": R, "reward_b": R}))


func _m(ev: Array, n: int = 2, drones: Array[int] = []) -> Dictionary:
	return MedalRules.medals(ev, _seats(n), drones)


# ---- Untouchable --------------------------------------------------------------------------

func test_untouchable_two_launches_none_landed() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	_launch(ev, 1, 0)
	assert_array(_m(ev)[0]).contains(["untouchable"])


func test_untouchable_when_both_landed_were_reflected() -> void:
	var ev: Array = []
	var a := _shot(ev, 1, 0)
	var b := _shot(ev, 1, 0)
	_reflect(ev, a, 0, 1)
	_reflect(ev, b, 0, 1)
	assert_array(_m(ev)[0]).contains(["untouchable"])


func test_untouchable_needs_two() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	assert_array(_m(ev)[0]).not_contains(["untouchable"])


func test_untouchable_lost_when_one_landed() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	_shot(ev, 1, 0)
	assert_array(_m(ev)[0]).not_contains(["untouchable"])


func test_untouchable_collision_counts_one_each_side() -> void:
	var ev: Array = []
	_collide(ev, 0, 1)
	_launch(ev, 1, 0)
	var m := _m(ev)
	assert_array(m[0]).contains(["untouchable"])
	assert_array(m[1]).not_contains(["untouchable"])  # only 1 fired at seat 1


func test_untouchable_collision_with_flight_not_double_counted() -> void:
	var ev: Array = []
	var id := _launch(ev, 1, 0)  # in the air, then hit by seat 0's pending launch
	ev.append(GameEvent.make(GameEvent.COLLISION, 1.5, {"a": 0, "b": 1, "ids": [999, id],
		"reward_a": R, "reward_b": R}))
	assert_array(_m(ev)[0]).not_contains(["untouchable"])  # 1 disruptor at seat 0, not 2


func test_untouchable_debris_never_counts() -> void:
	var ev: Array = []
	_launch(ev, 1, 0, true)
	_launch(ev, 1, 0, true)
	assert_array(_m(ev)[0]).not_contains(["untouchable"])
	var ev2: Array = []
	_launch(ev2, 1, 0)
	_launch(ev2, 1, 0)
	var d := _launch(ev2, 1, 0, true)
	_land(ev2, d, 1, 0, true)
	assert_array(_m(ev2)[0]).contains(["untouchable"])


# ---- Uno Reverse / Bounty Hunter ----------------------------------------------------------

func test_uno_reverse_ties_go_to_all() -> void:
	var ev: Array = []
	for pair in [[0, 2], [0, 2], [1, 2], [1, 2], [2, 0]]:
		_reflect(ev, _next_id, pair[0], pair[1])
		_next_id += 1
	var m := _m(ev, 3)
	assert_array(m[0]).contains(["uno_reverse"])
	assert_array(m[1]).contains(["uno_reverse"])
	assert_array(m[2]).not_contains(["uno_reverse"])


func test_uno_reverse_nobody_at_zero() -> void:
	var m := _m([], 3)
	for s in range(3):
		assert_array(m[s]).not_contains(["uno_reverse"])


func test_bounty_hunter_most_claims_with_ties() -> void:
	var ev: Array = []
	for f in [0, 2, 2, 1, 1]:
		ev.append(GameEvent.make(GameEvent.BOUNTY_CLAIMED, 1.0, {"from": f, "to": 3, "refund": 1}))
	var m := _m(ev, 4)
	assert_array(m[0]).not_contains(["bounty_hunter"])
	assert_array(m[1]).contains(["bounty_hunter"])
	assert_array(m[2]).contains(["bounty_hunter"])
	assert_array(m[3]).not_contains(["bounty_hunter"])


# ---- Shredder / Head-On -------------------------------------------------------------------

func test_shredder_duel_winner() -> void:
	var ev: Array = [GameEvent.make(GameEvent.DUEL_RESULT, 9.0, {"solo": 0, "winner": 1, "pct": 0.9,
		"best_pct": 0.9, "tied": false})]
	ev.append(GameEvent.make(GameEvent.DUEL_RESULT, 19.0, {"solo": 1, "winner": -1}))
	var m := _m(ev, 3)
	assert_array(m[1]).is_equal(["shredder"])
	assert_array(m[0]).is_empty()


func test_head_on_both_sides() -> void:
	var ev: Array = []
	_collide(ev, 1, 2)
	var m := _m(ev, 3)
	assert_array(m[1]).contains(["head_on"])
	assert_array(m[2]).contains(["head_on"])
	assert_array(m[0]).not_contains(["head_on"])


# ---- Grudge -------------------------------------------------------------------------------

func test_grudge_three_on_same_rival() -> void:
	var ev: Array = []
	for i in 3:
		_shot(ev, 0, 1)
	assert_array(_m(ev, 3)[0]).contains(["grudge"])


func test_grudge_spread_over_rivals_is_not_grudge() -> void:
	var ev: Array = []
	_shot(ev, 0, 1)
	_shot(ev, 0, 1)
	_shot(ev, 0, 2)
	assert_array(_m(ev, 3)[0]).not_contains(["grudge"])


func test_grudge_excludes_reflected_landings() -> void:
	var ev: Array = []
	_shot(ev, 0, 1)
	_shot(ev, 0, 1)
	var c := _shot(ev, 0, 1)
	_reflect(ev, c, 1, 0)
	assert_array(_m(ev, 3)[0]).not_contains(["grudge"])


func test_grudge_ignores_debris_and_reflected_relaunch() -> void:
	var ev: Array = []
	_shot(ev, 0, 1)
	_shot(ev, 0, 1)
	var d := _launch(ev, 0, 1, true)
	_land(ev, d, 0, 1, true)
	var r := _launch(ev, 0, 1, false, true)
	_land(ev, r, 0, 1, false, true)
	assert_array(_m(ev, 3)[0]).not_contains(["grudge"])


# ---- Dogpiled -----------------------------------------------------------------------------

func test_dogpiled_every_rival_in_four_player_match() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	_launch(ev, 2, 0)
	_collide(ev, 0, 3)
	var m := _m(ev, 4)
	assert_array(m[0]).contains(["dogpiled"])
	assert_array(m[1]).not_contains(["dogpiled"])


func test_dogpiled_needs_every_rival() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	_launch(ev, 2, 0)
	assert_array(_m(ev, 4)[0]).not_contains(["dogpiled"])


func test_dogpiled_never_in_two_player_match() -> void:
	var ev: Array = []
	_launch(ev, 1, 0)
	assert_array(_m(ev, 2)[0]).not_contains(["dogpiled"])


func test_drones_never_earn_or_count_as_rivals() -> void:
	var ev: Array = []
	for i in 3:
		_shot(ev, 0, 1)  # seat 1 is a drone: no Grudge
	_launch(ev, 1, 0)
	_launch(ev, 1, 0)
	_launch(ev, 0, 1)
	_launch(ev, 0, 1)
	var drones: Array[int] = [1]
	var m := MedalRules.medals(ev, _seats(2), drones)
	assert_array(m[1]).is_empty()
	assert_array(m[0]).not_contains(["grudge"])


# ---- cap, order, empty, malformed ---------------------------------------------------------

func test_more_than_three_shows_first_three_in_order() -> void:
	var ev: Array = []
	# Seat 0: untouchable (2 launches, none landed), uno reverse, bounty hunter, shredder, head-on.
	_launch(ev, 1, 0)
	_launch(ev, 2, 0)
	_reflect(ev, 777, 0, 1)
	ev.append(GameEvent.make(GameEvent.BOUNTY_CLAIMED, 1.0, {"from": 0, "to": 1, "refund": 1}))
	ev.append(GameEvent.make(GameEvent.DUEL_RESULT, 9.0, {"winner": 0}))
	ev.append(GameEvent.make(GameEvent.COLLISION, 1.0, {"a": 0, "b": 2, "ids": [200, 201]}))
	var m := _m(ev, 3)
	assert_array(m[0]).is_equal(["untouchable", "uno_reverse", "bounty_hunter"])


func test_empty_log_gives_no_medals() -> void:
	var m := _m([], 4)
	for s in range(4):
		assert_array(m[s]).is_empty()


func test_malformed_and_unknown_seat_events_are_ignored() -> void:
	var ev: Array = [
		{"type": GameEvent.REFLECTED},
		{"type": GameEvent.BOUNTY_CLAIMED, "from": 9},
		{"type": GameEvent.COLLISION, "a": 7},
		"not an event",
		{},
	]
	var m := _m(ev, 2)
	assert_array(m[0]).is_empty()
	assert_array(m[1]).is_empty()


func test_display_tables_cover_every_key() -> void:
	assert_array(MedalRules.ORDER).is_equal(["untouchable", "uno_reverse", "bounty_hunter", "shredder",
		"head_on", "grudge", "dogpiled"])
	for k in MedalRules.ORDER:
		assert_bool(MedalRules.NAMES.has(k)).is_true()
		assert_bool(UiIcons.names().has(MedalRules.GLYPHS[k])).is_true()
		assert_bool(MedalRules.LEGEND.has(k)).is_true()
	assert_str(MedalRules.legend_line("shredder")).is_equal("SHREDDER: won a Solo Duel.")
	assert_str(MedalRules.legend_line("untouchable")).is_equal(
		"UNTOUCHABLE: 2 or more disruptors were fired at you and none took effect.")
