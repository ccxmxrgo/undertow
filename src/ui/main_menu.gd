class_name MainMenu
extends Control
## Entry screen (02.2 UI-SPEC section 5, "living title screen"): an AbyssBackdrop (variant
## title) behind the generated UNDERTOW wordmark, the tagline, eight icon buttons at fixed
## positions (order unchanged), one FocusMarker, a one-line description of the focused item
## and a status line for prompts and errors.
## First launch (Settings.calibration_done false) routes straight to the skippable wizard once per
## session; an output-device change since the last calibration shows the re-calibrate prompt.

const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"
const FOLDER_MSG_SEC := 6.0
const CALIBRATION_SCENE := "res://scenes/calibration.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const CHART_SCENE := "res://scenes/chart_song.tscn"
const DEVICE_CHANGED_COPY := "Output device changed. Calibrate Sonar again for accurate timing."
const NO_RECORD_COPY := "No record yet. Finish a dive to set one."
const RECORDS_ERROR_COPY := "Records could not be loaded. Starting with an empty record book."
const NOT_CALIBRATED_BODY := "Timing may feel off until you calibrate. Choose Calibrate Sonar to fix it."
const TAGLINE := "YOUR STREAK IS A TORPEDO"
## Focus descriptions in button order (UI-SPEC 14).
const DESCRIPTIONS: Array[String] = [
	"Pick a song and dive. Your hull is on the line.",
	"Dive without imploding. Records are not saved.",
	"Turn an audio file you own into a playable chart.",
	"Line up audio and visuals for tight timing.",
	"Controls, scroll speed, effects and volume.",
	"Watch the sub play a song by itself.",
	"Add Clone Hero song folders or .zip files.",
	"Surface and close UNDERTOW.",
]

## Layout (UI-SPEC 5), 1920x1080 design pixels.
const ITEM_X := 128.0
const ITEM_W := 512.0
const ITEM_H := 56
const ITEM_TOP := 416.0
const ITEM_PITCH := 64.0
const TAGLINE_BASELINE := 360.0
const TAGLINE_SPACING := 4
const DESC_BASELINE := 960.0
const DESC_W := 760.0
const STATUS_BASELINE := 1000.0
const STATUS_W := 1180.0
const GLYPH_W := 16.0
const KEY_HINT_W := 120.0
const ENTRANCE_SLIDE := 16.0
const PROMPT_POS := Vector2(704.0, 776.0)
const PROMPT_W := 640.0
## Last-dive card (UI-SPEC 5): x 1376..1856, y 840..1000.
const CARD_RECT := Rect2(1376.0, 840.0, 480.0, 160.0)
const CARD_ENTRANCE_DELAY := 0.24
## Seconds between AbyssBackdrop.pulse_hz refreshes from the menu music tempo.
const PULSE_REFRESH_SEC := 1.0
const DIFFICULTY_LANES := {"easy": 0, "medium": 1, "hard": 2, "expert": 3}

## True once the first-launch redirect was taken or skipped this session.
static var boot_handled: bool = false

## True once the records-load error was shown this session (one-time message).
static var records_error_shown: bool = false

## True once the logo fade-in played this session (it fades only on the first show).
static var logo_shown: bool = false

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()

## Test seam: Callable() -> bool replaces SongLibrary.open_songs_folder().
var open_folder: Callable = Callable()

var start_button: Button
var practice_button: Button
var chart_button: Button
var autoplay_button: Button
var calibrate_button: Button
var settings_button: Button
var quit_button: Button
var open_folder_button: Button
var folder_message_label: Label
var prompt_calibrate_button: Button
var prompt_skip_button: Button

var best_label: Label
var records_error_label: Label
## The wordmark (LogoWordmark, TextureRect at 120, 168, 960 x 152).
var logo: LogoWordmark
## One-line description of the focused item (UI-SPEC 14 copy).
var description_label: Label
## Last dive (song, difficulty, length, best depth); hidden without a last song.
var last_dive_card: LastDiveCard

var _prompt: Control
var _empty_state: Control
var _backdrop: AbyssBackdrop
var _items: Control
var _status: VBoxContainer
var _desc_old: Label
var _desc_tween: Tween
var _focus_marker: FocusMarker
var _item_count := 0
var _entrance_tweens: Array[Tween] = []


