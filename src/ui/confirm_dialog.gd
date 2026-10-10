class_name ConfirmDialog
extends Control
## Modal destructive confirmation (02.2 UI-SPEC 9.6): ABYSS_900 70% backdrop, a danger glass
## panel x 600..1320 y 380..700 with a Heading title and a Body text wrapping in 656 px, and
## two 304x64 buttons at y 604 (confirm = destructive variant at x 632, safe at x 984).
## Initial focus on the SAFE button; Esc/B (ui_cancel) = the safe choice.
## Used for "Leave Dive"/"Stay", "Restart Dive"/"Keep Playing" and Reset Controls.

signal confirmed
signal cancelled

const DIM_ALPHA := 0.7
const PANEL_RECT := Rect2(600, 380, 720, 320)
const TITLE_AT := Vector2(632, 444)  # baseline
const RULE_Y := 460.0  # header divider 16 px under the title baseline
const BODY_AT := Vector2(632, 500)  # first baseline
const BODY_W := 656.0
const BUTTON_SIZE := Vector2(304, 64)
const CONFIRM_POS := Vector2(632, 604)
const SAFE_POS := Vector2(984, 604)
const RULE_ALPHA := 0.35
const BRACKET_ALPHA := 0.8

var confirm_button: Button
var safe_button: Button
var panel: Control
var title_label: Label
var body_label: Label


## Draws through a callable (the panel).
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## Build the dialog. Call before or after add_child.
func setup(title: String, body: String, confirm_text: String, safe_text: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.ABYSS_900, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	var sb := UiKit.style_panel("danger")
	sb.shadow_color = Color(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)
	panel = Painter.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.painter = func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, Color(Palette.WARNING_RED, BRACKET_ALPHA))
		var y := RULE_Y - PANEL_RECT.position.y
		var x0 := TITLE_AT.x - PANEL_RECT.position.x
		ci.draw_line(Vector2(x0, y), Vector2(x0 + BODY_W, y), Color(Palette.WARNING_RED, RULE_ALPHA), Palette.EDGE)
	add_child(panel)
	var hf := Palette.display_font()
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.add_theme_font_override("font", hf)
	title_label.add_theme_font_size_override("font_size", Palette.SIZE_HEADING)
	title_label.add_theme_color_override("font_color", Palette.TEXT_HI)
	title_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.clip_text = true
	title_label.position = Vector2(TITLE_AT.x, TITLE_AT.y - hf.get_ascent(Palette.SIZE_HEADING))
	title_label.size = Vector2(BODY_W, hf.get_height(Palette.SIZE_HEADING))
	add_child(title_label)
	var bf := Palette.font()
	body_label = Label.new()
	body_label.name = "Body"
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_override("font", bf)
	body_label.add_theme_font_size_override("font_size", Palette.SIZE_BODY)
	body_label.add_theme_color_override("font_color", Palette.TEXT_MID)
	body_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_label.position = Vector2(BODY_AT.x, BODY_AT.y - bf.get_ascent(Palette.SIZE_BODY))
	body_label.custom_minimum_size = Vector2(BODY_W, 0)
	body_label.size = Vector2(BODY_W, CONFIRM_POS.y - Palette.SP_MD - body_label.position.y)
	add_child(body_label)
	confirm_button = UiKit.make_button(confirm_text, "", "destructive", int(BUTTON_SIZE.y))
	confirm_button.name = "Confirm"
	confirm_button.position = CONFIRM_POS
	confirm_button.size = BUTTON_SIZE
	confirm_button.pressed.connect(_on_confirm)
	add_child(confirm_button)
	safe_button = UiKit.make_button(safe_text, "", "default", int(BUTTON_SIZE.y))
	safe_button.name = "Safe"
	safe_button.position = SAFE_POS
	safe_button.size = BUTTON_SIZE
	safe_button.pressed.connect(_on_cancel)
	add_child(safe_button)
	var marker := FocusMarker.new()
	marker.name = "FocusMarker"
	add_child(marker)
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
