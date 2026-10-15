extends GdUnitTestSuite
## 03-10: PeriscopePanel and PeriscopeColumn (03-UI-SPEC 6.2, 8.3, 12; MATCH-04, TORP-03, TORP-04).

const NAMES := ["YOU", "MAKO", "ORCA", "BARRACUDA"]

var _saved_low := false
var _saved_rm := false
var _pct := {}


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false
	_pct = {}


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm


func _live(seat: int) -> int:
	return int(_pct.get(seat, -1))


func _column(rivals: Array[int], training := false, names := PackedStringArray(NAMES)) -> Array:
	var col: PeriscopeColumn = auto_free(PeriscopeColumn.new())
	add_child(col)
	var ch := LoopbackChannel.new()
	var cfg := VersusConfig.new()
	col.bind(ch, 0, rivals, names, null, cfg, _live, training)
	col.step(1.0)  # finish the entrance
	return [col, ch]


func _send(ch: EventChannel, type: String, t: float, fields: Dictionary) -> void:
	ch.send(GameEvent.make(type, t, fields))


func _rect(p: Control) -> Rect2:
	return Rect2(p.position, p.size)


# ---- Layout -------------------------------------------------------------------------------

func test_three_rivals_exact_rects() -> void:
	var col: PeriscopeColumn = _column([1, 2, 3])[0]
	var ps := col.panels()
	assert_int(ps.size()).is_equal(3)
	assert_that(_rect(ps[0])).is_equal(Rect2(24, 216, 352, 88))
	assert_that(_rect(ps[1])).is_equal(Rect2(24, 312, 352, 88))
	assert_that(_rect(ps[2])).is_equal(Rect2(24, 408, 352, 88))
	assert_that(PeriscopeColumn.PANEL_RECTS[2].end.y).is_equal(496.0)
	assert_str(ps[0].callsign).is_equal("MAKO")
	assert_str(ps[2].callsign).is_equal("BARRACUDA")


func test_one_rival_only_p1() -> void:
	var col: PeriscopeColumn = _column([2])[0]
	assert_int(col.panels().size()).is_equal(1)
	assert_that(_rect(col.panels()[0])).is_equal(Rect2(24, 216, 352, 88))
	assert_int(col.panels()[0].seat).is_equal(2)


func test_training_drone_uses_p1() -> void:
	var col: PeriscopeColumn = _column([1], true, PackedStringArray(["YOU", "DRONE"]))[0]
	var p := col.panels()[0]
	assert_bool(p.drone).is_true()
	assert_str(p.callsign).is_equal("DRONE")
	assert_that(_rect(p)).is_equal(Rect2(24, 216, 352, 88))
	col.set_drone_status("NEXT IN 3 BARS")
	assert_str(p.status_text()).is_equal("NEXT IN 3 BARS")


func test_entrance_slides_then_settles() -> void:
	var col: PeriscopeColumn = auto_free(PeriscopeColumn.new())
	add_child(col)
	col.bind(LoopbackChannel.new(), 0, [1, 2] as Array[int], PackedStringArray(NAMES), null, VersusConfig.new(),
		_live, false)
	col.step(0.05)
	var p0 := col.panels()[0]
	assert_float(p0.position.x).is_less(24.0)
	assert_float(p0.modulate.a).is_less(1.0)
	assert_float(col.panels()[1].modulate.a).is_equal(0.0)  # 60 ms stagger
	col.step(1.0)
	assert_float(p0.position.x).is_equal(24.0)
	assert_float(p0.modulate.a).is_equal(1.0)


func test_entrance_fade_only_under_reduce() -> void:
	Settings.reduce_motion = true
	var col: PeriscopeColumn = auto_free(PeriscopeColumn.new())
	add_child(col)
	col.bind(LoopbackChannel.new(), 0, [1] as Array[int], PackedStringArray(NAMES), null, VersusConfig.new(),
		_live, false)
	col.step(0.05)
	assert_float(col.panels()[0].position.x).is_equal(24.0)
	assert_float(col.panels()[0].modulate.a).is_less(1.0)


