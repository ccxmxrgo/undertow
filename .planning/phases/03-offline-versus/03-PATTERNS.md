# Phase 3: Offline Versus - Pattern Map

**Mapped:** 2026-10-15
**Files analyzed:** 46 (new or modified, from 03-RESEARCH "Recommended Project Structure", "Validation Architecture" and D-01..D-33)
**Analogs found:** 44 / 46 (2 have only partial analogs: `match_sim.gd`, `ink_cloud_layer.gd`)

All line numbers refer to the repo at HEAD on 2026-10-15. All paths are relative to `C:\Users\User\UNDERTOW`.

## Project-wide conventions (apply to every file)

| Convention | Source | Rule |
|---|---|---|
| Header | every `src/**` file | Line 1 `class_name X`, line 2 `extends Y`, then a `##` doc block that cites the requirement / decision IDs (e.g. `(03-SPEC req 1, D-31)`), states what the file is NOT allowed to do, and names the effect contract if it is an effect node. |
| Pure logic | `src/core/streak_milestones.gd`, `src/core/run_stats.gd`, `src/core/autoplay.gd` | `extends RefCounted`, no scene / autoload access, time passed in as an argument (never `Time.*` or `_process` delta). Static helpers for pure math (`static func threshold(...)`). |
| Tunables | `src/core/judge_config.gd` | `extends Resource`, `@export var name: type = default` with one `##` line per group. No magic numbers in logic files. |
| Signals | `src/core/hull_score.gd:6-11`, `src/core/input_judge.gd:9-12` | Typed signal params `signal judged(lane: int, note_index: int, judgment: int, error_s: float)`. Listeners are named `on_<signal>` (public) and connected by a `connect_judge` / `bind` method on the listener. |
| Private | all | `_underscore` for private vars/methods; subclasses may call parent `_damage`/`_set_hull` (verified, RESEARCH Pitfall 4). |
| Typed arrays | `input_judge.gd:19-20`, `chart_data.gd:5` | `Array[int]`, `Array[Dictionary]`; dictionaries use string keys (`n["time"]`). |
| Epsilon | `input_judge.gd:14` `const EPS := 1e-9`; `beat_clock.gd:35` `const _EPS := 1e-6` | Every float comparison against a window/beat uses `+ EPS`. |
| RNG | `tests/test_autoplay.gd:10-11` | `var rng := RandomNumberGenerator.new(); rng.seed = N`. Never global `randi()` / `randomize()`. |
| Colours | `src/ui/palette.gd` (only file with literals) | UI uses `Palette.TOKEN` and `Palette.alpha(Palette.TOKEN, a)`. `tests/test_color_literals.gd` scans `res://src/ui` recursively, so `src/ui/versus/**` is covered automatically. |
| Effect contract | `src/ui/gauges/hull_arc.gd:50-55, 184-192`; `src/ui/ui_kit.gd:502-529` | `_ready`: `UiKit.register_fx(self); apply_effect_settings()`. Implement `apply_effect_settings()` (reads `Settings.reduce_motion` / `Settings.low_effects` or `UiKit.low_effects()`) and `effect_counts() -> Dictionary`. Timers are delta-driven via a public `step(dt)` so tests can step them. |
| Fixed-rect HUD nodes | `src/ui/gauges/torpedo_socket.gd:7,17-20`; `section_banner.gd:17,52-59` | `const RECT := Rect2(...)` at 1920x1080 design pixels; `_ready`: `position = RECT.position; size = RECT.size; mouse_filter = Control.MOUSE_FILTER_IGNORE`. |
| Full-screen canvases | `src/ui/hud.gd:428-440`, `section_banner.gd:257-262` | Any Control >= 90% of the viewport must implement `keepout_shapes() -> Array[PackedVector2Array]` in global space, or `test_layout_keepout` fails. |
| `.uid` sidecars | `git ls-files src/core` shows `*.gd.uid` tracked | Every new `.gd` gets a `.gd.uid` from the Godot import; commit both (explicit `git add` of each). |
| Tests | `tests/test_*.gd` | `extends GdUnitTestSuite`, a `##` line naming the requirement, `before_test`/`after_test` save+restore any `Settings.*` or `Gameplay.pending_*` static they touch, `auto_free(...)` for nodes, `assert_int/float/bool/array/str(...)`, `.override_failure_message(...)` for loops. Run: `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_<suite>.gd`. |

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/core/judge_config.gd` (MOD, 1 line) | config | n/a | itself; precedent commit `fbcf994` | exact (pin procedure) |
| `tools/check_timing_gate.ps1` (MOD) | config/tool | batch | itself (lines 1-17); precedent commit `c626ab9` | exact |
| `tests/test_hull_score.gd` (MOD) | test | unit | itself (lines 23-28) | exact |
| `src/versus/versus_config.gd` | config | n/a | `src/core/judge_config.gd` | exact |
| `src/versus/reward.gd` | model (enum + static table) | transform | `src/core/streak_milestones.gd`, `palette.gd` `GRADE_COLORS` | role-match |
| `src/versus/reward_meter.gd` | model (pure state) | event-driven | `src/core/hull_score.gd` | exact |
| `src/versus/reward_bag.gd` | utility (seeded) | transform | RESEARCH code example + `tests/test_autoplay.gd:10` RNG | role-match |
| `src/versus/player_state.gd` | model | CRUD | `src/core/hull_score.gd` (counters + signals) | role-match |
| `src/versus/game_event.gd` | model (constants + ctors) | transform | `src/core/chart_data.gd` (dictionary records), `StreakMilestones` statics | role-match |
| `src/versus/event_channel.gd` | service (interface) | pub-sub | `src/core/hit_offset_recorder.gd` (attach/detach listener) | partial |
| `src/versus/loopback_channel.gd` | service | pub-sub | same as above | partial |
| `src/versus/match_sim.gd` | service (referee) | event-driven, song-time | `src/core/input_judge.gd` (`tick(t)` + queue resolution) + `autoplay.gd` | partial |
| `src/versus/payload_notes.gd` | utility (generator) | transform | `src/core/autoplay.gd` (event list build/sort), `beat_clock.gd` | role-match |
| `src/versus/bot_profile.gd` | config | n/a | `src/core/judge_config.gd` | exact |
| `src/versus/bot_player.gd` | service | event-driven | `src/core/autoplay.gd` | exact |
| `src/versus/medal_rules.gd` | utility (pure rules) | transform | `src/core/run_stats.gd` (`grade()`) | exact |
| `src/versus/training_drone.gd` | service | event-driven | `src/core/autoplay.gd` + `BotPlayer` | role-match |
| `src/core/versus_judge.gd` | service (subclass) | event-driven | `src/core/input_judge.gd` (extend, never edit) | exact |
| `src/core/versus_hull.gd` | model (subclass) | event-driven | `src/core/hull_score.gd` (extend, never edit) | exact |
| `src/core/versus_autoplay.gd` | service | event-driven | `src/core/autoplay.gd` | exact |
| `src/input/lane_input.gd` (MOD, Crossed Wires remap) | input | event-driven | itself (lines 81-112) | exact |
| `src/ui/highway.gd` (MOD: `scroll_mult`, `lane_pos`, jam, overlay gems) | component | streaming (per-frame) | itself (`_update_window` 455-477) | exact |
| `src/ui/note_painter.gd` (MOD: `NOTE_GHOST`, `NOTE_DISRUPTOR`, jam) | utility (draw) | transform | itself (`resolve_type` 51-57, `layers` 60-70, `draw_note` 177-181) | exact |
| `src/ui/palette.gd` (MOD: new tokens e.g. `JAM_GREY`) | config | n/a | itself (lines 7-30) | exact |
| `src/ui/versus/ink_cloud_layer.gd` | component (board layer) | streaming | `src/ui/highway_notes.gd` | partial |
| `src/ui/versus/reward_socket.gd` | component (gauge) | event-driven | `src/ui/gauges/torpedo_socket.gd` + `hull_arc.gd` | exact |
| `src/ui/versus/incoming_alert.gd` | component (timed) | event-driven | `src/ui/gauges/section_banner.gd` | role-match |
| `src/ui/versus/periscope_panel.gd` | component (gauge) | event-driven | `src/ui/gauges/hull_arc.gd`, `results_screen.gd` `_panel` | role-match |
| `src/ui/versus/killfeed.gd` | component (timed list) | event-driven | `src/ui/gauges/section_banner.gd` (hold/fade timers) | role-match |
| `src/ui/versus/duel_banner.gd` | component (timed) | event-driven | `src/ui/gauges/section_banner.gd` | exact |
| `src/ui/versus/versus_controller.gd` | controller | event-driven | `src/ui/gameplay.gd` `start()` 88-198, `_process` 284-294 | exact |
| `src/ui/gameplay.gd` (MOD: `pending_match` mode flag) | controller | request-response | itself (statics 19-24, `_ready` 73-84) | exact |
| `src/ui/versus/match_setup_screen.gd` + `scenes/match_setup.tscn` | screen | request-response | `src/ui/main_menu.gd` (items/focus) + `scenes/song_select.tscn` | role-match |
| `src/ui/main_menu.gd` (MOD: "Versus Bots" item) | screen | request-response | itself (167-185, 228-230, 482-492) | exact |
| `src/ui/song_select.gd` (MOD: Training payloads row, versus launch) | screen | request-response | itself (`run_practice` 90-91, `_dive` 729-748, `_start_label` 1931-1944) | exact |
| `src/ui/versus/versus_results_screen.gd` | screen | request-response | `src/ui/results_screen.gd` | exact |
| `src/ui/ui_icons.gd` (MOD: killfeed + reward glyphs) | utility (draw) | transform | itself (`NAMES` 9-12, `draw` 21-) | exact |
| `src/audio/sfx_pool.gd` (MOD or new `versus_sfx.gd`: ping, collision) | service | event-driven | itself + `AudioSynth.make_tick/make_clunk` | exact |
| `tests/test_reward_meter.gd`, `test_reward_bag.gd`, `test_medal_rules.gd`, `test_solo_duel.gd` | test | unit | `tests/test_streak_milestones.gd`, `tests/test_hull_score.gd` | exact |
| `tests/test_match_sim_fire.gd`, `test_match_sim_bounty.gd`, `test_buffs.gd`, `test_return_to_sender.gd`, `test_match_standings.gd` | test | unit | `tests/test_hull_score.gd` (`_make`/`_hit` helpers) | exact |
| `tests/test_versus_subclass.gd`, `test_versus_judge.gd`, `test_payload_notes.gd` | test | unit/integration | `tests/test_autoplay.gd` (`_schedule`, `_run`, `_assert_all_perfect`) | exact |
| `tests/test_match_determinism.gd`, `test_bot_frequency.gd` | test | integration | `tests/test_autoplay.gd` + `tests/test_bundled_songs.gd` (`_parsed`) | exact |
| `tests/test_killfeed.gd` | test | scene | `tests/test_hud_gauges.gd` | exact |
| `tests/test_layout_keepout.gd` (EXTEND) | test | scene | itself (lines 88-104) | exact |
| `tests/test_effect_settings.gd` (EXTEND) | test | scene | itself (`EXPECTED`/`REDUCE` 17-41) | exact |
| `tests/test_contrast.gd` (EXTEND), `tests/test_visual_sync.gd` (EXTEND) | test | unit/scene | themselves | exact |

---

## Pattern Assignments

### `src/core/judge_config.gd` + `tests/test_hull_score.gd` + `tools/check_timing_gate.ps1` (D-29 pin move)

**Commit A** changes only `judge_config.gd:16`:
```gdscript
@export var perfect_regen: float = 1.0      # -> 0.25
```
**Commit B** edits `tests/test_hull_score.gd:23-28` (rename + new values) and adds the 32-Perfect test using the same `_make()` / `_hit(h, j, n)` helpers (lines 10-20):
```gdscript
func test_miss_costs_eight_perfect_restores_one() -> void:   # rename -> ..._restores_quarter
	var h := _make()
	_hit(h, M)
	assert_float(h.hull).is_equal(92.0)
	_hit(h, P)
	assert_float(h.hull).is_equal(93.0)                        # -> 92.25
