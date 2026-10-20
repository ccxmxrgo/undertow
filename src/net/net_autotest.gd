class_name NetAutotest
extends Node
## Command-line online autotest driver (04-17, D-24 layer 4). NetSession adds it as a child only
## when the user args contain `--net-autotest=` (T-04-51): friends never pass it, so nothing here
## runs in a normal game. tools/net_smoke.ps1 starts 4 headless processes with it on 127.0.0.1.
##
## User args (after `--`):
##   --net-autotest=host|client   role (required)
##   --net-address=<ip>           client: host address (default 127.0.0.1)
##   --net-port=<n>               1024..65535 (default 47474)
##   --net-players=<2..4>         host: waits for this many seats, host included (default 4)
##   --net-seconds=<n>            max_song_s of the match, 1..1200 (default 30)
##   --net-diff=<easy|medium|hard|expert>   (default easy)
##   --net-report=<path.json>     absolute .json path, or under the project's build/net_smoke/
##                                (res://build/net_smoke/... or build/net_smoke/...); anything else,
##                                any ".." segment or a non-.json name is rejected (T-04-49).
##                                Default: build/net_smoke/<name>.json
##   --net-name=<NAME>            player name (defaults HOST; clients C<profile-1>, else CLIENT)
##   --net-seed=<n>               match seed (default 1717)
##   --net-timeout=<s>            overall watchdog, 10..3600 (default 120): a report with
##                                error "timeout" is written and the process exits with code 3
##   --mute                       mutes the Master bus
## Use with `--net-profile=<n>` (Settings: user://settings_net<n>.cfg, never the real
## settings.cfg) and `--no-boot-scan`. The library is scanned by this driver into a private songs
## root and cache next to the report (bundled songs only), never the player's Songs folder.
##
## Flow:
## - Host: host(port) at once, scan, wait for net-players seats, pick the first bundled entry with
##   net-diff (host_set_song), wait for start_gate().ok, start_match({seed, max_song_s,
##   autoplay: true}).
## - Client: scan, join(address, port) (retried on an early connect error), Ready once its song
##   status is ok.
## - Both: match_loading -> build the chart by fingerprint -> Gameplay.pending_chart -> gameplay
##   scene (as LobbyScreen does). Client: RESULTS + 1 s (EVENTS drained) -> report -> leave ->
##   quit after 1.5 s. Host: RESULTS + 2 s (and until the clients left, at most 6 s more) ->
##   report -> quit after 1.5 s.
##
## Exit codes: 0 ok, 2 bad args / setup error, 3 timeout, 4 match error (abort, host lost).
##
## Report JSON: role, seat, name, version, start_unix_ms, host_log_sha (host), received_sha
## (clients), events, late_inputs, landed_late_max_ms, skew_ms, rtt_p50_ms, rtt_p90_ms,
## horizon_ms, strike_kicks, ping_dropped, rejected_packets, results_rows [{seat, name, left}],
## left_seats (host), error ("" when ok).

const ARG_ROLE := "--net-autotest="
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const SMOKE_DIR := "build/net_smoke/"
const DEFAULT_PORT := 47474
const DEFAULT_SEED := 1717
const MAX_SPREAD_MS := 20.0
const CLIENT_DRAIN_S := 1.0
const HOST_RESULTS_WAIT_S := 2.0
const HOST_PEERS_WAIT_S := 6.0
const QUIT_DELAY_S := 1.5
const JOIN_RETRIES := 5
const READY_RESEND_S := 1.0

enum Step { SETUP, LOBBY, MATCH, RESULTS, REPORTED }

## Parsed args (parse_args).
var cfg: Dictionary = {}
## Injectable for tests; null resolves the autoloads.
var session: Node
var library: Node

