---
phase: 05-polish-packaging
plan: 02
subsystem: audio
tags: [audio, downbeat, muffle, creaks, tdd, pure]
requires: [BeatClock.beats_between]
provides: [DownbeatScheduler, HullAudioCurve, CreakDirector]
affects: [05-04 DiveAudio]
tech-stack:
  added: []
  patterns: [lead-silence ping offset, log-space one-pole smoothing, seeded RNG director]
key-files:
  created:
    - src/audio/downbeat_scheduler.gd
    - src/audio/hull_audio_curve.gd
    - src/audio/creak_director.gd
    - tests/test_downbeat_scheduler.gd
    - tests/test_hull_audio_curve.gd
    - tests/test_creak_director.gd
  modified: []
decisions:
  - "DownbeatScheduler.reset() never re-pings a bar at or before the last fired bar, even after a backward seek"
  - "CreakDirector.reset() reseeds the RNG, so it returns to the freshly constructed state"
  - "CreakDirector._init's first parameter is named rng_seed (not seed) to avoid shadowing the global seed(); positional call is unchanged"
metrics:
  completed: 2026-10-21
  tasks: 2
  tests: 33
---

# Phase 5 Plan 02: Downbeat scheduler, hull audio curves and creak director Summary

The three pure audio-logic classes behind AV-03. DownbeatScheduler times sonar pings with the Conductor's resume lead (`head = song_t + latency + offset + to_next_mix`, `from_position = lead - (bar - head)`). HullAudioCurve maps hull to a log low-pass cutoff (20 kHz down to a 1.5 kHz floor below hull 75) and to the creak curves. CreakDirector is a seeded creak director with a shared 0.8 s cooldown. All three are RefCounted, have no nodes and make no AudioServer calls.

## Contract (implemented as in the plan interfaces block)

```
DownbeatScheduler (RefCounted)
  LATE_SKIP_SEC = 0.03, WINDOW_SEC = 4.0, var every_n_bars := 1
  _init(tempo_map: Array, time_sigs: Array, lead_sec := 0.15)
  tick(song_t, latency, offset, to_next_mix) -> float   # from_position in [0, lead] or -1.0
  reset(song_t, latency := 0, offset := 0, to_next_mix := 0)
  next_bar_time() -> float  # INF when none
  fired_count() -> int
HullAudioCurve (static)
  MUFFLE_START 75, OPEN_HZ 20000, FLOOR_HZ 1500, SMOOTH_TAU 0.25, SLAM_SEC 0.3
  cutoff_for_hull, muffle_active, smooth_cutoff(cur, tgt, dt, tau := SMOOTH_TAU),
  creak_interval_for_hull (INF at >= 60), creak_db_for_hull, damage_creak_chance
CreakDirector (RefCounted)
  COOLDOWN_SEC = 0.8
  _init(rng_seed: int, variants := 4)
  on_hull_changed(hull, delta, song_t) -> {} | {variant, db, pitch}
  tick(hull, song_t) -> {} | {variant, db, pitch}
  reset()
```

## Notes for 05-04 (DiveAudio wiring)

- Call `tick()` only while playing and not paused. On `resumed` or after a seek, call `reset(song_t, latency, offset, to_next_mix)`. When `tick()` returns `fp >= 0`, call `player.play(fp)` on the ping (its sample has `lead` seconds of leading silence, so lead must match the 05-01 ping's lead, 0.15 s by default).
- Inputs: `conductor.song_time()`, `conductor.output_latency()`, `conductor.audio_offset()`, `AudioServer.get_time_to_next_mix()`.
- The scheduler starts at the first bar at time >= 0, so the count-in never pings. Starting at song_t = 0 exactly makes the bar at 0 late (r = -0.035), so it is skipped. Gameplay always runs a count-in, so this does not happen in play.
- Damage creaks are already +3 dB (`creak_db_for_hull(hull) + 3`). The `db` in a creak result is absolute: set `volume_db = db` and `pitch_scale = pitch`, and use `variant` to index the four 05-01 creak variants.
- Muffle: when `muffle_active(hull)`, enable the LPF and each frame do `cutoff = smooth_cutoff(cutoff, cutoff_for_hull(hull), delta)`. Implement the SLAM_SEC wreck ramp in the node; the curve class only provides the constant.
- After a backward seek, the scheduler stays silent until it passes the last fired bar (it never double-pings). For a full restart, build a new DownbeatScheduler.

## Tasks / Commits

| Task | Commit | Description |
|------|--------|-------------|
| RED (both tasks) | 48191ee | test(05-02): failing tests for the three classes (they failed to parse: classes missing) |
| GREEN (both tasks) | 3ab1240 | feat(05-02): the three classes plus all .gd.uid files |

No refactor was needed. The suites: test_downbeat_scheduler 11/11, test_hull_audio_curve 10/10 and test_creak_director 12/12 pass. TIMING GATE OK.

## Deviations from Plan

- The RED and GREEN commits each cover both plan tasks (one combined test commit and one combined feat commit), which matches the plan's TDD flow block.
- The `_init` parameter is named `rng_seed` instead of `seed`, because `seed` shadows a global function. Positional calls are unchanged.
- The 4/4 test simulates from song_t = -1 (count-in) to 19.5 s. Starting at exactly 0 with a 35 ms head makes bar 0 late-skipped by design. The expected count is still 10 bars (0..18).

## TDD Gate Compliance

The RED commit (48191ee test) comes before the GREEN commit (3ab1240 feat).

## Self-Check: PASSED