```
**Commit C** edits `tools/check_timing_gate.ps1:8-10,17`: `$judgeBase = "fbcf994"` -> short hash of A, and add a header paragraph modelled on lines 8-10 ("03-SPEC req 14: on 2026-10-08 the user approved perfect_regen 1.0 -> 0.25. Commit <A> changes exactly that default; windows unchanged."). Do not touch `$base = "72e21ce"` (line 16) or the four-file group (lines 19-24).
Verify: `powershell -NoProfile -File tools/check_timing_gate.ps1` prints `TIMING GATE OK`; scratch whitespace edit -> `TIMING GATE FAILED`; `git diff fbcf994 <A> -- src/core/judge_config.gd` shows one line.

---

### `src/versus/versus_config.gd` and `src/versus/bot_profile.gd` (config)

**Analog:** `src/core/judge_config.gd` (lines 1-24)
```gdscript
class_name JudgeConfig
extends Resource
## All judgment, hull, score and clock tunables (D-08). Seconds unless noted.
## Windows and tuning live here only; the judge contains no magic numbers.

@export var perfect_window: float = 0.050
...
## Hull damage for a stray press (D-10): default 0, revisit in Phase 3.
@export var stray_hull_damage: float = 0.0
```
Copy: `class_name VersusConfig extends Resource`, one `@export` per tunable with a `##` comment citing the spec req / D-number (`reward_threshold_ratio = 0.12`, `torpedo_travel_beats = 1`, `bounty_refund_ratio = 0.25`, `solo_duel_min_notes = 16`, `solo_duel_min_accuracy = 0.85`, `immunity_bars = 1`, `ghost_hull_damage = 4.0`, `ghost_damage_cap = 12.0`, `warhead_count = 4`, `pressure_crack_max_speed = 3.5`, `depth_charge_density = 0.5`, `training_interval_bars = 8`, `ballast_restore_ratio = 0.25`, `debris_max_per_wreck = 2`, `ghost_resets_meter = false`, killfeed `max_lines = 4`, `fade_sec = 4.0`, per-reward bar durations). Add a `clamped()` or validate helper (RESEARCH Security V5: bot count 1..3, ratios 0..1, bars >= 1). `BotProfile` the same shape: `sigma_s`, `lapse`, payload penalty fields, plus `static func veteran()/regular()/rookie()` factories (D-19).