func test_names_clamped_and_unknown_seat() -> void:
	var col: PeriscopeColumn = _column([1, 5], false, PackedStringArray(["YOU", "mako"]))[0]
	assert_str(col.panel_for(1).callsign).is_equal("MAKO")
	assert_str(col.panel_for(5).callsign).is_equal("?")
	var p := PeriscopePanel.new()
	p.setup(1, "averyveryverylongcallsignindeed")
	assert_int(p.callsign.length()).is_less_equal(PeriscopePanel.MAX_NAME_CHARS)
	var w := PeriscopePanel.spaced_font().get_string_size(p.shown_callsign(), HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_LABEL).x
	assert_float(w).is_less_equal(p.call_max())
	p.free()


# ---- Status, hull, wreck ------------------------------------------------------------------

func test_status_hull_depth_place() -> void:
	var r := _column([1, 2, 3])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.STATUS, 1.0, {"seat": 2, "hull": 45.0, "depth": 1240, "alive": true, "place": 1})
	var p := col.panel_for(2)
	assert_float(p.lit_segments()).is_equal_approx(4.5, 0.001)
	assert_that(p.hull_color()).is_equal(Palette.TEXT_HI)
	assert_str(p.status_text()).is_equal("1,240 M")
	assert_str(p.place_text()).is_equal("1ST")
	assert_that(p.place_color()).is_equal(Palette.REWARD_GOLD)
	_send(r[1], GameEvent.STATUS, 2.0, {"seat": 2, "hull": 80.0, "depth": 10, "alive": true, "place": 3})
	assert_that(p.hull_color()).is_equal(Palette.SONAR)
	assert_str(p.place_text()).is_equal("3RD")
	assert_that(p.place_color()).is_equal(Palette.TEXT_MID)
	_send(r[1], GameEvent.STATUS, 3.0, {"seat": 2, "hull": 30.0, "depth": 10, "alive": true, "place": 3})
	assert_that(p.hull_color()).is_equal(Palette.WARNING_RED)
	# Other panels untouched.
	assert_float(col.panel_for(1).lit_segments()).is_equal(10.0)


func test_drone_status_place_zero() -> void:
	var r := _column([1], true, PackedStringArray(["YOU", "DRONE"]))
	_send(r[1], GameEvent.STATUS, 0.0, {"seat": 1, "hull": 100.0, "depth": 0, "alive": true, "place": 0})
	var p: PeriscopePanel = r[0].panel_for(1)
	assert_str(p.place_text()).is_equal("")


func test_wreck_and_sitting_out() -> void:
	var r := _column([1, 2])
	var p: PeriscopePanel = r[0].panel_for(2)
	_send(r[1], GameEvent.IMPLODED, 5.0, {"seat": 2})
	assert_bool(p.is_wreck()).is_true()
	assert_that(p.edge_color()).is_equal(Palette.alpha(Palette.TEXT_LO, 0.35))
	assert_that(p.bracket_color()).is_equal(Palette.alpha(Palette.TEXT_LO, 0.5))
	_send(r[1], GameEvent.DUEL_START, 6.0, {"solo": 0})
	assert_str(p.status_text()).is_equal("SITTING OUT")
	assert_that(p.status_color()).is_equal(Palette.TEXT_LO)


# ---- Threat block -------------------------------------------------------------------------

