extends SceneTree
## Regenerates res://ui/undertow_theme.tres from the Palette tokens (UiKit.build_theme).
## Run after changing a token or a UiKit style, then commit the .tres:
##   godot --headless --path . -s res://tools/make_theme.gd
## tests/test_ui_components.gd fails while the saved theme is out of sync (Pitfall 3).


func _initialize() -> void:
	var theme := UiKit.build_theme(false)
	var err := ResourceSaver.save(theme, Palette.THEME_PATH)
	if err != OK:
		push_error("make_theme: could not save %s (error %d)" % [Palette.THEME_PATH, err])
		quit(1)
		return
	print("make_theme: wrote %s" % Palette.THEME_PATH)
	quit(0)
