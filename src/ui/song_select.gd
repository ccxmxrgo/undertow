class_name SongSelect
extends Control
## Song Select (02-UI-SPEC): virtualised 9-row list, sonar detail panel, filter, sort, audio preview,
## scan status and footer. Everything is code-drawn on a few named pane Controls; the root handles
## input. Song strings are drawn as plain text (never BBCode) and truncated by measured width.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const AUDIO_ERR_USER := "This song's audio could not be loaded. Choose another song."
const AUDIO_ERR_BUNDLED := "Song audio could not be loaded. Reinstall the game files or choose another song."
const CREDITS := "Music: Pro Sensory (Alex McCulloch), CC0, via OpenGameArt.org"
const ONBOARD_TEXT := "Add your own songs. Open the Songs folder and drop Clone Hero song folders or .zip files in. The path is shown below."
const EMPTY_BODY := "Drop Clone Hero song folders or .zip files into the Songs folder, then press Rescan Library."
const NEEDS_HINT_ROW := "The extraction tool will chart this later"
const NEEDS_BODY := "This is audio only. The extraction tool will chart it in a later update."
const NO_RECORD := "No record yet. Finish a dive to set one."
const FOLDER_MSG_SEC := 6.0
const SCAN_STRIP_DELAY_MSEC := 300
const ROWS := 9
const ROW_PITCH := 80.0
const LIST_X := 64.0
const LIST_Y := 184.0
const LIST_W := 944.0
const PANEL_RECT := Rect2(1056.0, 120.0, 800.0, 784.0)
const START_RECT := Rect2(1080.0, 832.0, 752.0, 48.0)
const OPEN_RECT := Rect2(64.0, 928.0, 340.0, 48.0)
const RESCAN_RECT := Rect2(420.0, 928.0, 264.0, 48.0)
const SORT_RECT := Rect2(760.0, 64.0, 248.0, 48.0)
const PATH_RECT := Rect2(1056.0, 984.0, 800.0, 32.0)
const TILE_X: Array[float] = [1080.0, 1272.0, 1464.0, 1656.0]
const TILE_Y := 488.0

const C_PANEL := Color("0D1424")
const C_SEL := Color("123A52")
const C_BORDER := Color("1E8CB4")
const C_TEAL := Color("05D9E8")
const C_TEXT := Color("E8E6F0")
const C_CAP := Color("8A93AD")

## Run flags set by MainMenu; reset when Song Select exits (a dive copies them first).
static var run_autoplay: bool = false
static var run_practice: bool = false


## A Control that draws through a Callable in absolute screen coordinates.
class Pane extends Control:
	var painter: Callable

	func _draw() -> void:
		draw_set_transform(-position, 0.0, Vector2.ONE)
		if painter.is_valid():
			painter.call(self)


var navigate: Callable = Callable()
## Library node (autoload by default; tests inject their own instance).
var library: Node
## Callable(entry) -> AudioStream, run on a worker thread. Defaults to library.load_audio.
var preview_loader: Callable = Callable()

var _all: Array[SongEntry] = []
var _view: Array = []
var _sel_id: String = ""
var _wanted_diff: String = "expert"
var _diff: String = ""
var _offset: int = 0
var _scroll_vis: float = 0.0
var _filter: String = ""
var _typing: bool = false
var _sort: int = SongListModel.SortMode.TITLE
var _best_by_fp: Dictionary = {}
var _store: ScoreStore
var _user_moved: bool = false
var _restore_id: String = ""
var _hover_row: int = -1
var _hover_btn: String = ""
var _last_pad: bool = false
var _t: float = 0.0
var _ping_t: float = 99.0
var _diving: bool = false
var _fade: float = 0.0
var _message: String = ""
var _message_kind: String = ""
var _message_until_msec: int = 0
var _scan_started_msec: int = 0
var _scan_done: int = 0
var _scan_total: int = 0
var _scan_label: String = ""
var _scan_count: int = 0
var _scan_unplayable: int = 0
var _show_debug: bool = false
var _font: Font
var _bold: Font
var _fit_cache: Dictionary = {}
var _last_click_msec: int = 0
var _last_click_row: int = -1

var _hold_dir: int = 0
var _hold_t: float = 0.0
var _hold_next: float = 0.4
var _stick_dir: int = 0

# preview
var _preview_player: AudioStreamPlayer
var _preview_state: String = "none"
var _preview_change_msec: int = 0
var _preview_request: int = 0
var _preview_entry_id: String = ""
var _preview_tween: Tween
var _stream_cache: Array = []

var _arena: Arena
var _panes: Array[Pane] = []
var _p_header: Pane
var _p_filter: Pane
var _p_sort: Pane
var _p_list: Pane
var _p_detail: Pane
var _p_scan: Pane
var _p_footer: Pane
var _p_credits: Pane
var _p_fade: Pane


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	if library == null:
		library = get_node_or_null("/root/SongLibrary")
	_make_fonts()
	_arena = Arena.new()
	_arena.menu_mode = true
	_arena.name = "Arena"
	add_child(_arena)
	_p_header = _pane("Header", Rect2(64, 64, 700, 48), _paint_header)
	_p_filter = _pane("FilterField", Rect2(64, 120, 944, 48), _paint_filter)
	_p_sort = _pane("SortChip", SORT_RECT, _paint_sort)
	_p_list = _pane("SongList", Rect2(LIST_X, LIST_Y, 976, 720), _paint_list)
	_p_list.clip_contents = true
	_p_detail = _pane("DetailPanel", PANEL_RECT, _paint_detail)
	_p_detail.clip_contents = true
	_p_footer = _pane("FooterHints", Rect2(64, 928, 1792, 104), _paint_footer)
	_p_scan = _pane("ScanStatus", Rect2(704, 928, 480, 48), _paint_scan)
	_p_credits = _pane("CreditsLine", Rect2(1184, 928, 672, 48), _paint_credits)
	_p_fade = _pane("DiveFade", Rect2(0, 0, 1920, 1080), _paint_fade)
	_store = ScoreStore.new()
	_store.load()
	if library != null:
		if library.last_difficulty != "":
			_wanted_diff = library.last_difficulty
		_all.assign(library.entries)
		_refresh_bests(_all)
		_scan_count = maxi(0, _all.size() - 1)
		library.scan_started.connect(_on_scan_started)
		library.entries_added.connect(_on_entries_added)
		library.progress.connect(_on_progress)
		library.scan_finished.connect(_on_scan_finished)
		if library.scanning:
			_scan_started_msec = Time.get_ticks_msec()
	_rebuild(false)
	_initial_selection()
	_preview_player = AudioStreamPlayer.new()
	_preview_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(_preview_player)
	set_process(true)
	grab_focus()


func _exit_tree() -> void:
	_stop_preview(false)
	if library != null:
		for pair in [[library.scan_started, _on_scan_started], [library.entries_added, _on_entries_added],
				[library.progress, _on_progress], [library.scan_finished, _on_scan_finished]]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
	run_autoplay = false
	run_practice = false


