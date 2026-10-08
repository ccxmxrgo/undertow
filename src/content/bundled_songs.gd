class_name BundledSongs
extends RefCounted
## Manifest of songs shipped inside the game (filled in by plan 05).
## Each entry: {"id": String, "dir": "res://songs/<id>", "audio": "song.mp3" | "song.wav"}.
## The folder holds notes.chart (and optionally song.ini). The library reads these known
## paths directly instead of enumerating res:// (directory listings differ once exported).

const SONGS: Array[Dictionary] = []
