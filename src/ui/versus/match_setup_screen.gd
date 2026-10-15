class_name MatchSetupScreen
extends Control
## VERSUS match setup (03 UI-SPEC 9.2, MATCH-01, D-18). Left: the MATCH glass panel with the
## Song / Difficulty / Rivals / Bot skill rows, the skill description, "How rewards work" and
## Start Match. Right: the preview panel (cover, title, artist, difficulty, note count and
## reward threshold) and the roster (YOU + bot callsigns with skill chips).
##
## Defaults come from MatchSetup.pending (Versus Bots, Change Match) or MatchSetup.from_settings(),
## always clamped (T-03-32). A stored song id that no longer resolves falls back to the last
## played song, else the Song row is empty and Start Match is disabled (T-03-31).
##
## Focus: the five rows are Buttons in a closed Up/Down loop; Left/Right change the focused row's
## value; Accept on Song opens Song Select pick mode, on Start Match starts the match; Esc / B
## returns to the main menu. Row key handling runs in each row's gui_input (before the GUI focus
## navigation), so UiSounds still sees every press in _input.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SONG_SELECT_SCENE := "res://scenes/song_select.tscn"

## Copy (03 UI-SPEC 14).
const TITLE := "VERSUS"
const SUBTITLE := "Offline match against bot subs. Last hull standing wins."
const CAPTION_MATCH := "MATCH"
const ROW_LABELS: Array[String] = ["Song", "Difficulty", "Rivals", "Bot skill"]
const SKILL_LABELS: Array[String] = ["ROOKIE", "REGULAR", "VETERAN"]
const SKILL_DESCRIPTIONS := {
	"rookie": "Loose timing and frequent misses. Rarely earns a reward.",
	"regular": "Solid timing. Earns a reward now and then.",
	"veteran": "Tight timing. Earns about 3 rewards a song.",
}
const EMPTY_SONG := "No songs installed"
const EMPTY_HINT := "Add songs with Open Songs Folder on the main menu."
## No copy in the spec for "songs exist but none is chosen" (stored song removed, no last song).
const NO_SONG := "Choose a song"
const HOW_CAPTION := "HOW REWARDS WORK"
const HOW_LINES: Array[String] = [
	"Unbroken Perfects fill your torpedo tube. A full tube loads a random reward.",
	"{FIRE} fires it. Disruptors hit your target. Buffs help you.",
	"{TARGET} switches target: AUTO, each rival, ATTACKERS.",
	"Hit the red-ringed notes Perfect to send a torpedo back.",
]
const ROSTER_CAPTION := "SUBS IN THIS MATCH"
const NOTES_FORMAT := "%d NOTES · REWARD EVERY %d PERFECTS"
const HINT_KEYS := "UP DOWN MOVE  ·  LEFT RIGHT CHANGE  ·  ENTER SELECT  ·  ESC BACK"
const HINT_PAD := "D-PAD MOVE  ·  LEFT RIGHT CHANGE  ·  A SELECT  ·  B BACK"
const START_TEXT := "Start Match"

## Rows in focus order.
const ROWS: Array[String] = ["song", "difficulty", "rivals", "skill", "start"]
const ROW_SONG := 0
const ROW_DIFFICULTY := 1
const ROW_RIVALS := 2
const ROW_SKILL := 3
const ROW_START := 4