func _ready() -> void:
	UiLayout.fill_rect(self)
	if theme == null:
		theme = Palette.load_theme()
	_build()
	_route_on_boot.call_deferred()
	# D-07: quiet menu music (no-op when disabled, already playing, or about to calibrate).
	if not needs_first_launch_wizard():
		_menu_music_call("start")
	_sync_pulse()
	if is_inside_tree():
		var t := Timer.new()
		t.name = "PulseTimer"
		t.wait_time = PULSE_REFRESH_SEC
		t.autostart = true
		t.timeout.connect(_sync_pulse)
		add_child(t)
	var lib := get_node_or_null("/root/SongLibrary")
	if lib != null and lib.has_signal("entries_added"):
		lib.entries_added.connect(func(_b: Array) -> void: refresh_last_dive())


## True when this boot should open the calibration wizard instead of the menu.
func needs_first_launch_wizard() -> bool:
	return not Settings.calibration_done and not boot_handled


func _route_on_boot() -> void:
	if needs_first_launch_wizard():
		boot_handled = true
		_go(CALIBRATION_SCENE)


func _build() -> void:
	_backdrop = AbyssBackdrop.new()
	_backdrop.name = "Backdrop"
	_backdrop.variant = "title"
	add_child(_backdrop)

	logo = LogoWordmark.new()
	add_child(logo)
	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.text = TAGLINE
	tagline.add_theme_font_override("font", _spaced_font(TAGLINE_SPACING))
	tagline.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	tagline.add_theme_color_override("font_color", Palette.TEXT_MID)
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at_baseline(tagline, Vector2(ITEM_X, TAGLINE_BASELINE), Palette.SIZE_LABEL)
	add_child(tagline)

	_status = VBoxContainer.new()
	_status.name = "Status"
	_status.add_theme_constant_override("separation", Palette.SP_XS)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.position = Vector2(ITEM_X, STATUS_BASELINE - Palette.font().get_ascent(Palette.SIZE_LABEL))
	_status.custom_minimum_size = Vector2(STATUS_W, 0.0)

	_items = Control.new()
	_items.name = "Items"
	UiLayout.fill_rect(_items)
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items)
	start_button = _item("Start Dive", "dive", "primary", func() -> void: launch(false))
	practice_button = _item("Practice Dive (No-Fail)", "lifebuoy", "default", func() -> void: launch_practice())
	_build_best_line(_items)
	chart_button = _item("Chart a Song", "chart", "default", func() -> void: _go(CHART_SCENE))
	calibrate_button = _item("Calibrate Sonar", "sonar", "default", func() -> void: _calibrate())
	settings_button = _item("Settings", "sliders", "default", func() -> void: _go(SETTINGS_SCENE))
	autoplay_button = _item("Autoplay Dive (test)", "auto", "default", func() -> void: launch(true))
	open_folder_button = _item("Open Songs Folder", "folder", "default", func() -> void: open_songs_folder())
	quit_button = _item("Quit Game", "power", "default", func() -> void:
		if is_inside_tree():
			get_tree().quit())
	_add_key_hint(start_button, "ENTER")
	var items := menu_buttons()
	for i in range(items.size()):
		var b: Button = items[i]
		b.focus_neighbor_top = b.get_path_to(items[(i + items.size() - 1) % items.size()])
		b.focus_neighbor_bottom = b.get_path_to(items[(i + 1) % items.size()])
		var desc: String = DESCRIPTIONS[i]
		b.focus_entered.connect(func() -> void: _show_description(desc))
		b.mouse_entered.connect(func() -> void: _show_description(desc))

	# Focus description (Body 28, cross-fades on change) and the status line under it.
	_desc_old = _make_description()
	description_label = _make_description()
	description_label.name = "Description"
	add_child(_desc_old)
	add_child(description_label)

	folder_message_label = _status_label(true)
	folder_message_label.visible = false
	folder_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_state = _build_empty_state()
	_status.add_child(_empty_state)
	_status.add_child(folder_message_label)
	if records_error_label != null:
		_status.add_child(records_error_label)
	add_child(_status)

	last_dive_card = LastDiveCard.new()
	last_dive_card.name = "LastDiveCard"
	add_child(last_dive_card)
	refresh_last_dive()

	_prompt = _build_prompt()
	add_child(_prompt)
	_focus_marker = FocusMarker.new()
	add_child(_focus_marker)

	_empty_state.visible = not Settings.calibration_done
	_prompt.visible = Settings.device_changed()
	if _prompt.visible:
		prompt_calibrate_button.grab_focus()
	else:
		start_button.grab_focus()
		_show_description(DESCRIPTIONS[0], false)
	_entrance()


