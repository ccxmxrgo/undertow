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
## Scenario "immersion" (Phase 1.2): first-person lens-mask intro frames and timing, Space skip,
## QUICK retry, flat-line Trench board at 0.5x/1x/3x, HUD streak / HULL CRITICAL, Low effects and reduce motion,
## screen-edge cleanliness and fps. Non-intro scenarios run with Gameplay.pending_intro = NONE.
##
## Scenario "songs" (Phase 2): Song Select with 2 bundled + 30 generated fixture songs in a temp songs
## root (never the player's Songs folder): layout, overflow, footer, insert stability during a
## throttled rescan, broken / Needs-a-chart rows, filter, empty / onboarding states, Settings >
## LIBRARY, Low effects / Reduce motion, preview gate, difficulty snap, sort, dive to results.
## Since 02-03 every menu dive goes through Song Select: start_dive_from_menu() picks the
## Calibration Track (the hand chart) there so the Phase 1 scenarios keep their chart.
## run_all.ps1 passes --no-boot-scan so SongLibrary never scans the real Songs folder; every
## scenario points the library at user://playtest_library (removed at the end).

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
const SONG_SELECT := "res://scenes/song_select.tscn"
## Temp library root for every scenario (songs roots, cache, zip cache). Never user://songs.
const LIB_ROOT := "user://playtest_library"
const FIXTURE_SONGS := LIB_ROOT + "/songs"
const EMPTY_SONGS := LIB_ROOT + "/empty_songs"
const LANE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]
const TIMEOUTS := {"a": 120.0, "b": 120.0, "c": 60.0, "d": 90.0, "e": 120.0, "f": 90.0,
	"g": 90.0, "h": 150.0, "i": 90.0, "drift": 360.0, "layout": 240.0, "polish": 240.0, "immersion": 240.0,
	"songs": 360.0, "align": 150.0, "perf": 470.0, "visual": 420.0, "autoplay5": 1500.0}
## Scenario b offsets (seconds) per note, cycled. null = skip the note (miss). Values stay >= 5 ms
## from the JudgeConfig window edges (Perfect 50 / Good 100 / early-miss 130 ms since 02.2-26, G1)
## so frame jitter cannot flip the expected judgment: Perfect 0..+-40, Good +-60/75/90, late
## strays +115/+120 (the note expires as a miss, the press is a stray), early miss -115. Four misses
## per 32 notes keep the hull alive through the 124-note hand chart (8 per miss, +1 per Perfect).
const B_CYCLE := [0.0, 0.010, -0.010, 0.020, -0.020, 0.0, 0.030, -0.030, 0.0, 0.040, -0.040, 0.0,
	0.060, -0.060, 0.0, 0.075, -0.075, 0.0, 0.115, 0.0, 0.090, -0.090, 0.0, 0.005,
	-0.115, 0.0, -0.005, 0.120, 0.0, 0.015, -0.015, null]

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
		"songs": await sc_songs()
		"align": await sc_align()
		"perf": await sc_perf()
		"visual": await sc_visual()
		"autoplay5": await sc_autoplay5()
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
	# Pitfall 7: no menu music in the harness unless a scenario opts in (polish menu block).
	Settings.menu_music = false
	MenuMusic.stop(0.0)
	if calibrated:
		Settings.save_calibration(0.0, 0.0)
		MainMenu.boot_handled = true
	isolate_library(EMPTY_SONGS)


## Points SongLibrary at a temp songs root, cache and zip cache, then starts a rescan (bundled
## songs + Calibration Track + whatever is in songs_root). Extra folders come from the temp settings.
func isolate_library(songs_root: String) -> void:
	SongFixture.mkdir(songs_root)
	# --no-boot-scan leaves settings_ref unbound; the game binds it to Settings (now the temp file).
	SongLibrary.settings_ref = Settings
	SongLibrary.songs_root_override = songs_root
	SongLibrary.cache_path = LIB_ROOT + "/cache.json"
	SongScanner.zip_cache_root = LIB_ROOT + "/zipcache"
	SongLibrary._load_last(Settings.last_song_id, Settings.last_difficulty)
	SongLibrary.rescan()


func wait_library_idle(timeout: float = 20.0) -> bool:
	return await wait_until(func() -> bool: return not SongLibrary.scanning, timeout)


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
		# Test windows open on the secondary monitor (run_all.ps1 --position, UNDERTOW_TEST_SCREEN).
		"window_screen": DisplayServer.window_get_current_screen(),
		"window_screen_position": str(DisplayServer.screen_get_position(DisplayServer.window_get_current_screen())),
		"window_position": str(DisplayServer.window_get_position()),
		"primary_screen": DisplayServer.get_primary_screen(),
		"screen_count": DisplayServer.get_screen_count(),
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
	SongLibrary.test_scan_throttle_msec = 0
	if not SongLibrary.scanning:
		SongFixture.rm_tree(LIB_ROOT)
	SongScanner.zip_cache_root = "user://song_cache/zips"
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


## D-20: overlays (results / fail) are hosted the way the game shows them: nothing of the current
## scene may stay visible or processing behind. Hides and disables cur(), then adds `node` under /root.
var _hosted_scene: Node = null
var _hosted_mode: int = Node.PROCESS_MODE_INHERIT


func host_overlay(node: Control) -> void:
	var c := cur()
	if c != null:
		_hosted_scene = c
		_hosted_mode = c.process_mode
		if c is CanvasItem:
			(c as CanvasItem).visible = false
		c.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(node)


## Frees the overlay and restores the hidden scene.
func release_overlay(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	if _hosted_scene != null and is_instance_valid(_hosted_scene):
		if _hosted_scene is CanvasItem:
			(_hosted_scene as CanvasItem).visible = true
		_hosted_scene.process_mode = _hosted_mode as Node.ProcessMode
	_hosted_scene = null
	await frame()


## MainMenu nodes anywhere in the tree that are visible (must be none behind results).
func visible_main_menus() -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "MainMenu", true, false):
		if n.is_inside_tree() and not n.is_queued_for_deletion() and (n as CanvasItem).is_visible_in_tree():
			out.append(str(n.get_path()))
	return out


## Design-space rects of the MainMenu title (the UNDERTOW wordmark) and its button column (read before hiding).
func menu_text_rects(m: MainMenu) -> Array:
	var rects: Array = []
	for l in m.find_children("*", "Label", true, false):
		if (l as Label).text == "UNDERTOW":
			rects.append((l as Control).get_global_rect())
	# 02.2-06: the title is the wordmark TextureRect (LogoWordmark), not a Label.
	if m.logo != null and m.logo.is_visible_in_tree():
		rects.append(m.logo.get_global_rect())
	var col := Rect2()
	for b in [m.start_button, m.practice_button, m.calibrate_button, m.settings_button, m.autoplay_button,
			m.open_folder_button, m.quit_button]:
		if b != null and (b as Control).is_visible_in_tree():
			col = (b as Control).get_global_rect() if col.size == Vector2.ZERO else col.merge((b as Control).get_global_rect())
	if col.size != Vector2.ZERO:
		rects.append(col)
	return rects


## Max luminance of `img` inside `rects` (design space), skipping pixels covered by any visible,
## non-fullscreen Control of `overlay` (its own labels, buttons, bars). Returns {max, samples}.
func luma_outside_overlay(img: Image, rects: Array, overlay: Control) -> Dictionary:
	var skip: Array = []
	var full := Vector2(Highway.SCREEN_W, Highway.SCREEN_H)
	for n in overlay.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and not c.size.is_equal_approx(full):
			skip.append(c.get_global_rect().grow(4.0))
	var mx := 0.0
	var count := 0
	for r in rects:
		var rr: Rect2 = r
		var y := rr.position.y
		while y < rr.end.y:
			var x := rr.position.x
			while x < rr.end.x:
				var pt := Vector2(x, y)
				var covered := false
				for sr in skip:
					if (sr as Rect2).has_point(pt):
						covered = true
						break
				if not covered:
					mx = maxf(mx, _luma(_img_px(img, pt)))
					count += 1
				x += 2.0
			y += 2.0
	return {"max": mx, "samples": count}


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


## Main menu -> Song Select -> Calibration Track (the hand chart the Phase 1 scenarios assert on).
func start_dive_from_menu(autoplay: bool, intro: bool = false) -> Gameplay:
	Gameplay.pending_intro = IntroTimeline.Mode.FULL if intro else IntroTimeline.Mode.NONE
	if not scene_is(MENU):
		await goto(MENU)
	await wait(0.3)
	var m := cur() as MainMenu
	if m == null:
		check("main menu shown", false, cur())
		return null
	await menu_focus(m, m.autoplay_button if autoplay else m.start_button)
	await press_key(KEY_ENTER)
	return await dive_from_song_select(TestCharts.HAND_CHART_ID, "expert")


## Moves menu focus from Start Dive down to `target` with real Down presses (02-03 order: Start,
## Practice, Calibrate, Settings, Autoplay, Open Songs Folder, Quit).
func menu_focus(m: MainMenu, target: Control) -> bool:
	m.start_button.grab_focus()
	await frame()
	var n := 0
	while focus_owner() != target and n < 8:
		await press_key(KEY_DOWN)
		n += 1
	return check("menu focus on %s" % (target as Button).text, focus_owner() == target, focus_owner())


## On Song Select: select `id`, step to `diff` with Left / Right, press Enter, wait for Gameplay.
func dive_from_song_select(id: String, diff: String) -> Gameplay:
	var ok: bool = await wait_until(func() -> bool: return cur() is SongSelect, 5.0)
	if not check("Song Select opened", ok, cur()):
		return null
	var ss := cur() as SongSelect
	await wait_library_idle()
	await frame()
	ss.select_for_test(id)
	await _set_difficulty(ss, diff)
	var st := ss.debug_state()
	check("Song Select: %s / %s selected" % [id.get_file(), diff], st["selected"] == id and st["difficulty"] == diff, st)
	await press_key(KEY_ENTER)
	ok = await wait_until(func() -> bool: return cur() is Gameplay, 5.0)
	check("gameplay scene loaded", ok)
	return cur() as Gameplay


func _set_difficulty(ss: SongSelect, diff: String) -> void:
	var order: Array = SongListModel.DIFFICULTY_ORDER
	var n := 0
	while ss.debug_state()["difficulty"] != diff and n < 6:
		var cur_i: int = order.find(ss.debug_state()["difficulty"])
		await press_key(KEY_RIGHT if order.find(diff) > cur_i else KEY_LEFT)
		n += 1


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
	await shot("calibration_visual")
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
	await menu_focus(m, m.calibrate_button)
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
	# 02.2-21: one more (unscored) audio test, captured mid-run for the restyled stage.
	w.retry_button.grab_focus()
	await press_key(KEY_ENTER)
	await wait_until(func() -> bool: return w.conductor.song_time() > 5.0 * CalibrationWizard.SPB + 0.2, 8.0)
	await shot("calibration_audio")
	# 02.2-23 (W7): UI blips are muted while the wizard measures; a Tab focus move stays silent.
	var cal_last: String = UiSounds.last_played
	var cal_count: int = UiSounds.play_count
	var cal_focus0 := focus_owner()
	var cal_muted: bool = UiSounds.muted
	await press_key(KEY_TAB)
	await frame()
	# The step has one focusable button, so Tab may not move focus: also force a real focus change
	# right after a navigation press, which would play "move" anywhere else.
	var cal_nav := InputEventAction.new()
	cal_nav.action = &"ui_down"
	cal_nav.pressed = true
	UiSounds.handle_input(cal_nav)
	w.skip_button.release_focus()
	w.skip_button.grab_focus()
	await frame()
	check("no UI blip during calibration measuring", cal_muted and UiSounds.muted
		and w.step == CalibrationWizard.Step.AUDIO and UiSounds.play_count == cal_count
		and UiSounds.last_played == cal_last,
		{"muted": cal_muted, "count": UiSounds.play_count - cal_count, "last": UiSounds.last_played,
			"focus": "%s -> %s" % [cal_focus0, focus_owner()]})
	# A tap-perfect player (0 ms lag) on a calibrated (+40) profile should measure 0.
	await press_key(KEY_ESCAPE)
	ok = await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	check("Esc in wizard = Skip, back to menu, offset unchanged", ok and absf(Settings.audio_offset - lag) <= 0.005,
		"%.2f ms" % (Settings.audio_offset * 1000.0))
	check("UI blips unmuted again after leaving the wizard", not UiSounds.muted, UiSounds.muted)


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
	check("all judgments match JudgeConfig windows (50/100/130 ms)", mismatches.is_empty(), mismatches.slice(0, 8))
	var late_miss := 0
	var early_miss := 0
	for k in range(notes.size()):
		var off: Variant = B_CYCLE[k % B_CYCLE.size()]
		if off != null and float(off) > cfg.good_window:
			late_miss += 1
		elif off != null and float(off) < -cfg.good_window:
			early_miss += 1
	check("late presses beyond window (+115/+120 ms) produce strays", strays[0] == late_miss,
		"strays %d, +115/+120 presses %d" % [strays[0], late_miss])
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
				if off != null and absf(float(off)) <= cfg.perfect_window and int(judged.get(k, [9])[0]) != InputJudge.Judgment.PERFECT:
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
	await shot("pause_panel")
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
		await shot("confirm_dialog")
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
	await menu_focus(m, m.settings_button)
	await press_key(KEY_ENTER)
	var ok: bool = await wait_until(func() -> bool: return cur() is SettingsScreen, 5.0)
	if not check("Settings scene opens", ok):
		return
	await wait(0.3)
	var s := cur() as SettingsScreen
	await shot("settings_screen")
	var cell: RebindCell = s.cells["lane_1:keyboard"]
	check("initial focus on Lane 1 keyboard cell", focus_owner() == cell, focus_owner())
	await press_key(KEY_ENTER)
	check("Enter starts listening ('PRESS A KEY')", cell.listening and cell.text == "PRESS A KEY", cell.text)
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
	# 02.2-21: pill toggles and row hints (Display / Audio sections) for the visual review.
	s.low_effects_button.grab_focus()
	await wait(0.4)
	await shot("settings_toggles")
	s.back_button.grab_focus()
	await wait(0.4)
	await shot("settings_library_calibration")

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
	# 02.2-15: three buttons (Retry / Song Select / Back to Menu) wrap; Up from Retry = Back to Menu.
	# 02.2-16: a press during the results entrance only skips it, so wait for the entrance first.
	await wait_until(func() -> bool: return g.results == null or not g.results.entrance_running(), 3.0)
	await press_key(KEY_UP)
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
	# 02.2-15: results are opaque through the calm AbyssBackdrop (+ ABYSS_900 55% shade), not a dim layer.
	var opaque: bool = modal.has_method(&"backdrop_opaque") and bool(modal.call(&"backdrop_opaque"))
	entry["backdrop_opaque"] = opaque
	check("%s dim ColorRect covers the viewport, alpha >= 0.7 (or opaque backdrop)" % label,
		opaque or (dim != null and dim.color.a >= 0.7 - 0.0001), "alpha %.3f opaque %s" % [float(entry["dim_alpha"]), opaque])
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
	await wait_until(func() -> bool: return g2.results == null or not g2.results.entrance_running(), 3.0)
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


## Median brightest-channel value along the flat hit line (Trench.line_points interpolated at 41
## points, every 4th point, 5x5 patches).
func _line_median(img: Image) -> float:
	var ends := Trench.line_points()
	var vals: Array = []
	var i := 0
	while i < 41:
		vals.append(_chan_max(_patch(img, ends[0].lerp(ends[1], float(i) / 40.0), 2)))
		i += 4
	vals.sort()
	return float(vals[vals.size() / 2])


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Largest luminance step between adjacent design pixels along row y, x0..x1 (banding detector).
func _max_luma_step(img: Image, y: float, x0: float, x1: float) -> Dictionary:
	var mx := 0.0
	var at := x0
	var prev := _luma(_img_px(img, Vector2(x0, y)))
	var lo := prev
	var hi := prev
	var x := x0 + 1.0
	while x <= x1:
		var v := _luma(_img_px(img, Vector2(x, y)))
		if absf(v - prev) > mx:
			mx = absf(v - prev)
			at = x
		lo = minf(lo, v)
		hi = maxf(hi, v)
		prev = v
		x += 1.0
	return {"max_step": snappedf(mx, 0.0001), "at_x": at, "min": snappedf(lo, 0.0001), "max": snappedf(hi, 0.0001)}


## 02.2-20: scan the old intro-room rectangles (design px) for flat neutral-grey pixels:
## max - min channel <= 0.04 and max channel in 0.07..0.6 (the abyss base is 0.05 max).
const INTRO_ROOM_RECTS: Array[Rect2] = [Rect2(0, 768, 1920, 312), Rect2(1200, 360, 360, 228),
	Rect2(216, 192, 192, 276), Rect2(456, 240, 144, 192)]


func _intro_grey_scan(img: Image) -> Dictionary:
	var grey := 0
	var n := 0
	var first := ""
	var brightest := 0.0
	for r in INTRO_ROOM_RECTS:
		var y := r.position.y + 4.0
		while y < r.end.y:
			var x := r.position.x + 4.0
			while x < r.end.x:
				var c := _img_px(img, Vector2(x, y))
				var hi := maxf(c.r, maxf(c.g, c.b))
				var lo := minf(c.r, minf(c.g, c.b))
				brightest = maxf(brightest, hi)
				n += 1
				if hi - lo <= 0.04 and hi >= 0.07 and hi <= 0.6:
					grey += 1
					if first == "":
						first = "%s at (%d, %d)" % [c, x, y]
				x += 8.0
			y += 8.0
	return {"grey": grey, "samples": n, "first": first, "brightest": snappedf(brightest, 0.001)}


## Vertical centre of the bright pixels (max channel > thr) in column x, y0..y1; -1 if none.
func _bright_mid_y(img: Image, x: float, y0: float, y1: float, thr: float) -> float:
	var top := -1.0
	var bot := -1.0
	var y := y0
	while y <= y1:
		if _chan_max(_img_px(img, Vector2(x, y))) > thr:
			if top < 0.0:
				top = y
			bot = y
		y += 1.0
	return -1.0 if top < 0.0 else 0.5 * (top + bot)