func test_threat_incoming_active_immune() -> void:
	var r := _column([1, 2])
	var col: PeriscopeColumn = r[0]
	var p := col.panel_for(2)
	assert_str(p.threat_state()).is_equal("none")
	_send(r[1], GameEvent.TORPEDO_LAUNCH, 1.0, {"id": 7, "from": 1, "to": 2, "reward": Reward.Id.INK_CLOUD,
		"launch_t": 1.0, "arrive_t": 1.5, "reflected": false, "debris": false})
	assert_str(p.threat_state()).is_equal("incoming")
	assert_str(p.threat_glyph()).is_equal("ink_cloud")
	assert_bool(p.edge_flashing()).is_true()
	col.update(1.25)
	assert_float(p.threat_fraction()).is_equal_approx(0.5, 0.001)
	col.step(0.31)
	assert_bool(p.edge_flashing()).is_false()
	_send(r[1], GameEvent.LANDED, 1.5, {"id": 7, "from": 1, "to": 2, "reward": Reward.Id.INK_CLOUD,
		"arrive_t": 1.5, "active_start": 1.5, "end_t": 9.5, "reflected": false, "debris": false})
	assert_str(p.threat_state()).is_equal("active")
	col.update(5.5)
	assert_float(p.threat_fraction()).is_equal_approx(0.5, 0.001)
	_send(r[1], GameEvent.PAYLOAD_END, 9.5, {"id": 7, "seat": 2, "reward": Reward.Id.INK_CLOUD,
		"reason": "expired", "immune_until": 11.5})
	assert_str(p.threat_state()).is_equal("immune")
	assert_str(p.threat_glyph()).is_equal("shield")
	col.update(10.5)
	assert_float(p.threat_fraction()).is_equal_approx(0.5, 0.001)
	col.update(11.6)
	assert_str(p.threat_state()).is_equal("none")


func test_collision_burst_and_glyph() -> void:
	var r := _column([1, 2])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.TORPEDO_LAUNCH, 1.0, {"id": 1, "from": 1, "to": 2, "reward": 0, "launch_t": 1.0,
		"arrive_t": 1.5})
	_send(r[1], GameEvent.COLLISION, 1.0, {"a": 1, "b": 2, "ids": [1, 2], "reward_a": 0, "reward_b": 2})
	for s in [1, 2]:
		var p := col.panel_for(s)
		assert_str(p.threat_state()).is_equal("collision")
		assert_str(p.threat_glyph()).is_equal("cross")
	var p2 := col.panel_for(2)
	col.step(0.15)
	assert_float(p2.burst_radius()).is_greater(PeriscopePanel.THREAT_R)
	col.step(0.5)
	assert_str(p2.threat_state()).is_equal("none")  # incoming cleared by the collision


func test_collision_reduce_motion_fade_only() -> void:
	Settings.reduce_motion = true
	var r := _column([1, 2])
	_send(r[1], GameEvent.COLLISION, 1.0, {"a": 1, "b": 2, "ids": [1, 2], "reward_a": 0, "reward_b": 2})
	var p: PeriscopePanel = r[0].panel_for(2)
	r[0].step(0.15)
	assert_float(p.burst_radius()).is_equal(PeriscopePanel.THREAT_R)
	assert_bool(p.effect_counts()["burst_radius"]).is_false()


func test_absorbed_and_reflected_glyphs() -> void:
	var r := _column([1, 2, 3])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.ABSORBED, 1.0, {"id": 3, "from": 1, "to": 2, "reward": 2})
	assert_str(col.panel_for(2).threat_state()).is_equal("absorbed")
	assert_str(col.panel_for(2).threat_glyph()).is_equal("decoy_flare")
	_send(r[1], GameEvent.REFLECTED, 1.0, {"id": 4, "by": 3, "to": 1, "reward": 2})
	assert_str(col.panel_for(3).threat_state()).is_equal("reflected")
	assert_str(col.panel_for(3).threat_glyph()).is_equal("reflect")
	col.step(0.61)
	assert_str(col.panel_for(2).threat_state()).is_equal("none")
	assert_str(col.panel_for(3).threat_state()).is_equal("none")


# ---- Tube, held reward, blips -------------------------------------------------------------

