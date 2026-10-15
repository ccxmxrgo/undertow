extends GdUnitTestSuite
## 03-09 Task 1: RewardSocket (UI-SPEC 5.1), TargetReadout (5.2) and RewardPopup (5.4).
## Every view is driven only by EventChannel events plus step(dt).

const NAMES := ["YOU", "MAKO", "ORCA", "BARRACUDA"]

var _saved_low := false
var _saved_rm := false


func before_test() -> void:
	_saved_low = Settings.low_effects
	_saved_rm = Settings.reduce_motion
	Settings.low_effects = false
	Settings.reduce_motion = false


func after_test() -> void:
	Settings.low_effects = _saved_low
	Settings.reduce_motion = _saved_rm


func _ev(type: String, fields: Dictionary, t: float = 1.0) -> Dictionary:
	return GameEvent.make(type, t, fields)


func _socket() -> Array:
	var ch := LoopbackChannel.new()
	var s: RewardSocket = auto_free(RewardSocket.new())
	add_child(s)
	s.bind(ch, 0, VersusConfig.new())
	return [s, ch]


func _meter(ch: EventChannel, progress: int, threshold: int, held: int = -1, queued: int = -1,
		debris: bool = false, seat: int = 0) -> void:
	ch.send(_ev(GameEvent.METER, {"seat": seat, "progress": progress, "threshold": threshold,
		"held": held, "queued": queued, "debris": debris}))


# ---- RewardSocket ------------------------------------------------------------------------

