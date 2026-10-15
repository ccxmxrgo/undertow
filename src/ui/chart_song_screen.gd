class_name ChartSongScreen
extends Control
## Chart a Song (02.2.2 D-01 / D-03 / D-05 / D-06 / D-12 / D-14): turns an audio file the player
## owns into a chart. Seven states, one container each inside the glass content panel:
##   pack_missing - the one-time Autocharter pack download (Download / Install from Folder / Back);
##                  when the build has no pinned parts the not-available text replaces the size
##                  line and both install buttons are disabled.
##   installing   - PackInstaller progress (label + bar) with Cancel (confirmed).
##   pick         - Choose File... (native dialog, Godot FileDialog fallback) or drop a file on
##                  the window; Remove Autocharter Pack / Clear Chart Cache.
##   options      - Name / Artist (prefilled from ID3 or the file name) and the instrument choice;
##                  Start Charting emits start_requested(job) with a validated AutochartJob dict.
##   running      - the job in an AutochartRunner child: 5-row stage list, overall bar, elapsed
##                  time, Cancel (confirmed). MenuMusic is stopped for the CPU.
##   result       - name, instrument and Expert density; Play Now (rescan, then Song Select on the
##                  new song), Chart Another Instrument (cached stems) and Back to Menu.
##   error        - the plain reason (AutochartJob.error_text), Try Again, Show Details (log.txt).
## The screen itself listens to start_requested (the signal stays for tests). A pack whose
## selftest has not passed runs `autochart.py selftest` first (installing state). Leaving the
## screen or closing the game kills a running child (D-05). The stem cache keeps 3 songs (D-12).
## Seams: installer, navigate, library, file_picker, runner_factory, shell_opener, clock,
## music_stop (tests). Colours only from Palette.
## Effect node (UiKit contract): Low effects drops the panel glow; Reduce motion stops the caret
## pulse of the current stage row.

signal start_requested(job: Dictionary)
signal clear_cache_requested()

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"

## Layout (1920x1080 design pixels, same frame as Settings).
const TITLE_POS := Vector2(64.0, 104.0)  # baseline
const HINT_RIGHT := 1856.0
const PANEL_RECT := Rect2(64.0, 160.0, 1792.0, 760.0)
const PANEL_PAD := 48.0
const FOOTER_BASELINE := 1000.0
const FOOTER_W := 1792.0
const BUTTON_H := 64
const SMALL_BUTTON_H := 48
const EDIT_W := 900.0
const ROW_LABEL_W := 200.0
const PROGRESS_SIZE := Vector2(1200.0, 24.0)
const INSTRUMENT_MIN_W := 160.0

const STATES: Array[String] = ["pack_missing", "installing", "pick", "options", "running", "result", "error"]
const STAGE_MARK := 24.0

const INTRO_TEXT := "Chart a Song turns an audio file you own into a playable chart."
const SIZE_TEXT := "It needs a one-time download of %d MB (about %.1f GB on disk)."
const PRIVACY_TEXT := "Charting runs on your PC. Your music never leaves it."
const INSTALL_NOTE := "First setup can take a few minutes. Antivirus scans can slow it down."
const PICK_TEXT := "Choose an MP3, OGG, WAV or FLAC file you own, or drop one onto this window."
const NAME_EMPTY_TEXT := "Enter a song name."
const UNKNOWN_ARTIST := "Unknown"
const FILE_FILTER := "*.mp3,*.ogg,*.wav,*.flac ; Audio files"
const RUNNING_NOTE := "This can take a few minutes. You can leave the game open."
const STOPPING_TEXT := "Stopping..."
const STOPPED_TEXT := "Charting stopped."
const ADDING_TEXT := "Adding to your library..."
const DETAILS_TEXT := "Details: log.txt in the autocharter folder"
const SELFTEST_TEXT := "Testing the autocharter..."
const CLEARED_TEXT := "Chart cache cleared (%d MB freed)."
const CLEAR_FAILED_TEXT := "The chart cache could not be cleared."
const CLEAR_BODY := "Separated instruments of recent songs are deleted. Your charted songs stay."

## Stage rows of the running state; the Python job's 8 stages map onto them (plan 05 order).
const STAGE_ROWS: Array[String] = [
	"Separating instruments",
	"Finding the beat",
	"Finding notes",
	"Reading pitch",
	"Writing chart",
]
const STAGE_TO_ROW := {"decode": 0, "separate": 0, "beats": 1, "onsets": 2, "pitch": 3,
	"rank": 4, "chart": 4, "install": 4}
## done.stem -> result line name; lanes mode says Instrument Lanes.
const STEM_NAMES := {"other": "Melody", "bass": "Bass", "drums": "Drums", "vocals": "Vocals"}
## done.stem / ranking entry -> instrument key of the options form.
const STEM_TO_KEY := {"other": "melody", "bass": "bass", "drums": "drums", "vocals": "vocals"}

## Instrument choices in button order: key, label, job mode, job stem, description.
const INSTRUMENTS: Array[Dictionary] = [
	{"key": "auto", "label": "Auto (recommended)", "mode": "auto", "stem": "other",
		"desc": "Picks the clearest instrument for you."},
	{"key": "melody", "label": "Melody", "mode": "single", "stem": "other",
		"desc": "Follows the lead melody: synths, guitars, keys."},
	{"key": "bass", "label": "Bass", "mode": "single", "stem": "bass",
		"desc": "Follows the bass line on the 4 lanes."},
	{"key": "drums", "label": "Drums", "mode": "single", "stem": "drums",
		"desc": "Charts the drum hits on the 4 lanes."},
	{"key": "vocals", "label": "Vocals", "mode": "single", "stem": "vocals",
		"desc": "Charts the singer's melody on the 4 lanes."},
	{"key": "lanes", "label": "Instrument Lanes", "mode": "lanes", "stem": "other",
		"desc": "Each lane is one instrument: bass, drums, melody, vocals."},
]