## Brightest row (sum of max channel over x-2..x+2) in column x, y0..y1.
func _brightest_row(img: Image, x: float, y0: float, y1: float) -> float:
	var best := -1.0
	var best_y := -1.0
	var y := y0
	while y <= y1:
		var v := 0.0
		for dx in range(-2, 3):
			v += _chan_max(_img_px(img, Vector2(x + dx, y)))
		if v > best:
			best = v
			best_y = y
		y += 1.0
	return best_y


## Best colour match to `col` (cosine of RGB direction, max channel >= 0.2) within r design px of p.
func _colour_near(img: Image, p: Vector2, col: Color, r: float) -> Dictionary:
	var cv := Vector3(col.r, col.g, col.b).normalized()
	var best := 0.0
	var best_off := Vector2.ZERO
	var y := -r
	while y <= r:
		var x := -r
		while x <= r:
			var c := _img_px(img, p + Vector2(x, y))
			var v := Vector3(c.r, c.g, c.b)
			if _chan_max(c) >= 0.2 and v.length() > 0.0:
				var cs := v.normalized().dot(cv)
				if cs > best:
					best = cs
					best_off = Vector2(x, y)
			x += 1.0
		y += 1.0
	return {"ok": best >= 0.97, "cos": best, "offset": best_off}


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



## A depth near 0.5 where none of `lanes` has a visible note head or sustain (strip samples).
func _free_strip_depth(g: Gameplay, lanes: Array) -> float:
	var notes: Array = g.chart.notes
	var vt := last_shot_st + Settings.visual_offset
	var approach := Trench.approach_for(Settings.scroll_speed)
	for cand in [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74]:
		var busy := false
		for i in range(notes.size()):
			var n: Dictionary = notes[i]
			if not lanes.has(int(n["lane"])):
				continue
			if i < last_shot_state.size() and last_shot_state[i] == Highway.S_HIT:
				continue
			var d0 := Trench.depth_for(float(n["time"]), vt, approach)
			var d1 := Trench.depth_for(float(n["time"]) + float(n["duration"]), vt, approach)
			if d1 >= float(cand) - 0.09 and d0 <= float(cand) + 0.09:
				busy = true
				break
		if not busy:
			return float(cand)
	return 0.5


## Median luma of the halo/rim zone of a gem at depth d: two diagonal rays up-left and up-right
## (away from the hit line, popups and the neighbouring receptors) from 1.3 r to 1.6 r, where the
## ready halo (additive glow / Low ring) sits and a far gem shows only the lane strip.
func _halo_luma(img: Image, center: Vector2, d: float) -> float:
	var r := Trench.note_radius(Trench.scale_at(d))
	var vals: Array = []
	for sx in [-1.0, 1.0]:
		var dir := Vector2(sx, -1.0).normalized()
		var k := 1.3
		while k <= 1.6:
			vals.append(_luma(_img_px(img, center + dir * r * k)))
			k += 0.05
	vals.sort()
	return float(vals[vals.size() / 2]) if not vals.is_empty() else 0.0

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


