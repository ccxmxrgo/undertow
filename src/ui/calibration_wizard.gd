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
const WARNING_COPY := "Bluetooth audio detected. It adds delay that varies. Use wired headphones or speakers for the best timing."
const INTRO_COPY := "Your speakers and screen add delay. We will measure it so your hits line up. Tap along to the pings. Takes about one minute."
const FEW_TAPS_COPY := "Not enough taps recorded. Tap along to all the pings and try again."
const RECAL_NOTE := "Switched headphones or speakers? Calibrate Sonar again."
const LARGE_COPY := "That offset looks unusually large. Check your audio output and retry."

## ---- Layout (02.2 UI-SPEC 9.4), 1920 x 1080 design pixels.
const STEP_CHIPS: Array[String] = ["1 AUDIO", "2 VISUAL", "3 DONE"]
const CHIP_X := 64.0
const CHIP_Y := 64.0
const CHIP_W := 176.0
const CHIP_H := 48.0
const CHIP_GAP := 48.0
const TITLE_RIGHT := 1856.0
const TITLE_BASE := 100.0
const DEVICE_PANEL := Rect2(64.0, 136.0, 640.0, 160.0)
const WARNING_PANEL := Rect2(736.0, 136.0, 1120.0, 160.0)
const INSTRUCTION_AT := Vector2(64.0, 340.0)
const INSTRUCTION_W := 1792.0
const CAPTION_AT := Vector2(64.0, 384.0)
const VALUE_AT := Vector2(64.0, 476.0)
const SUMMARY_VISUAL_X := 704.0
const LEFT_COL_W := 544.0
const STATE_AT := Vector2(64.0, 532.0)  # WARM-UP / RECORDING
const COUNTER_AT := Vector2(64.0, 584.0)  # TAP n / 16
const FEEDBACK_AT := Vector2(64.0, 624.0)  # EARLY / LATE n MS
const PREVIOUS_AT := Vector2(64.0, 664.0)  # Previously saved
const STATUS_TOP := 688.0
const STAGE_RECT := Rect2(640.0, 440.0, 640.0, 320.0)
const SIDE_PANEL := Rect2(1312.0, 440.0, 544.0, 320.0)
const NOTE_CENTER := Vector2(960.0, 560.0)
const NOTE_R := 41.0
const HIT_LINE_Y := 700.0
const HIT_LINE_X := Vector2(840.0, 1080.0)
const HIT_LINE_W := 4.0
const PING_R0 := 160.0
const SLIDER_RECT := Rect2(64.0, 828.0, 1792.0, 48.0)  # thumb band y 836..868, centre 852
const SCALE_BASE := 904.0
const BUTTONS_Y := 920.0
const BUTTON_W := 320.0
const BUTTON_H := 48.0
const BUTTON_GAP := Palette.SP_MD
const TAP_CELL := Vector2(112.0, 48.0)
const TAP_GRID_AT := Vector2(1336.0, 520.0)
const RUNNING_VALUE := "-- MS"
const SAVED_AT := Vector2(64.0, 540.0)

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
## 02.2-21: "AUDIO OFFSET" / "VISUAL OFFSET" caption above the big value.
var offset_caption_label: Label
var backdrop: AbyssBackdrop
var focus_marker: FocusMarker

var _step_label: Label
var _info_label: Label
var _bt_panel: PanelContainer
var _content: Control
var _stage: Control
var _side: Control
var _chips: Control
var _device_name: String = ""
var _tap_deltas: Array[int] = []
var _low := false
var _quiet_bg: ColorRect


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
	_low = UiKit.low_effects()
	_build_frame()
	UiKit.register_fx(self)
	show_step(Step.INTRO)


# --- effect contract ---------------------------------------------------------------------------


## Effect contract: Low effects drops the panel glow and the ring / hit-line glow strokes. The
## Perfect ring itself stays in every mode (UI-SPEC 11 "Shockwave rings: on").
func apply_effect_settings() -> void:
	_low = UiKit.low_effects()
	if _stage != null:
		_stage.queue_redraw()
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"panel_glow": not _low, "ring_glow": not _low, "perfect_ring": true}