func test_socket_rect_and_mouse_filter() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	assert_object(RewardSocket.RECT).is_equal(Rect2(272.0, 928.0, 80.0, 80.0))
	assert_object(s.position).is_equal(Vector2(272.0, 928.0))
	assert_object(s.size).is_equal(Vector2(80.0, 80.0))
	assert_int(s.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(s.is_in_group(UiKit.FX_GROUP)).is_true()


func test_socket_meter_fill_and_name() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	_meter(ch, 23, 57)
	assert_str(s.name_text()).is_equal("23/57")
	assert_float(s.arc_fraction()).is_equal_approx(23.0 / 57.0, 0.0001)
	assert_object(s.name_color()).is_equal(Palette.TEXT_LO)
	assert_bool(s.breathing()).is_false()
	s.step(0.5)
	await get_tree().process_frame


func test_socket_name_label_geometry() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var l: Label = s.name_label
	assert_object(l).is_not_null()
	var gr := l.get_global_rect()
	assert_float(gr.position.x).is_equal_approx(232.0, 0.5)
	assert_float(gr.size.x).is_equal_approx(160.0, 0.5)
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	assert_int(fs).is_equal(Palette.SIZE_LABEL)
	assert_float(gr.position.y + f.get_ascent(fs)).is_equal_approx(1036.0, 0.5)
	assert_int(l.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)


func test_socket_held_disruptor_and_buff() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_str(s.name_text()).is_equal("INK CLOUD")
	assert_object(s.name_color()).is_equal(Palette.TEXT_HI)
	assert_object(s.ring_color()).is_equal(Palette.WARNING_RED)
	assert_bool(s.breathing()).is_true()
	assert_float(s.arc_fraction()).is_equal(1.0)
	Settings.reduce_motion = true
	s.apply_effect_settings()
	assert_bool(s.breathing()).is_false()
	assert_bool(bool(s.effect_counts()["breathing"])).is_false()
	assert_bool(bool(s.effect_counts()["pop"])).is_false()
	Settings.reduce_motion = false
	s.apply_effect_settings()
	var r2 := _socket()
	var s2: RewardSocket = r2[0]
	(r2[1] as EventChannel).send(_ev(GameEvent.REWARD_EARNED,
		{"seat": 0, "reward": Reward.Id.DECOY_FLARE, "source": "meter"}))
	assert_object(s2.ring_color()).is_equal(Palette.SONAR)
	assert_str(s2.name_text()).is_equal("DECOY FLARE")


func test_socket_earn_pop_scale() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_float(s.icon_scale()).is_less(0.2)
	s.step(Palette.DUR_BASE * 0.5)
	assert_float(s.icon_scale()).is_greater(1.0)
	s.step(Palette.DUR_BASE)
	assert_float(s.icon_scale()).is_equal_approx(1.0, 0.001)
	assert_float(s.icon_alpha()).is_equal_approx(1.0, 0.001)
	# Reduce motion: no scale, fade in.
	Settings.reduce_motion = true
	var r2 := _socket()
	var s2: RewardSocket = r2[0]
	(r2[1] as EventChannel).send(_ev(GameEvent.REWARD_EARNED,
		{"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_float(s2.icon_scale()).is_equal(1.0)
	assert_float(s2.icon_alpha()).is_less(0.2)


func test_socket_waiting_until_launch_or_refusal() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	s.step(1.0)
	ch.send(_ev(GameEvent.FIRE_QUEUED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "to": 2, "launch_beat": 4}))
	assert_bool(s.waiting()).is_true()
	assert_float(s.icon_alpha()).is_equal_approx(0.5, 0.001)
	ch.send(_ev(GameEvent.FIRE_REFUSED, {"seat": 0, "reason": "no_target"}))
	assert_bool(s.waiting()).is_false()
	assert_str(s.name_text()).is_equal("INK CLOUD")  # reward kept
	ch.send(_ev(GameEvent.FIRE_QUEUED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "to": 2, "launch_beat": 4}))
	assert_bool(s.waiting()).is_true()
	# Another seat's launch changes nothing.
	ch.send(_ev(GameEvent.TORPEDO_LAUNCH, {"id": 1, "from": 1, "to": 0, "reward": Reward.Id.SONAR_JAM,
		"debris": false}))
	assert_bool(s.waiting()).is_true()
	ch.send(_ev(GameEvent.TORPEDO_LAUNCH, {"id": 2, "from": 0, "to": 2, "reward": Reward.Id.INK_CLOUD,
		"debris": false}))
	assert_bool(s.waiting()).is_false()
	assert_bool(s.launching()).is_true()
	_meter(ch, 0, 57)
	assert_str(s.name_text()).is_equal("0/57")
	s.step(Palette.DUR_FAST + 0.01)
	assert_bool(s.launching()).is_false()


func test_socket_queue_pip() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	assert_bool(s.queue_pip_visible()).is_false()
	ch.send(_ev(GameEvent.REWARD_QUEUED, {"seat": 0, "reward": Reward.Id.OVERCLOCK}))
	assert_bool(s.queue_pip_visible()).is_true()
	assert_object(RewardSocket.PIP_CENTER).is_equal(Vector2(346.0, 934.0))
	assert_object(s.pip_color()).is_equal(Palette.REWARD_GOLD)
	_meter(ch, 0, 57, Reward.Id.INK_CLOUD, Reward.Id.OVERCLOCK)
	assert_bool(s.queue_pip_visible()).is_true()
	_meter(ch, 0, 57, Reward.Id.OVERCLOCK, -1)
	assert_bool(s.queue_pip_visible()).is_false()


func test_socket_wreck_debris_states() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	ch.send(_ev(GameEvent.IMPLODED, {"seat": 0}))
	assert_bool(s.lost_flashing()).is_true()
	assert_bool(s.is_debris()).is_true()
	s.step(0.25)
	assert_bool(s.lost_flashing()).is_false()
	_meter(ch, 5, 57, -1, -1, true)
	assert_str(s.name_text()).is_equal("DEBRIS 5/57")
	assert_object(s.arc_color()).is_equal(Palette.TEXT_MID)
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.SILT, "source": "debris"}))
	assert_str(s.name_text()).is_equal("SILT")
	assert_object(s.ring_color()).is_equal(Palette.TEXT_MID)
	assert_object(s.name_color()).is_equal(Palette.TEXT_MID)
	# Two debris shots (VersusConfig.debris_max_per_wreck = 2) use it up.
	for i in 2:
		ch.send(_ev(GameEvent.TORPEDO_LAUNCH, {"id": 10 + i, "from": 0, "to": 1, "reward": Reward.Id.SILT,
			"debris": true}))
		_meter(ch, 0, 57, -1, -1, true)
	assert_str(s.name_text()).is_equal("NO DEBRIS LEFT")
	assert_object(s.name_color()).is_equal(Palette.TEXT_LO)
	assert_bool(s.arc_visible()).is_false()


