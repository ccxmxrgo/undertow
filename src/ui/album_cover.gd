class_name AlbumCover
extends RefCounted
## Album art for the Song Select detail panel (UI-SPEC 4.10, D-11).
##
## Art: album.png, then album.jpg, directly in the folder of the song's chart (the extracted
## cache folder for zips). Nothing else is looked up: no ini-provided path, no other names,
## no parent folders (T-02.2-34). The file is untrusted (T-02.2-32/33): it is size-checked
## before reading, its header dimensions are checked before decoding, it is decoded only by
## Godot's built-in PNG/JPEG decoders, rejected above MAX_DIM, centre-cropped square and
## downscaled to <= MAX_SIZE. Any failure means "no art" (the generated cover shows).
##
## Loading runs on the WorkerThreadPool (selected song only; never during a scan). The
## ImageTexture is created on the main thread. Results (including "no art") are kept in an
## LRU of LRU_SIZE song ids. Call reap() every frame and shutdown() before freeing.
##
## Generated cover: a deterministic 512x512 image from the title's sha256 (gradient pair,
## arc corner, arc phase). The initials are drawn on top at display time (fonts cannot be
## rasterised into an Image off the main thread).

const ART_NAMES: Array[String] = ["album.png", "album.jpg"]
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_DIM := 4096
const MAX_SIZE := 512
const GEN_SIZE := 512
const LRU_SIZE := 32
const ARC_RADII: Array[int] = [80, 140, 200, 260]
const ARC_ALPHA := 0.14
## Half the 2 px arc stroke.
const ARC_HALF_W := 1.0
## Angular gap in each arc (degrees), placed by the arc phase.
const ARC_GAP_DEG := 18.0
## Initials baseline inside a drawn cover of side S: y + S * 162 / 256 (UI-SPEC: y + 162 at 256).
const INITIALS_BASELINE := 162.0 / 256.0

## Number of worker loads started (test seam: same id twice loads once).
var loads: int = 0

## id -> Texture2D or null (no art). Order of _lru = least recently used first.
var _cache: Dictionary = {}
var _lru: Array[String] = []
## id -> Array[Callable] waiting for a load in flight.
var _pending: Dictionary = {}
var _tasks: Array[int] = []
var _generated: Dictionary = {}
var _gen_order: Array[String] = []


# ---- art lookup and safe loading (worker-safe: no scene tree, no autoloads) ----

## The only folder searched for art: the folder holding the chart ("" when unknown).
static func art_dir(entry: SongEntry) -> String:
	if entry == null or entry.chart_path == "":
		return ""
	return entry.chart_path.get_base_dir()


## album.png (else album.jpg) in `dir` as a square Image of side <= MAX_SIZE, or null.
static func load_art_image(dir: String) -> Image:
	if dir == "":
		return null
	for nm in ART_NAMES:
		var p := dir.path_join(nm)
		if dir.begins_with("res://") and ResourceLoader.exists(p):
			# Imported project art (Pitfall 8): the raw file is not in an export pack.
			var tex := ResourceLoader.load(p) as Texture2D
			if tex == null:
				return null
			return _finish(tex.get_image())
		if FileAccess.file_exists(p):
			return _load_file(p)
	return null


static func _load_file(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var length := f.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		f.close()
		return null
	var bytes := f.get_buffer(length)
	f.close()
	var kind := _sniff(bytes)
	if kind == "":
		return null
	var dims := _header_dims(bytes, kind)
	if dims.x <= 0 or dims.y <= 0 or dims.x > MAX_DIM or dims.y > MAX_DIM:
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes) if kind == "png" else img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return _finish(img)


## Decoded image -> centre-cropped square, <= MAX_SIZE, no mipmaps; null if out of bounds.
static func _finish(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM:
		return null
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	if img.has_mipmaps():
		img.clear_mipmaps()
	var side := mini(w, h)
	var sq := img.get_region(Rect2i((w - side) / 2, (h - side) / 2, side, side))
	if side > MAX_SIZE:
		sq.resize(MAX_SIZE, MAX_SIZE, Image.INTERPOLATE_LANCZOS)
	return sq


## "png", "jpg" or "" from the file's magic bytes (the extension is not trusted).
static func _sniff(b: PackedByteArray) -> String:
	if b.size() >= 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47 \
			and b[4] == 0x0D and b[5] == 0x0A and b[6] == 0x1A and b[7] == 0x0A:
		return "png"
	if b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return "jpg"
	return ""


## Width/height from the header without decoding (decompression-bomb guard); (0, 0) if unreadable.
static func _header_dims(b: PackedByteArray, kind: String) -> Vector2i:
	if kind == "png":
		# Signature (8) + IHDR length (4) + "IHDR" (4) + width (4, BE) + height (4, BE).
		if b.size() < 24 or b[12] != 0x49 or b[13] != 0x48 or b[14] != 0x44 or b[15] != 0x52:
			return Vector2i.ZERO
		return Vector2i(_be32(b, 16), _be32(b, 20))
	var i := 2
	while i + 9 < b.size():
		if b[i] != 0xFF:
			return Vector2i.ZERO
		var m: int = b[i + 1]
		if m == 0xFF:
			i += 1
			continue
		if m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7):
			i += 2
			continue
		if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
			return Vector2i((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6])
		var seg := (b[i + 2] << 8) | b[i + 3]
		if seg < 2:
			return Vector2i.ZERO
		i += 2 + seg
	return Vector2i.ZERO


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


# ---- generated cover (deterministic) ----

static func _hash(title: String) -> PackedByteArray:
	return title.strip_edges().to_lower().sha256_buffer()


