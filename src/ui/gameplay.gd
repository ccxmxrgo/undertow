class_name Gameplay
extends Control
## Solo screen controller. Wires Conductor, LaneInput, InputJudge, HullScore, Highway,
## HighwayNotes, Hud, Feedback and SfxPool, and owns fail / results and the F4 autoplay restart (D-28).
## Every run lives under one `_run_root` node that is freed on restart, so a restart is a clean
## rebuild with no stale signal connections.

enum State { RUNNING, FAILED, DONE, ERROR }

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"
const FALLBACK_SCENE := "res://scenes/skeleton.tscn"
## Online (04-14): the lobby (04-15) and the Play Online screen (04-11), referenced by path only.
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const ONLINE_MENU_SCENE := "res://scenes/online_menu.tscn"
## Clients show NO HOST SIGNAL after this long without a host packet (UI-SPEC 11.5).
const LINK_WEAK_S := 1.0
const LEAD_IN_BEATS := 3
const QUICK_LEAD_IN_BEATS := 1
const END_PAD_SEC := 0.5
const ERROR_RETURN_SEC := 3.0
const AUDIO_ERROR := "Song audio could not be loaded. Reinstall the game files or choose another song."

## Launch parameters set by the menu before changing scene.
static var pending_chart: ChartData
static var pending_autoplay: bool = false
static var pending_practice: bool = false
## Intro mode for the next run. NOT reset in _ready: test suites set NONE so runs never wait.
static var pending_intro: int = IntroTimeline.Mode.FULL
## WR-02: one-shot, set by the lobby next to pending_chart for an online launch. If the match
## is gone by _ready (an abort arrived during the lobby -> gameplay wipe), the run goes back to
## the lobby instead of falling through to an offline dive with the match chart.
static var pending_online: bool = false

## Solo Dive: No-Fail forced on for this run only (never written to Settings).
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
## Gem layer above Feedback (02.2-08): gems, missed remnants, lane numbers.
var highway_notes: HighwayNotes
## One Control holding Arena, Highway, FxLayer, Feedback, HighwayNotes (in that order): the board
## moves as one on the FxLayer Miss shake; Hud and StreakCounter stay outside it.
var board_root: Control
## Static cockpit consoles and bezels (02.2-12) between BoardRoot and the Hud.
var cockpit_frame: CockpitFrame
var hud: Hud
var arena: Arena
var streak_counter: StreakCounter
var feedback: Feedback
## Board juice between Highway and Feedback (02.2-10): bursts, rings, crack, shake, sparks.
var fx_layer: FxLayer
var fail_screen: FailScreen
## Last finished-dive record outcome {eligible, new_record, previous_depth, best_depth, grade,
## accuracy (D-08, -1 when nothing was judged), offsets (PackedFloat32Array, seconds)}.
var record_info: Dictionary = {}
## Per-hit timing offsets for the results histogram (D-09). Read-only judge listener; attached
## to each run's judge in start(), reset on every (re)start, detached on teardown.
var offset_recorder := HitOffsetRecorder.new()
var results: ResultsScreen
## Versus results (03-12), shown at the song end of a versus match instead of ResultsScreen.
var versus_results: VersusResultsScreen
## The versus launch record (MatchSetup.pending, MODE_VERSUS) or null (solo / Solo Dive).
var match_setup: MatchSetup = null
## Match wiring (03-14) for versus and Solo Dive; null on a plain solo dive.
var versus: VersusController = null
var pause_menu: PauseMenu
var debug_overlay: DebugOverlay
var intro: GogglesIntro
var intro_mode: int = IntroTimeline.Mode.FULL

var _run_root: Control
var _autoplay_player: Autoplay
var _fail_tween: Tween
var _end_time: float = 0.0
var _began: bool = false
var _arena_miss_frame: int = -1
## The autoplay flag this run was launched with (Song Select restores it on the way back).
var _launch_autoplay: bool = false

