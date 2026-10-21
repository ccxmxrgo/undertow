class_name LowEffectsHint
extends RefCounted
## Slow-frame hint shared by ResultsScreen and VersusResultsScreen (05-06, D-06, AV-05).
## When the dive stuttered (FrameWatch.should_hint) the results data carries a local-only
## "slow_frames": true. The flag is never sent over the network: online, each PC adds its own
## value to a local copy of the results before showing them.
## Layout (D-13, no new tokens): the button takes the 4th slot of the 424 px results button pitch,
## (1368, 752) 400 x 64, ending at x 1768; the line is Body / TEXT_MID, right-aligned at x 1768 on
## the left hint's baseline 872.

const TEXT := "Some frames came late on this PC. Low effects can help."
const DONE_TEXT := "Low effects is on. Change it in Settings > Display."
const BUTTON_TEXT := "Turn on Low effects"
const DONE_BUTTON_TEXT := "Low effects on"
const BUTTON_RECT := Rect2(1368.0, 752.0, 400.0, 64.0)
const LINE_RIGHT := 1768.0
const LINE_BASELINE := 872.0


## True when the results data says the dive stuttered (a real bool true) and Low effects is off.
static func wanted(data: Dictionary) -> bool:
	var v: Variant = data.get("slow_frames", false)
	return v is bool and v and not Settings.low_effects


## One press: Low effects on, saved to the player's settings file, effect nodes notified.
static func enable_low_effects() -> void:
	Settings.low_effects = true
	Settings.save_to(Settings.save_path)
	Settings.settings_changed.emit()


## Replaces the hint line's text, keeping its right edge at LINE_RIGHT.
static func set_line(l: Label, text: String) -> void:
	if l == null or not is_instance_valid(l):
		return
	l.text = text
	var f := l.get_theme_font("font")
	var w := ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
	l.size.x = w
	l.position.x = LINE_RIGHT - w


## Closes a focus loop over `order`: Right / Down / Tab next, Left / Up / Shift+Tab previous.
static func link_loop(order: Array[Button]) -> void:
	for i in order.size():
		var b := order[i]
		var nxt := b.get_path_to(order[(i + 1) % order.size()])
		var prv := b.get_path_to(order[(i + order.size() - 1) % order.size()])
		b.focus_neighbor_right = nxt
		b.focus_neighbor_bottom = nxt
		b.focus_next = nxt
		b.focus_neighbor_left = prv
		b.focus_neighbor_top = prv
		b.focus_previous = prv


## Builds the hint button at BUTTON_RECT under `parent` and appends it to the closed focus loop
## of `order`. After the press it leaves the loop (FOCUS_NONE) and focus returns to the last
## existing button, so focus never sits on a disabled control. `on_done` updates the line.
static func add_button(parent: Control, order: Array[Button], on_done: Callable) -> Button:
	var b := UiKit.make_button(BUTTON_TEXT, "", "default", int(BUTTON_RECT.size.y))
	b.name = "TurnOnLowEffects"
	b.position = BUTTON_RECT.position
	b.size = BUTTON_RECT.size
	parent.add_child(b)
	var base: Array[Button] = []
	for o in order:
		if o != null:
			base.append(o)
	var full: Array[Button] = base.duplicate()
	full.append(b)
	link_loop(full)
	b.pressed.connect(func() -> void:
		if b.disabled:
			return
		enable_low_effects()
		b.text = DONE_BUTTON_TEXT
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		if not base.is_empty():
			link_loop(base)
			if b.is_inside_tree():
				base[base.size() - 1].grab_focus()
		on_done.call())
	return b
