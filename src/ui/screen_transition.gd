extends CanvasLayer
## ScreenTransition autoload (02.2 plan 22, UI-SPEC 9.7 / 11, D-13, VIS-09, AV-05): the single
## scene-change choke point for the game screens.
##
## Sonar wipe, 300 ms: COVER (150 ms) grows an ABYSS_900 disc with a 6 px SONAR_PALE rim from
## the focal point (radius 0 -> 2200, cubic-in), the scene swaps at full cover
## (SceneTree.change_scene_to_file), REVEAL (150 ms) grows a hole from the same point
## (cubic-out) once the new scene is in the tree. Hard cap 400 ms (Palette.DUR_MAX): a failsafe
## forces idle, so the overlay can never block the game.
## Reduce motion: a 160 ms cross-fade through ABYSS_900 (80 + 80), no ring.
## Low effects: the same wipe without the edge glow.
##
## Input: the rect ignores the mouse. During the COVER the old screen gets no keys, buttons or
## clicks (they are consumed); a key or joypad press jumps the wipe to its end and is consumed,
## so it reaches neither screen. From the start of the REVEAL input passes through to the new
## scene (a press there only completes the reveal visually).
##
## Seams for tests and the harness: `instant` swaps with no animation; `swap_fn` replaces the
## real scene change; `clock_fn` replaces the millisecond clock; step() advances the state.

signal started
signal swapped
signal finished

const COVER_MS := 150.0
const REVEAL_MS := 150.0
const FADE_HALF_MS := 80.0
const MAX_MS := Palette.DUR_MAX * 1000.0
const RADIUS_MAX := 2200.0
const EDGE_PX := 6.0
const LAYER := 100
const SCREEN_SIZE := Vector2(1920.0, 1080.0)
const SHADER_PATH := "res://shaders/sonar_wipe.gdshader"

enum Phase { IDLE, COVER, REVEAL }

## Tests / harness: swap at once, no animation.
var instant: bool = false
## Test seam: called with the target path instead of SceneTree.change_scene_to_file.
var swap_fn: Callable = Callable()
## Test seam: with swap_fn, the reveal begins right after the swap (true) or waits for
## notify_scene_changed() (false; simulates a scene that never arrives).
var swap_starts_reveal: bool = true
## Test seam: returns the current time in ms (default Time.get_ticks_usec).
var clock_fn: Callable = Callable()

var rect: ColorRect
var centre: Vector2 = SCREEN_SIZE * 0.5
var radius: float = 0.0
## Duration of the last finished transition (start -> idle), ms.
var last_duration_msec: int = 0

var _phase: Phase = Phase.IDLE
var _crossfade: bool = false
var _path: String = ""
var _swapped: bool = false
var _skip: bool = false
var _t0: float = 0.0
var _t_reveal: float = 0.0
var _t_swap: float = 0.0
var _reveal_len: float = REVEAL_MS
var _start_frame: int = -1
var _material: ShaderMaterial


func _init() -> void:
	layer = LAYER
	name = "ScreenTransition"
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.name = "Wipe"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.fill_rect(rect)
	rect.color = Palette.ABYSS_900
	rect.visible = false
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter("fill_color", Palette.ABYSS_900)
	_material.set_shader_parameter("edge_color", Palette.SONAR_PALE)
	_material.set_shader_parameter("edge_px", EDGE_PX)
	_material.set_shader_parameter("radius", 0.0)
	_material.set_shader_parameter("reveal", false)
	_material.set_shader_parameter("glow", true)
	rect.material = _material
	add_child(rect)


func _ready() -> void:
	UiKit.register_fx(self)
	apply_effect_settings()
	get_tree().scene_changed.connect(_on_scene_changed)


# ---- public API ----------------------------------------------------------------------------

## Starts a transition to `path`. `focal` is the wipe centre in design pixels; the default uses
## the focused control's centre, else the screen centre. Returns false (and does nothing) while
## a transition is already running, so a second call never swaps twice.
func change_scene(path: String, focal: Vector2 = Vector2(-1, -1)) -> bool:
	if _phase != Phase.IDLE:
		return false
	_path = path
	_swapped = false
	_skip = false
	_t0 = _now()
	_start_frame = Engine.get_process_frames()
	if instant:
		_phase = Phase.COVER
		_swapped = true
		_skip = true
		rect.visible = false
		_swap()
		if _phase != Phase.IDLE:
			_finish()
		return true
	_crossfade = UiKit.reduce_motion()
	centre = focal if focal.x >= 0.0 and focal.y >= 0.0 else _default_focal()
	radius = 0.0
	_phase = Phase.COVER
	# _input runs in reverse tree order: be the last root child so the leaving screen's _input
	# never sees a key before the wipe consumes it.
	var p := get_parent()
	if p != null:
		p.move_child(self, -1)
	apply_effect_settings()
	_apply(0.0)
	rect.visible = true
	started.emit()
	return true


func is_busy() -> bool:
	return _phase != Phase.IDLE