func test_socket_debris_used_field_from_meter() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.IMPLODED, {"seat": 0}))
	ch.send(_ev(GameEvent.METER, {"seat": 0, "progress": 0, "threshold": 57, "held": -1, "queued": -1,
		"debris": true, "debris_used": 2}))
	assert_str(s.name_text()).is_equal("NO DEBRIS LEFT")


func test_socket_ignores_other_seats_and_malformed_events() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	_meter(ch, 10, 57)
	_meter(ch, 40, 57, -1, -1, false, 2)
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 1, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	ch.send(_ev(GameEvent.IMPLODED, {"seat": 3}))
	ch.send(_ev(GameEvent.REWARD_QUEUED, {"seat": 1, "reward": Reward.Id.OVERCLOCK}))
	assert_str(s.name_text()).is_equal("10/57")
	assert_bool(s.is_debris()).is_false()
	assert_bool(s.queue_pip_visible()).is_false()
	ch.send({"type": GameEvent.METER})  # no seat: ignored
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": 999, "source": "meter"}))
	assert_str(s.name_text()).is_equal("10/57")


func test_socket_effect_counts_and_glow() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	assert_dict(s.effect_counts()).is_equal({"breathing": true, "glow": true, "pop": true})
	Settings.low_effects = true
	s.apply_effect_settings()
	assert_dict(s.effect_counts()).is_equal({"breathing": true, "glow": false, "pop": true})


func test_socket_breathing_alpha_range() -> void:
	var r := _socket()
	var s: RewardSocket = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.OVERCLOCK, "source": "meter"}))
	var lo := 2.0
	var hi := -1.0
	for i in 32:
		s.step(0.05)
		lo = minf(lo, s.full_alpha())
		hi = maxf(hi, s.full_alpha())
	assert_float(lo).is_greater_equal(0.69)
	assert_float(hi).is_less_equal(1.0)
	assert_float(hi - lo).is_greater(0.2)
	Settings.reduce_motion = true
	s.apply_effect_settings()
	s.step(0.3)
	assert_float(s.full_alpha()).is_equal(1.0)
	s.queue_redraw()
	await get_tree().process_frame


# ---- TargetReadout -----------------------------------------------------------------------

func _readout(training: bool = false) -> Array:
	var ch := LoopbackChannel.new()
	var t: TargetReadout = auto_free(TargetReadout.new())
	add_child(t)
	t.bind(ch, 0, PackedStringArray(NAMES), training)
	return [t, ch]


func test_readout_rect() -> void:
	var r := _readout()
	var t: TargetReadout = r[0]
	assert_object(TargetReadout.RECT).is_equal(Rect2(248.0, 752.0, 144.0, 88.0))
	assert_object(Rect2(t.position, t.size)).is_equal(TargetReadout.RECT)
	assert_int(t.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_readout_modes() -> void:
	var r := _readout()
	var t: TargetReadout = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 2}))
	assert_str(t.caption_text()).is_equal("AUTO TARGET")
	assert_object(t.caption_color()).is_equal(Palette.TEXT_LO)
	assert_str(t.value_text()).is_equal("ORCA")
	assert_object(t.value_color()).is_equal(Palette.TEXT_HI)
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.LOCKED, "target": 3}))
	assert_str(t.caption_text()).is_equal("TARGET")
	assert_str(t.value_text()).is_equal("BARRACUDA")
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.ATTACKERS, "target": 1}))
	assert_str(t.caption_text()).is_equal("ATTACKERS")
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": -1}))
	assert_str(t.value_text()).is_equal("NONE")
	assert_object(t.value_color()).is_equal(Palette.TEXT_LO)
	# Other seats do not change the readout.
	ch.send(_ev(GameEvent.TARGET, {"seat": 1, "mode": PlayerState.TargetMode.LOCKED, "target": 0}))
	assert_str(t.caption_text()).is_equal("AUTO TARGET")
	ch.send(_ev(GameEvent.IMPLODED, {"seat": 0}))
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 2}))
	assert_str(t.caption_text()).is_equal("DEBRIS TARGET")
	assert_str(t.value_text()).is_equal("ORCA")
	t.queue_redraw()
	await get_tree().process_frame