## Seams. installer: created as a child when null. navigate: scene changes (default
## ScreenTransition). library: anything with songs_dir() (default the SongLibrary autoload).
## file_picker: func(mode: String ("file" | "dir"), done: Callable(path)) replaces every dialog.
var installer: PackInstaller = null
var navigate: Callable = Callable()
var library: Object = null
var file_picker: Callable = Callable()
## func() -> AutochartRunner; tests return a runner with a scripted fake adapter.
var runner_factory: Callable = Callable()
## func(path: String) for Show Details; default OS.shell_show_in_file_manager.
var shell_opener: Callable = Callable()
## func() -> float seconds for the elapsed time; default the engine tick clock.
var clock: Callable = Callable()
## func() called when a job starts; default MenuMusic.stop().
var music_stop: Callable = Callable()

## The child process runner (created on first use, kept as a child node).
var runner: AutochartRunner = null

var backdrop: AbyssBackdrop
var title_label: Label
var panel: PanelContainer
var footer_label: Label
var focus_marker: FocusMarker
var dialog: ConfirmDialog

# pack_missing
var download_button: Button
var install_folder_button: Button
var pack_back_button: Button
# installing
var progress_label: Label
var progress_bar: ProgressBar
var cancel_install_button: Button
# pick
var choose_file_button: Button
var pick_back_button: Button
var remove_pack_button: Button
var clear_cache_button: Button
# options
var file_label: Label
var name_edit: LineEdit
var artist_edit: LineEdit
var instrument_buttons: Dictionary = {}  # key -> Button (toggle, one ButtonGroup)
var instrument_description: Label
var start_button: Button
var options_back_button: Button
# running
var stage_labels: Array[Label] = []
var stage_marks: Array = []  # StageMark per row
var job_bar: ProgressBar
var elapsed_label: Label
var elapsed_timer: Timer
var cancel_job_button: Button
# result
var result_title: Label
var result_detail: Label
var play_now_button: Button
var chart_another_button: Button
var result_back_button: Button
# error
var error_reason: Label
var retry_button: Button
var details_button: Button
var error_back_button: Button
var error_remove_button: Button

var _state := ""
var _containers: Dictionary = {}  # state -> VBoxContainer
var _headings: Dictionary = {}  # state -> Label
var _bodies: Dictionary = {}  # state -> Array[Label]
var _size_label: Label
var _footer_error := false
var _src := ""
var _instrument := "auto"
var _group: ButtonGroup
var _file_dialog: FileDialog
var _low := false
## "" | "job" | "selftest": what the runner is doing now.
var _run_mode := ""
var _selftest_passed := false
var _current_row := 0
var _t0 := 0.0
## Inputs of the last started job (Try Again / Chart Another Instrument / cancel).
var _ran: Dictionary = {}
var _job_dir := ""
var _result: Dictionary = {}
var _error_selftest := false
var _error_log := ""
var _adding := false


## Stage-row glyph: a check when done, a pulsing caret on the current row, nothing when pending.
class StageMark:
	extends Control
	const PULSE_HZ := 1.0
	var mode := "pending"
	var _t := 0.0

	func set_mode(m: String) -> void:
		mode = m
		_t = 0.0
		modulate.a = 1.0
		set_process(m == "current" and not UiKit.reduce_motion())
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * cos(_t * TAU * PULSE_HZ))

	func _draw() -> void:
		match mode:
			"done":
				UiIcons.draw(self, "check", Rect2(Vector2.ZERO, size), Palette.TEXT_MID)
			"current":
				UiIcons.draw(self, "chevron_right", Rect2(Vector2.ZERO, size), Palette.TEXT_HI)


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	if library == null:
		library = SongLibrary
	if installer == null:
		installer = PackInstaller.new()
	if installer.get_parent() == null:
		installer.name = "PackInstaller"
		add_child(installer)
	installer.progress_changed.connect(_on_progress)
	installer.installed.connect(_on_installed)
	installer.failed.connect(_on_failed)
	_build()
	start_requested.connect(_on_start_requested)
	clear_cache_requested.connect(_confirm_clear_cache)
	UiKit.register_fx(self)
	if is_inside_tree():
		get_window().files_dropped.connect(drop_files)
	if installer.is_installed():
		_enter_installed()
	else:
		show_state("pack_missing")


func _exit_tree() -> void:
	var w := get_window()
	if w != null and w.files_dropped.is_connected(drop_files):
		w.files_dropped.disconnect(drop_files)
	# D-05: leaving the screen never leaves a child running (the runner also kills on free).
	_kill_child()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_kill_child()


# ---- public API ------------------------------------------------------------------------------


func state() -> String:
	return _state


## The VBox of the current state (tests walk it for focus reachability).
func state_container() -> Control:
	return _containers.get(_state)


func heading_text() -> String:
	var l: Label = _headings.get(_state)
	return l.text if l != null else ""


func body_text() -> String:
	var lines := PackedStringArray()
	for l: Label in _bodies.get(_state, []):
		lines.append(l.text)
	return "\n".join(lines)


func footer_text() -> String:
	return footer_label.text


func footer_is_error() -> bool:
	return _footer_error


func selected_instrument() -> String:
	return _instrument


## Switches the visible state container, relinks focus and focuses its first control.
func show_state(s: String) -> void:
	if not STATES.has(s):
		return
	_state = s
	for k: String in _containers:
		(_containers[k] as Control).visible = k == s
	if s == "pack_missing":
		_refresh_pack_missing()
	elif s == "pick":
		# The pack and its cache are never touched while the child runs.
		remove_pack_button.disabled = is_job_running()
		clear_cache_button.disabled = is_job_running()
	_link_focus()
	var first := _first_focus()
	if first != null and is_inside_tree():
		first.grab_focus()