## 02.2-16: deterministic fake offsets (seconds) for the hosted results screens: `perfect` hits around
## `bias_ms` inside the Perfect window and `good` hits out in the Good band on the late side.
static func fake_offsets(perfect: int, good: int, bias_ms: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# Bands follow JudgeConfig (02.2-26): Perfect inside pw - 1 ms, Good from pw + 3 to gw - 4 ms.
	var cfg := JudgeConfig.new()
	var pw_ms := cfg.perfect_window * 1000.0
	var gw_ms := cfg.good_window * 1000.0
	var out := PackedFloat32Array()
	for i in perfect:
		out.append(clampf(rng.randfn(bias_ms, 11.0), -(pw_ms - 1.0), pw_ms - 1.0) / 1000.0)
	for i in good:
		var side := -1.0 if i % 3 == 0 else 1.0
		out.append(side * rng.randf_range(pw_ms + 3.0, gw_ms - 4.0) / 1000.0)
	return out


## 02.2-16: waits for the results entrance to finish (the S ring too), then checks the grade letter
## against RunStats, the histogram against the run's offsets, no MainMenu behind, takes the shot and
## checks that no menu text shows where the menu used to be (`menu_rects`, read before diving).
func review_results(label: String, rs: ResultsScreen, score: HullScore, offsets: PackedFloat32Array,
		menu_rects: Array) -> void:
	if not check("%s: results screen shown" % label, rs != null and is_instance_valid(rs)):
		return
	var settled: bool = await wait_until(func() -> bool: return not rs.entrance_running(), 3.0)
	await wait(0.15)
	check("%s: entrance finished within 0.9 s (+ frame slack)" % label, settled and ResultsScreen.ENTRANCE_SEC <= 0.9,
		ResultsScreen.ENTRANCE_SEC)
	var want := RunStats.grade(RunStats.accuracy(score.perfect_count, score.good_count, score.miss_count), score.miss_count)
	check("results grade letter matches RunStats (%s)" % label, rs.grade_letter == want, "%s vs %s" % [rs.grade_letter, want])
	var bins_ok := rs.histogram != null and rs.histogram.bins == RunStats.histogram(offsets)
	check("histogram bins match the run's offsets (%s)" % label, bins_ok,
		{"bins": Array(rs.histogram.bins) if rs.histogram else null, "n": offsets.size(), "summary": rs.histogram.summary if rs.histogram else ""})
	check("no visible MainMenu behind results (%s)" % label, visible_main_menus().is_empty(), visible_main_menus())
	await shot(label)
	if not menu_rects.is_empty():
		var lum := luma_outside_overlay(last_img, menu_rects, rs)
		metrics["%s_menu_band_luma" % label] = lum
		check("no menu text behind results (%s)" % label, int(lum["samples"]) > 0 and float(lum["max"]) < 0.35, lum)


## 02.2-22 (VIS-09, D-13, T-02.2-42): times the menu -> Song Select sonar wipe from the Enter press
## to ScreenTransition.finished, shoots a Song Select -> menu wipe mid-cover and mid-reveal, then
## presses a list key at the start of a reveal and checks that the new screen took it.
func _check_screen_transition() -> void:
	var m := cur() as MainMenu
	if not check("transition: main menu shown", m != null, cur()):
		return
	m.finish_entrance()
	m.start_button.grab_focus()
	await frame()
	var tr := {"start": -1, "swap": -1, "end": -1, "mode": ""}
	var on_start := func() -> void:
		tr["start"] = Time.get_ticks_msec()
		tr["mode"] = ScreenTransition.mode()
	var on_swap := func() -> void: tr["swap"] = Time.get_ticks_msec()
	var on_end := func() -> void: tr["end"] = Time.get_ticks_msec()
	ScreenTransition.started.connect(on_start, CONNECT_ONE_SHOT)
	ScreenTransition.swapped.connect(on_swap, CONNECT_ONE_SHOT)
	ScreenTransition.finished.connect(on_end, CONNECT_ONE_SHOT)
	var t_press := Time.get_ticks_msec()
	key(KEY_ENTER, true)
	await frame()
	key(KEY_ENTER, false)
	var done: bool = await wait_until(func() -> bool: return int(tr["end"]) >= 0, 3.0)
	for sig_cb in [[ScreenTransition.started, on_start], [ScreenTransition.swapped, on_swap],
			[ScreenTransition.finished, on_end]]:
		if (sig_cb[0] as Signal).is_connected(sig_cb[1]):
			(sig_cb[0] as Signal).disconnect(sig_cb[1])
	var key_to_end := int(tr["end"]) - t_press
	var detail := {"key_to_finished_ms": key_to_end, "wipe_ms": int(tr["end"]) - int(tr["start"]),
		"cover_ms": int(tr["swap"]) - int(tr["start"]), "reported_ms": ScreenTransition.last_duration_msec,
		"mode": tr["mode"], "fps": Engine.get_frames_per_second()}
	metrics["screen_transition"] = detail
	check("screen transition finishes within 400 ms", done and int(tr["start"]) >= 0 and key_to_end <= 400, detail)
	check("transition: Song Select shown after the wipe", cur() is SongSelect, cur())
	var ss := cur() as SongSelect
	if ss == null:
		return
	await wait_library_idle()
	await wait(0.3)
	# Song Select -> menu (Esc): shots of the cover and the reveal for the visual review. The wipe
	# runs on a frozen clock here (clock_fn seam) so the shots land at fixed radii at any frame rate.
	var fake := [0.0]
	ScreenTransition.clock_fn = func() -> float: return fake[0]
	key(KEY_ESCAPE, true)
	await frame()
	key(KEY_ESCAPE, false)
	if await wait_until(func() -> bool: return ScreenTransition.phase() == "cover", 1.0):
		fake[0] = 100.0  # cubic-in: r = 2200 * (100/150)^3 = 652
		await frame()
		await shot("sonar_wipe_cover")
		fake[0] = ScreenTransition.COVER_MS
		if await wait_until(func() -> bool: return ScreenTransition.phase() == "reveal", 2.0):
			fake[0] = ScreenTransition.COVER_MS + 15.0  # cubic-out: r = 2200 * (1 - 0.9^3) = 596
			await frame()
			await shot("sonar_wipe_reveal")
	ScreenTransition.clock_fn = Callable()  # real clock again: the failsafe ends the wipe at once
	var back: bool = await wait_until(func() -> bool:
		return not ScreenTransition.is_busy() and cur() is MainMenu, 3.0)
	check("transition: Esc on Song Select wipes back to the menu", back, cur())
	m = cur() as MainMenu
	if m == null:
		return
	await wait(0.3)
	m.finish_entrance()
	m.start_button.grab_focus()
	await frame()
	# Menu -> Song Select again; press a list key on the first frame of the reveal.
	key(KEY_ENTER, true)
	await frame()
	key(KEY_ENTER, false)
	var in_reveal: bool = await wait_until(func() -> bool:
		return ScreenTransition.phase() == "reveal" and cur() is SongSelect, 3.0)
	var ss2 := cur() as SongSelect
	if not check("transition: reveal into Song Select observed", in_reveal and ss2 != null,
			{"phase": ScreenTransition.phase(), "scene": cur()}):
		return
	var before := str(ss2.debug_state()["selected"])
	# Down unless the selection is already the last selectable row (null rows are dividers).
	var idx := -1
	var has_next := false
	for i in range(ss2._view.size()):
		if ss2._view[i] == null:
			continue
		if (ss2._view[i] as SongEntry).id == before:
			idx = i
		elif idx >= 0:
			has_next = true
	var code := KEY_DOWN if has_next or idx < 0 else KEY_UP
	var phase_at := ScreenTransition.phase()
	key(code, true)
	await frame()
	key(code, false)
	await frame()
	await frame()
	var after := str(ss2.debug_state()["selected"])
	check("input works from the start of the reveal", phase_at == "reveal" and after != before,
		{"key": OS.get_keycode_string(code), "phase_at_press": phase_at, "before": before.get_file(),
			"after": after.get_file()})
	await wait_until(func() -> bool: return not ScreenTransition.is_busy(), 1.0)


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
	m.finish_entrance()
	await frame()
	await shot("menu")
	# 02.2-06 living title screen: abyss backdrop, wordmark top-left, icon buttons at x 128.
	check("menu: AbyssBackdrop (title) is the first child", m.get_child(0) is AbyssBackdrop
		and (m.get_child(0) as AbyssBackdrop).variant == "title", m.get_child(0))
	var sonar_px := 0
	var ex := 128.0
	while ex < 640.0:
		for ey in [417.0, 478.0]:
			var px_c := _img_px(last_img, Vector2(ex, ey))
			if px_c.b > 0.55 and px_c.g > 0.45 and px_c.r < 0.35:
				sonar_px += 1
		ex += 4.0
	check("menu: SONAR edge pixels on the focused Start Dive button (x 128..640, y 416..480)", sonar_px > 20, sonar_px)
	var logo_lum := 0.0
	var ly := 180.0
	while ly < 310.0:
		var lx := 130.0
		while lx < 1070.0:
			logo_lum = maxf(logo_lum, _luma(_img_px(last_img, Vector2(lx, ly))))
			lx += 6.0
		ly += 6.0
	check("menu: wordmark rect (120, 168, 960 x 152) has bright pixels", logo_lum > 0.7, logo_lum)

	# --- 02.2-07: last-dive card, Full / Low / Reduce shots, menu music -----------------------
	await wait_library_idle()
	var ld_entry := SongLibrary.find(str(BundledSongs.SONGS[BundledSongs.SONGS.size() - 1]["dir"]))
	if ld_entry == null:
		ld_entry = SongLibrary.find(TestCharts.HAND_CHART_ID)
	var ld_diff := "expert"
	var ld_fp := str(ld_entry.difficulty(ld_diff).get("fingerprint", "")) if ld_entry != null else ""
	if ld_fp != "":
		var ld_store := ScoreStore.new()
		ld_store.load()
		ld_store.submit(ld_fp, 1240.0, 94.0, 212, true, "2026-10-10")
	Settings.set_last_played(ld_entry.id if ld_entry != null else "", ld_diff)
	m.refresh_last_dive()
	m.finish_entrance()
	var card := m.last_dive_card
	check("last-dive card visible with title", card != null and card.visible and card.title_label.text != ""
		and card.get_global_rect().is_equal_approx(MainMenu.CARD_RECT),
		{"title": card.title_label.text if card else "", "best": card.best_value_label.text if card else ""})
	check("last-dive card shows the best depth in gold", card != null and card.best_value_label.visible
		and card.best_value_label.text == "1,240 M", card.best_value_label.text if card else null)
	var bd := m.get_child(0) as AbyssBackdrop
	await frame()
	await shot("menu_full")
	var full_counts := bd.effect_counts()
	Settings.low_effects = true
	Settings.settings_changed.emit()
	await wait(0.3)
	await shot("menu_low")
	var low_counts := bd.effect_counts()
	var full_p := int(full_counts.get("snow", 0)) + int(full_counts.get("specks", 0))
	var low_p := int(low_counts.get("snow", 0)) + int(low_counts.get("specks", 0))
	metrics["menu_particles"] = {"full": full_counts, "low": low_counts}
	check("menu Low effects: snow + specks <= 30% of Full", full_p > 0 and low_p <= 0.3 * full_p,
		"%d -> %d" % [full_p, low_p])
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	await frame()
	var ridge0 := bd.ridge_offset()
	var kelp0 := bd.kelp_phase()
	await wait(1.0)
	check("menu Reduce motion: backdrop ridge and kelp frozen over 1 s",
		is_equal_approx(bd.ridge_offset(), ridge0) and is_equal_approx(bd.kelp_phase(), kelp0),
		"ridge %.2f -> %.2f, kelp %.3f -> %.3f" % [ridge0, bd.ridge_offset(), kelp0, bd.kelp_phase()])
	await shot("menu_reduce")
	Settings.reduce_motion = false
	Settings.settings_changed.emit()

	# Menu music: opt in (isolate_settings turns it off), check it plays on Preview.
	Settings.menu_music = true
	MenuMusic.start()
	await wait_until(func() -> bool: return MenuMusic.is_playing(), 10.0)
	await wait(1.5)
	var pv := AudioServer.get_bus_index("Preview")
	var peak := AudioServer.get_bus_peak_volume_left_db(pv, 0) if pv >= 0 else -200.0
	var mp: AudioStreamPlayer = MenuMusic.active_player()
	metrics["menu_music"] = {"state": MenuMusic.state(), "peak_db": peak, "bus": String(mp.bus) if mp else "",
		"pulse_hz": MenuMusic.pulse_hz(), "backdrop_pulse_hz": bd.pulse_hz,
		"stream": mp.stream.resource_path if mp and mp.stream else ""}
	check("menu music playing on Preview bus", mp != null and String(mp.bus) == "Preview"
		and (MenuMusic.is_playing() or peak > -60.0), metrics["menu_music"])
	await wait(1.1)
	check("menu backdrop pulse follows the menu music tempo", is_equal_approx(bd.pulse_hz, MenuMusic.pulse_hz()),
		"%.3f vs %.3f" % [bd.pulse_hz, MenuMusic.pulse_hz()])
	Settings.menu_music = false
	Settings.settings_changed.emit()
	await wait(0.6)
	check("menu music stops when the setting is turned off", not MenuMusic.is_playing(), MenuMusic.state())
	Settings.menu_music = true
	MenuMusic.start()
	await wait_until(func() -> bool: return MenuMusic.is_playing(), 10.0)

	# --- practice entry ---------------------------------------------------------------------
	m.start_button.grab_focus()
	await frame()
	var blips0: int = UiSounds.play_count
	await press_key(KEY_DOWN)
	check("Down from Start Dive focuses Practice Dive", focus_owner() == m.practice_button, focus_owner())
	# 02.2-23 (VIS-09): a focus move by a navigation key plays the soft "move" blip on SFX.
	var blip_player: AudioStreamPlayer = UiSounds.last_player()
	check("UI blip plays on focus move in the menu", UiSounds.last_played == "move" and UiSounds.play_count > blips0
		and blip_player != null and String(blip_player.bus) == "SFX",
		{"last": UiSounds.last_played, "count": UiSounds.play_count - blips0,
			"bus": String(blip_player.bus) if blip_player else ""})
	await press_key(KEY_ENTER)
	var pg: Gameplay = await dive_from_song_select(TestCharts.HAND_CHART_ID, "expert")
	if not check("Practice Dive opens gameplay (through Song Select)", pg != null, cur()):
		return
	await wait_until(func() -> bool: return pg.conductor.song_time() > 2.0, 10.0)
	check("practice run: Gameplay.practice, score.no_fail on, persisted Settings.no_fail untouched",
		pg.practice and pg.score.no_fail and not Settings.no_fail,
		"practice=%s score.no_fail=%s Settings.no_fail=%s" % [pg.practice, pg.score.no_fail, Settings.no_fail])
	check("menu music stopped when the dive starts", not MenuMusic.is_playing(), MenuMusic.state())
	# Back to the default harness state (Pitfall 7): no menu music for the rest of the scenario.
	Settings.menu_music = false
	MenuMusic.stop(0.0)
	await shot("practice_hud")
	await goto(MENU)
	await wait(0.3)
	await _check_screen_transition()
	if not scene_is(MENU):
		await goto(MENU)
	await wait(0.3)

	# --- normal dive with the keyboard bot ------------------------------------------------------
	var dive_menu_rects: Array = menu_text_rects(cur() as MainMenu) if cur() is MainMenu else []
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
		# Since the gem redesign (UI-SPEC 4.15, rule 13.1) the core is always the full lane colour,
		# so readiness is compared on the halo/rim zone just outside the gem instead of the core.
		var ready_halo := _halo_luma(last_img, ready_sample["center"], float(ready_sample["d"]))
		var far_halo := _halo_luma(last_img, ref["center"], float(ref["d"])) if ref.has("center") else 0.0
		var ratio := ready_halo / maxf(far_halo, 0.001)
		metrics["ready_vs_far"] = {"ready_note": ready_sample["i"], "ready_lane": ready_sample["lane"],
			"ready_dt_ms": float(ready_sample["dt"]) * 1000.0, "ready_center": rc.to_html(false),
			"far_note": ref.get("i", -1), "far_lane": ref.get("lane", -1), "far_center": fc.to_html(false),
			"same_lane_same_frame": not far_same.is_empty(), "ready_halo": ready_halo, "far_halo": far_halo, "ratio": ratio}
		note("ready note #%d lane %d dt %.1f ms center %s vs far note lane %d center %s -> halo x%.2f" % [
			ready_sample["i"], ready_sample["lane"], float(ready_sample["dt"]) * 1000.0, rc.to_html(false),
			int(ref.get("lane", -1)), fc.to_html(false), ratio])
		check("in-window note halo/rim zone is >= 20% brighter than a far note's (median luma)", ratio >= 1.2,
			"x%.2f (%.3f vs %.3f)" % [ratio, ready_halo, far_halo])
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
		check("receptor row is lit in all four lanes (non-black at the hit line)", all_lit, lane_vals)
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
	await wait(0.2)
	metrics["bot_record_info"] = g.record_info
	metrics["bot_score"] = {"depth": g.score.depth(), "max_combo": g.score.max_combo, "perfect": g.score.perfect_count,
		"good": g.score.good_count, "miss": g.score.miss_count}
	check("eligible bot dive set the first record (NEW RECORD, no previous)",
		bool(g.record_info.get("new_record", false)) and float(g.record_info.get("previous_depth", 0.0)) < 0.0
		and g.results != null and g.results.record_banner != null, g.record_info)
	check("no visible MainMenu behind in-game results", visible_main_menus().is_empty(), visible_main_menus())
	var bot_offsets: PackedFloat32Array = g.record_info.get("offsets", PackedFloat32Array())
	check("bot dive recorded one offset per Perfect/Good", bot_offsets.size() == g.score.perfect_count + g.score.good_count,
		"%d offsets, P%d G%d" % [bot_offsets.size(), g.score.perfect_count, g.score.good_count])
	await review_results("results_first_record", g.results, g.score, bot_offsets, dive_menu_rects)
	var first_depth := g.score.depth()
	# 02.2-16: Retry Dive (initial focus) on a real dive's results starts a new run in place. The new
	# run is abandoned (goto MENU below), so it writes no record.
	check("results initial focus is Retry Dive", focus_owner() == g.results.retry_button, focus_owner())
	var old_results := g.results
	await press_key(KEY_ENTER)
	var restarted: bool = await wait_until(func() -> bool:
		return (is_instance_valid(g) and g.state == Gameplay.State.RUNNING and g.conductor != null
			and g.conductor.song_time() > 0.3), 8.0)
	check("Retry Dive restarts the dive", restarted and scene_is(GAMEPLAY)
		and (not is_instance_valid(old_results) or not old_results.is_inside_tree()),
		{"state": g.state if is_instance_valid(g) else "freed", "scene": cur().scene_file_path if cur() else ""})

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
	var menu_rects: Array = menu_text_rects(cur() as MainMenu) if cur() is MainMenu else []
	metrics["menu_text_rects"] = str(menu_rects)
	var rs := ResultsScreen.new()
	host_overlay(rs)
	var rec_offsets := fake_offsets(hs.perfect_count, hs.good_count, 6.0, 1602)
	rs.setup(hs, false, info, false, {"title": "Hand Chart", "artist": "UNDERTOW test", "difficulty": "expert",
		"offsets": rec_offsets, "perfect_window": cfgj.perfect_window})
	await wait(0.2)
	check("histogram bins match the fake offsets",
		rs.histogram != null and rs.histogram.bins == RunStats.histogram(rec_offsets)
		and rs.histogram.perfect_window == cfgj.perfect_window,
		Array(rs.histogram.bins) if rs.histogram else null)
	check("results show NEW RECORD and a Previous best row",
		rs.record_banner != null and rs.rows.any(func(r: Array) -> bool: return r[0] == "Previous best"), rs.rows)
	check("no visible MainMenu behind results", visible_main_menus().is_empty(), visible_main_menus())
	await review_results("results_new_record", rs, hs, rec_offsets, [])
	var lum := luma_outside_overlay(last_img, menu_rects, rs)
	metrics["results_menu_band_luma"] = lum
	check("no menu text behind results", not menu_rects.is_empty() and int(lum["samples"]) > 0
		and float(lum["max"]) < 0.35, lum)
	# 02.2-15: the results backdrop is the calm abyss (snow, panel and grade glows), no longer a flat
	# fill, so "uniform" means: where the menu text was, nothing reaches half the dimmest text token.
	check("results backdrop where the menu text was stays below half of TEXT_LO luma",
		float(lum["max"]) < _luma(Palette.TEXT_LO) * 0.5, [lum, _luma(Palette.TEXT_LO) * 0.5])
	await release_overlay(rs)
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
	host_overlay(prs)
	var pr_offsets := fake_offsets(ps.perfect_count, ps.good_count, -9.0, 2216)
	prs.setup(ps, false, pinfo, true, {"title": "Hand Chart", "artist": "UNDERTOW test", "difficulty": "expert",
		"offsets": pr_offsets, "perfect_window": cfgj.perfect_window})
	await wait(0.2)
	check("practice results: PRACTICE DIVE flag and 'Not recorded' note",
		prs.flags.has("PRACTICE DIVE") and prs.note_label != null and prs.note_label.text.begins_with("Not recorded"),
		[prs.flags, prs.note_label.text if prs.note_label else null])
	check("no visible MainMenu behind practice results", visible_main_menus().is_empty(), visible_main_menus())
	await review_results("results_practice_not_recorded", prs, ps, pr_offsets, menu_rects)
	await release_overlay(prs)
	var fs := FailScreen.new()
	host_overlay(fs)
	var saved_best := float(store.best(TestCharts.HAND_CHART_ID)["depth"])
	fs.setup(612.0, 17, saved_best, 37.0)
	fs.play(0.0)
	await wait(0.6)
	check("IMPLOSION shows run stats and saved best",
		fs.stats_label.text == "Max combo: 17" and fs.best_label.text.begins_with("Saved best: "),
		[fs.stats_label.text, fs.best_label.text])
	check("IMPLOSION shows the song progress row", fs.progress_label.visible and fs.progress_label.text == "SONG PROGRESS 37%",
		fs.progress_label.text)
	await shot("implosion")
	await release_overlay(fs)
	await goto(MENU)
	await wait(0.4)
	m = cur() as MainMenu
	var expect := "Best: %s m" % Palette.fmt_depth(int(saved_best))
	check("menu best line shows the saved best", m != null and m.best_label.text.begins_with(expect),
		m.best_label.text if m else null)
	await shot("menu_best_line")
	check("records stayed in the temp record book (real scores.cfg path unused)",
		ScoreStore.default_path == POLISH_SCORES, ScoreStore.default_path)

	# --- 02.2-16: results routes from real (Autoplay, not recorded) dives --------------------------
	var route_rects: Array = menu_text_rects(cur() as MainMenu) if cur() is MainMenu else []
	var ga: Gameplay = await start_dive_from_menu(true)
	if ga == null:
		return
	# 02.2-23: no UI blip while the dive runs, even when the blip hooks fire (accept / cancel /
	# navigation focus moves are fed straight to UiSounds, so the run itself is not disturbed).
	var ui_last: String = UiSounds.last_played
	var ui_count: int = UiSounds.play_count
	var ui_seen := {"count": ui_count, "last": ui_last, "probes": 0, "running": 0}
	var ga_done: bool = await wait_until(func() -> bool:
		if is_instance_valid(ga) and ga.state == Gameplay.State.RUNNING:
			ui_seen["running"] += 1
			if ui_seen["probes"] < 3 and ui_seen["running"] % 20 == 5:
				ui_seen["probes"] += 1
				var ui_acc := InputEventAction.new()
				ui_acc.action = &"ui_accept"
				ui_acc.pressed = true
				UiSounds.handle_input(ui_acc)
				UiSounds.play("move")
			ui_seen["count"] = UiSounds.play_count
			ui_seen["last"] = UiSounds.last_played
		return not is_instance_valid(ga) or ga.state == Gameplay.State.DONE, 120.0)
	check("no UI blip during gameplay", ui_seen["count"] == ui_count and ui_seen["last"] == ui_last
		and ui_seen["probes"] > 0, ui_seen)
	if not check("autoplay dive (Song Select route) reaches results", ga_done and is_instance_valid(ga) and ga.results != null):
		return
	await review_results("results_route_song_select", ga.results, ga.score, ga.record_info.get("offsets", PackedFloat32Array()),
		route_rects)
	await press_key(KEY_RIGHT)
	check("Right from Retry Dive focuses Song Select", focus_owner() == ga.results.song_select_button, focus_owner())
	await press_key(KEY_ENTER)
	var ss_ok: bool = await wait_until(func() -> bool: return scene_is(SONG_SELECT) and cur() is SongSelect, 6.0)
	check("Song Select button opens Song Select", ss_ok, cur().scene_file_path if cur() else "")
	await wait(0.3)
	await goto(MENU)
	await wait(0.3)
	route_rects = menu_text_rects(cur() as MainMenu) if cur() is MainMenu else []
	var gb: Gameplay = await start_dive_from_menu(true)
	if gb == null:
		return
	var gb_done: bool = await wait_until(func() -> bool: return not is_instance_valid(gb) or gb.state == Gameplay.State.DONE, 120.0)
	if not check("autoplay dive (Back to Menu route) reaches results", gb_done and is_instance_valid(gb) and gb.results != null):
		return
	await review_results("results_route_menu", gb.results, gb.score, gb.record_info.get("offsets", PackedFloat32Array()),
		route_rects)
	await press_key(KEY_UP)
	check("Up from Retry Dive wraps to Back to Menu", focus_owner() == gb.results.menu_button, focus_owner())
	await press_key(KEY_ENTER)
	var menu_ok: bool = await wait_until(func() -> bool: return scene_is(MENU) and cur() is MainMenu, 6.0)
	check("Back to Menu opens the menu", menu_ok, cur().scene_file_path if cur() else "")


# ------------------------------------------------------------------------------------------------
# immersion (Phase 1.2): lens-mask intro, skip / quick retry timing, flat-line Trench board at three
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
	await _wait_elapsed(t0, 0.3)
	await shot("intro_rig_boot", g)
	# 02.2-20 (UI-SPEC 9.5): the room is gone. Sample where the old room rectangles were drawn
	# (floor, rig monitor, two shelves): no flat neutral-grey pixel, the frame is the abyss
	# base plus SONAR rings / text / backlight only.
	var grey := _intro_grey_scan(last_img)
	metrics["intro_rig_boot_grey_scan"] = grey
	check("intro has no grey placeholder rectangles", int(grey["grey"]) == 0, grey)
	await _wait_elapsed(t0, 0.35)
	await shot("intro_lens_closing", g)
	await _wait_elapsed(t0, 0.5)
	check("conductor not begun and lane input disabled at 0.5 s",
		not g.is_began() and not g.lane_input.enabled, "began=%s enabled=%s" % [g.is_began(), g.lane_input.enabled])
	await _wait_elapsed(t0, 1.0)
	await shot("intro_lens_focus", g)
	# Smooth falloff: a row through the left lens opening edge (opening centre x 780, r 330 at
	# scale 1, so the soft edge spans x ~450..630) has no visible luminance band steps.
	var band := _max_luma_step(last_img, 540.0, 300.0, 700.0)
	metrics["lens_edge_luma"] = band
	check("lens mask edge is smooth (adjacent luminance step < 0.08, no banding)",
		float(band["max_step"]) < 0.08, band)
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
		# Readability: two notes one beat apart at the flat hit line stay >= 40 px apart.
		var dd := minf(spb / approach, 1.0)
		var sep := Trench.point(Trench.lane_f(lane), 0.0).distance_to(Trench.point(Trench.lane_f(lane), dd))
		metrics["note_sep_px_%s" % sp[1]] = sep
		check("%sx: notes one beat apart are >= 40 px apart at the hit line" % sp[0], sep >= 40.0, "%.1f px" % sep)
		check("%sx: pending notes visible" % sp[0], vis.size() > 0, vis.size())
		if absf(float(sp[0]) - 1.0) < 0.01:
			# Radius covers the whole note glyph at the line (r ~ 41 px): its outline is the bright part.
			var bright := _region_max(last_img, Trench.hit_point(lane), Trench.note_radius(Trench.scale_at(0.0)) + 8.0, 1.0)
			check("1x: note within 5 ms of the hit line is bright (>= 0.85)", absf(dt) <= 0.005 and bright >= 0.85,
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
			# Max on-screen speed near the line in px per unit depth: numeric derivative at d = 0 for
			# this lane (TRAVEL * (1 + PERSPECTIVE) vertically plus the lane's x drift), scaled by
			# (1 - P|nd|)^-2 because the projection speeds up slightly past the line.
			var hstep := 0.0005
			var f_l := Trench.lane_f(lane)
			var v0 := Trench.point(f_l, -hstep).distance_to(Trench.point(f_l, hstep)) / (2.0 * hstep)
			var vmax := v0 / pow(maxf(1.0 - Trench.PERSPECTIVE * absf(nd), 0.1), 2.0)
			metrics["line_speed_px_per_depth_lane%d" % lane] = snappedf(v0, 0.1)
			metrics["line_speed_y_px_per_s_1x"] = snappedf(Trench.TRAVEL * (1.0 + Trench.PERSPECTIVE) / approach, 0.1)
			check("nearest note offset from the line is bounded by its time error (max line speed)",
				off_px <= vmax * absf(nd) + 0.5,
				"%.2f px for dt %.1f ms (bound %.2f)" % [off_px, dt * 1000.0, vmax * absf(nd) + 0.5])
			# Flat line: all four receptors share one y, numerically and on screen.
			var ys: Array = []
			var mids: Array = []
			var rows: Array = []
			for li in range(Highway.LANES):
				var hp := Trench.hit_point(li)
				ys.append(hp.y)
				mids.append(_bright_mid_y(last_img, hp.x, hp.y - 50.0, hp.y + 44.0, 0.45))
				rows.append(_brightest_row(last_img, hp.x + Highway.RECEPTOR_R + 22.0, hp.y - 30.0, hp.y + 30.0))
			metrics["receptor_hit_y"] = ys
			metrics["receptor_bright_mid_y_1x"] = mids
			metrics["line_brightest_row_1x"] = rows
			check("all four hit_point y equal within 0.5 px", float(ys.max()) - float(ys.min()) <= 0.5, ys)
			check("1x: receptor rows on screen share one y within 3 px",
				float(mids.min()) >= 0.0 and float(mids.max()) - float(mids.min()) <= 3.0, mids)
			check("1x: the hit line is one level row beside every receptor (within 3 px of HIT_Y)",
				float(rows.min()) >= Trench.HIT_Y - 3.0 and float(rows.max()) <= Trench.HIT_Y + 3.0, rows)
			# Filled lane strips (02.2-08): lane 1 and lane 4 strips carry their lane tint at d ~ 0.5.
			# The tint is 7% over a 90% surface, so it is measured against the neighbouring strip:
			# (this strip - neighbour) must point along (lane colour - neighbour lane colour).
			for pair in [[0, 1], [Highway.LANES - 1, Highway.LANES - 2]]:
				var li: int = pair[0]
				var nb: int = pair[1]
				var sd := _free_strip_depth(g, [li, nb])
				var sa := _patch(last_img, Trench.point(Trench.lane_f(li), sd), 3)
				var sb := _patch(last_img, Trench.point(Trench.lane_f(nb), sd), 3)
				var diff := Vector3(sa.r - sb.r, sa.g - sb.g, sa.b - sb.b)
				var la := Palette.lane_color(li)
				var lb := Palette.lane_color(nb)
				var want := Vector3(la.r - lb.r, la.g - lb.g, la.b - lb.b)
				var cos_t := diff.normalized().dot(want.normalized()) if diff.length() > 0.0 else 0.0
				var sm := {"d": snappedf(sd, 0.01), "max": snappedf(_chan_max(sa), 0.001), "cos": snappedf(cos_t, 0.001)}
				metrics["strip_lane%d_mid" % (li + 1)] = sm
				check("1x: lane %d strip tint present at d=0.5" % (li + 1), _chan_max(sa) >= 0.04 and cos_t >= 0.8, sm)
			# Solid gems: a visible far pending note's centre is the full lane colour (never dimmed).
			var gem := _far_note(vis)
			if not gem.is_empty():
				var gl: int = gem["lane"]
				var gcol := Palette.lane_color(gl)
				var gnear := _colour_near(last_img, gem["center"], gcol, 6.0)
				var gpatch := _patch(last_img, gem["center"], 1)
				var full := _chan_max(gpatch) >= 0.9 * _chan_max(gcol)
				var gm := {"lane": gl + 1, "cos": snappedf(float(gnear["cos"]), 0.001), "max": snappedf(_chan_max(gpatch), 0.001)}
				metrics["gem_core_far"] = gm
				check("1x: gem core is full lane colour", bool(gnear["ok"]) and full, gm)
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
	var ring_full := _line_median(img_full)
	var rec_full := 0.0
	for i in range(Highway.LANES):
		rec_full += _chan_max(_patch(img_full, Trench.hit_point(i), 3))
	var edges := [Vector2(3, 540), Vector2(1917, 540), Vector2(960, 3), Vector2(960, 1077),
		Vector2(3, 360), Vector2(1917, 720)]
	var edge_vals: Array = []
	var red_free := true
	for e in edges:
		var p := _patch(img_full, e, 1)
		edge_vals.append(snappedf(_chan_max(p), 0.001))
		red_free = red_free and not (p.r > 0.5 and p.g < 0.25 and p.b < 0.25)
	metrics["edge_values"] = edge_vals
	check("no red dominance at the edges outside a miss glitch", red_free, edge_vals)
	# 02.2-11: the arena may only pass its walls behind the note path. Sample 12 points inside the
	# expanded keep-out but outside the board strips (40 px beyond the outer rails, d 0.2..0.9):
	# no SONAR / BIO_VIOLET colony-coloured pixel there. (Replaces the old "screen edges are
	# clean" check: the living trench and the cockpit frame now light the screen edges on purpose.)
	var keep := Arena.note_path_polygon()
	var path_hits: Array = []
	var path_inside := true
	for side in [-1.0, 1.0]:
		for di in 6:
			var dd := 0.2 + 0.14 * float(di)
			var sp := Trench.point(2.0 * side, dd) + Vector2(40.0 * side, 0.0)
			path_inside = path_inside and Geometry2D.is_point_in_polygon(sp, keep)
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					var pc := _img_px(img_full, sp + Vector2(ox, oy))
					if _colony_coloured(pc):
						path_hits.append({"at": sp.round(), "rgb": [snappedf(pc.r, 0.01), snappedf(pc.g, 0.01), snappedf(pc.b, 0.01)]})
	var geo_hits := 0
	for dp in g.arena.colony_dots():
		if Geometry2D.is_point_in_polygon(dp, keep):
			geo_hits += 1
	metrics["note_path_decor"] = {"pixel_hits": path_hits.size(), "colony_dots_inside": geo_hits}
	check("no arena decoration inside the note path", path_inside and path_hits.is_empty() and geo_hits == 0,
		{"samples_inside_keep_out": path_inside, "hits": path_hits.slice(0, 4), "colony_dots_inside": geo_hits})
	Settings.low_effects = true
	Settings.settings_changed.emit()
	await wait(0.3)
	await shot("effects_low", g)
	var ring_low := _line_median(last_img)
	var rec_low := 0.0
	for i in range(Highway.LANES):
		rec_low += _chan_max(_patch(last_img, Trench.hit_point(i), 3))
	metrics["effects"] = {"line_full": ring_full, "line_low": ring_low, "receptors_full": rec_full, "receptors_low": rec_low}
	# +-15%: the 12 px teal glow stroke under the line is off in Low effects by spec, so the line core
	# sampled on the near-black abyss reads ~10% darker in Low; notes/receptor outlines are unchanged.
	check("hit line brightness equal full vs low effects (+-15%)",
		ring_low >= 0.85 * ring_full and ring_full >= 0.85 * ring_low, "%.3f vs %.3f" % [ring_full, ring_low])
	check("receptor brightness equal full vs low effects (+-15%)",
		rec_low >= 0.85 * rec_full and rec_full >= 0.85 * rec_low, "%.3f vs %.3f" % [rec_full, rec_low])
	check("Low effects uses fewer wall rings", Arena.ring_count(true) < Arena.ring_count(false),
		"%d vs %d" % [Arena.ring_count(true), Arena.ring_count(false)])
	Settings.low_effects = false
	Settings.settings_changed.emit()
	# I. Reduce motion: the arena must not breathe. Per UI-SPEC the walls still drift at x0.25 scroll,
	# so pixels are not identical; assert the spec instead: pulse term 0 and marine snow frozen.
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	await wait(0.4)
	await shot("effects_reduce_motion", g)
	var snow_a: PackedVector2Array = g.arena._snow_pos.duplicate()
	var pulse_max := 0.0
	for _k in 12:
		await wait(0.02)
		pulse_max = maxf(pulse_max, g.arena._pulse)
	var snow_moved := 0.0
	for si in snow_a.size():
		snow_moved = maxf(snow_moved, snow_a[si].distance_to(g.arena._snow_pos[si]))
	metrics["reduce_motion_pulse_max"] = pulse_max
	metrics["reduce_motion_snow_moved_px"] = snow_moved
	check("reduce motion: no beat breathing (arena pulse 0) and snow frozen", pulse_max == 0.0 and snow_moved == 0.0,
		"pulse %.3f snow %.2f px" % [pulse_max, snow_moved])
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



# ------------------------------------------------------------------------------------------------
# songs (Phase 2): Song Select, fixtures, states, Settings > LIBRARY, dives from Song Select
# ------------------------------------------------------------------------------------------------

const LONG_TITLE := "The Extraordinarily Long Title Of A Progressive Rock Epic That Never Ends Part IV (Live At The Trench)"
const CJK_TITLE := "深海の歌 Глубина"
const CJK_ARTIST := "Морской Оркестр 海"
const FIXTURE_NAMES := ["Abyssal Echo", "Ballast", "Coral Static", "Depth Charge", "Ebb Tide", "Fathom Line",
	"Gyre", "Hadal Zone", "Ink Cloud", "Jetsam", "Kelp Forest", "Lantern Fish", "Maelstrom", "Nautilus",
	"Oarfish", "Pressure Hull", "Quiet Running", "Riptide", "Sonar Ping", "Thermocline", "Upwelling",
	"Vent Field", "Whale Fall"]
## Plan 02.2-19: fixture folder that gets tests/fixtures/album_art/album.png and section events.
const ART_SONG := "Coral Static"
const ART_FIXTURE := "res://tests/fixtures/album_art/album.png"
const ART_SECTIONS: Array[String] = ["Intro", "Verse 1", "Chorus", "Outro"]
const HINT_KEYS := "UP DOWN SONG  ·  LEFT RIGHT DIFFICULTY  ·  ENTER DIVE  ·  F5 RESCAN  ·  ESC BACK"
const HINT_FILTER := "TYPE TO FILTER  ·  BACKSPACE EDIT  ·  ESC CLEAR FILTER  ·  UP DOWN SONG  ·  ENTER DIVE"
const HINT_PAD := "D-PAD SONG  ·  LEFT RIGHT DIFFICULTY  ·  A DIVE  ·  Y SORT  ·  X RESCAN  ·  B BACK"


func _ini(title: String, artist: String) -> String:
	return "[song]\nname = %s\nartist = %s\ncharter = Playtest Fixture\ndelay = 0\n" % [title, artist]


func _fixture_song(dir: String, title: String, artist: String, seconds: float = 2.0) -> void:
	SongFixture.mkdir(dir)
	SongFixture.write_text(dir.path_join("notes.chart"), SongFixture.CHART)
	SongFixture.write_text(dir.path_join("song.ini"), _ini(title, artist))
	SongFixture.make_wav(dir.path_join("song.wav"), seconds)


## A generated first-party art image: four lane-colour bands on the abyss with a sonar ring.
func _fixture_art(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Palette.ABYSS_700)
	for i in 4:
		img.fill_rect(Rect2i(i * w / 4 + 6, h / 3, w / 4 - 12, h / 3), Palette.lane_color(i))
	img.fill_rect(Rect2i(0, h - 12, w, 6), Palette.SONAR)
	return img


## 30 user songs: 23 plain, Opus (broken), bare WAV (Needs a chart), long title, CJK/Cyrillic title,
## community stems folder, zip, and a 6 s "Dive Test Song" for the full autoplay dive.
func _make_fixture_library() -> void:
	SongFixture.rm_tree(FIXTURE_SONGS)
	SongFixture.mkdir(FIXTURE_SONGS)
	for i in FIXTURE_NAMES.size():
		_fixture_song(FIXTURE_SONGS.path_join(FIXTURE_NAMES[i]), FIXTURE_NAMES[i], "Deep Band %02d" % (i + 1))
	var opus := FIXTURE_SONGS.path_join("Opus Broken Song")
	_fixture_song(opus, "Opus Broken Song", "Codec Crew")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(opus.path_join("song.wav")))
	SongFixture.write_bytes(opus.path_join("song.ogg"), SongFixture.opus_bytes())
	SongFixture.make_wav(FIXTURE_SONGS.path_join("Lonely Audio.wav"), 2.0)
	_fixture_song(FIXTURE_SONGS.path_join("Long Title"), LONG_TITLE, "An Artist With A Remarkably Long Name And Several Featured Guests")
	_fixture_song(FIXTURE_SONGS.path_join("CJK Title"), CJK_TITLE, CJK_ARTIST)
	SongFixture.make_community(FIXTURE_SONGS.path_join("Community Pack"))
	var zsrc := LIB_ROOT.path_join("zip_src")
	_fixture_song(zsrc, "Zipped Song", "Zip Band")
	# First-party album art (plan 02.2-17): png inside the zip, jpg in a plain folder.
	_fixture_art(300, 200).save_png(zsrc.path_join("album.png"))
	_fixture_art(256, 256).save_jpg(FIXTURE_SONGS.path_join("Ebb Tide").path_join("album.jpg"), 0.9)
	SongFixture.zip_folder(zsrc, FIXTURE_SONGS.path_join("Zipped Song.zip"), "Zipped Song")
	SongFixture.rm_tree(zsrc)
	# Plan 02.2-19: the first-party album.png fixture (plan 17) copied into an existing fixture folder,
	# whose chart also gets section events for the sections block.
	var art_dir := FIXTURE_SONGS.path_join(ART_SONG)
	SongFixture.write_bytes(art_dir.path_join("album.png"), FileAccess.get_file_as_bytes(ART_FIXTURE))
	SongFixture.write_text(art_dir.path_join("notes.chart"), SongFixture.CHART.replace("[Events]\n{\n}",
		"[Events]\n{\n  0 = E \"section Intro\"\n  384 = E \"section Verse 1\"\n  768 = E \"section Chorus\"\n"
		+ "  1152 = E \"section Outro\"\n}"))
	_fixture_song(FIXTURE_SONGS.path_join("Dive Test Song"), "Dive Test Song", "Harness Band", 6.0)


func _entry_titled(title: String) -> SongEntry:
	for e in SongLibrary.entries:
		if e.title == title:
			return e
	return null


func _song_select() -> SongSelect:
	return cur() as SongSelect


## Screen row (0..8) of the selection, -1 when it is not visible.
func _sel_row(ss: SongSelect) -> int:
	var st := ss.debug_state()
	return (st["rows"] as Array).find(st["selected"])


## Every visible row: title (+ badge) ends before the best-depth column, the second line ends
## before the length text, and nothing passes the row's right edge (x 1008).
func _check_rows_fit(ss: SongSelect, label: String) -> void:
	var st := ss.debug_state()
	var bad: Array = []
	var truncated: Array = []
	for id in st["rows"]:
		if id == "":
			continue
		var e: SongEntry = null
		for x in ss._all:
			if (x as SongEntry).id == id:
				e = x
		if e == null:
			continue
		var sel: bool = id == st["selected"]
		var bd := SongSelect.row_badge(e)
		var badge: String = bd[0]
		var bw := UiKit.chip_width(badge, bd[1]) + SongSelect.BADGE_GAP if badge != "" else 0.0
		var title_max := SongSelect.row_title_max(badge, bd[1])
		var title := e.title if e.title != "" else "Untitled"
		var shown := ss._fit(title, Palette.SIZE_BODY, title_max, sel)
		if shown != title:
			truncated.append(shown)
		var title_end := 112.0 + ss._w(shown, Palette.SIZE_BODY, sel) + bw
		var best_left := 992.0 - ss._w("99999 m", Palette.SIZE_LABEL)
		var second_end: float
		var second_limit := SongSelect.ROW_LEN_RIGHT
		if e.status == "broken":
			second_end = 128.0 + ss._w(ss._fit(e.error, Palette.SIZE_LABEL, 740.0), Palette.SIZE_LABEL)
		else:
			var second := SongSelect.NEEDS_HINT_ROW if e.status == "needs_chart" else (e.artist if e.artist != "" else "Unknown artist")
			second_end = 112.0 + ss._w(ss._fit(second, Palette.SIZE_LABEL, 700.0), Palette.SIZE_LABEL)
			if e.length_sec > 0.0:
				second_limit = SongSelect.ROW_LEN_RIGHT - ss._w(SongListModel.fmt_length(e.length_sec), Palette.SIZE_LABEL) - 8.0
		if title_end > best_left - 8.0 or second_end > second_limit or title_end > 1008.0:
			bad.append("%s title_end %.0f (limit %.0f) second_end %.0f (limit %.0f)" % [title, title_end,
				best_left - 8.0, second_end, second_limit])
	metrics["%s_truncated_titles" % label] = truncated
	check("%s: no row text overflows its column (%d rows)" % [label, (st["rows"] as Array).size()], bad.is_empty(), bad)


## Footer: keyboard hint fits x <= 1040 untruncated, Songs path starts at x >= 1056, credits clear the
## scan-status column.
func _check_footer(ss: SongSelect, label: String) -> void:
	var widths := {}
	var ok := true
	for pair in [["keys", HINT_KEYS], ["filter", HINT_FILTER], ["pad", HINT_PAD]]:
		var w := ss._w(pair[1], Palette.SIZE_LABEL)
		widths[pair[0]] = snappedf(64.0 + w, 0.1)
		ok = ok and 64.0 + w <= 1040.0
	check("%s: every hint line ends at x <= 1040 without truncation" % label, ok, widths)
	var full := "Songs folder: " + SongListModel.truncate_middle(SongLibrary.songs_dir(), 66 - "Songs folder: ".length())
	var path_x := 1856.0 - ss._w(full, Palette.SIZE_LABEL)
	metrics["%s_path_left_x" % label] = path_x
	check("%s: Songs folder path right-aligned, starts at x >= 1056 (clear of the hint)" % label, path_x >= 1056.0,
		"%.1f" % path_x)
	var credits_x := 1856.0 - ss._w(SongSelect.CREDITS, Palette.SIZE_LABEL)
	check("%s: credits line starts right of the scan-status column (x >= 1184)" % label, credits_x >= 1184.0,
		"%.1f" % credits_x)


## Replaces the retired outer-32-px check (RESEARCH Pitfall 9, clean-edge rule retired): the
## backdrop may reach the edges, but no bright decoration may sit over the list text. For every
## visible song row, the brightest-luminance pixel of its title must keep >= 4.5:1 (WCAG) against
## the row background sampled in the text-free gap left of the title (x 96, row centre).
func _check_list_text_contrast(ss: SongSelect, img: Image, label: String) -> void:
	var st := ss.debug_state()
	var worst := 99.0
	var worst_at := ""
	var n := 0
	for i in range(int(st["offset"]), mini(int(st["offset"]) + SongSelect.ROWS, ss._view.size())):
		var e: Variant = ss._view[i]
		if e == null:
			continue
		var y := SongSelect.LIST_Y + float(i - int(st["offset"])) * SongSelect.ROW_PITCH
		var sel: bool = (e as SongEntry).id == st["selected"]
		var title := (e as SongEntry).title if (e as SongEntry).title != "" else "Untitled"
		var shown := ss._fit(title, Palette.SIZE_BODY, 600.0, sel)
		var tw := minf(ss._w(shown, Palette.SIZE_BODY, sel), 600.0)
		var bg := _patch(img, Vector2(96.0, y + 36.0), 2)
		var best := bg
		var x := 112.0
		while x < 112.0 + tw:
			var yy := y + 12.0
			while yy <= y + 34.0:
				var px := _img_px(img, Vector2(x, yy))
				if Wcag.luminance(px) > Wcag.luminance(best):
					best = px
				yy += 1.0
			x += 1.0
		var r := Wcag.ratio(best, bg)
		n += 1
		if r < worst:
			worst = r
			worst_at = "%s (row %d)" % [title, i - int(st["offset"])]
	metrics["%s_list_text_contrast" % label] = {"min": snappedf(worst, 0.01), "at": worst_at, "rows": n}
	check("%s: no bright decoration over the list text (row title vs its row background >= 4.5:1)" % label,
		n > 0 and worst >= 4.5, "%.2f at %s (%d rows)" % [worst, worst_at, n])


## Viewport image of the next drawn frame (not saved).
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Hash of the album-cover area (inset 6 px past the edge and brackets) in design pixels.
func _cover_hash(img: Image) -> int:
	var r := SongSelect.COVER_RECT.grow(-6.0)
	var bytes := PackedByteArray()
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		while x < r.end.x:
			var c := _img_px(img, Vector2(x, y))
			bytes.append(c.r8)
			bytes.append(c.g8)
			bytes.append(c.b8)
			x += 2.0
		y += 2.0
	return hash(bytes)


## Glyphs the font stack cannot render (tofu): shaped glyphs without a font.
func _tofu(ss: SongSelect, text: String, size: int) -> int:
	var tl := TextLine.new()
	tl.add_string(text, ss._font, size)
	var ts := TextServerManager.get_primary_interface()
	var n := 0
	for g in ts.shaped_text_get_glyphs(tl.get_rid()):
		if not (g["font_rid"] as RID).is_valid() and String.chr(int(g["index"])) != " ":
			n += 1
	return n


func _view_statuses(ss: SongSelect) -> Array:
	var out: Array = []
	for e in ss._view:
		if e != null:
			out.append((e as SongEntry).status)
	return out


## Sorted view: every playable song before any needs-chart / broken one, broken last.
func _unplayable_last(statuses: Array) -> bool:
	var seen_needs := false
	var seen_broken := false
	for s in statuses:
		if s == "ok" and (seen_needs or seen_broken):
			return false
		if s == "needs_chart" and seen_broken:
			return false
		seen_needs = seen_needs or s == "needs_chart"
		seen_broken = seen_broken or s == "broken"
	return true


func sc_songs() -> void:
	isolate_settings(true)
	await wait_library_idle()
	_make_fixture_library()
	isolate_library(FIXTURE_SONGS)
	var t_scan := Time.get_ticks_msec()
	if not check("fixture scan finished", await wait_library_idle(60.0)):
		return
	metrics["fixture_scan_s"] = _since(t_scan)
	var counts := {"ok": 0, "broken": 0, "needs_chart": 0, "bundled": 0}
	for e in SongLibrary.entries:
		counts[e.status] = int(counts.get(e.status, 0)) + 1
		if e.source == "bundled":
			counts["bundled"] += 1
	metrics["library_counts"] = counts
	var lib_expected: int = 31 + BundledSongs.SONGS.size()
	check("library: Calibration Track + %d bundled + 30 fixtures (%d entries)" % [BundledSongs.SONGS.size(), 31 + BundledSongs.SONGS.size()],
		SongLibrary.entries.size() == lib_expected,
		"%d entries %s" % [SongLibrary.entries.size(), counts])
	var opus := _entry_titled("Opus Broken Song")
	var bare := _entry_titled("Lonely Audio")
	var long_e := _entry_titled(LONG_TITLE)
	var cjk := _entry_titled(CJK_TITLE)
	var comm := _entry_titled("Community Song")
	var zipped := _entry_titled("Zipped Song")
	var dive_e := _entry_titled("Dive Test Song")
	var april := _entry_titled("Synth Wave April 3, 2022")
	var ebb := _entry_titled("Ebb Tide")
	check("Opus song listed broken with 'Opus audio not supported'",
		opus != null and opus.status == "broken" and opus.error == SongEntry.ERR_OPUS, opus.error if opus else null)
	check("bare WAV listed as Needs a chart", bare != null and bare.status == "needs_chart", bare.status if bare else null)
	check("community stems folder and zip import as playable", comm != null and comm.status == "ok"
		and zipped != null and zipped.status == "ok", [comm.status if comm else null, zipped.status if zipped else null])
	check("long, CJK, dive-test and bundled April entries playable", long_e != null and long_e.status == "ok"
		and cjk != null and cjk.status == "ok" and dive_e != null and dive_e.status == "ok" and april != null
		and april.status == "ok" and april.difficulties.size() == 4, [long_e, cjk, dive_e, april])
	if opus == null or bare == null or long_e == null or cjk == null or dive_e == null or april == null or ebb == null:
		return

	# --- (1) Start Dive -> Song Select, mid-list selection ------------------------------------------
	await goto(MENU)
	await wait(0.3)
	var m := cur() as MainMenu
	await menu_focus(m, m.start_button)
	await press_key(KEY_ENTER)
	if not check("Start Dive opens Song Select", await wait_until(func() -> bool: return cur() is SongSelect, 5.0), cur()):
		return
	var ss := _song_select()
	await wait(0.4)
	for i in 14:
		await press_key(KEY_DOWN)
	await wait(0.6)
	var st := ss.debug_state()
	metrics["midlist_state"] = st
	check("exactly 9 rows drawn with a %d-row list" % (31 + BundledSongs.SONGS.size()),
		(st["rows"] as Array).size() == 9 and int(st["view_size"]) == 31 + BundledSongs.SONGS.size(),
		"%d rows, view %d" % [(st["rows"] as Array).size(), st["view_size"]])
	check("mid-list selection scrolled (offset > 0, selected row visible)", int(st["offset"]) > 0 and _sel_row(ss) >= 0,
		"offset %d row %d" % [st["offset"], _sel_row(ss)])
	check("no onboarding row once imported songs exist",
		not bool(st["onboarding"]), st)
	_check_rows_fit(ss, "midlist")
	_check_footer(ss, "midlist")
	await shot("library_midlist")
	_check_list_text_contrast(ss, last_img, "midlist")

	# --- preview gate: none before 0.4 s after the last highlight change ------------------------------
	var left_pending := [-1]
	await press_key(KEY_DOWN)
	var change_ms: int = ss._preview_change_msec
	var sel_e := ss._selected()
	await wait_until(func() -> bool:
		if left_pending[0] < 0 and ss.debug_state()["preview_state"] != "pending":
			left_pending[0] = Time.get_ticks_msec()
		return ss.debug_state()["preview_state"] == "playing", 4.0)
	var gate_ms: int = left_pending[0] - change_ms
	metrics["preview_gate_ms"] = gate_ms
	check("preview starts no sooner than 0.4 s after the highlight change", gate_ms >= 400 and gate_ms < 1500,
		"%d ms (%s)" % [gate_ms, sel_e.title if sel_e else "?"])
	check("preview plays the highlighted song on the Preview bus", ss.debug_state()["preview_state"] == "playing"
		and ss._preview_player.playing and ss._preview_player.bus == &"Preview", ss.debug_state()["preview_state"])
	await wait(0.5)
	var viz_max := 0.0
	for v in ss.visualizer_levels():
		viz_max = maxf(viz_max, v)
	metrics["preview_visualizer_max"] = viz_max
	note("preview visualizer max level %.2f (audio driver %s)" % [viz_max, AudioServer.get_driver_name()])
	var tiles: Array = ss.debug_state()["tiles"]
	check("difficulty tiles show note counts and intensity", tiles.size() == 4 and tiles.any(func(t: Dictionary) -> bool:
		return bool(t["available"]) and String(t["text"]).ends_with(" NOTES") and int(t["intensity"]) >= 1), tiles)
	await shot("preview_playing")

	# --- (3) throttled rescan with rows inserted above the selection ---------------------------------
	for nm in ["AAA New Arrival", "AAB New Arrival", "AAC New Arrival"]:
		_fixture_song(FIXTURE_SONGS.path_join(nm), nm, "Late Band")
	var before_row := _sel_row(ss)
	var before_id: String = ss.debug_state()["selected"]
	var before_off: int = ss.debug_state()["offset"]
	SongLibrary.test_scan_throttle_msec = 150
	await press_key(KEY_F5)
	check("F5 starts a rescan", SongLibrary.scanning)
	await wait_until(func() -> bool:
		return (ss.debug_state()["scan_text"] as String).begins_with("Scanning") and ss._scan_done > 2, 10.0)
	await wait(0.2)
	var mid := ss.debug_state()
	metrics["mid_scan_state"] = mid
	await shot("mid_scan_progress")
	check("mid-scan: progress text 'Scanning n / total' and the Rescan button disabled",
		(mid["scan_text"] as String).begins_with("Scanning") and SongLibrary.scanning, mid["scan_text"])
	var bar_px := _chan_max(_patch(last_img, Vector2(706, 940), 1))
	check("mid-scan: progress bar fill visible at x 704, y 936", bar_px > 0.5, "%.3f" % bar_px)
	await wait_library_idle(60.0)
	SongLibrary.test_scan_throttle_msec = 0
	await wait(0.5)
	var after := ss.debug_state()
	metrics["insert_stability"] = {"before_row": before_row, "after_row": _sel_row(ss), "before_offset": before_off,
		"after_offset": after["offset"], "selected": after["selected"]}
	check("rescan inserting 3 rows above keeps the selected song", after["selected"] == before_id, after["selected"])
	check("rescan inserting 3 rows above keeps the selected row at the same screen y",
		_sel_row(ss) == before_row and int(after["offset"]) == before_off + 3,
		"row %d -> %d, offset %d -> %d" % [before_row, _sel_row(ss), before_off, after["offset"]])
	check("library now %d entries" % (34 + BundledSongs.SONGS.size()), int(after["view_size"]) == 34 + BundledSongs.SONGS.size(), after["view_size"])

	# --- (2) broken Opus and Needs-a-chart rows ---------------------------------------------------------
	ss.select_for_test(opus.id)
	await wait(0.7)
	st = ss.debug_state()
	check("broken Opus song selectable, Start disabled, no preview", st["selected"] == opus.id
		and not bool(st["start_enabled"]) and st["preview_state"] == "none", st)
	_check_rows_fit(ss, "broken")
	await shot("broken_opus")
	await press_key(KEY_ENTER)
	await wait(0.3)
	check("Enter on the broken row does nothing", cur() == ss and not bool(ss.debug_state()["diving"]))
	ss.select_for_test(bare.id)
	await wait(0.3)
	check("Needs-a-chart row selectable, Start disabled", not bool(ss.debug_state()["start_enabled"])
		and ss._start_label(bare) == "Needs a chart", ss._start_label(bare))
	_check_rows_fit(ss, "needs_chart")
	await shot("needs_chart")
	await press_key(KEY_ENTER)
	await wait(0.3)
	check("Enter on the Needs-a-chart row does nothing", cur() == ss and not bool(ss.debug_state()["diving"]))

	# --- (7) long and CJK titles --------------------------------------------------------------------------
	ss.select_for_test(long_e.id)
	await wait(0.3)
	var long_shown := ss._fit(LONG_TITLE, Palette.SIZE_BODY, 776.0, true)
	check("long title truncated in the row with three ASCII dots", long_shown.ends_with("...") and long_shown != LONG_TITLE,
		long_shown)
	_check_rows_fit(ss, "long_title")
	await shot("long_title")
	ss.select_for_test(cjk.id)
	await wait(0.3)
	var tofu := _tofu(ss, CJK_TITLE, Palette.SIZE_BODY) + _tofu(ss, CJK_ARTIST, Palette.SIZE_LABEL) \
		+ _tofu(ss, CJK_TITLE.to_upper(), Palette.SIZE_HEADING)
	check("CJK / Cyrillic title and artist render without missing glyphs (system font fallback)", tofu == 0,
		"%d missing glyphs" % tofu)
	_check_rows_fit(ss, "cjk")
	await shot("cjk_title")

	# --- difficulty snap -----------------------------------------------------------------------------------
	ss.select_for_test(april.id)
	await _set_difficulty(ss, "medium")
	var d_april: String = ss.debug_state()["difficulty"]
	ss.select_for_test(ebb.id)
	await frame()
	var d_fixture: String = ss.debug_state()["difficulty"]
	ss.select_for_test(april.id)
	await frame()
	var d_back: String = ss.debug_state()["difficulty"]
	check("difficulty snap: Medium wanted -> Easy on an Easy/Expert song, Medium again on April",
		d_april == "medium" and d_fixture == "easy" and d_back == "medium", [d_april, d_fixture, d_back])

	# --- album cover (02.2-17, D-11 / D-19) -------------------------------------------------------------------
	await wait(0.6)
	check("bundled song shows the generated cover", ss.debug_state()["cover"] == "generated", ss.debug_state()["cover"])
	await shot("cover_generated")
	ss.select_for_test(zipped.id)
	check("zipped song keeps its album.png and shows it as art",
		await wait_until(func() -> bool: return ss.debug_state()["cover"] == "art", 3.0), ss.debug_state()["cover"])
	# A fake best record so the shot shows the best-values row (harness state only, nothing saved).
	var zfp: String = str(zipped.difficulty(ss._diff).get("fingerprint", ""))
	ss._best_by_fp[zfp] = {"depth": 1240.0, "accuracy": 96.24, "max_combo": 80, "grade": "A", "misses": 1}
	await wait(0.4)
	check("best values: depth, accuracy and grade", ss.best_values(zipped) == {"depth": "1,240 M", "accuracy": "96.2%",
		"grade": "A"}, ss.best_values(zipped))
	await shot("cover_art_zip_best")
	ss._best_by_fp.erase(zfp)
	ss.select_for_test(ebb.id)
	check("folder album.jpg shows as art",
		await wait_until(func() -> bool: return ss.debug_state()["cover"] == "art", 3.0), ss.debug_state()["cover"])
	ss.select_for_test(comm.id)
	await wait(0.6)
	check("corrupt album.png falls back to the generated cover", ss.debug_state()["cover"] == "generated",
		ss.debug_state()["cover"])

	# --- 02.2-19: album.png fixture, generated cover stability, sections, visualizer, tile counts ----------
	var art_e := _entry_titled(ART_SONG)
	if art_e != null:
		ss.select_for_test(art_e.id)
		check("selected song with album.png shows its art",
			await wait_until(func() -> bool: return ss.debug_state()["cover"] == "art", 3.0), ss.debug_state()["cover"])
		var sec_ok: bool = await wait_until(func() -> bool:
			return ss.debug_state()["sections"]["state"] == "ready", 3.0)
		var sec: Dictionary = ss.debug_state()["sections"]
		check("sections block lists the chart's sections (count chip, names)", sec_ok
			and sec["names"] == ART_SECTIONS and int(sec["count"]) == ART_SECTIONS.size(), sec)
		await wait(0.8)
		await shot("art_cover")
	else:
		check("selected song with album.png shows its art", false, "fixture %s missing" % ART_SONG)
	var gen_e := _entry_titled("Abyssal Echo")
	if gen_e != null:
		ss.select_for_test(gen_e.id)
		await wait(0.8)
		check("song without art shows a generated cover", ss.debug_state()["cover"] == "generated",
			ss.debug_state()["cover"])
		var sec2: Dictionary = ss.debug_state()["sections"]
		check("chart without section events shows the empty sections line", sec2["state"] == "ready"
			and int(sec2["count"]) == 0 and ss.section_names_text([]) == SongSelect.NO_SECTIONS, sec2)
		await shot("generated_cover")
		var h1 := _cover_hash(last_img)
		var tex_a: Texture2D = ss._cover.generated_texture(gen_e.title)
		var data_a := tex_a.get_image().get_data() if tex_a != null else PackedByteArray()
		ss.select_for_test(ebb.id)
		await wait(0.8)
		ss.select_for_test(gen_e.id)
		await wait(0.8)
		var h2 := _cover_hash(await _grab())
		var fresh := AlbumCover.generated(gen_e.title).get_data()
		check("generated cover identical on reselect (screen area and image data hash)",
			h1 == h2 and hash(data_a) == hash(fresh) and not data_a.is_empty(),
			{"screen": [h1, h2], "data": [hash(data_a), hash(fresh)]})
	# Visualizer on a bundled song: preview starts after the gate, bars must move within 3 s.
	ss.select_for_test(april.id)
	var pv_ok: bool = await wait_until(func() -> bool: return ss.debug_state()["preview_state"] == "playing", 5.0)
	var viz_peak := [0.0]
	var moved := false
	if pv_ok:
		moved = await wait_until(func() -> bool:
			for v in ss.visualizer_levels():
				viz_peak[0] = maxf(viz_peak[0], v)
			return viz_peak[0] > 0.1, 3.0)
	metrics["bundled_visualizer_max"] = viz_peak[0]
	check("visualizer moves while the preview plays (max level > 0.1 within 3 s, bundled April)", moved,
		"preview %s, max %.2f (driver %s)" % [ss.debug_state()["preview_state"], viz_peak[0],
		AudioServer.get_driver_name()])
	var tl: Array = ss.debug_state()["tiles"]
	var di := SongListModel.DIFFICULTY_ORDER.find(ss._diff)
	var want_n := int(april.difficulty(ss._diff).get("note_count", -1))
	check("difficulty tile shows note count", di >= 0 and want_n > 0
		and tl[di]["text"] == "%s NOTES" % SongListModel.fmt_count(want_n), [ss._diff, tl[di] if di >= 0 else null, want_n])

	# --- sort orders, broken last ---------------------------------------------------------------------------
	var sorts := {}
	var sort_ok := true
	for i in 3:
		var stat := _view_statuses(ss)
		sorts[SongListModel.sort_label(ss._sort)] = _unplayable_last(stat)
		sort_ok = sort_ok and _unplayable_last(stat) and stat[stat.size() - 1] == "broken"
		await press_key(KEY_F2)
	check("every sort order (title, artist, best) keeps Needs-a-chart then broken rows last", sort_ok, sorts)
	check("F2 cycles back to SORT: TITLE after 3 presses", ss._sort == SongListModel.SortMode.TITLE, ss._sort)

	# --- (4) filter with no match, (6) filter with count, digits, Esc order -----------------------------------
	ss.select_for_test(ebb.id)
	await frame()
	var idx0 := ss._sel_index()
	await press_key(KEY_2)
	check("digit 2 moves down one row while the filter is empty", ss._sel_index() == idx0 + 1 and ss._filter == "",
		"%d -> %d" % [idx0, ss._sel_index()])
	ss.type_for_test("zzqx")
	await wait(0.2)
	check("no-match filter shows NO MATCHES", ss.debug_state()["empty_state"] == "no_matches", ss.debug_state())
	await shot("filter_no_match")
	await press_key(KEY_ESCAPE)
	check("Esc clears the filter first and stays on Song Select", cur() == ss and ss._filter == "", ss._filter)
	ss.type_for_test("tide")
	await wait(0.2)
	st = ss.debug_state()
	check("filter 'tide' shows 2 matches (Ebb Tide, Riptide)", int(st["view_size"]) == 2, st)
	ss.press_key_for_test(KEY_1, 49)
	check("digit 1 types into a non-empty filter instead of navigating", ss._filter == "tide1", ss._filter)
	ss.press_key_for_test(KEY_BACKSPACE)
	await wait(0.2)
	await shot("filter_count")
	_check_footer(ss, "filter")
	await press_key(KEY_ESCAPE)
	check("Esc with a filter clears it", ss._filter == "" and cur() == ss, ss._filter)

	# --- (9) Low effects and Reduce motion ---------------------------------------------------------------------
	ss.select_for_test(april.id)
	await wait(0.5)
	var rows_full: Array = ss.debug_state()["rows"]
	Settings.low_effects = true
	Settings.settings_changed.emit()
	await wait(0.5)
	await shot("low_effects")
	_check_list_text_contrast(ss, last_img, "low_effects")
	check("Low effects: same rows and selection", ss.debug_state()["rows"] == rows_full)
	Settings.low_effects = false
	Settings.reduce_motion = true
	Settings.settings_changed.emit()
	await wait(0.5)
	await shot("reduce_motion")
	_check_list_text_contrast(ss, last_img, "reduce_motion")
	check("Reduce motion: same rows, scroll snapped (no smooth scroll)",
		ss.debug_state()["rows"] == rows_full and is_equal_approx(ss._scroll_vis, float(ss._offset)))
	Settings.reduce_motion = false
	Settings.settings_changed.emit()
	await wait(0.3)
	await press_key(KEY_ESCAPE)
	check("Esc with an empty filter returns to the main menu",
		await wait_until(func() -> bool: return cur() is MainMenu, 5.0), cur())

	# --- (8) Settings > LIBRARY with two folders (one missing) ---------------------------------------------------
	var extra := ProjectSettings.globalize_path(LIB_ROOT.path_join("extra_lib"))
	var missing := ProjectSettings.globalize_path(LIB_ROOT.path_join("missing_lib"))
	_fixture_song(extra.path_join("Library Song"), "Library Song", "Shelf Band")
	Settings.library_folders.assign([extra, missing])
	SongLibrary.rescan()
	await wait_library_idle(30.0)
	check("extra folder scanned read-in-place, missing folder reported", _entry_titled("Library Song") != null
		and _entry_titled("Library Song").source == "library" and SongLibrary.folder_error.contains("missing_lib"),
		SongLibrary.folder_error)
	m = cur() as MainMenu
	await menu_focus(m, m.settings_button)
	await press_key(KEY_ENTER)
	if not check("Settings opens", await wait_until(func() -> bool: return cur() is SettingsScreen, 5.0)):
		return
	var sset := cur() as SettingsScreen
	await wait(0.3)
	sset.add_folder_button.grab_focus()
	await wait(0.5)
	var statuses: Array = []
	for row in sset.library_rows.get_children():
		statuses.append((row.get_child(1) as Label).text)
	metrics["settings_library_status"] = statuses
	check("Settings > LIBRARY lists both folders: '1 song' and red 'Folder not found'", statuses.size() == 2
		and (statuses[0] as String).begins_with("1 song") and statuses[1] == "Folder not found", statuses)
	await shot("settings_library")
	await press_key(KEY_ESCAPE)
	await wait_until(func() -> bool: return cur() is MainMenu, 5.0)
	Settings.library_folders.clear()

	# --- (5) onboarding (bundled only) and empty library -----------------------------------------------------------
	isolate_library(EMPTY_SONGS)
	await wait_library_idle(30.0)
	await goto(SONG_SELECT)
	ss = _song_select()
	await wait(0.6)
	st = ss.debug_state()
	# rows: every bundled song + the Calibration Track + the onboarding row
	check("only bundled songs: onboarding row shown, footer shows the Songs path (%d rows)" % (2 + BundledSongs.SONGS.size()),
		bool(st["onboarding"]) and int(st["view_size"]) == 2 + BundledSongs.SONGS.size(), st)
	await shot("onboarding_bundled_only")
	_check_list_text_contrast(ss, last_img, "onboarding")
	var fake: Node = load("res://src/autoload/song_library.gd").new()
	fake.auto_scan = false
	fake.songs_root_override = EMPTY_SONGS
	fake.cache_path = LIB_ROOT + "/fake_cache.json"
	add_child(fake)
	fake.entries.clear()
	var empty_ss: SongSelect = load(SONG_SELECT).instantiate()
	empty_ss.library = fake
	var old := cur()
	get_tree().root.add_child(empty_ss)
	get_tree().current_scene = empty_ss
	old.queue_free()
	await wait(0.6)
	st = empty_ss.debug_state()
	check("empty library: NO SONGS FOUND with the exact Songs folder path, Start disabled",
		st["empty_state"] == "no_songs" and not bool(st["start_enabled"]), st)
	metrics["empty_state_path"] = fake.songs_dir()
	await shot("empty_library")
	await goto(MENU)
	fake.queue_free()
	await frame()

	# --- dive from Song Select: Autoplay on the 6 s fixture, to the results ---------------------------------------
	isolate_library(FIXTURE_SONGS)
	await wait_library_idle(30.0)
	await goto(MENU)
	await wait(0.3)
	m = cur() as MainMenu
	await menu_focus(m, m.autoplay_button)
	await press_key(KEY_ENTER)
	await wait_until(func() -> bool: return cur() is SongSelect, 5.0)
	ss = _song_select()
	await wait_library_idle()
	dive_e = _entry_titled("Dive Test Song")
	ss.select_for_test(dive_e.id)
	await _set_difficulty(ss, "expert")
	await wait(1.2)
	var pv_before: String = ss.debug_state()["preview_state"]
	await press_key(KEY_ENTER)
	check("dive stops the preview", pv_before == "playing" and ss.debug_state()["preview_state"] != "playing"
		and bool(ss.debug_state()["diving"]), "before %s after %s" % [pv_before, ss.debug_state()["preview_state"]])
	var ok: bool = await wait_until(func() -> bool: return cur() is Gameplay, 5.0)
	if not check("Song Select dive reaches Gameplay", ok, cur()):
		return
	var g := cur() as Gameplay
	var fp: String = dive_e.difficulty("expert")["fingerprint"]
	check("Gameplay runs the chosen chart (fingerprint id) with Autoplay", g.chart.id == fp and g.autoplay,
		"%s vs %s" % [g.chart.id, fp])
	ok = await wait_until(func() -> bool: return g.state == Gameplay.State.DONE, 30.0)
	await wait(0.6)
	check("autoplay dive on the imported song finishes P>0 M0", ok and g.score.perfect_count > 0
		and g.score.miss_count == 0, "P%d G%d M%d" % [g.score.perfect_count, g.score.good_count, g.score.miss_count])
	await shot("fixture_results")

	# --- gameplay on a bundled song (Autoplay, Expert) --------------------------------------------------------------
	await goto(MENU)
	await wait(0.3)
	m = cur() as MainMenu
	await menu_focus(m, m.autoplay_button)
	await press_key(KEY_ENTER)
	g = await dive_from_song_select(april.id, "expert")
	if g == null:
		return
	check("bundled April runs with its fingerprint chart and real audio",
		g.chart.id == april.difficulty("expert")["fingerprint"] and g.chart.audio_stream != null
		and g.chart.audio_stream.get_length() > 120.0, g.chart.id)
	await wait_until(func() -> bool: return g.conductor.song_time() > 22.0, 40.0)
	var fps0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await wait(2.0)
	var fps := (Engine.get_frames_drawn() - fps0) / maxf(0.001, _since(t0))
	metrics["bundled_fps"] = fps
	await shot("bundled_gameplay", g)
	check("bundled song autoplay: all judged notes Perfect so far", g.score.miss_count == 0 and g.score.good_count == 0
		and g.score.perfect_count > 20, "P%d G%d M%d" % [g.score.perfect_count, g.score.good_count, g.score.miss_count])
	check("bundled gameplay frame rate >= 60 fps", fps >= 60.0, "%.1f fps" % fps)
	await goto(MENU)
	await wait(0.3)
	metrics["real_songs_dir"] = ProjectSettings.globalize_path("user://songs")



# ------------------------------------------------------------------------------------------------
# align (02-06, not in run_all): bundled song audio vs chart grid. Writes, per bundled song,
#   build/playtest/align_<id>_decoded.wav   the game's own stream, whole song, decoded offline
#                                           (decode_stream: AudioStreamPlayback.mix_audio, sample exact)
#   build/playtest/align_<id>_recorded.wav  its first 24 s recorded live from a temp bus (AudioEffectRecord)
# Metrics <id>_decoded_frames / <id>_decoded_s are the real decoded length (some MP3s decode shorter than
# get_length() promises, 02.1 RESEARCH Pitfall 4); use it for song.ini song_length.
# Limit to chosen songs with a user arg: -- align --no-boot-scan --only=<id>[,<id>...]
# Analyse with: tools/autochart/note_sync.py (sync gate) or tools/charting/grid_offset.py <wav> <bpm> <delay_ms>
# ------------------------------------------------------------------------------------------------

const ALIGN_SECONDS := 24.0


func _write_wav16(path: String, frames: PackedVector2Array, rate: int) -> void:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = rate
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i in frames.size():
		data.encode_s16(i * 4, clampi(int(round(frames[i].x * 32767.0)), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(int(round(frames[i].y * 32767.0)), -32768, 32767))
	w.data = data
	w.save_to_wav(path)


## Decodes a whole stream offline through the same AudioStreamPlayback the player uses (02.1-01).
## Terminates when mix_audio returns no frames or the playback stops, and never returns more than
## ceil((get_length() + 5 s) * rate) frames, so an MP3 that decodes shorter than get_length()
## (02.1 RESEARCH Pitfall 4) cannot loop forever.
static func decode_stream(stream: AudioStream, rate: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	if stream == null:
		return frames
	var pb := stream.instantiate_playback()
	if pb == null or not pb.has_method("mix_audio"):
		return frames
	var cap := int(ceil((stream.get_length() + 5.0) * rate))
	pb.start(0.0)
	while frames.size() < cap:
		var chunk: PackedVector2Array = pb.mix_audio(1.0, mini(4096, cap - frames.size()))
		if chunk.is_empty():
			break
		frames.append_array(chunk)
		if not pb.is_playing():
			break
	pb.stop()
	return frames


## Bundled ids passed as --only=<id>[,<id>...] (empty = all songs).
func _align_only_ids() -> PackedStringArray:
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--only="):
			var ids := PackedStringArray()
			for part in arg.substr(7).split(",", false):
				ids.append(part.strip_edges())
			return ids
	return PackedStringArray()


func sc_align() -> void:
	isolate_settings(true)
	await wait_library_idle(60.0)
	var rate := int(AudioServer.get_mix_rate())
	metrics["mix_rate"] = rate
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "AlignRecord")
	AudioServer.set_bus_send(bus, "Master")
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, rec)
	var only := _align_only_ids()
	if not only.is_empty():
		metrics["align_only"] = ",".join(only)
	for b in BundledSongs.SONGS:
		if not only.is_empty() and not only.has(str(b["id"])):
			continue
		var e := SongLibrary.find(str(b["dir"]))
		if not check("bundled %s listed" % b["id"], e != null and e.status == "ok"):
			continue
		var chart := SongLibrary.build_chart(e, "expert")
		if not check("bundled %s builds" % b["id"], chart != null and chart.audio_stream != null):
			continue
		var stream: AudioStream = chart.audio_stream
		metrics["%s_delay_ms" % b["id"]] = e.delay_ms
		metrics["%s_stream" % b["id"]] = stream.get_class()
		# 1. offline decode through the same AudioStreamPlayback the player uses
		var frames := decode_stream(stream, rate)
		if frames.size() > 0:
			var dpath := ProjectSettings.globalize_path("%s/align_%s_decoded.wav" % [OUT_DIR, b["id"]])
			_write_wav16(dpath, frames, rate)
			metrics["%s_decoded_frames" % b["id"]] = frames.size()
			metrics["%s_decoded_s" % b["id"]] = frames.size() / float(rate)
			metrics["%s_length_s" % b["id"]] = stream.get_length()
			check("%s decoded %.1f s (whole song, get_length %.1f s) to %s" % [b["id"], frames.size() / float(rate),
				stream.get_length(), dpath.get_file()], frames.size() > 0)
		else:
			check("%s decoded (decode_stream returned 0 frames; mix_audio missing or stream empty)" % b["id"], false)
		# 2. live recording from the temp bus (start recording and playback in the same frame)
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "AlignRecord"
		add_child(player)
		await frame()
		rec.set_recording_active(true)
		player.play(0.0)
		await wait(ALIGN_SECONDS + 0.3)
		rec.set_recording_active(false)
		player.stop()
		player.queue_free()
		var wav := rec.get_recording()
		var rpath := ProjectSettings.globalize_path("%s/align_%s_recorded.wav" % [OUT_DIR, b["id"]])
		if check("%s recorded" % b["id"], wav != null and wav.data.size() > 0):
			wav.save_to_wav(rpath)
			metrics["%s_recorded_s" % b["id"]] = wav.get_length()
		await wait(0.3)
	AudioServer.remove_bus(bus)



# ------------------------------------------------------------------------------------------------
# Phase 2.2 Wave 0: frame-time capture (D-06 / D-17) and the visual screenshot scenario (D-15)
# ------------------------------------------------------------------------------------------------

const PERF_WINDOW_S := 30.0
const PERF_MAX_START_S := 60.0  # Conductor has no seek (timing core): the window must start early
const PERF_P95_GATE_MS := 4.35  # 4.35 ms p95 uncapped = the build can sustain >= 230 fps
const PERF_RES := Vector2i(1920, 1080)


## Priority-1000 per-frame recorder: Time.get_ticks_usec() deltas plus the root viewport's measured
## render CPU/GPU time. Read-only, like frame_probe.gd.
class FrameCapture extends Node:
	var deltas_ms: PackedFloat64Array = PackedFloat64Array()
	var cpu_ms: PackedFloat64Array = PackedFloat64Array()
	var gpu_ms: PackedFloat64Array = PackedFloat64Array()
	var vp_rid: RID
	var _last: int = -1

	func _ready() -> void:
		process_priority = 1000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if _last >= 0:
			deltas_ms.append((now - _last) / 1000.0)
			cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid))
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
		_last = now