# --- Online (04-14) ---------------------------------------------------------------------------
## The network session (NetSession autoload). Injectable: tests set it before add_child.
var session: Node = null
## NetSession.pending_match() for an online match; {} offline (every offline path is unchanged).
var online_spec: Dictionary = {}
var start_sync_overlay: StartSyncOverlay
var leave_overlay: LeaveOverlay
var host_left_dialog: HostLeftDialog
## Fire presses forwarded to the controller (tests read it).
var fire_count: int = 0
## Scene change seam (tests): called with the target path instead of ScreenTransition.
var navigate: Callable = Callable()
var _done_reported: bool = false
var _online_over: bool = false
var _link_weak: bool = false
var _waiting_n: int = -1
## seat -> {hull, depth, alive, left} from the last STATUS / IMPLODED / PLAYER_LEFT events.
var _last_status: Dictionary = {}
## WR-02: a scene change ScreenTransition refused (wipe running); retried once it is idle.
var _nav_pending: String = ""
## WR-02: an online launch whose match was gone at _ready; nothing runs, only the way back.
var _launch_lost: bool = false


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Palette.load_theme()
	var c := pending_chart if pending_chart != null else TestCharts.hand_chart()
	var a := pending_autoplay
	_launch_autoplay = a
	pending_chart = null
	pending_autoplay = false
	practice = pending_practice
	pending_practice = false
	# One-shot launch record (T-03-35): always cleared; honoured only for a versus launch that is
	# neither a practice nor an autoplay dive (those never become versus).
	var ms := MatchSetup.pending
	MatchSetup.pending = null
	match_setup = null
	if ms != null and ms.mode == MatchSetup.MODE_VERSUS and not practice and not a:
		match_setup = ms
	var want_online := pending_online
	pending_online = false
	if session == null:
		session = get_node_or_null("/root/NetSession")
	var spec: Dictionary = {}
	if session != null and session.has_method("pending_match"):
		spec = session.call("pending_match")
	if not spec.is_empty():
		# Online (D-07): no goggles intro, no practice / autoplay dive, no MatchSetup.
		online_spec = spec
		match_setup = null
		practice = false
		_connect_session()
		start(c, false, IntroTimeline.Mode.NONE)
		return
	if want_online:
		# WR-02: the match ended before this scene was built: back to the lobby (or Play Online
		# when the session is gone), never an offline dive with the match chart.
		_launch_lost = true
		state = State.ERROR
		chart = c
		var in_lobby := session != null and session.has_method("is_in_lobby") \
			and bool(session.call("is_in_lobby"))
		if in_lobby:
			_go_lobby()
		else:
			_goto(ONLINE_MENU_SCENE if ResourceLoader.exists(ONLINE_MENU_SCENE) else _menu_target())
		return
	start(c, a, pending_intro)


