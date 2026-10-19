---
phase: 03-offline-versus
fixed_at: 2026-10-20T00:30:00Z
review_path: .planning/phases/03-offline-versus/03-REVIEW.md
iteration: 1
findings_in_scope: 17
fixed: 17
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-10-20
**Source review:** .planning/phases/03-offline-versus/03-REVIEW.md
**Iteration:** 1

**Scope:** CR-01, CR-02, WR-01..WR-12 (with the visual follow-ups V-1, V-2, V-3, V-4, V-5, V-7 and the perf items WR-08/09/10), plus the cheap info items IN-01, IN-03 and IN-06.

**Summary:**
- Findings in scope: 17
- Fixed: 17 (5 of them need human verification, marked below)
- Skipped: 0
- Not in scope, left open: IN-02 (static test seam), IN-04 (prize meter progress), IN-05 (collision stamp), IN-07 (V-6 and V-8 are by design), and the `BotProfile.effective_for` part of IN-06 (see that section).

Gates on the final tree:
- Full gdUnit suite: 1727 test cases, 0 errors, 1 failure. The failure is the known red `test_bot_frequency.gd` (HRT seat 3 = 5 rewards, D-UAT-01). It is unchanged and was not touched.
- `tools/check_timing_gate.ps1`: TIMING GATE OK, before and after the zip. conductor, clock_model, input_judge, hull_score and judge_config were not edited.
- `tools/dist.ps1`: zip rebuilt, BUNDLED_OK 20 (see "Friend zip").

## Performance (versus playtest, `run_all.ps1 -Scenarios versus`)

The capture is the same as 03-15: 3 Veteran bots plus a forced Ink Cloud, the densest 30 s of space_synth_wave from 35.9 s, uncapped, windowed, 1920x1080. All runs below come from the same session on the same machine.

| Tree | p50 ms | p95 ms | VersusHud hidden p95 | Low effects p95 | Ink on frames |
|---|---|---|---|---|---|
| 03-15 record (earlier session) | 4.79 | 5.22 | 4.28 | 4.08 | 47-73% |
| Pre-fix commit aeda1d6 (temporary worktree) | 4.77 | **5.32** | 4.39 | 4.33 | 73% |
| After CR/WR-01..05, before the perf fixes | 4.87 | 5.41 | 4.40 | 4.27 | 34% |
| After WR-06..10 and IN-06 | 4.12 | 4.56 | 4.26 | 3.13 | 35% |
| Same tree, instrumented diagnostic run | 3.89 | 4.36 | 4.04 | 2.86 | 73% |
| Final tree (with the alert split and breathing throttle), run 1 | 4.00 | 4.45 | 3.99 | 3.00 | 42% |
| **Final tree, run 2** | **3.68** | **4.18 (gate PASS, scenario PASS)** | 4.01 | 2.79 | 46% |

Result: p95 went from 5.32 ms to 4.18-4.45 ms on the final tree, a gain of about 0.9-1.1 ms. VersusHud now costs about 0.2-0.4 ms, down from about 1 ms. Gameplay._process (controller with the new time-ordered stepping) stays at 0.26-0.32 ms p95.

The 4.35 ms gate is borderline. It passed in 1 of the 2 final runs, and run-to-run noise is about ±0.15 ms. What remains:
- Most of the remaining gap is Full-effects work outside VersusHud. Low effects is still 1.3-1.6 ms cheaper. Render CPU and GPU p95 are only about 0.6 ms each, so the cost is main-thread work: particles, glow shadows and other per-frame scripts. Review perf item 5 (one shared glow texture instead of per-box StyleBoxFlat shadows) is the next candidate. Profiling the Full-only effects would come after that.
- **Measurement caveat:** the playtest's own "Ink Cloud visible on >= 45% of frames" check varied from 34% to 73% between runs. The instrumented run dumped the human's payload log and showed the keeper working as designed: regular 8 s inks, 2 s immunity and same-beat races won by the keeper. A live Gameplay probe through the controller also gave 68-73%. The low-share runs probably come from bot disruptors occupying the human between inks; the harness injects ink with `sim.inject_fire` at frame time, outside the controller's time ordering. Low-share runs carry less ink drawing, so their p95 is slightly optimistic. The two 73%-share runs gave 4.36 ms on the perf tree and 5.32 ms pre-fix.

