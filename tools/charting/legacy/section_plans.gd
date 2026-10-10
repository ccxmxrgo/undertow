class_name SectionPlans
extends RefCounted
## Hand-written per-bar section plans for the bundled songs. This table is the creative
## input of the chart generator: it is NOT derived from the audio by code. The structure
## follows what was heard/measured once by a human (see 02-RESEARCH Section 8): both tracks
## are exactly 120 BPM 4/4, built from 8-bar phrases with a loud accent on every 4th bar.
##
## Row: {from, to (exclusive bar numbers, 0 based), label, intensity 0..4, family}
##   intensity: 0 = rest, 1 = pad/sparse, 2 = steady, 3 = driving, 4 = peak
##   family:    "stairs" | "trill" | "zig" | "pulse" | "pad"
## "solo": {from, to} bar range (to exclusive) of the guitar solo, written to Hard and Expert
## (and Easy/Medium too: the same bar span, thinned notes).

const SONGS := {
	"synth_wave_april": {
		"bars": 64,
		"seed": 20220403,
		"solo": {"from": 40, "to": 48},
		"sections": [
			{"from": 0, "to": 8, "label": "Intro", "intensity": 1, "family": "pad"},
			{"from": 8, "to": 16, "label": "Verse", "intensity": 2, "family": "stairs"},
			{"from": 16, "to": 24, "label": "Drive", "intensity": 3, "family": "zig"},
			{"from": 24, "to": 32, "label": "Break", "intensity": 1, "family": "trill"},
			{"from": 32, "to": 48, "label": "Drop", "intensity": 4, "family": "pulse"},
			{"from": 48, "to": 56, "label": "Drive", "intensity": 3, "family": "stairs"},
			{"from": 56, "to": 64, "label": "Outro", "intensity": 1, "family": "pad"},
		],
	},
	"space_synth_wave": {
		"bars": 96,
		"seed": 19850812,
		"solo": {"from": 48, "to": 56},
		"sections": [
			{"from": 0, "to": 8, "label": "Intro", "intensity": 1, "family": "pad"},
			{"from": 8, "to": 16, "label": "Verse", "intensity": 2, "family": "stairs"},
			{"from": 16, "to": 24, "label": "Drive", "intensity": 3, "family": "zig"},
			{"from": 24, "to": 32, "label": "Verse", "intensity": 2, "family": "trill"},
			{"from": 32, "to": 40, "label": "Break", "intensity": 1, "family": "pad"},
			{"from": 40, "to": 56, "label": "Drop", "intensity": 4, "family": "pulse"},
			{"from": 56, "to": 64, "label": "Drive", "intensity": 3, "family": "stairs"},
			{"from": 64, "to": 72, "label": "Break", "intensity": 1, "family": "trill"},
			{"from": 72, "to": 88, "label": "Drop", "intensity": 4, "family": "zig"},
			{"from": 88, "to": 96, "label": "Outro", "intensity": 1, "family": "pad"},
		],
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in SONGS.keys():
		out.append(k)
	return out
