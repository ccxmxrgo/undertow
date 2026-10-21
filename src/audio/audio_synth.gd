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


# --- Phase 5 SFX bank (05-01, AV-03, AV-04, D-02, D-04, D-05, D-12) -------------------------
# Every stream below is rendered in code (no recorded or downloaded audio). Gameplay reads them
# from sfx_bank(), which builds once per process at load time, never mid-song.

## Digital silence at the head of make_sonar_ping. Starting the ping PING_LEAD_SEC early (or
## seeking into it) lands its onset exactly on a downbeat.
const PING_LEAD_SEC := 0.15
## Peak level of the downbeat sonar ping, in dBFS.
const SONAR_PING_DB := -20.0
## Seeds of the four hull-creak variants held in sfx_bank()["creaks"], in this order.
const CREAK_SEEDS: Array[int] = [11, 23, 37, 51]

static var _sfx_cache: Dictionary = {}
static var _sfx_rate := 0


## Downbeat sonar ping (D-02): a soft low "pong", clearly unlike VersusSfx.make_ping (the
## 1.1 -> 1.7 kHz incoming-torpedo blip). Recipe:
##   lead     PING_LEAD_SEC of exact zeros
##   body     phase-continuous sine gliding 700 -> 520 Hz over 120 ms, 4 ms linear attack,
##            exp decay tau 0.12 s, plus a 2nd harmonic at 0.15 for a little sonar ring
##   echoes   dry body again at +180 ms (x0.30) and +360 ms (x0.12)
##   level    peak normalised to SONAR_PING_DB, 8 ms fade-out at the end
## Total length PING_LEAD_SEC + 0.75 s. 16-bit mono.
static func make_sonar_ping(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int((PING_LEAD_SEC + 0.75) * rate)
	var lead := int(round(PING_LEAD_SEC * rate))
	var body_n := n - lead
	var attack := maxi(int(0.004 * rate), 1)
	var dry := PackedFloat32Array()
	dry.resize(body_n)
	var phase := 0.0
	for i in range(body_n):
		var tt := float(i) / rate
		var f := lerpf(700.0, 520.0, clampf(tt / 0.12, 0.0, 1.0))
		var env := minf(1.0, float(i) / attack) * exp(-tt / 0.12)
		dry[i] = (sin(TAU * phase) + 0.15 * sin(TAU * 2.0 * phase)) * env
		phase += f / rate
	var e1 := int(0.18 * rate)
	var e2 := int(0.36 * rate)
	var fade := maxf(0.008 * rate, 1.0)
	var wet := PackedFloat32Array()
	wet.resize(body_n)
	var peak := 0.0
	for i in range(body_n):
		var s := dry[i]
		if i >= e1:
			s += dry[i - e1] * 0.30
		if i >= e2:
			s += dry[i - e2] * 0.12
		s *= minf(1.0, float(body_n - 1 - i) / fade)
		wet[i] = s
		peak = maxf(peak, absf(s))
	var gain := db_to_linear(SONAR_PING_DB) / maxf(peak, 1e-9)
	var buf := PackedByteArray()
	buf.resize(n * 2)  # zero-filled = the lead silence
	for i in range(body_n):
		buf.encode_s16((lead + i) * 2, int(round(wet[i] * gain * 32767.0)))
	return _wav16(buf, rate)


## Hull creak (D-04, stick-slip model), deterministic per seed. Recipe:
##   length   0.5 + 0.7 * u seconds (u from an LCG seeded by `seed`)
##   source   impulse train whose rate wanders 25..70 Hz (random walk with jitter plus a slow
##            glide up or down chosen by the seed), each impulse with a jittered strength
##   body     two 2-pole resonators, ~350 Hz (Q 8) and ~900 Hz (Q 6), centres detuned +-10%
##            by seed, plus a little one-pole lowpassed LCG noise (~0.05)
##   envelope smoothstep swell over the first 35%, then exp decay
##   level    10 ms fade in and out, peak normalised to 0.7
## O(n), no per-sample allocation. 16-bit mono.
static func make_creak(seed: int, rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var seed_v := (seed * 7919 + 104729) & 0x7FFFFFFF
	seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
	var sec := 0.5 + 0.7 * float(seed_v) / float(0x7FFFFFFF)
	seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
	var f_start := 30.0 + 30.0 * float(seed_v) / float(0x7FFFFFFF)
	seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
	var glide := (float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0) * 25.0  # Hz over the creak
	seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
	var f1 := 350.0 * (0.9 + 0.2 * float(seed_v) / float(0x7FFFFFFF))
	seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
	var f2 := 900.0 * (0.9 + 0.2 * float(seed_v) / float(0x7FFFFFFF))
	var r1 := exp(-PI * f1 / (8.0 * rate))
	var c1 := 2.0 * r1 * cos(TAU * f1 / rate)
	var q1 := r1 * r1
	var r2 := exp(-PI * f2 / (6.0 * rate))
	var c2 := 2.0 * r2 * cos(TAU * f2 / rate)
	var q2 := r2 * r2
	var n := int(sec * rate)
	var swell := maxi(int(0.35 * n), 1)
	var tau := maxf((n - swell) / float(rate) / 3.0, 0.01)
	var fade := maxf(0.01 * rate, 1.0)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var phase := 0.0
	var walk := 0.0
	var lp := 0.0
	var y1a := 0.0
	var y1b := 0.0
	var y2a := 0.0
	var y2b := 0.0
	var peak := 0.0
	for i in range(n):
		var tt := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		walk = clampf(walk + noise * 0.05, -10.0, 10.0)
		var hz := clampf(f_start + glide * tt / sec + walk, 25.0, 70.0)
		phase += hz / rate
		var x := 0.0
		if phase >= 1.0:
			phase -= 1.0
			x = 0.55 + 0.45 * absf(noise)
		lp += (noise - lp) * 0.05
		var y1 := x + c1 * y1a - q1 * y1b
		y1b = y1a
		y1a = y1
		var y2 := x + c2 * y2a - q2 * y2b
		y2b = y2a
		y2a = y2
		var env: float
		if i < swell:
			env = smoothstep(0.0, 1.0, float(i) / swell)
		else:
			env = exp(-float(i - swell) / rate / tau)
		env *= minf(1.0, minf(float(i) / fade, float(n - 1 - i) / fade))
		var s := (y1 * 0.06 + y2 * 0.04 + lp * 0.5) * env
		mix[i] = s
		peak = maxf(peak, absf(s))
	var gain := 0.7 / maxf(peak, 1e-9)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in range(n):
		buf.encode_s16(i * 2, int(round(mix[i] * gain * 32767.0)))
	return _wav16(buf, rate)


## Torpedo impact on your own board (D-05): a deep hit, distinct from VersusSfx.make_collision.
## Recipe:
##   body     sine falling 55 -> 35 Hz (pitch tau 0.25 s), amplitude decay tau 0.2 s
##   crack    one-pole lowpassed LCG noise at 0.6, decay tau 0.04 s
##   shape    2 ms attack (sub-thud), 10 ms tail fade
##   level    peak normalised to -6 dBFS
## 0.6 s, 16-bit mono, fixed seed.
static func make_impact(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(0.6 * rate)
	var attack := maxf(0.002 * rate, 1.0)
	var fade := maxf(0.01 * rate, 1.0)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var seed_v := 505050
	var phase := 0.0
	var lp := 0.0
	for i in range(n):
		var tt := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		lp += (noise - lp) * 0.15
		var body := sin(TAU * phase) * exp(-tt / 0.2)
		var crack := lp * 0.6 * exp(-tt / 0.04)
		phase += (35.0 + 20.0 * exp(-tt / 0.25)) / rate
		var env := minf(1.0, minf(float(i) / attack, float(n - 1 - i) / fade))
		mix[i] = (body + crack) * env
	return _encode_peak(mix, db_to_linear(-6.0), rate)


## Torpedo launch for the shooter (D-05): a short thump then a rising whoosh. Recipe:
##   thump    80 Hz sine, decay tau 0.06 s, 2 ms attack
##   whoosh   LCG noise through a one-pole lowpass whose coefficient rises 0.02 -> 0.25 over
##            0.3 s, envelope sin(pi * t / 0.4) (peaks around 0.2 s, silent after 0.4 s)
##   level    10 ms tail fade, peak normalised to -9 dBFS
## 0.45 s, 16-bit mono, fixed seed.
static func make_launch(rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(0.45 * rate)
	var attack := maxf(0.002 * rate, 1.0)
	var fade := maxf(0.01 * rate, 1.0)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var seed_v := 616161
	var lp := 0.0
	for i in range(n):
		var tt := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		lp += (noise - lp) * lerpf(0.02, 0.25, clampf(tt / 0.3, 0.0, 1.0))
		var thump := sin(TAU * 80.0 * tt) * exp(-tt / 0.06)
		var whoosh := lp * 2.0 * maxf(0.0, sin(PI * tt / 0.4))
		var env := minf(1.0, minf(float(i) / attack, float(n - 1 - i) / fade))
		mix[i] = (thump + whoosh) * env
	return _encode_peak(mix, db_to_linear(-9.0), rate)


## Implosion (D-05). Near = your own hull; distant = a rival's, heard through the water.
## Recipe:
##   rumble   40 Hz sine, decay tau 0.6 s
##   crunch   LCG noise burst, decay tau 0.12 s
##   metal    decaying sines 210 / 470 / 1130 Hz (tau 0.5 / 0.35 / 0.2 s) from 30 ms in
##   groan    late secondary glide 90 -> 60 Hz from 0.5 s
##   shape    2 ms attack, 10 ms tail fade
##   near     peak normalised to -4 dBFS
##   distant  same mix through a 2-stage one-pole lowpass (~600 Hz), peak = near peak x -14 dB
## 1.4 s, 16-bit mono, fixed seed.
static func make_implosion(distant: bool = false, rate: int = 0) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(AudioServer.get_mix_rate())
	var n := int(1.4 * rate)
	var attack := maxf(0.002 * rate, 1.0)
	var fade := maxf(0.01 * rate, 1.0)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var seed_v := 727272
	var groan_phase := 0.0
	for i in range(n):
		var tt := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed_v) / float(0x7FFFFFFF) * 2.0 - 1.0
		var s := sin(TAU * 40.0 * tt) * exp(-tt / 0.6)
		s += noise * 0.5 * exp(-tt / 0.12)
		if tt >= 0.03:
			var tm := tt - 0.03
			var m_env := minf(1.0, tm / 0.002)
			s += m_env * (0.30 * sin(TAU * 210.0 * tm) * exp(-tm / 0.5)
				+ 0.22 * sin(TAU * 470.0 * tm) * exp(-tm / 0.35)
				+ 0.14 * sin(TAU * 1130.0 * tm) * exp(-tm / 0.2))
		if tt >= 0.5:
			var tg := tt - 0.5
			s += sin(TAU * groan_phase) * minf(1.0, tg / 0.05) * exp(-tg / 0.35) * 0.5
			groan_phase += (60.0 + 30.0 * exp(-tg / 0.3)) / rate
		mix[i] = s * minf(1.0, minf(float(i) / attack, float(n - 1 - i) / fade))
	var near_peak := db_to_linear(-4.0)
	if not distant:
		return _encode_peak(mix, near_peak, rate)
	var a := 1.0 - exp(-TAU * 600.0 / rate)
	var y1 := 0.0
	var y2 := 0.0
	for i in range(n):
		y1 += (mix[i] - y1) * a
		y2 += (y1 - y2) * a
		mix[i] = y2
	return _encode_peak(mix, near_peak * db_to_linear(-14.0), rate)


## Scales `mix` so its peak is `peak_lin` and encodes it as 16-bit mono.
static func _encode_peak(mix: PackedFloat32Array, peak_lin: float, rate: int) -> AudioStreamWAV:
	var peak := 0.0
	for v in mix:
		peak = maxf(peak, absf(v))
	var gain := peak_lin / maxf(peak, 1e-9)
	var buf := PackedByteArray()
	buf.resize(mix.size() * 2)
	for i in range(mix.size()):
		buf.encode_s16(i * 2, int(round(clampf(mix[i] * gain, -1.0, 1.0) * 32767.0)))
	return _wav16(buf, rate)


## The Phase 5 SFX bank, built once per process (and rebuilt only if the mix rate changes).
## Keys: "sonar_ping", "creaks" (Array of 4 in CREAK_SEEDS order), "impact", "launch",
## "implosion", "implosion_distant". Call it at gameplay load so nothing is synthesised
## mid-song. Treat the returned Dictionary and streams as read-only.
static func sfx_bank() -> Dictionary:
	var rate := int(AudioServer.get_mix_rate())
	if not _sfx_cache.is_empty() and _sfx_rate == rate:
		return _sfx_cache
	var creaks: Array[AudioStreamWAV] = []
	for s in CREAK_SEEDS:
		creaks.append(make_creak(s, rate))
	_sfx_cache = {
		"sonar_ping": make_sonar_ping(rate),
		"creaks": creaks,
		"impact": make_impact(rate),
		"launch": make_launch(rate),
		"implosion": make_implosion(false, rate),
		"implosion_distant": make_implosion(true, rate),
	}
	_sfx_rate = rate
	return _sfx_cache


## Empties the sfx_bank() cache (tests only).
static func clear_sfx_cache() -> void:
	_sfx_cache = {}
	_sfx_rate = 0