func _pane(pane_name: String, r: Rect2, painter: Callable) -> Pane:
	var p := Pane.new()
	p.name = pane_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = r.position
	p.size = r.size
	p.painter = painter
	add_child(p)
	_panes.append(p)
	return p


func _make_fonts() -> void:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial", "sans-serif"])
	var reg := FontVariation.new()
	reg.base_font = Palette.font()
	var fb: Array[Font] = [sys]
	reg.fallbacks = fb
	_font = reg
	var b := FontVariation.new()
	b.base_font = Palette.font()
	b.variation_embolden = 0.5
	b.fallbacks = fb
	_bold = b


# ---- data ----

func _refresh_bests(batch: Array) -> void:
	if _store == null:
		return
	for item in batch:
		var e: SongEntry = item
		for d in e.difficulties:
			var fp: String = d["fingerprint"]
			var b := _store.best(fp)
			if not b.is_empty():
				_best_by_fp[fp] = b


func _on_scan_started() -> void:
	_restore_id = _sel_id
	_all.clear()
	_scan_started_msec = Time.get_ticks_msec()
	_scan_done = 0
	_scan_total = 0
	_scan_label = ""


func _on_entries_added(batch: Array) -> void:
	for item in batch:
		_all.append(item)
	_refresh_bests(batch)
	_rebuild(true)
	var want := _restore_id
	var center := false
	if want == "" and not _user_moved and library != null:
		want = library.last_song_id
		center = true
	if want != "":
		for item in batch:
			if (item as SongEntry).id == want:
				_restore_id = ""
				_select_id(want, center)
				break


func _on_progress(done: int, total: int, label: String) -> void:
	_scan_done = done
	_scan_total = total
	_scan_label = label


func _on_scan_finished(count: int, unplayable: int) -> void:
	_scan_count = count
	_scan_unplayable = unplayable


func _has_imported() -> bool:
	for e in _all:
		if e.source == "songs" or e.source == "library":
			return true
	return false


## Rebuild the filtered/sorted view. `stable` keeps the selected row at the same screen y.
func _rebuild(stable: bool) -> void:
	var old_ids := _view_ids()
	var shown: Array = SongListModel.filter(_all, _filter)
	var ordered: Array = SongListModel.order(shown, _sort, _best_by_fp)
	if _filter == "" and not _has_imported() and not ordered.is_empty():
		var at := 0
		for i in ordered.size():
			if (ordered[i] as SongEntry).status == "ok":
				at = i + 1
		ordered.insert(at, null)
	_view = ordered
	var new_ids := _view_ids()
	if _sel_id != "" and new_ids.has(_sel_id):
		if stable:
			_offset = SongListModel.insert_stable(old_ids, new_ids, _sel_id, _offset)
		else:
			_offset = SongListModel.scroll_for_selection(new_ids.find(_sel_id), _offset, _view.size())
	else:
		_pick_first_selectable()
	_offset = clampi(_offset, 0, maxi(0, _view.size() - ROWS))
	_scroll_vis = float(_offset)
	_ensure_diff()


func _view_ids() -> Array:
	var out: Array = []
	for e in _view:
		if e != null:
			out.append((e as SongEntry).id)
	return out


func _pick_first_selectable() -> void:
	var prev := _sel_id
	_sel_id = ""
	for e in _view:
		if e != null:
			_sel_id = (e as SongEntry).id
			break
	if _sel_id != prev:
		_offset = 0
		_selection_changed()


func _initial_selection() -> void:
	var want: String = library.last_song_id if library != null else ""
	if want != "" and _view_ids().has(want):
		_select_id(want, true)
		return
	for e in _view:
		if e != null and (e as SongEntry).status == "ok" and (e as SongEntry).source != "test":
			_select_id((e as SongEntry).id, false)
			return
	for e in _view:
		if e != null and (e as SongEntry).status == "ok":
			_select_id((e as SongEntry).id, false)
			return
	_pick_first_selectable()


func _selected() -> SongEntry:
	for e in _view:
		if e != null and (e as SongEntry).id == _sel_id:
			return e
	return null


func _sel_index() -> int:
	for i in _view.size():
		if _view[i] != null and (_view[i] as SongEntry).id == _sel_id:
			return i
	return -1


func _available(e: SongEntry) -> Array:
	var out: Array = []
	if e != null and e.status == "ok":
		for d in e.difficulties:
			out.append(d["name"])
	return out


func _ensure_diff() -> void:
	_diff = SongListModel.snap_difficulty(_available(_selected()), _wanted_diff)


func _select_id(id: String, center: bool) -> void:
	var idx := _view_ids().find(id)
	if idx < 0:
		return
	var changed := _sel_id != id
	_sel_id = id
	var vi := _sel_index()
	if center:
		_offset = clampi(vi - ROWS / 2, 0, maxi(0, _view.size() - ROWS))
		_scroll_vis = float(_offset)
	else:
		_offset = SongListModel.scroll_for_selection(vi, _offset, _view.size())
	_ensure_diff()
	if changed:
		_selection_changed()


func _selection_changed() -> void:
	_ping_t = 0.0
	if _message_kind == "audio":
		_message = ""
		_message_kind = ""
	_ensure_diff()
	_stop_preview(true)
	_preview_change_msec = Time.get_ticks_msec()
	var e := _selected()
	var can_preview := e != null and e.status != "broken" 			and (not e.audio_files.is_empty() or preview_loader.is_valid())
	_preview_state = "pending" if can_preview else "none"


func _move(delta: int) -> void:
	if _view.is_empty():
		return
	_user_moved = true
	var cur := _sel_index()
	if cur < 0:
		_pick_first_selectable()
		return
	var step := 1 if delta > 0 else -1
	var target := clampi(cur + delta, 0, _view.size() - 1)
	if _view[target] == null:
		var t2 := target + step
		if t2 < 0 or t2 >= _view.size() or _view[t2] == null:
			t2 = target - step
		target = t2
	if target < 0 or target >= _view.size() or target == cur or _view[target] == null:
		return
	_select_id((_view[target] as SongEntry).id, false)


func _move_edge(top: bool) -> void:
	_user_moved = true
	var rng: Array = range(_view.size()) if top else range(_view.size() - 1, -1, -1)
	for i in rng:
		if _view[i] != null:
			_select_id((_view[i] as SongEntry).id, false)
			return


func _change_difficulty(dir: int) -> void:
	var e := _selected()
	var next := SongListModel.next_difficulty(_available(e), _diff, dir)
	if next != "" and next != _diff:
		_wanted_diff = next
		_diff = next
		_ping_t = 0.0


func _set_filter(text: String) -> void:
	var t := SongListModel.clamp_filter(text)
	if t == _filter:
		return
	_filter = t
	_user_moved = true
	_rebuild(false)
	_selection_changed()


func _cycle_sort() -> void:
	_sort = SongListModel.next_sort(_sort)
	_rebuild(false)


# ---- actions ----

func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		get_tree().change_scene_to_file(path)


func _back() -> void:
	_stop_preview(true)
	_go(MENU_SCENE)


