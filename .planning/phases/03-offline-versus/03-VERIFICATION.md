---
phase: 03-offline-versus
verified: 2026-10-20T12:00:00Z
status: human_needed
score: 19/20 must-haves verified (1 uncertain: spec req 8 strong-bot frequency, pending D-UAT-01)
overrides_applied: 0
human_verification:
  - test: "D-UAT-01 decision: strong-bot reward frequency (03-SPEC req 8)"
    expected: "User picks option 1-4 in 03-HUMAN-UAT.md D-UAT-01; test_bot_frequency.gd is then aligned (or the red test is accepted as a known deviation)"
    why_human: "Spec acceptance criterion cannot be met per bot with any tested ratio/profile; changing the criterion is a design decision"
  - test: "Full versus match vs 3 Veteran bots (HUMAN-UAT tests 1, 2, 12)"
    expected: "Fun, fair, telegraph noticed before arrival, wreck path, results/medals, Rematch/Change Match/Menu work"
    why_human: "Feel, fairness and visual readability cannot be verified by grep or headless tests"
  - test: "Disruptor readability at 1x/3x, Full/Low (HUMAN-UAT test 7) and Crossed Wires input reading (test 4)"
    expected: "Every disruptor readable and survivable without mashing"
    why_human: "Visual perception (TORP-06 readability)"
  - test: "Review-fix logic needing human check: CR-01, WR-01 (live input routed through VersusController time ordering), WR-02, WR-03"
    expected: "Live presses feel identical to solo dive; reflected payloads end on the beat; Crossed Wires never swallows a press"
    why_human: "Input feel on real hardware"
  - test: "Versus p95 frame time vs U-12 gate 4.35 ms (borderline 4.18-4.45 ms on the final tree)"
    expected: "Accept the borderline result or plan a perf follow-up (shared glow texture, Full-only effects)"
    why_human: "Run-to-run noise (+-0.15 ms) straddles the gate; accept/fix is a product decision"
  - test: "Versus playtest 'Ink Cloud visible on >= 45% of frames' check is unreliable (34-73% between runs)"
    expected: "Decide whether to make the harness inject ink through the controller's time ordering so the perf capture is reproducible"
    why_human: "Measurement-tooling follow-up; the game logic itself was confirmed correct by the instrumented run"
  - test: "Friend PC test of v0.6.0 zip (HUMAN-UAT test 10)"
    expected: "Runs on a second PC; versus checklist filled in"
    why_human: "Needs a second machine"
---

# Phase 3: Offline Versus Verification Report

**Phase Goal:** Player can play a complete, fun, fair versus match against bot rivals, with the full torpedo and payload game working offline.
**Verified:** 2026-10-20
**Status:** human_needed
**Re-verification:** No, initial verification

## Gate results (run by the verifier)

| Gate | Command | Result |
|------|---------|--------|
| Timing gate | `powershell -NoProfile -File tools/check_timing_gate.ps1` | `TIMING GATE OK`, exit 0 |
| Full gdUnit suite | `tools/run_tests.ps1` (GODOT_BIN = 4.7.2 console) | 1726 test cases, 117/117 suites, 0 errors, **1 failure** (known red `test_bot_frequency.gd`: `hrt seat 3: 5`), 0 flaky. The three known alone-passing flakes (pause_overlay pause, review_fixes preroll, pack_installer update_app_only) all passed in this run. |
| Friend zip | `unzip -l build/dist/UNDERTOW-playtest-v0.6.0.zip` | 3 entries (README.txt, TESTER-CHECKLIST.txt, UNDERTOW.exe), 65,821,334 bytes, sha256 `8bb56f40a926de26aa653c438acc54d49922720d89434869f406ddd7cd75402e`. Built 2026-10-20 00:19, after the last source commit (3e8faeb, 00:03). |
| D-29 pin move | `git show 2c2e54c --stat`; `grep perfect_regen src/core/judge_config.gd` | One-line commit `perfect_regen` 1.0 -> 0.25; gate re-baselined to 2c2e54c for judge_config.gd only, the 72e21ce group is untouched |

