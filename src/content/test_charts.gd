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
