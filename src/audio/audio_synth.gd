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
