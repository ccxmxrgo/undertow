extends GdUnitTestSuite
## 03-10: Killfeed (03-UI-SPEC 6.6, 13, 14; 03-SPEC req 12, D-32).

const NAMES := ["YOU", "MAKO", "ORCA", "BARRACUDA"]
const INK := Reward.Id.INK_CLOUD

var _saved_low := false
var _saved_rm := false
var _texts: Array[String] = []


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false
	_texts.clear()


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm


func _feed(names := PackedStringArray(NAMES)) -> Array:
	var k: Killfeed = auto_free(Killfeed.new())
	add_child(k)
	var ch := LoopbackChannel.new()
	k.bind(ch, 0, names, VersusConfig.new())
	return [k, ch]


func _send(ch: EventChannel, type: String, fields: Dictionary, t := 1.0) -> void:
	ch.send(GameEvent.make(type, t, fields))


## Last pushed line (newest, top), recording its text segments for the has_char test.
func _top(k: Killfeed) -> Dictionary:
	var l: Dictionary = k.lines()[0]
	for s: Dictionary in l["segments"]:
		if s["kind"] == "text":
			_texts.append(String(s["text"]))
	return l


func _seg_shape(l: Dictionary) -> Array:
	var out := []
	for s: Dictionary in l["segments"]:
		out.append(["glyph", s["glyph"]] if s["kind"] == "glyph" else ["text", s["text"]])
	return out


func test_rect_and_slots() -> void:
	var k: Killfeed = _feed()[0]
	assert_that(Rect2(k.position, k.size)).is_equal(Rect2(1544, 216, 352, 184))
	assert_that(Killfeed.RECT).is_equal(Rect2(1544.0, 216.0, 352.0, 184.0))
	assert_int(k.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_landed_between_rivals() -> void:
	var r := _feed()
	_send(r[1], GameEvent.LANDED, {"id": 1, "from": 1, "to": 2, "reward": INK, "debris": false})
	var k: Killfeed = r[0]
	assert_int(k.lines().size()).is_equal(1)
	var l := _top(k)
	assert_array(_seg_shape(l)).is_equal([["text", "MAKO"], ["glyph", "arrow_right"], ["text", "Ink Cloud"],
		["glyph", "arrow_right"], ["text", "ORCA"]])
	assert_bool(l["own"]).is_false()
	assert_bool(l["victim"]).is_false()
	for s: Dictionary in l["segments"]:
		assert_that(s["color"]).is_equal(Palette.TEXT_MID)


func test_landed_on_you_and_by_you() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.LANDED, {"id": 1, "from": 1, "to": 0, "reward": INK})
	var v := _top(k)
	assert_bool(v["victim"]).is_true()
	assert_bool(v["own"]).is_false()
	assert_that(v["segments"][0]["color"]).is_equal(Palette.TEXT_HI)
	assert_str(v["text"]).is_equal("MAKO [arrow_right] Ink Cloud [arrow_right] YOU")
	_send(r[1], GameEvent.LANDED, {"id": 2, "from": 0, "to": 1, "reward": INK})
	var o := _top(k)
	assert_bool(o["own"]).is_true()
	assert_bool(o["victim"]).is_false()


func test_event_formats() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.REFLECTED, {"id": 1, "by": 2, "to": 1, "reward": INK})
	assert_str(_top(k)["text"]).is_equal("ORCA [reflect] REFLECTED Ink Cloud")
	_send(r[1], GameEvent.ABSORBED, {"id": 2, "from": 1, "to": 3, "reward": INK})
	assert_str(_top(k)["text"]).is_equal("BARRACUDA [shield] blocked")
	_send(r[1], GameEvent.COLLISION, {"a": 0, "b": 1, "ids": [3, 4], "reward_a": INK, "reward_b": INK})
	var col := _top(k)
	assert_str(col["text"]).is_equal("YOU [cross] MAKO collided")
	assert_bool(col["own"]).is_true()
	_send(r[1], GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 3})
	var b := _top(k)
	assert_str(b["text"]).is_equal("[bounty] MAKO claimed the bounty on ORCA")
	assert_that(b["segments"][0]["color"]).is_equal(Palette.REWARD_GOLD)
	assert_that(b["segments"][1]["color"]).is_equal(Palette.TEXT_MID)


