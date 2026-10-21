extends SceneTree
## Renders the UNDERTOW app icon (05-03, D-09): an original sonar scope in Palette colours.
## Saves two first-party files:
##   assets/ui/undertow_icon.png   256 x 256 RGBA (project icon, config/icon)
##   assets/ui/undertow_icon.ico   PNG-compressed entries 16/32/48/64/128/256 (Windows exe icon,
##                                 export_presets application/icon)
## Draws with the Image API only (no renderer), so it runs HEADLESS:
##   godot --headless --path . -s res://tools/make_icon.gd
## then `godot --headless --path . --import` and commit the PNG, its .import and the ICO.
## Rendered at 4x (1024 px) and downsampled with Lanczos for clean edges.

const OUT_PNG := "res://assets/ui/undertow_icon.png"
const OUT_ICO := "res://assets/ui/undertow_icon.ico"
const SIZE := 256
const SS := 4
const ICO_SIZES := [16, 32, 48, 64, 128, 256]

# Geometry as fractions of the icon size.
const DISC_R := 0.47
const BEZEL_W := 0.035
const INNER_RING_W := 0.03
const RANGE_RINGS := [0.15, 0.28, 0.41]
const RANGE_RING_W := 0.008
const CROSS_W := 0.006
const SWEEP_DEG := 70.0
const SWEEP_EDGE_W := 0.02
const BLIP_R := 0.035
const BLIP_HALO_R := 0.06
const BLIP_ANGLE := 40.0
const BLIP_DIST := 0.30
const RIVAL_R := 0.022
const RIVAL_ANGLE := 200.0
const RIVAL_DIST := 0.36


func _initialize() -> void:
	var big := SIZE * SS
	var img := Image.create(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := big * 0.5
	var blip := _clock_point(BLIP_ANGLE, BLIP_DIST)
	var rival := _clock_point(RIVAL_ANGLE, RIVAL_DIST)
	for y in big:
		for x in big:
			# Coordinates as fractions of the icon size, centred.
			var px := (float(x) + 0.5 - c) / big
			var py := (float(y) + 0.5 - c) / big
			var r := sqrt(px * px + py * py)
			if r > DISC_R:
				continue
			var col := Palette.ABYSS_900
			# Clock angle: 0 at 12 o'clock, growing clockwise (image y points down).
			var ang := fposmod(rad_to_deg(atan2(px, -py)), 360.0)
			# Crosshair.
			if absf(px) < CROSS_W * 0.5 or absf(py) < CROSS_W * 0.5:
				col = _over(col, Palette.SONAR, 0.20)
			# Range rings.
			for rr in RANGE_RINGS:
				if absf(r - float(rr)) < RANGE_RING_W * 0.5:
					col = _over(col, Palette.SONAR, 0.35)
			# Sweep wedge: leading edge at 70 deg, fading to 0 at 12 o'clock.
			var inner_lim := DISC_R - BEZEL_W - INNER_RING_W
			if ang <= SWEEP_DEG and r < inner_lim:
				col = _over(col, Palette.SONAR, 0.70 * (ang / SWEEP_DEG))
			# Leading edge line (perpendicular distance to the 70 deg ray).
			var lead := deg_to_rad(SWEEP_DEG)
			var dir := Vector2(sin(lead), -cos(lead))
			var along := px * dir.x + py * dir.y
			var perp := absf(px * dir.y - py * dir.x)
			if along > 0.0 and along < inner_lim and perp < SWEEP_EDGE_W * 0.5:
				col = _over(col, Palette.SONAR_PALE, 1.0)
			# Contact blip with a soft halo.
			var db := Vector2(px, py).distance_to(blip)
			if db < BLIP_HALO_R:
				var t := clampf((db - BLIP_R) / (BLIP_HALO_R - BLIP_R), 0.0, 1.0)
				col = _over(col, Palette.SONAR_PALE, 0.55 * (1.0 - t) * (1.0 - t))
			if db < BLIP_R:
				col = _over(col, Palette.SONAR_PALE, 1.0)
			# Rival blip.
			if Vector2(px, py).distance_to(rival) < RIVAL_R:
				col = _over(col, Palette.WARNING_RED, 1.0)
			# Inner ring then bezel.
			if r > DISC_R - BEZEL_W - INNER_RING_W:
				col = Palette.ABYSS_700
			if r > DISC_R - BEZEL_W:
				col = _over(Palette.ABYSS_900, Palette.SONAR, 0.85)
			col.a = 1.0
			img.set_pixel(x, y, col)
	var master := img
	img = master.duplicate()
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(OUT_PNG)
	if err != OK:
		push_error("save_png failed: %d" % err)
		quit(1)
		return
	var png := img.save_png_to_buffer()
	# One PNG entry per size Godot's resource editor asks for (16..256); every size is
	# downsampled from the 1024 px master so the small icons stay crisp.
	var entries: Array[PackedByteArray] = []
	for s in ICO_SIZES:
		var sized: Image = master.duplicate()
		sized.resize(s, s, Image.INTERPOLATE_LANCZOS)
		entries.append(sized.save_png_to_buffer())
	var f := FileAccess.open(OUT_ICO, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s" % OUT_ICO)
		quit(1)
		return
	f.big_endian = false
	# ICONDIR
	f.store_16(0)  # reserved
	f.store_16(1)  # type: icon
	f.store_16(ICO_SIZES.size())  # count
	# ICONDIRENTRY x count (16 bytes each), then the PNG blobs in order.
	var offset := 6 + 16 * ICO_SIZES.size()
	for i in ICO_SIZES.size():
		var s: int = ICO_SIZES[i]
		f.store_8(0 if s >= 256 else s)  # width (0 = 256)
		f.store_8(0 if s >= 256 else s)  # height (0 = 256)
		f.store_8(0)  # colour count
		f.store_8(0)  # reserved
		f.store_16(1)  # planes
		f.store_16(32)  # bpp
		f.store_32(entries[i].size())  # bytes in resource
		f.store_32(offset)  # offset of image data
		offset += entries[i].size()
	for e in entries:
		f.store_buffer(e)
	f.close()
	print("ICON OK %d %d" % [png.size(), offset])
	quit(0)


## Point at a clock angle (degrees clockwise from 12 o'clock) and distance from centre.
func _clock_point(deg: float, dist: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a), -cos(a)) * dist


func _over(base: Color, top: Color, alpha: float) -> Color:
	return base.lerp(Color(top.r, top.g, top.b, 1.0), clampf(alpha, 0.0, 1.0))
