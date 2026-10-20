class_name DebugOverlay
extends Control
## F3 timing overlay (D-29): song_time, raw playback position, time_since_last_mix, cached
## output latency, offsets, fps, a 320x96 song_time-per-frame graph and the last 20 hit errors.
## Hidden by default and unavailable in release builds. During an online match (04-16) five
## NetDebugRows lines (RTT, offset, horizon, late inputs, skew, late landings, packets) sit under
## the timing block in a second Label at y 430; offline that label is empty and hidden.

const PANEL_SIZE := Vector2(360.0, 580.0)  # 420 + 5 net rows (04-UI-SPEC 11.8)
const NET_ROWS_Y := 430.0  # under the hit-error rows, so the graph never moves
const GRAPH_SIZE := Vector2(320.0, 96.0)
const GRAPH_SAMPLES := 160
const GRAPH_MAX_MS := 33.0
const MAX_ERRORS := 20

var conductor: Conductor
var _errors: Array[float] = []  # ms, positive = late
var _graph := PackedFloat32Array()
var _prev_song_time: float = 0.0
var _label: Label
var _net_label: Label
var _graph_origin := Vector2.ZERO
## Test seam: the session to read net rows from. null = the /root/NetSession autoload.
var net_session: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	size = PANEL_SIZE
	position = Vector2((Highway.SCREEN_W - PANEL_SIZE.x) * 0.5, 32.0)
	_graph.resize(GRAPH_SAMPLES)
	_graph.fill(0.0)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	_label.add_theme_color_override("font_color", Palette.TEXT_MID)
	_label.position = Vector2(Palette.SP_SM, Palette.SP_SM)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_net_label = Label.new()
	_net_label.name = "NetRows"
	_net_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	_net_label.add_theme_color_override("font_color", Palette.TEXT_MID)
	_net_label.position = Vector2(Palette.SP_SM, NET_ROWS_Y)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_label.visible = false
	add_child(_net_label)


func setup(p_conductor: Conductor, judge: InputJudge) -> void:
	conductor = p_conductor
	judge.judged.connect(_on_judged)


func _on_judged(_lane: int, _idx: int, judgment: int, error_s: float) -> void:
	if judgment == InputJudge.Judgment.MISS:
		return
	_errors.append(error_s * 1000.0)
	while _errors.size() > MAX_ERRORS:
		_errors.pop_front()


func recent_errors() -> Array[float]:
	return _errors


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"debug_overlay"):
		return
	if not OS.is_debug_build():
		return
	visible = not visible


func _process(_delta: float) -> void:
	if conductor == null:
		return
	var st := conductor.song_time()
	_graph.remove_at(0)
	_graph.append(clampf((st - _prev_song_time) * 1000.0, 0.0, GRAPH_MAX_MS))
	_prev_song_time = st
	if not visible:
		return
	_label.text = "song_time   %9.4f\nraw pos     %9.4f\nsince mix   %9.4f\nlatency     %9.4f\noffsets a/v %+.0f / %+.0f ms\nfps         %d" % [
		st, conductor.raw_position(), AudioServer.get_time_since_last_mix(), conductor.output_latency(),
		Settings.audio_offset * 1000.0, Settings.visual_offset * 1000.0, Engine.get_frames_per_second()]
	_graph_origin = Vector2(Palette.SP_MD, 150.0)
	refresh_net_rows()
	queue_redraw()


## The session to read when a match is active, else null (offline, lobby only, or no autoload).
func _active_session() -> Node:
	var s: Node = net_session
	if s == null and is_inside_tree():
		s = get_node_or_null(^"/root/NetSession")
	if s == null or not s.has_method("pending_match") or not s.has_method("debug_stats"):
		return null
	var m: Variant = s.call("pending_match")
	if not (m is Dictionary) or (m as Dictionary).is_empty():
		return null
	return s


## Fills the five net rows during an online match; empty and hidden otherwise.
func refresh_net_rows() -> void:
	var s := _active_session()
	if s == null:
		_net_label.text = ""
		_net_label.visible = false
		return
	var stats: Variant = s.call("debug_stats")
	_net_label.text = NetDebugRows.format(stats if stats is Dictionary else {})
	_net_label.visible = true


## Timing block text (tests).
func timing_text() -> String:
	return _label.text


## Net rows text ("" offline) (tests).
func net_text() -> String:
	return _net_label.text if _net_label.visible else ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.alpha(Palette.ABYSS_900, 0.7))
	if _net_label != null and _net_label.visible:
		# The net lines run wider than the 360 px panel; extend the shade behind them only.
		var nw := _net_label.get_combined_minimum_size().x + Palette.SP_SM * 2.0
		if nw > size.x:
			draw_rect(Rect2(size.x, NET_ROWS_Y - Palette.SP_SM, nw - size.x, size.y - NET_ROWS_Y + Palette.SP_SM),
				Palette.alpha(Palette.ABYSS_900, 0.7))
	draw_rect(Rect2(_graph_origin, GRAPH_SIZE), Palette.ABYSS_500, false, 1.0)
	var step := GRAPH_SIZE.x / float(GRAPH_SAMPLES - 1)
	var prev := Vector2.ZERO
	for i in range(GRAPH_SAMPLES):
		var y := _graph_origin.y + GRAPH_SIZE.y * (1.0 - _graph[i] / GRAPH_MAX_MS)
		var p := Vector2(_graph_origin.x + i * step, y)
		if i > 0:
			draw_line(prev, p, Palette.SONAR, 1.5)
		prev = p
	var font := Palette.font()
	var y0 := _graph_origin.y + GRAPH_SIZE.y + 24.0
	var line := ""
	for i in range(_errors.size()):
		line += "%+.0f " % _errors[i]
		if i % 5 == 4 or i == _errors.size() - 1:
			draw_string(font, Vector2(Palette.SP_MD, y0), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, Palette.SIZE_LABEL, Palette.TEXT_MID)
			y0 += 24.0
			line = ""