Bot frequency on this run: synth_wave_april [3,3,3,4], space_synth_wave [2,3,4,2], sea_shanty_2 [3,4,3,4], hrt [4,3,3,5], invisible [4,4,2,2] (ratio 0.120, Veteran 33 ms / 1.5%). Per-song means are 3.25, 2.75, 3.5, 3.75, 3.0, all inside [2, 4].

## Goal Achievement

### Observable Truths (ROADMAP success criteria + SPEC requirements)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Perfect streak fills a visible tube; fire at a target (leader default, cycling, Attackers) with beat-snapped launch and arrival | VERIFIED | `RewardMeter` (124 lines) + `reward_socket.gd`; `MatchSim.request_fire` -> `_queue_launch` snaps to `launch_beat`, `_commit_launch` sets `arrive_beat = b + torpedo_travel_beats`; `cycle_target` cycles AUTO -> each rival -> ATTACKERS; `resolve_target` defaults to `_deepest_alive`. Gameplay wires `versus.fire` / `versus.cycle_target` (gameplay.gd 351, 356). Tests: test_match_sim_fire, test_versus_gameplay `test_fire_and_target_input` |
| SC2 | Telegraph >= 1 beat before landing; each disruptor readable and survivable without mashing | VERIFIED (automated) / readability human | TORPEDO_LAUNCH emitted 1 beat before arrival; `test_telegraph_alert_visible_at_launch_one_beat_before_arrival` passes. All 6 disruptors exist (Crossed Wires, Ghost Notes, Ink Cloud, Pressure Crack, Sonar Jam, Depth Charge); `test_each_disruptor_lands_expires_and_autoplay_stays_perfect` passes. Visual readability goes to HUMAN-UAT test 7. **Note:** ROADMAP SC2 text still names "Lane Flip"; it is superseded by Crossed Wires per SPEC req 7. Fix the text at the transition step (not a gap). |
| SC3 | One payload at a time + immunity; all-Perfect warheads reflect to sender | VERIFIED | `PlayerState.is_shielded` = incoming, active or `t < immune_until`; refusals `shielded` / `race`. `_warhead_judged` -> `_reflect` relaunches at the sender (D-17), with fizzle when the sender is gone or shielded. Tests: test_match_sim_fire, test_sub_rig, test_match_sim_bounty (CR-01 regressions) |
| SC4 | Periscope panels show each rival's hull, tube and incoming payloads; last hull wins, else deepest score | VERIFIED | `periscope_panel.gd` (768 lines) / `periscope_column.gd`; `MatchSim.standings` / `winner` / `_check_last_standing`; test_match_standings (10 cases incl. tie-breaks), test_periscope_panel |
| SC5 | Wreck ghosts with capped debris; results screen with winner, depth, accuracy, landed/reflected | VERIFIED | `on_failed` -> wreck, `_fire_debris` / `_consume_debris` with `debris_max_per_wreck = 2`; test_wreck_debris (10 cases). `versus_results_screen.gd` wired at gameplay.gd 422-427; test_versus_results, test_versus_gameplay `test_wreck_keeps_the_song_running_and_ends_on_versus_results` |
| SC6 | Solo Dive practice with chosen training payloads | VERIFIED | Settings.training_payload, Song Select F3 stepper (song_select.gd 991-1021), `MatchSetup.training_reward`, `TrainingDrone` fires every 8 bars; test_training_drone, test_versus_gameplay `test_training_drone_no_fail_and_solo_results` |
| R1 | Threshold `ceil(0.12 x notes)`; Miss resets, Good neutral, use keeps streak | VERIFIED | `RewardMeter.threshold`; test_reward_meter (120 / 48, 119 vs 120 Perfects) |
| R2 | One reward slot, meter paused while holding, 1-item prize queue | VERIFIED | test_reward_meter, test_solo_duel `test_winner_holding_reward_gets_it_queued` |
| R3 | Seeded shuffled bag of 9 | VERIFIED | `reward_bag.gd`, `Reward.ALL` (9 ids); test_reward_bag |
| R4 | Fire: disruptor to target, buff to self | VERIFIED | `_queue_launch` vs `_apply_buff`; test_match_sim_fire |
| R5 | 6 disruptors through one payload interface, end after duration | VERIFIED | `PayloadStack` (366 lines), `VersusConfig.bars_*`; test_payload_stack, test_highway_payloads, test_training_drone |
| R6 | Decoy / Ballast 25% / Overclock | VERIFIED | `_apply_buff`, `_arrive` absorb path; test_match_sim_fire, test_versus_hull. Ballast 25% value is still user-unconfirmed (HUMAN-UAT test 6) |
| R7 | Lane Flip out, Crossed Wires in; exactly 9 rewards | VERIFIED | `Reward.Id` / `Reward.ALL` have no LANE_FLIP |
| R8 | Strong bots earn 2-4 rewards per song | UNCERTAIN (WARNING, escalated) | test_bot_frequency red: hrt seat 3 = 5. The mean is about 3 and 19/20 bot-songs fall in range. Waiting on user decision D-UAT-01 |
| R9 | Torpedo Collision | VERIFIED | `_resolve_launches` head-on pairing + in-flight overlap, `_collide` uses both meters; test_match_sim_fire, test_medal_rules Head-On |
| R10 | Bounty on leader, 25% refund, none when blocked or reflected | VERIFIED | `_update_bounty` / `_on_landed_bounty` (live heads, CR-01 fix); test_match_sim_bounty (14 cases) |
| R11 | Solo Duel (16+ notes, 85%, tie-break, queue) | VERIFIED | `_build_duels` / `_resolve_duel`; test_solo_duel (13 cases incl. 90 vs 86, 10-note no duel); test_chart_solos for importer markers |
| R12 | Killfeed: 4 lines, 4 s fade, EventChannel only | VERIFIED | `killfeed.gd` (405 lines), `killfeed_max_lines = 4`, `killfeed_life_s = 4.0`; test_killfeed |
| R13 | Medals, up to 3 in table order | VERIFIED | `medal_rules.gd`; test_medal_rules (24 cases incl. `test_more_than_three_shows_first_three_in_order`) |
| R14 | `perfect_regen` 0.25 (Miss + Perfect = 92.25) with timing gate proven | VERIFIED | judge_config.gd:16; test_hull_score:28 and test_versus_hull:105 assert 92.25; TIMING GATE OK |

