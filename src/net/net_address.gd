class_name NetAddress
extends RefCounted
## Classifies this PC's local addresses for the Play Online invite list (D-15, NET-07,
## UI-SPEC 8.1). Pure: the caller passes IP.get_local_addresses(); no nodes, no Time, no Settings.
##
## Kinds: "tailscale" (100.64.0.0/10 CGNAT range), "lan" (10/8, 172.16/12, 192.168/16),
## "other" (any other routable address). Loopback, link-local (169.254/16, fe80::/10),
## unspecified and unparsable strings classify as "" and are never listed.

const TAILSCALE := "tailscale"
const LAN := "lan"
const OTHER := "other"
const MAX_LISTED := 4
const KIND_RANK := {TAILSCALE: 0, LAN: 1, OTHER: 2}


static func classify(ip: String) -> String:
	var s := ip.strip_edges()
	if s.begins_with("[") and s.ends_with("]"):
		s = s.substr(1, s.length() - 2)
	var pct := s.find("%")
	if pct >= 0:
		s = s.left(pct)
	if s == "":
		return ""
	if s.contains(":"):
		return _classify_v6(s)
	return _classify_v4(s)


static func _classify_v4(s: String) -> String:
	var parts := s.split(".")
	if parts.size() != 4:
		return ""
	var o: Array[int] = []
	for p in parts:
		if p == "" or p.length() > 3 or not p.is_valid_int():
			return ""
		var v := p.to_int()
		if v < 0 or v > 255:
			return ""
		o.append(v)
	if o[0] == 127 or o[0] == 0:
		return ""
	if o[0] == 169 and o[1] == 254:
		return ""
	if o[0] == 100 and o[1] >= 64 and o[1] <= 127:
		return TAILSCALE
	if o[0] == 10:
		return LAN
	if o[0] == 172 and o[1] >= 16 and o[1] <= 31:
		return LAN
	if o[0] == 192 and o[1] == 168:
		return LAN
	if o[0] >= 224:
		return ""
	return OTHER


static func _classify_v6(s: String) -> String:
	if not s.is_valid_ip_address():
		return ""
	var low := s.to_lower()
	if low == "::1" or low == "::":
		return ""
	# fe80::/10 link-local (fe80..febf).
	if low.length() >= 4 and low.substr(0, 3) in ["fe8", "fe9", "fea", "feb"]:
		return ""
	if low.begins_with("ff"):
		return ""
	return OTHER


## Up to MAX_LISTED entries [{ip, kind}], ordered tailscale, lan, other; stable within a kind;
## hidden and duplicate addresses dropped.
static func display_list(addrs: PackedStringArray) -> Array[Dictionary]:
	var buckets: Array = [[], [], []]
	var seen := {}
	for ip in addrs:
		var kind := classify(ip)
		if kind == "" or seen.has(ip):
			continue
		seen[ip] = true
		buckets[KIND_RANK[kind]].append({"ip": ip, "kind": kind})
	var out: Array[Dictionary] = []
	for b in buckets:
		for e in b:
			if out.size() >= MAX_LISTED:
				return out
			out.append(e)
	return out


## The address to give friends: first Tailscale, else first LAN, else "".
static func invite_address(addrs: PackedStringArray) -> String:
	var lan := ""
	for ip in addrs:
		var kind := classify(ip)
		if kind == TAILSCALE:
			return ip
		if kind == LAN and lan == "":
			lan = ip
	return lan


## "{ip}:{port}", with IPv6 addresses in brackets (UI-SPEC 8.3).
static func host_port(ip: String, port: int) -> String:
	if ip.contains(":") and not ip.begins_with("["):
		return "[%s]:%d" % [ip, port]
	return "%s:%d" % [ip, port]
