extends GdUnitTestSuite
## 03-11: IncomingAlert, EdgeFlash, VersusSfx (UI-SPEC 6.3, 6.5, TORP-04, spec req 9) and
## EventBanner + SectionBanner suppression (UI-SPEC 6.4, spec req 11, D-22, D-24).

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


func _chart() -> ChartData:
	var c := ChartData.new()
	c.tempo_map.append({"time": 0.0, "bpm": 120.0})  # 1 beat = 0.5 s, 1 bar = 2 s
	return c


func _cfg() -> VersusConfig:
	return VersusConfig.new()


func _sfx() -> VersusSfx:
	var s: VersusSfx = auto_free(VersusSfx.new())
	add_child(s)
	return s


func _alert(ch: EventChannel, sfx: VersusSfx = null) -> IncomingAlert:
	var a: IncomingAlert = auto_free(IncomingAlert.new())
	add_child(a)
	a.bind(ch, 0, NAMES, _chart(), _cfg(), sfx)
	return a


func _launch(id: int, from: int, to: int, reward: int, launch_t: float, arrive_t: float,
		warheads: Array = [3, 5, 7, 9], reflected := false, debris := false) -> Dictionary:
	return GameEvent.make(GameEvent.TORPEDO_LAUNCH, launch_t, {"id": id, "from": from, "to": to,
		"reward": reward, "launch_beat": 20, "launch_t": launch_t, "arrive_t": arrive_t, "warheads": warheads,
		"reflected": reflected, "debris": debris})


func _landed(id: int, from: int, to: int, reward: int, arrive_t: float, end_t: float) -> Dictionary:
	return GameEvent.make(GameEvent.LANDED, arrive_t, {"id": id, "from": from, "to": to, "reward": reward,
		"arrive_t": arrive_t, "active_start": arrive_t, "end_t": end_t, "seed": 1, "reflected": false,
		"debris": false})


# ---- IncomingAlert -----------------------------------------------------------------------

func test_alert_incoming_state_texts_and_lead() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	assert_object(IncomingAlert.RECT).is_equal(Rect2(640.0, 120.0, 640.0, 72.0))
	assert_int(a.state()).is_equal(IncomingAlert.State.HIDDEN)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	assert_int(a.state()).is_equal(IncomingAlert.State.INCOMING)
	assert_str(a.caption_text()).is_equal("INCOMING · MAKO")
	assert_object(a.caption_color()).is_equal(Palette.WARNING_RED)
	assert_str(a.headline_text()).is_equal("INK CLOUD")
	assert_str(a.hint_text()).is_equal("HIT RINGED NOTES PERFECT")
	assert_object(a.hint_color()).is_equal(Palette.TEXT_MID)
	assert_float(a.first_visible_t()).is_equal(10.0)
	var beat := 60.0 / 120.0
	assert_float(a.arrive_t() - a.first_visible_t()).is_greater_equal(beat * _cfg().torpedo_travel_beats - 1e-6)
	a.observe(10.25)
	assert_float(a.ring_fraction()).is_equal_approx(0.5, 1e-4)
	a.observe(10.0)
	assert_float(a.ring_fraction()).is_equal_approx(1.0, 1e-4)
	assert_bool(a.visible).is_true()
	assert_float(a.slide_offset()).is_equal_approx(-16.0, 0.01)
	a.step(Palette.DUR_FAST + 0.001)
	assert_float(a.alpha()).is_equal_approx(1.0, 1e-3)
	assert_float(a.slide_offset()).is_equal(0.0)


func test_alert_hint_variants() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.SONAR_JAM, 10.0, 10.5, []))
	assert_str(a.hint_text()).is_equal("CANNOT BE REFLECTED")
	assert_object(a.hint_color()).is_equal(Palette.TEXT_LO)
	ch.send(GameEvent.make(GameEvent.BUFF_APPLIED, 11.0, {"seat": 0, "reward": Reward.Id.DECOY_FLARE,
		"until_t": 30.0, "amount": 0}))
	ch.send(_launch(2, 2, 0, Reward.Id.GHOST_NOTES, 12.0, 12.5))
	assert_str(a.hint_text()).is_equal("DECOY WILL ABSORB")
	assert_object(a.hint_color()).is_equal(Palette.SONAR)
	ch.send(GameEvent.make(GameEvent.BUFF_ENDED, 12.5, {"seat": 0, "reward": Reward.Id.DECOY_FLARE,
		"reason": "used"}))
	ch.send(_launch(3, 1, 0, Reward.Id.INK_CLOUD, 14.0, 14.5, [], true))
	assert_str(a.caption_text()).is_equal("REFLECTED BY MAKO")
	assert_str(a.hint_text()).is_equal("CANNOT BE REFLECTED")
	ch.send(_launch(4, 1, 0, Reward.Id.SILT, 16.0, 16.5, [], false, true))
	assert_str(a.caption_text()).is_equal("WRECK DEBRIS · MAKO")
	assert_str(a.headline_text()).is_equal("SILT")
	assert_str(a.hint_text()).is_equal("CANNOT BE REFLECTED")