## Fixed Issues

### CR-01: Bounty claim is silently lost when the first warhead is judged before the torpedo arrives
**Files modified:** `src/versus/match_sim.gd`, `tests/test_match_sim_bounty.gd`
**Commit:** e4c640c
**Applied fix:** `_on_landed_bounty` now decides from the live `_heads` state instead of the launch snapshot. Two regression tests cover it: an early non-Perfect first warhead claims on arrival, and all warheads cleared early drops the claim. The first test was confirmed to fail without the fix.
**Status:** fixed: requires human verification (logic)

### CR-02: The SubRig lambda reference cycle leaks the whole match
**Files modified:** `src/versus/sub_rig.gd`, `tests/test_sub_rig.gd`
**Commit:** affce8c
**Applied fix:** `hull_changed` and `score_changed` now connect to method callables. A weakref test drops a whole rig and match graph in a helper and asserts that the rig, sim, hull and judge are freed; it fails without the fix. The headless "ObjectDB instances were leaked at exit" warning (358 in the determinism suite before) is gone. The remaining "19 resources still in use at exit" line is pre-existing gdUnit/static-cache noise and was also present at aeda1d6.

### WR-01: Live versus is not frame-rate independent
**Files modified:** `src/versus/sub_rig.gd`, `src/ui/versus/versus_controller.gd`, `src/ui/gameplay.gd`, `src/input/lane_input.gd`, `tests/test_sub_rig.gd`, `tests/test_versus_controller_determinism.gd` (+ .uid)
**Commit:** 71e20d5
**Applied fix:**
1. Late misses (base notes and Depth Charge) are stamped at their deadline (note + good window), never at tick or frame time.
2. VersusController mirrors MatchHarness and steps everything in global song-time order: a `TICK_S` judge-tick grid for every rig (then referee and channel), the autoplay human (reusing `MatchHarness._AutoActor`), the bots by seat and the drone. Gameplay no longer ticks the versus judge at frame time.
3. Real human presses and releases (`LaneInput.press_fn` / `release_fn` route to `human_press` / `human_release`), plus `fire` and `cycle_target`, first advance every rival to their own song time. Extra judgments, strays, ghost hits and failures are therefore stamped at the press time.

New tests drive a real VersusController like `Gameplay._process`:
- identical event logs at 30, 144 and 1000 fps
- a log equal to `MatchHarness.run` for the same seed
- no timestamp regression larger than one grid step

**Status:** fixed: requires human verification (logic, and the feel of live input through the new routing)

### WR-02: A reflected payload's ease-out and Crossed Wires remap end one beat late
**Files modified:** `src/versus/payload_stack.gd`, `src/versus/sub_rig.gd`, `tests/test_sub_rig.gd`
**Commit:** aa81e14
**Applied fix:** New `PayloadStack.end_at(id, t)` ends on the referee's end beat, and SubRig uses it for "reflected" PAYLOAD_END. Tests check that the ink is below 1 at te + 0.75 beat and 0 at te + 1 beat, and that the Crossed Wires input returns to identity one beat after the end.
**Status:** fixed: requires human verification (logic)

### WR-03: Crossed Wires remap can swallow a real press
**Files modified:** `src/input/lane_input.gd`, `tests/test_lane_input.gd`
**Commit:** 558450d
**Applied fix:** Every press edge now reaches the judge; the holder count only gates the release. The old "never double press" test was renamed and updated to match. A new test shows that the second key on a held lane hits the next note Perfect.
**Status:** fixed: requires human verification (logic)

