class_name SettingsScreen
extends Control
## Settings (UI-SPEC): Controls rebind table, Gameplay, Display, Audio, Library and Calibration
## sections in one scrollable list. Runs as a full scene (Back returns to the main menu) or, with
## `overlay = true` (set by the pause menu), as an overlay: Back saves, emits `closed` and never
## changes scene. Changes apply live through Settings and are saved on exit.
##
## 02.2 restyle (UI-SPEC 9.3): the table AbyssBackdrop (overlay mode: an opaque ABYSS_900 85%
## shade instead, no backdrop), "SETTINGS" Heading 40 at (64, 104), each section in a glass panel
## x 64..1856 with a Heading 40 header and a 2 px SONAR 35% rule, 56 px rows (label Body 28
## TEXT_MID at x 96, controls from x 440, hints Label 20 TEXT_LO), pill toggles ON/OFF, restyled
## StepSlider / RebindCell, a 4 px scrollbar and one FocusMarker. Effect node (UiKit contract):
## Low effects drops the panel glow; Reduce motion makes toggle knobs jump and rebind edges static.

signal closed

const MENU_SCENE := "res://scenes/main_menu.tscn"
const CALIBRATION_SCENE := "res://scenes/calibration.tscn"
const ROW_H := 56.0
const BUTTON_H := 48.0
const MESSAGE_SEC := 3.0
const ERR_DUPLICATE := "That folder is already in the list."
const ERR_MISSING := "That folder does not exist. Pick an existing folder."
const ERR_FULL := "You can add up to 8 library folders."
const ERR_SONGS_DIR := "That is the Songs folder. It is always scanned already."
const ACTION_ROWS: Array[StringName] = [
	&"lane_1", &"lane_2", &"lane_3", &"lane_4", &"fire", &"target_cycle", &"pause",
]

## Layout (UI-SPEC 9.3), 1920 x 1080 design pixels.
const TITLE_POS := Vector2(64.0, 104.0)  # "SETTINGS" baseline
const HINT_RIGHT := 1856.0  # "ESC BACK" right edge, on the title baseline
const PANEL_X0 := 64.0
const PANEL_X1 := 1856.0
const LABEL_X := 96.0
const CONTROL_X := 440.0
const VALUE_RIGHT := 1840.0
const VALUE_W := 120.0
const SCROLL_RECT := Rect2(40.0, 136.0, 1840.0, 920.0)
const SCROLL_PAD_L := PANEL_X0 - 40.0  # 24: room for the panel glow
const SCROLLBAR_W := 4.0
const ROW_GAP := Palette.SP_MD
const SECTION_GAP := Palette.SP_XL
const SHADE_ALPHA := 0.85
const RULE_ALPHA := 0.35
const HEADER_H := 64.0  # Heading 40 + rule 16 px under its baseline + gap

const HINT_REDUCE_MOTION := "Turns off screen shake, parallax and big movement. Effects fade instead of moving."
const HINT_LOW_EFFECTS := "Fewer particles, no glow or CRT effect, simpler backgrounds. Notes and lanes stay fully bright."
const HINT_MENU_MUSIC := "Plays a quiet song preview on the main menu."
const HINT_FULLSCREEN := "F11 toggles fullscreen at any time."
const HINT_BACKGROUND := "Calm: still trench walls, soft glow on the beat. Living: walls move and pulse with the music."
## Background value button width (fits "LIVING" in the button font with padding).
const BACKGROUND_BUTTON_W := 200.0


