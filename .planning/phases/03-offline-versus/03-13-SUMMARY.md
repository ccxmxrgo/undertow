---
phase: 03-offline-versus
plan: 13
subsystem: menus
tags: [versus, match-setup, ui, focus, gamepad]
requires: ["03-01 MatchSetup + Settings [versus]", "03-02 UiIcons chevrons", "03-05 Versus Bots menu entry + Song Select pick mode"]
provides:
  - "MatchSetupScreen (src/ui/versus/match_setup_screen.gd) at res://scenes/match_setup.tscn"
  - "MatchSetup.pending launch record (mode versus, seed, rivals, skill, song, difficulty) written on Start Match"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns: ["row Buttons handle ui_up/down/left/right/accept in their gui_input signal (before GUI focus navigation), so UiSounds still sees the press in _input"]
key-files:
  created:
    - src/ui/versus/match_setup_screen.gd
    - scenes/match_setup.tscn
    - tests/test_match_setup_screen.gd
  modified: []
decisions:
  - "The match seed is drawn when the screen opens and used by Start Match, so the roster callsigns in the preview are the ones in the match (a fresh seed per visit)"
  - "A stored song that no longer resolves falls back to the last played song, else the Song row is empty ('Choose a song', TEXT_LO) and Start Match is disabled"
  - "'No songs installed' shows only when the library has no playable entry at all"
metrics:
  duration: "~35 min"
  completed: 2026-10-15
---

# Phase 3 Plan 13: Match setup screen Summary

The VERSUS match setup screen (UI-SPEC 9.2). The player picks the song (through Song Select pick mode), the difficulty, 1 to 3 rivals and the bot skill, sees the chart preview and the roster, then starts the match. Start Match writes `MatchSetup.pending` and `Gameplay.pending_chart` and opens the gameplay scene.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | f9119e2 | test(03-13): add failing tests for match setup rows, preview and roster |
| 1 GREEN | 3e2785b | feat(03-13): match setup screen layout, rows, preview and roster |
| 2 RED | bd360f2 | test(03-13): add failing tests for Start Match, song pick round trip and back |
| 2 GREEN | 5ab02a2 | feat(03-13): Start Match, song pick round trip and back navigation |

## What was built

