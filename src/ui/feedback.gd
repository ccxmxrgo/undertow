class_name Feedback
extends Control
## Per-judgment text feedback and hit sounds (UI-SPEC 7.3 "Judgment popup" and "Early/late",
## 11 "Judgment pop / rise"). One shared popup per chord: judgments whose note time matches a
## popup that is still alive merge into it (centred on the mean lane x, worst judgment kept,
## timeline not restarted). The early/late readout lives here too (moved from Highway).
## Bursts, rings, the Miss crack and the board shake are FxLayer's job (02.2-10); this node
## draws text only and keeps the SfxPool hit sounds exactly as before.
## Place as a full-rect sibling above FxLayer and below HighwayNotes (gems stay on top).

const MAX_FLOATING := 6

## Popup (UI-SPEC 7.3): Heading 40 Oxanium, 3 px KEYLINE outline, spawn centred (hit.x, 846).
const POP_SIZE := Palette.SIZE_HEADING
const POP_Y := 846.0
const OUTLINE_PX := 6  # draw_string_outline size = both sides: 3 px outline
const POP_SCALE0 := 1.4
const POP_IN := Palette.DUR_FAST  # 120 ms back-out pop
const POP_HOLD_END := 0.40  # pop + 280 ms full opacity
const POP_DIM := 0.60
const POP_LIFE := 0.62  # then 60% and a 220 ms fade while rising
const POP_RISE := 24.0
## Popups closer than this (x) are crowding: the older one skips to its fade.
const CROWD_PX := 150.0
## ...halfway into its fade (about 30% opacity).
const CROWD_SKIP_TO := POP_HOLD_END + 0.5 * (POP_LIFE - POP_HOLD_END)
const POP_TEXT: Array[String] = ["PERFECT", "GOOD", "MISS"]
const GHOST_TEXT := "GHOST"

## Early/late (UI-SPEC 7.3): Label 20 TEXT_MID + KEYLINE outline, 10x12 SONAR triangle.
const INDICATOR_POS := Vector2(960.0, 1004.0)
const ARROW_SIZE := Vector2(10.0, 12.0)
const ARROW_GAP := 10.0
const INDICATOR_HOLD := 0.40
const INDICATOR_FADE := Palette.DUR_FAST

## Created in _ready unless a pool is assigned first or audio_enabled is false.
var sfx: SfxPool
var audio_enabled: bool = true
## Note times group chord popups. Set by Gameplay or taken from the judge in connect_judge.
var chart: ChartData
## Test clock override (microseconds); -1 = real time.
var clock_usec: int = -1
## Overclock active (03-UI-SPEC 5.3): GOOD popups born while true draw in SONAR_PALE; the
## word stays "GOOD". Set by the versus wiring; false (solo behaviour) by default.
var overclock: bool = false
## The highway whose receptors popups sit over (set by Gameplay). Under Crossed Wires the judged
## lane is drawn at the other column, so popups use Highway.receptor_center (WR-04).
var highway: Highway

var _ghost_seq: int = 0

var _floating: Array[Dictionary] = []  # {key, judgment, x_sum, n, born}
var _ind_err_ms: float = 0.0
var _ind_born: int = -10000000
var _ind_on: bool = false
var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


static func judgment_color(judgment: int) -> Color:
	match judgment:
		InputJudge.Judgment.PERFECT:
			return Palette.SONAR_PALE
		InputJudge.Judgment.GOOD:
			return Palette.TEXT_MID
		_:
			return Palette.WARNING_RED


static func popup_font() -> Font:
	return Palette.display_font()


## Popup look at `age` seconds: {scale, alpha, rise}. Reduce motion: no scale, no rise.
static func popup_state(age: float, reduce: bool) -> Dictionary:
	var scale := 1.0
	if not reduce and age < POP_IN:
		var t := clampf(age / POP_IN, 0.0, 1.0)
		var e: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT)
		scale = lerpf(POP_SCALE0, 1.0, float(e))
	var alpha := 1.0
	var rise := 0.0
	if age >= POP_HOLD_END:
		var k := clampf((age - POP_HOLD_END) / (POP_LIFE - POP_HOLD_END), 0.0, 1.0)
		alpha = POP_DIM * (1.0 - k)
		if not reduce:
			rise = POP_RISE * (1.0 - pow(1.0 - k, 2.0))
	return {"scale": scale, "alpha": alpha, "rise": rise}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(self)
	if sfx == null and audio_enabled:
		sfx = SfxPool.new()
		add_child(sfx)