## The eight menu buttons in focus order.
func menu_buttons() -> Array:
	return [start_button, practice_button, chart_button, calibrate_button, settings_button, autoplay_button,
		open_folder_button, quit_button]


## The visible "Best: ..." line moved into Song Select (records are per song and difficulty).
## The label stays as a hidden node for harness compatibility; never part of the focus ring.
func _build_best_line(parent: Control) -> void:
	var store := ScoreStore.new()
	store.load()
	var b := store.best(TestCharts.HAND_CHART_ID)
	best_label = Label.new()
	best_label.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	best_label.focus_mode = Control.FOCUS_NONE
	best_label.visible = false
	if b.is_empty():
		best_label.text = NO_RECORD_COPY
	else:
		best_label.text = "Best: %s m   Accuracy %d%%" % [
			Palette.fmt_depth(int(float(b["depth"]))), int(round(float(b["accuracy"])))]
	parent.add_child(best_label)
	if store.load_error and not records_error_shown:
		records_error_shown = true
		records_error_label = _status_label(true)
		records_error_label.text = RECORDS_ERROR_COPY


## Menu button (UI-SPEC 4.2 / 5): 512 x 56 at x 128, tops 416 + 64 * index (8 items, the last
## ends at 920, above the description baseline 960).
func _item(text: String, icon: String, variant: String, cb: Callable) -> Button:
	var i := _item_count
	_item_count += 1
	var b := UiKit.make_button(text, icon, variant, ITEM_H)
	b.name = "Item%d" % i
	b.position = Vector2(ITEM_X, ITEM_TOP + ITEM_PITCH * i)
	b.size = Vector2(ITEM_W, ITEM_H)
	b.pressed.connect(cb)
	_items.add_child(b)
	return b


## Primary-button key hint (UI-SPEC 4.2): Label 20 TEXT_LO, right-aligned 24 px inset.
func _add_key_hint(b: Button, text: String) -> void:
	var l := Label.new()
	l.name = "KeyHint"
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.TEXT_LO)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(ITEM_W - Palette.SP_LG - KEY_HINT_W, 0.0)
	l.size = Vector2(KEY_HINT_W, ITEM_H)
	b.add_child(l)


func _make_description() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_BODY)
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	_at_baseline(l, Vector2(ITEM_X, DESC_BASELINE), Palette.SIZE_BODY)
	l.size = Vector2(DESC_W, Palette.font().get_height(Palette.SIZE_BODY))
	return l


## Shows `text` as the focus description; the old line fades out while the new one fades in
## (DUR_FAST). The text changes immediately (tests and the harness read the new copy).
func _show_description(text: String, animate: bool = true) -> void:
	if description_label == null or description_label.text == text:
		return
	_desc_old.text = description_label.text
	description_label.text = text
	if _desc_tween != null and _desc_tween.is_valid():
		_desc_tween.kill()
	if not animate or not is_inside_tree():
		description_label.modulate.a = 1.0
		_desc_old.modulate.a = 0.0
		return
	description_label.modulate.a = 0.0
	_desc_old.modulate.a = 1.0
	_desc_tween = create_tween().set_parallel(true)
	_desc_tween.tween_property(description_label, "modulate:a", 1.0, Palette.DUR_FAST)
	_desc_tween.tween_property(_desc_old, "modulate:a", 0.0, Palette.DUR_FAST)


## Status line label (Label 20). Errors are WARNING_RED with a "!" glyph at the left.
func _status_label(error: bool) -> Label:
	var l := Label.new()
	l.focus_mode = Control.FOCUS_NONE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.WARNING_RED if error else Palette.TEXT_MID)
	l.custom_minimum_size = Vector2(STATUS_W, 0.0)
	if error:
		var pad := StyleBoxEmpty.new()
		pad.content_margin_left = GLYPH_W + Palette.SP_SM
		l.add_theme_stylebox_override("normal", pad)
		var g := StatusGlyph.new()
		g.position = Vector2(0.0, 2.0)
		g.size = Vector2(GLYPH_W, GLYPH_W)
		l.add_child(g)
	return l