func test_alert_active_reflect_count_and_bars_left() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	a.step(0.2)
	ch.send(_landed(1, 1, 0, Reward.Id.INK_CLOUD, 10.5, 18.5))
	a.observe(10.5)
	assert_int(a.state()).is_equal(IncomingAlert.State.ACTIVE)
	assert_str(a.caption_text()).is_equal("ACTIVE · MAKO")
	assert_str(a.hint_text()).is_equal("REFLECT 0/4")
	assert_object(a.hint_color()).is_equal(Palette.SONAR_PALE)
	assert_bool(a.is_cross_fading()).is_true()
	a.step(0.13)
	assert_bool(a.is_cross_fading()).is_false()
	ch.send(GameEvent.make(GameEvent.WARHEAD, 11.0, {"id": 1, "seat": 0, "note": 5, "k": 2, "n": 4, "ok": true}))
	assert_str(a.hint_text()).is_equal("REFLECT 2/4")
	ch.send(GameEvent.make(GameEvent.WARHEAD, 11.5, {"id": 1, "seat": 0, "note": 7, "k": 2, "n": 4, "ok": false}))
	a.observe(11.5)
	assert_str(a.hint_text()).is_equal("4 BARS LEFT")
	assert_object(a.hint_color()).is_equal(Palette.TEXT_MID)
	a.observe(17.0)
	assert_str(a.hint_text()).is_equal("1 BAR LEFT")
	assert_float(a.ring_fraction()).is_equal_approx(1.5 / 8.0, 1e-4)
	ch.send(GameEvent.make(GameEvent.PAYLOAD_END, 18.5, {"id": 1, "seat": 0, "reward": Reward.Id.INK_CLOUD,
		"reason": "expired", "immune_until": 20.5}))
	assert_int(a.state()).is_equal(IncomingAlert.State.ENDED)
	a.step(0.31)
	assert_int(a.state()).is_equal(IncomingAlert.State.HIDDEN)
	assert_bool(a.visible).is_false()


func test_alert_result_states_hold_then_fade() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	a.step(0.2)
	ch.send(GameEvent.make(GameEvent.REFLECTED, 12.0, {"id": 1, "by": 0, "to": 1, "reward": Reward.Id.INK_CLOUD}))
	assert_int(a.state()).is_equal(IncomingAlert.State.REFLECTED)
	assert_str(a.caption_text()).is_equal("REFLECTED")
	assert_str(a.headline_text()).is_equal("BACK TO MAKO")
	assert_str(a.hint_text()).is_equal("")
	# PAYLOAD_END (reason reflected) must not cut the result short.
	ch.send(GameEvent.make(GameEvent.PAYLOAD_END, 12.0, {"id": 1, "seat": 0, "reward": Reward.Id.INK_CLOUD,
		"reason": "reflected", "immune_until": 14.0}))
	assert_int(a.state()).is_equal(IncomingAlert.State.REFLECTED)
	a.step(1.19)
	assert_int(a.state()).is_equal(IncomingAlert.State.REFLECTED)
	a.step(0.02)
	assert_int(a.state()).is_equal(IncomingAlert.State.ENDED)
	a.step(0.15)
	assert_float(a.alpha()).is_between(0.3, 0.7)
	a.step(0.2)
	assert_int(a.state()).is_equal(IncomingAlert.State.HIDDEN)

	ch.send(GameEvent.make(GameEvent.ABSORBED, 20.0, {"id": 2, "from": 2, "to": 0, "reward": Reward.Id.SONAR_JAM}))
	assert_str(a.caption_text()).is_equal("DECOY ABSORBED")
	assert_str(a.headline_text()).is_equal("SONAR JAM")
	ch.send(GameEvent.make(GameEvent.COLLISION, 22.0, {"a": 0, "b": 2, "ids": [3, 4], "reward_a": 0, "reward_b": 1}))
	assert_str(a.caption_text()).is_equal("HEAD-ON COLLISION")
	assert_str(a.headline_text()).is_equal("BOTH TORPEDOES DESTROYED")