var _step: Step = Step.SETUP
var _t0 := 0.0
var _scan_started := false
var _scan_done := false
var _join_tries := 0
var _retry_at := -1.0
var _song_set := false
var _match_started := false
var _last_ready_sent := -INF
var _results_at := -1.0
var _error := ""
var _quit_at := -1.0
var _exit_code := 0
var _playing_logged := false
var _next_sample := 0.0
var _clock_samples := 0
var _clock_skew_max := 0.0
var _clock_skew_last := 0.0


# --- Pure helpers (unit tested) ---------------------------------------------------------------

## True when the user args ask for the autotest driver.
static func has_arg(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with(ARG_ROLE):
			return true
	return false


## Parses and validates the driver args. Returns {ok, error, role, address, port, players,
## seconds, diff, report (absolute path), name, seed, timeout, mute}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"ok": false, "error": "", "role": "", "address": "127.0.0.1",
		"port": DEFAULT_PORT, "players": 4, "seconds": 30.0, "diff": "easy", "report": "",
		"name": "", "seed": DEFAULT_SEED, "timeout": 120.0, "mute": false}
	var profile := -1
	var report_raw := ""
	for a in args:
		if a == "--mute":
			out.mute = true
			continue
		var eq := a.find("=")
		if not a.begins_with("--net-") or eq < 0:
			continue
		var key := a.substr(0, eq + 1)
		var v := a.substr(eq + 1)
		match key:
			"--net-autotest=":
				if v != "host" and v != "client":
					return _bad(out, "role")
				out.role = v
			"--net-address=":
				var addr := Settings.clean_address(v)
				if addr == "":
					return _bad(out, "address")
				out.address = addr
			"--net-port=":
				if not v.is_valid_int() or int(v) < 1024 or int(v) > 65535:
					return _bad(out, "port")
				out.port = int(v)
			"--net-players=":
				if not v.is_valid_int() or int(v) < 2 or int(v) > NetProtocol.MAX_SEATS:
					return _bad(out, "players")
				out.players = int(v)
			"--net-seconds=":
				if not v.is_valid_float() or float(v) < 1.0 or float(v) > NetProtocol.MAX_SONG_S:
					return _bad(out, "seconds")
				out.seconds = float(v)
			"--net-diff=":
				if not NetProtocol.DIFFICULTIES.has(v):
					return _bad(out, "diff")
				out.diff = v
			"--net-report=":
				report_raw = v
				if report_path(v) == "":
					return _bad(out, "report")
			"--net-name=":
				var n := Settings.clean_player_name(v)
				if n == "":
					return _bad(out, "name")
				out.name = n
			"--net-seed=":
				if not v.is_valid_int():
					return _bad(out, "seed")
				out.seed = int(v)
			"--net-timeout=":
				if not v.is_valid_float() or float(v) < 10.0 or float(v) > 3600.0:
					return _bad(out, "timeout")
				out.timeout = float(v)
			"--net-profile=":
				if v.is_valid_int():
					profile = int(v)
			_:
				pass
	if out.role == "":
		return _bad(out, "role")
	if out.name == "":
		if out.role == "host":
			out.name = "HOST"
		elif profile >= 2:
			out.name = "C%d" % (profile - 1)
		else:
			out.name = "CLIENT"
	if report_raw == "":
		report_raw = SMOKE_DIR + str(out.name).to_lower().replace(" ", "_") + ".json"
	out.report = report_path(report_raw)
	if out.report == "":
		return _bad(out, "report")
	out.ok = true
	return out


static func _bad(out: Dictionary, what: String) -> Dictionary:
	out.ok = false
	out.error = what
	return out