## Layout (1920x1080 design pixels, UI-SPEC 9.2).
const TITLE_POS := Vector2(64.0, 104.0)
const SUBTITLE_POS := Vector2(64.0, 140.0)
const SETTINGS_RECT := Rect2(64.0, 176.0, 880.0, 728.0)
const PREVIEW_RECT := Rect2(976.0, 176.0, 880.0, 728.0)
const CAPTION_POS := Vector2(96.0, 216.0)
const ROW_X := 96.0
const ROW_W := 816.0
const ROW_H := 64.0
const ROW_TOPS: Array[float] = [240.0, 312.0, 384.0, 456.0, 808.0]
const LABEL_X := 120.0
const VALUE_X := 400.0
const VALUE_W := 456.0
const CHEVRON_LEFT_X := 368.0
const CHEVRON_RIGHT_X := 872.0
const ICON := 24.0
const TILE_H := 48.0
const RIVAL_TILE_X: Array[float] = [400.0, 504.0, 608.0]
const RIVAL_TILE_W := 96.0
const SKILL_TILE_X: Array[float] = [400.0, 568.0, 736.0]
const SKILL_TILE_W := 160.0
const SEL_BAR := Vector2(24.0, 4.0)
const SKILL_DESC_POS := Vector2(120.0, 560.0)
const DIVIDER_Y := 592.0
const HOW_CAPTION_POS := Vector2(120.0, 632.0)
const HOW_BASELINES: Array[float] = [672.0, 704.0, 736.0, 768.0]
const KEY_HINT_W := 120.0
const COVER_RECT := Rect2(1008.0, 208.0, 256.0, 256.0)
const INFO_X := 1288.0
const TITLE_MAX_W := 544.0
const TITLE_BASELINES: Array[float] = [248.0, 296.0]
const ARTIST_BASELINE := 336.0
const CHIP_Y := 352.0
const NOTES_BASELINE := 424.0
const PREVIEW_DIVIDER_Y := 464.0
const ROSTER_CAPTION_POS := Vector2(1008.0, 504.0)
const ROSTER_X := 1008.0
const ROSTER_RIGHT := 1824.0
const ROSTER_TOPS: Array[float] = [520.0, 584.0, 648.0, 712.0]
const ROSTER_H := 56.0
const CALLSIGN_X := 1032.0
const HINT_POS := Vector2(64.0, 960.0)
const ERROR_POS := Vector2(64.0, 1000.0)
const ERROR_W := 1180.0
const GLYPH_W := 16.0
const DIVIDER_ALPHA := 0.35
const CAPTION_SPACING := 2

## Scene changes go through this so tests can observe them.
var navigate: Callable = Callable()
## The song library (the /root/SongLibrary autoload unless a test injects one).
var library: Node = null

var song_value_label: Label
var skill_label: Label
var start_button: Button
var error_label: Label

var _setup: MatchSetup
var _entry: SongEntry
var _focus := ROW_START
var _rows: Array[Button] = []
var _row_painters: Array[Control] = []
var _how_labels: Array[Label] = []
var _roster_rows: Array[RosterRow] = []
var _roster_tweens: Array[Tween] = []
var _layout: Control
var _hint_label: Label
var _key_hint: Label
var _title_labels: Array[Label] = []
var _artist_label: Label
var _notes_label: Label
var _chip_painter: Control
var _cover_painter: Control
var _cover: AlbumCover
var _cover_art: Texture2D
var _caption_font: FontVariation
var _last_pad := false
var _starting := false
var _error := ""


## Non-interactive canvas that draws with a callable.
class Painter:
	extends Control
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## One roster line (56 tall): callsign and a right-aligned chip.
class RosterRow:
	extends Control
	var callsign := ""
	var chip_text := ""
	var chip_variant := "mode"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var pts := UiKit.chamfer_points(r, float(Palette.CUT_SM))
		draw_colored_polygon(pts, Palette.alpha(Palette.ABYSS_800, 0.6))
		var f := Palette.font()
		var fs := Palette.SIZE_BODY
		var base := size.y * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(MatchSetupScreen.CALLSIGN_X - MatchSetupScreen.ROSTER_X, base), callsign,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Palette.TEXT_HI)
		if chip_text != "":
			var w := UiKit.chip_width(chip_text, chip_variant)
			UiKit.draw_chip(self, Rect2(size.x - Palette.SP_MD - w, (size.y - UiKit.CHIP_H) * 0.5, w, UiKit.CHIP_H),
				chip_text, chip_variant)


func _ready() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if theme == null:
		theme = Palette.load_theme()
	if library == null:
		library = get_node_or_null("/root/SongLibrary")
	_cover = AlbumCover.new()
	_load_setup()
	_build()
	_refresh()
	_request_cover()
	UiKit.register_fx(self)
	_set_focus(ROW_START if _start_enabled() else ROW_SONG)


func _exit_tree() -> void:
	if _cover != null:
		_cover.shutdown()


func _process(_delta: float) -> void:
	if _cover != null:
		_cover.reap()


# ---- model -------------------------------------------------------------------------------