## Red warning triangle with a "!" (polygons; the fonts have no warning glyph).
class StatusGlyph:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var tri := PackedVector2Array([Vector2(w * 0.5, 1.0), Vector2(w - 1.0, w - 1.0), Vector2(1.0, w - 1.0),
			Vector2(w * 0.5, 1.0)])
		draw_polyline(tri, Palette.WARNING_RED, 2.0, true)
		draw_rect(Rect2(w * 0.5 - 1.0, w * 0.36, 2.0, w * 0.3), Palette.WARNING_RED)
		draw_rect(Rect2(w * 0.5 - 1.0, w * 0.74, 2.0, 2.0), Palette.WARNING_RED)


func _build_empty_state() -> Control:
	var row := HBoxContainer.new()
	row.name = "EmptyState"
	row.add_theme_constant_override("separation", Palette.SP_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Label.new()
	h.text = "SONAR NOT CALIBRATED"
	h.add_theme_font_override("font", _spaced_font(2))
	h.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	h.add_theme_color_override("font_color", Palette.SONAR)
	row.add_child(h)
	var b := Label.new()
	b.text = NOT_CALIBRATED_BODY
	b.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	b.add_theme_color_override("font_color", Palette.TEXT_MID)
	row.add_child(b)
	return row


## Output-device-changed prompt: a glass panel right of the menu column with the copy and
## the Calibrate Sonar / Skip for now buttons (48 tall).
func _build_prompt() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DevicePrompt"
	panel.position = PROMPT_POS
	panel.custom_minimum_size = Vector2(PROMPT_W, 0.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.SP_MD)
	panel.add_child(box)
	var l := Label.new()
	l.text = DEVICE_CHANGED_COPY
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.TEXT_MID)
	l.custom_minimum_size = Vector2(PROMPT_W - UiKit.PANEL_PAD * 2, 0.0)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.SP_MD)
	box.add_child(row)
	prompt_calibrate_button = UiKit.make_button("Calibrate Sonar", "", "primary", 48)
	prompt_calibrate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_calibrate_button.pressed.connect(func() -> void: _calibrate())
	row.add_child(prompt_calibrate_button)
	prompt_skip_button = UiKit.make_button("Skip for now", "", "default", 48)
	prompt_skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_skip_button.pressed.connect(func() -> void:
		_prompt.visible = false
		start_button.grab_focus())
	row.add_child(prompt_skip_button)
	# G3: the prompt is modal for focus. Left / Right (D-pad, stick, arrows) and Tab swap between
	# its two buttons; Up / Down stay put instead of leaking to the menu items behind the panel.
	for pair: Array in [[prompt_calibrate_button, prompt_skip_button], [prompt_skip_button, prompt_calibrate_button]]:
		var b: Button = pair[0]
		var other := b.get_path_to(pair[1])
		var own := b.get_path_to(b)
		b.focus_neighbor_left = other
		b.focus_neighbor_right = other
		b.focus_next = other
		b.focus_previous = other
		b.focus_neighbor_top = own
		b.focus_neighbor_bottom = own
	return panel


## Entrance (UI-SPEC 5): items fade + slide 16 px from the left with a 40 ms stagger (fade
## only under Reduce motion); the logo fades in over 300 ms on the first show per session.
func _entrance() -> void:
	if not is_inside_tree():
		return
	var reduce := UiKit.reduce_motion()
	if not logo_shown:
		logo_shown = true
		var lt := logo.fade_in()
		if lt != null:
			_entrance_tweens.append(lt)
	var items := menu_buttons()
	for i in items.size():
		var b: Button = items[i]
		var final_x := b.position.x
		b.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, Palette.DUR_BASE).set_delay(Palette.STAGGER_MENU * i)
		if not reduce:
			b.position.x = final_x - ENTRANCE_SLIDE
			tw.tween_property(b, "position:x", final_x, Palette.DUR_BASE).set_delay(Palette.STAGGER_MENU * i) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_entrance_tweens.append(tw)
	if last_dive_card != null and last_dive_card.visible:
		last_dive_card.modulate.a = 0.0
		var ct := create_tween()
		ct.tween_property(last_dive_card, "modulate:a", 1.0, Palette.DUR_BASE).set_delay(CARD_ENTRANCE_DELAY)
		_entrance_tweens.append(ct)


