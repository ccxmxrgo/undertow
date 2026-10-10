class_name CalibrationWizard
extends Control
## Calibrate Sonar wizard (CAL-01, D-16, D-17): Intro, Audio offset, Visual offset, Summary.
## Audio: 16 clicks at 100 BPM; taps are stamped with Time.get_ticks_usec() in _input (the gameplay
## LaneInput is not used here), converted to RAW song time (applied offset removed) and reduced to
## a median by CalibrationMath.audio_offset_from_taps. Visual: a glyph crosses a line on the click
## and a +-200 ms slider shifts it. Nothing is stored until "Save and Continue" (T-06-03).

enum Step { INTRO, AUDIO, VISUAL, SUMMARY }
enum AudioPhase { IDLE, RUNNING, RESULT }

const MENU_SCENE := "res://scenes/main_menu.tscn"
const BPM := 100.0
const CLICK_COUNT := 16
const LEAD_IN := 1.5
const TRACK_SECONDS := 120.0
const SPB := 60.0 / BPM
const STAGE_SIZE := Vector2(640.0, 440.0)
const WARNING_COPY := "Bluetooth audio detected. It adds delay that varies. Use wired headphones or speakers for the best timing."
const INTRO_COPY := "Your speakers and screen add delay. We will measure it so your hits line up. Tap along to the pings. Takes about one minute."
const FEW_TAPS_COPY := "Not enough taps recorded. Tap along to all the pings and try again."
const RECAL_NOTE := "Switched headphones or speakers? Calibrate Sonar again."
const LARGE_COPY := "That offset looks unusually large. Check your audio output and retry."

var navigate: Callable = Callable()
var step: int = Step.INTRO
var audio_phase: int = AudioPhase.IDLE

## Values waiting for "Save and Continue" (seconds). Start at the current settings.
var pending_audio: float = 0.0
var pending_visual: float = 0.0
## Last measured audio offset (NAN = none / not enough taps).
var audio_result: float = NAN
var tap_times: Array = []
var taps_recorded: int = 0

var conductor: Conductor
var visual_slider: StepSlider
var skip_button: Button
var accept_button: Button
var retry_button: Button
var save_button: Button
var begin_button: Button
var status_label: Label
var result_label: Label
var caption_label: Label
var counter_label: Label
var tap_feedback_label: Label
var previous_label: Label
var note_label: Label

var _step_label: Label
var _info_label: Label
var _bt_panel: PanelContainer
var _content: VBoxContainer
var _stage: Control
var _device_name: String = ""


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	# Pitfall 7 / T-02.2-13: menu music would pollute the click-track measurement.
	MenuMusic.stop(0.0)
	pending_audio = Settings.audio_offset
	pending_visual = Settings.visual_offset
	conductor = Conductor.new()
	add_child(conductor)
	_build_frame()
	show_step(Step.INTRO)


# --- frame -------------------------------------------------------------------------------------


func _build_frame() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiLayout.fill_rect(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UiLayout.fill_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Palette.SP_3XL)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Palette.SP_MD)
	margin.add_child(root)
	_step_label = Label.new()
	_step_label.theme_type_variation = &"HeadingLabel"
	root.add_child(_step_label)
	_info_label = Label.new()
	_info_label.theme_type_variation = &"CaptionLabel"
	root.add_child(_info_label)
	note_label = Label.new()
	note_label.text = RECAL_NOTE
	note_label.theme_type_variation = &"CaptionLabel"
	note_label.add_theme_color_override("font_color", Palette.TEXT)
	root.add_child(note_label)
	_bt_panel = _build_warning()
	root.add_child(_bt_panel)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", Palette.SP_MD)
	root.add_child(_content)
	skip_button = Button.new()
	skip_button.text = "Skip for now"
	skip_button.custom_minimum_size = Vector2(280.0, 48.0)
	skip_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	skip_button.pressed.connect(skip)
	root.add_child(skip_button)
	refresh_info()