func _load_setup() -> void:
	var src: MatchSetup = MatchSetup.pending if MatchSetup.pending != null else MatchSetup.from_settings()
	_setup = src.clamped()
	_setup.mode = MatchSetup.MODE_VERSUS
	_setup.seed = _fresh_seed()
	_entry = _playable(_find(_setup.song_id))
	if _entry == null and library != null:
		var last := _playable(_find(str(library.last_song_id)))
		if last != null:
			_entry = last
			if _setup.difficulty == "":
				_setup.difficulty = str(library.last_difficulty)
	_setup.song_id = _entry.id if _entry != null else ""
	_setup.difficulty = SongListModel.snap_difficulty(_available(), _setup.difficulty)


static func _fresh_seed() -> int:
	var s := MatchSetup.new_seed()
	while s == 0:
		s = MatchSetup.new_seed()
	return s


func _find(id: String) -> SongEntry:
	if library == null or id == "":
		return null
	return library.find(id)


static func _playable(e: SongEntry) -> SongEntry:
	return e if e != null and e.status == "ok" and not e.difficulties.is_empty() else null


func _available() -> Array:
	var out: Array = []
	if _entry != null:
		for d in _entry.difficulties:
			out.append(str(d["name"]))
	return out


func _has_songs() -> bool:
	if library == null:
		return false
	for e in library.entries:
		if _playable(e) != null:
			return true
	return false


func _start_enabled() -> bool:
	return _entry != null and _setup.difficulty != "" and not _starting


func _note_count() -> int:
	if _entry == null:
		return 0
	return int(_entry.difficulty(_setup.difficulty).get("note_count", 0))


func _threshold() -> int:
	return RewardMeter.threshold(_note_count(), VersusConfig.new().reward_threshold_ratio)


func notes_line() -> String:
	if _entry == null:
		return ""
	return NOTES_FORMAT % [_note_count(), _threshold()]


func how_lines() -> Array[String]:
	var device := &"gamepad" if _last_pad else &"keyboard"
	var fire := Settings.bindings.display_name(&"fire", device).to_upper()
	var target := Settings.bindings.display_name(&"target_cycle", device).to_upper()
	var out: Array[String] = []
	for l in HOW_LINES:
		out.append(l.replace("{FIRE}", fire).replace("{TARGET}", target))
	return out


func roster_names() -> Array[String]:
	var out: Array[String] = ["YOU"]
	for n in MatchSetup.callsigns(_setup.seed, _setup.rivals):
		out.append(n)
	return out


func _skill_index() -> int:
	return maxi(0, MatchSetup.SKILLS.find(_setup.skill))


# ---- building ----------------------------------------------------------------------------

func _build() -> void:
	var backdrop := AbyssBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.variant = "table"
	add_child(backdrop)
	_layout = Control.new()
	_layout.name = "Layout"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(_layout)
	add_child(_layout)

	_label("Title", TITLE, Palette.display_font(), Palette.SIZE_HEADING, Palette.TEXT_HI, TITLE_POS)
	_label("Subtitle", SUBTITLE, Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, SUBTITLE_POS)
	_panel("SettingsPanel", SETTINGS_RECT)
	_panel("PreviewPanel", PREVIEW_RECT)
	_label("MatchCaption", CAPTION_MATCH, _caption(), Palette.SIZE_LABEL, Palette.SONAR, CAPTION_POS)

	for i in ROWS.size():
		_build_row(i)
	_wire_focus()

	skill_label = _label("SkillDescription", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID, SKILL_DESC_POS)
	_divider("Divider", Rect2(ROW_X, DIVIDER_Y - Palette.EDGE * 0.5, ROW_W, Palette.EDGE))
	_label("HowCaption", HOW_CAPTION, _caption(), Palette.SIZE_LABEL, Palette.SONAR, HOW_CAPTION_POS)
	for i in HOW_BASELINES.size():
		_how_labels.append(_label("HowLine%d" % i, "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID,
			Vector2(LABEL_X, HOW_BASELINES[i])))

	_build_preview()
	_hint_label = _label("Hint", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_LO, HINT_POS)
	error_label = _error_line()
	_layout.add_child(error_label)
	var marker := FocusMarker.new()
	marker.name = "FocusMarker"
	add_child(marker)