## Pill toggle (UI-SPEC 9.3): 160 x 40, CUT_SM chamfer. ON = SONAR 22% fill, SONAR edge, "ON"
## TEXT_HI, knob right; OFF = ABYSS_800 fill, TEXT_LO 35% edge, "OFF" TEXT_MID, knob left. The
## knob slides over DUR_FAST, or jumps under Reduce motion. `text` holds "ON"/"OFF" (the theme
## text is hidden and redrawn here so it sits beside the knob).
class PillToggle:
	extends Button

	const SIZE := Vector2(160.0, 40.0)
	const KNOB := Vector2(16.0, 24.0)
	const KNOB_INSET := 16.0  # clear of the FocusMarker bar at x+8

	var is_on := false
	var knob_t := 0.0:
		set(v):
			knob_t = v
			queue_redraw()
	var _tween: Tween

	func _init() -> void:
		custom_minimum_size = SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		focus_mode = Control.FOCUS_ALL
		text = "OFF"
		var empty := StyleBoxEmpty.new()
		for st in UiKit.BUTTON_STATES:
			add_theme_stylebox_override(st, empty)
		add_theme_stylebox_override("focus", empty)
		for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color", "font_disabled_color"]:
			add_theme_color_override(k, Color(Palette.TEXT_HI, 0.0))
		for sig: Signal in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
			sig.connect(queue_redraw)

	## {fill, edge, text} for the ON / OFF state.
	static func style_for(on: bool) -> Dictionary:
		if on:
			return {"fill": Color(Palette.SONAR, 0.22), "edge": Palette.SONAR, "text": Palette.TEXT_HI,
				"knob": Palette.TEXT_HI}
		return {"fill": Palette.ABYSS_800, "edge": Color(Palette.TEXT_LO, 0.35), "text": Palette.TEXT_MID,
			"knob": Palette.TEXT_MID}

	## Knob rect inside the 160 x 40 pill at slide position t (0 = left, 1 = right).
	static func knob_rect(t: float) -> Rect2:
		var x := lerpf(KNOB_INSET, SIZE.x - KNOB_INSET - KNOB.x, clampf(t, 0.0, 1.0))
		return Rect2(Vector2(x, (SIZE.y - KNOB.y) * 0.5), KNOB)

	## Sets the state; the knob slides (DUR_FAST, cubic out) when `animate` and Reduce motion
	## is off, else jumps. Same state = no-op.
	func set_on(v: bool, animate: bool = true) -> void:
		var changed := v != is_on or text != ("ON" if v else "OFF")
		is_on = v
		text = "ON" if v else "OFF"
		if not changed and (_tween == null or not _tween.is_running()):
			knob_t = 1.0 if v else 0.0
			return
		if _tween != null:
			_tween.kill()
			_tween = null
		var goal := 1.0 if v else 0.0
		if animate and not UiKit.reduce_motion() and is_inside_tree():
			_tween = create_tween()
			_tween.tween_property(self, "knob_t", goal, Palette.DUR_FAST) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			knob_t = goal
		queue_redraw()

	func _draw() -> void:
		var st := style_for(is_on)
		var oy := (size.y - SIZE.y) * 0.5
		var r := Rect2(Vector2(0.0, oy), SIZE)
		var pts := UiKit.chamfer_points(r, Palette.CUT_SM)
		var edge: Color = st.edge
		if has_focus():
			edge = Palette.SONAR
			if not UiKit.low_effects():
				for g: Array in [[12.0, 0.08], [6.0, 0.16]]:
					var gp := UiKit.chamfer_points(r.grow(g[0] * 0.5), Palette.CUT_SM + g[0] * 0.25)
					draw_colored_polygon(gp, Color(Palette.SONAR, g[1]))
				draw_colored_polygon(pts, Palette.ABYSS_900)
		elif is_hovered():
			edge = Color(edge, minf(edge.a + 0.3, 1.0))
		draw_colored_polygon(pts, st.fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, edge, Palette.EDGE, true)
		var kr := knob_rect(knob_t)
		kr.position.y += oy
		var kc: Color = Palette.mix(Palette.TEXT_MID, Palette.TEXT_HI, knob_t)
		draw_colored_polygon(UiKit.chamfer_points(kr, 4.0), kc)
		# Label in the half the knob is not in.
		var f := UiKit.chip_font()
		var fs := Palette.SIZE_LABEL
		var label := "ON" if is_on else "OFF"
		var area := Rect2(0.0, oy, SIZE.x - KNOB_INSET - KNOB.x, SIZE.y) if is_on \
			else Rect2(KNOB_INSET + KNOB.x, oy, SIZE.x - KNOB_INSET - KNOB.x, SIZE.y)
		var base := oy + SIZE.y * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(area.position.x, base), label, HORIZONTAL_ALIGNMENT_CENTER,
			area.size.x, fs, st.text)


