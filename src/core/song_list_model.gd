class_name SongListModel
extends RefCounted
## Pure rules for the Song Select list (D-10, D-11, D-12): filter, sort and ordering, digit-key and
## Esc rules, difficulty snapping, preview timing, scroll stability, and display text. No nodes, no
## Settings, no ScoreStore I/O (bests arrive as a prefetched fingerprint -> depth dictionary).

enum SortMode { TITLE, ARTIST, BEST }

const FILTER_MAX := 40
const PAGE := 9
const SCROLL_MARGIN := 2
const PREVIEW_DELAY_MSEC := 400
const PREVIEW_TAIL_SEC := 5.0
const DIFFICULTY_ORDER: Array[String] = ["easy", "medium", "hard", "expert"]
const STATUS_NAME_MAX := 28


# ---- filter ----

static func clamp_filter(text: String) -> String:
	return text.substr(0, FILTER_MAX)


## Case-insensitive; every whitespace-separated term must appear in title or artist.
static func filter(entries: Array, text: String) -> Array:
	var terms: PackedStringArray = []
	for t in clamp_filter(text).to_lower().split(" ", false):
		var s := t.strip_edges()
		if s != "":
			terms.append(s)
	if terms.is_empty():
		return entries.duplicate()
	var out: Array = []
	for item in entries:
		var e: SongEntry = item
		var hay: String = (e.title + "\n" + e.artist).to_lower()
		var ok := true
		for t in terms:
			if not hay.contains(t):
				ok = false
				break
		if ok:
			out.append(e)
	return out


# ---- ordering ----

static func next_sort(mode: int) -> int:
	return (mode + 1) % 3


static func sort_label(mode: int) -> String:
	match mode:
		SortMode.ARTIST:
			return "SORT: ARTIST"
		SortMode.BEST:
			return "SORT: BEST SCORE"
	return "SORT: TITLE"


## Best depth across the song's difficulties; -1 when none has a record.
static func best_depth(entry: SongEntry, best_by_fingerprint: Dictionary) -> float:
	var best := -1.0
	for d in entry.difficulties:
		var fp: String = d["fingerprint"]
		if best_by_fingerprint.has(fp):
			var v: Variant = best_by_fingerprint[fp]
			var depth := float(v["depth"]) if typeof(v) == TYPE_DICTIONARY else float(v)
			best = maxf(best, depth)
	return best


static func _is_calibration(e: SongEntry) -> bool:
	return e.source == "test"


## Stable merge-free sort: returns a new array. Playable (sorted), then the Calibration Track,
## then needs-chart rows by title, then broken rows by title.
static func order(entries: Array, mode: int, best_by_fingerprint: Dictionary) -> Array:
	var playable: Array = []
	var calibration: Array = []
	var needs: Array = []
	var broken: Array = []
	for item in entries:
		var e: SongEntry = item
		if _is_calibration(e):
			calibration.append(e)
		elif e.status == "ok":
			playable.append(e)
		elif e.status == "needs_chart":
			needs.append(e)
		else:
			broken.append(e)
	var keyed: Array = []
	for i in playable.size():
		var e: SongEntry = playable[i]
		keyed.append({"e": e, "i": i, "t": e.title.to_lower(), "a": e.artist.to_lower(),
				"b": best_depth(e, best_by_fingerprint)})
	keyed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		match mode:
			SortMode.ARTIST:
				if x["a"] != y["a"]:
					return x["a"] < y["a"]
				if x["t"] != y["t"]:
					return x["t"] < y["t"]
			SortMode.BEST:
				var bx: float = x["b"]
				var by: float = y["b"]
				if bx != by:
					return bx > by
				if (bx < 0.0) and x["t"] != y["t"]:
					return x["t"] < y["t"]
			_:
				if x["t"] != y["t"]:
					return x["t"] < y["t"]
		return x["i"] < y["i"])
	var out: Array = []
	for k in keyed:
		out.append(k["e"])
	out.append_array(calibration)
	out.append_array(_by_title(needs))
	out.append_array(_by_title(broken))
	return out


static func _by_title(list: Array) -> Array:
	var keyed: Array = []
	for i in list.size():
		keyed.append({"e": list[i], "i": i, "t": (list[i] as SongEntry).title.to_lower()})
	keyed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["t"] != y["t"]:
			return x["t"] < y["t"]
		return x["i"] < y["i"])
	var out: Array = []
	for k in keyed:
		out.append(k["e"])
	return out


# ---- keys ----

static func nav_digits_active(filter_text: String, typing_mode: bool) -> bool:
	return filter_text == "" and not typing_mode