func connect_judge(judge: InputJudge) -> void:
	if chart == null:
		chart = judge._chart
	judge.judged.connect(on_judged)
	judge.stray.connect(on_stray)


func now() -> int:
	return clock_usec if clock_usec >= 0 else Time.get_ticks_usec()


## Screen x of the judged lane's receptor right now (static column without a highway).
func lane_x(lane: int) -> float:
	if highway != null and is_instance_valid(highway):
		return highway.receptor_center(lane).x
	return Trench.hit_point(lane).x


## Popup opacity factor under an Ink Cloud / Silt band (WR-05, V-5): the band above Feedback
## hides the popup centre, but a wide outer-lane popup overhangs the band's trapezoid edge. While
## the popup row (POP_Y) lies inside the inked depth range, popups fade by 1 - ink amount so no
## stray letters show past the band. 1.0 without a highway, payloads or ink.
func ink_fade() -> float:
	if highway == null or not is_instance_valid(highway) or highway.payloads == null:
		return 1.0
	var ink := clampf(highway.payloads.ink_amount(highway._vt), 0.0, 1.0)
	if ink <= 0.0:
		return 1.0
	var bottom := highway.vcfg.ink_depth_bottom if highway.vcfg != null else Trench.D_MIN
	var top := highway.payloads.ink_top_depth(highway._vt)
	var y_near := Trench.point(0.0, bottom).y
	var y_far := Trench.point(0.0, top).y
	if POP_Y < y_far or POP_Y > y_near:
		return 1.0
	return 1.0 - ink


func floating_count() -> int:
	return _floating.size()


## Popup i for tests and the harness: {text, color, x, judgment, born, key}.
func popup(i: int) -> Dictionary:
	var e: Dictionary = _floating[i]
	var j := int(e["judgment"])
	return {"text": _entry_text(e), "color": _entry_color(e), "x": float(e["x_sum"]) / float(e["n"]),
		"judgment": j, "born": int(e["born"]), "key": float(e["key"])}


func _note_key(note_index: int) -> float:
	if chart != null and note_index >= 0 and note_index < chart.notes.size():
		return float(chart.notes[note_index]["time"])
	return -1.0 - float(note_index)  # unknown note: its own popup


func on_judged(lane: int, note_index: int, judgment: int, error_s: float) -> void:
	var t := now()
	var j := clampi(judgment, 0, 2)
	if lane >= 0 and lane < Highway.LANES:
		_add_popup(_note_key(note_index), j, lane_x(lane), t)
	if j == InputJudge.Judgment.MISS:
		_ind_on = false
	else:
		_ind_on = true
		_ind_err_ms = error_s * 1000.0
		_ind_born = t
	if sfx != null:
		sfx.play_judgment(judgment)
	queue_redraw()


## Stray presses show only the receptor press (Highway); no text, no sound change.
func on_stray(_lane: int) -> void:
	pass


## Ghost Note hit (03-UI-SPEC 7.2): a "GHOST" popup in WARNING_RED with the normal 3 px KEYLINE
## and timing. It never merges into a judgment popup. No hit sound here.
func on_ghost_hit(lane: int, _payload_id: int = -1) -> void:
	if lane < 0 or lane >= Highway.LANES:
		return
	_ghost_seq += 1
	_add_popup(-1.0e6 - float(_ghost_seq), InputJudge.Judgment.MISS, lane_x(lane), now(),
		{"text": GHOST_TEXT, "color": Palette.WARNING_RED})
	queue_redraw()


func _entry_text(e: Dictionary) -> String:
	if e.has("text"):
		return str(e["text"])
	return POP_TEXT[int(e["judgment"])]


func _entry_color(e: Dictionary) -> Color:
	if e.has("color"):
		return e["color"]
	var j := int(e["judgment"])
	if j == InputJudge.Judgment.GOOD and bool(e.get("oc", false)):
		return Palette.SONAR_PALE
	return judgment_color(j)