### WR-04 (V-3): Hit bursts, sparks and popups use the unswapped lane x under Crossed Wires
**Files modified:** `src/ui/fx/fx_layer.gd`, `src/ui/feedback.gd`, `src/ui/gameplay.gd`, `tests/test_phase3_review_fixes.gd` (+ .uid)
**Commit:** 219ed94
**Applied fix:** `FxLayer.lane_point` and `Feedback.lane_x` use `Highway.receptor_center` for the judged lane, and held sustain emitters follow the receptor every frame. Gameplay gives Feedback the highway.

### WR-05 (V-5): Ink Cloud lets judgment popups show past the band edge
**Files modified:** `src/ui/feedback.gd`, `tests/test_phase3_review_fixes.gd`
**Commit:** 5a70816
**Applied fix:** This is the review's first option. `Feedback.ink_fade()` fades popups by 1 - ink while the popup row is inside the inked depth range, so the read-ahead challenge stays intact.

### WR-06 (V-2): Periscope callsign width budget ignores the +2 px glyph spacing
**Files modified:** `src/ui/versus/periscope_panel.gd`, `tests/test_periscope_panel.gd`, `tests/test_phase3_review_fixes.gd`, `03-UI-SPEC.md` (row 6.2 Callsign)
**Commit:** 70eb098
**Applied fix:** `call_max()` runs to 8 px left of the measured place text. The truncated callsign is cached and recomputed only on a name, bounty or place change. "BARRACUDA" now fits next to "2ND", as the refreshed `versus_panels_bounty_target` shot shows.

### WR-07 (V-1): The collision headline is longer than the alert's headline box
**Files modified:** `src/ui/versus/incoming_alert.gd`, `tests/test_versus_alerts.gd`, `tests/test_phase3_review_fixes.gd`, `03-UI-SPEC.md` (row 340 and the copy table)
**Commit:** 1e205e5
**Applied fix:** The headline is now "BOTH DESTROYED". The caption "HEAD-ON COLLISION" keeps the torpedo context, in the same terse UPPERCASE tone as the rest of the alert copy. Alert texts are fitted through a small cache instead of `truncate_px` every frame.

### WR-08: PeriscopePanel redraws all of its chrome every frame (perf, top item)
**Files modified:** `src/ui/versus/periscope_panel.gd`, `tests/test_phase3_review_fixes.gd`
**Commit:** 744b3c6
**Applied fix:**
- The static layer (glass box with glow, outline, brackets, meter, held reward, text, hull) redraws on these triggers only:
  - events
  - targeting
  - a drone-status change
  - a 10 Hz live Solo Duel percent change
  - while an edge or damage flash runs
- A `Node2D` child draws the sweep, blips and threat block, and redraws per frame only while they move.
- The 16 dashes are one cached `draw_multiline`, and the outline is cached.
- `get` / `set` reflection is replaced by direct fields, and blips are removed in place.

### WR-09: IncomingAlert and EventBanner allocate a StyleBoxFlat per draw and rebuild texts per frame
**Files modified:** `src/ui/versus/incoming_alert.gd`, `src/ui/versus/event_banner.gd`, `tests/test_phase3_review_fixes.gd`
**Commits:** 07f958f, e34b3aa (follow-up)
**Applied fix:**
- Both views cache their style boxes per (state, Low effects).
- The alert refreshes texts only when the bar count changes and never redraws while hidden.
- The banner re-reads live duel percentages at 10 Hz, re-records its panel only on content change (or for the live duel line), caches text fitting and measuring, and redraws the vignette layer only while it runs.
- Follow-up: the alert's ring, burst and duration line moved to a dynamic child, so the glass panel is not re-recorded every frame while a payload is active (about 70% of capture frames).

### WR-10: Idle views still call queue_redraw every frame; Killfeed re-measures text every frame
**Files modified:** `src/ui/versus/killfeed.gd`, `reward_socket.gd`, `edge_flash.gd`, `ink_cloud_layer.gd`, `ink_top_layer.gd`, `status_chips.gd`, `tests/test_phase3_review_fixes.gd`
**Commits:** 2ec71f2, 3e8faeb (follow-up)
**Applied fix:**
- Killfeed redraws only while a line slides, glides or fades, and segment offsets are measured once per line.
- RewardSocket redraws only while animating. Follow-up: the breath redraws only on a 1/64 alpha step, about 24 times per second.
- EdgeFlash and the ink layers redraw only while visible, plus one clearing frame.
- InkTopLayer no longer allocates its debug Dictionary per draw.
- StatusChips rebuild a countdown chip only when its bar count changes.