## Build a fresh run. Tears down any previous one first.
func start(p_chart: ChartData, p_autoplay: bool, p_intro: int = pending_intro) -> void:
	_teardown()
	intro_mode = p_intro
	_began = false
	_arena_miss_frame = -1
	intro = null
	chart = p_chart
	autoplay = p_autoplay
	autoplay_used = autoplay_used or p_autoplay
	state = State.RUNNING
	fail_screen = null
	results = null
	versus_results = null
	versus = null
	_run_root = Control.new()
	UiLayout.fill_rect(_run_root)
	_run_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_run_root)
	if chart.audio_stream == null:
		_show_audio_error()
		if is_online() and session != null:
			session.call("report_load_failed")
		return
	var cfg := JudgeConfig.new()
	if is_online():
		# Online (04-13 / 04-10): host or client backend; the session pumps the link per frame.
		versus = VersusController.new()
		_run_root.add_child(versus)
		var spec := online_spec.duplicate()
		var song_len := ProgressTrack.song_length_of(chart)
		spec["song_len"] = song_len
		var host := _is_host()
		if not host and session != null:
			versus.net_send = Callable(session, "send_to_host")
		versus.setup_online(self, chart, cfg, spec)
		if session != null:
			if host:
				session.call("bind_host_match", versus.queue, versus.host_channel,
					chart.notes.size(), song_len)
			else:
				session.call("bind_client_match", versus.remote, versus.client_channel,
					chart.notes.size(), song_len)
		versus.channel.received.connect(_on_net_event)
		judge = versus.human_judge
		score = versus.human_hull
	elif match_setup != null or practice:
		# Versus / Solo Dive (03-14): the human plays through a SubRig. VersusJudge and VersusHull
		# are InputJudge / HullScore subtypes, so the wiring below is shared. The rig already
		# connects hull and judge (no connect_judge here) and forces no_fail (false in versus,
		# true in training); Settings.no_fail is never read (T-03-33).
		versus = VersusController.new()
		_run_root.add_child(versus)
		versus.setup(self, chart, cfg, match_setup,
			MatchSetup.training_reward(Settings.training_payload), autoplay)
		judge = versus.human_judge
		score = versus.human_hull
	else:
		judge = InputJudge.new(chart, cfg)
		score = HullScore.new(cfg)
		score.no_fail = Settings.no_fail or practice
		score.connect_judge(judge)
	offset_recorder.reset()
	offset_recorder.attach(judge)
	if match_setup != null or is_online():
		score.failed.connect(_on_versus_wreck)
	else:
		score.failed.connect(_on_failed)
	conductor = Conductor.new()
	conductor.tempo_map = chart.tempo_map
	_run_root.add_child(conductor)
	lane_input = LaneInput.new()
	_run_root.add_child(lane_input)
	lane_input.setup(conductor, judge)
	lane_input.enabled = false  # enabled by _begin_count_in (T-1.2-09)
	board_root = Control.new()
	board_root.name = "BoardRoot"
	UiLayout.fill_rect(board_root)
	board_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_root.add_child(board_root)
	arena = Arena.new()  # first board child: the world behind the board
	board_root.add_child(arena)
	arena.bind(conductor, chart.tempo_map, chart.id)  # chart id seeds the distant creature
	score.combo_changed.connect(arena.on_combo)
	arena.set_tier(1)
	score.multiplier_changed.connect(arena.set_tier)  # bio pulse gain, MAX fish energy (7.6)
	judge.judged.connect(_on_judged_arena)
	score.hull_changed.connect(_on_hull_arena)
	highway = Highway.new()
	UiLayout.fill_rect(highway)
	highway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_root.add_child(highway)
	highway.setup(chart, conductor, cfg)
	# Streak tiers (UI-SPEC 7.6): the surface follows the score multiplier; every run starts at x1.
	highway.set_tier(1)
	score.multiplier_changed.connect(highway.set_tier)
	# Hold the board's notes and beat pulse until the lead-in starts (WR-03).
	highway.notes_enabled = false
	arena.beat_live = false
	lane_input.lane_pressed.connect(highway.on_lane_pressed)
	judge.judged.connect(highway.on_judged)
	judge.stray.connect(highway.on_stray)
	judge.sustain_end.connect(highway.on_sustain_end)
	fx_layer = FxLayer.new()
	board_root.add_child(fx_layer)
	fx_layer.bind(highway, board_root)  # the Miss shake moves the board only; the HUD stays still
	judge.judged.connect(fx_layer.on_judged)
	fx_layer.set_tier(1)
	score.multiplier_changed.connect(fx_layer.set_tier)
	highway.hold_changed.connect(fx_layer.on_sustain_state)
	feedback = Feedback.new()
	feedback.chart = chart  # chord popups group by note time
	feedback.highway = highway  # popups follow the Crossed Wires receptor (WR-04)
	board_root.add_child(feedback)
	feedback.connect_judge(judge)
	highway_notes = HighwayNotes.new()
	board_root.add_child(highway_notes)
	highway_notes.bind(highway)
	cockpit_frame = CockpitFrame.new()  # static frame: above the board, below the HUD
	cockpit_frame.name = "CockpitFrame"
	_run_root.add_child(cockpit_frame)
	hud = Hud.new()
	_run_root.add_child(hud)
	hud.bind(score)
	hud.set_autoplay(autoplay_used)
	hud.setup_song(chart, conductor)  # progress track + section banner (read song_time only)
	judge.judged.connect(hud.on_judged)  # after HullScore: live accuracy reads updated counts
	# Bathymeter scale: all-Perfect estimate (reads JudgeConfig only) and the saved best (or -1).
	hud.set_depth_scale(Bathymeter.estimate_max_depth(chart, cfg))
	var best_store := ScoreStore.new()
	best_store.load()
	var best_rec := best_store.best(chart.id)
	hud.set_record(float(best_rec["depth"]) if not best_rec.is_empty() else -1.0)
	if versus != null:
		versus.bind_views(self)  # ink layers, Hud children, VersusHud (before StreakCounter)
	streak_counter = StreakCounter.new()
	_run_root.add_child(streak_counter)
	streak_counter.bind(score)
	streak_counter.highway = highway  # milestone rail flash
	# Versus / Solo Dive autoplay is the controller's VersusAutoplay (overlay notes, D-28).
	_autoplay_player = Autoplay.new(chart, judge) if autoplay and versus == null else null
	_end_time = 0.0
	for n in chart.notes:
		_end_time = maxf(_end_time, float(n["time"]) + float(n["duration"]))
	_on_run_built()
	if is_online():
		# Online: the conductor stays idle until START (_begin_online(lead)); never the count-in.
		_build_online_overlays()
	elif intro_mode == IntroTimeline.Mode.NONE and online_spec.is_empty():
		_begin_count_in()
	else:
		intro = GogglesIntro.new()
		# Above the streak counter, below the pause menu.
		_run_root.add_child(intro)
		_run_root.move_child(intro, pause_menu.get_index())
		intro.setup(intro_mode, conductor, chart, arena, highway, hud, streak_counter)
		intro.pre_count_finished.connect(_begin_count_in.bind(false))
		intro.skip_requested.connect(_begin_count_in.bind(true))


func _bpm() -> float:
	var bpm := 120.0
	if not chart.tempo_map.is_empty():
		bpm = float(chart.tempo_map[0]["bpm"])
	return maxf(bpm, 1.0)


func is_began() -> bool:
	return _began