## The absolute report path for `p`, or "" when it is not allowed (T-04-49): it must end in
## .json, contain no ".." segment or control character, and be either an absolute OS path or
## inside the project's build/net_smoke/ (res://build/net_smoke/... or build/net_smoke/...).
static func report_path(p: String) -> String:
	if p.is_empty() or p.length() > 400 or not p.to_lower().ends_with(".json"):
		return ""
	for i in p.length():
		if p.unicode_at(i) < 32:
			return ""
	var s := p.replace("\\", "/")
	for seg in s.split("/"):
		if seg == ".." or seg == ".":
			return ""
	if s.begins_with("res://"):
		var rest := s.substr(6)
		if not rest.begins_with(SMOKE_DIR) or rest.length() <= SMOKE_DIR.length():
			return ""
		return ProjectSettings.globalize_path("res://" + rest)
	if s.contains("://"):
		return ""  # user:// and any other scheme
	var c0 := s.unicode_at(0)
	var drive := s.length() >= 3 and s[1] == ":" and s[2] == "/" \
		and ((c0 >= 65 and c0 <= 90) or (c0 >= 97 and c0 <= 122))
	if drive or (s.begins_with("/") and not s.begins_with("//")):
		return s
	if s.begins_with(SMOKE_DIR) and s.length() > SMOKE_DIR.length():
		return ProjectSettings.globalize_path("res://" + s)
	return ""


## One SHA-256 over the canonical form of every event, in order. Each event is canonicalised as
## bytes_to_var(var_to_bytes(e)), which is exactly what a client holds after the wire round trip
## (same types, same key order); var_to_bytes of that copy is hashed. A decoded event
## canonicalises to itself, so host broadcast_log and client received_log hash alike.
static func log_digest(events: Array) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for e in events:
		var c: Variant = bytes_to_var(var_to_bytes(e))
		var b := var_to_bytes(c)
		if not b.is_empty():
			h.update(b)
	return h.finish().hex_encode()


## The smoke verdict over parsed reports (the same rules tools/net_smoke.ps1 applies).
## opts: players (int, default 4), dropped_seat (int, -1 = none), dropped_name (String, "" =
## none), max_spread_ms (float, default 20). The dropped client's report (by seat or name) is
## missing or partial and is ignored. Returns {ok, lines: Array[String]}.
static func compare_reports(reports: Array, opts: Dictionary = {}) -> Dictionary:
	var lines: Array[String] = []
	var players := int(opts.get("players", 4))
	var dropped_seat := int(opts.get("dropped_seat", -1))
	var dropped_name := str(opts.get("dropped_name", ""))
	var dropping := dropped_seat > 0 or dropped_name != ""
	var max_spread := float(opts.get("max_spread_ms", MAX_SPREAD_MS))
	var host: Dictionary = {}
	var clients: Array[Dictionary] = []
	for r: Variant in reports:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		if str(d.get("role", "")) != "host" and _is_dropped(d, dropped_seat, dropped_name):
			lines.append("[note] dropped client report ignored (%s)" % str(d.get("name", "?")))
			continue
		if str(d.get("role", "")) == "host":
			host = d
		else:
			clients.append(d)
	var fails := 0
	if host.is_empty():
		lines.append("[FAIL] host report missing")
		return {"ok": false, "lines": lines}
	var want_clients := players - 1 - (1 if dropping else 0)
	if clients.size() != want_clients:
		lines.append("[FAIL] client reports %d (want %d)" % [clients.size(), want_clients])
		fails += 1
	var all: Array[Dictionary] = [host]
	all.append_array(clients)
	var version := str(host.get("version", ""))
	for d in all:
		var who := str(d.get("name", "?"))
		var err := str(d.get("error", ""))
		if err != "":
			lines.append("[FAIL] %s error: %s" % [who, err])
			fails += 1
		if str(d.get("version", "")) != version:
			lines.append("[FAIL] %s version %s != host %s" % [who, str(d.get("version", "")),
				version])
			fails += 1
	var hsha := str(host.get("host_log_sha", ""))
	for c in clients:
		var who := str(c.get("name", "?"))
		var rsha := str(c.get("received_sha", ""))
		if hsha != "" and rsha == hsha:
			lines.append("[PASS] digest host == client %s (%s)" % [who, hsha.left(12)])
		else:
			lines.append("[FAIL] digest host %s != client %s %s" % [hsha.left(12), who,
				rsha.left(12)])
			fails += 1
	var lo := INF
	var hi := -INF
	for d in all:
		var s := float(d.get("start_unix_ms", 0.0))
		if s <= 0.0:
			lines.append("[FAIL] %s has no start_unix_ms" % str(d.get("name", "?")))
			fails += 1
			continue
		lo = minf(lo, s)
		hi = maxf(hi, s)
	if hi >= lo:
		var spread := hi - lo
		if spread <= max_spread:
			lines.append("[PASS] start spread %.2f ms <= %d" % [spread, int(max_spread)])
		else:
			lines.append("[FAIL] start spread %.2f ms > %d" % [spread, int(max_spread)])
			fails += 1
	var late := int(host.get("late_inputs", -1))
	if late == 0:
		lines.append("[PASS] late inputs 0")
	else:
		lines.append("[FAIL] late inputs %d" % late)
		fails += 1
	var kicks := int(host.get("strike_kicks", 0))
	if kicks != 0:
		lines.append("[FAIL] strike disconnects %d" % kicks)
		fails += 1
	for d in all:
		var rows: Variant = d.get("results_rows", [])
		var n := (rows as Array).size() if rows is Array else -1
		if n == players:
			lines.append("[PASS] results %d rows (%s)" % [n, str(d.get("name", "?"))])
		else:
			lines.append("[FAIL] results %d rows (%s), want %d" % [n, str(d.get("name", "?")),
				players])
			fails += 1
	if dropping:
		var row := {}
		var hrows: Variant = host.get("results_rows", [])
		if hrows is Array:
			for r: Variant in hrows:
				if r is Dictionary and _is_dropped(r, dropped_seat, dropped_name):
					row = r
		var seat := int(row.get("seat", dropped_seat))
		if not row.is_empty() and bool(row.get("left", false)):
			lines.append("[PASS] seat %d LEFT" % seat)
		else:
			lines.append("[FAIL] seat %d not LEFT in the host results" % seat)
			fails += 1
	return {"ok": fails == 0, "lines": lines}


