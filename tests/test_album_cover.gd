extends GdUnitTestSuite
## AlbumCover (UI-SPEC 4.10, D-11): safe art loading (size and dimension caps, square crop,
## <= 512 px), the deterministic generated cover, initials, the LRU cache and the lookup rule.

const D := "user://test_album_cover"
const FIXTURE_DIR := "res://tests/fixtures/album_art"


func before_test() -> void:
	SongFixture.rm_tree(D)
	SongFixture.mkdir(D)


func after_test() -> void:
	SongFixture.rm_tree(D)


func _entry(id: String, dir: String, title: String = "Song") -> SongEntry:
	var e := SongEntry.new()
	e.id = id
	e.title = title
	e.chart_path = dir.path_join("notes.chart")
	return e


func _wait_until(cond: Callable, timeout: float = 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			return false
		await get_tree().process_frame
	return true


# ---- load_art_image ----

func test_fixture_loads_as_centre_cropped_square() -> void:
	var img := AlbumCover.load_art_image(FIXTURE_DIR)
	assert_object(img).is_not_null()
	assert_int(img.get_width()).is_equal(48)
	assert_int(img.get_height()).is_equal(48)
	# 64x48 crops 8 px off each side: x 0 of the crop is source x 8 (ABYSS_700 half),
	# x 47 is source x 55 (SONAR half).
	assert_bool(img.get_pixel(0, 24).is_equal_approx(Palette.ABYSS_700)).is_true()
	assert_bool(img.get_pixel(47, 24).is_equal_approx(Palette.SONAR)).is_true()


func test_no_file_returns_null() -> void:
	assert_object(AlbumCover.load_art_image(D)).is_null()
	assert_object(AlbumCover.load_art_image(D + "/missing")).is_null()


func test_jpg_fallback_and_png_first() -> void:
	var img := Image.create(100, 200, false, Image.FORMAT_RGB8)
	img.fill(Palette.ABYSS_600)
	img.save_jpg(D + "/album.jpg")
	var j := AlbumCover.load_art_image(D)
	assert_object(j).is_not_null()
	assert_int(j.get_width()).is_equal(100)
	assert_int(j.get_height()).is_equal(100)
	var p := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	p.save_png(D + "/album.png")
	assert_int(AlbumCover.load_art_image(D).get_width()).is_equal(30)


func test_large_image_downscaled_to_512() -> void:
	var img := Image.create(1024, 600, false, Image.FORMAT_RGB8)
	img.save_png(D + "/album.png")
	var out := AlbumCover.load_art_image(D)
	assert_int(out.get_width()).is_equal(512)
	assert_int(out.get_height()).is_equal(512)
	assert_bool(out.has_mipmaps()).is_false()


func test_oversized_file_rejected_before_decode() -> void:
	var bytes := PackedByteArray()
	bytes.resize(AlbumCover.MAX_FILE_BYTES + 1)
	# A valid PNG signature so only the size cap can reject it.
	var sig := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	for i in sig.size():
		bytes[i] = sig[i]
	SongFixture.write_bytes(D + "/album.png", bytes)
	assert_object(AlbumCover.load_art_image(D)).is_null()


func test_too_large_dimensions_rejected() -> void:
	var img := Image.create(AlbumCover.MAX_DIM + 1, 2, false, Image.FORMAT_L8)
	img.save_png(D + "/album.png")
	assert_object(AlbumCover.load_art_image(D)).is_null()
	var tall := Image.create(2, AlbumCover.MAX_DIM + 1, false, Image.FORMAT_L8)
	tall.save_jpg(D + "/album.jpg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(D + "/album.png"))
	assert_object(AlbumCover.load_art_image(D)).is_null()


func test_corrupt_file_returns_null() -> void:
	SongFixture.write_bytes(D + "/album.png", SongFixture.garbage_bytes())
	assert_object(AlbumCover.load_art_image(D)).is_null()
	var trunc := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
	SongFixture.write_bytes(D + "/album.png", trunc)
	assert_object(AlbumCover.load_art_image(D)).is_null()


func test_lookup_only_album_names_in_chart_folder() -> void:
	# Art next to the chart under another name, or in the parent folder, is never used.
	SongFixture.mkdir(D + "/song")
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.save_png(D + "/song/cover.png")
	img.save_png(D + "/song/folder.jpg")
	img.save_png(D + "/album.png")
	var e := _entry("x", D + "/song")
	assert_str(AlbumCover.art_dir(e)).is_equal(D + "/song")
	assert_object(AlbumCover.load_art_image(AlbumCover.art_dir(e))).is_null()
	assert_str(AlbumCover.art_dir(SongEntry.new())).is_equal("")


# ---- generated cover ----

func test_generated_is_deterministic() -> void:
	var a := AlbumCover.generated("Sea Shanty 2")
	var b := AlbumCover.generated("Sea Shanty 2")
	assert_int(a.get_width()).is_equal(AlbumCover.GEN_SIZE)
	assert_int(a.get_height()).is_equal(AlbumCover.GEN_SIZE)
	assert_bool(a.get_data() == b.get_data()).is_true()
	# Title normalisation: case and outer spaces do not change the cover.
	assert_bool(AlbumCover.generated("  sea shanty 2 ").get_data() == a.get_data()).is_true()
	assert_bool(AlbumCover.generated("HRT").get_data() == a.get_data()).is_false()


func test_generated_gradient_pair_from_hash() -> void:
	for title in ["Sea Shanty 2", "HRT", "INVISIBLE", ""]:
		var h := title.strip_edges().to_lower().sha256_buffer()
		var idx := int(h[0]) % 8
		assert_int(AlbumCover.gradient_index(title)).is_equal(idx)
		var img := AlbumCover.generated(title)
		var pair: Array = Palette.COVER_GRADIENTS[idx]
		var tl := img.get_pixel(0, 0)
		var br := img.get_pixel(AlbumCover.GEN_SIZE - 1, AlbumCover.GEN_SIZE - 1)
		# The arc corner may tint one end by SONAR 14%; the far corner is the pure gradient stop.
		var corner := AlbumCover.arc_corner(title)
		var pure_tl: bool = corner != 0
		var pure_br: bool = corner != 3
		if pure_tl:
			assert_bool(_close(tl, pair[0])).is_true()
		if pure_br:
			assert_bool(_close(br, pair[1])).is_true()


func test_generated_draws_sonar_arcs() -> void:
	var title := "Sea Shanty 2"
	var img := AlbumCover.generated(title)
	var corner := AlbumCover.arc_corner(title)
	var origin := AlbumCover.corner_point(corner)
	var lit := 0
	for r in AlbumCover.ARC_RADII:
		# Sample along the arc; most samples sit on the ring (a gap is allowed by the phase).
		for k in 9:
			var ang := deg_to_rad(5.0 + 10.0 * k)
			var dir := Vector2((1.0 if origin.x == 0 else -1.0) * cos(ang), (1.0 if origin.y == 0 else -1.0) * sin(ang))
			var p := (Vector2(origin) + dir * float(r)).round()
			var px := img.get_pixel(clampi(int(p.x), 0, 511), clampi(int(p.y), 0, 511))
			if px.b > _gradient_at(title, int(p.x), int(p.y)).b + 0.02:
				lit += 1
	assert_int(lit).is_greater(20)


func test_initials() -> void:
	assert_str(AlbumCover.initials("Sea Shanty 2")).is_equal("SS")
	assert_str(AlbumCover.initials("HRT")).is_equal("H")
	assert_str(AlbumCover.initials("")).is_equal("?")
	assert_str(AlbumCover.initials("   ")).is_equal("?")
	assert_str(AlbumCover.initials("invisible touch remix")).is_equal("IT")


# ---- cache ----

func test_request_same_id_decodes_once() -> void:
	var cover := AlbumCover.new()
	var got: Array = []
	var cb := func(id: String, tex: Texture2D, _cached: bool) -> void: got.append([id, tex])
	var e := _entry("art", FIXTURE_DIR)
	cover.request(e, cb)
	cover.request(e, cb)
	assert_bool(await _wait_until(func() -> bool: return got.size() >= 2)).is_true()
	assert_int(cover.loads).is_equal(1)
	assert_object(got[0][1]).is_not_null()
	assert_int((got[0][1] as Texture2D).get_width()).is_equal(48)
	cover.request(e, cb)
	assert_int(got.size()).is_equal(3)
	assert_int(cover.loads).is_equal(1)
	cover.shutdown()


func test_missing_art_cached_as_none() -> void:
	var cover := AlbumCover.new()
	var got: Array = []
	var cb := func(id: String, tex: Texture2D, _cached: bool) -> void: got.append([id, tex])
	cover.request(_entry("none", D), cb)
	assert_bool(await _wait_until(func() -> bool: return got.size() >= 1)).is_true()
	assert_object(got[0][1]).is_null()
	cover.request(_entry("none", D), cb)
	assert_int(cover.loads).is_equal(1)
	cover.shutdown()


func test_lru_evicts_least_recently_used() -> void:
	var cover := AlbumCover.new()
	var done := {}
	var cb := func(id: String, _tex: Texture2D, _cached: bool) -> void: done[id] = true
	for i in AlbumCover.LRU_SIZE:
		cover.request(_entry("s%d" % i, D), cb)
	assert_bool(await _wait_until(func() -> bool: return done.size() >= AlbumCover.LRU_SIZE)).is_true()
	# Touch s0 so s1 becomes the least recently used.
	cover.request(_entry("s0", D), cb)
	cover.request(_entry("s_new", D), cb)
	assert_bool(await _wait_until(func() -> bool: return done.has("s_new"))).is_true()
	assert_int(cover.cached_ids().size()).is_equal(AlbumCover.LRU_SIZE)
	assert_bool(cover.is_cached("s0")).is_true()
	assert_bool(cover.is_cached("s1")).is_false()
	assert_bool(cover.is_cached("s_new")).is_true()
	cover.shutdown()


func test_generated_texture_cached_per_title() -> void:
	var cover := AlbumCover.new()
	var a := cover.generated_texture("HRT")
	assert_object(a).is_not_null()
	assert_bool(cover.generated_texture("HRT") == a).is_true()
	assert_bool(cover.generated_texture("Sea Shanty 2") == a).is_false()
	cover.shutdown()


# ---- helpers ----

func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _gradient_at(title: String, x: int, y: int) -> Color:
	var pair: Array = Palette.COVER_GRADIENTS[AlbumCover.gradient_index(title)]
	var t := float(x + y) / float(2 * (AlbumCover.GEN_SIZE - 1))
	return (pair[0] as Color).lerp(pair[1], t)
