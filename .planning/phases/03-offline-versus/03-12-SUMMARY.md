---
phase: 03-offline-versus
plan: 12
subsystem: versus-results
tags: [medals, results, pause, ui]
requires: ["03-02", "03-03"]
provides:
  - "MedalRules.medals(event_log, seats, drone_seats) -> seat -> Array[String] (max 3, ORDER)"
  - "VersusResultsScreen (setup(data), rematch_pressed / change_match_pressed / menu_pressed)"
  - "PauseMenu.match_mode versus copy"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns: ["pure RefCounted rules over the event log", "results_screen.gd structure (groups, deterministic apply_entrance(t))"]
key-files:
  created:
    - src/versus/medal_rules.gd
    - src/ui/versus/versus_results_screen.gd
    - tests/test_medal_rules.gd
    - tests/test_versus_results.gd
  modified:
    - src/ui/pause_menu.gd
    - tests/test_pause_overlay.gd
decisions:
  - "Fired at seat s = TORPEDO_LAUNCH to s (not debris) plus each COLLISION half aimed at s whose torpedo id has no TORPEDO_LAUNCH (a pending launch); a collision with a torpedo already in flight is not double counted"
  - "Took effect = LANDED to s, not debris, id without a REFLECTED event. Absorbed never takes effect"
  - "Grudge counts LANDED from seat to one rival, excluding debris, reflected relaunches and ids with a REFLECTED event"
  - "Dogpiled 'targeted' = non-debris, non-reflected launch from the rival, or a collision between the two; needs >= 3 non-drone players"
  - "Drones never earn medals and never count as rivals; malformed events / unknown seats are ignored (T-03-29)"
  - "Row accuracy is PlayerState convention 0..1 (-1 none), shown via RunStats.accuracy_text(acc * 100)"
  - "Versus Restart Match always confirms (even at score 0); solo keeps the score > 0 rule"
  - "Medal pops stagger 60 ms per row (all medals of a row together) so the entrance ends at 0.78 s (<= 0.9 s)"
  - "Winner glow stays under Reduce motion (static), off under Low effects"
metrics:
  duration: "~45 min (incl. usage-limit pause)"
  completed: 2026-10-15
---

# Phase 3 Plan 12: MedalRules, versus results and versus pause Summary

Pure MedalRules turns a MatchSim event_log into up to 3 medals per seat in spec order (ties to all, Dogpiled only in 3+ player matches). VersusResultsScreen shows the MATCH-05 standings, statuses, medal badges and the YOUR MEDALS legend per UI-SPEC 9.4. The pause menu gets a versus mode with the 9.5 copy.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 9a9daeb | test(03-12): add failing tests for MedalRules |
| 1 GREEN | 1df2898 | feat(03-12): MedalRules pure medal rules over the match event_log |
| 2 | ae52777 | feat(03-12): versus results screen and versus pause copy |

## Tests

- test_medal_rules 24/24 (RED confirmed first: parse error with medal_rules.gd absent)
- test_versus_results 14/14
- test_pause_overlay 8/8 (5 existing unchanged + 3 new match-mode cases)
- test_color_literals 7/7 (covers the new screen)
- tools/check_timing_gate.ps1: TIMING GATE OK
- Full suite not run (parallel-wave rule; 03-14/03-15 run it)

## VersusResultsScreen.setup(data) keys

| Key | Type | Meaning |
|-----|------|---------|
| rows | Array[Dictionary] | MatchSim.standings() rows {seat, place, alive, depth, hull, accuracy 0..1 or -1, eliminated_at (INF alive)} merged with `name` (callsign, "YOU" for the human), `landed`, `reflected` (PlayerState stats). Any order; sorted by place then seat. Max 4 rows |
| local_seat | int | the YOU row (highlight, legend, "YOU WIN") |
| medals | Dictionary | seat -> Array of MedalRules keys (pass MedalRules.medals(...) directly) |
| title, artist, difficulty | String | header line and difficulty chip |
| seed | int | "SEED {n}" |
| last_standing_seat | int | seat of the LAST_STANDING event, or -1 |

Signals: rematch_pressed, change_match_pressed, menu_pressed (Esc / B also emits menu_pressed). Test getters: headline_text(), headline_color(), row_count(), row_texts(i), medal_names(i), medal_columns(i), medal_nodes(i), row_group(i), header_group(), winner_glow(), legend_lines(), focus_buttons(), you_row. Entrance: entrance_running(), skip_entrance(), apply_entrance(t), ENTRANCE_SEC = 0.78. No ScoreStore call (D-23).

## Notes for 03-14

- Show the screen like ResultsScreen: instance VersusResultsScreen, add_child, setup(data) (or setup before add; _ready starts the entrance and focuses Rematch).
- medals: `MedalRules.medals(match_sim.event_log, seats, drone_seats)`; rows: merge `match_sim.standings()` with `players[seat].callsign`, `.landed`, `.reflected`.
- Set `pause_menu.match_mode = true` before the first open() in a versus match; set_run_info then adds "VERSUS". restart_confirmed / menu_confirmed are unchanged (Restart Match / Leave Match).
- test_effect_settings.gd EXPECTED does not list VersusResultsScreen yet (not in this plan's files). It registers via UiKit.register_fx; effect_counts() = {rise, medal_pop, glow}. Add it when 03-14/03-15 extend that suite.

## Deviations from Plan

- Task 2 was written tests-alongside rather than a separate RED commit (tests passed first run); the Task 1 RED/GREEN gate is in git.
- Hint swaps to "A SELECT  ·  B BACK TO MENU" on gamepad input (UI-SPEC 9.4 lists both; ResultsScreen only shows the keyboard one).

## Known Stubs

None. The screen is complete; wiring it into Gameplay is 03-14's scope.

## TDD Gate Compliance

Task 1: test commit 9a9daeb precedes feat commit 1df2898. Task 2: single feat commit (see Deviations).

## Self-Check: PASSED

- FOUND: src/versus/medal_rules.gd, src/ui/versus/versus_results_screen.gd, tests/test_medal_rules.gd, tests/test_versus_results.gd
- FOUND: 9a9daeb, 1df2898, ae52777