func test_reward_and_meter() -> void:
	var r := _column([1, 2])
	var p: PeriscopePanel = r[0].panel_for(2)
	_send(r[1], GameEvent.METER, 1.0, {"seat": 2, "progress": 5, "threshold": 20, "held": -1, "queued": -1,
		"debris": false})
	assert_float(p.meter_fraction()).is_equal_approx(0.25, 0.001)
	assert_int(p.blip_count()).is_equal(1)
	_send(r[1], GameEvent.METER, 1.1, {"seat": 2, "progress": 6, "threshold": 20, "held": -1, "queued": -1,
		"debris": false})
	assert_int(p.blip_count()).is_equal(2)
	_send(r[1], GameEvent.REWARD_EARNED, 2.0, {"seat": 2, "reward": Reward.Id.GHOST_NOTES, "source": "meter"})
	assert_str(p.held_glyph()).is_equal("ghost_notes")
	assert_float(p.meter_fraction()).is_equal(1.0)
	r[0].step(0.5)
	assert_int(p.blip_count()).is_equal(0)  # 400 ms life


func test_blip_caps_full_and_low() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	add_child(p)
	p.setup(1, "MAKO")
	for i in 10:
		p.add_blip()
	assert_int(p.blip_count()).is_equal(6)
	assert_bool(p.effect_counts()["sweep"]).is_true()
	Settings.low_effects = true
	p.apply_effect_settings()
	assert_int(p.blip_count()).is_equal(2)
	assert_bool(p.effect_counts()["sweep"]).is_false()
	assert_bool(p.effect_counts()["glow"]).is_false()
	Settings.low_effects = false
	Settings.reduce_motion = true
	p.apply_effect_settings()
	assert_bool(p.effect_counts()["sweep"]).is_false()
	p.add_blip()
	assert_int(p.blip_count()).is_greater(0)


func test_blips_seeded_per_seat() -> void:
	var a := PeriscopePanel.new()
	var b := PeriscopePanel.new()
	a.setup(2, "ORCA")
	b.setup(2, "ORCA")
	a.add_blip()
	b.add_blip()
	assert_float(float(a._blips[0]["a"])).is_equal(float(b._blips[0]["a"]))
	a.free()
	b.free()


# ---- Bounty -------------------------------------------------------------------------------

func test_bounty_moves() -> void:
	var r := _column([1, 2])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.BOUNTY_MOVED, 1.0, {"from_seat": -1, "to_seat": 2})
	var p := col.panel_for(2)
	assert_bool(p.bounty()).is_true()
	assert_float(p.callsign_x()).is_equal(120.0)
	assert_that(p.bracket_color()).is_equal(Palette.REWARD_GOLD)
	assert_that(PeriscopePanel.BOUNTY_RECT.position).is_equal(Vector2(96, 14))
	assert_bool(col.panel_for(1).bounty()).is_false()
	_send(r[1], GameEvent.BOUNTY_MOVED, 2.0, {"from_seat": 2, "to_seat": 1})
	assert_bool(p.bounty()).is_false()
	assert_float(p.callsign_x()).is_equal(96.0)
	assert_bool(col.panel_for(1).bounty()).is_true()


# ---- Solo Duel ----------------------------------------------------------------------------

func test_duel_status() -> void:
	var r := _column([1, 2])
	var p: PeriscopePanel = r[0].panel_for(2)
	_send(r[1], GameEvent.DUEL_START, 1.0, {"solo": 0})
	assert_str(p.status_text()).is_equal("SOLO --%")
	_pct[2] = 87
	assert_str(p.status_text()).is_equal("SOLO 87%")
	assert_that(p.status_color()).is_equal(Palette.SONAR_PALE)
	_pct[2] = 60
	assert_str(p.status_text()).is_equal("SOLO 60%")
	assert_that(p.status_color()).is_equal(Palette.TEXT_MID)
	_send(r[1], GameEvent.DUEL_RESULT, 9.0, {"solo": 0, "winner": -1, "pct": 0, "best_pct": 60, "tied": false})
	assert_str(p.status_text()).ends_with(" M")


# ---- Target reticle -----------------------------------------------------------------------

