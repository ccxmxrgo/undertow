class_name ZipExtractor
extends RefCounted
## Safe unzip of untrusted song archives. Only allow-listed extensions are written, every
## path is validated, and entry count / sizes are capped (sizes read from the central
## directory BEFORE any data is decompressed, since ZIPReader has no size query).

const ALLOWED_EXTS: Array[String] = ["chart", "ini", "ogg", "mp3", "wav", "opus", "mid", "png", "jpg", "jpeg"]
## Album art (D-11): images are kept, each capped at 8 MB; a larger image is skipped (the
## song still extracts) and never written to disk.
const IMAGE_EXTS: Array[String] = ["png", "jpg", "jpeg"]
const MAX_IMAGE_BYTES := 8 * 1024 * 1024
const MAX_ENTRIES := 4000
const MAX_TOTAL_BYTES := 2 * 1024 * 1024 * 1024
const MAX_ENTRY_BYTES := 512 * 1024 * 1024
const MAX_CENTRAL_BYTES := 16 * 1024 * 1024


## Normalised relative path ("/" separators) or "" to reject.
static func safe_rel(entry_name: String) -> String:
	var n := entry_name.replace("\\", "/")
	if n == "" or n.begins_with("/") or n.contains(":"):
		return ""
	var parts: Array[String] = []
	for seg in n.split("/"):
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			return ""
		for i in seg.length():
			if seg.unicode_at(i) < 32:
				return ""
		parts.append(seg)
	if parts.is_empty():
		return ""
	return "/".join(parts)


## limits (tests only): max_entries, max_total, max_entry, max_image.
static func extract(zip_path: String, dest_dir: String, limits: Dictionary = {}) -> Dictionary:
	var max_entries: int = limits.get("max_entries", MAX_ENTRIES)
	var max_total: int = limits.get("max_total", MAX_TOTAL_BYTES)
	var max_entry: int = limits.get("max_entry", MAX_ENTRY_BYTES)
	var max_image: int = limits.get("max_image", MAX_IMAGE_BYTES)
	var fail := {"ok": false, "error": SongEntry.ERR_ZIP}
	var sizes: Variant = _central_sizes(zip_path)
	if sizes == null:
		return fail
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return fail
	var files := zr.get_files()
	if files.size() > max_entries:
		zr.close()
		return fail
	# Pass 1: validate every claimed size before touching any data.
	var total := 0
	for name_s in files:
		if name_s.ends_with("/"):
			continue
		var sz: int = sizes.get(name_s, -1)
		if sz < 0 or sz > max_entry:
			zr.close()
			return fail
		total += sz
		if total > max_total:
			zr.close()
			return fail
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
	var written := 0
	for name_s in files:
		if name_s.ends_with("/"):
			continue
		var rel := safe_rel(name_s)
		var ext := rel.get_extension().to_lower()
		if rel == "" or not ALLOWED_EXTS.has(ext):
			continue
		if IMAGE_EXTS.has(ext) and int(sizes.get(name_s, -1)) > max_image:
			continue
		var target := dest_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		var data := zr.read_file(name_s)
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zr.close()
			return fail
		f.store_buffer(data)
		f.close()
		written += 1
	zr.close()
	return {"ok": true, "error": "", "written": written}


## name -> uncompressed size, from the end-of-central-directory record. null if unreadable
## or Zip64 (those archives are refused).
static func _central_sizes(zip_path: String) -> Variant:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return null
	var length := f.get_length()
	if length < 22:
		f.close()
		return null
	var tail_len := mini(length, 22 + 65535)
	f.seek(length - tail_len)
	var tail := f.get_buffer(tail_len)
	var eocd := -1
	for i in range(tail.size() - 22, -1, -1):
		if tail[i] == 0x50 and tail[i + 1] == 0x4B and tail[i + 2] == 0x05 and tail[i + 3] == 0x06:
			eocd = i
			break
	if eocd < 0:
		f.close()
		return null
	var count := tail.decode_u16(eocd + 10)
	var cd_size := tail.decode_u32(eocd + 12)
	var cd_off := tail.decode_u32(eocd + 16)
	if count == 0xFFFF or cd_size == 0xFFFFFFFF or cd_off == 0xFFFFFFFF \
			or cd_size > MAX_CENTRAL_BYTES or cd_off + cd_size > length:
		f.close()
		return null
	f.seek(cd_off)
	var cd := f.get_buffer(cd_size)
	f.close()
	var out := {}
	var pos := 0
	while pos + 46 <= cd.size():
		if cd.decode_u32(pos) != 0x02014B50:
			return null
		var usize := cd.decode_u32(pos + 24)
		var nlen := cd.decode_u16(pos + 28)
		var elen := cd.decode_u16(pos + 30)
		var clen := cd.decode_u16(pos + 32)
		if usize == 0xFFFFFFFF or pos + 46 + nlen > cd.size():
			return null
		var nm := cd.slice(pos + 46, pos + 46 + nlen).get_string_from_utf8()
		out[nm] = usize
		pos += 46 + nlen + elen + clen
	return out
