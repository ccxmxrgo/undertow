extends GdUnitTestSuite
## 05-05 (AV-04, D-05): torpedo juice. FlashLimiter (03-UI-SPEC 11.6 photosensitivity rule:
## <= 3 flashes per second, >= 1/3 s apart), TorpedoJuice reactions to existing EventChannel
## events (impact, launch, near / distant implosion), id dedupe, effect modes, the periscope
## implosion flash, the FailScreen implosion sound and the bind_views integration.


# ---- FlashLimiter ---------------------------------------------------------------------------

func test_flash_limiter_gap_and_window() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(0.0)).is_true()
	assert_bool(lim.try_flash(0.34)).is_true()
	assert_bool(lim.try_flash(0.68)).is_true()
	assert_bool(lim.try_flash(0.70)).is_false()  # within 1/3 s of the last
	assert_bool(lim.try_flash(0.99)).is_false()  # would be the 4th inside 1 s
	assert_bool(lim.try_flash(1.40)).is_true()


func test_flash_limiter_rejects_non_finite() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(NAN)).is_false()
	assert_bool(lim.try_flash(INF)).is_false()
	assert_bool(lim.try_flash(0.0)).is_true()


func test_flash_limiter_reset() -> void:
	var lim := FlashLimiter.new()
	assert_bool(lim.try_flash(5.0)).is_true()
	assert_bool(lim.try_flash(5.1)).is_false()
	lim.reset()
	assert_bool(lim.try_flash(5.1)).is_true()