---

### `src/versus/reward.gd` (enum + static table)

**Analog:** `src/core/streak_milestones.gd` (lines 1-6) and `Palette.GRADE_COLORS` (palette.gd:50)
```gdscript
class_name StreakMilestones
extends RefCounted
## Pure milestone logic for the note-streak popups (D-08): 10, 25, 50, then every 100.

const FIXED: Array[int] = [10, 25, 50]

static func is_milestone(n: int) -> bool:
```
Copy: `enum Id { PRESSURE_CRACK, CROSSED_WIRES, GHOST_NOTES, INK_CLOUD, DEPTH_CHARGE, SONAR_JAM, DECOY_FLARE, BALLAST_PATCH, OVERCLOCK }`, `enum Kind { DISRUPTOR, BUFF }`, `const ALL: Array[int] = [...]` (9 items; spec req 7 test asserts no Lane Flip), a `const TABLE := { Id.X: {"name": "Ink Cloud", "kind": Kind.DISRUPTOR, "icon": "ink"} }` and static getters `name_of(id)`, `is_disruptor(id)`. Durations stay in `VersusConfig`, not here.

---

### `src/versus/reward_meter.gd` and `src/versus/player_state.gd` (pure state with signals)

**Analog:** `src/core/hull_score.gd`

Signals + counters (lines 6-27):
```gdscript
signal hull_changed(value: float, delta: float)
signal combo_changed(value: int)
...
var perfect_count: int = 0
var _cfg: JudgeConfig

func _init(cfg: JudgeConfig) -> void:
	_cfg = cfg
	hull = cfg.hull_start
```
Judgment dispatch (lines 51-68) - the meter's `on_judged` should mirror this `match`:
```gdscript
func on_judged(_lane: int, _idx: int, judgment: int, _err: float) -> void:
	match judgment:
		InputJudge.Judgment.PERFECT:
			...
		InputJudge.Judgment.GOOD:
			...
		_:
			...
```
Setter-emits pattern (lines 108-120): every state change goes through one `_set_x(v)` that clamps, updates and emits `x_changed`. Use for `progress`, `held`, `queued`.
Copy: `RewardMeter._init(threshold: int, cfg: VersusConfig)`, `static func threshold(note_count: int, ratio: float) -> int` (RESEARCH "Threshold" example), signals `progress_changed(value: int, threshold: int)`, `reward_earned(id: int)`, `slot_changed(id: int)`. Note: the meter listens to the raw judgment plus an `overclock` flag passed in by `MatchSim`/`VersusHull`, not to `streak_changed` (Good must not reset the meter; HullScore resets `perfect_streak` on Good).
`PlayerState` collects `alive`, `eliminated_at`, `seat`, `name`, `meter`, `bag`, shield fields and match-log counters (landed / reflected / absorbed / bounties / duels / collisions / per-rival hits). Standings must read `alive`/`eliminated_at`, never `hull > 0` (RESEARCH Pitfall 5).

