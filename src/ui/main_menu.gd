class_name MainMenu
extends Control
## Entry screen (UI-SPEC): Start Dive, autoplay entry, Calibrate Sonar, Settings, Quit Game.
## First launch (Settings.calibration_done false) routes straight to the skippable wizard once per
## session; an output-device change since the last calibration shows the re-calibrate prompt.

const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const CALIBRATION_SCENE := "res://scenes/calibration.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const DEVICE_CHANGED_COPY := "Output device changed. Calibrate Sonar again for accurate timing."
const NOT_CALIBRATED_BODY := "Timing may feel off until you calibrate. Choose Calibrate Sonar to fix it."

## True once the first-launch redirect was taken or skipped this session.
static var boot_handled: bool = false

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()

var start_button: Button
var autoplay_button: Button
var calibrate_button: Button
var settings_button: Button
var quit_button: Button
var prompt_calibrate_button: Button
var prompt_skip_button: Button

var _prompt: Control
var _empty_state: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	autoplay_button = _item(box, "Autoplay Dive (test)", func() -> void: launch(true))
	calibrate_button = _item(box, "Calibrate Sonar", func() -> void: _go(CALIBRATION_SCENE))
	settings_button = _item(box, "Settings", func() -> void: _go(SETTINGS_SCENE))
	quit_button = _item(box, "Quit Game", func() -> void:
		if is_inside_tree():
			get_tree().quit())
	var items := [start_button, autoplay_button, calibrate_button, settings_button, quit_button]
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


func launch(autoplay: bool) -> void:
	Gameplay.pending_chart = TestCharts.hand_chart()
	Gameplay.pending_autoplay = autoplay
	_go(GAMEPLAY_SCENE)


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		get_tree().change_scene_to_file(path)