func test_target_reticle_and_caret() -> void:
	var r := _column([1, 2, 3])
	var col: PeriscopeColumn = r[0]
	assert_bool(col.has_reticle()).is_false()
	_send(r[1], GameEvent.TARGET, 0.0, {"seat": 0, "mode": 0, "target": 3})
	assert_that(col.reticle_rect()).is_equal(Rect2(24, 408, 352, 88).grow(4))
	var caret := col.caret_rect()
	assert_float(caret.position.x).is_equal(384.0)
	assert_float(caret.end.x).is_equal(396.0)
	assert_float(caret.get_center().y).is_equal(452.0)
	assert_bool(col.panel_for(3).is_targeted()).is_true()
	assert_that(col.panel_for(3).edge_color()).is_equal(Palette.SONAR)
	# Other seats' TARGET events are ignored.
	_send(r[1], GameEvent.TARGET, 0.1, {"seat": 1, "mode": 0, "target": 2})
	assert_int(col.target_seat()).is_equal(3)
	# Glide to panel 1 over DUR_FAST.
	_send(r[1], GameEvent.TARGET, 0.2, {"seat": 0, "mode": 1, "target": 1})
	assert_bool(col.is_gliding()).is_true()
	col.step(0.06)
	var mid := col.reticle_rect()
	assert_float(mid.position.y).is_less(408.0 - 4.0)
	assert_float(mid.position.y).is_greater(216.0 - 4.0)
	col.step(0.07)
	assert_that(col.reticle_rect()).is_equal(Rect2(24, 216, 352, 88).grow(4))
	assert_bool(col.panel_for(3).is_targeted()).is_false()
	_send(r[1], GameEvent.TARGET, 0.3, {"seat": 0, "mode": 0, "target": -1})
	assert_bool(col.has_reticle()).is_false()
	assert_that(col.reticle_rect()).is_equal(Rect2())


func test_target_jump_under_reduce() -> void:
	Settings.reduce_motion = true
	var r := _column([1, 2, 3])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.TARGET, 0.0, {"seat": 0, "mode": 0, "target": 3})
	_send(r[1], GameEvent.TARGET, 0.1, {"seat": 0, "mode": 0, "target": 1})
	assert_bool(col.is_gliding()).is_false()
	assert_that(col.reticle_rect()).is_equal(Rect2(24, 216, 352, 88).grow(4))
	assert_bool(col.effect_counts()["glide"]).is_false()


func test_keepout_shapes_cover_panels_and_reticle() -> void:
	var r := _column([1, 2])
	var col: PeriscopeColumn = r[0]
	assert_int(col.keepout_shapes().size()).is_equal(2)
	_send(r[1], GameEvent.TARGET, 0.0, {"seat": 0, "mode": 0, "target": 2})
	var shapes := col.keepout_shapes()
	assert_int(shapes.size()).is_equal(4)
	for s in shapes:
		for v in s:
			assert_float(v.x).is_less_equal(396.0)
			assert_float(v.y).is_greater_equal(212.0)
			assert_float(v.y).is_less_equal(500.0)
	assert_int(col.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_draw_does_not_error() -> void:
	var r := _column([1, 2, 3])
	var col: PeriscopeColumn = r[0]
	_send(r[1], GameEvent.TARGET, 0.0, {"seat": 0, "mode": 0, "target": 2})
	_send(r[1], GameEvent.IMPLODED, 0.0, {"seat": 3})
	_send(r[1], GameEvent.REWARD_EARNED, 0.0, {"seat": 1, "reward": Reward.Id.DECOY_FLARE, "source": "meter"})
	_send(r[1], GameEvent.TORPEDO_LAUNCH, 0.0, {"id": 1, "from": 1, "to": 2, "reward": 2, "launch_t": 0.0,
		"arrive_t": 0.5})
	col.update(0.2)
	await await_idle_frame()
	assert_int(col.panels().size()).is_equal(3)
