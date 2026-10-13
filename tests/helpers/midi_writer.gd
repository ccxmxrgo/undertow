class_name MidiWriter
extends RefCounted
## Builds Standard MIDI File bytes for tests (D-10: nothing committed).
## Events are {tick: int, bytes: PackedByteArray}; tracks sort them stably and delta-encode.


static func vlq(n: int) -> PackedByteArray:
	var groups: Array[int] = [n & 0x7F]
	var v := n >> 7
	while v > 0:
		groups.append((v & 0x7F) | 0x80)
		v >>= 7
	var out := PackedByteArray()
	for i in range(groups.size() - 1, -1, -1):
		out.append(groups[i])
	return out


static func _be32(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])


static func _be16(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 8) & 0xFF, n & 0xFF])


static func _meta(type: int, data: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray([0xFF, type])
	b.append_array(vlq(data.size()))
	b.append_array(data)
	return b


static func name(t: String) -> PackedByteArray:
	return _meta(0x03, t.to_ascii_buffer())


static func text(t: String) -> PackedByteArray:
	return _meta(0x01, t.to_ascii_buffer())


static func tempo(uspqn: int) -> PackedByteArray:
	return _meta(0x51, PackedByteArray([(uspqn >> 16) & 0xFF, (uspqn >> 8) & 0xFF, uspqn & 0xFF]))


static func ts(num: int, exp: int) -> PackedByteArray:
	return _meta(0x58, PackedByteArray([num, exp, 24, 8]))


static func on(pitch: int, vel: int = 100, ch: int = 0) -> PackedByteArray:
	return PackedByteArray([0x90 | ch, pitch, vel])


static func off(pitch: int, ch: int = 0) -> PackedByteArray:
	return PackedByteArray([0x80 | ch, pitch, 0x40])


static func sysex(payload: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray([0xF0])
	b.append_array(vlq(payload.size()))
	b.append_array(payload)
	return b


## Phase Shift open-note SysEx: F0 08 50 53 00 00 diff 01 (1|0) F7.
static func ps_open(diff: int, start: bool) -> PackedByteArray:
	return PackedByteArray([0xF0, 0x08, 0x50, 0x53, 0x00, 0x00, diff, 0x01, 1 if start else 0, 0xF7])


static func ev(tick: int, bytes: PackedByteArray) -> Dictionary:
	return {"tick": tick, "bytes": bytes}


static func track(events: Array, running_status: bool = false, end_of_track: bool = true) -> PackedByteArray:
	# stable sort: decorate with the original index
	var items: Array = []
	for i in events.size():
		items.append([int(events[i]["tick"]), i, events[i]["bytes"]])
	items.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var body := PackedByteArray()
	var last_tick := 0
	var last_status := -1
	for it in items:
		body.append_array(vlq(int(it[0]) - last_tick))
		last_tick = int(it[0])
		var bytes: PackedByteArray = it[2]
		var first := int(bytes[0])
		if first >= 0x80 and first <= 0xEF:
			if running_status and first == last_status:
				body.append_array(bytes.slice(1))
			else:
				body.append_array(bytes)
			last_status = first
		else:
			body.append_array(bytes)
	if end_of_track:
		body.append(0)
		body.append_array(PackedByteArray([0xFF, 0x2F, 0x00]))
	return body


static func chunk(type4: String, body: PackedByteArray) -> PackedByteArray:
	var b := type4.to_ascii_buffer()
	b.append_array(_be32(body.size()))
	b.append_array(body)
	return b


## tracks: Array of track bodies (from track()).
static func file(tracks: Array, division: int = 480, format: int = 1) -> PackedByteArray:
	var head := PackedByteArray()
	head.append_array(_be16(format))
	head.append_array(_be16(tracks.size()))
	head.append_array(_be16(division))
	var out := chunk("MThd", head)
	for t in tracks:
		out.append_array(chunk("MTrk", t))
	return out


# ---- twin song generators (Plans 02..04): one description -> .mid bytes + equivalent .chart text ----

const _DEMO_BASES := [60, 72, 84, 96]
const _DEMO_TRACKS := ["EasySingle", "MediumSingle", "HardSingle", "ExpertSingle"]


## Note pattern for difficulty d (0 easy .. 3 expert): Array of [tick, frets, length].
## frets 0..4 = G R Y B O, 7 = open. Lengths 60 are plain notes; >= 160 are sustains.
static func _demo_notes(d: int) -> Array:
	var pattern: Array = [
		[[0], 60], [[0, 2], 60], [[4], 240], [[0, 1, 2], 60],
		[[7], 60], [[3], 480], [[2, 4], 200], [[1], 60],
	]
	var out: Array = []
	for i in 48:
		var keep := true
		match d:
			0: keep = i % 2 == 0
			1: keep = i % 3 != 2
			2: keep = i % 4 != 3
		if not keep:
			continue
		var p: Array = pattern[i % 8]
		var frets: Array = p[0].duplicate()
		if frets.size() == 1 and frets[0] == 0:
			frets[0] = i % 5
		out.append([240 * i, frets, p[1]])
	return out


## {"mid": PackedByteArray, "chart": String}: the same song written both ways.
## Resolution 480; .mid note lengths below 160 become 0 in the .chart (Clone Hero .mid cutoff).
static func demo_song() -> Dictionary:
	var tempos: Array = [[0, 500000, 120000], [1920, 600000, 100000], [3840, 400000, 150000], [5760, 468750, 128000], [7680, 375000, 160000]]
	var sigs: Array = [[0, 4, 2], [3840, 3, 2], [5760, 6, 3]]
	var sections: Array = [[0, "[section Intro]", "section Intro"], [3840, "[prc_verse_1]", "section verse 1"], [7680, "[section Chorus]", "section Chorus"]]
	var solos: Array = [[1440, 2400], [5760, 7200]]

	var t0: Array = []
	for t in tempos:
		t0.append(ev(t[0], tempo(t[1])))
	for s in sigs:
		t0.append(ev(s[0], ts(s[1], s[2])))
	var guitar: Array = [ev(0, name("PART GUITAR")), ev(0, text("[ENHANCED_OPENS]"))]
	var events: Array = [ev(0, name("EVENTS"))]
	for s in sections:
		events.append(ev(s[0], text(s[1])))
	guitar.append(ev(960, on(116)))
	guitar.append(ev(1920, off(116)))
	for s in solos:
		guitar.append(ev(s[0], on(103)))
		guitar.append(ev(s[1], off(103)))

	var chart := "[Song]\n{\n  Resolution = 480\n}\n[SyncTrack]\n{\n"
	for t in tempos:
		chart += "  %d = B %d\n" % [t[0], t[2]]
	for s in sigs:
		chart += "  %d = TS %d %d\n" % [s[0], s[1], s[2]]
	chart += "}\n[Events]\n{\n"
	for s in sections:
		chart += "  %d = E \"%s\"\n" % [s[0], s[2]]
	chart += "}\n"
	for d in 4:
		var body := ""
		for n in _demo_notes(d):
			for f in n[1]:
				var pitch: int = _DEMO_BASES[d] + (f if f < 5 else -1)
				guitar.append(ev(n[0], on(pitch)))
				guitar.append(ev(n[0] + n[2], off(pitch)))
				body += "  %d = N %d %d\n" % [n[0], f, n[2] if n[2] >= 160 else 0]
		for s in solos:
			body += "  %d = E solo\n" % s[0]
			body += "  %d = E soloend\n" % (s[1] - 1)
		chart += "[%s]\n{\n%s}\n" % [_DEMO_TRACKS[d], body]
	var mid := file([track(t0), track(guitar), track(events)], 480)
	return {"mid": mid, "chart": chart}


## ~10 minute .mid with non-round tempos for the analytic precision test.
## {"mid", "tempos": [[tick, uspqn]], "note_ticks": [int], "resolution": 480}
static func long_odd_tempo_song() -> Dictionary:
	var tempos: Array = [[0, 500000], [96000, 461538], [192000, 428571], [288000, 333333], [384000, 500000], [480000, 461538]]
	var t0: Array = []
	for t in tempos:
		t0.append(ev(t[0], tempo(t[1])))
	t0.append(ev(0, ts(4, 2)))
	var guitar: Array = [ev(0, name("PART GUITAR"))]
	var ticks: Array = []
	var i := 0
	while i * 240 <= 672000:
		var pitch := 96 + (i % 5)
		guitar.append(ev(i * 240, on(pitch)))
		guitar.append(ev(i * 240 + 40, off(pitch)))
		ticks.append(i * 240)
		i += 1
	return {"mid": file([track(t0), track(guitar)], 480), "tempos": tempos, "note_ticks": ticks, "resolution": 480}