## Jump every entrance animation to its final state (tests; harness).
func finish_entrance() -> void:
	for tw in _entrance_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_entrance_tweens.clear()
	logo.modulate.a = 1.0
	if last_dive_card != null:
		last_dive_card.modulate.a = 1.0
	var items := menu_buttons()
	for i in items.size():
		var b: Button = items[i]
		b.modulate.a = 1.0
		b.position = Vector2(ITEM_X, ITEM_TOP + ITEM_PITCH * i)


func _spaced_font(spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = Palette.font()
	v.spacing_glyph = spacing
	return v


## Places a Label so its first baseline sits at `at.y` (Labels have no top padding here).
func _at_baseline(l: Label, at: Vector2, font_size: int) -> void:
	l.position = Vector2(at.x, at.y - Palette.font().get_ascent(font_size))


func prompt_visible() -> bool:
	return _prompt.visible


func empty_state_visible() -> bool:
	return _empty_state.visible


## Opens Song Select with the run flags; the chart is chosen there (D-13).
func launch(autoplay: bool) -> void:
	SongSelect.run_autoplay = autoplay
	SongSelect.run_practice = false
	_go(SONG_SELECT_SCENE)


## D-09: No-Fail run that never touches the persisted Settings.no_fail.
func launch_practice() -> void:
	SongSelect.run_autoplay = false
	SongSelect.run_practice = true
	_go(SONG_SELECT_SCENE)


## D-05/D-20: works before any scan; shows a red line for 6 s when the file manager fails.
func open_songs_folder() -> void:
	var lib := get_node_or_null("/root/SongLibrary")
	var ok := true
	if open_folder.is_valid():
		ok = bool(open_folder.call())
	else:
		ok = lib != null and lib.open_songs_folder()
	if ok:
		return
	var path := ProjectSettings.globalize_path("user://songs").simplify_path()
	folder_message_label.text = "Could not open the Songs folder. It is at %s" % path
	folder_message_label.visible = true
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_interval(FOLDER_MSG_SEC)
		tw.tween_callback(func() -> void: folder_message_label.visible = false)


func _calibrate() -> void:
	# Pitfall 7: the click-track calibration must not hear the menu music.
	_menu_music_call("stop", 0.4)
	_go(CALIBRATION_SCENE)


func _menu_music_call(method: String, arg: Variant = null) -> void:
	var mm := get_node_or_null("/root/MenuMusic") if is_inside_tree() else null
	if mm == null:
		return
	if arg == null:
		mm.call(method)
	else:
		mm.call(method, arg)


## Drives the abyss bio-speck pulse from the menu music tempo (0.5 Hz without a tempo).
func _sync_pulse() -> void:
	if _backdrop == null:
		return
	var mm := get_node_or_null("/root/MenuMusic") if is_inside_tree() else null
	_backdrop.pulse_hz = float(mm.pulse_hz()) if mm != null else 0.5


static func difficulty_lane(diff: String) -> int:
	return int(DIFFICULTY_LANES.get(diff, 0))


## Fills the last-dive card from Settings.last_song_id / last_difficulty and the record book.
## Hidden when there is no last song or it is no longer in the library.
func refresh_last_dive() -> void:
	if last_dive_card == null:
		return
	var lib := get_node_or_null("/root/SongLibrary") if is_inside_tree() else null
	var sid: String = Settings.last_song_id
	var e: SongEntry = null
	if sid != "" and lib != null:
		e = lib.find(sid)
	if e == null:
		last_dive_card.visible = false
		return
	var diff: String = Settings.last_difficulty
	var best := {}
	var fp := str(e.difficulty(diff).get("fingerprint", ""))
	if fp != "":
		var store := ScoreStore.new()
		store.load()
		best = store.best(fp)
	last_dive_card.setup(e.title, diff, e.length_sec, best)
	last_dive_card.visible = true


## Last-dive card (UI-SPEC 5 / 14): glass panel with brackets, "LAST DIVE" caption, title,
## difficulty chip + length, "BEST" and the best depth in REWARD_GOLD (or "No record yet.").
class LastDiveCard:
	extends Control

	const PAD := 24.0
	const TITLE_W := 432.0
	const CAPTION_BASE := 36.0
	const TITLE_BASE := 76.0
	const CHIP_Y := 88.0
	const BEST_BASE := 144.0
	const DEPTH_BASE := 148.0
	const DEPTH_RIGHT := 456.0
	const VALUE_W := 280.0
	const NO_RECORD := "No record yet."

	var caption_label: Label
	var title_label: Label
	var length_label: Label
	var best_caption: Label
	var best_value_label: Label
	var empty_label: Label
	var chip_text := ""
	var chip_lane := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		position = MainMenu.CARD_RECT.position
		size = MainMenu.CARD_RECT.size
		caption_label = _label("LAST DIVE", "CaptionLabel", Palette.SIZE_LABEL, Palette.SONAR, CAPTION_BASE)
		title_label = _label("", "", Palette.SIZE_BODY, Palette.TEXT_HI, TITLE_BASE)
		title_label.size.x = TITLE_W
		title_label.clip_text = true
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		length_label = _label("", "", Palette.SIZE_LABEL, Palette.TEXT_MID, 0.0)
		best_caption = _label("BEST", "CaptionLabel", Palette.SIZE_LABEL, Palette.TEXT_LO, BEST_BASE)
		best_value_label = _label("", "HeadingLabel", Palette.SIZE_HEADING, Palette.REWARD_GOLD, DEPTH_BASE,
			Palette.display_font())
		best_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		empty_label = _label(NO_RECORD, "", Palette.SIZE_LABEL, Palette.TEXT_LO, BEST_BASE)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for l in [best_value_label, empty_label]:
			l.position.x = DEPTH_RIGHT - VALUE_W
			l.size.x = VALUE_W
		UiKit.register_fx(self)

	func _label(text: String, variation: String, fs: int, color: Color, baseline: float,
			font: Font = null) -> Label:
		var l := Label.new()
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if variation != "":
			l.theme_type_variation = variation
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", color)
		if font != null:
			l.add_theme_font_override("font", font)
		var f := font if font != null else Palette.font()
		l.position = Vector2(PAD, baseline - f.get_ascent(fs))
		l.size = Vector2(0.0, f.get_height(fs))
		add_child(l)
		return l

	func setup(title: String, diff: String, length_sec: float, best: Dictionary) -> void:
		title_label.text = title
		chip_text = diff.to_upper()
		chip_lane = MainMenu.difficulty_lane(diff)
		var chip_w := UiKit.chip_width(chip_text, "difficulty") if chip_text != "" else 0.0
		length_label.text = SongListModel.fmt_length(length_sec) if length_sec > 0.0 else ""
		var lf := Palette.font()
		var fs := Palette.SIZE_LABEL
		var cy := CHIP_Y + UiKit.CHIP_H * 0.5
		var base := cy + (lf.get_ascent(fs) - lf.get_descent(fs)) * 0.5
		var lx := PAD + (chip_w + Palette.SP_MD if chip_w > 0.0 else 0.0)
		length_label.position = Vector2(lx, base - lf.get_ascent(fs))
		var has_best := not best.is_empty()
		best_value_label.visible = has_best
		empty_label.visible = not has_best
		best_value_label.text = "%s M" % Palette.fmt_depth(int(float(best.get("depth", 0.0)))) if has_best else ""
		queue_redraw()

	func apply_effect_settings() -> void:
		queue_redraw()

	func effect_counts() -> Dictionary:
		return {"glow": not UiKit.low_effects()}

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiKit.style_panel(), r)
		UiKit.draw_brackets(self, r, Color(Palette.SONAR, 0.8))
		if chip_text != "":
			var w := UiKit.chip_width(chip_text, "difficulty")
			UiKit.draw_chip(self, Rect2(PAD, CHIP_Y, w, UiKit.CHIP_H), chip_text, "difficulty", chip_lane)


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		ScreenTransition.change_scene(path)