static func _is_dropped(d: Dictionary, seat: int, p_name: String) -> bool:
	if p_name != "" and str(d.get("name", "")) == p_name:
		return true
	return seat > 0 and d.has("seat") and int(d.get("seat", -1)) == seat


# --- Driver -------------------------------------------------------------------------------------

func _ready() -> void:
	if cfg.is_empty():
		cfg = parse_args(OS.get_cmdline_user_args())
	if not bool(cfg.get("ok", false)):
		push_error("[autotest] bad args: %s" % str(cfg.get("error", "")))
		print("[autotest] bad args: %s" % str(cfg.get("error", "")))
		get_tree().quit.call_deferred(2)
		set_process(false)
		return
	_t0 = _now()
	if session == null:
		session = get_parent()
	if library == null:
		library = get_node_or_null("/root/SongLibrary")
	if bool(cfg.mute):
		var bus := AudioServer.get_bus_index("Master")
		if bus >= 0:
			AudioServer.set_bus_mute(bus, true)
	var st := get_node_or_null("/root/Settings")
	if st != null:
		# In memory only: the per-process profile file is the only one that could ever be saved.
		st.set("player_name", str(cfg.name))
		st.set("player_name_set", true)
		st.set("calibration_done", true)  # no first-launch wizard
		st.set("menu_music", false)
	session.connect("match_loading", _on_match_loading)
	session.connect("start_scheduled", _on_start_scheduled)
	session.connect("match_aborted_to_lobby", _on_aborted)
	session.connect("host_left", _on_host_left)
	session.connect("connect_error", _on_connect_error)
	session.connect("left_lobby", _on_left_lobby)
	print("[autotest] %s %s port %d players %d seconds %.0f diff %s audio %s report %s" % [
		cfg.role, cfg.name, cfg.port, cfg.players, cfg.seconds, cfg.diff,
		AudioServer.get_driver_name(), cfg.report])
	if cfg.role == "host":
		var err := int(session.call("host", int(cfg.port)))
		if err != OK:
			_fail("host_failed:%d" % err, 2)
			return
		print("[autotest] hosting")
	_start_scan()