func _build_row(i: int) -> void:
	var b: Button
	if i == ROW_START:
		b = UiKit.make_button(START_TEXT, "", "primary", int(ROW_H))
		b.name = "StartMatch"
		_key_hint = Label.new()
		_key_hint.name = "KeyHint"
		_key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_key_hint.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
		_key_hint.add_theme_color_override("font_color", Palette.TEXT_LO)
		_key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_key_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_key_hint.position = Vector2(ROW_W - Palette.SP_LG - KEY_HINT_W, 0.0)
		_key_hint.size = Vector2(KEY_HINT_W, ROW_H)
		b.add_child(_key_hint)
		start_button = b
	else:
		b = UiKit.make_button("", "", "default", int(ROW_H))
		b.name = "Row" + ROW_LABELS[i].replace(" ", "")
		var p := Painter.new()
		p.name = "Content"
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size = Vector2(ROW_W, ROW_H)
		p.painter = _paint_row.bind(i)
		b.add_child(p)
		_row_painters.append(p)
	b.position = Vector2(ROW_X, ROW_TOPS[i])
	b.size = Vector2(ROW_W, ROW_H)
	b.gui_input.connect(_on_row_input.bind(i))
	b.focus_entered.connect(_on_row_focus.bind(i))
	b.focus_exited.connect(_redraw_rows)
	if i == ROW_SONG:
		song_value_label = Label.new()
		song_value_label.name = "SongValue"
		song_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		song_value_label.add_theme_font_size_override("font_size", Palette.SIZE_BODY)
		song_value_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		var f := Palette.font()
		song_value_label.position = Vector2(VALUE_X - ROW_X, _baseline(ROW_H, f, Palette.SIZE_BODY)
			- f.get_ascent(Palette.SIZE_BODY))
		song_value_label.size = Vector2(VALUE_W, f.get_height(Palette.SIZE_BODY))
		b.add_child(song_value_label)
	if i == ROW_SONG or i == ROW_START:
		b.pressed.connect(_activate.bind(i))
	_layout.add_child(b)
	_rows.append(b)


## Closed Up/Down loop; Left/Right never move focus (they change the row's value).
func _wire_focus() -> void:
	for i in _rows.size():
		var b := _rows[i]
		var nxt := b.get_path_to(_rows[(i + 1) % _rows.size()])
		var prv := b.get_path_to(_rows[(i + _rows.size() - 1) % _rows.size()])
		b.focus_neighbor_bottom = nxt
		b.focus_next = nxt
		b.focus_neighbor_top = prv
		b.focus_previous = prv
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func _build_preview() -> void:
	_cover_painter = _painter("Cover", COVER_RECT, _paint_cover)
	for i in TITLE_BASELINES.size():
		_title_labels.append(_label("SongTitle%d" % i, "", Palette.display_font(), Palette.SIZE_HEADING, Palette.TEXT_HI,
			Vector2(INFO_X, TITLE_BASELINES[i])))
	_artist_label = _label("Artist", "", Palette.font(), Palette.SIZE_BODY, Palette.TEXT_HI,
		Vector2(INFO_X, ARTIST_BASELINE))
	_chip_painter = _painter("DifficultyChip", Rect2(INFO_X, CHIP_Y, TITLE_MAX_W, UiKit.CHIP_H), _paint_preview_chip)
	_notes_label = _label("NotesLine", "", Palette.font(), Palette.SIZE_LABEL, Palette.TEXT_MID,
		Vector2(INFO_X, NOTES_BASELINE))
	_divider("PreviewDivider", Rect2(INFO_X, PREVIEW_DIVIDER_Y - Palette.EDGE * 0.5, ROSTER_RIGHT - INFO_X,
		Palette.EDGE))
	_label("RosterCaption", ROSTER_CAPTION, _caption(), Palette.SIZE_LABEL, Palette.TEXT_LO, ROSTER_CAPTION_POS)
	for i in ROSTER_TOPS.size():
		var r := RosterRow.new()
		r.name = "Roster%d" % i
		var rr := roster_row_rect(i)
		r.position = rr.position
		r.size = rr.size
		_layout.add_child(r)
		_roster_rows.append(r)
		_roster_tweens.append(null)