func test_readout_training_drone() -> void:
	var r := _readout(true)
	var t: TargetReadout = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 1}))
	assert_str(t.value_text()).is_equal("DRONE")


func test_readout_truncates_long_callsign() -> void:
	var ch := LoopbackChannel.new()
	var t: TargetReadout = auto_free(TargetReadout.new())
	add_child(t)
	t.bind(ch, 0, PackedStringArray(["YOU", "AVERYVERYLONGCALLSIGN"]), false)
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 1}))
	assert_str(t.value_text()).ends_with("...")
	var w := Palette.font().get_string_size(t.value_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_BODY).x
	assert_float(w).is_less_equal(136.0)


func test_readout_refusal_and_bounty_flashes() -> void:
	var r := _readout()
	var t: TargetReadout = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 2}))
	ch.send(_ev(GameEvent.FIRE_REFUSED, {"seat": 0, "reason": "shielded"}))
	assert_str(t.caption_text()).is_equal("SHIELDED")
	assert_object(t.caption_color()).is_equal(Palette.WARNING_RED)
	t.step(0.7)
	assert_str(t.caption_text()).is_equal("SHIELDED")
	t.step(0.11)
	assert_str(t.caption_text()).is_equal("AUTO TARGET")
	ch.send(_ev(GameEvent.FIRE_REFUSED, {"seat": 0, "reason": "no_target"}))
	assert_str(t.caption_text()).is_equal("NO TARGET")
	assert_object(t.caption_color()).is_equal(Palette.WARNING_RED)
	t.step(0.81)
	ch.send(_ev(GameEvent.FIRE_REFUSED, {"seat": 1, "reason": "shielded"}))
	assert_str(t.caption_text()).is_equal("AUTO TARGET")
	ch.send(_ev(GameEvent.BOUNTY_CLAIMED, {"from": 0, "to": 2, "refund": 14}))
	assert_str(t.caption_text()).is_equal("BOUNTY +14")
	assert_object(t.caption_color()).is_equal(Palette.REWARD_GOLD)
	t.step(1.1)
	assert_str(t.caption_text()).is_equal("BOUNTY +14")
	t.step(0.11)
	assert_str(t.caption_text()).is_equal("AUTO TARGET")
	ch.send(_ev(GameEvent.BOUNTY_CLAIMED, {"from": 1, "to": 2, "refund": 9}))
	assert_str(t.caption_text()).is_equal("AUTO TARGET")


func test_readout_pulse_on_change_off_under_reduce() -> void:
	var r := _readout()
	var t: TargetReadout = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.AUTO, "target": 2}))
	t.step(1.0)
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.LOCKED, "target": 3}))
	t.step(Palette.DUR_FAST * 0.5)
	assert_float(t.glyph_scale()).is_greater(1.1)
	t.step(Palette.DUR_FAST)
	assert_float(t.glyph_scale()).is_equal(1.0)
	assert_bool(bool(t.effect_counts()["pulse"])).is_true()
	Settings.reduce_motion = true
	t.apply_effect_settings()
	ch.send(_ev(GameEvent.TARGET, {"seat": 0, "mode": PlayerState.TargetMode.LOCKED, "target": 1}))
	t.step(Palette.DUR_FAST * 0.5)
	assert_float(t.glyph_scale()).is_equal(1.0)
	assert_bool(bool(t.effect_counts()["pulse"])).is_false()


# ---- RewardPopup -------------------------------------------------------------------------

var _blocked := false


func _popup() -> Array:
	var ch := LoopbackChannel.new()
	var p: RewardPopup = auto_free(RewardPopup.new())
	add_child(p)
	_blocked = false
	p.bind(ch, 0, func() -> bool: return _blocked)
	return [p, ch]


func _fire_kb() -> String:
	return Settings.bindings.display_name(&"fire", &"keyboard").to_upper()


func test_popup_reward_ready_disruptor_and_buff() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	var ch: EventChannel = r[1]
	assert_bool(p.showing()).is_false()
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_bool(p.showing()).is_true()
	assert_str(p.caption_text()).is_equal("REWARD READY · " + _fire_kb())
	assert_str(p.name_text()).is_equal("INK CLOUD")
	assert_object(p.name_color()).is_equal(Palette.WARNING_RED)
	p.step(RewardPopup.LIFE + 0.01)
	assert_bool(p.showing()).is_false()
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.OVERCLOCK, "source": "meter"}))
	assert_object(p.name_color()).is_equal(Palette.SONAR_PALE)