static func _quantile(sorted: Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[int(q * (sorted.size() - 1))])


## Records `seconds` of frames uncapped (vsync off, Engine.max_fps = 0) and restores both after
## (T-02.2-01). uncapped = false measures with vsync on (240 Hz screens only). Returns n,
## p50/p95/p99/max frame ms, avg fps, render cpu/gpu p95 ms.
func capture_frames(seconds: float, uncapped: bool = true) -> Dictionary:
	var prev_vsync := DisplayServer.window_get_vsync_mode()
	var prev_max := Engine.max_fps
	if uncapped:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await frame()
	await frame()
	var cap := FrameCapture.new()
	cap.vp_rid = rid
	add_child(cap)
	var t0 := Time.get_ticks_usec()
	await wait(seconds)
	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0
	remove_child(cap)
	RenderingServer.viewport_set_measure_render_time(rid, false)
	DisplayServer.window_set_vsync_mode(prev_vsync)
	Engine.max_fps = prev_max
	var d := Array(cap.deltas_ms)
	var c := Array(cap.cpu_ms)
	var gg := Array(cap.gpu_ms)
	cap.free()
	d.sort()
	c.sort()
	gg.sort()
	return {"n": d.size(), "p50": _quantile(d, 0.50), "p95": _quantile(d, 0.95), "p99": _quantile(d, 0.99),
		"max": float(d[-1]) if not d.is_empty() else 0.0, "avg_fps": d.size() / maxf(elapsed, 0.001),
		"cpu_p95": _quantile(c, 0.95), "gpu_p95": _quantile(gg, 0.95)}