func test_duel_implosion_and_debris() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.DUEL_RESULT, {"solo": 0, "winner": 2, "pct": 91, "best_pct": 91, "tied": false})
	assert_str(_top(k)["text"]).is_equal("ORCA wins the solo")
	var n := k.lines().size()
	_send(r[1], GameEvent.DUEL_RESULT, {"solo": 1, "winner": -1, "pct": 0, "best_pct": 40, "tied": false})
	assert_int(k.lines().size()).is_equal(n)
	_send(r[1], GameEvent.IMPLODED, {"seat": 3})
	assert_str(_top(k)["text"]).is_equal("[skull] BARRACUDA imploded")
	_send(r[1], GameEvent.LANDED, {"id": 9, "from": 3, "to": 1, "reward": Reward.Id.SILT, "debris": true})
	var d := _top(k)
	assert_str(d["text"]).is_equal("[skull] BARRACUDA [arrow_right] Silt [arrow_right] MAKO")
	assert_that(d["segments"][1]["color"]).is_equal(Palette.TEXT_LO)
	assert_that(d["segments"][5]["color"]).is_equal(Palette.TEXT_MID)


func test_you_imploded_is_victim_line() -> void:
	var r := _feed()
	_send(r[1], GameEvent.IMPLODED, {"seat": 0})
	var l := _top(r[0])
	assert_bool(l["victim"]).is_true()


func test_training_line() -> void:
	var r := _feed(PackedStringArray(["YOU", "DRONE"]))
	_send(r[1], GameEvent.LANDED, {"id": 1, "from": 0, "to": 1, "reward": INK})
	assert_str(_top(r[0])["text"]).is_equal("YOU [arrow_right] Ink Cloud [arrow_right] DRONE")


func test_unknown_seat_renders_question_mark() -> void:
	var r := _feed()
	_send(r[1], GameEvent.IMPLODED, {"seat": 9})
	assert_str(_top(r[0])["text"]).is_equal("[skull] ? imploded")


func test_silent_events() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.BUFF_APPLIED, {"seat": 1, "reward": Reward.Id.BALLAST_PATCH, "until_t": 1.0, "amount": 25})
	_send(r[1], GameEvent.LAST_STANDING, {"seat": 1})
	_send(r[1], GameEvent.METER, {"seat": 1, "progress": 3, "threshold": 9, "held": -1})
	_send(r[1], GameEvent.TARGET, {"seat": 0, "mode": 0, "target": 1})
	_send(r[1], GameEvent.STATUS, {"seat": 1, "hull": 50, "depth": 10, "alive": true, "place": 1})
	assert_int(k.lines().size()).is_equal(0)


func test_cap_newest_on_top_and_slots() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	for s in [1, 2, 3, 0, 1]:
		_send(r[1], GameEvent.IMPLODED, {"seat": s})
		k.step(0.01)
	k.step(0.5)
	var ls := k.lines()
	assert_int(ls.size()).is_equal(4)
	assert_str(ls[0]["text"]).is_equal("[skull] MAKO imploded")  # newest
	assert_str(ls[3]["text"]).is_equal("[skull] ORCA imploded")  # oldest MAKO line dropped
	for i in 4:
		assert_float(ls[i]["y"]).is_equal([216.0, 264.0, 312.0, 360.0][i])


func test_shift_glides_then_jumps_under_reduce() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.IMPLODED, {"seat": 1})
	k.step(0.5)
	_send(r[1], GameEvent.IMPLODED, {"seat": 2})
	k.step(0.06)
	var y := float(k.lines()[1]["y"])
	assert_float(y).is_greater(216.0)
	assert_float(y).is_less(264.0)
	assert_float(k.lines()[0]["x_offset"]).is_greater(0.0)
	Settings.reduce_motion = true
	k.apply_effect_settings()
	_send(r[1], GameEvent.IMPLODED, {"seat": 3})
	assert_float(k.lines()[1]["y"]).is_equal(264.0)
	assert_float(k.lines()[0]["x_offset"]).is_equal(0.0)
	assert_bool(k.effect_counts()["slide"]).is_false()


func test_life_and_fade() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.IMPLODED, {"seat": 1})
	k.step(1.0)
	_send(r[1], GameEvent.IMPLODED, {"seat": 2})
	k.step(2.5)  # first line at 3.5 s
	assert_float(k.lines()[1]["alpha"]).is_equal(1.0)
	k.step(0.3)  # 3.8 s
	assert_float(k.lines()[1]["alpha"]).is_equal_approx(0.5, 0.01)
	k.step(0.25)  # 4.05 s -> removed
	assert_int(k.lines().size()).is_equal(1)
	assert_str(k.lines()[0]["text"]).is_equal("[skull] ORCA imploded")
	assert_float(k.lines()[0]["y"]).is_equal(216.0)