## Accepts a picked or dropped audio file: unsupported types stay in pick with the reason;
## otherwise options opens with Name / Artist prefilled.
func pick_file(path: String) -> void:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty():
		return
	if not AutochartJob.AUDIO_EXTS.has(p.get_extension().to_lower()):
		set_footer(AutochartJob.error_text("bad_type"), true)
		return
	_src = p
	var title := ""
	var artist := ""
	if p.get_extension().to_lower() == "mp3":
		var tags := SongScanner.read_id3(p)
		title = String(tags.get("title", "")).strip_edges()
		artist = String(tags.get("artist", "")).strip_edges()
	if title.is_empty():
		title = p.get_file().get_basename()
	if artist.is_empty():
		artist = UNKNOWN_ARTIST
	name_edit.text = title.left(AutochartJob.MAX_TEXT)
	artist_edit.text = artist.left(AutochartJob.MAX_TEXT)
	file_label.text = "File: %s" % p.get_file()
	select_instrument("auto")
	set_footer("")
	show_state("options")


## Window drag and drop: the first file is used while picking or choosing options.
func drop_files(files: PackedStringArray) -> void:
	if files.is_empty() or not (_state == "pick" or _state == "options") or dialog != null:
		return
	pick_file(files[0])


func select_instrument(key: String) -> void:
	var b: Button = instrument_buttons.get(key)
	if b == null:
		return
	b.button_pressed = true
	_set_instrument(key)


## Builds the job from the options and emits start_requested(job) when it validates.
func request_start() -> void:
	if name_edit.text.strip_edges().is_empty():
		set_footer(NAME_EMPTY_TEXT, true)
		return
	var info := _instrument_info(_instrument)
	var threads := clampi(OS.get_processor_count() / 2, 1, 64)
	var job := AutochartJob.make_job(_src, name_edit.text, artist_edit.text, String(info["mode"]),
		String(info["stem"]), _songs_dir(), AutochartPaths.work_root(), AutochartPaths.models_dir(), threads)
	var code := AutochartJob.validate(job)
	if code != "":
		set_footer(AutochartJob.error_text(code), true)
		return
	set_footer("")
	start_requested.emit(job)


func set_footer(text: String, error: bool = false) -> void:
	_footer_error = error and not text.is_empty()
	footer_label.text = text
	footer_label.add_theme_color_override("font_color", Palette.WARNING_RED if _footer_error else Palette.TEXT_MID)


## True while the autocharter child (job or selftest) is alive.
func is_job_running() -> bool:
	return runner != null and runner.is_running()


## Row states of the running list, top to bottom: "done" | "current" | "pending".
func stage_row_states() -> Array:
	var out: Array = []
	for i in STAGE_ROWS.size():
		out.append("done" if i < _current_row else ("current" if i == _current_row else "pending"))
	return out


## Esc / B. Installing and running ask first; options goes back to pick; error goes back to
## pick (the menu after a failed selftest); elsewhere back to the menu.
func back_pressed() -> void:
	match _state:
		"installing":
			_confirm_stop_install()
		"options":
			set_footer("")
			show_state("pick")
		"running":
			_confirm_stop_job()
		"error":
			_error_back()
		_:
			_go(MENU_SCENE)


# ---- effect contract -------------------------------------------------------------------------


func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	if panel != null:
		panel.add_theme_stylebox_override("panel", _panel_style())
	_refresh_stage_rows()  # Reduce motion starts / stops the caret pulse


func effect_counts() -> Dictionary:
	return {"panel_glow": not _low}


# ---- build -----------------------------------------------------------------------------------


func _build() -> void:
	_low = UiKit.low_effects()
	backdrop = AbyssBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.variant = "table"
	UiLayout.fill_rect(backdrop)
	add_child(backdrop)

	var hf := Palette.display_font()
	title_label = _label("CHART A SONG", Palette.SIZE_HEADING, Palette.TEXT_HI, hf)
	title_label.name = "Title"
	title_label.position = Vector2(TITLE_POS.x, TITLE_POS.y - hf.get_ascent(Palette.SIZE_HEADING))
	add_child(title_label)
	var esc := Label.new()
	esc.name = "EscHint"
	esc.text = "ESC BACK"
	esc.theme_type_variation = &"CaptionLabel"
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cf := Palette.font()
	esc.size = Vector2(320.0, Palette.SIZE_LABEL * 1.5)
	esc.position = Vector2(HINT_RIGHT - 320.0, TITLE_POS.y - cf.get_ascent(Palette.SIZE_LABEL)
		- (esc.size.y - cf.get_height(Palette.SIZE_LABEL)) * 0.5)
	esc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(esc)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.custom_minimum_size = PANEL_RECT.size
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var stack := Control.new()
	stack.name = "States"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	for s in STATES:
		var box := VBoxContainer.new()
		box.name = s.capitalize().replace(" ", "")
		box.add_theme_constant_override("separation", Palette.SP_LG)
		UiLayout.fill_rect(box)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.visible = false
		stack.add_child(box)
		_containers[s] = box
		_bodies[s] = []
	_build_pack_missing(_containers["pack_missing"])
	_build_installing(_containers["installing"])
	_build_pick(_containers["pick"])
	_build_options(_containers["options"])
	_build_running(_containers["running"])
	_build_result(_containers["result"])
	_build_error(_containers["error"])

	elapsed_timer = Timer.new()
	elapsed_timer.name = "ElapsedTimer"
	elapsed_timer.wait_time = 1.0
	elapsed_timer.timeout.connect(_update_elapsed)
	add_child(elapsed_timer)

	footer_label = _label("", Palette.SIZE_BODY, Palette.TEXT_MID)
	footer_label.name = "Footer"
	footer_label.position = Vector2(PANEL_RECT.position.x, FOOTER_BASELINE - cf.get_ascent(Palette.SIZE_BODY))
	footer_label.size = Vector2(FOOTER_W, cf.get_height(Palette.SIZE_BODY))
	footer_label.clip_text = true
	footer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(footer_label)

	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)