- **scenes/match_setup.tscn**: a 12-line stub (root `MatchSetup`, anchors preset 15) pointing at the script. Its path is the one `MainMenu.MATCH_SETUP_SCENE` and `SongSelect.MATCH_SETUP_SCENE` already use.
- **MatchSetupScreen** (`class_name MatchSetupScreen`):
  - **Layout.** AbyssBackdrop `table`, title "VERSUS" at (64, 104) and the subtitle at (64, 140).
    - MATCH glass panel at 64..944 x 176..904 with the caption at (96, 216).
    - Rows at y 240 / 312 / 384 / 456. Each row is a 64-tall Button, 816 wide, starting at x 96.
    - Skill description at baseline 560, divider at y 592, then HOW REWARDS WORK and its 4 lines at 672..768.
    - Start Match (primary) at y 808..872 with key hint ENTER (A after gamepad input).
    - Preview panel at 976..1856: cover 256 at (1008, 208); a 2-line Heading title at x 1288 (baselines 248 / 296, "..." when cut, max 544 px); artist at baseline 336; difficulty chip at y 352; the "{N} NOTES · REWARD EVERY {T} PERFECTS" line at baseline 424.
    - Roster caption at (1008, 504) and 4 roster rows (56 tall) at y 520 / 584 / 648 / 712.
    - Hint at (64, 960). The error line sits at (64, 1000) in WARNING_RED with the main menu's "!" StatusGlyph.
  - **Rows.**
    - Song: value at x 400, truncated at 456 px, `chevron_right` at 872.
    - Difficulty: chip at 400 with chevrons at 368 / 872. It cycles the song's difficulties through `SongListModel.next_difficulty` (clamps, no wrap, same as Song Select).
    - Rivals: tiles 1/2/3, each 96x48, at x 400 / 504 / 608.
    - Bot skill: ROOKIE / REGULAR / VETERAN tiles, each 160x48, at x 400 / 568 / 736.
    - Tile states: idle tiles use the idle button style. The selected tile uses the focus style (ABYSS_600 92% fill, 2 px SONAR edge), bold TEXT_HI text and a 24x4 SONAR bar under it. It glows only while its row is focused.
    - Rivals and skill wrap on Left/Right.
  - **Live values.**
    - T = `RewardMeter.threshold(N, VersusConfig.new().reward_threshold_ratio)`, where N is the difficulty's `note_count`.
    - The {FIRE} / {TARGET} names come from `Settings.bindings.display_name(&"fire" / &"target_cycle", device)`, upper-cased (SPACE and H by default). They switch to gamepad names after pad input.
    - Roster: YOU (info chip "YOU") plus `MatchSetup.callsigns(seed, rivals)` with a mode chip of the skill. Rows fade in and out over DUR_BASE, instantly under Reduce motion.
  - **Defaults.** Taken from `MatchSetup.pending` when it is set, else `MatchSetup.from_settings()`, then always `clamped()` (T-03-32). Initial focus is Start Match when a song is set, else Song.
  - **Focus.** Song -> Difficulty -> Rivals -> Bot skill -> Start Match, wrapping. Each row Button handles ui_up / ui_down / ui_left / ui_right / ui_accept in its `gui_input` signal and marks the event handled. The GUI never moves focus sideways (left/right neighbours point at the row itself). UiSounds still plays move / confirm / back from `_input`, and value changes play `move` explicitly. Mouse: clicking a tile selects it, clicking the left or right half of the difficulty row steps it, and clicking Song or Start activates them. One FocusMarker.
  - **Start Match** (`start_match()`):
    1. Disabled without a song. A `_starting` guard means a second Enter does not navigate again.
    2. Calls `library.build_chart(entry, difficulty)`. If it returns null, the screen shows the Song Select audio error copy (the user or bundled variant, same rule as `_dive`), plays the `error` blip and stays put (T-03-31).
    3. Otherwise it saves the choices to Settings and sets `MatchSetup.pending` (MODE_VERSUS, the screen's seed, rivals, skill, song, difficulty).
    4. Sets `Gameplay.pending_chart`, with `pending_autoplay` and `pending_practice` false and the SongSelect run flags cleared.
    5. Stops MenuMusic and navigates to `res://scenes/gameplay.tscn`.
  - **Song pick.** Accept on Song stores the current choices in `MatchSetup.pending`, sets `SongSelect.run_pick = true` and navigates to Song Select. The 03-05 pick mode updates the pending song and difficulty, so the rival and skill choices survive the round trip.
  - **Esc / B.** Calls `save_to_settings()`, sets `MatchSetup.pending = null`, then goes to the main menu.
  - **Effect contract.** `UiKit.register_fx(self)`, `apply_effect_settings()` and `effect_counts()` (`roster_fade`).
  - **Test seams.** `navigate`, `library`, `debug_state()`, `press_key_for_test(key)`, `focus_row_for_test(row)`, `row_rect()`, static `tile_rect()` and `roster_row_rect()`.

## Tests

| Suite | Result |
|-------|--------|
| test_match_setup_screen | 21/21. Task 1 (15): scene root, calibration preview + threshold + initial focus, empty library, Down/Up loop, rivals wrap + roster, skill + descriptions, Left/Right inert on Song/Start, difficulty cycling, How rewards key names, defaults from pending, clamping, unknown-song fallback (two cases), layout rects, drawing every state. Task 2 (6): pick mode open, pick round trip, Start Match record + single navigation, disabled start, load-failure error line, Esc save + clear pending |
| test_color_literals | 7/7 |
| tools/check_timing_gate.ps1 | TIMING GATE OK |

The suite points `Settings.save_path` at `user://test_match_setup_screen/settings.cfg` and resets MatchSetup.pending, the SongSelect run flags, Gameplay.pending_* and Settings.versus_* in before_test and after_test.

The full suite was not run (parallel-wave rule). It runs at wave end in 03-14 / 03-15.

## Deviations from Plan

**1. [Rule 2 - Missing copy] "Choose a song" for a library with songs but no chosen song**
- UI-SPEC 14 only covers the empty library ("No songs installed"). The threat model says an unknown song id leaves the Song row empty with Start disabled. When the stored id does not resolve and there is no last played song, the row shows "Choose a song" in TEXT_LO. The UI auditor can replace the wording.

**2. [Rule 1 - Layout] Preview divider at y 464 spans x 1288..1824**
- The cover occupies y 208..464, so a full-width divider at y 464 would run along the cover's bottom edge. The divider spans the info column only.

**3. Seed chosen at screen open, not at Start**
- The plan says Start Match uses "a fresh seed". The screen draws a fresh `MatchSetup.new_seed()` (never 0) every time it opens, and Start Match uses that seed. This keeps the preview roster's callsigns identical to the match's. Every visit, including Change Match, still gets a fresh seed.

No other deviations. Nothing outside files_modified was touched. default_bus_layout.tres and the *.import churn were left unstaged.

## TDD Gate Compliance

RED (test) commits f9119e2 and bd360f2 precede GREEN (feat) commits 3e2785b and 5ab02a2. Both RED runs failed: Task 1 had a missing class and scene, and Task 2 had Accept, Start and Esc as no-ops.

## Notes for 03-14 (gameplay wiring)

- When gameplay.tscn opens from this screen: `MatchSetup.pending` is non-null, `mode == MODE_VERSUS`, the seed is non-zero, rivals is 1..3 and skill is one of `MatchSetup.SKILLS`, all already clamped. `Gameplay.pending_chart` is the built chart, and `pending_autoplay` / `pending_practice` are false. Gameplay should read `pending` and clear it.
- Callsigns: call `MatchSetup.callsigns(pending.seed, pending.rivals)` to get the exact names the roster preview showed, in seat order.
- Versus results: "Change Match" should navigate to `res://scenes/match_setup.tscn` with `MatchSetup.pending` set to the finished match. The screen keeps its rivals, skill, song and difficulty and draws a new seed. "Rematch" can go straight to gameplay with `pending.rematch()` and a rebuilt chart, without this screen.
- 03-15: `test_effect_settings.EXPECTED` has no entry for this screen yet. Its effect node reports `roster_fade`.

## Known Stubs

None.

## Threat Flags

None. No new network, file or trust-boundary surface. Settings writes go through the existing `MatchSetup.save_to_settings()`.

## Self-Check: PASSED