func _error_line() -> Label:
	var l := Label.new()
	l.name = "ErrorLine"
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	l.add_theme_color_override("font_color", Palette.WARNING_RED)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = GLYPH_W + Palette.SP_SM
	l.add_theme_stylebox_override("normal", pad)
	var f := Palette.font()
	l.position = Vector2(ERROR_POS.x, ERROR_POS.y - f.get_ascent(Palette.SIZE_LABEL))
	l.size = Vector2(ERROR_W, f.get_height(Palette.SIZE_LABEL))
	var g := MainMenu.StatusGlyph.new()
	g.name = "Glyph"
	g.position = Vector2(0.0, 2.0)
	g.size = Vector2(GLYPH_W, GLYPH_W)
	l.add_child(g)
	return l


# ---- refresh -----------------------------------------------------------------------------

## Re-reads every value into the labels, painters and roster.
func _refresh() -> void:
	var has_songs := _has_songs()
	if _entry != null:
		song_value_label.text = ProgressTrack.truncate_px(_entry.title if _entry.title != "" else "Untitled",
			Palette.font(), Palette.SIZE_BODY, VALUE_W)
		song_value_label.add_theme_color_override("font_color", Palette.TEXT_HI)
	else:
		song_value_label.text = EMPTY_SONG if not has_songs else NO_SONG
		song_value_label.add_theme_color_override("font_color", Palette.TEXT_LO)
	_set_text(skill_label, EMPTY_HINT if not has_songs else str(SKILL_DESCRIPTIONS.get(_setup.skill, "")))
	var lines := how_lines()
	for i in _how_labels.size():
		_set_text(_how_labels[i], lines[i])
	start_button.disabled = not _start_enabled()
	_key_hint.text = "A" if _last_pad else "ENTER"
	_set_text(_hint_label, HINT_PAD if _last_pad else HINT_KEYS)
	_refresh_preview()
	_refresh_roster()
	_redraw_rows()


func _refresh_preview() -> void:
	var show := _entry != null
	var title_lines := _title_lines(_entry.title if show and _entry.title != "" else ("Untitled" if show else ""))
	for i in _title_labels.size():
		_set_text(_title_labels[i], title_lines[i] if i < title_lines.size() else "")
	_set_text(_artist_label, ProgressTrack.truncate_px(_entry.artist, Palette.font(), Palette.SIZE_BODY, TITLE_MAX_W)
		if show else "")
	_set_text(_notes_label, notes_line())
	_cover_painter.visible = show
	_chip_painter.queue_redraw()
	_cover_painter.queue_redraw()


func _refresh_roster() -> void:
	var names := roster_names()
	var all := MatchSetup.callsigns(_setup.seed, MatchSetup.MAX_RIVALS)
	for i in _roster_rows.size():
		var r := _roster_rows[i]
		r.callsign = "YOU" if i == 0 else all[i - 1]
		r.chip_text = "YOU" if i == 0 else _setup.skill.to_upper()
		r.chip_variant = "info" if i == 0 else "mode"
		r.queue_redraw()
		_fade_roster_row(i, 1.0 if i < names.size() else 0.0)


## Rows appear / disappear with the Rivals value (fade DUR_BASE; instant under Reduce motion).
func _fade_roster_row(i: int, target: float) -> void:
	var r := _roster_rows[i]
	var tw := _roster_tweens[i]
	if tw != null and tw.is_valid():
		tw.kill()
	_roster_tweens[i] = null
	if is_equal_approx(r.modulate.a, target) and r.visible == (target > 0.0):
		return
	if UiKit.reduce_motion() or not is_inside_tree() or not r.visible and target == 0.0:
		r.modulate.a = target
		r.visible = target > 0.0
		return
	r.visible = true
	tw = create_tween()
	tw.tween_property(r, "modulate:a", target, Palette.DUR_BASE)
	if target == 0.0:
		tw.tween_callback(func() -> void: r.visible = false)
	_roster_tweens[i] = tw


func _set_text(l: Label, text: String) -> void:
	l.text = text
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	l.size.x = ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


