extends GdUnitTestSuite
## AV-05 (02.2 plan 24, UI-SPEC 11): every effect node of every screen honours Low effects
## and Reduce motion, at start and on Settings.settings_changed. Each context declares the
## owners it MUST contain (W8): a missing owner fails with its name. Every node found in
## UiKit.FX_GROUP inside the context (plus the ScreenTransition autoload) is then toggled:
## Low effects must change its effect_counts(), Reduce motion must change the listed motion
## entries, and switching back must restore the Full values exactly.

const SCORES_TMP := "user://test_effect_settings_scores.cfg"

## Owner name = script class_name (or the node name for autoloads / inner classes).
## Real owners found by grep "register_fx" (plan 24):
## - Song Select draws its list focus bar and caret itself (FocusMarker.bar_rect /
##   caret_points), because the list root keeps focus: the focus-marker owner there is
##   SongSelect, which is already in the set.
## - Results gained a FocusMarker in plan 24 (UI-SPEC 4.3: one per screen).
const EXPECTED := {
	"menu": ["AbyssBackdrop", "LogoWordmark", "FocusMarker", "ScreenTransition"],
	"song_select": ["AbyssBackdrop", "SongSelect", "ScreenTransition"],
	"gameplay": ["Arena", "Highway", "HighwayNotes", "FxLayer", "MultiplierRing", "SectionBanner",
		"StreakCounter", "ScreenTransition"],
	"results": ["AbyssBackdrop", "GradeEmblem", "FocusMarker", "ScreenTransition"],
}

## Motion entries that Reduce motion must flip, per owner: key -> value under Reduce motion.
## Owners not listed have no Reduce-motion row in UI-SPEC 11 that changes their counts
## (e.g. HighwayNotes: glow sprites stay on under Reduce motion).
const REDUCE := {
	"AbyssBackdrop": {"frozen": true},
	"LogoWordmark": {"shimmer": false},
	"FocusMarker": {"glide": false, "breathing": false},
	"ScreenTransition": {"crossfade": true},
	"SongSelect": {"visualizer_animated": false, "sweep": false},
	"Arena": {"snow_frozen": true, "creature": false, "colony_radius_pulse": false},
	"Highway": {"receptor_squash": false},
	"FxLayer": {"shake": false, "flash": false, "sustain_rate": 0.0},
	"MultiplierRing": {"pop": false, "drain": false},
	"SectionBanner": {"slide": false},
	"StreakCounter": {"milestone_sparks": 0},
	"GradeEmblem": {"scale": false},
}

var _low := false
var _reduce := false
var _style := ""
var _old_scores_path := ""


func before_test() -> void:
	_low = Settings.low_effects
	_reduce = Settings.reduce_motion
	_style = Settings.background_style
	# 02.2-27: Calm is the default background; these checks assert Living behaviour.
	Settings.background_style = Settings.BACKGROUND_LIVING
	Settings.low_effects = false
	Settings.reduce_motion = false
	Settings.settings_changed.emit()
	_old_scores_path = ScoreStore.default_path
	ScoreStore.default_path = SCORES_TMP