## T-02.2-41: taps are stamped when Godot processes the input event, once per frame, so a
## heavy frame delays every stamp. While the audio test runs, the decorative backdrop is
## hidden behind a plain ABYSS_900 fill (measured under software GL: the table backdrop
## shifted the result by about 21 ms). It comes back for the result and the other steps.
func set_quiet(on: bool) -> void:
	if backdrop != null:
		backdrop.visible = not on
		backdrop.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if _quiet_bg != null:
		_quiet_bg.visible = on


func is_quiet() -> bool:
	return _quiet_bg != null and _quiet_bg.visible


# --- static layout helpers (tests) -------------------------------------------------------------


static func chip_rect(i: int) -> Rect2:
	return Rect2(CHIP_X + i * (CHIP_W + CHIP_GAP), CHIP_Y, CHIP_W, CHIP_H)


## "current" / "done" / "upcoming" for the three step chips at step `s`.
static func chip_states(s: int) -> Array[String]:
	var current := -1
	match s:
		Step.AUDIO:
			current = 0
		Step.VISUAL:
			current = 1
		Step.SUMMARY:
			current = 2
	var out: Array[String] = []
	for i in 3:
		if current < 0 or i > current:
			out.append("upcoming")
		elif i == current:
			out.append("current")
		else:
			out.append("done")
	return out


## The Perfect shockwave ring {r, w, a} `age` seconds after the click, or {} outside its life.
static func flash_ring(age: float) -> Dictionary:
	if age < 0.0 or age >= HitBurst.life(HitBurst.RING_PERFECT):
		return {}
	return HitBurst.ring_state(HitBurst.RING_PERFECT, age)


## Visual test note centre y at beat phase p (0 = just after a click, 1 = on the next click,
## where it sits on the hit line).
static func visual_note_y(p: float) -> float:
	var top := STAGE_RECT.position.y + NOTE_R + Palette.SP_MD
	return HIT_LINE_Y - (1.0 - clampf(p, 0.0, 1.0)) * (HIT_LINE_Y - top)


# --- frame -------------------------------------------------------------------------------------


func _build_frame() -> void:
	_quiet_bg = ColorRect.new()
	_quiet_bg.name = "QuietBackground"
	_quiet_bg.color = Palette.ABYSS_900
	_quiet_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quiet_bg.visible = false
	UiLayout.fill_rect(_quiet_bg)
	add_child(_quiet_bg)
	backdrop = AbyssBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.variant = "table"
	UiLayout.fill_rect(backdrop)
	add_child(backdrop)

	_chips = _painter("StepChips", Rect2(0.0, 0.0, 1920.0, 128.0), _draw_chips)
	add_child(_chips)
	var hf := Palette.display_font()
	_step_label = Label.new()
	_step_label.name = "Title"
	_step_label.text = "CALIBRATE SONAR"
	_step_label.theme_type_variation = &"HeadingLabel"
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_step_label.size = Vector2(720.0, hf.get_height(Palette.SIZE_HEADING))
	_step_label.position = Vector2(TITLE_RIGHT - 720.0, TITLE_BASE - hf.get_ascent(Palette.SIZE_HEADING))
	add_child(_step_label)

	# Device info: glass panel with the readout and the re-calibration note.
	add_child(_glass("DevicePanel", DEVICE_PANEL, "default"))
	var pad := float(UiKit.PANEL_PAD)
	_info_label = Label.new()
	_info_label.name = "DeviceInfo"
	_info_label.theme_type_variation = &"CaptionLabel"
	_info_label.add_theme_color_override("font_color", Palette.TEXT_MID)
	_info_label.position = DEVICE_PANEL.position + Vector2(pad, pad - 4.0)
	_info_label.size = Vector2(DEVICE_PANEL.size.x - pad * 2.0, 96.0)
	add_child(_info_label)
	note_label = Label.new()
	note_label.name = "RecalNote"
	note_label.text = RECAL_NOTE
	note_label.theme_type_variation = &"CaptionLabel"
	# Plain Share Tech Mono (no +2 caption spacing) so the sentence fits the 592 px panel.
	note_label.add_theme_font_override("font", Palette.font())
	note_label.add_theme_color_override("font_color", Palette.TEXT_LO)
	note_label.position = Vector2(DEVICE_PANEL.position.x + pad, DEVICE_PANEL.end.y - pad - 26.0)
	note_label.size = Vector2(DEVICE_PANEL.size.x - pad * 2.0, 28.0)
	add_child(note_label)
	_bt_panel = _build_warning()
	add_child(_bt_panel)

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(_content)
	add_child(_content)

	skip_button = _button("Skip for now", skip)
	skip_button.position = Vector2(TITLE_RIGHT - BUTTON_W, BUTTONS_Y)
	add_child(skip_button)
	focus_marker = FocusMarker.new()
	focus_marker.name = "FocusMarker"
	add_child(focus_marker)
	refresh_info()