var overlay: bool = false
## Scene changes go through this so tests can observe them. Default: the ScreenTransition sonar wipe.
var navigate: Callable = Callable()

var cells: Dictionary = {}  # "<action>:<device>" -> RebindCell
var scroll_slider: StepSlider
var master_slider: StepSlider
var music_slider: StepSlider
var sfx_slider: StepSlider
var early_late_button: Button
var no_fail_button: Button
var reduce_motion_button: Button
var fullscreen_button: Button
var low_effects_button: Button
## 02.2-27 (gap G2): Display > Background value button (CALM / LIVING).
var background_button: Button
var menu_music_button: Button
var reset_button: Button
var recalibrate_button: Button
var back_button: Button
var dialog: ConfirmDialog
## Library section (D-06). `library` defaults to the SongLibrary autoload; tests inject a fake.
var library: Node = null
## Test seam: when valid, Add Folder calls this instead of opening any OS/Godot dialog.
var folder_picker: Callable = Callable()
var add_folder_button: Button
var open_songs_button: Button
var library_rows: VBoxContainer
var songs_folder_label: Label
var library_message: Label

## Restyle nodes (02.2-21).
var backdrop: AbyssBackdrop
var shade: ColorRect
var title_label: Label
var focus_marker: FocusMarker
var scroll: ScrollContainer
var scroll_value_label: Label
var section_panels: Array[PanelContainer] = []

var _messages: Dictionary = {}  # action -> Label
var _message_timers: Dictionary = {}  # action -> SceneTreeTimer
var _volume_labels: Dictionary = {}
var _offsets_label: Label
var _sample_player: AudioStreamPlayer
var _first_focus: Control
var _folders_at_open: Array[String] = []
var _library_timer: SceneTreeTimer
var _folder_dialog: FileDialog
var _row_titles: Array[String] = []
var _hints: Dictionary = {}  # row title -> hint text
var _toggles: Array[PillToggle] = []
var _low := false


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	_build()
	UiKit.register_fx(self)
	if _first_focus != null:
		_first_focus.grab_focus()


func _build() -> void:
	if library == null:
		library = SongLibrary
	_folders_at_open = Settings.library_folders.duplicate()
	_low = UiKit.low_effects()
	if overlay:
		# Over the frozen run: opaque enough that the board does not compete (no backdrop scene).
		shade = ColorRect.new()
		shade.name = "Shade"
		shade.color = Color(Palette.ABYSS_900, SHADE_ALPHA)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		UiLayout.fill_rect(shade)
		add_child(shade)
	else:
		backdrop = AbyssBackdrop.new()
		backdrop.name = "Backdrop"
		backdrop.variant = "table"
		UiLayout.fill_rect(backdrop)
		add_child(backdrop)

	title_label = _heading("SETTINGS")
	title_label.name = "Title"
	var hf := Palette.display_font()
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
	add_child(esc)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = SCROLL_RECT.position
	scroll.size = SCROLL_RECT.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	_style_scrollbar(scroll.get_v_scroll_bar())
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", int(SCROLL_PAD_L))
	pad.add_theme_constant_override("margin_right", int(SCROLL_RECT.end.x - SCROLLBAR_W - PANEL_X1))
	pad.add_theme_constant_override("margin_top", Palette.SP_MD)
	pad.add_theme_constant_override("margin_bottom", Palette.SP_XL)
	scroll.add_child(pad)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", int(SECTION_GAP))
	pad.add_child(root)

	_build_controls(_section(root, "CONTROLS"))
	_build_gameplay(_section(root, "GAMEPLAY"))
	_build_display(_section(root, "DISPLAY"))
	_build_audio(_section(root, "AUDIO"))
	_build_library(_section(root, "LIBRARY"))
	_build_calibration(_section(root, "CALIBRATION"))

	back_button = _compact_button("Back", 280.0)
	back_button.pressed.connect(back_pressed)
	var back_row := HBoxContainer.new()
	back_row.add_child(back_button)
	root.add_child(back_row)

	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)

	_sample_player = AudioStreamPlayer.new()
	_sample_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	_sample_player.stream = AudioSynth.make_tick(1.0)
	add_child(_sample_player)
	_refresh_all(false)
	Settings.settings_changed.connect(_refresh_all)