## Start the conductor lead-in (the 3-2-1). The only place Conductor.begin is called.
func _begin_count_in(skipped: bool = false) -> void:
	if _began or conductor == null:
		return
	var beats := IntroTimeline.lead_in_beats(intro_mode, skipped)
	conductor.begin(chart.audio_stream, IntroTimeline.lead_in_seconds(beats, _bpm()))
	lane_input.enabled = not autoplay  # autoplay presses for the player
	_began = true
	highway.notes_enabled = true
	arena.beat_live = true
	if intro != null and is_instance_valid(intro):
		intro.on_count_started(skipped)


## Online: the scheduled start (NET-03). song_time 0 lands on the host-scheduled instant. The
## only other place Conductor.begin is called (same flags as _begin_count_in).
func _begin_online(lead_s: float) -> void:
	if _began or conductor == null or not (lead_s >= 0.0):
		return
	conductor.begin(chart.audio_stream, lead_s)
	lane_input.enabled = not autoplay and not _done_reported
	_began = true
	highway.notes_enabled = true
	arena.beat_live = true


func _on_run_built() -> void:
	# Prewarm the burst emitters off-screen before the first note (intro / count-in).
	if fx_layer != null:
		fx_layer.prewarm()
	debug_overlay = DebugOverlay.new()
	_run_root.add_child(debug_overlay)
	debug_overlay.setup(conductor, judge)
	pause_menu = PauseMenu.new()
	pause_menu.match_mode = match_setup != null  # before the first open() (03-UI-SPEC 9.5)
	_run_root.add_child(pause_menu)
	pause_menu.setup(conductor, lane_input, score)
	pause_menu.restore_input = not autoplay
	pause_menu.restart_confirmed.connect(func() -> void: call_deferred("restart", false))
	pause_menu.menu_confirmed.connect(go_to_menu)


func _on_judged_arena(_lane: int, _idx: int, judgment: int, _err: float) -> void:
	if judgment == InputJudge.Judgment.MISS:
		_arena_miss()


func _on_hull_arena(_value: float, delta: float) -> void:
	if delta < 0.0:
		_arena_miss()


## A miss reaches the arena through both `judged` and `hull_changed` in the same frame; react
## once per frame so energy drops x0.4, not x0.16 (WR-05). Stray-press damage still counts.
func _arena_miss() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var frame := Engine.get_process_frames()
	if frame == _arena_miss_frame:
		return
	_arena_miss_frame = frame
	arena.on_miss()


func _teardown() -> void:
	if _fail_tween != null and _fail_tween.is_valid():
		_fail_tween.kill()
	_fail_tween = null
	offset_recorder.detach()
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
	if _nav_pending != "":
		_retry_nav()
	if _launch_lost:
		return
	if is_online():
		_process_online()
		return
	if state != State.RUNNING or conductor == null or not _began:
		return
	if conductor.is_paused():
		return
	var t := conductor.song_time()
	if _autoplay_player != null:
		_autoplay_player.update(t)  # exact note times, never the frame time (D-28)
	if versus != null:
		# Every rig (the human's included) ticks on the controller's song-time grid in global
		# time order with the bots and the drone (WR-01), so no frame-time judge.tick here.
		versus.pre_tick(t)
		versus.update(t)  # payload stack and the versus views
	else:
		judge.tick(t)
	if state == State.RUNNING and judge.is_finished() and t >= _end_time + END_PAD_SEC:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _launch_lost:
		return
	if is_online():
		_online_input(event)
		return
	if event.is_action_pressed(&"pause") and state == State.RUNNING and _began and pause_menu != null 			and not pause_menu.is_open() and not pause_menu.is_counting_down():
		get_viewport().set_input_as_handled()
		pause_menu.set_run_info(chart.title, chart.difficulty, progress_pct())
		pause_menu.open()
		return
	if versus != null and state == State.RUNNING and _began and pause_menu != null \
			and not pause_menu.is_open() and not pause_menu.is_counting_down():
		if event.is_action_pressed(&"fire"):
			var ft := conductor.song_time_at(Time.get_ticks_usec())
			get_viewport().set_input_as_handled()
			fire_count += 1
			versus.fire(ft)
			return
		if event.is_action_pressed(&"target_cycle"):
			var tt := conductor.song_time_at(Time.get_ticks_usec())
			get_viewport().set_input_as_handled()
			versus.cycle_target(tt)
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
	var mode := IntroTimeline.Mode.QUICK
	if pending_intro == IntroTimeline.Mode.NONE:
		mode = IntroTimeline.Mode.NONE
	start(c, a, mode)


