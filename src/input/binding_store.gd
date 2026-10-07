class_name BindingStore
extends RefCounted
## Runtime bind/unbind/validate/serialize/reset for the gameplay InputMap actions (D-18..D-21).
## The InputMap is the live truth; this class mutates it and (de)serializes it. Each action holds
## at most one keyboard key and one gamepad binding. Duplicates are checked inside the gameplay
## set only (D-20). Tab is reserved for the overlay and Escape belongs to Pause.
## Serialized form (settings.cfg [bindings]): "<action>_key" = physical_keycode (int),
## "<action>_pad" = button_index (int) or [axis, sign] for a trigger. File contents are
## untrusted: anything invalid falls back to the default for that action (T-04-01).

enum Result { OK, DUPLICATE, RESERVED, INVALID }

const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"lane_1", &"lane_2", &"lane_3", &"lane_4", &"fire", &"target_cycle", &"pause",
]
const SECTION := "bindings"
const VERSION_KEY := "bindings_version"
const CURRENT_VERSION := 2
const LEGACY_LANE_KEYS: Array[int] = [KEY_D, KEY_F, KEY_J, KEY_K]
const TRIGGER_DEADZONE := 0.5
const TRIGGER_AXES: Array[int] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
const KEY_CODE_BITS := 0x007FFFFF  # KEY_CODE_MASK: keycode + KEY_SPECIAL, no modifier bits

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
}


## Default key and pad descriptor per action. A pad descriptor is
## {"kind": "button", "index": int} or {"kind": "axis", "axis": int, "sign": 1}.
static func _defaults() -> Dictionary:
	return {
		&"lane_1": {"key": KEY_1, "pad": _button(JOY_BUTTON_LEFT_SHOULDER)},
		&"lane_2": {"key": KEY_2, "pad": _axis(JOY_AXIS_TRIGGER_LEFT)},
		&"lane_3": {"key": KEY_3, "pad": _axis(JOY_AXIS_TRIGGER_RIGHT)},
		&"lane_4": {"key": KEY_4, "pad": _button(JOY_BUTTON_RIGHT_SHOULDER)},
		&"fire": {"key": KEY_SPACE, "pad": _button(JOY_BUTTON_A)},
		&"target_cycle": {"key": KEY_H, "pad": _button(JOY_BUTTON_Y)},
		&"pause": {"key": KEY_ESCAPE, "pad": _button(JOY_BUTTON_START)},
	}


static func _button(index: int) -> Dictionary:
	return {"kind": "button", "index": index}


static func _axis(axis: int) -> Dictionary:
	return {"kind": "axis", "axis": axis, "sign": 1}


static func _pad_sig(pad: Dictionary) -> String:
	if pad.is_empty():
		return ""
	if pad["kind"] == "button":
		return "b%d" % pad["index"]
	return "a%d:%d" % [pad["axis"], pad["sign"]]


# --- public API ----------------------------------------------------------------------------


func reset_defaults() -> void:
	var d := _defaults()
	for a in GAMEPLAY_ACTIONS:
		_apply(a, d[a]["key"], d[a]["pad"])


func bind_key(action: StringName, physical_keycode: int) -> Dictionary:
	if not GAMEPLAY_ACTIONS.has(action):
		return _res(Result.INVALID)
	var v := _validate_key(action, physical_keycode)
	if v != Result.OK:
		return _res(v)
	for other in GAMEPLAY_ACTIONS:
		if other != action and _current_key(other) == physical_keycode:
			return _res(Result.DUPLICATE, other)
	_apply(action, physical_keycode, _current_pad(action))
	return _res(Result.OK)


func bind_pad(action: StringName, event: InputEvent) -> Dictionary:
	if not GAMEPLAY_ACTIONS.has(action):
		return _res(Result.INVALID)
	var pad := _pad_from_event(event)
	if pad.is_empty():
		return _res(Result.INVALID)
	var sig := _pad_sig(pad)
	for other in GAMEPLAY_ACTIONS:
		if other != action and _pad_sig(_current_pad(other)) == sig:
			return _res(Result.DUPLICATE, other)
	_apply(action, _current_key(action), pad)
	return _res(Result.OK)


func to_config(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, VERSION_KEY, CURRENT_VERSION)
	for a in GAMEPLAY_ACTIONS:
		var key := _current_key(a)
		if key > 0:
			cfg.set_value(SECTION, "%s_key" % a, key)
		var pad := _current_pad(a)
		if not pad.is_empty():
			if pad["kind"] == "button":
				cfg.set_value(SECTION, "%s_pad" % a, int(pad["index"]))
			else:
				cfg.set_value(SECTION, "%s_pad" % a, [int(pad["axis"]), int(pad["sign"])])


func from_config(cfg: ConfigFile) -> void:
	var defaults := _defaults()
	var keys := {}
	var pads := {}
	var migrate := _is_legacy_lane_set(cfg)
	for a in GAMEPLAY_ACTIONS:
		keys[a] = defaults[a]["key"]
		pads[a] = defaults[a]["pad"]
		if migrate and _lane_index(a) >= 0:
			pass  # D-11: untouched v0.1 D/F/J/K lane keys fall back to the new 1-4 defaults
		elif cfg.has_section_key(SECTION, "%s_key" % a):
			var kv: Variant = cfg.get_value(SECTION, "%s_key" % a)
			if typeof(kv) == TYPE_INT and _validate_key(a, int(kv)) == Result.OK:
				keys[a] = int(kv)
		if cfg.has_section_key(SECTION, "%s_pad" % a):
			var pad := _pad_from_config(cfg.get_value(SECTION, "%s_pad" % a))
			if not pad.is_empty():
				pads[a] = pad
	_resolve_duplicates(keys, defaults, "key")
	_resolve_duplicates(pads, defaults, "pad")
	for a in GAMEPLAY_ACTIONS:
		_apply(a, keys[a], pads[a])


