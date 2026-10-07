class_name SettingsScreen
extends Control
## Settings (UI-SPEC): Controls rebind table, Gameplay, Audio and Calibration sections in one
## scrollable list. Runs as a full scene (Back returns to the main menu) or, with `overlay = true`
## (set by the pause menu), as an overlay: Back saves, emits `closed` and never changes scene.
## Changes apply live through Settings and are saved on exit.

signal closed

const MENU_SCENE := "res://scenes/main_menu.tscn"
const CALIBRATION_SCENE := "res://scenes/calibration.tscn"
const ROW_H := 48.0
const MESSAGE_SEC := 3.0
const ACTION_ROWS: Array[StringName] = [
	&"lane_1", &"lane_2", &"lane_3", &"lane_4", &"fire", &"target_cycle", &"pause",
]

var overlay: bool = false
## Scene changes go through this so tests can observe them. Default: SceneTree.change_scene_to_file.
var navigate: Callable = Callable()

var cells: Dictionary = {}  # "<action>:<device>" -> RebindCell
var scroll_slider: StepSlider
var master_slider: StepSlider
var music_slider: StepSlider
var sfx_slider: StepSlider
var early_late_button: Button
var no_fail_button: Button
var reduce_motion_button: Button
var reset_button: Button
var recalibrate_button: Button
var dialog: ConfirmDialog

var _messages: Dictionary = {}  # action -> Label
var _message_timers: Dictionary = {}  # action -> SceneTreeTimer
var _scroll_value_label: Label
var _volume_labels: Dictionary = {}
var _offsets_label: Label
var _sample_player: AudioStreamPlayer
var _first_focus: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if theme == null:
		theme = Palette.load_theme()
	_build()
	if _first_focus != null:
		_first_focus.grab_focus()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Palette.SP_3XL)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", Palette.SP_MD)
	scroll.add_child(root)

	root.add_child(_heading("SETTINGS"))
	_build_controls(root)
	_build_gameplay(root)
	_build_audio(root)
	_build_calibration(root)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(280.0, ROW_H)
	back.pressed.connect(back_pressed)
	root.add_child(back)

	_sample_player = AudioStreamPlayer.new()
	_sample_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	_sample_player.stream = AudioSynth.make_tick(1.0)
	add_child(_sample_player)
	_refresh_all()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	return l


func _build_controls(root: VBoxContainer) -> void:
	root.add_child(_heading("CONTROLS"))
	var head := HBoxContainer.new()
	head.add_child(_fixed_label("", 240.0))
	head.add_child(_fixed_label("KEYBOARD", 280.0))
	head.add_child(_fixed_label("GAMEPAD", 280.0))
	root.add_child(head)
	var store := Settings.bindings
	for action in ACTION_ROWS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", Palette.SP_XS)
		root.add_child(col)
		var row := HBoxContainer.new()
		col.add_child(row)
		var title: String = RebindCell.ACTION_NAMES[action]
		row.add_child(_fixed_label(title, 240.0))
		for device in [&"keyboard", &"gamepad"]:
			var cell := RebindCell.new()
			cell.setup(action, device, store)
			cell.message.connect(show_message)
			cell.bound.connect(_on_bound)
			row.add_child(cell)
			cells["%s:%s" % [action, device]] = cell
			if _first_focus == null:
				_first_focus = cell
		if action == &"fire" or action == &"target_cycle":
			var note := Label.new()
			note.text = "(Not active yet)"
			note.theme_type_variation = &"CaptionLabel"
			row.add_child(note)
		var msg := Label.new()
		msg.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
		msg.visible = false
		col.add_child(msg)
		_messages[action] = msg
	reset_button = Button.new()
	reset_button.text = "Reset Controls"
	reset_button.custom_minimum_size = Vector2(280.0, ROW_H)
	reset_button.pressed.connect(request_reset)
	root.add_child(reset_button)


func _build_gameplay(root: VBoxContainer) -> void:
	root.add_child(_heading("GAMEPLAY"))
	scroll_slider = StepSlider.new()
	scroll_slider.setup(Settings.SCROLL_MIN, Settings.SCROLL_MAX, 0.1, Settings.scroll_speed)
	scroll_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_scroll_speed(v)
		_refresh_all())
	_scroll_value_label = Label.new()
	root.add_child(_slider_row("Scroll speed", scroll_slider, _scroll_value_label))
	early_late_button = _toggle_row(root, "Early/late indicator", func() -> void:
		Settings.early_late_indicator = not Settings.early_late_indicator)
	no_fail_button = _toggle_row(root, "No-Fail", func() -> void:
		Settings.no_fail = not Settings.no_fail)
	reduce_motion_button = _toggle_row(root, "Reduce screen shake", func() -> void:
		Settings.reduce_motion = not Settings.reduce_motion)


func _build_audio(root: VBoxContainer) -> void:
	root.add_child(_heading("AUDIO"))
	master_slider = _volume_row(root, "Master", "Master", Settings.volume_master, true)
	music_slider = _volume_row(root, "Music", "Music", Settings.volume_music, false)
	sfx_slider = _volume_row(root, "SFX", "SFX", Settings.volume_sfx, true)