## Row delta for the digit keys 1-4 (1 up, 2 down, 3 page up, 4 page down); 0 for anything else.
static func digit_delta(keycode: int) -> int:
	match keycode:
		KEY_1:
			return -1
		KEY_2:
			return 1
		KEY_3:
			return -PAGE
		KEY_4:
			return PAGE
	return 0


static func esc_action(filter_text: String) -> String:
	return "clear_filter" if filter_text != "" else "back"


## Typing mode after a Backspace left `new_text` in the field.
static func typing_after_backspace(new_text: String) -> bool:
	return new_text != ""


# ---- difficulty ----

static func _rank(name: String) -> int:
	return DIFFICULTY_ORDER.find(name)


## `wanted` if available, else the nearest available (ties go to the lower); "" when none.
static func snap_difficulty(available: Array, wanted: String) -> String:
	if available.is_empty():
		return ""
	if available.has(wanted):
		return wanted
	var w := _rank(wanted)
	var best := ""
	var best_dist := 1000
	var best_rank := 1000
	for a in available:
		var r := _rank(a)
		var dist := absi(r - w)
		if dist < best_dist or (dist == best_dist and r < best_rank):
			best = a
			best_dist = dist
			best_rank = r
	return best


## Next available difficulty in direction dir (+1 harder, -1 easier). Clamps, never wraps.
static func next_difficulty(available: Array, current: String, dir: int) -> String:
	if available.is_empty():
		return ""
	var cur := _rank(current)
	var best := current if available.has(current) else snap_difficulty(available, current)
	for step in range(1, DIFFICULTY_ORDER.size()):
		var r := cur + dir * step
		if r < 0 or r >= DIFFICULTY_ORDER.size():
			break
		if available.has(DIFFICULTY_ORDER[r]):
			return DIFFICULTY_ORDER[r]
	return best


# ---- preview ----

static func preview_start_sec(preview_start_ms: int, length_sec: float) -> float:
	if preview_start_ms >= 0:
		var s := float(preview_start_ms) / 1000.0
		if s < length_sec - PREVIEW_TAIL_SEC:
			return s
	return 0.3 * length_sec


static func preview_gate(last_change_msec: int, now_msec: int, delay: int = PREVIEW_DELAY_MSEC) -> bool:
	return now_msec - last_change_msec >= delay


static func accept_result(request_id: int, current_id: int) -> bool:
	return request_id == current_id


# ---- scrolling ----

## New top-row offset so the selected row stays at the same visible y after rows were inserted.
static func insert_stable(old_ids: Array, new_ids: Array, selected_id: String, scroll_offset: int) -> int:
	var oi := old_ids.find(selected_id)
	var ni := new_ids.find(selected_id)
	if oi < 0 or ni < 0:
		return scroll_offset
	return maxi(0, scroll_offset + (ni - oi))


## Smallest scroll change that keeps `index` inside rows 3..7 of 9 (margin 2), clamped to the list.
static func scroll_for_selection(index: int, offset: int, count: int) -> int:
	var max_off := maxi(0, count - PAGE)
	var off := offset
	if index < off + SCROLL_MARGIN:
		off = index - SCROLL_MARGIN
	elif index > off + PAGE - 1 - SCROLL_MARGIN:
		off = index - (PAGE - 1 - SCROLL_MARGIN)
	return clampi(off, 0, max_off)


# ---- text ----

static func truncate_middle(text: String, max_chars: int) -> String:
	if text.length() <= max_chars or max_chars < 4:
		return text
	var keep := max_chars - 3
	var head := int(ceil(float(keep) / 2.0))
	var tail := keep - head
	return text.substr(0, head) + "..." + text.substr(text.length() - tail, tail)


static func fmt_length(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	return "%d:%02d" % [s / 60, s % 60]


static func fmt_count(n: int) -> String:
	return Palette.fmt_depth(n)


static func count_text(n: int) -> String:
	return "1 song" if n == 1 else "%s songs" % fmt_count(n)


## Footer status. While scanning: "Looking for songs..." until a total is known, then the counter,
## or "Unpacking {name}" (name capped at 28 chars) while a zip job runs.
static func scan_status_text(scanning: bool, done: int, total: int, label: String, count: int,
		unplayable: int) -> String:
	if not scanning:
		var s := count_text(count)
		if unplayable > 0:
			s += "  ·  %s unplayable" % fmt_count(unplayable)
		return s
	if label.begins_with("Unpacking "):
		var name := label.trim_prefix("Unpacking ")
		if name.length() > STATUS_NAME_MAX:
			name = name.substr(0, STATUS_NAME_MAX) + "..."
		return "Unpacking " + name
	if total <= 0:
		return "Looking for songs..."
	return "Scanning %d / %d" % [done, total]
