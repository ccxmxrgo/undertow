---
phase: 05-polish-packaging
plan: 04
subsystem: audio
tags: [audio, sonar-ping, creaks, low-pass, settings, AV-03]
requires: ["05-01 AudioSynth.sfx_bank / PING_LEAD_SEC", "05-02 DownbeatScheduler / HullAudioCurve / CreakDirector"]
provides: ["class_name DiveAudio (gameplay node)", "Settings.sonar_pings / Settings.hull_sounds ([audio])", "Gameplay.dive_audio"]
affects: [src/ui/gameplay.gd, src/ui/settings_screen.gd, src/autoload/settings.gd, tools/playtest/playtest_driver.gd]
tech-stack:
  added: []
  patterns: ["runtime bus effect added on _enter_tree, removed by instance on _exit_tree", "lead-silence ping started with play(from_position)"]
key-files:
  created: [src/audio/dive_audio.gd, tests/test_dive_audio.gd]
  modified: [src/autoload/settings.gd, src/ui/settings_screen.gd, src/ui/gameplay.gd, tools/playtest/playtest_driver.gd, tests/test_settings_roundtrip.gd, tests/test_settings_online.gd]
decisions:
  - "Slam glide uses tau = SLAM_SEC / 4 (not / 3): the smoothing runs in log frequency, so / 3 is still 8 % above the floor at 0.35 s; / 4 reaches FLOOR_HZ * 1.05 at 0.30 s"
  - "LPF installed in _enter_tree (not _ready), so a re-parented node reinstalls symmetrically with the _exit_tree removal"
  - "A paused -> unpaused transition seen by step() also resets the scheduler (in addition to Conductor.resumed)"
metrics:
  duration: "~35 min"
  completed: 2026-10-21
---

# Phase 5 Plan 04: DiveAudio (pings, creaks, Music low-pass) Summary

DiveAudio is a gameplay node. It plays a lead-silence sonar ping on every bar using `play(from_position)`, plays seeded hull creaks chosen by CreakDirector, and owns one runtime AudioEffectLowPassFilter on bus Music. That filter follows the hull and slams to 1500 Hz on a wreck. Two Audio settings switch the feature off, and the playtest harness turns both off.

## What was built

- **src/audio/dive_audio.gd** (`class_name DiveAudio extends Node`)
  - API: `bind(conductor, chart, score)`, `set_live(on)`, `slam()`, `step(dt, song_t, latency, offset, to_next_mix, paused)`. Getters: `ping_count()`, `creak_count()`, `current_cutoff()`, `lpf_enabled()`, `slammed()`, `is_live()`, `static music_lpf_count()`.
  - `_process` calls `step()` with the Conductor's public values and `AudioServer.get_time_to_next_mix()`, and only does so once the node is bound.
  - It uses 2 ping players and 2 creak players on SFX (Master as a fallback). The streams come from `AudioSynth.sfx_bank()` in `_ready`.
  - The filter: `_enter_tree` first removes every LPF already on Music, then adds its own (12 dB, resonance 0.5, disabled). `_exit_tree` finds that filter by instance and removes it. The cutoff is written only when it moves by more than 0.5 %.
  - The node is not registered as an fx node (Pitfall 3).
- **Settings:** `sonar_pings` and `hull_sounds` are both on by default. They are saved in `[audio]`, read back through the typed `_bool()` (a wrong type falls back to true) and reset by `reset_defaults()`.
- **SettingsScreen:** two new PillToggle rows after SFX, "Sonar pings" and "Hull sounds", using `HINT_SONAR_PINGS` and `HINT_HULL_SOUNDS`. They are refreshed in `_refresh_all`.
- **Gameplay wiring** in gameplay.gd:
  - `start()` creates `dive_audio` right after `_run_root.add_child(conductor)`, then calls `bind(conductor, chart, score)`. When there is no audio stream it returns early, so `dive_audio` stays null.
  - `set_live(true)` is called at the end of `_begin_count_in` and `_begin_online`.
  - `_dive_audio_off()` (`set_live(false)`) is called from `_finish`, `_on_failed`, `_on_match_aborted` and `_on_host_left`.
  - `_teardown` sets the reference to null. Removing the run root fires `_exit_tree`, which removes the filter on retry, F4, rematch and every other exit.