func test_alert_ignores_events_not_involving_local_seat() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send(_launch(1, 1, 2, Reward.Id.INK_CLOUD, 10.0, 10.5))
	ch.send(_landed(1, 1, 2, Reward.Id.INK_CLOUD, 10.5, 18.5))
	ch.send(GameEvent.make(GameEvent.REFLECTED, 12.0, {"id": 1, "by": 2, "to": 1, "reward": 2}))
	ch.send(GameEvent.make(GameEvent.ABSORBED, 12.0, {"id": 1, "from": 1, "to": 2, "reward": 2}))
	ch.send(GameEvent.make(GameEvent.COLLISION, 13.0, {"a": 1, "b": 2, "ids": [5, 6]}))
	assert_int(a.state()).is_equal(IncomingAlert.State.HIDDEN)
	assert_bool(a.visible).is_false()


func test_alert_malformed_event_is_safe() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send({"type": GameEvent.TORPEDO_LAUNCH, "to": 0, "from": 9, "launch_t": 5.0, "arrive_t": 4.0})
	assert_str(a.caption_text()).is_equal("INCOMING · ?")
	a.observe(-100.0)
	assert_float(a.ring_fraction()).is_between(0.0, 1.0)
	a.observe(NAN)
	a.step(0.5)


func test_alert_effect_contract_and_reduce_motion() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	assert_bool(a.is_in_group(UiKit.FX_GROUP)).is_true()
	var full := a.effect_counts()
	Settings.reduce_motion = true
	a.apply_effect_settings()
	assert_bool(a.effect_counts() != full).is_true()
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	assert_float(a.slide_offset()).is_equal(0.0)
	Settings.reduce_motion = false
	Settings.low_effects = true
	a.apply_effect_settings()
	assert_bool(a.effect_counts()["glow"]).is_false()
	assert_bool(a.effect_counts() != full).is_true()
	for poly in a.keepout_shapes():
		for pt in poly:
			assert_bool(Rect2(640.0, 120.0, 640.0, 72.0).grow(0.5).has_point(pt)).is_true()