---

### `src/versus/reward_bag.gd` (seeded utility)

**Analog:** RESEARCH "Seeded bag" code example (03-RESEARCH.md lines 366-385) and RNG seeding from `tests/test_autoplay.gd:10-11`:
```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = 1234
```
Copy the RESEARCH Fisher-Yates verbatim (`_rng.randi_range(0, i)`, `pop_back`). Seed per player `hash([match_seed, seat])`. Expose `peek_remaining()` for the test only.

---

### `src/versus/game_event.gd`, `event_channel.gd`, `loopback_channel.gd` (pub-sub seam)

**Analog (records):** `src/core/chart_data.gd` (lines 5-11) - dictionaries with string keys, documented inline:
```gdscript
var notes: Array[Dictionary] = []  # {lane:int 0-3, time:float, duration:float}
## Solo sections (D-17): {start: float, end: float, note_count: int}, seconds.
var solos: Array[Dictionary] = []
```
Copy: `GameEvent` = `class_name GameEvent extends RefCounted` with `const FIRE := "fire"`, `TORPEDO_LAUNCH`, `ARRIVE`, `LANDED`, `ABSORBED`, `REFLECTED`, `COLLISION`, `BOUNTY_MOVED`, `BOUNTY_CLAIMED`, `DUEL_START`, `DUEL_WON`, `IMPLODED`, `BUFF_APPLIED`, ... and static constructors `static func make(type: String, song_time: float, from: int, to: int, extra: Dictionary = {}) -> Dictionary`. Every event carries `song_time` (spec constraint: host-decidable).

**Analog (listener attach/detach):** `src/core/hit_offset_recorder.gd` (lines 14-25):
```gdscript
func attach(judge: Object) -> void:
	detach()
	if judge == null or not judge.has_signal("judged"):
		return
	_judge = judge
	judge.judged.connect(_on_judged)
```
Copy: `EventChannel extends RefCounted` with `signal received(e: Dictionary)` and virtual `func send(e: Dictionary) -> void`. `LoopbackChannel extends EventChannel` emits `received` synchronously (optional `latency_s` queue drained by `update(t)` for tests). Views (killfeed, panels, HUD socket) subscribe only to `received` - never to `MatchSim` internals (spec req 12).

---

### `src/versus/match_sim.gd` (song-time referee) - partial analog

**Analog for the "process everything due up to t" loop:** `src/core/input_judge.gd` `tick`/`_expire` (lines 53-56, 111-119):
```gdscript
func tick(t: float) -> void:
	for lane in range(4):
		_expire(lane, t)
		_advance_hold(lane, t)

func _expire(lane: int, t: float) -> void:
	var q: Array[int] = _queues[lane]
	while _heads[lane] < q.size():
		var idx: int = q[_heads[lane]]
		var dt: float = t - float(_chart.notes[idx]["time"])
		if dt > _cfg.good_window + EPS:
			_resolve(lane, idx, Judgment.MISS, dt)
		else:
			break
```
**Analog for time-ordered event queue with deterministic tie order:** `src/core/autoplay.gd` lines 12-33 (sort by time, then kind, then lane; `while _next < size and time <= song_time`).
**Beat math:** `BeatClock.beat_at(t, tempo_map)` (beat_clock.gd:87) and `BeatClock.time_at_beat(b, tempo_map)` (106); bar length from `chart.time_sigs` as in `beat_clock.gd:51-58` (`bar_len = num * 4.0 / den`). Launch beat per RESEARCH Pattern 2: `int(floor(BeatClock.beat_at(t_press, tempo_map) + EPS)) + 1`.
Rules: `update(t)` resolves per beat boundary (collisions first, then shields in seat order); never depends on frame order (RESEARCH Pitfall 6). Solo duels resolve at `solo.end + good_window + 1e-3` (Pitfall 9). Ignore malformed solos (end <= start). No novel analog exists for collision/bounty/standings - follow RESEARCH Pattern 2 and D-01..D-25.

---

### `src/core/versus_judge.gd` and `src/core/versus_hull.gd` (subclass the pinned core)

**Analog:** `src/core/input_judge.gd` / `src/core/hull_score.gd` - **extend, never edit** (gate pins `72e21ce`).
Key hooks to override (InputJudge lines 34-56, 59-69):
```gdscript
func press(lane: int, t: float) -> void:   # base: _expire, then judge queue head, else stray.emit
func tick(t: float) -> void:
func release(lane: int, t: float) -> void:
```
HullScore hooks (lines 17-20, 31-49, 77-94): `connect_judge(judge)` connects `judged.connect(on_judged)` - the subclass override is dispatched (verified). Use parent `_damage(amount)`, `_set_hull(v)`; for the Overclock score top-up do NOT call `_add_score` (it multiplies again after the combo rose) - capture `multiplier()` before `super.on_judged(...)` exactly as RESEARCH Pattern 1 (lines 194-214) shows.
Doc header must say: "Never edit input_judge.gd / hull_score.gd (pinned 72e21ce)". Overlay notes live in the subclass's own queue; never append to `ChartData.notes` (breaks `Highway._state` indexing and fingerprints).

---

### `src/core/versus_autoplay.gd`, `src/versus/bot_player.gd`, `src/versus/training_drone.gd` (time-ordered press drivers)

