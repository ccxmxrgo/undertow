class_name SongFixture
extends RefCounted
## Builds song folders, zips and hostile files at test time under user://test_* dirs.
## Audio is generated (AudioSynth), never committed.

const CHART := """[Song]
{
  Name = "Fixture Song"
  Artist = "Fixture Band"
  Resolution = 192
}
[SyncTrack]
{
  0 = TS 4
  0 = B 120000
}
[Events]
{
}
[ExpertSingle]
{
  0 = N 0 0
  192 = N 1 0
  384 = N 2 96
  576 = N 3 0
  768 = N 0 0
  960 = N 1 0
  1152 = N 2 192
  1536 = N 3 0
}
[EasySingle]
{
  0 = N 0 0
  384 = N 1 0
  768 = N 2 0
}
"""
const CHART_NO_GUITAR := """[Song]
{
  Name = "Drums Only"
  Resolution = 192
}
[SyncTrack]
{
  0 = B 120000
}
[ExpertDrums]
{
  0 = N 0 0
}
"""
const INI := "[song]\nname = Ini Title\nartist = Ini Artist\ncharter = Ini Charter\ndelay = 0\n"


static func rm_tree(dir: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("user://") else dir
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	for d in DirAccess.get_directories_at(abs_dir):
		rm_tree(abs_dir.path_join(d))
	DirAccess.remove_absolute(abs_dir)


static func mkdir(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


static func write_text(path: String, text: String) -> void:
	mkdir(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func write_bytes(path: String, bytes: PackedByteArray) -> void:
	mkdir(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


static func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


## Small mono WAV (8 kHz) through AudioSynth.save_to_wav.
static func make_wav(path: String, seconds: float = 2.0) -> void:
	mkdir(path.get_base_dir())
	var w := AudioSynth.make_click_track(120.0, seconds, 8000)
	var err := w.save_to_wav(path)
	assert(err == OK, "save_to_wav failed")


static func opus_bytes() -> PackedByteArray:
	var b := "OggS".to_ascii_buffer()
	b.append_array(PackedByteArray([0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 19]))
	b.append_array("OpusHead".to_ascii_buffer())
	b.append_array(PackedByteArray([1, 2, 0, 0, 0x80, 0xBB, 0, 0, 0, 0, 0]))
	return b


static func garbage_bytes() -> PackedByteArray:
	return PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])


## ID3v2.3 tag (latin1 text) followed by one MPEG sync frame header; not decodable audio.
static func mp3_bytes(tit: String = "", art: String = "") -> PackedByteArray:
	var frames := PackedByteArray()
	for pair in [["TIT2", tit], ["TPE1", art]]:
		if String(pair[1]) == "":
			continue
		var txt := PackedByteArray([0])
		txt.append_array(String(pair[1]).to_ascii_buffer())
		frames.append_array(String(pair[0]).to_ascii_buffer())
		var sz := PackedByteArray([0, 0, 0, 0])
		sz.encode_u32(0, txt.size())
		frames.append(sz[3])
		frames.append(sz[2])
		frames.append(sz[1])
		frames.append(sz[0])
		frames.append_array(PackedByteArray([0, 0]))
		frames.append_array(txt)
	var head := "ID3".to_ascii_buffer()
	head.append_array(PackedByteArray([3, 0, 0]))
	var n := frames.size()
	head.append_array(PackedByteArray([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F]))
	head.append_array(frames)
	head.append_array(PackedByteArray([0xFF, 0xFB, 0x90, 0x00, 0, 0, 0, 0]))
	return head


## Plain playable folder: notes.chart + song.ini + song.wav.
static func make_song(dir: String, with_ini: bool = true, chart_text: String = CHART) -> void:
	mkdir(dir)
	write_text(dir.path_join("notes.chart"), chart_text)
	if with_ini:
		write_text(dir.path_join("song.ini"), INI)
	make_wav(dir.path_join("song.wav"))


static func make_mid_song(dir: String, mid_bytes: PackedByteArray, with_ini: bool = true) -> void:
	mkdir(dir)
	write_bytes(dir.path_join("notes.mid"), mid_bytes)
	if with_ini:
		write_text(dir.path_join("song.ini"), INI)
	make_wav(dir.path_join("song.wav"))


## Community style: song-named chart, mixed-case keys, split stems, album art.
static func make_community(dir: String) -> void:
	mkdir(dir)
	write_text(dir.path_join("Some Song.chart"), CHART)
	write_text(dir.path_join("song.ini"),
		"[Song]\nName = Community Song\nArtist = Some Band\nFrets = Somebody\nDelay = 0\nPreview_Start_Time = 1500\n")
	for stem in ["guitar", "rhythm", "drums", "vocals", "crowd"]:
		make_wav(dir.path_join(stem + ".wav"), 2.0)
	write_bytes(dir.path_join("album.png"), PackedByteArray([0x89, 0x50, 0x4E, 0x47]))


## entries: name -> PackedByteArray | String. Returns OK or the packer error.
static func make_zip(zip_path: String, entries: Dictionary) -> int:
	mkdir(zip_path.get_base_dir())
	var zp := ZIPPacker.new()
	var err := zp.open(ProjectSettings.globalize_path(zip_path))
	if err != OK:
		return err
	for name_s in entries:
		zp.start_file(name_s)
		var v: Variant = entries[name_s]
		zp.write_file(v if typeof(v) == TYPE_PACKED_BYTE_ARRAY else String(v).to_utf8_buffer())
		zp.close_file()
	zp.close()
	return OK


## Zip the files of a folder (flat), optionally under a top-level folder name.
static func zip_folder(dir: String, zip_path: String, top: String = "") -> int:
	var entries := {}
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(dir)):
		entries[top.path_join(f) if top != "" else f] = read_bytes(dir.path_join(f))
	return make_zip(zip_path, entries)
