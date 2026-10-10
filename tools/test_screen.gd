extends RefCounted
## DEV-ONLY: picks the monitor for windowed test/tool launches (tools/* is excluded from export).
## The user asked (2026-10-10) for every windowed test launch to open on the SECOND monitor so it
## does not disturb the main one. Override with the env var UNDERTOW_TEST_SCREEN=primary|secondary
## (default secondary). With a single monitor the primary is used.
## tools/playtest/run_all.ps1 already places the harness window with Godot's --position; scripts
## started directly with `godot --path . -s <tool>.gd` call move_window() themselves.
## Usage: const TestScreen := preload("res://tools/test_screen.gd"); TestScreen.move_window()


## Index of the screen tests should use.
static func pick() -> int:
	var primary := DisplayServer.get_primary_screen()
	var want := OS.get_environment("UNDERTOW_TEST_SCREEN").strip_edges().to_lower()
	if want == "primary":
		return primary
	for i in DisplayServer.get_screen_count():
		if i != primary:
			return i
	return primary


## Moves the main window onto the test screen (centred, windowed size kept). No-op when headless.
static func move_window() -> int:
	if DisplayServer.get_name() == "headless":
		return -1
	var scr := pick()
	if DisplayServer.window_get_current_screen() != scr:
		DisplayServer.window_set_current_screen(scr)
	var origin := DisplayServer.screen_get_position(scr)
	var ssize := DisplayServer.screen_get_size(scr)
	var wsize := DisplayServer.window_get_size()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_position(origin + (ssize - wsize) / 2)
	return scr
