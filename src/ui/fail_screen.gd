class_name FailScreen
extends Control
## IMPLOSION panel (D-15, UI-SPEC Fail screen): fades in after the highway squash, Display-size
## IMPLOSION in destructive color, "Hull breached at {depth} m.", Retry Dive (initial focus)
## and Back to Menu.

signal retry_pressed
signal menu_pressed

const SQUASH_SEC := 0.4
const FADE_SEC := 0.3

var retry_button: Button
var menu_button: Button
var title_label: Label
var body_label: Label


func setup(depth_m: float) -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	var dim := ColorRect.new()
	dim.color = Palette.alpha(Palette.BG, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UiLayout.fill_rect(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_LG)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	title_label = Label.new()
	title_label.text = "IMPLOSION"
	title_label.theme_type_variation = &"DisplayLabel"
	title_label.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	body_label = Label.new()
	body_label.text = "Hull breached at %d m." % int(depth_m)
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body_label)
	retry_button = Button.new()
	retry_button.text = "Retry Dive"
	retry_button.custom_minimum_size = Vector2(320.0, 56.0)
	retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	box.add_child(retry_button)
	menu_button = Button.new()
	menu_button.text = "Back to Menu"
	menu_button.custom_minimum_size = Vector2(320.0, 56.0)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(menu_button)
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(menu_button)
	menu_button.focus_neighbor_top = menu_button.get_path_to(retry_button)


## Fade the panel in over 300 ms after `delay` seconds (the highway squash).
func play(delay: float = SQUASH_SEC) -> void:
	modulate.a = 0.0
	if is_inside_tree():
		# Inert until visible (WR-06): a mashed Space/Enter must not hit an invisible Retry.
		retry_button.disabled = true
		menu_button.disabled = true
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(self, "modulate:a", 1.0, FADE_SEC)
		tw.tween_callback(func() -> void:
			retry_button.disabled = false
			menu_button.disabled = false
			retry_button.grab_focus())
	else:
		modulate.a = 1.0