func _finish() -> void:
	state = State.DONE
	lane_input.enabled = false
	if match_setup != null:
		_finish_versus()
		return
	# The ONLY place records are written. Failed dives never reach here (see _on_failed).
	var store := ScoreStore.new()
	store.load()
	var eligible := ScoreStore.is_eligible(autoplay_used, score.no_fail, practice)
	# D-08 weighted accuracy (-1 when nothing was judged; stored as 0) and the D-16 grade.
	var acc := RunStats.accuracy(score.perfect_count, score.good_count, score.miss_count)
	var grade := RunStats.grade(acc, score.miss_count)
	var res := store.submit(chart.id, score.depth(), maxf(acc, 0.0), score.max_combo, eligible,
		Time.get_date_string_from_system(), grade if grade != "-" else "", score.miss_count)
	var prev: Dictionary = res["previous"]
	var best := store.best(chart.id)
	record_info = {
		"eligible": eligible,
		"new_record": res["new_record"],
		"previous_depth": float(prev["depth"]) if not prev.is_empty() else -1.0,
		"best_depth": float(best["depth"]) if not best.is_empty() else -1.0,
		"grade": grade,
		"accuracy": acc,
		"offsets": offset_recorder.offsets(),
	}
	var run_info := {
		"title": chart.title,
		"artist": chart.artist,
		"difficulty": chart.difficulty,
		"offsets": record_info["offsets"],
		"accuracy": acc,
		"grade": grade,
		"perfect_window": JudgeConfig.new().perfect_window,
	}
	results = ResultsScreen.new()
	_run_root.add_child(results)
	results.setup(score, autoplay_used, record_info, practice, run_info)
	results.retry_pressed.connect(_on_retry)
	results.song_select_pressed.connect(go_to_song_select)
	results.menu_pressed.connect(go_to_menu)


## Versus end (MATCH-05, D-23): standings, medals and the seed on VersusResultsScreen. Versus
## never writes ScoreStore.
func _finish_versus() -> void:
	var t := conductor.song_time() if conductor != null else _end_time
	versus_results = VersusResultsScreen.new()
	_run_root.add_child(versus_results)
	versus_results.setup(versus.finish(t))
	versus_results.rematch_pressed.connect(_on_rematch)
	versus_results.change_match_pressed.connect(_on_change_match)
	versus_results.menu_pressed.connect(go_to_menu)


## The local hull broke in versus (D-22, D-24): no FailScreen, the song and lane input keep
## going, the HUD shows WRECK, and the results come at the song end.
func _on_versus_wreck() -> void:
	if hud != null and is_instance_valid(hud):
		hud.set_wreck(true)


## Rematch: the same match with a new seed, rebuilt in place (start() tears the run down).
func _on_rematch() -> void:
	if match_setup == null:
		return
	match_setup = match_setup.rematch()
	call_deferred("restart", false)


## Change Match: back to match setup with the finished match's choices (it draws a new seed).
func _on_change_match() -> void:
	MatchSetup.pending = match_setup
	ScreenTransition.change_scene(SongSelect.MATCH_SETUP_SCENE)


## Song progress 0..100 from the song clock and the song length (pause run line, IMPLOSION).
func progress_pct() -> float:
	if chart == null or conductor == null:
		return 0.0
	var length := ProgressTrack.song_length_of(chart)
	if length <= 0.0:
		return 0.0
	return clampf(conductor.song_time() / length, 0.0, 1.0) * 100.0


func _on_failed() -> void:
	var fail_pct := progress_pct()  # read before the conductor stops
	state = State.FAILED
	conductor.stop()  # audio stops immediately
	lane_input.enabled = false
	if arena != null:
		arena.fail()
	fail_screen = FailScreen.new()
	_run_root.add_child(fail_screen)
	# Read-only: failed dives never update records.
	var fail_store := ScoreStore.new()
	fail_store.load()
	var saved := fail_store.best(chart.id)
	fail_screen.setup(score.depth(), score.max_combo,
		float(saved["depth"]) if not saved.is_empty() else -1.0, fail_pct)
	fail_screen.retry_pressed.connect(_on_retry)
	fail_screen.menu_pressed.connect(go_to_menu)
	fail_screen.play(FailScreen.SQUASH_SEC)
	if fx_layer != null:
		fx_layer.stop()
	var pivot := Vector2(Trench.VP.x, Trench.HIT_Y)
	var squashed: Array[Control] = [highway, feedback, highway_notes]
	for ctl in squashed:
		ctl.pivot_offset = pivot
	var tw := create_tween().set_parallel(true)
	_fail_tween = tw
	tw.tween_property(fx_layer, "modulate:a", 0.0, FailScreen.SQUASH_SEC)
	for ctl in squashed:
		if Settings.reduce_motion:
			tw.tween_property(ctl, "modulate:a", 0.0, FailScreen.SQUASH_SEC)
		else:
			tw.tween_property(ctl, "scale:y", 0.0, FailScreen.SQUASH_SEC)


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
	l.add_theme_color_override("font_color", Palette.WARNING_RED)
	_run_root.add_child(l)
	# WR-02: online the session decides the way out (the abort sends everyone to the lobby);
	# the timer only falls back to the lobby / menu, never strands a live lobby.
	get_tree().create_timer(ERROR_RETURN_SEC).timeout.connect(
		_audio_error_exit_online if is_online() else go_to_menu)


