class_name InkCloudLayer
extends Control
## Ink Cloud / Silt band (03-UI-SPEC 7.4, PAY-04, D-13): an opaque ABYSS_900 polygon over the
## lane area (f -2..+2) for depth d in [ink_depth_bottom, payloads.ink_top_depth()], built from
## Trench.point corners (never hard-coded pixels). It sits in Gameplay's board_root ABOVE
## HighwayNotes / Feedback (order set by 03-14), so gems, sustains, bursts and judgment popups
## inside the band are hidden; InkTopLayer redraws the hit line, receptors and lane numbers
## above it. Opacity = PayloadStack.ink_amount (1-beat beat-locked fade in every mode). Top
## edge: Full = 6 overlapping glow sprites in ABYSS_900 (normal blend) drifting +/-12 px over
## 4 s; Low effects = flat band + 1 px TEXT_LO 35% edge line; Reduce motion = static feather.
## Reads the highway's state only; decides nothing (D-28). Board layer: exempt from the HUD
## keep-out scan, like HighwayNotes.

const FEATHER_SPRITES := 6
const FEATHER_PX := 32.0
const FEATHER_DRIFT_PX := 12.0
const FEATHER_PERIOD_SEC := 4.0
const EDGE_LINE_ALPHA := 0.35
const EDGE_LINE_W := 1.0
const BAND_F := 2.0

var highway: Highway
var _poly := PackedVector2Array()
var _dbg_band := false
var _dbg_feathers := 0
var _dbg_edge := false
var _ink_shown := false


func _init() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poly.resize(4)


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(p_highway: Highway) -> void:
	highway = p_highway
	queue_redraw()


## Effect contract (UiKit.register_fx): the edge style follows Low effects / Reduce motion.
func apply_effect_settings() -> void:
	queue_redraw()


func effect_counts() -> Dictionary:
	var low := UiKit.low_effects()
	return {"feather": not low, "edge_line": low, "drift": not UiKit.reduce_motion() and not low}


## Band opacity 0..1 this frame (PayloadStack.ink_amount at the board's visual time).
func band_alpha() -> float:
	if highway == null or highway.payloads == null:
		return 0.0
	return clampf(highway.payloads.ink_amount(highway._vt), 0.0, 1.0)


## Band corners: bottom-left, bottom-right, top-right, top-left (Trench.point space).
func band_polygon() -> PackedVector2Array:
	var bottom := Trench.D_MIN
	var top := 0.35
	if highway != null:
		if highway.vcfg != null:
			bottom = highway.vcfg.ink_depth_bottom
			top = highway.vcfg.ink_depth_top
		if highway.payloads != null:
			top = highway.payloads.ink_top_depth(highway._vt)
	return PackedVector2Array([
		Trench.point(-BAND_F, bottom), Trench.point(BAND_F, bottom),
		Trench.point(BAND_F, top), Trench.point(-BAND_F, top),
	])


## Sideways drift of feather sprite i at time t_sec (0 under Reduce motion or Low effects).
func feather_offset(t_sec: float, i: int) -> float:
	if UiKit.reduce_motion() or UiKit.low_effects():
		return 0.0
	return FEATHER_DRIFT_PX * sin(TAU * t_sec / FEATHER_PERIOD_SEC + float(i) * 1.7)


func debug_state() -> Dictionary:
	return {"band_drawn": _dbg_band, "feathers_drawn": _dbg_feathers, "edge_line_drawn": _dbg_edge, "alpha": band_alpha()}


func _process(_delta: float) -> void:
	# Redraw only while ink is visible, plus one frame to clear it (WR-10).
	if highway == null:
		return
	var on := band_alpha() > 0.0
	if on or _ink_shown:
		queue_redraw()
	_ink_shown = on


func _draw() -> void:
	_dbg_band = false
	_dbg_feathers = 0
	_dbg_edge = false
	var a := band_alpha()
	if a <= 0.0:
		return
	_poly = band_polygon()
	draw_colored_polygon(_poly, Palette.alpha(Palette.ABYSS_900, a))
	_dbg_band = true
	var tl := _poly[3]
	var tr := _poly[2]
	if UiKit.low_effects():
		draw_line(tl, tr, Palette.alpha(Palette.TEXT_LO, EDGE_LINE_ALPHA * a), EDGE_LINE_W)
		_dbg_edge = true
		return
	# Feather: soft dark sprites centred on the top edge, reaching FEATHER_PX above it.
	var t_sec := Time.get_ticks_msec() / 1000.0
	var span := tr.x - tl.x
	var w := span / float(FEATHER_SPRITES - 1) * 1.6
	var tex := UiKit.glow_texture()
	for i in range(FEATHER_SPRITES):
		var cx := tl.x + span * float(i) / float(FEATHER_SPRITES - 1) + feather_offset(t_sec, i)
		var rect := Rect2(cx - w * 0.5, tl.y - FEATHER_PX, w, FEATHER_PX * 2.0)
		draw_texture_rect(tex, rect, false, Palette.alpha(Palette.ABYSS_900, a))
		_dbg_feathers += 1
