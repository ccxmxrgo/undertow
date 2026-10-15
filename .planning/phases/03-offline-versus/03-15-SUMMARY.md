---
phase: 03-offline-versus
plan: 15
subsystem: ship-and-verify
tags: [gates, playtest, screenshots, performance, dist, uat]
requires: ["03-14"]
provides:
  - "Playtest scenario \"versus\" (UI-SPEC 11.8 shot set, 3-bot + Ink Cloud p95 capture with attribution)"
  - "make_uat_shots.gd --phase 03 (33-shot versus gallery)"
  - "Friend zip build/dist/UNDERTOW-playtest-v0.6.0.zip (local only, not published)"
  - "03-HUMAN-UAT.md with 12 pending tests, visual and performance follow-ups"
affects: [tools/playtest/playtest_driver.gd, tools/make_uat_shots.gd, tools/playtest/run_all.ps1, tools/dist.ps1, tools/dist/README.txt, tools/dist/TESTER-CHECKLIST.txt]
tech-stack:
  added: []
  patterns: ["harness forces payloads via MatchSim.inject_fire with a per-launch warhead_count", "process-order probe pair around Gameplay to time its _process"]
key-files:
  created:
    - .planning/phases/03-offline-versus/uat-shots/ (33 PNG)
    - .planning/phases/03-offline-versus/03-15-SUMMARY.md
  modified:
    - tools/playtest/playtest_driver.gd
    - tools/make_uat_shots.gd
    - tools/playtest/run_all.ps1
    - tools/dist.ps1
    - tools/dist/README.txt
    - tools/dist/TESTER-CHECKLIST.txt
    - .planning/phases/03-offline-versus/03-HUMAN-UAT.md
decisions:
  - "The versus p95 (5.22 ms) misses the 4.35 ms U-12 gate. It is recorded as a performance follow-up in 03-HUMAN-UAT.md; no src change in this plan."
  - "To shoot each disruptor, the harness sets warhead_count to 0 for that launch, because the autoplay human would otherwise reflect it at once. Sonar Jam + warheads and the REFLECTED alert keep the real count."
  - "The final human-verify checkpoint is recorded as pending (03-HUMAN-UAT.md test 12) and does not block the phase."
metrics:
  duration: "~3 h (including a usage-limit pause)"
  completed: 2026-10-15
  tasks: 3
  files: 7 (+33 PNG)
---

# Phase 3 Plan 15: Final gates, versus playtest, v0.6.0 zip and UAT sheet Summary

This plan re-ran Phase 3's gates on the final tree and re-recorded the strong-bot reward table. A new windowed playtest scenario ("versus") plays a real 3-Veteran-bot match from the main menu. It forces every disruptor onto the human, shoots the UI-SPEC 11.8 set and measures the 3-bot + Ink Cloud frame cost. It also built the v0.6.0 friend zip with README and checklist updates and wrote the human UAT sheet.

## Gates

- **Full gdUnit suite:** 1693 test cases, 0 errors, **1 failure**. The one failure is `tests/test_bot_frequency.gd::test_four_veteran_bots_earn_2_to_4_rewards_on_every_bundled_song` (HRT seat 3 = 5 rewards). It is the known red test pending user decision D-UAT-01, and it was not loosened, skipped or retuned. No flaky failures in this run.
- **`tools/check_timing_gate.ps1`:** TIMING GATE OK. It ran at the start, after the zip, and at the end. conductor, clock_model, input_judge, hull_score and judge_config were not touched.

## Reward frequency (spec req 8, re-run on the final tree)

`reward_threshold_ratio` 0.120, Veteran sigma 33 ms, lapse 1.5%, 4 Veteran bots:

| song | notes | threshold | rewards per bot |
|------|-------|-----------|-----------------|
| synth_wave_april | 416 | 50 | 3, 3, 3, 4 |
| space_synth_wave | 569 | 69 | 2, 3, 4, 2 |
| sea_shanty_2 | 471 | 57 | 3, 4, 2, 4 |
| hrt | 394 | 48 | 4, 3, 3, **5** |
| invisible | 440 | 53 | 4, 4, 2, 2 |

This is identical to 03-07. Per-song means are 3.25 / 2.75 / 3.25 / 3.75 / 3.0. The decision is still D-UAT-01.

## Versus playtest scenario (`run_all.ps1 -Scenarios versus`, windowed, real audio, 1920x1080)

Flow:
1. Main menu, then Versus Bots, then match setup. The temp settings give 3 rivals, VETERAN, space_synth_wave, Expert.
2. Start Match (Enter on the Start row). The human is driven by `VersusController.test_autoplay_human`, which is reset afterwards.
3. Each of the 6 disruptors is injected from a rival seat, and the scenario checks that it landed. It shoots x1 Full, x3 Full and x1 Low. Scroll speed and Low effects change only through the redirected temp settings.
4. Extras:
   - Crossed Wires mid-slide and settled.
   - Ink Cloud timed so that a sustain is held.
   - Sonar Jam with live warheads, then REFLECTED.
   - Decoy, then ABSORBED.
   - A same-beat collision, then COLLISION.
   - Space fires the human's held reward. Bots trade torpedoes, giving 4 killfeed lines.
   - H locks a target.
   - Solo Duel live at 136 s.
   - Versus results with medals ("YOU WIN", 3 rows with medals).