func _process(_delta: float) -> void:
	var now := _now()
	if _quit_at >= 0.0:
		if now >= _quit_at:
			_quit_at = -1.0
			get_tree().quit(_exit_code)
		return
	if _step == Step.REPORTED:
		return
	if now - _t0 > float(cfg.timeout):
		_fail("timeout", 3)
		return
	if not _scan_done:
		_poll_scan()
		return
	match _step:
		Step.SETUP, Step.LOBBY:
			if cfg.role == "host":
				_host_lobby()
			else:
				_client_lobby(now)
		Step.MATCH:
			_sample_clock(now)
			if int(session.get("state")) == NetSession.State.RESULTS:
				_step = Step.RESULTS
				_results_at = now
				print("[autotest] results")
		Step.RESULTS:
			var waited := now - _results_at
			if cfg.role == "client":
				if waited >= CLIENT_DRAIN_S:
					_finish()
			elif waited >= HOST_RESULTS_WAIT_S:
				var peers := int((session.call("debug_stats") as Dictionary).get("peers", 0))
				if peers == 0 or waited >= HOST_RESULTS_WAIT_S + HOST_PEERS_WAIT_S:
					_finish()
		_:
			pass


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


# --- Library -----------------------------------------------------------------------------------

## Bundled songs only, into a private songs root and cache next to the report (headless never
## boot-scans, and --no-boot-scan keeps SongLibrary off the real Songs folder and cache).
func _start_scan() -> void:
	if library == null:
		_fail("no_library", 2)
		return
	var base := str(cfg.report).get_base_dir().path_join("lib_" + str(cfg.name).to_lower()
		.replace(" ", "_"))
	DirAccess.make_dir_recursive_absolute(base.path_join("songs"))
	library.set("auto_scan", false)
	library.set("settings_ref", null)
	library.set("extra_folders", [] as Array[String])
	library.set("songs_root_override", base.path_join("songs"))
	library.set("cache_path", base.path_join("cache.json"))
	library.call("rescan")
	_scan_started = true


func _poll_scan() -> void:
	if not _scan_started or bool(library.get("scanning")):
		return
	_scan_done = true
	print("[autotest] library %d entries" % (library.get("entries") as Array).size())
	_step = Step.LOBBY
	if cfg.role == "client":
		_join()


func _pick_song() -> Dictionary:
	var entries: Array = library.get("entries")
	var ordered: Array = []
	for e: Variant in entries:
		if e is Object and str((e as Object).get("source")) == "bundled":
			ordered.append(e)
	for e: Variant in entries:
		if e is Object and str((e as Object).get("source")) != "bundled":
			ordered.append(e)
	for e: Object in ordered:
		var d: Variant = e.call("difficulty", str(cfg.diff))
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		var c: Variant = library.call("build_chart", e, str(cfg.diff))
		if not (c is ChartData):
			continue
		var fp := str((d as Dictionary).get("fingerprint", ""))
		if fp == "":
			fp = (c as ChartData).id
		return {"fp": fp, "sig": VersusSig.of(c as ChartData), "diff": str(cfg.diff),
			"title": str(e.get("title")), "artist": str(e.get("artist"))}
	return {}


func _build_chart(spec: Dictionary) -> ChartData:
	var fp := str(spec.get("fp", ""))
	var diff := str(spec.get("diff", ""))
	for e: Variant in library.get("entries"):
		if not (e is Object) or not (e as Object).has_method("difficulty"):
			continue
		var d: Variant = (e as Object).call("difficulty", diff)
		if d is Dictionary and str((d as Dictionary).get("fingerprint", "")) == fp:
			var c: Variant = library.call("build_chart", e, diff)
			return c if c is ChartData else null
	return null


