extends Node
## Automated real-hardware playtest driver (Phase 1 human gate, plan 01-07 task 3).
## Drives the shipped scenes only through Input.parse_input_event (keyboard / joypad), waits on real
## time and song_time, and asserts on game state. Never modifies game code or the player's
## settings: Settings.save_path is redirected to user://playtest_settings.cfg for the whole run.
##
## Bot timing: input dispatch is synchronous (use_accumulated_input = false), so a press scheduled
## for song time T spin-waits inside the frame until Conductor.song_time_at(now) >= T and then
## parses the event. LaneInput stamps ticks on dispatch, so the judged error is the scheduled
## offset to well under 1 ms. This tests the clock + judge pipeline; it cannot measure the
## acoustic path (speaker -> ear), which needs a human or a loopback microphone.
##
## Scenario "immersion" (Phase 1.2): goggles intro frames and timing, Space skip, QUICK retry,
## curved Trench board at 0.5x/1x/3x, HUD streak / HULL CRITICAL, Low effects and reduce motion,
## screen-edge cleanliness and fps. Non-intro scenarios run with Gameplay.pending_intro = NONE.

const OUT_DIR := "res://build/playtest"
const TEMP_SETTINGS := "user://playtest_settings.cfg"
const REAL_SETTINGS := "user://settings.cfg"
## Records written by eligible bot dives go here, never to the player's user://scores.cfg (T-1.1-15).
const REAL_SCORES := "user://scores.cfg"
const TEMP_SCORES := "user://playtest_scores.cfg"
const POLISH_SCORES := "user://polish_scores.cfg"
const MENU := "res://scenes/main_menu.tscn"
const GAMEPLAY := "res://scenes/gameplay.tscn"
const CALIB := "res://scenes/calibration.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const DRIFT := "res://scenes/drift_harness.tscn"
const LANE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]
const TIMEOUTS := {"a": 120.0, "b": 120.0, "c": 60.0, "d": 90.0, "e": 120.0, "f": 90.0,
	"g": 90.0, "h": 150.0, "i": 90.0, "drift": 360.0, "layout": 240.0, "polish": 240.0, "immersion": 240.0}
## Scenario b offsets (seconds) per note, cycled. null = skip the note. Values stay >= 5 ms
## from window edges (35 / 70 / 100 ms) so frame jitter cannot flip the expected judgment.
const B_CYCLE := [0.0, 0.010, -0.010, 0.020, -0.020, 0.0, 0.030, -0.030, 0.0, 0.040, -0.040,
	0.050, -0.050, 0.0, 0.060, -0.060, 0.0, 0.005, -0.005, 0.090, 0.0, -0.090, 0.015, null]

var scenario: String = "a"
var checks: Array = []
var metrics: Dictionary = {}
var shots: Array = []
var notes_log: Array = []
var probe: Node
var _start_ms: int = 0
var _done: bool = false
var _real_settings_existed: bool = false
## Frame captured by the latest shot(), plus song time / highway note states when a Gameplay is passed.
var last_img: Image
var last_shot_st: float = 0.0
var last_shot_state := PackedByteArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		scenario = String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Evidence must never be imported as resources or packed into an export (01-10 finding).
	if not FileAccess.file_exists("res://build/.gdignore"):
		var gi := FileAccess.open("res://build/.gdignore", FileAccess.WRITE)
		if gi != null:
			gi.close()
	_real_settings_existed = FileAccess.file_exists(REAL_SETTINGS)
	probe = preload("res://tools/playtest/frame_probe.gd").new()
	add_child(probe)
	_start_ms = Time.get_ticks_msec()
	print("[playtest] scenario=%s" % scenario)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _done:
		return
	var limit: float = TIMEOUTS.get(scenario, 120.0)
	if (Time.get_ticks_msec() - _start_ms) / 1000.0 > limit:
		check("scenario finished before %.0f s watchdog" % limit, false, "TIMEOUT")
		_finish()


func _run() -> void:
	match scenario:
		"a": await sc_a()
		"b": await sc_b()
		"c": await sc_c()
		"d": await sc_d()
		"e": await sc_e()
		"f": await sc_f()
		"g": await sc_g()
		"h": await sc_h()
		"i": await sc_i()
		"drift": await sc_drift()
		"layout": await sc_layout()
		"polish": await sc_polish()
		"immersion": await sc_immersion()
		_: check("known scenario", false, scenario)
	_finish()


# ------------------------------------------------------------------------------------------------
# infrastructure
# ------------------------------------------------------------------------------------------------


func isolate_settings(calibrated: bool) -> void:
	_use_temp_scores(TEMP_SCORES)
	Gameplay.pending_intro = IntroTimeline.Mode.NONE  # scenarios opt in to the intro explicitly
	Settings.save_path = TEMP_SETTINGS
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	Settings.load_from(TEMP_SETTINGS)
	if calibrated:
		Settings.save_calibration(0.0, 0.0)
		MainMenu.boot_handled = true


func _use_temp_scores(path: String) -> void:
	ScoreStore.default_path = path
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func check(name: String, ok: bool, detail: Variant = "") -> bool:
	checks.append({"name": name, "pass": ok, "detail": str(detail)})
	print("[%s] %s  %s" % ["PASS" if ok else "FAIL", name, str(detail)])
	return ok


func note(text: String) -> void:
	notes_log.append(text)
	print("[note] " + text)