## Densest 30 s Expert window per bundled song, starting within the first PERF_MAX_START_S seconds.
## Parses the chart only (no audio decode). Returns {id, dir, start, count, per_song}.
func _densest_bundled_window() -> Dictionary:
	var best := {"id": "", "dir": "", "start": 0.0, "count": -1}
	var per_song := {}
	for b in BundledSongs.SONGS:
		var e := SongLibrary.find(str(b["dir"]))
		if e == null or e.status != "ok" or e.difficulty("expert").is_empty():
			per_song[str(b["id"])] = "unavailable"
			continue
		var parsed := ChartParser.parse_bytes(FileAccess.get_file_as_bytes(e.chart_path))
		if not parsed.ok:
			per_song[str(b["id"])] = "parse failed"
			continue
		var chart := ChartImporter.build(parsed, "expert", e.delay_ms)
		var times: Array = []
		for n in chart.notes:
			times.append(float(n["time"]))
		times.sort()
		var j := 0
		var top := 0
		var top_start := 0.0
		for i in range(times.size()):
			var s: float = times[i]
			if s > PERF_MAX_START_S:
				break
			if j < i:
				j = i
			while j < times.size() and float(times[j]) < s + PERF_WINDOW_S:
				j += 1
			if j - i > top:
				top = j - i
				top_start = s
		per_song[str(b["id"])] = {"start": top_start, "count": top}
		if top > int(best["count"]):
			best = {"id": str(b["id"]), "dir": str(b["dir"]), "start": top_start, "count": top}
	best["per_song"] = per_song
	return best


