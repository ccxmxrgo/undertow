class_name VersusHud
extends Control
## Versus view container (03-UI-SPEC 1 render order): a full-screen, non-interactive canvas above
## Hud and below StreakCounter that holds PeriscopeColumn, Killfeed, IncomingAlert, EventBanner,
## EdgeFlash and RewardPopup in that order. It draws nothing itself. keepout_shapes() gathers
## its children's shapes (or their rects) so the note-path keep-out scan sees every element.


func _init() -> void:
	name = "VersusHud"
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func keepout_shapes() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for c in get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		var ctl := c as Control
		if ctl.has_method("keepout_shapes"):
			for s in ctl.call("keepout_shapes"):
				out.append(s)
		else:
			var r := ctl.get_global_rect()
			out.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
				Vector2(r.position.x, r.end.y)]))
	return out
