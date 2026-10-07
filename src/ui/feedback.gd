class_name Feedback
extends Control
## Per-judgment feedback (UI-SPEC feedback table, D-22/D-23): lane flash (+ ring for Perfect,
## X glyph for Miss), floating PERFECT/GOOD/MISS text (pool capped at 6, oldest recycled),
## hit SFX and the Miss screen nudge. Shape and text always accompany color.
## Place as a full-rect sibling above the Highway. Hull bar damage flash lives in Hud.

enum Kind { PERFECT, GOOD, MISS, STRAY }

const MAX_FLOATING := 6
const FLASH_USEC := {Kind.PERFECT: 120000, Kind.GOOD: 120000, Kind.MISS: 160000, Kind.STRAY: 80000}
const RING_USEC := 200000
const FLOAT_USEC := 500000
const FLOAT_RISE := 48.0
const FLOAT_START_OFFSET := 64.0
const FLASH_H := 160.0
const NUDGE_PX := 8.0
const NUDGE_USEC := 100000

## Gameplay root that gets the Miss nudge (optional).
var nudge_target: Control
## Created in _ready unless a pool is assigned first or audio_enabled is false.
var sfx: SfxPool
var audio_enabled: bool = true

var _flashes: Array = [null, null, null, null]  # per lane: {kind, born} or null
var _floating: Array[Dictionary] = []  # {text, color, lane, born}
var _nudging: bool = false
var _nudge_base: Vector2 = Vector2.ZERO
var _nudge_end: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(self)
	if sfx == null and audio_enabled:
		sfx = SfxPool.new()
		add_child(sfx)


func connect_judge(judge: InputJudge) -> void:
	judge.judged.connect(on_judged)
	judge.stray.connect(on_stray)


func floating_count() -> int:
	return _floating.size()


func on_judged(lane: int, _note_index: int, judgment: int, _error_s: float) -> void:
	var now := Time.get_ticks_usec()
	var kind: int
	var text: String
	var color: Color
	match judgment:
		InputJudge.Judgment.PERFECT:
			kind = Kind.PERFECT
			text = "PERFECT"
			color = Palette.ACCENT
		InputJudge.Judgment.GOOD:
			kind = Kind.GOOD
			text = "GOOD"
			color = Palette.TEXT
		_:
			kind = Kind.MISS
			text = "MISS"
			color = Palette.DESTRUCTIVE
	if lane >= 0 and lane < Highway.LANES:
		_flashes[lane] = {"kind": kind, "born": now}
		_spawn_text(text, color, lane, now)
	if sfx != null:
		sfx.play_judgment(judgment)
	if kind == Kind.MISS:
		_start_nudge(now)
	queue_redraw()


func on_stray(lane: int) -> void:
	if lane >= 0 and lane < Highway.LANES:
		_flashes[lane] = {"kind": Kind.STRAY, "born": Time.get_ticks_usec()}
	queue_redraw()


func _spawn_text(text: String, color: Color, lane: int, now: int) -> void:
	while _floating.size() >= MAX_FLOATING:
		_floating.pop_front()  # recycle the oldest
	_floating.append({"text": text, "color": color, "lane": lane, "born": now})


func _start_nudge(now: int) -> void:
	if Settings.reduce_motion or nudge_target == null:
		return
	if not _nudging:
		_nudge_base = nudge_target.position
		_nudging = true
	nudge_target.position = _nudge_base + Vector2(NUDGE_PX, 0.0)
	_nudge_end = now + NUDGE_USEC


func _end_nudge() -> void:
	if _nudging and is_instance_valid(nudge_target):
		nudge_target.position = _nudge_base
	_nudging = false


func _exit_tree() -> void:
	_end_nudge()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _nudging and now >= _nudge_end:
		_end_nudge()
	while not _floating.is_empty() and now - int(_floating[0]["born"]) >= FLOAT_USEC:
		_floating.pop_front()
	var active := not _floating.is_empty()
	for lane in range(Highway.LANES):
		var f = _flashes[lane]
		if f != null:
			if now - int(f["born"]) >= _flash_life(int(f["kind"])):
				_flashes[lane] = null
			else:
				active = true
	if active:
		queue_redraw()


func _flash_life(kind: int) -> int:
	return maxi(int(FLASH_USEC[kind]), RING_USEC if kind == Kind.PERFECT else 0)


func _draw() -> void:
	var now := Time.get_ticks_usec()
	for lane in range(Highway.LANES):
		var f = _flashes[lane]
		if f != null:
			_draw_flash(lane, int(f["kind"]), now - int(f["born"]))
	var font := Palette.bold()
	for e in _floating:
		var t := clampf(float(now - int(e["born"])) / FLOAT_USEC, 0.0, 1.0)
		var rise := FLOAT_RISE * (1.0 - pow(1.0 - t, 2.0))  # ease-out
		var y := Highway.HULL_Y - FLOAT_START_OFFSET - rise
		var col: Color = Palette.alpha(e["color"], 1.0 - t)
		var cx := Highway.lane_center_x(int(e["lane"]))
		draw_string(font, Vector2(cx - 100.0, y), e["text"], HORIZONTAL_ALIGNMENT_CENTER, 200.0, Palette.SIZE_BODY, col)


func _draw_flash(lane: int, kind: int, age: int) -> void:
	var life: int = FLASH_USEC[kind]
	var cx := Highway.lane_center_x(lane)
	var lane_col := Palette.lane_color(lane)
	var rect := Rect2(Highway.lane_left() + lane * Highway.LANE_W, Highway.HULL_Y - FLASH_H, Highway.LANE_W, FLASH_H)
	if age < life:
		var fade := 1.0 - float(age) / life
		match kind:
			Kind.PERFECT:
				draw_rect(rect, Palette.alpha(lane_col, 0.4 * fade))
			Kind.GOOD:
				draw_rect(rect, Palette.alpha(lane_col, 0.2 * fade))
			Kind.MISS:
				draw_rect(rect, Palette.alpha(Palette.DESTRUCTIVE, 0.4 * fade))
			_:
				draw_rect(rect, Palette.alpha(lane_col, 0.25 * fade))
	if kind == Kind.PERFECT and age < RING_USEC:
		var t := float(age) / RING_USEC
		var r := lerpf(NoteShape.SIZE * 0.5, NoteShape.SIZE, t)  # 80 px to 160 px diameter
		draw_arc(Vector2(cx, Highway.HULL_Y), r, 0.0, TAU, 48, Palette.alpha(lane_col, 1.0 - t), 3.0, true)
	elif kind == Kind.MISS and age < life:
		var c := Vector2(cx, Highway.HULL_Y)
		var h := 20.0
		var col := Palette.alpha(Palette.DESTRUCTIVE, 1.0 - float(age) / life)
		draw_line(c + Vector2(-h, -h), c + Vector2(h, h), col, 4.0)
		draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, 4.0)