func test_alert_draws_every_state_without_error() -> void:
	var ch := LoopbackChannel.new()
	var a := _alert(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	a.queue_redraw()
	await get_tree().process_frame
	ch.send(_landed(1, 1, 0, Reward.Id.INK_CLOUD, 10.5, 18.5))
	await get_tree().process_frame
	ch.send(GameEvent.make(GameEvent.COLLISION, 13.0, {"a": 0, "b": 1, "ids": [5, 6]}))
	await get_tree().process_frame
	ch.send(GameEvent.make(GameEvent.REFLECTED, 14.0, {"id": 1, "by": 0, "to": 1, "reward": 2}))
	await get_tree().process_frame
	assert_bool(a.is_showing()).is_true()


# ---- Ping ----------------------------------------------------------------------------------

func test_alert_pings_once_per_launch_with_sfx_also_bound() -> void:
	var ch := LoopbackChannel.new()
	var sfx := _sfx()
	sfx.bind(ch, 0)
	var a := _alert(ch, sfx)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	assert_int(sfx.ping_count()).is_equal(1)
	assert_int(a.state()).is_equal(IncomingAlert.State.INCOMING)
	ch.send(_launch(2, 1, 2, Reward.Id.INK_CLOUD, 12.0, 12.5))  # not at us
	assert_int(sfx.ping_count()).is_equal(1)
	ch.send(_launch(3, 2, 0, Reward.Id.SONAR_JAM, 14.0, 14.5))
	assert_int(sfx.ping_count()).is_equal(2)


func test_alert_pings_without_sfx_bound_to_channel() -> void:
	var ch := LoopbackChannel.new()
	var sfx := _sfx()
	_alert(ch, sfx)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	assert_int(sfx.ping_count()).is_equal(1)


# ---- VersusSfx -------------------------------------------------------------------------------

func test_sfx_plays_headless_on_sfx_bus() -> void:
	var sfx := _sfx()
	assert_bool(sfx.ping()).is_true()
	assert_bool(sfx.collision()).is_true()
	assert_int(sfx.players().size()).is_greater(0)
	var want: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	for p in sfx.players():
		assert_str(str(p.bus)).is_equal(str(want))
	var ping := VersusSfx.make_ping(44100)
	var hit := VersusSfx.make_collision(44100)
	assert_int(ping.data.size()).is_equal(int(VersusSfx.PING_SEC * 44100) * 2)
	assert_int(hit.data.size()).is_equal(int(VersusSfx.COLLISION_SEC * 44100) * 2)
	assert_int(ping.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)


func test_sfx_collision_for_everyone_and_ping_dedup() -> void:
	var ch := LoopbackChannel.new()
	var sfx := _sfx()
	sfx.bind(ch, 0)
	ch.send(GameEvent.make(GameEvent.COLLISION, 5.0, {"a": 1, "b": 2, "ids": [1, 2]}))
	assert_int(sfx.collision_count()).is_equal(1)
	ch.send(GameEvent.make(GameEvent.COLLISION, 6.0, {"a": 0, "b": 3, "ids": [3, 4]}))
	assert_int(sfx.collision_count()).is_equal(2)
	assert_bool(sfx.ping(7)).is_true()
	assert_bool(sfx.ping(7)).is_false()
	assert_int(sfx.ping_count()).is_equal(1)


# ---- EdgeFlash ---------------------------------------------------------------------------

func _flash(ch: EventChannel) -> EdgeFlash:
	var f: EdgeFlash = auto_free(EdgeFlash.new())
	add_child(f)
	f.bind(ch, 0)
	return f


func test_edge_flash_envelope() -> void:
	var ch := LoopbackChannel.new()
	var f := _flash(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	assert_float(f.alpha_at(9.99)).is_equal(0.0)
	assert_float(f.alpha_at(10.0)).is_equal_approx(0.0, 1e-4)
	assert_float(f.alpha_at(10.03)).is_equal_approx(0.25, 1e-3)
	assert_float(f.alpha_at(10.06)).is_equal_approx(0.5, 1e-3)
	assert_float(f.alpha_at(10.28)).is_equal_approx(0.25, 1e-3)
	assert_float(f.alpha_at(10.499)).is_less(0.01)
	assert_float(f.alpha_at(10.5)).is_equal_approx(0.3, 1e-3)
	assert_float(f.alpha_at(10.65)).is_equal_approx(0.15, 1e-3)
	assert_float(f.alpha_at(10.8)).is_equal(0.0)
	assert_int(f.pulse_times().size()).is_equal(2)  # at most 2 per torpedo
	f.observe(10.06)
	assert_float(f.current_alpha()).is_equal_approx(0.5, 1e-3)
	# Not at us: nothing.
	ch.send(_launch(2, 1, 2, Reward.Id.INK_CLOUD, 20.0, 20.5))
	assert_float(f.alpha_at(20.06)).is_equal(0.0)


func test_edge_flash_photosensitivity_cap() -> void:
	var ch := LoopbackChannel.new()
	var f := _flash(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	ch.send(_launch(2, 2, 0, Reward.Id.INK_CLOUD, 10.2, 10.7))  # within 333 ms: skipped
	assert_int(f.pulse_times().size()).is_equal(2)
	# A barrage: one launch every 50 ms for 3 s never exceeds 3 pulses in any 1 s window.
	var g := _flash(LoopbackChannel.new())
	for i in range(60):
		var t := 30.0 + 0.05 * i
		g.add_threat(t, t + 0.3)
	var times := g.pulse_times()
	times.sort()
	for i in range(times.size()):
		var c := 0
		for j in range(i, times.size()):
			if times[j] - times[i] <= 1.0:
				c += 1
		assert_int(c).is_less_equal(3)
		if i > 0:
			assert_float(times[i] - times[i - 1]).is_greater_equal(1.0 / 3.0 - 1e-6)


func test_edge_flash_keepout_and_no_fx_registration() -> void:
	var f := _flash(LoopbackChannel.new())
	var shapes := f.keepout_shapes()
	assert_int(shapes.size()).is_equal(2)
	var rects: Array[Rect2] = [Rect2(0.0, 0.0, 16.0, 1080.0), Rect2(1904.0, 0.0, 16.0, 1080.0)]
	for i in range(2):
		var r := rects[i]
		for pt in shapes[i]:
			assert_bool(r.grow(0.5).has_point(pt)).is_true()
	assert_bool(f.is_in_group(UiKit.FX_GROUP)).is_false()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_edge_flash_draws() -> void:
	var ch := LoopbackChannel.new()
	var f := _flash(ch)
	ch.send(_launch(1, 1, 0, Reward.Id.INK_CLOUD, 10.0, 10.5))
	f.observe(10.06)
	await get_tree().process_frame
	assert_float(f.current_alpha()).is_greater(0.4)
