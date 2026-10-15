extends GdUnitTestSuite
## 03-07 Task 2 (03-SPEC req 8, Pitfall 11): in a 4-Veteran-bot match on each bundled song at
## Expert, every bot earns 2..4 meter rewards. Strict per-bot assertion; never loosen it. If it
## fails, the escalation order is: reward_threshold_ratio, then the Veteran profile within the
## strong definition (sigma 28..36 ms, lapse 1..2%), else a user decision in 03-HUMAN-UAT.md.

const IDS: Array[String] = ["synth_wave_april", "space_synth_wave", "sea_shanty_2", "hrt", "invisible"]
const SEEDS := {"synth_wave_april": 101, "space_synth_wave": 202, "sea_shanty_2": 303,
		"hrt": 404, "invisible": 505}
const MIN_REWARDS := 2
const MAX_REWARDS := 4


func _chart(id: String) -> ChartData:
	var parsed := ChartParser.parse_bytes(
		FileAccess.get_file_as_bytes("res://songs/%s/notes.chart" % id))
	var ini := SongIni.parse(FileAccess.get_file_as_string("res://songs/%s/song.ini" % id))
	return ChartImporter.build(parsed, "expert", SongIni.get_int(ini, "delay", 0))


func test_veteran_is_the_strong_profile() -> void:
	var v := BotProfile.veteran()
	assert_float(v.sigma_s).is_between(0.028, 0.036)
	assert_float(v.lapse).is_between(0.010, 0.020)


func test_four_veteran_bots_earn_2_to_4_rewards_on_every_bundled_song() -> void:
	var cfg := VersusConfig.new()
	var lines: Array[String] = []
	lines.append("ratio %.3f  veteran sigma %.0f ms lapse %.1f%%" % [cfg.reward_threshold_ratio,
		BotProfile.veteran().sigma_s * 1000.0, BotProfile.veteran().lapse * 100.0])
	lines.append("song               | notes | threshold | rewards per bot")
	var bad: Array[String] = []
	for id in IDS:
		var chart := _chart(id)
		var r := MatchHarness.run(chart, {"human": "none",
			"bots": ["veteran", "veteran", "veteran", "veteran"],
			"seed": SEEDS[id], "fps": 60.0, "cfg": cfg})
		var per: Array = []
		for seat in range(4):
			var n: int = r["meter_rewards"].get(seat, 0)
			per.append(n)
			if n < MIN_REWARDS or n > MAX_REWARDS:
				bad.append("%s seat %d: %d" % [id, seat, n])
		lines.append("%-18s | %5d | %9d | %s" % [id, chart.notes.size(), r["threshold"], str(per)])
	print("\nREWARD FREQUENCY TABLE (spec req 8)\n" + "\n".join(lines))
	assert_array(bad).override_failure_message(
		"bots outside [2, 4]: %s\n%s" % [str(bad), "\n".join(lines)]).is_empty()
