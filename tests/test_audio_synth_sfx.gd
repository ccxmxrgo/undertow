extends GdUnitTestSuite
## Phase 5 procedural SFX bank (05-01, AV-03, AV-04, D-02, D-04, D-05, D-12): downbeat sonar
## ping with lead silence, seeded hull creaks, and the once-per-process sfx_bank() cache.

const RATE := 44100


func after_test() -> void:
	AudioSynth.clear_sfx_cache()


## Decodes a 16-bit mono stream into floats in [-1, 1].
func _samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var n := w.data.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(w.data.decode_s16(i * 2)) / 32767.0
	return out


func _peak(s: PackedFloat32Array, from: int = 0, to: int = -1) -> float:
	if to < 0:
		to = s.size()
	var p := 0.0
	for i in range(from, to):
		p = maxf(p, absf(s[i]))
	return p


func _rms(s: PackedFloat32Array, from: int = 0, to: int = -1) -> float:
	if to < 0:
		to = s.size()
	if to <= from:
		return 0.0
	var acc := 0.0
	for i in range(from, to):
		acc += s[i] * s[i]
	return sqrt(acc / float(to - from))


## Zero-crossing frequency estimate (crossings / 2 / seconds) over [from, to).
func _zcr_hz(s: PackedFloat32Array, from: int, to: int) -> float:
	var crossings := 0
	var prev := 0.0
	for i in range(from, to):
		var v := s[i]
		if v == 0.0:
			continue
		if prev != 0.0 and signf(v) != signf(prev):
			crossings += 1
		prev = v
	return float(crossings) / 2.0 / (float(to - from) / RATE)


func _assert_format(w: AudioStreamWAV) -> void:
	assert_object(w).is_not_null()
	assert_int(w.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_bool(w.stereo).is_false()
	assert_int(w.mix_rate).is_equal(RATE)


func _assert_clean_ends(s: PackedFloat32Array) -> void:
	assert_float(absf(s[0])).is_less_equal(0.01)
	assert_float(absf(s[s.size() - 1])).is_less_equal(0.01)
	assert_float(_peak(s)).is_less_equal(0.9)
	assert_float(_peak(s)).is_greater(0.0)


# --- Sonar ping (D-02) ---------------------------------------------------------------------

func test_sonar_ping_format_and_length() -> void:
	var w := AudioSynth.make_sonar_ping(RATE)
	_assert_format(w)
	var s := _samples(w)
	var expected := (AudioSynth.PING_LEAD_SEC + 0.75) * RATE
	assert_float(absf(s.size() - expected)).is_less_equal(1.0)


func test_sonar_ping_lead_is_digital_silence() -> void:
	var s := _samples(AudioSynth.make_sonar_ping(RATE))
	var lead := int(round(AudioSynth.PING_LEAD_SEC * RATE))
	for i in lead:
		if s[i] != 0.0:
			fail("non-zero sample %d inside the ping lead" % i)
			return
	var first := -1
	for i in range(lead, s.size()):
		if s[i] != 0.0:
			first = i
			break
	assert_int(first).is_greater_equal(lead)
	assert_int(first - lead).is_less_equal(int(0.002 * RATE))


func test_sonar_ping_level_and_tail() -> void:
	var s := _samples(AudioSynth.make_sonar_ping(RATE))
	assert_float(_peak(s)).is_equal_approx(db_to_linear(AudioSynth.SONAR_PING_DB), 0.01)
	var tail := int(0.005 * RATE)
	assert_float(_peak(s, s.size() - tail)).is_less_equal(0.01)
	_assert_clean_ends(s)


func test_sonar_ping_is_lower_than_incoming_ping() -> void:
	var s := _samples(AudioSynth.make_sonar_ping(RATE))
	var lead := int(round(AudioSynth.PING_LEAD_SEC * RATE))
	var hz := _zcr_hz(s, lead, lead + int(0.06 * RATE))
	assert_float(hz).is_less(800.0)
	assert_float(hz).is_greater(300.0)
	var incoming := _samples(VersusSfx.make_ping(RATE))
	assert_float(_zcr_hz(incoming, 0, int(0.06 * RATE))).is_greater(1100.0)


# --- Hull creaks (D-04) --------------------------------------------------------------------

func test_creak_is_deterministic_per_seed() -> void:
	var a := AudioSynth.make_creak(11, RATE)
	var b := AudioSynth.make_creak(11, RATE)
	assert_bool(a.data == b.data).is_true()
	var c := AudioSynth.make_creak(23, RATE)
	assert_bool(a.data == c.data).is_false()


func test_creaks_shape_and_level() -> void:
	for seed in AudioSynth.CREAK_SEEDS:
		var w := AudioSynth.make_creak(seed, RATE)
		_assert_format(w)
		var s := _samples(w)
		var sec := float(s.size()) / RATE
		assert_float(sec).is_between(0.5, 1.2)
		assert_float(_peak(s)).is_between(0.3, 0.9)
		assert_float(_rms(s)).is_greater(0.02)
		_assert_clean_ends(s)


# --- Bank cache ----------------------------------------------------------------------------

func test_sfx_bank_has_ping_and_creaks() -> void:
	var bank := AudioSynth.sfx_bank()
	assert_bool(bank.has("sonar_ping")).is_true()
	assert_bool(bank.has("creaks")).is_true()
	assert_object(bank["sonar_ping"]).is_not_null()
	assert_int((bank["creaks"] as Array).size()).is_equal(4)
	for c in bank["creaks"]:
		assert_object(c).is_not_null()


func test_sfx_bank_is_cached_once_per_process() -> void:
	AudioSynth.clear_sfx_cache()
	var a := AudioSynth.sfx_bank()
	var b := AudioSynth.sfx_bank()
	assert_bool(is_same(a["sonar_ping"], b["sonar_ping"])).is_true()
	for i in 4:
		assert_bool(is_same(a["creaks"][i], b["creaks"][i])).is_true()
	AudioSynth.clear_sfx_cache()
	var c := AudioSynth.sfx_bank()
	assert_bool(is_same(a["sonar_ping"], c["sonar_ping"])).is_false()
	assert_bool(is_same(a["creaks"][0], c["creaks"][0])).is_false()
