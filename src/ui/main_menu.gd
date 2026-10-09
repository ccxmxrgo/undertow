class_name MainMenu
extends Control
## Entry screen (UI-SPEC): Start Dive, autoplay entry, Calibrate Sonar, Settings, Quit Game.
## First launch (Settings.calibration_done false) routes straight to the skippable wizard once per
## session; an output-device change since the last calibration shows the re-calibrate prompt.

const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"
const FOLDER_MSG_SEC := 6.0
const CALIBRATION_SCENE := "res://scenes/calibration.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const DEVICE_CHANGED_COPY := "Output device changed. Calibrate Sonar again for accurate timing."
const NO_RECORD_COPY := "No record yet. Finish a dive to set one."
const RECORDS_ERROR_COPY := "Records could not be loaded. Starting with an empty record book."
const NOT_CALIBRATED_BODY := "Timing may feel off until you calibrate. Choose Calibrate Sonar to fix it."

## True once the first-launch redirect was taken or skipped this session.
static var boot_handled: bool = false

## True once the records-load error was shown this session (one-time message).
static var records_error_shown: bool = false

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()

## Test seam: Callable() -> bool replaces SongLibrary.open_songs_folder().
var open_folder: Callable = Callable()

var start_button: Button
var practice_button: Button
var autoplay_button: Button
var calibrate_button: Button
var settings_button: Button
var quit_button: Button
var open_folder_button: Button
var folder_message_label: Label
var prompt_calibrate_button: Button
var prompt_skip_button: Button

var best_label: Label
var records_error_label: Label

var _prompt: Control
var _empty_state: Control


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	_build()
	_route_on_boot.call_deferred()


## True when this boot should open the calibration wizard instead of the menu.
func needs_first_launch_wizard() -> bool:
	return not Settings.calibration_done and not boot_handled


func _route_on_boot() -> void:
	if needs_first_launch_wizard():
		boot_handled = true
		_go(CALIBRATION_SCENE)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiLayout.fill_rect(bg)
	add_child(bg)
	var center := CenterContainer.new()
	UiLayout.fill_rect(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_MD)
	center.add_child(box)
	var title := Label.new()
	title.text = "UNDERTOW"
	title.theme_type_variation = &"DisplayLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_prompt = _build_prompt()
	box.add_child(_prompt)
	_empty_state = _build_empty_state()
	box.add_child(_empty_state)

	start_button = _item(box, "Start Dive", func() -> void: launch(false))
	practice_button = _item(box, "Practice Dive (No-Fail)", func() -> void: launch_practice())
	_build_best_line(box)
	calibrate_button = _item(box, "Calibrate Sonar", func() -> void: _go(CALIBRATION_SCENE))
	settings_button = _item(box, "Settings", func() -> void: _go(SETTINGS_SCENE))
	autoplay_button = _item(box, "Autoplay Dive (test)", func() -> void: launch(true))
	open_folder_button = _item(box, "Open Songs Folder", func() -> void: open_songs_folder())
	folder_message_label = Label.new()
	folder_message_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	folder_message_label.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
	folder_message_label.focus_mode = Control.FOCUS_NONE
	folder_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	folder_message_label.custom_minimum_size = Vector2(480.0, 0.0)
	folder_message_label.visible = false
	box.add_child(folder_message_label)
	quit_button = _item(box, "Quit Game", func() -> void:
		if is_inside_tree():
			get_tree().quit())
	var items := [start_button, practice_button, calibrate_button, settings_button, autoplay_button,
			open_folder_button, quit_button]
	for i in range(items.size()):
		var b: Button = items[i]
		b.focus_neighbor_top = b.get_path_to(items[(i + items.size() - 1) % items.size()])
		b.focus_neighbor_bottom = b.get_path_to(items[(i + 1) % items.size()])

	_empty_state.visible = not Settings.calibration_done
	_prompt.visible = Settings.device_changed()
	if _prompt.visible:
		prompt_calibrate_button.grab_focus()
	else:
		start_button.grab_focus()


## The visible "Best: ..." line moved into Song Select (records are per song and difficulty).
## The label stays as a hidden node for harness compatibility; never part of the focus ring.
func _build_best_line(box: VBoxContainer) -> void:
	var store := ScoreStore.new()
	store.load()
	var b := store.best(TestCharts.HAND_CHART_ID)
	best_label = Label.new()
	best_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	best_label.focus_mode = Control.FOCUS_NONE
	best_label.visible = false
	if b.is_empty():
		best_label.text = NO_RECORD_COPY
	else:
		best_label.text = "Best: %s m   Accuracy %d%%" % [
			Palette.fmt_depth(int(float(b["depth"]))), int(round(float(b["accuracy"])))]
	box.add_child(best_label)
	if store.load_error and not records_error_shown:
		records_error_shown = true
		records_error_label = Label.new()
		records_error_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		records_error_label.focus_mode = Control.FOCUS_NONE
		records_error_label.text = RECORDS_ERROR_COPY
		box.add_child(records_error_label)


func _item(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(480.0, 56.0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_empty_state() -> Control:
	var v := VBoxContainer.new()
	var h := Label.new()
	h.text = "SONAR NOT CALIBRATED"
	h.theme_type_variation = &"HeadingLabel"
	v.add_child(h)
	var b := Label.new()
	b.text = NOT_CALIBRATED_BODY
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(720.0, 0.0)
	v.add_child(b)
	return v


func _build_prompt() -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var l := Label.new()
	l.text = DEVICE_CHANGED_COPY
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(720.0, 0.0)
	box.add_child(l)
	var row := HBoxContainer.new()
	box.add_child(row)
	prompt_calibrate_button = Button.new()
	prompt_calibrate_button.text = "Calibrate Sonar"
	prompt_calibrate_button.custom_minimum_size = Vector2(320.0, 56.0)
	prompt_calibrate_button.pressed.connect(func() -> void: _go(CALIBRATION_SCENE))
	row.add_child(prompt_calibrate_button)
	prompt_skip_button = Button.new()
	prompt_skip_button.text = "Skip for now"
	prompt_skip_button.custom_minimum_size = Vector2(320.0, 56.0)
	prompt_skip_button.pressed.connect(func() -> void:
		_prompt.visible = false
		start_button.grab_focus())
	row.add_child(prompt_skip_button)
	return panel


func prompt_visible() -> bool:
	return _prompt.visible


func empty_state_visible() -> bool:
	return _empty_state.visible


## Opens Song Select with the run flags; the chart is chosen there (D-13).
func launch(autoplay: bool) -> void:
	SongSelect.run_autoplay = autoplay
	SongSelect.run_practice = false
	_go(SONG_SELECT_SCENE)


## D-09: No-Fail run that never touches the persisted Settings.no_fail.
func launch_practice() -> void:
	SongSelect.run_autoplay = false
	SongSelect.run_practice = true
	_go(SONG_SELECT_SCENE)


## D-05/D-20: works before any scan; shows a red line for 6 s when the file manager fails.
func open_songs_folder() -> void:
	var lib := get_node_or_null("/root/SongLibrary")
	var ok := true
	if open_folder.is_valid():
		ok = bool(open_folder.call())
	else:
		ok = lib != null and lib.open_songs_folder()
	if ok:
		return
	var path := ProjectSettings.globalize_path("user://songs").simplify_path()
	folder_message_label.text = "Could not open the Songs folder. It is at %s" % path
	folder_message_label.visible = true
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_interval(FOLDER_MSG_SEC)
		tw.tween_callback(func() -> void: folder_message_label.visible = false)


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		get_tree().change_scene_to_file(path)