5. In-place Rematch (new seed, checked), then the frame capture.
6. Solo Dive, then Song Select, then F3 twice for the training stepper shot.

The real user data proof passed: settings.cfg, scores.cfg and drift_log are unchanged, and songs/ is unchanged.

All of the scenario's own checks pass **except the U-12 p95 gate**, so the scenario reports FAIL on purpose. Shots were copied with `make_uat_shots.gd -- --phase 03`, 33/33.

### Frame cost (UI-SPEC 12, 3 bots + Ink Cloud, densest 30 s of space_synth_wave from 35.9 s, uncapped)

| Capture | p50 ms | p95 ms |
|---|---|---|
| Solo baseline (scenario perf, sea_shanty_2 Full, same session) | 2.66 | 2.95 |
| **Versus 3 Veteran bots + Ink Cloud, Full** (n = 6255) | **4.79** | **5.22 > 4.35 gate** |
| VersusHud hidden and not processing | 3.97 | 4.28 |
| Ink layers hidden | 4.91 | 5.34 |
| Socket, readout and chips hidden | 4.91 | 5.32 |
| Versus Low effects | 3.60 | 4.08 |
| **Gameplay._process = VersusController.pre_tick + judge.tick + VersusController.update** | 0.18 | **0.28** (p99 0.58, max 2.0) |

Ink Cloud was visible on 47-73% of captured frames across runs. D-07 immunity (1 bar) plus the 1-beat flight caps it near 60-70%. Render CPU p95 is 0.57 ms and GPU p95 0.63 ms.

Conclusion: the controller with 3 bots is cheap (0.28 ms p95). The miss comes from per-frame view work, about 1 ms of it in VersusHud. This is recorded as a performance follow-up in 03-HUMAN-UAT.md.

### Screenshot review (against UI-SPEC 6-9, 11.8)

| Shot | Finding |
|---|---|
| versus_match_setup | Matches 9.2: rows, tiles, roster YOU + 3 VETERAN, "REWARD EVERY 69 PERFECTS", focus on Start Match. OK |
| versus_alert_incoming | INCOMING · NARWHAL, "CANNOT BE REFLECTED" (no warheads), CROSSED WIRES, red edge. OK |
| versus_alert_active | ACTIVE · ORCA, "3 BARS LEFT", BOUNTY ON YOU chip, killfeed victim line with red bar. OK |
| versus_crossed_mid / _settled / crossed_wires_x1/x3/low | Slide plus swap-guide arc under the receptors; settled lanes 3 and 4 swapped with dashed edges; lane numbers stay at their screen positions (D-10). **V-3:** hit bursts appear at the original lane x after the swap (03-08 open item confirmed) |
| versus_ghost_notes_* | Hollow dashed ghosts, readable in Low and at 3x. OK |
| versus_ink_cloud_* / versus_ink_sustain | Opaque band, receptors and lane numbers on top, press fill on the held sustain lane. **V-5:** a stray popup letter ("T") shows past the band's right edge |
| versus_pressure_crack_* | Faster scroll is visible. **V-4:** the rail tint reads pale white, not red |
| versus_sonar_jam_* | Plain grey circles, lane strips keep their tint. OK in Low and at 3x |
| versus_depth_charge_* | Solid gems with the dark charge mark. OK |
| versus_jam_warheads | Warhead rings plus up-chevrons, "REFLECT 1/4"; jam at 50% (**V-6**, by design) |
| versus_alert_reflected / absorbed | "REFLECTED / BACK TO NARWHAL"; "DECOY ABSORBED / GHOST NOTES"; killfeed "YOU [shield] blocked". OK |
| versus_alert_collision | **V-1:** headline "BOTH TORPEDOES DESTR..." clipped at 528 px |
| versus_killfeed_4 | 4 lines, newest still sliding in (**V-8**, cosmetic); a fired Ballast shows the "HULL +25" chip |
| versus_panels_bounty_target | Reticle and caret on NARWHAL, "TARGET NARWHAL", threat glyphs on the panels; the bounty is on YOU (chip), so no gold panel glyph. **V-2:** "BARRA..." truncated (spec says 9 chars fit) |
| versus_duel_live | Banner "SOLO DUEL · YOU 100% · LEADER BARRACUDA 87%", panels "SOLO nn%". OK |
| versus_results_medals | Places, depth, accuracy, landed/reflected, medals with legend, seed, NOT RECORDED. OK |
| solo_training_stepper | CROSSED WIRES stepper with description. **V-7:** the description crowds the header |

Nothing is on the note path. Every disruptor is readable in Low effects. V-1..V-8 are in 03-HUMAN-UAT.md as visual follow-ups (non-blocking).

