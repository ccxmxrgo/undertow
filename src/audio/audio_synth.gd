class_name AudioSynth
extends RefCounted
## Procedural audio. Pre-rendered AudioStreamWAV only (never AudioStreamGenerator as the
## clock stream). Beat 0 sits at stream time 0; pre-roll is the Conductor's job.
## Phase 1 content is procedural (no copyright, D-27b); a CC0 OGG may replace make_song later.

const CLICK_SAMPLES := 1200  # ~27 ms burst at 44.1 kHz


## 16-bit mono PCM, 1 kHz decaying burst at each beat. rate <= 0 uses the mixer rate.
static func make_click_track(bpm: float, seconds: float, rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(seconds * rate)
	var buf := PackedByteArray()
	buf.resize(n * 2)  # zero-filled = silence
	var spb := 60.0 / bpm
	var beat := 0
	while true:
		var start := int(round(beat * spb * rate))
		if start >= n:
			break
		for i in range(mini(CLICK_SAMPLES, n - start)):
			var s := sin(TAU * 1000.0 * i / rate) * exp(-i / 250.0) * 0.8
			buf.encode_s16((start + i) * 2, int(s * 32767.0))
		beat += 1
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = buf
	return w


## Short hit tick (SFX). pitch 1.0 = 1800 Hz; Good uses a lower pitch. ~45 ms, 16-bit mono.
static func make_tick(pitch: float = 1.0, rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(0.045 * rate)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in range(n):
		var s := sin(TAU * 1800.0 * pitch * i / rate) * exp(-i / (0.008 * rate)) * 0.5
		buf.encode_s16(i * 2, int(s * 32767.0))
	return _wav16(buf, rate)


## Dull low clunk for a Miss: 90 Hz thump plus a little deterministic noise. ~140 ms.
static func make_clunk(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(0.14 * rate)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var seed_v := 12345
	for i in range(n):
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		var env := exp(-i / (0.035 * rate))
		var s := (sin(TAU * 90.0 * i / rate) * 0.7 + noise * 0.15) * env * 0.6
		buf.encode_s16(i * 2, int(s * 32767.0))
	return _wav16(buf, rate)


## UI navigation blips (02.2 UI-SPEC 10.4, VIS-09). 16-bit mono, phase-continuous, with a
## 2 ms attack and an 8 ms release so neither end clicks. Peaks are exact dBFS levels:
##   move    1.6 kHz sine, 30 ms, -18 dBFS
##   confirm 880 Hz then 1320 Hz (two equal steps), 70 ms, -14 dBFS
##   back    1320 Hz then 660 Hz (two equal steps), 60 ms, -16 dBFS
##   error   220 Hz square, 90 ms, -18 dBFS
## Unknown names return null.
static func make_ui_blip(blip_name: String, rate: int = 0) -> AudioStreamWAV:
	var spec: Dictionary
	match blip_name:
		"move":
			spec = {"sec": 0.030, "db": -18.0, "f0": 1600.0, "f1": 1600.0, "square": false}
		"confirm":
			spec = {"sec": 0.070, "db": -14.0, "f0": 880.0, "f1": 1320.0, "square": false}
		"back":
			spec = {"sec": 0.060, "db": -16.0, "f0": 1320.0, "f1": 660.0, "square": false}
		"error":
			spec = {"sec": 0.090, "db": -18.0, "f0": 220.0, "f1": 220.0, "square": true}
		_:
			return null
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(float(spec["sec"]) * rate)
	var amp := db_to_linear(float(spec["db"]))
	var attack := maxi(int(0.002 * rate), 1)
	var release := maxi(int(0.008 * rate), 1)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var f: float = spec["f0"] if i < n / 2 else spec["f1"]
		var env := minf(1.0, minf(float(i) / attack, float(n - 1 - i) / release))
		var s: float
		if spec["square"]:
			s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		else:
			s = sin(TAU * phase)
		buf.encode_s16(i * 2, int(round(s * env * amp * 32767.0)))
		phase += f / rate
	return _wav16(buf, rate)


static func _wav16(buf: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = buf
	return w


## Kick on every beat plus a bass sine on each bar's first two beats, following a tempo map
## ({time, bpm} sorted, 4/4) so a tempo change is audible. 16-bit mono PCM.
static func make_song(tempo_map: Array, seconds: float, rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(seconds * rate)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var beat := 0
	var t := 0.0
	var seg := 0
	while t < seconds:
		while seg + 1 < tempo_map.size() and tempo_map[seg + 1]["time"] <= t + 1e-9:
			seg += 1
		var spb: float = 60.0 / float(tempo_map[seg]["bpm"])
		var start := int(round(t * rate))
		var kick_n := mini(int(0.15 * rate), n - start)
		for i in range(kick_n):
			var tt := float(i) / rate
			mix[start + i] += sin(TAU * (50.0 + 90.0 * exp(-tt * 40.0)) * tt) * exp(-tt * 18.0) * 0.7
		if beat % 4 == 0:
			var pitch := 55.0 * (1.0 if (beat / 4) % 2 == 0 else 1.5)
			var bass_n := mini(int(spb * 2.0 * rate), n - start)
			for i in range(bass_n):
				var tt := float(i) / rate
				mix[start + i] += sin(TAU * pitch * tt) * (1.0 - float(i) / bass_n) * 0.35
		t += spb
		beat += 1
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in range(n):
		buf.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = buf
	return w