func _build_warning() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.border_color = Palette.DESTRUCTIVE
	sb.border_width_left = 4
	sb.content_margin_left = Palette.SP_MD
	sb.content_margin_right = Palette.SP_MD
	sb.content_margin_top = Palette.SP_SM
	sb.content_margin_bottom = Palette.SP_SM
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = "! " + WARNING_COPY
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1200.0, 0.0)
	l.add_theme_color_override("font_color", Palette.DESTRUCTIVE)
	p.add_child(l)
	return p


## Latency / buffer / device readout and the (non-blocking) Bluetooth heuristic.
func refresh_info() -> void:
	var snap := Settings.device_info.snapshot()
	_device_name = snap.display
	var latency_ms := AudioServer.get_output_latency() * 1000.0
	var buffer_ms := float(ProjectSettings.get_setting("audio/driver/output_latency", 15))
	_info_label.text = "Output latency: %d ms
Buffer: %d ms
Output device: %s" % [
		roundi(latency_ms), roundi(buffer_ms), _device_name]
	_bt_panel.visible = snap.is_bluetooth


func bluetooth_warning_visible() -> bool:
	return _bt_panel.visible


func _clear_content() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_stage = null
	visual_slider = null
	accept_button = null
	retry_button = null
	save_button = null
	begin_button = null
	status_label = null
	result_label = null
	caption_label = null
	counter_label = null
	tap_feedback_label = null
	previous_label = null


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	return l


func _body(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1200.0, 0.0)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320.0, 56.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b


# --- steps -------------------------------------------------------------------------------------


func show_step(s: int) -> void:
	conductor.stop()
	conductor.offset_override = NAN
	step = s
	_clear_content()
	audio_phase = AudioPhase.IDLE
	match s:
		Step.INTRO:
			_step_label.text = "CALIBRATE SONAR"
			_content.add_child(_body(INTRO_COPY))
			begin_button = _button("Begin", func() -> void: show_step(Step.AUDIO))
			_content.add_child(begin_button)
			begin_button.grab_focus()
		Step.AUDIO:
			_step_label.text = _steps_text(1)
			_build_audio_step()
		Step.VISUAL:
			_step_label.text = _steps_text(2)
			_build_visual_step()
		Step.SUMMARY:
			_step_label.text = _steps_text(3)
			_build_summary_step()


func _steps_text(current: int) -> String:
	var parts: Array[String] = []
	for i in range(3):
		var name_text: String = ["1 AUDIO", "2 VISUAL", "3 DONE"][i]
		parts.append(("▶ " + name_text) if i + 1 == current else name_text)
	return "  ".join(parts)


func _make_stage() -> Control:
	var st := Control.new()
	st.custom_minimum_size = STAGE_SIZE
	st.draw.connect(_draw_stage.bind(st))
	return st


func _build_audio_step() -> void:
	_content.add_child(_body("Tap to each ping. The first 4 are warm-up."))
	caption_label = Label.new()
	counter_label = Label.new()
	tap_feedback_label = Label.new()
	tap_feedback_label.theme_type_variation = &"CaptionLabel"
	_stage = _make_stage()
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(1200.0, 0.0)
	result_label = Label.new()
	result_label.theme_type_variation = &"DisplayLabel"
	_content.add_child(caption_label)
	_content.add_child(counter_label)
	_content.add_child(_stage)
	_content.add_child(tap_feedback_label)
	_content.add_child(result_label)
	previous_label = Label.new()
	previous_label.theme_type_variation = &"CaptionLabel"
	previous_label.add_theme_color_override("font_color", Palette.TEXT)
	_content.add_child(previous_label)
	_content.add_child(status_label)
	var row := HBoxContainer.new()
	accept_button = _button("Accept Offset", accept_audio)
	retry_button = _button("Retry Test", begin_audio_test)
	row.add_child(accept_button)
	row.add_child(retry_button)
	_content.add_child(row)
	begin_audio_test()