## Friend zip

- `build/dist/UNDERTOW-playtest-v0.6.0.zip`: 65,811,213 bytes (62.76 MB), sha256 `9d4a31188b47b01993083ee8438fd80f60ad98ca7ac6a1e26e0430c8c7c093a2`.
- It has exactly 3 entries: UNDERTOW.exe (129.47 MB), README.txt and TESTER-CHECKLIST.txt.
- The unzipped exe printed **BUNDLED_OK 20**.
- It was built locally only. Nothing was published or uploaded.
- README: v0.6.0 title and intro, Fire (Space / pad A) and Switch target (H / pad Y) controls, Solo Dive copy, WHAT'S NEW IN v0.6.0. Checklist: v0.6.0 header, Solo Dive line, a "4d. VERSUS (new in v0.6.0)" block. Both are plain ASCII.

## Deviations from Plan

1. **[Rule 3] run_all.ps1 changed** (not in files_modified). "versus" is added to the default scenario list with a 510 s watchdog, so the scenario runs with the user-data backup and proof like the others.
2. **Harness manipulations (documented in code).** Payloads are forced through `MatchSim.inject_fire` with `warhead_count = 0` for that launch only. The Decoy is armed by setting `decoy_until` and emitting BUFF_APPLIED without `meter.use()`, so the human keeps its held reward. Nothing in src was changed.
3. **Diagnostic additions beyond the plan.** The scenario also times Gameplay._process (a probe pair around Gameplay) and takes 6 s attribution captures with view groups hidden, plus Low effects. These give the p95 follow-up something to act on. A solo `perf` run was taken in the same session as the baseline.
4. **README "WHAT'S NEW IN v0.6.0" appears twice.** The done criterion says 1, but the plan's own intro sentence "(see WHAT'S NEW IN v0.6.0)" adds the second match, the same pattern as v0.5.4. "Practice Dive" remains only in the plan-mandated WHAT'S NEW bullet and the historical v0.2 note.
5. **Shot list is 33, not 34.** 18 disruptor shots plus the 15 named extras in the plan.
6. **Song choice.** space_synth_wave (192 s, solo at 133 s) instead of an arbitrary bundled song, so that all forced payloads fit before the Solo Duel.
7. **[Rule 1] Polish menu edge-pixel check.** The 9-item menu (03-05) moved Start Dive to y 392, so the hard-coded y 416..480 band failed. It now reads the button's own rect (commit c910eef). After this fix, scenarios polish and pad both PASS, including every Solo Dive / Versus Bots order check.
8. **Not fixed (plan says record, not fix):** the U-12 p95 miss and V-1..V-8.

## Pending UAT / human actions

These are all in `.planning/phases/03-offline-versus/03-HUMAN-UAT.md` (status pending):
- **D-UAT-01:** the strong-bot reward frequency criterion (decides the red test).
1. Full versus match vs 3 Veteran bots on Expert: fun and fairness.
2. Telegraph: alert slot vs edge flash, ping and rings (open question 1).
3. Decoy visible on rival panels? (open question 2)
4. Crossed Wires input reading, position (D-10) vs colour (open question 3), and slide feel.
5. Rival held-reward icons distracting? (open question 4)
6. Ballast Patch 25%.
7. Readability of every disruptor at 1x and 3x, Full and Low.
8. Bot tiers distinct, and the medium-player reward rate on Expert (Pitfall 11).
9. Slower hull repair (perfect_regen 0.25) feel.
10. Friend PC test of zip v0.6.0.
11. Visual follow-ups V-1..V-8 and the p95 result.
12. **Final checkpoint of 03-15 (human-verify, non-blocking):** recorded as pending with the how-to-verify steps.
- Also from 03-14: the error blip volume and the in-place Rematch flow (checked inside test 12).

## Known Stubs

None.

## Threat Flags

None. T-03-37: the allow-list kept the zip at exactly 3 entries. T-03-38: the scenario uses the temp settings and scores, and the run_all proof shows the real files unchanged. T-03-40: TIMING GATE OK on the shipped tree.

## Commits

- dcaddfd test(03-15): versus playtest scenario, phase 03 UAT shot gallery and Solo Dive menu checks
- 752c19d chore(03-15): v0.6.0 friend zip, README WHAT'S NEW, VERSUS checklist and phase 3 UAT sheet
- c910eef fix(03-15): polish menu edge-pixel check reads the focused button's own rect

## Notes

- `tests/zz_sweep_0307_scratch.gd` (+ .uid) is still untracked and was not committed.
- The export left `.import` churn and `default_bus_layout.tres` modified. Neither was committed.

## Self-Check: PASSED

- FOUND: playtest_driver.gd, make_uat_shots.gd, run_all.ps1, dist.ps1, README.txt, TESTER-CHECKLIST.txt, 03-HUMAN-UAT.md, 33 uat-shots PNGs, build/dist/UNDERTOW-playtest-v0.6.0.zip
- FOUND on origin/main: dcaddfd, 752c19d, c910eef
