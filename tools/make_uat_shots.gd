extends SceneTree
## Builds the 02.2 UAT screenshot gallery (plan 02.2-25, D-15): copies a fixed list of harness
## screenshots from build/playtest/ into the phase's uat-shots/ folder at 960x540.
##
## Run after the windowed harness (tools/playtest/run_all.ps1 -SkipDrift, or each scenario directly):
##   godot --headless --path . -s res://tools/make_uat_shots.gd
## Works headless: only Image load / resize / save. Exit code 1 if any listed shot is missing.
##
## Phase 03 (plan 03-15): `-- --phase 03` copies the versus set (scenario "versus") into
##   .planning/phases/03-offline-versus/uat-shots instead (NAMES_03). Default behaviour is unchanged.
##
## Matching: the harness names files "<scenario>_<NN>_<shot>.png". A listed name matches a file when
##   - the file stem equals the name (immersion_01_intro_rig_boot), or
##   - the stem ends with "_<name>" (menu_full -> polish_02_menu_full), or
##   - the name starts with the scenario and the stem is "<scenario>_<NN>_<rest>"
##     (songs_art_cover -> songs_10_art_cover).
## When several files match (one shot taken in a loop, or by two scenarios), PREFER picks the scenario,
## then the highest NN wins (the last frame of the loop).

const SRC_DIR := "res://build/playtest"
const OUT_DIR := "res://.planning/phases/02.2-visual-design-overhaul/uat-shots"
const OUT_SIZE := Vector2i(960, 540)

const NAMES: Array[String] = [
	"menu_full", "menu_low", "menu_reduce",
	"songs_art_cover", "songs_generated_cover",
	"gameplay_x1", "gameplay_x4", "gameplay_burst_perfect", "gameplay_miss", "gameplay_trench_beat",
	"hud_streak_0", "hud_streak_25", "hud_streak_100",
	"hud_hull_100", "hud_hull_40", "hud_hull_critical", "hud_section_change",
	"gameplay_scroll_0_5x", "gameplay_scroll_3x", "gameplay_full", "gameplay_low",
	"pause_panel", "implosion", "confirm_dialog", "settings_screen", "calibration_audio",
	"results_first_record", "results_new_record", "results_practice_not_recorded",
	"immersion_01_intro_rig_boot",
	"background_living", "background_calm",
]

## Phase 03 versus readability set (UI-SPEC 11.8), shot by playtest scenario "versus".
const OUT_DIR_03 := "res://.planning/phases/03-offline-versus/uat-shots"
const PAYLOAD_KEYS_03: Array[String] = ["crossed_wires", "ghost_notes", "ink_cloud", "pressure_crack",
	"sonar_jam", "depth_charge"]
const EXTRA_03: Array[String] = [
	"versus_jam_warheads", "versus_ink_sustain", "versus_crossed_mid", "versus_crossed_settled",
	"versus_alert_incoming", "versus_alert_active", "versus_alert_reflected", "versus_alert_absorbed",
	"versus_alert_collision", "versus_panels_bounty_target", "versus_killfeed_4", "versus_duel_live",
	"versus_results_medals", "versus_match_setup", "solo_training_stepper",
]

## Scenario to prefer when a shot exists in more than one scenario.
const PREFER := {"implosion": "polish"}


static func names_03() -> Array[String]:
	var out: Array[String] = []
	for k in PAYLOAD_KEYS_03:
		for v in ["x1_full", "x3_full", "x1_low"]:
			out.append("versus_%s_%s" % [k, v])
	out.append_array(EXTRA_03)
	return out


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var phase := ""
	var pi := args.find("--phase")
	if pi != -1 and pi + 1 < args.size():
		phase = args[pi + 1]
	var names: Array[String] = NAMES
	var out_dir := OUT_DIR
	if phase == "03" or phase == "3":
		names = names_03()
		out_dir = OUT_DIR_03
	var src_abs := ProjectSettings.globalize_path(SRC_DIR)
	var out_abs := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_abs)
	var files: PackedStringArray = DirAccess.get_files_at(src_abs)
	var missing: Array[String] = []
	for n in names:
		var src := _match(n, files)
		if src.is_empty():
			missing.append(n)
			continue
		var img := Image.load_from_file(src_abs.path_join(src))
		if img == null or img.is_empty():
			missing.append(n)
			continue
		if img.get_size() != OUT_SIZE:
			img.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var err := img.save_png(out_abs.path_join(n + ".png"))
		if err != OK:
			missing.append(n)
			continue
		print("UAT_SHOT %s <- %s" % [n, src])
	for n in missing:
		print("UAT_SHOT_MISSING %s" % n)
	print("UAT_SHOTS %d/%d" % [names.size() - missing.size(), names.size()])
	quit(0 if missing.is_empty() else 1)


func _match(n: String, files: PackedStringArray) -> String:
	var hits: Array[String] = []
	for f in files:
		if not f.ends_with(".png"):
			continue
		var stem := f.get_basename()
		if stem == n or stem.ends_with("_" + n):
			hits.append(f)
			continue
		var cut := n.find("_")
		if cut > 0:
			var re := RegEx.create_from_string(
				"^%s_\\d+_%s$" % [n.substr(0, cut), n.substr(cut + 1)])
			if re.search(stem) != null:
				hits.append(f)
	if hits.is_empty():
		return ""
	var pref: String = PREFER.get(n, "")
	if not pref.is_empty():
		var preferred := hits.filter(func(f: String) -> bool: return f.begins_with(pref + "_"))
		if not preferred.is_empty():
			hits.assign(preferred)
	hits.sort_custom(func(x: String, y: String) -> bool: return _index(x) < _index(y))
	return hits[-1]


## The NN of "<scenario>_<NN>_<shot>.png" (0 when absent).
func _index(f: String) -> int:
	var parts := f.split("_")
	return int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 0