## Up to 2 lines of the title within TITLE_MAX_W; the second ends in "..." when cut.
func _title_lines(title: String) -> Array[String]:
	var f := Palette.display_font()
	var fs := Palette.SIZE_HEADING
	var out: Array[String] = []
	if title == "":
		return out
	var words := title.split(" ", false)
	var cur := ""
	var wi := 0
	while wi < words.size():
		var trial: String = words[wi] if cur == "" else cur + " " + words[wi]
		if f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= TITLE_MAX_W:
			cur = trial
			wi += 1
			continue
		if cur == "":
			cur = words[wi]
			wi += 1
		break
	out.append(ProgressTrack.truncate_px(cur, f, fs, TITLE_MAX_W))
	if wi < words.size():
		var rest := " ".join(words.slice(wi))
		out.append(ProgressTrack.truncate_px(rest, f, fs, TITLE_MAX_W))
	return out


func _redraw_rows() -> void:
	for p in _row_painters:
		p.queue_redraw()


# ---- painting ----------------------------------------------------------------------------

static func _baseline(h: float, f: Font, fs: int) -> float:
	return h * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5


func _paint_row(c: CanvasItem, i: int) -> void:
	var f := Palette.font()
	var fs := Palette.SIZE_BODY
	c.draw_string(f, Vector2(LABEL_X - ROW_X, _baseline(ROW_H, f, fs)), ROW_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, fs, Palette.TEXT_MID)
	var focused := _focus == i
	var icon_y := (ROW_H - ICON) * 0.5
	var chev := Palette.SONAR if focused else Palette.TEXT_LO
	match i:
		ROW_SONG:
			UiIcons.draw(c, "chevron_right", Rect2(CHEVRON_RIGHT_X - ROW_X, icon_y, ICON, ICON), chev)
		ROW_DIFFICULTY:
			UiIcons.draw(c, "chevron_left", Rect2(CHEVRON_LEFT_X - ROW_X, icon_y, ICON, ICON), chev)
			UiIcons.draw(c, "chevron_right", Rect2(CHEVRON_RIGHT_X - ROW_X, icon_y, ICON, ICON), chev)
			if _setup.difficulty != "":
				var t := _setup.difficulty.to_upper()
				var w := UiKit.chip_width(t, "difficulty")
				UiKit.draw_chip(c, Rect2(VALUE_X - ROW_X, (ROW_H - UiKit.CHIP_H) * 0.5, w, UiKit.CHIP_H), t,
					"difficulty", MainMenu.difficulty_lane(_setup.difficulty))
		ROW_RIVALS:
			for k in 3:
				_paint_tile(c, i, tile_rect("rivals", k), str(k + 1), _setup.rivals == k + 1, focused, Palette.SIZE_BODY)
		ROW_SKILL:
			for k in 3:
				_paint_tile(c, i, tile_rect("skill", k), SKILL_LABELS[k], _skill_index() == k, focused, Palette.SIZE_LABEL)


## Segmented tile (UI-SPEC 9.2): idle = button idle; selected = ABYSS_600 92% fill, 2 px SONAR
## edge, bold TEXT_HI and a 24 x 4 SONAR bar under it; the focused row's selected tile glows.
func _paint_tile(c: CanvasItem, row: int, global_rect: Rect2, text: String, selected: bool, row_focused: bool,
		fs: int) -> void:
	var r := Rect2(global_rect.position - Vector2(ROW_X, ROW_TOPS[row]), global_rect.size)
	var sb := UiKit.style_button("focus", "default", not row_focused) if selected else UiKit.style_button("normal")
	c.draw_style_box(sb, r)
	var f := Palette.bold() if selected else Palette.font()
	var col := Palette.TEXT_HI if selected else Palette.TEXT_MID
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	c.draw_string(f, Vector2(r.get_center().x - w * 0.5, r.position.y + _baseline(r.size.y, f, fs)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)
	if selected:
		c.draw_rect(Rect2(r.get_center().x - SEL_BAR.x * 0.5, r.end.y + 2.0, SEL_BAR.x, SEL_BAR.y), Palette.SONAR)


func _paint_preview_chip(c: CanvasItem) -> void:
	if _entry == null or _setup.difficulty == "":
		return
	var t := _setup.difficulty.to_upper()
	var w := UiKit.chip_width(t, "difficulty")
	UiKit.draw_chip(c, Rect2(0.0, 0.0, w, UiKit.CHIP_H), t, "difficulty", MainMenu.difficulty_lane(_setup.difficulty))


## Album cover (UI-SPEC 4.10): generated cover with initials, loaded art over it.
func _paint_cover(c: CanvasItem) -> void:
	if _entry == null:
		return
	var r := Rect2(Vector2.ZERO, COVER_RECT.size)
	var pts := UiKit.chamfer_points(r, float(Palette.CUT_MD))
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / r.size)
	var title := _entry.title if _entry.title != "" else "Untitled"
	c.draw_polygon(pts, PackedColorArray([Palette.WHITE]), uvs, _cover.generated_texture(title))
	if _cover_art != null:
		c.draw_polygon(pts, PackedColorArray([Palette.WHITE]), uvs, _cover_art)
	else:
		var ini := AlbumCover.initials(title)
		var df := Palette.display_font()
		var iw := df.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1.0, Palette.SIZE_DISPLAY).x
		c.draw_string(df, Vector2(r.get_center().x - iw * 0.5, r.size.y * AlbumCover.INITIALS_BASELINE), ini,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, Palette.SIZE_DISPLAY, Palette.TEXT_HI)
	var edge := UiKit.chamfer_points(r.grow(-Palette.EDGE * 0.5), float(Palette.CUT_MD))
	edge.append(edge[0])
	c.draw_polyline(edge, Palette.alpha(Palette.SONAR, 0.45), Palette.EDGE, true)
	UiKit.draw_brackets(c, r, Palette.alpha(Palette.SONAR, 0.8))


