class_name UiLayout
extends RefCounted
## Layout helpers shared by overlays.


## Fill the parent rect with explicit anchors 0..1 and zero offsets. Unlike
## set_anchors_preset(PRESET_FULL_RECT) (keep_offsets=false), this never recomputes offsets from
## the node's current rect, which is 0x0 before the first layout pass and left the overlays
## collapsed (playtest gap 1).
static func fill_rect(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
