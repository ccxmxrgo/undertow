extends GdUnitTestSuite
## 05-05 (AV-04, D-05): torpedo juice. FlashLimiter (03-UI-SPEC 11.6 photosensitivity rule:
## <= 3 flashes per second, >= 1/3 s apart), TorpedoJuice reactions to existing EventChannel
## events (impact, launch, near / distant implosion), id dedupe, effect modes, the periscope
## implosion flash, the FailScreen implosion sound and the bind_views integration.


# ---- FlashLimiter ---------------------------------------------------------------------------

func test_flash_limiter_gap_and_window() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(0.0)).is_true()
	assert_bool(lim.try_flash(0.34)).is_true()
	assert_bool(lim.try_flash(0.68)).is_true()
	assert_bool(lim.try_flash(0.70)).is_false()  # within 1/3 s of the last
	assert_bool(lim.try_flash(0.99)).is_false()  # would be the 4th inside 1 s
	assert_bool(lim.try_flash(1.40)).is_true()


func test_flash_limiter_rejects_non_finite() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(NAN)).is_false()
	assert_bool(lim.try_flash(INF)).is_false()
	assert_bool(lim.try_flash(0.0)).is_true()


func test_flash_limiter_reset() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(5.0)).is_true()
	assert_bool(lim.try_flash(5.1)).is_false()
	lim.reset()
	assert_bool(lim.try_flash(5.1)).is_true()


# ---- TorpedoJuice unit ------------------------------------------------------------------------

const NAMES := ["YOU", "MAKO", "ORCA", "BARRACUDA"]
const SCENE := "res://scenes/gameplay.tscn"

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
	MatchSetup.pending = null
	VersusController.test_autoplay_human = false
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


func _live(_seat: int) -> int:
	return -1


## [juice, fx, board, socket, column-or-null]
func _juice(with_column := false) -> Array:
	var board: Control = auto_free(Control.new())
	add_child(board)
	var fx: FxLayer = auto_free(FxLayer.new())
	board.add_child(fx)
	fx.bind(null, board)
	var socket: Control = auto_free(Control.new())
	add_child(socket)
	socket.position = Vector2(272.0, 928.0)
	socket.size = Vector2(80.0, 80.0)
	var col: PeriscopeColumn = null
	if with_column:
		col = auto_free(PeriscopeColumn.new())
		add_child(col)
		var rivals: Array[int] = [1, 2, 3]
		col.bind(null, 0, rivals, PackedStringArray(NAMES), null, VersusConfig.new(), _live, false)
		col.step(1.0)
	var j: TorpedoJuice = auto_free(TorpedoJuice.new())
	add_child(j)
	j.bind(null, 0, fx, socket, col)
	return [j, fx, board, socket, col]


static func _ev(type: String, t: float, fields: Dictionary) -> Dictionary:
	return GameEvent.make(type, t, fields)


func _set_mode(j: TorpedoJuice, low: bool, reduce: bool) -> void:
	Settings.low_effects = low
	Settings.reduce_motion = reduce
	j.apply_effect_settings()


func test_landed_on_local_seat_impacts_once() -> void:
	var r := _juice()
	var j: TorpedoJuice = r[0]
	var fx: FxLayer = r[1]
	j.on_event(_ev(GameEvent.LANDED, 10.0, {"id": 5, "from": 1, "to": 0}))
	assert_int(j.impact_count).is_equal(1)
	assert_int(j.flash_count).is_equal(1)
	assert_int(j.sfx_count("impact")).is_equal(1)
	assert_array(j.shake_requests).is_equal([[10.0, 160000]])
	assert_bool(fx.shaking()).is_true()
	assert_bool(j.impact_active()).is_true()
	assert_float(j.impact_alpha()).is_equal_approx(0.35, 0.001)
	# The same id again (an online echo) changes nothing.
	j.on_event(_ev(GameEvent.LANDED, 10.0, {"id": 5, "from": 1, "to": 0}))
	assert_int(j.impact_count).is_equal(1)
	assert_int(j.sfx_count("impact")).is_equal(1)
	assert_int(j.shake_requests.size()).is_equal(1)
	# A landing on another seat does nothing.
	j.on_event(_ev(GameEvent.LANDED, 12.0, {"id": 6, "from": 0, "to": 1}))
	assert_int(j.impact_count).is_equal(1)


func test_impact_flash_decays_in_120_ms() -> void:
	var j: TorpedoJuice = _juice()[0]
	j.on_event(_ev(GameEvent.LANDED, 3.0, {"id": 1, "to": 0}))
	j.step(0.06)
	assert_float(j.impact_alpha()).is_equal_approx(0.175, 0.01)
	j.step(0.07)
	assert_bool(j.impact_active()).is_false()