func _request_cover() -> void:
	_cover_art = null
	if _entry != null and _cover != null:
		_cover.request(_entry, _on_cover)
	if _cover_painter != null:
		_cover_painter.queue_redraw()


func _on_cover(id: String, tex: Texture2D, _cached: bool) -> void:
	if _entry == null or id != _entry.id:
		return
	_cover_art = tex
	if _cover_painter != null:
		_cover_painter.queue_redraw()


# ---- helpers -----------------------------------------------------------------------------

func _caption() -> Font:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = Palette.font()
		_caption_font.spacing_glyph = CAPTION_SPACING
	return _caption_font


## A label whose first baseline sits at `at.y`, sized to its text.
func _label(node_name: String, text: String, font: Font, font_size: int, color: Color, at: Vector2) -> Label:
	var l := Label.new()
	l.name = node_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	l.position = Vector2(at.x, at.y - font.get_ascent(font_size))
	l.size = Vector2(0.0, ceilf(font.get_height(font_size)))
	_layout.add_child(l)
	_set_text(l, text)
	return l


func _painter(node_name: String, rect: Rect2, fn: Callable) -> Painter:
	var c := Painter.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size
	c.painter = fn
	_layout.add_child(c)
	return c


func _panel(node_name: String, rect: Rect2) -> void:
	var sb := UiKit.style_panel("default")
	_painter(node_name, rect, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, Palette.alpha(Palette.SONAR, 0.8)))


func _divider(node_name: String, rect: Rect2) -> void:
	var d := ColorRect.new()
	d.name = node_name
	d.color = Palette.alpha(Palette.SONAR, DIVIDER_ALPHA)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = rect.position
	d.size = rect.size
	_layout.add_child(d)


## Design-space rect of a row ("song", "difficulty", "rivals", "skill", "start").
func row_rect(row: String) -> Rect2:
	var i := ROWS.find(row)
	return Rect2(ROW_X, ROW_TOPS[i], ROW_W, ROW_H)


## Design-space rect of selector tile k of "rivals" or "skill".
static func tile_rect(row: String, k: int) -> Rect2:
	if row == "rivals":
		return Rect2(RIVAL_TILE_X[k], ROW_TOPS[ROW_RIVALS] + 8.0, RIVAL_TILE_W, TILE_H)
	return Rect2(SKILL_TILE_X[k], ROW_TOPS[ROW_SKILL] + 8.0, SKILL_TILE_W, TILE_H)


static func roster_row_rect(i: int) -> Rect2:
	return Rect2(ROSTER_X, ROSTER_TOPS[i], ROSTER_RIGHT - ROSTER_X, ROSTER_H)


# ---- input -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Device tracking only (never consumed): hints and key names follow the last device used.
	var pad := _last_pad
	if event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion
			and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad = true
	if pad != _last_pad:
		_last_pad = pad
		_refresh()