## "idle", "cover" or "reveal".
func phase() -> String:
	match _phase:
		Phase.COVER:
			return "cover"
		Phase.REVEAL:
			return "reveal"
	return "idle"


## "crossfade" (Reduce motion) or "wipe".
func mode() -> String:
	return "crossfade" if _crossfade else "wipe"


## Advances the transition to the current clock time (called every frame from _process).
func step() -> void:
	if _phase == Phase.IDLE:
		return
	var now := _now()
	var t := now - _t0
	if t >= MAX_MS:
		# Failsafe (T-02.2-42): never block input beyond the 400 ms cap.
		if not _swapped:
			_swapped = true
			_swap()
		_finish()
		return
	if _phase == Phase.COVER:
		if _swapped:
			return  # full cover, waiting for the new scene
		var p := clampf(t / _cover_ms(), 0.0, 1.0)
		_apply(p)
		if p >= 1.0:
			_swapped = true
			_swap()
		return
	var pr := clampf((now - _t_reveal) / _reveal_len, 0.0, 1.0)
	_apply(pr)
	if pr >= 1.0:
		_finish()


## Input policy (see the header). Returns true when the event must be consumed.
func handle_input(event: InputEvent) -> bool:
	if _phase == Phase.IDLE:
		return false
	var press := _is_press(event)
	if _phase == Phase.REVEAL:
		if press:
			_finish()  # input already belongs to the new scene; only the visual completes
		return false
	var blocking := event is InputEventKey or event is InputEventJoypadButton \
		or event is InputEventMouseButton or event is InputEventJoypadMotion
	if not blocking:
		return false
	if press and Engine.get_process_frames() != _start_frame:
		_skip = true
		if not _swapped:
			_swapped = true
			_swap()
		else:
			notify_scene_changed()  # already swapped: end as soon as the new scene is in
	return true


## Begins the reveal (the new scene is in the tree). Called on SceneTree.scene_changed.
func notify_scene_changed() -> void:
	if _phase != Phase.COVER or not _swapped:
		return
	if _skip:
		_finish()
		return
	_phase = Phase.REVEAL
	_t_reveal = _now()
	# The new scene's load time (swap request -> scene_changed) comes out of the reveal, down to
	# half of it, so a slow load keeps the wipe near 300 ms instead of stretching to the cap.
	var load_ms := maxf(0.0, _t_reveal - _t_swap)
	_reveal_len = maxf(_reveal_ms() - load_ms, _reveal_ms() * 0.5)
	_apply(0.0)
	swapped.emit()


# ---- effect contract (UiKit.register_fx) -----------------------------------------------------

func apply_effect_settings() -> void:
	_material.set_shader_parameter("glow", not UiKit.low_effects())


func effect_counts() -> Dictionary:
	return {"glow": not UiKit.low_effects(), "crossfade": UiKit.reduce_motion()}


# ---- internals -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	step()


func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _on_scene_changed() -> void:
	notify_scene_changed()


func _now() -> float:
	if clock_fn.is_valid():
		return float(clock_fn.call())
	return Time.get_ticks_usec() / 1000.0


func _cover_ms() -> float:
	return FADE_HALF_MS if _crossfade else COVER_MS


func _reveal_ms() -> float:
	return FADE_HALF_MS if _crossfade else REVEAL_MS


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not event.is_echo()
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _default_focal() -> Vector2:
	var vp := get_viewport()
	var f: Control = vp.gui_get_focus_owner() if vp != null else null
	if f != null and f.is_visible_in_tree():
		return f.get_global_rect().get_center()
	return SCREEN_SIZE * 0.5


func _swap() -> void:
	_t_swap = _now()
	if swap_fn.is_valid():
		swap_fn.call(_path)
		if swap_starts_reveal:
			notify_scene_changed()
		return
	if not is_inside_tree():
		return
	var err := get_tree().change_scene_to_file(_path)
	if err != OK:
		push_warning("ScreenTransition: change_scene_to_file(%s) failed (%d)" % [_path, err])
		_finish()


## Draws progress p (0..1) of the current phase.
func _apply(p: float) -> void:
	if _crossfade:
		rect.material = null
		var a := p if _phase == Phase.COVER else 1.0 - p
		rect.color = Palette.alpha(Palette.ABYSS_900, clampf(a, 0.0, 1.0))
		return
	rect.material = _material
	rect.color = Palette.ABYSS_900
	if _phase == Phase.COVER:
		radius = RADIUS_MAX * p * p * p
	else:
		var q := 1.0 - p
		radius = RADIUS_MAX * (1.0 - q * q * q)
	_material.set_shader_parameter("centre", centre)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("reveal", _phase == Phase.REVEAL)


func _finish() -> void:
	if _phase == Phase.IDLE:
		return
	last_duration_msec = int(round(_now() - _t0))
	_phase = Phase.IDLE
	_skip = false
	rect.visible = false
	rect.material = _material
	radius = 0.0
	finished.emit()
