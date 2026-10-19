class_name Killfeed
extends Control
## The versus event log in the right column (03-UI-SPEC 6.6; 03-SPEC req 12, D-32).
## Four 352 x 40 line slots at y 216 / 264 / 312 / 360, newest on top. A new line pushes the
## others down; past killfeed_max_lines the oldest (bottom) drops. Each line lives
## killfeed_life_s (full opacity, then a 0.4 s fade) and its slot closes upward.
## Exactly one line per landed / reflected / absorbed / collision / bounty claimed / solo won /
## imploded / debris event. Glyphs are UiIcons (no emoji; the fonts lack arrows).
## Reads only EventChannel events (spec req 12), never MatchSim.
## Effect contract: UiKit.register_fx, apply_effect_settings(), effect_counts().

const RECT := Rect2(1544.0, 216.0, 352.0, 184.0)
const LINE_W := 352.0
const LINE_H := 40.0
const PITCH := 48.0
const PAD_L := 16.0
const PAD_L_BAR := 20.0
const PAD_R := 12.0
const GAP := 4.0
const GLYPH := 16.0
const BAR_W := 4.0
const TEXT_MAX := 324.0
const FADE_SEC := 0.4
const ENTER_SLIDE := 16.0
const NAME_CHARS := 6
const NAME_SPACING := 0  # killfeed drops the +2 callsign tracking to fit 324 px (03-10 deviation)
const MIN_SQUEEZE := 0.85  # last-resort horizontal condense before a verb is truncated
const MAX_NAME_CHARS := 24
const ELLIPSIS := "..."

static var _name_font: FontVariation

var local_seat: int = 0
var max_lines: int = 4
var life_s: float = 4.0

var _channel: EventChannel
var _names: PackedStringArray = PackedStringArray()
## Each line: {segments, own, victim, age, enter, y, y_from, move}
var _lines: Array[Dictionary] = []
var _reduce: bool = false


func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.register_fx(self)
	apply_effect_settings()


func bind(channel: EventChannel, p_local_seat: int, names: PackedStringArray, cfg: VersusConfig) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	local_seat = p_local_seat
	_names = names
	if cfg != null:
		max_lines = maxi(1, cfg.killfeed_max_lines)
		life_s = maxf(FADE_SEC, cfg.killfeed_life_s)
	_lines.clear()
	if _channel != null:
		_channel.received.connect(on_event)
	queue_redraw()


static func name_font() -> Font:
	if _name_font == null:
		_name_font = FontVariation.new()
		_name_font.base_font = Palette.font()
		_name_font.spacing_glyph = NAME_SPACING
	return _name_font


## UPPERCASE callsign for a seat; unknown seats render "?" (T-03-25).
func name_of(seat: int) -> String:
	if seat < 0 or seat >= _names.size():
		return "?"
	var n := _names[seat].strip_edges().to_upper().left(MAX_NAME_CHARS)
	return "?" if n.is_empty() else n


# ---- Line building ----------------------------------------------------------------------

static func _text(s: String, role: String = "word", reward: int = -1) -> Dictionary:
	return {"kind": "text", "text": s, "role": role, "reward": reward}


static func _glyph(g: String) -> Dictionary:
	return {"kind": "glyph", "glyph": g, "role": "icon"}


func _name(seat: int) -> Dictionary:
	return _text(name_of(seat), "name")


static func _payload(reward: int) -> Dictionary:
	return _text(Reward.feed_name(reward), "payload", reward)


## Builds the line for one event, or {} when the event produces no line.
func line_for(e: Dictionary) -> Dictionary:
	var segs: Array[Dictionary] = []
	var actor := -1
	var victim := -1
	var neutral: Array[int] = []
	match String(e.get("type", "")):
		GameEvent.LANDED:
			var from := int(e.get("from", -1))
			var to := int(e.get("to", -1))
			var reward := int(e.get("reward", -1))
			if Reward.is_buff(reward):
				return {}
			if bool(e.get("debris", false)) or Reward.is_debris(reward):
				segs.append(_glyph("skull"))
				var n := _name(from)
				n["role"] = "wreck"
				segs.append(n)
			else:
				segs.append(_name(from))
			segs.append_array([_glyph("arrow_right"), _payload(reward), _glyph("arrow_right"), _name(to)])
			actor = from
			victim = to
		GameEvent.REFLECTED:
			var by := int(e.get("by", -1))
			segs.append_array([_name(by), _glyph("reflect"), _text("REFLECTED"), _payload(int(e.get("reward", -1)))])
			actor = by
		GameEvent.ABSORBED:
			var to := int(e.get("to", -1))
			segs.append_array([_name(to), _glyph("shield"), _text("blocked")])
			actor = to
		GameEvent.COLLISION:
			var a := int(e.get("a", -1))
			var b := int(e.get("b", -1))
			segs.append_array([_name(a), _glyph("cross"), _name(b), _text("collided")])
			neutral = [a, b]
		GameEvent.BOUNTY_CLAIMED:
			var from := int(e.get("from", -1))
			var to := int(e.get("to", -1))
			segs.append_array([_glyph("bounty"), _name(from), _text("claimed the bounty on"), _name(to)])
			actor = from
			victim = to
		GameEvent.DUEL_RESULT:
			var w := int(e.get("winner", -1))
			if w < 0:
				return {}
			segs.append_array([_name(w), _text("wins the solo")])
			actor = w
		GameEvent.IMPLODED:
			var s := int(e.get("seat", -1))
			segs.append_array([_glyph("skull"), _name(s), _text("imploded")])
			victim = s
		_:
			return {}
	var own := actor == local_seat or neutral.has(local_seat)
	var vic := not own and victim == local_seat
	_color_segments(segs, own or vic)
	var squeeze := _fit(segs, own or vic)
	return {"segments": segs, "own": own, "victim": vic, "squeeze": squeeze}