### WR-11 (V-4): The Pressure Crack rail tint blends to pink-grey instead of red
**Files modified:** `src/ui/highway.gd`, `tests/test_visual_sync.gd`, `03-UI-SPEC.md` (7.5)
**Commit:** 757451e
**Applied fix:** `rail_color = SONAR.lerp(WARNING_RED, k)`: full red at the Pressure Crack peak, and a half blend for Groan. Palette colours only.

### WR-12 (V-7): The Solo Dive training description sits 24 px above the stepper caption
**Files modified:** `src/ui/song_select.gd`, `tests/test_phase3_review_fixes.gd`, `03-UI-SPEC.md` (8.2 Description row)
**Commit:** a15635d
**Applied fix:** The description now draws at `TRAINING_DESC_BASELINE` 728, which is 8 px higher. The stepper and its keep-out and focus rects are unchanged.

### IN-01: The `ghost_resets_meter` tunable does nothing
**Files modified:** `src/versus/match_sim.gd`, `src/versus/sub_rig.gd`, `tests/test_sub_rig.gd`
**Commit:** fc2662c
**Applied fix:** The flag is wired rather than removed: `SubRig._on_ghost_hit` calls `MatchSim.on_ghost_hit`, which resets the meter only when the flag is on. The CONTEXT default stays off, so a ghost hit does not reset the meter. Tests cover both settings.

### IN-03: `approach_s` goes stale if the scroll speed changes mid-match
**Files modified:** `src/ui/versus/versus_controller.gd`, `tests/test_versus_controller_determinism.gd`
**Commit:** 43bc9ca
**Applied fix:** The controller refreshes `human_rig.approach_s` on `Settings.settings_changed`.

### IN-06: Per-frame / per-note allocation outside VersusHud (Highway and PayloadStack parts)
**Files modified:** `src/ui/highway.gd`, `src/versus/payload_stack.gd`, `tests/test_phase3_review_fixes.gd`
**Commit:** ad51bda
**Applied fix:**
- Highway rebuilds its strips once per frame and compares columns in place, with no per-frame key allocation.
- `PayloadStack._beat` is memoized on the last song time, so the dozen per-frame queries share one tempo walk. It is a pure function of t.
- **Not done:** the `BotProfile.effective_for` cache. It runs about 3 times per second per bot, and a per-reward cache would serve stale values whenever a profile's exported fields change, so the risk was not worth it.

## Skipped Issues

None in scope.

## Other changes and notes

- **UAT shots:** `.planning/phases/03-offline-versus/uat-shots/` (33) were refreshed from the passing run (`make_uat_shots.gd -- --phase 03`). The collision headline, BARRACUDA callsign, red Pressure Crack rail and training description were checked by eye.
- **Friend zip:** `build/dist/UNDERTOW-playtest-v0.6.0.zip` was rebuilt. It is 65,821,334 bytes, sha256 `8bb56f40a926de26aa653c438acc54d49922720d89434869f406ddd7cd75402e`, has 3 entries and printed BUNDLED_OK 20. 03-15-SUMMARY was updated with the new hash and size.
- **Real settings file:** during the IN-03 test development, one run used `Settings.set_scroll_speed`, which saves. It rewrote the real `user://settings.cfg` once with the values the test process had loaded from it, with scroll speed restored. The committed test assigns and emits directly and never saves.
- **Not committed:**
  - `tests/zz_sweep_0307_scratch.gd` (+ .uid)
  - `tests/zz_tmp_ink_probe.gd` (+ .uid), an emptied scratch probe; the delete was blocked, so it was emptied instead
  - `default_bus_layout.tres` and `*.import` churn
  - `build/` outputs
- **Not edited:** STATE.md, ROADMAP.md, and the five pinned timing files.

---

_Fixed: 2026-10-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