## Restores the Song Select run flags this dive was launched with (SongSelect resets them when it
## exits into gameplay), so "Song Select" from results keeps Practice / Autoplay mode.
func prepare_song_select() -> void:
	SongSelect.run_autoplay = _launch_autoplay
	SongSelect.run_practice = practice


func go_to_song_select() -> void:
	prepare_song_select()
	var target := SONG_SELECT_SCENE if ResourceLoader.exists(SONG_SELECT_SCENE) else MENU_SCENE
	ScreenTransition.change_scene(target)


func go_to_menu() -> void:
	var target := MENU_SCENE if ResourceLoader.exists(MENU_SCENE) else FALLBACK_SCENE
	ScreenTransition.change_scene(target)


# --- Online (04-14) ---------------------------------------------------------------------------

func is_online() -> bool:
	return not online_spec.is_empty()


func _is_host() -> bool:
	return str(online_spec.get("role", "")) == "host"


func _local_seat() -> int:
	return int(online_spec.get("local_seat", 0))


func _names() -> PackedStringArray:
	var v: Variant = online_spec.get("names", PackedStringArray())
	if v is PackedStringArray or v is Array:
		return PackedStringArray(v)
	return PackedStringArray()


## Roster seats (spec.seats, else every named seat), in seat order.
func _seats() -> Array:
	var out: Array = []
	var v: Variant = online_spec.get("seats", [])
	if v is Array and not (v as Array).is_empty():
		for s: Variant in v:
			out.append(int(s))
		out.sort()
		return out
	var names := _names()
	for s in names.size():
		if names[s] != "":
			out.append(s)
	return out


func _connect_session() -> void:
	if session == null:
		return
	var wiring := {
		"start_scheduled": _on_start_scheduled,
		"match_aborted_to_lobby": _on_match_aborted,
		"host_left": _on_host_left,
		"results_due": _host_results,
		"results_received": _show_online_results,
		"returned_to_lobby": _on_returned_to_lobby,
		"left_lobby": _on_left_lobby,
	}
	for sig: String in wiring:
		var cb: Callable = wiring[sig]
		if session.has_signal(sig) and not session.is_connected(sig, cb):
			session.connect(sig, cb)


## StartSyncOverlay and LeaveOverlay above the board, HUD and StreakCounter and below the pause
## menu and dialogs (UI-SPEC: VersusHud < StartSyncOverlay < LeaveOverlay < overlays).
func _build_online_overlays() -> void:
	start_sync_overlay = StartSyncOverlay.new()
	_run_root.add_child(start_sync_overlay)
	_run_root.move_child(start_sync_overlay, pause_menu.get_index())
	var names := _names()
	var rows: Array = []
	for s: int in _seats():
		rows.append({"seat": s, "name": names[s] if s < names.size() else "",
			"is_you": s == _local_seat()})
	start_sync_overlay.setup(rows)
	start_sync_overlay.set_stage("loading")
	leave_overlay = LeaveOverlay.new()
	_run_root.add_child(leave_overlay)
	_run_root.move_child(leave_overlay, pause_menu.get_index())
	leave_overlay.leave_confirmed.connect(_on_leave_confirmed)
	# The run is built: LINKING SUBS and LOADED go out on the next idle step (the overlay shows
	# LOADING SONG for the build frame).
	call_deferred("_report_loaded_online")


func _report_loaded_online() -> void:
	if _online_over or not is_online() or state == State.ERROR:
		return
	if start_sync_overlay != null and is_instance_valid(start_sync_overlay):
		start_sync_overlay.set_stage("linking")
		start_sync_overlay.set_loaded(_local_seat(), true)
	if session != null:
		session.call("report_loaded")


## START received. The first lead_in_for_start call decides: -1 (late or unsynced) never begins;
## the host then aborts everyone to the lobby (match_aborted_to_lobby).
func _on_start_scheduled() -> void:
	if _began or _online_over or conductor == null or session == null:
		return
	var lead := float(session.call("lead_in_for_start"))
	if not (lead >= 0.0):
		return
	_begin_online(lead)
	if versus != null and versus.event_banner != null:
		versus.event_banner.start_countdown(-lead, int(online_spec.get("flight", 1)))
	if start_sync_overlay != null and is_instance_valid(start_sync_overlay):
		for s: int in _seats():
			start_sync_overlay.set_loaded(s, true)
		start_sync_overlay.dismiss()  # gone DUR_BASE after begin (keep-out exception)


## The local song end: min(chart end + END_PAD_SEC, max_song_s when > 0; autotest only).
func online_end_time() -> float:
	var end_t := _end_time + END_PAD_SEC
	var cap := float(online_spec.get("max_song_s", 0.0))
	if is_finite(cap) and cap > 0.0:
		end_t = minf(end_t, cap)
	return end_t


