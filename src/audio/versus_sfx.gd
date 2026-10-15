class_name VersusSfx
extends Node
## Versus sound effects (03-UI-SPEC 6.3 / 11.1, TORP-04, 03-SPEC req 9). Two procedural streams,
## no recorded audio (no copyright, D-27b):
##   ping      - sonar ping: a short rising sine blip (1.1 kHz -> 1.7 kHz) with a soft echo
##               tail, played on the launch beat of a threat aimed at the local seat (one of the
##               four telegraph cues, alongside the alert slot, edge flash and warhead rings).
##   collision - a noisy low clunk, played for everyone on any head-on COLLISION (spec req 9).
## Pooled AudioStreamPlayers on the "SFX" bus (Master if the bus is missing), like SfxPool.
## Headless safe: the dummy audio driver accepts play(); nothing here needs a device.
## Pings are de-duplicated per torpedo id, so the IncomingAlert and bind() can both request the
## ping for the same launch and it still plays once.

const POOL_SIZE := 4
const PING_SEC := 0.22
const COLLISION_SEC := 0.32
const PING_DB := -12.0
const COLLISION_DB := -9.0
const MAX_REMEMBERED_IDS := 64

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _ping: AudioStreamWAV
var _collision: AudioStreamWAV
var _channel: EventChannel
var _local_seat: int = 0
var _pinged_ids: Array[int] = []
var _ping_count: int = 0
var _collision_count: int = 0


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if _ping == null:
		_ping = make_ping()
	if _collision == null:
		_collision = make_collision()
	if _players.is_empty():
		var bus: StringName = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		for i in range(POOL_SIZE):
			var p := AudioStreamPlayer.new()
			p.bus = bus
			add_child(p)
			_players.append(p)


## Listens to the channel: ping on TORPEDO_LAUNCH aimed at local_seat, collision on any COLLISION.
func bind(channel: EventChannel, local_seat: int) -> void:
	if _channel != null and _channel.received.is_connected(_on_event):
		_channel.received.disconnect(_on_event)
	_channel = channel
	_local_seat = local_seat
	if _channel != null:
		_channel.received.connect(_on_event)


func _on_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		GameEvent.TORPEDO_LAUNCH:
			if int(e.get("to", -1)) == _local_seat:
				ping(int(e.get("id", -1)))
		GameEvent.COLLISION:
			collision()


## Plays the sonar ping. With a torpedo id >= 0 it plays at most once per id (returns false for
## a repeat). True when a player was started.
func ping(id: int = -1) -> bool:
	if id >= 0:
		if _pinged_ids.has(id):
			return false
		_pinged_ids.append(id)
		if _pinged_ids.size() > MAX_REMEMBERED_IDS:
			_pinged_ids.pop_front()
	if not _play(_ensure_ping()):
		return false
	_ping_count += 1
	return true


## Plays the collision clunk (for everyone, spec req 9). True when a player was started.
func collision() -> bool:
	if not _play(_ensure_collision()):
		return false
	_collision_count += 1
	return true


func ping_count() -> int:
	return _ping_count


func collision_count() -> int:
	return _collision_count


func players() -> Array[AudioStreamPlayer]:
	return _players


func _ensure_ping() -> AudioStreamWAV:
	_ensure()
	return _ping


func _ensure_collision() -> AudioStreamWAV:
	_ensure()
	return _collision


func _play(stream: AudioStreamWAV) -> bool:
	if _players.is_empty() or stream == null or not is_inside_tree():
		return false
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.play()
	return true


## Sonar ping: phase-continuous sine sweeping 1.1 -> 1.7 kHz over the first 60 ms, 3 ms attack,
## exponential decay, plus one quieter echo 90 ms later. 16-bit mono, peak at PING_DB.
static func make_ping(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(PING_SEC * rate)
	var amp := db_to_linear(PING_DB)
	var attack := maxi(int(0.003 * rate), 1)
	var echo := int(0.09 * rate)
	var dry := PackedFloat32Array()
	dry.resize(n)
	var phase := 0.0
	for i in range(n):
		var tt := float(i) / rate
		var f := lerpf(1100.0, 1700.0, clampf(tt / 0.06, 0.0, 1.0))
		var env := minf(1.0, float(i) / attack) * exp(-tt / 0.045)
		dry[i] = sin(TAU * phase) * env
		phase += f / rate
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in range(n):
		var s := dry[i]
		if i >= echo:
			s += dry[i - echo] * 0.35
		var tail := minf(1.0, float(n - 1 - i) / maxf(0.008 * rate, 1.0))  # no click at the end
		buf.encode_s16(i * 2, int(round(clampf(s * tail, -1.0, 1.0) * amp * 32767.0)))
	return AudioSynth._wav16(buf, rate)


## Collision: 60 Hz thump falling to 40 Hz plus a deterministic noise burst, ~320 ms.
static func make_collision(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(COLLISION_SEC * rate)
	var amp := db_to_linear(COLLISION_DB)
	var attack := maxi(int(0.002 * rate), 1)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var seed_v := 424242
	var phase := 0.0
	var lp := 0.0
	for i in range(n):
		var tt := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		lp += (noise - lp) * 0.25  # dull the noise a little
		var f := lerpf(60.0, 40.0, clampf(tt / COLLISION_SEC, 0.0, 1.0))
		var thump := sin(TAU * phase) * exp(-tt / 0.09)
		var crash := lp * exp(-tt / 0.05)
		phase += f / rate
		var env := minf(1.0, float(i) / attack) * minf(1.0, float(n - 1 - i) / maxf(0.01 * rate, 1.0))
		var s := clampf((thump * 0.75 + crash * 0.6) * env, -1.0, 1.0)
		buf.encode_s16(i * 2, int(round(s * amp * 32767.0)))
	return AudioSynth._wav16(buf, rate)