## D-11: true only when no int bindings_version marker exists and the four lane keys are
## exactly the old defaults D F J K. Anything else is a player choice and is never altered.
func _is_legacy_lane_set(cfg: ConfigFile) -> bool:
	if cfg.has_section_key(SECTION, VERSION_KEY) 			and typeof(cfg.get_value(SECTION, VERSION_KEY)) == TYPE_INT:
		return false
	for i in range(4):
		var k := "lane_%d_key" % (i + 1)
		if not cfg.has_section_key(SECTION, k):
			return false
		var v: Variant = cfg.get_value(SECTION, k)
		if typeof(v) != TYPE_INT or int(v) != LEGACY_LANE_KEYS[i]:
			return false
	return true


func _lane_index(action: StringName) -> int:
	return [&"lane_1", &"lane_2", &"lane_3", &"lane_4"].find(action)


## Label for the lane/action UI. device is &"keyboard" or &"gamepad".
func display_name(action: StringName, device: StringName) -> String:
	if device == &"keyboard":
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				return (ev as InputEventKey).as_text_physical_keycode()
		return "Unbound"
	var pad := _current_pad(action)
	if pad.is_empty():
		return "Unbound"
	if pad["kind"] == "axis":
		match int(pad["axis"]):
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		return "Axis %d" % int(pad["axis"])
	var idx := int(pad["index"])
	if PAD_BUTTON_NAMES.has(idx):
		return PAD_BUTTON_NAMES[idx]
	return "Btn %d" % idx


# --- validation ----------------------------------------------------------------------------


func _validate_key(action: StringName, k: int) -> int:
	if k <= 0 or (k & ~KEY_CODE_BITS) != 0 or OS.get_keycode_string(k).is_empty():
		return Result.INVALID
	if k == KEY_TAB:
		return Result.RESERVED
	if k == KEY_ESCAPE and action != &"pause":
		return Result.RESERVED
	return Result.OK


## Returns {} for anything that is not a bindable gamepad input. Sticks and weak axis values
## (below 0.5) are ignored so stick drift cannot be captured (T-04-02).
func _pad_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton:
		var b := (event as InputEventJoypadButton).button_index
		if b >= 0 and b < JOY_BUTTON_SDL_MAX:
			return _button(b)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if TRIGGER_AXES.has(m.axis) and m.axis_value >= TRIGGER_DEADZONE:
			return _axis(m.axis)
	return {}


func _pad_from_config(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_INT:
		if int(v) >= 0 and int(v) < JOY_BUTTON_SDL_MAX:
			return _button(int(v))
	elif typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		var arr: Array = v
		if typeof(arr[0]) == TYPE_INT and typeof(arr[1]) == TYPE_INT:
			if TRIGGER_AXES.has(int(arr[0])) and int(arr[1]) == 1:
				return _axis(int(arr[0]))
	return {}


## Reverts customised entries that collide with another action until no duplicates remain.
func _resolve_duplicates(map: Dictionary, defaults: Dictionary, field: String) -> void:
	for _i in range(GAMEPLAY_ACTIONS.size() * 2):
		var conflict := _find_conflict(map, field)
		if conflict.is_empty():
			return
		var a: StringName = conflict[0]
		var b: StringName = conflict[1]
		if _sig(map[b], field) != _sig(defaults[b][field], field):
			map[b] = defaults[b][field]
		elif _sig(map[a], field) != _sig(defaults[a][field], field):
			map[a] = defaults[a][field]
		else:
			# Both are defaults and still collide: cannot happen, but never leave a duplicate.
			for x in GAMEPLAY_ACTIONS:
				map[x] = defaults[x][field]
			return


func _find_conflict(map: Dictionary, field: String) -> Array:
	for i in range(GAMEPLAY_ACTIONS.size()):
		for j in range(i + 1, GAMEPLAY_ACTIONS.size()):
			var a := GAMEPLAY_ACTIONS[i]
			var b := GAMEPLAY_ACTIONS[j]
			if _sig(map[a], field) == _sig(map[b], field):
				return [a, b]
	return []


func _sig(v: Variant, field: String) -> String:
	if field == "key":
		return "k%d" % int(v)
	return _pad_sig(v)


# --- InputMap access ------------------------------------------------------------------------


func _current_key(action: StringName) -> int:
	if not InputMap.has_action(action):
		return 0
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0


func _current_pad(action: StringName) -> Dictionary:
	if not InputMap.has_action(action):
		return {}
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return _button((ev as InputEventJoypadButton).button_index)
		if ev is InputEventJoypadMotion:
			return _axis((ev as InputEventJoypadMotion).axis)
	return {}


func _apply(action: StringName, key: int, pad: Dictionary) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, TRIGGER_DEADZONE)
	InputMap.action_set_deadzone(action, TRIGGER_DEADZONE)
	InputMap.action_erase_events(action)
	if key > 0:
		var ke := InputEventKey.new()
		ke.physical_keycode = key as Key
		InputMap.action_add_event(action, ke)
	if not pad.is_empty():
		if pad["kind"] == "button":
			var be := InputEventJoypadButton.new()
			be.device = -1
			be.button_index = int(pad["index"]) as JoyButton
			InputMap.action_add_event(action, be)
		else:
			var me := InputEventJoypadMotion.new()
			me.device = -1
			me.axis = int(pad["axis"]) as JoyAxis
			me.axis_value = float(pad["sign"])
			InputMap.action_add_event(action, me)


func _res(result: int, conflict: StringName = &"") -> Dictionary:
	return {"result": result, "conflict_action": conflict}