## Index into Palette.COVER_GRADIENTS: sha256 byte 0 mod 8.
static func gradient_index(title: String) -> int:
	return int(_hash(title)[0]) % Palette.COVER_GRADIENTS.size()


## Arc corner 0..3 = top-left, top-right, bottom-left, bottom-right (sha256 byte 1).
static func arc_corner(title: String) -> int:
	return int(_hash(title)[1]) % 4


## Arc phase 0..65535 (sha256 bytes 2..3): where the gap of each arc sits.
static func arc_phase(title: String) -> int:
	var h := _hash(title)
	return (int(h[2]) << 8) | int(h[3])


static func corner_point(corner: int) -> Vector2i:
	var m := GEN_SIZE - 1
	return Vector2i(m if corner % 2 == 1 else 0, m if corner >= 2 else 0)


## First letter of the first two words, uppercase (1-2 chars); "?" when empty.
static func initials(title: String) -> String:
	var out := ""
	for word in title.strip_edges().split(" ", false):
		out += word.substr(0, 1).to_upper()
		if out.length() >= 2:
			break
	return out if out != "" else "?"


## GEN_SIZE square: diagonal gradient (top-left -> bottom-right) plus 4 concentric 2 px
## SONAR 14% arcs centred on the chosen corner, each with one gap placed by the phase.
static func generated(title: String) -> Image:
	var n := GEN_SIZE
	var pair: Array = Palette.COVER_GRADIENTS[gradient_index(title)]
	var c0: Color = pair[0]
	var c1: Color = pair[1]
	# The gradient depends only on x + y: one diagonal strip, each row is a slice of it.
	var diag := 2 * n - 1
	var strip := PackedByteArray()
	strip.resize(diag * 3)
	for k in diag:
		var col := c0.lerp(c1, float(k) / float(diag - 1))
		strip[k * 3] = col.r8
		strip[k * 3 + 1] = col.g8
		strip[k * 3 + 2] = col.b8
	var data := PackedByteArray()
	for y in n:
		data.append_array(strip.slice(y * 3, (y + n) * 3))
	var corner := arc_corner(title)
	var o := corner_point(corner)
	var phase := arc_phase(title)
	var sx := 1.0 if o.x == 0 else -1.0
	var sy := 1.0 if o.y == 0 else -1.0
	var sonar8: Array[int] = [Palette.SONAR.r8, Palette.SONAR.g8, Palette.SONAR.b8]
	for ri in ARC_RADII.size():
		var r := float(ARC_RADII[ri])
		# Gap start inside the quarter arc (0..90 degrees from the x axis, measured inward).
		var gap0 := float((phase >> (ri * 4)) % 72)
		var r_in := r - ARC_HALF_W
		var r_out := r + ARC_HALF_W
		for dy in range(0, int(r_out) + 1):
			var y := o.y + int(sy) * dy
			if y < 0 or y >= n:
				continue
			var x_hi := sqrt(maxf(0.0, r_out * r_out - float(dy * dy)))
			var x_lo := sqrt(maxf(0.0, r_in * r_in - float(dy * dy))) if float(dy) < r_in else 0.0
			for dx in range(int(ceil(x_lo)), int(floor(x_hi)) + 1):
				var x := o.x + int(sx) * dx
				if x < 0 or x >= n:
					continue
				var ang := rad_to_deg(atan2(float(dy), float(dx)))
				if ang >= gap0 and ang < gap0 + ARC_GAP_DEG:
					continue
				var at := (y * n + x) * 3
				for ch in 3:
					var v: int = data[at + ch]
					data[at + ch] = clampi(int(round(lerpf(float(v), float(sonar8[ch]), ARC_ALPHA))), 0, 255)
	return Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data)


# ---- instance: cache and worker loads (main thread API) ----

## Generated cover texture for a title, built once and kept (bounded).
func generated_texture(title: String) -> Texture2D:
	var key := title.strip_edges().to_lower()
	if _generated.has(key):
		return _generated[key]
	var tex := ImageTexture.create_from_image(generated(title))
	_generated[key] = tex
	_gen_order.append(key)
	while _gen_order.size() > LRU_SIZE:
		_generated.erase(_gen_order.pop_front())
	return tex


func is_cached(id: String) -> bool:
	return _cache.has(id)


func cached_ids() -> Array[String]:
	return _lru.duplicate()


## Art for `entry`: callback(id, texture_or_null, cached) is called once the result is known
## (immediately when cached, else on the main thread after the worker load).
func request(entry: SongEntry, callback: Callable) -> void:
	if entry == null:
		return
	var id := entry.id
	if _cache.has(id):
		_touch(id)
		callback.call(id, _cache[id], true)
		return
	if _pending.has(id):
		(_pending[id] as Array).append(callback)
		return
	_pending[id] = [callback]
	loads += 1
	var dir := art_dir(entry)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var img := AlbumCover.load_art_image(dir)
		_deliver.call_deferred(id, img)))


func _deliver(id: String, img: Image) -> void:
	var tex: Texture2D = null
	if img != null:
		tex = ImageTexture.create_from_image(img)
	_cache[id] = tex
	_touch(id)
	while _lru.size() > LRU_SIZE:
		_cache.erase(_lru.pop_front())
	var cbs: Array = _pending.get(id, [])
	_pending.erase(id)
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(id, tex, false)


func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)


## Reaps finished worker tasks (every frame), or all of them (`all`, e.g. on leaving).
func reap(all: bool = false) -> void:
	var keep: Array[int] = []
	for t in _tasks:
		if all or WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			keep.append(t)
	_tasks = keep


## Waits for every load and drops pending callbacks (call before the owner is freed).
func shutdown() -> void:
	reap(true)
	_pending.clear()
