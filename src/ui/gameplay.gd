class_name Gameplay
extends Control
## Solo screen controller. Wires Conductor, LaneInput, InputJudge, HullScore, Highway, Hud,
## Feedback and SfxPool, and owns fail / results and the F4 autoplay restart (D-28).
## Every run lives under one `_run_root` node that is freed on restart, so a restart is a clean
## rebuild with no stale signal connections.

enum State { RUNNING, FAILED, DONE, ERROR }

const MENU_SCENE := "res://scenes/main_menu.tscn"
const FALLBACK_SCENE := "res://scenes/skeleton.tscn"
const LEAD_IN_BEATS := 2
const END_PAD_SEC := 0.5
const ERROR_RETURN_SEC := 3.0
const AUDIO_ERROR := "Song audio could not be loaded. Reinstall the game files or choose another song."

## Launch parameters set by the menu before changing scene.
static var pending_chart: ChartData
static var pending_autoplay: bool = false

var state: State = State.RUNNING
var chart: ChartData
var autoplay: bool = false
var autoplay_used: bool = false
var judge: InputJudge
var score: HullScore
var conductor: Conductor
var lane_input: LaneInput
var highway: Highway
var hud: Hud
var feedback: Feedback
var fail_screen: FailScreen
var results: ResultsScreen
var pause_menu: PauseMenu
var debug_overlay: DebugOverlay

var _run_root: Control
var _autoplay_player: Autoplay
var _fail_tween: Tween
var _end_time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Palette.load_theme()
	var c := pending_chart if pending_chart != null else TestCharts.hand_chart()
	var a := pending_autoplay
	pending_chart = null
	pending_autoplay = false
	start(c, a)


## Build a fresh run. Tears down any previous one first.
func start(p_chart: ChartData, p_autoplay: bool) -> void:
	_teardown()
	chart = p_chart
	autoplay = p_autoplay
	autoplay_used = autoplay_used or p_autoplay
	state = State.RUNNING
	fail_screen = null
	results = null
	_run_root = Control.new()
	_run_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_run_root)
	if chart.audio_stream == null:
		_show_audio_error()
		return
	var cfg := JudgeConfig.new()
	judge = InputJudge.new(chart, cfg)
	score = HullScore.new(cfg)
	score.no_fail = Settings.no_fail
	score.connect_judge(judge)
	score.failed.connect(_on_failed)
	conductor = Conductor.new()
	conductor.tempo_map = chart.tempo_map
	_run_root.add_child(conductor)
	lane_input = LaneInput.new()
	_run_root.add_child(lane_input)
	lane_input.setup(conductor, judge)
	lane_input.enabled = not autoplay  # autoplay presses for the player
	highway = Highway.new()
	highway.set_anchors_preset(Control.PRESET_FULL_RECT)
	highway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_root.add_child(highway)
	highway.setup(chart, conductor)
	judge.judged.connect(highway.on_judged)
	judge.stray.connect(highway.on_stray)
	judge.sustain_end.connect(highway.on_sustain_end)
	feedback = Feedback.new()
	feedback.nudge_target = _run_root
	_run_root.add_child(feedback)
	feedback.connect_judge(judge)
	hud = Hud.new()
	_run_root.add_child(hud)
	hud.bind(score)
	hud.set_autoplay(autoplay_used)
	_autoplay_player = Autoplay.new(chart, judge) if autoplay else null
	_end_time = 0.0
	for n in chart.notes:
		_end_time = maxf(_end_time, float(n["time"]) + float(n["duration"]))
	var bpm := 120.0
	if not chart.tempo_map.is_empty():
		bpm = float(chart.tempo_map[0]["bpm"])
	conductor.begin(chart.audio_stream, LEAD_IN_BEATS * 60.0 / bpm)
	_on_run_built()