func _build_visual_step() -> void:
	_content.add_child(_body("Adjust until the flash and the ping land together."))
	result_label = Label.new()
	result_label.theme_type_variation = &"HeadingLabel"
	_content.add_child(result_label)
	_stage = _make_stage()
	_content.add_child(_stage)
	visual_slider = StepSlider.new()
	visual_slider.custom_minimum_size = Vector2(1200.0, 48.0)
	var start_ms := roundf(CalibrationMath.visual_offset_clamp(pending_visual, true) * 1000.0)
	visual_slider.setup(-200.0, 200.0, 1.0, start_ms, 10.0)
	visual_slider.value_changed.connect(_on_visual_changed)
	_content.add_child(visual_slider)
	var row := HBoxContainer.new()
	accept_button = _button("Accept Offset", accept_visual)
	retry_button = _button("Retry Test", func() -> void: visual_slider.set_value(0.0))
	row.add_child(accept_button)
	row.add_child(retry_button)
	_content.add_child(row)
	_on_visual_changed(visual_slider.value)
	# WR-02: measure against the audio offset that is about to be saved, not the old one.
	conductor.offset_override = pending_audio
	_start_loop()
	visual_slider.grab_focus()


func _build_summary_step() -> void:
	_content.add_child(_heading("AUDIO OFFSET %s" % format_ms(pending_audio)))
	_content.add_child(_heading("VISUAL OFFSET %s" % format_ms(pending_visual)))
	var row := HBoxContainer.new()
	save_button = _button("Save and Continue", save_and_continue)
	row.add_child(save_button)
	row.add_child(_button("Redo", func() -> void: show_step(Step.AUDIO)))
	_content.add_child(row)
	save_button.grab_focus()


## "+42 MS" with sign, from seconds.
static func format_ms(seconds: float) -> String:
	return "%+d MS" % roundi(seconds * 1000.0)


# --- audio test --------------------------------------------------------------------------------


func click_times() -> Array:
	var out: Array = []
	for i in range(CLICK_COUNT):
		out.append(i * SPB)
	return out


func begin_audio_test() -> void:
	tap_times.clear()
	taps_recorded = 0
	audio_result = NAN
	audio_phase = AudioPhase.RUNNING
	if status_label != null:
		status_label.text = ""
		result_label.text = ""
		previous_label.text = ""
		tap_feedback_label.text = ""
		accept_button.visible = false
		retry_button.visible = false
	_update_tap_labels()
	conductor.begin(AudioSynth.make_click_track(BPM, TRACK_SECONDS), LEAD_IN)
	if skip_button != null:
		skip_button.grab_focus()


func _start_loop() -> void:
	conductor.begin(AudioSynth.make_click_track(BPM, TRACK_SECONDS), LEAD_IN)


## Stamp -> song time (the applied audio_offset is removed again in evaluate_audio).
func record_tap_ticks(ticks: int) -> void:
	record_tap(conductor.song_time_at(ticks))


## Records one tap at the given song time (offset-adjusted domain, as Conductor reports it).
func record_tap(song_time: float) -> void:
	if audio_phase != AudioPhase.RUNNING or taps_recorded >= CLICK_COUNT:
		return
	tap_times.append(song_time)
	taps_recorded += 1
	var delta := _nearest_delta(song_time + Settings.audio_offset)
	var ms := roundi(absf(delta) * 1000.0)
	tap_feedback_label.text = ("EARLY %d MS" % ms) if delta < 0.0 else ("LATE %d MS" % ms)
	_update_tap_labels()


func _nearest_delta(t: float) -> float:
	var best := INF
	for c in click_times():
		var d: float = t - float(c)
		if absf(d) < absf(best):
			best = d
	return best


func _update_tap_labels() -> void:
	if counter_label == null:
		return
	counter_label.text = "TAP %d / %d" % [taps_recorded, CLICK_COUNT]
	caption_label.text = "WARM-UP" if taps_recorded < CalibrationMath.DEFAULT_DISCARD else "RECORDING"


## Reduces the recorded taps to an offset and shows the result / error copy.
func evaluate_audio() -> void:
	audio_phase = AudioPhase.RESULT
	conductor.stop()
	var taps := CalibrationMath.remove_applied_offset(tap_times, Settings.audio_offset)
	audio_result = CalibrationMath.audio_offset_from_taps(taps, click_times())
	accept_button.visible = false
	retry_button.visible = true
	if is_nan(audio_result):
		result_label.text = ""
		previous_label.text = ""
		status_label.text = FEW_TAPS_COPY
	else:
		audio_result = CalibrationMath.clamp_offset(audio_result)
		result_label.text = format_ms(audio_result)
		# Gap 5: the result is the ABSOLUTE offset (what Accept stores); show the saved one beside it.
		previous_label.text = ("Previously saved: %s" % format_ms(Settings.audio_offset)) 			if Settings.calibration_done else ""
		status_label.text = LARGE_COPY if CalibrationMath.is_suspicious(audio_result) else ""
		accept_button.visible = true
	(accept_button if accept_button.visible else retry_button).grab_focus()


