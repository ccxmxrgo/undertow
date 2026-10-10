class_name BundledSongs
extends RefCounted
## Manifest of songs shipped inside the game (D-14, SONG-04).
## Each entry: {"id": String, "dir": "res://songs/<id>", "audio": "song.mp3" | "song.wav"}.
## The folder holds notes.chart (and optionally song.ini). The library reads these known
## paths directly instead of enumerating res:// (directory listings differ once exported).
## Credits: songs/CREDITS.txt. The first two songs are Pro Sensory / Alex McCulloch (CC0, via
## OpenGameArt.org). Later entries are non-CC0 tracks bundled for the friends-only build with the
## user's permission (D-13, 02.1-NOTES.md), charted by tools/autochart ("UNDERTOW autochart").

const SONGS: Array[Dictionary] = [
	{"id": "synth_wave_april", "dir": "res://songs/synth_wave_april", "audio": "song.mp3"},
	{"id": "space_synth_wave", "dir": "res://songs/space_synth_wave", "audio": "song.wav"},
	{"id": "sea_shanty_2", "dir": "res://songs/sea_shanty_2", "audio": "song.mp3"},
	{"id": "hrt", "dir": "res://songs/hrt", "audio": "song.mp3"},
	{"id": "invisible", "dir": "res://songs/invisible", "audio": "song.mp3"},
]