func _open_folder() -> void:
	if library == null:
		return
	if library.open_songs_folder():
		return
	_message = "Could not open the Songs folder. It is at %s" % library.songs_dir()
	_message_kind = "folder"
	_message_until_msec = Time.get_ticks_msec() + int(FOLDER_MSG_SEC * 1000.0)


func _rescan() -> void:
	if library != null and not library.scanning:
		library.rescan()


func _start_enabled() -> bool:
	var e := _selected()
	return not _diving and e != null and e.status == "ok" and _diff != ""


func _dive() -> void:
	if _diving or not _start_enabled():
		return
	var e := _selected()
	var chart: ChartData = library.build_chart(e, _diff)
	if chart == null:
		_message = AUDIO_ERR_BUNDLED if (e.source == "bundled" or e.source == "test") else AUDIO_ERR_USER
		_message_kind = "audio"
		return
	_diving = true
	Gameplay.pending_chart = chart
	Gameplay.pending_autoplay = run_autoplay
	Gameplay.pending_practice = run_practice
	library.last_song_id = e.id
	library.last_difficulty = _diff
	_stop_preview(true)
	if Settings.reduce_motion or not is_inside_tree():
		_fade = 1.0
		_go(GAMEPLAY_SCENE)
		return
	var tw := create_tween()
	tw.tween_property(self, "_fade", 1.0, 0.15)
	tw.tween_callback(_go.bind(GAMEPLAY_SCENE))


# ---- input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_last_pad = false
		_handle_key(event)
	elif event is InputEventJoypadButton:
		_last_pad = true
		_handle_pad_button(event)
	elif event is InputEventJoypadMotion:
		_handle_stick(event)
	if event.is_action_pressed(&"debug_overlay") and not event.is_echo():
		_show_debug = not _show_debug


func _hold(dir: int) -> void:
	_hold_dir = dir
	_hold_t = 0.0
	_hold_next = 0.4


func _handle_key(ev: InputEventKey) -> void:
	var code: int = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if not ev.pressed:
		if (code == KEY_UP and _hold_dir < 0) or (code == KEY_DOWN and _hold_dir > 0):
			_hold_dir = 0
		return
	var ctrl: bool = ev.ctrl_pressed or ev.meta_pressed
	match code:
		KEY_UP:
			if not ev.echo:
				_move(-1)
				_hold(-1)
			return
		KEY_DOWN:
			if not ev.echo:
				_move(1)
				_hold(1)
			return
		KEY_PAGEUP:
			_move(-SongListModel.PAGE)
			return
		KEY_PAGEDOWN:
			_move(SongListModel.PAGE)
			return
		KEY_HOME:
			_move_edge(true)
			return
		KEY_END:
			_move_edge(false)
			return
		KEY_LEFT:
			_change_difficulty(-1)
			return
		KEY_RIGHT:
			_change_difficulty(1)
			return
		KEY_ENTER, KEY_KP_ENTER:
			if not ev.echo:
				_dive()
			return
		KEY_ESCAPE:
			if not ev.echo:
				if SongListModel.esc_action(_filter) == "clear_filter":
					_typing = false
					_set_filter("")
				else:
					_typing = false
					_back()
			return
		KEY_F2:
			if not ev.echo:
				_cycle_sort()
			return
		KEY_F5:
			if not ev.echo:
				_rescan()
			return
		KEY_F6:
			if not ev.echo:
				_open_folder()
			return
		KEY_BACKSPACE:
			if _filter != "":
				_set_filter(_filter.substr(0, _filter.length() - 1))
				_typing = SongListModel.typing_after_backspace(_filter)
			return
		KEY_SLASH:
			if not ctrl:
				_typing = true
				return
		KEY_F:
			if ctrl:
				_typing = true
				return
	if code >= KEY_1 and code <= KEY_4 and SongListModel.nav_digits_active(_filter, _typing) and not ctrl:
		_move(SongListModel.digit_delta(code))
		return
	if ctrl or ev.alt_pressed:
		return
	var u: int = ev.unicode
	if (u >= 33 and u != 127) or (u == 32 and _filter != ""):
		_typing = true
		_set_filter(_filter + String.chr(u))


