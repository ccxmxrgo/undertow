class_name HighwayNotes
extends Control
## Gem layer of the board (02.2 UI-SPEC 7.4 rows 9..11): gems, missed remnants and lane
## numbers, drawn ABOVE FxLayer and Feedback so bursts and judgment text never cover an
## upcoming note. All state lives in Highway (the surface layer and state owner); this node
## only calls highway.draw_notes_into(self). Ready-gem halos are additive, so they go into
## the "Halos" child, which carries the shared additive material and show_behind_parent:
## Godot draws children after their parent, so without that flag the halos would be added
## on top of the gem cores and wash them out.

## Additive halo layer; delegates its drawing to the owning HighwayNotes' highway.
class HaloLayer extends Node2D:
	var owner_notes: HighwayNotes

	func _draw() -> void:
		if owner_notes != null and owner_notes.highway != null:
			owner_notes.highway.draw_halos_into(self)


var highway: Highway
var halos: HaloLayer


func _init() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	halos = HaloLayer.new()
	halos.name = "Halos"
	halos.owner_notes = self
	halos.show_behind_parent = true
	halos.material = UiKit.additive_material()
	add_child(halos)


func bind(p_highway: Highway) -> void:
	highway = p_highway


func _process(_delta: float) -> void:
	if highway == null:
		return
	queue_redraw()
	halos.queue_redraw()


func _draw() -> void:
	if highway != null:
		highway.draw_notes_into(self)
