class_name AudioSynth
extends RefCounted
## Procedural audio. Pre-rendered AudioStreamWAV only (never AudioStreamGenerator as the
## clock stream). Beat 0 sits at stream time 0; pre-roll is the Conductor's job.

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