**Analog:** `src/core/autoplay.gd` (whole file, 37 lines):
```gdscript
func _init(chart: ChartData, judge: InputJudge) -> void:
	_judge = judge
	for n in chart.notes:
		_events.append({"time": n["time"], "kind": 1, "lane": n["lane"]})
		if n["duration"] > 0.0:
			_events.append({"time": n["time"] + n["duration"], "kind": 0, "lane": n["lane"]})
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: ...)

func update(song_time: float) -> void:
	while _next < _events.size() and _events[_next]["time"] <= song_time:
		var e: Dictionary = _events[_next]
		_next += 1
		if e["kind"] == 1:
			_judge.press(e["lane"], e["time"])
		else:
			_judge.release(e["lane"], e["time"])
```
Copy: same `update(song_time)` contract; presses pass the **event time**, never the frame time (Phase 1 D-28). `VersusAutoplay` adds overlay notes (Depth Charge) and skips ghosts. `BotPlayer` samples each note once in a 1 s lookahead (`time + N(0, sigma)` or lapse) with its own seeded RNG and inserts into the sorted queue; it owns a `VersusJudge` + `VersusHull` + `PlayerState`. `TrainingDrone` emits FIRE events to `LoopbackChannel` every `training_interval_bars`.

---

### `src/versus/payload_notes.gd` (seeded generators) and `src/versus/medal_rules.gd` (pure rules)

**Analog (generators):** `autoplay.gd` sort (above) + `BeatClock.beats_between(t0, t1, tempo_map, time_sigs)` (beat_clock.gd:43, bounded by `MAX_BEATS := 4096` line 34 - copy that bound for overlay counts, RESEARCH Security).
**Analog (rules):** `src/core/run_stats.gd` (lines 17-40) - all-static, input numbers -> output, sentinel for "nothing":
```gdscript
## S >= 98 with no miss, A >= 93, B >= 85, C >= 75, else D; "-" when nothing was judged.
static func grade(acc: float, misses: int) -> String:
	if acc < 0.0 or not is_finite(acc):
		return "-"
	if acc >= 98.0 and misses == 0:
		return "S"
```
Copy: `static func medals(log: Array[Dictionary], players: int) -> Array` returning per-seat `Array[String]` in spec table order, max 3; constants `const ORDER: Array[String] = ["Untouchable", "Uno Reverse", ...]`.

---

### `src/input/lane_input.gd` (MOD: Crossed Wires physical->lane remap)

**Analog:** itself, lines 81-105:
```gdscript
func _press(lane: int, ticks: int) -> void:
	if _held[lane]:
		return
	_held[lane] = true
	if conductor != null and judge != null:
		judge.press(lane, conductor.song_time_at(ticks))
	lane_pressed.emit(lane, ticks)
```
Add `var lane_map: PackedInt32Array = [0,1,2,3]` applied when an ACTION index becomes a judged lane, and a `_pressed_lane[action]` array so release uses the lane recorded at press time (RESEARCH Pitfall 3). Keep `inject(event)` (line 42-44) as the test seam; extend `tests/test_lane_input.gd` with `_key(...)` helper (lines 17-22). Keep the `judge: InputJudge` type (VersusJudge is-a InputJudge).

---

### `src/ui/highway.gd`, `src/ui/note_painter.gd`, `src/ui/palette.gd` (MOD: payload visuals)

