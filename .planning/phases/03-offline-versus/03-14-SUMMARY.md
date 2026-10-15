---
phase: 03-offline-versus
plan: 14
subsystem: versus-gameplay-wiring
tags: [versus, gameplay, hud, training, results, contracts]
requires: ["03-06", "03-07", "03-08", "03-09", "03-10", "03-11", "03-12", "03-13"]
provides:
  - VersusController (match wiring under Gameplay's run root)
  - VersusHud (rival/event view container with keepout_shapes)
  - Gameplay versus / Solo Dive training branch, fire + target input, wreck path, versus results, rematch
affects: [src/ui/gameplay.gd, tests/test_layout_keepout.gd, tests/test_effect_settings.gd]
tech-stack:
  added: []
  patterns: ["one-shot static launch record cleared in _ready", "controller pre_tick/update around judge.tick", "test seam static bool reset in after_test"]
key-files:
  created:
    - src/ui/versus/versus_controller.gd
    - src/ui/versus/versus_hud.gd
    - tests/test_versus_gameplay.gd
  modified:
    - src/ui/gameplay.gd
    - tests/test_layout_keepout.gd
    - tests/test_effect_settings.gd
decisions:
  - "Every Solo Dive (practice) runs through VersusController: training ON adds the drone, training OFF has zero rivals but keeps the meter, bag and buffs; a plain Start Dive keeps InputJudge/HullScore unchanged"
  - "Rematch rebuilds the match in place (match_setup = rematch(); restart) instead of reloading the scene, so the static Gameplay.pending_intro is never changed"
  - "The refusal error blip plays through the controller's own AudioStreamPlayer, because UiSounds is suppressed while Gameplay is RUNNING"
  - "test_effect_settings gains a PRESENT list for owners that must be registered but change only under Reduce motion (RewardPopup, TargetReadout, Killfeed, MatchSetupScreen)"
metrics:
  duration: "~1h"
  completed: 2026-10-15
  tasks: 3
  files: 8
---

# Phase 3 Plan 14: Versus Gameplay Wiring Summary

VersusController builds a live offline match under Gameplay's run root: the MatchSim referee, a LoopbackChannel, the human SubRig, 1 to 3 BotPlayers or the TrainingDrone, and every versus view. Gameplay gets the versus/training branch, Space/H fire and target input, the WRECK path in place of the FailScreen, and VersusResultsScreen (no records) with Rematch and Change Match. The keep-out and effect-settings contract suites now cover the whole versus HUD.

## What was built

- **VersusController** (`src/ui/versus/versus_controller.gd`)
  - `setup(gp, chart, jcfg, setup, drone_mode, autoplay)` follows MatchHarness. Seat 0 is "YOU". Bots get `MatchSetup.callsigns(seed, rivals)`, or the training run gets one DRONE seat.
  - The human rig uses `no_fail = training`. Versus is false and training is true; Settings.no_fail is never read. `approach_s = Trench.approach_for(Settings.scroll_speed)`. Bot seeds are `hash([seed, "bot", seat])`.
  - `bind_views(gp)`:
    - `highway.bind_versus`, `lane_input.payloads`, and `lane_released -> highway.on_lane_released`.
    - InkCloudLayer and InkTopLayer go in board_root after HighwayNotes.
    - RewardSocket and TargetReadout become Hud children.
    - StatusChips and VersusSfx are added under the controller.
    - VersusHud goes right after Hud: PeriscopeColumn, Killfeed, IncomingAlert, EventBanner, EdgeFlash, RewardPopup. The column and killfeed are skipped when training is OFF.
    - `hud.set_solo_dive(true)` is set in training. The Feedback ghost-hit and overclock hooks are wired, and the RewardPopup blocker is `streak_counter.popup_text() != ""`.
  - Per frame:
    - `pre_tick(t)` stamps the rig time and runs VersusAutoplay.
    - Gameplay then calls `judge.tick(t)`.
    - `update(t)` prunes the stack, then runs bots, the drone, `sim.update`, `channel.update`, status chips, the column (plus the drone's "NEXT IN n BARS" / "NEXT IN 1 BAR"), and alert/banner/edge-flash `observe`.
  - `fire(t)` plays the error blip only on FIRE_SHIELDED or FIRE_NO_TARGET and counts it in `error_blips`. `cycle_target(t)` cycles the target. `finish(t)` returns the VersusResultsScreen data: rows merged with name, landed and reflected; MedalRules medals; seed; last_standing_seat taken from the event log.
  - Static test seam: `VersusController.test_autoplay_human`.
- **VersusHud**: a full-screen IGNORE container. `keepout_shapes()` gathers its children's shapes, or their rects when a child has none.
- **Gameplay**
  - `MatchSetup.pending` is always cleared in `_ready`. It is used only when the mode is MODE_VERSUS and the launch is neither practice nor autoplay.
  - Versus and practice dives build through the controller (`judge`/`score` = VersusJudge/VersusHull, no `connect_judge`). Versus connects `score.failed` to `_on_versus_wreck`: `hud.set_wreck(true)`; the song and lane input keep going.
  - The `fire` and `target_cycle` actions are handled in `_unhandled_input` while running and unpaused, after pause handling. The time is taken first from `conductor.song_time_at(Time.get_ticks_usec())`.
  - `_finish` in versus never touches ScoreStore and shows VersusResultsScreen.
    - Rematch: `match_setup.rematch()` plus an in-place restart.
    - Change Match: `MatchSetup.pending = match_setup`, then go to match_setup.tscn.
    - Menu: go_to_menu.
  - `pause_menu.match_mode` is set before the first open. Restart Match reuses the same setup and seed.

## Tests

- `tests/test_versus_gameplay.gd`: 12 tests, all passing.
  - Full versus run with 3 bots: render order, VersusJudge, no ScoreStore file, results with 4 rows, one MATCH_END.
  - Fire with nothing held does nothing and plays no blip. Target cycle goes to LOCKED on seat 1. A held Ink Cloud queues a FIRE_QUEUED. A shielded rival gives a blip and keeps the reward.
  - Wreck: no FailScreen, the conductor keeps advancing, input stays enabled, the WRECK caption shows, IMPLODED is logged, and results come at the end.
  - Telegraph: the alert's first_visible_t equals launch_t, it is at least one beat before arrive_t, and the alert is on screen within one frame of the launch.
  - Training with the drone: DRONE panel with "NEXT IN ... BAR(S)", No-Fail survives hull 0, Solo Dive results, not eligible, no file. Training OFF: no column or killfeed, RewardSocket present.
  - A plain solo dive uses InputJudge.
  - Stale-record regression through `MainMenu.launch(false)` and `launch_practice()`. A pending record is ignored for autoplay and practice launches.
  - Rematch draws a new seed.
- `tests/test_layout_keepout.gd`: 2 new tests, 7/7 passing. Every versus element is in its largest state, the exact UI-SPEC 13 rects hold, and nothing intersects the keep-out polygon.
- `tests/test_effect_settings.gd`: new "versus", "match_setup" and "versus_results" contexts and REDUCE rows for every versus owner, 12/12 passing. No owner file needed a fix.
- Existing suites still pass: test_gameplay_smoke 13/13, test_intro_flow 12/12, test_pause_resume 5/5.
- **Full suite: 1693 test cases, 0 errors, 1 failure.** Everything passes except test_bot_frequency, which is waiting on D-UAT-01 (see 03-HUMAN-UAT.md) and was not changed.
- `tools/check_timing_gate.ps1`: **TIMING GATE OK**. conductor, clock_model, input_judge, hull_score and judge_config were not touched.

## Deviations from Plan

1. **[Rule 1 - Bug] Error blip player.** `UiSounds.play()` is suppressed while Gameplay is RUNNING, so the UI-SPEC 5.2 in-gameplay "error" exception would never sound. The controller owns an AudioStreamPlayer with `AudioSynth.make_ui_blip("error")` on the UiSounds bus.
2. **Rematch is rebuilt in place, not via a scene reload.** Reloading with `pending_intro = QUICK` would leave the static at QUICK for every later dive, because nothing in src resets it. In-place `restart()` gives the same clean `_run_root` rebuild with a QUICK intro.
3. **Telegraph assertion uses the event-stamped first-visible time.** Flight is exactly one beat (`torpedo_travel_beats = 1`). The frame that first shows the alert is always a few ms after `launch_t`, so "frame time <= arrive_t - 1 beat" cannot hold literally. The test checks `first_visible_t == launch_t`, `arrive_t - first_visible_t >= 1 beat`, and that the alert is on screen less than half a beat after the launch (per the 03-11 note).
4. **Practice stray timing.** LaneInput presses the VersusJudge directly, so the rig's `now` is refreshed by `pre_tick(t)` once per frame. Judgments stamp themselves with note time plus error (exact). Only stray reports to the referee can be up to one frame stale.
5. **TDD ordering.** Task 1 already included the fire/target handler, so Task 2's suite was committed as a single test commit that passed on its first run (no separate RED commit).
6. **test_effect_settings PRESENT list (Rule 2).** Reduce-only owners could not go into EXPECTED, which requires a Low-effects change. The PRESENT list still makes the test fail if one of them goes missing.

## Known Stubs

None.

## Threat Flags

None. T-03-33: versus rig no_fail is false and training is true, both tested. T-03-34: there is no ScoreStore call in the versus `_finish`, and training goes through the not-eligible Solo Dive path, both tested. T-03-35: everything lives under `_run_root`, and pending is one-shot, tested.

## Notes for 03-15

- Frame budget (T-03-36): with 3 bots, `VersusController.update` runs every frame after `judge.tick`. Profile it there.
- `VersusController.test_autoplay_human` is the seam for driving a whole versus match in a scene (reset it in after_test).
- FxLayer bursts and Feedback popups still use `Trench.hit_point(lane)` under Crossed Wires (03-08 note). This is not addressed here.
- UAT items: the killfeed condense fallback (03-10); the error blip volume in gameplay; the Rematch flow (in place, QUICK intro).
- `tests/zz_sweep_0307_scratch.gd` (+ .uid) is still an untracked leftover and was not committed.

## Commits

- dbf697b feat(03-14): VersusController, VersusHud and the Gameplay versus/training branch
- 231a5fc test(03-14): end-to-end versus gameplay suite
- bafbe21 test(03-14): keep-out and effect-settings contracts for the versus HUD

## Self-Check: PASSED

- FOUND: src/ui/versus/versus_controller.gd, src/ui/versus/versus_hud.gd, tests/test_versus_gameplay.gd (+ .uid sidecars)
- FOUND: dbf697b, 231a5fc, bafbe21 on origin/main
