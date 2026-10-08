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
static var pending_practice: bool = false

## Practice Dive: No-Fail forced on for this run only (never written to Settings).
var practice: bool = false
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
var visor: VisorFrame
var visor_hud: VisorHud
var streak_counter: StreakCounter
var visor_brackets: VisorBrackets
var feedback: Feedback
var fail_screen: FailScreen
## Last finished-dive record outcome {eligible, new_record, previous_depth, best_depth}.
var record_info: Dictionary = {}
var results: ResultsScreen
var pause_menu: PauseMenu
var debug_overlay: DebugOverlay

var _run_root: Control
var _autoplay_player: Autoplay
var _fail_tween: Tween
var _end_time: float = 0.0


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Palette.load_theme()
	var c := pending_chart if pending_chart != null else TestCharts.hand_chart()
	var a := pending_autoplay
	pending_chart = null
	pending_autoplay = false
	practice = pending_practice
	pending_practice = false
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
	UiLayout.fill_rect(_run_root)
	_run_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_run_root)
	if chart.audio_stream == null:
		_show_audio_error()
		return
	var cfg := JudgeConfig.new()
	judge = InputJudge.new(chart, cfg)
	score = HullScore.new(cfg)
	score.no_fail = Settings.no_fail or practice
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
	UiLayout.fill_rect(highway)
	highway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_root.add_child(highway)
	highway.setup(chart, conductor, cfg)
	lane_input.lane_pressed.connect(highway.on_lane_pressed)
	judge.judged.connect(highway.on_judged)
	judge.stray.connect(highway.on_stray)
	judge.sustain_end.connect(highway.on_sustain_end)
	feedback = Feedback.new()
	feedback.nudge_target = _run_root
	_run_root.add_child(feedback)
	feedback.connect_judge(judge)
	visor = VisorFrame.new()  # below the HUD so HUD contrast is untouched
	_run_root.add_child(visor)
	visor_hud = VisorHud.new()  # recording-frame instruments: above the lens, below the HUD
	_run_root.add_child(visor_hud)
	visor_hud.bind(score)
	judge.judged.connect(_on_judged_glitch)
	score.hull_changed.connect(_on_hull_glitch)
	hud = Hud.new()
	_run_root.add_child(hud)
	hud.bind(score)
	hud.set_autoplay(autoplay_used)
	streak_counter = StreakCounter.new()
	_run_root.add_child(streak_counter)
	streak_counter.bind(score)
	visor_brackets = VisorBrackets.new()
	_run_root.add_child(visor_brackets)
	_autoplay_player = Autoplay.new(chart, judge) if autoplay else null
	_end_time = 0.0
	for n in chart.notes:
		_end_time = maxf(_end_time, float(n["time"]) + float(n["duration"]))
	visor_hud.setup_timeline(conductor, chart.tempo_map, song_length(chart, _end_time))
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


## Timeline length: the audio length when known, else the last note end.
static func song_length(c: ChartData, last_note_end: float) -> float:
	var l := 0.0
	if c.audio_stream != null:
		l = c.audio_stream.get_length()
	return l if l > 0.0 else last_note_end


func _on_judged_glitch(_lane: int, _idx: int, judgment: int, _err: float) -> void:
	if judgment == InputJudge.Judgment.MISS and visor != null:
		visor.trigger_glitch()


func _on_hull_glitch(_value: float, delta: float) -> void:
	if delta < 0.0 and visor != null:
		visor.trigger_glitch()


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
	# The ONLY place records are written. Failed dives never reach here (see _on_failed).
	var store := ScoreStore.new()
	store.load()
	var eligible := ScoreStore.is_eligible(autoplay_used, score.no_fail, practice)
	var acc := ScoreStore.accuracy(score.perfect_count, score.good_count, score.miss_count)
	var res := store.submit(chart.id, score.depth(), acc, score.max_combo, eligible,
		Time.get_date_string_from_system())
	var prev: Dictionary = res["previous"]
	var best := store.best(chart.id)
	record_info = {
		"eligible": eligible,
		"new_record": res["new_record"],
		"previous_depth": float(prev["depth"]) if not prev.is_empty() else -1.0,
		"best_depth": float(best["depth"]) if not best.is_empty() else -1.0,
	}
	results = ResultsScreen.new()
	_run_root.add_child(results)
	results.setup(score, autoplay_used, record_info, practice)
	results.retry_pressed.connect(_on_retry)
	results.menu_pressed.connect(go_to_menu)


func _on_failed() -> void:
	state = State.FAILED
	conductor.stop()  # audio stops immediately
	lane_input.enabled = false
	fail_screen = FailScreen.new()
	_run_root.add_child(fail_screen)
	# Read-only: failed dives never update records.
	var fail_store := ScoreStore.new()
	fail_store.load()
	var saved := fail_store.best(chart.id)
	fail_screen.setup(score.depth(), score.max_combo,
		float(saved["depth"]) if not saved.is_empty() else -1.0)
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