- **Harness:** `isolate_settings()` sets `Settings.sonar_pings = false` and `Settings.hull_sounds = false`.

## Tests

- `test_dive_audio`: 18/18 pass. Covered:
  - Filter lifetime: added with the node, gone after free, two runs in a row, a stale filter removed, removal by instance after the indices shift, no filter on SFX or Master.
  - Hull follow and heal, slam, Hull sounds OFF.
  - Pings: 5 pings from -1 to 9 s at 120 bpm, none extra with a pause, none doubled after resume, none with Sonar pings OFF, none when not live, none after the song end, none when unbound.
  - Creaks: they play at hull 20 and stay silent at hull 90. The node is not in FX_GROUP.
  - Scene level: one filter with gameplay running, still one after `restart`, and none after `queue_free`.
- Green suites:

  | Suite | Result |
  |---|---|
  | test_settings_roundtrip | 19 |
  | test_settings | 25 |
  | test_settings_online | 9 |
  | test_gamepad_settings | 19 |
  | test_library_settings | 12 |
  | test_menu_flow | 44 |
  | test_gameplay_smoke | 13 |
  | test_pause_resume | 5 |
  | test_versus_gameplay | 12 |
  | test_online_gameplay | 18 |
  | test_versus_controller_determinism | 5 |
  | test_match_determinism | 4 |
  | test_match_sim_determinism | 2 |
  | test_effect_settings | 14 |
  | test_layout_keepout | 8 |

- TIMING GATE OK.

## Deviations from Plan

1. **[Rule 3 - Blocking] Settings vars landed in the Task 1 commit.** DiveAudio reads `Settings.sonar_pings` and `Settings.hull_sounds`, so settings.gd (vars, defaults, save, load) had to be committed with the node or the node would not compile.
2. **[Rule 1 - Bug] Slam tau.** The plan's `SLAM_SEC / 3.0` cannot meet "<= FLOOR_HZ * 1.05 within 0.35 s", because `smooth_cutoff` glides in log frequency (ln(20000/1500) * e^-3.5 gives 1.08x). The node now uses `SLAM_TAU = SLAM_SEC / 4` (1.048x at 0.30 s). The reasoning is in a comment on the constant.
3. **Row-order spec update (not a loosening) in tests/test_settings_online.gd.** That file was not in the plan's file list. The Audio section's last row is now "Hull sounds" instead of "SFX", so two assertions changed:
   - The title just before "Player name" is now "Hull sounds".
   - The D-pad Down walk now starts from `hull_sounds_button`.
   No count assertions in test_settings, test_gamepad_settings or test_menu_flow needed a change.
4. The filter is installed in `_enter_tree` rather than `_ready`, which keeps it symmetric with the `_exit_tree` removal. The behaviour is the same.

## Notes for 05-06

- `Gameplay.dive_audio` is created in `start()` right after the conductor. FrameWatch can sit next to it. DiveAudio itself does nothing per frame beyond the scheduler's 4 s refill and a throttled `cutoff_hz` write.
- The harness keeps pings and hull sounds off by default. A perf or align scenario that wants them must set `Settings.sonar_pings` and `Settings.hull_sounds` to true after `isolate_settings()`.
- The Song Select preview bus "Preview" sends to Music. The filter only exists while Gameplay is in the tree, so previews are never muffled.

## Known Stubs

None.

## Self-Check: PASSED
- FOUND: src/audio/dive_audio.gd, src/audio/dive_audio.gd.uid, tests/test_dive_audio.gd
- FOUND commits: 9ffd713, e2ecb3c, 3e63c97
