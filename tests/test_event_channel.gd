extends GdUnitTestSuite
## 03-03 Task 1: GameEvent records, the EventChannel seam (spec req 12) and PlayerState defaults.

var _got: Array = []


func _capture(ch: EventChannel) -> void:
	_got = []
	ch.received.connect(func(e: Dictionary) -> void: _got.append(e))


func test_make_builds_typed_record() -> void:
	var e := GameEvent.make(GameEvent.LANDED, 12.5, {"from": 1, "to": 0})
	assert_dict(e).is_equal({"type": "landed", "t": 12.5, "from": 1, "to": 0})


func test_make_without_fields() -> void:
	var e := GameEvent.make(GameEvent.LAST_STANDING, 3.0)
	assert_str(e["type"]).is_equal(GameEvent.LAST_STANDING)
	assert_float(e["t"]).is_equal(3.0)
	assert_int(e.size()).is_equal(2)


func test_every_type_is_unique() -> void:
	var seen := {}
	for ty in GameEvent.ALL_TYPES:
		assert_bool(seen.has(ty)).is_false()
		seen[ty] = true
	assert_bool(seen.has(GameEvent.TORPEDO_LAUNCH)).is_true()
	assert_bool(seen.has(GameEvent.MATCH_END)).is_true()
	assert_int(GameEvent.ALL_TYPES.size()).is_equal(25)


func test_base_channel_emits_synchronously() -> void:
	var ch := EventChannel.new()
	_capture(ch)
	ch.send(GameEvent.make(GameEvent.IMPLODED, 1.0, {"seat": 2}))
	assert_int(_got.size()).is_equal(1)


func test_loopback_emits_once_synchronously() -> void:
	var ch := LoopbackChannel.new()
	_capture(ch)
	var e := GameEvent.make(GameEvent.IMPLODED, 1.0, {"seat": 2})
	ch.send(e)
	assert_int(_got.size()).is_equal(1)
	assert_dict(_got[0]).is_equal(e)
	ch.update(100.0)
	assert_int(_got.size()).is_equal(1)


func test_loopback_latency_holds_until_due_then_fifo() -> void:
	var ch := LoopbackChannel.new()
	ch.latency_s = 0.2
	_capture(ch)
	ch.send(GameEvent.make(GameEvent.LANDED, 1.0, {"id": 1}))
	ch.send(GameEvent.make(GameEvent.LANDED, 1.0, {"id": 2}))
	ch.send(GameEvent.make(GameEvent.LANDED, 1.5, {"id": 3}))
	assert_int(_got.size()).is_equal(0)
	ch.update(1.19)
	assert_int(_got.size()).is_equal(0)
	ch.update(1.2)
	assert_int(_got.size()).is_equal(2)
	assert_int(_got[0]["id"]).is_equal(1)
	assert_int(_got[1]["id"]).is_equal(2)
	ch.update(1.69)
	assert_int(_got.size()).is_equal(2)
	ch.update(1.7)
	assert_int(_got.size()).is_equal(3)
	assert_int(_got[2]["id"]).is_equal(3)
	assert_int(ch.pending_count()).is_equal(0)


func test_player_state_defaults() -> void:
	var p := PlayerState.new(2, "ORCA")
	assert_int(p.seat).is_equal(2)
	assert_str(p.callsign).is_equal("ORCA")
	assert_bool(p.alive).is_true()
	assert_float(p.eliminated_at).is_equal(INF)
	assert_int(p.target_mode).is_equal(PlayerState.TargetMode.AUTO)
	assert_float(p.immune_until).is_equal(-INF)
	assert_float(p.decoy_until).is_equal(-INF)
	assert_float(p.overclock_until).is_equal(-INF)
	assert_int(p.incoming_id).is_equal(-1)
	assert_bool(p.active.is_empty()).is_true()
	assert_int(p.locked_target).is_equal(-1)
	assert_int(p.last_attacker).is_equal(-1)
	assert_bool(p.is_drone).is_false()
	assert_float(p.hull).is_equal(100.0)


func test_player_state_flags_from_ctor() -> void:
	var p := PlayerState.new(1, "DRONE", false, true)
	assert_bool(p.is_drone).is_true()
	assert_bool(p.is_human).is_false()
	var h := PlayerState.new(0, "YOU", true)
	assert_bool(h.is_human).is_true()


func test_is_shielded() -> void:
	var p := PlayerState.new(0, "YOU")
	assert_bool(p.is_shielded(5.0)).is_false()
	p.incoming_id = 3
	assert_bool(p.is_shielded(5.0)).is_true()
	p.incoming_id = -1
	p.active = {"id": 3}
	assert_bool(p.is_shielded(5.0)).is_true()
	p.active = {}
	p.immune_until = 6.0
	assert_bool(p.is_shielded(5.99)).is_true()
	assert_bool(p.is_shielded(6.0)).is_false()


func test_hull_zero_does_not_kill() -> void:
	# Pitfall 5: life is alive / eliminated_at, never hull > 0.
	var p := PlayerState.new(0, "YOU")
	p.hull = 0.0
	assert_bool(p.alive).is_true()