func _handle_pad_button(ev: InputEventJoypadButton) -> void:
	var idx: int = ev.button_index
	if not ev.pressed:
		if (idx == JOY_BUTTON_DPAD_UP and _hold_dir < 0) or (idx == JOY_BUTTON_DPAD_DOWN and _hold_dir > 0):
			_hold_dir = 0
		return
	match idx:
		JOY_BUTTON_DPAD_UP:
			_move(-1)
			_hold(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move(1)
			_hold(1)
		JOY_BUTTON_DPAD_LEFT:
			_change_difficulty(-1)
		JOY_BUTTON_DPAD_RIGHT:
			_change_difficulty(1)
		JOY_BUTTON_LEFT_SHOULDER:
			_move(-SongListModel.PAGE)
		JOY_BUTTON_RIGHT_SHOULDER:
			_move(SongListModel.PAGE)
		JOY_BUTTON_A:
			_dive()
		JOY_BUTTON_B:
			if SongListModel.esc_action(_filter) == "clear_filter":
				_set_filter("")
			else:
				_back()
		JOY_BUTTON_Y:
			_cycle_sort()
		JOY_BUTTON_X:
			_rescan()
		JOY_BUTTON_BACK:
			_open_folder()


func _handle_stick(ev: InputEventJoypadMotion) -> void:
	if ev.axis != JOY_AXIS_LEFT_Y and ev.axis != JOY_AXIS_LEFT_X:
		return
	var dir := 0
	if absf(ev.axis_value) > 0.6:
		dir = 1 if ev.axis_value > 0.0 else -1
	_last_pad = true
	if ev.axis == JOY_AXIS_LEFT_Y:
		if dir != _stick_dir:
			_stick_dir = dir
			if dir != 0:
				_move(dir)
				_hold(dir)
			else:
				_hold_dir = 0
	elif dir != 0 and absf(ev.axis_value) > 0.9:
		_change_difficulty(dir)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		_hover_row = _row_at(m.position)
		_hover_btn = _button_at(m.position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(mb.position, mb.double_click)


func _click(p: Vector2, double: bool) -> void:
	var row := _row_at(p)
	if row >= 0:
		var e: Variant = _view[row]
		if e != null:
			_user_moved = true
			var same := (e as SongEntry).id == _sel_id
			_select_id((e as SongEntry).id, false)
			if double or (same and row == _last_click_row and Time.get_ticks_msec() - _last_click_msec < 400):
				_dive()
		_last_click_row = row
		_last_click_msec = Time.get_ticks_msec()
		return
	match _button_at(p):
		"open", "path":
			_open_folder()
		"rescan":
			_rescan()
		"sort":
			_cycle_sort()
		"start":
			_dive()
		_:
			for i in 4:
				if Rect2(TILE_X[i], TILE_Y, 176.0, 72.0).has_point(p):
					var nm: String = SongListModel.DIFFICULTY_ORDER[i]
					if _available(_selected()).has(nm):
						_wanted_diff = nm
						_diff = nm
						_ping_t = 0.0


func _row_at(p: Vector2) -> int:
	if p.x < LIST_X or p.x >= LIST_X + LIST_W or p.y < LIST_Y or p.y >= LIST_Y + ROWS * ROW_PITCH:
		return -1
	var yy := p.y - LIST_Y + _scroll_vis * ROW_PITCH
	if fposmod(yy, ROW_PITCH) >= 72.0:
		return -1
	var i := int(floor(yy / ROW_PITCH))
	return i if i >= 0 and i < _view.size() else -1


func _button_at(p: Vector2) -> String:
	if OPEN_RECT.has_point(p):
		return "open"
	if RESCAN_RECT.has_point(p):
		return "rescan"
	if SORT_RECT.has_point(p):
		return "sort"
	if START_RECT.has_point(p):
		return "start"
	if PATH_RECT.has_point(p):
		return "path"
	return ""


# ---- per frame ----

func _process(delta: float) -> void:
	_t += delta
	_ping_t += delta
	if Settings.reduce_motion:
		_scroll_vis = float(_offset)
	else:
		_scroll_vis += (float(_offset) - _scroll_vis) * (1.0 - exp(-delta / 0.04))
		if absf(float(_offset) - _scroll_vis) < 0.01:
			_scroll_vis = float(_offset)
	if _hold_dir != 0:
		_hold_t += delta
		while _hold_t >= _hold_next:
			_move(_hold_dir)
			_hold_next += 0.1 if _hold_t < 1.2 else 0.05
	if _message_kind == "folder" and Time.get_ticks_msec() > _message_until_msec:
		_message = ""
		_message_kind = ""
	tick_preview(Time.get_ticks_msec())
	for p in _panes:
		p.queue_redraw()


# ---- preview (D-10) ----

func _loader() -> Callable:
	if preview_loader.is_valid():
		return preview_loader
	return Callable(library, "load_audio")


## Public so tests can drive the clock.
func tick_preview(now_msec: int) -> void:
	if _preview_state != "pending":
		return
	if not SongListModel.preview_gate(_preview_change_msec, now_msec):
		return
	var e := _selected()
	if e == null or e.status == "broken" or Settings.volume_music <= 0.0 or library == null:
		_preview_state = "none"
		return
	_preview_entry_id = e.id
	for c in _stream_cache:
		if c["id"] == e.id:
			_play_stream(c["stream"], e)
			return
	_preview_state = "loading"
	_preview_request += 1
	var req := _preview_request
	var loader := _loader()
	WorkerThreadPool.add_task(func() -> void:
		var s: AudioStream = loader.call(e)
		_preview_loaded.call_deferred(req, e.id, s))


func _preview_loaded(req: int, id: String, stream: AudioStream) -> void:
	if not SongListModel.accept_result(req, _preview_request) or id != _sel_id or _preview_state != "loading":
		return
	if stream == null:
		_preview_state = "none"
		return
	_stream_cache.append({"id": id, "stream": stream})
	while _stream_cache.size() > 2:
		_stream_cache.pop_front()
	_play_stream(stream, _selected())


func _play_stream(stream: AudioStream, e: SongEntry) -> void:
	if _preview_player == null or not is_inside_tree():
		_preview_state = "none"
		return
	var len := stream.get_length()
	var start := SongListModel.preview_start_sec(e.preview_start_ms, len if len > 0.0 else e.length_sec)
	if len > 0.0:
		start = minf(start, maxf(0.0, len - 1.0))
	_preview_player.stream = stream
	_preview_player.volume_db = -40.0
	_preview_player.play(start)
	_preview_state = "playing"
	if _preview_tween != null:
		_preview_tween.kill()
	if Settings.reduce_motion:
		_preview_player.volume_db = 0.0
	else:
		_preview_tween = create_tween()
		_preview_tween.tween_property(_preview_player, "volume_db", 0.0, 0.4)


func _stop_preview(fade: bool) -> void:
	_preview_request += 1
	if _preview_tween != null:
		_preview_tween.kill()
		_preview_tween = null
	if _preview_player != null and not is_instance_valid(_preview_player):
		_preview_player = null
	if _preview_state == "playing" and _preview_player != null and _preview_player.playing:
		if fade and is_inside_tree() and not Settings.reduce_motion:
			_preview_tween = create_tween()
			_preview_tween.tween_property(_preview_player, "volume_db", -40.0, 0.25)
			_preview_tween.tween_callback(_preview_player.stop)
		else:
			_preview_player.stop()
	elif _preview_player != null:
		_preview_player.stop()
	_preview_state = "none"


# ---- test seam ----

func debug_state() -> Dictionary:
	var rows: Array = []
	for i in range(_offset, mini(_offset + ROWS, _view.size())):
		rows.append("" if _view[i] == null else (_view[i] as SongEntry).id)
	var empty := ""
	if _all.is_empty():
		empty = "no_songs"
	elif _view.is_empty():
		empty = "no_matches"
	return {
		"rows": rows, "view_size": _view.size(), "selected": _sel_id, "filter": _filter,
		"typing": _typing, "sort": _sort, "difficulty": _diff, "preview_state": _preview_state,
		"start_enabled": _start_enabled(), "message": _message, "empty_state": empty,
		"offset": _offset, "diving": _diving, "scan_text": _scan_text(),
		"onboarding": _view.has(null),
	}


func set_filter_for_test(text: String) -> void:
	_typing = text != ""
	_set_filter(text)


func select_for_test(id: String) -> void:
	_user_moved = true
	_select_id(id, false)


func press_key_for_test(keycode: int, unicode: int = 0, ctrl: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	ev.physical_keycode = keycode as Key
	ev.pressed = true
	ev.unicode = unicode
	ev.ctrl_pressed = ctrl
	_handle_key(ev)


func type_for_test(text: String) -> void:
	for i in text.length():
		var ch := text.unicode_at(i)
		var code: int = ch
		if ch >= 97 and ch <= 122:
			code = ch - 32
		press_key_for_test(code, ch)


func set_sort_for_test(mode: int) -> void:
	_sort = mode
	_rebuild(false)


func open_folder_for_test() -> void:
	_open_folder()


# ---- drawing ----

func _txt(c: CanvasItem, pos: Vector2, s: String, size: int, col: Color, bold: bool = false) -> void:
	c.draw_string(_bold if bold else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


func _txt_r(c: CanvasItem, right: float, y: float, s: String, size: int, col: Color, bold: bool = false) -> void:
	var f := _bold if bold else _font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	c.draw_string(f, Vector2(right - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


func _w(s: String, size: int, bold: bool = false) -> float:
	return (_bold if bold else _font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x


## Truncate by measured width with three ASCII dots (T-02-13).
func _fit(s: String, size: int, max_w: float, bold: bool = false) -> String:
	var key := "%s|%d|%d|%s" % [s, size, int(max_w), bold]
	if _fit_cache.has(key):
		return _fit_cache[key]
	var out := s
	if _w(s, size, bold) > max_w:
		var lo := 0
		var hi := s.length()
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if _w(s.substr(0, mid) + "...", size, bold) <= max_w:
				lo = mid
			else:
				hi = mid - 1
		out = s.substr(0, lo).strip_edges(false, true) + "..."
	if _fit_cache.size() > 600:
		_fit_cache.clear()
	_fit_cache[key] = out
	return out


func _box(c: CanvasItem, r: Rect2, fill: Color, border: Color, bw: float) -> void:
	if fill.a > 0.0:
		c.draw_rect(r, fill)
	if bw > 0.0 and border.a > 0.0:
		c.draw_rect(r.grow(-bw * 0.5), border, false, bw)


func _outline_badge(c: CanvasItem, x: float, base_y: float, label: String) -> float:
	var w := _w(label, Palette.SIZE_LABEL) + 16.0
	var r := Rect2(x, base_y - 24.0, w, 32.0)
	c.draw_rect(r.grow(-1.0), Palette.TEXT, false, 2.0)
	_txt(c, Vector2(x + 8.0, base_y - 2.0), label, Palette.SIZE_LABEL, Palette.TEXT)
	return w


func _paint_header(c: CanvasItem) -> void:
	_txt(c, Vector2(64, 104), "SELECT SONG", Palette.SIZE_HEADING, C_TEXT, true)
	var x := 384.0
	if run_practice:
		x += _outline_badge(c, x, 100.0, "PRACTICE DIVE") + 8.0
	if run_autoplay:
		_outline_badge(c, x, 100.0, "AUTOPLAY")


func _paint_sort(c: CanvasItem) -> void:
	var label := SongListModel.sort_label(_sort)
	var prefix := "SORT: "
	var value := label.trim_prefix(prefix)
	var total := _w(label, Palette.SIZE_LABEL)
	var x := 1008.0 - total
	_txt(c, Vector2(x, 100), prefix, Palette.SIZE_LABEL, C_CAP)
	_txt(c, Vector2(x + _w(prefix, Palette.SIZE_LABEL), 100), value, Palette.SIZE_LABEL, C_TEXT)


func _paint_filter(c: CanvasItem) -> void:
	var r := Rect2(64, 120, 944, 48)
	var active := _filter != ""
	_box(c, r, Color(C_PANEL, 0.6), Color(C_TEAL, 0.6) if active else Color(C_BORDER, 0.35), 2.0)
	if active:
		_txt(c, Vector2(80, 156), _filter, Palette.SIZE_BODY, C_TEXT)
		if Settings.reduce_motion or fmod(_t, 1.0) < 0.5:
			c.draw_rect(Rect2(80.0 + _w(_filter, Palette.SIZE_BODY), 128.0, 2.0, 28.0), C_TEXT)
		var shown := _view.size() - (1 if _view.has(null) else 0)
		_txt_r(c, 992, 152, "%d / %d" % [shown, _all.size()], Palette.SIZE_LABEL, C_CAP)
	else:
		_txt(c, Vector2(80, 156), "Type to search title or artist", Palette.SIZE_BODY, C_CAP)
		_txt_r(c, 992, 152, SongListModel.count_text(maxi(0, _all.size())), Palette.SIZE_LABEL, C_CAP)


func _paint_credits(c: CanvasItem) -> void:
	_txt_r(c, 1856, 960, CREDITS, Palette.SIZE_LABEL, C_CAP)


func _paint_fade(c: CanvasItem) -> void:
	if _fade > 0.0:
		c.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, clampf(_fade, 0.0, 1.0)))


# -- list --

func _paint_list(c: CanvasItem) -> void:
	if _all.is_empty():
		_paint_empty(c, "NO SONGS FOUND", EMPTY_BODY, true)
		return
	if _view.is_empty():
		_paint_empty(c, "NO MATCHES", "No song matches \"%s\". Press Esc to clear it." % _filter, false)
		return
	var first := int(floor(_scroll_vis))
	for i in range(maxi(0, first), mini(_view.size(), first + ROWS + 2)):
		var y := LIST_Y + (float(i) - _scroll_vis) * ROW_PITCH
		if y > LIST_Y + 720.0 or y + 72.0 < LIST_Y:
			continue
		if _view[i] == null:
			_paint_info_row(c, y)
		else:
			_paint_row(c, _view[i], y, i)
	if _view.size() > ROWS:
		var track := Rect2(1024, LIST_Y, 4, 720)
		c.draw_rect(track, Color(0.91, 0.9, 0.94, 0.25))
		var th := maxf(24.0, 720.0 * float(ROWS) / float(_view.size()))
		var ty := LIST_Y + (720.0 - th) * (_scroll_vis / float(_view.size() - ROWS))
		c.draw_rect(Rect2(1024, ty, 4, th), C_TEAL)


func _paint_empty(c: CanvasItem, title: String, body: String, show_path: bool) -> void:
	var cx := LIST_X + LIST_W * 0.5
	var tw := _w(title, Palette.SIZE_HEADING, true)
	_txt(c, Vector2(cx - tw * 0.5, 480), title, Palette.SIZE_HEADING, C_TEXT, true)
	var lines := _wrap(body, Palette.SIZE_BODY, 800.0)
	var y := 540.0
	for ln in lines.slice(0, 3):
		var lw := _w(ln, Palette.SIZE_BODY)
		_txt(c, Vector2(cx - lw * 0.5, y), ln, Palette.SIZE_BODY, C_CAP)
		y += 40.0
	if show_path and library != null:
		var cap := "Your Songs folder is:"
		_txt(c, Vector2(cx - _w(cap, Palette.SIZE_LABEL) * 0.5, 620), cap, Palette.SIZE_LABEL, C_CAP)
		var py := 660.0
		for ln in _wrap(library.songs_dir(), Palette.SIZE_BODY, 800.0).slice(0, 3):
			_txt(c, Vector2(cx - _w(ln, Palette.SIZE_BODY) * 0.5, py), ln, Palette.SIZE_BODY, C_TEXT)
			py += 36.0


## Greedy word wrap by measured width; over-long words are split by character.
func _wrap(s: String, size: int, max_w: float) -> Array:
	var lines: Array = []
	var cur := ""
	for word in s.split(" ", false):
		var trial := word if cur == "" else cur + " " + word
		if _w(trial, size) <= max_w:
			cur = trial
			continue
		if cur != "":
			lines.append(cur)
			cur = ""
		var rest: String = word
		while _w(rest, size) > max_w and rest.length() > 1:
			var n := rest.length()
			while n > 1 and _w(rest.substr(0, n), size) > max_w:
				n -= 1
			lines.append(rest.substr(0, n))
			rest = rest.substr(n)
		cur = rest
	if cur != "":
		lines.append(cur)
	return lines


func _paint_info_row(c: CanvasItem, y: float) -> void:
	var r := Rect2(LIST_X, y, LIST_W, 72.0)
	var col := Color(0.54, 0.58, 0.68, 0.35)
	var x := r.position.x
	while x < r.end.x:
		var x2 := minf(x + 12.0, r.end.x)
		c.draw_line(Vector2(x, r.position.y + 1), Vector2(x2, r.position.y + 1), col, 2.0)
		c.draw_line(Vector2(x, r.end.y - 1), Vector2(x2, r.end.y - 1), col, 2.0)
		x += 20.0
	var lines := _wrap(ONBOARD_TEXT, Palette.SIZE_LABEL, LIST_W - 48.0)
	var ly := y + 28.0
	for ln in lines.slice(0, 2):
		_txt(c, Vector2(LIST_X + 24.0, ly), _fit(ln, Palette.SIZE_LABEL, LIST_W - 48.0), Palette.SIZE_LABEL, C_CAP)
		ly += 28.0


func _paint_row(c: CanvasItem, e: SongEntry, y: float, index: int) -> void:
	var sel := e.id == _sel_id
	var broken := e.status == "broken"
	var needs := e.status == "needs_chart"
	var r := Rect2(LIST_X, y, LIST_W, 72.0)
	if sel:
		_box(c, r, Color(C_SEL, 0.7), Palette.ACCENT, 4.0)
		var cy := y + 36.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(80, cy - 8), Vector2(96, cy), Vector2(80, cy + 8)]),
				Palette.ACCENT)
	else:
		var hov := index == _hover_row
		_box(c, r, Color(C_PANEL, 0.6), Color(C_TEAL, 0.6) if hov else Color(C_BORDER, 0.35), 2.0)
	var is_cal := e.source == "test"
	var title_col := C_CAP if broken else (Color(C_TEXT, 0.7) if needs else C_TEXT)
	var badge := "TEST" if is_cal else ("NEEDS A CHART" if needs else "")
	var title_max := 776.0 - (_w(badge, Palette.SIZE_LABEL) + 24.0 if badge != "" else 0.0)
	var title := e.title if e.title != "" else "Untitled"
	var shown_title := _fit(title, Palette.SIZE_BODY, title_max, sel)
	_txt(c, Vector2(112, y + 32), shown_title, Palette.SIZE_BODY, title_col, sel)
	if badge != "":
		_outline_badge(c, 112.0 + _w(shown_title, Palette.SIZE_BODY, sel) + 8.0, y + 30.0, badge)
	# second line
	if broken:
		_txt(c, Vector2(112, y + 60), "!", Palette.SIZE_LABEL, Palette.DESTRUCTIVE, true)
		_txt(c, Vector2(128, y + 60), _fit(e.error, Palette.SIZE_LABEL, 740.0), Palette.SIZE_LABEL, C_CAP)
	else:
		var second := e.artist if e.artist != "" else "Unknown artist"
		if needs:
			second = NEEDS_HINT_ROW
		_txt(c, Vector2(112, y + 60), _fit(second, Palette.SIZE_LABEL, 700.0), Palette.SIZE_LABEL, C_CAP)
		if e.length_sec > 0.0:
			_txt_r(c, 904, y + 60, SongListModel.fmt_length(e.length_sec), Palette.SIZE_LABEL, C_CAP)
	# best depth
	if e.status == "ok":
		var bd := SongListModel.best_depth(e, _best_by_fp)
		if bd >= 0.0:
			_txt_r(c, 992, y + 32, "%s m" % Palette.fmt_depth(int(bd)), Palette.SIZE_LABEL, C_TEAL)
		else:
			_txt_r(c, 992, y + 32, "-", Palette.SIZE_LABEL, C_CAP)
	_paint_pips(c, e, y, sel)


func _paint_pips(c: CanvasItem, e: SongEntry, y: float, sel: bool) -> void:
	var avail := _available(e)
	for i in 4:
		var nm: String = SongListModel.DIFFICULTY_ORDER[i]
		var cx := 992.0 - 8.0 - float(3 - i) * 24.0
		var cy := y + 52.0
		var col := Palette.lane_color(i)
		if avail.has(nm):
			var chosen := sel and nm == _diff
			NoteShape.draw(c, NoteShape.kind_for_lane(i), Vector2(cx, cy), 16.0, col if chosen else Palette.dim(col), 2.0)
			if chosen:
				c.draw_line(Vector2(cx - 8.0, cy + 12.0), Vector2(cx + 8.0, cy + 12.0), col, 2.0)
		else:
			NoteShape.draw_outline(c, NoteShape.kind_for_lane(i), Vector2(cx, cy), 16.0, Color(C_CAP, 0.35), 2.0)


# -- detail panel --

func _paint_detail(c: CanvasItem) -> void:
	var e := _selected()
	_box(c, PANEL_RECT, Color(C_PANEL, 0.8), Color(C_BORDER, 0.6), 2.0)
	_paint_sonar(c)
	var x0 := 1080.0
	if e == null:
		_paint_stats(c, null)
		_paint_tiles(c, null)
		_paint_start(c, null)
		return
	var ok := e.status == "ok"
	var tcol := C_TEXT if ok or e.status == "needs_chart" else C_CAP
	var title := (e.title if e.title != "" else "Untitled").to_upper()
	var tl := _wrap(title, Palette.SIZE_HEADING, 752.0)
	if tl.size() > 2:
		tl = tl.slice(0, 2)
		tl[1] = _fit(String(tl[1]) + "...", Palette.SIZE_HEADING, 752.0, true)
	elif tl.size() == 1 and _w(tl[0], Palette.SIZE_HEADING, true) > 752.0:
		tl[0] = _fit(tl[0], Palette.SIZE_HEADING, 752.0, true)
	for i in tl.size():
		_txt(c, Vector2(x0, 184 + 48 * i), _fit(tl[i], Palette.SIZE_HEADING, 752.0, true), Palette.SIZE_HEADING, tcol, true)
	var artist := e.artist if e.artist != "" else "Unknown artist"
	_txt(c, Vector2(x0, 272), _fit(artist, Palette.SIZE_BODY, 752.0), Palette.SIZE_BODY, C_TEXT)
	var charter := ("CHARTED BY " + e.charter.to_upper()) if e.charter != "" else "CHARTED BY UNKNOWN"
	_txt(c, Vector2(x0, 304), _fit(charter, Palette.SIZE_LABEL, 752.0), Palette.SIZE_LABEL, C_CAP)
	_paint_stats(c, e)
	c.draw_rect(Rect2(x0, 439, 752, 2), Color(C_BORDER, 0.35))
	_txt(c, Vector2(x0, 476), "DIFFICULTY", Palette.SIZE_LABEL, C_CAP)
	_paint_tiles(c, e)
	if ok:
		_paint_best(c, e)
	else:
		_paint_reason(c, e)
	if e.warnings > 0:
		var wt := "1 line in this chart was skipped." if e.warnings == 1 else \
				"%d lines in this chart were skipped." % e.warnings
		_txt(c, Vector2(x0, 696), wt, Palette.SIZE_LABEL, C_CAP)
	_txt(c, Vector2(x0, 728), "SOURCE", Palette.SIZE_LABEL, C_CAP)
	_txt(c, Vector2(1200, 728), _fit(_source_text(e), Palette.SIZE_LABEL, 600.0), Palette.SIZE_LABEL, C_TEXT)
	_paint_preview_row(c)
	_paint_start(c, e)
	if _show_debug and _diff != "":
		_txt_r(c, 1832, 696, str(e.difficulty(_diff).get("fingerprint", "")), Palette.SIZE_LABEL, C_CAP)


func _source_text(e: SongEntry) -> String:
	match e.source:
		"bundled":
			return "Bundled"
		"test":
			return "Test chart"
		"library":
			return "Library: " + e.library_name
	return "Songs folder"


func _paint_sonar(c: CanvasItem) -> void:
	var ctr := Vector2(1456, 512)
	for r in [160.0, 280.0, 400.0]:
		c.draw_arc(ctr, r, 0.0, TAU, 64, Color(C_BORDER, 0.10), 2.0, true)
	c.draw_line(Vector2(1056, 512), Vector2(1856, 512), Color(C_BORDER, 0.06), 2.0)
	c.draw_line(Vector2(1456, 120), Vector2(1456, 904), Color(C_BORDER, 0.06), 2.0)
	if Settings.low_effects or Settings.reduce_motion:
		return
	var base := _t * TAU / 8.0
	for i in 12:
		var a0 := base - deg_to_rad(5.0) * float(i)
		var a1 := a0 - deg_to_rad(5.0)
		var col := Color(C_TEAL, 0.10 * (1.0 - float(i) / 12.0))
		c.draw_colored_polygon(PackedVector2Array([ctr, ctr + Vector2.from_angle(a0) * 440.0,
				ctr + Vector2.from_angle(a1) * 440.0]), col)
	if _ping_t < 0.6:
		var k := _ping_t / 0.6
		c.draw_arc(ctr, 400.0 * k, 0.0, TAU, 64, Color(C_TEAL, 0.20 * (1.0 - k)), 2.0, true)


func _paint_stats(c: CanvasItem, e: SongEntry) -> void:
	var xs: Array[float] = [1080.0, 1336.0, 1592.0]
	var caps := ["LENGTH", "BPM", "NOTES"]
	var vals := ["-", "-", "-"]
	var ok := e != null and e.status == "ok"
	if e != null:
		if e.length_sec > 0.0:
			vals[0] = SongListModel.fmt_length(e.length_sec)
		if ok:
			if e.bpm_max > 0.0:
				var lo := int(round(e.bpm_min))
				var hi := int(round(e.bpm_max))
				vals[1] = str(hi) if lo == hi else "%d-%d" % [lo, hi]
			var d := e.difficulty(_diff)
			if not d.is_empty():
				vals[2] = SongListModel.fmt_count(int(d["note_count"]))
	for i in 3:
		_txt(c, Vector2(xs[i], 364), caps[i], Palette.SIZE_LABEL, C_CAP)
		var has: bool = vals[i] != "-"
		_txt(c, Vector2(xs[i], 412), vals[i], Palette.SIZE_HEADING, C_TEAL if has else C_CAP, true)


func _paint_tiles(c: CanvasItem, e: SongEntry) -> void:
	var avail := _available(e)
	for i in 4:
		var nm: String = SongListModel.DIFFICULTY_ORDER[i]
		var r := Rect2(TILE_X[i], TILE_Y, 176.0, 72.0)
		var col := Palette.lane_color(i)
		var kind := NoteShape.kind_for_lane(i)
		var name_up := nm.to_upper()
		if not avail.has(nm):
			NoteShape.draw_outline(c, kind, Vector2(r.position.x + 28.0, r.position.y + 36.0), 24.0, Color(C_CAP, 0.35), 2.0)
			_txt(c, Vector2(r.position.x + 52.0, r.position.y + 46.0), name_up, Palette.SIZE_BODY, Color(C_CAP, 0.5))
			continue
		var chosen := nm == _diff
		if chosen:
			_box(c, r, Color(col, 0.25), col, 4.0)
			c.draw_rect(Rect2(r.position.x + 76.0, r.end.y, 24.0, 4.0), col)
			NoteShape.draw(c, kind, Vector2(r.position.x + 28.0, r.position.y + 36.0), 24.0, col, 2.0)
		else:
			_box(c, r, Color(col, 0.10), Palette.dim(col), 2.0)
			NoteShape.draw(c, kind, Vector2(r.position.x + 28.0, r.position.y + 36.0), 24.0, Palette.dim(col), 2.0)
		_txt(c, Vector2(r.position.x + 52.0, r.position.y + 46.0), name_up, Palette.SIZE_BODY, C_TEXT, chosen)


func _paint_best(c: CanvasItem, e: SongEntry) -> void:
	var d := e.difficulty(_diff)
	var cap := "BEST DEPTH - " + _diff.to_upper() if _diff != "" else "BEST DEPTH"
	_txt(c, Vector2(1080, 604), cap, Palette.SIZE_LABEL, C_CAP)
	var b: Dictionary = _best_by_fp.get(str(d.get("fingerprint", "")), {})
	if b.is_empty():
		_txt(c, Vector2(1080, 652), NO_RECORD, Palette.SIZE_LABEL, C_CAP)
		return
	_txt(c, Vector2(1336, 604), "ACCURACY", Palette.SIZE_LABEL, C_CAP)
	_txt(c, Vector2(1080, 652), "%s M" % Palette.fmt_depth(int(float(b["depth"]))), Palette.SIZE_HEADING, C_TEAL, true)
	_txt(c, Vector2(1336, 652), "%d%%" % int(round(float(b["accuracy"]))), Palette.SIZE_HEADING, C_TEAL, true)


func _paint_reason(c: CanvasItem, e: SongEntry) -> void:
	var needs := e.status == "needs_chart"
	var edge := Palette.TEXT if needs else Palette.DESTRUCTIVE
	c.draw_rect(Rect2(1080, 588, 4, 112), edge)
	var title := "Needs a chart" if needs else e.error
	var hint := NEEDS_BODY if needs else e.fix_hint
	var x := 1100.0
	if not needs:
		_txt(c, Vector2(x, 620), "!", Palette.SIZE_BODY, Palette.DESTRUCTIVE, true)
		x += 24.0
	var tcol := C_TEXT if needs else Palette.DESTRUCTIVE
	var y := 620.0
	for ln in _wrap(title, Palette.SIZE_BODY, 1832.0 - x).slice(0, 2):
		_txt(c, Vector2(x, y), ln, Palette.SIZE_BODY, tcol, true)
		y += 32.0
	y += 4.0
	for ln in _wrap(hint, Palette.SIZE_LABEL, 1832.0 - 1100.0).slice(0, 3):
		_txt(c, Vector2(1100, y), ln, Palette.SIZE_LABEL, C_CAP)
		y += 24.0


func _paint_preview_row(c: CanvasItem) -> void:
	if _message_kind == "audio":
		_txt(c, Vector2(1080, 760), "!", Palette.SIZE_LABEL, Palette.DESTRUCTIVE, true)
		_txt(c, Vector2(1100, 760), _fit(_message, Palette.SIZE_LABEL, 732.0), Palette.SIZE_LABEL, Palette.DESTRUCTIVE)
		return
	if _preview_state != "playing" or Settings.volume_music <= 0.0:
		return
	var heights: Array[float] = [12.0, 20.0, 16.0, 8.0]
	if not Settings.reduce_motion:
		var bus := AudioServer.get_bus_index("Music")
		var peak := 0.0
		if bus >= 0:
			peak = clampf(db_to_linear(AudioServer.get_bus_peak_volume_left_db(bus, 0)), 0.0, 1.0)
		for i in 4:
			heights[i] = 4.0 + 20.0 * clampf(peak * (0.6 + 0.4 * sin(_t * 9.0 + float(i) * 1.7)), 0.0, 1.0)
	for i in 4:
		c.draw_rect(Rect2(1080.0 + 10.0 * i, 760.0 - heights[i], 6.0, heights[i]), C_TEAL)
	_txt(c, Vector2(1136, 760), "PREVIEW", Palette.SIZE_LABEL, C_CAP)


func _start_label(e: SongEntry) -> String:
	if e == null:
		return "Unavailable"
	if e.status == "needs_chart":
		return "Needs a chart"
	if e.status != "ok" or _diff == "":
		return "Unavailable"
	if _diving:
		return "Loading..."
	if run_autoplay:
		return "Start Autoplay Dive"
	if run_practice:
		return "Start Practice Dive"
	return "Start Dive"


func _paint_start(c: CanvasItem, e: SongEntry) -> void:
	var on := e != null and _start_enabled()
	var r := START_RECT
	var hover := _hover_btn == "start" and on
	if on:
		_box(c, r, C_SEL, Color(C_TEAL, 1.0 if hover else 0.8), 2.0)
	else:
		_box(c, r, Color(C_PANEL, 0.6), Color(C_CAP, 0.35), 2.0)
	_txt(c, Vector2(r.position.x + 24.0, r.position.y + 34.0), _start_label(e), Palette.SIZE_BODY,
			C_TEXT if on else Color(C_CAP, 0.5), true)
	if on:
		_txt_r(c, r.end.x - 24.0, r.position.y + 32.0, "A" if _last_pad else "ENTER", Palette.SIZE_LABEL, C_CAP)


# -- footer --

func _paint_button(c: CanvasItem, r: Rect2, label: String, id: String, enabled: bool = true) -> void:
	var hover := _hover_btn == id and enabled
	_box(c, r, Color(C_PANEL, 0.6), Color(C_TEAL, 0.9) if hover else Color(C_BORDER, 0.6), 2.0)
	_txt(c, Vector2(r.position.x + 24.0, r.position.y + 34.0), label, Palette.SIZE_BODY,
			C_TEXT if enabled else Color(C_CAP, 0.5), true)


func _paint_footer(c: CanvasItem) -> void:
	_paint_button(c, OPEN_RECT, "Open Songs Folder", "open")
	var scanning: bool = library != null and library.scanning
	_paint_button(c, RESCAN_RECT, "Scanning..." if scanning else "Rescan Library", "rescan", not scanning)
	var hint: String
	if _last_pad:
		hint = "D-PAD SONG  ·  LEFT RIGHT DIFFICULTY  ·  A DIVE  ·  Y SORT  ·  X RESCAN  ·  B BACK"
	elif _filter != "" or _typing:
		hint = "TYPE TO FILTER  ·  BACKSPACE EDIT  ·  ESC CLEAR FILTER  ·  UP DOWN SONG  ·  ENTER DIVE"
	else:
		hint = "UP DOWN SONG  ·  LEFT RIGHT DIFFICULTY  ·  ENTER DIVE  ·  F5 RESCAN  ·  ESC BACK"
	_txt(c, Vector2(64, 1008), _fit(hint, Palette.SIZE_LABEL, 976.0), Palette.SIZE_LABEL, C_CAP)
	if library != null:
		var prefix := "Songs folder: "
		var path := SongListModel.truncate_middle(library.songs_dir(), 66 - prefix.length())
		var full := prefix + path
		var x := 1856.0 - _w(full, Palette.SIZE_LABEL)
		_txt(c, Vector2(x, 1008), prefix, Palette.SIZE_LABEL, C_CAP)
		_txt(c, Vector2(x + _w(prefix, Palette.SIZE_LABEL), 1008), path, Palette.SIZE_LABEL, C_TEXT)


func _scan_text() -> String:
	var scanning: bool = library != null and library.scanning
	return SongListModel.scan_status_text(scanning, _scan_done, _scan_total, _scan_label,
			_scan_count if _scan_count > 0 else maxi(0, _all.size() - 1), _scan_unplayable)


func _paint_scan(c: CanvasItem) -> void:
	var scanning: bool = library != null and library.scanning
	if _message_kind == "folder":
		_txt(c, Vector2(704, 960), "!", Palette.SIZE_LABEL, Palette.DESTRUCTIVE, true)
		var ml := _wrap(_message, Palette.SIZE_LABEL, 456.0)
		var y := 946.0 if ml.size() > 1 else 960.0
		for ln in ml.slice(0, 2):
			_txt(c, Vector2(724, y), ln, Palette.SIZE_LABEL, Palette.DESTRUCTIVE)
			y += 22.0
		return
	if library != null and library.folder_error != "":
		var nm: String = library.folder_error.trim_prefix("Folder not found: ").trim_suffix("/").get_file()
		var msg := "Could not read library folder \"%s\". Check that it still exists, then press Rescan Library." % nm
		_txt(c, Vector2(704, 946), "!", Palette.SIZE_LABEL, Palette.DESTRUCTIVE, true)
		var y2 := 946.0
		for ln in _wrap(msg, Palette.SIZE_LABEL, 456.0).slice(0, 2):
			_txt(c, Vector2(724, y2), ln, Palette.SIZE_LABEL, Palette.DESTRUCTIVE)
			y2 += 22.0
		return
	if scanning and Time.get_ticks_msec() - _scan_started_msec >= SCAN_STRIP_DELAY_MSEC:
		var track := Rect2(704, 936, 240, 8)
		c.draw_rect(track, Color(0.91, 0.9, 0.94, 0.25))
		if _scan_total > 0:
			c.draw_rect(Rect2(track.position, Vector2(240.0 * clampf(float(_scan_done) / float(_scan_total), 0.0, 1.0), 8.0)), C_TEAL)
		elif Settings.reduce_motion:
			c.draw_rect(Rect2(track.position, Vector2(120.0, 8.0)), C_TEAL)
		else:
			var sx := fmod(_t / 1.2, 1.0) * (240.0 + 64.0) - 64.0
			var x0 := maxf(sx, 0.0)
			var x1 := minf(sx + 64.0, 240.0)
			if x1 > x0:
				c.draw_rect(Rect2(704.0 + x0, 936.0, x1 - x0, 8.0), C_TEAL)
		_txt(c, Vector2(704, 968), _fit(_scan_text(), Palette.SIZE_LABEL, 456.0), Palette.SIZE_LABEL, C_CAP)
	elif scanning:
		pass
	else:
		_txt(c, Vector2(704, 960), _fit(_scan_text(), Palette.SIZE_LABEL, 456.0), Palette.SIZE_LABEL, C_CAP)