func _build_pack_missing(box: VBoxContainer) -> void:
	_heading(box, "pack_missing", "AUTOCHARTER PACK NEEDED")
	_body(box, "pack_missing", INTRO_TEXT)
	_size_label = _body(box, "pack_missing", "")
	_body(box, "pack_missing", PRIVACY_TEXT)
	var row := _button_row(box)
	download_button = _button(row, "Download", "dive", "primary", BUTTON_H, _start_download)
	install_folder_button = _button(row, "Install from Folder...", "folder", "default", BUTTON_H,
		_install_from_folder)
	pack_back_button = _button(row, "Back", "chevron_left", "default", BUTTON_H, back_pressed)


func _build_installing(box: VBoxContainer) -> void:
	_heading(box, "installing", "INSTALLING THE AUTOCHARTER")
	progress_label = _body(box, "installing", "Checking the Autocharter pack...")
	progress_bar = ProgressBar.new()
	progress_bar.name = "Progress"
	progress_bar.custom_minimum_size = PROGRESS_SIZE
	progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	progress_bar.focus_mode = Control.FOCUS_NONE
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(progress_bar)
	var note := _label(INSTALL_NOTE, Palette.SIZE_LABEL, Palette.TEXT_LO)
	box.add_child(note)
	var row := _button_row(box)
	cancel_install_button = _button(row, "Cancel", "chevron_left", "default", BUTTON_H, _confirm_stop_install)


func _build_pick(box: VBoxContainer) -> void:
	_heading(box, "pick", "PICK A SONG")
	_body(box, "pick", PICK_TEXT)
	var row := _button_row(box)
	choose_file_button = _button(row, "Choose File...", "folder", "primary", BUTTON_H, _choose_file)
	pick_back_button = _button(row, "Back", "chevron_left", "default", BUTTON_H, back_pressed)
	var row2 := _button_row(box)
	remove_pack_button = _button(row2, "Remove Autocharter Pack", "", "default", SMALL_BUTTON_H,
		func() -> void: _confirm_remove_pack(remove_pack_button))
	clear_cache_button = _button(row2, "Clear Chart Cache", "", "default", SMALL_BUTTON_H,
		func() -> void: clear_cache_requested.emit())
	for b: Button in [remove_pack_button, clear_cache_button]:
		b.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		b.custom_minimum_size.x = 360.0


func _build_options(box: VBoxContainer) -> void:
	_heading(box, "options", "CHART OPTIONS")
	file_label = _label("", Palette.SIZE_LABEL, Palette.TEXT_LO)
	file_label.clip_text = true
	file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	file_label.custom_minimum_size = Vector2(EDIT_W + ROW_LABEL_W, 0.0)
	file_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(file_label)
	name_edit = _edit_row(box, "Name")
	artist_edit = _edit_row(box, "Artist")

	var irow := HBoxContainer.new()
	irow.name = "InstrumentRow"
	irow.add_theme_constant_override("separation", Palette.SP_MD)
	box.add_child(irow)
	var il := _label("Instrument", Palette.SIZE_BODY, Palette.TEXT_MID)
	il.custom_minimum_size = Vector2(ROW_LABEL_W, 0.0)
	il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	irow.add_child(il)
	_group = ButtonGroup.new()
	for info: Dictionary in INSTRUMENTS:
		var key := String(info["key"])
		var b := UiKit.make_button(String(info["label"]), "", "default", SMALL_BUTTON_H)
		b.name = "Instrument" + key.capitalize()
		b.toggle_mode = true
		b.button_group = _group
		b.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		b.custom_minimum_size.x = INSTRUMENT_MIN_W
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_set_instrument(key))
		irow.add_child(b)
		instrument_buttons[key] = b
	instrument_description = _label("", Palette.SIZE_LABEL, Palette.TEXT_MID)
	instrument_description.name = "InstrumentDescription"
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", int(ROW_LABEL_W) + Palette.SP_MD)
	pad.add_child(instrument_description)
	box.add_child(pad)

	var row := _button_row(box)
	start_button = _button(row, "Start Charting", "dive", "primary", BUTTON_H, request_start)
	options_back_button = _button(row, "Back", "chevron_left", "default", BUTTON_H, back_pressed)
	select_instrument("auto")


func _build_running(box: VBoxContainer) -> void:
	var h := _heading(box, "running", "CHARTING")
	h.clip_text = true
	h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.custom_minimum_size = Vector2(PANEL_RECT.size.x - PANEL_PAD * 2.0, 0.0)
	var list := VBoxContainer.new()
	list.name = "Stages"
	list.add_theme_constant_override("separation", Palette.SP_SM)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(list)
	for i in STAGE_ROWS.size():
		var row := HBoxContainer.new()
		row.name = "Stage%d" % i
		row.add_theme_constant_override("separation", Palette.SP_MD)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(row)
		var mark := StageMark.new()
		mark.name = "Mark"
		mark.custom_minimum_size = Vector2(STAGE_MARK, STAGE_MARK)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var l := _label(STAGE_ROWS[i], Palette.SIZE_BODY, Palette.TEXT_LO)
		l.name = "Label"
		row.add_child(l)
		stage_marks.append(mark)
		stage_labels.append(l)
	job_bar = ProgressBar.new()
	job_bar.name = "JobProgress"
	job_bar.custom_minimum_size = PROGRESS_SIZE
	job_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	job_bar.show_percentage = false
	job_bar.min_value = 0.0
	job_bar.max_value = 100.0
	job_bar.focus_mode = Control.FOCUS_NONE
	job_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(job_bar)
	elapsed_label = _label("0:00", Palette.SIZE_LABEL, Palette.TEXT_MID)
	elapsed_label.name = "Elapsed"
	box.add_child(elapsed_label)
	var note := _label(RUNNING_NOTE, Palette.SIZE_LABEL, Palette.TEXT_LO)
	box.add_child(note)
	(_bodies["running"] as Array).append(note)
	var row2 := _button_row(box)
	cancel_job_button = _button(row2, "Cancel", "chevron_left", "default", BUTTON_H, _confirm_stop_job)
	_refresh_stage_rows()


