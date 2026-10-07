class_name ConfirmDialog
extends Control
## Modal destructive confirmation (UI-SPEC): panel with a 4px destructive top border, Heading
## title, Body text, initial focus on the SAFE button, Esc/B (ui_cancel) = the safe choice.
## Used for "Leave Dive"/"Stay" and "Restart Dive"/"Keep Playing".

signal confirmed
signal cancelled

var confirm_button: Button
var safe_button: Button


## Build the dialog. Call before or after add_child.
func setup(title: String, body: String, confirm_text: String, safe_text: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiLayout.fill_rect(self)
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
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.border_color = Palette.DESTRUCTIVE
	sb.border_width_top = 4
	sb.content_margin_left = Palette.SP_XL
	sb.content_margin_right = Palette.SP_XL
	sb.content_margin_top = Palette.SP_XL
	sb.content_margin_bottom = Palette.SP_XL
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(720.0, 0.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_MD)
	panel.add_child(box)
	var h := Label.new()
	h.text = title
	h.theme_type_variation = &"HeadingLabel"
	box.add_child(h)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.SP_MD)
	box.add_child(row)
	confirm_button = Button.new()
	confirm_button.text = confirm_text
	confirm_button.custom_minimum_size = Vector2(280.0, 56.0)
	confirm_button.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
	confirm_button.pressed.connect(_on_confirm)
	row.add_child(confirm_button)
	safe_button = Button.new()
	safe_button.text = safe_text
	safe_button.custom_minimum_size = Vector2(280.0, 56.0)
	safe_button.pressed.connect(_on_cancel)
	row.add_child(safe_button)
	# Real modal focus (WR-05): every direction (and Tab order) stays inside the dialog, so
	# the controls behind the dim cannot be reached with the keyboard or gamepad.
	var to_safe := confirm_button.get_path_to(safe_button)
	var to_confirm := safe_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_left = confirm_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_right = to_safe
	confirm_button.focus_neighbor_top = confirm_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_bottom = confirm_button.get_path_to(confirm_button)
	confirm_button.focus_next = to_safe
	confirm_button.focus_previous = to_safe
	safe_button.focus_neighbor_left = to_confirm
	safe_button.focus_neighbor_right = safe_button.get_path_to(safe_button)
	safe_button.focus_neighbor_top = safe_button.get_path_to(safe_button)
	safe_button.focus_neighbor_bottom = safe_button.get_path_to(safe_button)
	safe_button.focus_next = to_confirm
	safe_button.focus_previous = to_confirm
	if is_inside_tree():
		safe_button.grab_focus()


func _ready() -> void:
	if safe_button != null:
		safe_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel()


func _on_confirm() -> void:
	confirmed.emit()


func _on_cancel() -> void:
	cancelled.emit()
