class_name TorpedoSocket
extends Control
## Empty torpedo socket on the left console (UI-SPEC 4.14): the Phase 3 home for charged
## torpedoes. Recessed circle, dashed inner ring, faint outer ring. No text, no icon, no
## animation, identical in every effect mode (so it is not an effect node).

const RECT := Rect2(272.0, 928.0, 80.0, 80.0)
const R_OUTER := 36.0
const R_DASH := 30.0
const DASHES := 12
const FILL_ALPHA := 0.90
const DASH_ALPHA := 0.35
const OUTER_ALPHA := 0.20
const ARC_POINTS := 8


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Global rect of the socket (Phase 3 anchors torpedo icons here).
func socket_rect() -> Rect2:
	return RECT


func _draw() -> void:
	var c := RECT.size * 0.5
	draw_circle(c, R_OUTER, Palette.alpha(Palette.ABYSS_900, FILL_ALPHA), true, -1.0, true)
	var step := TAU / DASHES
	var dash_col := Palette.alpha(Palette.TEXT_LO, DASH_ALPHA)
	for i in DASHES:
		var a0 := step * i
		draw_arc(c, R_DASH, a0, a0 + step * 0.5, ARC_POINTS, dash_col, Palette.EDGE_HAIR, true)
	draw_arc(c, R_OUTER, 0.0, TAU, 64, Palette.alpha(Palette.SONAR, OUTER_ALPHA), Palette.EDGE_HAIR, true)
