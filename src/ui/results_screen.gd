class_name ResultsScreen
extends Control
## "DIVE COMPLETE" results (UI-SPEC): Depth, Max combo, Perfect, Good, Miss, Final hull rows
## plus NO-FAIL USED / AUTOPLAY USED flag rows, Retry Dive (initial focus) and Back to Menu.

signal retry_pressed
signal menu_pressed

var retry_button: Button
var menu_button: Button
## Flag row texts shown, e.g. "NO-FAIL USED", "AUTOPLAY USED".
var flags: Array[String] = []
## [label, value text] pairs in display order.
var rows: Array[Array] = []


## NEW RECORD banner node (null unless the run set a record).
var record_banner: Label
var note_label: Label


func setup(score: HullScore, autoplay_used: bool, record_info: Dictionary = {},
		practice: bool = false) -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	var dim := ColorRect.new()
	dim.color = Palette.alpha(Palette.BG, 0.85)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UiLayout.fill_rect(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_SM)
	box.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(box)
	var title := Label.new()
	title.text = "DIVE COMPLETE"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_color_override("font_color", Palette.ACCENT)
	box.add_child(title)
	var is_record: bool = record_info.get("new_record", false)
	var eligible: bool = record_info.get("eligible", true)
	if is_record:
		box.add_child(_bar())
		record_banner = Label.new()
		record_banner.text = "NEW RECORD"
		record_banner.theme_type_variation = &"HeadingLabel"
		record_banner.add_theme_color_override("font_color", Palette.ACCENT)
		record_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(record_banner)
		box.add_child(_bar())
		if not Settings.reduce_motion and is_inside_tree():
			record_banner.modulate.a = 0.0
			create_tween().tween_property(record_banner, "modulate:a", 1.0, 0.3)
	rows = [
		["Depth", "%d m" % int(score.depth())],
		["Max combo", str(score.max_combo)],
		["Perfect", str(score.perfect_count)],
		["Good", str(score.good_count)],
		["Miss", str(score.miss_count)],
		["Final hull", "%d%%" % int(round(score.hull))],
	]
	if is_record:
		var prev: float = record_info.get("previous_depth", -1.0)
		rows.append(["Previous best", "%s m" % Palette.fmt_depth(int(prev)) if prev >= 0.0 else "none"])
	for r in rows:
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = r[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(k)
		var v := Label.new()
		v.text = r[1]
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		box.add_child(row)
	flags.clear()
	if score.no_fail_used:
		flags.append("NO-FAIL USED")
	if autoplay_used:
		flags.append("AUTOPLAY USED")
	if practice:
		flags.append("PRACTICE DIVE")
	for f in flags:
		var fl := Label.new()
		fl.text = f
		fl.add_theme_color_override("font_color", Palette.TEXT)
		box.add_child(fl)
	if not record_info.is_empty():
		var best_d: float = record_info.get("best_depth", -1.0)
		note_label = Label.new()
		note_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		if not eligible:
			note_label.text = "Not recorded. Practice, Autoplay and No-Fail dives do not set records."
		elif not is_record and best_d >= 0.0:
			note_label.text = "Best: %s m" % Palette.fmt_depth(int(best_d))
		if note_label.text != "":
			box.add_child(note_label)
		else:
			note_label.free()
			note_label = null
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, Palette.SP_MD)
	box.add_child(spacer)
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
	if is_inside_tree():
		retry_button.grab_focus()


func _bar() -> ColorRect:
	var b := ColorRect.new()
	b.color = Palette.ACCENT
	b.custom_minimum_size = Vector2(120.0, 2.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _ready() -> void:
	if retry_button != null:
		retry_button.grab_focus()
