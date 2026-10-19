extends GdUnitTestSuite
## Phase 3 code review (03-REVIEW.md) view-level regressions: WR-04 .. WR-12 and the cheap info
## items. Rules-engine fixes live next to their own suites (bounty, sub rig, controller).


func _crossed_highway() -> Highway:
	var hw: Highway = auto_free(Highway.new())
	# Lanes 1 and 2 settled in each other's column (Crossed Wires).
	hw._lane_x = PackedFloat32Array([-1.5, 0.5, -0.5, 1.5])
	return hw


# ---- WR-04 (V-3): bursts, sparks and popups follow the judged lane's drawn column ----------

func test_fx_layer_bursts_use_the_swapped_receptor() -> void:
	var hw := _crossed_highway()
	var fx: FxLayer = auto_free(FxLayer.new())
	fx.bind(hw, null)
	assert_vector(fx.lane_point(1)).is_equal(hw.receptor_center(1))
	assert_vector(fx.lane_point(1)).is_equal(Trench.hit_point(2))
	assert_vector(fx.lane_point(0)).is_equal(Trench.hit_point(0))
	fx.on_judged(1, 0, InputJudge.Judgment.GOOD, 0.0)
	assert_vector(fx.good_emitters[1].position).is_equal(Trench.hit_point(2))


func test_fx_layer_without_highway_uses_static_column() -> void:
	var fx: FxLayer = auto_free(FxLayer.new())
	assert_vector(fx.lane_point(1)).is_equal(Trench.hit_point(1))


func test_feedback_popup_sits_over_the_swapped_receptor() -> void:
	var hw := _crossed_highway()
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	fb.highway = hw
	fb.on_judged(2, 0, InputJudge.Judgment.PERFECT, 0.0)
	assert_float(float(fb.popup(0)["x"])).is_equal_approx(Trench.hit_point(1).x, 1e-3)
	fb.on_ghost_hit(1)
	assert_float(float(fb.popup(1)["x"])).is_equal_approx(Trench.hit_point(2).x, 1e-3)


# ---- WR-05 (V-5): judgment popups never show past the Ink Cloud band edge ------------------

func _inked_highway(t: float) -> Highway:
	var chart := TestCharts.click_chart(120.0, 64, 1000)
	var cfg := VersusConfig.new()
	var stack := PayloadStack.new(chart, cfg)
	stack.install({"id": 1, "reward": Reward.Id.INK_CLOUD, "arrive_t": 2.0, "end_t": 10.0,
		"seed": 3})
	var hw: Highway = auto_free(Highway.new())
	hw.payloads = stack
	hw.vcfg = cfg
	hw._vt = t
	return hw


func test_popups_fade_out_under_full_ink() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	fb.highway = _inked_highway(5.0)
	assert_float(fb.ink_fade()).is_equal_approx(0.0, 1e-6)
	fb.highway = _inked_highway(1.0)  # before arrival: no ink
	assert_float(fb.ink_fade()).is_equal(1.0)
	fb.highway = _inked_highway(2.25)  # half a beat into the 1-beat fade in
	assert_float(fb.ink_fade()).is_between(0.01, 0.99)


func test_popups_unchanged_without_payloads() -> void:
	var fb: Feedback = auto_free(Feedback.new())
	fb.audio_enabled = false
	assert_float(fb.ink_fade()).is_equal(1.0)
	fb.highway = _crossed_highway()
	assert_float(fb.ink_fade()).is_equal(1.0)


# ---- WR-06 (V-2): periscope callsign budget includes the +2 px glyph spacing ---------------