## Danger glass panel with the Bluetooth warning (shown only when the heuristic fires).
func _build_warning() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "BluetoothWarning"
	var sb := UiKit.style_panel("danger", _low)
	sb.shadow_color = Color(Palette.WARNING_RED, Palette.PANEL_GLOW_ALPHA)
	p.add_theme_stylebox_override("panel", sb)
	p.position = WARNING_PANEL.position
	p.size = WARNING_PANEL.size
	p.custom_minimum_size = WARNING_PANEL.size
	p.draw.connect(func() -> void:
		UiKit.draw_brackets(p, Rect2(Vector2.ZERO, p.size), Color(Palette.WARNING_RED, 0.8)))
	var l := Label.new()
	l.text = "! " + WARNING_COPY
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Palette.WARNING_RED)
	p.add_child(l)
	return p


## Latency / buffer / device readout and the (non-blocking) Bluetooth heuristic.
func refresh_info() -> void:
	var snap := Settings.device_info.snapshot()
	_device_name = snap.display
	var latency_ms := AudioServer.get_output_latency() * 1000.0
	var buffer_ms := float(ProjectSettings.get_setting("audio/driver/output_latency", 15))
	_info_label.text = "Output latency: %d ms\nBuffer: %d ms\nOutput device: %s" % [
		roundi(latency_ms), roundi(buffer_ms), _device_name]
	_bt_panel.visible = snap.is_bluetooth


func bluetooth_warning_visible() -> bool:
	return _bt_panel.visible


func _clear_content() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_stage = null
	_side = null
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
	offset_caption_label = null


## A Control at `rect` whose drawing is `fn(ci)`.
func _painter(node_name: String, rect: Rect2, fn: Callable) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size
	c.draw.connect(func() -> void: fn.call(c))
	return c


## Glass panel (UiKit.style_panel + corner brackets) as a painter.
func _glass(node_name: String, rect: Rect2, variant: String) -> Control:
	return _painter(node_name, rect, func(ci: Control) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_style_box(UiKit.style_panel(variant, _low), r)
		UiKit.draw_brackets(ci, r, Color(Palette.SONAR, 0.8)))