func test_impact_under_reduce_motion_flashes_without_shake() -> void:
	var r := _juice()
	var j: TorpedoJuice = r[0]
	var fx: FxLayer = r[1]
	Settings.reduce_motion = true
	fx.apply_effect_settings()
	j.apply_effect_settings()
	j.on_event(_ev(GameEvent.LANDED, 10.0, {"id": 5, "to": 0}))
	assert_int(j.impact_count).is_equal(1)
	assert_int(j.flash_count).is_equal(1)
	assert_array(j.shake_requests).is_empty()
	assert_bool(fx.shaking()).is_false()


func test_own_launch_thumps_rings_and_kicks() -> void:
	var r := _juice()
	var j: TorpedoJuice = r[0]
	j.on_event(_ev(GameEvent.TORPEDO_LAUNCH, 12.0, {"id": 7, "from": 0, "to": 2}))
	assert_int(j.launch_count).is_equal(1)
	assert_int(j.sfx_count("launch")).is_equal(1)
	assert_bool(j.ring_active()).is_true()
	assert_array(j.shake_requests).is_equal([[3.0, 80000]])
	assert_float(j.ring_radius()).is_equal_approx(40.0, 0.01)
	assert_float(j.ring_alpha()).is_equal_approx(0.8, 0.01)
	j.step(0.1)
	assert_float(j.ring_radius()).is_equal_approx(56.0, 0.5)
	j.step(0.11)
	assert_bool(j.ring_active()).is_false()
	# An echo of the same id, and a rival launch, do nothing.
	j.on_event(_ev(GameEvent.TORPEDO_LAUNCH, 12.0, {"id": 7, "from": 0, "to": 2}))
	j.on_event(_ev(GameEvent.TORPEDO_LAUNCH, 14.0, {"id": 8, "from": 1, "to": 0}))
	assert_int(j.launch_count).is_equal(1)


func test_launch_under_low_effects_has_no_ring_but_sound_and_kick() -> void:
	var j: TorpedoJuice = _juice()[0]
	_set_mode(j, true, false)
	j.on_event(_ev(GameEvent.TORPEDO_LAUNCH, 12.0, {"id": 7, "from": 0, "to": 2}))
	assert_bool(j.ring_active()).is_false()
	assert_int(j.sfx_count("launch")).is_equal(1)
	assert_array(j.shake_requests).is_equal([[3.0, 80000]])


func test_launch_under_reduce_motion_rings_fade_only_without_kick() -> void:
	var j: TorpedoJuice = _juice()[0]
	_set_mode(j, false, true)
	j.on_event(_ev(GameEvent.TORPEDO_LAUNCH, 12.0, {"id": 7, "from": 0, "to": 2}))
	assert_array(j.shake_requests).is_empty()
	assert_bool(j.ring_active()).is_true()
	assert_float(j.ring_radius()).is_equal(56.0)
	j.step(0.1)
	assert_float(j.ring_radius()).is_equal(56.0)
	assert_float(j.ring_alpha()).is_equal_approx(0.4, 0.01)


func test_near_and_distant_implosions() -> void:
	var r := _juice(true)
	var j: TorpedoJuice = r[0]
	var col: PeriscopeColumn = r[4]
	var panel := col.panel_for(2)
	assert_object(panel).is_not_null()
	j.on_event(_ev(GameEvent.IMPLODED, 30.0, {"seat": 0}))
	assert_int(j.near_implosion_count).is_equal(1)
	assert_int(j.sfx_count("implosion")).is_equal(1)
	j.on_event(_ev(GameEvent.IMPLODED, 31.0, {"seat": 2}))
	assert_int(j.distant_implosion_count).is_equal(1)
	assert_int(j.sfx_count("implosion_distant")).is_equal(1)
	assert_bool(panel.edge_flashing()).is_true()
	panel.step(0.31)
	assert_bool(panel.edge_flashing()).is_false()
	# Each seat implodes once; bad seats are ignored.
	j.on_event(_ev(GameEvent.IMPLODED, 32.0, {"seat": 2}))
	j.on_event(_ev(GameEvent.IMPLODED, 33.0, {"seat": -1}))
	j.on_event(_ev(GameEvent.IMPLODED, 34.0, {"seat": 99}))
	assert_int(j.distant_implosion_count).is_equal(1)
	assert_int(j.sfx_count("implosion_distant")).is_equal(1)


func test_rival_implosion_without_column_still_sounds() -> void:
	var j: TorpedoJuice = _juice()[0]
	j.on_event(_ev(GameEvent.IMPLODED, 31.0, {"seat": 3}))
	assert_int(j.distant_implosion_count).is_equal(1)
	assert_int(j.flash_count).is_equal(0)


func test_flood_is_flash_limited_but_every_sound_plays() -> void:
	var j: TorpedoJuice = _juice()[0]
	for i in range(5):
		j.on_event(_ev(GameEvent.LANDED, 20.0 + 0.1 * i, {"id": 100 + i, "to": 0}))
	assert_int(j.impact_count).is_equal(5)
	assert_int(j.sfx_count("impact")).is_equal(5)
	assert_int(j.flash_count).is_less_equal(3)


