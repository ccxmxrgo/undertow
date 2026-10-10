extends GdUnitTestSuite
## VIS-01 guardrail: colours come from Palette only. Scans src/ui/**/*.gd for colour
## literals (`Color("`, `Color(<number>`, `Color8(`, named `Color.X` other than
## Color.TRANSPARENT) and scenes/**/*.tscn for any `Color(` value other than neutral
## white/black that differs only in alpha. `Color(token, alpha)` with a token is allowed.

const SCRIPT_ROOT := "res://src/ui"
const SCENE_ROOT := "res://scenes"

## Permanent allow-list (UI-SPEC section 4 intro).
const ALLOW: Array[String] = [
	"res://src/ui/palette.gd",
	"res://src/ui/debug_overlay.gd",
	"res://src/ui/drift_harness.gd",
]

## Files that still hold literals and are waiting for their migration plan.
## Each migration plan removes its file; plan 24 empties this list.
const PENDING_MIGRATION: Array[String] = []

const SCRIPT_PATTERN := "Color\\(\\s*\"|Color\\(\\s*[0-9.]|Color8\\(|Color\\.(?!TRANSPARENT\\b)[A-Z][A-Z_0-9]*\\b"
const SCENE_PATTERN := "Color\\(([^)]*)\\)"

var _script_re: RegEx
var _scene_re: RegEx


func before() -> void:
	_script_re = RegEx.create_from_string(SCRIPT_PATTERN)
	_scene_re = RegEx.create_from_string(SCENE_PATTERN)


func _files(root: String, ext: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for f in dir.get_files():
		if f.get_extension() == ext:
			out.append(root.path_join(f))
	for d in dir.get_directories():
		if d.begins_with("."):
			continue
		_files(root.path_join(d), ext, out)


## True when a script line holds a colour literal (comment lines are ignored).
func _script_line_hits(line: String) -> bool:
	if line.strip_edges().begins_with("#"):
		return false
	return _script_re.search(line) != null


## True when every `Color(...)` on a scene line is neutral white/black differing only in alpha.
func _scene_line_ok(line: String) -> bool:
	for m in _scene_re.search_all(line):
		var parts := m.get_string(1).split(",")
		if parts.size() < 3 or parts.size() > 4:
			return false
		var rgb: Array[float] = []
		for i in 3:
			var s := parts[i].strip_edges()
			if not s.is_valid_float():
				return false
			rgb.append(s.to_float())
		if parts.size() == 4 and not parts[3].strip_edges().is_valid_float():
			return false
		var white := rgb[0] == 1.0 and rgb[1] == 1.0 and rgb[2] == 1.0
		var black := rgb[0] == 0.0 and rgb[1] == 0.0 and rgb[2] == 0.0
		if not (white or black):
			return false
	return true


## path -> Array of "path:line: text" hits for every scanned script.
func _script_hits() -> Dictionary:
	var paths: Array[String] = []
	_files(SCRIPT_ROOT, "gd", paths)
	var out := {}
	for p in paths:
		var hits: Array[String] = []
		var lines := FileAccess.get_file_as_string(p).split("\n")
		for i in lines.size():
			if _script_line_hits(lines[i]):
				hits.append("%s:%d: %s" % [p, i + 1, lines[i].strip_edges()])
		out[p] = hits
	return out


func test_matcher_flags_literals_and_allows_tokens() -> void:
	for bad in ["c = Color(\"123456\")", "Color(0.2, 0.3, 0.4)", "Color(.5, 0, 0)", "Color8(10, 20, 30)",
			"modulate = Color.WHITE", "x = Color.RED * 0.5"]:
		assert_bool(_script_line_hits(bad)).override_failure_message("not flagged: " + bad).is_true()
	for good in ["Color(Palette.SONAR, 0.5)", "Color.TRANSPARENT", "Palette.alpha(Palette.TEXT_HI, 0.3)",
			"# Color(\"123456\") in a comment", "var c: Color = Palette.ABYSS_900"]:
		assert_bool(_script_line_hits(good)).override_failure_message("false positive: " + good).is_false()
	assert_bool(_scene_line_ok("modulate = Color(1, 1, 1, 0)")).is_true()
	assert_bool(_scene_line_ok("color = Color(0, 0, 0, 0.5)")).is_true()
	assert_bool(_scene_line_ok("color = Color(0.2, 0.3, 0.4, 1)")).is_false()
	assert_bool(_scene_line_ok("color = Color(1, 1, 0.9, 1)")).is_false()


func test_no_colour_literals_in_ui_scripts() -> void:
	var hits := _script_hits()
	assert_bool(hits.has("res://src/ui/palette.gd")).override_failure_message("scan did not see palette.gd").is_true()
	var bad: Array[String] = []
	for p: String in hits:
		if p in ALLOW or p in PENDING_MIGRATION:
			continue
		bad.append_array(hits[p])
	assert_array(bad).override_failure_message(
		"Colour literals outside Palette (use Palette tokens):\n" + "\n".join(bad)
	).is_empty()


func test_pending_migration_entries_are_not_stale() -> void:
	var hits := _script_hits()
	var stale: Array[String] = []
	for p in PENDING_MIGRATION:
		if not hits.has(p) or (hits[p] as Array).is_empty():
			stale.append(p)
	assert_array(stale).override_failure_message(
		"Stale pending entry, remove it from PENDING_MIGRATION:\n" + "\n".join(stale)
	).is_empty()


func test_no_colour_literals_in_scenes() -> void:
	var paths: Array[String] = []
	_files(SCENE_ROOT, "tscn", paths)
	var bad: Array[String] = []
	for p in paths:
		var lines := FileAccess.get_file_as_string(p).split("\n")
		for i in lines.size():
			if not _scene_line_ok(lines[i]):
				bad.append("%s:%d: %s" % [p, i + 1, lines[i].strip_edges()])
	assert_array(bad).override_failure_message(
		"Colour values in scenes (set them from Palette in code):\n" + "\n".join(bad)
	).is_empty()


## 02.2-20: overlays restyled in this plan use the Abyssal Cockpit tokens, not the legacy
## aliases (BG, PANEL, DIM, TEXT, ACCENT, DESTRUCTIVE, REC_TEXT) that plan 24 deletes.
const LEGACY_FREE: Array[String] = [
	"res://src/ui/pause_menu.gd",
	"res://src/ui/fail_screen.gd",
	"res://src/ui/confirm_dialog.gd",
	"res://src/ui/goggles_intro.gd",
	"res://src/ui/settings_screen.gd",
	"res://src/ui/step_slider.gd",
	"res://src/ui/rebind_cell.gd",
]
const LEGACY_PATTERN := "Palette\\.(BG|PANEL|DIM|TEXT|ACCENT|DESTRUCTIVE|REC_TEXT)\\b"


func test_restyled_overlays_use_no_legacy_aliases() -> void:
	var re := RegEx.create_from_string(LEGACY_PATTERN)
	var bad: Array[String] = []
	for p in LEGACY_FREE:
		var lines := FileAccess.get_file_as_string(p).split("\n")
		for i in lines.size():
			if not lines[i].strip_edges().begins_with("#") and re.search(lines[i]) != null:
				bad.append("%s:%d: %s" % [p, i + 1, lines[i].strip_edges()])
	assert_array(bad).override_failure_message("Legacy Palette aliases:\n" + "\n".join(bad)).is_empty()