func test_closing_slot_moves_lines_up() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.IMPLODED, {"seat": 1})
	k.step(2.0)
	_send(r[1], GameEvent.IMPLODED, {"seat": 2})
	k.step(1.0)
	_send(r[1], GameEvent.IMPLODED, {"seat": 3})
	k.step(1.05)  # oldest (seat 1) expires at 4.0
	var ls := k.lines()
	assert_int(ls.size()).is_equal(2)
	assert_float(ls[1]["y"]).is_equal(264.0)


func test_overlong_collapses_payload_then_truncates() -> void:
	var r := _feed(PackedStringArray(["YOU", "BARRACUDA", "LEVIATHANS"]))
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.LANDED, {"id": 1, "from": 1, "to": 2, "reward": Reward.Id.PRESSURE_CRACK})
	var l := _top(k)
	assert_str(l["text"]).is_equal("BARRACUDA [arrow_right] [pressure_crack] [arrow_right] LEVIATHANS")
	assert_float(Killfeed.content_width(l["segments"])).is_less_equal(Killfeed.TEXT_MAX)
	_send(r[1], GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 2})
	var b := _top(k)
	assert_str(b["text"]).starts_with("[bounty] BARRAC... claimed")
	assert_str(b["text"]).ends_with(" LEVIAT...")
	assert_float(b["squeeze"]).is_greater_equal(Killfeed.MIN_SQUEEZE - 0.001)
	assert_float(Killfeed.content_width(b["segments"]) * b["squeeze"]).is_less_equal(Killfeed.TEXT_MAX + 0.01)
	# The spec's bounty line with short names keeps every word, condensed slightly.
	var r2 := _feed()
	_send(r2[1], GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 2})
	var m := _top(r2[0])
	assert_str(m["text"]).is_equal("[bounty] MAKO claimed the bounty on ORCA")
	assert_float(m["squeeze"]).is_less(1.0)
	assert_float(m["squeeze"]).is_greater_equal(Killfeed.MIN_SQUEEZE)
	assert_float(Killfeed.content_width(m["segments"]) * m["squeeze"]).is_less_equal(Killfeed.TEXT_MAX + 0.01)
	# A short line keeps its payload name.
	_send(r[1], GameEvent.REFLECTED, {"id": 2, "by": 0, "to": 1, "reward": INK})
	assert_str(_top(k)["text"]).is_equal("YOU [reflect] REFLECTED Ink Cloud")


func test_every_character_in_label_font() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	var evs := [
		[GameEvent.LANDED, {"from": 1, "to": 2, "reward": INK}],
		[GameEvent.REFLECTED, {"by": 2, "to": 1, "reward": Reward.Id.CROSSED_WIRES}],
		[GameEvent.ABSORBED, {"from": 1, "to": 3, "reward": INK}],
		[GameEvent.COLLISION, {"a": 0, "b": 1}],
		[GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 1}],
		[GameEvent.DUEL_RESULT, {"winner": 3}],
		[GameEvent.IMPLODED, {"seat": 2}],
		[GameEvent.LANDED, {"from": 3, "to": 0, "reward": Reward.Id.GROAN, "debris": true}],
	]
	for id in Reward.ALL:
		evs.append([GameEvent.LANDED, {"from": 2, "to": 3, "reward": id}])
	for ev in evs:
		_send(r[1], ev[0], ev[1])
		_top(k)
	_texts.append("...")
	var f := Palette.font()
	for t in _texts:
		for i in t.length():
			assert_bool(f.has_char(t.unicode_at(i))).override_failure_message(
				"'%s' in '%s' missing from the Label font" % [t[i], t]).is_true()


func test_draw_does_not_error() -> void:
	var r := _feed()
	var k: Killfeed = r[0]
	_send(r[1], GameEvent.LANDED, {"from": 0, "to": 1, "reward": INK})
	_send(r[1], GameEvent.LANDED, {"from": 1, "to": 0, "reward": INK})
	_send(r[1], GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 1})
	await await_idle_frame()
	assert_int(k.lines().size()).is_equal(3)
