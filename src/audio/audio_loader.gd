class_name AudioLoader
extends RefCounted
## Runtime audio loading for imported songs. Worker-thread safe (no scene tree access).
## Only the header is trusted to pick a decoder: Opus and unknown data never reach the
## engine loaders. User paths use load_from_file only, never ResourceLoader (res:// only).

const AUDIO_EXTS: Array[String] = ["ogg", "mp3", "wav", "opus"]
const MAX_AUDIO_BYTES := 1024 * 1024 * 1024
const _RESERVED := ["song", "guitar", "rhythm", "bass", "keys", "drums", "drums_1", "drums_2",
		"drums_3", "drums_4", "vocals", "vocals_1", "vocals_2", "crowd"]
const _OPTIONAL := ["crowd"]


static func is_audio_name(file_name: String) -> bool:
	return AUDIO_EXTS.has(file_name.get_extension().to_lower())


## "ogg" | "opus" | "wav" | "mp3" | "missing" | "unknown"
static func detect(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return "missing"
		return ext if ["ogg", "opus", "wav", "mp3"].has(ext) else "unknown"
	if not FileAccess.file_exists(path):
		return "missing"
	if ext == "opus":
		return "opus"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "missing"
	var head := f.get_buffer(128)
	f.close()
	if head.size() >= 12 and _tag(head, 0, "RIFF") and _tag(head, 8, "WAVE"):
		return "wav"
	if head.size() >= 4 and _tag(head, 0, "OggS"):
		if _find(head, "OpusHead") >= 0:
			return "opus"
		if _find(head, "\u0001vorbis") >= 0:
			return "ogg"
		return "unknown"
	if head.size() >= 3 and _tag(head, 0, "ID3"):
		return "mp3"
	if head.size() >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0:
		return "mp3"
	if ext == "mp3":
		return "mp3"  # forgiving: leading padding is common, a decode failure reports it
	return "unknown"


static func _tag(b: PackedByteArray, at: int, s: String) -> bool:
	var t := s.to_ascii_buffer()
	if at + t.size() > b.size():
		return false
	for i in t.size():
		if b[at + i] != t[i]:
			return false
	return true


static func _find(b: PackedByteArray, s: String) -> int:
	var t := s.to_utf8_buffer()
	for i in range(0, b.size() - t.size() + 1):
		var hit := true
		for j in t.size():
			if b[i + j] != t[j]:
				hit = false
				break
		if hit:
			return i
	return -1


## null on any failure; never calls an engine loader on Opus, unknown or missing files.
static func load_file(path: String) -> AudioStream:
	var kind := detect(path)
	if kind == "missing" or kind == "opus" or kind == "unknown":
		return null
	if path.begins_with("res://"):
		var r: Resource = ResourceLoader.load(path)
		return r as AudioStream
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var size := f.get_length()
	f.close()
	if size <= 0 or size > MAX_AUDIO_BYTES:
		return null
	var s: AudioStream = null
	match kind:
		"ogg":
			s = AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			s = AudioStreamMP3.load_from_file(path)
		"wav":
			s = AudioStreamWAV.load_from_file(path)
	if s != null and s.get_length() <= 0.0:
		return null
	return s


## Splits file names into core stems, optional stems (crowd) and a preview file.
## With no reserved names and exactly one audio file, that file is the core stem.
static func classify_stems(file_names: Array) -> Dictionary:
	var core: Array[String] = []
	var optional: Array[String] = []
	var preview := ""
	var audio: Array[String] = []
	for n in file_names:
		var name_s := String(n)
		if not is_audio_name(name_s):
			continue
		audio.append(name_s)
		var base := name_s.get_basename().to_lower()
		if base == "preview":
			preview = name_s
		elif _OPTIONAL.has(base):
			optional.append(name_s)
		elif _RESERVED.has(base):
			core.append(name_s)
	if core.is_empty() and optional.is_empty():
		var others: Array[String] = []
		for a in audio:
			if a != preview:
				others.append(a)
		if others.size() == 1:
			core.append(others[0])
	return {"core": core, "optional": optional, "preview": preview}


## files: full paths. One file -> that stream; several -> AudioStreamSynchronized (the song's
## length is the longest stem). A failing optional stem (crowd) is skipped.
static func load_song_audio(files: Array) -> Dictionary:
	var out := {"stream": null, "error": "", "length": 0.0}
	if files.is_empty():
		out["error"] = SongEntry.ERR_AUDIO_MISSING
		return out
	var names: Array = []
	var by_name := {}
	for p in files:
		var fname := String(p).get_file()
		names.append(fname)
		by_name[fname] = String(p)
	var streams: Array[AudioStream] = []
	if files.size() == 1:
		var err := _check(String(files[0]))
		if err != "":
			out["error"] = err
			return out
		var s := load_file(String(files[0]))
		if s == null:
			out["error"] = SongEntry.ERR_AUDIO_BAD
			return out
		streams.append(s)
	else:
		var cls := classify_stems(names)
		var core: Array = cls["core"]
		if core.is_empty():
			core = [names[0]]
		for n in core:
			var err2 := _check(by_name[n])
			if err2 != "":
				out["error"] = err2
				return out
			var cs := load_file(by_name[n])
			if cs == null:
				out["error"] = SongEntry.ERR_AUDIO_BAD
				return out
			streams.append(cs)
		for n in cls["optional"]:
			if _check(by_name[n]) != "":
				continue
			var os := load_file(by_name[n])
			if os != null:
				streams.append(os)
	if streams.size() == 1:
		out["stream"] = streams[0]
		out["length"] = streams[0].get_length()
		return out
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = streams.size()
	var longest := 0.0
	for i in streams.size():
		sync.set_sync_stream(i, streams[i])
		longest = maxf(longest, streams[i].get_length())
	out["stream"] = sync
	out["length"] = longest
	return out


## "" when the header looks decodable, else the row error.
static func _check(path: String) -> String:
	match detect(path):
		"missing":
			return SongEntry.ERR_AUDIO_MISSING
		"opus":
			return SongEntry.ERR_OPUS
		"unknown":
			return SongEntry.ERR_UNSUPPORTED_AUDIO
	return ""
