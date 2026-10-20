extends GdUnitTestSuite
## The generated PackSpec pins a real Autocharter pack v1 (plan 06, D-04): unique part names,
## positive sizes, 64-hex SHA-256 values, valid roots, exactly one app part and one models part,
## the release URL and a download size inside the D-14 budget.

const ALLOWED_ROOTS := ["app", "NOTICES", "rt", "rt310", "models"]
const MB := 1000 * 1000


func test_available() -> void:
	assert_bool(PackSpec.available()).is_true()
	assert_int(PackSpec.VERSION).is_equal(1)
	assert_str(PackSpec.TAG).is_equal("autocharter-pack-v1")


func test_parts_are_well_formed() -> void:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{64}$")
	var names := {}
	var app_owners := 0
	var models_owners := 0
	for p in PackSpec.PARTS:
		var name := String(p["name"])
		assert_bool(name.begins_with("undertow-ac-v1-")).is_true()
		assert_bool(name.ends_with(".zip")).is_true()
		assert_bool(names.has(name)).is_false()
		names[name] = true
		assert_int(int(p["size"])).is_greater(0)
		assert_object(re.search(String(p["sha256"]))).is_not_null()
		var roots: Array = p["roots"]
		assert_bool(roots.is_empty()).is_false()
		for r in roots:
			assert_bool(ALLOWED_ROOTS.has(String(r))).is_true()
		if roots.has("app"):
			app_owners += 1
		if roots.has("models"):
			models_owners += 1
	assert_int(app_owners).is_equal(1)
	assert_int(models_owners).is_equal(1)


func test_urls_and_sizes() -> void:
	assert_bool(PackSpec.BASE_URL.begins_with(
		"https://github.com/ccxmxrgo/Undertow-autocharter/releases/download/autocharter-pack-v1/")).is_true()
	var total := 0
	for p in PackSpec.PARTS:
		total += int(p["size"])
		assert_str(PackSpec.url(p)).is_equal(PackSpec.BASE_URL + String(p["name"]))
	assert_int(PackSpec.download_bytes()).is_equal(total)
	assert_int(total).is_between(300 * MB, 600 * MB)
	assert_int(PackSpec.UNPACKED_BYTES).is_greater(total)
	var d := PackSpec.as_dict()
	assert_int((d["parts"] as Array).size()).is_equal(PackSpec.PARTS.size())
