class_name StatusChips
extends Node
## Translates EventChannel events for the local seat into Hud right-console chips
## (03-UI-SPEC 5.3, S-6, S-10, D-06, D-07): PLACE ("1ST OF 4"), BOUNTY ON YOU, DECOY ARMED n,
## OVERCLOCK n (n = bars left), HULL +p (1.6 s after Ballast Patch) and IMMUNE (until the
## immunity window ends). Training shows no PLACE or BOUNTY. PLACE freezes when you implode.
## It does not draw (Hud pops, slides and fades the chips), so it is not an effect node.
## update(song_time) refreshes the bar countdowns and the IMMUNE / BALLAST timers from the song
## clock (never frame time). Malformed events are read with defaults (T-03-23).

const BALLAST_SHOW_SEC := 1.6
const EPS_BEATS := 1e-4

var _channel: EventChannel
var _seat: int = 0
var _hud: Hud
var _cfg: VersusConfig
var _chart: ChartData
var _players: int = 1
var _training: bool = false
var _wreck: bool = false
var _decoy_until: float = -1.0
var _overclock_until: float = -1.0
var _ballast_until: float = -1.0
var _immune_until: float = -1.0
var _now: float = 0.0
## Last bar count shown per countdown chip (WR-10): the chip text is rebuilt only on change.
var _last_bars := {}


func bind(channel: EventChannel, seat: int, hud: Hud, cfg: VersusConfig, chart: ChartData,
		player_count: int, training: bool) -> void:
	if _channel != null and _channel.received.is_connected(on_event):
		_channel.received.disconnect(on_event)
	_channel = channel
	_seat = seat
	_hud = hud
	_cfg = cfg if cfg != null else VersusConfig.new()
	_chart = chart
	_players = clampi(player_count, 1, 4)
	_training = training
	if channel != null:
		channel.received.connect(on_event)


static func ordinal(place: int) -> String:
	match place:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
	return "%dTH" % place


func on_event(e: Dictionary) -> void:
	_last_bars.clear()  # any event may reset a chip: re-check the countdowns once
	if _hud == null or not is_instance_valid(_hud):
		return
	var t := float(e.get("t", _now))
	match str(e.get("type", "")):
		GameEvent.STATUS:
			if int(e.get("seat", -1)) != _seat or _training or _wreck:
				return
			var place := int(e.get("place", 0))
			if place >= 1 and place <= 4:
				_hud.set_chip("PLACE", "%s OF %d" % [ordinal(place), _players], "info", "", true)
		GameEvent.BOUNTY_MOVED:
			if _training:
				return
			_hud.set_chip("BOUNTY", "BOUNTY ON YOU", "reward", "bounty", int(e.get("to_seat", -1)) == _seat)
		GameEvent.BUFF_APPLIED:
			if int(e.get("seat", -1)) != _seat:
				return
			var until := float(e.get("until_t", t))
			match int(e.get("reward", -1)):
				Reward.Id.DECOY_FLARE:
					_decoy_until = until
					_set_bars_chip("DECOY", "DECOY ARMED %d", "decoy_flare", until, t)
				Reward.Id.OVERCLOCK:
					_overclock_until = until
					_set_bars_chip("OVERCLOCK", "OVERCLOCK %d", "overclock", until, t)
				Reward.Id.BALLAST_PATCH:
					_ballast_until = t + BALLAST_SHOW_SEC
					var pct := roundi(_cfg.ballast_restore_ratio * 100.0)
					_hud.set_chip("BALLAST", "HULL +%d" % pct, "info", "ballast_patch", true)
		GameEvent.BUFF_ENDED:
			if int(e.get("seat", -1)) != _seat:
				return
			match int(e.get("reward", -1)):
				Reward.Id.DECOY_FLARE:
					_decoy_until = -1.0
					_hud.set_chip("DECOY", "", "info", "decoy_flare", false)
				Reward.Id.OVERCLOCK:
					_overclock_until = -1.0
					_hud.set_chip("OVERCLOCK", "", "info", "overclock", false)
		GameEvent.PAYLOAD_END:
			if int(e.get("seat", -1)) != _seat:
				return
			var iu := float(e.get("immune_until", -1.0))
			if iu > t:
				_immune_until = iu
				_hud.set_chip("IMMUNE", "IMMUNE", "muted", "shield", true)
		GameEvent.IMPLODED:
			if int(e.get("seat", -1)) == _seat:
				_wreck = true
		_:
			return
	_now = maxf(_now, t)


## Refreshes the bar countdowns and expires IMMUNE / HULL +p at song time t.
func update(song_time: float) -> void:
	if _hud == null or not is_instance_valid(_hud) or not is_finite(song_time):
		return
	_now = song_time
	if _decoy_until >= 0.0:
		_set_bars_chip("DECOY", "DECOY ARMED %d", "decoy_flare", _decoy_until, song_time)
	if _overclock_until >= 0.0:
		_set_bars_chip("OVERCLOCK", "OVERCLOCK %d", "overclock", _overclock_until, song_time)
	if _ballast_until >= 0.0 and song_time >= _ballast_until:
		_ballast_until = -1.0
		_hud.set_chip("BALLAST", "", "info", "ballast_patch", false)
	if _immune_until >= 0.0 and song_time >= _immune_until:
		_immune_until = -1.0
		_hud.set_chip("IMMUNE", "", "muted", "shield", false)


func _set_bars_chip(key: String, fmt: String, glyph: String, until: float, t: float) -> void:
	var n := bars_left(t, until)
	if int(_last_bars.get(key, -1)) == n:
		return  # unchanged: no string format, no chip_rects() text measuring per frame (WR-10)
	_last_bars[key] = n
	var text := fmt % n
	if _hud.chip_text(key) != text or not _hud.chip_rects().has(key):
		_hud.set_chip(key, text, "info", glyph, true)


## Whole bars left from t until `until` (rounded up, at least 1 while active).
func bars_left(t: float, until: float) -> int:
	if until <= t:
		return 1
	if _chart == null or _chart.tempo_map.is_empty():
		return maxi(1, ceili((until - t) / 2.0 - EPS_BEATS))
	var tm: Array = _chart.tempo_map
	var beats := BeatClock.beat_at(until, tm) - BeatClock.beat_at(t, tm)
	var bar := MatchSim.bar_beats_at(t, _chart)
	return clampi(ceili(beats / bar - EPS_BEATS), 1, 999)