func _build_calibration(root: VBoxContainer) -> void:
	root.add_child(_heading("CALIBRATION"))
	_offsets_label = Label.new()
	root.add_child(_offsets_label)
	recalibrate_button = Button.new()
	recalibrate_button.text = "Re-run Calibration"
	recalibrate_button.custom_minimum_size = Vector2(360.0, ROW_H)
	recalibrate_button.pressed.connect(func() -> void: _go(CALIBRATION_SCENE))
	# A scene change would tear down the paused run, so the overlay never offers it.
	recalibrate_button.disabled = overlay
	root.add_child(recalibrate_button)


func _volume_row(root: VBoxContainer, title: String, bus: String, start: float, sample: bool) -> StepSlider:
	var s := StepSlider.new()
	s.setup(0.0, 100.0, 5.0, start * 100.0)
	var lbl := Label.new()
	_volume_labels[bus] = lbl
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(bus, v / 100.0)
		_refresh_all())
	if sample:
		s.released.connect(play_sample)
	root.add_child(_slider_row(title, s, lbl))
	return s


func _slider_row(title: String, slider: StepSlider, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_fixed_label(title, 360.0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	value_label.custom_minimum_size = Vector2(120.0, ROW_H)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _toggle_row(root: VBoxContainer, title: String, flip: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_child(_fixed_label(title, 360.0))
	var b := Button.new()
	b.custom_minimum_size = Vector2(200.0, ROW_H)
	b.pressed.connect(func() -> void:
		flip.call()
		Settings.save_to(Settings.save_path)
		Settings.settings_changed.emit()
		_refresh_all())
	row.add_child(b)
	root.add_child(row)
	return b


func _fixed_label(text: String, w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _refresh_all() -> void:
	if _scroll_value_label == null:
		return
	_scroll_value_label.text = "%.1fx" % Settings.scroll_speed
	_volume_labels["Master"].text = "%d%%" % roundi(Settings.volume_master * 100.0)
	_volume_labels["Music"].text = "%d%%" % roundi(Settings.volume_music * 100.0)
	_volume_labels["SFX"].text = "%d%%" % roundi(Settings.volume_sfx * 100.0)
	early_late_button.text = _on_off(Settings.early_late_indicator)
	no_fail_button.text = _on_off(Settings.no_fail)
	reduce_motion_button.text = _on_off(Settings.reduce_motion)
	_offsets_label.text = "Audio offset: %+d ms    Visual offset: %+d ms" % [
		roundi(Settings.audio_offset * 1000.0), roundi(Settings.visual_offset * 1000.0)]
	for c in cells.values():
		(c as RebindCell).refresh()


static func _on_off(v: bool) -> String:
	return "[ ON ]" if v else "[ OFF ]"


func play_sample() -> void:
	if _sample_player != null:
		_sample_player.play()


# --- rebinding -------------------------------------------------------------------------------


func _on_bound(action: StringName) -> void:
	clear_message(action)
	Settings.save_to(Settings.save_path)
	_refresh_all()


## Inline destructive-color message under the row; clears after 3 s or on the next input.
func show_message(action: StringName, text: String) -> void:
	var l: Label = _messages.get(action)
	if l == null:
		return
	l.text = "! " + text
	l.visible = true
	if is_inside_tree():
		var t := get_tree().create_timer(MESSAGE_SEC)
		_message_timers[action] = t
		t.timeout.connect(func() -> void:
			if _message_timers.get(action) == t:
				clear_message(action))


func clear_message(action: StringName) -> void:
	var l: Label = _messages.get(action)
	if l != null:
		l.visible = false
		l.text = ""
	_message_timers.erase(action)


func message_text(action: StringName) -> String:
	var l: Label = _messages.get(action)
	return l.text if l != null and l.visible else ""


func request_reset() -> void:
	if dialog != null:
		return
	dialog = ConfirmDialog.new()
	add_child(dialog)
	dialog.setup("RESET CONTROLS", "Restore the default keyboard and gamepad bindings?",
		"Reset Controls", "Keep Bindings")
	dialog.safe_button.grab_focus()
	dialog.cancelled.connect(func() -> void:
		_close_dialog()
		reset_button.grab_focus())
	dialog.confirmed.connect(func() -> void:
		_close_dialog()
		Settings.bindings.reset_defaults()
		Settings.save_to(Settings.save_path)
		for a in ACTION_ROWS:
			clear_message(a)
		_refresh_all()
		reset_button.grab_focus())


func _close_dialog() -> void:
	if dialog != null:
		dialog.queue_free()
		dialog = null


# --- navigation ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_pressed() and not (event is InputEventMouse):
		for a in ACTION_ROWS:
			clear_message(a)  # "or next input"
	if dialog == null and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed()


## Esc / B / Back button. Saves; overlay mode emits `closed`, full mode returns to the menu.
func back_pressed() -> void:
	for c in cells.values():
		if (c as RebindCell).listening:
			(c as RebindCell).cancel_listen()
	Settings.save_to(Settings.save_path)
	if overlay:
		closed.emit()
	else:
		_go(MENU_SCENE)


func _go(path: String) -> void:
	if overlay:
		return
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		get_tree().change_scene_to_file(path)