func _color_segments(segs: Array[Dictionary], you: bool) -> void:
	var base := Palette.TEXT_HI if you else Palette.TEXT_MID
	for s in segs:
		var c := base
		if s.get("glyph", "") == "bounty":
			c = Palette.REWARD_GOLD
		elif s["role"] == "wreck" and not you:
			c = Palette.TEXT_LO
		s["color"] = c


static func _seg_width(s: Dictionary) -> float:
	if s["kind"] == "glyph":
		return GLYPH
	var f: Font = name_font() if s["role"] == "name" or s["role"] == "wreck" else Palette.font()
	return f.get_string_size(String(s["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x


## Gap before segment i (a word space between two text segments, else 4 px).
static func _gap(prev: Dictionary, cur: Dictionary) -> float:
	if prev["kind"] == "text" and cur["kind"] == "text":
		return Palette.font().get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.SIZE_LABEL).x
	return GAP


static func content_width(segs: Array) -> float:
	var w := 0.0
	for i in segs.size():
		if i > 0:
			w += _gap(segs[i - 1], segs[i])
		w += _seg_width(segs[i])
	return w


## Too long: collapse payload names to their glyph; then truncate callsigns to 6 characters
## (UI-SPEC 6.6). Last resort (the spec's bounty line alone measures ~357 px in Share Tech
## Mono 20): condense horizontally down to MIN_SQUEEZE, then pixel-truncate the longest verb
## segment. Returns the horizontal scale to draw the content with (1.0 = natural).
func _fit(segs: Array[Dictionary], bar: bool) -> float:
	var max_w := minf(TEXT_MAX, LINE_W - (PAD_L_BAR if bar else PAD_L) - PAD_R)
	if content_width(segs) <= max_w:
		return 1.0
	for i in segs.size():
		if segs[i]["role"] == "payload":
			var g := Reward.glyph(int(segs[i]["reward"]))
			if g != "":
				segs[i] = {"kind": "glyph", "glyph": g, "role": "payload_icon", "color": segs[i]["color"],
					"reward": segs[i]["reward"]}
	if content_width(segs) <= max_w:
		return 1.0
	for s in segs:
		if (s["role"] == "name" or s["role"] == "wreck") and String(s["text"]).length() > NAME_CHARS:
			s["text"] = String(s["text"]).left(NAME_CHARS) + ELLIPSIS
	var w := content_width(segs)
	if w <= max_w:
		return 1.0
	var budget := max_w / MIN_SQUEEZE
	if w > budget:
		var longest := -1
		for i in segs.size():
			if segs[i]["role"] == "word" and (longest < 0 or _seg_width(segs[i]) > _seg_width(segs[longest])):
				longest = i
		if longest >= 0:
			var keep := maxf(_seg_width(segs[longest]) - (w - budget), 0.0)
			segs[longest]["text"] = ProgressTrack.truncate_px(String(segs[longest]["text"]), Palette.font(),
				Palette.SIZE_LABEL, keep)
		w = content_width(segs)
	return clampf(max_w / maxf(w, 1.0), 0.0, 1.0)


# ---- Events and timing ------------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	var line := line_for(e)
	if line.is_empty():
		return
	push_line(line)


func push_line(line: Dictionary) -> void:
	line["age"] = 0.0
	line["enter"] = 1.0 if _reduce else 0.0
	line["enter_alpha"] = 0.0
	line["y"] = 0.0
	line["y_from"] = 0.0
	line["move"] = 1.0
	_lines.push_front(line)
	while _lines.size() > max_lines:
		_lines.pop_back()
	_reslot()
	queue_redraw()


## Retargets every line to its slot; lines that change slot glide over DUR_FAST (jump under
## Reduce motion). The new top line starts in place (it slides in from the right instead).
func _reslot() -> void:
	for i in _lines.size():
		var l := _lines[i]
		var target := PITCH * i
		if is_equal_approx(float(l.get("slot_y", -1.0)), target):
			continue
		if _reduce or not l.has("slot_y"):
			l["y"] = target
			l["move"] = 1.0
		else:
			l["y_from"] = float(l["y"])
			l["move"] = 0.0
		l["slot_y"] = target


func step(dt: float) -> void:
	if _lines.is_empty():
		return
	var removed := false
	var moving := false
	for l in _lines:
		# Checked before advancing so the frame an animation completes still redraws.
		if float(l["enter"]) < 1.0 or float(l["move"]) < 1.0 or float(l["age"]) + dt > life_s - FADE_SEC:
			moving = true
		l["age"] = float(l["age"]) + dt
		if float(l["enter"]) < 1.0:
			l["enter"] = minf(float(l["enter"]) + dt / Palette.DUR_BASE, 1.0)
		if float(l["move"]) < 1.0:
			l["move"] = minf(float(l["move"]) + dt / Palette.DUR_FAST, 1.0)
			var k := 1.0 - pow(1.0 - float(l["move"]), 3.0)
			l["y"] = lerpf(float(l["y_from"]), float(l["slot_y"]), k)
		elif l.has("slot_y"):
			l["y"] = float(l["slot_y"])
		if float(l["age"]) >= life_s:
			removed = true
	if removed:
		_lines = _lines.filter(func(l: Dictionary) -> bool: return float(l["age"]) < life_s)
		_reslot()
	# Redraw only while a line slides, glides or fades (WR-10); settled lines are static.
	if moving or removed:
		queue_redraw()


func _process(delta: float) -> void:
	step(delta)


func _alpha(l: Dictionary) -> float:
	var enter := float(l["enter"])
	var age := float(l["age"])
	var life := 1.0
	if age > life_s - FADE_SEC:
		life = clampf((life_s - age) / FADE_SEC, 0.0, 1.0)
	return enter * life


func _slide(l: Dictionary) -> float:
	if _reduce:
		return 0.0
	var k := 1.0 - pow(1.0 - float(l["enter"]), 3.0)
	return ENTER_SLIDE * (1.0 - k)


## Read-only view for tests: {segments, own, victim, age, alpha, y (screen), x_offset, text}.
func lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _lines:
		out.append({"segments": l["segments"], "own": l["own"], "victim": l["victim"], "age": l["age"],
			"alpha": _alpha(l), "y": RECT.position.y + float(l["y"]), "x_offset": _slide(l),
			"squeeze": float(l.get("squeeze", 1.0)), "text": line_text(l)})
	return out


## Plain text of a line with glyphs as "[name]", e.g. "ORCA [reflect] REFLECTED Ink Cloud".
static func line_text(line: Dictionary) -> String:
	var parts: PackedStringArray = []
	for s: Dictionary in line.get("segments", []):
		parts.append("[%s]" % s["glyph"] if s["kind"] == "glyph" else String(s["text"]))
	return " ".join(parts)


func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	if _reduce:
		for l in _lines:
			l["move"] = 1.0
			if l.has("slot_y"):
				l["y"] = l["slot_y"]
	queue_redraw()


func effect_counts() -> Dictionary:
	return {"slide": not _reduce}


# ---- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var fs := Palette.SIZE_LABEL
	var f := Palette.font()
	var base_off := (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	for l in _lines:
		var a := _alpha(l)
		if a <= 0.0:
			continue
		var x0 := _slide(l)
		var y := float(l["y"])
		var r := Rect2(x0, y, LINE_W, LINE_H)
		draw_colored_polygon(UiKit.chamfer_points(r, Palette.CUT_SM),
			Palette.alpha(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA * a))
		var bar := bool(l["own"]) or bool(l["victim"])
		if bar:
			var bc := Palette.WARNING_RED if bool(l["victim"]) else Palette.SONAR
			draw_rect(Rect2(x0, y + Palette.CUT_SM, BAR_W, LINE_H - Palette.CUT_SM), Palette.alpha(bc, a))
		var left := x0 + (PAD_L_BAR if bar else PAD_L)
		draw_set_transform(Vector2(left, 0.0), 0.0, Vector2(float(l.get("squeeze", 1.0)), 1.0))
		var cy := y + LINE_H * 0.5
		var segs: Array = l["segments"]
		var xs: PackedFloat32Array = _seg_xs(l)
		for i in segs.size():
			var s: Dictionary = segs[i]
			var x := xs[i]
			var c: Color = s["color"]
			c = Palette.alpha(c, c.a * a)
			if s["kind"] == "glyph":
				UiIcons.draw(self, String(s["glyph"]), Rect2(x, cy - GLYPH * 0.5, GLYPH, GLYPH), c)
			else:
				var font: Font = name_font() if s["role"] == "name" or s["role"] == "wreck" else f
				draw_string(font, Vector2(x, cy + base_off), String(s["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Segment x offsets of a line, measured once and stored on the line (WR-10): no text shaping
## lookups per frame.
static func _seg_xs(l: Dictionary) -> PackedFloat32Array:
	var xs = l.get("xs")
	if xs is PackedFloat32Array:
		return xs
	var segs: Array = l["segments"]
	var out := PackedFloat32Array()
	out.resize(segs.size())
	var x := 0.0
	for i in segs.size():
		if i > 0:
			x += _gap(segs[i - 1], segs[i])
		out[i] = x
		x += _seg_width(segs[i])
	l["xs"] = out
	return out