func env_info() -> Dictionary:
	var d := {
		"engine": Engine.get_version_info()["string"],
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"debug_build": OS.is_debug_build(),
		"audio_driver_setting": str(ProjectSettings.get_setting("audio/driver/driver", "")),
		"audio_output_device": AudioServer.output_device,
		"audio_device_list": AudioServer.get_output_device_list(),
		"audio_output_latency_ms": AudioServer.get_output_latency() * 1000.0,
		"audio_mix_rate": AudioServer.get_mix_rate(),
		"audio_buffer_setting_ms": ProjectSettings.get_setting("audio/driver/output_latency", 15),
		"render_method": RenderingServer.get_current_rendering_method(),
		"render_driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"window_size": str(DisplayServer.window_get_size()),
		"joypads": Input.get_connected_joypads(),
	}
	if AudioServer.has_method("get_driver_name"):
		d["audio_driver"] = AudioServer.call("get_driver_name")
	return d


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _real_settings_existed:
		check("real user://settings.cfg untouched (still absent)", not FileAccess.file_exists(REAL_SETTINGS))
	var ok := true
	for c in checks:
		ok = ok and bool(c["pass"])
	var out := {
		"scenario": scenario,
		"pass": ok,
		"checks": checks,
		"metrics": metrics,
		"notes": notes_log,
		"screenshots": shots,
		"env": env_info(),
		"duration_s": (Time.get_ticks_msec() - _start_ms) / 1000.0,
	}
	var f := FileAccess.open("%s/%s.json" % [OUT_DIR, scenario], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	if ScoreStore.default_path != REAL_SCORES:
		_use_temp_scores(ScoreStore.default_path)
	ScoreStore.default_path = REAL_SCORES
	print("[playtest] scenario=%s result=%s" % [scenario, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func frame() -> void:
	await get_tree().process_frame


func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func cur() -> Node:
	return get_tree().current_scene


func goto(path: String) -> bool:
	get_tree().change_scene_to_file(path)
	var ok: bool = await wait_until(func() -> bool:
		return cur() != null and cur().scene_file_path == path, 5.0)
	await frame()
	return ok


func scene_is(path: String) -> bool:
	return cur() != null and cur().scene_file_path == path


func shot(label: String, g: Gameplay = null) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	last_img = img
	if g != null and is_instance_valid(g) and g.conductor != null:
		last_shot_st = g.conductor.song_time()
		last_shot_state = g.highway._state.duplicate()
	var path := ProjectSettings.globalize_path("%s/%s_%02d_%s.png" % [OUT_DIR, scenario, shots.size() + 1, label])
	img.save_png(path)
	shots.append(path)
	print("[shot] " + path)
	return path


func focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


# --- synthetic input ----------------------------------------------------------------------------


func key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.keycode = code as Key
	e.pressed = pressed
	Input.parse_input_event(e)


## Full key press + release across frames (menus).
func press_key(code: int, hold: float = 0.0) -> void:
	key(code, true)
	if hold > 0.0:
		await wait(hold)
	else:
		await frame()
	key(code, false)
	await frame()
	await frame()


func pad_button(idx: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = idx as JoyButton
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func pad_axis(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis as JoyAxis
	e.axis_value = v
	Input.parse_input_event(e)


## Runs callables at exact song times. schedule: Array of {t, o (order), fn}. Spin-waits inside the
## frame so the event is dispatched when song_time_at(now) >= t (sub-ms). Stops when stop() is true.
func run_schedule(conductor: Conductor, schedule: Array, stop: Callable) -> void:
	schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["t"]), float(b["t"])):
			return int(a["o"]) < int(b["o"])
		return float(a["t"]) < float(b["t"]))
	var i := 0
	var last := Time.get_ticks_usec()
	while i < schedule.size():
		await get_tree().process_frame
		if stop.call() or not is_instance_valid(conductor):
			return
		var now := Time.get_ticks_usec()
		var frame_s := clampf((now - last) / 1000000.0, 0.004, 0.034)
		last = now
		if conductor.is_paused():
			continue
		var horizon := conductor.song_time_at(now) + frame_s + 0.002
		while i < schedule.size() and float(schedule[i]["t"]) <= horizon:
			var target := float(schedule[i]["t"])
			while conductor.song_time_at(Time.get_ticks_usec()) < target and not conductor.is_paused():
				pass
			(schedule[i]["fn"] as Callable).call()
			i += 1


## Keyboard schedule that plays notes at note.time + offsets[k] (null skips the note).
func keyboard_schedule(notes: Array, offsets: Array, start_t: float = -INF) -> Array:
	var sched: Array = []
	for k in range(notes.size()):
		var n: Dictionary = notes[k]
		if float(n["time"]) < start_t:
			continue
		var off: Variant = offsets[k % offsets.size()]
		if off == null:
			continue
		var lane: int = n["lane"]
		var tp: float = float(n["time"]) + float(off)
		var tr: float = tp + 0.06
		if float(n["duration"]) > 0.0:
			tr = maxf(tr, float(n["time"]) + float(n["duration"]))
		var code: int = LANE_KEYS[lane]
		sched.append({"t": tp, "o": 1, "k": k, "fn": func() -> void: key(code, true)})
		sched.append({"t": tr, "o": 0, "k": k, "fn": func() -> void: key(code, false)})
	return sched


## Stop condition for bots that must not keep a strong capture on a Gameplay that may be freed.
func _gone_or_stopped(gw: WeakRef) -> bool:
	var g := gw.get_ref() as Gameplay
	return g == null or g.state != Gameplay.State.RUNNING


func start_dive_from_menu(autoplay: bool, intro: bool = false) -> Gameplay:
	Gameplay.pending_intro = IntroTimeline.Mode.FULL if intro else IntroTimeline.Mode.NONE
	if not scene_is(MENU):
		await goto(MENU)
	await wait(0.3)
	var m := cur() as MainMenu
	if m == null:
		check("main menu shown", false, cur())
		return null
	m.start_button.grab_focus()
	if autoplay:
		# Menu order since 01.1-01: Start, Practice, Autoplay, Calibrate, Settings, Quit.
		await press_key(KEY_DOWN)
		await press_key(KEY_DOWN)
	check("menu focus on %s" % ("Autoplay Dive (test)" if autoplay else "Start Dive"),
		focus_owner() == (m.autoplay_button if autoplay else m.start_button), focus_owner())
	await press_key(KEY_ENTER)
	var ok: bool = await wait_until(func() -> bool: return cur() is Gameplay, 5.0)
	check("gameplay scene loaded", ok)
	return cur() as Gameplay


func wait_for_began(g: Gameplay, timeout: float = 8.0) -> bool:
	return await wait_until(func() -> bool: return not is_instance_valid(g) or g.is_began(), timeout)


func stats(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {"n": 0}
	var s := 0.0
	var mx := -INF
	var mn := INF
	var amax := 0.0
	for v in arr:
		s += float(v)
		mx = maxf(mx, float(v))
		mn = minf(mn, float(v))
		amax = maxf(amax, absf(float(v)))
	var mean := s / arr.size()
	var ss := 0.0
	for v in arr:
		ss += (float(v) - mean) * (float(v) - mean)
	var sorted := arr.duplicate()
	sorted.sort()
	var abs_sorted: Array = []
	for v in arr:
		abs_sorted.append(absf(float(v)))
	abs_sorted.sort()
	return {"n": arr.size(), "mean": mean, "std": sqrt(ss / arr.size()), "min": mn, "max": mx,
		"max_abs": amax, "p50": sorted[sorted.size() / 2],
		"p99_abs": abs_sorted[mini(int(abs_sorted.size() * 0.99), abs_sorted.size() - 1)]}


## Least squares y = a + b x. Returns {a, b, resid_std, resid_max_abs}.
func linfit(xs: Array, ys: Array) -> Dictionary:
	var n := xs.size()
	if n < 2:
		return {}
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for i in range(n):
		sx += float(xs[i])
		sy += float(ys[i])
		sxx += float(xs[i]) * float(xs[i])
		sxy += float(xs[i]) * float(ys[i])
	var b := (n * sxy - sx * sy) / (n * sxx - sx * sx)
	var a := (sy - b * sx) / n
	var res: Array = []
	for i in range(n):
		res.append(float(ys[i]) - (a + b * float(xs[i])))
	var st := stats(res)
	return {"a": a, "b": b, "resid_std": st["std"], "resid_max_abs": st["max_abs"]}


## Frame-to-frame clock analysis over probe rows in [t_from, t_to] song time (playing, unpaused).
func clock_analysis(rows: Array, t_from: float, t_to: float) -> Dictionary:
	var devs: Array = []
	var dts: Array = []
	var track: Array = []
	var backwards := 0
	var snaps := 0
	var prev: Array = []
	var xs: Array = []
	var raw_minus_sys: Array = []
	var t0_ticks := -1
	for r in rows:
		var st: float = r[1]
		if bool(r[5]) or st < t_from or st > t_to:
			prev = []
			continue
		if bool(r[2]):
			var e: float = (st - float(r[3])) * 1000.0
			track.append(e)
			if absf(e) > 50.0:
				snaps += 1
			if t0_ticks < 0:
				t0_ticks = int(r[0])
			xs.append((int(r[0]) - t0_ticks) / 1000000.0)
			raw_minus_sys.append(float(r[3]))
		if not prev.is_empty():
			var dsys := (int(r[0]) - int(prev[0])) / 1000000.0
			var dsong := st - float(prev[1])
			if dsong < 0.0:
				backwards += 1
			dts.append(dsys * 1000.0)
			devs.append((dsong - dsys) * 1000.0)
		prev = r
	var out := {"frame_dt_ms": stats(dts), "dsong_minus_dsys_ms": stats(devs),
		"song_minus_audio_target_ms": stats(track), "backwards_steps": backwards,
		"tracking_err_gt_50ms_frames": snaps}
	# Raw audio clock vs system clock: fit audio_target(t_sys); slope - 1 = rate difference.
	var fit := linfit(xs, raw_minus_sys)
	if not fit.is_empty():
		out["audio_vs_system_rate_ppm"] = (float(fit["b"]) - 1.0) * 1000000.0
		out["audio_target_jitter_resid_std_ms"] = float(fit["resid_std"]) * 1000.0
		out["audio_target_jitter_resid_max_ms"] = float(fit["resid_max_abs"]) * 1000.0
	return out


## D-30 jitter figure, same method as tools/playtest/analyze_probe.py: fit the raw audio target
## against system time over audio-valid, unpaused frames with song_time in [t_from, t_to], then
## report song_time minus that smooth line (ms), overall and per `window_s` of system time.
func smooth_clock_error(rows: Array, t_from: float, t_to: float, window_s: float = 60.0) -> Dictionary:
	var xs: Array = []
	var tg: Array = []
	var sts: Array = []
	var t0 := -1
	for r in rows:
		var st: float = r[1]
		if bool(r[5]) or not bool(r[2]) or st < t_from or st > t_to:
			continue
		if t0 < 0:
			t0 = int(r[0])
		xs.append((int(r[0]) - t0) / 1000000.0)
		tg.append(float(r[3]))
		sts.append(st)
	var fit := linfit(xs, tg)
	if fit.is_empty():
		return {}
	var a := float(fit["a"])
	var b := float(fit["b"])
	var err: Array = []
	var windows: Array = []
	var cur_w := -1
	var w_err: Array = []
	for i in range(xs.size()):
		var e := (float(sts[i]) - (a + b * float(xs[i]))) * 1000.0
		err.append(e)
		var wi := int(float(xs[i]) / window_s)
		if wi != cur_w:
			if not w_err.is_empty():
				windows.append(_win_stats(cur_w, window_s, w_err))
			cur_w = wi
			w_err = []
		w_err.append(e)
	if not w_err.is_empty():
		windows.append(_win_stats(cur_w, window_s, w_err))
	return {"song_minus_smooth_audio_ms": stats(err), "windows": windows,
		"audio_vs_system_rate_ppm": (b - 1.0) * 1000000.0, "frames": xs.size()}


func _win_stats(wi: int, window_s: float, v: Array) -> Dictionary:
	var s := stats(v)
	return {"from_s": wi * window_s, "n": s["n"], "std": s["std"], "p99_abs": s["p99_abs"], "max_abs": s["max_abs"]}


# ------------------------------------------------------------------------------------------------
# a. first launch + calibration wizard
# ------------------------------------------------------------------------------------------------


func sc_a() -> void:
	isolate_settings(false)
	MainMenu.boot_handled = false
	await goto(MENU)
	var ok: bool = await wait_until(func() -> bool: return cur() is CalibrationWizard, 5.0)
	if not check("first launch (no settings) routes main menu -> calibration wizard", ok, cur()):
		return
	await wait(0.5)
	var w := cur() as CalibrationWizard
	var info: String = w.get("_info_label").text
	metrics["wizard_readout"] = info
	check("readout shows latency, buffer and device",
		info.contains("Output latency:") and info.contains("Buffer:") and info.contains("Output device:"), info)
	metrics["bluetooth_warning_visible"] = w.bluetooth_warning_visible()
	# Gap 2 (01-09): honest readout from the Godot-only device snapshot.
	var snap: Dictionary = Settings.device_info.snapshot()
	metrics["device_snapshot"] = {"configured": snap.configured, "display": snap.display,
		"is_alias": snap.is_alias, "signature": snap.signature, "is_bluetooth": snap.is_bluetooth}
	check("readout names the snapshot display ('Output device: %s')" % snap.display,
		info.contains("Output device: %s" % snap.display), info)
	if bool(snap.is_alias):
		check("alias readout says 'Output device: System default', not the bare 'Default'",
			info.contains("Output device: System default") and not info.contains("Output device: Default"), info)
	check("Bluetooth warning follows the snapshot (alias -> hidden)",
		w.bluetooth_warning_visible() == bool(snap.is_bluetooth), "visible=%s is_bluetooth=%s" % [w.bluetooth_warning_visible(), snap.is_bluetooth])
	var note_text: String = w.note_label.text if w.note_label != null else ""
	metrics["recalibration_note"] = note_text
	check("recalibration note shown", w.note_label != null and w.note_label.is_visible_in_tree()
		and note_text == "Switched headphones or speakers? Calibrate Sonar again.", note_text)
	_check_button_widths("intro", {"begin": w.begin_button, "skip": w.skip_button})
	await shot("wizard_intro")
	check("Begin button focused", focus_owner() == w.begin_button, focus_owner())
	await press_key(KEY_ENTER)
	check("Enter on Begin -> audio step", w.step == CalibrationWizard.Step.AUDIO, w.step)

	var lag := 0.040
	var r1: float = await _calibration_run(w, lag, "run1")
	metrics["run1_measured_ms"] = r1 * 1000.0
	check("run 1: taps at heard click +40 ms -> measured +40 ms (+-5)", absf(r1 - lag) <= 0.005,
		"%.2f ms" % (r1 * 1000.0))
	_check_button_widths("audio_result", {"accept": w.accept_button, "retry": w.retry_button})
	check("first run: no 'Previously saved' caption (nothing saved yet)", w.previous_label.text == "", w.previous_label.text)
	await shot("wizard_audio_result")

	# Accept -> visual step
	check("Accept focused after result", focus_owner() == w.accept_button, focus_owner())
	await press_key(KEY_ENTER)
	check("Accept -> visual step", w.step == CalibrationWizard.Step.VISUAL, w.step)
	await frame()
	var s := w.visual_slider
	check("visual slider focused", focus_owner() == s, focus_owner())
	var v0 := s.value
	await press_key(KEY_RIGHT)
	var v1 := s.value
	await press_key(KEY_LEFT)
	var v2 := s.value
	check("visual slider: Right tap +1 ms, Left tap -1 ms", is_equal_approx(v1 - v0, 1.0) and is_equal_approx(v2, v0),
		"%s -> %s -> %s" % [v0, v1, v2])
	await press_key(KEY_RIGHT, 1.0)
	var v3 := s.value
	var rep := v3 - v2 - 1.0
	metrics["visual_hold_1s_delta_ms"] = v3 - v2
	check("visual slider: hold Right 1 s -> 1 ms then +10 ms repeats", rep >= 10.0 and is_equal_approx(fmod(rep, 10.0), 0.0),
		"delta %.0f ms (1 + %d x 10)" % [v3 - v2, int(rep / 10.0)])
	check("pending visual offset follows slider", is_equal_approx(w.pending_visual * 1000.0, v3),
		"%.1f ms" % (w.pending_visual * 1000.0))
	await shot("wizard_visual")
	# Retry Test resets the slider to 0 (Right moves focus? use the button directly via focus+Enter)
	w.retry_button.grab_focus()
	await press_key(KEY_ENTER)
	check("visual Retry Test resets slider to 0", is_equal_approx(s.value, 0.0), s.value)
	w.accept_button.grab_focus()
	await press_key(KEY_ENTER)
	check("Accept -> summary step", w.step == CalibrationWizard.Step.SUMMARY, w.step)
	_check_button_widths("summary", {"save": w.save_button})
	await shot("wizard_summary")
	check("Save and Continue focused", focus_owner() == w.save_button, focus_owner())
	await press_key(KEY_ENTER)
	ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	check("Save and Continue -> main menu", ok, cur())
	var live: Dictionary = Settings.device_info.snapshot()
	metrics["saved_device_name"] = Settings.output_device_name
	metrics["saved_device_signature"] = Settings.output_device_signature
	check("calibration saved: audio_offset ~ +40 ms, done=true, device name + signature = live snapshot",
		absf(Settings.audio_offset - lag) <= 0.005 and Settings.calibration_done
		and Settings.output_device_name == live.configured and Settings.output_device_signature == live.signature
		and not Settings.output_device_signature.is_empty(),
		"audio %.2f ms, visual %.1f ms, device '%s', signature '%s'" % [Settings.audio_offset * 1000.0,
			Settings.visual_offset * 1000.0, Settings.output_device_name, Settings.output_device_signature])
	check("no device-change prompt right after saving (signature unchanged)", not Settings.device_changed())
	check("saved to the redirected temp settings file", FileAccess.file_exists(TEMP_SETTINGS))
	await wait(0.3)
	var m := cur() as MainMenu
	check("menu: empty state hidden after calibration", not m.empty_state_visible())
	await shot("menu_after_calibration")

	# Re-run from the menu with the offset applied. Same simulated player (40 ms behind heard audio).
	m.start_button.grab_focus()
	for i in range(3):  # Start -> Practice -> Autoplay -> Calibrate (01.1-01 menu order)
		await press_key(KEY_DOWN)
	check("menu focus on Calibrate Sonar", focus_owner() == m.calibrate_button, focus_owner())
	await press_key(KEY_ENTER)
	ok = await wait_until(func() -> bool: return cur() is CalibrationWizard, 5.0)
	check("Calibrate Sonar opens wizard", ok)
	await wait(0.3)
	w = cur() as CalibrationWizard
	await press_key(KEY_ENTER)
	var r2: float = await _calibration_run(w, lag, "run2")
	metrics["run2_measured_ms"] = r2 * 1000.0
	metrics["run2_residual_vs_applied_ms"] = (r2 - Settings.audio_offset) * 1000.0
	check("run 2 (offset applied): wizard reports the absolute offset again (~+40 ms)", absf(r2 - lag) <= 0.005,
		"%.2f ms" % (r2 * 1000.0))
	check("run 2 residual vs applied offset ~ 0 ms (+-5)", absf(r2 - Settings.audio_offset) <= 0.005,
		"%.2f ms" % ((r2 - Settings.audio_offset) * 1000.0))
	# Gap 5 (01-09): the re-run shows the saved offset beside the new absolute result.
	var prev_text: String = w.previous_label.text
	metrics["run2_previous_caption"] = prev_text
	check("run 2: 'Previously saved' caption shows the saved offset",
		prev_text == "Previously saved: %s" % CalibrationWizard.format_ms(Settings.audio_offset), prev_text)
	check("run 2: 'Previously saved' value within 5 ms of the new result",
		prev_text.begins_with("Previously saved: ") and absf(Settings.audio_offset - r2) <= 0.005,
		"saved %.2f ms vs new %.2f ms" % [Settings.audio_offset * 1000.0, r2 * 1000.0])
	_check_button_widths("rerun_result", {"accept": w.accept_button, "retry": w.retry_button})
	await shot("wizard_rerun_previously_saved")
	# A tap-perfect player (0 ms lag) on a calibrated (+40) profile should measure 0.
	await press_key(KEY_ESCAPE)
	ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	check("Esc in wizard = Skip, back to menu, offset unchanged", ok and absf(Settings.audio_offset - lag) <= 0.005,
		"%.2f ms" % (Settings.audio_offset * 1000.0))


## Gap 6 (01-09): wizard buttons stay 280-480 px wide instead of stretching across the window.
func _check_button_widths(step: String, buttons: Dictionary) -> void:
	var widths := {}
	var ok := true
	for k in buttons:
		var b: Button = buttons[k]
		if b == null or not is_instance_valid(b):
			widths[k] = "missing"
			ok = false
			continue
		var wpx := b.get_global_rect().size.x
		widths[k] = wpx
		ok = ok and wpx >= 280.0 and wpx <= 480.0
	metrics["button_widths_%s" % step] = widths
	check("%s: wizard buttons 280-480 px wide" % step, ok, widths)


## Plays one 16-click audio test. The simulated player taps `lag` seconds after the click is HEARD,
## which in Conductor song time is click - audio_offset + lag.
func _calibration_run(w: CalibrationWizard, lag: float, label: String) -> float:
	check("%s: audio test running" % label, w.audio_phase == CalibrationWizard.AudioPhase.RUNNING, w.audio_phase)
	var sched: Array = []
	for c in w.click_times():
		var t: float = float(c) - Settings.audio_offset + lag
		sched.append({"t": t, "o": 1, "fn": func() -> void: key(KEY_SPACE, true)})
		sched.append({"t": t + 0.05, "o": 0, "fn": func() -> void: key(KEY_SPACE, false)})
	await run_schedule(w.conductor, sched, func() -> bool: return w.audio_phase != CalibrationWizard.AudioPhase.RUNNING)
	var ok: bool = await wait_until(func() -> bool: return w.audio_phase == CalibrationWizard.AudioPhase.RESULT, 5.0)
	check("%s: all 16 taps recorded and evaluated" % label, ok and w.taps_recorded == 16, "taps %d" % w.taps_recorded)
	var raw: Array = []
	for t in w.tap_times:
		raw.append(snappedf(float(t) * 1000.0, 0.01))
	metrics["%s_tap_song_times_ms" % label] = raw
	metrics["%s_result_label" % label] = w.result_label.text
	return w.audio_result


# ------------------------------------------------------------------------------------------------
# b. keyboard bot with mixed offsets on the hand chart
# ------------------------------------------------------------------------------------------------


func sc_b() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	var j := g.judge
	var notes: Array = g.chart.notes
	var judged := {}
	var strays := [0]
	var ticks := [0]
	var press_err := {}
	var pending := [-1]
	j.judged.connect(func(_l: int, idx: int, jj: int, err: float) -> void: judged[idx] = [jj, err])
	j.stray.connect(func(_l: int) -> void: strays[0] += 1)
	j.sustain_tick.connect(func(_l: int) -> void: ticks[0] += 1)
	g.lane_input.lane_pressed.connect(func(_l: int, tk: int) -> void:
		if pending[0] >= 0:
			press_err[pending[0]] = c.song_time_at(tk) - float(notes[pending[0]]["time"]))
	var sched := keyboard_schedule(notes, B_CYCLE)
	for e in sched:
		if int(e["o"]) == 1:
			var k: int = e["k"]
			var f: Callable = e["fn"]
			e["fn"] = func() -> void:
				pending[0] = k
				f.call()
				pending[0] = -1
	var hud_samples: Array = []
	var hud_mismatch: Array = []
	var sampler := func() -> void:
		while is_instance_valid(g) and g.state == Gameplay.State.RUNNING:
			await wait(1.0)
			if not is_instance_valid(g) or g.state != Gameplay.State.RUNNING:
				break
			var sc := g.score
			var h := g.hud
			hud_samples.append({"t": snappedf(c.song_time(), 0.01), "hull": h.hull_value.text,
				"combo": h.combo_value.text, "depth": h.depth_value.text, "mult": h.mult_value.text})
			var exp_hull := "%d%%" % int(round(sc.hull / 100.0 * 100.0))
			if h.combo_value.text != str(sc.combo) or h.depth_value.text != h.depth_text(sc.depth()) \
					or h.hull_value.text != exp_hull or h.mult_value.text != "x%d" % sc.multiplier():
				hud_mismatch.append(hud_samples.back())
	sampler.call()
	var shooter := func() -> void:
		await wait_until(func() -> bool: return c.song_time() > 21.3, 60.0)
		await shot("midsong_hud_notes_feedback")
	shooter.call()
	await run_schedule(c, sched, func() -> bool: return g.state != Gameplay.State.RUNNING)
	var ok: bool = await wait_until(func() -> bool: return g.state != Gameplay.State.RUNNING, 15.0)
	check("run ends", ok and g.state == Gameplay.State.DONE, g.state)
	await wait(0.6)
	await shot("results")

	# Judgment validation against JudgeConfig windows using the ACTUAL press error.
	var cfg := JudgeConfig.new()
	var mismatches: Array = []
	var timing_dev: Array = []
	var counts := {"P": 0, "G": 0, "M": 0}
	for k in range(notes.size()):
		var off: Variant = B_CYCLE[k % B_CYCLE.size()]
		if not judged.has(k):
			mismatches.append({"k": k, "why": "never judged"})
			continue
		var jj: int = judged[k][0]
		var err: float = judged[k][1]
		counts[["P", "G", "M"][jj]] += 1
		var expect: int
		if off == null:
			expect = InputJudge.Judgment.MISS
		else:
			if not press_err.has(k):
				mismatches.append({"k": k, "why": "press not captured"})
				continue
			var e: float = press_err[k]
			timing_dev.append((e - float(off)) * 1000.0)
			if absf(e) <= cfg.perfect_window:
				expect = InputJudge.Judgment.PERFECT
			elif absf(e) <= cfg.good_window:
				expect = InputJudge.Judgment.GOOD
			else:
				expect = InputJudge.Judgment.MISS
			if jj != InputJudge.Judgment.MISS and absf(err - e) > 1e-6:
				mismatches.append({"k": k, "why": "judged err %.4f != press err %.4f" % [err, e]})
		if jj != expect:
			mismatches.append({"k": k, "off": off, "got": jj, "expect": expect, "err": err})
	metrics["notes"] = notes.size()
	metrics["judged"] = judged.size()
	metrics["counts"] = counts
	metrics["strays"] = strays[0]
	metrics["sustain_ticks"] = ticks[0]
	metrics["bot_press_error_vs_intended_ms"] = stats(timing_dev)
	metrics["hud_samples"] = hud_samples
	metrics["judgment_mismatches"] = mismatches
	check("every note judged exactly once", judged.size() == notes.size(), "%d / %d" % [judged.size(), notes.size()])
	check("bot hit intended offsets (max |actual - intended| < 2 ms)",
		float(stats(timing_dev).get("max_abs", 99.0)) < 2.0, stats(timing_dev))
	check("all judgments match JudgeConfig windows (35/70/100 ms)", mismatches.is_empty(), mismatches.slice(0, 8))
	var late_miss := 0
	var early_miss := 0
	for k in range(notes.size()):
		var off: Variant = B_CYCLE[k % B_CYCLE.size()]
		if off != null and float(off) > 0.07:
			late_miss += 1
		elif off != null and float(off) < -0.07:
			early_miss += 1
	check("late presses beyond window (+90 ms) produce strays", strays[0] == late_miss, "strays %d, +90 presses %d" % [strays[0], late_miss])
	var chords := 0
	var chord_ok := true
	var times := {}
	for k in range(notes.size()):
		var key_t := snappedf(float(notes[k]["time"]), 0.0001)
		times[key_t] = times.get(key_t, []) + [k]
	for t in times:
		if (times[t] as Array).size() >= 2:
			chords += 1
			for k in times[t]:
				var off: Variant = B_CYCLE[int(k) % B_CYCLE.size()]
				if off != null and absf(float(off)) <= 0.035 and int(judged.get(k, [9])[0]) != InputJudge.Judgment.PERFECT:
					chord_ok = false
	metrics["chords"] = chords
	check("chords present and each chord note judged independently", chords > 0 and chord_ok, "%d chords" % chords)
	var sustains := 0
	for n in notes:
		if float(n["duration"]) > 0.0:
			sustains += 1
	metrics["sustains"] = sustains
	check("sustains present and award ticks when held", sustains > 0 and ticks[0] > 0 and g.score.sustain_ticks == ticks[0],
		"%d sustains, %d ticks" % [sustains, ticks[0]])
	var sc := g.score
	check("score counters match judged tallies", sc.perfect_count == counts["P"] and sc.good_count == counts["G"] and sc.miss_count == counts["M"],
		"P%d G%d M%d" % [sc.perfect_count, sc.good_count, sc.miss_count])
	var min_hull := 100.0
	for s in hud_samples:
		min_hull = minf(min_hull, float(String(s["hull"]).trim_suffix("%")))
	check("HUD hull/combo/depth/multiplier match score every second", hud_mismatch.is_empty() and hud_samples.size() > 30,
		"%d samples, %d mismatches, min hull %s%%" % [hud_samples.size(), hud_mismatch.size(), min_hull])
	check("hull dropped on misses", min_hull < 100.0, min_hull)
	if g.results != null:
		metrics["results_rows"] = g.results.rows
		check("results: no flags on a clean manual run", g.results.flags.is_empty(), g.results.flags)


# ------------------------------------------------------------------------------------------------
# c. F3 overlay + per-frame clock smoothness from real audio
# ------------------------------------------------------------------------------------------------


func sc_c() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	probe.conductor = c
	probe.enabled = true
	var offs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(64):
		offs.append(rng.randf_range(-0.015, 0.015))
	var sched := keyboard_schedule(g.chart.notes, offs)
	var stop_at := 22.5
	var bot := func() -> void:
		await run_schedule(c, sched, func() -> bool: return c.song_time() > stop_at)
	bot.call()
	await wait_until(func() -> bool: return c.song_time() > 1.0, 10.0)
	check("F3 overlay hidden by default", not g.debug_overlay.visible)
	await press_key(KEY_F3)
	check("F3 shows overlay (debug build)", g.debug_overlay.visible)
	await wait_until(func() -> bool: return c.song_time() > 14.0, 30.0)
	await shot("f3_overlay")
	await wait_until(func() -> bool: return c.song_time() > stop_at, 30.0)
	probe.enabled = false
	var errs: Array = g.debug_overlay.recent_errors()
	metrics["overlay_recent_errors_ms"] = errs
	check("overlay lists recent hit errors", errs.size() > 0, "%d listed" % errs.size())
	var a := clock_analysis(probe.rows, 1.5, 21.5)
	metrics["clock"] = a
	var dev: Dictionary = a["dsong_minus_dsys_ms"]
	check("song_time monotonic over ~20 s (no backwards steps)", int(a["backwards_steps"]) == 0, a["backwards_steps"])
	check("per-frame song_time delta tracks system delta (|dev| max < 4 ms)", float(dev["max_abs"]) < 4.0,
		"mean %.3f std %.3f max %.3f ms" % [dev["mean"], dev["std"], dev["max_abs"]])
	check("no clock snaps (> 50 ms error) during play", int(a["tracking_err_gt_50ms_frames"]) == 0, a["tracking_err_gt_50ms_frames"])
	# Recorded metric, not a gate (20 s is short for a p99; the drift run gates D-30).
	var sm := smooth_clock_error(probe.rows, 1.5, 21.5, 5.0)
	metrics["jitter"] = sm
	if not sm.is_empty():
		var j: Dictionary = sm["song_minus_smooth_audio_ms"]
		note("Jitter (song_time - smooth audio clock, %d frames): std %.3f p99 %.3f max %.3f ms" % [
			int(j["n"]), float(j["std"]), float(j["p99_abs"]), float(j["max_abs"])])
	_save_probe_csv("c_probe.csv")


func _save_probe_csv(fname: String) -> void:
	var f := FileAccess.open("%s/%s" % [OUT_DIR, fname], FileAccess.WRITE)
	f.store_line("ticks_usec,song_time,audio_valid,audio_target,raw_pos,paused,latency")
	for r in probe.rows:
		f.store_line("%d,%.6f,%d,%.6f,%.6f,%d,%.6f" % [r[0], r[1], int(r[2]), r[3], r[4], int(r[5]), r[6]])
	f.close()


# ------------------------------------------------------------------------------------------------
# d. pause / resume / countdown / confirm dialogs
# ------------------------------------------------------------------------------------------------


func sc_d() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	probe.conductor = c
	probe.enabled = true
	var sched := keyboard_schedule(g.chart.notes, [0.0])
	var gw: WeakRef = weakref(g)
	var bot := func() -> void:
		await run_schedule(c, sched, func() -> bool: return _gone_or_stopped(gw) or not scene_is(GAMEPLAY))
	bot.call()
	await wait_until(func() -> bool: return c.song_time() > 10.3, 20.0)
	var score_before := g.score.score
	await press_key(KEY_ESCAPE)
	var p0 := c.song_time()
	check("Esc opens pause menu and freezes conductor", g.pause_menu.is_open() and c.is_paused())
	check("pause menu focus on Resume Dive", focus_owner() == g.pause_menu.resume_button, focus_owner())
	var frozen: Array = []
	var t_end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < t_end:
		frozen.append(c.song_time())
		await frame()
	var max_dev := 0.0
	for v in frozen:
		max_dev = maxf(max_dev, absf(float(v) - p0))
	metrics["pause_song_time"] = p0
	metrics["pause_frozen_frames"] = frozen.size()
	check("song_time frozen for 3 s of real time while paused", max_dev == 0.0, "max change %.6f s over %d frames" % [max_dev, frozen.size()])
	check("audio stopped while paused", not (c.get("_player") as AudioStreamPlayer).playing)
	await shot("pause_menu")
	var cd_ticks: Array = []
	var cd_cb := func(n: int) -> void: cd_ticks.append([n, Time.get_ticks_usec()])
	c.countdown_tick.connect(cd_cb)
	var resumed_at := [-1, 0.0]
	c.resumed.connect(func() -> void: resumed_at[0] = Time.get_ticks_usec(); resumed_at[1] = c.song_time(), CONNECT_ONE_SHOT)
	var t_resume := Time.get_ticks_usec()
	await press_key(KEY_ESCAPE)
	check("Esc on open pause menu starts countdown", g.pause_menu.is_counting_down())
	await wait(0.25)
	await shot("countdown")
	var ok: bool = await wait_until(func() -> bool: return int(resumed_at[0]) > 0, 6.0)
	check("countdown completes and run resumes", ok)
	var seq: Array = []
	for e in cd_ticks:
		seq.append(e[0])
	var expected_cd := 3.0 * 60.0 / c.bpm_at(p0)
	var cd_len := (int(resumed_at[0]) - t_resume) / 1000000.0
	metrics["countdown_sequence"] = seq
	metrics["countdown_seconds"] = cd_len
	metrics["countdown_expected_seconds"] = expected_cd
	check("countdown ticks 3-2-1", seq == [3, 2, 1], seq)
	check("countdown lasts 3 beats at chart BPM (+-50 ms incl. frame quantisation)", absf(cd_len - expected_cd) < 0.05,
		"%.3f s vs %.3f s" % [cd_len, expected_cd])
	var jump := float(resumed_at[1]) - p0
	metrics["resume_song_time_minus_paused_ms"] = jump * 1000.0
	check("song_time continues from paused position (+-20 ms)", absf(jump) <= 0.020, "%.2f ms" % (jump * 1000.0))
	await wait(1.5)
	# audio restarted at the right place: compare audio target with song_time over the last 0.5 s
	var errs: Array = []
	var now_t := Time.get_ticks_usec()
	for r in probe.rows:
		if bool(r[2]) and int(r[0]) > now_t - 500000:
			errs.append((float(r[1]) - float(r[3])) * 1000.0)
	var es := stats(errs)
	metrics["post_resume_song_minus_audio_ms"] = es
	check("audio resumed from the paused position (|song_time - audio clock| < 20 ms)", errs.size() > 0 and float(es["max_abs"]) < 20.0, es)
	check("score kept across pause", g.score.score >= score_before, "%d -> %d" % [score_before, g.score.score])

	# Restart confirm
	await press_key(KEY_ESCAPE)
	check("pause again", g.pause_menu.is_open())
	await press_key(KEY_DOWN)
	check("focus Restart Dive", focus_owner() == g.pause_menu.restart_button, focus_owner())
	await press_key(KEY_ENTER)
	var dlg: ConfirmDialog = g.pause_menu.get("_dialog")
	check("Restart (score > 0) shows confirm dialog", dlg != null)
	if dlg != null:
		check("restart dialog initial focus on SAFE 'Keep Playing'", focus_owner() == dlg.safe_button and dlg.safe_button.text == "Keep Playing", focus_owner())
		await shot("restart_confirm")
		await press_key(KEY_ESCAPE)
		check("Esc in dialog = safe choice, focus back on Restart Dive", g.pause_menu.get("_dialog") == null and focus_owner() == g.pause_menu.restart_button and g.pause_menu.is_open())
	await press_key(KEY_DOWN)
	await press_key(KEY_DOWN)
	check("focus Back to Menu", focus_owner() == g.pause_menu.menu_button, focus_owner())
	await press_key(KEY_ENTER)
	dlg = g.pause_menu.get("_dialog")
	check("Back to Menu shows confirm dialog", dlg != null)
	if dlg != null:
		check("menu dialog initial focus on SAFE 'Stay'", focus_owner() == dlg.safe_button and dlg.safe_button.text == "Stay", focus_owner())
		await shot("menu_confirm")
		await press_key(KEY_LEFT)
		check("Left moves focus to 'Leave Dive'", focus_owner() == dlg.confirm_button, focus_owner())
		await press_key(KEY_ENTER)
		ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
		check("Leave Dive -> main menu", ok)
	probe.enabled = false


# ------------------------------------------------------------------------------------------------
# e. fail -> IMPLOSION, then No-Fail
# ------------------------------------------------------------------------------------------------


func sc_e() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var ok: bool = await wait_until(func() -> bool: return g.state == Gameplay.State.FAILED, 30.0)
	check("no input -> hull reaches 0 -> FAILED", ok and g.score.hull <= 0.0, "hull %.1f at song_time %.2f, misses %d" % [g.score.hull, g.conductor.song_time() if g.conductor else -1.0, g.score.miss_count])
	metrics["fail_song_time"] = g.conductor.song_time() if g.conductor else -1.0
	metrics["fail_misses"] = g.score.miss_count
	check("audio stopped on fail", not (g.conductor.get("_player") as AudioStreamPlayer).playing)
	await wait(1.2)
	var fs := g.fail_screen
	check("IMPLOSION screen", fs != null and fs.title_label.text == "IMPLOSION" and fs.modulate.a > 0.99, fs.title_label.text if fs else null)
	if fs != null:
		metrics["fail_body"] = fs.body_label.text
		check("fail screen focus on Retry Dive", focus_owner() == fs.retry_button, focus_owner())
	await shot("implosion")
	# Enable No-Fail (as the Settings toggle does) and retry via the focused Retry button.
	Settings.no_fail = true
	Settings.save_to(Settings.save_path)
	await press_key(KEY_ENTER)
	await wait_until(func() -> bool: return g.state == Gameplay.State.RUNNING and g.score != null and g.score.miss_count == 0, 5.0)
	check("Retry restarts the run", g.state == Gameplay.State.RUNNING)
	check("No-Fail applied to the new run", g.score.no_fail)
	await wait_until(func() -> bool: return g.score.hull <= 0.0, 30.0)
	await wait(0.5)
	await shot("nofail_hull_zero_still_running")
	check("hull 0 with No-Fail: play continues", g.state == Gameplay.State.RUNNING and g.score.hull <= 0.0 and g.conductor.song_time() > 0.0,
		"song_time %.2f" % g.conductor.song_time())
	ok = await wait_until(func() -> bool: return g.state == Gameplay.State.DONE, 75.0)
	check("No-Fail run reaches results", ok)
	await wait(0.6)
	if g.results != null:
		check("results show NO-FAIL USED", g.results.flags.has("NO-FAIL USED"), g.results.flags)
		metrics["nofail_results_rows"] = g.results.rows
	await shot("nofail_results")


# ------------------------------------------------------------------------------------------------
# f. gamepad: LB / LT / RT / RB, Start pauses
# ------------------------------------------------------------------------------------------------


func sc_f() -> void:
	isolate_settings(true)
	metrics["physical_joypads"] = Input.get_connected_joypads()
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	var presses := [0, 0, 0, 0]
	var releases := [0, 0, 0, 0]
	g.lane_input.lane_pressed.connect(func(l: int, _t: int) -> void: presses[l] += 1)
	g.lane_input.lane_released.connect(func(l: int, _t: int) -> void: releases[l] += 1)
	var judged := {}
	g.judge.judged.connect(func(_l: int, idx: int, jj: int, err: float) -> void: judged[idx] = [jj, err])
	# Notes in [1.0, 15.0) s; each lane uses its pad control.
	var notes: Array = g.chart.notes
	var sched: Array = []
	var expect_press := [0, 0, 0, 0]
	var used: Array = []
	for k in range(notes.size()):
		var n: Dictionary = notes[k]
		var t: float = n["time"]
		if t < 1.0 or t >= 15.0:
			continue
		var lane: int = n["lane"]
		var tail: float = t + maxf(float(n["duration"]), 0.08)
		expect_press[lane] += 1
		used.append(k)
		match lane:
			0, 3:
				var btn: int = JOY_BUTTON_LEFT_SHOULDER if lane == 0 else JOY_BUTTON_RIGHT_SHOULDER
				sched.append({"t": t, "o": 1, "fn": func() -> void: pad_button(btn, true)})
				# duplicate down (driver re-report) must not re-press
				sched.append({"t": t + 0.02, "o": 1, "fn": func() -> void: pad_button(btn, true)})
				sched.append({"t": tail, "o": 0, "fn": func() -> void: pad_button(btn, false)})
			1, 2:
				var ax: int = JOY_AXIS_TRIGGER_LEFT if lane == 1 else JOY_AXIS_TRIGGER_RIGHT
				# analog ramp; the first value >= 0.5 lands exactly on the note time
				var ramp_pre := [0.1, 0.25, 0.45]
				for i in range(ramp_pre.size()):
					var v: float = ramp_pre[i]
					sched.append({"t": t - 0.012 * (ramp_pre.size() - i), "o": 1, "fn": func() -> void: pad_axis(ax, v)})
				var after := [0.55, 0.8, 1.0, 1.0, 0.49, 0.52, 0.47, 0.51, 0.45]  # noise around 0.5 while held
				sched.append({"t": t, "o": 1, "fn": func() -> void: pad_axis(ax, 0.55)})
				for i in range(1, after.size()):
					var v2: float = after[i]
					sched.append({"t": t + 0.008 * i, "o": 1, "fn": func() -> void: pad_axis(ax, v2)})
				var rel := [0.42, 0.38, 0.2, 0.0]
				for i in range(rel.size()):
					var v3: float = rel[i]
					sched.append({"t": tail + 0.008 * i, "o": 0, "fn": func() -> void: pad_axis(ax, v3)})
	await run_schedule(c, sched, func() -> bool: return g.state != Gameplay.State.RUNNING)
	await wait(0.2)
	metrics["pad_presses_per_lane"] = presses
	metrics["pad_releases_per_lane"] = releases
	metrics["pad_expected_per_lane"] = expect_press
	check("LB/LT/RT/RB: exactly one press and one release per note (with trigger noise + duplicate downs)",
		presses == expect_press and releases == expect_press, "pressed %s released %s expected %s" % [presses, releases, expect_press])
	var perf := 0
	for k in used:
		if judged.has(k) and int(judged[k][0]) == InputJudge.Judgment.PERFECT:
			perf += 1
	check("all pad-played notes judged PERFECT", perf == used.size(), "%d / %d" % [perf, used.size()])
	check("no strays from pad input", g.score.stray_count == 0, g.score.stray_count)
	pad_button(JOY_BUTTON_START, true)
	await frame()
	pad_button(JOY_BUTTON_START, false)
	await frame()
	check("Start button pauses", g.pause_menu.is_open() and c.is_paused())
	await shot("pad_start_pause")


# ------------------------------------------------------------------------------------------------
# g. settings: rebind, duplicate, Tab, scroll, volumes, reset
# ------------------------------------------------------------------------------------------------


func sc_g() -> void:
	isolate_settings(true)
	await goto(MENU)
	await wait(0.3)
	var m := cur() as MainMenu
	m.start_button.grab_focus()
	for i in range(4):  # Start -> Practice -> Autoplay -> Calibrate -> Settings
		await press_key(KEY_DOWN)
	check("menu focus on Settings", focus_owner() == m.settings_button, focus_owner())
	await press_key(KEY_ENTER)
	var ok: bool = await wait_until(func() -> bool: return cur() is SettingsScreen, 5.0)
	if not check("Settings scene opens", ok):
		return
	await wait(0.3)
	var s := cur() as SettingsScreen
	await shot("settings")
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	check("initial focus on Lane 1 keyboard cell", focus_owner() == cell, focus_owner())
	await press_key(KEY_ENTER)
	check("Enter starts listening ('PRESS A KEY...')", cell.listening and cell.text == "PRESS A KEY...", cell.text)
	await shot("rebind_listening")
	await press_key(KEY_Q)
	check("Lane 1 rebound to Q (no longer 1)", not cell.listening and cell.text == "Q" and _action_has_key(&"lane_1", KEY_Q) and not _action_has_key(&"lane_1", KEY_1), cell.text)
	var cfg := ConfigFile.new()
	cfg.load(TEMP_SETTINGS)
	metrics["saved_lane_1_key"] = cfg.get_value("bindings", "lane_1_key", null)
	check("rebind persisted", int(cfg.get_value("bindings", "lane_1_key", 0)) == KEY_Q, metrics["saved_lane_1_key"])
	# duplicate
	await press_key(KEY_ENTER)
	await press_key(KEY_2)
	var msg := s.message_text(&"lane_1")
	check("duplicate (2 = Lane 2) rejected with inline message", msg.contains("2 is already used for Lane 2") and cell.text == "Q" and _action_has_key(&"lane_2", KEY_2), msg)
	await shot("rebind_duplicate_rejected")
	# Tab
	await press_key(KEY_ENTER)
	await press_key(KEY_TAB)
	msg = s.message_text(&"lane_1")
	check("Tab rejected with inline message", msg.contains("Tab can't be used") and cell.text == "Q", msg)
	await shot("rebind_tab_rejected")
	# Esc cancels listening
	await press_key(KEY_ENTER)
	await press_key(KEY_ESCAPE)
	check("Esc cancels listening with no change", not cell.listening and cell.text == "Q" and scene_is(SETTINGS_SCENE))

	# scroll speed
	s.scroll_slider.grab_focus()
	for i in range(6):
		await press_key(KEY_LEFT)
	check("scroll speed min 0.5x (clamped)", is_equal_approx(Settings.scroll_speed, 0.5), Settings.scroll_speed)
	await press_key(KEY_RIGHT, 3.2)
	check("scroll speed max 3.0x (hold Right)", is_equal_approx(Settings.scroll_speed, 3.0), Settings.scroll_speed)
	await shot("scroll_3x")
	for i in range(20):
		await press_key(KEY_LEFT)
	check("scroll back to 1.0x", is_equal_approx(Settings.scroll_speed, 1.0), Settings.scroll_speed)

	# volumes
	s.master_slider.grab_focus()
	for i in range(4):
		await press_key(KEY_LEFT)
	s.music_slider.grab_focus()
	for i in range(2):
		await press_key(KEY_LEFT)
	s.sfx_slider.grab_focus()
	await press_key(KEY_RIGHT)
	var mdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	var mudb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	metrics["bus_db"] = {"Master": mdb, "Music": mudb, "SFX": sdb}
	check("volumes: Master 80%, Music 70%, SFX 85% applied to buses",
		is_equal_approx(Settings.volume_master, 0.8) and is_equal_approx(Settings.volume_music, 0.7) and is_equal_approx(Settings.volume_sfx, 0.85)
		and absf(mdb - linear_to_db(0.8)) < 0.01 and absf(mudb - linear_to_db(0.7)) < 0.01 and absf(sdb - linear_to_db(0.85)) < 0.01,
		"%.0f/%.0f/%.0f%%  %.2f/%.2f/%.2f dB" % [Settings.volume_master * 100, Settings.volume_music * 100, Settings.volume_sfx * 100, mdb, mudb, sdb])
	cfg.load(TEMP_SETTINGS)
	check("volumes persisted", is_equal_approx(float(cfg.get_value("audio", "master", 0)), 0.8) and is_equal_approx(float(cfg.get_value("audio", "music", 0)), 0.7))

	# Reset controls
	s.reset_button.grab_focus()
	await press_key(KEY_ENTER)
	check("Reset Controls shows confirm with SAFE focus", s.dialog != null and focus_owner() == s.dialog.safe_button, focus_owner())
	await shot("reset_controls_confirm")
	await press_key(KEY_LEFT)
	await press_key(KEY_ENTER)
	check("Reset Controls restores Lane 1 = 1", s.dialog == null and cell.text == "1" and _action_has_key(&"lane_1", KEY_1), cell.text)
	await press_key(KEY_ESCAPE)
	ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	check("Esc in Settings -> back to main menu", ok)


func _action_has_key(action: StringName, code: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == code:
			return true
	return false


# ------------------------------------------------------------------------------------------------
# h. autoplay from menu; F4 mid-run
# ------------------------------------------------------------------------------------------------


func sc_h() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(true)
	if g == null:
		return
	check("autoplay run, lane input disabled, AUTOPLAY badge", g.autoplay and not g.lane_input.enabled and g.hud.is_autoplay_shown())
	var judged: Array = []
	g.judge.judged.connect(func(_l: int, _i: int, jj: int, err: float) -> void: judged.append([jj, err]))
	await wait_until(func() -> bool: return g.conductor.song_time() > 30.0, 40.0)
	await shot("autoplay_midsong")
	var ok: bool = await wait_until(func() -> bool: return g.state == Gameplay.State.DONE, 45.0)
	check("autoplay run reaches results", ok)
	await wait(0.6)
	await shot("autoplay_results")
	var sc := g.score
	var n := g.chart.notes.size()
	check("all notes PERFECT", sc.perfect_count == n and sc.good_count == 0 and sc.miss_count == 0,
		"P%d G%d M%d of %d" % [sc.perfect_count, sc.good_count, sc.miss_count, n])
	var max_err := 0.0
	for e in judged:
		max_err = maxf(max_err, absf(float(e[1])))
	metrics["autoplay_max_abs_err_ms"] = max_err * 1000.0
	check("autoplay errors are exactly 0", max_err == 0.0, max_err)
	check("results show AUTOPLAY USED", g.results != null and g.results.flags.has("AUTOPLAY USED"), g.results.flags if g.results else null)
	# Back to menu via results
	await press_key(KEY_DOWN)
	check("results focus Back to Menu", focus_owner() == g.results.menu_button, focus_owner())
	await press_key(KEY_ENTER)
	ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	check("results Back to Menu -> menu", ok)
	await wait(0.3)
	# F4 mid normal run
	g = await start_dive_from_menu(false)
	check("normal run starts without autoplay", not g.autoplay and g.lane_input.enabled and not g.hud.is_autoplay_shown())
	await wait_until(func() -> bool: return g.conductor.song_time() > 5.0, 10.0)
	var old_cond := g.conductor
	await press_key(KEY_F4)
	await frame()
	var st := g.conductor.song_time()
	check("F4 restarts the run with autoplay on", g.autoplay and g.autoplay_used and g.conductor != old_cond and st < 1.0 and g.hud.is_autoplay_shown(),
		"autoplay=%s song_time after F4=%.3f" % [g.autoplay, st])
	var j2: Array = [0, 0]
	g.judge.judged.connect(func(_l: int, _i: int, jj: int, _e: float) -> void:
		j2[0] += 1
		if jj == InputJudge.Judgment.PERFECT:
			j2[1] += 1)
	await wait_until(func() -> bool: return g.conductor.song_time() > 6.0, 10.0)
	await shot("f4_autoplay_restart")
	check("F4 autoplay run judges PERFECT", j2[0] > 5 and j2[0] == j2[1], "%d/%d" % [j2[1], j2[0]])


# ------------------------------------------------------------------------------------------------
# i. settings overlay from pause
# ------------------------------------------------------------------------------------------------


func sc_i() -> void:
	isolate_settings(true)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	var sched := keyboard_schedule(g.chart.notes, [0.0])
	var gw: WeakRef = weakref(g)
	var bot := func() -> void:
		await run_schedule(c, sched, func() -> bool: return _gone_or_stopped(gw) or c.song_time() > 25.0)
	bot.call()
	await wait_until(func() -> bool: return c.song_time() > 12.2, 20.0)
	await press_key(KEY_ESCAPE)
	var p0 := c.song_time()
	var score0 := g.score.score
	var combo0 := g.score.combo
	await press_key(KEY_DOWN)
	await press_key(KEY_DOWN)
	check("focus Settings in pause menu", focus_owner() == g.pause_menu.settings_button, focus_owner())
	await press_key(KEY_ENTER)
	await wait(0.3)
	check("Settings opens as overlay over the paused run", g.pause_menu.has_settings_overlay() and scene_is(GAMEPLAY) and c.is_paused())
	var ss: SettingsScreen = null
	var ov: CanvasLayer = g.pause_menu.get("_overlay")
	if ov != null and ov.get_child_count() > 0:
		ss = ov.get_child(0) as SettingsScreen
	check("overlay is SettingsScreen in overlay mode with Re-run Calibration disabled", ss != null and ss.overlay and ss.recalibrate_button.disabled)
	await shot("settings_overlay_over_pause")
	await wait(1.0)
	check("song_time frozen under overlay", c.song_time() == p0)
	await press_key(KEY_ESCAPE)
	await frame()
	check("closing overlay returns to pause menu, focus on Settings", not g.pause_menu.has_settings_overlay() and g.pause_menu.is_open() and focus_owner() == g.pause_menu.settings_button, focus_owner())
	await press_key(KEY_UP)
	await press_key(KEY_UP)
	check("focus Resume Dive", focus_owner() == g.pause_menu.resume_button, focus_owner())
	var res := [0.0]
	c.resumed.connect(func() -> void: res[0] = c.song_time(), CONNECT_ONE_SHOT)
	await press_key(KEY_ENTER)
	var ok: bool = await wait_until(func() -> bool: return float(res[0]) > 0.0, 6.0)
	check("Resume Dive -> countdown -> resumed", ok)
	metrics["resume_jump_ms"] = (float(res[0]) - p0) * 1000.0
	check("resumes from the same place (+-20 ms)", absf(float(res[0]) - p0) <= 0.02, "%.2f ms" % ((float(res[0]) - p0) * 1000.0))
	check("score and combo intact after overlay", g.score.score == score0 and g.score.combo == combo0, "%d/%d -> %d/%d" % [score0, combo0, g.score.score, g.score.combo])
	await wait_until(func() -> bool: return c.song_time() > p0 + 4.0, 10.0)
	check("run continues and scores after resume", g.score.score > score0 and g.score.miss_count == 0, "score %d misses %d" % [g.score.score, g.score.miss_count])


# ------------------------------------------------------------------------------------------------
# drift: shipped drift harness, full 5 minutes, instrumented by the frame probe
# ------------------------------------------------------------------------------------------------


func sc_drift() -> void:
	isolate_settings(true)
	if not await goto(DRIFT):
		check("drift harness scene loads", false)
		return
	var h := cur()
	probe.conductor = h.get("conductor")
	probe.enabled = true
	await wait_until(func() -> bool: return bool(h.get("_finished")), 320.0)
	probe.enabled = false
	check("drift harness ran to completion (300 s)", bool(h.get("_finished")))
	# Keep a copy: the gdUnit suite (test_gameplay_smoke) rewrites user://drift_log.csv.
	DirAccess.copy_absolute(ProjectSettings.globalize_path(DriftHarness.LOG_PATH),
		ProjectSettings.globalize_path(OUT_DIR + "/drift_log_copy.csv"))
	await shot("drift_harness_done")
	_save_probe_csv("drift_probe.csv")
	var a := clock_analysis(probe.rows, 1.0, 299.5)
	metrics["probe"] = a
	# CSV written by the game
	var f := FileAccess.open(DriftHarness.LOG_PATH, FileAccess.READ)
	var xs: Array = []
	var ds: Array = []
	if f != null:
		f.get_line()
		while not f.eof_reached():
			var line := f.get_line()
			if line.strip_edges() == "":
				continue
			var p := line.split(",")
			xs.append(float(p[0]))
			ds.append(float(p[2]))
	var steady_x: Array = []
	var steady_d: Array = []
	for i in range(xs.size()):
		if float(xs[i]) >= 1.0:
			steady_x.append(xs[i])
			steady_d.append(ds[i])
	var dst := stats(steady_d)
	var fit := linfit(steady_x, steady_d)
	metrics["csv_rows"] = xs.size()
	metrics["csv_drift_ms_t_ge_1s"] = dst
	metrics["csv_drift_fit"] = fit
	metrics["csv_drift_trend_ms_per_min"] = float(fit.get("b", 0.0)) * 60.0
	if not steady_d.is_empty():
		metrics["csv_drift_first_last_ms"] = [steady_d[0], steady_d[steady_d.size() - 1]]
	check("drift_log.csv covers 300 s", xs.size() >= 300, xs.size())
	# D-30 reference is the smooth (fitted) audio clock, as in analyze_probe.py. The instantaneous
	# audio target itself steps in 10.67 ms mix chunks (std ~3.2 ms, max ~15 ms in the first run), so
	# it is recorded as a metric (probe.song_minus_audio_target_ms) but cannot be a +-2 ms reference.
	var sm := smooth_clock_error(probe.rows, 1.0, 299.5, 60.0)
	metrics["jitter"] = sm
	var tr: Dictionary = sm.get("song_minus_smooth_audio_ms", {"n": 0, "mean": INF, "std": INF, "p99_abs": INF, "max_abs": INF})
	check("D-30: song_time - smooth audio clock p99 <= 2.0 ms (t >= 1 s)", float(tr["p99_abs"]) <= 2.0,
		"mean %.3f std %.3f p99 %.3f max %.3f ms over %d frames" % [tr["mean"], tr["std"], tr["p99_abs"], tr["max_abs"], int(tr["n"])])
	check("D-30 strict: max |song_time - smooth audio clock| <= 2 ms every frame", float(tr["max_abs"]) <= 2.0, "max %.3f ms" % tr["max_abs"])
	var wins: Array = sm.get("windows", [])
	var win_p99: Array = []
	for wd in wins:
		if int(wd["n"]) >= 1000:
			win_p99.append(snappedf(float(wd["p99_abs"]), 0.001))
	check("jitter flat across 60 s windows (every window p99 <= 2.0 ms)", win_p99.size() >= 4 and (win_p99.max() as float) <= 2.0, win_p99)
	check("song_time monotonic for 5 min", int(a["backwards_steps"]) == 0, a["backwards_steps"])
	check("no clock snaps in 5 min", int(a["tracking_err_gt_50ms_frames"]) == 0, a["tracking_err_gt_50ms_frames"])
	var trend := float(fit.get("b", 0.0)) * 60.0
	check("drift trend near 0 (|trend| <= 0.5 ms/min over drift_log.csv)", not fit.is_empty() and absf(trend) <= 0.5, "%.4f ms/min" % trend)
	check("audio clock vs system clock within 100 ppm", absf(float(a.get("audio_vs_system_rate_ppm", INF))) <= 100.0,
		"%.2f ppm" % float(a.get("audio_vs_system_rate_ppm", INF)))
	var spread := float(dst.get("max", 0.0)) - float(dst.get("min", 0.0))
	metrics["csv_drift_spread_ms"] = spread
	note("Raw audio clock vs system clock rate: %.1f ppm (%.2f ms over 300 s). song_time follows the audio clock by design, so song_time - system elapsed tracks this." % [
		float(a.get("audio_vs_system_rate_ppm", 0.0)), float(a.get("audio_vs_system_rate_ppm", 0.0)) * 300.0 / 1000.0])


# ------------------------------------------------------------------------------------------------
# layout: every modal overlay must be viewport-sized, dimmed (alpha >= 0.7) and block the mouse
# (gap 1, plan 01-08). Asserts, not just evidence.
# ------------------------------------------------------------------------------------------------


func _rect(c: Control) -> String:
	return str(c.get_global_rect()) if c != null and is_instance_valid(c) else "null"


func _find_dim(root: Node, vp: Vector2) -> ColorRect:
	var best: ColorRect = null
	for n in root.find_children("*", "ColorRect", true, false):
		var cr := n as ColorRect
		if cr.is_visible_in_tree() and cr.get_global_rect().size.is_equal_approx(vp) \
				and cr.get_global_rect().position.is_equal_approx(Vector2.ZERO):
			if best == null or cr.color.a > best.color.a:
				best = cr
	return best


## Synthetic left click at (5, 5) with a probe Button placed behind the overlay under `host`.
## Returns true when the click did NOT reach the probe.
func _click_blocked(host: Control) -> bool:
	var probe_btn := Button.new()
	probe_btn.name = "PlaytestClickProbe"
	probe_btn.custom_minimum_size = Vector2(100.0, 100.0)
	probe_btn.position = Vector2.ZERO
	probe_btn.focus_mode = Control.FOCUS_NONE
	host.add_child(probe_btn)
	host.move_child(probe_btn, 0)
	var hits := [0]
	probe_btn.pressed.connect(func() -> void: hits[0] += 1)
	await frame()
	await frame()
	var vp := host.get_viewport()
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(5.0, 5.0)
	mm.global_position = mm.position
	vp.push_input(mm)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = Vector2(5.0, 5.0)
		mb.global_position = mb.position
		vp.push_input(mb)
	await frame()
	await frame()
	probe_btn.queue_free()
	return hits[0] == 0


## Asserts the three gap-1 properties for one overlay and records its rect in layout.json.
## `root` is the overlay node itself, `modal` the node that must stop the mouse (may equal root).
func _assert_overlay(label: String, root: Control, modal: Control, host: Control) -> void:
	var vp := get_viewport().get_visible_rect().size
	if not check("%s exists" % label, root != null and is_instance_valid(root) and modal != null and is_instance_valid(modal)):
		return
	await frame()
	var dim := _find_dim(modal, vp)
	var entry := {"root_rect": _rect(root), "modal_rect": _rect(modal),
		"dim_alpha": dim.color.a if dim != null else -1.0, "mouse_filter": modal.mouse_filter}
	check("%s global rect == viewport %s" % [label, vp],
		root.get_global_rect().size.is_equal_approx(vp) and root.get_global_rect().position.is_equal_approx(Vector2.ZERO)
		and modal.get_global_rect().size.is_equal_approx(vp), "%s / modal %s" % [entry["root_rect"], entry["modal_rect"]])
	check("%s dim ColorRect covers the viewport, alpha >= 0.7" % label, dim != null and dim.color.a >= 0.7 - 0.0001,
		"alpha %.3f" % float(entry["dim_alpha"]))
	var blocked: bool = await _click_blocked(host)
	entry["click_at_5_5_blocked"] = blocked
	check("%s blocks a click at (5, 5) from reaching a control behind it" % label, blocked)
	var overlays: Dictionary = metrics.get("overlays", {})
	overlays[label] = entry
	metrics["overlays"] = overlays


func sc_layout() -> void:
	isolate_settings(true)
	var vp := get_viewport().get_visible_rect().size
	metrics["viewport"] = str(vp)
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	var run_root: Control = g.get("_run_root")
	metrics["gameplay_rect"] = _rect(g)
	metrics["run_root_rect"] = _rect(run_root)
	check("gameplay root fills the viewport", g.size.is_equal_approx(vp), metrics["gameplay_rect"])
	check("run root fills the viewport", run_root.size.is_equal_approx(vp), metrics["run_root_rect"])
	# Score some notes so Restart asks for confirmation (score > 0), then stop playing.
	var stop_bot := [false]
	var gw: WeakRef = weakref(g)
	var sched := keyboard_schedule(g.chart.notes, [0.0])
	var bot := func() -> void:
		await run_schedule(c, sched, func() -> bool: return stop_bot[0] or _gone_or_stopped(gw) or not scene_is(GAMEPLAY))
	bot.call()
	await wait_until(func() -> bool: return c.song_time() > 4.0 and g.score.score > 0, 15.0)

	# Pause menu
	await press_key(KEY_ESCAPE)
	check("Esc opens pause menu", g.pause_menu.is_open())
	var panel: Control = g.pause_menu.get("_panel_root")
	await _assert_overlay("PauseMenu", g.pause_menu, panel, g)
	await shot("pause_menu")

	# Restart confirm (score > 0)
	g.pause_menu.restart_button.grab_focus()
	await press_key(KEY_ENTER)
	var dlg: ConfirmDialog = g.pause_menu.get("_dialog")
	check("Restart Dive asks for confirmation (score %d)" % g.score.score, dlg != null)
	await _assert_overlay("ConfirmDialog(restart)", dlg, dlg, g)
	await shot("restart_confirm")
	await press_key(KEY_ESCAPE)
	check("Esc on restart confirm = Keep Playing (dialog closed, still paused)",
		g.pause_menu.get("_dialog") == null and g.pause_menu.is_open())

	# Back to Menu confirm
	g.pause_menu.menu_button.grab_focus()
	await press_key(KEY_ENTER)
	dlg = g.pause_menu.get("_dialog")
	await _assert_overlay("ConfirmDialog(menu)", dlg, dlg, g)
	await shot("menu_confirm")
	await press_key(KEY_ESCAPE)
	check("Esc on menu confirm = Stay", g.pause_menu.get("_dialog") == null and g.pause_menu.is_open())

	# Fail screen: resume, stop the bot, let the hull reach 0.
	stop_bot[0] = true
	await press_key(KEY_ESCAPE)
	var failed: bool = await wait_until(func() -> bool: return g.state == Gameplay.State.FAILED, 40.0)
	check("hull reaches 0 -> FAILED", failed)
	await wait(1.0)
	await _assert_overlay("FailScreen", g.fail_screen, g.fail_screen, g)
	await shot("implosion")

	# Results screen: autoplay run to the end.
	await goto(MENU)
	var g2: Gameplay = await start_dive_from_menu(true)
	if g2 == null:
		return
	var done: bool = await wait_until(func() -> bool: return g2.state == Gameplay.State.DONE, 120.0)
	check("autoplay run reaches results", done)
	await wait(0.8)
	await _assert_overlay("ResultsScreen", g2.results, g2.results, g2)
	await shot("results")

	# Reset Controls confirm in Settings.
	if not await goto(SETTINGS_SCENE):
		check("settings scene loads", false)
		return
	var s := cur() as Control
	var reset_btn: Button = s.get("reset_button")
	reset_btn.grab_focus()
	await press_key(KEY_ENTER)
	var rdlg: ConfirmDialog = s.get("dialog")
	check("Reset Controls asks for confirmation", rdlg != null)
	await _assert_overlay("ConfirmDialog(reset_controls)", rdlg, rdlg, s)
	await shot("reset_controls_confirm")
	await press_key(KEY_ESCAPE)
	check("Esc on Reset Controls confirm = Keep Bindings", s.get("dialog") == null)


# ------------------------------------------------------------------------------------------------
# polish (Phase 1.1): lane colors, receptors, ready brightening, streak, fullscreen,
# records, practice entry. Screenshots feed the human look/feel checkpoint (01.1-05 Task 4).
# ------------------------------------------------------------------------------------------------


## Viewport image pixel for a design-space (1920x1080) point; stretch mode is canvas_items + keep.
func _img_px(img: Image, design: Vector2) -> Color:
	var isz := Vector2(img.get_width(), img.get_height())
	var sc := minf(isz.x / Highway.SCREEN_W, isz.y / Highway.SCREEN_H)
	var off := (isz - Vector2(Highway.SCREEN_W, Highway.SCREEN_H) * sc) * 0.5
	var p := (off + design * sc).floor()
	return img.get_pixel(clampi(int(p.x), 0, img.get_width() - 1), clampi(int(p.y), 0, img.get_height() - 1))


func _chan_max(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## Mean color of a (2r+1)^2 design-pixel patch (anti-aliasing tolerant center sample).
func _patch(img: Image, center: Vector2, r: int = 2) -> Color:
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			acc += _img_px(img, center + Vector2(dx, dy))
			n += 1
	return acc / float(n)


## Brightest channel value anywhere in a square design-space region.
func _region_max(img: Image, center: Vector2, r: float, step: float = 2.0) -> float:
	var best := 0.0
	var y := -r
	while y <= r:
		var x := -r
		while x <= r:
			best = maxf(best, _chan_max(_img_px(img, center + Vector2(x, y))))
			x += step
		y += step
	return best


## Median brightest-channel value along the curved hit ring (every 4th ring point, 5x5 patches).
func _ring_median(img: Image) -> float:
	var vals: Array = []
	var pts := Trench.ring_points()
	var i := 0
	while i < pts.size():
		vals.append(_chan_max(_patch(img, pts[i], 2)))
		i += 4
	vals.sort()
	return float(vals[vals.size() / 2])


## Mean and max abs brightest-channel difference over a grid covering the lanes (x 480..1440, y 396..1040).
func _highway_diff(a: Image, b: Image) -> Dictionary:
	var mx := 0.0
	var sa := 0.0
	var sb := 0.0
	var n := 0
	var y := 396.0
	while y < 1040.0:
		var x := 480.0
		while x < 1440.0:
			var va := _chan_max(_img_px(a, Vector2(x, y)))
			var vb := _chan_max(_img_px(b, Vector2(x, y)))
			mx = maxf(mx, absf(va - vb))
			sa += va
			sb += vb
			n += 1
			x += 8.0
		y += 8.0
	return {"max_abs_diff": mx, "mean_full": sa / n, "mean_low_effects": sb / n, "samples": n}


## Pending notes visible in the last captured frame: {i, lane, dt, d, y, ready, center}.
func _visible_pending(g: Gameplay) -> Array:
	var out: Array = []
	var notes: Array = g.chart.notes
	var vt := last_shot_st + Settings.visual_offset
	var approach := Trench.approach_for(Settings.scroll_speed)
	var cfg := JudgeConfig.new()
	for i in range(notes.size()):
		if i >= last_shot_state.size() or last_shot_state[i] != Highway.S_PENDING:
			continue
		var n: Dictionary = notes[i]
		var d := Trench.depth_for(float(n["time"]), vt, approach)
		if d < -0.05 or d > 1.0:
			continue
		var dt := float(n["time"]) - last_shot_st
		var lane: int = n["lane"]
		var pos := Trench.point(Trench.lane_f(lane), d)
		out.append({"i": i, "lane": lane, "dt": dt, "d": d, "y": pos.y,
			"ready": Highway.note_is_ready(dt, cfg.good_window), "center": pos})
	return out



func _far_note(vis: Array, lane: int = -1) -> Dictionary:
	for v in vis:
		if float(v["dt"]) > 0.30 and float(v["d"]) > 0.15 and (lane < 0 or int(v["lane"]) == lane):
			return v
	return {}


func _pending_dt_within(g: Gameplay, lo: float, hi: float) -> bool:
	var st := g.conductor.song_time()
	var notes: Array = g.chart.notes
	for i in range(notes.size()):
		if g.highway._state[i] != Highway.S_PENDING:
			continue
		var dt := float(notes[i]["time"]) - st
		if dt > hi:
			return false
		if dt >= lo:
			return true
	return false


func sc_polish() -> void:
	isolate_settings(true)
	_use_temp_scores(POLISH_SCORES)
	metrics["scores_path"] = ScoreStore.default_path
	# --- main menu --------------------------------------------------------------------------
	await goto(MENU)
	await wait(0.4)
	var m := cur() as MainMenu
	if not check("main menu shown", m != null, cur()):
		return
	var box := m.start_button.get_parent()
	check("Practice Dive (No-Fail) sits directly after Start Dive",
		m.practice_button != null and m.practice_button.text == "Practice Dive (No-Fail)"
		and m.practice_button.get_parent() == box and m.practice_button.get_index() == m.start_button.get_index() + 1,
		"start #%d, practice #%d" % [m.start_button.get_index(), m.practice_button.get_index() if m.practice_button else -1])
	check("menu best line shows the empty-state copy (fresh temp record book)",
		m.best_label != null and m.best_label.text == MainMenu.NO_RECORD_COPY, m.best_label.text if m.best_label else null)
	await shot("menu")

	# --- practice entry ---------------------------------------------------------------------
	m.start_button.grab_focus()
	await press_key(KEY_DOWN)
	check("Down from Start Dive focuses Practice Dive", focus_owner() == m.practice_button, focus_owner())
	await press_key(KEY_ENTER)
	var ok: bool = await wait_until(func() -> bool: return cur() is Gameplay, 5.0)
	if not check("Practice Dive opens gameplay", ok, cur()):
		return
	var pg := cur() as Gameplay
	await wait_until(func() -> bool: return pg.conductor.song_time() > 2.0, 10.0)
	check("practice run: Gameplay.practice, score.no_fail on, persisted Settings.no_fail untouched",
		pg.practice and pg.score.no_fail and not Settings.no_fail,
		"practice=%s score.no_fail=%s Settings.no_fail=%s" % [pg.practice, pg.score.no_fail, Settings.no_fail])
	await shot("practice_hud")
	await goto(MENU)
	await wait(0.3)

	# --- normal dive with the keyboard bot ------------------------------------------------------
	var g: Gameplay = await start_dive_from_menu(false)
	if g == null:
		return
	var c := g.conductor
	var gw: WeakRef = weakref(g)
	var last_press := [-1]
	g.lane_input.lane_pressed.connect(func(_l: int, _t: int) -> void: last_press[0] = Time.get_ticks_usec())
	var sched := keyboard_schedule(g.chart.notes, [0.0])
	var bot := func() -> void:
		await run_schedule(c, sched, func() -> bool: return _gone_or_stopped(gw))
	bot.call()
	# Streak watcher runs alongside: popup shot the instant combo first reaches 10, big counter at 25.
	var streak_done := [false]
	var streak := func() -> void:
		var hit10: bool = await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.score.combo >= 10, 60.0)
		if hit10 and not _gone_or_stopped(gw):
			var popup := g.streak_counter.popup_text()
			metrics["streak_at_10"] = {"combo": g.score.combo, "popup": popup, "number": g.streak_counter.number_text()}
			check("combo 10 -> '10 STREAK' milestone popup", popup == "10 STREAK", popup)
			check("NOTE STREAK counter visible at combo 10", g.streak_counter.is_counter_visible())
			await shot("streak_10_popup", g)
		var hit25: bool = await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.score.combo >= 25, 60.0)
		if hit25 and not _gone_or_stopped(gw):
			metrics["streak_at_25"] = {"combo": g.score.combo, "popup": g.streak_counter.popup_text(),
				"number": g.streak_counter.number_text()}
			await shot("streak_counter_big", g)
		else:
			note("combo 25 not reached before the run ended")
		streak_done[0] = true
	streak.call()

	# Far (dim) note: capture until a pending note > 0.30 s out is on screen, then save the shot.
	var far_sample := {}
	for attempt in range(40):
		await wait_until(func() -> bool: return _gone_or_stopped(gw) or _pending_dt_within(g, 0.32, 1.1), 10.0)
		if _gone_or_stopped(gw):
			break
		await shot("notes_far_dim", g)
		var f := _far_note(_visible_pending(g))
		if not f.is_empty():
			far_sample = f
			far_sample["color"] = _patch(last_img, f["center"])
			break
		DirAccess.remove_absolute(shots.pop_back())
		await frame()
	if check("captured a pending note more than 0.30 s from the hit line", not far_sample.is_empty(), far_sample):
		note("far note #%d lane %d dt %.3f s: center %s" % [far_sample["i"], far_sample["lane"], far_sample["dt"],
			(far_sample["color"] as Color).to_html(false)])
	# In-window (bright) note.
	var ready_sample := {}
	var far_same := {}
	for attempt in range(40):
		await wait_until(func() -> bool: return _gone_or_stopped(gw) or _pending_dt_within(g, 0.0, 0.03), 10.0)
		if _gone_or_stopped(gw):
			break
		await shot("note_in_window_bright", g)
		var vis := _visible_pending(g)
		for v in vis:
			if bool(v["ready"]) and float(v["dt"]) > -0.02:
				ready_sample = v
				break
		if not ready_sample.is_empty():
			ready_sample["color"] = _patch(last_img, ready_sample["center"])
			far_same = _far_note(vis, int(ready_sample["lane"]))
			if not far_same.is_empty():
				far_same["color"] = _patch(last_img, far_same["center"])
			break
		# Not usable (note judged before the frame was drawn): drop the file and retry.
		DirAccess.remove_absolute(shots.pop_back())
	if check("captured a pending note inside the Good window", not ready_sample.is_empty(), ready_sample):
		var ref: Dictionary = far_same if not far_same.is_empty() else far_sample
		var rc: Color = ready_sample["color"]
		var fc: Color = ref.get("color", Color.BLACK)
		var ratio := _chan_max(rc) / maxf(_chan_max(fc), 0.001)
		metrics["ready_vs_far"] = {"ready_note": ready_sample["i"], "ready_lane": ready_sample["lane"],
			"ready_dt_ms": float(ready_sample["dt"]) * 1000.0, "ready_center": rc.to_html(false),
			"far_note": ref.get("i", -1), "far_lane": ref.get("lane", -1), "far_center": fc.to_html(false),
			"same_lane_same_frame": not far_same.is_empty(), "ratio": ratio}
		note("ready note #%d lane %d dt %.1f ms center %s vs far note lane %d center %s -> x%.2f" % [
			ready_sample["i"], ready_sample["lane"], float(ready_sample["dt"]) * 1000.0, rc.to_html(false),
			int(ref.get("lane", -1)), fc.to_html(false), ratio])
		check("in-window note center is >= 20% brighter than a far note (brightest channel)", ratio >= 1.2, "x%.2f" % ratio)
	# Receptors with a visible pulse.
	var pulsed: bool = await wait_until(func() -> bool:
		return _gone_or_stopped(gw) or (last_press[0] > 0 and Time.get_ticks_usec() - last_press[0] < 30000), 10.0)
	if check("lane press observed for the receptor shot", pulsed and not _gone_or_stopped(gw)):
		await shot("receptors_lane_colors", g)
		var lane_vals: Array = []
		var all_lit := true
		for i in range(Highway.LANES):
			var v := _region_max(last_img, Trench.hit_point(i), 44.0)
			lane_vals.append(snappedf(v, 0.001))
			all_lit = all_lit and v > 0.25
		metrics["receptor_row_brightness"] = lane_vals
		check("receptor row is lit in all four lanes (non-black at the hit ring)", all_lit, lane_vals)
	# Fullscreen / windowed toggle on the real window.
	if not _gone_or_stopped(gw):
		metrics["window_mode_start"] = DisplayServer.window_get_mode()
		Settings.set_fullscreen(false)
		await wait(0.5)
		var mode := DisplayServer.window_get_mode()
		var wsize := DisplayServer.window_get_size()
		metrics["windowed"] = {"mode": mode, "size": str(wsize), "pos": str(DisplayServer.window_get_position())}
		check("set_fullscreen(false) -> windowed", mode == DisplayServer.WINDOW_MODE_WINDOWED, mode)
		check("windowed size is 1600x900", wsize == Vector2i(1600, 900), wsize)
		await shot("windowed_1600x900", g)
		Settings.set_fullscreen(true)
		await wait(0.5)
		check("set_fullscreen(true) -> fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.window_get_mode())
		await press_key(KEY_F11)
		await wait(0.5)
		var f11_off := not Settings.fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
		await press_key(KEY_F11)
		await wait(0.5)
		var f11_on := Settings.fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		check("F11 toggles fullscreen -> windowed -> fullscreen", f11_off and f11_on, "off=%s on=%s" % [f11_off, f11_on])
		var cfg := ConfigFile.new()
		cfg.load(TEMP_SETTINGS)
		check("fullscreen flag persisted to the temp settings file", bool(cfg.get_value("display", "fullscreen", false)))
	# Let the run finish: the bot dive is eligible, so it sets the first record.
	var done: bool = await wait_until(func() -> bool: return not is_instance_valid(g) or g.state != Gameplay.State.RUNNING, 90.0)
	check("bot dive finishes (DONE)", done and is_instance_valid(g) and g.state == Gameplay.State.DONE,
		g.state if is_instance_valid(g) else "freed")
	await wait_until(func() -> bool: return streak_done[0], 5.0)
	if not is_instance_valid(g) or g.state != Gameplay.State.DONE:
		return
	await wait(0.6)
	metrics["bot_record_info"] = g.record_info
	metrics["bot_score"] = {"depth": g.score.depth(), "max_combo": g.score.max_combo, "perfect": g.score.perfect_count,
		"good": g.score.good_count, "miss": g.score.miss_count}
	check("eligible bot dive set the first record (NEW RECORD, no previous)",
		bool(g.record_info.get("new_record", false)) and float(g.record_info.get("previous_depth", 0.0)) < 0.0
		and g.results != null and g.results.record_banner != null, g.record_info)
	await shot("results_first_record")
	var first_depth := g.score.depth()

	# --- records / results layouts ----------------------------------------------------------------
	await goto(MENU)
	await wait(0.3)
	var store := ScoreStore.new()
	store.load()
	var cfgj := JudgeConfig.new()
	var hs := HullScore.new(cfgj)
	hs.perfect_count = 61
	hs.good_count = 9
	hs.miss_count = 2
	hs.max_combo = 48
	hs.score = int((first_depth + 250.0) * cfgj.score_per_meter)
	hs.hull = 82.0
	var acc := ScoreStore.accuracy(hs.perfect_count, hs.good_count, hs.miss_count)
	var res := store.submit(TestCharts.HAND_CHART_ID, hs.depth(), acc, hs.max_combo, true, "2026-10-08")
	var prev: Dictionary = res["previous"]
	var info := {"eligible": true, "new_record": res["new_record"],
		"previous_depth": float(prev["depth"]) if not prev.is_empty() else -1.0,
		"best_depth": float(store.best(TestCharts.HAND_CHART_ID)["depth"])}
	check("second submit beats the first record (previous = bot dive depth)",
		bool(res["new_record"]) and absf(float(info["previous_depth"]) - first_depth) < 1.0, info)
	var rs := ResultsScreen.new()
	get_tree().root.add_child(rs)
	rs.setup(hs, false, info, false)
	await wait(0.5)
	check("results show NEW RECORD and a Previous best row",
		rs.record_banner != null and rs.rows.any(func(r: Array) -> bool: return r[0] == "Previous best"), rs.rows)
	await shot("results_new_record")
	rs.queue_free()
	await frame()
	var ps := HullScore.new(cfgj)
	ps.no_fail = true
	ps.perfect_count = 40
	ps.good_count = 12
	ps.miss_count = 20
	ps.max_combo = 22
	ps.score = int(900.0 * cfgj.score_per_meter)
	ps.hull = 0.0
	var pres := store.submit(TestCharts.HAND_CHART_ID, ps.depth(), 50.0, ps.max_combo,
		ScoreStore.is_eligible(false, ps.no_fail, true))
	var pinfo := {"eligible": false, "new_record": pres["new_record"], "previous_depth": -1.0,
		"best_depth": float(store.best(TestCharts.HAND_CHART_ID)["depth"])}
	check("practice run is not recorded", not bool(pres["recorded"]) and not bool(pres["new_record"]), pres)
	var prs := ResultsScreen.new()
	get_tree().root.add_child(prs)
	prs.setup(ps, false, pinfo, true)
	await wait(0.4)
	check("practice results: PRACTICE DIVE flag and 'Not recorded' note",
		prs.flags.has("PRACTICE DIVE") and prs.note_label != null and prs.note_label.text.begins_with("Not recorded"),
		[prs.flags, prs.note_label.text if prs.note_label else null])
	await shot("results_practice_not_recorded")
	prs.queue_free()
	await frame()
	var fs := FailScreen.new()
	get_tree().root.add_child(fs)
	var saved_best := float(store.best(TestCharts.HAND_CHART_ID)["depth"])
	fs.setup(612.0, 17, saved_best)
	fs.play(0.0)
	await wait(0.6)
	check("IMPLOSION shows run stats and saved best",
		fs.stats_label.text == "Max combo: 17" and fs.best_label.text.begins_with("Saved best: "),
		[fs.stats_label.text, fs.best_label.text])
	await shot("implosion_stats")
	fs.queue_free()
	await frame()
	await goto(MENU)
	await wait(0.4)
	m = cur() as MainMenu
	var expect := "Best: %s m" % Palette.fmt_depth(int(saved_best))
	check("menu best line shows the saved best", m != null and m.best_label.text.begins_with(expect),
		m.best_label.text if m else null)
	await shot("menu_best_line")
	check("records stayed in the temp record book (real scores.cfg path unused)",
		ScoreStore.default_path == POLISH_SCORES, ScoreStore.default_path)


# ------------------------------------------------------------------------------------------------
# immersion (Phase 1.2): goggles intro, skip / quick retry timing, curved Trench board at three
# scroll speeds, HUD streak / critical, Low effects, edge cleanliness, fps, reduce motion.
# ------------------------------------------------------------------------------------------------


func _bpm_of(g: Gameplay) -> float:
	if g.chart.tempo_map.is_empty():
		return 120.0
	return maxf(float(g.chart.tempo_map[0]["bpm"]), 1.0)


## Seconds since `t0_ms` (Time.get_ticks_msec) elapsed.
func _since(t0_ms: int) -> float:
	return (Time.get_ticks_msec() - t0_ms) / 1000.0


func _wait_elapsed(t0_ms: int, secs: float) -> void:
	while _since(t0_ms) < secs:
		await get_tree().process_frame


func _intro_alive(g: Gameplay) -> bool:
	return is_instance_valid(g) and g.intro != null and is_instance_valid(g.intro)


## Pauses the conductor `lead` seconds before the next pending note (>= min_ahead away). Returns the
## note index, or -1. Input is disabled so the frame stays frozen for pixel sampling.
func _freeze_before_note(g: Gameplay, lead: float = 0.002, min_ahead: float = 0.15) -> int:
	var st := g.conductor.song_time()
	var pick := -1
	for i in range(g.chart.notes.size()):
		if g.highway._state[i] == Highway.S_PENDING and float(g.chart.notes[i]["time"]) > st + min_ahead:
			pick = i
			break
	if pick < 0:
		return -1
	var gw: WeakRef = weakref(g)
	var c := g.conductor
	var sched := [{"t": float(g.chart.notes[pick]["time"]) - lead, "o": 0, "fn": func() -> void:
		c.pause()
		g.lane_input.enabled = false}]
	await run_schedule(c, sched, func() -> bool: return _gone_or_stopped(gw))
	return pick if is_instance_valid(g) and g.conductor != null and g.conductor.is_paused() else -1


func _unfreeze(g: Gameplay) -> void:
	if is_instance_valid(g) and g.conductor != null and g.conductor.is_paused():
		g.conductor.resume(0)
		g.lane_input.enabled = not g.autoplay


## Brightest-channel scan: any pixel above `thr` in design rect [x0,x1] x [y0,y1].
func _any_bright(img: Image, x0: float, x1: float, y0: float, y1: float, thr: float) -> bool:
	var y := y0
	while y <= y1:
		var x := x0
		while x <= x1:
			if _chan_max(_img_px(img, Vector2(x, y))) > thr:
				return true
			x += 3.0
		y += 3.0
	return false


func sc_immersion() -> void:
	isolate_settings(true)
	var orig_speed := Settings.scroll_speed
	metrics["gpu"] = RenderingServer.get_video_adapter_name()

	# --- A. FULL intro --------------------------------------------------------------------------
	var g: Gameplay = await start_dive_from_menu(false, true)
	if g == null:
		return
	var t0 := Time.get_ticks_msec()
	var spb := 60.0 / _bpm_of(g)
	check("intro mode FULL on a normal Start Dive", g.intro_mode == IntroTimeline.Mode.FULL, g.intro_mode)
	await _wait_elapsed(t0, 0.4)
	await shot("intro_room", g)
	await _wait_elapsed(t0, 0.5)
	check("conductor not begun and lane input disabled at 0.5 s",
		not g.is_began() and not g.lane_input.enabled, "began=%s enabled=%s" % [g.is_began(), g.lane_input.enabled])
	await _wait_elapsed(t0, 1.0)
	await shot("intro_goggles", g)
	await _wait_elapsed(t0, 1.4)
	await shot("intro_crt_line", g)
	await _wait_elapsed(t0, 1.55)
	await shot("intro_link", g)
	await _wait_elapsed(t0, 2.2)
	await shot("intro_arena_fade", g)
	var began: bool = await wait_for_began(g, 3.2 - _since(t0) + 0.5)
	var began_t := _since(t0)
	metrics["intro_began_s"] = began_t
	check("count-in begins 2.2-3.2 s after scene load (pre-count 2.6 +- 0.4)",
		began and began_t >= 2.2 and began_t <= 3.2, "%.2f s" % began_t)
	if not began:
		return
	var lead := g.conductor.song_time()
	metrics["intro_lead_in_song_time"] = lead
	check("lead-in is about 3 beats at the first began sample", absf(lead + 3.0 * spb) <= 0.35,
		"song_time %.3f vs %.3f" % [lead, -3.0 * spb])
	await frame()
	await shot("intro_count_3", g)
	check("numeral count active right after began", _intro_alive(g) and g.intro.is_counting())
	await wait_until(func() -> bool: return g.conductor.song_time() >= 0.05, 6.0)
	await shot("intro_dive", g)
	await wait_until(func() -> bool: return g.conductor.song_time() >= 0.8, 3.0)
	check("intro node gone by song_time 0.8 s", not _intro_alive(g))
	check("arena reveal and cable_grow back to 1.0",
		absf(g.arena.reveal - 1.0) < 0.001 and absf(g.highway.cable_grow - 1.0) < 0.001,
		"reveal %.3f grow %.3f" % [g.arena.reveal, g.highway.cable_grow])

	# --- B. Skip --------------------------------------------------------------------------------
	g = await start_dive_from_menu(false, true)
	if g == null:
		return
	t0 = Time.get_ticks_msec()
	await _wait_elapsed(t0, 0.8)
	var skip_ms := Time.get_ticks_msec()
	await press_key(KEY_SPACE)
	var sk: bool = await wait_for_began(g, 0.5)
	check("Space during the intro begins the count within 0.5 s", sk, "%.3f s" % _since(skip_ms))
	await frame()
	check("numeral visible after skip", _intro_alive(g) and g.intro.is_counting())
	await shot("skip_count", g)
	await wait_until(func() -> bool: return g.conductor.song_time() >= 1.0, 6.0)
	var st_before := g.conductor.song_time()
	await press_key(KEY_SPACE)
	check("Space in a normal run changes nothing (no pause, no skip, still RUNNING)",
		g.state == Gameplay.State.RUNNING and not g.pause_menu.is_open() and g.conductor.song_time() >= st_before
		and g.is_began(), g.state)

	# --- C. Quick retry -------------------------------------------------------------------------
	check("pending_intro still FULL for the retry", Gameplay.pending_intro == IntroTimeline.Mode.FULL)
	var r0 := Time.get_ticks_msec()
	g.restart(false)
	check("restart while pending FULL -> QUICK", g.intro_mode == IntroTimeline.Mode.QUICK, g.intro_mode)
	await _wait_elapsed(r0, 0.3)
	await shot("quick_blink", g)
	var qd: bool = await wait_until(func() -> bool:
		return g.conductor != null and g.is_began() and g.conductor.song_time() >= 0.0, 4.0)
	var q_s := _since(r0)
	metrics["quick_retry_s"] = q_s
	check("quick retry reaches song_time 0 in < 1.6 s", qd and q_s < 1.6, "%.2f s" % q_s)
	await wait_until(func() -> bool: return g.conductor.song_time() > 0.3, 3.0)
	await press_key(KEY_F4)
	check("F4 restart is QUICK", g.intro_mode == IntroTimeline.Mode.QUICK, g.intro_mode)

	# --- D. Board at three speeds (autoplay, intro off) -----------------------------------------
	g = await start_dive_from_menu(true)
	if g == null:
		return
	var speeds := [[0.5, "board_scroll_0_5x"], [1.0, "board_scroll_1x"], [3.0, "board_scroll_3x"]]
	var gw: WeakRef = weakref(g)
	await wait_until(func() -> bool: return g.conductor.song_time() > 3.0, 15.0)
	for sp in speeds:
		if _gone_or_stopped(gw):
			check("run alive for board speed %s" % sp[0], false)
			break
		Settings.set_scroll_speed(float(sp[0]))
		await wait(0.3)
		var idx := await _freeze_before_note(g)
		if not check("froze a frame before a note at %sx" % sp[0], idx >= 0):
			_unfreeze(g)
			continue
		await wait(0.25)
		await shot(String(sp[1]), g)
		var approach := Trench.approach_for(Settings.scroll_speed)
		var vis := _visible_pending(g)
		var lane: int = g.chart.notes[idx]["lane"]
		var dt := float(g.chart.notes[idx]["time"]) - last_shot_st
		# Readability: two notes one beat apart at the hit ring stay >= 40 px apart.
		var dd := minf(spb / approach, 1.0)
		var sep := Trench.point(Trench.lane_f(lane), 0.0).distance_to(Trench.point(Trench.lane_f(lane), dd))
		metrics["note_sep_px_%s" % sp[1]] = sep
		check("%sx: notes one beat apart are >= 40 px apart at the ring" % sp[0], sep >= 40.0, "%.1f px" % sep)
		check("%sx: pending notes visible" % sp[0], vis.size() > 0, vis.size())
		if absf(float(sp[0]) - 1.0) < 0.01:
			var bright := _region_max(last_img, Trench.hit_point(lane), 30.0)
			check("1x: note within 5 ms of the ring is bright (>= 0.85)", absf(dt) <= 0.005 and bright >= 0.85,
				"dt %.1f ms, max %.3f" % [dt * 1000.0, bright])
			var far := _far_note(vis)
			if check("1x: a far note is visible alongside the ready note", not far.is_empty()):
				var far_b := _chan_max(_patch(last_img, far["center"]))
				check("1x: far note dimmer than the ready note", far_b < bright, "far %.3f vs ready %.3f" % [far_b, bright])
			# Timing invariant: a note at exactly the visual time projects onto the hit point.
			var vt := last_shot_st + Settings.visual_offset
			var exact := Trench.point(Trench.lane_f(lane), Trench.depth_for(vt, vt, approach))
			check("note at visual time projects onto hit_point (< 0.5 px)",
				exact.distance_to(Trench.hit_point(lane)) < 0.5, exact)
			var nd := Trench.depth_for(float(g.chart.notes[idx]["time"]), vt, approach)
			var off_px := Trench.point(Trench.lane_f(lane), nd).distance_to(Trench.hit_point(lane))
			check("nearest note offset from the ring is bounded by its time error",
				off_px <= 3200.0 * absf(nd) + 0.5, "%.2f px for dt %.1f ms" % [off_px, dt * 1000.0])
		_unfreeze(g)
	Settings.set_scroll_speed(orig_speed)

	# --- F/E/H/G/I on one autoplay run (intro off) ----------------------------------------------
	g = await start_dive_from_menu(true)
	if g == null:
		return
	gw = weakref(g)
	var hit10: bool = await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.score.combo >= 10, 40.0)
	if check("autoplay reached combo 10", hit10 and not _gone_or_stopped(gw), g.score.combo):
		await shot("hud_milestone", g)
		check("10-streak milestone popup text", g.streak_counter.popup_text() == "10 STREAK", g.streak_counter.popup_text())
		await wait(0.9)
		await shot("hud_streak", g)
		var rx := StreakCounter.right_x()
		check("streak counter visible and right edge near x=390", g.streak_counter.is_counter_visible()
			and absf(rx - 390.0) <= 30.0, "right_x %.1f" % rx)
		check("streak number pixels lie left of the anchor, none in x < 32",
			_any_bright(last_img, 32.0, rx + 4.0, 100.0, 1000.0, 0.6)
			and not _any_bright(last_img, 0.0, 31.0, 100.0, 1000.0, 0.6), "right_x %.1f" % rx)
		check("depth label matches depth_text", g.hud.depth_value.text == g.hud.depth_text(g.score.depth()),
			g.hud.depth_value.text)
	# H. fps (full effects, mid-song).
	await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.conductor.song_time() > 6.0, 15.0)
	if _gone_or_stopped(gw):
		check("run reached mid-song for fps", false)
		return
	Settings.low_effects = false
	Settings.settings_changed.emit()
	var f0 := Engine.get_frames_drawn()
	var tf := Time.get_ticks_usec()
	await wait(5.0)
	var fps := float(Engine.get_frames_drawn() - f0) / (float(Time.get_ticks_usec() - tf) / 1000000.0)
	metrics["fps_full_5s"] = snappedf(fps, 0.1)
	check("full effects hold >= 60 fps averaged over 5 s", fps >= 60.0, "%.1f fps" % fps)
	Settings.low_effects = true
	Settings.settings_changed.emit()
	f0 = Engine.get_frames_drawn()
	tf = Time.get_ticks_usec()
	await wait(3.0)
	metrics["fps_low_3s"] = snappedf(float(Engine.get_frames_drawn() - f0) / (float(Time.get_ticks_usec() - tf) / 1000000.0), 0.1)
	Settings.low_effects = false
	Settings.settings_changed.emit()
	if _gone_or_stopped(gw):
		return
	# G. Effects and edges on a frozen frame.
	g.conductor.pause()
	g.lane_input.enabled = false
	await wait(1.0)
	await shot("effects_full", g)
	var img_full := last_img
	var ring_full := _ring_median(img_full)
	var rec_full := 0.0
	for i in range(Highway.LANES):
		rec_full += _chan_max(_patch(img_full, Trench.hit_point(i), 3))
	var edges := [Vector2(3, 540), Vector2(1917, 540), Vector2(960, 3), Vector2(960, 1077),
		Vector2(3, 360), Vector2(1917, 720)]
	var edge_vals: Array = []
	var edge_ok := true
	var red_free := true
	for e in edges:
		var p := _patch(img_full, e, 1)
		edge_vals.append(snappedf(_chan_max(p), 0.001))
		edge_ok = edge_ok and _chan_max(p) <= 0.35
		red_free = red_free and not (p.r > 0.5 and p.g < 0.25 and p.b < 0.25)
	metrics["edge_values"] = edge_vals
	check("screen edges are clean (max channel <= 0.35, D-06)", edge_ok, edge_vals)
	check("no red dominance at the edges outside a miss glitch", red_free, edge_vals)
	Settings.low_effects = true
	Settings.settings_changed.emit()
	await wait(0.3)
	await shot("effects_low", g)
	var ring_low := _ring_median(last_img)
	var rec_low := 0.0
	for i in range(Highway.LANES):
		rec_low += _chan_max(_patch(last_img, Trench.hit_point(i), 3))
	metrics["effects"] = {"ring_full": ring_full, "ring_low": ring_low, "receptors_full": rec_full, "receptors_low": rec_low}
	check("hit ring brightness equal full vs low effects (+-10%)",
		ring_low >= 0.9 * ring_full and ring_full >= 0.9 * ring_low, "%.3f vs %.3f" % [ring_full, ring_low])
	check("receptor brightness equal full vs low effects (+-10%)",
		rec_low >= 0.9 * rec_full and rec_full >= 0.9 * rec_low, "%.3f vs %.3f" % [rec_full, rec_low])
	check("Low effects uses fewer wall rings", Arena.ring_count(true) < Arena.ring_count(false),
		"%d vs %d" % [Arena.ring_count(true), Arena.ring_count(false)])
	Settings.low_effects = false
	Settings.settings_changed.emit()
	# I. Reduce motion: the arena must not breathe.
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	await wait(0.4)
	await shot("effects_reduce_motion", g)
	var rm_a := last_img
	await wait(0.2)
	await RenderingServer.frame_post_draw
	var rm_b := get_viewport().get_texture().get_image()
	var mxd := 0.0
	var yy := 100.0
	while yy < 1000.0:
		for xx in [60.0, 150.0, 300.0, 1620.0, 1770.0, 1860.0]:
			mxd = maxf(mxd, absf(_chan_max(_img_px(rm_a, Vector2(xx, yy))) - _chan_max(_img_px(rm_b, Vector2(xx, yy)))))
		yy += 8.0
	metrics["reduce_motion_wall_diff"] = mxd
	check("reduce motion: wall pixels identical 0.2 s apart", mxd <= 0.01, mxd)
	Settings.reduce_motion = false
	Settings.settings_changed.emit()
	_unfreeze(g)
	# E. Autoplay timing over the first 25 s (or the whole chart).
	await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.conductor.song_time() > 25.0, 40.0)
	if is_instance_valid(g):
		check("autoplay is all-Perfect (no Good, no Miss) and hull 100",
			g.score.miss_count == 0 and g.score.good_count == 0 and g.score.hull >= 99.99,
			"P%d G%d M%d hull %.1f" % [g.score.perfect_count, g.score.good_count, g.score.miss_count, g.score.hull])
	# F2. Critical hull.
	if not _gone_or_stopped(gw):
		var n := 0
		while not g.hud.is_critical() and n < 12:
			g.score.on_judged(0, -1, InputJudge.Judgment.MISS, 0.0)
			n += 1
		await wait(0.4)
		await shot("hud_critical", g)
		check("HULL CRITICAL caption shown at low hull",
			g.hud.hull_caption.visible and g.hud.hull_caption.text == "HULL CRITICAL", g.hud.hull_caption.text)
	Settings.set_scroll_speed(orig_speed)