**Highway approach hook** (highway.gd:455-462) - the single place to apply `scroll_mult`:
```gdscript
	_st = conductor.song_time()
	_vt = _st + Settings.visual_offset
	_approach = Trench.approach_for(Settings.scroll_speed)
```
-> `Trench.approach_for(effective_speed)` where effective = `min(base * mult, max(base, pressure_crack_max_speed))`. Lane x comes from `Trench.lane_f(lane)` (highway.gd:888-889, 962) - route through a `lane_pos(lane)` float that interpolates during the 1-beat slide. Add a `var modifiers: Object` (the target's PayloadStack) read each frame; Highway never decides rules.
**NotePainter extension points** (note_painter.gd:51-57, 177-181) - the doc header (line 3-4) already reserves this:
```gdscript
static func resolve_type(type: int) -> int:
	match type:
		NOTE_NORMAL:
			return NOTE_NORMAL
		_:
			return NOTE_NORMAL
```
Add `const NOTE_GHOST := 1`, `NOTE_DISRUPTOR := 2`, `NOTE_JAM := 3` as new `match` arms in `resolve_type`, `layers` and `draw_note`; extend `tests/test_note_painter.gd`.
**Palette tokens** (palette.gd:7-30): add `const JAM_GREY := ...` with a trailing `# purpose` comment; add a contrast row in `tests/test_contrast.gd` using `_check(label, fg, bg, minimum)` (lines 31-35) over `_surface()` (lines 11-13).

---

### `src/ui/versus/ink_cloud_layer.gd` (board layer) - partial analog

**Analog:** `src/ui/highway_notes.gd` (lines 20-67): a full-rect board child that reads all state from `highway` and only draws.
```gdscript
func _init() -> void:
	UiLayout.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	apply_effect_settings()
	UiKit.register_fx(self)

func apply_effect_settings() -> void:
	halos.visible = not UiKit.low_effects()
	queue_redraw()

func effect_counts() -> Dictionary:
	var low := UiKit.low_effects()
	return {"halos": halos.visible, "halo_ring": low}
```
Insert as a `board_root` child **above** `highway_notes` (gameplay.gd:161-163 order), band geometry from `Trench.point(f, d)` for d in [-0.15, 0.35]; Low effects = flat band, Full = noise edge. Because it is a board layer it is exempt from the HUD keep-out scan (like Feedback/HighwayNotes, test_layout_keepout.gd:6-8). No existing occluder layer exists - this is the novel part.

---

### `src/ui/versus/reward_socket.gd` (meter arc + held icon on TorpedoSocket)

**Analog:** `src/ui/gauges/torpedo_socket.gd` (whole file) for rect/geometry, `hull_arc.gd` for effect contract and animated fill.
```gdscript
const RECT := Rect2(272.0, 928.0, 80.0, 80.0)
const R_OUTER := 36.0
...
func _draw() -> void:
	var c := RECT.size * 0.5
	draw_circle(c, R_OUTER, Palette.alpha(Palette.ABYSS_900, FILL_ALPHA), true, -1.0, true)
	...
	draw_arc(c, R_OUTER, 0.0, TAU, 64, Palette.alpha(Palette.SONAR, OUTER_ALPHA), Palette.EDGE_HAIR, true)
```
hull_arc.gd public API style (lines 58-80): `reset(...)`, `set_x(value, delta)`, read-only getters `pct()`, `is_flashing()` for tests; `_process(delta)` drives timers (lines 195-209). Either draw on top of the existing socket (Hud keeps `torpedo_socket`, hud.gd:110-112) or make RewardSocket a child of `hud` at `TorpedoSocket.RECT` - D-33 radius 40 arc, `SONAR` / `SONAR_PALE` full pulse (static under Reduce motion), `REWARD_GOLD` queue pip. Icon via `UiIcons.draw(ci, name, rect, color)`. Add its rects to Hud-style `keepout_shapes()` or keep it a plain fixed-rect Control so the scanner checks its rect.

---

### `src/ui/versus/duel_banner.gd`, `incoming_alert.gd`, `killfeed.gd` (timed overlays)

**Analog:** `src/ui/gauges/section_banner.gd`
State machine + constants (lines 15-34):
```gdscript
enum Phase { IDLE, IN, HOLD, OUT }

const RECT := Rect2(640.0, 200.0, 640.0, 72.0)
const HOLD_SEC := 1.6
const OUT_SEC := 0.3
```
Ready + effect contract (lines 52-59, 235-247):
```gdscript
func _ready() -> void:
	position = RECT.position
	size = RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	UiKit.register_fx(self)
	apply_effect_settings()

func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	_panel = UiKit.style_panel("default", _low)
	...
func effect_counts() -> Dictionary:
	return {"slide": not _reduce, "glow": not _low, "sweep": sweep_on()}
```
Test seam (lines 157-168): public `step(dt)` advances timers; `_process(delta)` only calls `observe(song_time)` then `step(delta)`. Text truncation via `ProgressTrack.truncate_px(text, font, size, max_w)`; keep-out via `keepout_shapes()` (lines 257-262).
- `DuelBanner`: same RECT family as SectionBanner (do not overlap it: show 1 bar before solo; coordinate with UI-SPEC).
- `Killfeed`: right column rect `Rect2(1544, 216, 352, 184)` (D-26); per line `{text, age, own}`; `max_lines` 4, 5th pops oldest, fade at 4 s, driven by `step(dt)`. Glyphs via `UiIcons` (D-32), own-line `SONAR` left bar + `TEXT_HI`, else `TEXT_MID`. Subscribes to `EventChannel.received` only.
- `IncomingAlert`: telegraph with a 1-beat countdown ring; edge flash under Reduce motion becomes static.

---

### `src/ui/versus/periscope_panel.gd` (rival gauge, x3)

**Analog:** glass panel + brackets from `results_screen.gd` `_panel` (lines 439-446):
```gdscript
func _panel(node_name: String, rect: Rect2, bracket: Color) -> void:
	var sb := UiKit.style_panel("default")
	_painter(node_name, rect, func(ci: CanvasItem) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_style_box(sb, r)
		UiKit.draw_brackets(ci, r, bracket))
```
Segmented hull bar: reuse `HullArc.segments_lit(pct)` / `HullArc.color_for(pct)` statics (hull_arc.gd:110-131) so rival hull colours match the player's. Chips via `UiKit.draw_chip(ci, rect, text, variant)` (ui_kit.gd:413). Fixed rects in the left column x 24..376, y 216..584 (D-26), one `const RECT_FOR(seat)` static. Target bracket = `UiKit.draw_brackets`. Register as effect node if it blinks (scope blip, flash).

---

### `src/ui/versus/versus_controller.gd` + `src/ui/gameplay.gd` (MOD)

**Analog:** `src/ui/gameplay.gd`
Launch statics (lines 19-24) - add `static var pending_match: Dictionary = {}` (or a `MatchSetup` object) next to them, reset in `_ready` like `pending_practice` (lines 80-83):
```gdscript
static var pending_chart: ChartData
static var pending_autoplay: bool = false
static var pending_practice: bool = false
...
	practice = pending_practice
	pending_practice = false
```
Judge/hull construction (lines 107-114) - the ONLY branch point: versus builds `VersusJudge`/`VersusHull` and forces `no_fail = false` (RESEARCH anti-pattern); solo keeps `InputJudge`/`HullScore` unchanged:
```gdscript
	var cfg := JudgeConfig.new()
	judge = InputJudge.new(chart, cfg)
	score = HullScore.new(cfg)
	score.no_fail = Settings.no_fail or practice
	score.connect_judge(judge)
```
Child wiring under `_run_root` (lines 164-182): HUD-level nodes are added after `hud` and before `streak_counter`; board layers go into `board_root`. Per-frame driving (lines 284-294) - `VersusController._process` (or a call from Gameplay `_process`) runs after `judge.tick(t)`: bots `update(t)`, `match_sim.update(t)`; skip while `conductor.is_paused()`.
```gdscript
	var t := conductor.song_time()
	if _autoplay_player != null:
		_autoplay_player.update(t)
	judge.tick(t)
```
Failure path: in versus, `score.failed` must NOT call `_on_failed` (lines 372-403, solo FailScreen + conductor.stop); instead mark `PlayerState.alive = false`, show an in-match IMPLOSION flash, keep playing as WRECK (D-24). `_finish` (lines 322-359): versus skips `ScoreStore.submit` (D-23) and builds `VersusResultsScreen` with the same `retry_pressed / song_select_pressed / menu_pressed` connections. Teardown: everything lives under `_run_root`, so restart is free (lines 262-277); `offset_recorder` pattern (lines 56, 112-113) is reused per player for accuracy.
Fire / target input: add `_unhandled_input` handling like `pause` (lines 297-307) using actions `&"fire"` and `&"target_cycle"` (already in InputMap/BindingStore), stamping song time via `conductor.song_time_at(Time.get_ticks_usec())` like `LaneInput._input` (lane_input.gd:47-48).

---

### `src/ui/versus/match_setup_screen.gd` + `scenes/match_setup.tscn`, `src/ui/main_menu.gd` (MOD)

**Menu item analog** (main_menu.gd:167-185, 228-230, 482-492):
```gdscript
	practice_button = _item("Practice Dive (No-Fail)", "lifebuoy", "default", func() -> void: launch_practice())
...
func menu_buttons() -> Array:
	return [start_button, practice_button, chart_button, ...]
...
func launch_practice() -> void:
	SongSelect.run_autoplay = false
	SongSelect.run_practice = true
	_go(SONG_SELECT_SCENE)
```
Add a "Versus Bots" item (and a `DESCRIPTIONS` entry; focus ring wraps automatically via the loop at 179-185); `menu_buttons()` order is asserted by `tests/test_menu_flow.gd` / `test_gamepad_menus.gd` - update them. Flow: Menu -> Song Select with `SongSelect.run_versus = true` -> Match Setup (bot count 1..3, tier) -> Gameplay, or Setup first; follow UI-SPEC. Scene files are 12-line stubs (e.g. `scenes/song_select.tscn`) pointing at the script; navigate with `ScreenTransition.change_scene(path)` (main_menu.gd:661-666 `_go`). Buttons via `UiKit.make_button(text, icon, variant, height)` and the closed focus loop from `results_screen.gd:362-373`.

---

### `src/ui/song_select.gd` (MOD: Training payloads row / versus launch)

**Analog:** itself. Run flags (lines 90-91), launch (lines 738-748), start label (lines 1931-1944), header chip (lines 1359-1366):
```gdscript
static var run_autoplay: bool = false
static var run_practice: bool = false
...
	Gameplay.pending_chart = chart
	Gameplay.pending_autoplay = run_autoplay
	Gameplay.pending_practice = run_practice
...
	if run_practice:
		return "Start Practice Dive"
```
Add `static var run_training: int` (Off / All / single payload id) cycled like `_change_difficulty` (lines 671-677), painted in `_paint_detail` area, passed as `Gameplay.pending_training`. Reset in `_exit_tree` alongside lines 276-277. Rename visible copy "Practice Dive" -> "Solo Dive" only if UI-SPEC says so (tests grep these strings).

---

### `src/ui/versus/versus_results_screen.gd`

**Analog:** `src/ui/results_screen.gd` - copy the structure wholesale:
- signals `retry_pressed`, `menu_pressed`, `song_select_pressed` (lines 24-26)
- `setup(...)`: `UiLayout.fill_rect(self)`, `mouse_filter = STOP`, theme, clear children, `_build_backdrop()`, `_layout` Control (lines 117-137)
- helpers `_label(...)` baseline-positioned (lines 404-425), `_painter(...)` with inner `class Painter` (line 108), `_panel(...)` (439-446), `_chip(...)` (448-472), `_bar(...)` (475-485), `_begin_group` for entrance stagger (488-496)
- `_build_buttons()` closed focus loop (346-373)
- entrance: `entrance_running()/skip_entrance()/apply_entrance(t)` + `apply_effect_settings`/`effect_counts` (lines 505-583)
Per player row: placement, name, depth, `RunStats.accuracy_text(RunStats.accuracy(p, g, m))`, landed / reflected, up to 3 medal chips (variant "reward" uses `REWARD_GOLD`; keep REWARD_GOLD out of the note-path keep-out). Show the match seed (D-18). Add a context to `test_effect_settings.gd` `EXPECTED` for the new screen.

---

### Tests

**Pure unit suites** (`test_reward_meter`, `test_reward_bag`, `test_medal_rules`, `test_solo_duel`, `test_match_sim_*`, `test_buffs`, `test_return_to_sender`, `test_match_standings`): copy `tests/test_hull_score.gd` lines 1-20 (judgment consts + `_make()` factory + `_hit(h, j, n)` loop helper) and `tests/test_streak_milestones.gd` (static-function table asserts, `for n in [...]` loops).
```gdscript
extends GdUnitTestSuite

const P := InputJudge.Judgment.PERFECT
const G := InputJudge.Judgment.GOOD
const M := InputJudge.Judgment.MISS

func _make(no_fail: bool = false) -> HullScore:
	var h := HullScore.new(JudgeConfig.new())
	...
	h.failed.connect(func() -> void: _failed_count += 1)
	return h
```
Signal capture via lambdas appending to arrays (test_autoplay.gd:30-31). Charts: `TestCharts.click_chart(bpm, beats)` / `short_chart()` / `five_minute_click_chart()` (src/content/test_charts.gd) - add a `solo_chart()` there if needed, or set `chart.solos.append({"start":..,"end":..,"note_count":..})` directly.

**Frame-rate determinism / autoplay-under-payload** (`test_match_determinism`, `test_versus_judge`, `test_payload_notes`, `test_versus_subclass`): copy `tests/test_autoplay.gd` `_schedule(fps, length, jitter)` (lines 8-21), `_run(chart, times)` (24-36), `_assert_all_perfect` (39-51) and the `for fps in [30.0, 60.0, 144.0]` loop (57-59); add 1000 fps.

**Bundled-song sweeps** (`test_bot_frequency`, payload spacing invariant over 5 songs x 4 diffs): copy `tests/test_bundled_songs.gd` lines 8-9 (`IDS`, `DIFFS`) and `_parsed(id)` (lines 15-16), then `ChartImporter.build(parsed, diff)` (chart_importer.gd:54) for a ChartData without audio.

**Scene suites** (`test_killfeed`, panel/socket tests): copy `tests/test_hud_gauges.gd` lines 1-24 (save/restore `Settings.low_effects`/`reduce_motion`, `auto_free(X.new())`, `add_child`, drive by emitting signals or `step(dt)`).

**Keep-out** (`test_layout_keepout.gd` extend): launch helper `_launch()` (lines 47-55) sets `Gameplay.pending_*` - add `pending_match` there; in the main test (lines 88-104) add the versus HUD roots to `for root in [...]` and make panels/killfeed/banner visible first (as done with `section_banner.show_section` + `step`). Reset every new `Gameplay.pending_*` in `after_test` (lines 23-27).

**Effect settings** (`test_effect_settings.gd` extend): add a `"versus"` context to `EXPECTED` (lines 17-23) listing `RewardSocket`, `Killfeed`, `DuelBanner`, `IncomingAlert`, `PeriscopePanel`, `InkCloudLayer` (whatever registers fx) and their Reduce-motion keys to `REDUCE` (lines 27-40).

**Colour literals**: nothing to add - `test_color_literals.gd` scans `res://src/ui` recursively (lines 7, 33-40). `src/versus/**` holds no colours.

---

## Shared Patterns

### Effect contract (every animated view node)
**Source:** `src/ui/ui_kit.gd:502-512`, `src/ui/gauges/section_banner.gd:52-59, 235-247`
**Apply to:** reward_socket, incoming_alert, periscope_panel, killfeed, duel_banner, ink_cloud_layer, versus_results_screen, NOTE_GHOST / jam drawing (Low effects readability, spec constraint).
```gdscript
	UiKit.register_fx(self)
	apply_effect_settings()
...
func apply_effect_settings() -> void:
	_reduce = Settings.reduce_motion
	_low = Settings.low_effects
	queue_redraw()

func effect_counts() -> Dictionary:
	return {"slide": not _reduce, "glow": not _low}
```

### Note-path keep-out
**Source:** `tests/test_layout_keepout.gd:30-34, 59-78`; `src/ui/hud.gd:428-440`
**Apply to:** every HUD-level versus node (not board layers). Fixed-rect Controls are checked by rect; full-screen canvases need `keepout_shapes()`. Rects from D-26: panels x 24..376 y 216..584, killfeed x 1544..1896 y 216..400, socket 272,928,80,80.

### Palette-only colour
**Source:** `src/ui/palette.gd:1-4`, `Palette.alpha(c, a)`; `tests/test_contrast.gd:31-35`
**Apply to:** all `src/ui/**`. New tokens get a `# purpose` comment and a contrast row. Disruptor edge `WARNING_RED`, buff edge `SONAR`, duel pip `REWARD_GOLD`, own killfeed line `SONAR` bar + `TEXT_HI`.

### Glyphs instead of emoji
**Source:** `src/ui/ui_icons.gd:1-4, 9-12, 21-25` ("Oxanium has no arrow glyphs")
**Apply to:** killfeed separators, reward icons, medal icons: add names to `NAMES` and a `match` arm; `tests/test_ui_components.gd` enumerates `UiIcons.names()` - extend it.

### Song-time, never frame-time
**Source:** `src/core/autoplay.gd:1-3` doc ("presses and releases at the exact note times, never the frame time"); `lane_input.gd:47-48` (tick stamp first statement); `fake_time.gd` (injectable ticks)
**Apply to:** MatchSim, BotPlayer, TrainingDrone, VersusAutoplay, fire input. Views poll `conductor.song_time()` read-only (section_banner.gd:250-253).

### Pinned timing core
**Source:** `tools/check_timing_gate.ps1`
**Apply to:** every plan's verification step: `powershell -NoProfile -File tools/check_timing_gate.ps1` -> `TIMING GATE OK`. Only `judge_config.gd` moves (D-29), once.

### Run-scoped wiring and teardown
**Source:** `src/ui/gameplay.gd:87-103, 262-277`
**Apply to:** VersusController - everything under `_run_root` so restart frees all bots, channels and views with no stale connections.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `src/versus/match_sim.gd` (beat-boundary collision / bounty / shield resolution) | service | event-driven | No multi-player rules engine exists; only the "drain everything due up to t" loop shape is reusable (InputJudge.tick, Autoplay.update). Use RESEARCH Pattern 2 + D-01..D-25. |
| `src/ui/versus/ink_cloud_layer.gd` (occluder band with receptors redrawn on top) | component | streaming | No layer currently hides part of the board; HighwayNotes gives the layer/binding shape only. Use D-13 geometry and UI-SPEC. |

## Metadata

**Analog search scope:** `src/core`, `src/input`, `src/ui` (+ `gauges`, `fx`), `src/audio`, `src/autoload`, `src/content`, `scenes`, `tests` (+ `helpers`), `tools` (`check_timing_gate.ps1`, `run_tests.ps1`, `playtest/`)
**Files scanned:** ~45 read or grepped
**Pattern extraction date:** 2026-10-15
