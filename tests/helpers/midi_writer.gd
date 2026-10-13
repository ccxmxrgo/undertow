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
