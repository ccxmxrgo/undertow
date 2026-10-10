extends Node
## Autoload "UiSounds" (02.2 plan 23, VIS-09, UI-SPEC 10.4): soft procedural navigation blips on
## the existing SFX bus (so Settings volume_sfx applies). Gameplay hit sounds (SfxPool) are
## untouched.
##   move    a focus change caused by a navigation press (ui_up/down/left/right, focus next/prev)
##   confirm ui_accept pressed
##   back    ui_cancel pressed
##   error   only on request (play("error"))
## Events are observed in _input and never consumed. Programmatic focus (a screen grabbing focus
## when it opens) is silent: "move" needs a navigation press in the same or the previous frame.
## Nothing plays while a Gameplay runs (count-in and play; results / fail screens are menus
## again), and nothing plays while `muted` is set: the calibration wizard mutes it for its audio
## and visual measuring steps (W7, T-02.2-43). Setting `muted` also stops any blip in flight.

const BUS := &"SFX"
const NAMES: Array[String] = ["move", "confirm", "back", "error"]
const POOL_SIZE := 4
const NAV_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]
## A focus change at most this many process frames after a navigation press plays "move".
const NAV_FRAMES := 1

var muted: bool = false:
	set(v):
		muted = v
		if v:
			for p in _players:
				p.stop()
## Last blip actually played ("" = none yet). Read by tests and the playtest harness.
var last_played: String = ""
var play_count: int = 0
## Tests: the node treated as the current scene (null = SceneTree.current_scene).
var scene_override: Node = null

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last: AudioStreamPlayer
var _streams: Dictionary = {}
var _nav_frame: int = -1000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for blip_name in NAMES:
		_streams[blip_name] = AudioSynth.make_ui_blip(blip_name)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Blip%d" % i
		p.bus = bus_name()
		add_child(p)
		_players.append(p)
	var vp := get_viewport()
	if vp != null and not vp.gui_focus_changed.is_connected(on_focus_changed):
		vp.gui_focus_changed.connect(on_focus_changed)


func bus_name() -> StringName:
	return BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"


func last_player() -> AudioStreamPlayer:
	return _last


## Plays a blip by name. Returns false (and plays nothing) for unknown names, while muted and
## while a Gameplay is running.
func play(blip_name: String) -> bool:
	if muted or not _streams.has(blip_name) or _players.is_empty() or suppressed():
		return false
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[blip_name]
	p.play()
	_last = p
	last_played = blip_name
	play_count += 1
	return true


## True while the current scene is a Gameplay in its running state (intro, count-in, play,
## pause). FAILED / DONE (fail and results screens) are menus.
func suppressed() -> bool:
	var scene := scene_override
	if scene == null and is_inside_tree():
		scene = get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return false
	return scene is Gameplay and (scene as Gameplay).state == Gameplay.State.RUNNING


func _input(event: InputEvent) -> void:
	handle_input(event)


## Observes one input event (never consumes it).
func handle_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	for a in NAV_ACTIONS:
		if event.is_action_pressed(a, true):
			_nav_frame = Engine.get_process_frames()
			return
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_accept"):
		play("confirm")
	elif event.is_action_pressed(&"ui_cancel"):
		play("back")


func on_focus_changed(_control: Control) -> void:
	if Engine.get_process_frames() - _nav_frame <= NAV_FRAMES:
		play("move")
