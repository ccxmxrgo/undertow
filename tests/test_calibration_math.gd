extends GdUnitTestSuite
## CAL-01: audio offset from tap-to-click calibration. Sign: positive = player late.

func _clicks(n: int, bpm: float) -> Array[float]:
	var out: Array[float] = []
	var spb := 60.0 / bpm
	for i in range(n):
		out.append(1.0 + i * spb)
	return out


func _shifted(clicks: Array[float], by: float) -> Array[float]:
	var out: Array[float] = []
	for c in clicks:
		out.append(c + by)
	return out


func test_recovers_plus_37ms_bias() -> void:
	var clicks := _clicks(16, 100.0)
	var taps := _shifted(clicks, 0.037)
	var off := CalibrationMath.audio_offset_from_taps(taps, clicks)
	assert_float(off).is_equal_approx(0.037, 0.001)


func test_recovers_negative_bias() -> void:
	var clicks := _clicks(16, 100.0)
	var off := CalibrationMath.audio_offset_from_taps(_shifted(clicks, -0.020), clicks)
	assert_float(off).is_equal_approx(-0.020, 0.001)


func test_outliers_do_not_move_median() -> void:
	var clicks := _clicks(16, 100.0)
	var taps := _shifted(clicks, 0.037)
	taps[6] += 0.25
	taps[9] -= 0.2
	taps[12] += 0.18
	var off := CalibrationMath.audio_offset_from_taps(taps, clicks)
	assert_float(off).is_equal_approx(0.037, 0.001)


func test_first_four_taps_discarded() -> void:
	var clicks := _clicks(16, 100.0)
	var taps := _shifted(clicks, 0.037)
	for i in range(4):
		taps[i] += 0.15  # warm-up sloppiness must not count
	assert_float(CalibrationMath.audio_offset_from_taps(taps, clicks)).is_equal_approx(0.037, 0.001)


func test_too_few_taps_returns_nan() -> void:
	var clicks := _clicks(16, 100.0)
	var taps := _shifted(clicks, 0.037).slice(0, 11)  # 7 remaining after discard
	assert_bool(is_nan(CalibrationMath.audio_offset_from_taps(taps, clicks))).is_true()
	assert_bool(is_nan(CalibrationMath.audio_offset_from_taps([], clicks))).is_true()


func test_remeasure_after_applying_is_about_zero() -> void:
	var clicks := _clicks(16, 100.0)
	var applied := 0.037
	# Taps recorded in song time (offset already subtracted by the conductor).
	var measured: Array[float] = []
	for c in clicks:
		measured.append(c + 0.037 - applied)
	assert_float(CalibrationMath.audio_offset_from_taps(measured, clicks)).is_equal_approx(0.0, 0.001)
	# remove_applied_offset restores raw times so the absolute offset is stable.
	var raw := CalibrationMath.remove_applied_offset(measured, applied)
	assert_float(CalibrationMath.audio_offset_from_taps(raw, clicks)).is_equal_approx(0.037, 0.001)


func test_suspicious_and_clamp() -> void:
	assert_bool(CalibrationMath.is_suspicious(0.301)).is_true()
	assert_bool(CalibrationMath.is_suspicious(-0.4)).is_true()
	assert_bool(CalibrationMath.is_suspicious(0.3)).is_false()
	assert_bool(CalibrationMath.is_suspicious(0.037)).is_false()
	assert_float(CalibrationMath.clamp_offset(0.9)).is_equal(0.5)
	assert_float(CalibrationMath.clamp_offset(-0.9)).is_equal(-0.5)
	assert_float(CalibrationMath.visual_offset_clamp(0.9)).is_equal(0.5)
	assert_float(CalibrationMath.visual_offset_clamp(0.9, true)).is_equal(0.2)
	assert_float(CalibrationMath.visual_offset_clamp(-0.9, true)).is_equal(-0.2)