func _process_online() -> void:
	if session == null or _online_over:
		return
	if conductor == null or not _began or state == State.ERROR:
		# Waiting for START: control packets flow and the watchdog stays live.
		session.call("pump_match", NAN)
		return
	var t := conductor.song_time()
	if state == State.RUNNING and versus != null:
		versus.pre_tick(t)
		versus.update(t)
		versus.net_tick(t)
	session.call("pump_match", t)
	if _online_over:
		return  # a session signal ended the match during the pump
	if not _is_host() and state == State.RUNNING and versus != null and versus.status_chips != null:
		var weak := float(session.call("seconds_since_host_packet")) >= LINK_WEAK_S
		if weak != _link_weak:
			_link_weak = weak
			versus.status_chips.set_link_weak(weak)
	if leave_overlay != null and leave_overlay.is_open() and not _is_host():
		leave_overlay.set_ping(int(session.call("ping_ms")))
	if state == State.RUNNING and not _done_reported and t >= online_end_time():
		_online_song_done(t)
	elif state == State.RUNNING and _done_reported and _is_host():
		_update_waiting()


## DONE (D-19): lanes off, WAITING FOR RESULTS, report once. Never the offline _finish path.
func _online_song_done(t: float) -> void:
	_done_reported = true
	lane_input.enabled = false
	_update_waiting()
	session.call("report_done", t)  # the host may emit results_due right here


func _update_waiting() -> void:
	if versus == null or versus.event_banner == null or state != State.RUNNING:
		return
	var n := int(session.call("still_diving")) if session != null else 0
	if n != _waiting_n:
		_waiting_n = n
		versus.event_banner.show_waiting(n)


## Host (results_due): build the results once, send them, show them.
func _host_results(end_t: float) -> void:
	if versus == null or versus_results != null or _online_over:
		return
	var data := versus.finish(end_t)
	data["is_host"] = true
	session.call("host_send_results", data)
	_show_online_results(data)


## Host after results_due, client on results_received: the online results variant (04-12).
func _show_online_results(data: Dictionary) -> void:
	if versus_results != null or _online_over or _run_root == null:
		return
	state = State.DONE
	if lane_input != null:
		lane_input.enabled = false
	if leave_overlay != null and leave_overlay.is_open():
		leave_overlay.close()
	if versus != null and versus.event_banner != null:
		versus.event_banner.hide_waiting()
	versus_results = VersusResultsScreen.new()
	_run_root.add_child(versus_results)
	versus_results.setup(data)
	if _is_host():
		versus_results.back_to_lobby_pressed.connect(_on_results_back_to_lobby)
		versus_results.close_lobby_pressed.connect(_on_results_close_lobby)
	else:
		versus_results.leave_lobby_pressed.connect(_on_results_leave_lobby)
	versus_results.menu_pressed.connect(_go_main_menu)


func _on_results_back_to_lobby() -> void:
	if session != null:
		session.call("host_back_to_lobby")
	_go_lobby()


## Host "Back to Menu" with CLOSE LOBBY confirmed: the lobby closes, the host goes to the menu.
func _on_results_close_lobby() -> void:
	if session != null:
		session.call("leave")
	_go_main_menu()


## Client "Leave Lobby" (confirmed): Play Online keeps the saved address (UI-SPEC decision 15).
func _on_results_leave_lobby() -> void:
	if session != null:
		session.call("leave")
	_goto(ONLINE_MENU_SCENE if ResourceLoader.exists(ONLINE_MENU_SCENE) else _menu_target())


func _on_returned_to_lobby() -> void:
	_go_lobby()


## load_timeout / load_fail / start_late: back to the lobby (it shows the log line).
func _on_match_aborted(_code: String, _who: String) -> void:
	if conductor != null and is_instance_valid(conductor):
		conductor.stop()
	if lane_input != null:
		lane_input.enabled = false
	_go_lobby()


## LOBBY_CLOSED while the results show (the host left from RESULTS). WR-03: with no results
## screen up yet (this client still diving / waiting for RESULTS) the session is already
## offline, so the HOST LEFT dialog shows the last known standings instead.
func _on_left_lobby(code: String) -> void:
	if versus_results != null and is_instance_valid(versus_results):
		versus_results.set_lobby_closed()
		return
	if _online_over:
		return
	_on_host_left("connection_lost" if code == "lost" else "host_left")