# --- Lobby -------------------------------------------------------------------------------------

func _host_lobby() -> void:
	if _match_started:
		return
	var rows: Array = session.call("lobby_rows")
	if rows.size() < int(cfg.players):
		return
	if not _song_set:
		var key := _pick_song()
		if key.is_empty():
			_fail("no_song", 2)
			return
		if not bool(session.call("host_set_song", key)):
			_fail("song_rejected", 2)
			return
		_song_set = true
		print("[autotest] song %s %s" % [key.title, key.diff])
		return
	var gate: Dictionary = session.call("start_gate")
	if not bool(gate.get("ok", false)):
		return
	var r := str(session.call("start_match", {"seed": int(cfg.seed),
		"max_song_s": float(cfg.seconds), "autoplay": true}))
	if r != "":
		_fail("start_match:" + r, 2)
		return
	_match_started = true


func _join() -> void:
	_join_tries += 1
	_retry_at = -1.0
	var err := int(session.call("join", str(cfg.address), int(cfg.port)))
	if err != OK:
		_retry_at = _now() + 1.0
	else:
		print("[autotest] joining (try %d)" % _join_tries)


func _client_lobby(now: float) -> void:
	if _retry_at >= 0.0:
		if now >= _retry_at:
			_join()
		return
	if not bool(session.call("is_in_lobby")):
		return
	if str(session.call("my_song_status")) != "ok":
		return
	var seat := int(session.call("local_seat"))
	for r: Variant in session.call("lobby_rows"):
		if r is Dictionary and int(r.get("seat", -1)) == seat and bool(r.get("ready", false)):
			return
	if now - _last_ready_sent >= READY_RESEND_S:
		_last_ready_sent = now
		session.call("set_ready", true)


func _on_connect_error(code: String, _info: Dictionary) -> void:
	if cfg.role != "client" or _step != Step.LOBBY:
		return
	if _join_tries < JOIN_RETRIES and (code == "timeout" or code == "lost"):
		print("[autotest] connect error %s, retrying" % code)
		_retry_at = _now() + 1.0
		return
	_fail("connect_error:" + code, 2)


# --- Match -------------------------------------------------------------------------------------

func _on_match_loading() -> void:
	var spec: Dictionary = session.call("pending_match")
	var chart := _build_chart(spec)
	if chart == null:
		session.call("report_load_failed")
		_fail("chart_build", 4)
		return
	_step = Step.MATCH
	MatchSetup.pending = null
	Gameplay.pending_chart = chart
	Gameplay.pending_autoplay = false
	Gameplay.pending_practice = false
	print("[autotest] loading seat %d D %d ms" % [int(spec.get("local_seat", -1)),
		int(round(float(spec.get("d_s", 0.0)) * 1000.0))])
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY_SCENE)


func _on_start_scheduled() -> void:
	if _playing_logged:
		return
	_playing_logged = true
	# Gameplay calls lead_in_for_start in its own handler; print on the next idle step.
	_log_playing.call_deferred()


func _log_playing() -> void:
	var d: Dictionary = session.call("debug_stats")
	print("[autotest] playing start_unix_ms %.3f" % float(d.get("start_unix_ms", 0.0)))


## Once a second while playing: this process's song_time against the wall clock since the
## scheduled start (start_unix_ms), in ms. Positive = the song clock runs ahead of the schedule.
func _sample_clock(now: float) -> void:
	if now < _next_sample:
		return
	_next_sample = now + 1.0
	var gp := get_tree().current_scene
	if gp == null or not gp.has_method("is_began") or not bool(gp.call("is_began")):
		return
	var cond: Variant = gp.get("conductor")
	var st := float((session.call("debug_stats") as Dictionary).get("start_unix_ms", 0.0))
	if not (cond is Conductor) or st <= 0.0:
		return
	var t := (cond as Conductor).song_time()
	var wall := (Time.get_unix_time_from_system() * 1000.0 - st) / 1000.0
	var skew := (t - wall) * 1000.0
	_clock_samples += 1
	_clock_skew_max = maxf(_clock_skew_max, absf(skew))
	_clock_skew_last = skew
	print("[autotest] clock t %.3f wall %.3f skew %.1f ms audio %s" % [t, wall, skew,
		str((cond as Conductor).audio_valid())])


