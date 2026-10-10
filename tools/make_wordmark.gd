extends SceneTree
## Renders the UNDERTOW menu wordmark (02.2 UI-SPEC section 5 "Logo") from the committed
## OFL Oxanium font at weight 700 (Palette.display_font()) and saves two first-party PNGs:
##   assets/ui/undertow_wordmark.png       white glyphs on transparent, 1920 x 304 (2x)
##   assets/ui/undertow_wordmark_glow.png  the same, box-blurred (3 passes, radius 12 px)
## The menu draws them in a 960 x 152 rect (tinted TEXT_HI; glow additive SONAR 25%).
##
## Run WINDOWED (the headless renderer draws nothing):
##   godot --path . -s res://tools/make_wordmark.gd
## then `godot --headless --path . --import` and commit both PNGs and their .import files.

const OUT := "res://assets/ui/undertow_wordmark.png"
const OUT_GLOW := "res://assets/ui/undertow_wordmark_glow.png"
const TEXT := "UNDERTOW"
const W := 1920
const H := 304
const PAD_X := 24  # glyph ink starts 24 px in (12 px at 1x), leaving room for the glow
const INK_H := 224  # cap height at 2x (112 px on screen); leaves 40 px above/below for the glow
const RENDER_SIZE := 300  # font size of the first render (cropped and fitted afterwards)
const CANVAS := Vector2i(2600, 600)
const BLUR_R := 12
const BLUR_PASSES := 3
const GLOW_GAIN := 1.6


class Painter:
	extends Control
	var font: Font
	var font_size := RENDER_SIZE

	func _draw() -> void:
		draw_string(font, Vector2(100.0, 420.0), TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.WHITE)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("make_wordmark: run windowed (the headless renderer draws nothing).")
		quit(1)
		return
	preload("res://tools/test_screen.gd").move_window()  # windowed tools open on the test (secondary) screen
	var vp := SubViewport.new()
	vp.size = CANVAS
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var p := Painter.new()
	p.font = Palette.display_font()
	p.size = Vector2(CANVAS)
	vp.add_child(p)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("make_wordmark: nothing was rendered.")
		quit(1)
		return
	var ink := img.get_region(used)
	var s := float(INK_H) / float(ink.get_height())
	s = minf(s, float(W - 2 * PAD_X) / float(ink.get_width()))
	var iw := int(round(ink.get_width() * s))
	var ih := int(round(ink.get_height() * s))
	ink.resize(iw, ih, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.blit_rect(ink, Rect2i(Vector2i.ZERO, ink.get_size()), Vector2i(PAD_X, (H - ih) / 2))
	var alpha := _alpha(out)
	var mark := _from_alpha(alpha, 1.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	mark.save_png(ProjectSettings.globalize_path(OUT))
	for k in BLUR_PASSES:
		alpha = _blur(alpha, W, H, BLUR_R, true)
		alpha = _blur(alpha, W, H, BLUR_R, false)
	_from_alpha(alpha, GLOW_GAIN).save_png(ProjectSettings.globalize_path(OUT_GLOW))
	print("make_wordmark: ink %dx%d at (%d, %d); saved %s and %s" % [iw, ih, PAD_X, (H - ih) / 2, OUT, OUT_GLOW])
	quit(0)


## Alpha channel as floats. The viewport blends white onto transparent black, so RGB holds
## premultiplied grey; only alpha is kept and RGB is rebuilt as pure white.
func _alpha(img: Image) -> PackedFloat32Array:
	var data := img.get_data()
	var a := PackedFloat32Array()
	a.resize(W * H)
	for i in W * H:
		a[i] = data[i * 4 + 3] / 255.0
	return a


func _from_alpha(a: PackedFloat32Array, gain: float) -> Image:
	var data := PackedByteArray()
	data.resize(W * H * 4)
	for i in W * H:
		data[i * 4] = 255
		data[i * 4 + 1] = 255
		data[i * 4 + 2] = 255
		data[i * 4 + 3] = int(clampf(a[i] * gain, 0.0, 1.0) * 255.0 + 0.5)
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data)


## One separable box-blur pass (running sum, edges clamped to zero).
func _blur(src: PackedFloat32Array, w: int, h: int, r: int, horizontal: bool) -> PackedFloat32Array:
	var dst := PackedFloat32Array()
	dst.resize(w * h)
	var inv := 1.0 / float(2 * r + 1)
	var lines := h if horizontal else w
	var length := w if horizontal else h
	var stride := 1 if horizontal else w
	for line in lines:
		var base := line * w if horizontal else line
		var acc := 0.0
		for k in range(0, mini(r, length - 1) + 1):
			acc += src[base + k * stride]
		for i in length:
			dst[base + i * stride] = acc * inv
			var add := i + r + 1
			if add < length:
				acc += src[base + add * stride]
			var rem := i - r
			if rem >= 0:
				acc -= src[base + rem * stride]
	return dst
