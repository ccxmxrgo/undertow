class_name ParsedChart
extends RefCounted
## Tick-based intermediate produced by ChartParser (.chart) or MidiChartReader (.mid); no seconds, no lanes yet.

var ok: bool = false
## "" when ok; else "Unreadable .chart (line N)", "Unreadable .mid", "No guitar part in .mid" or "Chart too large".
var error: String = ""
var error_line: int = 0
var resolution: int = 192
## [Song] section: lowercased key -> string value.
var song: Dictionary = {}
## Array of {tick:int, milli_bpm:int|float}, stably sorted by tick (float = exact MIDI uspqn conversion).
var tempo: Array = []
## Array of {tick:int, num:int, exp:int}.
var time_sigs: Array = []
## [Events] section: Array of {tick:int, text:String}.
var events: Array = []
## Track name ("ExpertSingle") -> Array of {tick:int, type:"N"|"S"|"E", a:int, b:int, text:String, seq:int}.
var tracks: Dictionary = {}
var warnings: int = 0
var first_warning_line: int = 0