func _on_aborted(code: String, who: String) -> void:
	_fail("aborted:%s:%s" % [code, who], 4)


func _on_host_left(kind: String) -> void:
	_fail("host_left:" + kind, 4)


func _on_left_lobby(code: String) -> void:
	if _step == Step.RESULTS:
		return
	_fail("left_lobby:" + code, 4)


# --- Report --------------------------------------------------------------------------------------

func build_report() -> Dictionary:
	var d: Dictionary = session.call("debug_stats")
	var ch: Variant = session.call("match_channel")
	var res: Dictionary = session.call("last_results")
	var rep := {"role": cfg.get("role", ""), "seat": int(d.get("seat", -1)),
		"name": cfg.get("name", ""), "version": NetProtocol.game_version(),
		"start_unix_ms": float(d.get("start_unix_ms", 0.0)), "host_log_sha": "",
		"received_sha": "", "events": 0, "late_inputs": int(d.get("late_inputs", 0)),
		"landed_late_max_ms": float(d.get("landed_late_max_ms", 0.0)),
		"skew_ms": float(d.get("skew_ms", 0.0)), "rtt_p50_ms": int(d.get("rtt_p50_ms", 0)),
		"rtt_p90_ms": int(d.get("rtt_p90_ms", 0)), "horizon_ms": int(d.get("horizon_ms", 0)),
		"strike_kicks": int(d.get("strike_kicks", 0)),
		"ping_dropped": int(d.get("ping_dropped", 0)),
		"rejected_packets": int(d.get("rejected_packets", 0)),
		"clock_skew_max_ms": _clock_skew_max, "clock_skew_last_ms": _clock_skew_last,
		"audio_driver": AudioServer.get_driver_name(),
		"results_rows": [], "left_seats": [], "error": _error}
	if ch is NetHostChannel:
		var evs: Array = (ch as NetHostChannel).broadcast_log
		rep.host_log_sha = log_digest(evs)
		rep.events = evs.size()
		var left: Array = []
		for e: Dictionary in evs:
			if str(e.get("type", "")) == GameEvent.PLAYER_LEFT:
				left.append(int(e.get("seat", -1)))
		rep.left_seats = left
	elif ch is NetClientChannel:
		var evs: Array = (ch as NetClientChannel).received_log
		rep.received_sha = log_digest(evs)
		rep.events = evs.size()
	var rows: Array = []
	for r: Variant in res.get("rows", []):
		if r is Dictionary:
			rows.append({"seat": int(r.get("seat", -1)), "name": str(r.get("name", "")),
				"left": bool(r.get("left", false))})
	rep.results_rows = rows
	return rep


func _write_report() -> void:
	var rep := build_report()
	var path := str(cfg.get("report", ""))
	if path == "":
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[autotest] cannot write %s" % path)
		return
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	var sha := str(rep.host_log_sha) if str(rep.role) == "host" else str(rep.received_sha)
	print("[autotest] report %s events %d sha %s error '%s'" % [path, int(rep.events),
		sha.left(16), rep.error])


func _finish() -> void:
	_write_report()
	_step = Step.REPORTED
	if cfg.role == "client":
		session.call("leave")
	_exit_code = 0
	_quit_at = _now() + QUIT_DELAY_S


func _fail(err: String, code: int) -> void:
	if _step == Step.REPORTED:
		return
	_error = err
	print("[autotest] FAIL %s" % err)
	_write_report()
	_step = Step.REPORTED
	_exit_code = code
	_quit_at = _now() + 0.2