func _exit_tree() -> void:
	if Settings.settings_changed.is_connected(_refresh_all):
		Settings.settings_changed.disconnect(_refresh_all)


# --- effect contract -------------------------------------------------------------------------


## Effect contract: Low effects drops the panel glow; the toggles, sliders and rebind cells read
## Reduce motion / Low effects when they animate or draw.
func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	for p in section_panels:
		p.add_theme_stylebox_override("panel", _panel_style())
		p.queue_redraw()
	for t in _toggles:
		t.queue_redraw()


func effect_counts() -> Dictionary:
	var rm := UiKit.reduce_motion()
	return {"panel_glow": not _low, "knob_slide": not rm, "listen_pulse": not rm, "slider_glow": not _low}


# --- building blocks -------------------------------------------------------------------------


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	return l


func _panel_style() -> StyleBoxFlat:
	var sb := UiKit.style_panel("default", _low)
	sb.content_margin_left = LABEL_X - PANEL_X0
	sb.content_margin_right = PANEL_X1 - VALUE_RIGHT
	sb.content_margin_top = Palette.SP_LG
	sb.content_margin_bottom = Palette.SP_LG
	return sb


## A glass section panel (x 64..1856) with its Heading 40 header and SONAR 35% rule; returns the
## VBox the rows go into.
func _section(root: VBoxContainer, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = title.capitalize().replace(" ", "") + "Section"
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.draw.connect(func() -> void:
		UiKit.draw_brackets(panel, Rect2(Vector2.ZERO, panel.size), Color(Palette.SONAR, 0.8)))
	root.add_child(panel)
	section_panels.append(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var head := Control.new()
	head.custom_minimum_size = Vector2(0.0, HEADER_H)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := _heading(title)
	var hf := Palette.display_font()
	hl.position = Vector2(0.0, 0.0)
	head.add_child(hl)
	var base := hf.get_ascent(Palette.SIZE_HEADING)
	head.draw.connect(func() -> void:
		var y := base + Palette.SP_MD
		head.draw_line(Vector2(0.0, y), Vector2(head.size.x, y), Color(Palette.SONAR, RULE_ALPHA), Palette.EDGE))
	box.add_child(head)
	return box


## Compact (48 px) theme button.
func _compact_button(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, BUTTON_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.button_down.connect(func() -> void: UiKit.press_squash(b))
	return b


## A 56 px row: label (Body 28 TEXT_MID at x 96) then the controls from x 440.
func _row(box: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_H)
	row.add_theme_constant_override("separation", int(ROW_GAP))
	row.add_child(_row_label(title))
	box.add_child(row)
	if title != "":
		_row_titles.append(title)
	return row


func _row_label(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(CONTROL_X - LABEL_X - ROW_GAP, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	return l


## Label 20 TEXT_LO hint.
func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"CaptionLabel"
	l.add_theme_color_override("font_color", Palette.TEXT_LO)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## MarginContainer indenting its child to the control column (the theme's 32 px margins are
## zeroed on the other sides).
func _indent(bottom: int = 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(CONTROL_X - LABEL_X))
	m.add_theme_constant_override("margin_right", 0)
	m.add_theme_constant_override("margin_top", 0)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m


## A full-width hint line under rows, indented to the control column.
func _hint_line(box: VBoxContainer, text: String) -> Label:
	var m := _indent(Palette.SP_XS)
	var l := _hint(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(l)
	box.add_child(m)
	return l


func _style_scrollbar(bar: VScrollBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(Palette.TEXT_LO, 0.25)
	track.content_margin_left = SCROLLBAR_W * 0.5
	track.content_margin_right = SCROLLBAR_W * 0.5
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Palette.SONAR
	thumb.content_margin_left = SCROLLBAR_W * 0.5
	thumb.content_margin_right = SCROLLBAR_W * 0.5
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(k, thumb)
	bar.custom_minimum_size = Vector2(SCROLLBAR_W, 0.0)


## Row titles in build order (tests).
func row_titles() -> Array[String]:
	return _row_titles.duplicate()


## The hint shown with a row ("" when none).
func hint_for(title: String) -> String:
	return String(_hints.get(title, ""))


# --- sections --------------------------------------------------------------------------------


func _build_controls(box: VBoxContainer) -> void:
	var head := _row(box, "")
	head.custom_minimum_size = Vector2(0.0, Palette.SP_XL)
	for t in ["KEYBOARD", "GAMEPAD"]:
		var c := _hint(t)
		c.autowrap_mode = TextServer.AUTOWRAP_OFF
		c.custom_minimum_size = Vector2(280.0, Palette.SP_XL)
		head.add_child(c)
	var store := Settings.bindings
	for action in ACTION_ROWS:
		var title: String = RebindCell.ACTION_NAMES[action]
		var row := _row(box, title)
		for device in [&"keyboard", &"gamepad"]:
			var cell := RebindCell.new()
			cell.setup(action, device, store)
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.message.connect(show_message)
			cell.bound.connect(_on_bound)
			row.add_child(cell)
			cells["%s:%s" % [action, device]] = cell
			if _first_focus == null:
				_first_focus = cell
		if action == &"fire" or action == &"target_cycle":
			var na := _hint("(Not active yet)")
			na.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(na)
		var m := _indent(Palette.SP_XS)
		var msg := Label.new()
		msg.theme_type_variation = &"CaptionLabel"
		msg.add_theme_color_override("font_color", Palette.WARNING_RED)
		msg.visible = false
		m.add_child(msg)
		box.add_child(m)
		_messages[action] = msg
	reset_button = _compact_button("Reset Controls", 280.0)
	reset_button.pressed.connect(request_reset)
	_row(box, "").add_child(reset_button)


func _build_gameplay(box: VBoxContainer) -> void:
	scroll_slider = StepSlider.new()
	scroll_slider.setup(Settings.SCROLL_MIN, Settings.SCROLL_MAX, 0.1, Settings.scroll_speed)
	scroll_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_scroll_speed(v)
		_refresh_all())
	scroll_value_label = Label.new()
	_slider_row(box, "Scroll speed", scroll_slider, scroll_value_label)
	early_late_button = _toggle_row(box, "Early/late indicator", func() -> void:
		Settings.early_late_indicator = not Settings.early_late_indicator)
	no_fail_button = _toggle_row(box, "No-Fail", func() -> void:
		Settings.no_fail = not Settings.no_fail)
	reduce_motion_button = _toggle_row(box, "Reduce motion", func() -> void:
		Settings.reduce_motion = not Settings.reduce_motion, HINT_REDUCE_MOTION)


func _build_display(box: VBoxContainer) -> void:
	fullscreen_button = _toggle_row(box, "Fullscreen", func() -> void:
		Settings.set_fullscreen(not Settings.fullscreen), HINT_FULLSCREEN)
	low_effects_button = _toggle_row(box, "Low effects", func() -> void:
		Settings.low_effects = not Settings.low_effects, HINT_LOW_EFFECTS)
	_build_background_row(box)


## Display > Background: a value button showing CALM / LIVING. Press (click / ui_accept) or
## ui_left / ui_right while focused switches it (two values, so every step flips).
func _build_background_row(box: VBoxContainer) -> void:
	var title := "Background"
	var row := _row(box, title)
	background_button = _compact_button(background_label(Settings.background_style), BACKGROUND_BUTTON_W)
	background_button.name = "BackgroundButton"
	background_button.pressed.connect(cycle_background)
	background_button.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed(&"ui_left") or ev.is_action_pressed(&"ui_right"):
			cycle_background()
			background_button.accept_event())
	row.add_child(background_button)
	var h := _hint(HINT_BACKGROUND)
	h.custom_minimum_size = Vector2(VALUE_RIGHT - CONTROL_X - BACKGROUND_BUTTON_W - ROW_GAP, 0.0)
	row.add_child(h)
	_hints[title] = HINT_BACKGROUND


static func background_label(style: String) -> String:
	return "LIVING" if style == Settings.BACKGROUND_LIVING else "CALM"


## Flip Living <-> Calm; Settings persists and emits settings_changed (the arena re-reads it).
func cycle_background() -> void:
	var next := Settings.BACKGROUND_CALM if Settings.background_style == Settings.BACKGROUND_LIVING \
		else Settings.BACKGROUND_LIVING
	Settings.set_background_style(next)
	_refresh_all()


func _build_audio(box: VBoxContainer) -> void:
	master_slider = _volume_row(box, "Master", "Master", Settings.volume_master, true)
	music_slider = _volume_row(box, "Music", "Music", Settings.volume_music, false)
	menu_music_button = _toggle_row(box, "Menu music", func() -> void:
		Settings.menu_music = not Settings.menu_music, HINT_MENU_MUSIC)
	sfx_slider = _volume_row(box, "SFX", "SFX", Settings.volume_sfx, true)


func _build_library(box: VBoxContainer) -> void:
	var row := _row(box, "Songs folder")
	songs_folder_label = Label.new()
	songs_folder_label.text = middle_truncate(_songs_dir(), 64)
	songs_folder_label.custom_minimum_size = Vector2(760.0, ROW_H)
	songs_folder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	songs_folder_label.theme_type_variation = &"CaptionLabel"
	songs_folder_label.add_theme_color_override("font_color", Palette.TEXT_LO)
	row.add_child(songs_folder_label)
	open_songs_button = _compact_button("Open Songs Folder", 300.0)
	open_songs_button.pressed.connect(func() -> void:
		if library != null and library.has_method("open_songs_folder"):
			library.open_songs_folder())
	row.add_child(open_songs_button)
	_row(box, "Extra library folders")
	var lm := _indent()
	library_rows = VBoxContainer.new()
	library_rows.add_theme_constant_override("separation", Palette.SP_XS)
	lm.add_child(library_rows)
	box.add_child(lm)
	var mm := _indent()
	library_message = Label.new()
	library_message.theme_type_variation = &"CaptionLabel"
	library_message.add_theme_color_override("font_color", Palette.WARNING_RED)
	library_message.visible = false
	mm.add_child(library_message)
	box.add_child(mm)
	add_folder_button = _compact_button("Add Folder", 280.0)
	add_folder_button.pressed.connect(request_add_folder)
	_row(box, "").add_child(add_folder_button)
	for h in ["Extra folders are scanned where they are. Your files are never copied or changed.",
			"Tip: add your Clone Hero songs folder.",
			"Songs from added or removed folders update in a background scan when you leave Settings."]:
		_hint_line(box, h)
	rebuild_library_rows()


func _songs_dir() -> String:
	if library != null and library.has_method("songs_dir"):
		return library.songs_dir()
	return ProjectSettings.globalize_path(SongLibrary.DEFAULT_SONGS_DIR)


## Keeps the start and the end of a long path, joined by three ASCII dots.
static func middle_truncate(text: String, max_chars: int) -> String:
	if text.length() <= max_chars or max_chars < 8:
		return text
	var keep := max_chars - 3
	var head := int(ceil(keep / 2.0))
	return text.left(head) + "..." + text.right(keep - head)


func rebuild_library_rows() -> void:
	if library_rows == null:
		return
	for c in library_rows.get_children():
		c.free()
	for f in Settings.library_folders:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, ROW_H)
		row.add_theme_constant_override("separation", int(ROW_GAP))
		var path := _fixed_label(middle_truncate(f, 60), 760.0)
		path.theme_type_variation = &"CaptionLabel"
		path.add_theme_color_override("font_color", Palette.TEXT_MID)
		row.add_child(path)
		var status := _fixed_label(folder_status(f), 240.0)
		status.theme_type_variation = &"CaptionLabel"
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.add_theme_color_override("font_color",
			Palette.WARNING_RED if status.text == "Folder not found" else Palette.TEXT_LO)
		row.add_child(status)
		var rm := _compact_button("Remove Folder", 240.0)
		# Deferred: rebuilding frees this very button, which must not happen inside its own signal.
		rm.pressed.connect(remove_library_folder.bind(f), CONNECT_DEFERRED)
		row.add_child(rm)
		library_rows.add_child(row)
	if add_folder_button != null:
		add_folder_button.disabled = Settings.library_folders.size() >= Settings.MAX_LIBRARY_FOLDERS


## "{n} songs" / "Not scanned yet" / "Folder not found".
func folder_status(folder: String) -> String:
	if not DirAccess.dir_exists_absolute(folder):
		return "Folder not found"
	if library == null or not (folder in library.extra_folders):
		return "Not scanned yet"
	var n := 0
	var prefix := _norm_path(folder) + "/"
	for e in library.entries:
		if e.source == "library" and _norm_path(e.path).begins_with(prefix):
			n += 1
	return "%d song%s" % [n, "" if n == 1 else "s"]


static func _norm_path(p: String) -> String:
	return p.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


## Validates and adds a folder. Returns "" on success or the exact inline error text.
func add_library_folder(path: String) -> String:
	var p := path.replace("\\", "/").simplify_path().trim_suffix("/")
	if p == "" or p.length() > Settings.MAX_PATH_LEN or not DirAccess.dir_exists_absolute(p):
		return ERR_MISSING
	var key := _norm_path(p)
	for f in Settings.library_folders:
		if _norm_path(f) == key:
			return ERR_DUPLICATE
	if Settings.library_folders.size() >= Settings.MAX_LIBRARY_FOLDERS:
		return ERR_FULL
	if _norm_path(_songs_dir()) == key:
		return ERR_SONGS_DIR
	Settings.library_folders.append(p)
	Settings.save_to(Settings.save_path)
	rebuild_library_rows()
	return ""


## Forgets the path only; nothing on disk changes.
func remove_library_folder(path: String) -> void:
	var i := Settings.library_folders.find(path)
	if i < 0:
		return
	Settings.library_folders.remove_at(i)
	Settings.save_to(Settings.save_path)
	rebuild_library_rows()
	if add_folder_button != null and is_inside_tree():
		add_folder_button.grab_focus()


func folders_changed() -> bool:
	return Settings.library_folders != _folders_at_open


## Add Folder pressed: injected picker, else native directory dialog, else Godot FileDialog.
func request_add_folder() -> void:
	if Settings.library_folders.size() >= Settings.MAX_LIBRARY_FOLDERS:
		show_library_message(ERR_FULL)
		return
	if folder_picker.is_valid():
		folder_picker.call(_on_folder_picked)
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var cb := func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			if ok and not paths.is_empty():
				_on_folder_picked.call_deferred(paths[0])
		DisplayServer.file_dialog_show("Add library folder", _songs_dir(), "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(), cb)
		return
	if _folder_dialog == null:
		_folder_dialog = FileDialog.new()
		_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_folder_dialog.use_native_dialog = false
		_folder_dialog.title = "Add library folder"
		_folder_dialog.dir_selected.connect(_on_folder_picked)
		add_child(_folder_dialog)
	_folder_dialog.popup_centered_ratio(0.6)


func _on_folder_picked(path: String) -> void:
	var err := add_library_folder(path)
	if err != "":
		show_library_message(err)
	else:
		clear_library_message()


func show_library_message(text: String) -> void:
	library_message.text = "! " + text
	library_message.visible = true
	if is_inside_tree():
		var t := get_tree().create_timer(MESSAGE_SEC)
		_library_timer = t
		t.timeout.connect(func() -> void:
			if _library_timer == t:
				clear_library_message())


func clear_library_message() -> void:
	if library_message != null:
		library_message.visible = false
		library_message.text = ""
	_library_timer = null


func library_message_text() -> String:
	return library_message.text if library_message != null and library_message.visible else ""


func _build_calibration(box: VBoxContainer) -> void:
	var row := _row(box, "Offsets")
	_offsets_label = Label.new()
	_offsets_label.custom_minimum_size = Vector2(0.0, ROW_H)
	_offsets_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offsets_label.add_theme_color_override("font_color", Palette.TEXT_HI)
	row.add_child(_offsets_label)
	recalibrate_button = _compact_button("Re-run Calibration", 360.0)
	recalibrate_button.pressed.connect(func() -> void: _go(CALIBRATION_SCENE))
	# A scene change would tear down the paused run, so the overlay never offers it.
	recalibrate_button.disabled = overlay
	_row(box, "").add_child(recalibrate_button)
	_hint_line(box, "Switched headphones or speakers? Calibrate Sonar again.")


func _volume_row(box: VBoxContainer, title: String, bus: String, start: float, sample: bool) -> StepSlider:
	var s := StepSlider.new()
	s.setup(0.0, 100.0, 5.0, start * 100.0)
	var lbl := Label.new()
	_volume_labels[bus] = lbl
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(bus, v / 100.0)
		_refresh_all())
	if sample:
		s.released.connect(play_sample)
	_slider_row(box, title, s, lbl)
	return s


## Slider row: label, slider from x 440 (stretching), value Body 28 TEXT_HI right-aligned to x 1840.
func _slider_row(box: VBoxContainer, title: String, slider: StepSlider, value_label: Label) -> HBoxContainer:
	var row := _row(box, title)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	value_label.custom_minimum_size = Vector2(VALUE_W, ROW_H)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", Palette.TEXT_HI)
	row.add_child(value_label)
	return row


## Toggle row: label, pill toggle at x 440, optional hint (Label 20 TEXT_LO) beside it.
func _toggle_row(box: VBoxContainer, title: String, flip: Callable, hint: String = "") -> Button:
	var row := _row(box, title)
	var b := PillToggle.new()
	b.pressed.connect(func() -> void:
		flip.call()
		Settings.save_to(Settings.save_path)
		Settings.settings_changed.emit()
		_refresh_all())
	row.add_child(b)
	_toggles.append(b)
	if hint != "":
		# Fixed width up to the value column, wrapping if a translation or font runs long, so the
		# row never widens the scroll content past x 1840.
		var h := _hint(hint)
		h.custom_minimum_size = Vector2(VALUE_RIGHT - CONTROL_X - PillToggle.SIZE.x - ROW_GAP, 0.0)
		row.add_child(h)
		_hints[title] = hint
	return b


func _fixed_label(text: String, w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, ROW_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _refresh_all(animate: bool = true) -> void:
	if scroll_value_label == null:
		return
	scroll_value_label.text = "%.1fx" % Settings.scroll_speed
	_volume_labels["Master"].text = "%d%%" % roundi(Settings.volume_master * 100.0)
	_volume_labels["Music"].text = "%d%%" % roundi(Settings.volume_music * 100.0)
	_volume_labels["SFX"].text = "%d%%" % roundi(Settings.volume_sfx * 100.0)
	(early_late_button as PillToggle).set_on(Settings.early_late_indicator, animate)
	(no_fail_button as PillToggle).set_on(Settings.no_fail, animate)
	(reduce_motion_button as PillToggle).set_on(Settings.reduce_motion, animate)
	(fullscreen_button as PillToggle).set_on(Settings.fullscreen, animate)
	(low_effects_button as PillToggle).set_on(Settings.low_effects, animate)
	background_button.text = background_label(Settings.background_style)
	(menu_music_button as PillToggle).set_on(Settings.menu_music, animate)
	_offsets_label.text = "Audio offset: %+d ms    Visual offset: %+d ms" % [
		roundi(Settings.audio_offset * 1000.0), roundi(Settings.visual_offset * 1000.0)]
	for c in cells.values():
		(c as RebindCell).refresh()


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
	for device in [&"keyboard", &"gamepad"]:
		var cell: RebindCell = cells.get("%s:%s" % [action, device])
		if cell != null:
			cell.clear_rejected()


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
		clear_library_message()
	if dialog == null and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed()


## Esc / B / Back button. Saves; overlay mode emits `closed`, full mode returns to the menu.
func back_pressed() -> void:
	for c in cells.values():
		if (c as RebindCell).listening:
			(c as RebindCell).cancel_listen()
	Settings.save_to(Settings.save_path)
	if folders_changed():
		_folders_at_open = Settings.library_folders.duplicate()
		if library != null and library.has_method("rescan"):
			library.rescan()
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
		ScreenTransition.change_scene(path)