**Score:** 19/20 verified, 1 uncertain (R8, human decision). 0 failed.

### Required Artifacts (plan 14/15 must_haves, sampled)

| Artifact | Status | Details |
|----------|--------|---------|
| `src/ui/versus/versus_controller.gd` | VERIFIED | 418 lines; `sim.update` at 265/354; `pre_tick`, `human_press`, `fire`, `cycle_target` |
| `src/ui/versus/versus_hud.gd` | VERIFIED | Container bound by `versus.bind_views(self)` |
| `src/ui/gameplay.gd` versus branch | VERIFIED | Builds VersusController for match_setup or training (123-131); `pre_tick` / `update` per frame (330-331); VersusResultsScreen on finish |
| `src/versus/*` (18 files) | VERIFIED | MatchSim 1353 lines; no stubs |
| `tools/dist.ps1`, `tools/dist/README.txt` (WHAT'S NEW IN v0.6.0), `TESTER-CHECKLIST.txt` (4d VERSUS) | VERIFIED | Present |
| Main menu "Versus Bots" | VERIFIED | main_menu.gd:172 -> `launch_versus()` -> scenes/match_setup.tscn |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| gameplay.gd | VersusController | start() branch + `_process` pre_tick/update | WIRED |
| VersusController | MatchSim | `sim.update(t)` in time-ordered stepping (WR-01 replaced "after judge.tick") | WIRED |
| gameplay.gd | VersusResultsScreen | finish branch, rematch / change / menu signals | WIRED |
| LaneInput | VersusController | `press_fn` / `release_fn` -> `human_press` / `human_release` (WR-01) | WIRED |
| Killfeed / panels | EventChannel | LoopbackChannel events | WIRED (test_killfeed, test_versus_gameplay) |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| TORP-01 | SATISFIED | R1/R2, reward socket always visible |
| TORP-02 | SATISFIED (as amended by SPEC req 4) | beat-snapped launch/arrive |
| TORP-03 | SATISFIED | AUTO (leader) / LOCKED cycle / ATTACKERS |
| TORP-04 | SATISFIED | 1-beat travel, alert at launch (test) |
| TORP-05 | SATISFIED | `is_shielded` + `immunity_bars` |
| TORP-06 | SATISFIED (automated) / NEEDS HUMAN (readability) | autoplay stays all-Perfect under each disruptor; HUMAN-UAT 7 |
| PAY-01 | SATISFIED | Pressure Crack x1.5 |
| PAY-02 | SUPERSEDED -> Crossed Wires (SPEC req 7) | REQUIREMENTS.md text update due at transition |
| PAY-03 / 04 / 05 | SATISFIED | Ghost Notes / Ink Cloud / Depth Charge |
| PAY-06 | SATISFIED | warheads + `_reflect` |
| MATCH-01..06 | SATISFIED | see SC1-SC6 |

No orphaned requirements: all 18 IDs mapped to Phase 3 are claimed by plans.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| src/versus, src/ui/versus, src/core/versus_* | TBD/FIXME/XXX/TODO scan | none found | n/a |
| Full suite exit | "926 ObjectDB instances leaked / 22 resources still in use at exit" | Info | Headless suite-teardown noise across all suites. CR-02 fixed the match-graph cycle (weakref test passes); not phase-blocking |
| tests/zz_* (untracked) | leftover scratch tests run with the suite | Info | Not committed; they did not fail. Delete when convenient |

### Behavioral Spot-Checks / Probes

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Timing core untouched except the approved pin | check_timing_gate.ps1 | TIMING GATE OK | PASS |
| Whole phase test suite | run_tests.ps1 | 1725/1726 pass, known red only | PASS (with known red) |
| Friend zip shape | unzip -l | 3 entries | PASS |

No `scripts/*/tests/probe-*.sh` probes are declared for this phase.

### Notes for the transition step (not gaps)

- ROADMAP Phase 3 SC2 still names "Lane Flip"; replace it with "Crossed Wires" (and Sonar Jam) per SPEC req 7. REQUIREMENTS.md PAY-02 likewise.
- ROADMAP plan list shows 03-14 and 03-15 unchecked and "13/15 plans executed", but both SUMMARYs exist and the code is in the tree. Update STATE/ROADMAP.
- 03-HUMAN-UAT.md test 10 still quotes the first zip hash (9d4a3118...). The current zip is `8bb56f40...` (noted in the verifier section of the UAT file).

### Human Verification Required

See frontmatter and 03-HUMAN-UAT.md: D-UAT-01 decision, full versus match (tests 1, 2, 12), readability (7), Crossed Wires input (4), review-fix input-feel items (CR-01, WR-01..03), borderline p95 perf gate, unreliable ink-share playtest check, friend PC zip test (10).

### Gaps Summary

No blocking gaps. The codebase delivers the complete offline versus loop: killstreak meter and bag, 9 rewards, firing, targeting and telegraph, one payload plus immunity, Return to Sender, wreck ghosts with capped debris, periscope panels, killfeed, bounty, Solo Duel, medals, results, Solo Dive training payloads, and the slower hull repair with the timing gate proven. Each piece is substantive, wired into Gameplay and covered by passing tests. The one red test (spec req 8 per-bot frequency) is a design decision escalated as D-UAT-01, not a missing implementation. Perf (p95 4.18-4.45 ms vs 4.35 ms) is borderline and goes to the human for accept or fix.

---

_Verified: 2026-10-20_
_Verifier: Claude (gsd-verifier)_