func after_test() -> void:
	Settings.low_effects = _low
	Settings.reduce_motion = _reduce
	Settings.background_style = _style
	Settings.settings_changed.emit()
	ScoreStore.default_path = _old_scores_path
	for p in [SCORES_TMP, SCORES_TMP + ".tmp", SCORES_TMP + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Gameplay.pending_chart = null
	Gameplay.pending_autoplay = false
	Gameplay.pending_intro = IntroTimeline.Mode.FULL


# ---- helpers ----------------------------------------------------------------------------

static func owner_name(n: Node) -> String:
	var s := n.get_script() as Script
	if s != null and s.get_global_name() != &"":
		return String(s.get_global_name())
	return String(n.name)


## Effect nodes of a context: FX_GROUP members inside root, plus the ScreenTransition autoload.
func _fx_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var st := get_tree().root.get_node_or_null("ScreenTransition")
	for n in get_tree().get_nodes_in_group(UiKit.FX_GROUP):
		if n == root or root.is_ancestor_of(n) or n == st:
			out.append(n)
	return out


func _apply(low: bool, reduce: bool) -> void:
	Settings.low_effects = low
	Settings.reduce_motion = reduce
	Settings.settings_changed.emit()


## Snapshot of every node's effect_counts() (keyed by instance id).
func _snap(nodes: Array[Node]) -> Dictionary:
	var out := {}
	for n in nodes:
		out[n.get_instance_id()] = (n.call(&"effect_counts") as Dictionary).duplicate(true)
	return out


func _check_context(ctx: String, root: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var nodes := _fx_nodes(root)
	var names: Array[String] = []
	for n in nodes:
		names.append(owner_name(n))
	var missing: Array[String] = []
	for want: String in EXPECTED[ctx]:
		if not names.has(want):
			missing.append(want)
	assert_array(missing).override_failure_message(
		"%s: effect owners missing from FX_GROUP: %s (found %s)" % [ctx, missing, names]).is_empty()

	var full := _snap(nodes)
	_apply(true, false)
	var low := _snap(nodes)
	_apply(false, true)
	var red := _snap(nodes)
	_apply(false, false)
	var back := _snap(nodes)

	var errors: Array[String] = []
	for n in nodes:
		var id := n.get_instance_id()
		var nm := owner_name(n)
		var f: Dictionary = full[id]
		if (back[id] as Dictionary) != f:
			errors.append("%s: not restored to Full (%s -> %s)" % [nm, f, back[id]])
		var low_changes: bool = (low[id] as Dictionary) != f
		var red_changes: bool = (red[id] as Dictionary) != f
		if (EXPECTED[ctx] as Array).has(nm) and not low_changes:
			errors.append("%s: Low effects changes nothing (%s)" % [nm, f])
		if not (low_changes or red_changes):
			errors.append("%s: neither Low effects nor Reduce motion changes anything (%s)" % [nm, f])
		if REDUCE.has(nm):
			var want: Dictionary = REDUCE[nm]
			var r: Dictionary = red[id]
			for k: String in want:
				if not r.has(k):
					errors.append("%s: Reduce motion entry '%s' missing (%s)" % [nm, k, r])
				elif r[k] != want[k]:
					errors.append("%s: under Reduce motion '%s' = %s, want %s" % [nm, k, r[k], want[k]])
				elif f.has(k) and f[k] == want[k]:
					errors.append("%s: '%s' is already %s at Full" % [nm, k, want[k]])
	assert_array(errors).override_failure_message("%s:\n%s" % [ctx, "\n".join(errors)]).is_empty()


func _find(root: Node, cls: String) -> Node:
	for n in _fx_nodes(root):
		if owner_name(n) == cls:
			return n
	return null


func _main_menu() -> MainMenu:
	MainMenu.boot_handled = true
	var m: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(m)
	auto_free(m)
	return m


func _song_select() -> SongSelect:
	var lib: Node = load("res://src/autoload/song_library.gd").new()
	lib.songs_root_override = "user://test_effect_settings_songs"
	lib.cache_path = "user://test_effect_settings_cache.json"
	lib.auto_scan = false
	add_child(lib)
	auto_free(lib)
	var e := SongEntry.new()
	e.id = "fx01"
	e.title = "Effect Song"
	e.difficulties.append({"name": "expert", "note_count": 100, "fingerprint": "fp_fx01"})
	lib.entries.assign([e])
	var s: SongSelect = (load("res://scenes/song_select.tscn") as PackedScene).instantiate()
	s.library = lib
	add_child(s)
	auto_free(s)
	return s


func _gameplay() -> Gameplay:
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	Gameplay.pending_chart = TestCharts.short_chart()
	Gameplay.pending_autoplay = true
	var gp: Gameplay = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	add_child(gp)
	auto_free(gp)
	return gp


func _results() -> ResultsScreen:
	var host := Control.new()
	add_child(host)
	auto_free(host)
	var r := ResultsScreen.new()
	host.add_child(r)
	r.setup(HullScore.new(JudgeConfig.new()), false,
		{"eligible": true, "new_record": true, "previous_depth": 10.0, "best_depth": 20.0}, false,
		{"offsets": PackedFloat32Array([0.0, 0.01, -0.02])})
	return r


# ---- tests ------------------------------------------------------------------------------

func test_owner_name_uses_class_name_or_node_name() -> void:
	var b := AbyssBackdrop.new()
	auto_free(b)
	assert_str(owner_name(b)).is_equal("AbyssBackdrop")
	var st := get_tree().root.get_node_or_null("ScreenTransition")
	assert_object(st).is_not_null()
	assert_str(owner_name(st)).is_equal("ScreenTransition")


func test_menu_effect_nodes_follow_settings() -> void:
	var m := _main_menu()
	await _check_context("menu", m)


func test_menu_particles_160_to_40() -> void:
	var m := _main_menu()
	await get_tree().process_frame
	var bd := _find(m, "AbyssBackdrop")
	assert_object(bd).is_not_null()
	var c: Dictionary = bd.effect_counts()
	assert_int(int(c["snow"]) + int(c["specks"])).is_equal(160)
	_apply(true, false)
	c = bd.effect_counts()
	assert_int(int(c["snow"]) + int(c["specks"])).is_equal(40)
	_apply(false, true)
	c = bd.effect_counts()
	assert_int(int(c["snow"]) + int(c["specks"])).is_equal(160)
	assert_bool(c["frozen"]).is_true()


func test_song_select_effect_nodes_follow_settings() -> void:
	var s := _song_select()
	await _check_context("song_select", s)


func test_gameplay_effect_nodes_follow_settings() -> void:
	var gp := _gameplay()
	await _check_context("gameplay", gp)


func test_gameplay_snow_bursts_and_shake_values() -> void:
	var gp := _gameplay()
	await get_tree().process_frame
	var arena := _find(gp, "Arena")
	var fx := _find(gp, "FxLayer")
	var notes := _find(gp, "HighwayNotes")
	assert_object(arena).is_not_null()
	assert_object(fx).is_not_null()
	assert_object(notes).is_not_null()
	assert_int(int(arena.effect_counts()["snow"])).is_equal(80)
	var f: Dictionary = fx.effect_counts()
	assert_array([f["perfect_amount"], f["good_amount"], f["miss_amount"]]).is_equal([24, 10, 6])
	assert_bool(f["shake"]).is_true()
	assert_bool(notes.effect_counts()["halos"]).is_true()
	_apply(true, false)
	assert_int(int(arena.effect_counts()["snow"])).is_equal(24)
	f = fx.effect_counts()
	assert_array([f["perfect_amount"], f["good_amount"], f["miss_amount"]]).is_equal([8, 4, 0])
	assert_bool(f["shake"]).override_failure_message("shake is off only under Reduce motion").is_true()
	assert_bool(notes.effect_counts()["halos"]).is_false()
	assert_bool(notes.effect_counts()["halo_ring"]).is_true()
	_apply(false, true)
	assert_bool(fx.effect_counts()["shake"]).is_false()
	assert_bool(arena.effect_counts()["snow_frozen"]).is_true()
	_apply(false, false)
	assert_int(int(arena.effect_counts()["snow"])).is_equal(80)
	assert_bool(fx.effect_counts()["shake"]).is_true()


func test_results_effect_nodes_follow_settings() -> void:
	var r := _results()
	await _check_context("results", r)


func test_results_screen_has_one_focus_marker() -> void:
	var r := _results()
	await get_tree().process_frame
	assert_int(r.find_children("*", "FocusMarker", true, false).size()).is_equal(1)
	assert_object(r.focus_marker).is_not_null()


# 02.2-27 (gap G2): the Background style switches the running dive's arena through the effect
# contract; Low effects / Reduce motion still apply on top of Calm; the board is untouched.
func test_gameplay_background_style_switches_live() -> void:
	var gp := _gameplay()
	await get_tree().process_frame
	var arena := _find(gp, "Arena")
	var notes := _find(gp, "HighwayNotes")
	var highway := _find(gp, "Highway")
	assert_object(arena).is_not_null()
	var board_living := [notes.effect_counts().duplicate(true), highway.effect_counts().duplicate(true)]
	assert_str(arena.effect_counts()["style"]).is_equal("living")
	assert_bool(arena.effect_counts()["creature"]).is_true()
	Settings.background_style = Settings.BACKGROUND_CALM
	Settings.settings_changed.emit()
	var c: Dictionary = arena.effect_counts()
	assert_str(c["style"]).is_equal("calm")
	assert_bool(c["creature"]).is_false()
	assert_bool(c["wall_scroll"]).is_false()
	assert_bool(c["glitch"]).is_false()
	assert_int(int(c["snow"])).is_equal(24)
	assert_array([notes.effect_counts(), highway.effect_counts()]).is_equal(board_living)
	_apply(true, false)
	c = arena.effect_counts()
	assert_int(int(c["rings"])).is_equal(6)
	assert_bool(c["colony_glow"]).is_false()
	_apply(false, true)
	assert_bool(arena.effect_counts()["snow_frozen"]).is_true()
	_apply(false, false)
	Settings.background_style = Settings.BACKGROUND_LIVING
	Settings.settings_changed.emit()
	assert_str(arena.effect_counts()["style"]).is_equal("living")
	assert_int(int(arena.effect_counts()["snow"])).is_equal(80)