## Forces a 1920x1080 render (B1: project.godot overrides the window to 1600x900). On a 1920x1080
## screen this is the game's own default, borderless WINDOW_MODE_FULLSCREEN (D-06 settings): a
## hand-made borderless window covering the screen is promoted to EXCLUSIVE_FULLSCREEN by Windows /
## Godot, where vsync can no longer be turned off (measured: 16.7 ms frames). On any other screen
## size a 1920x1080 window is used. Returns the saved window state for _restore_window().
func _force_capture_window() -> Dictionary:
	var saved := {
		"mode": DisplayServer.window_get_mode(),
		"size": DisplayServer.window_get_size(),
		"pos": DisplayServer.window_get_position(),
		"borderless": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
	}
	# Always the screen the window is on (the secondary monitor under run_all.ps1), never screen 0
	# or the primary, so the capture never takes over the user's main monitor.
	var scr := DisplayServer.window_get_current_screen()
	var screen := DisplayServer.screen_get_size(scr)
	saved["screen"] = screen
	saved["screen_index"] = scr
	if screen == PERF_RES:
		DisplayServer.window_set_current_screen(scr)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await frame()
		DisplayServer.window_set_size(PERF_RES)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(scr))
	for k in range(3):
		await frame()
	saved["capture_mode"] = DisplayServer.window_get_mode()
	return saved


func _restore_window(saved: Dictionary) -> void:
	var scr := int(saved.get("screen_index", DisplayServer.window_get_current_screen()))
	if DisplayServer.window_get_current_screen() != scr:
		DisplayServer.window_set_current_screen(scr)
	if saved["mode"] == DisplayServer.WINDOW_MODE_WINDOWED or saved["mode"] == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await frame()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(saved["borderless"]))
		DisplayServer.window_set_size(saved["size"])
		DisplayServer.window_set_position(saved["pos"])
	DisplayServer.window_set_mode(saved["mode"])
	await frame()


