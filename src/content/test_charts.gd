class_name TestCharts
extends RefCounted
## Hand-authored / generated ChartData builders (D-27).


## Click track chart: lane = beat % 4, time = beat * 60 / bpm.
static func click_chart(bpm: float, beats: int, rate: int = 0) -> ChartData:
	var c := ChartData.new()
	c.title = "Click %d BPM" % int(bpm)
	var spb := 60.0 / bpm
	for beat in range(beats):
		c.add_note(beat % 4, beat * spb)
	c.tempo_map.append({"time": 0.0, "bpm": bpm})
	c.audio_stream = AudioSynth.make_click_track(bpm, beats * spb + 2.0, rate)
	c.finalize()
	return c


const HAND_BPM_A := 100.0
const HAND_BPM_B := 140.0
const HAND_BARS_A := 16
const HAND_BARS_B := 12


## Seconds at a beat index for a two-segment tempo (A for bars_a bars, then B), 4/4.
static func _beat_time(beat: int, bpm_a: float, bars_a: int, bpm_b: float) -> float:
	var change_beat := bars_a * 4
	if beat <= change_beat:
		return beat * 60.0 / bpm_a
	return change_beat * 60.0 / bpm_a + (beat - change_beat) * 60.0 / bpm_b


## About 59 s: taps, chords (every 4th bar), long (1.5 s) and short (0.5 s) sustains, and a
## tempo change 100 -> 140 BPM at bar 16 (recorded in tempo_map). Taps never share a lane
## with a sustain that is still held.
static func hand_chart(rate: int = 0) -> ChartData:
	var c := ChartData.new()
	c.title = "Hand chart"
	var change_time := _beat_time(HAND_BARS_A * 4, HAND_BPM_A, HAND_BARS_A, HAND_BPM_B)
	c.tempo_map.append({"time": 0.0, "bpm": HAND_BPM_A})
	c.tempo_map.append({"time": change_time, "bpm": HAND_BPM_B})
	for b in range(HAND_BARS_A + HAND_BARS_B):
		var chord := b > 0 and b % 4 == 0
		var long_lane := -1
		var short_lane := -1
		if not chord and b % 5 == 1:
			long_lane = (b / 5 + 1) % 4
		elif not chord and b % 5 == 3:
			short_lane = (b / 5 + 2) % 4
		var held := long_lane if long_lane >= 0 else short_lane
		for k in range(4):
			var t := _beat_time(b * 4 + k, HAND_BPM_A, HAND_BARS_A, HAND_BPM_B)
			if k == 0 and chord:
				var lanes := [0, 1, 2] if b % 8 == 0 else [1, 2, 3]
				for l in lanes:
					c.add_note(l, t)
				continue
			if k == 0 and long_lane >= 0:
				c.add_note(long_lane, t, 1.5)
				continue
			if k == 2 and short_lane >= 0:
				c.add_note(short_lane, t, 0.5)
				continue
			var lane := (b * 4 + k) % 4
			if lane == held:
				lane = (lane + 1) % 4
			c.add_note(lane, t)
	c.audio_stream = AudioSynth.make_song(c.tempo_map, change_time \
		+ HAND_BARS_B * 4 * 60.0 / HAND_BPM_B + 2.0, rate)
	c.finalize()
	return c


## 300 s of notes on every beat (lanes cycle) with a matching click track.
static func five_minute_click_chart(bpm: float = 120.0, rate: int = 0) -> ChartData:
	return click_chart(bpm, int(300.0 * bpm / 60.0), rate)
