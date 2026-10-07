extends Node
## Playtest bootstrap. Usage (windowed, real audio):
##   godot --path . res://tools/playtest/playtest.tscn -- <scenario>
## Adds a persistent driver under the root (it survives scene changes) and gets out of the way.
## Scenarios: a b c d e f g h i layout drift. Results: build/playtest/<scenario>.json + PNG screenshots.


func _ready() -> void:
	var script := load("res://tools/playtest/playtest_driver.gd") as GDScript
	if script == null or not script.can_instantiate():
		push_error("playtest driver failed to compile")
		get_tree().quit(2)
		return
	var driver: Node = script.new()
	driver.name = "PlaytestDriver"
	get_tree().root.add_child.call_deferred(driver)