func test_flood_of_implosions_is_flash_limited() -> void:
	var r := _juice(true)
	var j: TorpedoJuice = r[0]
	j.on_event(_ev(GameEvent.LANDED, 40.0, {"id": 1, "to": 0}))
	j.on_event(_ev(GameEvent.IMPLODED, 40.05, {"seat": 1}))
	j.on_event(_ev(GameEvent.IMPLODED, 40.1, {"seat": 2}))
	j.on_event(_ev(GameEvent.IMPLODED, 40.15, {"seat": 3}))
	assert_int(j.flash_count).is_equal(1)
	assert_int(j.distant_implosion_count).is_equal(3)
	var col: PeriscopeColumn = r[4]
	assert_bool(col.panel_for(1).edge_flashing()).is_false()


func test_malformed_fields_are_safe() -> void:
	var j: TorpedoJuice = _juice()[0]
	j.on_event({})
	j.on_event({"type": GameEvent.LANDED})
	j.on_event({"type": GameEvent.IMPLODED, "seat": "x"})
	j.on_event({"type": 7, "to": 0})
	assert_int(j.impact_count).is_equal(0)


func test_effect_counts_per_mode() -> void:
	var j: TorpedoJuice = _juice()[0]
	var full := {"launch_ring": true, "kick": true, "impact_shake": true, "edge_flash": true}
	assert_dict(j.effect_counts()).is_equal(full)
	_set_mode(j, true, false)
	assert_bool(bool(j.effect_counts()["launch_ring"])).is_false()
	assert_bool(bool(j.effect_counts()["edge_flash"])).is_true()
	_set_mode(j, false, true)
	assert_bool(bool(j.effect_counts()["kick"])).is_false()
	assert_bool(bool(j.effect_counts()["impact_shake"])).is_false()
	assert_bool(bool(j.effect_counts()["edge_flash"])).is_true()
	_set_mode(j, false, false)
	assert_dict(j.effect_counts()).is_equal(full)


func test_registered_as_effect_node() -> void:
	var j: TorpedoJuice = _juice()[0]
	assert_bool(j.is_in_group(UiKit.FX_GROUP)).is_true()


func test_keepout_shapes_are_the_three_bands() -> void:
	var j: TorpedoJuice = _juice()[0]
	assert_int(j.keepout_shapes().size()).is_equal(3)
	var rects := j.band_rects()
	var w := j._screen_size()
	assert_object(rects[0]).is_equal(Rect2(0.0, 0.0, 96.0, w.y))
	assert_object(rects[1]).is_equal(Rect2(w.x - 96.0, 0.0, 96.0, w.y))
	assert_object(rects[2]).is_equal(Rect2(0.0, 0.0, w.x, 96.0))


func test_socket_ring_centres_on_the_socket() -> void:
	var j: TorpedoJuice = _juice()[0]
	assert_vector(j._ring_center()).is_equal(Vector2(312.0, 968.0) - j.global_position)


func test_panel_flash_implosion_alone() -> void:
	var p: PeriscopePanel = auto_free(PeriscopePanel.new())
	add_child(p)
	p.setup(2, "ORCA")
	p.flash_implosion()
	assert_bool(p.edge_flashing()).is_true()
	assert_bool(p.edge_color().is_equal_approx(Palette.WARNING_RED)).override_failure_message(str(p.edge_color())).is_true()
	p.step(0.15)
	assert_bool(p.edge_flashing()).is_true()
	p.step(0.16)
	assert_bool(p.edge_flashing()).is_false()


func test_fail_screen_plays_the_implosion() -> void:
	var f: FailScreen = auto_free(FailScreen.new())
	add_child(f)
	f.setup(120.0)
	assert_bool(f.implosion_played()).is_false()
	f.play(0.05)
	assert_bool(f.implosion_played()).is_true()


# ---- Integration --------------------------------------------------------------------------------

func test_versus_match_wires_torpedo_juice() -> void:
	var m := MatchSetup.new()
	m.mode = MatchSetup.MODE_VERSUS
	m.rivals = 3
	m.skill = "regular"
	m.seed = 424242
	MatchSetup.pending = m
	VersusController.test_autoplay_human = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = false
	var gp: Gameplay = (load(SCENE) as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	await get_tree().process_frame
	var v: VersusController = gp.versus
	assert_object(v).is_not_null()
	var j: TorpedoJuice = v.torpedo_juice
	assert_object(j).is_not_null()
	assert_object(j.get_parent()).is_same(v.versus_hud)
	assert_int(j.get_index()).is_greater(v.edge_flash.get_index())
	var before := j.impact_count
	v.channel.send(_ev(GameEvent.LANDED, 1.0, {"id": 900001, "from": 1, "to": v.local_seat}))
	assert_int(j.impact_count).is_equal(before + 1)