func _on_run_built() -> void:
	debug_overlay = DebugOverlay.new()
	_run_root.add_child(debug_overlay)
	debug_overlay.setup(conductor, judge)
	pause_menu = PauseMenu.new()
	_run_root.add_child(pause_menu)
	pause_menu.setup(conductor, lane_input, score)
	pause_menu.restore_input = not autoplay
	pause_menu.restart_confirmed.connect(func() -> void: call_deferred("restart", false))
	pause_menu.menu_confirmed.connect(go_to_menu)


func _teardown() -> void:
	if _fail_tween != null and _fail_tween.is_valid():
		_fail_tween.kill()
	_fail_tween = null
	if _run_root == null:
		return
	if conductor != null and is_instance_valid(conductor):
		conductor.stop()
	remove_child(_run_root)
	_run_root.queue_free()
	_run_root = null
	conductor = null
	lane_input = null
	pause_menu = null
	debug_overlay = null


func is_done() -> bool:
	return state != State.RUNNING


func _process(_delta: float) -> void:
	if state != State.RUNNING or conductor == null:
		return
	if conductor.is_paused():
		return
	var t := conductor.song_time()
	if _autoplay_player != null:
		_autoplay_player.update(t)  # exact note times, never the frame time (D-28)
	judge.tick(t)
	if state == State.RUNNING and judge.is_finished() and t >= _end_time + END_PAD_SEC:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"pause") and state == State.RUNNING and pause_menu != null 			and not pause_menu.is_open() and not pause_menu.is_counting_down():
		get_viewport().set_input_as_handled()
		pause_menu.open()
		return
	if event.is_action_pressed(&"debug_autoplay"):
		get_viewport().set_input_as_handled()
		restart(true)


## Restart the current chart from the beginning, optionally with autoplay on (F4).
func restart(with_autoplay: bool = false) -> void:
	var c := chart
	var a := autoplay or with_autoplay
	if a and not autoplay_used:
		autoplay_used = true
	start(c, a)


func _finish() -> void:
	state = State.DONE
	lane_input.enabled = false
	results = ResultsScreen.new()
	_run_root.add_child(results)
	results.setup(score, autoplay_used)
	results.retry_pressed.connect(_on_retry)
	results.menu_pressed.connect(go_to_menu)


func _on_failed() -> void:
	state = State.FAILED
	conductor.stop()  # audio stops immediately
	lane_input.enabled = false
	fail_screen = FailScreen.new()
	_run_root.add_child(fail_screen)
	fail_screen.setup(score.depth())
	fail_screen.retry_pressed.connect(_on_retry)
	fail_screen.menu_pressed.connect(go_to_menu)
	fail_screen.play(FailScreen.SQUASH_SEC)
	var pivot := Vector2(Highway.SCREEN_W * 0.5, Highway.HULL_Y)
	for ctl in [highway, feedback]:
		(ctl as Control).pivot_offset = pivot
	var tw := create_tween().set_parallel(true)
	_fail_tween = tw
	if Settings.reduce_motion:
		tw.tween_property(highway, "modulate:a", 0.0, FailScreen.SQUASH_SEC)
		tw.tween_property(feedback, "modulate:a", 0.0, FailScreen.SQUASH_SEC)
	else:
		tw.tween_property(highway, "scale:y", 0.0, FailScreen.SQUASH_SEC)
		tw.tween_property(feedback, "scale:y", 0.0, FailScreen.SQUASH_SEC)


func _on_retry() -> void:
	# Deferred: the pressed signal comes from a node inside the run being torn down.
	call_deferred("restart", false)


func _show_audio_error() -> void:
	state = State.ERROR
	var l := Label.new()
	l.text = AUDIO_ERROR
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.custom_minimum_size = Vector2(900.0, 0.0)
	l.position = Vector2(510.0, 500.0)
	l.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
	_run_root.add_child(l)
	get_tree().create_timer(ERROR_RETURN_SEC).timeout.connect(go_to_menu)


func go_to_menu() -> void:
	var target := MENU_SCENE if ResourceLoader.exists(MENU_SCENE) else FALLBACK_SCENE
	get_tree().change_scene_to_file(target)
