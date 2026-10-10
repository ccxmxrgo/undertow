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

## Layout (02.2 UI-SPEC 9.1), 1920x1080 design pixels.
const DIM_ALPHA := 0.85
const PANEL_RECT := Rect2(672, 288, 576, 504)
const TITLE_AT := Vector2(704, 352)  # "PAUSED" baseline
const RUN_AT := Vector2(704, 384)  # run line baseline
const RULE_Y := 400.0  # header divider between the run line and the buttons
const HINT_AT := Vector2(704, 752)
const BUTTON_X := 704.0
const BUTTON_W := 512.0
const BUTTON_H := 64.0
const BUTTON_TOPS: Array[float] = [416.0, 488.0, 560.0, 632.0]
const RUN_MAX_W := 512.0
const RULE_ALPHA := 0.35
const BRACKET_ALPHA := 0.8
## Resume countdown: Display 96 numeral centred in a SONAR ring that drains once per beat.
const COUNTDOWN_CENTER := Vector2(960, 560)
const RING_R := 80.0
const RING_W := 4.0
const RING_TRACK_ALPHA := 0.2
const RING_DISC_ALPHA := 0.82

var conductor: Conductor
var lane_input: LaneInput
var score: HullScore
## False in autoplay runs: the player never has live lane input there.
var restore_input: bool = true

var resume_button: Button
var restart_button: Button
var settings_button: Button
var menu_button: Button
var panel: Control
var title_label: Label
var run_label: Label
var hint_label: Label
var countdown_label: Label
var countdown_ring: Control

static var _vignette: GradientTexture2D

var _panel_root: Control
var _focus_marker: FocusMarker
var _beat_sec: float = 0.5
var _tick_usec: int = 0
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


## Run line under the title: "{title} · {DIFFICULTY} · {nn}%" (UI-SPEC 9.1 / 14).
static func run_line(title: String, difficulty: String, progress_pct: float) -> String:
	var pct := int(clampf(progress_pct, 0.0, 100.0))
	return "%s · %s · %d%%" % [title, difficulty.to_upper(), pct]


## Gameplay passes the current run before opening the pause panel.
func set_run_info(title: String, difficulty: String, progress_pct: float) -> void:
	if run_label == null:
		return
	var font := run_label.get_theme_font("font")
	var full := run_line(title, difficulty, progress_pct)
	var tail := full.substr(title.length())  # " · DIFFICULTY · nn%" always stays visible
	var tail_w := font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	run_label.text = ProgressTrack.truncate_px(title, font, Palette.SIZE_LABEL, RUN_MAX_W - tail_w) + tail


## Ring fill left after `elapsed` seconds of a beat lasting `beat_sec` (1 at the tick, 0 at the end).
static func ring_fraction_at(elapsed: float, beat_sec: float) -> float:
	if beat_sec <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / beat_sec, 0.0, 1.0)


func ring_fraction() -> float:
	if not _counting or _tick_usec == 0:
		return 0.0
	return ring_fraction_at(float(Time.get_ticks_usec() - _tick_usec) / 1000000.0, _beat_sec)


func open() -> void:
	if is_open() or _counting or conductor == null:
		return
	conductor.pause()
	lane_input.enabled = false
	_panel_root.visible = true
	_set_marker_active(true)
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
	countdown_label.text = str(n)
	countdown_label.visible = true
	countdown_ring.visible = true
	_tick_usec = Time.get_ticks_usec()
	if conductor != null:
		_beat_sec = 60.0 / maxf(conductor.bpm_at(conductor.song_time()), 1.0)
	countdown_label.modulate.a = 1.0
	countdown_label.scale = Vector2.ONE
	if not is_inside_tree():
		return
	var tw := create_tween().set_parallel(true)
	if not Settings.reduce_motion:
		countdown_label.scale = Vector2(TICK_SCALE_FROM, TICK_SCALE_FROM)
		tw.tween_property(countdown_label, "scale", Vector2.ONE, TICK_SCALE_SEC).set_ease(Tween.EASE_OUT)
	tw.tween_property(countdown_label, "modulate:a", 0.0, TICK_FADE_SEC).set_delay(TICK_SCALE_SEC)


func _on_resumed() -> void:
	if not _counting:
		return
	_counting = false
	countdown_label.visible = false
	countdown_ring.visible = false
	if restore_input:
		lane_input.enabled = true


func _show_dialog(title: String, body: String, confirm_text: String, safe_text: String,
		return_focus: Button, on_confirm: Callable) -> void:
	if _dialog != null:
		return
	_dialog = ConfirmDialog.new()
	_set_marker_active(false)  # the dialog has its own marker; this one must not draw over it
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
	_set_marker_active(true)


func _set_marker_active(on: bool) -> void:
	if _focus_marker == null:
		return
	_focus_marker.set_process(on)
	if not on:
		_focus_marker.visible = false


func _process(_delta: float) -> void:
	if _counting and countdown_ring != null and countdown_ring.visible:
		countdown_ring.queue_redraw()