func test_nine_letter_callsign_fits_next_to_the_place() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	p.setup(1, "barracuda")
	p.on_event(GameEvent.make(GameEvent.STATUS, 1.0, {"seat": 1, "hull": 100.0, "depth": 10,
		"alive": true, "place": 2}))
	assert_str(p.place_text()).is_equal("2ND")
	assert_str(p.shown_callsign()).is_equal("BARRACUDA")
	var w := PeriscopePanel.spaced_font().get_string_size("BARRACUDA", HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_LABEL).x
	assert_float(w).is_greater(PeriscopePanel.CALL_MAX)  # the old fixed budget cut it
	assert_float(w).is_less_equal(p.call_max())
	# The callsign never runs into the place text.
	var pw := Palette.font().get_string_size("2ND", HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	assert_float(p.callsign_x() + p.call_max()).is_less_equal(PeriscopePanel.PLACE_RIGHT - pw)


func test_callsign_cache_follows_bounty_shift() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	p.setup(1, "averyveryverylongcallsign")
	var plain := p.shown_callsign()
	p.on_event(GameEvent.make(GameEvent.BOUNTY_MOVED, 1.0, {"from_seat": -1, "to_seat": 1}))
	var shifted := p.shown_callsign()
	assert_int(shifted.length()).is_less_equal(plain.length())
	var w := PeriscopePanel.spaced_font().get_string_size(shifted, HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_LABEL).x
	assert_float(w).is_less_equal(p.call_max())


# ---- WR-08 (perf): PeriscopePanel static / dynamic split ---------------------------------------

func test_periscope_dynamic_layer_and_dashes() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	p.setup(1, "orca")
	assert_int(p.get_child_count(true)).is_equal(1)
	assert_bool(p.get_child(0, true) is Node2D).is_true()
	assert_int(PeriscopePanel.dash_points().size()).is_equal(PeriscopePanel.DASHES * PeriscopePanel.DASH_SEG * 2)


func test_periscope_flashes_and_blips_still_expire_without_reflection() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	p.setup(1, "orca")
	p.add_blip()
	p.add_blip()
	p.on_event(GameEvent.make(GameEvent.COLLISION, 1.0, {"a": 1, "b": 2}))
	assert_bool(p.edge_flashing()).is_true()
	assert_bool(p.dynamic_moving()).is_true()
	p.step(0.25)
	assert_int(p.blip_count()).is_equal(2)
	p.step(0.5)
	assert_int(p.blip_count()).is_equal(0)
	assert_bool(p.edge_flashing()).is_false()
	assert_str(p.threat_state()).is_equal("none")


func test_periscope_draws_in_tree() -> void:
	var p: PeriscopePanel = PeriscopePanel.new()
	add_child(p)
	p.setup(1, "orca")
	p.on_event(GameEvent.make(GameEvent.TORPEDO_LAUNCH, 0.0, {"id": 1, "from": 2, "to": 1,
		"reward": Reward.Id.INK_CLOUD, "launch_t": 0.0, "arrive_t": 0.5}))
	p.update(0.25)
	await await_idle_frame()
	assert_float(p.threat_fraction()).is_equal_approx(0.5, 1e-6)
	p.queue_free()


# ---- WR-07 (V-1): the collision headline fits the alert's headline box ------------------------

func test_collision_headline_fits_without_truncation() -> void:
	var w := Palette.display_font().get_string_size("BOTH DESTROYED", HORIZONTAL_ALIGNMENT_LEFT, -1,
		Palette.SIZE_HEADING).x
	assert_float(w).is_less_equal(IncomingAlert.HEADLINE_MAX)


# ---- WR-09 (perf): alert and banner reuse their style boxes -------------------------------------

func test_alert_and_banner_style_boxes_are_cached() -> void:
	var a: IncomingAlert = auto_free(IncomingAlert.new())
	assert_object(a._panel_style()).is_same(a._panel_style())
	var b: EventBanner = auto_free(EventBanner.new())
	assert_object(b._panel_style()).is_same(b._panel_style())
	var fit: Array = b._fit("SOLO DUEL", Palette.font(), Palette.SIZE_LABEL, 0.0)
	assert_str(fit[0]).is_equal("SOLO DUEL")
	assert_float(fit[1]).is_greater(0.0)


# ---- WR-10 (perf): idle views stop redrawing; killfeed measures once -------------------------

func test_killfeed_segment_offsets_measured_once_and_match_content_width() -> void:
	var k: Killfeed = auto_free(Killfeed.new())
	var names := PackedStringArray(["YOU", "ORCA", "MAKO"])
	k.bind(LoopbackChannel.new(), 0, names, VersusConfig.new())
	var line := k.line_for(GameEvent.make(GameEvent.LANDED, 1.0, {"id": 1, "from": 1, "to": 2,
		"reward": Reward.Id.INK_CLOUD, "reflected": false, "debris": false}))
	assert_bool(line.is_empty()).is_false()
	var xs := Killfeed._seg_xs(line)
	assert_bool(line.has("xs")).is_true()
	assert_object(Killfeed._seg_xs(line)).is_equal(xs)
	var segs: Array = line["segments"]
	assert_int(xs.size()).is_equal(segs.size())
	var last: Dictionary = segs[segs.size() - 1]
	assert_float(xs[xs.size() - 1] + Killfeed._seg_width(last)).is_equal_approx(Killfeed.content_width(segs), 1e-3)


func test_reward_socket_idle_does_not_animate() -> void:
	var s: RewardSocket = auto_free(RewardSocket.new())
	assert_bool(s.breathing()).is_false()
	assert_int(s._anim).is_equal(RewardSocket.Anim.NONE)
	assert_float(s._arc_t).is_equal(1.0)


func test_edge_flash_idle_clears_shown_flag() -> void:
	var ef: EdgeFlash = auto_free(EdgeFlash.new())
	ef.observe(1.0)
	assert_bool(ef._shown).is_false()
	assert_float(ef.current_alpha()).is_equal(0.0)