## Waits until the run's song clock reaches `t` (re-reads the conductor: restarts replace it).
func _wait_song_time(g: Gameplay, t: float, timeout: float) -> bool:
	return await wait_until(func() -> bool:
		return is_instance_valid(g) and g.conductor != null and g.conductor.song_time() >= t, timeout)


## D-17 frame-time capture: uncapped p95 over the densest 30 s of a bundled Expert chart, Full and
## Low effects, at a forced 1920x1080 window. Refresh rate is logged, never a failure.
func sc_perf() -> void:
	isolate_settings(true)
	await wait_library_idle(60.0)
	var win := _densest_bundled_window()
	metrics["perf_windows"] = win["per_song"]
	if not check("perf: densest bundled window found", int(win["count"]) > 0, win):
		return
	# Gameplay exposes no start-position option and Conductor (timing core) has no public seek: wait.
	var method := "wait"
	note("perf window: %s @ %.1f s, %d notes in %d s (%s)" % [win["id"], win["start"], win["count"],
		int(PERF_WINDOW_S), method])
	metrics["song_id"] = win["id"]
	metrics["window_start_s"] = win["start"]
	metrics["window_notes"] = win["count"]
	metrics["window_method"] = method
	metrics["refresh_hz"] = DisplayServer.screen_get_refresh_rate()
	metrics["gpu"] = RenderingServer.get_video_adapter_name()
	var saved := await _force_capture_window()
	var sz := get_window().size
	var vis := get_viewport().get_visible_rect().size
	metrics["capture_resolution"] = "%dx%d" % [sz.x, sz.y]
	metrics["screen_size"] = str(saved["screen"])
	metrics["capture_window_mode"] = saved["capture_mode"]
	check("capture window is 1920x1080", sz == PERF_RES and Vector2i(vis) == PERF_RES,
		"window %s, visible rect %s, screen %s, mode %d" % [sz, vis, saved["screen"], saved["capture_mode"]])
	check("capture window is not exclusive fullscreen (vsync could not be disabled)",
		saved["capture_mode"] != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, saved["capture_mode"])
	Settings.low_effects = false
	Settings.settings_changed.emit()
	await goto(MENU)
	SongSelect.run_autoplay = true
	await goto(SONG_SELECT)
	var g := await dive_from_song_select(str(win["dir"]), "expert")
	if g == null or not await wait_for_began(g):
		check("perf dive began", false)
		await _restore_window(saved)
		return
	var start_t: float = win["start"]
	var wait_limit := start_t + 20.0
	check("perf: Full reached window start", await _wait_song_time(g, start_t, wait_limit))
	var full := await capture_frames(PERF_WINDOW_S)
	metrics["frames"] = full["n"]
	metrics["frame_ms_p50_full"] = full["p50"]
	metrics["frame_ms_p95_full"] = full["p95"]
	metrics["frame_ms_p99_full"] = full["p99"]
	metrics["frame_ms_max_full"] = full["max"]
	metrics["avg_fps_full"] = full["avg_fps"]
	metrics["render_cpu_ms_p95"] = full["cpu_p95"]
	metrics["render_gpu_ms_p95"] = full["gpu_p95"]
	if float(metrics["refresh_hz"]) >= 239.0:
		var vs := await capture_frames(5.0, false)
		metrics["vsync_avg_fps"] = vs["avg_fps"]
	note("Full: n=%d p50 %.3f p95 %.3f p99 %.3f ms (cpu p95 %.3f, gpu p95 %.3f)" % [full["n"], full["p50"],
		full["p95"], full["p99"], full["cpu_p95"], full["gpu_p95"]])
	# Low effects: the same window on a restarted run.
	Settings.low_effects = true
	Settings.settings_changed.emit()
	if is_instance_valid(g):
		g.restart(true)
		await frame()
	var began_low: bool = is_instance_valid(g) and await wait_for_began(g)
	check("perf: Low run began", began_low)
	var reached_low: bool = began_low and await _wait_song_time(g, start_t, wait_limit)
	check("perf: Low reached window start", reached_low)
	var low := await capture_frames(PERF_WINDOW_S)
	metrics["frames_low"] = low["n"]
	metrics["frame_ms_p50_low"] = low["p50"]
	metrics["frame_ms_p95_low"] = low["p95"]
	metrics["frame_ms_p99_low"] = low["p99"]
	metrics["frame_ms_max_low"] = low["max"]
	metrics["avg_fps_low"] = low["avg_fps"]
	metrics["render_cpu_ms_p95_low"] = low["cpu_p95"]
	metrics["render_gpu_ms_p95_low"] = low["gpu_p95"]
	note("Low: n=%d p50 %.3f p95 %.3f p99 %.3f ms" % [low["n"], low["p50"], low["p95"], low["p99"]])
	Settings.low_effects = false
	Settings.settings_changed.emit()
	await _restore_window(saved)
	note("refresh %.2f Hz (logged only, never a failure)" % float(metrics["refresh_hz"]))
	check("perf Full capture has >= 1000 frames", int(full["n"]) >= 1000, full["n"])
	check("Full p95 <= 4.35 ms (uncapped, D-17)", float(full["p95"]) <= PERF_P95_GATE_MS, "%.3f ms" % full["p95"])
	check("Low p95 <= 4.35 ms (uncapped)", float(low["p95"]) <= PERF_P95_GATE_MS, "%.3f ms" % low["p95"])
	await goto(MENU)


## Board/HUD screenshots of later 02.2 slices go here (not into sc_immersion).
func sc_visual() -> void:
	isolate_settings(true)
	await wait_library_idle(60.0)
	var b: Dictionary = BundledSongs.SONGS[0]
	await goto(MENU)
	SongSelect.run_autoplay = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	await goto(SONG_SELECT)
	var g := await dive_from_song_select(str(b["dir"]), "expert")
	var ok: bool = g != null and await wait_for_began(g)
	if ok:
		await _visual_board_tiers(g)
	if ok and is_instance_valid(g):
		ok = await _wait_song_time(g, maxf(6.0, g.conductor.song_time()), 20.0)
		await shot("visual_baseline", g)
	check("visual scenario runs", ok and is_instance_valid(g) and g.state == Gameplay.State.RUNNING)
	if ok and is_instance_valid(g):
		await _visual_trench(g)
	if ok and is_instance_valid(g):
		await _visual_bursts(g)
	await _visual_hud()
	# 02.2-24: readability / Full vs Low on a fresh dive, so the burst and trench shots above keep
	# their song moments (judgment popup crowding depends on where in the song they land).
	await goto(MENU)
	SongSelect.run_autoplay = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	await goto(SONG_SELECT)
	var g2 := await dive_from_song_select(str(b["dir"]), "expert")
	if g2 != null and await wait_for_began(g2) and await _wait_song_time(g2, 6.0, 20.0):
		await _visual_readability(g2)
	else:
		check("readability dive reached 6 s", false)
	await goto(MENU)


## WCAG relative luminance of an sRGB colour (alpha ignored).
func _wcag_lum(c: Color) -> float:
	var ch := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * float(ch.call(c.r)) + 0.7152 * float(ch.call(c.g)) + 0.0722 * float(ch.call(c.b))


func _wcag_ratio(a: Color, b: Color) -> float:
	var la := _wcag_lum(a)
	var lb := _wcag_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Rim vs the strip just outside a gem, on rays from its centre (left, right and down; `rays`
## lists the ones to use): the rim is the brightest pixel between 0.5 r and 1.4 r (the top-light
## sits above the centre line, so each ray crosses core -> rim -> keyline -> strip), the keyline
## the darkest pixel within 6 px past it, and the strip pixel sits 4 px outside the keyline's outer
## edge. Returns the worst ray: {ratio, rim, out, ray}.
func _gem_rim_contrast(img: Image, center: Vector2, r: float, rays: Array = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]) -> Dictionary:
	var worst := {"ratio": INF}
	for dir: Vector2 in rays:
		var best_l := -1.0
		var best_x := 0.0
		var x := 0.5 * r
		while x <= 1.4 * r:
			var l := _wcag_lum(_img_px(img, center + dir * x))
			if l > best_l:
				best_l = l
				best_x = x
			x += 1.0
		var key_l := INF
		var key_x := best_x
		var k := best_x + 1.0
		while k <= best_x + 6.0:
			var l2 := _wcag_lum(_img_px(img, center + dir * k))
			if l2 < key_l:
				key_l = l2
				key_x = k
			k += 1.0
		var rim := _img_px(img, center + dir * best_x)
		var out := _img_px(img, center + dir * (key_x + NotePainter.KEYLINE_W * 0.5 + 4.0))
		var ratio := _wcag_ratio(rim, out)
		if ratio < float(worst["ratio"]):
			worst = {"ratio": snappedf(ratio, 0.01), "rim": rim.to_html(false), "out": out.to_html(false),
				"ray": dir, "rim_dx": snappedf(best_x, 0.1)}
	return worst


## Rays for _gem_rim_contrast that do not cross a chord bar or a neighbouring gem: left / right
## are dropped when another pending note lies within 2 lanes on that side at about the same depth,
## down when a note in the same lane is close below.
func _clear_rays(g: Gameplay, info: Dictionary) -> Array:
	var rays: Array = []
	var lane := int(info["lane"])
	var d := float(info["d"])
	var left_busy := false
	var right_busy := false
	var down_busy := false
	for v in _visible_pending(g):
		if int(v["i"]) == int(info["i"]):
			continue
		var dd := absf(float(v["d"]) - d)
		var vl := int(v["lane"])
		if vl < lane and dd < 0.08:
			left_busy = true
		elif vl > lane and dd < 0.08:
			right_busy = true
		elif vl == lane and float(v["d"]) < d and d - float(v["d"]) < 0.12:
			down_busy = true
	if not left_busy:
		rays.append(Vector2.LEFT)
	if not right_busy:
		rays.append(Vector2.RIGHT)
	if not down_busy:
		rays.append(Vector2.DOWN)
	return rays


## True when another note starts within 2 ms of note i (a chord: a chord bar joins the gems).
func _is_chord(g: Gameplay, i: int) -> bool:
	var t := float(g.chart.notes[i]["time"])
	for j in range(maxi(i - 4, 0), mini(i + 5, g.chart.notes.size())):
		if j != i and absf(float(g.chart.notes[j]["time"]) - t) < 0.002:
			return true
	return false


## Pauses the conductor when the next single (non-chord) pending note in `lane` (at least `min_ahead` s ahead of the
## pause) sits at depth `d`; returns its index or -1. Input is disabled for the frozen frame.
func _freeze_gem_at_depth(g: Gameplay, lane: int, d: float, min_ahead: float = 0.4) -> int:
	var approach := Trench.approach_for(Settings.scroll_speed)
	var st := g.conductor.song_time()
	var pick := -1
	for i in range(g.chart.notes.size()):
		var n: Dictionary = g.chart.notes[i]
		if g.highway._state[i] != Highway.S_PENDING or (lane >= 0 and int(n["lane"]) != lane):
			continue
		if float(n["time"]) - Settings.visual_offset - d * approach > st + min_ahead and not _is_chord(g, i):
			pick = i
			break
	if pick < 0:
		return -1
	var gw: WeakRef = weakref(g)
	var c := g.conductor
	var t := float(g.chart.notes[pick]["time"]) - Settings.visual_offset - d * approach
	var sched := [{"t": t, "o": 0, "fn": func() -> void:
		c.pause()
		g.lane_input.enabled = false}]
	await run_schedule(c, sched, func() -> bool: return _gone_or_stopped(gw))
	return pick if is_instance_valid(g) and g.conductor != null and g.conductor.is_paused() else -1


## Readability of the gem `idx` in the last shot: core matches the lane colour within r 6 and the
## rim-to-strip WCAG ratio. {ok, core_cos, rim, d, r, lane}.
func _gem_readable(g: Gameplay, idx: int) -> Dictionary:
	var info := {}
	for v in _visible_pending(g):
		if int(v["i"]) == idx:
			info = v
	if info.is_empty():
		return {"ok": false, "why": "gem %d not visible in the shot" % idx}
	var d := float(info["d"])
	var r := Trench.note_radius(Trench.scale_at(d))
	var lane := int(info["lane"])
	var core := _colour_near(last_img, info["center"], Palette.lane_color(lane), 6.0)
	var rays := _clear_rays(g, info)
	if rays.is_empty():
		return {"ok": false, "why": "gem %d boxed in by neighbours" % idx}
	var rim := _gem_rim_contrast(last_img, info["center"], r, rays)
	return {"ok": bool(core["ok"]) and float(rim["ratio"]) >= 4.5, "core_cos": snappedf(float(core["cos"]), 0.001),
		"rim": rim, "rays": rays.size(), "d": snappedf(d, 0.01), "r": snappedf(r, 0.1), "lane": lane}


## 02.2-24 (VIS-10, S-10, AV-01): gems readable at scroll 0.5x and 3x, gem rim crisp at Full, and a
## Full vs Low pair of the same frozen frame. The amber lane (circle gem) is used so the rim ray
## meets the outline square-on; the gem is frozen at depth 0.35 (mid-board, not yet ready, no halo).
func _visual_readability(g: Gameplay) -> void:
	var orig_speed := Settings.scroll_speed
	var gw: WeakRef = weakref(g)
	for sp in [[0.5, "gameplay_scroll_0_5x", "0.5x"], [3.0, "gameplay_scroll_3x", "3x"]]:
		if _gone_or_stopped(gw):
			check("gems readable at %s" % sp[2], false, "run stopped")
			break
		Settings.set_scroll_speed(float(sp[0]))
		await wait(0.3)
		var idx := await _freeze_gem_at_depth(g, 1, 0.35)
		if idx < 0:
			_unfreeze(g)
			check("gems readable at %s" % sp[2], false, "no amber gem to freeze")
			continue
		await wait(0.2)
		await shot(String(sp[1]), g)
		var res := _gem_readable(g, idx)
		check("gems readable at %s" % sp[2], bool(res["ok"]), res)
		_unfreeze(g)
	Settings.set_scroll_speed(orig_speed)
	await wait(0.3)
	if _gone_or_stopped(gw):
		check("gem rim crisp", false, "run stopped")
		return
	var idx1 := await _freeze_gem_at_depth(g, 1, 0.35)
	if idx1 < 0:
		_unfreeze(g)
		check("gem rim crisp", false, "no amber gem to freeze")
		return
	await wait(0.2)
	await shot("gameplay_full", g)
	var full := _gem_readable(g, idx1)
	check("gem rim crisp", full.has("rim") and float(full["rim"]["ratio"]) >= 4.5, full)
	Settings.low_effects = true
	Settings.settings_changed.emit()
	await wait(0.3)
	await shot("gameplay_low", g)
	var low := _gem_readable(g, idx1)
	check("gems readable in Low effects (same frame)", bool(low.get("ok", false)), low)
	Settings.low_effects = false
	Settings.settings_changed.emit()
	await wait(0.1)
	_unfreeze(g)


## 02.2-14: the HUD screenshot set (UI-SPEC 15): streak 0 / 25 / 100, hull 100 / 40 / critical
## and a section change, on an Autoplay dive of INVISIBLE (Expert, it has section events).
## Hull states are set on a frozen board (conductor paused) by injecting misses into HullScore,
## as sc_immersion does, so the run cannot fail mid-sequence.
func _visual_hud() -> void:
	var dir := ""
	for b in BundledSongs.SONGS:
		if str(b["id"]) == "invisible":
			dir = str(b["dir"])
	if not check("INVISIBLE is bundled for the HUD shots", dir != "", dir):
		return
	await goto(MENU)
	SongSelect.run_autoplay = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	await goto(SONG_SELECT)
	var g := await dive_from_song_select(dir, "expert")
	if g == null or not await wait_for_began(g):
		check("HUD dive began", false)
		return
	var first := INF
	for n in g.chart.notes:
		first = minf(first, float(n["time"]))
	await frame()
	await frame()
	# Streak 0, before the first note.
	check("accuracy shows --.-% before the first note",
		g.hud.accuracy_label.text == "--.-%" and g.conductor.song_time() < first,
		{"text": g.hud.accuracy_label.text, "t": snappedf(g.conductor.song_time(), 0.01), "first": first})
	var box0 := g.hud.depth_box()
	var acc0 := g.hud.accuracy_label.get_global_rect()
	await shot("hud_streak_0", g)
	# Streak 25 (the milestone popup is up).
	var gw: WeakRef = weakref(g)
	var got: bool = await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.score.combo >= 25, 60.0)
	if not check("autoplay reached streak 25", got and not _gone_or_stopped(gw), g.score.combo if is_instance_valid(g) else -1):
		return
	await wait(0.15)
	await shot("hud_streak_25", g)
	# Streak 100 (x4, MAX chip, SONAR_PALE + glow numeral) with hull 100.
	got = await wait_until(func() -> bool: return _gone_or_stopped(gw) or g.score.combo >= 100, 120.0)
	if _gone_or_stopped(gw):
		check("HUD dive still running at streak 100", false)
		return
	if not got:
		note("streak 100 not reached by autoplay in 120 s; showing the counters through the HUD bind path")
		g.score.combo = 100
		g.score.combo_changed.emit(100)
	check("autoplay reached streak 100", g.score.combo >= 100, g.score.combo)
	await wait(0.8)  # past the milestone pop
	await shot("hud_streak_100", g)
	await shot("hud_hull_100", g)
	check("depth value box did not move",
		g.score.depth() > 0.0 and g.hud.depth_box() == box0 and g.hud.accuracy_label.get_global_rect().position == acc0.position,
		{"box0": box0, "box": g.hud.depth_box(), "depth": g.score.depth()})
	# Section change: the next section that the banner announces.
	var song_len := ProgressTrack.song_length_of(g.chart)
	var now := g.conductor.song_time()
	var sec_t := -1.0
	var sec_name := ""
	for s in g.chart.sections:
		var st := float(s["time"])
		if st > now + 0.6 and SectionBanner.should_show(st, song_len):
			sec_t = st
			sec_name = str(s["name"])
			break
	if not check("a later section exists for the banner shot", sec_t > 0.0, {"now": now, "sections": g.chart.sections.size()}):
		return
	await _wait_song_time(g, sec_t + 0.3, sec_t - now + 20.0)
	if _gone_or_stopped(gw):
		check("HUD dive still running at the section change", false)
		return
	var b: SectionBanner = g.hud.section_banner
	var alpha_at := b.modulate.a
	var dt := g.conductor.song_time() - sec_t
	await shot("hud_section_change", g)
	check("section banner visible at a section change",
		b.visible and alpha_at > 0.9 and dt <= 0.4 and b.shown_text() == SectionBanner.display_name(sec_name),
		{"alpha": snappedf(alpha_at, 0.01), "dt": snappedf(dt, 0.01), "text": b.shown_text(), "want": sec_name,
			"track_section": g.hud.progress_track.section_label.text})
	var track_text := g.hud.progress_track.section_label.text
	check("progress track names the current section",
		track_text != "" and sec_name.to_upper().begins_with(track_text.trim_suffix("...")), track_text)
	# Hull 40 and critical, on a frozen board.
	g.conductor.pause()
	g.lane_input.enabled = false
	g._autoplay_player = null
	var n := 0
	while g.score.hull > 40.0 and n < 20:
		g.score.on_judged(0, -1, InputJudge.Judgment.MISS, 0.0)
		n += 1
	await wait(0.6)  # past the damage flash + shrink
	check("hull at about 40% for the hull shot", g.score.hull <= 40.0 and g.score.hull > 30.0, g.score.hull)
	await shot("hud_hull_40", g)
	n = 0
	while not g.hud.is_critical() and n < 20:
		g.score.on_judged(0, -1, InputJudge.Judgment.MISS, 0.0)
		n += 1
	await wait(0.6)
	await shot("hud_hull_critical", g)
	check("HULL CRITICAL caption shown at <= 30",
		g.score.hull <= 30.0 and g.hud.hull_caption.visible and g.hud.hull_caption.text == "HULL CRITICAL",
		{"hull": g.score.hull, "caption": g.hud.hull_caption.text})


func grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## True for a pixel that reads as a bio-colony dot: hue within cos 0.995 of SONAR or BIO_VIOLET
## and bright enough (max channel >= 0.3). The VP glow (cos 0.976 to SONAR, max 0.32) and the
## translucent wall rings over it stay below this.
func _colony_coloured(c: Color) -> bool:
	if _chan_max(c) < 0.3:
		return false
	var v := Vector3(c.r, c.g, c.b)
	if v.length() < 0.001:
		return false
	for ref in [Palette.SONAR, Palette.BIO_VIOLET]:
		var rv := Vector3(ref.r, ref.g, ref.b)
		if v.normalized().dot(rv.normalized()) >= 0.995:
			return true
	return false


## Sum of the brightest channel around 4 visible colony centres in the frame drawn right now,
## once `cond` holds (positions read from the arena after frame_post_draw, so they match the image).
## Colonies are taken from the HUD-free centre band (x 420..1500, y 290..640, UI-SPEC 7.1).
func _colony_luma(g: Gameplay, cond: Callable, label: String) -> Dictionary:
	var a := g.arena
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline and is_instance_valid(g):
		await get_tree().process_frame
		if not cond.call():
			continue
		var img: Image
		if label != "":
			await shot(label, g)
			img = last_img
		else:
			img = await grab()
		if not cond.call():
			continue  # the frame drawn is past the beat window; try the next beat
		var picks: Array = []
		for c in Arena.COLONIES_FULL:
			var vis: float = a._colony_vis[c]
			var ctr: Vector2 = a._colony_center[c]
			if vis >= 0.6 and ctr.x >= 420.0 and ctr.x <= 1500.0 and ctr.y >= 290.0 and ctr.y <= 640.0:
				picks.append(c)
		if picks.size() < 4:
			continue
		var total := 0.0
		var vals: Array = []
		for i in 4:
			var v := _region_max(img, a._colony_center[picks[i]], 3.0, 1.0)
			vals.append(snappedf(v, 0.001))
			total += v
		return {"n": 4, "sum": snappedf(total, 0.001), "vals": vals, "pulse": snappedf(a.beat_pulse(), 0.01)}
	return {"n": 0, "sum": 0.0}


## 02.2-11: the living trench. A shot at a beat peak (colonies bright), the colony brightness check
## on vs off the beat, and two forced creature crossings (leviathan, jellyfish) for the visual review.
func _visual_trench(g: Gameplay) -> void:
	var a := g.arena
	var on := await _colony_luma(g, func() -> bool: return is_instance_valid(g) and a.beat_pulse() > 0.8,
		"gameplay_trench_beat")
	var off := await _colony_luma(g, func() -> bool: return is_instance_valid(g) and a.beat_pulse() < 0.2, "")
	check("bio colonies brighter on the beat than off it",
		int(on["n"]) == 4 and int(off["n"]) == 4 and float(on["sum"]) > float(off["sum"]) * 1.2, {"on": on, "off": off})
	if not is_instance_valid(g):
		return
	var sched := a.creature_schedule()
	if sched.is_empty():
		check("creature schedule exists", false)
		return
	var e: Dictionary = sched[0]
	var saved := e.duplicate()
	for kind in [Arena.LEVIATHAN, Arena.JELLYFISH]:
		if not is_instance_valid(g):
			return
		# Forced for the shot: put the first crossing at x ~ 640 (dir +1) right now.
		e["kind"] = kind
		e["dir"] = 1.0
		var sz := Vector2(420.0, 120.0) if kind == Arena.LEVIATHAN else Vector2(90.0, 140.0)
		e["start"] = g.conductor.song_time() - (640.0 + sz.x * 0.5 + 40.0) / float(e["speed"])
		await wait(0.15)
		await shot("gameplay_trench_creature_%s" % ("leviathan" if kind == Arena.LEVIATHAN else "jellyfish"), g)
		var r := a.creature_rect(g.conductor.song_time())
		check("distant creature (%s, forced) visible and above the note path" % ("leviathan" if kind == Arena.LEVIATHAN else "jellyfish"),
			a.creature_active() and r.position.y >= 120.0 and r.end.y <= 340.0, {"rect": r})
	for k in saved:
		e[k] = saved[k]


# ------------------------------------------------------------------------------------------------
# autoplay5 (02.2-11, W2; all 5 bundled songs since 02.2-24): every bundled song on Expert with Full
# effects and the real board/FX, autoplay to the results. The visuals must not disturb judgment:
# 0 Good / 0 Miss on each song.
# ------------------------------------------------------------------------------------------------
func sc_autoplay5() -> void:
	isolate_settings(true)
	await wait_library_idle(60.0)
	Settings.low_effects = false
	Settings.reduce_motion = false
	Settings.settings_changed.emit()
	var per_song := {}
	for b in BundledSongs.SONGS:
		var res := await _autoplay5_song(str(b["id"]), str(b["dir"]))
		per_song[str(b["id"])] = res
	metrics["per_song"] = per_song
	await goto(MENU)


## One full Expert autoplay dive at Full effects; returns {title, perfect, good, miss, notes}.
func _autoplay5_song(id: String, dir: String) -> Dictionary:
	await goto(MENU)
	SongSelect.run_autoplay = true
	Gameplay.pending_intro = IntroTimeline.Mode.NONE
	await goto(SONG_SELECT)
	var g := await dive_from_song_select(dir, "expert")
	var label := id
	if g == null or not await wait_for_began(g):
		check("%s Expert autoplay at Full effects: 0 Good / 0 Miss" % label, false, "dive did not begin")
		return {"title": label, "began": false}
	if g.chart.title != "":
		label = g.chart.title
	var counts: Dictionary = g.arena.effect_counts()
	check("%s: Full effects on the live board (arena 36 colonies, creature on; FX Full)" % label,
		int(counts["colonies"]) == 36 and bool(counts["creature"]) and not Settings.low_effects
		and int(g.fx_layer.effect_counts()["perfect_amount"]) == 24, {"arena": counts})
	var length := 0.0
	for n in g.chart.notes:
		length = maxf(length, float(n["time"]) + float(n["duration"]))
	note("%s Expert: %d notes, last note end %.1f s" % [label, g.chart.notes.size(), length])
	await wait_until(func() -> bool: return not is_instance_valid(g) or g.conductor.song_time() > minf(40.0, length * 0.3),
		60.0)
	if is_instance_valid(g):
		await shot("autoplay5_%s_midsong" % id, g)
	var done: bool = await wait_until(func() -> bool:
		return not is_instance_valid(g) or g.state == Gameplay.State.DONE, length + 60.0)
	if not is_instance_valid(g):
		check("%s Expert autoplay at Full effects: 0 Good / 0 Miss" % label, false, "gameplay freed")
		return {"title": label, "began": true, "done": false}
	await wait(0.8)
	await shot("autoplay5_%s_results" % id, g)
	var sc := g.score
	var res := {"title": label, "perfect": sc.perfect_count, "good": sc.good_count, "miss": sc.miss_count,
		"notes": g.chart.notes.size(), "length_s": snappedf(length, 0.1)}
	check("%s Expert autoplay at Full effects: 0 Good / 0 Miss" % label,
		done and g.state == Gameplay.State.DONE and sc.good_count == 0 and sc.miss_count == 0 and sc.perfect_count > 0,
		"P%d G%d M%d of %d" % [sc.perfect_count, sc.good_count, sc.miss_count, g.chart.notes.size()])
	return res


## 02.2-10: hit bursts and the judgment popup. Shot ~40 ms after a PERFECT; "burst visible"
## counts bright pixels beside the receptor between y 895 and 922 (ring + particles, away from
## the popup at y 846 and the neighbouring receptors); an upcoming gem above the clip line
## must keep its lane colour. Then autoplay stops so the next note is missed for the crack shot.
func _visual_bursts(g: Gameplay) -> void:
	var got := {"lane": -1, "ms": 0, "miss_lane": -1, "miss_ms": 0}
	var cb := func(lane: int, _idx: int, j: int, _err: float) -> void:
		if j == InputJudge.Judgment.PERFECT and int(got["lane"]) < 0:
			got["lane"] = lane
			got["ms"] = Time.get_ticks_msec()
		elif j == InputJudge.Judgment.MISS and int(got["miss_lane"]) < 0:
			got["miss_lane"] = lane
			got["miss_ms"] = Time.get_ticks_msec()
	g.judge.judged.connect(cb)
	var seen: bool = await wait_until(func() -> bool:
		return not is_instance_valid(g) or int(got["lane"]) >= 0, 10.0)
	if not is_instance_valid(g) or not check("perfect judged for the burst shot", seen):
		return
	var t0 := int(got["ms"])
	await _wait_elapsed(t0, 0.04)
	await shot("gameplay_burst_perfect", g)
	var img := last_img
	var hit := Trench.hit_point(int(got["lane"]))
	var bright := 0
	var dx := 48.0
	while dx <= 110.0:
		var y := 895.0
		while y <= 922.0:
			for sx in [-1.0, 1.0]:
				if _chan_max(_img_px(img, Vector2(hit.x + sx * dx, y))) >= 0.55:
					bright += 1
			y += 3.0
		dx += 3.0
	check("perfect burst visible near the hit point", bright >= 10, {"bright": bright, "lane": got["lane"]})
	var gem := {}
	for v in _visible_pending(g):
		var vy := float(v["y"])
		if vy >= 450.0 and vy <= 830.0 and (gem.is_empty() or vy > float(gem["y"])):
			gem = v
	if gem.is_empty():
		note("no upcoming gem between y 450 and 830 in the burst shot")
		check("upcoming gem above the burst stays full lane colour", true, "no gem in range")
	else:
		var c := _colour_near(img, gem["center"], Palette.lane_color(int(gem["lane"])), 6.0)
		check("upcoming gem above the burst stays full lane colour", bool(c["ok"]),
			{"lane": gem["lane"], "y": snappedf(float(gem["y"]), 0.1), "cos": snappedf(float(c["cos"]), 0.001)})
	# Popup readability: bright text at (popup x, 846) at 0.1 s and 0.35 s after the judgment.
	var lumas: Array = []
	for at in [0.10, 0.35]:
		await _wait_elapsed(t0, at)
		if not is_instance_valid(g):
			return
		var im: Image
		if at < 0.2:
			await shot("gameplay_burst_spread", g)  # particles past the flash, for the visual review
			im = last_img
		else:
			im = await grab()
		var px := hit.x
		if g.feedback.floating_count() > 0:
			px = float(g.feedback.popup(0)["x"])
			for i in range(g.feedback.floating_count()):
				var pp: Dictionary = g.feedback.popup(i)
				if int(pp["born"]) / 1000 <= t0 + 5:
					px = float(pp["x"])
		lumas.append(snappedf(_region_max(im, Vector2(px, Feedback.POP_Y), 16.0), 0.001))
	check("judgment popup readable", float(lumas[0]) >= 0.6 and float(lumas[1]) >= 0.6, {"max_chan": lumas})
	# Miss: stop autoplay; the next note passes the window.
	g._autoplay_player = null
	g.lane_input.enabled = false
	var missed: bool = await wait_until(func() -> bool:
		return not is_instance_valid(g) or int(got["miss_lane"]) >= 0, 10.0)
	if not is_instance_valid(g) or not check("miss judged for the crack shot", missed):
		return
	await _wait_elapsed(int(got["miss_ms"]), 0.04)
	await shot("gameplay_miss", g)
	var mh := Trench.hit_point(int(got["miss_lane"]))
	var red := 0
	var yy := 875.0
	while yy <= 990.0:
		var xx := -62.0
		while xx <= 62.0:
			var c2 := _img_px(last_img, Vector2(mh.x + xx, yy))
			if c2.r >= 0.6 and c2.g <= 0.45 and c2.b <= 0.4:
				red += 1
			xx += 2.0
		yy += 2.0
	check("red crack near hit point", red >= 8, {"red_px": red, "lane": got["miss_lane"]})


## 02.2-09: x1 and x4 board shots. "x4 rails brighter than x1" samples both outer rails at
## d 0.3; "beat line present" looks for the faint horizontal line at a beat that
## Highway.visible_beat_lines reports in view, in a lane column with no note there.
func _visual_board_tiers(g: Gameplay) -> void:
	var first := INF
	for n in g.chart.notes:
		first = minf(first, float(n["time"]))
	# x1: notes approaching, no combo yet.
	await _wait_song_time(g, first - 0.5, 20.0)
	if not is_instance_valid(g):
		return
	check("x1 shot taken at multiplier 1", g.score.multiplier() == 1 and g.highway.tier == 1,
		{"mult": g.score.multiplier(), "tier": g.highway.tier})
	await shot("gameplay_x1", g)
	var img1 := last_img
	var rail1 := _rail_luma(img1)
	var beat := _beat_line_contrast(g, img1)
	check("beat line present", float(beat.get("diff", 0.0)) >= 0.015, beat)
	# x4: autoplay drives the combo to 30+.
	var got4: bool = await wait_until(func() -> bool:
		return not is_instance_valid(g) or g.score.multiplier() >= 4, 90.0)
	if not is_instance_valid(g):
		return
	await wait(0.5)  # past the 200 ms entry flash
	if not check("multiplier reached x4", got4 and g.score.multiplier() == 4 and g.highway.tier == 4,
			{"mult": g.score.multiplier(), "tier": g.highway.tier, "combo": g.score.combo}):
		return
	await shot("gameplay_x4", g)
	var rail4 := _rail_luma(last_img)
	check("x4 rails brighter than x1", rail4 > rail1 + 0.02, {"x1": snappedf(rail1, 0.001), "x4": snappedf(rail4, 0.001)})
	var beat4 := _beat_line_contrast(g, last_img)
	note("x4 beat line contrast %s" % str(beat4))


## Mean luma of 5x5 patches on both outer rails at d 0.3.
func _rail_luma(img: Image) -> float:
	var l := _luma(_patch(img, Trench.point(-2.0, 0.3), 2))
	var r := _luma(_patch(img, Trench.point(2.0, 0.3), 2))
	return 0.5 * (l + r)


## True when `lane` has no unhit note head or sustain body within +/- 0.08 of depth d.
func _lane_free_at(g: Gameplay, lane: int, d: float, vt: float, approach: float) -> bool:
	var notes: Array = g.chart.notes
	for i in range(notes.size()):
		var n: Dictionary = notes[i]
		if int(n["lane"]) != lane or g.highway._state[i] == Highway.S_HIT:
			continue
		var d0 := Trench.depth_for(float(n["time"]), vt, approach)
		var d1 := Trench.depth_for(float(n["time"]) + float(n["duration"]), vt, approach)
		if d1 >= d - 0.08 and d0 <= d + 0.08:
			return false
	return true


## Best beat/bar line contrast in the frame just shot: luma at the line (max over +/- 3 px)
## minus the mean luma 10 px above and below, in a free lane column, for lines at y 450..900.
func _beat_line_contrast(g: Gameplay, img: Image) -> Dictionary:
	var hw := g.highway
	var vt: float = hw._vt
	var approach: float = hw._approach
	var best := {"diff": 0.0, "lines": 0}
	var lines := hw.visible_beat_lines(vt, approach)
	best["lines"] = lines.size()
	for l in lines:
		var d := float(l["d"])
		var y := Trench.point(0.0, d).y
		if y < 450.0 or y > 900.0:
			continue
		for lane in range(4):
			if not _lane_free_at(g, lane, d, vt, approach):
				continue
			var x := Trench.point(Trench.lane_f(lane), d).x
			var peak := 0.0
			for dy in range(-3, 4):
				peak = maxf(peak, _luma(_img_px(img, Vector2(x, y + dy))))
			var bg := 0.5 * (_luma(_patch(img, Vector2(x, y - 10.0), 1)) + _luma(_patch(img, Vector2(x, y + 10.0), 1)))
			if peak - bg > float(best["diff"]):
				best = {"diff": snappedf(peak - bg, 0.0001), "y": snappedf(y, 0.1), "lane": lane,
					"bar": bool(l["bar"]), "lines": lines.size()}
	return best