func _build_result(box: VBoxContainer) -> void:
	_heading(box, "result", "READY")
	result_title = _body(box, "result", "")
	result_title.add_theme_color_override("font_color", Palette.TEXT_HI)
	result_detail = _body(box, "result", "")
	var row := _button_row(box)
	play_now_button = _button(row, "Play Now", "dive", "primary", BUTTON_H, _play_now)
	chart_another_button = _button(row, "Chart Another Instrument", "chart", "default", BUTTON_H, _chart_another)
	result_back_button = _button(row, "Back to Menu", "chevron_left", "default", BUTTON_H,
		func() -> void: _go(MENU_SCENE))


func _build_error(box: VBoxContainer) -> void:
	_heading(box, "error", "CHARTING FAILED")
	error_reason = _body(box, "error", "")
	error_reason.add_theme_color_override("font_color", Palette.WARNING_RED)
	var details := _label(DETAILS_TEXT, Palette.SIZE_LABEL, Palette.TEXT_LO)
	box.add_child(details)
	(_bodies["error"] as Array).append(details)
	var row := _button_row(box)
	retry_button = _button(row, "Try Again", "", "primary", BUTTON_H, _retry)
	details_button = _button(row, "Show Details", "folder", "default", BUTTON_H, _show_details)
	error_back_button = _button(row, "Back", "chevron_left", "default", BUTTON_H, _error_back)
	var row2 := _button_row(box)
	error_remove_button = _button(row2, "Remove Autocharter Pack", "", "default", SMALL_BUTTON_H,
		func() -> void: _confirm_remove_pack(error_remove_button))
	error_remove_button.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	error_remove_button.custom_minimum_size.x = 360.0
	error_remove_button.visible = false