func accept_audio() -> void:
	if is_nan(audio_result):
		return
	pending_audio = audio_result
	show_step(Step.VISUAL)


# --- visual test -------------------------------------------------------------------------------


func _on_visual_changed(ms: float) -> void:
	pending_visual = CalibrationMath.visual_offset_clamp(ms / 1000.0, true)
	if result_label != null:
		result_label.text = "VISUAL OFFSET %s" % format_ms(pending_visual)


func accept_visual() -> void:
	pending_visual = CalibrationMath.visual_offset_clamp(visual_slider.value / 1000.0, true)
	show_step(Step.SUMMARY)


# --- summary / exit ----------------------------------------------------------------------------


func save_and_continue() -> void:
	Settings.save_calibration(pending_audio, pending_visual)
	_leave()


func skip() -> void:
	_leave()


func _leave() -> void:
	conductor.stop()
	MainMenu.boot_handled = true
	if navigate.is_valid():
		navigate.call(MENU_SCENE)
	elif is_inside_tree():
		get_tree().change_scene_to_file(MENU_SCENE)


# --- input / frame -----------------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if step != Step.AUDIO or audio_phase != AudioPhase.RUNNING or event.is_echo():
		return
	var ticks := Time.get_ticks_usec()  # stamp first
	if not event.is_pressed():
		return
	var is_tap := false
	if event is InputEventKey:
		var k := event as InputEventKey
		is_tap = event.is_action_pressed(&"lane_1") or k.physical_keycode == KEY_SPACE \
			or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER
	elif event is InputEventJoypadButton:
		is_tap = (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_tap = mb.button_index == MOUSE_BUTTON_LEFT and not skip_button.get_global_rect().has_point(mb.global_position)
	if is_tap:
		get_viewport().set_input_as_handled()  # a tap must not also press a focused button
		record_tap_ticks(ticks)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		skip()


func _process(_delta: float) -> void:
	if _stage != null:
		_stage.queue_redraw()
	if step == Step.AUDIO and audio_phase == AudioPhase.RUNNING:
		if conductor.song_time() > (CLICK_COUNT - 1) * SPB + 0.6:
			evaluate_audio()
	elif step == Step.VISUAL and conductor.song_time() > TRACK_SECONDS - 10.0:
		_start_loop()


func _draw_stage(c: Control) -> void:
	var st := conductor.song_time()
	var center := c.size * 0.5
	if step == Step.AUDIO:
		var p := 1.0
		if audio_phase == AudioPhase.RUNNING and st >= 0.0 and st <= (CLICK_COUNT - 1) * SPB + SPB:
			p = fposmod(st / SPB, 1.0)
		# Ring contracts to a dot on each click.
		c.draw_arc(center, lerpf(8.0, 140.0, p), 0.0, TAU, 64, Palette.ACCENT, 4.0)
		c.draw_circle(center, 8.0, Palette.ACCENT)
	elif step == Step.VISUAL:
		var line_y := c.size.y - 60.0
		var vt := st + pending_visual
		var p := fposmod(vt / SPB, 1.0)
		var travel := line_y - 40.0
		var y := line_y - (1.0 - p) * travel
		var flash := p < 0.12 or p > 0.98
		c.draw_line(Vector2(center.x - 120.0, line_y), Vector2(center.x + 120.0, line_y),
			Palette.ACCENT, 8.0 if flash else 4.0)
		var d := 40.0
		var pts := PackedVector2Array([Vector2(center.x, y - d), Vector2(center.x + d, y),
			Vector2(center.x, y + d), Vector2(center.x - d, y), Vector2(center.x, y - d)])
		c.draw_polyline(pts, Palette.ACCENT, 4.0)