## MATCH_ABORT, server loss or the 4 s watchdog (NET-06, UI-SPEC 11.6): the conductor stops,
## lanes disable, then the dialog shows the last known standings with one exit.
func _on_host_left(kind: String) -> void:
	if versus_results != null and is_instance_valid(versus_results):
		versus_results.set_lobby_closed()
		return
	if host_left_dialog != null or _run_root == null:
		return
	_online_over = true
	state = State.DONE
	if conductor != null and is_instance_valid(conductor):
		conductor.stop()
	if lane_input != null:
		lane_input.enabled = false
	if leave_overlay != null and leave_overlay.is_open():
		leave_overlay.close()
	if start_sync_overlay != null and is_instance_valid(start_sync_overlay):
		start_sync_overlay.queue_free()
	start_sync_overlay = null
	var names := _names()
	var statuses := {}
	for s: int in _seats():
		statuses[s] = _last_status.get(s, _default_status())
	host_left_dialog = HostLeftDialog.new()
	_run_root.add_child(host_left_dialog)
	host_left_dialog.setup(kind, names[0] if names.size() > 0 else "",
		HostLeftDialog.rows_from_status(statuses, names, _local_seat(), 0))
	host_left_dialog.back_to_menu.connect(_go_main_menu)


static func _default_status() -> Dictionary:
	return {"hull": 100.0, "depth": 0.0, "alive": true, "left": false}


## Last known per-seat standings for the HOST LEFT dialog (STATUS, IMPLODED, PLAYER_LEFT).
func _on_net_event(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	if type != GameEvent.STATUS and type != GameEvent.IMPLODED and type != GameEvent.PLAYER_LEFT:
		return
	var seat := int(e.get("seat", -1))
	if seat < 0:
		return
	var cur: Dictionary = _last_status.get(seat, _default_status())
	if type == GameEvent.STATUS:
		cur["hull"] = float(e.get("hull", cur["hull"]))
		cur["depth"] = float(e.get("depth", cur["depth"]))
		cur["alive"] = bool(e.get("alive", cur["alive"]))
	elif type == GameEvent.IMPLODED:
		cur["alive"] = false
	else:
		cur["alive"] = false
		cur["left"] = true
	_last_status[seat] = cur


func last_status() -> Dictionary:
	return _last_status


## Online input (D-18): Esc / Start opens the non-pausing Leave overlay, never the PauseMenu
## (also during the sync overlay and the countdown). Fire never goes through while the overlay
## is open (it consumes ui_accept itself). No restart (F4) online.
func _online_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if state == State.RUNNING and not _online_over and leave_overlay != null \
				and not leave_overlay.is_open():
			var ping := -1
			if session != null and not _is_host():
				ping = int(session.call("ping_ms"))
			leave_overlay.open(_is_host(), ping)
		return
	if event.is_action_pressed(&"debug_autoplay"):
		get_viewport().set_input_as_handled()
		return
	if versus == null or state != State.RUNNING or not _began or _online_over:
		return
	if event.is_action_pressed(&"fire"):
		get_viewport().set_input_as_handled()
		if leave_overlay != null and leave_overlay.is_open():
			return
		fire_count += 1
		versus.fire(conductor.song_time_at(Time.get_ticks_usec()))
		return
	if event.is_action_pressed(&"target_cycle"):
		get_viewport().set_input_as_handled()
		versus.cycle_target(conductor.song_time_at(Time.get_ticks_usec()))


## Leave Match confirmed (11.4): client disconnects (the host wrecks the seat), the host sends
## MATCH_ABORT; both go to the main menu.
func _on_leave_confirmed() -> void:
	_online_over = true
	if conductor != null and is_instance_valid(conductor):
		conductor.stop()
	if lane_input != null:
		lane_input.enabled = false
	if session != null:
		session.call("leave")
	_go_main_menu()


func _menu_target() -> String:
	return MENU_SCENE if ResourceLoader.exists(MENU_SCENE) else FALLBACK_SCENE


func _go_main_menu() -> void:
	_goto(_menu_target())


func _go_lobby() -> void:
	var target := LOBBY_SCENE
	if not ResourceLoader.exists(target):
		target = ONLINE_MENU_SCENE if ResourceLoader.exists(ONLINE_MENU_SCENE) else _menu_target()
	_goto(target)


func _goto(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
		return
	# WR-02: change_scene refuses while a wipe runs (e.g. an abort inside _ready, mid-wipe);
	# keep the target and retry from _process once ScreenTransition is idle.
	if not ScreenTransition.change_scene(path):
		_nav_pending = path


func _retry_nav() -> void:
	if ScreenTransition.is_busy():
		return
	var p := _nav_pending
	_nav_pending = ""
	if not ScreenTransition.change_scene(p):
		_nav_pending = p


## Online audio error fallback (WR-02): lobby while the session is in the lobby, the menu once
## it is offline; mid-match the session's abort / watchdog handles navigation.
func _audio_error_exit_online() -> void:
	if _nav_pending != "" or session == null:
		return
	if session.has_method("is_in_lobby") and bool(session.call("is_in_lobby")):
		_go_lobby()
	elif session.has_method("is_offline") and bool(session.call("is_offline")):
		_go_main_menu()