## Label whose baseline sits at `at` (left-aligned), added to the step content.
func _text(text: String, font: Font, font_size: int, color: Color, at: Vector2, w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.position = Vector2(at.x, at.y - font.get_ascent(font_size))
	if w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(w, font.get_height(font_size))
		l.custom_minimum_size = Vector2(w, 0.0)
	else:
		l.size = Vector2(LEFT_COL_W, font.get_height(font_size))
	_content.add_child(l)
	return l


func _caption_font() -> Font:
	return get_theme_font("font", &"CaptionLabel")


func _instruction(text: String) -> Label:
	return _text(text, Palette.font(), Palette.SIZE_BODY, Palette.TEXT_HI, INSTRUCTION_AT, INSTRUCTION_W)


## Caption (Label 20 TEXT_LO) + big value (Display 96 SONAR) pair at x.
func _offset_readout(caption: String, value: String, x: float) -> Label:
	var cap := _text(caption, _caption_font(), Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(x, CAPTION_AT.y))
	if x == CAPTION_AT.x:
		offset_caption_label = cap
	return _text(value, Palette.display_font(), Palette.SIZE_DISPLAY, Palette.SONAR, Vector2(x, VALUE_AT.y))


func _button(text: String, cb: Callable, variant: String = "default") -> Button:
	var b := UiKit.make_button(text, "", variant, int(BUTTON_H))
	b.name = text.replace(" ", "")
	b.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	b.size = Vector2(BUTTON_W, BUTTON_H)
	b.pressed.connect(cb)
	return b


## Places step buttons left to right on the button row.
func _button_row(buttons: Array[Button]) -> void:
	var x := INSTRUCTION_AT.x
	for b in buttons:
		b.position = Vector2(x, BUTTONS_Y)
		_content.add_child(b)
		x += BUTTON_W + BUTTON_GAP


# --- steps -------------------------------------------------------------------------------------


func show_step(s: int) -> void:
	conductor.stop()
	set_quiet(false)
	conductor.offset_override = NAN
	step = s
	_clear_content()
	audio_phase = AudioPhase.IDLE
	match s:
		Step.INTRO:
			_instruction(INTRO_COPY)
			_add_stage()
			begin_button = _button("Begin", func() -> void: show_step(Step.AUDIO), "primary")
			_button_row([begin_button])
			begin_button.grab_focus()
		Step.AUDIO:
			_build_audio_step()
		Step.VISUAL:
			_build_visual_step()
		Step.SUMMARY:
			_build_summary_step()
	if _chips != null:
		_chips.queue_redraw()


func _add_stage() -> void:
	_stage = _painter("Stage", STAGE_RECT, _draw_stage)
	_stage.clip_contents = true
	_content.add_child(_stage)


func _build_audio_step() -> void:
	_instruction("Tap to each ping. The first 4 are warm-up.")
	result_label = _offset_readout("AUDIO OFFSET", "", VALUE_AT.x)
	var cf := _caption_font()
	caption_label = _text("", cf, Palette.SIZE_LABEL, Palette.SONAR, STATE_AT)
	counter_label = _text("", Palette.display_font(), Palette.SIZE_HEADING, Palette.TEXT_HI, COUNTER_AT)
	tap_feedback_label = _text("", cf, Palette.SIZE_LABEL, Palette.TEXT_MID, FEEDBACK_AT)
	previous_label = _text("", cf, Palette.SIZE_LABEL, Palette.TEXT_MID, PREVIOUS_AT)
	status_label = _text("", Palette.font(), Palette.SIZE_BODY, Palette.TEXT_HI,
		Vector2(INSTRUCTION_AT.x, STATUS_TOP + Palette.font().get_ascent(Palette.SIZE_BODY)), LEFT_COL_W)
	_add_stage()
	_side = _painter("TapGrid", SIDE_PANEL, _draw_tap_grid)
	_content.add_child(_side)
	accept_button = _button("Accept Offset", accept_audio, "primary")
	retry_button = _button("Retry Test", begin_audio_test)
	_button_row([accept_button, retry_button])
	begin_audio_test()


func _build_visual_step() -> void:
	_instruction("Adjust until the flash and the ping land together.")
	result_label = _offset_readout("VISUAL OFFSET", "", VALUE_AT.x)
	_add_stage()
	_side = _painter("VisualHelp", SIDE_PANEL, _draw_visual_help)
	_content.add_child(_side)
	visual_slider = StepSlider.new()
	visual_slider.name = "VisualSlider"
	visual_slider.position = SLIDER_RECT.position
	visual_slider.size = SLIDER_RECT.size
	visual_slider.custom_minimum_size = SLIDER_RECT.size
	var start_ms := roundf(CalibrationMath.visual_offset_clamp(pending_visual, true) * 1000.0)
	visual_slider.setup(-200.0, 200.0, 1.0, start_ms, 10.0)
	visual_slider.value_changed.connect(_on_visual_changed)
	_content.add_child(visual_slider)
	var cf := _caption_font()
	var track_x0 := SLIDER_RECT.position.x + StepSlider.PAD_X
	var track_x1 := SLIDER_RECT.end.x - StepSlider.PAD_X
	_text("-200 MS", cf, Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(track_x0, SCALE_BASE))
	var zero := _text("0", cf, Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(0.0, SCALE_BASE))
	zero.size.x = 80.0
	zero.position.x = (track_x0 + track_x1) * 0.5 - 40.0
	zero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hi := _text("+200 MS", cf, Palette.SIZE_LABEL, Palette.TEXT_LO, Vector2(0.0, SCALE_BASE))
	hi.size.x = 200.0
	hi.position.x = track_x1 - 200.0
	hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	accept_button = _button("Accept Offset", accept_visual, "primary")
	retry_button = _button("Retry Test", func() -> void: visual_slider.set_value(0.0))
	_button_row([accept_button, retry_button])
	_on_visual_changed(visual_slider.value)
	# WR-02: measure against the audio offset that is about to be saved, not the old one.
	conductor.offset_override = pending_audio
	_start_loop()
	visual_slider.grab_focus()


func _build_summary_step() -> void:
	_offset_readout("AUDIO OFFSET", format_ms(pending_audio), VALUE_AT.x)
	_offset_readout("VISUAL OFFSET", format_ms(pending_visual), SUMMARY_VISUAL_X)
	if Settings.calibration_done:
		_text("CURRENTLY SAVED  AUDIO %s  ·  VISUAL %s" % [format_ms(Settings.audio_offset),
			format_ms(Settings.visual_offset)], _caption_font(), Palette.SIZE_LABEL, Palette.TEXT_LO, SAVED_AT,
			INSTRUCTION_W)
	save_button = _button("Save and Continue", save_and_continue, "primary")
	_button_row([save_button, _button("Redo", func() -> void: show_step(Step.AUDIO))])
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
	_tap_deltas.clear()
	if _side != null:
		_side.queue_redraw()
	taps_recorded = 0
	audio_result = NAN
	audio_phase = AudioPhase.RUNNING
	if status_label != null:
		status_label.text = ""
		# Placeholder while measuring (dim); evaluate_audio writes the value in SONAR.
		result_label.text = RUNNING_VALUE
		result_label.add_theme_color_override("font_color", Color(Palette.TEXT_LO, 0.4))
		previous_label.text = ""
		tap_feedback_label.text = ""
		accept_button.visible = false
		retry_button.visible = false
	_update_tap_labels()
	set_quiet(true)
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
	_tap_deltas.append(roundi(delta * 1000.0))
	if _side != null:
		_side.queue_redraw()
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
	set_quiet(false)
	var taps := CalibrationMath.remove_applied_offset(tap_times, Settings.audio_offset)
	audio_result = CalibrationMath.audio_offset_from_taps(taps, click_times())
	accept_button.visible = false
	retry_button.visible = true
	result_label.add_theme_color_override("font_color", Palette.SONAR)
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
		result_label.text = format_ms(pending_visual)


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
		ScreenTransition.change_scene(MENU_SCENE)


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


func _draw_chips(c: Control) -> void:
	var states := chip_states(step)
	var f := UiKit.chip_font()
	var fs := Palette.SIZE_LABEL
	for i in 3:
		var r := chip_rect(i)
		if i < 2:
			var y := r.position.y + r.size.y * 0.5
			c.draw_line(Vector2(r.end.x, y), Vector2(chip_rect(i + 1).position.x, y),
				Color(Palette.SONAR, 0.35), Palette.EDGE)
		var st: String = states[i]
		var fill: Color
		var edge: Color
		var text_col: Color
		match st:
			"current":
				fill = Color(Palette.ABYSS_600, 0.92)
				edge = Palette.SONAR
				text_col = Palette.TEXT_HI
			"done":
				var info := UiKit.chip_style("info")
				fill = info.fill
				edge = info.edge
				text_col = info.text
			_:
				var muted := UiKit.chip_style("muted")
				fill = Color(Palette.ABYSS_800, 0.6)
				edge = muted.edge
				text_col = muted.text
		var pts := UiKit.chamfer_points(r, Palette.CUT_SM)
		if st == "current" and not _low:
			for g: Array in [[16.0, 0.06], [8.0, 0.12]]:
				c.draw_colored_polygon(UiKit.chamfer_points(r.grow(g[0] * 0.5), Palette.CUT_SM + g[0] * 0.25),
					Color(Palette.SONAR, g[1]))
			c.draw_colored_polygon(pts, Palette.ABYSS_900)
		c.draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		c.draw_polyline(closed, edge, Palette.EDGE, true)
		var label: String = STEP_CHIPS[i]
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon_w := 16.0 + Palette.SP_SM if st == "done" else 0.0
		var x := r.position.x + (r.size.x - tw - icon_w) * 0.5
		var cy := r.position.y + r.size.y * 0.5
		if st == "done":
			UiIcons.draw(c, "check", Rect2(x, cy - 8.0, 16.0, 16.0), text_col)
			x += icon_w
		if st == "current":
			# Current-step bar, like the focus marker bar.
			c.draw_rect(Rect2(r.position.x + Palette.SP_SM, r.position.y + Palette.SP_SM,
				Palette.FOCUS_BAR, r.size.y - Palette.SP_SM * 2.0), Palette.SONAR)
		c.draw_string(f, Vector2(x, cy + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)


## Stage-local point for a design-space point.
static func _local(p: Vector2) -> Vector2:
	return p - STAGE_RECT.position


func _draw_stage(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, STAGE_RECT.size)
	c.draw_style_box(UiKit.style_panel("default", _low), r)
	UiKit.draw_brackets(c, r, Color(Palette.SONAR, 0.8))
	var st := conductor.song_time()
	var lane_col := Palette.lane_color(0)
	# The test lane: a faint lane-1 strip down to the hit line, like one board lane.
	var lane_w := NOTE_R * 2.0 + Palette.SP_LG
	var lx := _local(NOTE_CENTER).x - lane_w * 0.5
	var line_y := _local(Vector2(0.0, HIT_LINE_Y)).y
	c.draw_rect(Rect2(lx, Palette.SP_MD, lane_w, line_y - Palette.SP_MD), Color(lane_col, 0.07))
	c.draw_line(Vector2(lx, Palette.SP_MD), Vector2(lx, line_y), Color(lane_col, 0.25), Palette.EDGE_HAIR)
	c.draw_line(Vector2(lx + lane_w, Palette.SP_MD), Vector2(lx + lane_w, line_y), Color(lane_col, 0.25),
		Palette.EDGE_HAIR)
	# Hit line (UI-SPEC 7.4 style): SONAR glow stroke (not on Low) + 4 px SONAR_PALE core.
	var a := Vector2(HIT_LINE_X.x - STAGE_RECT.position.x, line_y)
	var b := Vector2(HIT_LINE_X.y - STAGE_RECT.position.x, line_y)
	if not _low:
		c.draw_line(a, b, Color(Palette.SONAR, 0.18), HIT_LINE_W + 12.0, true)
	c.draw_line(a, b, Palette.SONAR_PALE, HIT_LINE_W, true)
	var gem := _local(NOTE_CENTER)
	var ring_at := gem
	var age := -1.0
	var pre_ring := -1.0
	if step == Step.AUDIO:
		if audio_phase == AudioPhase.RUNNING and st >= 0.0 and st <= (CLICK_COUNT - 1) * SPB + SPB:
			var p := fposmod(st / SPB, 1.0)
			age = p * SPB
			pre_ring = p
	elif step == Step.VISUAL:
		var vt := st + pending_visual
		var p := fposmod(vt / SPB, 1.0)
		gem = Vector2(gem.x, visual_note_y(p) - STAGE_RECT.position.y)
		ring_at = Vector2(gem.x, line_y)
		age = p * SPB
	if pre_ring >= 0.0:
		# Ping ring closing in on the gem; it reaches the rim on the click.
		var pr := lerpf(PING_R0, NOTE_R, pre_ring)
		c.draw_arc(gem, pr, 0.0, TAU, 64, Color(Palette.SONAR, lerpf(0.15, 0.8, pre_ring)), Palette.EDGE, true)
	NotePainter.draw_note(c, NotePainter.NOTE_NORMAL, 0, gem, NOTE_R, NotePainter.STATE_READY, st)
	var ring := flash_ring(age)
	if not ring.is_empty():
		var col := Palette.mix(lane_col, Palette.WHITE, FxLayer.PERFECT_RING_WHITE_MIX)
		if not _low:
			c.draw_arc(ring_at, ring.r, 0.0, TAU, FxLayer.RING_SEGMENTS,
				Color(lane_col, ring.a * FxLayer.RING_GLOW_ALPHA), ring.w + FxLayer.RING_GLOW_EXTRA_W, true)
		c.draw_arc(ring_at, ring.r, 0.0, TAU, FxLayer.RING_SEGMENTS, Color(col, ring.a), ring.w, true)


## Audio step side panel: the 16 taps as cells (first row = warm-up), each with its offset.
func _draw_tap_grid(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, SIDE_PANEL.size)
	c.draw_style_box(UiKit.style_panel("default", _low), r)
	UiKit.draw_brackets(c, r, Color(Palette.SONAR, 0.8))
	var f := UiKit.chip_font()
	var fs := Palette.SIZE_LABEL
	var pad := float(UiKit.PANEL_PAD)
	c.draw_string(f, Vector2(pad, pad + f.get_ascent(fs)), "TAPS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT_LO)
	c.draw_string(f, Vector2(pad, pad + f.get_ascent(fs)), "WARM-UP ROW 1", HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x - pad * 2.0, fs, Palette.TEXT_LO)
	var origin := TAP_GRID_AT - SIDE_PANEL.position
	var gap := Palette.SP_SM
	var base_off := (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	for i in CLICK_COUNT:
		var cell := Rect2(origin + Vector2((i % 4) * (TAP_CELL.x + gap), floori(i / 4.0) * (TAP_CELL.y + gap)), TAP_CELL)
		var warm := i < CalibrationMath.DEFAULT_DISCARD
		var done := i < _tap_deltas.size()
		var fill := Color(Palette.ABYSS_800, 0.8)
		var edge := Color(Palette.TEXT_LO, 0.35)
		var tc := Palette.TEXT_LO
		var label := "%d" % (i + 1)
		if done:
			label = "%+d" % _tap_deltas[i]
			if warm:
				edge = Color(Palette.TEXT_MID, 0.7)
				tc = Palette.TEXT_MID
			else:
				fill = Palette.mix(Palette.ABYSS_600, Palette.SONAR, 0.22)
				edge = Palette.SONAR
				tc = Palette.TEXT_HI
		var pts := UiKit.chamfer_points(cell, Palette.CUT_SM)
		c.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		c.draw_polyline(pts, edge, Palette.EDGE, true)
		c.draw_string(f, Vector2(cell.position.x, cell.position.y + cell.size.y * 0.5 + base_off), label,
			HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, fs, tc)


## Visual step side panel: the key hints for the slider.
func _draw_visual_help(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, SIDE_PANEL.size)
	c.draw_style_box(UiKit.style_panel("default", _low), r)
	UiKit.draw_brackets(c, r, Color(Palette.SONAR, 0.8))
	var f := UiKit.chip_font()
	var fs := Palette.SIZE_LABEL
	var pad := float(UiKit.PANEL_PAD)
	c.draw_string(f, Vector2(pad, pad + f.get_ascent(fs)), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Palette.TEXT_LO)
	var rows := [["LEFT / RIGHT", "1 MS"], ["HOLD", "10 MS STEPS"], ["ENTER", "ACCEPT"], ["ESC", "SKIP"]]
	var y := pad + 80.0
	for row: Array in rows:
		c.draw_string(f, Vector2(pad, y), String(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SONAR)
		c.draw_string(f, Vector2(pad, y), String(row[1]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - pad * 2.0, fs,
			Palette.TEXT_MID)
		c.draw_line(Vector2(pad, y + 16.0), Vector2(r.size.x - pad, y + 16.0), Color(Palette.SONAR, 0.15),
			Palette.EDGE_HAIR)
		y += 52.0