func _on_row_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_click_row(i, mb.position)
		return
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"ui_up", true):
		_step_focus(-1)
	elif event.is_action_pressed(&"ui_down", true):
		_step_focus(1)
	elif event.is_action_pressed(&"ui_left", true):
		_change(-1)
	elif event.is_action_pressed(&"ui_right", true):
		_change(1)
	elif event.is_action_pressed(&"ui_accept"):
		_activate(i)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_back()


func _on_row_focus(i: int) -> void:
	_focus = i
	_redraw_rows()


func _set_focus(i: int) -> void:
	_focus = posmod(i, ROWS.size())
	if is_inside_tree() and _rows[_focus].is_visible_in_tree():
		_rows[_focus].grab_focus()
	_redraw_rows()


func _step_focus(dir: int) -> void:
	_set_focus(_focus + dir)


## Left / Right on the focused row (Song and Start Match ignore it).
func _change(dir: int) -> void:
	var changed := false
	match _focus:
		ROW_DIFFICULTY:
			var next := SongListModel.next_difficulty(_available(), _setup.difficulty, dir)
			if next != "" and next != _setup.difficulty:
				_setup.difficulty = next
				changed = true
		ROW_RIVALS:
			_setup.rivals = posmod(_setup.rivals - 1 + dir, MatchSetup.MAX_RIVALS) + MatchSetup.MIN_RIVALS
			changed = true
		ROW_SKILL:
			_setup.skill = MatchSetup.SKILLS[posmod(_skill_index() + dir, MatchSetup.SKILLS.size())]
			changed = true
	if changed:
		UiSounds.play("move")
		_refresh()


func _click_row(i: int, local: Vector2) -> void:
	var p := local + Vector2(ROW_X, ROW_TOPS[i])
	match i:
		ROW_DIFFICULTY:
			_focus = i
			_change(-1 if local.x < ROW_W * 0.5 else 1)
		ROW_RIVALS, ROW_SKILL:
			var row := "rivals" if i == ROW_RIVALS else "skill"
			for k in 3:
				if tile_rect(row, k).has_point(p):
					if i == ROW_RIVALS:
						_setup.rivals = k + 1
					else:
						_setup.skill = MatchSetup.SKILLS[k]
					UiSounds.play("move")
					_refresh()
					return


func _activate(_i: int) -> void:
	pass


func _back() -> void:
	pass


func _go(path: String) -> void:
	if navigate.is_valid():
		navigate.call(path)
	elif is_inside_tree():
		ScreenTransition.change_scene(path)


# ---- effects contract --------------------------------------------------------------------

func apply_effect_settings() -> void:
	if UiKit.reduce_motion():
		for i in _roster_rows.size():
			var tw := _roster_tweens[i]
			if tw != null and tw.is_valid():
				tw.kill()
				_roster_tweens[i] = null
				var on := i < _setup.rivals + 1
				_roster_rows[i].modulate.a = 1.0 if on else 0.0
				_roster_rows[i].visible = on
	_redraw_rows()


func effect_counts() -> Dictionary:
	return {"roster_fade": not UiKit.reduce_motion()}


# ---- test seams --------------------------------------------------------------------------

func debug_state() -> Dictionary:
	var chips: Array = []
	var names := roster_names()
	for i in names.size():
		chips.append("YOU" if i == 0 else _setup.skill.to_upper())
	return {
		"focused": ROWS[_focus],
		"rivals": _setup.rivals,
		"skill": _setup.skill,
		"song_id": _setup.song_id,
		"song_value": song_value_label.text,
		"difficulty": _setup.difficulty,
		"start_enabled": _start_enabled(),
		"roster": Array(names),
		"roster_chips": chips,
		"how_lines": Array(how_lines()),
		"skill_line": skill_label.text,
		"notes_line": notes_line(),
		"seed": _setup.seed,
		"error": _error,
		"starting": _starting,
	}


func focus_row_for_test(row: String) -> void:
	_set_focus(ROWS.find(row))


func press_key_for_test(keycode: int) -> void:
	match keycode:
		KEY_UP:
			_step_focus(-1)
		KEY_DOWN:
			_step_focus(1)
		KEY_LEFT:
			_change(-1)
		KEY_RIGHT:
			_change(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_focus)
		KEY_ESCAPE:
			_back()