## Draws through a callable (backdrop, panel, ring).
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _build() -> void:
	_panel_root = Control.new()
	_panel_root.name = "PanelRoot"
	UiLayout.fill_rect(_panel_root)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.visible = false
	add_child(_panel_root)
	# Backdrop: ABYSS_900 85% over the frozen board, then the corner vignette (no blur, UI-SPEC 12).
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.ABYSS_900, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(dim)
	_panel_root.add_child(dim)
	var vignette := _painter(_panel_root, "Vignette", Rect2(Vector2.ZERO, Vector2(Highway.SCREEN_W, Highway.SCREEN_H)),
		func(ci: CanvasItem) -> void:
			ci.draw_texture_rect(corner_vignette(), Rect2(Vector2.ZERO, ci.get("size")), false))
	UiLayout.fill_rect(vignette)
	# Glass panel with brackets and a header rule.
	var sb := UiKit.style_panel("default")
	panel = _painter(_panel_root, "Panel", PANEL_RECT, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, PANEL_RECT.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, Color(Palette.SONAR, BRACKET_ALPHA))
		var y := RULE_Y - PANEL_RECT.position.y
		var x0 := BUTTON_X - PANEL_RECT.position.x
		ci.draw_line(Vector2(x0, y), Vector2(x0 + BUTTON_W, y), Color(Palette.SONAR, RULE_ALPHA), Palette.EDGE))
	title_label = _text(_panel_root, "Title", "PAUSED", Palette.display_font(), Palette.SIZE_HEADING,
		Palette.TEXT_HI, TITLE_AT)
	run_label = _text(_panel_root, "RunLine", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, RUN_AT)
	run_label.size.x = RUN_MAX_W
	run_label.clip_text = true
	hint_label = _text(_panel_root, "Hint", "ESC RESUME", _spaced(Palette.font(), 2), Palette.SIZE_LABEL,
		Palette.TEXT_LO, HINT_AT)
	resume_button = _button("Resume Dive", "primary", 0, resume_dive)
	restart_button = _button("Restart Dive", "default", 1, request_restart)
	settings_button = _button("Settings", "default", 2, open_settings)
	menu_button = _button("Back to Menu", "default", 3, request_menu)
	var buttons := [resume_button, restart_button, settings_button, menu_button]
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i + buttons.size() - 1) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
	_focus_marker = FocusMarker.new()
	_focus_marker.name = "FocusMarker"
	_panel_root.add_child(_focus_marker)
	# Resume countdown: a dark disc, a SONAR ring draining once per beat and the numeral.
	var ring_rect := Rect2(COUNTDOWN_CENTER - Vector2(RING_R + 24.0, RING_R + 24.0), Vector2(RING_R + 24.0, RING_R + 24.0) * 2.0)
	countdown_ring = _painter(self, "CountdownRing", ring_rect, _draw_ring)
	countdown_ring.visible = false
	countdown_label = Label.new()
	countdown_label.name = "Countdown"
	countdown_label.add_theme_font_override("font", Palette.display_font())
	countdown_label.add_theme_font_size_override("font_size", Palette.SIZE_DISPLAY)
	countdown_label.add_theme_color_override("font_color", Palette.TEXT_HI)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.size = Vector2(240.0, 160.0)
	countdown_label.position = COUNTDOWN_CENTER - countdown_label.size * 0.5
	countdown_label.pivot_offset = countdown_label.size * 0.5
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.visible = false
	add_child(countdown_label)


func _draw_ring(ci: CanvasItem) -> void:
	var c: Vector2 = ci.get("size") * 0.5
	ci.draw_circle(c, RING_R + 12.0, Color(Palette.ABYSS_900, RING_DISC_ALPHA))
	ci.draw_arc(c, RING_R, 0.0, TAU, 64, Color(Palette.SONAR, RING_TRACK_ALPHA), RING_W, true)
	var f := ring_fraction()
	if f > 0.0:
		var a0 := -PI * 0.5
		if not UiKit.low_effects():  # stroke glow under the live arc (UI-SPEC 3.3)
			ci.draw_arc(c, RING_R, a0, a0 + TAU * f, 64, Color(Palette.SONAR, 0.12), RING_W + 8.0, true)
		ci.draw_arc(c, RING_R, a0, a0 + TAU * f, 64, Palette.SONAR, RING_W, true)


## Corner vignette: clear in the middle, SHADOW at the corners (UI-SPEC 11: always on).
static func corner_vignette() -> GradientTexture2D:
	if _vignette != null:
		return _vignette
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(Palette.SHADOW, 0.0), Color(Palette.SHADOW, 0.0), Palette.SHADOW])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 144
	_vignette = tex
	return tex


func _painter(parent: Control, node_name: String, rect: Rect2, fn: Callable) -> Painter:
	var p := Painter.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = rect.position
	p.size = rect.size
	p.painter = fn
	parent.add_child(p)
	return p


static func _spaced(base: Font, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	return v


## Label whose baseline sits at `at` (left-aligned).
func _text(parent: Control, node_name: String, text: String, font: Font, font_size: int, color: Color,
		at: Vector2) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.position = Vector2(at.x, at.y - font.get_ascent(font_size))
	l.size = Vector2(maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, 1.0),
		font.get_height(font_size))
	parent.add_child(l)
	return l


func _button(text: String, variant: String, i: int, cb: Callable) -> Button:
	var b := UiKit.make_button(text, "", variant, int(BUTTON_H))
	b.name = text.replace(" ", "")
	b.position = Vector2(BUTTON_X, BUTTON_TOPS[i])
	b.size = Vector2(BUTTON_W, BUTTON_H)
	b.pressed.connect(cb)
	_panel_root.add_child(b)
	return b