func _edit_row(box: VBoxContainer, title: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.name = title + "Row"
	row.add_theme_constant_override("separation", Palette.SP_MD)
	box.add_child(row)
	var l := _label(title, Palette.SIZE_BODY, Palette.TEXT_MID)
	l.custom_minimum_size = Vector2(ROW_LABEL_W, 0.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var e := LineEdit.new()
	e.name = title + "Edit"
	e.max_length = AutochartJob.MAX_TEXT
	e.custom_minimum_size = Vector2(EDIT_W, SMALL_BUTTON_H)
	e.add_theme_font_size_override("font_size", Palette.SIZE_BODY)
	e.focus_mode = Control.FOCUS_ALL
	e.text_submitted.connect(func(_t: String) -> void: request_start())
	row.add_child(e)
	return e


# ---- building blocks -------------------------------------------------------------------------


func _panel_style() -> StyleBoxFlat:
	var sb := UiKit.style_panel("default", _low)
	sb.content_margin_left = PANEL_PAD
	sb.content_margin_right = PANEL_PAD
	sb.content_margin_top = PANEL_PAD
	sb.content_margin_bottom = PANEL_PAD
	return sb


func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


func _heading(box: VBoxContainer, s: String, text: String) -> Label:
	var l := _label(text, Palette.SIZE_HEADING, Palette.TEXT_HI, Palette.display_font())
	l.name = "Heading"
	box.add_child(l)
	_headings[s] = l
	return l


func _body(box: VBoxContainer, s: String, text: String) -> Label:
	var l := _label(text, Palette.SIZE_BODY, Palette.TEXT_MID)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_RECT.size.x - PANEL_PAD * 2.0, 0.0)
	box.add_child(l)
	(_bodies[s] as Array).append(l)
	return l


func _button_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.SP_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	return row


func _button(row: HBoxContainer, text: String, icon: String, variant: String, height: int,
		cb: Callable) -> Button:
	var b := UiKit.make_button(text, icon, variant, height)
	b.name = text.replace(".", "").replace(" ", "")
	if b.custom_minimum_size.x < 280.0:
		b.custom_minimum_size.x = 280.0 if icon == "" else 320.0
	b.pressed.connect(cb)
	row.add_child(b)
	return b


# ---- focus -----------------------------------------------------------------------------------


## Focus rows of the current state (enabled controls only), top to bottom.
func focus_rows() -> Array:
	var rows: Array = []
	match _state:
		"pack_missing":
			rows.append([download_button, install_folder_button, pack_back_button])
		"installing":
			rows.append([cancel_install_button])
		"pick":
			rows.append([choose_file_button, pick_back_button])
			rows.append([remove_pack_button, clear_cache_button])
		"options":
			rows.append([name_edit])
			rows.append([artist_edit])
			var inst: Array = []
			for info: Dictionary in INSTRUMENTS:
				inst.append(instrument_buttons[String(info["key"])])
			rows.append(inst)
			rows.append([start_button, options_back_button])
		"running":
			rows.append([cancel_job_button])
		"result":
			rows.append([play_now_button, chart_another_button, result_back_button])
		"error":
			rows.append([retry_button, details_button, error_back_button])
			rows.append([error_remove_button])
	var out: Array = []
	for r: Array in rows:
		var live: Array = []
		for c: Control in r:
			if c.visible and not (c is BaseButton and (c as BaseButton).disabled):
				live.append(c)
		if not live.is_empty():
			out.append(live)
	return out


## Up / down move between rows (wrapping), left / right within a row (wrapping); disabled
## controls are skipped so the ring never lands on them.
func _link_focus() -> void:
	var rows := focus_rows()
	for i in rows.size():
		var row: Array = rows[i]
		var above: Control = (rows[(i + rows.size() - 1) % rows.size()] as Array)[0]
		var below: Control = (rows[(i + 1) % rows.size()] as Array)[0]
		for j in row.size():
			var c: Control = row[j]
			c.focus_neighbor_top = c.get_path_to(above)
			c.focus_neighbor_bottom = c.get_path_to(below)
			c.focus_neighbor_left = c.get_path_to(row[(j + row.size() - 1) % row.size()])
			c.focus_neighbor_right = c.get_path_to(row[(j + 1) % row.size()])
			c.focus_previous = c.focus_neighbor_left
			c.focus_next = c.focus_neighbor_right
	# Disabled buttons cannot take focus at all.
	for b: Button in [download_button, install_folder_button, remove_pack_button, clear_cache_button]:
		b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL


func _first_focus() -> Control:
	var rows := focus_rows()
	if rows.is_empty():
		return null
	if _state == "pack_missing" and download_button.disabled:
		return pack_back_button
	return (rows[0] as Array)[0]


# ---- pack_missing / installing ---------------------------------------------------------------


func _available() -> bool:
	return not (installer.spec.get("parts", []) as Array).is_empty()


func _download_bytes() -> int:
	var total := 0
	for p: Dictionary in installer.spec.get("parts", []):
		total += int(p.get("size", 0))
	return total


func _refresh_pack_missing() -> void:
	var ok := _available()
	if ok:
		_size_label.text = SIZE_TEXT % [int(round(_download_bytes() / 1e6)),
			float(installer.spec.get("unpacked_bytes", 0)) / 1e9]
	else:
		_size_label.text = PackInstaller.NOT_AVAILABLE_TEXT
	download_button.disabled = not ok
	install_folder_button.disabled = not ok


func _start_download() -> void:
	if not _available():
		return
	installer.source_dir = ""
	_begin_install()


func _install_from_folder() -> void:
	if not _available():
		return
	_pick("dir", func(path: String) -> void:
		if _state != "pack_missing" or path.strip_edges().is_empty():
			return
		installer.source_dir = path.strip_edges()
		_begin_install())


func _begin_install() -> void:
	set_footer("")
	progress_label.text = "Checking the Autocharter pack..."
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	show_state("installing")
	installer.start()  # may fail synchronously; _on_failed then returns to pack_missing


func _on_progress(done: int, total: int, label: String) -> void:
	if label != "":
		progress_label.text = label
	progress_bar.max_value = maxf(1.0, float(total))
	progress_bar.value = clampf(float(done), 0.0, progress_bar.max_value)


func _on_installed() -> void:
	_close_dialog()
	set_footer("")
	_enter_installed()


## The pack is installed: pick when its selftest passed, else run the selftest first (T-48).
func _enter_installed() -> void:
	if installer.selftest_ok():
		show_state("pick")
	else:
		_run_selftest()


func _on_failed(_code: String, message: String) -> void:
	_close_dialog()
	show_state("pack_missing")
	set_footer(message, true)


func _confirm_stop_install() -> void:
	if dialog != null or _state != "installing":
		return
	if _run_mode == "selftest":
		_open_dialog("STOP THE TEST?", "The Autocharter is tested again next time you open this screen.",
			"Stop Test", "Keep Testing",
			func() -> void:
				_kill_child()
				_go(MENU_SCENE),
			cancel_install_button)
		return
	_open_dialog("STOP THE INSTALL?", "The download so far is discarded. You can install again later.",
		"Stop Install", "Keep Installing",
		func() -> void:
			installer.cancel()
			show_state("pack_missing"),
		cancel_install_button)


# ---- pick ------------------------------------------------------------------------------------


func _choose_file() -> void:
	_pick("file", func(path: String) -> void:
		if _state == "pick" or _state == "options":
			pick_file(path))


func _confirm_remove_pack(refocus: Control) -> void:
	if dialog != null or is_job_running():
		return
	_open_dialog("REMOVE THE AUTOCHARTER?",
		"This frees about 1 GB. Your charted songs stay in your library.", "Remove", "Keep",
		func() -> void:
			if installer.remove_pack(is_job_running()):
				set_footer("")
				show_state("pack_missing")
			else:
				set_footer("The Autocharter pack could not be removed. Close other programs using it and try again.", true),
		refocus)


## Clear Chart Cache (D-12): confirmed, refused while the child runs.
func _confirm_clear_cache() -> void:
	if dialog != null or is_job_running():
		return
	_open_dialog("CLEAR CHART CACHE?", CLEAR_BODY, "Clear", "Keep",
		func() -> void:
			if is_job_running():
				return
			var freed := AutochartWorkCache.clear(AutochartPaths.work_root())
			if freed < 0:
				set_footer(CLEAR_FAILED_TEXT, true)
			else:
				set_footer(CLEARED_TEXT % int(round(freed / 1e6)))
			if clear_cache_button.is_visible_in_tree():
				clear_cache_button.grab_focus(),
		clear_cache_button)


## Opens the injected picker, else the native dialog, else a Godot FileDialog.
## mode "file" = one audio file, "dir" = a folder (Install from Folder).
func _pick(mode: String, done: Callable) -> void:
	if file_picker.is_valid():
		file_picker.call(mode, done)
		return
	var is_dir := mode == "dir"
	var title := "Choose the Autocharter pack folder" if is_dir else "Choose a song"
	var filters := PackedStringArray() if is_dir else PackedStringArray([FILE_FILTER])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var cb := func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			if ok and not paths.is_empty():
				done.call_deferred(paths[0])
		DisplayServer.file_dialog_show(title, OS.get_system_dir(OS.SYSTEM_DIR_MUSIC), "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR if is_dir else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters, cb)
		return
	if _file_dialog != null:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if is_dir else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false
	_file_dialog.title = title
	_file_dialog.filters = filters
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if is_dir:
		_file_dialog.dir_selected.connect(func(p: String) -> void: done.call(p))
	else:
		_file_dialog.file_selected.connect(func(p: String) -> void: done.call(p))
	add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


# ---- options ---------------------------------------------------------------------------------


func _instrument_info(key: String) -> Dictionary:
	for info: Dictionary in INSTRUMENTS:
		if String(info["key"]) == key:
			return info
	return INSTRUMENTS[0]


func _set_instrument(key: String) -> void:
	_instrument = key
	instrument_description.text = String(_instrument_info(key)["desc"])


func _songs_dir() -> String:
	if library != null and library.has_method("songs_dir"):
		return String(library.call("songs_dir")).replace("\\", "/").simplify_path()
	return ProjectSettings.globalize_path("user://songs").simplify_path()


# ---- runner ----------------------------------------------------------------------------------


func _ensure_runner() -> AutochartRunner:
	if runner != null:
		return runner
	runner = runner_factory.call() if runner_factory.is_valid() else AutochartRunner.new()
	runner.name = "AutochartRunner"
	add_child(runner)
	runner.stage_changed.connect(_on_runner_stage)
	runner.progress_changed.connect(_on_runner_progress)
	runner.warned.connect(_on_runner_warned)
	runner.event_received.connect(_on_runner_event)
	runner.finished.connect(_on_runner_finished)
	runner.failed.connect(_on_runner_failed)
	runner.cancelled.connect(_on_runner_cancelled)
	return runner


## Kills a running child (screen exit, window close, stopped selftest). Idempotent.
func _kill_child() -> void:
	if runner != null and runner.is_running():
		runner.cancel()


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_msec() / 1000.0


func _stop_menu_music() -> void:
	if music_stop.is_valid():
		music_stop.call()
		return
	var mm := get_node_or_null("/root/MenuMusic") if is_inside_tree() else null
	if mm != null and mm.has_method("stop"):
		mm.call("stop")


## start_requested(job): the job is already validated (plan 08). Writes job.json into a fresh
## job dir and starts `autochart.py job <job.json>` with the fixed argv (T-44).
func _on_start_requested(job: Dictionary) -> void:
	if is_job_running() or _state == "running":
		return
	if not installer.is_installed():
		show_state("pack_missing")
		return
	if not installer.selftest_ok():
		_run_selftest()
		return
	_ran = {"src": _src, "name": String(job.get("name", "")), "artist": String(job.get("artist", "")),
		"instrument": _instrument}
	_result = {}
	_job_dir = AutochartWorkCache.new_job_dir(AutochartPaths.work_root())
	var job_path := _job_dir.path_join("job.json")
	if _job_dir == "" or AutochartJob.write_job(job_path, job) != OK:
		_show_error("disk" if _job_dir != "" else "start", "", false)
		return
	_title_running(String(_ran["name"]))
	_current_row = 0
	_refresh_stage_rows()
	job_bar.value = 0.0
	_t0 = _now()
	_update_elapsed()
	elapsed_timer.start()
	set_footer("")
	show_state("running")
	_stop_menu_music()
	_run_mode = "job"
	# A synchronous start failure arrives through failed() and shows the error state.
	_ensure_runner().start(AutochartPaths.python_exe(),
		AutochartJob.build_args(AutochartPaths.app_dir(), "job", job_path))


func _title_running(song_name: String) -> void:
	(_headings["running"] as Label).text = "CHARTING %s" % song_name.to_upper()


func _update_elapsed() -> void:
	var s := maxi(0, int(floor(_now() - _t0)))
	elapsed_label.text = "%d:%02d" % [s / 60, s % 60]


func _refresh_stage_rows() -> void:
	var states := stage_row_states()
	for i in mini(stage_labels.size(), stage_marks.size()):
		var st: String = states[i]
		var col := Palette.TEXT_MID if st == "done" else (Palette.TEXT_HI if st == "current" else Palette.TEXT_LO)
		stage_labels[i].add_theme_color_override("font_color", col)
		(stage_marks[i] as StageMark).set_mode(st)


func _on_runner_stage(_k: int, _n: int, stage_name: String) -> void:
	if _run_mode != "job" or not STAGE_TO_ROW.has(stage_name):
		return
	_current_row = maxi(_current_row, int(STAGE_TO_ROW[stage_name]))
	_refresh_stage_rows()


func _on_runner_progress(frac: float) -> void:
	if _run_mode == "job":
		job_bar.value = clampf(frac, 0.0, 1.0) * 100.0


func _on_runner_warned(msg: String) -> void:
	if _run_mode == "job" and msg.strip_edges() != "":
		set_footer(msg.strip_edges().left(200))


func _on_runner_event(ev: Dictionary) -> void:
	if _run_mode == "selftest" and ev.get("ev") == "selftest" and ev.get("ok") == true:
		_selftest_passed = true


func _end_run() -> String:
	var mode := _run_mode
	_run_mode = ""
	elapsed_timer.stop()
	return mode


func _on_runner_finished(result: Dictionary) -> void:
	match _end_run():
		"job":
			_result = result
			# D-12: keep the stems of the last 3 songs; the one just used always stays.
			AutochartWorkCache.prune(AutochartPaths.work_root(), AutochartWorkCache.KEEP, runner.work_dir())
			_show_result()
		"selftest":
			_selftest_finished(_selftest_passed)


func _on_runner_failed(code: String, _message: String, log_path: String) -> void:
	match _end_run():
		"job":
			_show_error(code, log_path, false)
		"selftest":
			# The selftest prints its own event and exits 0 without a done event, which the runner
			# reports as a failure; the selftest event decides.
			if _selftest_passed:
				_selftest_finished(true)
			else:
				_show_error(code, log_path, true)


## The process is gone (the runner only emits cancelled after it exited): remove the stems of
## an analysis that never finished (T-46) and return to the options.
func _on_runner_cancelled() -> void:
	if _end_run() != "job":
		return
	AutochartWorkCache.remove_unfinished(runner.work_dir())
	_restore_options(String(_ran.get("instrument", "auto")))
	set_footer(STOPPED_TEXT)


func _confirm_stop_job() -> void:
	if dialog != null or _state != "running":
		return
	_open_dialog("STOP CHARTING?", "The chart for %s will not be saved." % String(_ran.get("name", "")),
		"Stop", "Keep Charting",
		func() -> void:
			if is_job_running():
				set_footer(STOPPING_TEXT)
				runner.cancel(),
		cancel_job_button)


# ---- selftest --------------------------------------------------------------------------------


func _run_selftest() -> void:
	if is_job_running():
		return
	_selftest_passed = false
	progress_label.text = SELFTEST_TEXT
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	set_footer("")
	show_state("installing")
	_run_mode = "selftest"
	_ensure_runner().start(AutochartPaths.python_exe(),
		AutochartJob.build_args(AutochartPaths.app_dir(), "selftest"))


func _selftest_finished(ok: bool) -> void:
	installer.mark_selftest(ok)
	if ok:
		progress_bar.value = progress_bar.max_value
		set_footer("")
		show_state("pick")


# ---- result ----------------------------------------------------------------------------------


func _show_result() -> void:
	result_title.text = "%s - %s" % [String(_ran.get("name", "")), String(_ran.get("artist", ""))]
	var nps = _result.get("expert_nps", 0.0)
	result_detail.text = "Instrument: %s   Expert: %.1f notes/s" % [
		_instrument_name(_result), float(nps) if (nps is float or nps is int) else 0.0]
	_adding = false
	set_footer("")
	show_state("result")


static func _instrument_name(r: Dictionary) -> String:
	var stem := String(r.get("stem", "")) if r.get("stem") is String else ""
	if String(r.get("mode", "")) == "lanes" or stem == "lanes":
		return "Instrument Lanes"
	return String(STEM_NAMES.get(stem, "Melody"))


## Instrument for Chart Another Instrument: the best-ranked stem that differs from the one just
## charted; Instrument Lanes after a single stem when there is no ranking.
static func next_instrument(r: Dictionary) -> String:
	var charted := String(r.get("stem", "")) if r.get("stem") is String else ""
	if String(r.get("mode", "")) == "lanes":
		charted = "lanes"
	var ranking = r.get("ranking", [])
	if ranking is Array:
		for s in ranking:
			if s is String and STEM_TO_KEY.has(s) and s != charted:
				return String(STEM_TO_KEY[s])
	return "auto" if charted == "lanes" else "lanes"


## Play Now (D-06): rescan, then open Song Select on the new song. A scan that is already
## running may predate the new folder, so it is waited out and a fresh scan follows.
func _play_now() -> void:
	if _adding or _result.is_empty():
		return
	_adding = true
	set_footer(ADDING_TEXT)
	if library == null or not library.has_signal("scan_finished") or not library.has_method("rescan"):
		_open_new_song()
		return
	if library.get("scanning") == true:
		library.connect("scan_finished", _on_prior_scan_finished, CONNECT_ONE_SHOT)
	else:
		_rescan_for_play()


func _on_prior_scan_finished(_count: int, _unplayable: int) -> void:
	_rescan_for_play()


func _rescan_for_play() -> void:
	library.connect("scan_finished", _on_play_scan_finished, CONNECT_ONE_SHOT)
	library.call("rescan")


func _on_play_scan_finished(_count: int, _unplayable: int) -> void:
	_open_new_song()


## T-45: the done folder is only turned into a song id; the library scan validates it like any
## other song folder and Song Select restores the selection from last_song_id.
func _open_new_song() -> void:
	var folder := String(_result.get("folder", "")) if _result.get("folder") is String else ""
	if library != null and folder != "" and "last_song_id" in library:
		library.set("last_song_id", SongScanner.norm(folder.replace("\\", "/")))
	_go(SONG_SELECT_SCENE)


func _chart_another() -> void:
	_restore_options(next_instrument(_result))


## Back to options with the inputs of the last job and `key` selected.
func _restore_options(key: String) -> void:
	_src = String(_ran.get("src", _src))
	name_edit.text = String(_ran.get("name", name_edit.text))
	artist_edit.text = String(_ran.get("artist", artist_edit.text))
	file_label.text = "File: %s" % _src.get_file()
	select_instrument(key)
	set_footer("")
	show_state("options")


# ---- error -----------------------------------------------------------------------------------


func _show_error(code: String, log_path: String, selftest: bool) -> void:
	_error_selftest = selftest
	_error_log = _log_target(log_path, selftest)
	(_headings["error"] as Label).text = "AUTOCHARTER TEST FAILED" if selftest else "CHARTING FAILED"
	error_reason.text = AutochartJob.error_text(code)
	error_remove_button.visible = selftest
	set_footer("")
	show_state("error")


## The log to show: the event's path when it lies inside the pack root, else the job's own
## log.txt (W1) or the selftest log next to the models. Child output never points Explorer
## outside the pack folder.
func _log_target(log_path: String, selftest: bool) -> String:
	var p := log_path.strip_edges().replace("\\", "/").simplify_path()
	if p != "" and p.get_extension().to_lower() == "txt" and AutochartPaths.is_under_root(p):
		return p
	if selftest:
		return AutochartPaths.version_dir().path_join("selftest_log.txt")
	return _job_dir.path_join("log.txt") if _job_dir != "" else AutochartPaths.work_root()


func error_log_path() -> String:
	return _error_log


func _show_details() -> void:
	if _error_log == "":
		return
	if shell_opener.is_valid():
		shell_opener.call(_error_log)
		return
	if DisplayServer.get_name() == "headless":
		return
	var target := _error_log if FileAccess.file_exists(_error_log) else _error_log.get_base_dir()
	OS.shell_show_in_file_manager(target, true)


func _retry() -> void:
	if _error_selftest:
		_run_selftest()
	else:
		_restore_options(String(_ran.get("instrument", "auto")))


func _error_back() -> void:
	if _error_selftest:
		_go(MENU_SCENE)
	else:
		set_footer("")
		show_state("pick")


# ---- dialogs / navigation --------------------------------------------------------------------


func _open_dialog(title: String, body: String, confirm_text: String, safe_text: String,
		on_confirm: Callable, refocus: Control) -> void:
	dialog = ConfirmDialog.new()
	add_child(dialog)
	dialog.setup(title, body, confirm_text, safe_text)
	if dialog.is_inside_tree():
		dialog.safe_button.grab_focus()
	dialog.cancelled.connect(func() -> void:
		_close_dialog()
		if is_instance_valid(refocus) and refocus.is_visible_in_tree():
			refocus.grab_focus())
	dialog.confirmed.connect(func() -> void:
		_close_dialog()
		on_confirm.call())


func _close_dialog() -> void:
	if dialog != null:
		dialog.queue_free()
		dialog = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or dialog != null:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed()


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		ScreenTransition.change_scene(path)