func test_popup_default_binding_is_space() -> void:
	var saved := Settings.bindings
	Settings.bindings = BindingStore.new()
	Settings.bindings.reset_defaults()
	var r := _popup()
	var p: RewardPopup = r[0]
	(r[1] as EventChannel).send(_ev(GameEvent.REWARD_EARNED,
		{"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	var text := p.caption_text()
	Settings.bindings = saved
	assert_str(text).is_equal("REWARD READY · SPACE")


func test_popup_variants_and_other_seats() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 1, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_bool(p.showing()).is_false()
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.SONAR_JAM, "source": "duel"}))
	assert_str(p.caption_text()).is_equal("SOLO PRIZE · " + _fire_kb())
	assert_str(p.name_text()).is_equal("SONAR JAM")
	ch.send(_ev(GameEvent.REWARD_QUEUED, {"seat": 0, "reward": Reward.Id.DECOY_FLARE}))
	# FIFO: the queued popup waits for the first one.
	assert_str(p.name_text()).is_equal("SONAR JAM")
	assert_int(p.queued_count()).is_equal(1)
	p.step(RewardPopup.LIFE + 0.01)
	assert_str(p.caption_text()).is_equal("PRIZE QUEUED")
	assert_str(p.name_text()).is_equal("DECOY FLARE")
	assert_object(p.name_color()).is_equal(Palette.SONAR_PALE)


func test_popup_waits_behind_blocker() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	var ch: EventChannel = r[1]
	_blocked = true
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_bool(p.showing()).is_false()
	p.step(0.5)
	assert_bool(p.showing()).is_false()
	_blocked = false
	p.step(0.016)
	assert_bool(p.showing()).is_true()
	assert_str(p.name_text()).is_equal("INK CLOUD")


func test_popup_timeline_and_no_rise() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	var ch: EventChannel = r[1]
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	assert_float(p.pop_scale()).is_equal_approx(1.3, 0.001)
	p.step(Palette.DUR_FAST)
	assert_float(p.pop_scale()).is_equal_approx(1.0, 0.001)
	assert_float(p.alpha()).is_equal(1.0)
	p.step(RewardPopup.HOLD_SEC - 0.01)
	assert_float(p.alpha()).is_equal(1.0)
	p.step(0.01 + RewardPopup.FADE_SEC * 0.5)
	assert_float(p.alpha()).is_equal_approx(0.5, 0.02)
	assert_float(RewardPopup.FADE_SEC).is_equal(0.22)
	assert_float(RewardPopup.HOLD_SEC).is_equal(1.2)
	p.queue_redraw()
	await get_tree().process_frame
	Settings.reduce_motion = true
	p.apply_effect_settings()
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.OVERCLOCK, "source": "meter"}))
	p.step(RewardPopup.LIFE)
	assert_float(p.pop_scale()).is_equal(1.0)
	assert_bool(bool(p.effect_counts()["pop"])).is_false()


func test_popup_keepout_and_full_canvas() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(p.anchor_right).is_equal(1.0)
	assert_float(p.anchor_bottom).is_equal(1.0)
	var shapes := p.keepout_shapes()
	assert_int(shapes.size()).is_equal(1)
	for pt in shapes[0]:
		assert_bool(pt.x >= 0.0 and pt.x <= 416.0).is_true()
		assert_bool(pt.y >= 516.0 and pt.y <= 598.0).is_true()


func test_popup_pad_label_after_pad_input() -> void:
	var r := _popup()
	var p: RewardPopup = r[0]
	var ch: EventChannel = r[1]
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_B
	ev.pressed = true
	p._input(ev)
	ch.send(_ev(GameEvent.REWARD_EARNED, {"seat": 0, "reward": Reward.Id.INK_CLOUD, "source": "meter"}))
	var pad := Settings.bindings.display_name(&"fire", &"gamepad").to_upper()
	assert_str(p.caption_text()).is_equal("REWARD READY · " + pad)
