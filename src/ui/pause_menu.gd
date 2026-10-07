class_name PauseMenu
extends Control
## Solo pause overlay (D-26, UI-SPEC Countdown and pause). Pausing freezes the Conductor and
## disables LaneInput; the SceneTree is never paused (Pitfall 8). Resume Dive runs a 3-beat
## 3-2-1 countdown at the chart BPM, then audio restarts from the paused position and lane
## input comes back. Settings opens as a CanvasLayer overlay over the paused run (no scene
## change) and is freed when it emits `closed`.

signal restart_confirmed
signal menu_confirmed

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const OVERLAY_LAYER := 100
const COUNTDOWN_BEATS := 3
const TICK_SCALE_FROM := 1.2
const TICK_SCALE_SEC := 0.15
const TICK_FADE_SEC := 0.5

var conductor: Conductor
var lane_input: LaneInput
var score: HullScore
## False in autoplay runs: the player never has live lane input there.
var restore_input: bool = true

var resume_button: Button
var restart_button: Button
var settings_button: Button
var menu_button: Button

var _panel_root: Control
var _countdown_label: Label
var _dialog: ConfirmDialog
var _overlay: CanvasLayer
var _counting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null:
		theme = Palette.load_theme()
	_build()


func setup(p_conductor: Conductor, p_lane_input: LaneInput, p_score: HullScore) -> void:
	conductor = p_conductor
	lane_input = p_lane_input
	score = p_score
	conductor.countdown_tick.connect(_on_countdown_tick)
	conductor.resumed.connect(_on_resumed)


## True while the pause panel is showing (not during the countdown).
func is_open() -> bool:
	return _panel_root != null and _panel_root.visible


func is_counting_down() -> bool:
	return _counting


func has_settings_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func open() -> void:
	if is_open() or _counting or conductor == null:
		return
	conductor.pause()
	lane_input.enabled = false
	_panel_root.visible = true
	resume_button.grab_focus()


func resume_dive() -> void:
	if not is_open():
		return
	_panel_root.visible = false
	_counting = true
	conductor.resume(COUNTDOWN_BEATS)


func request_restart() -> void:
	if score != null and score.score > 0:
		_show_dialog("RESTART", "Restart this dive from the beginning? Your progress will be lost.",
			"Restart Dive", "Keep Playing", restart_button, func() -> void: restart_confirmed.emit())
	else:
		restart_confirmed.emit()


func request_menu() -> void:
	_show_dialog("BACK TO MENU", "Leave this dive? Your progress will be lost.",
		"Leave Dive", "Stay", menu_button, func() -> void: menu_confirmed.emit())


## Settings entry: instantiate the Settings scene into a CanvasLayer over the paused run.
func open_settings() -> void:
	if has_settings_overlay() or not ResourceLoader.exists(SETTINGS_SCENE):
		return
	var packed := load(SETTINGS_SCENE) as PackedScene
	if packed == null:
		return
	open_settings_with(packed.instantiate())


## Overlay code path (also used by tests with a stub that has a `closed` signal).
func open_settings_with(screen: Node) -> void:
	if has_settings_overlay():
		screen.queue_free()
		return
	if "overlay" in screen:
		screen.set("overlay", true)
	_overlay = CanvasLayer.new()
	_overlay.layer = OVERLAY_LAYER
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(screen)
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(_overlay)
	_panel_root.visible = false
	screen.connect("closed", _on_settings_closed)


func _on_settings_closed() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_panel_root.visible = true
	settings_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		return
	if _counting:
		get_viewport().set_input_as_handled()  # Esc is ignored during the countdown
		return
	if is_open() and _dialog == null and not has_settings_overlay():
		get_viewport().set_input_as_handled()
		resume_dive()


func _on_countdown_tick(n: int) -> void:
	if not _counting:
		return
	_countdown_label.text = str(n)
	_countdown_label.visible = true
	_countdown_label.modulate.a = 1.0
	_countdown_label.scale = Vector2.ONE
	if not is_inside_tree():
		return
	var tw := create_tween().set_parallel(true)
	if not Settings.reduce_motion:
		_countdown_label.scale = Vector2(TICK_SCALE_FROM, TICK_SCALE_FROM)
		tw.tween_property(_countdown_label, "scale", Vector2.ONE, TICK_SCALE_SEC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown_label, "modulate:a", 0.0, TICK_FADE_SEC).set_delay(TICK_SCALE_SEC)


func _on_resumed() -> void:
	if not _counting:
		return
	_counting = false
	_countdown_label.visible = false
	if restore_input:
		lane_input.enabled = true


func _show_dialog(title: String, body: String, confirm_text: String, safe_text: String,
		return_focus: Button, on_confirm: Callable) -> void:
	if _dialog != null:
		return
	_dialog = ConfirmDialog.new()
	add_child(_dialog)
	_dialog.setup(title, body, confirm_text, safe_text)
	_dialog.safe_button.grab_focus()
	_dialog.cancelled.connect(func() -> void:
		_close_dialog()
		return_focus.grab_focus())
	_dialog.confirmed.connect(func() -> void:
		_close_dialog()
		on_confirm.call())


func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


func _build() -> void:
	_panel_root = Control.new()
	UiLayout.fill_rect(_panel_root)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.visible = false
	add_child(_panel_root)
	var dim := ColorRect.new()
	dim.color = Palette.alpha(Palette.BG, 0.7)
	UiLayout.fill_rect(dim)
	_panel_root.add_child(dim)
	var center := CenterContainer.new()
	UiLayout.fill_rect(center)
	_panel_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_MD)
	center.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	resume_button = _button(box, "Resume Dive", resume_dive)
	restart_button = _button(box, "Restart Dive", request_restart)
	settings_button = _button(box, "Settings", open_settings)
	menu_button = _button(box, "Back to Menu", request_menu)
	var buttons := [resume_button, restart_button, settings_button, menu_button]
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i + buttons.size() - 1) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = &"DisplayLabel"
	_countdown_label.add_theme_color_override("font_color", Palette.ACCENT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.size = Vector2(240.0, 160.0)
	_countdown_label.position = Vector2((Highway.SCREEN_W - 240.0) * 0.5, 360.0)
	_countdown_label.pivot_offset = Vector2(120.0, 80.0)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	add_child(_countdown_label)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320.0, 56.0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