func _add_popup(key: float, j: int, x: float, t: int, extra: Dictionary = {}) -> void:
	expire()
	for e in _floating:
		if float(e["key"]) == key:
			e["judgment"] = maxi(int(e["judgment"]), j)  # MISS > GOOD > PERFECT
			e["x_sum"] = float(e["x_sum"]) + x
			e["n"] = int(e["n"]) + 1
			if overclock:
				e["oc"] = true
			return
	# A new popup next to an older one (same lane area) pushes the older one into its fade,
	# so two words never sit on top of each other at full opacity.
	for e in _floating:
		if absf(float(e["x_sum"]) / float(e["n"]) - x) < CROWD_PX:
			var fade_born := t - int(CROWD_SKIP_TO * 1e6)
			if int(e["born"]) > fade_born:
				e["born"] = fade_born
	while _floating.size() >= MAX_FLOATING:
		_floating.pop_front()  # recycle the oldest
	var entry := {"key": key, "judgment": j, "x_sum": x, "n": 1, "born": t, "oc": overclock}
	entry.merge(extra, true)
	_floating.append(entry)


func expire() -> void:
	var t := now()
	var i := 0
	while i < _floating.size():
		if float(t - int(_floating[i]["born"])) / 1e6 >= POP_LIFE:
			_floating.remove_at(i)
		else:
			i += 1


func indicator_text() -> String:
	return "%s %d MS" % ["EARLY" if _ind_err_ms < 0.0 else "LATE", int(round(absf(_ind_err_ms)))]


func indicator_early() -> bool:
	return _ind_err_ms < 0.0


func indicator_visible() -> bool:
	return Settings.early_late_indicator and _ind_on and indicator_alpha() > 0.0


func indicator_alpha() -> float:
	var age := float(now() - _ind_born) / 1e6
	if age < INDICATOR_HOLD:
		return 1.0
	return clampf(1.0 - (age - INDICATOR_HOLD) / INDICATOR_FADE, 0.0, 1.0)


func _process(_delta: float) -> void:
	expire()
	if not _floating.is_empty() or (_ind_on and indicator_alpha() > 0.0):
		queue_redraw()


func _draw() -> void:
	var t := now()
	var reduce: bool = Settings.reduce_motion
	var font := popup_font()
	var asc := font.get_ascent(POP_SIZE)
	var desc := font.get_descent(POP_SIZE)
	var ink_k := ink_fade()
	for e in _floating:
		var age := float(t - int(e["born"])) / 1e6
		if age >= POP_LIFE:
			continue
		var s := popup_state(age, reduce)
		var j := int(e["judgment"])
		var text := _entry_text(e)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_SIZE).x
		var cx := float(e["x_sum"]) / float(e["n"])
		var cy := POP_Y - float(s["rise"])
		var a: float = float(s["alpha"]) * ink_k
		if a <= 0.0:
			continue
		var pos := Vector2(-w * 0.5, (asc - desc) * 0.5)
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE * float(s["scale"]))
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_SIZE, OUTLINE_PX,
			Palette.alpha(Palette.KEYLINE, Palette.KEYLINE.a * a))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_SIZE, Palette.alpha(_entry_color(e), a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if indicator_visible():
		_draw_early_late()


func _draw_early_late() -> void:
	var a := indicator_alpha()
	var font := Palette.font()
	var size := Palette.SIZE_LABEL
	var txt := indicator_text()
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var total := ARROW_SIZE.x + ARROW_GAP + tw
	var x0 := INDICATOR_POS.x - total * 0.5
	var base := INDICATOR_POS.y
	var ay := base - font.get_ascent(size) * 0.35
	var early := indicator_early()
	var text_x := x0 + ARROW_SIZE.x + ARROW_GAP if early else x0
	var ax := x0 if early else x0 + tw + ARROW_GAP
	var hw := ARROW_SIZE.x
	var hh := ARROW_SIZE.y * 0.5
	if early:  # left-pointing, before the text
		_tri[0] = Vector2(ax, ay)
		_tri[1] = Vector2(ax + hw, ay - hh)
		_tri[2] = Vector2(ax + hw, ay + hh)
	else:  # right-pointing, after the text
		_tri[0] = Vector2(ax + hw, ay)
		_tri[1] = Vector2(ax, ay - hh)
		_tri[2] = Vector2(ax, ay + hh)
	var key := Palette.alpha(Palette.KEYLINE, Palette.KEYLINE.a * a)
	var outline := PackedVector2Array([_tri[0], _tri[1], _tri[2], _tri[0]])
	draw_polyline(outline, key, 4.0, true)
	draw_colored_polygon(_tri, Palette.alpha(Palette.SONAR, a))
	var p := Vector2(text_x, base)
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, OUTLINE_PX, key)
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.alpha(Palette.TEXT_MID, a))
